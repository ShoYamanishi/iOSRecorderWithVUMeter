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

#include <stdlib.h>
#include "SlowTaskQueue.hpp"

void* SQTThreadFunc ( void* p );


SlowTaskQueue::SlowTaskQueue(
        int        limit,
        int        high,
        int        low,
        STCallback cbMain,
        STCallback cbFlush,
        void*      userData
) {

    mState = STATE_ERR;
    
    // Sanity check.
    if ( limit <= 0 ) {
        limit = DEFAULT_LIMIT;
    }
    
    if ( high <= 0 || high > limit ) {
        high = limit;
    }
    
    if ( low < 0 || low >= limit ) {
        low = 0;
    }

    mHasOOB        = false;
    mCmdOOB        = 0;
    mDataOOB       = NULL;
    mLimit         = limit;
    mHighWater     = high;
    mLowWater      = low;
    mNumElems      = 0;
    mNextGet       = 0;
    mNextPut       = 0;
    mPutOnHold     = 0;
    mGetOnHold     = 0;
    mCallbackMain  = cbMain;
    mCallbackFlush = cbFlush;
    mUserData      = userData;
    mFlushing      = false;
    mCmd           = NULL;
    mData          = NULL;

    mCmd = (int*) malloc ( sizeof(int) * limit );
    if ( mCmd == NULL ) {
        return;
    }

    mData = (void**) malloc (sizeof(void*) * limit );
    if ( mData == NULL ) {
        return;
    }
    
    if ( pthread_mutex_init( &mLock, NULL ) !=0 ) {
        return;
    }
    if( pthread_cond_init( &mRcvCond, NULL ) != 0 ) {
        return;
    }
    if( pthread_cond_init( &mSndCond, NULL ) != 0 ) {
        return;
    }
    if( pthread_create( &mThread, NULL, SQTThreadFunc, this ) != 0 ) {
        return;
    }

    mState = STATE_CLOSED;
}


SlowTaskQueue::~SlowTaskQueue()
{

    pthread_mutex_lock ( &mLock );

    mState = STATE_TERMINATING;

    pthread_cond_signal ( &mRcvCond );

    pthread_mutex_unlock ( &mLock );

    pthread_join ( mThread, NULL );

    if ( mCmd != NULL ) {
        free( mCmd );
    }
    
    if ( mData != NULL ) {
        free( mData );
    }
    
    pthread_cond_destroy ( &mSndCond );

    pthread_cond_destroy ( &mRcvCond );

    pthread_mutex_destroy ( &mLock );
}


int SlowTaskQueue::open()
{

    pthread_mutex_lock( &mLock );
    
    if ( mState != STATE_CLOSED ) {

        pthread_mutex_unlock ( &mLock );
        return ERR_STATE;
    }
    
    mState = STATE_OPENED;
    
    pthread_mutex_unlock ( &mLock );

    return OK;
}


int SlowTaskQueue::close()
{
    pthread_mutex_lock( &mLock );
    
    if ( mState != STATE_OPENED ) {
    
        pthread_mutex_unlock( &mLock );
        return ERR_STATE;
    }
    
    mState = STATE_CLOSED;
    
    pthread_mutex_unlock( &mLock );

    return OK;
}


int SlowTaskQueue::put ( int cmd, void* data )
{
    pthread_mutex_lock( &mLock );
    
    if ( mState != STATE_OPENED ) {
    
        pthread_mutex_unlock( &mLock );
        return ERR_STATE;
    }
    
    while( mNumElems >= mHighWater && mState == STATE_OPENED ) {
        
        mPutOnHold++;
        pthread_cond_wait ( &mSndCond, &mLock );
        mPutOnHold--;
    }

    if(mState != STATE_OPENED ) {
    
        pthread_mutex_unlock( &mLock );
        return ERR_STATE;
    }
    
    mCmd  [ mNextPut ] = cmd;
    mData [ mNextPut ] = data;

    mNextPut++;
    if ( mNextPut >= mLimit ) {
        mNextPut = 0;
    }

    mNumElems++;

    if ( mGetOnHold > 0 && mNumElems >= mLowWater ) {

        pthread_cond_signal( &mRcvCond );
    }
    
    pthread_mutex_unlock( &mLock );

    return OK;
}


int SlowTaskQueue::tryPutting( int cmd, void* data )
{

    pthread_mutex_lock( &mLock );

    if ( mState != STATE_OPENED ) {
    
        pthread_mutex_unlock( &mLock );
        return ERR_STATE;
    }
    
    if ( mNumElems >= mLimit ) {

        pthread_mutex_unlock( &mLock );
        return ERR_FULL;
    }
    
    mCmd  [ mNextPut ] = cmd;
    mData [ mNextPut ] = data;
    
    mNextPut++;
    if ( mNextPut >= mLimit ) {
        mNextPut = 0;
    }
    
    mNumElems++;

    if ( mGetOnHold > 0 && mNumElems >= mLowWater ) {

        pthread_cond_signal( &mRcvCond );
    }

    if ( mNumElems >= mHighWater ) {
    
        pthread_mutex_unlock( &mLock );
        
        return HIGHWATER;
    }
    
    pthread_mutex_unlock( &mLock );

    return OK;
}


int SlowTaskQueue::peek(
    int*    cmd,
    void**  data,
    bool*   hasOOB,
    int*    cmdOOB,
    void**  dataOOB
) {
    pthread_mutex_lock( &mLock );

    if ( mState != STATE_OPENED && mState != STATE_CLOSED ) {

        pthread_mutex_unlock( &mLock );
        return ERR_STATE;
    }
    
    if ( cmd != NULL ) {

        *cmd = mCmd [ mNextGet ];
    }

    if ( data != NULL ) {
        *data = mData [ mNextGet ];
    }
    
    if ( hasOOB != NULL ) {
        *hasOOB = mHasOOB;
    }
    
    if ( cmdOOB != NULL ) {
        *cmdOOB = mCmdOOB;
    }
    
    if ( dataOOB != NULL ) {
        *dataOOB = mDataOOB;
    }
    
    pthread_mutex_unlock( &mLock );

    return mNumElems;
}


int SlowTaskQueue::flush()
{
    pthread_mutex_lock( &mLock );
    
    if(mState != STATE_OPENED && mState != STATE_CLOSED ){

        pthread_mutex_unlock( &mLock );
        return ERR_STATE;
    }

    mFlushing = true;
    
    if ( mGetOnHold > 0 ) {
        pthread_cond_signal( &mRcvCond );
    }
    
    pthread_mutex_unlock( &mLock );

    return OK;
}


void* SQTThreadFunc ( void* p )
{
    SlowTaskQueue *THIS = (SlowTaskQueue*) p;
    
    pthread_mutex_lock( &(THIS->mLock) );
    
    while ( THIS->mState != SlowTaskQueue::STATE_TERMINATING ) {
    
        while ( THIS->mState != SlowTaskQueue::STATE_TERMINATING
                && THIS->mNumElems <= 0
                && !THIS->mHasOOB
                && !THIS->mFlushing                              ) {
            
            (THIS->mGetOnHold)++;

            pthread_cond_wait( &(THIS->mRcvCond), &(THIS->mLock) );
            (THIS->mGetOnHold)--;
        }
        
        if ( THIS->mFlushing ) {
        
            THIS->mFlushing = false;
            
            while ( (THIS->mNumElems) > 0 ) {
            
                if ( THIS->mCallbackFlush != NULL ) {

                    THIS->mCallbackFlush ( THIS->mCmd [ THIS->mNextGet ],
                                           THIS->mData[ THIS->mNextGet ],
                                           THIS->mUserData                );
                }
                (THIS->mNextGet)++;
                
                if ( THIS->mNextGet >= THIS->mLimit ) {
                
                    THIS->mNextGet = 0;
                }
                (THIS->mNumElems)--;

                if ( THIS->mPutOnHold > 0 ) {

                    pthread_cond_signal( &(THIS->mSndCond) );
                }
            }
        }
        else if ( THIS->mHasOOB ) {
        
            THIS->mHasOOB = false;
            pthread_mutex_unlock( &(THIS->mLock) );
            if ( THIS->mCallbackMain != NULL ) {
            
                 THIS->mCallbackMain ( THIS->mCmdOOB,
                                       THIS->mDataOOB,
                                       THIS->mUserData );

            }

            pthread_mutex_lock( &(THIS->mLock) );

            if( (THIS->mPutOnHold) > 0
                && (THIS->mNumElems) <= (THIS->mHighWater) ) {

                pthread_cond_signal( &(THIS->mSndCond) );
            }
        }
        else if ( THIS->mNumElems > 0 ) {

            int idx = THIS->mNextGet;
            (THIS->mNextGet)++;

            if (THIS->mNextGet>=THIS->mLimit ) {

                THIS->mNextGet = 0;
            }

            (THIS->mNumElems)--;

            pthread_mutex_unlock( &(THIS->mLock) );
            
            if ( THIS->mCallbackMain != NULL ) {
                THIS->mCallbackMain ( THIS->mCmd  [ idx ],
                                      THIS->mData [ idx ],
                                      THIS->mUserData     );
            }
            
            pthread_mutex_lock( &(THIS->mLock) );
            
            if( (THIS->mPutOnHold) > 0
                && (THIS->mNumElems) <= (THIS->mHighWater) ) {

                pthread_cond_signal( &(THIS->mSndCond) );
            }
        }
    }
    
    pthread_mutex_unlock( &(THIS->mLock) );
    pthread_exit(0);

    return (void*) 0;
}


