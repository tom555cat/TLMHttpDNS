//
//  TLMViewController.m
//  TLMHttpDNS
//
//  Created by tongleiming1989@sina.com on 05/16/2019.
//  Copyright (c) 2019 tongleiming1989@sina.com. All rights reserved.
//

#import "TLMViewController.h"
#import "TestViewController.h"
#import "PostTestViewController.h"
#import "WKWebViewTestController.h"
#import "URLConnectionViewController.h"
#import "CertificateAuthViewController.h"

@interface TLMViewController () <UITableViewDelegate, UITableViewDataSource>

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray *dataArray;

@end

@implementation TLMViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view, typically from a nib.

    self.dataArray = @[@"正常测试", @"Post请求测试", @"WKWebView测试", @"URLConnection测试", @"客户端证书验证"];
    
    self.tableView = [[UITableView alloc] initWithFrame:CGRectMake(0, 0, [UIScreen mainScreen].bounds.size.width, [UIScreen mainScreen].bounds.size.height)];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    [self.view addSubview:self.tableView];
    [self.tableView reloadData];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - UITableViewDelegate & UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.dataArray.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"HttpDNSCell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"HttpDNSCell"];
    }
    cell.textLabel.text = self.dataArray[indexPath.row];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.row == 0) {
        TestViewController *vc = [[TestViewController alloc] init];
        [self.navigationController pushViewController:vc animated:YES];
    } else if (indexPath.row == 1) {
        PostTestViewController *vc = [[PostTestViewController alloc] init];
        [self.navigationController pushViewController:vc animated:YES];
    } else if (indexPath.row == 2) {
        WKWebViewTestController *vc = [[WKWebViewTestController alloc] init];
        [self.navigationController pushViewController:vc animated:YES];
    } else if (indexPath.row == 3) {
        URLConnectionViewController *vc = [[URLConnectionViewController alloc] init];
        [self.navigationController pushViewController:vc animated:YES];
    } else if (indexPath.row == 4) {
        CertificateAuthViewController *vc = [[CertificateAuthViewController alloc] init];
        [self.navigationController pushViewController:vc animated:YES];
    }
    return;
}

@end
