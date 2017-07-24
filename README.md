
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
- It listens for csound score data on port: 5000 and url: "/score"

### Backstory:

I wanted to see just how much could be done in a *single* csound file.
It turns out quite a lot, though it involves a lot of questionable (convoluted) uses of csound.

### Usage:

This application is controlled by sending (csound) score data to it (via OSC).
The score data however is fairly high-level (ish).  The csound instruments
were designed to mimic an API in a sense.  One can think of this application as
an audio backend for making higher level musical applications tailored specifically for sampling.

### Current API:

"PlayPart" is responsible for initiating sample playback.  It takes a
Part# (which is an ftable#) to play a sample on (which is itself an ftable#).
It routes to an FXSend or Master.



### Terminology:

A sample is an audio recording.

A Part represents a group of parameters relevant for sample playback.
The current part DSP chain is:
TODO:

An FXSend represents a group of parameters relevant for further
sonic alteration (after the Part processes the audio). In other words,
it's basically an effects bus (common to most analog mixers).
Multiple parts can route their audio output simultaneously to one FXSend.
The current effects DSP chain in an FXSend is:
    3-band EQ -> chorus -> delay -> ringmod -> reverb -> bitcrusher -> compressor -> gain

All FXSends route to Master.  Master also has a DSP chain.
The current Master DSP chain is:
    3-band EQ -> reverb -> -> bitcrusher -> compressor -> gain

