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

#import "CacheStoragePolicy.h"
#import "CanonicalRequest.h"
#import "CFHTTPDNSRequestTask.h"
#import "NSURLProtocol+WKWebView.h"
#import "NSURLRequest+NSURLProtocolExtension.h"
#import "NSURLSession+hook.h"
#import "NSURLSession+SynchronousTask.h"
#import "QNSURLSessionDemux.h"
#import "TLMHTTPDNSCookieManager.h"
#import "TLMHTTPProtocol.h"
#import "TLMIPDefinition.h"

FOUNDATION_EXPORT double TLMHttpDNSVersionNumber;
FOUNDATION_EXPORT const unsigned char TLMHttpDNSVersionString[];

