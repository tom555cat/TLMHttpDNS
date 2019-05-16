//
//  TLMHttpDNS.m
//  DNSTest
//
//  Created by tongleiming on 2019/5/13.
//  Copyright © 2019 tongleiming. All rights reserved.
//

#import "TLMHttpDNS.h"
#import "NSURLSession+SynchronousTask.h"
#import "TLMURLProtocol.h"

@interface TLMHttpDNS ()

@property (nonatomic, assign) BOOL async;

@end

@implementation TLMHttpDNS

+ (instancetype)sharedInstance {
    static TLMHttpDNS *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[super allocWithZone:NULL] init];
    });
    return instance;
}

+ (instancetype)allocWithZone:(struct _NSZone *)zone {
    return [self sharedInstance];
}

- (void)replaceHostWithIPAsync:(BOOL)async {
    self.async = async;
    [NSURLProtocol registerClass:[TLMURLProtocol class]];
}

//- (void)replaceHostWithIP {
//    [NSURLProtocol registerClass:[TLMURLProtocol class]];
//}


@end
