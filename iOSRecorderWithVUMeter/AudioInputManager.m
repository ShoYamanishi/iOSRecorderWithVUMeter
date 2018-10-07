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
#include "stdatomic.h"

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <Accelerate/Accelerate.h>

#include <libkern/OSAtomic.h>

static const UInt32       kOutputBus = 0;
static const UInt32       kInputBus  = 1;

#define AUDIO_CB_BUF_IN_SAMPLES 1024

#import "AudioInputManager.h"


@implementation AudioInputManager {
 
    volatile BOOL      mSessionActive;

    //App's preference.
    NSString*          mPreferredInputByApp;
    long               mPreferredNumberOfChannelsByApp;
    double             mPreferredSampleRateByApp;
    
    // Current values on the system.
    NSArray*           mAvailableInputs;
    AVAudioSessionRouteDescription*
                       mCurrentRoute;
    long               mMaximumInputNumberOfChannels;
    double             mSampleRate;
    long               mNumberOfInputComponents;
    double             mPreferredSampleRateByAudioSession;
    long               mNumInputComponents;
    AudioComponent*    mInputComponents;
    
    // Float buffer to calculate some values out of
    // audio chunks given by the AudioUnit's callback.
    float              mFloatBuffer[ AUDIO_CB_BUF_IN_SAMPLES ];

}


@synthesize mDelegate;
@synthesize mState;
@synthesize mNumberOfChannels;
@synthesize mAudioUnit;

static OSStatus renderCallbackOnAudioThread(
    void*                       inRefCon,
    AudioUnitRenderActionFlags* ioActionFlags,
    const AudioTimeStamp*       inTimeStamp,
    UInt32                      inBusNumber,
    UInt32                      inNumberFrames,
    AudioBufferList*            ioData
);


-(id)initWithDelegate : (id < AudioInputManagerDelegate > ) delegate
{
    self = [super init];

    if( self == nil ) {
        return nil;
    }
    
    mDelegate = delegate;
    
    AVAudioSession *audioSession = [ AVAudioSession sharedInstance ];
    
    if ( audioSession == nil ) {
        return nil;
    }
    
    NSError *error;
    
    if ( [ audioSession setMode : AVAudioSessionModeDefault
                          error : &error]                    != YES ) {
        // An alternative is AVAudioSessionModeMeasurement.
        return nil;
    }
    
    if ( [ audioSession setCategory : AVAudioSessionCategoryPlayAndRecord
                        withOptions : (
                            AVAudioSessionCategoryOptionDuckOthers      |
                            AVAudioSessionCategoryOptionAllowBluetooth  |
                            AVAudioSessionCategoryOptionDefaultToSpeaker
                        )
                              error : &error                        ] != YES ) {
        return nil;
    }
    
    if ( [ audioSession
              overrideOutputAudioPort : AVAudioSessionPortOverrideSpeaker
                                error : &error                      ] != YES ) {
        return nil;
    }
    
    if ( ![ audioSession setActive : YES error : &error ] ) {

        return nil;
    }

    [ self getCurrentAudioSessionProperties ];
    
    [ self setupNotifications ];

    mState = INIT;
    atomic_thread_fence(memory_order_release);

    return self;
}


-(void)terminate
{
    [ self close ];
    [ self unregisterNotifications ];
    NSError *er;
    [ [ AVAudioSession sharedInstance ] setActive : NO error : &er ];
}


-(bool) open : (double) sampleRate NumberOfChennels : (UInt32) numOfChan;
{
    // Somehow as of iOS 12.0 (16A366), we have to wait for a bit
    // before calling AudioOutputUnitStart().
    [ NSThread sleepForTimeInterval : 0.1 ];

    atomic_thread_fence(memory_order_acquire);

    if ( mState == INIT ) {

        bool res = [ self createAudioUnitWithSampleRate : sampleRate
                                       NumberOfChennels : numOfChan  ];
        if (!res) {

            return false;
        }
        
        /** Release the lock before calling AudioOutputUnitStart
          * as it seems it does not come back until the first call
          * to the audio callback is returned. This means a deadlock
          * if the callback locks in it.
          * This phenomena started occuring as of iOS 12.0.
          */
        OSStatus status = AudioOutputUnitStart( mAudioUnit );

        if ( status != 0 ) {
            return false;
        }
        mState = DEVICE_OPENED;
        atomic_thread_fence(memory_order_release);

        return true;
    }
    else {
        return false;
    }
}

-(bool) close
{
    atomic_thread_fence(memory_order_acquire);

    if (mState == DEVICE_OPENED) {
        
        OSStatus status = AudioOutputUnitStop( mAudioUnit );
        
        if ( status != 0 ) {
            return false;
        }

        [ self destroyAudioUnit ];
        
        mState = INIT;
        atomic_thread_fence(memory_order_release);

        return true;
    }
    else {
        return false;
    }
    
}


-(void)getCurrentAudioSessionProperties
{
    AVAudioSession *audioSession = [ AVAudioSession sharedInstance ];
    
    if ( audioSession == nil ) {
        return;
    }
    
    mAvailableInputs  = [ audioSession availableInputs              ];

    mCurrentRoute     = [ audioSession currentRoute                 ];

    mNumberOfChannels = (UInt32)
                        [ audioSession inputNumberOfChannels        ];

    mMaximumInputNumberOfChannels
                      = [ audioSession maximumInputNumberOfChannels ];

    mPreferredSampleRateByAudioSession
                      = [ audioSession preferredSampleRate          ];

    mSampleRate       = [ audioSession sampleRate                   ];


    for ( long i = 0; i < [ mAvailableInputs count ]; i++ ) {
        
        AVAudioSessionPortDescription* pd =
                        [ mAvailableInputs objectAtIndex : i ];

        [ self getAudioSessionPortDescription : pd ];
    }


    for ( long i = 0; i < [ mCurrentRoute.inputs count ]; i++ ) {
        
        AVAudioSessionPortDescription* pd =
                        [ mCurrentRoute.inputs objectAtIndex : i ];

        [ self getAudioSessionPortDescription : pd ];
    }


    for(long i = 0; i < [ mCurrentRoute.outputs count ]; i++ ) {
        
        AVAudioSessionPortDescription* pd =
                        [ mCurrentRoute.outputs objectAtIndex : i ];

        [ self getAudioSessionPortDescription : pd ];
    }
}


-(void)getAudioSessionPortDescription:( AVAudioSessionPortDescription* )pd
{

    NSLog( @"portType [%@]", pd.portType );
    NSLog( @"portName [%@]", pd.portName );
    NSLog( @"UID [%@]",      pd.UID      );

    NSArray* na = pd.channels;
    
    for ( long j = 0; j < [na count]; j++ ) {
        
        AVAudioSessionChannelDescription *cd = [na objectAtIndex : j ];
        
        NSLog( @"channelName [%@]",   cd.channelName   );
        NSLog( @"chnnelNumber [%ld]", cd.channelNumber );
        NSLog( @"owningPortUID [%@]", cd.owningPortUID );
        NSLog( @"channelLabel [%d]",  cd.channelLabel  );
    }
    
    na = pd.dataSources;
    for ( long k = 0; k < [na count]; k++ ) {
 
        AVAudioSessionDataSourceDescription *dd = [ na objectAtIndex : k ];
 
        NSLog( @"DataSource[%ld].dataSourceID [%@]",
                                k, dd.dataSourceID.stringValue );

        NSLog( @"DataSource[%ld].dataSourceName [%@]",
                                k, dd.dataSourceName           );

        NSLog( @"DataSource[%ld].location [%@]",
                                k, dd.location                 );

        NSLog( @"DataSource[%ld].orientation[%@]",
                                k, dd.orientation              );

    }

    NSLog( @"preferredDataSource.dataSourceID [%@]",
                    pd.preferredDataSource.dataSourceID.stringValue );

    NSLog( @"preferredDataSource.dataSourceName [%@]",
                    pd.preferredDataSource.dataSourceName           );

    NSLog( @"preferredDataSource.location [%@]",
                    pd.preferredDataSource.location                 );

    NSLog( @"preferredDataSource.orientation [%@]",
                    pd.preferredDataSource.orientation              );

    NSLog( @"selectedDataSource.dataSourceID [%@]",
                    pd.selectedDataSource.dataSourceID.stringValue );

    NSLog( @"selectedDataSource.dataSourceName [%@]",
                    pd.selectedDataSource.dataSourceName           );

    NSLog( @"selectedDataSource.location [%@]",
                    pd.selectedDataSource.location                 );

    NSLog( @"selectedDataSource.orientation [%@]",
                    pd.selectedDataSource.orientation              );

}


-(bool)setPreferredDevice    : (NSString*) devName
               SampleRate    : (long     ) sampleRate
               NumOfChannels : (long     ) numChan
               DataSource    : (NSString*) dataSource
{

    NSError* nserror;
    AVAudioSession *audioSession = [ AVAudioSession sharedInstance ];

    if ( audioSession == nil ) {
        return false;
    }
    
    mAvailableInputs  = [ audioSession availableInputs ];

    if ( mAvailableInputs == nil ) {
        return false;
    }
    
    AVAudioSessionPortDescription* pd = nil;
    
    if ( devName != nil ) {
        
        mPreferredInputByApp = devName;
        for ( long i = 0; i < [ mAvailableInputs count ]; i++ ) {
            
            pd = [ mAvailableInputs objectAtIndex : i ];
            if ( [ pd.portName compare : devName] == NSOrderedSame ) {

                break;
            }
        }

        if ( pd == nil ) {
            return false;
        }
        
        if( [ audioSession setPreferredInput : pd error : &nserror ] != YES ) {
            return false;
        }
        
        // Setting override here as setPreferredInput seems to reset it.
        if ( [audioSession
                 overrideOutputAudioPort : AVAudioSessionPortOverrideSpeaker
                                   error : &nserror                ] != YES ) {
            return false;
        }
    }

    if ( sampleRate != 0 ) {
        
        if ( [audioSession setPreferredSampleRate : (double)sampleRate
                                            error : &nserror        ] != YES ) {
            return false;
        }
    }
    
    if ( numChan != 0 ) {
        if ( [audioSession setPreferredInputNumberOfChannels : (double)numChan
                                                       error : &nserror
                                                                   ] != YES ) {
            return false;
        }
    }
    
    if( dataSource != nil ) {
        
        mCurrentRoute = [ audioSession currentRoute ];
        
        pd = [ mCurrentRoute.inputs objectAtIndex : 0 ];

        NSArray *na = pd.dataSources;
        
        for ( long k = 0; k < [na count]; k++ ) {

            AVAudioSessionDataSourceDescription *dd = [na objectAtIndex:k];
            
            if ( [ dataSource compare : dd.dataSourceName ] == NSOrderedSame ) {
                
                if ( [audioSession setInputDataSource : dd
                                                error : &nserror ] != YES ) {
                    return false;
                }
                break;
            }
        }
    }

    // Check the current values in the audio session.
    mCurrentRoute     = [ audioSession currentRoute ];

    mNumberOfChannels = (UInt32)[ audioSession inputNumberOfChannels ];

    mMaximumInputNumberOfChannels =
                        [ audioSession maximumInputNumberOfChannels ];

    mPreferredSampleRateByAudioSession =
                        [ audioSession preferredSampleRate ];

    mSampleRate       = [ audioSession sampleRate ];
    
    pd = [ mCurrentRoute.inputs objectAtIndex : 0 ];
    
    //pd.portName
    //pd.selectedDataSource.dataSourceID.stringValue
    //pd.selectedDataSource.dataSourceName
    
    return true;
}


-(bool)getCurrentlySetDevice : (NSString **) devName
                  SampleRate : (long*      ) sampleRate
               NumOfChannels : (long*      ) numChan
                  DataSource : (NSString **) dataSource
{
    
    AVAudioSession *audioSession = [ AVAudioSession sharedInstance ];

    if ( audioSession == nil ) {
        return false;
    }
    
    AVAudioSessionPortDescription* pd =nil;
    
    mCurrentRoute     = [ audioSession currentRoute ];
    mNumberOfChannels = (UInt32) [ audioSession inputNumberOfChannels ];
    mSampleRate       = [ audioSession sampleRate ];
    pd                = [ mCurrentRoute.inputs objectAtIndex : 0 ];

    if ( devName != NULL ) {
        *devName = pd.portName;
    }
    
    if ( sampleRate != NULL ) {
        *sampleRate = (long) mSampleRate;
    }
    
    if( numChan != NULL ) {
        *numChan = mNumberOfChannels;
    }
    
    if ( dataSource != NULL ) {
        *dataSource = audioSession.inputDataSource.dataSourceName;
    }
    
    return true;
}


-(NSArray*)getAvailableDataSources
{

    NSMutableArray* sourceArray = [ [ NSMutableArray alloc ] init ];
    

    AVAudioSessionPortDescription* pd =
                                  [ mCurrentRoute.inputs objectAtIndex : 0 ];

    NSArray* na = pd.dataSources;
    
    for ( long k = 0; k < [na count]; k++ ) {
        
        AVAudioSessionDataSourceDescription* dd = [ na objectAtIndex : k ];

        [ sourceArray addObject : dd.dataSourceName ];
    }
    
    return sourceArray;
}


-(bool)createAudioUnitWithSampleRate : (double) sampleRate
                    NumberOfChennels : (UInt32) numOfChan
{
    mSampleRate       = sampleRate;
    mNumberOfChannels = numOfChan;
    
    AudioComponentDescription desc;
    desc.componentType         = kAudioUnitType_Output;
    desc.componentSubType      = kAudioUnitSubType_RemoteIO;
    desc.componentFlags        = 0;
    desc.componentFlagsMask    = 0;
    desc.componentManufacturer = 0; /*kAudioUnitManufacturer_Apple*/
    
    mNumInputComponents = AudioComponentCount( &desc );
    
    if ( mNumInputComponents == 0 ) {
        return false;
    }
    
    mInputComponents = (AudioComponent*)
 
    malloc( sizeof(AudioComponent) * mNumInputComponents );
    
    if ( mInputComponents == NULL ) {
        return false;
    }
    
    for( long i = 0 ; i < mNumInputComponents ; i++ ) {

        mInputComponents[i] = AudioComponentFindNext( NULL, &desc );
    }
    
    OSStatus status = AudioComponentInstanceNew( mInputComponents[0],
                                                 &mAudioUnit          );

    if ( status != 0 ) {
        
        free( mInputComponents );
        return false;
    }
    
    // Enable IO for recording
    UInt32 flag = 1;
    status = AudioUnitSetProperty( mAudioUnit,
                                   kAudioOutputUnitProperty_EnableIO,
                                   kAudioUnitScope_Input,
                                   kInputBus,
                                   &flag,
                                   sizeof(flag)                        );

    
    
    if ( status != 0 ) {
    
        free( mInputComponents );
        return false;
    }
    
    status = AudioUnitSetProperty( mAudioUnit,
                                   kAudioOutputUnitProperty_EnableIO,
                                   kAudioUnitScope_Output,
                                   kOutputBus,
                                   &flag,
                                   sizeof(flag)                        );
    
    if ( status != 0 ) {
        
        free( mInputComponents );
        return false;
    }
    
    
    // Describe format
    AudioStreamBasicDescription recordFormat;
    memset( &recordFormat, 0, sizeof(recordFormat) );
    
    recordFormat.mSampleRate       = sampleRate;
    recordFormat.mChannelsPerFrame = numOfChan;
    recordFormat.mFormatID         = kAudioFormatLinearPCM;
    recordFormat.mFormatFlags      = kLinearPCMFormatFlagIsSignedInteger |
                                     kLinearPCMFormatFlagIsPacked        ;
    recordFormat.mBitsPerChannel   = 16;
    recordFormat.mBytesPerPacket   = (recordFormat.mBitsPerChannel / 8) *
                                     recordFormat.mChannelsPerFrame;
    recordFormat.mBytesPerFrame    = recordFormat.mBytesPerPacket;
    recordFormat.mFramesPerPacket  = 1;
    
    status = AudioUnitSetProperty( mAudioUnit,
                                   kAudioUnitProperty_StreamFormat,
                                   kAudioUnitScope_Output,
                                   kInputBus,
                                   &recordFormat,
                                   sizeof(recordFormat)             );
    
    if ( status != 0 ) {
        
        free( mInputComponents );
        return false;
    }

    // Set input callback
    AURenderCallbackStruct callbackStruct;
    callbackStruct.inputProc       = renderCallbackOnAudioThread;
    callbackStruct.inputProcRefCon = (__bridge void*)self;
    
    status = AudioUnitSetProperty( mAudioUnit,
                                   kAudioOutputUnitProperty_SetInputCallback,
                                   kAudioUnitScope_Global,
                                   kInputBus,
                                   &callbackStruct,
                                   sizeof(callbackStruct)                    );
    if( status != 0 ) {
        
        free( mInputComponents );
        return false;
    }
    
    flag = 0;
    status = AudioUnitSetProperty( mAudioUnit,
                                   kAudioUnitProperty_ShouldAllocateBuffer,
                                   kAudioUnitScope_Output,
                                   kInputBus,
                                   &flag,
                                   sizeof(flag)                              );
    if( status != 0 ) {
        
        free( mInputComponents );
        return false;
    }
    
    status = AudioUnitInitialize( mAudioUnit );
    
    if( status != 0 ) {
        
        free( mInputComponents );
        return false;
    }

    return true;
}


-(void)destroyAudioUnit
{
    OSStatus status = AudioUnitUninitialize( mAudioUnit );
    
    if( status != 0 ) {
        return;
    }
    
    status = AudioComponentInstanceDispose( mAudioUnit );
    
    if( status != 0 ) {
        return;
    }
    
    free(mInputComponents);
}


-(void)setupNotifications
{
    NSNotificationCenter* notificationCenter =
                [ NSNotificationCenter defaultCenter ];
    
    [ notificationCenter
        addObserver : self
        selector    : @selector(audioSessionInterrupted:)
        name        : AVAudioSessionInterruptionNotification
        object      : nil                                            ];
    
    [ notificationCenter
        addObserver : self
        selector    : @selector(audioSessionRouteChanged:)
        name        : AVAudioSessionRouteChangeNotification
        object      : nil                                            ];
    
    [ notificationCenter
        addObserver : self
        selector    : @selector(audioSessionMediaServicesLost:)
        name        : AVAudioSessionMediaServicesWereLostNotification
        object      : nil                                            ];
    
    [ notificationCenter
        addObserver : self
        selector    : @selector(audioSessionMediaServicesReset:)
        name        : AVAudioSessionMediaServicesWereResetNotification
        object      : nil                                            ];
    
    [ notificationCenter
        addObserver : self
        selector    : @selector(receiveResignActive:)
        name        : NSExtensionHostWillResignActiveNotification
        object      : nil                                            ];
    
    [ notificationCenter
        addObserver : self
        selector    : @selector(receiveDidBecomeActive:)
        name        : NSExtensionHostDidBecomeActiveNotification
        object      : nil                                            ];
}


-(void)unregisterNotifications
{
    NSNotificationCenter* notificationCenter
                    = [ NSNotificationCenter defaultCenter ];
    
    [ notificationCenter
        removeObserver : self
        name           : AVAudioSessionInterruptionNotification
        object         : nil                                         ];
    
    [ notificationCenter
        removeObserver : self
        name           : AVAudioSessionRouteChangeNotification
        object         : nil                                         ];
    
    [ notificationCenter
        removeObserver : self
        name           : AVAudioSessionMediaServicesWereLostNotification
        object         : nil                                         ];
    
    [ notificationCenter
        removeObserver : self
        name           : AVAudioSessionMediaServicesWereResetNotification
        object         : nil                                         ];
    
    [ notificationCenter
        removeObserver : self
        name           : NSExtensionHostWillResignActiveNotification
        object         : nil                                         ];
    
    [ notificationCenter
        removeObserver : self
        name           : NSExtensionHostDidBecomeActiveNotification
        object         : nil                                         ];
}


-(void)onArrivalOfInputAudioWithNumberOfFrames: (UInt32 ) inNumberFrames
                                          data: (SInt16*) frameBuf
{
    if ( mDelegate != nil ) {
        
        if( [ mDelegate respondsToSelector :
             @selector( inputDataArrivedWithData:size: ) ] ) {
            
            // Do your light-weight stuff here. Do not block.
            // Do not wait for any condition that depends on anything
            // that can run on the main thread.
            [ mDelegate inputDataArrivedWithData : frameBuf
                                            size : inNumberFrames ];
        }
    }
    else {
        free( frameBuf );
    }
}


- (void)audioSessionInterrupted : (NSNotification *) notification
{
    [ self handleAbort ];
}


- (void)audioSessionRouteChanged : (NSNotification *) notification
{
    [ self handleAbort ];
}


- (void)audioSessionMediaServicesLost : (NSNotification *) notification
{
    [ self handleAbort ];
}


- (void)audioSessionMediaServicesReset : (NSNotification *) notification
{
    [ self handleAbort ];
}


- (void)receiveResignActive : (NSNotification *) notification
{
    [ self handleAbort ];
}


- (void)receiveDidBecomeActive : (NSNotification *) notification
{
    ;
}


-(void) handleAbort
{

    atomic_thread_fence(memory_order_acquire);
    
    if ( mState == DEVICE_OPENED ) {

        AudioOutputUnitStop( mAudioUnit );

        [ self destroyAudioUnit ];

        [ self getCurrentAudioSessionProperties ];

        mState = INIT;
        atomic_thread_fence(memory_order_release);

        if ( mDelegate != nil ) {
            
            if( [ mDelegate respondsToSelector :
                  @selector( audioInputClosed )  ] ) {

                [ mDelegate audioInputClosed ];
            }
        }
        
    }
}


static OSStatus renderCallbackOnAudioThread(

    void*                       inRefCon,
    AudioUnitRenderActionFlags* ioActionFlags,
    const AudioTimeStamp*       inTimeStamp,
    UInt32                      inBusNumber,
    UInt32                      inNumberFrames,
    AudioBufferList*            ioData

) {
 
    AudioInputManager* SELF = (__bridge AudioInputManager*)inRefCon;

    atomic_thread_fence(memory_order_acquire);

    if ( SELF.mState == DEVICE_OPENED ) {

        AudioBufferList bufferList;
        SInt16* frameBuf = (SInt16*) malloc ( sizeof(SInt16) * inNumberFrames );
    
        if ( frameBuf == NULL ) {
        
            return kAudio_MemFullError;
        }

        bufferList.mNumberBuffers              = 1;
        bufferList.mBuffers[0].mNumberChannels =
                                        (UInt32)[SELF mNumberOfChannels];
        bufferList.mBuffers[0].mDataByteSize   = inNumberFrames * sizeof(SInt16);
        bufferList.mBuffers[0].mData           = frameBuf;

        // Num of Bytes is usually 2048.
        OSStatus status = AudioUnitRender( [ SELF mAudioUnit ],
                                           ioActionFlags,
                                           inTimeStamp,
                                           1,
                                           inNumberFrames,
                                           &bufferList          );
        if ( status != 0 ) {
            
            free( frameBuf );
            return status;
        }

        dispatch_async ( dispatch_get_main_queue(), ^{

            [ SELF onArrivalOfInputAudioWithNumberOfFrames : inNumberFrames
                                                      data : frameBuf       ];
        } );
    }

    return 0;
}


-(void) calsRMS : (float*)  rms
      andAbsMax : (float*)  max
       fromData : (SInt16*) data
        andSize : (UInt32)  size
{

    // This demonstrates the use of vDSP to calculate RMS.
    // The performance gain, if any, will be limited due to
    // the conversion from Int16 to Float.

    if ( size > 0 ) {

        for ( int i = 0; i < size; i++ ) {

            mFloatBuffer[i] = (float)( data[i] );
        }

        // Calculate RMS
        vDSP_rmsqv ( mFloatBuffer, 1, rms, size );

        // Calculate Abs Max
        vDSP_maxmgv( mFloatBuffer, 1, max, size );

    }
}


@end


