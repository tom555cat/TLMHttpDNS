//
//  TLMHttpDNS.h
//  DNSTest
//
//  Created by tongleiming on 2019/5/13.
//  Copyright © 2019 tongleiming. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface TLMHttpDNS : NSObject

+ (instancetype)sharedInstance;

// 需要替换ip地址的host数组
@property (nonatomic, copy) NSArray *resolveHosts;

// 是否从HTTPDNS异步请求ip地址
@property (nonatomic, assign, readonly) BOOL async;

/**
 resolveHosts中的host用ip地址替换

 @param async YES，HTTPDNS使用异步请求；NO，HTTPDNS使用同步请求
 */
- (void)replaceHostWithIPAsync:(BOOL)async;


@end

NS_ASSUME_NONNULL_END
