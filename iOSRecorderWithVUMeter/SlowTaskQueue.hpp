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


#ifndef _SLOW_TASK_QUEUE_HPP_
#define _SLOW_TASK_QUEUE_HPP_

#include<pthread.h>

using  STCallback =  void(*) ( int cmd, void* data, void* user );

class SlowTaskQueue {

private:

    volatile int       mState;
    int*               mCmd;
    void**             mData;
    int                mNextGet;
    int                mNextPut;
    bool               mHasOOB;
    int                mCmdOOB;
    void *             mDataOOB;
    bool               mFlushing;
    pthread_mutex_t    mLock;
    pthread_cond_t     mRcvCond;
    pthread_cond_t     mSndCond;
    int                mPutOnHold;
    int                mGetOnHold;
    int                mNumElems;
    int                mLimit;
    int                mHighWater;
    int                mLowWater;
    STCallback         mCallbackMain;
    STCallback         mCallbackFlush;
    void*              mUserData;
    pthread_t          mThread;

    static const int STATE_ERR         = -1;
    static const int STATE_CLOSED      =  0;
    static const int STATE_OPENED      =  1;
    static const int STATE_FLUSHING    =  2;
    static const int STATE_TERMINATING =  3;
    static const int STATE_TERMINATED  =  4;

    static const int DEFAULT_LIMIT     =  128;
public:

    static const int HIGHWATER  =  1;
    static const int OK         =  0;
    static const int ERR_STATE  = -1;
    static const int ERR_PARAM  = -2;
    static const int ERR_MEMORY = -3;
    static const int ERR_SYNC   = -4;
    static const int ERR_FULL   = -5;
    static const int ERR_EMPTY  = -6;

    SlowTaskQueue(
        int        limit,
        int        high,
        int        low,
        STCallback cbMain,
        STCallback cbFlush,
        void*      userData
    );
    
    ~SlowTaskQueue();
    
    int open();
    
    int close();
    
    int flush();
    
    int putOOB     ( int  cmd, void*  data );
    
    int put        ( int  cmd, void*  data );
    
    int tryPutting ( int  cmd, void*  data );
    
    int peek       ( int* cmd, void** data, bool* hasOOB, int* cmdOOB, void** dataOOB );

    friend void* SQTThreadFunc ( void* p );

};

#endif /*_SLOW_TASK_QUEUE_HPP_*/
