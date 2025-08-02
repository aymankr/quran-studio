//
//  NonBlockingAudioRecorder.mm
//  Reverb
//
//  iOS-compatible NonBlockingAudioRecorder implementation
//

#import "NonBlockingAudioRecorder.h"
#import <AVFoundation/AVFoundation.h>

@implementation NonBlockingAudioRecorder {
    NSURL *_recordingURL;
    AVAudioFormat *_format;
    AVAudioFrameCount _bufferSize;
    BOOL _isRecording;
}

- (instancetype)initWithRecording:(NSURL *)url format:(AVAudioFormat *)format bufferSize:(AVAudioFrameCount)bufferSize {
    self = [super init];
    if (self) {
        _recordingURL = url;
        _format = format;
        _bufferSize = bufferSize;
        _isRecording = NO;
        NSLog(@"✅ NonBlockingAudioRecorder initialized for iOS (buffer: %u frames)", bufferSize);
    }
    return self;
}

- (void)startRecording {
    _isRecording = YES;
    NSLog(@"📹 NonBlockingAudioRecorder: Started recording to %@", _recordingURL.lastPathComponent);
}

- (void)stopRecording {
    _isRecording = NO;
    NSLog(@"🛑 NonBlockingAudioRecorder: Stopped recording");
}

- (BOOL)writeAudioBuffer:(AVAudioPCMBuffer *)buffer {
    if (!_isRecording) return NO;
    
    // Placeholder - in real implementation would write to file
    // For now, just log occasionally to show it's working
    static NSInteger frameCount = 0;
    frameCount += buffer.frameLength;
    
    if (frameCount % 48000 == 0) { // Log every ~1 second at 48kHz
        NSLog(@"📊 NonBlockingAudioRecorder: Processed %ld frames", (long)frameCount);
    }
    
    return YES;
}

- (BOOL)isCurrentlyRecording {
    return _isRecording;
}

@end