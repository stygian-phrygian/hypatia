# Hypatia

### What Is This?
- A sampler engine
- Written in CSound
- 1 file (main.csd)

## What Does It Do?
- It records sounds
- It plays back those sounds
- It can load existing sound files (.wavs) and play them
- It can tweak sounds during playback
- It can send the sounds through effects
- It can tweak the effects themselves during playback
- It uses OSC for controlling all this (MIDI is fun but too limited)

## Requirements
[Install CSound](http://csound.com/download.html)

## Quick Start
run: ` ./hypatia `
This script:
* boots CSound with `main.csd` and the necessary runtime constants
* opens the default audio input/output devices
* listens for CSound score data on port: 8080 and OSC address: "/score"
* creates a maximum of 16 Parts and 2 FXSend instruments

## Configuration
If you wanna change the:
* number of Parts created
* number of FXSends created
* sample rate or k-rate
* OSC port (for receiving OSC messages)
* hardware audio input device
* hardware audio output device
* other CSound specific options

Edit the script `hypatia` wherein the above mentioned variables are passed as flags to CSound.
See [this](http://www.csounds.com/manual/html/CommandFlags.html) for further info on flag configuration.
Though, I'd recommend you reconsider your life choices.
You can thank CSound for being so user friendly and configurable. ;)
If you'd like to turn off OSC listening, set `OSC_LISTEN_PORT=0`.

## Backstory
How much can one *single* csound file do?
It turns out quite a lot, though it involves high carbohydrate traditional italian cuisine.

## Usage
This application is controlled by sending CSound score data to it (after booting it up with ./hypatia)
The score data is transmitted through:
* OSC
* stdin pipe (if you use a unix-y system and pass -Lstdin as a flag (edit `hypatia` to do so))

The score data activates CSound instruments which resemble an API of sorts.
See the API below for further details on what the instruments can do.
The instruments are fairly high-level (ish) however probably not meant to be written by hand.
In fact, you *should* probably only use this within a wrapper language or application (which I'm working on maybe).
One can think of this as an audio backend perhaps for other things.
Or it's an exploration in masochism.

## Terminology
A sample is an audio recording.

A Part holds the playback state of a sample.
That is, a part is a sample and an associated group of parameters relevant for sample playback.
One can think of a Part like a track within a DAW (in a sense).
The parameters of the Part (sample amplitude, filter, distortion, etc.) are all realtime editable.

An FXSend represents a group of parameters relevant for further effects processing.
After a Part produces audio, the audio can be mixed into an FXSend.
Basically, it's an effects buss (common to most analog mixers).
Multiple Parts can mix their audio output simultaneously to one FXSend.
A Part can only mix with one FXSend at a time.

The Master receives the audio output of all the Parts and FXSends, and itself contains further effects.

## Signal Flow
Parts:
  * Parts -> Master
  * Parts -> FXSend -> Master

Audio Input:
  * Audio Input -> Master
  * Audio Input -> FXSend -> Master

The FXSend effects chain is:
  * 3-band EQ -> chorus -> delay -> ringmod -> bitcrusher -> distortion -> reverb -> compressor -> gain

The Master effects chain is:
  * 3-band EQ -> reverb -> distortion -> compressor -> gain

Recorded audio can come from the hardware audio input *or* from the Master output (ie. resampling).
Recorded audio can then be loaded into a sample slot (which should be set to a Part for playback)

Audio input can only come from 1 source currently (no multitrack recording).
Audio input can be monitored in real-time though.
Monitored audio input can either flow into master directly or through an FXSend (then master).

The parameters for the Parts, FXSends, Master can *all* be changed during playback.
Recording can happen during playback too.

## Current API:
Note, the current "API" if you will, is really a collection of CSound instruments.
The CSound instruments are controlled by score strings which follow the CSound score syntax, namely ["i statements"](http://www.csounds.com/manual/html/i.html).
Consulting the CSound documentation reveals, the instrument's name, startTime, duration are refered to as p1, p2, and p3 respectively.
p4, p5, p6.. etc, are the remaining arguments passed into the instrument (and for the following instruments) related to performance aspects.
Above each instrument is a comment regarding its arguments (not including p2 (startTime) and p3 (duration)).

* LoadSample
    * p4: sample slot  : Integer
    * p5: sample file  : String
    * ex: `i "LoadSample" 0 1 3 "909kick.wav"` (load 909kick.wav into slot 3 at time now (0))

* PlayPart
    * p4: part            : Integer
    * p5: semitone offset : Integer
    * ex: `i "PlayPart" 0 1 4 12"` (play part 4 with 12 semitone offset at time now (0) for duration 1)
    * nb: do not specify indefinite duration (numbers <= 0)

* RecordSample
    * p4: sample slot      : Integer {0 => don't load into a sample slot, 1 to N => load into slot N}
    * p5: recording source : Float   {0 => record from master,             not 0 => record from system audio input}
    * p6: filename         : String  {S => save recording to string S,        "" => auto-generate a file name}
    * ex: `i "RecordSample" 2 -1 12 1 ""` (2 seconds from now (for indefinite (-1) duration), record from audio in, into sample slot 12, autogenerating a fileName)

* StopRecording
    * ex: `i "StopRecording" 10 1` (10 seconds from now, stop recording)

* MonitorInput
    * p4: input audio destination : Integer {0 => master, N>0 => FXSend N }
    * ex: `i "MonitorInput" 0 -1 2` (send audio input (for indefinite duration) into fxsend 2)

* StopMonitoring
    * ex: `i "StopMonitoring" 0 1` (stop audio input monitoring now)

All the SetPartXXX instruments follow this syntax:
`i "SetPartXXX" startTime duration partNumber value`
* SetPartSample
* SetPartPitch
* SetPartAmp
* SetPartSampleOffset
* SetPartFilterCutoff
* SetPartFilterResonance
* SetPartFilterType
* SetPartDistortion
* SetPartPan
* SetLoopStart
* SetLoopEnd
* SetLoopOn
* SetPartReverse
* SetPartSendDestination
* SetPartSendWet
* SetPartAmpAttack
* SetPartAmpDecay
* SetPartAmpSustain
* SetPartAmpRelease
* SetPartModAttack
* SetPartModDecay
* SetPartModDepth
* SetPartModDestination

All the SetFXSendXXX instruments follow this syntax:
`i "SetFXSendXXX" startTime duration fxSendNumber value`
* SetFXSendEQGainLow
* SetFXSendEQGainMid
* SetFXSendEQGainHigh
* SetFXSendEQLowCornerFrequency
* SetFXSendEQMidPeakingFrequency
* SetFXSendEQHighCornerFrequency
* SetFXSendChorusDelayTime
* SetFXSendChordDepth
* SetFXSendChorusRate
* SetFXSendChorusFeedback
* SetFXSendChorusWet
* SetFXSendDelayLeftTime
* SetFXSendDelayLeftFeedback
* SetFXSendDelayRightTime
* SetFXSendDelayRightFeedback
* SetFXSendDelayWet
* SetFXSendRingModFrequency
* SetFXSendRingModDepth
* SetFXSendBitDepth
* SetFXSendSRFold
* SetFXSendDistortion
* SetFXSendReverbRoomSize
* SetFXSendReverbDamping
* SetFXSendReverbWet
* SetFXSendCompressorRatio
* SetFXSendCompressorThreshold
* SetFXSendCompressorAttack
* SetFXSendCompressorRelease
* SetFXSendCompressorGain
* SetFXSendGain

All the SetMasterXXX instruments follow this syntax:
`i "SetMasterXXX" startTime duration value`
* SetMasterEQGainLow
* SetMasterEQGainMid
* SetMasterEQGainHigh
* SetMasterEQLowCornerFrequency
* SetMasterEQMidPeakingFrequency
* SetMasterEQHighCornerFrequency
* SetMasterReverbRoomSize
* SetMasterReverbDamping
* SetMasterReverbWet
* SetMasterDistortion
* SetMasterCompressorRatio
* SetMasterCompressorThreshold
* SetMasterCompressorAttack
* SetMasterCompressorRelease
* SetMasterCompressorGain
* SetMasterGain
