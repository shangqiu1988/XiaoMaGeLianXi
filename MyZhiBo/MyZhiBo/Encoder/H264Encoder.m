//
//  H264Encoder.m
//  VideoAudioCapture
//
//  Created by Leo on 2017/8/5.
//  Copyright © 2017年 Leo. All rights reserved.
//

#import "H264Encoder.h"
@import VideoToolbox;
@import AVFoundation;

#define kFrameRate 30
NSUInteger videoFrameRate = kFrameRate;
NSUInteger gop = kFrameRate * 2;
NSUInteger averageBitRate = 800 * 1024; // 800kbps



@implementation H264Encoder
{
    VTCompressionSessionRef encodeeSssion;
    dispatch_queue_t workQueue;
    CMFormatDescriptionRef  format;
    CMSampleTimingInfo * timingInfo;
    BOOL initialized;
    int  frameCount;
    NSData *sps;
    NSData *pps;
}

- (void)initializeEncoder {
    encodeeSssion = nil;
    initialized = true;
    workQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    frameCount = 0;
    sps = NULL;
    pps = NULL;
}

- (void)initEncoderWithWith:(int)width height:(int)height {
    dispatch_sync(workQueue, ^{
        
        CFMutableDictionaryRef sessionAttributes = CFDictionaryCreateMutable(
                                                                             NULL,
                                                                             0,
                                                                             &kCFTypeDictionaryKeyCallBacks,
                                                                             &kCFTypeDictionaryValueCallBacks);
        
        
        // 创建编码
        OSStatus status = VTCompressionSessionCreate(NULL, width, height, kCMVideoCodecType_H264, sessionAttributes, NULL, NULL, didCompressH264, (__bridge void *)(self),  &encodeeSssion);
        NSLog(@"H264: VTCompressionSessionCreate %d", (int)status);
        
        if (status != 0)
        {
            NSLog(@"H264: Unable to create a H264 session");
            return ;
        }
        
        /// 最大关键帧间隔，可设定为 fps 的2倍，影响一个 gop 的大小
        VTSessionSetProperty(encodeeSssion, kVTCompressionPropertyKey_MaxKeyFrameInterval, (__bridge CFTypeRef)@(gop));
        /// 一个GOP的时间间隔
        VTSessionSetProperty(encodeeSssion, kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration, (__bridge CFTypeRef)@(gop/videoFrameRate));
        VTSessionSetProperty(encodeeSssion, kVTCompressionPropertyKey_ExpectedFrameRate, (__bridge CFTypeRef)@(videoFrameRate));
        /// /// 视频的码率，单位是 bps
        VTSessionSetProperty(encodeeSssion, kVTCompressionPropertyKey_AverageBitRate, (__bridge CFTypeRef)@(averageBitRate));
        
        NSArray *limit = @[@(averageBitRate * 1.5/8), @(1)];
        // 设置码率的最高限制，不超过平均码率的1.5倍，因为这里的单位是byte，所以除以8，这是为了防止某一秒的码率超过限制
        VTSessionSetProperty(encodeeSssion, kVTCompressionPropertyKey_DataRateLimits, (__bridge CFArrayRef)limit);
        VTSessionSetProperty(encodeeSssion, kVTCompressionPropertyKey_RealTime, kCFBooleanTrue);// 实时编码
        VTSessionSetProperty(encodeeSssion, kVTCompressionPropertyKey_ProfileLevel, kVTProfileLevel_H264_Main_AutoLevel);// 编码等级
        VTSessionSetProperty(encodeeSssion, kVTCompressionPropertyKey_AllowFrameReordering, kCFBooleanTrue); // 是否在编码中使用B帧，因为B帧是双向预测帧，所以编码时间顺序和展示时间顺序不同，设置为true压缩率会更高
        
        // 基于上下文的自适应可变长编码 和 基于上下文的自适应二进制算术编码 选择熵编码方式
        VTSessionSetProperty(encodeeSssion, kVTCompressionPropertyKey_H264EntropyMode, kVTH264EntropyMode_CABAC);
        
        VTCompressionSessionPrepareToEncodeFrames(encodeeSssion);
        
        
        
    });
}


- (void)encode:(CMSampleBufferRef)sampleBuffer {
    dispatch_sync(workQueue, ^{
        
        frameCount++;
        // Get the CV Image buffer
        CVImageBufferRef imageBuffer = (CVImageBufferRef)CMSampleBufferGetImageBuffer(sampleBuffer);
        //            CVPixelBufferRef pixelBuffer = (CVPixelBufferRef)CMSampleBufferGetImageBuffer(sampleBuffer);
        
        // Create properties
        CMTime presentationTimeStamp = CMTimeMake(frameCount, (int32_t)videoFrameRate);
        CMTime duration = CMTimeMake(1, (int32_t)videoFrameRate);
        VTEncodeInfoFlags flags;
        NSDictionary *properties = nil;
        if (frameCount % (int32_t)gop == 0) {
            properties = @{(__bridge NSString *)kVTEncodeFrameOptionKey_ForceKeyFrame: @YES};
        }
        // Pass it to the encoder
        OSStatus statusCode = VTCompressionSessionEncodeFrame(encodeeSssion,
                                                              imageBuffer,
                                                              presentationTimeStamp,
                                                              duration,
                                                              (__bridge CFDictionaryRef)properties,
                                                              NULL, &flags);
        // Check for error
        if (statusCode != noErr) {
            NSLog(@"H264: VTCompressionSessionEncodeFrame failed with %d", (int)statusCode);
            
            // End the session
            VTCompressionSessionInvalidate(encodeeSssion);
            CFRelease(encodeeSssion);
            encodeeSssion = NULL;
            return;
        }
        NSLog(@"H264: VTCompressionSessionEncodeFrame Success");
    });

}

- (void) endEncode
{
    // Mark the completion
    VTCompressionSessionCompleteFrames(encodeeSssion, kCMTimeInvalid);
    
    // End the session
    VTCompressionSessionInvalidate(encodeeSssion);
    CFRelease(encodeeSssion);
    encodeeSssion = NULL;
}


// VTCompressionOutputCallback（回调方法）  由VTCompressionSessionCreate调用
void didCompressH264(void *outputCallbackRefCon, void *sourceFrameRefCon, OSStatus status, VTEncodeInfoFlags infoFlags,
                     CMSampleBufferRef sampleBuffer )
{
    NSLog(@"didCompressH264 called with status %d infoFlags %d", (int)status, (int)infoFlags);
    if (status != 0) return;
    
    if (!CMSampleBufferDataIsReady(sampleBuffer))
    {
        NSLog(@"didCompressH264 data is not ready ");
        return;
    }
    H264Encoder* encoder = (__bridge H264Encoder*)outputCallbackRefCon;
    
    // Check if we have got a key frame first
    bool keyframe = !CFDictionaryContainsKey( (CFArrayGetValueAtIndex(CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, true), 0)), kCMSampleAttachmentKey_NotSync);
    
    if (keyframe)
    {
        CMFormatDescriptionRef format = CMSampleBufferGetFormatDescription(sampleBuffer);
        // CFDictionaryRef extensionDict = CMFormatDescriptionGetExtensions(format);
        // Get the extensions
        // From the extensions get the dictionary with key "SampleDescriptionExtensionAtoms"
        // From the dict, get the value for the key "avcC"
        
        size_t sparameterSetSize, sparameterSetCount;
        const uint8_t *sparameterSet;
        OSStatus statusCode = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, 0, &sparameterSet, &sparameterSetSize, &sparameterSetCount, 0 );
        if (statusCode == noErr)
        {
            // Found sps and now check for pps
            size_t pparameterSetSize, pparameterSetCount;
            const uint8_t *pparameterSet;
            OSStatus statusCode = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, 1, &pparameterSet, &pparameterSetSize, &pparameterSetCount, 0 );
            if (statusCode == noErr)
            {
                // Found pps
                encoder->sps = [NSData dataWithBytes:sparameterSet length:sparameterSetSize];
                encoder->pps = [NSData dataWithBytes:pparameterSet length:pparameterSetSize];
                if (encoder->_delegate)
                {
                    [encoder->_delegate didGetSparameterSet:encoder->sps pictureParameterSet:encoder->pps];
                }
            }
        }
    }
    
    CMBlockBufferRef dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer);
    size_t length, totalLength;
    char *dataPointer;
    OSStatus statusCodeRet = CMBlockBufferGetDataPointer(dataBuffer, 0, &length, &totalLength, &dataPointer);
    if (statusCodeRet == noErr) {
        
        size_t bufferOffset = 0;
        static const int AVCCHeaderLength = 4;
        //一般情况下都是只有1帧，在最开始编码的时候有2帧，取最后一帧
        while (bufferOffset < totalLength - AVCCHeaderLength) {
            
            // Read the NAL unit length
            uint32_t NALUnitLength = 0;
            memcpy(&NALUnitLength, dataPointer + bufferOffset, AVCCHeaderLength);
            
            // Convert the length value from Big-endian to Little-endian，网络字节序一般使用大端字节序
            NALUnitLength = CFSwapInt32BigToHost(NALUnitLength);
            
            //naluData 即为一帧h264数据。
            //如果保存到文件中，需要将此数据前加上 [0 0 0 1] 4个字节，按顺序写入到h264文件中。
            //如果推流，需要将此数据前加上4个字节表示数据长度的数字，此数据需转为大端字节序。
            //关于大端和小端模式
            
            
            NSData* data = [[NSData alloc] initWithBytes:(dataPointer + bufferOffset + AVCCHeaderLength) length:NALUnitLength];
            [encoder->_delegate didGetEncodedData:data isKeyFrame:keyframe];
            
            // Move to the next NAL unit in the block buffer
            bufferOffset += AVCCHeaderLength + NALUnitLength;
        }
        
    }
    
}
@end
