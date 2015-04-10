/*
 * Alarm_Clock.asm
 *
 *  Created: 10-4-2015 16:02:57
 *   Author: Rick
 */ 

 .include "m32def.inc"

 .def secs = r16		; Seconds count
 .def mins = r17		; Minutes count
 .def hours = r18		; Hours count

 .def temp = r19		; Save temporary values
 .def temp2 = r20		; Save secondairy temp values

 .def alarmsecs = r21	; Seconds alarm is set on
 .def alarmmins = r22	; Minutes alarm is set on
 .def alarmhours = r23  ; Hours alarm is set on

 .def state = r24		; 7th byte state
 .def timeset = r25		; Blinking of time that needs to be set

 .org 0x0000			; On reset 
 rjmp init				; Jump to init

 .org OC1Aaddr
 rjmp TIMER1_COMP_ISR

 ; Init program
 init:
 ldi secs, 0
 ldi mins, 0
 ldi hours, 0

 ldi alarmsecs, 0
 ldi alarmmins, 0
 ldi alarmhours, 0

 ldi state, 0x00
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

 ldi temp, (1 << URSEL) | (1 << USBS) | (3 << UCSZ0) ; Frameformat: 8data, 2stop bit
 out UCSRC, temp
 ldi temp, 0x00

 loop:
	rjmp loop			; Wait for interupts
 
 ; Internal interupt
 TIMER1_COMP_ISR:				; ISR wordt elke seconde aangeroepen
	ldi temp, 0x80				; Load 0x80 in to temp
	rcall transmit				; Send 0x80 to the display to remove so far send bytes
	rcall incTime				; Let the time tick
	rcall sendTime				; Handle the time on the display
	rcall sendState				; Send the state of the 7th byte
	reti						; Return from interupt
 
 ; Transmit data
 transmit:
    sbis UCSRA, UDRE	; wait for an empty transmit buffer 
	rjmp transmit		; This is skipped when UDRE flag is cleared, if not then it jumps back to transmit
	out UDR, temp		; Send the temp date over Tx
	ret					; Return from subroutine
 
 toggleColons:
	ldi temp, 0b00000110
	eor state, temp
	ret
 
 sendState:				
	rcall toggleColons		
	mov temp, state	
	rcall transmit
	ret
 
 sendTime:
	mov temp, hours		; Copy hours into temp
	rcall splitNumber	; Separate the numbers and send them to display
	mov temp, mins		; Copy minutes into temp
	rcall splitNumber	; Separate the numbers and send them to display
	mov temp, secs		; Copy seconds into temp
	rcall splitNumber	; Separate the numbers and send them to display
	ret
 
 ; Increase time subroutines
 ; These routines manage the timetable's 
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
		brne numberTen			; If temp is not 9 go to numberTen
		ldi temp, 0b01101111	; Load the segments for 9 into temp
		rjmp numberDone			; Jump to numberDone if this is te right number

	numberTen:
		cpi temp, 10
		brne numberClear
		ldi temp, 0b00000000	
		rjmp numberDone

	numberClear:
		ldi temp, 0b00000000	; Send nothing to indicate something goes wrong
		rjmp numberDone			; Jump to numberDone 	

 numberDone:
	rcall transmit			; Tranmit segment with the right bytes
	ret
		