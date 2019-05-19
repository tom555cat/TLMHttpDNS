//
//  AVPlayerViewController.m
//  DNSTest
//
//  Created by tom555cat on 2019/5/7.
//  Copyright © 2019年 tongleiming. All rights reserved.
//

#import "AVPlayerViewController.h"
#import <AVFoundation/AVFoundation.h>

#define KScreemWidth  [UIScreen mainScreen].bounds.size.width
#define KScreemHeight  [UIScreen mainScreen].bounds.size.height


@interface AVPlayerViewController ()

//视频播放器
@property (nonatomic,strong) AVPlayer *avplayer;

@end

@implementation AVPlayerViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    self.title = @"视频播放";
    [self setUI];
}

- (void)setUI {
    //初始化视频播放地址
    NSURL *mediaUrl = [NSURL URLWithString:@"http://cctv5ksw.v.kcdnvip.com"];
    
    // 初始化播放单元
    AVPlayerItem *item = [AVPlayerItem playerItemWithURL:mediaUrl];
    
    //初始化播放器对象
    self.avplayer = [[AVPlayer alloc]initWithPlayerItem:item];
    
    //显示画面
    AVPlayerLayer *layer = [AVPlayerLayer playerLayerWithPlayer:self.avplayer];
    
    //视频填充模式
    layer.videoGravity = AVLayerVideoGravityResizeAspect;
    
    //设置画布frame
    layer.frame = CGRectMake(0, KScreemHeight/2-250/2, KScreemWidth, 250);
    
    //添加到当前视图
    [self.view.layer addSublayer:layer];
    
    //设置播放暂停按钮
    NSArray *titles = @[@"播放",@"暂停"];
    CGFloat gap = (KScreemWidth-120)/3.0f;
    
    for (int i = 0; i < 2; i++) {
        UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
        [btn setTitle:titles[i] forState:UIControlStateNormal];
        btn.backgroundColor = [UIColor redColor];
        btn.tag = 555+i;
        btn.frame = CGRectMake(gap+i*(gap+60), KScreemHeight-100, 60, 40);
        btn.titleLabel.textAlignment = NSTextAlignmentCenter;
        btn.titleLabel.font = [UIFont systemFontOfSize:16.0f];
        [btn addTarget:self action:@selector(targetAction:) forControlEvents:UIControlEventTouchUpInside];
        [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        [self.view addSubview:btn];
    }
}


- (void)targetAction:(UIButton*)sender {
    switch (sender.tag) {
        case 555:  //播放
            [self play];
            break;
            
        case 556:  //暂停
            [self pause];
            break;
            
        default:
            break;
    }
}


- (void)play {
    if (self.avplayer.rate == 0) {
        [self.avplayer play];
    }
}

- (void)pause {
    if (self.avplayer.rate != 0) {
        [self.avplayer pause];
    }
}

@end
