/* MIT License
 *
 * Copyright (c) [2018] [Shoichiro Yamanishi]
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

#include "estimateSNR.h"

#define SNR_HIGH_DB            96.875
#define SNR_LOW_DB             -28.125
#define SNR_NUM_BINS           500
#define SNR_BLOCKSIZE          2048
#define SNR_NEGATIVE_INFINITY  -20.0
#define SNR_SMOOTH_BINS        7
#define SNR_PI                 3.14159265358979323846
#define SNR_CDB_BUF_SIZE_BYTES 4096
#define SNR_PEAK_LEVEL         0.95

/** @brief element of the bucket for the histogram */
typedef struct hist{

    int   count;
    float from;
    float to;

} SNR_HIST;

/** @brief header of the wave file */
struct RIFF {

    unsigned char magic [ 4 ];
    uint32_t      chunkSize;
    unsigned char wave [ 4 ];
    unsigned char fmtMarker [ 4 ];
    uint32_t      subChunkSize;
    uint16_t      fmtCode;
    uint16_t      numChannels;
    uint32_t      sampleRate;
    uint32_t      SBC;  // (Sample Rate * BitsPerSample * Channels) / 8
    uint16_t      BPSC; // (BitsPerSample * Channels) / 8
    uint16_t      BitsPerSample;
    unsigned char dataMarker [ 4 ];
    uint32_t      dataSize;

};


/******************************/
/* static function definition */
/******************************/


static SNR_HIST** alloc_hist ( int num_bins, int num_elems );

static SNR_HIST** init_hist ( int num_bins, float from, float to );

static float      compute_dc_bias ( const char *filename );

static float      pwr1 ( short *win, int len, float dc_bias );

static int        compute_pwr_hist_sd (
                      const char* filename,
                      SNR_HIST**  pwr_hist,
                      int         num_bins,
                      int         frame_width,
                      int         frame_adv,
                      float       dc_bias        );

static void       build_raised_cos_hist (
                      SNR_HIST**   ref_hist,
                      SNR_HIST**   ret_hist,
                      int          num_bins,
                      float*       noise_peak    );

static void       smooth_hist (
                      SNR_HIST**   from,
                      SNR_HIST**   to,
                      int          num_bins,
                      int          window        );

static int        hist_slope (
                      SNR_HIST**   hist,
                      int          num_bins,
                      int          center,
                      int          factor        );

static void       hist_copy (
                      SNR_HIST**   from,
                      SNR_HIST**   to,
                      int          num_bins,
                      int          start,
                      int          end           );

static void       do_init_comp1 ( SNR_HIST **ref, SNR_HIST **hyp, int num_bins);

static float      comp1 ( int *vector );

static float      do_least_squares (
                      SNR_HIST**   noise,
                      SNR_HIST**   normal,
                      int          num_bins      );

static void       special_cosine_hist (
                      SNR_HIST** hist,
                      int        num_bins,
                      int        middle,
                      int        height,
                      int        width           );

static void       free_hist ( SNR_HIST **hist, int num_bins );

static void       erase_hist ( SNR_HIST **hist, int num_bins );

static void       subtract_hist (
                      SNR_HIST** h1,
                      SNR_HIST** h2,
                      SNR_HIST** hs,
                      int        num_bins        );

static int        hist_area ( SNR_HIST **hist, int num_bins );

static int        read_bytes ( FILE *fp, char *b, int len );

static void       direct_search (
                      int*       IN_psi,
                      int        IN_K,
                      float*     IN_DELTA,
                      float      IN_rho,
                      float*     IN_delta        );

static void       snr (
                      SNR_HIST** full_hist,
                      int        num_bins,
                      float      cutoff_percentile,
                      float*     noise_lvl,
                      float*     speech_lvl      );

static float      percentile_hist (
                      SNR_HIST** hist,
                      int        num_bins,
                      float      percentile      );

static int        max_hist ( SNR_HIST **hist, int num_bins );


static int read_bytes ( FILE *fp, char *b, int len )
{
    int totalRead = 0;

    while ( totalRead < len ) {
    
        int bytesRead = (int)fread ( &(b[totalRead]),
                                     1,
                                     (int)( len - totalRead ),
                                     fp                        );
        if ( bytesRead == -1 ) {
            /* Error.*/
            return -1;
        }
        
        if ( bytesRead == 0 ) {
            /* EOF */
            return 0;
        }
        
        totalRead += bytesRead;
    }
    
    return totalRead;
}


int *computePeakAndPlots (
    const char* filename,
    int         width,
    int         height,
    int*        peak,
    int*        length
) {

    struct RIFF header;

    FILE *fp;

    fp = fopen ( filename, "rb" );

    if ( fp == NULL ) {
        return NULL;
    }

    if ( read_bytes( fp,
                     (char *)&header,
                     sizeof(header)   ) < sizeof(header) ) {

        fclose(fp);
        return NULL;
    }

    int totalSamples = header.dataSize / 2;
    
    *length = totalSamples;

    int *plotArray = (int*)malloc( sizeof(int) * width * 2 );

    if ( plotArray == NULL ) {

        fclose(fp);
        return NULL;
    }

    memset(plotArray, 0, sizeof(int) * width * 2 );

    short *readBuffer = (short*)malloc( SNR_CDB_BUF_SIZE_BYTES );

    if ( readBuffer == NULL ) {
    
        free(plotArray);
        fclose(fp);
        return NULL;
    }

    int samplesRead = 0;
    int samplesToBeRequested;

    if ( (totalSamples - samplesRead)
         > (SNR_CDB_BUF_SIZE_BYTES / 2) ) {

        samplesToBeRequested = SNR_CDB_BUF_SIZE_BYTES / 2;
    }
    else{
        samplesToBeRequested = totalSamples - samplesRead;
    }

    int currentPos   = 0;
    int currentX     = 0;
    int currentMaxYp = 0;
    int currentMaxYn = 0;
    int lPeak        = 0;

    while ( totalSamples > samplesRead ) {
        int bytesRead = read_bytes(fp,
                                   (char *)readBuffer,
                                   samplesToBeRequested * 2 );
        if ( bytesRead == -1 ) {
            /* error */
            free(plotArray);
            free(readBuffer);
            fclose(fp);
            return NULL;
        }
        
        samplesRead += (bytesRead / 2);

        int i;
        for ( i = 0; i < bytesRead / 2; i++, currentPos++ ) {

            short y = *( (short *) (&(readBuffer[i])) );

            int   x = (int) ( ((double)currentPos)
                              * ((double)width)
                              / ((double)totalSamples)  );

            if ( x > currentX ) {

                plotArray [ currentX * 2     ] = currentMaxYp;
                plotArray [ currentX * 2 + 1 ] = currentMaxYn;
                currentX++;
                
                if ( y >= 0 ) {
                    currentMaxYp = y;
                    currentMaxYn = 0;
                }
                else{
                    currentMaxYp = 0;
                    currentMaxYn = y;
                }
            }
            else{
                if ( ( y >= 0 ) && ( currentMaxYp < y ) ) {
                    currentMaxYp = y;
                }
                else if ( ( y < 0 ) && ( currentMaxYn > y ) ) {
                    currentMaxYn = y;
                }
            }

            if( abs(y) > lPeak ) {
                lPeak = abs(y);
            }
        }

        if ( ( totalSamples - samplesRead)
             > (SNR_CDB_BUF_SIZE_BYTES / 2) ) {

            samplesToBeRequested = SNR_CDB_BUF_SIZE_BYTES / 2;
        }
        else{
            samplesToBeRequested = totalSamples - samplesRead;
        }
    }
    
    if ( currentX < width ) {

        plotArray [ currentX * 2     ] = currentMaxYp;
        plotArray [ currentX * 2 + 1 ] = currentMaxYn;
        currentX++;
    }

    while ( currentX < width ) {

        plotArray [ currentX * 2     ] = 0;
        plotArray [ currentX * 2 + 1 ] = 0;
        currentX++;
    }
    
    *peak =lPeak;

    int i2;
    double halfHeight = ((double)height) / 2.0 ;
    
    for ( i2 = 0; i2 < width * 2; i2++ ) {
    
        plotArray[i2] = (int) ( ((double)plotArray[i2])
                                * halfHeight
                                / 32767.0
                                + halfHeight            );
    }
    
    free(readBuffer);
    fclose(fp);

    return plotArray;
}


static float compute_dc_bias( const char *filename )
{
    struct RIFF header;
    FILE *fp;

    fp = fopen( filename, "rb" );

    if ( fp == NULL ) {

        return 0.0;
    }

    if(read_bytes ( fp, (char *)&header, sizeof(header) )
                  < sizeof(header)                        ) {

        fclose(fp);
        return 0.0;
    }

    int    totalSamples = header.dataSize / 2;
    short* readBuffer   = (short*)malloc(SNR_CDB_BUF_SIZE_BYTES);

    if ( readBuffer == NULL ) {
        fclose(fp);
        return 0.0;
    }

    double sum         = 0.0;
    int    samplesRead = 0;

    int samplesToBeRequested;

    if ( ( totalSamples - samplesRead )
         > (SNR_CDB_BUF_SIZE_BYTES / 2) ) {

        samplesToBeRequested = SNR_CDB_BUF_SIZE_BYTES / 2;
    }
    else{

        samplesToBeRequested = totalSamples - samplesRead;
    }

    while ( totalSamples > samplesRead ) {

        int bytesRead = read_bytes ( fp,
                                     (char *)readBuffer,
                                     samplesToBeRequested * 2 );
        if ( bytesRead == -1 ) {
            /* error */
            free(readBuffer);
            fclose(fp);
            return 0.0;
        }

        samplesRead += ( bytesRead / 2 );

        for ( int i = 0; i < bytesRead / 2; i++ ) {
        
            double val = (double)(readBuffer[i]);
            sum += val;
        }
        
        if( ( totalSamples - samplesRead)
            > (SNR_CDB_BUF_SIZE_BYTES / 2) ) {

            samplesToBeRequested = SNR_CDB_BUF_SIZE_BYTES / 2;
        }
        else{

            samplesToBeRequested = totalSamples - samplesRead;
        }
    }

    free(readBuffer);
    fclose(fp);

    return (float)( sum / (double)(samplesRead) );
}


int estimateSNR(
    const char* filename,
    float*      noiseLevel,
    float*      speechLevel
) {

    int        frameWidth = 320; /* 20ms */
    int        frameAdv   = frameWidth / 2;
    float      dcBias     = compute_dc_bias ( filename );
    SNR_HIST** powerHist  = init_hist ( SNR_NUM_BINS,
                                        SNR_LOW_DB,
                                        SNR_HIGH_DB   );
    int rtn_val;
    rtn_val = compute_pwr_hist_sd( filename,
                                   powerHist,
                                   SNR_NUM_BINS,
                                   frameWidth,
                                   frameAdv,
                                   dcBias          );

    if ( rtn_val < 0 ) {
        return -1;
    }

    snr ( powerHist,
          SNR_NUM_BINS,
          SNR_PEAK_LEVEL,
          noiseLevel,
          speechLevel     );

    free_hist ( powerHist, SNR_NUM_BINS );

    return 0;
}


static SNR_HIST** init_hist(int numBins, float from, float to)
{
    SNR_HIST** th;
    double     dist;

    /* what's the span of possible values */
    dist = (double) ( to - from );
    
    th = alloc_hist( numBins, 1 );

    /* initialize the count, and set up the ranges */
    int i;
    for ( i = 0; i < numBins; i++ ) {

        th[i]->count = 0;

        th[i]->from  = from
                       + ( dist
                           * ( (double)i     / (double)numBins) );

        th[i]->to    = from
                       + ( dist
                           * ( (double)(i+1) / (double)numBins) );
    }

    return th;
}


static SNR_HIST** alloc_hist( int numBins, int numElems )
{
    SNR_HIST** th;

    th = (SNR_HIST**)malloc( sizeof(SNR_HIST*) * numBins );

    if ( th == NULL ) {
        return NULL;
    }

    int i;
    for ( i = 0; i <numBins; i++ ) {

        th[i] = (SNR_HIST*)malloc( sizeof(SNR_HIST) * numElems );

        if ( th[i] == NULL ) {

            int j;
            for ( j = 0; j < i; j++ ) {

                free(th[j]);
            }

            return NULL;
        }
    }

    return th;
}


static int compute_pwr_hist_sd(

    const char*  filename,
    SNR_HIST**   pwrHist,
    int          numBins,
    int          frameWidth,
    int          frameAdv,
    float        dcBias

) {
    int    samplesRead = 0;
    float  pwr;

    struct RIFF header;
    FILE* fp;

    fp = fopen ( filename, "r" );
    if(fp == NULL){
        return -1;
    }

    if(read_bytes( fp,
                   (char *)&header,
                   sizeof(header)   ) < sizeof(header) ) {

        fclose(fp);
        return -1;
    }

    int    totalSamples = header.dataSize / 2;
    short* readBuffer  = (short*)malloc( SNR_CDB_BUF_SIZE_BYTES +
                                          +frameWidth * sizeof(short) );
    if ( readBuffer == NULL ) {
        fclose(fp);
        return -1;
    }

    samplesRead = 0;
    int samplesProcessed   = 0;
    int samplesCarriedOver = 0;
    int samplesToBeRequested;
    int samplesInBuffer;

    if( (totalSamples - samplesRead) > (SNR_CDB_BUF_SIZE_BYTES / 2) ) {

        samplesToBeRequested = (SNR_CDB_BUF_SIZE_BYTES / 2);
    }
    else{
        samplesToBeRequested = (totalSamples - samplesRead);
    }
    
    while((totalSamples - samplesProcessed) >= frameWidth ) {

        int bytesRead = read_bytes( fp,
                                    (char*)&(readBuffer[ samplesCarriedOver ]),
                                    samplesToBeRequested * 2
                                  );
        if ( bytesRead == -1 ) {

            free(readBuffer);
            fclose(fp);
            return -1;
        }

        samplesRead    += ( bytesRead / 2 );
        samplesInBuffer = samplesCarriedOver + ( bytesRead / 2 );

        int index;
        int outOfRange=0;
        float from = pwrHist [0]->from;
        float dist = pwrHist [numBins - 1]->to - pwrHist [0]->from;

        int samplesProcessedInBuffer = 0;
        
        while( (samplesInBuffer - samplesProcessedInBuffer) >= frameWidth ) {

            /* compute log magnitude of (filtered) speech vector */
            pwr = pwr1( &(readBuffer[ samplesProcessedInBuffer ] ),
                        frameWidth,
                        dcBias                                     );

            if ( pwr != SNR_NEGATIVE_INFINITY ) {

                /* insert that value in the histogram */
                index = (int) ( (float)numBins
                                * ( (float)pwr - (float)from )
                                / (float)dist                  );

                if( ( index >= 0 ) && ( index < numBins ) ) {

                    pwrHist [index]->count++;
                }
                else{
                    outOfRange++;
                }
            }
            samplesProcessedInBuffer += frameAdv;
        }

        samplesProcessed += samplesProcessedInBuffer;
        samplesCarriedOver = samplesInBuffer - samplesProcessedInBuffer;

        memcpy( readBuffer,
                &(readBuffer [ samplesProcessedInBuffer ] ),
                samplesCarriedOver * 2                       );
        
        if ( outOfRange > 0 ) {
            /*printf("Hist Library: %d samples out of range (%4.2f,%4.2f)\n",
                   _out_of_range,_from,pwr_hist[num_bins-1]->to);*/
        }

        if( (totalSamples - samplesRead)
            > (SNR_CDB_BUF_SIZE_BYTES / 2) ) {

            samplesToBeRequested = ( SNR_CDB_BUF_SIZE_BYTES / 2 );
        }
        else{
            samplesToBeRequested = ( totalSamples - samplesRead );
        }
    }

    free(readBuffer);
    fclose(fp);

    return 0; /* OK */
}


float pwr1( short int *win, int len, float dcBias )
{
    int    i;
    double sum = 0.0;
    int    same = 1;  /* is this sample value equal to the previous ? */

    for ( i = 0; i < len; i++ ) {

        double v = (double) (win[i]) - dcBias;

        sum += ( v * v );

        if ( i > 0 ) {

            if ( win[i] != win[i-1] ) {

                same = 0;
            }
        }
    }

    /* watch out for log(zero) errors */
    /* also watch out for constant values */
    if ( (sum <= 0.0) || same == 1 ) {

        return (float)SNR_NEGATIVE_INFINITY;
    }

    if ( len == 0 ) {

        return (float)SNR_NEGATIVE_INFINITY;
    }

    return (float)( 10.0 * log10( ((double)sum / (double)len ) ) );
}


static void snr (
    SNR_HIST** fullHist,
    int        numBins,
    float      cutoffPercentile,
    float*     noiseLevel,
    float*     speechLevel
)
{

    SNR_HIST** cosHist;
    SNR_HIST** workHist;

    cosHist  = init_hist( numBins,
                          fullHist [0]->from,
                          fullHist [numBins - 1]->to  );

    workHist = init_hist( numBins,
                          fullHist [0]->from,
                          fullHist [numBins - 1]->to   );
  
    build_raised_cos_hist( fullHist,cosHist,numBins, noiseLevel );

    erase_hist( workHist, numBins );

    subtract_hist( cosHist, fullHist, workHist, numBins );

    *speechLevel = percentile_hist(workHist, numBins, cutoffPercentile );

    free_hist( workHist, numBins );
    free_hist( cosHist,  numBins );

}


void build_raised_cos_hist(
    SNR_HIST** refHist,
    SNR_HIST** retHist,
    int        numBins,
    float*     noisePeak
) {

    SNR_HIST** workHist;
    int        beginVal = 1;
    int        beginBin;
    int        peakSlope;
    int        peakBin = 0;
    int        tmp;
    int        maxHeight;
    int        halfPeakHeight;
    int        beginTop;
    int        endTop;
    int        vector[3];
    float      chgFact[3];
    float      chgLimit[3];

    workHist = init_hist( numBins,
                          refHist [0]->from,
                          refHist [numBins-1]->to  );

    smooth_hist( refHist, workHist, numBins, SNR_SMOOTH_BINS );

    /* set the threshold for the beginning of the histogram */
    beginVal = (int) ( (float)max_hist( workHist, numBins ) * 0.05 );

    /* find the beginning of the hist and the first peak */
    int i;
    for ( i = 0; (i < numBins) && (workHist[i]->count <= beginVal ) ; i++ ) {
        /*fprintf(stderr,"In loop1 %d\n",i)*/;
    }

    beginBin = i;
    /* calculate where we think the peak bin should be */

    /* first the slope method */
    for ( i = beginBin;
          ( i < numBins)
          && ( ( tmp = hist_slope( workHist, numBins, i, 2 ) ) >= 0 );
          i++                                                           ){
        /*fprintf(stderr, "In loop2 %d\n",i)*/;
    }
    
    peakBin = peakSlope = i;
    
    /* find the maximum height on the original histogram within +|- */
    /* 5 bins */
    maxHeight = 0;
    for ( i = peakSlope - 5; i <= peakBin + 5; i++ ) {
    
        if ( ( i >= 0 ) && ( i < numBins ) ) {
        
            if (refHist[i]->count > maxHeight ) {
            
                maxHeight =refHist[i]->count;
            }
        }
    }
    
    halfPeakHeight = workHist[peakBin]->count / 2;
    beginTop = endTop = peakBin;
    
    for ( i = peakBin;
          (i>=0) && ( workHist [i]->count > halfPeakHeight );
          i--                                                 ) {

        beginTop = i;
        int j;
        for ( j = peakBin;
              ( j < numBins) && (workHist[j]->count > halfPeakHeight);
              j++                                                      ) {

            endTop = j;
        }

        erase_hist( workHist, numBins );
        hist_copy( refHist, workHist, numBins, 0, numBins );

    }

    /* set up a vector for doing the direct search */
    /* then generate a full cosine wave for the using the best fit */
  
    vector[0] = peakBin;                   /* middle */
    vector[1] = maxHeight;                 /*half_peak_height*4; *//* height */
    vector[2] = (peakBin - beginTop) * 4;  /* width */

    chgFact[0] = numBins   * 0.01;
    chgFact[1] = maxHeight * 0.05;
    chgFact[2] = numBins   * 0.01;

    if ( chgFact[0] < 2.0 ) {
        chgFact[0] = 2.0;
    }
    
    if ( chgFact[1] < 2.0 ) {
        chgFact[1] = 2.0;
    }
    
    if ( chgFact[2] < 2.0 ) {
        chgFact[2] = 2.0;
    }

    chgLimit[0] = chgFact[0] / 2;
    chgLimit[1] = chgFact[1] / 2;
    chgLimit[2] = chgFact[2] / 2;

    do_init_comp1( workHist, retHist, numBins );

    direct_search(vector, 3, chgFact, 0.7, chgLimit );
  
    special_cosine_hist( retHist,
                         numBins,
                         vector[0],
                         vector[1],
                         vector[2]  );
  
    *noisePeak = (   retHist[ vector[0] ]->from
                   + retHist[ vector[0] ]->to   ) / 2.0;

    free_hist( workHist, numBins );
}


static void smooth_hist(
    SNR_HIST** from,
    SNR_HIST** to,
    int        numBins,
    int        window
) {
    int i;
    int value   = 0;
    int window2 = window * 2;

    for ( value = 0, i = ( -1 * window ); i < (numBins + window ); i++ ) {

        if ( i - window >= 0 ) {

            value -= from [ i - window ]->count;
        }

        if ( i + window < numBins ) {

            value += from [ i + window ]->count;
        }

        if ( (i >= 0) && (i < numBins) ) {

            to[i]->count = value / window2;
        }
    }
}


static int max_hist( SNR_HIST** hist, int numBins )
{
    int i;
    int max=0;

    for ( i = 0; i < numBins; i++ ) {

        if ( max < hist[i]->count ) {

            max = hist[i]->count;
        }
    }
    return max ;
}


static int hist_slope( SNR_HIST** hist, int numBins, int center, int factor )
{
    int ind, cnt;

    for ( ind = 0, cnt = 0; ind < factor; ind++ ) {

        if ( center - ind < 0 ) {

            cnt -= hist[ center + ind ]->count;
        }
        else if ( ind + center >= numBins ) {
        
            cnt += hist[ center - ind ]->count;
        }
        else{

            cnt += hist[ center - ind ]->count - hist[ center + ind ]->count;
        }
    }

    return (int) ( -1.0 * ( (float)cnt / (float)factor ) * 1000.0 );
}


static void hist_copy(
    SNR_HIST** from,
    SNR_HIST** to,
    int        numBins,
    int        start,
    int        end
) {
    int i;
    for ( i = start; ( i < numBins ) && ( i <= end ); i++ ) {

         to[i]->count = from[i]->count;
    }
}

static SNR_HIST** stRef;
static SNR_HIST** stHyp;
static int        stNumBins;

static void do_init_comp1(SNR_HIST** ref, SNR_HIST** hyp, int numBins )
{
    stRef     = ref;
    stHyp     = hyp;
    stNumBins = numBins;
}


static float comp1( int* vector )
{
    float result;

    erase_hist( stHyp, stNumBins );
    
    /* at least 4 bins wide, height at least 10 */
    if ( (vector[0] <= 0) || (vector[1] < 10) || (vector[2] < 4) ) {
    
        result = 99999999.99; /* a really large float */
    }
    else {

        special_cosine_hist( stHyp,
                             stNumBins,
                             vector[0],
                             vector[1],
                             vector[2]   );

        result = do_least_squares( stRef, stHyp, stNumBins );
    }

    return result;
}


static float do_least_squares(

    SNR_HIST** noise,
    SNR_HIST** normal,
    int        numBins

) {

    double sqrSum  = 0.0;
    double sqr;
    double extendDB = 5.0;

    int i   = 0;
    int end = 0;

    while ( (i < numBins) && (normal[i]->count <= 0 ) ) {
        i++;
    }
    
    end = i;
    i -= numBins;

    if ( i < 0 ) {
        i = 0;
    }

    for (; end < numBins && ( normal[end]->count > 0 ); end++ ) {
        ;
    }
    
    if (end >= numBins ) {

        end = numBins - 1;
    }

    end += ( (float)numBins
             / ( normal[numBins-1]->to - normal[0]->from ) )
             * extendDB;

    if ( end >= numBins ) {

        end = numBins - 1;
    }

    for (; i < end; i++ ) {

        sqr =   (float)( noise[i]->count - normal[i]->count )
              * (float)( noise[i]->count - normal[i]->count ) ;
        
        if ( noise[i]->count == 0 ) {

            sqrSum += (sqr * sqr);
        }
        else{

            sqrSum += sqr;
        }
    }

    return sqrSum ;
}


static void special_cosine_hist(
    SNR_HIST** hist,
    int        numBins,
    int        middle,
    int        height,
    int        width
) {
    int   i;
    float factor;
    float heightby2;
    float cFact = 0.0;
    float SNR_PI2 = SNR_PI * 2.0;

    factor    = 1.0 / (float)(width);

    heightby2 = height / 2;

    for ( i = middle - (width/2); i <= (middle + (width/2)); i++ ) {
    
        if ( (i >= 0) && (i < numBins) ) {

            hist[i]->count = heightby2
                             + heightby2
                             * cos( (float)(cFact * SNR_PI2 - SNR_PI) );
        }

        cFact += factor;
    }
}


static void free_hist( SNR_HIST** hist, int numBins )
{
    int ny;
    for (ny = 0; ny<numBins; ny++ ) {
    
        free(hist[ny]);
    }

    free(hist);
}


static void erase_hist( SNR_HIST** hist, int numBins )
{
    int i;
    for (i = 0; i < numBins; i++ ) {

        hist[i]->count = 0;
    }
}


void subtract_hist(SNR_HIST** h1, SNR_HIST** h2, SNR_HIST** hs, int numBins )
{
    int i;
    for ( i = 0; i < numBins; i++ ) {
    
        hs[i]->count = h2[i]->count - h1[i]->count;
    
        if ( hs[i]->count < 0 ) {

            hs[i]->count = 0;
        }
    }
}


static float percentile_hist(SNR_HIST** hist, int numBins, float percentile )
{
    int i;
    int pctArea;
    int area = 0;

    pctArea = (int) ( (float)hist_area( hist, numBins ) * percentile );
   
    for ( i = 0; (i < numBins) && (area + hist[i]->count < pctArea ); i++ ) {

        area += hist[i]->count;
    }

    return hist[i]->from + ( ( hist[i]->to - hist[i]->from ) / 2.0 );
}


static int hist_area(SNR_HIST** hist, int numBins )
{
    int i;
    int sum=0;

    for ( i = 0; i < numBins; i++ ) {

        sum += hist[i]->count;
    }

    return sum;
}


/*  this the direct_search algorithm from Robert Hook and T. A. Reeves
    "Direct Search" Solution of Numerical and Statistical Problems
    (Journal ACM 1961 (p212-229)

    The search uses an input vector to calculate a value from a function
    S and then modifies the vector to minimize the function.  Input
    parameters are:

        phi:   the current base point
        K:     The number of coordinate points
        DELTA: The current step size
        delta: The "minimum" step size
        rho:   The reduction factor for the step size (rho < 1)
        S:     The function used for the minimization

    OTHER VARIABLES:

        theta:    the previous base point
        psi:    the base point resulting from the current move
        Spsi:    The functional value of S(psi)
        Sphi:    The functional value of S(phi)
        SS:    ?

    Last change date: Nov 27 1990
    cleaned up slightly, verbose option removed summer 1992.
*/


static void direct_search(

    int*   IN_psi,
    int    IN_K,
    float* IN_DELTA,
    float  IN_rho,
    float* IN_delta

) {

    float  SS;
    float  Spsi;
    float  Sphi;
    float  theta;
    float* DELTA;
    float* delta;
    float  rho;
    int    phi[30];
    int    K;
    int    k;
    int*   psi;
    int    DELTA_change;

    psi   = IN_psi;
    K     = IN_K;
    DELTA = IN_DELTA;
    rho   = IN_rho;
    delta = IN_delta;

    Spsi  = comp1(psi);

L1:
    SS = Spsi;

    for ( k = 0; k < K; k++ ) {

        phi[k] = psi[k];
    }

    for ( k = 0; k < K; k++ ) {

        phi[k] += DELTA[k];
        Sphi = comp1(phi);

        if ( Sphi < SS ) {

            SS = Sphi;
        }
        else{

            phi[k] -= ( 2 * (int)DELTA[k] );
            Sphi = comp1(phi);

            if ( Sphi < SS ) {
                SS = Sphi;
            }
            else{
                phi[k] += DELTA[k];
            }
        }
    }

    if ( SS < Spsi ) {

        do{
        
            for ( k = 0; k < K; k++ ) {
                theta  = psi[k];
                psi[k] = phi[k];
                phi[k] = 2 * phi[k] - theta;
            }
            
            Spsi = SS;
            SS   = Sphi = comp1(phi);

            for ( k = 0; k < K; k++ ) {

                phi[k] += DELTA[k];
                Sphi   = comp1(phi);
                
                if ( Sphi < SS ) {
                    SS = Sphi;
                }
                else{
                
                    phi[k] -= ( 2 * (int)DELTA[k] );
                    Sphi   = comp1(phi);

                    if ( Sphi < SS ) {
                        SS = Sphi;
                    }
                    else{
                        phi[k] += DELTA[k];
                    }
                }
            }
            
        } while ( SS < Spsi );
        
        goto L1;
    }

    DELTA_change = 0;

    for( k = 0; k < K; k++ ) {
    
        if( DELTA[k] >= delta[k] ) {

            DELTA[k]     = rho * DELTA[k];
            DELTA_change = 1;
        }
    }
    
    if ( DELTA_change == 1 ) {

        goto L1;
    }

}


