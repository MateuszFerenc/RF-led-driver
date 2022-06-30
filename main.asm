;
; RF_led_driver.asm
;
; Created: 18.04.2022 01:22:51
; Author : Mateusz
;


.NOLIST
			.INCLUDE "m48def.inc"
.LIST

			#define		ITOA(i) ((i % 9) + 48)		; one int to one char (ASCII) int (0-9) => (48-57) ASCII
			#define		FLASH_ADDR(dw)	(dw << 1)
.DEF		machine_cnt		=		r25

.DSEG
			.ORG SRAM_START
v_PB0_last:		.BYTE		1
v_hi_count:		.BYTE		1
v_lo_count:		.BYTE		1
v_uart_tx:		.BYTE		30
v_uart_tcnt:	.BYTE		1
v_uart_tsize:	.BYTE		1
v_uart_rx:		.BYTE		10
v_uart_rflag:	.BYTE		1
v_rc_buff:		.BYTE		4
v_rc_cnt:		.BYTE		1

.CSEG
			.ORG $0000
			RJMP		reset_handler
			RJMP		empty_interrupt_handler
			RJMP		empty_interrupt_handler
			RJMP		pcint0_handler
			RJMP		empty_interrupt_handler
			RJMP		empty_interrupt_handler
			RJMP		empty_interrupt_handler
			RJMP		empty_interrupt_handler
			RJMP		empty_interrupt_handler
			RJMP		empty_interrupt_handler
			RJMP		empty_interrupt_handler
			RJMP		timer1_compa_handler
			RJMP		empty_interrupt_handler
			RJMP		empty_interrupt_handler
			RJMP		timer0_compa_handler
			RJMP		empty_interrupt_handler
			RJMP		empty_interrupt_handler
			RJMP		empty_interrupt_handler
			RJMP		empty_interrupt_handler
			RJMP		empty_interrupt_handler
			RJMP		empty_interrupt_handler
			RJMP		empty_interrupt_handler
			RJMP		empty_interrupt_handler
			RJMP		empty_interrupt_handler
			RJMP		empty_interrupt_handler
			RJMP		empty_interrupt_handler

reset_handler:
			LDI YH, HIGH(RAMEND)
			OUT SPH, YH
			LDI YL, LOW(RAMEND)
			OUT SPL, YL

			LDI XH, $01
			LDI XL, $00
			CLR r1
		ram_clr_loop:
			ST X+, r1
			CP YL, XL
			CPC YH, XH
			BRSH ram_clr_loop
			CLR machine_cnt

main:
			RCALL main_init
	main_loop:
			LDI ZH, HIGH(tasks << 1)
			LDI ZL, LOW(tasks << 1)
			MOV r16, machine_cnt
			LSL r16
			ADD ZL, r16
			CLR r16
			ADC ZH, r16
			LPM YL, Z+
			LPM YH, Z
			MOVW Z, Y
			IJMP

	main_continue:
			CPI machine_cnt, tasks_number-1
			BRNE PC+2
			SER machine_cnt
			INC machine_cnt

			WDR
			RJMP main_loop

main_init:
			CLI
			WDR

			IN r16, MCUSR
			LDI ZH, HIGH(c_reset_array << 1)
			LDI ZL, LOW(c_reset_array << 1)
			ANDI r16, $0E
			SBRC r16, 3
			SUBI r16, 2
			ADD ZL, r16
			CLR r16
			ADC ZH, r16
			LPM r18, Z+
			LPM r19, Z
			MOVW Z, r18:r19
			LDI r16, $05
			RCALL UART_fill

			LDI r16, $0F
			OUT MCUSR, r16

			LDI r16, $12
			OUT DDRB, r16
			LDI r16, $01
			OUT DDRB, r16

			;LDI r16, $41
			;STS TCCR1A, r16
			;LDI r16, $12
			;STS TCCR1B, r16
			;LDI r16, 0
			;STS OCR1AH, r16
			;STS OCR1AL, r16
			;LDI r16, $02
			;STS TIMSK1, r16

			;LDI r16, $01
			;OUT TCCR0A, r16
			;LDI r16, $02
			;OUT TCCR0B, r16
			;STS TIMSK0, r16
			;LDI r16, $09
			;OUT OCR0A, r16

			LDI r16, 51				; baudrate 9600
			LDI r17, 0
			RCALL UART_init

			LDI r16, $E1
			STS PRR, r16

			WDR
			LDI r16, $0A
			STS WDTCSR, r16

			SEI
			RET

UART_init:						; r16:r17 - UBRR value
			STS UBRR0H, r17
			STS UBRR0L, r16
			;LDI r16, (1<<U2X0)
			;STS UCSR0A, r16
			LDI r16, (1<<USBS0)|(3<<UCSZ00)
			STS UCSR0C,r16
			LDI r16, (1<<RXEN0)|(1<<TXEN0)
			STS UCSR0B,r16
			RET

UART_fill:						; Z : data pointer ( SREG(T) = 0 - flash/ 1 - ram )
								; r16 - range ( r16(7) = 0 - update uart_tsize / 1 - do not update), r16(6:0) - 0-127 characters
			STS v_uart_tcnt, r1
			LDI XH, HIGH(v_uart_tx)
			LDI XL, LOW(v_uart_tx)
			LDS r17, SREG
			SBRC r17, SREG_T
			RJMP use_ram

	flash_LD:
			LPM r17, Z+
			ST X+, r17
			; TODO do loading from flash in range  
			CPI r16, $7F
			BRSH PC+2
			DEC r16
			RJMP flash_LD
			CPI r17, '\n'
			BRNE flash_LD
			CPI r16, $80
			RJMP PC+3
			SUBI XL, LOW(v_uart_tx)
			STS v_uart_tsize, XL
			RET

	use_ram:
			;CBR XH, $80
	ram_LD:
			LD r17, Z+
			ST X+, r17
			DEC r16
			BRMI PC+2
			BRNE ram_LD
			RET

uart_transmit:
			LDS r16, UCSR0A
			ANDI r16, (1<<UDRE0)
			BREQ no_transfer
			LDS r16, v_uart_tsize
			TST r16
			BREQ no_transfer
			LDS r17, v_uart_tcnt
			LDI XL, LOW(v_uart_tx)
			LDI XH, HIGH(v_uart_tx)
			ADD XL, r17
			ADC XH, r17
			SBC XH, r17
			DEC r16
			INC r17
			STS v_uart_tsize, r16
			STS v_uart_tcnt, r17
			LD r16, X
			STS UDR0, r16
		no_transfer:
			RET

timer0_compa_handler:
			;PUSH r16
			;SBIC PORTB, 0
			;RJMP PB0_Hi
			
	PB0_Hi:
			;POP r16
			RETI

timer1_compa_handler:
			RETI

pcint0_handler:
			RETI

empty_interrupt_handler:
			RETI

task0:
			RCALL uart_transmit
			RJMP main_continue

task1:
			NOP
			NOP
			NOP
			NOP
			NOP
			NOP
			NOP
			RJMP main_continue

; constants

tasks:			.DW		task0, task1
.EQU			tasks_number = 2

; Device constants
c_DEV_name:		.DB		"SemiSmart Home controller", '\n'
c_DEV_date:		.DB		__DATE__, '\n'

; RESET sources
c_PO_reset:		.DB		"Power-on reset", '\n', 0
c_EXT_reset:	.DB		"External reset", '\n', 0
c_BR_reset:		.DB		"Brown-out reset", '\n'
c_WD_reset:		.DB		"Watchdog reset", '\n', 0
c_reset_array:	.DW		FLASH_ADDR(c_PO_reset), FLASH_ADDR(c_EXT_reset), FLASH_ADDR(c_BR_reset), FLASH_ADDR(c_WD_reset)

; Smoe text constants
c_OK:			.DB		"OK!", '\n'
c_EEROR:		.DB		"ERROR", '\n'
c_DUMPING:		.DB		"Dumping memory...", '\n'
c_DECODED:		.DB		"Decoded data:", '\n'