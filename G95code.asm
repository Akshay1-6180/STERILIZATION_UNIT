#make_bin#

; BIN is plain binary format similar to .com format, but not limited to 1 segment;
; All values between # are directives, these values are saved into a separate .binf file.
; Before loading .bin file emulator reads .binf file with the same file name.

; All directives are optional, if you don't need them, delete them.

; set loading address, .bin file will be loaded to this address:
#LOAD_SEGMENT=0500h#
#LOAD_OFFSET=0000h#

; set entry point:
#CS=0500h#	; same as loading segment
#IP=0000h#	; same as loading offset

; set segment registers
#DS=0500h#	; same as loading segment
#ES=0500h#	; same as loading segment

; set stack
#SS=0500h#	; same as loading segment
#SP=FFFEh#	; set to top of loading segment

; set general registers (optional)
#AX=0000h#
#BX=0000h#
#CX=0000h#
#DX=0000h#
#SI=0000h#
#DI=0000h#
#BP=0000h#

; add your code here

;PB7 - sterilise input
;PB5 - end input
;PB2 - level1
;PB3 - level2  
;PB5 - level3
;PB7 - level4

;PC4 - GATE0
;PC3 - GAte1
;PC7 - staus and lock led
;PC5 - Door motor
;PC2 - motor control for 2 min
;PC1 - heater

;PA0 - PA7 - analog inputs
jmp		st1
;jmp st1 - takes 3 bytes followed by nop that is 4 bytes
         nop  
;int 1 is not used so 1 x4 = 00004h - it is stored with 0
         dw      0000
         dw      0000   
;eoc - is used as nmi - ip value points to ad_isr and cs value will
;remain at 0000
         dw      ad_isr
         dw      0000
;int 3 to int 255 unused so ip and cs intialized to 0000
;from 3x4 = 0000cH		 
		 db     1012 dup(0)

st1:
	cli

;initialize es, ds, ss to start of RAM
	mov		ax, 0200h
	mov		ds, ax
	mov		es, ax
	mov		ss, ax
	mov		sp, 0FFFEh    
	
    
;initialize values for constants
;8255
	porta	equ		00h
	portb	equ		02h
	portc	equ		04h
	creg1	equ		06h
;8253-1	
	cnt0	equ		08h
	cnt1	equ		0Ah
	cnt2	equ		0Ch
	creg2	equ		0Eh 
	
;8259
    A0      equ     10h
    A1      equ     12h
    
mov al,00010011b      ;icw1
out 10h,al

mov al,00010000b      ;icw2
out 12h,al 

mov al,00000001b      ;icw4
out 12h,al 

mov al,11111110b      ;ocw1
out 12h,al





;Port A and Port B are input, Port C is output   
;initally all port B are high
mov al,10010010b
out creg1,al    ;configure 8255  

mov al,00110100b      ;configure counter 0 of 8253A for timer(mode2)
out creg2,al

mov al,01110010b      ;configure counter 1 of  8253A for PWM(mode 1)
out creg2,al
  
;check if door is open or closed
chkdr:
	in al,portb            ; for 0 input door is closed
	and al,01h
	jnz chkdr

;switch off heater
mov al,00000000b    	;( pc1- heater =0)        
out portc,al                       
 
; maintaining temperature at 30 degrees
start:
	in al, porta
	cmp al,38                ; if temperatur is less than 30  switch on heater
	jge x1
	mov al,00000010b     ;heater(pc 1) on
	out portc,al
	jmp start 

;if greater than 30 degrees switch of the heater	
x1:
	mov al,00000000b    ;heater(pc 1) off
	out portc,al  
	
;checking the level switch and if the user pressed sterilize         
	
	
level:
	in al,portb
	mov ah,al
	and ah,01000000b
	jnz lvl3
	mov cl,04h
	jmp end10     
	
lvl3:
	mov ah,al
	and ah,00010000b
	jnz lvl2
	mov cl,03h
	jmp end10       
	
lvl2:
	mov ah,al
	and ah,00001000b
	jnz lvl1
	mov cl,02h
	jmp end10

;level 1 is default	
lvl1:
	mov cl,01h     
	

;checking if sterilise is pressed else open the door if end is pressed
end10:
	in al,portb
	mov ah,al
	and ah,80h 			; sterlize at 80h
	jz steril
	mov ah,al
	and ah,20h      	   ;end = 20h
	jz endster
	jmp start  
	
endster:

;end switch debounce
call delay_20ms

in al,portb
and al,20h
jnz start

;if the user has pressed end it opens the door
door:
	mov al,00100000b
	out portc,al           ;switching motor on( pc 5)  to open the door in clockwise
	call delay_3s           ;out 1 (pb1) 

;delay 3s given to open the door and then switch off the motor           
mov al,00000000b      ;switching motor off( pc 5)
out portc,al

;after the user upens the door it goes back to  the begining to check if the door is closed or not

jmp chkdr

;user selected sterilize
steril:                ;sterilize pressed
	call delay_20ms        ;de-bounce
	in al,portb
	and al,80h
	jnz start
	mov al,10000000b    ;lock door( pc 7)/ status on led
	out portc,al

heat:
	mov al,10000010b    ; heater (pc 1)-on and swtiches on event the status leds
	out portc,al 

waits:						   	;20h=end
	in al, porta
	cmp al,154            ; waiting for 120 degree celsius to be recorded by the sensor
	jle waits 

mov di,1	
mov al,0E0h			
out cnt0,al           ;2 minutes(12000<2EE0> since clk is 100Hz 
mov al,2Eh
out cnt0,al
mov al,10010000b 	;  pulse to gate 1 (pc4) for the gate signal and the status led
out portc,al
nop
nop

mov al,10000010b	;  pulse to motor<pc2> to cool in case temperature rises and status led

out portc,al  

;switched off the heater if temperature is greater than 120
temp120:
	in al, porta
	cmp al,154          ; mantaining temperature=120 degrees
	jle htron
	mov al,10000000b    ;heater(pc 1) off
	out portc,al  

;switched on the heater if temperature is lesser than 120
htron:
	mov al,10000010b    ;heater(pc 1) on and status led
	out portc,al
	cmp di,0            ; checks if interupt is raised
	jnz temp120

cmp cl,1            ;count of level button
jz s1
cmp cl,2
jz s2
cmp cl,3
jz s3
cmp cl,4
jz s4


s1:
	mov al,02h            ;given count 2 (duty cycle:80%) for the 3 min cooling
	out cnt1,al
	mov al,00h 
	out cnt1,al
	mov al,50h           ;3 minutes(18000<4650h> since clk is 100Hz 
	out cnt0,al
	mov al,46h           
	out cnt0,al

fan1:
	mov di,1  
	mov al,10011000b     ;pulse to gate 1 (pc3) to switch on the motor and PC4 to start the counting
	out portc,al
	nop
	nop
	mov al,10010000b     ;pulse   ; for the mode 1 gate signal
	out portc,al 
x4: cmp  di,0
    jnz  x4
	jmp out1

s2:
	mov al,04h            ;given count 4 (duty cycle:60%) for the 5 min cooling
	out cnt1,al
	mov al,00h 
	out cnt1,al
	mov al,30h           ;5 minutes(30000<7530h> since clk is 100Hz 
	out cnt0,al
	mov al,75h           
	out cnt0,al

fan2:
	mov di,1  
	mov al,10011000b     ;pulse to gate 1 (pc3) to switch on the motor and PC4 to start the counting
	out portc,al
	nop
	nop
	mov al,10010000b     ;pulse   ; for the mode 1 gate signal
	out portc,al 
x5: cmp  di,0
    jnz  x5
	jmp out1

s3:
	mov al,06h            ;given count 6 (duty cycle:40%) for the 7 min cooling
	out cnt1,al
	mov al,00h 
	out cnt1,al
	mov al,60h           ;7 minutes(42000<A460h> since clk is 100Hz 
	out cnt0,al
	mov al,0A4h           
	out cnt0,al

fan3:
	mov di,1  
	mov al,10011000b     ;pulse to gate 1 (pc3) to switch on the motor and PC4 to start the counting
	out portc,al
	nop
	nop
	mov al,10010000b     ;pulse   ; for the mode 1 gate signal
	out portc,al 
x6: cmp  di,0
    jnz  x6
	jmp out1
	
s4:
	mov al,01h            ;given count 9 (duty cycle:10%) for the 10 min cooling
	out cnt1,al
	mov al,00h 
	out cnt1,al
	mov al,60h           ;10 minutes(60000<EA60h> since clk is 100Hz 
	out cnt0,al
	mov al,0EAh           
	out cnt0,al

fan4:
	mov di,1  
	mov al,10011000b     ;pulse to gate 1 (pc3) to switch on the motor and PC4 to start the counting
	out portc,al
	nop
	nop
	mov al,10010000b     ;pulse   ; for the mode 1 gate signal
	out portc,al 
x7: cmp  di,0
    jnz  x7
	jmp out1
	

    

out1:
	mov al,10000000b     ;switching motor off (pc 3)
	out portc,al
	mov al,00100000b     ;opening the door and switching off the leds
	out portc,al      

	in al,portb
	mov ah,al           ;checks if the user pressed end 
	and ah,20h
	jz endster						   	;20h=end

	jmp start 


delay_20ms proc near    ;subroutine
	mov  cx,5555        ;
xn: loop xn             ;.2 us is the clock frequency 
	ret  

;delay calculation
; no. of cycles for loop = 18 if taken/ 5 if not taken = 5554x 18 +5
;no. of cycles for ret 16
;no. of cycles for call 19
;no. of cycles for mov 4  
;clock speed  MHz - 1 clock cycle 0.2us
;total no.cycles delay =  clkcycles for call + mov cx + (content of cx-1)*18+5 + ret
;= (19 +4 + 18*5554 +5+16 )0.2us = 20003.2us = 20ms
	
delay_3s proc near    ;subroutine
	mov dl,17
xm: mov cx,50000 ; delay generated will be approx 0.45 secs
xo: loop xo
    dec  dl
    jnz  xm
    ret 
	                ; 
delay_3s endp

;delay calculation
; no. of cycles for loop = 18 if taken/ 5 if not taken = 5554x 18 +5
;no. of cycles for ret 16
;no. of cycles for call 19
;no. of cycles for mov 4  
;clock speed  MHz - 1 clock cycle 0.2us
;total no.cycles delay =  clkcycles for call + mov cx + (content of cx-1)*18+5 + ret
;= (19 +4 + 18*49999 +5+16 )0.2us = .18s
;.18*17 = 3s

ad_isr:   
          push      ax
          push      bx  
;di is decremented to show nmi isr is executed
          dec       di
          mov al,00000000b    ; swtiched off the gate0 to switch off the timer
	      out portc,al
	      mov al,10100000b      ;0cw2
	      out 10h,al
		  pop       bx
		  pop       ax
          iret
