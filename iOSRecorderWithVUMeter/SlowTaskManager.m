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
#import "SlowTaskManager.h"

@implementation SlowTaskManager {

    volatile enum _stateSTM mState;
    NSLock*                 mStateLock;
    dispatch_queue_t        mQueue;

}

@synthesize mDelegate;

enum _command {

    COMMAND_START,
    COMMAND_STOP,
    COMMAND_DATA

};


typedef struct _queueElem {
    enum _command mCommand;
    void*         mData;
    int           mLen;
} QueueElem;


-(id)init
{
    self = [ super init ];

    if ( self != nil ) {
        mState     = IDLE;
        mStateLock = [NSLock new];
    }
    return self;
}


-(bool) start
{
    [ mStateLock lock ];

    if ( mState == IDLE ) {

        // The previous dispatch queue will be destroyed
        // after losing the reference count.

        mQueue = dispatch_queue_create( NULL , NULL );
        mState = RUNNING;

        QueueElem elem;
        elem.mCommand = COMMAND_START;
        elem.mData    = nil;
        elem.mLen     = 0;

        dispatch_async ( mQueue, ^{
            [ self onArrivalOfDataInBackgroundThread : elem ];
        } );

        [ mStateLock unlock ];
        return true;

    }
    else {
        [ mStateLock unlock ];
        return false;
    }
}


-(bool) stop
{
    [ mStateLock lock ];

    if ( mState == RUNNING ) {

        QueueElem elem;
        elem.mCommand = COMMAND_STOP;
        elem.mData    = nil;
        elem.mLen     = 0;
        dispatch_async ( mQueue, ^{
            [ self onArrivalOfDataInBackgroundThread : elem ];
        } );

        [ mStateLock unlock ];
        return true;
    }
    else {
        [ mStateLock unlock ];
        return false;
    }
}

-(bool) abort
{
    [ mStateLock lock ];

    if ( mState == RUNNING ) {

        mState = STOPPING;

        [ mStateLock unlock ];
        return true;
    }
    else {

        [ mStateLock unlock ];
        return false;
    }
}

-(bool) feed : (void*) data length : (int) len
{
    [ mStateLock lock ];

    if ( mState == RUNNING ) {

        QueueElem elem;
        elem.mCommand = COMMAND_DATA;
        elem.mData    = data;
        elem.mLen     = len;

        dispatch_async ( mQueue, ^{
            [ self onArrivalOfDataInBackgroundThread : elem];
        } );
        [ mStateLock unlock ];
        return true;
    }
    else {

        free(data);
        [ mStateLock unlock ];
        return false;

    }
}


-(void) dispatchStoppingOnMainQueue
{
    dispatch_async ( dispatch_get_main_queue(), ^{

        if ( self.mDelegate != nil) {

            if ( [ self.mDelegate respondsToSelector :
                             @selector( slowTaskManagerStopping ) ] ) {

                [ self.mDelegate slowTaskManagerStopping ];
            }
        }

    } );
}


-(void) dispatchReadyOnMainQueue
{
    dispatch_async ( dispatch_get_main_queue(), ^{

        if ( self.mDelegate != nil) {

            if( [ self.mDelegate respondsToSelector :
                                  @selector( slowTaskManagerReady ) ] ) {

                [ self.mDelegate slowTaskManagerReady ];
            }
        }
    } );
}


-(void) onArrivalOfDataInBackgroundThread: (QueueElem) elem
{
    [ mStateLock lock ];

    if ( mState == RUNNING ) {

        switch (elem.mCommand) {
          
          case COMMAND_START:

            [ mStateLock unlock ];

            // Start a session here and store the result to res;
            bool resStart = [ self taskStart ];

            if (!resStart) {

                // Start command failed.
                [ mStateLock lock];

                if ( mState == RUNNING ) {

                    mState = IDLE;
                    [self dispatchStoppingOnMainQueue ];
                    [self dispatchReadyOnMainQueue ];
                    [ mStateLock unlock ];

                }
                else if ( mState == STOPPING ) {

                    mState = IDLE;
                    [self dispatchReadyOnMainQueue ];
                    [ mStateLock unlock ];

                }
                else {

                    [ mStateLock unlock ];
                }
            }
            break;

          case COMMAND_DATA:

            [ mStateLock unlock ];

            // Process data here.
            bool resData = [ self taskFeed : elem.mData length : elem.mLen ];
            
            if (!resData) {

                [ mStateLock lock];

                if ( mState == RUNNING ) {

                    [self dispatchStoppingOnMainQueue ];
                    [self dispatchReadyOnMainQueue ];
                    mState = IDLE;
                    [ mStateLock unlock ];
                }
                else if ( mState == STOPPING ) {

                    [self dispatchReadyOnMainQueue ];
                    mState = IDLE;
                    [ mStateLock unlock ];
                }
                else {

                    [ mStateLock unlock ];
                }
            }
            break;

          case COMMAND_STOP:

            mState = STOPPING;

            [ mStateLock unlock ];
            
            // Stop the current session here.
            [ self taskStop ];
            
            [ mStateLock lock ];
            [self dispatchReadyOnMainQueue ];
            mState = IDLE;
            [ mStateLock unlock ];

            break;

        }
    }
    else if ( mState == STOPPING) {
   
        switch (elem.mCommand) {
          
          case COMMAND_DATA:

            [ mStateLock unlock ];

            // Discarding data here.
            [ self taskIgnore : elem.mData length : elem.mLen];
            [ mStateLock lock ];
            break;

          default:
            break;

        }
    
        [ mStateLock unlock ];
        
        // Abort the current session here.
        [ self taskAbort ];
        
        [ mStateLock lock ];
        [self dispatchReadyOnMainQueue ];
        mState = IDLE;
        [ mStateLock unlock ];
    }
    else {
        switch (elem.mCommand) {

          case COMMAND_DATA:

            [ mStateLock unlock ];
            // Discarding data here.
            [ self taskIgnore : elem.mData length : elem.mLen ];
            [ mStateLock lock ];
            break;

          default:
            break;

        }
        [ mStateLock unlock ];
    }
}


// Those will run in the background and are expected to be
// overridden by the subclasses.
-(bool) taskStart              { return true; }
-(void) taskStop               {;}
-(void) taskAbort              {;}
-(bool) taskFeed:  (void*) data length : (int) len { return true; }
-(void) taskIgnore:(void*) data length : (int) len {;}

@end

