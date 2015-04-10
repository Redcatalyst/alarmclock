/*
 * Wekker.asm
 *
 *  Created: 8-4-2015 14:07:18
 *   Author: Rick van der Poel en Erik Ottema
 */ 

 .include "m32def.inc"

 .def secs = r16		; Seconds count
 .def mins = r17		; Minutes count
 .def hours = r18		; Hours count

 .def temp = r19		; Save temporary values

 .def alarmsecs = r21	; Seconds alarm is set on
 .def alarmmins = r22	; Minutes alarm is set on
 .def alarmhours = r23  ; Hours alarm is set on

 .def alarmstate		; State of alarm
 .def timeset			; Blinking of time that needs to be set

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
 ldi r16, high(RAMEND)	; Load the high value for the stackpointer
 ldi SPH, r16			; Output high value for the stackpointer
 ldi r16, low(RAMEND)	; Load the low value for the stackpointer
 ldi SPL, r16			; Output low value for the stackpointer

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
 ldi temp, (1 << CS12) | (1 << WWGM12)		; Set prescaler to 256 and timer to CTC mode
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
	rjmp loop								; Wait for interupts

 TIMER1_COMP_ISR:							; ISR wordt elke seconde aangeroepen
	rcall transmit							; Call subroutine transmit
	rcall buttonCheck						; Call subroutine buttonCheck
	rcall setDisplay						
	rcall sendToDisplay
	rcall checkAlarm
	rcall sendAlarmState
	reti									; return from interupt

 transmit:
	sbis UCSRA, UDRE
	rjmp transmit
	out UDR, temp
	ret

; Check for the alarm time
 checkAlarm:
	sbrs state, 0							; Check if the alarm is set or not
	rjmp noAlarm							; Jump to noAlarm when alarm has not been set

	cp secs, alarmsecs						; Compare if current seconds are the same of the alarm seconds
	brne noAlarm							; Jump to noAlarm if the secs dont match

	cp mins, alarmmins						; Compare if current minutes are the same of the alarm minutes
	brne noAlarm							; Jump to noAlarm if the minutes dont match

	cp hours, alarmhours					; Compare if current hours are the same of the alarm hours
	brne noAlarm							; Jump to noAlarm if the hours dont match

	rcall soundTheAlarm						; All checks have been passed. Make the alarm go off. 
 
 ; When the alarm isnt set
 noAlarm:									; Do nothing because the alarm time has not been reached
	ret										; Return to interupt handling

 ; When the alarm is set
 soundTheAlarm:
	sbr alarmstate, 0b00001000				; Set bits in alarmstate register so that the alarm goes off
	ret										; Return to interupt handling
	
 ;
 toggleSegments:
	ldi temp, 0b00001000					; Load 8 into temp
	eor state, temp							; Preform an eor (switch bytes) with temp

 sendState:
	rcall toggleSegements					; We have to update the segments
	mov temp, alarmstate					; Copy state to the temp register
	rcall transmit							; Send the bytes away
	ret

 sendDisplay:
	cp timeset, secs						; Compare timeset with secs register
	brge sendEmpty							; Is it more or equal to secs

	mov temp, hours							; Copy hours to the temp register
	rcall splitParts						; Split the parts and send them to the display
	mov temp, mins							; Copy minutes to the temp register
	rcall splitParts						; Split the parts and send them to the display 
	mov temp, secs							; Copy seconds to the temp register
	rcall splitParts						; Split the parts and send them to the display

sendEmpty:
	sbrc timeset, 0							; Check if the zero bit is cleared
	rjmp sendSecsFlashing					; Zerobit is set, so we are adjusting the seconds
	sbrc timeset, 1							; Check if the one bit is cleared
	rjmp sendMinsFlashing					; Onebit is set, so we are adjusting the minutes
	sbrc timeset, 2							; Check if the two bit is cleared 
	rjmp sendHoursFlashing					; Twobit is set, so we are adjusting the hours
	ret

sendSecsFlashing:							; 
	ldi temp, 0								; Load 0 into temp
	rcall tranmit							; Send temp away 4 times (Result 4 times an empty char on segement 7)
	rcall tranmit
	rcall tranmit
	rcall tranmit
	mov temp, secs							; Copy secs to temp
	rcall splitParts						; Send the seconds away
	ret

sendMinsFlashing:							
	ldi temp, 0								; Load 0 into temp
	rcall transmit
	rcall transmit	
	mov temp, mins							; Copy mins to temp
	rcall splitParts						; Send the mins away
	ldi temp, 0								; Load 0 into temp
	rcall transmit
	rcall transmit
	ret

sendHoursFlashing:
	mov temp, hours							; Copy hours into temp
	rcall splitParts						; Send the hours away
	ldi temp, 0								; load 0 into temp
	rcall transmit
	rcall transmit
	rcall transmit
	rcall transmit					










