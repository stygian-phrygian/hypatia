# Hypatia

### What Is This?
- A sampler
- Written in csound
- 1 file

## What Does It Do?
- It records sounds
- It plays back those sounds
- It can load existing sound files (.wavs) and play them
- It can tweak sounds during playback
- It can send the sounds through effects
- It can tweak the effects themselves during playback
- It uses OSC for controlling all this (MIDI is fun but too limited)

## Quick Start:
run:
csound main.csd

It listens for csound score data on port: 8080 and url: "/score"
If you wanna change which port and url it uses I'd recommend you reconsider your life choices.
If you wanna change which hardware device audio input comes from (see above sentence).

## Backstory:
How much can one *single* csound file do?
It turns out quite a lot, though it involves high carbohydrate traditional italian cuisine.

## Usage:
This application is controlled by sending (csound) score data to it (via OSC).
The score data however is fairly high-level (ish).
The csound instruments were designed to mimic an API in a sense.
One can think of this application as an audio backend perhaps for other things.
Or it's an exploration in masochism.

## Terminology:
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
PlayPart     (NB. this instrument should not be triggered with indefinite duration)
LoadSample
RecordSample
StopRecording
MonitorInput
StopMonitoring
SetPartSample
SetPartPitch
SetPartAmp
SetPartSampleOffset
SetPartFilterCutoff
SetPartFilterResonance
SetPartFilterType
SetPartDistortion
SetPartPan
SetPartTimestretchFactor
SetPartTimestretchWindowSize
SetPartReverse
SetPartSendDestination
SetPartSendWet
SetPartAmpAttack
SetPartAmpDecay
SetPartAmpSustain
SetPartAmpRelease
SetPartEnv1Attack
SetPartEnv1Decay
SetPartEnv1Depth
SetFXSendEQGainLow
SetFXSendEQGainMid
SetFXSendEQGainHigh
SetFXSendEQLowCornerFrequency
SetFXSendEQMidPeakingFrequency
SetFXSendEQHighCornerFrequency
SetFXSendChorusDelayTime
SetFXSendChordDepth
SetFXSendChorusRate
SetFXSendChorusFeedback
SetFXSendChorusWet
SetFXSendDelayLeftTime
SetFXSendDelayLeftFeedback
SetFXSendDelayRightTime
SetFXSendDelayRightFeedback
SetFXSendDelayWet
SetFXSendRingModFrequency
SetFXSendReverbRoomSize
SetFXSendReverbDamping
SetFXSendReverbWet
SetFXSendBitReduction
SetFXSendCompressorRatio
SetFXSendCompressorThreshold
SetFXSendCompressorAttack
SetFXSendCompressorRelease
SetFXSendCompressorGain
SetFXSendGain
SetMasterEQGainLow
SetMasterEQGainMid
SetMasterEQGainHigh
SetMasterEQLowCornerFrequency
SetMasterEQMidPeakingFrequency
SetMasterEQHighCornerFrequency
SetMasterReverbRoomSize
SetMasterReverbDamping
SetMasterReverbWet
SetMasterBitReduction
SetMasterCompressorRatio
SetMasterCompressorThreshold
SetMasterCompressorAttack
SetMasterCompressorRelease
SetMasterCompressorGain
SetMasterGain

