#ifdef __OBJC__
#import <UIKit/UIKit.h>
#else
#ifndef FOUNDATION_EXPORT
#if defined(__cplusplus)
#define FOUNDATION_EXPORT extern "C"
#else
#define FOUNDATION_EXPORT extern
#endif
#endif
#endif

#import "NSURLProtocol+WKWebView.h"
#import "NSURLSession+hook.h"
#import "NSURLSession+SynchronousTask.h"
#import "TLMHttpDNS.h"
#import "TLMIPDefinition.h"
#import "TLMURLProtocol.h"

FOUNDATION_EXPORT double TLMHttpDNSVersionNumber;
FOUNDATION_EXPORT const unsigned char TLMHttpDNSVersionString[];

