; C64 port of the NEC PC-8201A game Shifty

; VIC-II registers
VIC_CONTROL_REG1  = $d011
VIC_SPRITE_ENABLE = $d015
VIC_MEM_OFFSET    = $d018
VIC_BORDER_COLOR  = $d020
VIC_BACK1_COLOR   = $d021

; VIC-II flags
VIC_CR1_BMM       = %00100000

; Buffers
SCREEN_BUFFER     = $2000
SCREEN_OFFSET     = $0668 ; offset within the screen for the game display
COLOR_BUFFER      = $0400

; Kernal routines
KERNAL_READ_KEY   = $ffe4

; Key codes
KEY_QUIT_TO_TITLE = $D1 ; Q
KEY_RESTART_LEVEL = $0D ; Return
KEY_UP            = $D7 ; W
KEY_LEFT          = $C1 ; A
KEY_DOWN          = $D3 ; S
KEY_RIGHT         = $C4 ; D

;
; How tiles are stored in the loaded level:
;
PushableMask      = 0b10000000 ; bit 7 of tile
NeedsRedrawMask   = 0b01000000 ; bit 6 of tile
ActiveTileMask    = 0b00100000 ; bit 5 of tile
TileIndexMask     = 0b00011111 ; bits 0-4 of tile

; Direction encoding:
; bit 0: Axis (0: X, 1: Y)
; bit 1: Sign of direction along axis (0: positive, 1: negative)
DirectionSignBit  = 0b00000010
DirectionAxisBit  = 0b00000001
DirectionRight    = 0b00000000
DirectionUp       = 0b00000001
DirectionLeft     = 0b00000010
DirectionDown     = 0b00000011

!cpu 6502
*=$0801   ; Starting Address

!byte $0C,$08,$40,$00,$9E,$20,$32,$30,$36,$32,$00,$00,$00 ; BASIC CODE: 1024 SYS 2062	

        jsr prepareScreen
gameTitle:
        jsr showTitle

gameStart:
        jsr readInput
        bcs gameStart

        jsr gameInit

gameLoop:
        jsr readInput
        bcs gameLoop

        ; TODO Handle exit to title

        jsr playerMove
        bcs gameLoop

        jsr draw
        jmp gameLoop

;------------------------------------------------------------------------------
; tryGetNeighborAddress: Given a tile address in A and a direction in X, returns the address of the neighboring tile in A. Returns with carry set if the neighbor is vertical (up or down), clear if horizontal (left or right). Returns with carry clear if the neighbor is out of bounds.
;------------------------------------------------------------------------------
tryGetNeighborAddress:
        ror
        bcs verticalNeighbor

horizontalNeighbor:
        ror
        bcs leftNeighbor

rightNeighbor:
        rts

leftNeighbor:
        rts

verticalNeighbor:

upNeighbor:

        rts

downNeighbor:

        rts

playerMove:
        ; TODO
        rts

moveSearchLoop:
        ; TODO
        rts

moveFoundOpenDoor:
        ; TODO
        rts

moveFoundHole:
        ; TODO
        rts

moveFoundPushable:
        ; TODO
        rts

moveFoundSolid:
        ; TODO
        rts

moveCancel:
        ; TODO
        rts

movePerform:
        ; TODO
        rts

removeGoal:
        ; TODO
        rts

readInput:
        ; TODO filter input before returning
        jsr KERNAL_READ_KEY
        beq noInput
        clc
        rts
noInput:
        lda #00
        sec
        rts


        ;Level index in A
gotoLevel:
        ; Look up pointer to compressed level data
        asl
        tax
        lda LevelLookupTable, x
        sta $fb
        lda LevelLookupTable + 1, X
        sta $fc

        ; Level pointer
        lda #<Level
        sta $f9
        lda #>Level
        sta $fa

        ; Input and output offsets
        lda #00
        sta $fd
        sta $fe

readCompressed:
        ; Load compressed data offset
        ldy $fd
        
        ; Read run length and add 1
        lda ($fb),Y
        lsr
        lsr
        lsr
        lsr
        lsr
        tax
        inx
        stx $ff

        ; Read tile type and set redraw flag
        lda ($fb),Y
        and #%00011111
        ora #NeedsRedrawMask

        ; Compressed data offset += 1
        iny
        sty $fd

        ; Load decompressed data offset and write to screen buffer
        ; X is already the number of bytes to write        
        ldy $fe
writeRun:
        sta ($f9),Y
        iny
        dex
        bne writeRun

        ; update output pointer offset
        clc
        lda $fe
        adc $ff
        sta $fe

        ; Check if done
        cmp #$c0
        bcc readCompressed
        ; TODO Call InitLevelVariables and undo init
        rts

gameInit:
        lda #$00
        sta CurrentLevelIndex
        jsr gotoLevel
        jsr draw
        rts

;------------------------------------------------------------------------------
; draw: Draws the current level to the screen buffer
; Uses zp $02..$04, $f6..$f7
; Clobbers A, X, Y
;------------------------------------------------------------------------------
draw:
        ; Level pointer
        lda #<Level
        sta $a6
        lda #>Level
        sta $a7

        ; level offset
        ldy #00
        sty $03
        sty $04
nextRow:
        ; offset in row
        ldx #00
nextTile:
        ; Check dirty flag
        lda ($a6),y
        and #NeedsRedrawMask
        beq drawContinue

        ; Check active flag
        ; TODO

        ; Draw tile
        lda ($a6), y
        sta $02
        stx $04
        jsr drawTile

        ; Clear redraw flag
        lda ($a6),y
        eor #NeedsRedrawMask
        sta ($a6),y

drawContinue:
        inx
        iny

        cpx #08
        bne nextTile
        inc $03
        cpy #$c0
        bne nextRow
done:
        rts

;------------------------------------------------------------------------------
; prepareScreen: Sets up the VIC-II for bitmap mode, clears the screen and 
; color RAM, and sets the background colors.
;------------------------------------------------------------------------------
prepareScreen:
        ; Set border and background
        lda #$0e
        sta VIC_BORDER_COLOR
        lda #$06
        sta VIC_BACK1_COLOR

        ;no visible sprites
        lda #$00
        sta VIC_SPRITE_ENABLE

        ; Clear hi-res screen RAM
        lda #<SCREEN_BUFFER
        sta $fd
        lda #>SCREEN_BUFFER
        sta $fe
        lda #$00 ; zero value
        ldy #$00 ; byte counter within page
        ldx #$20 ; 32 pages x 256 bytes = 8 KB
clearBitmap:
        sta ($fd),y
        iny
        bne clearBitmap
        inc $fe
        dex
        bne clearBitmap

        ; Clear color RAM
        lda #<COLOR_BUFFER
        sta $fd
        lda #>COLOR_BUFFER
        sta $fe
        lda #$e6 ; Screen colors, e = light blue, 6 = dark blue
        ldy #$00 ; byte counter
        ldx #$04 ; 4 pages x 256 bytes = 1 KB
clearColors:
        sta ($fd), y
        iny
        bne clearColors
        inc $fe
        dex
        bne clearColors

        ; Set light gray background and dark gray foreground on display area
        ; b = dark gray, f = light gray
        lda #$bf
        ldx #$00
setDisplayBackground:
        sta $04cd,x
        sta $04f5,x
        sta $051d,x
        sta $0545,x
        sta $056d,x
        sta $0595,x
        sta $05bd,x
        sta $05e5,x
        inx
        cpx #$1e
        bne setDisplayBackground

        ; Enable hi-res bitmap mode
        lda VIC_CONTROL_REG1
        ora #VIC_CR1_BMM
        sta VIC_CONTROL_REG1

        ; Select bitmap at $2000 and colors as $0400
        lda #%00011000
        sta VIC_MEM_OFFSET

        rts ; return prepareScreen

;------------------------------------------------------------------------------
; showTitle: Copies the splash screen to the bitmap display area
; Uses zp $fb..fe
; Clobbers A, X, Y
;------------------------------------------------------------------------------
showTitle:
        ; Set source pointer
        lda #<splash
        sta $fb
        lda #>splash
        sta $fc

        ; Set target pointer
        lda #<SCREEN_BUFFER + SCREEN_OFFSET
        sta $fd
        lda #>SCREEN_BUFFER + SCREEN_OFFSET
        sta $fe

        ; Copy 8 char rows = 64 pixels
        ldx #$08

copyLine:
        ; Copy single char line ($f0 (240) bytes) from source to target
        ldy #$00
copyBytes:
        lda ($fb),y
        sta ($fd),y
        iny
        cpy #$f0
        bne copyBytes

        ; Add source stride (240 pixels) to source pointer
        clc
        lda $fb
        adc #$f0
        sta $fb
        lda $fc
        adc #$00
        sta $fc

        ; Add target stride (320 pixels) to target pointer
        clc
        lda $fd
        adc #$40
        sta $fd
        lda $fe
        adc #$01
        sta $fe

        ; Check if we need to copy more lines
        dex
        bne copyLine

        rts ; return showTitle

;------------------------------------------------------------------------------
; drawTile: Draws tile with index $02 at x = $03, y = $04
; Uses zp $f8..ff
; Preserves A, X, Y
;------------------------------------------------------------------------------
drawTile:
        ; --- SAVE REGISTERS TO STACK ---
        pha         ; Save Accumulator
        txa
        pha         ; Save X register
        tya
        pha         ; Save Y register

        ;lda #0
        ;sta $f8
        ;sta $f9

        ; Pick out active flag
        ;lda $02
        ;and #ActiveTileMask
        ;sta $fa

        ; Set source pointer (tile index + bit shift)
        clc
        lda $02
        asl
        asl
        asl
        asl
        adc #<tiles
        sta $fb
        lda $03
        and #%00000011
        adc #>tiles
        sta $fc

        ; Set target pointer
        lda #<SCREEN_BUFFER + SCREEN_OFFSET
        sta $fd
        lda #>SCREEN_BUFFER + SCREEN_OFFSET
        sta $fe

        ; Add row offset
        ldy $04
        cpy #$00
        beq +
-       clc
        lda $fd
        adc #$40
        sta $fd
        lda $fe
        adc #$01
        sta $fe
        dey
+       bne -

        ; Add col offset
        ldx $03
        clc
        lda $fd
        adc tileCells, X
        sta $fd
        lda $fe
        adc #$00
        sta $fe

        ; x -> x % 4
        lda $03
        and #%00000011
        tax

        ; Mask out first 8x8 box and draw partial tile
        ;lda maskLeft, X
        ;sta $f8
        ;lda activeMaskLeft, X
        ;sta $f9

        ldy #$00
-       lda ($fd),Y
        ;and $f8
        and maskLeft, X
        ora ($fb),Y
        ;eor $f9
        sta ($fd),Y
        iny
        cpy #$08
        bcc -

        ; Mask out second 8x8 box and draw partial tile
        ;lda maskRight, X
        ;sta $f8
        ;lda activeMaskRight, X
       ; sta $f9

        ldy #$08
-       lda ($fd),y
        ;and $f8
        and maskRight, X
        ora ($fb),Y
        ;eor $f9
        sta ($fd),Y
        iny
        cpy #$10
        bcc -

        ; --- RESTORE REGISTERS FROM STACK ---
        pla
        tay         ; Restore Y register (must be pulled first)
        pla
        tax         ; Restore X register
        pla         ; Restore Accumulator

        rts

tileCells:
        !byte $00, $08, $10, $18, $28, $30, $38, $40
        !byte $50, $58, $60, $68, $78, $80, $88, $90
        !byte $a0, $a8, $b0, $b8, $c8, $d0, $d8, $e0

maskLeft:
        !byte $00, $c0, $f0, $fc

activeMaskLeft:
        !byte $ff, $3f, $0f, $03

maskRight:
        !byte $3f, $0f, $03, $00

activeMaskRight:
        !byte $c0, $f0, $fc, $ff

;=======================================
; Splash screen

splash:
!src "src/splash.asm"

;=======================================
; Tile images

tiles:
!src "src/tiles.asm"

;=======================================
; Level data

!src "src/levels.asm"

;=======================================
; Game data
PlayerPos: !byte 0

PlayerMoveDir: !byte 0

MissingTargets: !byte 0

CurrentLevelIndex: !byte 0

; buffers
Level = (CurrentLevelIndex + $ff) & $ff00
LevelEnd = Level + 8*24

UndoEntryCount = Level + $0100 - 2
UndoBufferAt = Level + $0100 - 1
Undobuffer = Level + $0100
UndoBufferEnd = Undobuffer + $0100

; Assert that the buffer fits before the VIC-II screen area
!if UndoBufferEnd > $A000 {
    !error "Out of memory"
}