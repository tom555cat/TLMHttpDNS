//
//  NSURLRequest+NSURLProtocolExtension.h
//  Pods
//
//  Created by tongleiming on 2019/5/20.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSURLRequest (NSURLProtocolExtension)

- (NSMutableURLRequest *)TLMHttpDNS_getPostRequestIncludeBody;

@end

NS_ASSUME_NONNULL_END
