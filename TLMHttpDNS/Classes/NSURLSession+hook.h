//
//  NSURLSession+hook.h
//  DNSTest
//
//  Created by tom555cat on 2019/5/6.
//  Copyright © 2019年 tongleiming. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSURLSession (hook)

+ (void)hookHTTPProtocol;

@end
