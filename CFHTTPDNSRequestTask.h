//
//  CFHTTPDNSRequestTask.h
//  Pods
//
//  Created by tongleiming on 2019/5/20.
//

#import <Foundation/Foundation.h>

@class CFHTTPDNSRequestTask;
@protocol CFHTTPDNSRequestTaskDelegate <NSObject>

- (void)task:(CFHTTPDNSRequestTask *)task didReceiveResponse:(NSURLResponse *)response cachePolicy:(NSURLCacheStoragePolicy)cachePolicy;
- (void)task:(CFHTTPDNSRequestTask *)task didReceiveRedirection:(NSURLRequest *)request response:(NSURLResponse *)response;
- (void)task:(CFHTTPDNSRequestTask *)task didReceiveData:(NSData *)data;
- (void)task:(CFHTTPDNSRequestTask *)task didCompleteWithError:(NSError *)error;

@end

@interface CFHTTPDNSRequestResponse : NSObject

// 这里为什么用CFIndex类型，为什么不用NSInteger?
@property (nonatomic, assign) CFIndex statusCode;
@property (nonatomic, copy) NSDictionary *headerFields;
@property (nonatomic, copy) NSString *httpVersion;

@end

@interface CFHTTPDNSRequestTask : NSObject

- (CFHTTPDNSRequestTask *)initWithURLRequest:(NSURLRequest *)request swizzleRequest:(NSURLRequest *)swizzleRequest delegate:(id<CFHTTPDNSRequestTaskDelegate>)delegate;
- (void)startLoading;

@end

@interface NSInputStream (ReadOutData)

- (NSData *)readOutData;

@end


