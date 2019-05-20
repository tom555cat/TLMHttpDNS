//
//  CFHTTPDNSRequestTask.m
//  Pods
//
//  Created by tongleiming on 2019/5/20.
//

#import "CFHTTPDNSRequestTask.h"

@implementation CFHTTPDNSRequestResponse
@end

@interface CFHTTPDNSRequestTask () <NSStreamDelegate>

// 这个是atomic，为什么要写成atomic？
@property (atomic, assign) BOOL completed;
@property (nonatomic, weak) id<CFHTTPDNSRequestTaskDelegate> delegate;
@property (nonatomic, copy) NSURLRequest *originalRequest;          // 原始网络请求
@property (nonatomic, copy) NSURLRequest *swizzleRequst;            // HTTPDNS处理后的请求
@property (nonatomic, strong) NSInputStream *inputStream;           // 读数据stream
@property (nonatomic, strong) NSMutableData *resultData;            // 请求结果数据
@property (nonatomic, strong) CFHTTPDNSRequestResponse *response;   // 请求Response

@end

@implementation CFHTTPDNSRequestTask

- (instancetype)init {
    if (self = [super init]) {
        self.completed = NO;
        self.response = [[CFHTTPDNSRequestResponse alloc] init];
    }
    return self;
}

#pragma mark external call

- (CFHTTPDNSRequestTask *)initWithURLRequest:(NSURLRequest *)request swizzleRequest:(NSURLRequest *)swizzleRequest delegate:(id<CFHTTPDNSRequestTaskDelegate>)delegate {
    
    if (!request || !delegate || !swizzleRequest) {
        return nil;
    }
    
    if (self = [self init]) {
        self.originalRequest = request;
        self.swizzleRequst = swizzleRequest;
        self.delegate = delegate;
        self.resultData = [NSMutableData data];
    }
    return self;
}

- (void)startLoading {
    // HTTP Header
    NSDictionary *headFields = self.swizzleRequst.allHTTPHeaderFields;
    
    // HTTP Body
    CFDataRef bodyData = NULL;
    if (self.swizzleRequst.HTTPBody) {
        // bodyData也持有数据
        bodyData = (__bridge_retained CFDataRef) self.swizzleRequst.HTTPBody;
    } else if (self.swizzleRequst.HTTPBodyStream) {
        // 从HTTPBodyStream中读取出http body
        bodyData = (__bridge_retained CFDataRef)[self.swizzleRequst.HTTPBodyStream readOutData];
    }
    
    // url并没有持有，为什么上面bodyData需要持有？
    CFStringRef url = (__bridge CFStringRef) [self.swizzleRequst.URL absoluteString];
    CFURLRef requestURL = CFURLCreateWithString(kCFAllocatorDefault, url, NULL);
    
    // 原请求所使用的方法，GET或POST；为什么又持有了？
    CFStringRef requestMethod = (__bridge_retained CFStringRef) self.swizzleRequst.HTTPMethod;
    
    // 根据请求的URL、方法、版本创建CFHTTPMessageRef对象
    CFHTTPMessageRef cfRequest = CFHTTPMessageCreateRequest(kCFAllocatorDefault, requestMethod, requestURL, kCFHTTPVersion1_1);
    if (bodyData) {
        CFHTTPMessageSetBody(cfRequest, bodyData);
    }
    
    // Set HTTP Header
    for (NSString *header in headFields) {
        CFStringRef requestHeader = (__bridge CFStringRef)header;
        CFStringRef requestHeaderValue = (__bridge CFStringRef)[headFields valueForKey:header];
        CFHTTPMessageSetHeaderFieldValue(cfRequest, requestHeader, requestHeaderValue);
    }
    
    // 创建CFHTTPMessage对象的输入流
    CFReadStreamRef readStream = CFReadStreamCreateForHTTPRequest(kCFAllocatorDefault, cfRequest);
    self.inputStream = (__bridge_transfer NSInputStream *)readStream;
    
    // HTTPS请求处理SNI场景
    if ([self isHTTPSScheme]) {
        // 设置SNI host信息
        NSString *host = [self.swizzleRequst.allHTTPHeaderFields objectForKey:@"host"];
        if (!host) {
            host = self.originalRequest.URL.host;
        }
        [self.inputStream setProperty:NSStreamSocketSecurityLevelNegotiatedSSL forKey:NSStreamSocketSecurityLevelKey];
        NSDictionary *sslProperties = @{(__bridge id) kCFStreamSSLPeerName : host};
        [self.inputStream setProperty:sslProperties forKey:(__bridge_transfer NSString *)kCFStreamPropertySSLSettings];
    }
    [self openInputStream];
    
    CFRelease(cfRequest);
    CFRelease(requestURL);
    cfRequest = NULL;
    CFRelease(requestMethod);
    if (bodyData) {
        CFRelease(bodyData);
    }
}

/**
 *  判断是否为HTTPS请求
 */
- (BOOL)isHTTPSScheme {
    return [self.originalRequest.URL.scheme isEqualToString:@"https"];
}

@end

@implementation NSInputStream (ReadOutData)

- (NSData *)readOutData
{
    NSMutableData *resultData = [NSMutableData data];
    uint8_t *buffer = (uint8_t *)malloc(4096);
    [self open];
    NSInteger amount;
    while ((amount = [self read:buffer maxLength:4096]) > 0) {
        [resultData appendBytes:buffer length:amount];
    }
    [self close];
    free(buffer);
    return resultData;
}

@end
