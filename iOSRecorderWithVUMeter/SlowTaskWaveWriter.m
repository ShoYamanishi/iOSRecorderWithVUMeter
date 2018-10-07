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
#import "SlowTaskWaveWriter.h"

#include <stdlib.h>
#include <unistd.h>
#include <time.h>
#include <fcntl.h>
#include <string.h>
#include <sys/stat.h>

static const int readBufferSize = 4096;


@implementation SlowTaskWaveWriter {
    int       mFd;
}


@synthesize mBaseFileName;
@synthesize mSampleRate;
@synthesize mNumberOfChannels;


-(id) init
{
    self =  [ super init ];

    if (self) {
        mFd = -1;
    }

    return self;
}


-(NSString*) makePermissibleFilePathFromBaseFileName : (NSString*) fileName
                                        andExtension : (NSString*) ext
{

    NSArray* paths = NSSearchPathForDirectoriesInDomains( NSDocumentDirectory,
                                                          NSUserDomainMask,
                                                          YES                 );
    NSString* docsDir  = [ paths objectAtIndex : 0 ];

    return [ docsDir stringByAppendingPathComponent :
                     [ NSString stringWithFormat : @"%@.%@", fileName, ext ] ];
}


-(bool) taskStart
{
    NSString* PCMFileName =
         [ self makePermissibleFilePathFromBaseFileName : mBaseFileName
                                           andExtension : @"pcm"        ];

    unlink( PCMFileName.UTF8String );

    mFd = open( PCMFileName.UTF8String,
                O_CREAT | O_WRONLY | O_TRUNC, S_IRWXU | S_IRWXG | S_IRWXO
              );

    if ( mFd == -1 ) {
        return false;
    }
    return true;
}


-(void) taskStop
{
    if ( mFd != -1 ) {

        close(mFd);

        [ self convertFromPCMToWave ];
    }
}


-(void) taskAbort
{
    if ( mFd != -1 ) {
    
        close(mFd);

        NSString* PCMFileName =
            [ self makePermissibleFilePathFromBaseFileName : mBaseFileName
                                              andExtension : @"pcm"         ];
        unlink( PCMFileName.UTF8String );
    }
}


-(bool) taskFeed : (void*) data length : (int) len
{
    if( write( mFd, data, len*sizeof(short) ) == -1 ) {

        free( data );
        return false;
    }
    
    free( data );

    return true;
}


-(void) taskIgnore : (void*) data length : (int) len
{
    free(data);
}


struct RIFF {
    unsigned char   magic     [ 4 ];
    uint32_t        chunkSize;
    unsigned char   wave      [ 4 ];
    unsigned char   fmtMarker [ 4 ];
    uint32_t        subChunkSize;
    uint16_t        fmtCode;
    uint16_t        numChannels;
    uint32_t        sampleRate;
    uint32_t        SBC;  // (Sample Rate * BitsPerSample * Channels) / 8
    uint16_t        BPSC; // (BitsPerSample * Channels) / 8
    uint16_t        BitsPerSample;
    unsigned char   dataMarker [ 4 ];
    uint32_t        dataSize;
};


-(void) populateRiff:(struct RIFF*) riff fileSize:(uint32_t) fileSizeBytes
{
    riff->magic[0]      = 'R';
    riff->magic[1]      = 'I';
    riff->magic[2]      = 'F';
    riff->magic[3]      = 'F';
    riff->chunkSize     =  fileSizeBytes + 36;
    riff->wave[0]       = 'W';
    riff->wave[1]       = 'A';
    riff->wave[2]       = 'V';
    riff->wave[3]       = 'E';
    riff->fmtMarker[0]  = 'f';
    riff->fmtMarker[1]  = 'm';
    riff->fmtMarker[2]  = 't';
    riff->fmtMarker[3]  = ' ';
    riff->subChunkSize  = 16;
    riff->fmtCode       = 0x0001; // PCM
    riff->numChannels   = mNumberOfChannels;
    riff->sampleRate    = mSampleRate;
    // SampleRate * BitsPerSample *Channels)/8
    riff->SBC           = mSampleRate * 2 * mNumberOfChannels;
    riff->BPSC          = 2 * mNumberOfChannels; //BitPerSample * Channels/8
    riff->BitsPerSample = 16;
    riff->dataMarker[0] = 'd';
    riff->dataMarker[1] = 'a';
    riff->dataMarker[2] = 't';
    riff->dataMarker[3] = 'a';
    riff->dataSize      = fileSizeBytes;
}


-(bool) convertFromPCMToWave
{
    int          fdi;
    int          fdo;
    struct RIFF  riff;
    struct stat  statBuf;
    char         readBuf [ readBufferSize ];
    long         readLen;

    NSString* PCMFileName =
        [ self makePermissibleFilePathFromBaseFileName : mBaseFileName
                                          andExtension : @"pcm"         ];
    NSString* WAVFileName =
        [ self makePermissibleFilePathFromBaseFileName : mBaseFileName
                                          andExtension : @"wav"         ];

    fdi = open( PCMFileName.UTF8String, O_RDONLY );

    if ( fdi == -1 ) {
        return false;
    }
    
    fdo = open( WAVFileName.UTF8String,
                O_CREAT | O_WRONLY | O_TRUNC, S_IRWXU | S_IRWXG | S_IRWXO );

    if ( fdo == -1 ) {
        return false;
    }

    if( fstat( fdi, &statBuf ) != 0 ) {
        close(fdo);
        close(fdi);
        return false;
    }

    [ self populateRiff : &riff fileSize: (int)statBuf.st_size ];

    if ( ![self writeCompleteFd : fdo
                           data : (char*) &riff
                         length : sizeof(riff)  ] ) {
        close(fdo);
        close(fdi);
        return false;
    }
    
    bool eofDetected = false;
    while ( !eofDetected ) {
    
        readLen = read( fdi, readBuf, readBufferSize );
        if ( readLen == -1 ) {
            close(fdo);
            close(fdi);
            return false;
        }
        else if( readLen == 0 ) {
            eofDetected = true;
        }
        else {
            if( ![self writeCompleteFd : fdo
                                  data : readBuf
                                length : (int) readLen ] ) {
                close(fdo);
                close(fdi);
                return false;
            }
        }
    }
 
    close(fdo);
    close(fdi);

    unlink( PCMFileName.UTF8String );

    return true;
}


-(bool) writeCompleteFd : (int) fd data : (char*) data length : (int) len
{
    long bytesWritten = 0;
    long rtnVal;

    for ( bytesWritten = 0 ; bytesWritten < len ; ) {
        rtnVal = write ( fd, &(data[bytesWritten]), len - bytesWritten );
        if ( rtnVal == -1 ) {
            return false;
        }
        bytesWritten = bytesWritten + rtnVal;
    }
    return true;
}

@end

