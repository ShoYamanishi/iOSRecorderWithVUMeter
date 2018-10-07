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
#ifndef _SLOW_TASK_WAVE_WRITER_H_
#define _SLOW_TASK_WAVE_WRITER_H_


#ifdef USE_POSIX_VERSION_OF_SLOW_TASK_MANAGER
#import "SlowTaskManagerPosix.h"
#else
#import "SlowTaskManager.h"
#endif


#ifdef USE_POSIX_VERSION_OF_SLOW_TASK_MANAGER
@interface SlowTaskWaveWriter : SlowTaskManagerPosix
#else
@interface SlowTaskWaveWriter : SlowTaskManager
#endif

@property (nonatomic, strong) NSString *mBaseFileName;
@property int mSampleRate;
@property int mNumberOfChannels;

@end

#endif /*_SLOW_TASK_WAVE_WRITER_H_*/

