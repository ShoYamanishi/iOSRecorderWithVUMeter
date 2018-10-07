// MIT License
//
// Copyright (c) [2018] [Shoichiro Yamanishi]
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.
//
#ifndef _AUDIO_INPUT_MANAGER_H_
#define _AUDIO_INPUT_MANAGER_H_

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>

@protocol AudioInputManagerDelegate <NSObject>

@optional
-(void) audioInputClosed;
-(void) inputDataArrivedWithData:(SInt16*)data size:(UInt32)size;
@end

enum _stateAIM {
    INIT,
    DEVICE_OPENED,
    DEAD
};

@interface AudioInputManager : NSObject

@property (nonatomic,weak) id <AudioInputManagerDelegate>
                          mDelegate;

@property (atomic)NSLock* mStateLock;

@property (atomic) volatile enum _stateAIM
                          mState;

@property long            mNumberOfChannels;

@property AudioUnit       mAudioUnit;

-(id)   initWithDelegate : (id<AudioInputManagerDelegate>)delegate;

-(void) terminate;

-(bool) open : (double) sampleRate NumberOfChennels : (UInt32) numOfChan;

-(bool) close;

-(bool) setPreferredDevice    : (NSString*) devName
                SampleRate    : (long     ) sampleRate
                NumOfChannels : (long     ) numChan
                DataSource    : (NSString*) dataSource;

-(bool) getCurrentlySetDevice : (NSString **) devName
                   SampleRate : (long*      ) sampleRate
                NumOfChannels : (long*      ) numChan
                   DataSource : (NSString **) dataSource;

-(NSArray*) getAvailableDataSources;

-(void) calsRMS : (float*)  rms
      andAbsMax : (float*)  max
       fromData : (SInt16*) data
        andSize : (UInt32)  size;

@end

#endif /* _AUDIO_INPUT_MANAGER_H_ */

