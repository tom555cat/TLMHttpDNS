//
//  NSURLSessionConfiguration+protocol.h
//  TLMHttpDNS
//
//  Created by tongleiming on 2019/5/29.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSURLSessionConfiguration (protocol)

+ (void)hookDefaultSessionConfiguration;

@end

NS_ASSUME_NONNULL_END
