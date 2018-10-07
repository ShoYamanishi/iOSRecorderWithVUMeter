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
 *
 *
 * Comments on the algorithm:
 *
 * SNR = 10*log_10(RMS_peak_speech / RMS_mean_noise)
 * The window size is 20ms, and the shift is 10ms.
 *
 * It first calculates RMS for each frame, and make a histogram.
 * It then finds the average noise power with a raised cosine function with
 * Chi-square distance fitting.
 * The fitting is done on the low-frequency side of the lower peak of the
 * histogram..
 * The mid-point of the function is considered the mean noise.
 * It then finds the peak speech.
 * It subtract the raised cosine from the histogram to extract the speech
 * energy only.
 * The point where 95% of the energy falls below it is considrered the peak.
 *
 * Dependencies:
 *
 * The implementation was taken from the following NIST algorithm
 * https://www.nist.gov/information-technology-laboratory/iad/mig/mk3-downloads
 *
 * Disclaimer of the NIST algorithm cited above:
 * "This software was developed at the National Institute of Standards and
 * Technology by employees of the Federal Government in the course of their
 * official duties. Pursuant to Title 17 Section 105 of the United States Code
 * this software is not subject to copyright protection and is in the public
 * domain. The Mark-III microphone array is an experimental system and is
 * offered AS IS. NIST assumes no responsibility whatsoever for its use by other
 * parties, and makes no guarantees and NO WARRANTIES, EXPRESS OR IMPLIED, about
 * its quality, reliability, fitness for any purpose, or any other
 * characteristic. We would appreciate acknowledgment if the software is used.
 * This software can be redistributed and/or modified freely provided that any
 * derivative works bear some notice that they are derived from it, and any
 * modified versions bear some notice that they have been modified from the
 * original."
 */

#ifndef _ESTIMATE_SNR_H_
#define _ESTIMATE_SNR_H_

#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <math.h>

/** @brief estimate the speech and the background noise levels of the given
 *         wave file, assuming the wave file contains human speech.
 *
 *  @param filename    (in):  wave file name
 *  @param noiseLevel  (out): background noise level in [dB]
 *  @param speechLevel (out): speech level in [dB]
 *
 *  @return 0:  Success
 *          -1: Failure mostlikely due to wrong input file.
 */
 
int estimateSNR(
    const char* filename,
    float*      noiseLevel,
    float*      speechLevel   );


/** @brief generate an array of integers to plot the wave on the 2D screen.
 *         The array has width * 2 elements. The elements at even indices
 *         (index starts at 0) are positive amplitude, and at odd indices
 *         are negative amplitude. The amplitude 0 is height/2.
 *
 *  @param filename    (in):  wave file name
 *  @param width       (in):  width of the screen (axis of time)
 *  @param height      (in):  height of the screen (axis of amplitude)
 *  @param peak        (out): absolute peak amplitude
 *  @param length      (out): length of the wave file in samples
 *
 *  @return array of integers to plot the wave
 */

int* computePeakAndPlots(
    const char* filename,
    int         width,
    int         height,
    int*        peak,
    int*        length         );



#endif /*_ESTIMATE_SNR_H_*/
