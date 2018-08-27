//
//  MyH264Encoder.h
//  MyZhiBo
//
//  Created by tanpeng on 2018/8/27.
//  Copyright © 2018年 Study. All rights reserved.
//

#import <Foundation/Foundation.h>


@import AVFoundation;
@protocol H264EncoderDelegate <NSObject>
- (void)didGetSparameterSet:(NSData *)sps pictureParameterSet:(NSData *) pps;
- (void)didGetEncodedData:(NSData *)data isKeyFrame:(BOOL)isKeyFrame;
    
    @end

@interface MyH264Encoder : NSObject
    @property(weak, nonatomic) id<H264EncoderDelegate>delegate;
- (void)initializeEncoder;
- (void)initEncoderWithWith:(int)width height:(int) height;
- (void)encode:(CMSampleBufferRef)sampleBuffer;
- (void)endEncode;
    
@end
