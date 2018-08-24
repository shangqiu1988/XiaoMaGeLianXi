//
//  H264Encoder.h
//  VideoAudioCapture
//
//  Created by Leo on 2017/8/5.
//  Copyright © 2017年 Leo. All rights reserved.
//

#import <Foundation/Foundation.h>

@import AVFoundation;
@protocol H264EncoderDelegate <NSObject>
- (void)didGetSparameterSet:(NSData *)sps pictureParameterSet:(NSData *) pps;
- (void)didGetEncodedData:(NSData *)data isKeyFrame:(BOOL)isKeyFrame;

@end

@interface H264Encoder : NSObject
@property(weak, nonatomic) id<H264EncoderDelegate>delegate;
- (void)initializeEncoder;
- (void)initEncoderWithWith:(int)width height:(int) height;
- (void)encode:(CMSampleBufferRef)sampleBuffer;
- (void)endEncode;
@end
