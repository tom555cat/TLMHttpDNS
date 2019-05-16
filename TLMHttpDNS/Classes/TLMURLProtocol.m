//
//  TLMURLProtocol.m
//  DNSTest
//
//  Created by tongleiming on 2019/5/6.
//  Copyright © 2019 tongleiming. All rights reserved.
//

#import "TLMURLProtocol.h"
#import "NSURLSession+SynchronousTask.h"
#import "TLMHttpDNS.h"
#import "TLMIPDefinition.h"

static NSString *const kTLMURLProtocolKey = @"kTLMURLProtocolKey";
static NSString *kIP = nil;
static NSMutableDictionary<NSString *, TLMIPDefinition *> *hostIPMap = nil;


@interface TLMURLProtocol () <NSURLSessionDelegate>

@property (nonnull,strong) NSURLSessionDataTask *task;

@end

@implementation TLMURLProtocol

+ (void)setIP:(NSString *)ip {
    kIP = ip;
}

+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    if ([NSURLProtocol propertyForKey:kTLMURLProtocolKey inRequest:request]) {
        // 自己复制的request也会走到这里，如果不排除就会进入死循环
        return NO;
    }
    
    // Determines whether the protocol subclass can handle the specified request.
    // 拦截对域名的请求
    if ([[TLMHttpDNS sharedInstance].resolveHosts containsObject:request.URL.host]) {
        return YES;
    }
    return NO;
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request {
    // 如果上面的方法返回YES，那么request会传到这里，通常什么都不做，直接返回request
    // 该方法在Queue:com.apple.NSURLSession-work(serial)队列中调用，所以在这一层级做同步调用HTTPDNS请求
    
    NSMutableURLRequest *mutableRequest;
    if ([request.HTTPMethod isEqualToString:@"POST"]) {  // 由于拷贝HTTP body的原因，单独处理
        mutableRequest = [self handlePostRequestBodyWithRequest:request];
    } else {
        mutableRequest = [request mutableCopy];
    }
    
    // 给复制的请求打标记，打过标记的请求直接放行
    [NSURLProtocol setProperty:@YES forKey:kTLMURLProtocolKey inRequest:mutableRequest];
    
    // 解析request的域名对应的IP地址
    NSString *ip = [self ipForHost:request.URL.host];
    if (ip) {   // ip地址不为空，则将host替换为ip地址，否则降级为LocalDNS解析
        // ip地址替换host
        NSURL *url = mutableRequest.URL;
        NSRange hostRange = [url.absoluteString rangeOfString:url.host];
        NSMutableString *urlStr = [NSMutableString stringWithString:url.absoluteString];
        [urlStr stringByReplacingCharactersInRange:hostRange withString:ip];
        [mutableRequest setURL:[NSURL URLWithString:urlStr]];
        
        // 在header中增加域名，防止运营商懵逼
        [mutableRequest setValue:url.host forHTTPHeaderField:@"HOST"];
    }
    
    return mutableRequest;
}

- (void)startLoading {
    // 进行请求
    NSURLSession *session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration] delegate:self delegateQueue:nil];
    self.task = [session dataTaskWithRequest:self.request];
    [self.task resume];
}

- (void)stopLoading {

}

#pragma mark -

+ (NSString *)ipForHost:(NSString *)host {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        hostIPMap = [[NSMutableDictionary alloc] init];
    });
    
    TLMIPDefinition *ipDefinition = hostIPMap[host];
    if (!ipDefinition) {
        if ([TLMHttpDNS sharedInstance].async == YES) {
            [self getIPFromHTTPDNSAsync:host];
            return nil;
        } else {
            ipDefinition = [self getIPFromHTTPDNSSync:host];
            hostIPMap[host] = ipDefinition;
        }
    }
    
    // 过期检查
    if (ipDefinition) {
        if ([ipDefinition isServerTTLTimeout]) {
            if ([TLMHttpDNS sharedInstance].async == YES) {
                [self getIPFromHTTPDNSAsync:host];
                return nil;
            } else {
                ipDefinition = [self getIPFromHTTPDNSSync:host];
                hostIPMap[host] = ipDefinition;
            }
        }
    }
    
    return ipDefinition.ip;
}

// 从HTTPDNS中异步获取IP地址
+ (void)getIPFromHTTPDNSAsync:(NSString *)host {
    NSString *url = [NSString stringWithFormat:@"http://119.29.29.29/d?dn=%@&ttl=1", host];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url] cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:5];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];
    
    NSURLSessionDataTask *dataTask = [session dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        TLMIPDefinition *ipDefinition = [self parseHTTPDNSResponse:data];
        hostIPMap[host] = ipDefinition;
    }];
    [dataTask resume];
}

// 从HTTPDNS中同步获取IP地址
+ (TLMIPDefinition *)getIPFromHTTPDNSSync:(NSString *)host {
    NSString *url = [NSString stringWithFormat:@"http://119.29.29.29/d?dn=%@&ttl=1", host];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url] cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:5];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];
    
    NSURLResponse *response = nil;
    NSError *error = nil;
    NSData *data = [session sendSynchronousDataTaskWithRequest:request returningResponse:&response error:&error];
    
    TLMIPDefinition *ipDefinition = [self parseHTTPDNSResponse:data];
    return ipDefinition;
}

+ (TLMIPDefinition *)parseHTTPDNSResponse:(NSData *)data {
    // 解析ip地址和ttl
    NSString *ip;
    NSInteger ttl = 0;
    
    NSString *result = [[NSString alloc] initWithData:data encoding:NSASCIIStringEncoding];
    NSArray *ttlArray = [result componentsSeparatedByString:@","];
    if (ttlArray.count > 1) {
        ttl = [ttlArray[1] integerValue];
    }
    NSArray *ipArray = [result componentsSeparatedByString:@";"];
    if (ipArray.count > 0) {
#warning 使用返回的第一个ip地址
        ip = ipArray[0];
    }
    if ([self isIPAddressValid:ip]) {
        TLMIPDefinition *ipDefinition = [[TLMIPDefinition alloc] initWithIP:ip serverTTL:ttl];
        return ipDefinition;
    } else {
        return nil;
    }
}

+ (BOOL)isIPAddressValid:(NSString *)ipAddress {
    NSArray *components = [ipAddress componentsSeparatedByString:@"."];
    if (components.count != 4) {
        return NO;
    }
    NSCharacterSet *unwantedCharacters = [[NSCharacterSet characterSetWithCharactersInString:@"0123456789."] invertedSet];
    if ([ipAddress rangeOfCharacterFromSet:unwantedCharacters].location != NSNotFound) {
        return NO;
    }
    for (NSString *string in components) {
        if ((string.length < 1) || (string.length > 3 )) {return NO;}
        if (string.intValue > 255) {return NO;}
    }
    if  ([[components objectAtIndex:0] intValue]==0){return NO;}
    return YES;
}

#pragma mark 处理POST请求相关POST  用HTTPBodyStream来处理BODY体
// A HTTP body stream is preserved when copying an NSURLRequest object
+ (NSMutableURLRequest *)handlePostRequestBodyWithRequest:(NSURLRequest *)request {
    NSMutableURLRequest * req = [request mutableCopy];
    if ([request.HTTPMethod isEqualToString:@"POST"]) {
        if (!request.HTTPBody) {
            uint8_t d[1024] = {0};
            NSInputStream *stream = request.HTTPBodyStream;
            NSMutableData *data = [[NSMutableData alloc] init];
            [stream open];
            while ([stream hasBytesAvailable]) {
                NSInteger len = [stream read:d maxLength:1024];
                if (len > 0 && stream.streamError == nil) {
                    [data appendBytes:(void *)d length:len];
                }
            }
            req.HTTPBody = [data copy];
            [stream close];
        }
    }
    return req;
}

#pragma mark - NSURLSessionDelegate

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler {
    [[self client] URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageAllowed];
    
    completionHandler(NSURLSessionResponseAllow);
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data {
    [[self client] URLProtocol:self didLoadData:data];
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(nullable NSError *)error {
    [self.client URLProtocolDidFinishLoading:self];
}

@end
