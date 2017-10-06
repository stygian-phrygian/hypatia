# SOCKS
#### Spaghetti OSC Csound Kludge Sampler
#ARKOSE
#### A really kludged osc sampler engine



### What This Is:
- This is a sampler
- It records sounds
- It plays back those sounds
- It can load existing sound files (.wavs) and play them
- It can tweak sounds during playback
- It can send the sounds through effects
- It can tweak the effects themselves during playback
- It uses OSC for controlling all this (MIDI is fun but too limited)

### Quick Start:
- csound main.csd
- It listens for csound score data on port: 8080 and url: "/score"

### Backstory:

How much can one *single* csound file do.
It turns out quite a lot, though it involves a number of questionable (convoluted) uses of csound.

### Usage:

This application is controlled by sending (csound) score data to it (via OSC).
The score data however is fairly high-level (ish).  The csound instruments
were designed to mimic an API in a sense.  One can think of this application as
an audio backend for making higher level musical applications tailored specifically for sampling.

### Terminology:

A sample is an audio recording.

A Part represents a group of parameters relevant for sample playback.
A Part plays back wav files that have been loaded by csound.

An FXSend represents a group of parameters relevant for further effects processing
(after a Part produces audio).
It's basically an effects buss (common to most analog mixers).
Multiple Parts can route their audio output simultaneously to one FXSend.
A Part can only route to one FXSend at a time.

The Master receives the audio output of all the Parts and FXSends.

###  Application Signal Flow
Parts -> Master -> speakers
*or*
Parts -> FXSend -> Master -> speakers

The FXSend effects chain is:
    3-band EQ -> chorus -> delay -> ringmod -> reverb -> bitcrusher -> compressor -> gain

The Master effects chain is:
    3-band EQ -> reverb -> -> bitcrusher -> compressor -> gain

Recorded audio can come from the hardware audio input *or* from the Master output (ie. resampling).
Recorded audio can then be loaded into a Part for playback.

Audio input can only come from 1 source currently.
Audio input can be monitored in real-time.
Monitored audio input can either flow into master directly or through an FXSend (then master).

The parameters for the Parts, FXSends, Master can *all* be changed during playback.
Recording can happen during playback too.

### Current API:

"PlayPart" is responsible for initiating sample playback.
It takes a Part# (integer between 1 & MAX_NUMBER_OF_PARTS) 

SetPartParameter
SetFXSendParameter
SetMasterParameter
LoadPartFromSample
RecordIntoPart
StopRecording
MonitorInput
StopMonitoring




