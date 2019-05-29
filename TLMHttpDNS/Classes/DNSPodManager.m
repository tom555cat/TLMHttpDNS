//
//  DNSPodManager.m
//  TLMHttpDNS_Example
//
//  Created by tongleiming on 2019/5/24.
//  Copyright © 2019 tongleiming1989@sina.com. All rights reserved.
//

#import "DNSPodManager.h"
#import "TLMIPDefinition.h"
#import "NSURLSession+SynchronousTask.h"
#import "TLMHTTPProtocol.h"

static NSString *const urlStr = @"http://119.29.29.29/d?dn=%@&ttl=1";

static NSString *const kTLMURLProtocolKey = @"kTLMURLProtocolKey";
static NSMutableDictionary<NSString *, TLMIPDefinition *> *hostIPMap = nil;

@interface DNSPodManager ()

// 是否从HTTPDNS异步请求ip地址
@property (nonatomic, assign) BOOL async;

@end

@implementation DNSPodManager

+ (instancetype)sharedInstance {
    static DNSPodManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[super allocWithZone:NULL] init];
    });
    return instance;
}

+ (instancetype)allocWithZone:(struct _NSZone *)zone {
    return [self sharedInstance];
}

- (void)replaceHostWithIPAsync:(BOOL)async {
    _async = async;
}

- (void)start {
    [TLMHTTPProtocol start];
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _async = YES;
        [TLMHTTPProtocol setDelegate:(id<TLMHTTPProtocolDelegate>)self];
    }
    return self;
}

#pragma mark - private

+ (NSString *)ipForHost:(NSString *)host {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        hostIPMap = [[NSMutableDictionary alloc] init];
    });
    
    TLMIPDefinition *ipDefinition = hostIPMap[host];
    if (!ipDefinition) {
        if ([DNSPodManager sharedInstance].async == YES) {
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
            if ([DNSPodManager sharedInstance].async == YES) {
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
    NSArray *partArray = [result componentsSeparatedByString:@","];
    if (partArray.count == 2) {
        // ttl部分
        ttl = [partArray[1] integerValue];
        
        // ip地址部分
        NSArray *ipArray = [partArray[0] componentsSeparatedByString:@";"];
        if (ipArray.count > 0) {
            // 使用返回的第一个ip地址
            ip = ipArray[0];
        }
        if ([self isIPAddressValid:ip]) {
            TLMIPDefinition *ipDefinition = [[TLMIPDefinition alloc] initWithIP:ip serverTTL:ttl];
            return ipDefinition;
        }
    }
    
    return nil;
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


#pragma mark - TLMHTTPProtocolDelegate

- (BOOL)protocolShouldHandleURL:(NSURL *)url {
    // DNSPod不需要进行ip直连
    if ([[url host] isEqualToString:@"119.29.29.29"]) {
        return NO;
    }
    return YES;
}

- (NSString *)protocolCFNetworkHTTPDNSGetIPByDomain:(NSString *)domain {
    NSString *ip = [[self class] ipForHost:domain];
    return ip;
}

@end
