//
//  ViewController.m
//  MyZhiBo
//
//  Created by tanpeng on 2018/8/23.
//  Copyright © 2018年 Study. All rights reserved.
//

#import "ViewController.h"
#import <VideoToolbox/VideoToolbox.h>
#import <AVFoundation/AVFoundation.h>
#import "ViewUtils.h"
#import "H264Encoder.h"
// 主要功能：
// 点击录制按钮开始采集视频，通过H264Encoder对视频进行视频编码，编码结果回调到一下两个方法：
// - (void)didGetEncodedData:(NSData *)data isKeyFrame:(BOOL)isKeyFrame
// - (void)didGetSparameterSet:(NSData *)sps pictureParameterSet:(NSData *)pps
// 将数据根据H264的帧格式保存到本地Document目录下的test.h264文件，这是一个H264的裸数据，只有
// 视频信息和时长，没有音频和播放进度。
// 播放的话需要将test.h264改为test.mov播放器才能识别。
// demo的目的是通过调整kFrameRate、GOP、averageBitRate平均码率、然后看test.h264的效果，主要
// 从大小，清晰度等因素去观察参数的影响。
// 这个demo还没有包含解码的代码，需要的话后面加上，在发给大家
@interface ViewController ()<AVCaptureVideoDataOutputSampleBufferDelegate,H264EncoderDelegate>
@property (nonatomic, strong) H264Encoder *encoder;
@property (nonatomic, strong) AVCaptureSession *captureSession;
@property (nonatomic, strong) AVCaptureConnection * connection;
@property (nonatomic, strong) AVSampleBufferDisplayLayer *displayLayer;
@property (nonatomic, strong) NSFileHandle *fileHandle;
@property (nonatomic, assign) int fd;
@property (nonatomic, strong) NSString *savePath;

@property (nonatomic, strong) UIButton *snapButton;
@property (nonatomic, assign) BOOL isrecording;

@property (weak, nonatomic) IBOutlet UILabel *fileSizeLabel;// 用于显示保存在本地目录视频文件的大小

//@property (nonatomic, assign) uint8_t *sps;
//@property (nonatomic, assign) uint8_t *pps;
//@property (nonatomic, assign) NSInteger *spsSize;
//@property (nonatomic, assign) NSInteger *ppsSize;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self commonInitialize];
    [self setupUI];
    // Do any additional setup after loading the view, typically from a nib.
}
- (void)setupUI {
    // 添加另一个播放Layer，这个layer接收CMSampleBuffer来播放
    AVSampleBufferDisplayLayer *sb = [[AVSampleBufferDisplayLayer alloc]init];
    sb.backgroundColor = [UIColor clearColor].CGColor;
    self.displayLayer = sb;
    sb.videoGravity = AVLayerVideoGravityResizeAspect;
    [self.view.layer addSublayer:self.displayLayer];
    
    
    // snap button to capture image
    self.snapButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.snapButton.frame = CGRectMake(0, 0, 70.0f, 70.0f);
    self.snapButton.clipsToBounds = YES;
    self.snapButton.layer.cornerRadius = self.snapButton.width / 2.0f;
    self.snapButton.layer.borderColor = [UIColor whiteColor].CGColor;
    self.snapButton.layer.borderWidth = 2.0f;
    self.snapButton.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.5];
    self.snapButton.layer.rasterizationScale = [UIScreen mainScreen].scale;
    self.snapButton.layer.shouldRasterize = YES;
    [self.snapButton addTarget:self action:@selector(snapButtonPressed:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.snapButton];
}
- (void)snapButtonPressed:(UIButton *)button
{
    if(!self.isrecording) {
        self.snapButton.layer.borderColor = [UIColor redColor].CGColor;
        self.snapButton.backgroundColor = [[UIColor redColor] colorWithAlphaComponent:0.5];
        [self startCamera];
        self.isrecording = YES;
        
        // 启动录制十秒后自动关闭，为了比较相同时间长度的视频大小，可以注释掉
        [self performSelector:@selector(stopAction) withObject:nil afterDelay:10];
    } else {
        
        self.snapButton.layer.borderColor = [UIColor whiteColor].CGColor;
        self.snapButton.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.5];
        
        [self stopCamera];
        self.isrecording = NO;
    }
}
- (void) stopCamera
{
        
    }
- (void) startCamera
{
    AVCaptureDevice *cameraDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    AVCaptureDeviceInput *inputDevice = [AVCaptureDeviceInput deviceInputWithDevice:cameraDevice error:nil
                                       ];
    AVCaptureVideoDataOutput *outoutDevice = [[AVCaptureVideoDataOutput alloc] init];
      NSString* key = (NSString*)kCVPixelBufferPixelFormatTypeKey;
    NSNumber *val = [NSNumber numberWithUnsignedInteger:kCVPixelFormatType_420YpCbCr8BiPlanarFullRange];
    NSDictionary *videoSetting = [NSDictionary dictionaryWithObject:val forKey:key];
    outoutDevice.videoSettings = videoSetting;
    [outoutDevice setSampleBufferDelegate:self queue:dispatch_get_main_queue()];
    self.captureSession = [[AVCaptureSession alloc] init];
    [self.captureSession addInput:inputDevice];
    [self.captureSession addOutput:outoutDevice];
    
    [self.captureSession beginConfiguration];
    [self.captureSession setSessionPreset:AVCaptureSessionPresetMedium];
    [self.captureSession setSessionPreset:[NSString stringWithString:AVCaptureSessionPreset640x480]];
    self.connection = [outoutDevice connectionWithMediaType:AVMediaTypeVideo];
    
    [self setRelativeVideoOrientation];
    NSNotificationCenter* notify = [NSNotificationCenter defaultCenter];
    
    [notify addObserver:self
               selector:@selector(statusBarOrientationDidChange:)
                   name:@"StatusBarOrientationDidChange"
                 object:nil];
    
    
    [self.captureSession commitConfiguration];
    
    
    
}
- (void)setRelativeVideoOrientation
{
    switch (<#expression#>) {
        case <#constant#>:
        <#statements#>
        break;
        
        default:
        break;
    }
}
- (void)viewWillLayoutSubviews
{
    [super viewWillLayoutSubviews];
    self.displayLayer.frame = self.view.frame;
    
    self.snapButton.center = self.view.contentCenter;
    self.snapButton.bottom = self.view.height - 15.0f;
    
}

- (void) commonInitialize {
    self.encoder = [[H264Encoder alloc] init];
    [self.encoder initializeEncoder];
    
    // 设置文件保存位置在document文件夹
    NSFileManager *fileManager = [NSFileManager defaultManager];
    self.savePath = [self path];
    [fileManager removeItemAtPath:self.savePath error:nil];
    [fileManager createFileAtPath:self.savePath contents:nil attributes:nil];
    
    self.isrecording = NO;
}
#pragma mark - private helper
- (NSString *)path {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *docDir = paths.firstObject;
    return  [docDir stringByAppendingPathComponent:@"test.h264"];
    
}
    
- (int64_t)fileSize {
    return [[[NSFileManager defaultManager] attributesOfItemAtPath:self.savePath error:nil] fileSize];
}
    
- (NSString *)fileSizeString:(int64_t)size {
    double totalBytes = size / 1024.0f;
    NSInteger multiplyFactor = 0;
    NSArray *tokens = @[@"KB",@"MB",@"GB",@"TB"];
    
    while (totalBytes > 1024) {
        totalBytes /= 1024;
        multiplyFactor += 1;
    }
    return [NSString stringWithFormat:@"%.2f%@",totalBytes,tokens[multiplyFactor]];
}
- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


@end
