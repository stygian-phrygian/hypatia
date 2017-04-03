
; This is a sampler
; It records sounds
; It plays back those sounds
; It can load existing sound files and play them too
; It can tweak sounds during playback
; It can also send the sounds to effects busses
; It can save a bunch of sounds to a project directory
; It uses OSC for controlling all this (MIDI is fun but too limited)


; OSC NETWORK
; /loadsampleintopart [part# filename]
; /loadproject [directoryname]
; /recordstart [recordmode]
; /recordstop [dummyvariable]
; /playpart [part# when duration]
; /setpartparameter [part# partparameter# value]
; /setfxbussparameter [buss# bussparameter# value] 
; /setmasterbussparameter [buss# bussparameter# value] 



<CsoundSynthesizer>
<CsOptions>

; realtime output
-odac

; realtime input (will need configuring)
-iadc

</CsOptions>
<CsInstruments>

sr	=	48000
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
; sonic alteration (after the Part processes the audio).  Multiple
; parts can route the audio simultaneously to one.
; An FXSend is also an ftable.
;
; All FXSends route to Master.
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
; [1-128] : Parts
; [129-132] : FXSends
; [133] : Master
; [1000-1256] : Sample Ftables [mono pairs]
;
;
;
;
#define MAX_NUMBER_OF_PARTS		#128#
#define MAX_NUMBER_OF_FX_SEND		#4#

#define PART_FTABLE_OFFSET              #1#
#define FX_SEND_FTABLE_OFFSET           #$MAX_NUMBER_OF_PARTS + 1#
#define MASTER_FTABLE_OFFSET		#$MAX_NUMBER_OF_PARTS + $MAX_NUMBER_OF_FX_SEND + 1#
#define SAMPLE_FTABLE_OFFSET            #1000#

#define PLAY_PART_INSTRUMENT_INDEX      #100#
;
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
#define PART_STEP_NUDGE			#12#
#define PART_GATE			#13#	; how many steps
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

; fx bus state
#define NUMBER_OF_PARAMETERS_PER_FX_SEND	#16#
; fx bus parameter indices

instr InitializePart

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

instr CreatePart

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

instr CreateAllParts

	ipart		init 1
	next_part:
			event_i "i", "CreatePart", 0, -1, ipart
	ipart		+= 1
			if ( ipart <= $MAX_NUMBER_OF_PARTS ) igoto next_part
			turnoff
		
endin
turnon nstrnum("CreateAllParts")

instr +LoadSample
; args: ftable number, filename
;
; NB. never call this function directly.  Use LoadSampleIntoPart which will take care of
; ftable memory layout (otherwise the results could be quite... dangerous).

iftn		init p4
Sfilename	init p5

		; determine how many channels are in our sample file
inchnls		filenchnls Sfilename

		; mono file loads into iftn and iftn+1
		; stereo file loads left and right channels into iftn and iftn+1 respectively
		if (inchnls == 1) then
				prints "Loading mono sample into ftable # %d\n", iftn
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

instr +LoadSampleIntoPart
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
;				event_i "i", "LoadSample", 0, -1, itrueftableindex, Sfilename
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


instr PlayPart, 100
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

			prints "playing sample # %d on part # %d\n", isamplenumber, ipartnumber

			; -- realtime editable parameters --
kpitch			tab $PART_PITCH			    , ipartnumber
kpitch			+= p5
kamp			tab $PART_AMP                       , ipartnumber
kamp			+= p5
kfiltercutoff		tab $PART_FILTER_CUTOFF             , ipartnumber 
kfiltercutoff		+= p7
kfilterresonance	tab $PART_FILTER_RESONANCE          , ipartnumber 
kfilterresonance	+= p8
kfiltertype		tab $PART_FILTER_TYPE               , ipartnumber 
kfiltertype		+= p9
kpan			tab $PART_PAN                       , ipartnumber 
kpan			+= p10
kdetunespread		tab $PART_DETUNE_SPREAD             , ipartnumber 
kdetunespread		+= p11
kdistortionamount	tab $PART_DISTORTION_AMOUNT         , ipartnumber 
kdistortionamount	+= p12
			; -- realtime editable parameters
			; -- but are i-values in the instrument therefore
			; -- changing them causes instrument reinitialization
			; -----------------------------------------------
ksampleoffset		tab $PART_SAMPLE_OFFSET             , ipartnumber
ksampleoffset		+= p13
isampleoffset		init i(ksampleoffset)	
ktimestretchfactor	tab   $PART_TIMESTRETCH_FACTOR      , ipartnumber
ktimestretchfactor	+= p14
itimestretchfactor	init i(ktimestretchfactor)
ktimestretchwindowsize	tab   $PART_TIMESTRETCH_WINDOW_SIZE , ipartnumber
ktimestretchwindowsize	+= p15
itimestretchwindowsize	init i(ktimestretchwindowsize)
;istepnudge		tab_i $PART_STEP_NUDGE              , ipartnumber
;igate			tab_i $PART_GATE                    , ipartnumber
kbusdestination		tab $PART_BUS_DESTINATION           , ipartnumber
kbusdestination		+= p16
			; -----------------------------------------------
			; -- realtime editable modulation --
kampattack		tab $PART_AMP_ATTACK                , ipartnumber
kampattack		+= p17
kampdecay		tab $PART_AMP_DECAY                 , ipartnumber
kampdecay		+= p18
kampsustainlevel	tab $PART_AMP_SUSTAIN_LEVEL         , ipartnumber
kampsustainlevel	+= p19
kamprelease		tab $PART_AMP_RELEASE               , ipartnumber
kamprelease		+= p20
kenv1attack		tab $PART_ENV1_ATTACK               , ipartnumber
kenv1attack		+= p21
kenv1decay		tab $PART_ENV1_DECAY                , ipartnumber
kenv1decay		+= p22
kenv1depth		tab $PART_ENV1_DEPTH                , ipartnumber
kenv1depth		+= p23
kenv1destination	tab $PART_ENV1_DESTINATION          , ipartnumber
kenv1destination	+= p24
			
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

			; scale env1 envelope, unscaled env1: [ 0 - 1 ], scaled env1 : [ 1 - env1depth ]
			; NB. env1depth should *always* be >= 1
			; FIXME: handle negative depth?
kenv1envelope		*= (kenv1depth - 1)
kenv1envelope		+= 1

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

			; output on one of the tracks (...really zak channels)
			; zawm asigl, ichanl
			; zawm asigr, ichanr
			; gamastertrackl += asigl
			; gamastertrackr += asigr


			; just testing right now
			; output with 'outs' opcode


			outs asigl, asigr

endin


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; FX TRACK PROCESSING GOES HERE
; DUE TO CSOUND DSP PRECEDENCE
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; ------------------------------------------
; record audio from sources (master or audio input)
; critical to workflow (tweak - resample - repeat)
;
; NB. This instrument must come at the end of all the audio processing
; *BUT* before Master clears the master signal data
; CSound's DSP precedence... Yep.

instr +RecordIntoPart

#define MODE_RECORD_MASTER	#0#

imode		init p4	; 0 - mastertrack, != 0 - audio_in
ipartnumber     init p5

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
	prints "Recording into part#: %d\n", ipartnumber

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
	        Sfstatement	sprintfk {{i "LoadSampleIntoPart" 0 -1 %d "%s"}}, ipartnumber, Sfilename
				scoreline Sfstatement, 1
				printks "Done recording into part#: %d\n", 0, ipartnumber
				turnoff
	endif

endin

; ------------------------------------------

instr +Master
;		output to DAC
		outs gamastersigl, gamastersigr
;		clear master channels for the next a-rate loop iteration to accumulate into
gamastersigl	= 0.0
gamastersigr	= 0.0
;		clear zak channels for the next a-rate loop iteration to write into
;		zacl 0, ( 2 * $N_TRACKS ) 
endin

; ------------------------------------------
instr +OSCLoadSampleIntoPartListener
kpartnumber	init 1
Sfilename	strcpy ""
next:
kresponse	OSClisten giosclistenhandle, "/loadsampleintopart", "is", kpartnumber, Sfilename
if (kresponse == 0) goto done
;		printks "CSOUND: OSC message received on /loadsample\n", 0
		; f#, time, defered size, gen#, filename, skiptime, format, which-channel-to-read
;Sfstatement	sprintfk {{f %d 0 0 1 "%s" 0 0 0 }}, kftablenumber, Sfilename
Sfstatement	sprintfk {{i "LoadSampleIntoPart" 0 -1 %d "%s"}}, kpartnumber, Sfilename
		scoreline Sfstatement, 1
	
		kgoto next
done:
endin
; ------------------------------------------
; the listener starts and stops a recorder instrument
; which takes as p-values one of the available audio sources
; (maybe implement threshold recording?)

instr +OSCRecordIntoPartListener

; TODO can we record concurrently?... i think no
kmode			init 0	; 0 - mastertrack, != 0 - audio_in
kpartnumber		init 0
irecorder		nstrnum "RecordIntoPart"
kcurrentlyrecording	init 0

; *do not* get rid of this variable, OSClisten needs at least 1 variable to work proper
kdummyvariable		init 0 

kstart	OSClisten giosclistenhandle, "/recordstart", "ii", kmode, kpartnumber
kstop	OSClisten giosclistenhandle, "/recordstop", "i", kdummyvariable

if (kcurrentlyrecording == 1) kgoto checkstop
if (kstart == 1)  then
	; turn on the recorder
	kcurrentlyrecording = 1
	event "i", irecorder, 0, -1, kmode, kpartnumber
	printks "CSOUND: started recording...\n", 0
endif

checkstop:
if (kcurrentlyrecording == 0) kgoto done
if (kstop == 1) then
	; turn off the recorder
	kcurrentlyrecording = 0
	event "i", -irecorder, 0, 0, 0, 0
	printks "CSOUND: stopped recording...\n", 0
endif

done:

endin

; instr Recorder is defined below everything else
; due to csound's instr calculation precedence
; ------------------------------------------

; turn on master track
turnon nstrnum("Master")
; turn on OSC listeners
turnon nstrnum("OSCLoadSampleIntoPartListener")
turnon nstrnum("OSCRecordIntoPartListener")

; limit the allocations of Recorder to 1
maxalloc "RecordIntoPart", 1


</CsInstruments>
<CsScore>
e 3600 ; stay on for 1 hour
</CsScore>
</CsoundSynthesizer>

