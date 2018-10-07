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
#import "SlowTaskManagerPosix.h"
#import "SlowTaskQueue.hpp"


class QueueElemPosix {
  public:
  
    QueueElemPosix( void* data, int len )
        :mData(data),
         mLen(len)
         {;}
    
    ~QueueElemPosix(){;}

    void*         mData;
    int           mLen;
};


@implementation SlowTaskManagerPosix {

    volatile enum _stateSTM mState;
    pthread_mutex_t         mLock;
    SlowTaskQueue*          mQueue;

}

@synthesize mDelegate;

enum _command {

    COMMAND_START,
    COMMAND_STOP,
    COMMAND_DATA

};


static void callbackMain( int cmd, void* data, void* user )
{
    SlowTaskManagerPosix* SELF = (__bridge SlowTaskManagerPosix*) user;
    
    [ SELF onArrivalOfDataInBackgroundThreadonCommand : (enum _command) cmd
                                              andData : (QueueElemPosix*)data
                                              flushing: NO                     ];
}


static void callbackFlushing( int cmd, void* data, void* user )
{
    SlowTaskManagerPosix* SELF = (__bridge SlowTaskManagerPosix*) user;
    
   [ SELF onArrivalOfDataInBackgroundThreadonCommand : (enum _command) cmd
                                             andData : (QueueElemPosix*)data
                                            flushing : YES                     ];
}




-(id)init
{
    self = [ super init ];

    if ( self != nil ) {

        mState     = IDLE;
        
        pthread_mutex_init( &mLock, NULL );
        
        mQueue     = new SlowTaskQueue( 100,
                                         90,
                                         10,
                                         callbackMain,
                                         callbackFlushing,
                                         (__bridge void*)self );
        mQueue->open();
    }
    return self;
}


-(bool) start
{

    pthread_mutex_lock ( &mLock );

    if ( mState == IDLE ) {

        mState = RUNNING;

        QueueElemPosix* elem = new QueueElemPosix( nullptr, 0 );

        mQueue->put( COMMAND_START, elem );

        pthread_mutex_unlock ( &mLock );

        return true;

    }
    else {
        pthread_mutex_unlock ( &mLock );
        return false;
    }
}


-(bool) stop
{
    pthread_mutex_lock ( &mLock );

    if ( mState == RUNNING ) {

        QueueElemPosix* elem = new QueueElemPosix( nullptr, 0 );
        
        mQueue->put( COMMAND_STOP, elem );

        pthread_mutex_unlock ( &mLock );
        return true;
    }
    else {
        pthread_mutex_unlock ( &mLock );
        return false;
    }
}

-(bool) abort
{
    pthread_mutex_lock ( &mLock );

    if ( mState == RUNNING ) {

        mState = STOPPING;

        QueueElemPosix* elem = new QueueElemPosix( nullptr, 0 );
        
        mQueue->flush();
        mQueue->put( COMMAND_STOP, elem );

        pthread_mutex_unlock ( &mLock );
        return true;
    }
    else {

        pthread_mutex_unlock ( &mLock );
        return false;
    }
}

-(bool) feed : (void*) data length : (int) len
{
    pthread_mutex_lock ( &mLock );

    if ( mState == RUNNING ) {

        QueueElemPosix* elem = new QueueElemPosix( data, len );

        mQueue->put( COMMAND_DATA, elem );

        pthread_mutex_unlock ( &mLock );
        return true;
    }
    else {

        free(data);
        pthread_mutex_unlock ( &mLock );
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

-(void) onArrivalOfDataInBackgroundThreadonCommand : (enum _command)   com
                                           andData : (QueueElemPosix*) elem
                                          flushing : (BOOL)            flushing
{
    pthread_mutex_lock ( &mLock );
    
    if ( flushing ) {

        [ self taskIgnore: elem->mData length: elem->mLen ];

    }
    else if ( mState == RUNNING ) {

        switch ( com ) {
          
          case COMMAND_START:
            {
                pthread_mutex_unlock ( &mLock );

                // Start a session here and store the result to res;
                bool resStart = [ self taskStart ];

                if ( !resStart ) {

                    // Start command failed.
                    pthread_mutex_lock ( &mLock );

                    if ( mState == RUNNING ) {

                        mState = IDLE;
                        [self dispatchStoppingOnMainQueue ];
                        [self dispatchReadyOnMainQueue ];
                        pthread_mutex_unlock ( &mLock );

                    }
                    else if ( mState == STOPPING ) {

                        mState = IDLE;
                        [self dispatchReadyOnMainQueue ];
                        pthread_mutex_unlock ( &mLock );

                    }
                    else {

                        pthread_mutex_unlock ( &mLock );
                    }
                }
            }
            break;

          case COMMAND_DATA:
            {
                pthread_mutex_unlock ( &mLock );

                // Process data here.
                bool resData = [ self taskFeed : elem->mData length : elem->mLen ];
            
                if ( !resData ) {

                    pthread_mutex_lock ( &mLock );

                    if ( mState == RUNNING ) {

                        [self dispatchStoppingOnMainQueue ];
                        [self dispatchReadyOnMainQueue ];
                        mState = IDLE;
                        pthread_mutex_unlock ( &mLock );
                    }
                    else if ( mState == STOPPING ) {

                        [self dispatchReadyOnMainQueue ];
                        mState = IDLE;
                        pthread_mutex_unlock ( &mLock );
                    }
                    else {

                        pthread_mutex_unlock ( &mLock );
                    }
                }
            }
            break;

          case COMMAND_STOP:
            {
                mState = STOPPING;

                pthread_mutex_unlock ( &mLock );
            
                // Stop the current session here.
                [ self taskStop ];
            
                pthread_mutex_lock ( &mLock );
                [self dispatchReadyOnMainQueue ];
                mState = IDLE;
                pthread_mutex_unlock ( &mLock );
            }
            break;
        }
    }
    else if ( mState == STOPPING) {
   
        switch ( com ) {
          
          case COMMAND_DATA:
            {
                pthread_mutex_unlock ( &mLock );

                // Discarding data here.
                [ self taskIgnore : elem->mData length : elem->mLen ];
                pthread_mutex_lock ( &mLock );
            }
            break;

          default:
            break;

        }
    
        pthread_mutex_unlock ( &mLock );
        
        // Abort the current session here.
        [ self taskAbort ];
        
        pthread_mutex_lock ( &mLock );
        [self dispatchReadyOnMainQueue ];
        mState = IDLE;
        pthread_mutex_unlock ( &mLock );
    }
    else {
        switch ( com ) {

          case COMMAND_DATA:

            pthread_mutex_unlock ( &mLock );
            // Discarding data here.
            [ self taskIgnore : elem->mData length : elem->mLen ];
            pthread_mutex_lock ( &mLock );
            break;

          default:
            break;

        }
        pthread_mutex_unlock ( &mLock );
    }
    
    if ( elem != nullptr) {
        delete elem;
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

