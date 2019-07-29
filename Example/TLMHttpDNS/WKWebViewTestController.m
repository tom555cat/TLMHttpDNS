//
//  WKWebViewTestController.m
//  DNSTest
//
//  Created by tongleiming on 2019/5/9.
//  Copyright © 2019 tongleiming. All rights reserved.
//

#import "WKWebViewTestController.h"
#import <WebKit/WebKit.h>
#import "NSURLProtocol+WKWebView.h"

@interface WKWebViewTestController ()

@end

@implementation WKWebViewTestController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    [NSURLProtocol wk_registerScheme:@"http"];
    [NSURLProtocol wk_registerScheme:@"https"];
    
    
    NSString *url = [NSString stringWithFormat:@"http://www.tomcat.com:3000/users"];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url] cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:10];
    
    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    WKWebView *wkWebView = [[WKWebView alloc] initWithFrame:CGRectMake(0, 0, [UIScreen mainScreen].bounds.size.width, [UIScreen mainScreen].bounds.size.height) configuration:config];
    [wkWebView loadRequest:request];
    [self.view addSubview:wkWebView];
}

/*
#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
}
*/

@end
