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

#import <Accelerate/Accelerate.h>
#import "ViewController.h"


@interface ViewController ()

@end

@implementation ViewController {

    bool                mRecording;
    AudioInputManager*  mAIManager;
    NSString*           mDevName;
    NSString*           mDataSource;
    long                mSampleRate;
    long                mNumOfChan;
    SlowTaskWaveWriter* mWaveWriter;

}


static const NSString* const RecordingButtonStartRecording = @"Start Recording";
static const NSString* const RecordingButtonStopRecording  = @"Stop Recording";


- (void)viewDidLoad {

    [ super viewDidLoad ];

    mAIManager = [ [ AudioInputManager alloc ] initWithDelegate : self ];

    NSString*          devName;
    NSString*          dataSource;

    [ mAIManager getCurrentlySetDevice : &devName
                            SampleRate : &mSampleRate
                         NumOfChannels : &mNumOfChan
                            DataSource : &dataSource   ];

    NSLog( @"Audio Input Device [%@]",  devName     );
    NSLog( @"Data Source [%@]",         dataSource  );
    NSLog( @"Sample Rate [%ld]",        mSampleRate );
    NSLog( @"Number of Channels [%ld]", mNumOfChan  );

    mWaveWriter = [ [ SlowTaskWaveWriter alloc ] init ];
    mWaveWriter.mBaseFileName     = @"sample_recorded";
    mWaveWriter.mSampleRate       = (int)mSampleRate;
    mWaveWriter.mNumberOfChannels = (int)mNumOfChan;

    mRecording = false;

    [ mRecordingButton setEnabled: YES ];
    [ mRecordingButton setTitleColor : [UIColor blackColor]
                            forState : UIControlStateNormal ];
    [ mRecordingButton
           setTitle : (NSString*_Nullable)RecordingButtonStartRecording
           forState : UIControlStateNormal                               ];
}


-(void) viewWillAppear : (BOOL) animated
{
    NSLog(@"viewWillAppear");
    [ mAIManager open : mSampleRate NumberOfChennels : (UInt32) mNumOfChan ];
    [ mVUMeter activate ];
}


-(void) viewDidAppear : (BOOL) animated
{
    [ mVUMeter reset ];
}


-(void) viewWillDisappear : (BOOL) animated
{
    NSLog(@"viewWillDisappear");
    [ mVUMeter   deactivate ];
    [ mAIManager close      ];
}


- (IBAction) onRecordingButtonPressed : (id) sender
{
    if ( mRecording ) {

        [ mWaveWriter stop ];

        [ mRecordingButton setTitleColor : [ UIColor blackColor ]
                                forState : UIControlStateNormal   ];
        [ mRecordingButton
            setTitle : (NSString *_Nullable)RecordingButtonStartRecording
            forState : UIControlStateNormal                               ];
        mRecording = false;

    }
    else {

        [ mWaveWriter start ];
        [ mRecordingButton setTitleColor : [UIColor redColor]
                                forState : UIControlStateNormal ];
        [ mRecordingButton
            setTitle : (NSString *_Nullable)RecordingButtonStopRecording
            forState : UIControlStateNormal                              ];
        mRecording = true;
    }
}



-(void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    if ( [segue.identifier isEqualToString : @"RecordingVCtoPlayWaveViewVC" ]){
    
        PlayWaveViewController *destDC = segue.destinationViewController;
        destDC.mDelegate = self;
    }
}

- (void) playWaveViewControllerDone : (PlayWaveViewController *) c
{
    ;
}


- (NSString*) playWaveViewControllerFileName {

    return @"sample_recorded.wav";

}


-(void) inputDataArrivedWithData : (SInt16*) data size : (UInt32) size
{
    // This demonstrates the use of vDSP to calculate RMS.
    // The performance gain, if any, will be limited due to
    // the conversion from Int16 to Float.

    if ( size > 0 ) {

        float fRMS, fAbsMAX;
        
        [ mAIManager calsRMS : &fRMS
                   andAbsMax : &fAbsMAX
                    fromData : data
                     andSize : size      ];

        [ mVUMeter setRMS : (unsigned short) fRMS
                andAbsMax : (unsigned short) fAbsMAX ];

        [ mWaveWriter feed : data length:size ];
        
    }
    else {

        free( data );
    }
    
}


-(void) slowTaskManagerStopping
{
    ;
}


-(void) slowTaskManagerReady
{
    ;
}

@end

