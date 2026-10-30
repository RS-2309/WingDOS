bits 16
org 100h

jmp start

; ============================================================
; FLAPPY BIRD - 16-bit DOS / NASM / VGA MODE 13h
; Controls: SPACE = flap, ESC = exit
; Game over: press ESC to exit
; ============================================================

SCREEN_W       equ 320
SCREEN_H       equ 200
BUFFER_PARAS   equ 4000            ; 64,000 bytes
BIRD_X         equ 68
PIPE_W         equ 32
GAP_H          equ 70

bird_y         dw 92              ; bird top coordinate
bird_vy        dw 0
pipe_x         dw 288
pipe_speed     db 3              ; initial movement: 3 pixels per frame
next_speedup   dw 3              ; increase speed every 3 points
pipe_gap_top   dw 62
score          dw 0
scored         db 0
game_over      db 0
back_segment   dw 0
frame_counter  dw 0
random_state   dw 0A53Dh
draw_color     db 0
lower_pipe_y   dw 0
lower_pipe_h   dw 0
font_index     dw 0
text_x         dw 0
text_y         dw 0
text_offset    dw 0
text_bits      db 0
score_digits   db '00000',0

score_text     db 'SCORE: ',0
gameover_text  db 'GAME OVER',0
exit_text      db 'PRESS ESC TO EXIT',0

; ------------------------------------------------------------
; Entry / setup
; ------------------------------------------------------------
start:
    push cs
    pop ds

    ; A DOS .COM program initially owns almost all available DOS memory.
    ; Shrink our own block first so AH=48h can allocate the framebuffer.
    mov ax, cs
    mov es, ax
    mov bx, resident_end
    add bx, 15
    shr bx, 4
    mov ah, 4Ah
    int 21h
    jc no_memory

    ; The old DOS stack was near the end of the original large block.
    ; Move it into the 1 KB stack area reserved at the end of this program.
    cli
    mov ax, cs
    mov ss, ax
    mov sp, stack_top
    sti

    ; Allocate 64,000 bytes for the off-screen framebuffer.
    mov bx, BUFFER_PARAS
    mov ah, 48h
    int 21h
    jc no_memory
    mov [back_segment], ax

    ; Set VGA 320x200x256.
    mov ax, 0013h
    int 10h

    ; Palette entry 9 = light sky blue (RGB 135,206,235; VGA 6-bit DAC).
    mov dx, 03C8h
    mov al, 9
    out dx, al
    inc dx
    mov al, 34
    out dx, al
    mov al, 52
    out dx, al
    mov al, 59
    out dx, al

    ; Hide text cursor.
    mov ah, 01h
    mov cx, 2000h
    int 10h

    call seed_random

main_loop:
    call poll_input
    cmp al, 1
    je exit_game

    cmp byte [game_over], 1
    je game_over_loop

    call update_game
    cmp byte [game_over], 1
    je game_over_loop

    call render_frame
    jmp main_loop

game_over_loop:
    call stop_speaker
    call render_frame
    call draw_game_over_text
    call present_buffer
.game_over_wait:
    call poll_input
    cmp al, 1
    jne .game_over_wait
    jmp exit_game

no_memory:
    mov dx, memory_error
    mov ah, 09h
    int 21h
    mov ax, 4C01h
    int 21h

memory_error db 'Not enough DOS memory for framebuffer.$'

; ------------------------------------------------------------
; Input: AL=1 if ESC was pressed
; ------------------------------------------------------------
poll_input:
    xor al, al
    mov ah, 01h
    int 16h
    jz .done
    xor ah, ah
    int 16h
    cmp al, 27
    jne .flap_check
    mov al, 1
    ret
.flap_check:
    cmp al, ' '
    jne .done
    cmp byte [game_over], 1
    je .done
    mov word [bird_vy], -5
.done:
    xor al, al
    ret

; ------------------------------------------------------------
; Game physics, pipe movement, scoring, collision
; ------------------------------------------------------------
update_game:
    ; Gravity with terminal velocity.
    inc word [bird_vy]
    cmp word [bird_vy], 5
    jle .velocity_ok
    mov word [bird_vy], 5
.velocity_ok:
    mov ax, [bird_y]
    add ax, [bird_vy]
    mov [bird_y], ax

    ; Screen boundaries.
    cmp word [bird_y], 2
    jl .dead
    cmp word [bird_y], 182
    jg .dead

    ; Move pipe left using the current speed.
    xor ax, ax
    mov al, [pipe_speed]
    sub word [pipe_x], ax

    ; Award score once when the pipe passes the bird.
    cmp byte [scored], 1
    je .check_reset
    mov ax, [pipe_x]
    add ax, PIPE_W
    cmp ax, BIRD_X
    jge .check_reset
    inc word [score]
    mov byte [scored], 1

    ; Increase difficulty every 3 points, up to 6 pixels per frame.
    mov ax, [score]
    cmp ax, [next_speedup]
    jb .speed_checked
    cmp byte [pipe_speed], 6
    jae .speed_checked
    inc byte [pipe_speed]
    add word [next_speedup], 3
.speed_checked:
    call beep

.check_reset:
    cmp word [pipe_x], 4
    jg .collision
    mov word [pipe_x], 288
    mov byte [scored], 0
    call choose_gap

.collision:
    ; Horizontal overlap between bird [68,86) and pipe [x,x+32).
    mov ax, [pipe_x]
    cmp ax, BIRD_X+18
    jge .done
    add ax, PIPE_W
    cmp ax, BIRD_X
    jle .done

    ; Bird must fit entirely inside the gap.
    mov ax, [bird_y]
    cmp ax, [pipe_gap_top]
    jl .dead
    add ax, 14
    mov bx, [pipe_gap_top]
    add bx, GAP_H
    cmp ax, bx
    jg .dead
.done:
    ret
.dead:
    mov byte [game_over], 1
    call stop_speaker
    ret

; ------------------------------------------------------------
; Pseudo-random gap top, constrained to 35..105
; ------------------------------------------------------------
seed_random:
    mov ah, 00h
    int 1Ah
    xor dx, [random_state]
    or dx, 1
    mov [random_state], dx
    ret

choose_gap:
    ; 16-bit LFSR-like update.
    mov ax, [random_state]
    shl ax, 1
    jnc .no_xor
    xor ax, 002Dh
.no_xor:
    or ax, 1
    mov [random_state], ax
    and ax, 003Fh
    cmp ax, 70
    jbe .range_ok
    sub ax, 35
.range_ok:
    add ax, 35
    mov [pipe_gap_top], ax
    ret

; ------------------------------------------------------------
; Render complete frame into off-screen buffer, then copy it.
; ------------------------------------------------------------
render_frame:
    mov ax, [back_segment]
    mov es, ax

    ; Sky background.
    mov bx, 0
    mov dx, 0
    mov cx, 320
    mov si, 200
    mov al, 9                       ; light sky blue
    call fill_rect

    ; Repeating soft white clouds.
    mov bx, 22
    mov dx, 27
    mov cx, 25
    mov si, 8
    mov al, 15
    call fill_rect
    mov bx, 30
    mov dx, 21
    mov cx, 17
    mov si, 14
    mov al, 15
    call fill_rect
    mov bx, 42
    mov dx, 27
    mov cx, 21
    mov si, 8
    mov al, 15
    call fill_rect

    mov bx, 145
    mov dx, 48
    mov cx, 28
    mov si, 8
    mov al, 15
    call fill_rect
    mov bx, 155
    mov dx, 41
    mov cx, 18
    mov si, 15
    mov al, 15
    call fill_rect
    mov bx, 168
    mov dx, 48
    mov cx, 20
    mov si, 8
    mov al, 15
    call fill_rect

    mov bx, 250
    mov dx, 24
    mov cx, 25
    mov si, 8
    mov al, 15
    call fill_rect
    mov bx, 259
    mov dx, 18
    mov cx, 17
    mov si, 14
    mov al, 15
    call fill_rect
    mov bx, 271
    mov dx, 24
    mov cx, 20
    mov si, 8
    mov al, 15
    call fill_rect

    ; Distant ground strip.
    mov bx, 0
    mov dx, 194
    mov cx, 320
    mov si, 6
    mov al, 10
    call fill_rect

    call draw_pipes
    call draw_bird
    call draw_score_text

    ; Wait for vertical retrace immediately before presenting the frame.
    call wait_frame

    ; Copy 64,000 bytes from backbuffer to VGA memory.
    cld
    push ds
    push es
    mov ax, [back_segment]
    mov ds, ax
    mov ax, 0A000h
    mov es, ax
    xor si, si
    xor di, di
    mov cx, 32000
    rep movsw
    pop es
    pop ds
    ret

; Present the already-rendered backbuffer (used after drawing game-over text).
present_buffer:
    cld
    push ds
    push es
    mov ax, [back_segment]
    mov ds, ax
    mov ax, 0A000h
    mov es, ax
    xor si, si
    xor di, di
    mov cx, 32000
    rep movsw
    pop es
    pop ds
    ret

; ------------------------------------------------------------
; Filled rectangle
; Input: BX=x, DX=y, CX=width, SI=height, AL=colour
; Uses ES as framebuffer segment. Coordinates must be on-screen.
; ------------------------------------------------------------
fill_rect:
    cld
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push bp

    mov [draw_color], al
    mov bp, cx
.row:
    ; DI = y*320 + x = y*256 + y*64 + x
    mov ax, dx
    mov di, ax
    shl di, 6
    shl ax, 8
    add di, ax
    add di, bx

    mov cx, bp
    mov al, [draw_color]
    rep stosb

    inc dx
    dec si
    jnz .row

    pop bp
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; ------------------------------------------------------------
; Pipes: dark outline, green body, bright highlight and caps.
; ------------------------------------------------------------
draw_pipes:
    ; Upper pipe outer border.
    mov bx, [pipe_x]
    mov dx, 0
    mov cx, PIPE_W
    mov si, [pipe_gap_top]
    mov al, 1
    call fill_rect

    ; Upper pipe green interior.
    mov bx, [pipe_x]
    add bx, 2
    mov dx, 0
    mov cx, PIPE_W-4
    mov si, [pipe_gap_top]
    mov al, 2
    call fill_rect

    ; Upper highlight.
    mov bx, [pipe_x]
    add bx, 6
    mov dx, 0
    mov cx, 4
    mov si, [pipe_gap_top]
    mov al, 10
    call fill_rect

    ; Upper cap outline.
    mov bx, [pipe_x]
    sub bx, 4
    mov dx, [pipe_gap_top]
    sub dx, 9
    mov cx, PIPE_W+8
    mov si, 9
    mov al, 1
    call fill_rect

    ; Upper cap face.
    mov bx, [pipe_x]
    sub bx, 2
    mov dx, [pipe_gap_top]
    sub dx, 7
    mov cx, PIPE_W+4
    mov si, 5
    mov al, 10
    call fill_rect

    ; Calculate lower-pipe vertical geometry once for every layer.
    mov ax, [pipe_gap_top]
    add ax, GAP_H
    mov [lower_pipe_y], ax
    mov bx, 200
    sub bx, ax
    mov [lower_pipe_h], bx

    ; Lower pipe outer border.
    mov bx, [pipe_x]
    mov dx, [lower_pipe_y]
    mov cx, PIPE_W
    mov si, [lower_pipe_h]
    mov al, 1
    call fill_rect

    ; Lower pipe green interior.
    mov bx, [pipe_x]
    add bx, 2
    mov dx, [lower_pipe_y]
    mov cx, PIPE_W-4
    mov si, [lower_pipe_h]
    mov al, 2
    call fill_rect

    ; Lower highlight.
    mov bx, [pipe_x]
    add bx, 6
    mov dx, [lower_pipe_y]
    mov cx, 4
    mov si, [lower_pipe_h]
    mov al, 10
    call fill_rect

    ; Lower cap outline and face.
    mov bx, [pipe_x]
    sub bx, 4
    mov dx, [lower_pipe_y]
    mov cx, PIPE_W+8
    mov si, 9
    mov al, 1
    call fill_rect

    mov bx, [pipe_x]
    sub bx, 2
    mov dx, [lower_pipe_y]
    add dx, 2
    mov cx, PIPE_W+4
    mov si, 5
    mov al, 10
    call fill_rect
    ret

; ------------------------------------------------------------
; Bird sprite: shaped yellow body, orange wing/beak, eye.
; ------------------------------------------------------------
draw_bird:
    ; Tail feathers.
    mov bx, BIRD_X-5
    mov dx, [bird_y]
    add dx, 6
    mov cx, 6
    mov si, 3
    mov al, 12
    call fill_rect

    ; Body outline (dark edge).
    mov bx, BIRD_X
    mov dx, [bird_y]
    mov cx, 19
    mov si, 15
    mov al, 6
    call fill_rect

    ; Body rows create a rounded silhouette.
    mov bx, BIRD_X+2
    mov dx, [bird_y]
    inc dx
    mov cx, 14
    mov si, 12
    mov al, 14
    call fill_rect
    mov bx, BIRD_X+1
    mov dx, [bird_y]
    add dx, 3
    mov cx, 17
    mov si, 8
    mov al, 14
    call fill_rect

    ; Wing.
    mov bx, BIRD_X+3
    mov dx, [bird_y]
    add dx, 7
    mov cx, 9
    mov si, 5
    mov al, 12
    call fill_rect
    mov bx, BIRD_X+5
    mov dx, [bird_y]
    add dx, 8
    mov cx, 6
    mov si, 2
    mov al, 4
    call fill_rect

    ; Eye white and pupil.
    mov bx, BIRD_X+12
    mov dx, [bird_y]
    add dx, 3
    mov cx, 4
    mov si, 4
    mov al, 15
    call fill_rect
    mov bx, BIRD_X+14
    mov dx, [bird_y]
    add dx, 4
    mov cx, 2
    mov si, 2
    mov al, 0
    call fill_rect

    ; Beak.
    mov bx, BIRD_X+18
    mov dx, [bird_y]
    add dx, 7
    mov cx, 6
    mov si, 4
    mov al, 12
    call fill_rect
    mov bx, BIRD_X+19
    mov dx, [bird_y]
    add dx, 8
    mov cx, 5
    mov si, 2
    mov al, 14
    call fill_rect
    ret

; ------------------------------------------------------------
; Text overlays using BIOS teletype in Mode 13h.
; ------------------------------------------------------------
draw_score_text:
    mov si, score_text
    mov bx, 8
    mov dx, 8
    mov byte [draw_color], 15
    call draw_text_buffer

    ; Convert score to five decimal digits.
    mov ax, [score]
    mov bx, 10
    mov cx, 5
    mov di, score_digits+4
.convert_score:
    xor dx, dx
    div bx
    add dl, '0'
    mov [di], dl
    dec di
    loop .convert_score

    mov si, score_digits
    mov bx, 64
    mov dx, 8
    mov byte [draw_color], 15
    call draw_text_buffer
    ret

draw_game_over_text:
    mov si, gameover_text
    mov bx, 120
    mov dx, 96
    mov byte [draw_color], 15
    call draw_text_buffer

    mov si, exit_text
    mov bx, 104
    mov dx, 112
    mov byte [draw_color], 15
    call draw_text_buffer
    ret

; Draw a zero-terminated string using the built-in 8x8 font below.
; Input: DS:SI = string, BX = x, DX = y, ES = backbuffer segment.
draw_text_buffer:
    mov [text_x], bx
    mov [text_y], dx
.next_char:
    lodsb
    test al, al
    jz .finished

    ; Font table covers ASCII 32 through 90. Unsupported chars are blank.
    cmp al, 32
    jb .blank_char
    cmp al, 90
    ja .blank_char
    sub al, 32
    xor ah, ah
    mov bp, ax
    shl bp, 3
    mov [font_index], bp
    jmp .draw_glyph
.blank_char:
    mov word [font_index], (90-32+1)*8
.draw_glyph:
    ; Destination offset = y*320 + x.
    mov ax, [text_y]
    mov bp, ax
    shl ax, 6
    shl bp, 8
    add ax, bp
    add ax, [text_x]
    mov [text_offset], ax

    mov cx, 8
.row:
    mov bp, [font_index]
    mov al, [cs:font8x8+bp]
    mov [text_bits], al
    mov di, [text_offset]
    mov dl, 8
.bit:
    test byte [text_bits], 80h
    jz .skip_pixel
    mov al, [draw_color]
    mov [es:di], al
.skip_pixel:
    shl byte [text_bits], 1
    inc di
    dec dl
    jnz .bit

    inc word [font_index]
    add word [text_offset], 320
    loop .row

    add word [text_x], 8
    jmp .next_char
.finished:
    ret

; ------------------------------------------------------------
; PC speaker short score beep. Always silenced on death/exit.
; ------------------------------------------------------------
beep:
    mov al, 0B6h
    out 43h, al
    mov ax, 1193
    out 42h, al
    mov al, ah
    out 42h, al
    in al, 61h
    or al, 3
    out 61h, al
    ; Keep the tone on for about 70 ms (BIOS wait uses microseconds).
    mov ah, 86h
    mov cx, 0001h
    mov dx, 4464
    int 15h
    call stop_speaker
    ret

stop_speaker:
    in al, 61h
    and al, 0FCh
    out 61h, al
    ret

; ------------------------------------------------------------
; Wait for vertical retrace to reduce tearing.
; ------------------------------------------------------------
wait_frame:
    mov dx, 03DAh
.wait_end:
    in al, dx
    test al, 8
    jnz .wait_end
.wait_start:
    in al, dx
    test al, 8
    jz .wait_start
    ret

; ------------------------------------------------------------
; Exit cleanly to DOS.
; ------------------------------------------------------------
exit_game:
    call stop_speaker
    mov ax, 0003h
    int 10h
    mov ax, 4C00h
    int 21h


; Built-in 8x8 bitmap font: ASCII 32..90, one byte per row.
font8x8:
    db 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h
    db 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h
    db 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h
    db 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h
    db 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h
    db 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h
    db 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h
    db 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h
    db 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h
    db 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h
    db 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h
    db 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h
    db 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h
    db 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h
    db 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h
    db 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h
    db 00h, 38h, 44h, 4Ch, 54h, 64h, 44h, 38h
    db 00h, 10h, 30h, 10h, 10h, 10h, 10h, 38h
    db 00h, 38h, 44h, 04h, 08h, 10h, 20h, 7Ch
    db 00h, 78h, 04h, 04h, 38h, 04h, 04h, 78h
    db 00h, 08h, 18h, 28h, 48h, 7Ch, 08h, 08h
    db 00h, 7Ch, 40h, 40h, 78h, 04h, 04h, 78h
    db 00h, 38h, 40h, 40h, 78h, 44h, 44h, 38h
    db 00h, 7Ch, 04h, 08h, 10h, 20h, 20h, 20h
    db 00h, 38h, 44h, 44h, 38h, 44h, 44h, 38h
    db 00h, 38h, 44h, 44h, 3Ch, 04h, 04h, 38h
    db 00h, 00h, 10h, 10h, 00h, 10h, 10h, 00h
    db 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h
    db 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h
    db 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h
    db 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h
    db 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h
    db 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h
    db 00h, 38h, 44h, 44h, 7Ch, 44h, 44h, 44h
    db 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h
    db 00h, 3Ch, 40h, 40h, 40h, 40h, 40h, 3Ch
    db 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h
    db 00h, 7Ch, 40h, 40h, 78h, 40h, 40h, 7Ch
    db 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h
    db 00h, 3Ch, 40h, 40h, 5Ch, 44h, 44h, 3Ch
    db 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h
    db 00h, 38h, 10h, 10h, 10h, 10h, 10h, 38h
    db 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h
    db 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h
    db 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h
    db 00h, 44h, 6Ch, 54h, 54h, 44h, 44h, 44h
    db 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h
    db 00h, 38h, 44h, 44h, 44h, 44h, 44h, 38h
    db 00h, 78h, 44h, 44h, 78h, 40h, 40h, 40h
    db 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h
    db 00h, 78h, 44h, 44h, 78h, 50h, 48h, 44h
    db 00h, 3Ch, 40h, 40h, 38h, 04h, 04h, 78h
    db 00h, 7Ch, 10h, 10h, 10h, 10h, 10h, 10h
    db 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h
    db 00h, 44h, 44h, 44h, 44h, 44h, 28h, 10h
    db 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h
    db 00h, 44h, 44h, 28h, 10h, 28h, 44h, 44h
    db 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h
    db 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h
font8x8_end:
; Reserve a private stack before releasing the unused DOS memory.
; resident_end is also used to calculate the minimum COM block size.
stack_space times 1024 db 0
stack_top:
resident_end:
