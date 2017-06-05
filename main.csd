
; This is a sampler
; It records sounds
; It plays back those sounds
; It can load existing sound files and play them too
; It can tweak sounds during playback
; It can also send the sounds to effects busses
; It can save a bunch of sounds to a project directory
; It uses OSC for controlling all this (MIDI is fun but too limited)
; It receives csound score data on the OSC port and url of '/score'


<CsoundSynthesizer>
<CsOptions>
; Select audio/midi flags here according to platform
;;-odac   -i adc:hw:1,0   ;;;realtime audio I/O
;;-odac   -i adc:hw:2,0  ;;;realtime audio I/O
;;-odac -+rtaudio=alsa -i adc:hw:2,0
;;-odac -iadc:hw:2,0

; realtime output
-odac

; realtime input (will need configuring)
-iadc
;-iadc:hw:2,0 ; (my zoom h2n usb microphone)

</CsOptions>
<CsInstruments>

sr	=	44100 ; 48000 makes csound explode UNDERRUNS with -iadc for whatever reason
ksmps	=	32
nchnls	=	2
0dbfs	=	1

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Terminology:
;
; A Sample is an audio recording.  In Csound this is represented as a pair
; of ftables (due to implentation details below) ie left and right stereo
; channels or a duplication of a mono channel.

; A "Part" represents a group of parameters relevant for sample playback.
; A part is an ftable.
;
; An FXSend represents a group of parameters relevant for further
; sonic alteration (after the Part processes the audio). In other words,
; it's an effect bus common to most analog mixers.  Multiple
; parts can route the audio simultaneously to one.
; An FXSend instrument has a corresponding ftable to hold its state.
; The current DSP chain is: delay -> ringmod -> reverb -> bitcrusher -> compressor
;
; All FXSends route to Master.  Master also has a DSP chain too.
; The current DSP chain is: equalizer -> reverb -> compressor
;
; A project is a collection of sample files in a directory which
; this application knows how to reassign to Parts.
; There can be a max of $MAX_NUMBER_OF_PARTS samples per project.
;
; "PlayPart" is responsible for initiating sample playback.  It takes a 
; Part# (which is an ftable#) to play a sample on (which is itself an ftable#).
; It routes to an FXSend or Master.
;
; Samples, Parts, FXSends, and Master are represented by ftables so we must be careful of
; incorrect indexing when PlayPart is called.  Ftables are laid out in
; in memory thusly:
;
; Ftable #:
; [1-128]   : Parts
; [129-130] : FXSends
; [131]     : Master
; [131-N]   : Sample Ftables [mono pairs]
;
; assuming MAX_NUMBER_OF_PARTS == 128
;	   MAX_NUMBER_OF_FX_SEND == 2
;
;


#define MAX_NUMBER_OF_PARTS		#128#
#define MAX_NUMBER_OF_FX_SEND		#2#

; ftable offset indices
#define PART_FTABLE_OFFSET              #1#
#define FX_SEND_FTABLE_OFFSET           #$MAX_NUMBER_OF_PARTS + 1#
#define MASTER_FTABLE_OFFSET		#$MAX_NUMBER_OF_PARTS + $MAX_NUMBER_OF_FX_SEND + 1#
#define SAMPLE_FTABLE_OFFSET            #$MASTER_FTABLE_OFFSET + 1#

; zak busses (for routing a-rate data out of PlayPart into FXSend)
#define NUMBER_OF_ZAK_AUDIO_CHANNELS	#2 * $MAX_NUMBER_OF_FX_SEND#
#define zak_dummy_variable #$NUMBER_OF_ZAK_AUDIO_CHANNELS#
zakinit ($NUMBER_OF_ZAK_AUDIO_CHANNELS) , ($zak_dummy_variable)

; master audio left & right
gamastersigl		init 0
gamastersigr		init 0

; osc network
giosclistenport		init 5000
gioscsendport		init 5001
giosclistenhandle	OSCinit giosclistenport


; part state
#define NUMBER_OF_PARAMETERS_PER_PART	#32#
; part parameter indices (we need indices because parts are just ftables... csound is low level bro, we doin' objects son)
; part parameters 
#define PART_SAMPLE			#0#
#define PART_PITCH			#1#
#define PART_AMP			#2#
#define PART_SAMPLE_OFFSET		#3#	; 0: start, 1: end
#define PART_FILTER_CUTOFF		#4#
#define PART_FILTER_RESONANCE		#5#
#define PART_FILTER_TYPE		#6#	; 0: none, 1: lp, 2: hp, 3: bp
#define PART_PAN			#7#
#define PART_DETUNE_SPREAD		#8#
#define PART_DISTORTION_AMOUNT		#9#
#define PART_TIMESTRETCH_FACTOR		#10#
#define PART_TIMESTRETCH_WINDOW_SIZE	#11#	; nice window size? 0.002205
#define PART_STEP_NUDGE			#12#	; unused 
#define PART_GATE			#13#	; unused
#define PART_BUS_DESTINATION		#14#	; 0:  master, >0: fx bus
; part parameters - modulation 
#define PART_AMP_ATTACK			#17#
#define PART_AMP_DECAY			#18#
#define PART_AMP_SUSTAIN_LEVEL		#19#
#define PART_AMP_RELEASE		#20#
#define PART_ENV1_ATTACK		#21#
#define PART_ENV1_DECAY			#22#
#define PART_ENV1_DEPTH			#23#
#define PART_ENV1_DESTINATION		#24#	; 0: pitch, 1: filter-cutoff, 2: pitch & filter-cutoff


; fx send state
#define NUMBER_OF_PARAMETERS_PER_FX_SEND	#32#
;
#define FX_SEND_INPUT_LEFT			#0# ; <--- currently unused (due to zak channel implementation below)
#define FX_SEND_INPUT_RIGHT			#1# ; <---
;
#define FX_SEND_DELAY_LEFT_TIME			#2#
#define FX_SEND_DELAY_LEFT_FEEDBACK		#3#
#define FX_SEND_DELAY_RIGHT_TIME		#4#
#define FX_SEND_DELAY_RIGHT_FEEDBACK		#5#
#define FX_SEND_DELAY_WET			#6#
#define FX_SEND_RING_MOD_FREQUENCY		#7#
;
#define FX_SEND_REVERB_ROOM_SIZE		#8#
#define FX_SEND_REVERB_DAMPING			#9#
#define FX_SEND_REVERB_WET			#10#
#define FX_SEND_BIT_REDUCTION			#11#
;
#define FX_SEND_COMPRESSOR_RATIO		#12# 
#define FX_SEND_COMPRESSOR_THRESHOLD		#13#
#define FX_SEND_COMPRESSOR_ATTACK		#14#
#define FX_SEND_COMPRESSOR_RELEASE		#15#
#define FX_SEND_SIDE_CHAIN_SOURCE		#16#
#define FX_SEND_GAIN				#17#


; master state 
#define NUMBER_OF_PARAMETERS_PER_MASTER #16#
;
#define MASTER_EQ_GAIN_LOW		 #0#
#define MASTER_EQ_GAIN_MID		 #1#
#define MASTER_EQ_GAIN_HIGH		 #2#
#define MASTER_EQ_LOW_CORNER_FREQUENCY	 #3#
#define MASTER_EQ_MID_PEAKING_FREQUENCY	 #4#
#define MASTER_EQ_HIGH_CORNER_FREQUENCY	 #5#
#define MASTER_REVERB_ROOM_SIZE	         #6#
#define MASTER_REVERB_DAMPING		 #7#
#define MASTER_REVERB_WET		 #8#
#define MASTER_BIT_REDUCTION		 #9#
#define MASTER_COMPRESSOR_RATIO		 #10# 
#define MASTER_COMPRESSOR_THRESHOLD	 #11#
#define MASTER_COMPRESSOR_ATTACK	 #12#
#define MASTER_COMPRESSOR_RELEASE	 #13#
#define MASTER_GAIN			 #14#

; instrument which listens for score data
;
; NB. I tried making seperate instruments which listened for seperate 
; "things" (ie. LoadPartFromSample, RecordIntoPart, PlayPart, etc) but 
; this created extremely weird timing issues.  Therefore, there's now only
; one OSC input port which listens for csound score data.
instr +OSCScoreListener
Sscore			strcpy ""
nextscore:
kscorereceived		OSClisten giosclistenhandle, "/score", "s", Sscore
			if (kscorereceived == 0) kgoto donescore
				printks "[OSC] received score:\n", 0
				printks Sscore, 0
				printks "\n", 0
				scoreline Sscore, 1
				kgoto nextscore
donescore:
endin

instr +InitializePart

	iftablenumber	init p4
			tabw_i $SAMPLE_FTABLE_OFFSET      , $PART_SAMPLE                  , iftablenumber
			tabw_i 1			  , $PART_PITCH			  , iftablenumber
			tabw_i 1                          , $PART_AMP                     , iftablenumber
			tabw_i 0                          , $PART_SAMPLE_OFFSET           , iftablenumber
			tabw_i 0.3                        , $PART_FILTER_CUTOFF           , iftablenumber
			tabw_i 0.2                        , $PART_FILTER_RESONANCE        , iftablenumber
			tabw_i 0                          , $PART_FILTER_TYPE             , iftablenumber
			tabw_i 0.5                        , $PART_PAN                     , iftablenumber
			tabw_i 0.0			  , $PART_DETUNE_SPREAD           , iftablenumber
			tabw_i 1                          , $PART_TIMESTRETCH_FACTOR      , iftablenumber
			tabw_i 0.05                       , $PART_TIMESTRETCH_WINDOW_SIZE , iftablenumber
			tabw_i 1                          , $PART_GATE                    , iftablenumber
			tabw_i 1                          , $PART_AMP_SUSTAIN_LEVEL       , iftablenumber
			tabw_i 1                          , $PART_ENV1_DEPTH              , iftablenumber
			
			prints "initialized Part on ftable # %d\n", iftablenumber

			turnoff
endin

instr +CreatePart

irequestedftablenumber	init p4
iftablesize		init $NUMBER_OF_PARAMETERS_PER_PART 
itime			init 0
igenroutine		init 2

			prints "requested allocation of a Part on ftable # %d\n", irequestedftablenumber
icreatedftablenumber	ftgen irequestedftablenumber, itime, iftablesize, igenroutine,  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 ; <--- only one 0 is necessary apparently 
			prints "allocated a Part on ftable # %d\n", icreatedftablenumber

			event_i "i", "InitializePart", 0, -1, icreatedftablenumber

			turnoff

endin

instr +CreateAllParts

	ipart		init 1
	next_part:
			event_i "i", "CreatePart", 0, -1, ipart
	ipart		+= 1
			if ( ipart <= $MAX_NUMBER_OF_PARTS ) igoto next_part
			turnoff
		
endin
turnon nstrnum("CreateAllParts")



instr +InitializeFXSend

	iftablenumber	init p4
			tabw_i 0, $FX_SEND_INPUT_LEFT , iftablenumber
			tabw_i 0, $FX_SEND_INPUT_RIGHT , iftablenumber
			;
			tabw_i 0.18, $FX_SEND_DELAY_LEFT_TIME , iftablenumber
			tabw_i 0.5, $FX_SEND_DELAY_LEFT_FEEDBACK , iftablenumber
			tabw_i 0.025, $FX_SEND_DELAY_RIGHT_TIME , iftablenumber
			tabw_i 0.3, $FX_SEND_DELAY_RIGHT_FEEDBACK , iftablenumber
			tabw_i 0, $FX_SEND_DELAY_WET , iftablenumber
			tabw_i 0, $FX_SEND_RING_MOD_FREQUENCY , iftablenumber
			;
			tabw_i 0.3, $FX_SEND_REVERB_ROOM_SIZE , iftablenumber
			tabw_i 0.8, $FX_SEND_REVERB_DAMPING , iftablenumber
			tabw_i 0, $FX_SEND_REVERB_WET , iftablenumber
			tabw_i 0, $FX_SEND_BIT_REDUCTION , iftablenumber
			;
			tabw_i 0, $FX_SEND_COMPRESSOR_RATIO , iftablenumber
			tabw_i 0, $FX_SEND_COMPRESSOR_THRESHOLD , iftablenumber
			tabw_i 0.1, $FX_SEND_COMPRESSOR_ATTACK , iftablenumber
			tabw_i 0.2, $FX_SEND_COMPRESSOR_RELEASE , iftablenumber
			tabw_i 0, $FX_SEND_SIDE_CHAIN_SOURCE , iftablenumber
			tabw_i 1, $FX_SEND_GAIN , iftablenumber
			
			prints "initialized FXSend on ftable # %d\n", iftablenumber

			turnoff
endin

instr +CreateFXSend

irequestedftablenumber	init p4
iftablesize		init $NUMBER_OF_PARAMETERS_PER_FX_SEND
itime			init 0
igenroutine		init 2

			prints "requested allocation of a FXSend on ftable # %d\n", irequestedftablenumber
icreatedftablenumber	ftgen irequestedftablenumber, itime, iftablesize, igenroutine,  0 ; <--- only one 0 is necessary apparently 
			prints "allocated a FXSend on ftable # %d\n", icreatedftablenumber

			event_i "i", "InitializeFXSend", 0, -1, icreatedftablenumber

			turnoff

endin

instr +CreateAllFXSends

	ifxsend		init $FX_SEND_FTABLE_OFFSET
	next_fxsend:
			event_i "i", "CreateFXSend", 0, -1, ifxsend
	ifxsend		+= 1
			if ( ifxsend < $FX_SEND_FTABLE_OFFSET + $MAX_NUMBER_OF_FX_SEND ) igoto next_fxsend
			turnoff
		
endin
turnon nstrnum("CreateAllFXSends")



instr +InitializeMaster

	iftablenumber	init p4
			tabw_i 1, $MASTER_EQ_GAIN_LOW , iftablenumber
			tabw_i 1, $MASTER_EQ_GAIN_MID , iftablenumber
			tabw_i 1, $MASTER_EQ_GAIN_HIGH , iftablenumber
			tabw_i 180, $MASTER_EQ_LOW_CORNER_FREQUENCY , iftablenumber
			tabw_i 1000, $MASTER_EQ_MID_PEAKING_FREQUENCY , iftablenumber
			tabw_i 9000, $MASTER_EQ_HIGH_CORNER_FREQUENCY , iftablenumber
			tabw_i 0.4, $MASTER_REVERB_ROOM_SIZE , iftablenumber
			tabw_i 0.7, $MASTER_REVERB_DAMPING , iftablenumber
			tabw_i 0, $MASTER_REVERB_WET , iftablenumber
			tabw_i 0, $MASTER_BIT_REDUCTION , iftablenumber
			tabw_i 0, $MASTER_COMPRESSOR_RATIO , iftablenumber
			tabw_i 0, $MASTER_COMPRESSOR_THRESHOLD , iftablenumber
			tabw_i 0, $MASTER_COMPRESSOR_ATTACK , iftablenumber
			tabw_i 0, $MASTER_COMPRESSOR_RELEASE , iftablenumber
			tabw_i 1, $MASTER_GAIN , iftablenumber
			
			prints "initialized Master on ftable # %d\n", iftablenumber

			turnoff
endin

instr +CreateMaster

irequestedftablenumber	init $MASTER_FTABLE_OFFSET
iftablesize		init $NUMBER_OF_PARAMETERS_PER_MASTER
itime			init 0
igenroutine		init 2

			prints "requested allocation of a Master on ftable # %d\n", irequestedftablenumber
icreatedftablenumber	ftgen irequestedftablenumber, itime, iftablesize, igenroutine,  0 ; <--- only one 0 is necessary apparently 
			prints "allocated a Master on ftable # %d\n", icreatedftablenumber

			event_i "i", "InitializeMaster", 0, -1, icreatedftablenumber

			turnoff

endin
turnon nstrnum("CreateMaster")

instr +LoadSample
; args: ftable number, filename
;
; NB. never call this function directly.  Use LoadPartFromSample which will take care of
; ftable memory layout (otherwise the results could be quite... dangerous).

iftn		init p4
Sfilename	init p5

		; determine how many channels are in our sample file
inchnls		filenchnls Sfilename

		; mono file loads into iftn and iftn+1
		; stereo file loads left and right channels into iftn and iftn+1 respectively
		if (inchnls == 1) then
				prints "Loading mono sample into ftable # %d & %d respectively\n", iftn, iftn+1
			gir	ftgen iftn  , 0, 0, 1, Sfilename, 0, 0, 0
			gir	ftgen iftn+1, 0, 0, 1, Sfilename, 0, 0, 0
		elseif (inchnls == 2) then
				prints "Loading stereo sample left and right channels into ftable # %d & %d respectively\n", iftn, iftn+1
			gir	ftgen iftn  , 0, 0, 1, Sfilename, 0, 0, 1	; <--- left channel
			gir	ftgen iftn+1, 0, 0, 1, Sfilename, 0, 0, 2	; <--- right channel
		else
				prints "Cannot load sample (unsupported number of channels)\n"
		endif

		turnoff
endin

instr +LoadPartFromSample
ipartnumber	init p4		; [ 1 - $MAX_NUMBER_OF_PARTS ]
Sfilename	init p5

	; check that this part exists
	if (ipartnumber < 1 || ipartnumber > $MAX_NUMBER_OF_PARTS) then
		prints "Cannot load sample into nonexistent part #: %d\n", ipartnumber
		turnoff
	endif

	itrueftableindex	init $SAMPLE_FTABLE_OFFSET + ((ipartnumber - 1) * 2)
	Sfstatement		sprintfk {{i "LoadSample" 0 -1 %d "%s"}}, itrueftableindex, Sfilename
				scoreline Sfstatement, 1
				tabw_i itrueftableindex, $PART_SAMPLE , ipartnumber
				turnoff
endin

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; usage
; asig PlayTable iftn, kpitch, ioffset, kloopsize
;	where:	iftn is the ftable #
;		kpitch is pitch ratio (0 - inf)
;		ioffset   [0 - 1) start playback here
;		kloopstart [0 - 1)
;		kloopend [0 - 1) (kloopend == 0 means no-looping)
;
;	cool hack: turn into an even number x := x & (~1)
opcode PlayTable, a, ikikk
				setksmps 1
iftn, kpitch, ioffset, kloopstart, kloopend	xin
			asig	init 0

		imaxtableindex	init tableng(iftn) - 1
		kindex		init ioffset * imaxtableindex

				; determine table index bounds
				
				; if looping
				if ((kloopend > 0) && (kloopend < 1)) then
					; calculate loop points
					kloopstartindex   = (kloopstart > 0) ? kloopstart * imaxtableindex : 0
					kloopendindex	  = (kloopend > kloopstart) ?  kloopend * imaxtableindex : imaxtableindex
					koutofboundsindex = kloopendindex
				; else not looping
				else
					koutofboundsindex = imaxtableindex
				endif
				
				; if table index is within our determined bounds (looping or not)
				if(kindex <= koutofboundsindex) then
							; read table value
					asig		tab int(kindex), iftn
							; update index (according to pitch)	
					kindex		+= (kpitch > 0) ? kpitch : 0.001
				; else if out of bounds and looping?
				elseif (kloopend > 0) then
							; reset index to start of loop index
					kindex		= kloopstartindex 
				; else out of bounds and *not* looping
				else
							; output zeros
					asig		= 0
				endif

				xout asig
endop


; ADSR envelope which operates with k-rate arguments
; the existing envelop opcodes have only i-time arguments which won't suffice for realtime tweaking)
; hence we must create our own
opcode kmadsr, k, kkkk

			
kampattack, kampdecay, kampsustainlevel, kamprelease	xin

	kcurrenttimeinseconds			timeinsts
	kreleased				release

						; the following few variables are all related to the release stage of our envelope
	iamprelease				init i(kamprelease)
	iampsustainlevel			init i(kampsustainlevel)
	kreleasestagestarted			init 0


	; release stage
	if ( kreleasestagestarted == 1 ) then
						; create the release envelope (fall to 0 value)
		kampenvelope			line iampsustainlevel, iamprelease, 0.0001


	; attack stage (rise to kamp level)
	elseif ( kcurrenttimeinseconds <= kampattack && kampattack > 0) then
	
		kampenvelope			= kcurrenttimeinseconds / kampattack

	; decay stage (fall to sustain level)
	elseif ( (kcurrenttimeinseconds <= (kampattack + kampdecay)) && kampdecay > 0 ) then

					; scale amp sustain level such that 0 <= sustain level <= 1
		kampsustainlevel		scale kampsustainlevel, 1, 0

		kcomplementarylevel		= 1 - kampsustainlevel 
		kcomplementarylevelscalefactor	= kcurrenttimeinseconds / (kampattack + kampdecay)
		kampenvelope			= 1 - (kcomplementarylevel * kcomplementarylevelscalefactor)

	; check if we released and determine values for release
	; (we should only enter this block once)
	elseif ( kreleased == 1 && kamprelease > 0 ) then
		

						; flag that we started the release stage
						; (this allows us to skip the above envelope stages each k-rate pass
						; as well as make sure we only release once)
		kreleasestagestarted		= 1

						; perform a reinitialization pass to ascertain 
						; the current value of kamprelease & kampsustainlevel
						; as well as grant our instrument extra time to perform this release
						reinit  reinit_for_release
		reinit_for_release:
		
						; get current i-values for the respective k-values of release and sustain
		iamprelease			init i(kamprelease)
		iampsustainlevel		init i(kampsustainlevel)

						; give our instrument extratime for the release envelope
						xtratim iamprelease

						; finish reinitialization pass
						rireturn

	; sustain stage
	else
		kampenvelope			= kampsustainlevel

	endif



		
						xout kampenvelope
endop

;
; Warning: the following "Setter" instruments 
; do *no* bounds checking for invalid ftable numbers
;

instr +SetPartParameter
ipartnumber		init p4		; 1 - $MAX_NUMBER_OF_PARTS
ipartparameter		init p5
iparametervalue		init p6
			tabw_i iparametervalue, ipartparameter, ipartnumber
			turnoff
endin

instr +SetFXSendParameter
iftablenumber		init p4 + ($FX_SEND_FTABLE_OFFSET) - 1	; 1 - $MAX_NUMBER_OF_FX_SEND
iparameter		init p5
iparametervalue		init p6
			tabw_i iparametervalue, iparameter, iftablenumber
			turnoff
endin

instr +SetMasterParameter
iftablenumber		init $MASTER_FTABLE_OFFSET 
iparameter		init p4
iparametervalue		init p5
			tabw_i iparametervalue, iparameter, iftablenumber
			turnoff
endin

instr +PlayPart
; playback of a sample (ftable) with an existing part's state (which is also an ftable)

reinitialize_instrument:	; <--- reinitialization label, for use if we change part parameters
				;      which are represented as i-values 
				;      (due to the constraints of certain opcodes within this instrument)
				;      therefore requiring a reinitialization pass

ipartnumber		init p4


			; grab snapshot of current part state 
			; all the p-values are relative values to whatever the part currently has
			; as such, we can edit the part parameters in realtime with realtime reflection of changes (for most but not all)
			; all the i-values can be edited during playback but won't reflect changes until the part is retriggered
isamplenumber		tab_i $PART_SAMPLE , ipartnumber

			prints "playing ftables: %d & %d on part # %d\n", isamplenumber, isamplenumber+1, ipartnumber

			; -- realtime editable parameters --
kpitch			tab $PART_PITCH			    , ipartnumber
kamp			tab $PART_AMP                       , ipartnumber
kfiltercutoff		tab $PART_FILTER_CUTOFF             , ipartnumber 
kfilterresonance	tab $PART_FILTER_RESONANCE          , ipartnumber 
kfiltertype		tab $PART_FILTER_TYPE               , ipartnumber 
kpan			tab $PART_PAN                       , ipartnumber 
kdetunespread		tab $PART_DETUNE_SPREAD             , ipartnumber 
kdistortionamount	tab $PART_DISTORTION_AMOUNT         , ipartnumber 
kbusdestination		tab $PART_BUS_DESTINATION           , ipartnumber
			; -- realtime editable parameters
			; -- but are i-values in the instrument therefore
			; -- changing them causes instrument reinitialization
			; -----------------------------------------------
ksampleoffset		tab $PART_SAMPLE_OFFSET             , ipartnumber
isampleoffset		init i(ksampleoffset)	
ktimestretchfactor	tab   $PART_TIMESTRETCH_FACTOR      , ipartnumber
itimestretchfactor	init i(ktimestretchfactor)
ktimestretchwindowsize	tab   $PART_TIMESTRETCH_WINDOW_SIZE , ipartnumber
itimestretchwindowsize	init i(ktimestretchwindowsize)
;istepnudge		tab_i $PART_STEP_NUDGE              , ipartnumber
;igate			tab_i $PART_GATE                    , ipartnumber
			; -----------------------------------------------
			; -- realtime editable modulation --
kampattack		tab $PART_AMP_ATTACK                , ipartnumber
kampdecay		tab $PART_AMP_DECAY                 , ipartnumber
kampsustainlevel	tab $PART_AMP_SUSTAIN_LEVEL         , ipartnumber
kamprelease		tab $PART_AMP_RELEASE               , ipartnumber
kenv1attack		tab $PART_ENV1_ATTACK               , ipartnumber
kenv1decay		tab $PART_ENV1_DECAY                , ipartnumber
kenv1depth		tab $PART_ENV1_DEPTH                , ipartnumber
kenv1destination	tab $PART_ENV1_DESTINATION          , ipartnumber
			
			; if user changed sample offset in realtime, reinit this instrument
			if ( ksampleoffset != isampleoffset ) then
				reinit reinitialize_instrument
			endif

			; if user changed timestretch factor/windowsize in realtime, reinit this instrument
			if ( ktimestretchfactor != itimestretchfactor || ktimestretchwindowsize != itimestretchwindowsize ) then
				reinit reinitialize_instrument
			endif
			
			; create amp envelope
kampenvelope		kmadsr kampattack, kampdecay, kampsustainlevel, kamprelease

			; scale amp envelope
kampenvelope		*= kamp

			; create env1 (assignable) envelope (this has just attack and decay)
kenv1envelope		kmadsr kenv1attack, kenv1decay, 0, 0

			; scale env1envelope by env1depth
			; env1depth must be > 1 or < -1 to have any effect
			; the original env1 : [ 0 - 1 ]
			; the scaled env1   : [ 1 - env1depth ] or [env1depth - -1]
			;
			; handle positive depth
			if(kenv1depth >= 1) then 
				kenv1envelope	*= (kenv1depth - 1)
				kenv1envelope	+= 1
			; handle negative depth
			elseif(kenv1depth <= -1) then
				kenv1envelope	*= (-1 - kenv1depth)
				kenv1envelope	-= 1
			; handle invalid depth (between -1 and 1)
			else
				kenv1envelope = 1
			endif

			; determine playback speed
isamplesr		init ftsr(isamplenumber); sample's original sample rate
isrfactor		init (isamplesr/sr)	; sample rate factor to correct for mismatched csound and sound file sample rates
kplaybackspeed		= isrfactor * kpitch

			; determine whether to apply pitch envelope
			if(kenv1destination == 0 || kenv1destination == 2 && kenv1depth != 1) then
				kplaybackspeed	*= kenv1envelope
			endif

			; initialize loop points (for PlayTable opcode) in case we want to timestretch
kloopstart		init isampleoffset
kloopend		init 0			; NB. iloopend == 0 ---> no looping


			; determine which ftables our PlayTable opcode is reading from
ileftchannel		init isamplenumber
irightchannel		init isamplenumber + 1


			; check whether timestretch is on (and apply it if so)
			if(itimestretchfactor > 0 && itimestretchfactor != 1 && itimestretchwindowsize > 0) then


				insampleframes		init nsamp(isamplenumber)	; sample's length (in sample frames)
				ioriginalsampleduration	init isrfactor            * (insampleframes / sr) 
				itimestretchduration	init itimestretchfactor   *  ioriginalsampleduration
				itimestretchduration	init itimestretchduration - (isampleoffset * ioriginalsampleduration)

							; modulate sample looppoints to simulate (shitty) timestretch effect
				kline			line isampleoffset, itimestretchduration, 1
				kloopstart		= kline
				kloopend		= kline + itimestretchwindowsize
			endif

			; determine detuned playback speed
kdetunedplaybackspeed	= kplaybackspeed + (kdetunespread * 0.059463094)	; 1.059463094 ~ 2**(1/12)

			; create left and right pitch playback jitter
kjitteramp		= 0.0007 * kdetunespread
kjitterl		jitter kjitteramp, 0.04, 0.80
kjitterr		jitter kjitteramp, 0.02, 0.58

			; create a random table offset for left and right channels
irandomoffsetl		init random(0, 0.001)
irandomoffsetr		init random(0, 0.002)

			; read (detuned) table data (for use in detune-spread effect)
asigdetunedl		PlayTable ileftchannel , kdetunedplaybackspeed+kjitterl, isampleoffset+irandomoffsetl, kloopstart, kloopend
asigdetunedr		PlayTable irightchannel, kdetunedplaybackspeed+kjitterr, isampleoffset+irandomoffsetr, kloopstart, kloopend

			; read table data (normally)
asigl			PlayTable ileftchannel,  kplaybackspeed, isampleoffset, kloopstart, kloopend
asigr			PlayTable irightchannel, kplaybackspeed, isampleoffset, kloopstart, kloopend

			; check if we should apply detune spread while reading the ftables
			if(kdetunespread > 0) then
					; mix detuned & jittered signals with normal playback signals
				asigl	= (asigl * 0.4) + (asigdetunedl * 0.6)
				asigr	= (asigr * 0.4) + (asigdetunedr * 0.6)

			endif


			;filter 
;
			; NB. regarding the resonance or "Q" of this filter
			; The filter opcode "rbjeq" has 0 resonance when its "Q" argument == sqrt(0.5) == 0.7071
			; I don't know why but that's what the docs say.
			; I want *my* "Q" argument to range between [0 - 1] so I've chosen a lower bound of 0.7071
			; and a high bound of what I perceived to be a high "Q."

			#define FILTER_LEVEL #1#	; these are *only* used for the shelving filter mode 
			#define FILTER_SLOPE #1#	; which we aren't using here

			#define FILTER_MODE_LP #0#
			#define FILTER_MODE_HP #2#
			#define FILTER_MODE_BP #4#

			#define MAX_FILTER_CUTOFF_HZ #sr * 0.475#	; sr * 0.49   ~ 21-22khz
			#define MIN_FILTER_CUTOFF_HZ #sr * 0.0009#	; sr * 0.0009 ~ 40hz

			; determine whether to apply filter
			if (kfiltertype != 0) then

				; determine whether to apply filter envelope to the filter cutoff  
				if (kenv1destination >= 1 && kenv1depth != 1) then
								; scale filter cutoff by env1 envelope
					kfiltercutoff		*= kenv1envelope
				endif

						; we could use the 'scale' opcode (which only operates between 0 - 1) but eh						

						; scale filter cutoff [0 - 1] to hz [0 - sr/2]
						; (actually a little bit less then the nyquist frequency)
				kfiltercutoffhz	= kfiltercutoff * $MAX_FILTER_CUTOFF_HZ 

						; clip (maximum) filter cutoff to acceptable levels
				kfiltercutoffhz	= ( kfiltercutoffhz > $MAX_FILTER_CUTOFF_HZ ) ? $MAX_FILTER_CUTOFF_HZ : kfiltercutoffhz

						; clip (minimum) filter cutoff to acceptable levels
				kfiltercutoffhz = ( kfiltercutoffhz < $MIN_FILTER_CUTOFF_HZ ) ? $MIN_FILTER_CUTOFF_HZ : kfiltercutoffhz

						; scale resonance from [0 - 1] to... an arbitrary resonance
						; (due to this opcode's particular idiosyncrasy (see above))
				kres		= (kfilterresonance * 10) + 0.7071	; 0 : 0.7071,  1 : 10.7071


				; low pass
				if     (kfiltertype == 1) then	
					asigl	rbjeq   asigl, kfiltercutoffhz, $FILTER_LEVEL , kres, $FILTER_SLOPE , $FILTER_MODE_LP 
					asigr	rbjeq   asigr, kfiltercutoffhz, $FILTER_LEVEL , kres, $FILTER_SLOPE , $FILTER_MODE_LP 
				; high pass
				elseif (kfiltertype == 2) then
					asigl	rbjeq   asigl, kfiltercutoffhz, $FILTER_LEVEL , kres, $FILTER_SLOPE , $FILTER_MODE_HP 
					asigr	rbjeq   asigr, kfiltercutoffhz, $FILTER_LEVEL , kres, $FILTER_SLOPE , $FILTER_MODE_HP 
				; band pass
				elseif (kfiltertype == 3) then
					asigl	rbjeq   asigl, kfiltercutoffhz, $FILTER_LEVEL , kres, $FILTER_SLOPE , $FILTER_MODE_BP 
					asigr	rbjeq   asigr, kfiltercutoffhz, $FILTER_LEVEL , kres, $FILTER_SLOPE , $FILTER_MODE_BP 
				endif
			endif




			; pan method which retains full power in center (homebrewed)
			; center : [0.5], left/right : [0 - 1.0]
			if     (kpan < 0.5) then       ; left  panning (lower right channel amp)
				asigr	*= (2 * kpan)
			elseif (kpan > 0.5) then       ; right panning (lower left  channel amp)
				asigl	*= (2 * (1 - kpan))
			endif


			; apply amp envelope
asigl			*= kampenvelope
asigr			*= kampenvelope


			; apply distortion 
			#define MAX_DISTORTION #66#
			if(kdistortionamount > 0) then
				asigl	distort1 asigl, kdistortionamount * $MAX_DISTORTION , 1, 1, 0
				asigr	distort1 asigr, kdistortionamount * $MAX_DISTORTION , 1, 1, 0
			endif

			; output on either master or one of the fxsends
			; kbusdestination <  1         ---> master
			; kbusdestination >= 1 & < 2   ---> fxsend 1
			; kbusdestination >= 2 & < 3   ---> fxsend 2
			; etc...
			if(kbusdestination >= 1) then
				; NB. can't use 'tabw' because its 3rd argument 
				; only operates at i-rate (and we need k-rate)
				; hence we have to resort to zak channels
				kleftzakchannel		= int((kbusdestination - 1 ) * 2)
				krightzakchannel	= kleftzakchannel + 1
				zawm asigl, kleftzakchannel
				zawm asigr, krightzakchannel
				;asigl_ zar kleftzakchannel
				;asigr_ zar krightzakchannel
				;outs asigl_, asigr_
			else
				gamastersigl += asigl
				gamastersigr += asigr
				
			endif
endin


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; FX TRACK PROCESSING GOES HERE AND BELOW ;
; DUE TO CSOUND DSP PRECEDENCE            ;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

instr +FXSend

	iftablenumber	init p4

			; conjure the correct zak channels to read a-rate data from PlayPart
			; based off of the ftable we are provided
			;
			; DO NOT remove ifxsendftableoffset
			; I know it looks tempting to just use the macro itself in the expression
			; for ileftzakchannel.  Do not do it.  It will segfault (not sure why),
			; or it will produce weird arithmetic errors due to dumb macro expansion.
			; Errors which I thought were the fault of csound and spent an hour debugging.
			; So once again.
			; DO NOT remove ifxsendftableoffset
ifxsendftableoffset	init $FX_SEND_FTABLE_OFFSET 
ileftzakchannel		init int(2 * (iftablenumber - ifxsendftableoffset))
irightzakchannel	init i(ileftzakchannel) + 1

			; read in audio input
asigl			zar ileftzakchannel
asigr			zar irightzakchannel

			; read the ftable associated with this FXSend
kdelaylefttime		tab $FX_SEND_DELAY_LEFT_TIME, iftablenumber
kdelayleftfeedback	tab $FX_SEND_DELAY_LEFT_FEEDBACK, iftablenumber
kdelayrighttime		tab $FX_SEND_DELAY_RIGHT_TIME, iftablenumber
kdelayrightfeedback	tab $FX_SEND_DELAY_RIGHT_FEEDBACK, iftablenumber
kdelaywet		tab $FX_SEND_DELAY_WET, iftablenumber
kringmodfrequency	tab $FX_SEND_RING_MOD_FREQUENCY, iftablenumber
			;
kreverbroomsize		tab $FX_SEND_REVERB_ROOM_SIZE, iftablenumber
kreverbdamping		tab $FX_SEND_REVERB_DAMPING, iftablenumber
kreverbwet		tab $FX_SEND_REVERB_WET, iftablenumber
kbitreduction		tab $FX_SEND_BIT_REDUCTION, iftablenumber
			;
kcompressorratio	tab $FX_SEND_COMPRESSOR_RATIO, iftablenumber
kcompressorthreshold	tab $FX_SEND_COMPRESSOR_THRESHOLD, iftablenumber
kcompressorattack	tab $FX_SEND_COMPRESSOR_ATTACK, iftablenumber
kcompressorrelease	tab $FX_SEND_COMPRESSOR_RELEASE, iftablenumber
kcompressorsidechainsource	tab $FX_SEND_SIDE_CHAIN_SOURCE, iftablenumber
kgain			tab $FX_SEND_GAIN, iftablenumber

; apply effects now

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; ring modulation
;
if (kringmodfrequency > 0) then
	amodband	oscil 1, kringmodfrequency, -1, 0.0
	asigl		*= amodband
	asigr		*= amodband
endif

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; delay 
;
#define 	MAX_DELAY_TIME #1.0#
;
;		left channel delay
adelaybufferl	delayr $MAX_DELAY_TIME 
asigdelayl	deltapi kdelaylefttime
		delayw asigl + (asigdelayl * kdelayleftfeedback)
;
;		right channel delay
adelaybufferr	delayr $MAX_DELAY_TIME 
asigdelayr	deltapi kdelayrighttime
		delayw asigr + (asigdelayr * kdelayrightfeedback)
;
;		delay wetness
kdelaydry	= (1 - kdelaywet)
asigl		= (kdelaydry * asigl) + (kdelaywet * asigdelayl)
asigr		= (kdelaydry * asigr) + (kdelaywet * asigdelayr)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; reverb
;
; duplicate signals for denorm opcode (denorm improves efficiency)
asigreverbinl			= asigl
asigreverbinr			= asigr
				denorm asigreverbinl, asigreverbinr
;
ihalfsr		= sr / 2
kreverbdamping	= kreverbdamping * ihalfsr
asigreverboutl, asigreverboutr	reverbsc asigreverbinl, asigreverbinr, kreverbroomsize, kreverbdamping
;asigreverboutl, asigreverboutr	freeverb asigreverbinl, asigreverbinr, kreverbroomsize, kreverbdamping

; reverb wetness
kreverbdry	= (1.0 - kreverbwet)
asigl		= (kreverbdry * asigl) + (kreverbwet * asigreverboutl)
asigr		= (kreverbdry * asigr) + (kreverbwet * asigreverboutr)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; bitcrusher
;
; adapted from LoFi.csd found here:
; http://iainmccurdy.org/csound.html
;
if (kbitreduction > 0) then 
	k_bitdepth	= 16 - kbitreduction		; 0 -> 16  , 16 -> 1 
	k_values	pow 2, k_bitdepth
	asigl		= (int((asigl/0dbfs)*k_values))/k_values
	asigr		= (int((asigr/0dbfs)*k_values))/k_values
endif

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; compressor/limiter/ducker
;
#define LOWKNEE 	#48#		; * hard knee only *
#define HIGHKNEE	#48#		;
if (kcompressorratio >= 1) then
	; compress it
	asigl	compress asigl, asigl+0.0001, kcompressorthreshold, $LOWKNEE , $HIGHKNEE , kcompressorratio, kcompressorattack, kcompressorrelease, 0
	asigr	compress asigl, asigl+0.0001, kcompressorthreshold, $LOWKNEE , $HIGHKNEE , kcompressorratio, kcompressorattack, kcompressorrelease, 0
	; apply post gain
	;asigl	*= kcompressorpostgain
	;asigr	*= kcompressorpostgain
endif

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; gain
;
asigl		*= kgain
asigr		*= kgain

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;		accumulate into master
gamastersigl	+= asigl
gamastersigr	+= asigr

endin


; ------------------------------------------
instr +Master
				; find which ftable master is
iftablenumber			init $MASTER_FTABLE_OFFSET
				; read master state
kmastereqgainlow		tab $MASTER_EQ_GAIN_LOW, iftablenumber
kmastereqgainmid		tab $MASTER_EQ_GAIN_MID, iftablenumber
kmastereqgainhigh		tab $MASTER_EQ_GAIN_HIGH, iftablenumber
kmastereqlowcornerfrequency	tab $MASTER_EQ_LOW_CORNER_FREQUENCY, iftablenumber
kmastereqmidpeakingfrequency	tab $MASTER_EQ_MID_PEAKING_FREQUENCY, iftablenumber
kmastereqhighcornerfrequency	tab $MASTER_EQ_HIGH_CORNER_FREQUENCY, iftablenumber
kmasterreverbroomsize		tab $MASTER_REVERB_ROOM_SIZE, iftablenumber
kmasterreverbdamping		tab $MASTER_REVERB_DAMPING, iftablenumber
kmasterreverbwet		tab $MASTER_REVERB_WET, iftablenumber
kmasterbitreduction		tab $MASTER_BIT_REDUCTION, iftablenumber
kmastercompressorratio		tab $MASTER_COMPRESSOR_RATIO, iftablenumber
kmastercompressorthreshold	tab $MASTER_COMPRESSOR_THRESHOLD, iftablenumber
kmastercompressorattack		tab $MASTER_COMPRESSOR_ATTACK, iftablenumber
kmastercompressorrelease	tab $MASTER_COMPRESSOR_RELEASE, iftablenumber
kmastergain			tab $MASTER_GAIN, iftablenumber


; apply effects now

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; eq
;
#define PEAKING		 #0#
#define LOW_SHELVING	 #1#
#define HIGH_SHELVING	 #2#
#define NO_RESONANCE	 #0.707106# ; == sqrt(0.5) which is no resonance for this opcode ("pareq")
; low shelf eq
gamastersigl	pareq gamastersigl, kmastereqlowcornerfrequency, kmastereqgainlow, $NO_RESONANCE, $LOW_SHELVING
gamastersigr	pareq gamastersigr, kmastereqlowcornerfrequency, kmastereqgainlow, $NO_RESONANCE, $LOW_SHELVING
; mid peaking eq
gamastersigl	pareq gamastersigl, kmastereqmidpeakingfrequency, kmastereqgainmid, $NO_RESONANCE, $PEAKING
gamastersigr	pareq gamastersigr, kmastereqmidpeakingfrequency, kmastereqgainmid, $NO_RESONANCE, $PEAKING
; high shelf eq
gamastersigl	pareq gamastersigl, kmastereqhighcornerfrequency, kmastereqgainhigh, $NO_RESONANCE, $HIGH_SHELVING
gamastersigr	pareq gamastersigr, kmastereqhighcornerfrequency, kmastereqgainhigh, $NO_RESONANCE, $HIGH_SHELVING

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; reverb
;
; duplicate signals for denorm opcode (denorm improves efficiency)
amastersigreverbinl				= gamastersigl
amastersigreverbinr				= gamastersigr
						denorm amastersigreverbinl, amastersigreverbinr
;
ihalfsr						= sr / 2
kmasterreverbdamping				= kmasterreverbdamping * ihalfsr ; <--- reverbsc has a different damping than freeverb
amastersigreverboutl, amastersigreverboutr	reverbsc amastersigreverbinl, amastersigreverbinr, kmasterreverbroomsize, kmasterreverbdamping
;
; reverb wetness
kmasterreverbdry				= (1.0 - kmasterreverbwet)
gamastersigl					= (kmasterreverbdry * gamastersigl) + (kmasterreverbwet * amastersigreverboutl)
gamastersigr					= (kmasterreverbdry * gamastersigr) + (kmasterreverbwet * amastersigreverboutr)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; bitcrusher
;
; adapted from LoFi.csd found here:
; http://iainmccurdy.org/csound.html
;
if (kmasterbitreduction > 0) then 
	k_bitdepth	= 16 - kmasterbitreduction		; 0 -> 16  , 16 -> 1 
	k_values	pow 2, k_bitdepth
	gamastersigl	= (int((gamastersigl/0dbfs)*k_values))/k_values
	gamastersigr	= (int((gamastersigr/0dbfs)*k_values))/k_values
endif

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; compressor/limiter/ducker
;
#define LOWKNEE 	#48#		; * hard knee only *
#define HIGHKNEE	#48#		;
if (kmastercompressorratio >= 1) then
	; compress it
	gamastersigl	compress gamastersigl, gamastersigl+0.0001, kmastercompressorthreshold, $LOWKNEE , $HIGHKNEE , kmastercompressorratio, kmastercompressorattack, kmastercompressorrelease, 0
	gamastersigr	compress gamastersigl, gamastersigl+0.0001, kmastercompressorthreshold, $LOWKNEE , $HIGHKNEE , kmastercompressorratio, kmastercompressorattack, kmastercompressorrelease, 0
endif

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; gain
;
gamastersigl		*= kmastergain
gamastersigr		*= kmastergain

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


			; clip everything
gamastersigl		clip gamastersigl, 2, 1.0
gamastersigr		clip gamastersigr, 2, 1.0

			; output to DAC
			outs gamastersigl, gamastersigr

			; clearing gamastersigl & gamastersigr 
			; as well as clearing the zak channels
			; is handled in ClearAudioChannels
			; (so we can record the output of Master with RecordIntoPart)

endin

; ------------------------------------------
; record audio from sources (Master's output or audio input)
; critical to workflow (tweak - resample - repeat)
;
; NB. This instrument must come at the end of all the audio processing
; *BUT* before the audio data is cleared for the next a-rate loop
; CSound's DSP precedence... Yep.
instr +RecordIntoPart

#define MODE_RECORD_MASTER	#0#

ipartnumber     init p4
imode		init p5	; 0 - mastertrack, != 0 - audio_in

kreleased	release

; generate a different filename each time instrument is called
; perhaps name should be conjoined from existing vocabulary?
;     ex: projectname + rand(dictonary) + rand(dictionary) -> proj1_monkey_helicopter.wav
;     it's easier to remember and read than a date... idk
;     it's also funny
itim      date
Stim      dates     itim
Syear     strsub    Stim, 20, 24
Smonth    strsub    Stim, 4, 7
Sday      strsub    Stim, 8, 10
iday      strtod    Sday
Shor      strsub    Stim, 11, 13
Smin      strsub    Stim, 14, 16
Ssec      strsub    Stim, 17, 19
Sfilename sprintf  "%s_%s_%02d_%s_%s_%s.wav", Syear, Smonth, iday, Shor,Smin, Ssec

	;debug
	prints "Recording into part#: %d\n\n\n", ipartnumber

	if (imode == $MODE_RECORD_MASTER ) then
				fout Sfilename, 14, gamastersigl, gamastersigr
	else
		asigl, asigr	ins
				; should we be playing audio_in through a track simultaneously ?
				; outs asigl, asigr
				fout Sfilename, 14, asigl, asigr
	endif

	; when we're done recording
	; load the new sample into the provided part
	if (kreleased == 1) then
	        Sfstatement	sprintfk {{i "LoadPartFromSample" 0 -1 %d "%s"}}, ipartnumber, Sfilename
				scoreline Sfstatement, 1
				printks "Done recording into part#: %d\n\n\n", 0, ipartnumber
				turnoff
	endif

endin

; this instrument exists so we can turn off a held recorder using
; the score (which is how communication occurs with this application
; via sending score data over OSC)
instr +StopRecording
	; turn off all instances of RecordIntoPart
	; and allow it to release
	turnoff2 nstrnum("RecordIntoPart"), 0, 1
	; turn off this instrument itself
	turnoff
endin


; this instrument's code *could* have gone in Master
; but then we couldn't record the master audio channels with RecordIntoPart
; due to Csound's instrument DSP precedence
instr ClearAudioChannels
;
			; clear master channels for the next a-rate loop iteration to accumulate into
gamastersigl		= 0.0
gamastersigr		= 0.0
			; clear zak channels for the next a-rate loop iteration to write into
			; (is this necessary?)
inumberofzakaudiochannels = $NUMBER_OF_ZAK_AUDIO_CHANNELS	; <--- if we don't do this
								; macro expansion will create weird errors
			zacl 0, inumberofzakaudiochannels  
endin


; the following instrument turns on necessary performance instruments
; as well as performs any other necessary initialization 
instr BootUp

			; turn on our OSC score listener
			turnon nstrnum("OSCScoreListener")

			; turn on $MAX_NUMBER_OF_FX_SEND FXSend instruments
			; and associate them with the proper ftables
			;
			;
			; Alright.  Rant-time.
			; 
			; The code below looks odd (why is ifxsendinstrnum being incremented?).
			; Well dear reader, it's because if you don't increment it 
			; (which semantically creates seperate instruments), 
			; the zak opcode won't work in FXSend.
			;
			; I hear you say:
			; "B-But I thought the 'event' opcode *did* instantiate seperate instruments..."
			;
			; In fact, it does! ...and yet the zak opcode won't work regardless.
			; You need the witchcraft I've written below.
			;
			; Who knows.  Fuck this language. I spent hours trying it figure it out.
			; HOURS.
			;
			; Csound's documentation...
			; regarding the zak opcodes is amazingly unhelpful (with literal contradictions
			; regarding where you index for reading and writing into zak space).
			; It says zak-space starts at 0 and goes to N, and in the very same 
			; fucking demo csd file the provided code doesn't follow this convention 
			; and get this...
			; it fucking RUNS anyway!
			;
			;
			; In summary. Fuck this language.  Fuck the parser for it.  Fuck its shitty
			; macro system.  Fuck its dated assembler syntax.
			; Fuck it
			;
			;
	kfxsendftable	init $FX_SEND_FTABLE_OFFSET
	ifxsendinstrnum = nstrnum("FXSend")
	kinc		init 0
	next_fxsend:
			event "i", ifxsendinstrnum+kinc, 0, -1, kfxsendftable ; <--- there be dragons
	kfxsendftable	+= 1
	kinc		+= 0.001 ; <--- technically, this limits us to 1000 FXSends... but dude.
			if ( kfxsendftable < $FX_SEND_FTABLE_OFFSET + $MAX_NUMBER_OF_FX_SEND ) kgoto next_fxsend

			; turn on the master
			turnon nstrnum("Master")
			; make sure audio channels are cleared each a-rate loop
			turnon nstrnum("ClearAudioChannels")

			; limit the allocations of Recorder to 1
			maxalloc "RecordIntoPart", 1

			turnoff

endin
turnon nstrnum("BootUp")



</CsInstruments>
<CsScore>
e 3600 ; stay on for 1 hour
</CsScore>
</CsoundSynthesizer>

