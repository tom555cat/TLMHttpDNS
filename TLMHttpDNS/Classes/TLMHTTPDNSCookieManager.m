//
//  TLMHTTPDNSCookieManager.m
//  Pods
//
//  Created by tongleiming on 2019/5/23.
//

#import "TLMHTTPDNSCookieManager.h"

@interface TLMHTTPDNSCookieManager ()

@end

@implementation TLMHTTPDNSCookieManager
{
    MAHTTPDNSCookieFilterBlock filterBlock;
}

+ (instancetype)sharedInstance {
    static TLMHTTPDNSCookieManager *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[TLMHTTPDNSCookieManager alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init
{
    if (self = [super init]) {
        filterBlock = ^BOOL(NSHTTPCookie *cookie, NSURL *URL) {
            if ([URL.host containsString:cookie.domain]) {
                return YES;
            }
            return NO;
        };
    }
    return self;
}

- (void)setFilterBlock:(MAHTTPDNSCookieFilterBlock)aFilter
{
    if (aFilter != nil) {
        filterBlock = aFilter;
    }
}

- (NSArray <NSHTTPCookie *> *)handleHeaderFields:(NSDictionary *)headerFields forURL:(NSURL *)URL
{
    NSArray *cookieArray = [NSHTTPCookie cookiesWithResponseHeaderFields:headerFields forURL:URL];
    if (cookieArray != nil) {
        NSHTTPCookieStorage *cookieStorage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
        for (NSHTTPCookie *cookie in cookieArray) {
            if (filterBlock(cookie,URL)) {
                [cookieStorage setCookie:cookie];
            }
        }
    }
    return cookieArray;
}

- (NSArray <NSHTTPCookie *> *)getCookiesForURL:(NSURL *)URL
{
    NSMutableArray *cookieArray = [NSMutableArray array];
    NSHTTPCookieStorage *cookieStorage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
    for (NSHTTPCookie *cookie in [cookieStorage cookies]) {
        if (filterBlock(cookie, URL)) {
            [cookieArray addObject:cookie];
        }
    }
    return cookieArray;
}

- (NSString *)getRequestCookieHeaderForURL:(NSURL *)URL {
    NSArray *cookieArray = [self getCookiesForURL:URL];
    if (cookieArray != nil && cookieArray.count > 0) {
        NSDictionary *cookieDic = [NSHTTPCookie requestHeaderFieldsWithCookies:cookieArray];
        if ([cookieDic objectForKey:@"Cookie"]) {
            NSString *returnString = cookieDic[@"Cookie"];
            return returnString;
        }
    }
    return nil;
}

@end
