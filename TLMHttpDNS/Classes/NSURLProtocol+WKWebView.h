//
//  NSURLProtocol+WKWebView.h
//  DNSTest
//
//  Created by tongleiming on 2019/5/9.
//  Copyright © 2019 tongleiming. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSURLProtocol (WKWebView)

+ (void)wk_registerScheme:(NSString*)scheme;

+ (void)wk_unregisterScheme:(NSString*)scheme;

@end

NS_ASSUME_NONNULL_END
