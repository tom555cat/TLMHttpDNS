//
//  TLMURLProtocol.h
//  DNSTest
//
//  Created by tongleiming on 2019/5/6.
//  Copyright © 2019 tongleiming. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface TLMURLProtocol : NSURLProtocol

+ (void)setIP:(NSString *)ip;

@end

NS_ASSUME_NONNULL_END
