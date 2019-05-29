/*
 File: CustomHTTPProtocol.m
 Abstract: An NSURLProtocol subclass that overrides the built-in HTTP/HTTPS protocol.
 Version: 1.1
 
 Disclaimer: IMPORTANT:  This Apple software is supplied to you by Apple
 Inc. ("Apple") in consideration of your agreement to the following
 terms, and your use, installation, modification or redistribution of
 this Apple software constitutes acceptance of these terms.  If you do
 not agree with these terms, please do not use, install, modify or
 redistribute this Apple software.
 
 In consideration of your agreement to abide by the following terms, and
 subject to these terms, Apple grants you a personal, non-exclusive
 license, under Apple's copyrights in this original Apple software (the
 "Apple Software"), to use, reproduce, modify and redistribute the Apple
 Software, with or without modifications, in source and/or binary forms;
 provided that if you redistribute the Apple Software in its entirety and
 without modifications, you must retain this notice and the following
 text and disclaimers in all such redistributions of the Apple Software.
 Neither the name, trademarks, service marks or logos of Apple Inc. may
 be used to endorse or promote products derived from the Apple Software
 without specific prior written permission from Apple.  Except as
 expressly stated in this notice, no other rights or licenses, express or
 implied, are granted by Apple herein, including but not limited to any
 patent rights that may be infringed by your derivative works or by other
 works in which the Apple Software may be incorporated.
 
 The Apple Software is provided by Apple on an "AS IS" basis.  APPLE
 MAKES NO WARRANTIES, EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION
 THE IMPLIED WARRANTIES OF NON-INFRINGEMENT, MERCHANTABILITY AND FITNESS
 FOR A PARTICULAR PURPOSE, REGARDING THE APPLE SOFTWARE OR ITS USE AND
 OPERATION ALONE OR IN COMBINATION WITH YOUR PRODUCTS.
 
 IN NO EVENT SHALL APPLE BE LIABLE FOR ANY SPECIAL, INDIRECT, INCIDENTAL
 OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 INTERRUPTION) ARISING IN ANY WAY OUT OF THE USE, REPRODUCTION,
 MODIFICATION AND/OR DISTRIBUTION OF THE APPLE SOFTWARE, HOWEVER CAUSED
 AND WHETHER UNDER THEORY OF CONTRACT, TORT (INCLUDING NEGLIGENCE),
 STRICT LIABILITY OR OTHERWISE, EVEN IF APPLE HAS BEEN ADVISED OF THE
 POSSIBILITY OF SUCH DAMAGE.
 
 Copyright (C) 2014 Apple Inc. All Rights Reserved.
 
 */

#import "TLMHTTPProtocol.h"

#import "CanonicalRequest.h"
#import "CacheStoragePolicy.h"
#import "QNSURLSessionDemux.h"
#import "TLMHTTPDNSCookieManager.h"
#import "CFHTTPDNSRequestTask.h"
#import "QNSURLSessionDemux.h"
//#import "NSURLSession+hook.h"
#import "NSURLSessionConfiguration+protocol.h"

// I use the following typedef to keep myself sane in the face of the wacky
// Objective-C block syntax.

typedef void (^ChallengeCompletionHandler)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential * credential);

@interface TLMHTTPProtocol () <NSURLSessionDataDelegate, CFHTTPDNSRequestTaskDelegate>

@property (atomic, strong, readwrite) NSThread *                        clientThread;       ///< The thread on which we should call the client.

/*! The run loop modes in which to call the client.
 *  \details The concurrency control here is complex.  It's set up on the client
 *  thread in -startLoading and then never modified.  It is, however, read by code
 *  running on other threads (specifically the main thread), so we deallocate it in
 *  -dealloc rather than in -stopLoading.  We can be sure that it's not read before
 *  it's set up because the main thread code that reads it can only be called after
 *  -startLoading has started the connection running.
 */

@property (atomic, copy,   readwrite) NSArray *                         modes;
@property (atomic, assign, readwrite) NSTimeInterval                    startTime;          ///< The start time of the request; written by client thread only; read by any thread.
@property (atomic, assign, readwrite) NSTimeInterval                    endTime;
@property (atomic, strong, readwrite) NSURLSessionDataTask *            task;               ///< The NSURLSession task for that request; client thread only.
@property (atomic, strong, readwrite) NSURLAuthenticationChallenge *    pendingChallenge;
@property (atomic, copy,   readwrite) ChallengeCompletionHandler        pendingChallengeCompletionHandler;  ///< The completion handler that matches pendingChallenge; main thread only.

@property (atomic, strong, readwrite) NSURLRequest *                    actualRequest;      // client thread only
@property (atomic, strong) NSURLResponse *response;

@property (atomic) BOOL isWebCoreThread;

//用于ip直连的cfTask
@property (atomic, strong) CFHTTPDNSRequestTask *cfTask;

@end

@implementation TLMHTTPProtocol

#pragma mark * Subclass specific additions

/*! The backing store for the class delegate.  This is protected by @synchronized on the class.
 */

static id<TLMHTTPProtocolDelegate> sDelegate;

+ (void)start
{
    if ([[UIDevice currentDevice].systemVersion floatValue] >= 9.0) {
        [NSURLProtocol registerClass:self];
        //[NSURLSession hookHTTPProtocol];
        [NSURLSessionConfiguration hookDefaultSessionConfiguration];
    }
}

+ (id<TLMHTTPProtocolDelegate>)delegate
{
    id<TLMHTTPProtocolDelegate> result;
    
    @synchronized (self) {
        result = sDelegate;
    }
    return result;
}

+ (void)setDelegate:(id<TLMHTTPProtocolDelegate>)newValue
{
    @synchronized (self) {
        sDelegate = newValue;
    }
}

/*! Returns the session demux object used by all the protocol instances.
 *  \details This object allows us to have a single NSURLSession, with a session delegate,
 *  and have its delegate callbacks routed to the correct protocol instance on the correct
 *  thread in the correct modes.  Can be called on any thread.
 */

+ (QNSURLSessionDemux *)sharedDemux
{
    static dispatch_once_t      sOnceToken;
    static QNSURLSessionDemux * sDemux;
    dispatch_once(&sOnceToken, ^{
        NSURLSessionConfiguration *     config;
        
        config = [NSURLSessionConfiguration defaultSessionConfiguration];
        // You have to explicitly configure the session to use your own protocol subclass here
        // otherwise you don't see redirects <rdar://problem/17384498>.
        config.protocolClasses = @[ self ];
        sDemux = [[QNSURLSessionDemux alloc] initWithConfiguration:config];
    });
    return sDemux;
}

#pragma mark * NSURLProtocol overrides

/*! Used to mark our recursive requests so that we don't try to handle them (and thereby
 *  suffer an infinite recursive death).
 */

static NSString * kOurRecursiveRequestFlagProperty = @"com.apple.dts.TLMHTTPProtocol";

+ (BOOL)canInitWithRequest:(NSURLRequest *)request
{
    BOOL        shouldAccept;
    NSURL *     url;
    NSString *  scheme;
    
    // Check the basics.  This routine is extremely defensive because experience has shown that
    // it can be called with some very odd requests <rdar://problem/15197355>.
    
    shouldAccept = (request != nil);
    if (shouldAccept) {
        url = [request URL];
        shouldAccept = (url != nil);
    }
    
    // url过滤
    
    if (shouldAccept) {
        shouldAccept = ([sDelegate protocolShouldHandleURL:url]);
    }
    
    
    // Decline our recursive requests.
    
    if (shouldAccept) {
        shouldAccept = ([self propertyForKey:kOurRecursiveRequestFlagProperty inRequest:request] == nil);
    }
    
    // Get the scheme.
    
    if (shouldAccept) {
        scheme = [[url scheme] lowercaseString];
        shouldAccept = (scheme != nil);
    }
    
    // Look for "http" or "https".
    //
    // Flip either or both of the following to YESes to control which schemes go through this custom
    // NSURLProtocol subclass.
    
    if (shouldAccept) {
        shouldAccept = YES && [scheme isEqual:@"http"];
        if ( ! shouldAccept ) {
            shouldAccept = YES && [scheme isEqual:@"https"];
        }
    }
    
    //过滤host为空的情况
    if (shouldAccept) {
        shouldAccept = YES && ([url host].length > 0);
    }
    
    if (shouldAccept) {
        shouldAccept = YES && (![[url host] isEqualToString:@"119.29.29.229"]);
    }
    
    return shouldAccept;
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request
{
    NSString *host = request.URL.host;
    if ([[[self class] delegate] respondsToSelector:@selector(protocolReplacedHostForHost:)] &&
        [[[self class] delegate] protocolReplacedHostForHost:host].length > 0) {
        if ([[[self class] delegate] respondsToSelector:@selector(protocolShouldHTTPDNSByURL:)] &&
            [[[self class] delegate] protocolShouldHTTPDNSByURL:request.URL]) {
            NSMutableURLRequest *mutableRequest = [request mutableCopy];
            NSURLComponents *components = [NSURLComponents componentsWithURL:request.URL resolvingAgainstBaseURL:NO];
            components.host = [[[self class] delegate] protocolReplacedHostForHost:host];
            mutableRequest.URL = components.URL;
            request = mutableRequest;
        }
    }
    
    NSURLRequest *      result;
    
    NSCAssert(request != nil,@"request == nil");
    // can be called on any thread
    
    // Canonicalising a request is quite complex, so all the heavy lifting has
    // been shuffled off to a separate module.
    
    result = CanonicalRequestForRequest(request);
    return result;
}

//- (id)initWithRequest:(NSURLRequest *)request cachedResponse:(NSCachedURLResponse *)cachedResponse client:(id <NSURLProtocolClient>)client
//{
//    NSCAssert(request != nil);
//    // cachedResponse may be nil
//    NSCAssert(client != nil);
//    // can be called on any thread
//
//    self = [super initWithRequest:request cachedResponse:cachedResponse client:client];
//    if (self != nil) {
//        // All we do here is log the call.
//        [[self class] customHTTPProtocol:self logWithFormat:@"init for %@ from <%@ %p>", [request URL], [client class], client];
//    }
//    return self;
//}

- (void)dealloc
{
    // can be called on any thread
    
    NSCAssert(self->_task == nil,@"self->_task != nil");                     // we should have cleared it by now
    NSCAssert(self->_pendingChallenge == nil,@"self->_pendingChallenge != nil");         // we should have cancelled it by now
    NSCAssert(self->_pendingChallengeCompletionHandler == nil,@"self->_pendingChallengeCompletionHandler != nil");    // we should have cancelled it by now
}

- (void)startLoading
{
    NSMutableURLRequest *   recursiveRequest;
    NSMutableArray *        calculatedModes;
    NSString *              currentMode;
    
    // At this point we kick off the process of loading the URL via NSURLSession.
    // The thread that calls this method becomes the client thread.
    
    NSCAssert(self.clientThread == nil,@"self.clientThread != nil");           // you can't call -startLoading twice
    NSCAssert(self.task == nil,@"self.task != nil");
    
    // Calculate our effective run loop modes.  In some circumstances (yes I'm looking at
    // you UIWebView!) we can be called from a non-standard thread which then runs a
    // non-standard run loop mode waiting for the request to finish.  We detect this
    // non-standard mode and add it to the list of run loop modes we use when scheduling
    // our callbacks.  Exciting huh?
    //
    // For debugging purposes the non-standard mode is "WebCoreSynchronousLoaderRunLoopMode"
    // but it's better not to hard-code that here.
    
    NSCAssert(self.modes == nil,@"self.modes != nil");
    calculatedModes = [NSMutableArray array];
    [calculatedModes addObject:NSDefaultRunLoopMode];
    currentMode = [[NSRunLoop currentRunLoop] currentMode];
    if ( (currentMode != nil) && ! [currentMode isEqual:NSDefaultRunLoopMode] ) {
        [calculatedModes addObject:currentMode];
    }
    self.modes = calculatedModes;
    NSCAssert([self.modes count] > 0,@"[self.modes count] <= 0");
    
    // Create new request that's a clone of the request we were initialised with,
    // except that it has our 'recursive request flag' property set on it.
    
    recursiveRequest = [[self request] mutableCopy];
    NSCAssert(recursiveRequest != nil,@"recursiveRequest == nil");
    
    
    self.startTime = [[NSDate date] timeIntervalSince1970];
#warning rxBytes和txBytes是干什么的？
    //    self.rxBytes = 0;
    //    self.txBytes = 0;
    
    // 递归标志设置
    [[self class] setProperty:@YES forKey:kOurRecursiveRequestFlagProperty inRequest:recursiveRequest];
    
    NSString *originalUrl = [recursiveRequest.URL absoluteString];
    NSURL *url = [NSURL URLWithString:originalUrl];
    
    // 优先级1：根据URL进行IP直连
    if (url.host.length && [[self class] delegate] && [[[self class] delegate] respondsToSelector:@selector(protocolCheckURLIfNeededHTTPDNSByURL:)]) {
        NSString *ip = [[[self class] delegate] protocolCheckURLIfNeededHTTPDNSByURL:url];
        if (ip && ![ip isEqualToString:url.host]) {
            
            NSRange hostFirstRange = [originalUrl rangeOfString:url.host];
            if (NSNotFound != hostFirstRange.location) {
                NSString *newUrl = [originalUrl stringByReplacingCharactersInRange:hostFirstRange withString:ip];
                [recursiveRequest setValue:url.host forHTTPHeaderField:@"host"];
                
                // 处理URL和Host
                NSMutableURLRequest *swizzleRequest = [recursiveRequest mutableCopy];
                swizzleRequest.URL = [NSURL URLWithString:newUrl];
                [swizzleRequest setValue:url.host forHTTPHeaderField:@"host"];
                
                // 处理cookie，因为url变化，系统不会自动带上原有domain的cookie
                NSString *cookieString = [[TLMHTTPDNSCookieManager sharedInstance] getRequestCookieHeaderForURL:url];
                [swizzleRequest setValue:cookieString forHTTPHeaderField:@"Cookie"];
                
                // 创建cfTask
                self.cfTask = [[CFHTTPDNSRequestTask alloc] initWithURLRequest:recursiveRequest
                                                                swizzleRequest:swizzleRequest
                                                                      delegate:self];
                if (self.cfTask) {
                    [self.cfTask startLoading];
                }
                
                // 保存actualRequest
                self.actualRequest = recursiveRequest;
                return;
            }
            
        }
    }
    
    
    // 优先级2：根据host获取IP来进行IP直连
    if (url.host.length && [[self class] delegate] && [[[self class] delegate] respondsToSelector:@selector(protocolCFNetworkHTTPDNSGetIPByDomain:)]) {
        NSString *ip = [[[self class] delegate] protocolCFNetworkHTTPDNSGetIPByDomain:url.host];
        if (ip && ![ip isEqualToString:url.host]) {
            NSRange hostFirstRange = [originalUrl rangeOfString:url.host];
            if (NSNotFound != hostFirstRange.location) {
                NSString *newUrl = [originalUrl stringByReplacingCharactersInRange:hostFirstRange withString:ip];
                [recursiveRequest setValue:url.host forHTTPHeaderField:@"host"];
                
                // 处理URL和Host
                NSMutableURLRequest *swizzleRequest = [recursiveRequest mutableCopy];
                swizzleRequest.URL = [NSURL URLWithString:newUrl];
                [swizzleRequest setValue:url.host forHTTPHeaderField:@"host"];
                
                // 处理cookie，因为url变化，系统不会自动带上原有domain的cookie
                NSString *cookieString = [[TLMHTTPDNSCookieManager sharedInstance] getRequestCookieHeaderForURL:url];
                [swizzleRequest setValue:cookieString forHTTPHeaderField:@"Cookie"];
                
                // 创建cfTask
                self.cfTask = [[CFHTTPDNSRequestTask alloc] initWithURLRequest:recursiveRequest
                                                                swizzleRequest:swizzleRequest
                                                                      delegate:self];
                if (self.cfTask) {
                    [self.cfTask startLoading];
                }
                
                // 保存actualRequest
                self.actualRequest = recursiveRequest;
                return;
            }
        }
    }
    
    // 优先级3:非IP直连，使用localDNS降级处理
    self.actualRequest = recursiveRequest;
    
    // Latch the thread we were called on, primarily for debugging purposes.
    self.clientThread = [NSThread currentThread];
    self.isWebCoreThread = (self.clientThread && self.clientThread.name && [self.clientThread.name hasPrefix:@"WebCore: CFNetwork Loader"]) ? YES:NO;
    
    // Once everything is ready to go, create a data task with the new request.
    self.task = [[[self class] sharedDemux] dataTaskWithRequest:recursiveRequest delegate:self modes:self.modes];
    NSCAssert(self.task != nil,@"self.task == nil");
    
    [self.task resume];
}

- (void)stopLoading
{
    self.endTime = [[NSDate date] timeIntervalSince1970];
    
    if (self.cfTask) {
        [self.cfTask stopLoading];
        self.cfTask = nil;
        return;
    }
    
    //FIX iphone4s-iphone4+ios6-ios7machine webcore thread crash, don't log
    if(self.clientThread == nil && self.isWebCoreThread){
        self.task = nil;
        self.modes = nil;
        return;
    }
    
    NSCAssert(self.clientThread != nil,@"self.clientThread == nil");           // someone must have called -startLoading
    
    // Check that we're being stopped on the same thread that we were started
    // on.  Without this invariant things are going to go badly (for example,
    // run loop sources that got attached during -startLoading may not get
    // detached here).
    //
    // I originally had code here to bounce over to the client thread but that
    // actually gets complex when you consider run loop modes, so I've nixed it.
    // Rather, I rely on our client calling us on the right thread, which is what
    // the following assert is about.
    
    NSCAssert([NSThread currentThread] == self.clientThread,@"[NSThread currentThread] != self.clientThread");
    
    if (self.task != nil) {
        [self.task cancel];
        self.task = nil;
        // The following ends up calling -URLSession:task:didCompleteWithError: with NSURLErrorDomain / NSURLErrorCancelled,
        // which specificallys traps and ignores the error.
    }
    // Don't nil out self.modes; see property declaration comments for a a discussion of this.
    self.actualRequest = nil;
}

//#pragma mark * Authentication challenge handling
//
///*! Performs the block on the specified thread in one of specified modes.
// *  \param thread The thread to target; nil implies the main thread.
// *  \param modes The modes to target; nil or an empty array gets you the default run loop mode.
// *  \param block The block to run.
// */
//
//- (void)performOnThread:(NSThread *)thread modes:(NSArray *)modes block:(dispatch_block_t)block
//{
//    // thread may be nil
//    // modes may be nil
//    NSCAssert(block != nil);
//
//    if (thread == nil) {
//        thread = [NSThread mainThread];
//    }
//    if ([modes count] == 0) {
//        modes = @[ NSDefaultRunLoopMode ];
//    }
//    [self performSelector:@selector(onThreadPerformBlock:) onThread:thread withObject:[block copy] waitUntilDone:NO modes:modes];
//}
//
///*! A helper method used by -performOnThread:modes:block:. Runs in the specified context
// *  and simply calls the block.
// *  \param block The block to run.
// */
//
//- (void)onThreadPerformBlock:(dispatch_block_t)block
//{
//    assert(block != nil);
//    block();
//}
//
///*! Called by our NSURLSession delegate callback to pass the challenge to our delegate.
// *  \description This simply passes the challenge over to the main thread.
// *  We do this so that all accesses to pendingChallenge are done from the main thread,
// *  which avoids the need for extra synchronisation.
// *
// *  By the time this runes, the NSURLSession delegate callback has already confirmed with
// *  the delegate that it wants the challenge.
// *
// *  Note that we use the default run loop mode here, not the common modes.  We don't want
// *  an authorisation dialog showing up on top of an active menu (-:
// *
// *  Also, we implement our own 'perform block' infrastructure because Cocoa doesn't have
// *  one <rdar://problem/17232344> and CFRunLoopPerformBlock is inadequate for the
// *  return case (where we need to pass in an array of modes; CFRunLoopPerformBlock only takes
// *  one mode).
// *  \param challenge The authentication challenge to process; must not be nil.
// *  \param completionHandler The associated completion handler; must not be nil.
// */
//
//- (void)didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(ChallengeCompletionHandler)completionHandler
//{
//    NSCAssert(challenge != nil);
//    NSCAssert(completionHandler != nil);
//    NSCAssert([NSThread currentThread] == self.clientThread);
//
//    [[self class] customHTTPProtocol:self logWithFormat:@"challenge %@ received", [[challenge protectionSpace] authenticationMethod]];
//
//    [self performOnThread:nil modes:nil block:^{
//        [self mainThreadDidReceiveAuthenticationChallenge:challenge completionHandler:completionHandler];
//    }];
//}
//
///*! The main thread side of authentication challenge processing.
// *  \details If there's already a pending challenge, something has gone wrong and
// *  the routine simply cancels the new challenge.  If our delegate doesn't implement
// *  the -customHTTPProtocol:canAuthenticateAgainstProtectionSpace: delegate callback,
// *  we also cancel the challenge.  OTOH, if all goes well we simply call our delegate
// *  with the challenge.
// *  \param challenge The authentication challenge to process; must not be nil.
// *  \param completionHandler The associated completion handler; must not be nil.
// */
//
//- (void)mainThreadDidReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(ChallengeCompletionHandler)completionHandler
//{
//    NSCAssert(challenge != nil);
//    NSCAssert(completionHandler != nil);
//    NSCAssert([NSThread isMainThread]);
//
//    if (self.pendingChallenge != nil) {
//
//        // Our delegate is not expecting a second authentication challenge before resolving the
//        // first.  Likewise, NSURLSession shouldn't send us a second authentication challenge
//        // before we resolve the first.  If this happens, assert, log, and cancel the challenge.
//        //
//        // Note that we have to cancel the challenge on the thread on which we received it,
//        // namely, the client thread.
//
//        [[self class] customHTTPProtocol:self logWithFormat:@"challenge %@ cancelled; other challenge pending", [[challenge protectionSpace] authenticationMethod]];
//        NSCAssert(NO);
//        [self clientThreadCancelAuthenticationChallenge:challenge completionHandler:completionHandler];
//    } else {
//        id<CustomHTTPProtocolDelegate>  strongDelegate;
//
//        strongDelegate = [[self class] delegate];
//
//        // Tell the delegate about it.  It would be weird if the delegate didn't support this
//        // selector (it did return YES from -customHTTPProtocol:canAuthenticateAgainstProtectionSpace:
//        // after all), but if it doesn't then we just cancel the challenge ourselves (or the client
//        // thread, of course).
//
//        if ( ! [strongDelegate respondsToSelector:@selector(customHTTPProtocol:canAuthenticateAgainstProtectionSpace:)] ) {
//            [[self class] customHTTPProtocol:self logWithFormat:@"challenge %@ cancelled; no delegate method", [[challenge protectionSpace] authenticationMethod]];
//            NSCAssert(NO);
//            [self clientThreadCancelAuthenticationChallenge:challenge completionHandler:completionHandler];
//        } else {
//
//            // Remember that this challenge is in progress.
//
//            self.pendingChallenge = challenge;
//            self.pendingChallengeCompletionHandler = completionHandler;
//
//            // Pass the challenge to the delegate.
//
//            [[self class] customHTTPProtocol:self logWithFormat:@"challenge %@ passed to delegate", [[challenge protectionSpace] authenticationMethod]];
//            [strongDelegate customHTTPProtocol:self didReceiveAuthenticationChallenge:self.pendingChallenge];
//        }
//    }
//}
//
///*! Cancels an authentication challenge that hasn't made it to the pending challenge state.
// *  \details This routine is called as part of various error cases in the challenge handling
// *  code.  It cancels a challenge that, for some reason, we've failed to pass to our delegate.
// *
// *  The routine is always called on the main thread but bounces over to the client thread to
// *  do the actual cancellation.
// *  \param challenge The authentication challenge to cancel; must not be nil.
// *  \param completionHandler The associated completion handler; must not be nil.
// */
//
//- (void)clientThreadCancelAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(ChallengeCompletionHandler)completionHandler
//{
//#pragma unused(challenge)
//    NSCAssert(challenge != nil);
//    NSCAssert(completionHandler != nil);
//    NSCAssert([NSThread isMainThread]);
//
//    [self performOnThread:self.clientThread modes:self.modes block:^{
//        completionHandler(NSURLSessionAuthChallengeCancelAuthenticationChallenge, nil);
//    }];
//}
//
///*! Cancels an authentication challenge that /has/ made to the pending challenge state.
// *  \details This routine is called by -stopLoading to cancel any challenge that might be
// *  pending when the load is cancelled.  It's always called on the client thread but
// *  immediately bounces over to the main thread (because .pendingChallenge is a main
// *  thread only value).
// */
//
//- (void)cancelPendingChallenge
//{
//    NSCAssert([NSThread currentThread] == self.clientThread);
//
//    // Just pass the work off to the main thread.  We do this so that all accesses
//    // to pendingChallenge are done from the main thread, which avoids the need for
//    // extra synchronisation.
//
//    [self performOnThread:nil modes:nil block:^{
//        if (self.pendingChallenge == nil) {
//            // This is not only not unusual, it's actually very typical.  It happens every time you shut down
//            // the connection.  Ideally I'd like to not even call -mainThreadCancelPendingChallenge when
//            // there's no challenge outstanding, but the synchronisation issues are tricky.  Rather than solve
//            // those, I'm just not going to log in this case.
//            //
//            // [[self class] customHTTPProtocol:self logWithFormat:@"challenge not cancelled; no challenge pending"];
//        } else {
//            id<CustomHTTPProtocolDelegate>  strongeDelegate;
//            NSURLAuthenticationChallenge *  challenge;
//
//            strongeDelegate = [[self class] delegate];
//
//            challenge = self.pendingChallenge;
//            self.pendingChallenge = nil;
//            self.pendingChallengeCompletionHandler = nil;
//
//            if ([strongeDelegate respondsToSelector:@selector(customHTTPProtocol:didCancelAuthenticationChallenge:)]) {
//                [[self class] customHTTPProtocol:self logWithFormat:@"challenge %@ cancellation passed to delegate", [[challenge protectionSpace] authenticationMethod]];
//                [strongeDelegate customHTTPProtocol:self didCancelAuthenticationChallenge:challenge];
//            } else {
//                [[self class] customHTTPProtocol:self logWithFormat:@"challenge %@ cancellation failed; no delegate method", [[challenge protectionSpace] authenticationMethod]];
//                // If we managed to send a challenge to the client but can't cancel it, that's bad.
//                // There's nothing we can do at this point except log the problem.
//                NSCAssert(NO);
//            }
//        }
//    }];
//}
//
//- (void)resolveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge withCredential:(NSURLCredential *)credential
//{
//    NSCAssert(challenge == self.pendingChallenge);
//    // credential may be nil
//    NSCAssert([NSThread isMainThread]);
//    NSCAssert(self.clientThread != nil);
//
//    if (challenge != self.pendingChallenge) {
//        [[self class] customHTTPProtocol:self logWithFormat:@"challenge resolution mismatch (%@ / %@)", challenge, self.pendingChallenge];
//        // This should never happen, and we want to know if it does, at least in the debug build.
//        NSCAssert(NO);
//    } else {
//        ChallengeCompletionHandler  completionHandler;
//
//        // We clear out our record of the pending challenge and then pass the real work
//        // over to the client thread (which ensures that the challenge is resolved on
//        // the same thread we received it on).
//
//        completionHandler = self.pendingChallengeCompletionHandler;
//        self.pendingChallenge = nil;
//        self.pendingChallengeCompletionHandler = nil;
//
//        [self performOnThread:self.clientThread modes:self.modes block:^{
//            if (credential == nil) {
//                [[self class] customHTTPProtocol:self logWithFormat:@"challenge %@ resolved without credential", [[challenge protectionSpace] authenticationMethod]];
//                completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, nil);
//            } else {
//                [[self class] customHTTPProtocol:self logWithFormat:@"challenge %@ resolved with <%@ %p>", [[challenge protectionSpace] authenticationMethod], [credential class], credential];
//                completionHandler(NSURLSessionAuthChallengeUseCredential, credential);
//            }
//        }];
//    }
//}

- (BOOL)evaluateServerTrust:(SecTrustRef)serverTrust
                  forDomain:(NSString *)domain {
    /*
     * 创建证书校验策略
     */
    NSMutableArray *policies = [NSMutableArray array];
    if (domain) {
        [policies addObject:(__bridge_transfer id) SecPolicyCreateSSL(true, (__bridge CFStringRef) domain)];
    } else {
        [policies addObject:(__bridge_transfer id) SecPolicyCreateBasicX509()];
    }
    /*
     * 绑定校验策略到服务端的证书上
     */
    SecTrustSetPolicies(serverTrust, (__bridge CFArrayRef) policies);
    /*
     * 评估当前serverTrust是否可信任，
     * 官方建议在result = kSecTrustResultUnspecified 或 kSecTrustResultProceed
     * 的情况下serverTrust可以被验证通过，https://developer.apple.com/library/ios/technotes/tn2232/_index.html
     * 关于SecTrustResultType的详细信息请参考SecTrust.h
     */
    SecTrustResultType result;
    SecTrustEvaluate(serverTrust, &result);
    return (result == kSecTrustResultUnspecified || result == kSecTrustResultProceed);
}

#pragma mark * NSURLSession delegate callbacks

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)newRequest completionHandler:(void (^)(NSURLRequest *))completionHandler
{
    NSMutableURLRequest *    redirectRequest;
    
#pragma unused(session)
#pragma unused(task)
    NSCAssert(task == self.task,@"task != self.task");
    NSCAssert(response != nil,@"response == nil");
    NSCAssert(newRequest != nil,@"newRequest == nil");
#pragma unused(completionHandler)
    NSCAssert(completionHandler != nil,@"completionHandler == nil");
    NSCAssert([NSThread currentThread] == self.clientThread,@"[NSThread currentThread] != self.clientThread");
    
    // The new request was copied from our old request, so it has our magic property.  We actually
    // have to remove that so that, when the client starts the new request, we see it.  If we
    // don't do this then we never see the new request and thus don't get a chance to change
    // its caching behaviour.
    //
    // We also cancel our current connection because the client is going to start a new request for
    // us anyway.
    
    NSCAssert([[self class] propertyForKey:kOurRecursiveRequestFlagProperty inRequest:newRequest] != nil,@"[[self class] propertyForKey:kOurRecursiveRequestFlagProperty inRequest:newRequest] == nil");
    
    redirectRequest = [newRequest mutableCopy];
    
    // 处理走IP直连时我们在header中设置的"host"字段情况
    if ([self.actualRequest.allHTTPHeaderFields valueForKey:@"host"] &&
        ![[self.actualRequest.allHTTPHeaderFields valueForKey:@"host"] isEqualToString:self.actualRequest.URL.host]) {
        
        NSString *originHost = [self.actualRequest.allHTTPHeaderFields valueForKey:@"host"];
        NSURLComponents *components = [NSURLComponents componentsWithURL:self.actualRequest.URL resolvingAgainstBaseURL:NO];
        components.host = originHost;
        // IP直连以前的URL
        NSURL *originURL = components.URL;
        // 进行IP直连之后，自己管理cookie
        [[TLMHTTPDNSCookieManager sharedInstance] handleHeaderFields:[response allHeaderFields] forURL:originURL];
        
        // 这句话是因为之前的httpdns的过程会把host手动设置，导致重定向的请求的host是之前的host，因此要把它置空
        [redirectRequest setValue:nil forHTTPHeaderField:@"host"];
    }
    
    // 有替换host的需求进行host替换
    NSString *host = newRequest.URL.host;
    if ([[[self class] delegate] respondsToSelector:@selector(protocolReplacedHostForHost:)] &&
        [[[self class] delegate] protocolReplacedHostForHost:host].length > 0) {
        if ([[[self class] delegate] respondsToSelector:@selector(protocolShouldHTTPDNSByURL:)] &&
            [[[self class] delegate] protocolShouldHTTPDNSByURL:newRequest.URL]) {
            NSURLComponents *components = [NSURLComponents componentsWithURL:newRequest.URL resolvingAgainstBaseURL:NO];
            components.host = [[[self class] delegate] protocolReplacedHostForHost:host];
            redirectRequest.URL = components.URL;
        }
    }
    
    [[self class] removePropertyForKey:kOurRecursiveRequestFlagProperty inRequest:redirectRequest];
    
    // Tell the client about the redirect.
    
    [[self client] URLProtocol:self wasRedirectedToRequest:redirectRequest redirectResponse:response];
    
    // Stop our load.  The CFNetwork infrastructure will create a new NSURLProtocol instance to run
    // the load of the redirect.
    
    // The following ends up calling -URLSession:task:didCompleteWithError: with NSURLErrorDomain / NSURLErrorCancelled,
    // which specificallys traps and ignores the error.
    
    [self.task cancel];
    
    [[self client] URLProtocol:self didFailWithError:[NSError errorWithDomain:NSCocoaErrorDomain code:NSUserCancelledError userInfo:nil]];
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential *))completionHandler
{
    if (!challenge) {
        return;
    }
    NSURLSessionAuthChallengeDisposition disposition = NSURLSessionAuthChallengePerformDefaultHandling;
    NSURLCredential *credential = nil;
    /*
     * 获取原始域名信息。
     */
    NSString *host = [[self.actualRequest allHTTPHeaderFields] objectForKey:@"host"];
    if (!host) {
        host = self.actualRequest.URL.host;
    }
    if ([challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust]) {
        if ([self evaluateServerTrust:challenge.protectionSpace.serverTrust forDomain:host]) {
            disposition = NSURLSessionAuthChallengeUseCredential;
            credential = [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust];
        } else {
            disposition = NSURLSessionAuthChallengePerformDefaultHandling;
        }
    } else {
        disposition = NSURLSessionAuthChallengePerformDefaultHandling;
    }
    // 对于其他的challenges直接使用默认的验证方案
    completionHandler(disposition, credential);
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler
{
    self.response = response;
    
    NSURLCacheStoragePolicy cacheStoragePolicy;
    NSInteger               statusCode;
    
#pragma unused(session)
#pragma unused(dataTask)
    NSCAssert(dataTask == self.task,@"dataTask != self.task");
    NSCAssert(response != nil,@"response == nil");
    NSCAssert(completionHandler != nil,@"completionHandler == nil");
    NSCAssert([NSThread currentThread] == self.clientThread,@"[NSThread currentThread] != self.clientThread");
    
    // Pass the call on to our client.  The only tricky thing is that we have to decide on a
    // cache storage policy, which is based on the actual request we issued, not the request
    // we were given.
    
    if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
        cacheStoragePolicy = CacheStoragePolicyForRequestAndResponse(self.actualRequest, (NSHTTPURLResponse *) response);
        statusCode = [((NSHTTPURLResponse *) response) statusCode];
    } else {
        NSCAssert(NO,@"response is Not KindOfClass:NSHTTPURLResponse");
        cacheStoragePolicy = NSURLCacheStorageNotAllowed;
        statusCode = 42;
    }
    
    [[self client] URLProtocol:self didReceiveResponse:response cacheStoragePolicy:cacheStoragePolicy];
    
    completionHandler(NSURLSessionResponseAllow);
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data
{
#pragma unused(session)
#pragma unused(dataTask)
    NSCAssert(dataTask == self.task,@"dataTask != self.task");
    NSCAssert(data != nil,@"data == nil");
    NSCAssert([NSThread currentThread] == self.clientThread,@"[NSThread currentThread] != self.clientThread");
    
    // Just pass the call on to our client.
    
    [[self client] URLProtocol:self didLoadData:data];
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask willCacheResponse:(NSCachedURLResponse *)proposedResponse completionHandler:(void (^)(NSCachedURLResponse *))completionHandler
{
#pragma unused(session)
#pragma unused(dataTask)
    NSCAssert(dataTask == self.task,@"dataTask != self.task");
    NSCAssert(proposedResponse != nil,@"proposedResponse == nil");
    NSCAssert(completionHandler != nil,@"completionHandler == nil");
    NSCAssert([NSThread currentThread] == self.clientThread,@"[NSThread currentThread] != self.clientThread");
    
    // We implement this delegate callback purely for the purposes of logging.
    
    completionHandler(proposedResponse);
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error
// An NSURLSession delegate callback.  We pass this on to the client.
{
#pragma unused(session)
#pragma unused(task)
    NSCAssert( (self.task == nil) || (task == self.task),@"(self.task != nil) && (task != self.task)" );        // can be nil in the 'cancel from -stopLoading' case
    NSCAssert([NSThread currentThread] == self.clientThread,@"[NSThread currentThread] != self.clientThread");
    
    // Just log and then, in most cases, pass the call on to our client.
    
    if (error == nil) {
        // 处理走IP直连时我们在header中设置的"host"字段情况，自行处理cookie
        if ([self.actualRequest.allHTTPHeaderFields valueForKey:@"host"]
            && ![[self.actualRequest.allHTTPHeaderFields valueForKey:@"host"] isEqualToString:self.actualRequest.URL.host]
            && [task.response isKindOfClass:[NSHTTPURLResponse class]]) {
            NSString *originHost =[self.actualRequest.allHTTPHeaderFields valueForKey:@"host"];
            NSURLComponents *components = [NSURLComponents componentsWithURL:self.actualRequest.URL resolvingAgainstBaseURL:NO];
            components.host = originHost;
            NSURL *originURL = components.URL;
            [[TLMHTTPDNSCookieManager sharedInstance] handleHeaderFields:[(NSHTTPURLResponse *)task.response allHeaderFields] forURL:originURL];
        }
        
        [[self client] URLProtocolDidFinishLoading:self];
    } else if ( [[error domain] isEqual:NSURLErrorDomain] && ([error code] == NSURLErrorCancelled) ) {
        // Do nothing.  This happens in two cases:
        //
        // o during a redirect, in which case the redirect code has already told the client about
        //   the failure
        //
        // o if the request is cancelled by a call to -stopLoading, in which case the client doesn't
        //   want to know about the failure
    } else {
        
        [[self client] URLProtocol:self didFailWithError:error];
    }
    
    // We don't need to clean up the connection here; the system will call, or has already called,
    // -stopLoading to do that.
}

#pragma mark - CFHTTPDNSRequestTaskDelegate

- (void)task:(CFHTTPDNSRequestTask *)task didReceiveRedirection:(NSURLRequest *)request response:(NSURLResponse *)response {
    NSMutableURLRequest *mRequest = [request mutableCopy];
    [NSURLProtocol removePropertyForKey:kOurRecursiveRequestFlagProperty inRequest:mRequest];
    NSURLResponse *cResponse = [response copy];
    
    //处理原始请求的cookie,因为url与实际host的不匹配，系统不会把cookie放到cookiestorage中。
    //这里暂时没做条件判断，因为能进到这里的都是被操作过cf-httpdns的
    NSString *originHost =[self.actualRequest.allHTTPHeaderFields valueForKey:@"host"];
    NSURLComponents *components = [NSURLComponents componentsWithURL:self.actualRequest.URL resolvingAgainstBaseURL:NO];
    components.host = originHost;
    NSURL *originURL = components.URL;
    if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
        [[TLMHTTPDNSCookieManager sharedInstance] handleHeaderFields:[(NSHTTPURLResponse *)response allHeaderFields] forURL:originURL];
    }
    
    [task stopLoading];
    [self.client URLProtocol:self wasRedirectedToRequest:mRequest redirectResponse:cResponse];
    [self.client URLProtocolDidFinishLoading:self];
}

- (void)task:(CFHTTPDNSRequestTask *)task didReceiveResponse:(NSURLResponse *)response cachePolicy:(NSURLCacheStoragePolicy)cachePolicy {
    [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:cachePolicy];
}

- (void)task:(CFHTTPDNSRequestTask *)task didReceiveData:(NSData *)data {
    [self.client URLProtocol:self didLoadData:data];
}
- (void)task:(CFHTTPDNSRequestTask *)task didCompleteWithError:(NSError *)error {
    if (error) {
        //NSLog(@"Did complete with error, %@.", error);
        [self.client URLProtocol:self didFailWithError:error];
    } else {
        //NSLog(@"Did complete success.");
        //cookie设置
        NSString *originHost =[self.actualRequest.allHTTPHeaderFields valueForKey:@"host"];
        NSURLComponents *components = [NSURLComponents componentsWithURL:self.actualRequest.URL resolvingAgainstBaseURL:NO];
        components.host = originHost;
        NSURL *originURL = components.URL;
        [[TLMHTTPDNSCookieManager sharedInstance] handleHeaderFields:task.response.headerFields forURL:originURL];
        
        [self.client URLProtocolDidFinishLoading:self];
    }
}

@end
