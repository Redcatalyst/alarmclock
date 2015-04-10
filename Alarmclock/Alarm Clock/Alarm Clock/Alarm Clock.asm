/*
 * Alarm_Clock.asm
 *
 *  Created: 10-4-2015 16:02:57
 *   Author: Rick
 */ 

 .NOLIST
 .include "m32def.inc"

 .LIST
 .def secs = r16		; Seconds count
 .def mins = r17		; Minutes count
 .def hours = r18		; Hours count

 .def temp = r19		; Save temporary values
 .def temp2 = r20		; Save secondairy temp values

 .def alarmsecs = r21	; Seconds alarm is set on
 .def alarmmins = r22	; Minutes alarm is set on
 .def alarmhours = r23  ; Hours alarm is set on

 .def alarmstate = r24		; State of alarm
 .def timeset = r25			; Blinking of time that needs to be set

 .org 0x0000			; On reset 
 rjmp init				; Jump to init

 ; Init program
 init:
 ldi secs, 0
 ldi mins, 0
 ldi hours, 0
 ldi alarmsecs, 0
 ldi alarmmins, 0
 ldi alarmhours, 0
 ldi alarmstate, 0x00
 ldi timeset, 0x00

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

 ldi temp, high(43200)	; Load the high value for the timer 
 out OCR1AH, temp		; Output high value for the timer
 ldi temp, low(43200)	; Load the low value for the timer
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

 clr temp
 ldi temp, (1 << URSEL) | (1 << USBS) | (3 << UCSZ0)
 out UCSRC, temp
 clr temp

 loop:
	rjmp loop			; Wait for interupts

 TIMER1_COMP_ISR:		; ISR wordt elke seconde aangeroepen
	rcall incTime		; Handle the time on the display
	reti				; Return from interupt

 incTime:
	ldi temp2, 0		; Load 0 for comparison
	rcall incSecs		; Increase seconds
	cpse temp, temp2	; Skip next part if temp isnt 1 (i.e. seconds have not reached 60)
	rcall incMins		; Increase minutes
	cpse temp, temp2	; Skip next part if temp isnt 1 (i.e. minutes have not reached 60)
	rcall incHours		; Increase hours
	ret

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
	clr mins			; Clear secs (We reached 60)
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

 sendSegments:
	cpi temp, 0			; Check if temp equals 0
	brne segment		; 