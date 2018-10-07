# iOS Realtime Audio Recorder with a Realistic VU Meter

![alt text](docs/readme/main_screen.png "Main Screen")
![alt text](docs/readme/play_screen.png "Play Screen")

Video:

[![alt text](docs/readme/youtube_thumbnail.png "Youtube Thumbnail")](https://youtu.be/LAM0Uln6PAQ)


# Overview

* A working demo App in Xcode project.

* Realtime audio sampling and processing with CoreAudio

* Audio recorded to a wave file in 'Documents' directory.

* Framework for heavy background tasks such as speech recognition

* Realistic VU meter in OpenGL

* Brief playback and NIST SNR estimator


# Description


# Issues and Limitations

* Proper external event handling missing.

Ex. Plugging a USB or Bluetooth Mic is internally detected,
but the main screen will not be udpated.
