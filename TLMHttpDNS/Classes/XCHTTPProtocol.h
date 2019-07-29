//
//  XCHTTPProtocol.h
//  DNSTest
//
//  Created by tongleiming on 2019/5/6.
//  Copyright © 2019 tongleiming. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "XCHTTPProtocolDelegate.h"


@interface XCHTTPProtocol : NSURLProtocol

+ (void)start;

+ (void)setDelegate:(id<XCHTTPProtocolDelegate>)newValue;

@end

