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
// Dependencies:
// The image of VU Meter taken from the following:
// https://en.wikipedia.org/wiki/VU_meter#/media/File:VU_Meter.jpg
// Iainf 05:15, 12 August 2006 (UTC) - Own work CC BY 2.5
//

#ifndef _VU_METER_VIEW_GL_H_
#define _VU_METER_VIEW_GL_H_

#import  <UIKit/UIKit.h>
#import  <QuartzCore/QuartzCore.h>
#include <OpenGLES/ES2/gl.h>
#include <OpenGLES/ES2/glext.h>

@interface VUMeterViewGL : UIView {}

-(void)setRMS : (unsigned short)rms andAbsMax : (unsigned short)absMax;
-(void)reset;
-(void)activate;
-(void)deactivate;

@end

#endif/*_VU_METER_VIEW_GL_H_*/


