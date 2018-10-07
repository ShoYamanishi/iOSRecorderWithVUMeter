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
#ifndef _SLOW_TASK_MANAGER_POSIX_H_
#define _SLOW_TASK_MANAGER_POSIX_H_

#import <Foundation/Foundation.h>

#import "SlowTaskManager.h"

@class SlowTaskManagerPosix;

@interface SlowTaskManagerPosix : NSObject

@property (nonatomic,weak) id <SlowTaskManagerDelegate> mDelegate;
-(id)    init;
-(bool)  start;
-(bool)  stop;
-(bool)  abort;
-(bool)  feed: (void*)data length:(int)len;

// Following 4 will be overriden by the subclasses.
-(bool) taskStart;
-(void) taskStop;
-(void) taskAbort;
-(bool) taskFeed:   (void*) data length : (int)len;
-(void) taskIgnore: (void*) data length : (int)len;
@end


#endif /*_SLOW_TASK_MANAGER_POSIX_H_*/

