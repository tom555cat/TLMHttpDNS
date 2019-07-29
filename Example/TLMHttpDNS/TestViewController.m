//
//  TestViewController.m
//  DNSTest
//
//  Created by tongleiming on 2019/5/6.
//  Copyright © 2019 tongleiming. All rights reserved.
//

#import "TestViewController.h"

@interface TestViewController ()

@property (nonatomic,strong) UITextView *textArea;

@end

@implementation TestViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    
    self.view.backgroundColor = [UIColor whiteColor];
    self.textArea = [[UITextView alloc] initWithFrame:CGRectMake(0, 0, [UIScreen mainScreen].bounds.size.width, 800)];
    [self.view addSubview:self.textArea];
    
    NSString *url = [NSString stringWithFormat:@"https://www.hao123.com"];
    NSMutableURLRequest * request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url] cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:10];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];
    
    NSURLSessionDataTask *dataTask = [session dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        NSString *str = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        NSLog(@"%@", str);
        dispatch_async(dispatch_get_main_queue(), ^{
            NSString *text = self.textArea.text;
            NSString *result = [NSString stringWithFormat:@"%@\n%@", text, str];
            self.textArea.text = result;
        });
    }];
    [dataTask resume];
}

@end
