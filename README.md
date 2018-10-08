# iOS Realtime Audio Recorder with a Realistic VU Meter

![alt text](docs/readme/main_screen.png "Main Screen")
![alt text](docs/readme/play_screen.png "Play Screen")

Video:

[![alt text](docs/readme/youtube_thumbnail.png "Youtube Thumbnail")](https://youtu.be/LAM0Uln6PAQ)


# Highlights

* A working demo App in Xcode project.

* Realtime audio sampling and processing with CoreAudio

* Audio recorded to a wave file in 'Documents' directory.

* Framework for heavy background tasks such as speech recognition

* Realistic VU meter in OpenGL

* Brief playback and NIST SNR estimator


# Description

  This App was originally made to demonstrate how to sample audio input in
realtime using a low level API available in iOS, which has been CoreAudio.
There are some high level APIs but they don't provide finer control and access
to the audio input.
As far as I know, CoreAudio's AudioUnit and Audio Queue are the only two APIs
that provide audio in chunks.
However, according to my chat with a CoreAudio engineer at Apple Cupertino
a few years ago, the latter would not be suitable for realtime update.
E.g.) the callback timing to render audio chunks can be irregular and delayed.
Assuming it is correct, this leaves AudioUnit the only choice to process audio
inputs in chunks in realtime.
To use AudioUnit, you need help from AVAudioSession to get/set the current 
audio configuration.
In the application those functionalities are comopactly implemented in
AudioInputManager.{h,m}.

  To demonstrate realtime audio sampling, I have implemented a nice realistic
VU meter with OpenGL whose hand moves according to a physical model.
On my iPhone 6+/iOS 12.0, the audio render callback is called quite regularly
at around 50 Hz (1024 samples @48000 sample rate for the front internal mic).
It is moves at the OpenGL frame rate but the current energy info gets updated
at the rate of the AudioUnit callbacks, which is 
The VU meter is implemented as a UIView in VUMeterViewGL.{h.m} with 
accompanying texture PNG file and the two tiny shaders.

  The recording to a file is treated as a slow heavy task to demonstrate
how to handle such a task, which can lag behing real-time, in a separate
back ground thread.
During a recording the raw audio that comes in chunks get accummulated to a 
temporary file.
At the end of recording, the raw audio is converted to a wav file with RIFF 
header.
The handling of background task is generalized in SlowTaskManager.{h,m} that 
utilizes iOS's very covenient Dispatch Queue mechanism.
The actual file access is done by its subclass SlowTaskWaveWriter.{h,m}.
I have also implemented another base class SlowTaskManagerPosix.{h,m}, which
does not use Dispatch Queue, but use the POSIX primitives such as pthread and
condvar.
It was taken from my old code for an old bare-bone embedded system to which
I was implementing an ASR task.
I just wanted to see how the POSIX primitives work on the latest iOS.

  To check the wave file recorded, I have implemented a brief playback
mechanism using a high level API, AVAudioPlayer.
It draws the wave shape on the screen, and gives some info about the file,
such as SNR, which is estimated by NIST algorithm.
The playback part is implemented as a UIViewController,
"PlayWaveViewController.{h,m}.

It has a bare minimum functionality, but adding some more UIs such as
file name selection, and some error and external event handling to make
it more robust, it can be easily elaborated to a real usable App.


# Issues and Limitations

* The file name of the recorded audio is fixed.
The App is eastily made more flexible with some additional file name
selection/entering UI.

* Proper external event handling currently not implemented.

Ex. Plugging a USB or Bluetooth Mic is internally detected,
but the main screen will not be udpated.
The App is easily modifiable for more proper error and external event handling.
