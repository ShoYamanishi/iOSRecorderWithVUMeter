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

#import "PlayWaveViewController.h"

#import "AVFoundation/AVFoundation.h"
#import "PlayWaveViewController.h"
#import "estimateSNR.h"

@interface PlayWaveViewController ()

@end
#define FILE_PATH_LEN  4096

@implementation PlayWaveViewController {

    char mFilePathBuf [ FILE_PATH_LEN ];
}


@synthesize mDelegate;
@synthesize mAP;


- (id) initWithNibName : (NSString *) nibNameOrNil
                bundle : (NSBundle *) nibBundleOrNil
{
    self = [ super initWithNibName : nibNameOrNil bundle : nibBundleOrNil ];
    
    if (self) {
        ;
    }

    return self;
}


-(NSData*) getWaveInfoFor : (NSString *) filepath
                    noise : (float*)     noiseLevel
                   speech : (float*)     speechLevel
                 drawArea : (CGRect)     area
                     peak : (int *)      peakVal
                   length : (int*)       lengthVal
{

    int width  = area.size.width;
    int height = area.size.height;
    
    [ filepath getCString : mFilePathBuf
                maxLength : FILE_PATH_LEN - 1
                 encoding : NSUTF8StringEncoding ];

    estimateSNR( mFilePathBuf, noiseLevel, speechLevel );
    
    int* plots  = computePeakAndPlots( mFilePathBuf,
                                       width,
                                       height,
                                       peakVal,
                                       lengthVal     );

    if ( plots == NULL ) {
        return nil;
    }

    NSData* plotsNSD = [ NSData dataWithBytes : plots
                                       length : width * 2 * sizeof(int) ];

    free(plots);

    return plotsNSD;
}


- (void) viewDidLoad
{
    [super viewDidLoad];

    CGRect drawFrame = mLabelWaveDrawing.frame;
    
   
    NSString *fileName = [ mDelegate playWaveViewControllerFileName ];

    if ( fileName == nil ) {

        mLabelFileName.text = @"<No file selected>";
        return;
    }

    mLabelFileName.text = fileName;
    
    NSArray* paths = NSSearchPathForDirectoriesInDomains( NSDocumentDirectory,
                                                          NSUserDomainMask,
                                                          YES                 );

    NSString* docsDir  = [ paths objectAtIndex : 0 ];
    NSString* fullPath = [ docsDir stringByAppendingPathComponent : fileName ];
    NSURL*    url      = [ NSURL fileURLWithPath : fullPath ];

    float noiseLevel;
    float speechLevel;
    int   peakVal;
    int   lengthVal;

    NSData* plots = [ self getWaveInfoFor : fullPath
                                    noise : &noiseLevel
                                   speech : &speechLevel
                                 drawArea : drawFrame
                                     peak : &peakVal
                                   length : &lengthVal   ];

    //Plot the graph on the screen.
    [ mLabelWaveDrawing plotWith : plots ];
    
    mLabelSNR.text       = [ NSString stringWithFormat : @"%3.1f[dB]",
                             speechLevel - noiseLevel                  ];

    mLabelSpeechRMS.text = [ NSString stringWithFormat : @"%3.1f[dB]",
                             speechLevel                               ];

    mLabelNoiseRMS.text  = [ NSString stringWithFormat : @"%3.1f[dB]",
                             noiseLevel                                ];

    mLabelPeak.text      = [ NSString stringWithFormat : @"%d",
                             peakVal                                   ];

    mLabelLength.text    = [ NSString stringWithFormat : @"%5.3f[sec]",
                             ((double)lengthVal) / 16000               ];

    NSError *error;

    mAP = [ [ AVAudioPlayer alloc ] initWithContentsOfURL : url
                                                    error : &error ];

    [ mAP prepareToPlay ];
    [ mAP play ];

}


-(IBAction) done : (id) sender
{
    [ self dismissViewControllerAnimated : true completion : nil ];
}


@end

