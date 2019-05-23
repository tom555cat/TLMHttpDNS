//
//  TLMHTTPProtocol.h
//  DNSTest
//
//  Created by tongleiming on 2019/5/6.
//  Copyright © 2019 tongleiming. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol TLMHTTPProtocolDelegate <NSObject>

/**
 是否需要继续处理这个url的网络请求；
 用户可以在这个方法中加入某些URL访问的过滤，例如DNSPod的请求可以返回NO。

 @param url 网络请求的url
 @return YES,继续处理;NO,不进行处理
 */
- (bool)protocolShouldHandleURL:(NSURL*)url;

@optional


/**
 判断url是否需要IP直连

 @param url url参数
 @return YES,需要;NO,不需要
 */
- (BOOL)protocolShouldHTTPDNSByURL:(NSURL *)url;

/**
 替换host

 @param host 需要替换的host
 @return 替换的host
 */
- (NSString *)protocolReplacedHostForHost:(NSString *)host;

/**
 获取该url需要IP直连返回的IP

 @param url 请求url
 @return 返回nil则不需要进行ip直连；返回ip则需要进行ip直连
 */
- (NSString *)protocolCheckURLIfNeededHTTPDNSByURL:(NSURL *)url;

/**
 获取域名对应的IP

 @param domain 域名(host)
 @return 返回nil则不需要进行ip直连；返回ip则需要进行ip直连
 */
- (NSString *)protocolCFNetworkHTTPDNSGetIPByDomain:(NSString *)domain;

@end

@interface TLMHTTPProtocol : NSURLProtocol

@end

NS_ASSUME_NONNULL_END
