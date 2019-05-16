//
//  TLMIPDefinition.m
//  DNSTest
//
//  Created by tongleiming on 2019/5/16.
//  Copyright © 2019 tongleiming. All rights reserved.
//

#import "TLMIPDefinition.h"

@interface TLMIPDefinition ()

@property (nonatomic, copy) NSString *ip;
@property (nonatomic, strong) NSDate *serverTTL;
@property (nonatomic, strong) NSDate *localTTL;

@end

@implementation TLMIPDefinition

- (instancetype)initWithIP:(NSString *)ip serverTTL:(NSInteger)ttl {
    NSParameterAssert(ip);
    
    self = [super init];
    if (self) {
        self.ip = ip;
        self.serverTTL = [NSDate dateWithTimeIntervalSinceNow:ttl];
        self.localTTL = [NSDate dateWithTimeIntervalSinceNow:60];
    }
    return self;
}

- (BOOL)isServerTTLTimeout {
#warning 手机如果调整时区，那么会造成TTL时间过长
    NSDate *date = [NSDate date];
    if ([date compare:self.serverTTL] == NSOrderedAscending) {
        return NO;
    } else {
        return YES;
    }
}

- (BOOL)isLocalTTLTimeout {
    NSDate *date = [NSDate date];
    if ([date compare:self.localTTL] == NSOrderedAscending) {
        return NO;
    } else {
        return YES;
    }
}

@end
