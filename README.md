# Hypatia

### What Is This?
- A sampler engine
- Written in CSound
- 1 file

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
* stdin pipe (if you use a unix-y system and pass -Lstdin as a flag)
The score data activates CSound instruments which resemble an API of sorts.
See the API below for further details on what the instruments can do.
The instruments are fairly high-level (ish) however probably not meant to be written by hand.
In fact, you should probably only use this within a wrapper language or application (which I'm working on maybe).
One can think of this as an audio backend perhaps for other things.
Or it's an exploration in masochism.

## Terminology
A sample is an audio recording.

A Part holds the playback state of a sample.
That is, a part is a sample and an associated group of parameters relevant for sample playback.
One can think of a Part like a track within a DAW (in a sense)
The parameters of the Part (sample amplitude, filter, distortion, etc.) are all realtime editable.

An FXSend represents a group of parameters relevant for further effects processing
After a Part produces audio, the audio can be mixed into an FXSend.
Basically, it's an effects buss (common to most analog mixers).
Multiple Parts can mix their audio output simultaneously to one FXSend.
A Part can only mix with one FXSend at a time.

The Master receives the audio output of all the Parts and FXSends, and itself contains further effects.

## Signal Flow
Parts -> Master
*or*
Parts -> FXSend -> Master
*or*
Audio Input -> Master
*or*
Audio Input -> FXSend -> Master

The FXSend effects chain is:
    3-band EQ -> chorus -> delay -> ringmod -> reverb -> bitcrusher -> compressor -> gain

The Master effects chain is:
    3-band EQ -> reverb -> -> bitcrusher -> compressor -> gain

Recorded audio can come from the hardware audio input *or* from the Master output (ie. resampling).
Recorded audio can then be loaded into a sample slot (which should be set to a Part for playback)

Audio input can only come from 1 source currently.
Audio input can be monitored in real-time though.
Monitored audio input can either flow into master directly or through an FXSend (then master).

The parameters for the Parts, FXSends, Master can *all* be changed during playback.
Recording can happen during playback too.

## Current API:
- PlayPart     (NB. this instrument should not be triggered with indefinite duration)
- LoadSample
- RecordSample
- StopRecording
- MonitorInput
- StopMonitoring
- SetPartSample
- SetPartPitch
- SetPartAmp
- SetPartSampleOffset
- SetPartFilterCutoff
- SetPartFilterResonance
- SetPartFilterType
- SetPartDistortion
- SetPartPan
- SetPartTimestretchFactor
- SetPartTimestretchWindowSize
- SetPartReverse
- SetPartSendDestination
- SetPartSendWet
- SetPartAmpAttack
- SetPartAmpDecay
- SetPartAmpSustain
- SetPartAmpRelease
- SetPartEnv1Attack
- SetPartEnv1Decay
- SetPartEnv1Depth
- SetFXSendEQGainLow
- SetFXSendEQGainMid
- SetFXSendEQGainHigh
- SetFXSendEQLowCornerFrequency
- SetFXSendEQMidPeakingFrequency
- SetFXSendEQHighCornerFrequency
- SetFXSendChorusDelayTime
- SetFXSendChordDepth
- SetFXSendChorusRate
- SetFXSendChorusFeedback
- SetFXSendChorusWet
- SetFXSendDelayLeftTime
- SetFXSendDelayLeftFeedback
- SetFXSendDelayRightTime
- SetFXSendDelayRightFeedback
- SetFXSendDelayWet
- SetFXSendRingModFrequency
- SetFXSendReverbRoomSize
- SetFXSendReverbDamping
- SetFXSendReverbWet
- SetFXSendBitReduction
- SetFXSendCompressorRatio
- SetFXSendCompressorThreshold
- SetFXSendCompressorAttack
- SetFXSendCompressorRelease
- SetFXSendCompressorGain
- SetFXSendGain
- SetMasterEQGainLow
- SetMasterEQGainMid
- SetMasterEQGainHigh
- SetMasterEQLowCornerFrequency
- SetMasterEQMidPeakingFrequency
- SetMasterEQHighCornerFrequency
- SetMasterReverbRoomSize
- SetMasterReverbDamping
- SetMasterReverbWet
- SetMasterBitReduction
- SetMasterCompressorRatio
- SetMasterCompressorThreshold
- SetMasterCompressorAttack
- SetMasterCompressorRelease
- SetMasterCompressorGain
- SetMasterGain
