/// MIT License
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
#import "WaveDrawingView.h"

@implementation WaveDrawingView

@synthesize mData;


- (id)initWithFrame : (CGRect)frame
{
    self = [ super initWithFrame : frame ];

    if (self) {
        mData = nil;
    }

    return self;
}


- (void)drawRect : (CGRect)rect {

    [ super drawRect : rect ];

    CGContextRef context = UIGraphicsGetCurrentContext();
    
    CGContextSetStrokeColorWithColor( context, [UIColor greenColor].CGColor );

    CGContextSetLineWidth( context, 1.0 );

    int *plots = malloc( [ mData length ] );

    if ( plots == NULL ) {
        return;
    }

    [ mData getBytes : plots length : [ mData length ] ];

    unsigned long plotLen = [ mData length ] / sizeof(int);

    CGContextMoveToPoint( context, 0, plots[0] );

    for ( int i = 1; i < plotLen; i++ ) {
    
        CGContextAddLineToPoint( context, i/2, plots[i] );
    }

    CGContextStrokePath( context );

    free( plots );

}


-(void)plotWith : (NSData *)plots
{

    mData = plots;
    
    [ self setNeedsDisplay ];

}

@end

