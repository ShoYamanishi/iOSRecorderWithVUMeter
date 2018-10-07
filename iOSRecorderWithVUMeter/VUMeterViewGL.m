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
// Dependencies:
// The image of VU Meter taken from the following:
// https://en.wikipedia.org/wiki/VU_meter#/media/File:VU_Meter.jpg
// Iainf 05:15, 12 August 2006 (UTC) - Own work CC BY 2.5
//

#import <Foundation/Foundation.h>
#import "VUMeterViewGL.h"

typedef struct _VUMeterVertex {

    float Position [3];
    float TexCoord [2];

} VUMeterVertex;

@implementation VUMeterViewGL {

    EAGLContext*   mGLContext;
    CAEAGLLayer*   mEaglLayer;
    CADisplayLink* mDisplayLink;
    GLuint         mTexture;

    GLuint         mPositionSlot;
    GLuint         mTexCoordSlot;
    GLuint         mTextureUniform;
 
    GLuint         mVertexBuffer;
    GLuint         mIndexBuffer;
    GLuint         mColorRenderBuffer;
    GLuint         mFramebuffer;

    VUMeterVertex  mVertices [3 * 4];
    GLubyte        mIndices  [18];
    
    float          mTheta;
    float          mVelocity;
    float          mAccel;
    float          mPrevTime;
    
    unsigned short mRMS;
    unsigned short mAbsMax;
    
    BOOL           mIsActive;
}


/////////////////////////////////////////////
//                                         //
//         TEXTURE RELATED SECTION         //
//                                         //
/////////////////////////////////////////////


/** @brief Positions in pixel in VU_Meter_Texture.png
 * The positions are in the xy integer coordinates
 * of the PNG file where Y's positive direction is
 * downward.
 *
 *           PNG Texture Coordinates
 *           -----------------------
 *
 *  (0,0)                          (TextureWidth, 0)
 *    +---------------------------------------->X
 *    |
 *    |
 *    |  [ Pixels are in this rectangular area ]
 *    |
 *  Y\|/
 *   (0,TextureHeight)
 *
 *
 *  Normalized Texture Coordinates used by OpenGL
 *  ---------------------------------------------
 *
 *                  (0,1)
 *                     ^
 *                     |
 *                     |
 *                     |
 *                     |
 *  (-1,0)        (0,0)|                (1,0)
 *    -----------------+------------------>
 *                     |
 *                     |
 *                     |
 *                     |
 *                     |
 *                   (0,-1)
 */

/** @brief Following are points in PNG texture coordinates. */

static const float TextureWidth             = 512.0;
static const float TextureHeight            = 512.0;

static const float BaseWidth                = 512.0;
static const float BaseHeight               = 300.0;

static const float HandTopLeftX             =   8.0;
static const float HandTopLeftY             = 313.0;
static const float HandBottomRightX         = 187.0;
static const float HandBottomRightY         = 316.0;
static const float HandRotatingCenterX      = 251.0;
static const float HandRotatingCenterY      = 288.0;
static const float HandBottomUprightOnBaseY = 240.0;

static const float LEDTopLeftOnBaseX        = 414.0;
static const float LEDTopLeftOnBaseY        = 116.0;
static const float LEDTopLeftX              = 198.0;
static const float LEDTopLeftY              = 304.0;
static const float LEDBottomRightX          = 231.0;
static const float LEDBottomRightY          = 339.0;


/**  @brief Converting from PNG texture Coord to Normalized Coord */

- (float) fromTexCoordToNormCoordX : (float) x
{
    return ( x / BaseWidth ) * 2.0 - 1.0;
}


/** @brief Converting from PNG texture Coord to Normalized Coord */

- (float) fromTexCoordToNormCoordYInverted : (float) y
{
    return ( y / BaseHeight ) * -2.0 + 1.0;
}


/** @brief Construct the vertices, texture points, and the indices for OpenGL.
 *         Called only once at initialization.
 */

-(void) makeInitialVertexCoordinates
{
    // VU Meter base.
    mVertices[ 0].Position[0] = [ self fromTexCoordToNormCoordX :
                                                             BaseWidth  ];

    mVertices[ 0].Position[1] = [ self fromTexCoordToNormCoordYInverted :
                                                             BaseHeight ];

    mVertices[ 0].Position[2] = 0.0;


    mVertices[ 1].Position[0] = [ self fromTexCoordToNormCoordX :
                                                             BaseWidth  ];

    mVertices[ 1].Position[1] = [ self fromTexCoordToNormCoordYInverted :
                                                             0.0        ];

    mVertices[ 1].Position[2] = 0.0;


    mVertices[ 2].Position[0] = [ self fromTexCoordToNormCoordX :
                                                             0.0        ];

    mVertices[ 2].Position[1] = [ self fromTexCoordToNormCoordYInverted :
                                                             0.0        ];

    mVertices[ 2].Position[2] = 0.0;


    mVertices[ 3].Position[0] = [ self fromTexCoordToNormCoordX :
                                                             0.0        ];

    mVertices[ 3].Position[1] = [ self fromTexCoordToNormCoordYInverted :
                                                             BaseHeight ];

    mVertices[ 3].Position[2] = 0.0;
    
    // LED
    float LEDWidth  = LEDBottomRightX - LEDTopLeftX;
    float LEDHeight = LEDBottomRightY - LEDTopLeftY;

    mVertices[ 8].Position[0] = [ self fromTexCoordToNormCoordX :
                                          LEDTopLeftOnBaseX + LEDWidth  ];

    mVertices[ 8].Position[1] = [ self fromTexCoordToNormCoordYInverted :
                                          LEDTopLeftOnBaseY + LEDHeight ];

    mVertices[ 8].Position[2] = 0.0;


    mVertices[ 9].Position[0] = [ self fromTexCoordToNormCoordX :
                                          LEDTopLeftOnBaseX + LEDWidth  ];

    mVertices[ 9].Position[1] = [ self fromTexCoordToNormCoordYInverted :
                                          LEDTopLeftOnBaseY             ];

    mVertices[ 9].Position[2] = 0.0;


    mVertices[10].Position[0] = [ self fromTexCoordToNormCoordX :
                                          LEDTopLeftOnBaseX             ];

    mVertices[10].Position[1] = [ self fromTexCoordToNormCoordYInverted :
                                          LEDTopLeftOnBaseY             ];

    mVertices[10].Position[2] = 0.0;


    mVertices[11].Position[0] = [ self fromTexCoordToNormCoordX :
                                          LEDTopLeftOnBaseX             ];

    mVertices[11].Position[1] = [ self fromTexCoordToNormCoordYInverted :
                                          LEDTopLeftOnBaseY + LEDHeight ];

    mVertices[11].Position[2] = 0.0;
    
    // Base
    mVertices[ 0].TexCoord[0] = BaseWidth  / TextureWidth;
    mVertices[ 0].TexCoord[1] = BaseHeight / TextureHeight;
    mVertices[ 1].TexCoord[0] = BaseWidth  / TextureWidth;
    mVertices[ 1].TexCoord[1] = 0.0;
    mVertices[ 2].TexCoord[0] = 0.0;
    mVertices[ 2].TexCoord[1] = 0.0;
    mVertices[ 3].TexCoord[0] = 0.0;
    mVertices[ 3].TexCoord[1] = BaseHeight / TextureHeight;
    
    // Indicator
    mVertices[ 4].TexCoord[0] = HandBottomRightX / TextureWidth;
    mVertices[ 4].TexCoord[1] = HandBottomRightY / TextureHeight;
    mVertices[ 5].TexCoord[0] = HandBottomRightX / TextureWidth;
    mVertices[ 5].TexCoord[1] = HandTopLeftY     / TextureHeight;
    mVertices[ 6].TexCoord[0] = HandTopLeftX     / TextureWidth;
    mVertices[ 6].TexCoord[1] = HandTopLeftY     / TextureHeight;
    mVertices[ 7].TexCoord[0] = HandTopLeftX     / TextureWidth;
    mVertices[ 7].TexCoord[1] = HandBottomRightY / TextureHeight;
    
    // LED
    mVertices[ 8].TexCoord[0] = LEDBottomRightX / TextureWidth;
    mVertices[ 8].TexCoord[1] = LEDBottomRightY / TextureHeight;
    mVertices[ 9].TexCoord[0] = LEDBottomRightX / TextureWidth;
    mVertices[ 9].TexCoord[1] = LEDTopLeftY     / TextureHeight;
    mVertices[10].TexCoord[0] = LEDTopLeftX     / TextureWidth;
    mVertices[10].TexCoord[1] = LEDTopLeftY     / TextureHeight;
    mVertices[11].TexCoord[0] = LEDTopLeftX     / TextureWidth;
    mVertices[11].TexCoord[1] = LEDBottomRightY / TextureHeight;

    // Indices
    mIndices[ 0] =  0;
    mIndices[ 1] =  1;
    mIndices[ 2] =  2;
    mIndices[ 3] =  2;
    mIndices[ 4] =  3;
    mIndices[ 5] =  0;
    mIndices[ 6] =  4;
    mIndices[ 7] =  5;
    mIndices[ 8] =  6;
    mIndices[ 9] =  6;
    mIndices[10] =  7;
    mIndices[11] =  4;
    mIndices[12] =  8;
    mIndices[13] =  9;
    mIndices[14] = 10;
    mIndices[15] = 10;
    mIndices[16] = 11;
    mIndices[17] =  8;
    
}


/** @brief Construct/Update the vertices, texture points, and the indices
 *         of the hand of the VU meter for OpenGL.
 *         Called at every screen update (at frame rate).
 *         It depends on mTheta, the angle of the hand.
 */
- (void) makeHandVertices
{
    float radiusShort   = HandRotatingCenterY - HandBottomUprightOnBaseY;

    float radiusLong    = radiusShort + HandBottomRightX - HandTopLeftX;

    float handHalfWidth = ( HandBottomRightY - HandTopLeftY ) * 0.5;
    
    float cosTheta = cos( mTheta );
    float sinTheta = sin( mTheta );
    
    float posBottomCenterX = HandRotatingCenterX + cosTheta * radiusShort;
    float posBottomCenterY = HandRotatingCenterY - sinTheta * radiusShort;
    float posTopCenterX    = HandRotatingCenterX + cosTheta * radiusLong;
    float posTopCenterY    = HandRotatingCenterY - sinTheta * radiusLong;

    float offsetFromCenterToTopLeftX = handHalfWidth * -1.0 * sinTheta;
    float offsetFromCenterToTopLeftY = handHalfWidth * cosTheta;

    mVertices[4].Position[0] = [ self fromTexCoordToNormCoordX :
                                posTopCenterX    + offsetFromCenterToTopLeftX ];

    mVertices[4].Position[1] = [ self fromTexCoordToNormCoordYInverted :
                                posTopCenterY    - offsetFromCenterToTopLeftY ];

    mVertices[4].Position[2] = 0.0;


    mVertices[5].Position[0] = [ self fromTexCoordToNormCoordX :
                                posTopCenterX    - offsetFromCenterToTopLeftX ];

    mVertices[5].Position[1] = [ self fromTexCoordToNormCoordYInverted :
                                posTopCenterY    + offsetFromCenterToTopLeftY ];

    mVertices[5].Position[2] = 0.0;


    mVertices[6].Position[0] = [ self fromTexCoordToNormCoordX :
                                posBottomCenterX + offsetFromCenterToTopLeftX ];

    mVertices[6].Position[1] = [ self fromTexCoordToNormCoordYInverted :
                                posBottomCenterY - offsetFromCenterToTopLeftY ];

    mVertices[6].Position[2] = 0.0;


    mVertices[7].Position[0] = [ self fromTexCoordToNormCoordX :
                                posBottomCenterX - offsetFromCenterToTopLeftX ];

    mVertices[7].Position[1] = [ self fromTexCoordToNormCoordYInverted :
                                posBottomCenterY + offsetFromCenterToTopLeftY ];

    mVertices[7].Position[2] = 0.0;

}


/////////////////////////////////////////////
//                                         //
//        VU METER MOVEMENT SECTION        //
//                                         //
/////////////////////////////////////////////


static const float HandAngularLimitLeft     = M_PI * 3.0/4.0;
static const float HandAngularLimitRight    = M_PI * 1.0/4.0;

static const float AccelerationCoefficient  = 100.0;
static const float FrictionCoefficient      =  10.0;
static const float AmplitudeRef             = SHRT_MAX / 1.4142135623;
//static const float DynamicRangeFloorDB      = -96.0;

// Following three parameters depend on the microphone and the amplifier.
static const short OverloadThreshold        = SHRT_MAX - 500;
static const float MicGainCalibFloorDB      = -55.0;
static const float MicGainCalibPeakDB       =  -0.0;


-(void) resetPhysics
{
    mTheta    = HandAngularLimitLeft;
    mVelocity = 0.0;
    mAccel    = 0.0;
    mPrevTime = 0.0;
}


-(void) updatePhysics
{
    double currentTime = CACurrentMediaTime();
    double dt;

    if ( mPrevTime == 0.0 ) {

        dt = 0.01;
    }
    else{

        dt = currentTime - mPrevTime;
    }

    mPrevTime = currentTime;
    
    if ( mRMS < 1 ) {
        mRMS = 1;
    }

    // The range of micDB is expected to be in
    // [ MicGainCalibFloorDB ,MicGainCalibPeakDB ].

    float micDB = 20.0 * log10 ( ( (float)mRMS ) / AmplitudeRef );

    float targetTheta = HandAngularLimitLeft
                        + ( HandAngularLimitRight - HandAngularLimitLeft )
                            * ( micDB - MicGainCalibFloorDB )
                            / ( MicGainCalibPeakDB - MicGainCalibFloorDB );
    
    
    mAccel = AccelerationCoefficient * ( targetTheta - mTheta )
             - FrictionCoefficient * mVelocity;

    mVelocity = mVelocity + mAccel * dt;
    mTheta    = mTheta + mVelocity * dt;

    if ( mTheta > HandAngularLimitLeft ) {

        mTheta = HandAngularLimitLeft;
        mVelocity = 0.0;
    }

    if ( mTheta < HandAngularLimitRight ) {

        mTheta = HandAngularLimitRight;
        mVelocity = 0.0;
    }
}


/////////////////////////////////////////////
//                                         //
//              OPEN GL SECTION            //
//                                         //
/////////////////////////////////////////////



-(void) prepareShaders
{

    GLuint vertexShader   = [ self compileShader : @"2DOrthoVertex"
                                            type :GL_VERTEX_SHADER   ];

    GLuint fragmentShader = [ self compileShader : @"PassThruFragment"
                                            type :GL_FRAGMENT_SHADER ];
    
    GLuint programHandle = glCreateProgram();

    glAttachShader( programHandle, vertexShader   );
    glAttachShader( programHandle, fragmentShader );

    glLinkProgram ( programHandle );
    
    GLint linkSuccess;

    glGetProgramiv( programHandle, GL_LINK_STATUS, &linkSuccess );

    if ( linkSuccess == GL_FALSE ) {

        GLchar messages [ 256 ];

        glGetProgramInfoLog ( programHandle,
                              sizeof(messages),
                              0,
                              &messages[0]      );

        NSString *messageString = [ NSString stringWithUTF8String : messages ];

        NSLog(@"%@", messageString);
        exit(1);

    }
    
    glUseProgram( programHandle );
    
    mPositionSlot   = glGetAttribLocation( programHandle, "Position"   );
    mTexCoordSlot   = glGetAttribLocation( programHandle, "TexCoordIn" );
    
    glEnableVertexAttribArray( mPositionSlot );
    glEnableVertexAttribArray( mTexCoordSlot );

    mTextureUniform = glGetUniformLocation( programHandle, "Texture" );
}


-(GLuint)compileShader : (NSString*) shaderName type : (GLenum) shaderType
{
    NSString* shaderPath =
        [ [NSBundle mainBundle] pathForResource:shaderName ofType : @"glsl" ];
    
    NSError* error;
    NSString* shaderString =
        [ NSString stringWithContentsOfFile : shaderPath
                                   encoding : NSUTF8StringEncoding
                                      error : &error                ];
    if ( !shaderString ) {

        NSLog(@"Error loading shader: %@", error.localizedDescription);
        exit(1);

    }
    
    GLuint shaderHandle = glCreateShader( shaderType );
    
    const char * shaderStringUTF8 = [ shaderString UTF8String ];

    int shaderStringLength = (int) [ shaderString length ];
    
    glShaderSource  ( shaderHandle,
                      1,
                      &shaderStringUTF8,
                      &shaderStringLength  );

    glCompileShader ( shaderHandle );
    
    GLint compileSuccess;
    glGetShaderiv( shaderHandle, GL_COMPILE_STATUS, &compileSuccess );

    if ( compileSuccess == GL_FALSE ) {

        GLchar messages [ 256 ];
        
        glGetShaderInfoLog( shaderHandle, sizeof(messages), 0, &messages[0] );
        NSString *messageString = [ NSString stringWithUTF8String : messages ];

        NSLog(@"%@", messageString);
        exit(1);

    }
    
    return shaderHandle;
}


-(GLuint) setupTexture : (NSString*) fileName
{
    CGImageRef spriteImage = [ UIImage imageNamed : fileName ].CGImage;

    if ( !spriteImage ) {

        NSLog(@"Failed to load image %@", fileName);
        exit(1);

    }
    
    size_t width  = CGImageGetWidth (spriteImage);
    size_t height = CGImageGetHeight(spriteImage);
    
    GLubyte * spriteData =
               (GLubyte *) calloc( width * height * 4, sizeof(GLubyte) );
    
    CGContextRef spriteContext = CGBitmapContextCreate (
                                    spriteData,
                                    width,
                                    height,
                                    8,
                                    width * 4,
                                    CGImageGetColorSpace(spriteImage),
                                    (enum CGBitmapInfo)
                                        kCGImageAlphaPremultipliedLast
                                );
    
    CGContextDrawImage( spriteContext,
                        CGRectMake( 0, 0, width, height ),
                        spriteImage                       );
    
    CGContextRelease( spriteContext );
    
    GLuint texName;
    glGenTextures( 1, &texName );
    glBindTexture( GL_TEXTURE_2D, texName );
    
    glTexParameteri( GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST );
    
    glTexImage2D( GL_TEXTURE_2D,
                  0,
                  GL_RGBA,
                  (int)width,
                  (int)height,
                  0,
                  GL_RGBA,
                  GL_UNSIGNED_BYTE,
                  spriteData        );
    
    glTexParameterf( GL_TEXTURE_2D, GL_TEXTURE_WRAP_S,     GL_REPEAT  );
    glTexParameterf( GL_TEXTURE_2D, GL_TEXTURE_WRAP_T,     GL_REPEAT  );
    glTexParameterf( GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST );
    glTexParameterf( GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST );
    
    free(spriteData);
    
    return texName;
}


-(void) setupOpenGL
{
    glGenBuffers        ( 1, &mVertexBuffer      );
    glGenBuffers        ( 1, &mIndexBuffer       );
    glGenRenderbuffers  ( 1, &mColorRenderBuffer );
    glGenFramebuffers   ( 1, &mFramebuffer       );

    mEaglLayer = (CAEAGLLayer*) self.layer;
    mEaglLayer.opaque = YES;
    self.contentScaleFactor = [ [UIScreen mainScreen] nativeScale ];

    glBindRenderbuffer( GL_RENDERBUFFER, mColorRenderBuffer );

    [ mGLContext renderbufferStorage : GL_RENDERBUFFER
                        fromDrawable : mEaglLayer       ];

    glBindFramebuffer( GL_FRAMEBUFFER, mFramebuffer );

    glFramebufferRenderbuffer( GL_FRAMEBUFFER,
                               GL_COLOR_ATTACHMENT0,
                               GL_RENDERBUFFER,
                               mColorRenderBuffer    );
}


- (void)render : (CADisplayLink*) displayLink {
    
    if( !mIsActive ) {
        return;
    }
    
    [ self updatePhysics    ];
    [ self makeHandVertices ];
    
    glBindBuffer( GL_ARRAY_BUFFER, mVertexBuffer );
    glBufferData( GL_ARRAY_BUFFER,
                  sizeof(mVertices),
                  mVertices,
                  GL_STATIC_DRAW      );

    glBindBuffer( GL_ELEMENT_ARRAY_BUFFER, mIndexBuffer );
    glBufferData( GL_ELEMENT_ARRAY_BUFFER,
                  sizeof(mIndices),
                  mIndices,
                  GL_STATIC_DRAW           );
    
    glClearColor( 0.0, 0.0, 0.0, 0.0 );
    glClear     ( GL_COLOR_BUFFER_BIT );
    glEnable    ( GL_TEXTURE_2D );
    glEnable    ( GL_BLEND );
    glDepthMask ( GL_FALSE );
    glBlendFunc ( GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA );
    
    glViewport(0,
               0,
               self.frame.size.width  * self.contentScaleFactor,
               self.frame.size.height * self.contentScaleFactor  );
    
    glVertexAttribPointer( mPositionSlot,
                           3,
                           GL_FLOAT,
                           GL_FALSE,
                           sizeof(VUMeterVertex),
                           0                        );

    glVertexAttribPointer( mTexCoordSlot,
                           2,
                           GL_FLOAT,
                           GL_FALSE,
                           sizeof(VUMeterVertex),
                           (GLvoid*) (sizeof(float) * 3)  );
    
    glActiveTexture( GL_TEXTURE0 );
    glBindTexture( GL_TEXTURE_2D, mTexture );
    glUniform1i( mTextureUniform, 0 );
    
    glDrawElements( GL_TRIANGLES, 6, GL_UNSIGNED_BYTE, (GLvoid*)0 );
    glDrawElements( GL_TRIANGLES, 6, GL_UNSIGNED_BYTE, (GLvoid*)6 );
    
    if ( mAbsMax >= OverloadThreshold ) {

        glDrawElements( GL_TRIANGLES, 6, GL_UNSIGNED_BYTE, (GLvoid*)12 );
    }
    
    [ mGLContext presentRenderbuffer : GL_RENDERBUFFER ];
}


/////////////////////////////////////////////
//                                         //
//         UIVIEW RELATED SECTION          //
//                                         //
/////////////////////////////////////////////


+ (Class)layerClass {

    return [ CAEAGLLayer class ];

}


-(id)initWithCoder:(NSCoder *)aDecoder
{
    self = [ super initWithCoder : aDecoder ];

    if (self) {
        
        mGLContext = NULL;
        mGLContext =
             [ [EAGLContext alloc] initWithAPI : kEAGLRenderingAPIOpenGLES2 ];
        
        if ( !mGLContext ) {

            NSLog(@"Failed to initialize OpenGLES 2.0 context");
            exit(1);
        }
        
        if ( ![ EAGLContext setCurrentContext : mGLContext ] ) {

            NSLog(@"Failed to set current OpenGL context");
            exit(1);
        }
        
        [ self prepareShaders ];
        
        [ self makeInitialVertexCoordinates ];
        
        mTexture = [ self setupTexture : @"VU_Meter_Texture.png" ];

        [ self setupOpenGL ];
        
        [ self resetPhysics ];

        mIsActive = FALSE;
    }

    return self;
}

- (void)dealloc
{
    mGLContext = nil;
}


/////////////////////////////////////////////
//                                         //
//        EXPOSED INTERFACE SECTION        //
//                                         //
/////////////////////////////////////////////

-(void)setRMS : (unsigned short) rms andAbsMax : (unsigned short) absMax;
{
    mRMS    = rms;
    mAbsMax = absMax;
}


-(void)reset
{
    mRMS    = 0;
    mAbsMax = 0;
}


-(void)activate
{
    if ( !mIsActive ) {
        
        mDisplayLink =
            [ CADisplayLink displayLinkWithTarget : self
                                         selector : @selector( render: ) ];

        [ mDisplayLink addToRunLoop : [ NSRunLoop currentRunLoop ]
                            forMode : NSDefaultRunLoopMode           ];

        mIsActive = TRUE;

    }
}


-(void)deactivate
{
    if ( mIsActive ) {
        
        [ mDisplayLink invalidate ];
        mDisplayLink = nil;
        
        [ self reset ];

        mIsActive = FALSE;
    }
}





@end



