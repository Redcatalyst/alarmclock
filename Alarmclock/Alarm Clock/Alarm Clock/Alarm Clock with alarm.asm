/*
 * Alarm_Clock.asm
 *
 *  Created: 10-4-2015 16:02:57
 *   Author: Rick
 */ 

 .include "m32def.inc"

 .def parts	= r15		; Parts of a second
 .def secs = r16		; Seconds count
 .def mins = r17		; Minutes count
 .def hours = r18		; Hours count

 .def temp = r19		; Save temporary values
 .def temp2 = r20		; Save secondairy temp values

 .def alarmsecs = r21	; Seconds alarm is set on
 .def alarmmins = r22	; Minutes alarm is set on
 .def alarmhours = r23  ; Hours alarm is set on

 .def state = r24		; Stores diffrents display states
 .def setting = r25		; Stores the button settings

 .org 0x0000			; On reset 
 rjmp init				; Jump to init

 .org OC1Aaddr			; On internalinterupt
 rjmp TIMER1_COMP_ISR	; Call the Interupt Service Routine: TIMER1_COMP_ISR

 ; Init program
 ; Load 0 for default values
 init:
 ldi secs, 0
 ldi mins, 0
 ldi hours, 0

 ldi alarmsecs, 0
 ldi alarmmins, 0
 ldi alarmhours, 0

 ldi state, 0x00			
 ldi setting, 0b00100001	

 ; Init stackpointer
 ldi temp, high(RAMEND)	; Load the high value for the stackpointer
 out SPH, temp			; Output high value for the stackpointer
 ldi temp, low(RAMEND)	; Load the low value for the stackpointer
 out SPL, temp			; Output low value for the stackpointer

 ; Init timer settings
 ; Crystal Hz = 11059200
 ; Prescaler 256 so 256/11059200 = 0.00002314814
 ; We need 1 sec so, 1/0.00002314814 = 43200~
 ; 43200 is the value we need to give to the timer to get 1 sec
 ; But 1 second is to slow when we need to adjust the time
 ; So we are dividing the time by 4, every 1/4th of a second it will call the timer
 ; The value will be 10800 for 1/4 of a second

 ldi temp, high(10800)	; Load the high value for the timer 
 out OCR1AH, temp		; Output high value for the timer
 ldi temp, low(10800)	; Load the low value for the timer
 out OCR1AL, temp		; Output low value for the timer

 ; Set prescaler and timer to CTC mode
 ldi temp, (1 << CS12) | (1 << WGM12)		; Set prescaler to 256 and timer to CTC mode
 out TCCR1B, temp							; Output settings for the prescaler and timer mode

 ldi temp, (1 << OCIE1A)					; Enable timer interupt 
 out TIMSK, temp							; Output the interupt enable

 ; Init switches and external interupt
 clr temp
 out DDRD, temp								; Use switches as input

 ; External interupt settings
 ldi temp, (1 << ISC11)						; Use falling edge to generate an interupt
 out MCUCR, temp							; Output these settings

 ; Enable external interupt					
 ldi temp, (1 << INT1) | (1 << INT0)		; Enable INT1 and INT0
 out GICR, temp								; Output these settings

 sei										; Enable all interupts

 ; Init reciever / transmitter
 clr temp									; Clear temp so the value is 0x00
 out UBRRH, temp							; Output high value
 ldi temp, 35								; Load 35 into temp
 out UBRRL, temp							; Output low value

 ldi temp, (1 << RXEN) | (1 << TXEN)		; Enable receiver/tranmitter
 out UCSRB, temp							; Output these settings

 ldi temp, (1 << URSEL) | (1 << USBS) | (3 << UCSZ0) ; Frameformat: 8data, 2stop bit
 out UCSRC, temp
 ldi temp, 0x00

 loop:
	rjmp loop			; Wait for interupts
 
 ; Internal interupt
 TIMER1_COMP_ISR:				; ISR wordt elke seconde aangeroepen
	ldi temp, 0x80				; Load 0x80 in to temp
	rcall transmit				; Send 0x80 to the display to remove so far send bytes
	rcall checkSwitches			; Listen to the switches
	rcall displayTime			; Display the time/timesettings
	rcall sendTime				; Handle the time on the display
	rcall checkAlarm			; Check if the alarm should go off
	rcall sendState				; Send the state of the 7th byte
	reti						; Return from interupt
 
 ; Transmit data
 transmit:
    sbis UCSRA, UDRE	; wait for an empty transmit buffer 
	rjmp transmit		; This is skipped when UDRE flag is cleared, if not then it jumps back to transmit
	out UDR, temp		; Send the temp date over Tx
	ret					; Return from subroutine
 
 updateState:
	ldi temp, 0b00000110	; Load 6 into temp
	eor state, temp			; Preform an exlusive OR 
	ret
 
 sendState:				
	rcall updateState		; Before the state is send it has to be updated		
	mov temp, state			; Copy the state to temp so it can be send away with transmit
	rcall transmit			; Send the state to the device
	ret
 
 sendTime:
	cpi setting, 33		; Check if the 5 and 0 bit are set in setting (adjust time, start with secs)
	breq setTime		; If its equal then the time needs to be set
	mov temp, hours		; Copy hours into temp
	rcall splitNumber	; Separate the numbers and send them to display
	mov temp, mins		; Copy minutes into temp
	rcall splitNumber	; Separate the numbers and send them to display
	mov temp, secs		; Copy seconds into temp
	rcall splitNumber	; Separate the numbers and send them to display
	ret
 
 sendAlarmTime:
    cpi setting, 64			; Check if the 6 bit is set
	brge setAlarm			; If its equal or greater
	mov temp, alarmhours	; Copy hours into temp
	rcall splitNumber		; Separate the numbers and send them to display
	mov temp, alarmmins		; Copy minutes into temp
	rcall splitNumber		; Separate the numbers and send them to display
	mov temp, alarmsecs		; Copy seconds into temp
	rcall splitNumber		; Separate the numbers and send them to display
	ret
 
 ; Time configuring subroutines
 setTime:
	sbrc setting, 0			; Check if the 0 bit is cleared
	rjmp adjustSecs			; Jump to the adjust seconds routine
	sbrc setting, 1			; Check if the 1 bit is cleared 
	rjmp adjustMins			; Jump to the adjust minutes routine
	sbrc setting, 2			; Check if the 2 bit is cleared
	rjmp adjustHours		; Jump to the adjust hours routine
	ret

 setAlarm:
 	sbrc setting, 3			; Check if the 3 bit is cleared
	rjmp adjustAlarmMins	; Jump to the adjust alarm minutes routine
	sbrc setting, 4			; Check if the 4 bit is cleared
	rjmp adjustAlarmHours
	ret

 adjustSecs:
	ldi temp, 0				; Load 0 into temp
	rcall transmit			; Send empty byte away left hour (i.e. Blink once)
	rcall transmit			; Send empty byte away right hour (i.e. Blink once)
	rcall transmit			; Send empty byte away left min (i.e. Blink once)
	rcall transmit			; Send empty byte away right min (i.e. Blink once)
	mov temp, secs			; Load seconds into temp
	rcall splitNumber		; Send the seconds away
	ret

 adjustMins:
	ldi temp, 0				; Load 0 into temp
	rcall transmit			; Send empty byte away left hour (i.e. Blink once)
	rcall transmit			; Send empty byte away right hour (i.e. Blink once)
	mov temp, mins			; Load the minutes into temp
	rcall splitNumber		; Send the minutes away
	ldi temp, 0				; Load 0 into temp
	rcall transmit			; Send empty byte away left sec (i.e. Blink once)
	rcall transmit			; Send empty byte away right sec (i.e. Blink once)
	ret			

 adjustHours:
	mov temp, hours			; Load the hours into temp
	rcall splitNumber		; rcall splitnumber
	ldi temp, 0				; Load 0 into temp
	rcall transmit			; Send empty byte away left min (i.e. Blink once)
	rcall transmit			; Send empty byte away right min (i.e. Blink once)
	rcall transmit			; Send empty byte away left sec (i.e. Blink once)
	rcall transmit			; Send empty byte away right sec (i.e. Blink once)
	ret

 adjustAlarmMins:
	ldi temp, 0				; Load 0 into temp
	rcall transmit			; Send empty byte away left hour (i.e. Blink once)
	rcall transmit			; Send empty byte away right hour (i.e. Blink once)
	mov temp, alarmmins		; Load the alarmminutes into temp
	rcall splitNumber		; Send the alarmminutes away
	ldi temp, 0				; Load 0 into temp
	rcall transmit			; Send empty byte away left sec (i.e. Blink once)
	rcall transmit			; Send empty byte away right sec (i.e. Blink once)
	ret		

 adjustAlarmHours:
	mov temp, alarmhours	; Load the hours into temp
	rcall splitNumber		; rcall splitnumber
	ldi temp, 0				; Load 0 into temp
	rcall transmit			; Send empty byte away left min (i.e. Blink once)
	rcall transmit			; Send empty byte away right min (i.e. Blink once)
	rcall transmit			; Send empty byte away left sec (i.e. Blink once)
	rcall transmit			; Send empty byte away right sec (i.e. Blink once)
	ret

 displayTime:
	cpi setting, 8		; Check if setting is equal to 8 (3rd bit)
	brlo incTime		; If its lower than 8 continue with increasing the time
	ldi temp, 16		; Load 4th bit into temp
	eor setting, temp	; Exclusive OR setting with temp to get the right output
	ret

 checkAlarm:
	sbrs state, 0			; Check if alarm alarm is set
	rjmp noAlarm			; If not been set jump to noAlarm
	cp secs, alarmsecs		; Check if the current seconds match the set seconds of the alarm
	brne noAlarm			; If not equal jump to noAlarm
	cp mins, alarmmins		; Check if the current minutes match the set minutes of the alarm
	brne noAlarm			; If not equal jump to noAlarm
	cp hours, alarmhours	; Check if the current hours match the set hours of the alarm
	brne noAlarm			; If not equal jump to noAlarm
	rcall soundAlarm		; If eveything passes then sound the alarm
	
 noAlarm:		
	ret						; Alarm should not go off, return from interupt

 soundAlarm:
	sbr state, 0b0001000	; Set 3 bits in the state register (toggle alarm buzzer)
	ret						

 ; Increase time subroutines
 ; These routines manage the timetable's 
 incTime:
	ldi temp2, 0		; Load 0 for comparison
	rcall incParts		; Increase the parts to make a whole second after 4 interupts
	cpse temp, temp2	; Skip next part if temp isnt 1 (i.e. parts have not reached 4)
	rcall incSecs		; Increase seconds
	cpse temp, temp2	; Skip next part if temp isnt 1 (i.e. seconds have not reached 60)
	rcall incMins		; Increase minutes
	cpse temp, temp2	; Skip next part if temp isnt 1 (i.e. minutes have not reached 60)
	rcall incHours		; Increase hours
	ret

 incParts:
	inc parts			; Increment the parts with 1
	mov temp, parts		; Copy the parts into temp
	cpi temp, 4			; Check if parts equals 4 (4 times a part equals one second(interupt timing))
	ldi temp, 0			; Clear temp
	brne nextPart		; If not equal continue with counting parts
	clr parts			; Clear parts when it reached 4
	ldi temp, 1			; Load temp with 1 for incTime

 nextPart:
    ret					; Return from subroutine				

 incSecs:
	ldi temp, 0			; Load 0 into temp for resetting secs when needed
	inc secs			; Increment seconds with one
	cpi secs, 60		; Check if seconds reached 60
	brne nextSec		; Branch if secs not equal to 60 to skip clearing
	clr secs			; Clear secs (We reached 60)
	ldi temp, 1			; Load with 1 for incTime
 
 nextSec:
	ret					; Return from subroutine

 incMins:
	ldi temp, 0			; Load 0 to clear temp
	inc mins			; Increment minutes with one
	cpi mins, 60		; Check if minutes reached 60
	brne nextMin		; Branch if mins not equal to 60 to skip clearing
	clr mins			; Clear minutes (We reached 60)
	ldi temp, 1			; Load with 1 for incTime

 nextMin:
	ret					; Return from subroutine

  incHours:
	ldi temp, 0			; Load 0 to clear temp
	inc hours			; Increment hours with one
	cpi hours, 24		; Check if hours reached 24
	brne nextHour		; Branch if hours not equal to 24 to skip clearing
	clr hours			; Clear hours (We reached 24)
	ldi temp, 1			; Load with 1 for incTime

 nextHour:
	ret					; Return from subroutine

 incAlarmMins:
	ldi temp, 0			; Load 0 to clear temp
	inc alarmmins		; Increment alarm minutes with one
	cpi alarmmins, 60	; Check if alarm minutes reached 60
	brne nextAlarmMin	; Branch if alarm mins not equal to 60 to skip clearing
	clr alarmmins		; Clear alarm minutes (We reached 60)

 nextAlarmMin:
	ret					; Return from subroutine

 incAlarmHours:
	ldi temp, 0				; Load 0 to clear temp
	inc alarmhours			; Increment alarm hours with one
	cpi alarmhours, 24		; Check if alarm hours reached 24
	brne nextAlarmHour		; Branch if alarm hours not equal to 24 to skip clearing
	clr alarmhours			; Clear alarm hours (We reached 24)

 nextAlarmHour:
	ret					; Return from subroutine

 ; Split number subroutine
 ; This routine splits the number into 2 parts that are 0 through 9 (i.e. 43 = 4 and 3)
 splitNumber:			
	mov temp2, temp			; Copy temp to temp2 for
	clr temp				; Empty temp

	splitting:		
		cpi temp2, 10			; Check if temp2 equals to 10
		brlo sendNumberPart		; If lower than 10 jump to sendNumberPart
		subi temp2, 10			; subtract 10 from temp 2
		inc temp				; Increment temp by one (i.e. 10th of a number)
		rjmp splitting			; Jump back to splitting to continue splitting of number (i.e. /10)

	sendNumberPart:
		rcall sendNumber		; Send the number currently in temp (the number devided by 10)
		mov temp, temp2			; Copy temp2 to temp (the number lower than 10)
		rcall sendNumber		; Send the number to display

	ret
 
 ; Send number subroutine
 ; This routine generates the segments to show on the display
 ; Also calls transmit to send it to the display
 sendNumber:
	cpi temp, 0				; Check if temp equals 0
	brne numberOne			; If temp is not 0 continue with 1
	ldi temp, 0b01110111	; Load segments for 0 into temp
	rjmp numberDone			; Jump to numberDone if this is te right number	

	numberOne:
		cpi temp, 1				; Check if temp equals 1
		brne numberTwo			; If temp is not 1 continue with 2
		ldi temp, 0b00100100	; Load the segments for 1 into temp
		rjmp numberDone			; Jump to numberDone if this is te right number	

	numberTwo:
		cpi temp, 2				; Check if temp equals 2
		brne numberThree		; If temp is not 2 continue with 3
		ldi temp, 0b01011101	; Load the segments for 2 into temp
		rjmp numberDone			; Jump to numberDone if this is te right number	

	numberThree:
		cpi temp, 3				; Check if temp equals 3
		brne numberFour			; If temp is not 3 continue with 4
		ldi temp, 0b01101101	; Load the segments for 3 into temp
		rjmp numberDone			; Jump to numberDone if this is te right number	

	numberFour:
		cpi temp, 4				; Check if temp equals 4
		brne numberFive			; If temp is not 4 continue with 5
		ldi temp, 0b00101110	; Load the segments for 4 into temp
		rjmp numberDone			; Jump to numberDone if this is te right number	
	
	numberFive:			
		cpi temp, 5				; Check if temp equals 5
		brne numberSix			; If temp is not 5 continue with 6
		ldi temp, 0b01101011	; Load the segments for 6 into temp
		rjmp numberDone			; Jump to numberDone if this is te right number

	numberSix:				
		cpi temp, 6				; Check if temp equals 6
		brne numberSeven		; If temp is not 6 continue with 7
		ldi temp, 0b01111011	; Load the segments for 6 into temp
		rjmp numberDone			; Jump to numberDone if this is te right number
	
	numberSeven:
		cpi temp, 7				; Check if temp equals 7
		brne numberEight		; If temp is not 7 continue with 8
		ldi temp, 0b00100101	; Load the segments for 7 into temp	
		rjmp numberDone			; Jump to numberDone if this is te right number

	numberEight:
		cpi temp, 8				; Check if temp equals 8
		brne numberNine			; If temp is not 8 continue with 9
		ldi temp, 0b01111111	; Load the segments for 8 into temp
		rjmp numberDone			; Jump to numberDone if this is te right number

	numberNine:
		cpi temp, 9				; Check if temp equals 9
		brne numberClear		; If temp is not 9 go to numberTen
		ldi temp, 0b01101111	; Load the segments for 9 into temp
		rjmp numberDone			; Jump to numberDone if this is te right number

	numberClear:
		ldi temp, 0b00000000	; Send nothing to indicate something goes wrong
		rjmp numberDone			; Jump to numberDone 	

 numberDone:
	rcall transmit			; Tranmit segment with the right bytes
	ret
	
 ; Switch routines
 ; External input will be done by these routines	
 checkSwitches:
	in temp, PINA			; Read port A as input (Switches)
	cpi temp, 0xfe			; Check if switch 0 is pressed
	breq switchZero			; Branch to switch 0 subroutine
	cpi temp, 0xfd			; Check if switch 1 is pressed
	breq switchOne			; Branch to switch 1 subroutine
	ret

 alarmOff:
	cbr state, 0b00001001	; Turn all bits off to make the alarm stop
	ret

 toggleAlarm:
	ldi temp, 0b00000001	; Load the indicator bit
	sbrs state, 3			; Check if the alarm is sounding or not
	eor state, temp			; Skip if the alarm is sounder else turn off the indicator bit
	ret				

 switchZero:
	rcall alarmOff				; Turn off the alarm when its sounding
	sbrs setting, 5				; Check if the first 2 bits are set 
	ret							; If set then return from subroutine
	sbrc setting, 0 			; Check if the 0 bit is cleared
	rjmp buttonIncSecs			; If its not cleared increase seconds
	sbrc setting, 1				; Check if the 1 bit is cleared 
	rjmp buttonIncMins			; If its not cleared increase minutes
	sbrc setting, 2				; Check if the 2 bit is cleared
	rjmp buttonIncHours			; If its not cleared increase hours
	sbrc setting, 3				; Check if the 3 bit is cleared
	rjmp buttonIncAlarmMins		; If its not cleared increase alarm minutes
	sbrc setting, 4				; Check if the 4 bit is cleared 
	rjmp buttonIncAlarmHours	; If its not cleared increase alarm hours
	ret

 buttonIncSecs:
	rcall incSecs			; Increase seconds by calling the incSec routine
	ret
 
 buttonIncMins:
	rcall incMins			; Increase minutes by calling the incMins routine
	ret

 buttonIncHours:
	rcall incHours			; Increase hours by calling the incHours routine
	ret

 buttonIncAlarmMins:		
	rcall incAlarmMins		; Increase alarm minutes by calling the incAlarmMins routine
	ret

 buttonIncAlarmHours:
	rcall incAlarmHours		; Increase alarm hours by calling the incAlarmHours routine
	ret

 switchOne:					
	sbrc setting, 3		    ; Check if the first 2 bits are cleared
	rjmp checkSetting		; Jump to the checkSetting routine
	rcall toggleAlarm		; Toggle the alarm on/off
	ret

 checkSetting:
	sbrc setting, 0					; Check if the 0 bit is cleared
	rjmp secsJumpMins				; Jump from seconds to minutes
	sbrc setting, 1					; Check if the 1st bit is cleared 
	rjmp minsJumpHours				; Jump from minutes to hours
	sbrc setting, 2					; Check if the 2nd bit is cleared
	rjmp hoursJumpAlarmMins			; Jump from hours to alarm minutes
	sbrc setting, 3					; Check if the 4th bit is cleared
	rjmp alarmMinsJumpAlarmHours	; Jump from alarm minutes to alarm hours
	sbrc setting, 4					; Check if the 5th bit is cleared
	rjmp alarmHoursJumpStart		; Finish hours and start the clock
	ret
 
 secsJumpMins:
	ldi temp, 0b00000011	; Load 3 into temp, turn bit 0 off and bit 1 on with EOR
	eor setting, temp		; Preform a Exclusive OR to get the right bits set
	ret

 minsJumpHours:
	ldi temp, 0b00000110	; Load 6 into temp, turn bit 1 off and bit 2 on with EOR
	eor setting, temp		; Preform a exclusive OR to get the right bits set
	ret

 hoursJumpAlarmMins:
	ldi temp, 0b00001100	; Load the 3rd and 5th bit into temp to turn off bit 3 and turn on bit 5
	eor setting, temp		; Preform a exclusive OR to get the right bits set
	ret

 alarmMinsJumpAlarmHours:
	ldi temp, 0b00011000	; Load the 5th and 6th bit into temp to turn off bit 5 and turn on bit 6
	eor setting, temp
	ret

 alarmHoursJumpStart:
	ldi setting, 0b00000000	; Load 0 into setting to stop setting time and alarm and let the clock run
	ret