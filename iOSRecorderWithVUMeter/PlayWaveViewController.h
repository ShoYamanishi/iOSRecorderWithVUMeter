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

#ifndef _PLAY_WAVE_VIEW_CONTROLLER_H_
#define _PLAY_WAVE_VIEW_CONTROLLER_H_

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

#import "WaveDrawingView.h"

@class PlayWaveViewController;

@protocol PlayWaveViewControllerDelegate <NSObject>

- (void)      playWaveViewControllerDone : (PlayWaveViewController *) c;
- (NSString*) playWaveViewControllerFileName;

@end

@interface PlayWaveViewController : UIViewController
{
IBOutlet UILabel*           mLabelFileName;
IBOutlet UILabel*           mLabelSNR;
IBOutlet UILabel*           mLabelSpeechRMS;
IBOutlet UILabel*           mLabelNoiseRMS;
IBOutlet UILabel*           mLabelPeak;
IBOutlet UILabel*           mLabelLength;
IBOutlet WaveDrawingView*   mLabelWaveDrawing;
}

@property (nonatomic, weak) id < PlayWaveViewControllerDelegate > mDelegate;
@property (nonatomic, strong) AVAudioPlayer* mAP;

-(IBAction) done : (id) sender;

@end

#endif /*_PLAY_WAVE_VIEW_CONTROLLER_H_*/
