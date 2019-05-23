//
//  TLMHTTPDNSCookieManager.h
//  Pods
//
//  Created by tongleiming on 2019/5/23.
//

#import <Foundation/Foundation.h>

typedef BOOL(^MAHTTPDNSCookieFilterBlock)(NSHTTPCookie *, NSURL *);

@interface TLMHTTPDNSCookieManager : NSObject

+ (instancetype)sharedInstance;

- (void)setFilterBlock:(MAHTTPDNSCookieFilterBlock)aFilter;

- (NSArray<NSHTTPCookie *> *)handleHeaderFields:(NSDictionary *)headerFields forURL:(NSURL *)URL;

- (NSArray<NSHTTPCookie *> *)getCookiesForURL:(NSURL *)URL;

- (NSString *)getRequestCookieHeaderForURL:(NSURL *)URL;

@end
