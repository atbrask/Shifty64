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
KEY_QUIT_TO_TITLE = $51 ; Q
KEY_RESTART_LEVEL = $52 ; R
KEY_UNDO          = $5a ; Z
KEY_UP            = $57 ; W
KEY_LEFT          = $41 ; A
KEY_DOWN          = $53 ; S
KEY_RIGHT         = $44 ; D

;
; How tiles are stored in the loaded level:
;
PushableMask      = 0b10000000 ; bit 7 of tile
NeedsRedrawMask   = 0b01000000 ; bit 6 of tile
ActiveTileMask    = 0b00100000 ; bit 5 of tile
TileIndexMask     = 0b00011111 ; bits 0-4 of tile (This port assumes a max of 16 tile types due to memory layout)

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

; BASIC stub to start the game
!byte $0C,$08,$40,$00,$9E,$20,$32,$30,$36,$32,$00,$00,$00 ; BASIC CODE: 1024 SYS 2062	

;--------------------------------------------------------------------------------
; Main program loop
;--------------------------------------------------------------------------------
        cld
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

        cpy #KEY_QUIT_TO_TITLE
        beq gameTitle

        jsr playerMove
        bcs gameLoop

        jsr draw
        jmp gameLoop

;------------------------------------------------------------------------------
; tryGetNeighborAddress: Expects a tile offset in A and a direction in X.
; Returns the offset of the neighboring tile in A.
; Sets carry if the neighbor is out of bounds.
;------------------------------------------------------------------------------
tryGetNeighborAddress:
        pha
        txa
        ror
        bcs verticalNeighbor

horizontalNeighbor:
        ror
        bcs leftNeighbor

rightNeighbor:
        pla
        clc
        adc #$08
        cmp #$c0
        rts

leftNeighbor:
        pla
        sec
        sbc #$08
        bcc +
        clc
        rts
+       sec
        rts

verticalNeighbor:
        ror
        bcs downNeighbor

upNeighbor:
        pla
        sec
        sbc #$01
        pha
        and #$07
        cmp #$07
        beq +
        pla
        clc
        rts
+       pla
        sec
        rts

downNeighbor:
        pla
        clc
        adc #01
        pha
        and #$07
        beq +
        pla
        clc
        rts
+       pla
        sec
        rts

;------------------------------------------------------------------------------
; playerMove: Moves the player in the direction specified in X.
; PlayerMoveDir = Direction (0 -> right, 1 -> up, 2 -> right, 3 -> down)
; This procedure pushes the pushable positions to the stack
; -> [A] = the number of positions pushed to the stack
;------------------------------------------------------------------------------
playerMove:
        ; Push the player position onto the stack
        lda PlayerPos
        pha

        ; Initial position count
        lda #$01
        sta $02

moveSearchLoop:
        lda PlayerPos
        ldx PlayerMoveDir
        jsr tryGetNeighborAddress
        bcs moveFoundSolid ; handle out of bounds as solid

        ldy PlayerPos
        lda Level, y

        cmp #PushableMask
        bcs moveFoundPushable

        and #TileIndexMask

        ; Check for solid tiles
        cmp #TileWallBrick_Index
        beq moveFoundSolid

        cmp #TileDoorClosed_Index
        beq moveFoundSolid

        cmp #TileDoorOpen_Index
        beq moveFoundOpenDoor

        ; Check for hole
        cmp #TileHole_Index
        beq moveFoundHole

        ; Block the move if search has looped around and is trying to push into current player position
        eor #TileBoxKidRight_Index
        cmp #$04
        bcc moveFoundSolid

        ; Assume we found empty
        jmp movePerform

moveFoundOpenDoor:
        lda $02 ; Read the number of positions pushed to the stack
        cmp #$01
        bne moveFoundSolid ; If we have more than one position, treat as solid

        ; TODO(jkk): What if we have the following?
	; ..###    ..###
	; .@>D# or ..#D#
	; ..###    ..@^#

        ; Go through the open door
        pla
        inc CurrentLevelIndex
        lda CurrentLevelIndex
        jsr gotoLevel
        clc
        rts

moveFoundHole:
	; First we must find the head pushable tile.
	; Because the train of pushables could have turns signified by 0xFF sentinels,
	; we need to keep popping the stack as long as the top is a 0xFF turn sentinel.

skipDirectionChangeSentinelsLoop:
        ; We need to follow the arrows
        pla
        dec $02
        beq setCarryAndReturn
        cmp #$ff
        beq skipDirectionChangeSentinelsLoop
        
        ; Now we are on the first non-direction change tile
	; If it is pushable, it should go in the hole

        tay
        lda Level, y
        cmp #PushableMask
        bcc moveCancel; If it is not pushable, we cannot move into the hole

        ; Head was a pushable, so it should go in the hole (remove both)

	; Test if head was a goal
        and #TileIndexMask
        cmp #TileGoal_Index
        beq removeGoal

        ; TODO
        jsr undoSaveTile
        ;TODO xchg
        jsr undoSaveTile
        lda #(TileEmpty_Index | NeedsRedrawMask)
        sta Level, y
        jmp movePerform

moveFoundPushable:
        ; it's a pushable, so push it (^;
	pha
	inc $02 ; increment position count
	jmp moveSearchLoop

moveFoundSolid:
        ; Go backwards through the stack and find the first arrow pointing
	; at a right angle to the current direction of movement.
	; If such a perpendicular arrow is found:
	; return from here and continue searching for solids from that arrow in the direction dictated by that arrow.
	;
	; i.e. the arrow changes the direction of search
	;
	; If during this search we get all the way back to the player, the move can't be performed.
	;
perpArrowSearchLoop:
        pla
        dec $02
        beq setCarryAndReturn

        ; We must check if this is a real position or a search direction change
        cmp #$ff
        bne notDirectionChangeSentinel


notDirectionChangeSentinel:
notGoal:
        ; TODO
        rts

moveCancel:
        ; TODO
        rts

setCarryAndReturn:
        sec
        rts

movePerform:
skipPlayerPosUpdate:
tileDidntChange:
decrementAndLoop:
        ; TODO
        rts

undoEndMoveRecord:
searchSentinel:
foundSentinel:
oldestRecordNotTruncated:
        ; TODO
        rts

; A = tile offset
; Clobbers y
undoSaveTile:
        ; preserve A
        pha
    
        ; save tile offset
        ldy UndoBufferAt
        sta UndoBuffer, y
        iny
        sty UndoBufferAt

        ; save tile value
        tay
        lda Level, y
        ldy UndoBufferAt
        sta UndoBuffer, y
        iny
        sty UndoBufferAt

        ; Update the count of entries in the undo buffer
        inc UndoEntryCount

        ; restore A and return
        pla
        rts

removeGoal:
openDoorsLoop:
notClosedDoor:
end:
        ; TODO
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

undoClear:
loopUndoCLear:
        ; TODO
        rts

initLeveLVariables:
loopLevelVariables:
notTarget:
notThePlayer:
endLevelVariables:
        ; TODO
        rts

undo:
undoLoop:
undoEnd:
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

gameInit:
        lda #$00
        sta CurrentLevelIndex
        jsr gotoLevel
        jsr draw
        rts

;------------------------------------------------------------------------------
; draw: Draws the current level to the screen buffer
; Uses zp $02..$05
;------------------------------------------------------------------------------
draw:
        ; level offset
        ldy #00
        sty $03
        sty $04
nextRow:
        ; offset in row
        ldx #00
nextTile:
        ; Check dirty flag
        lda Level,y
        and #NeedsRedrawMask
        beq drawContinue

        ; Draw tile
        lda Level,y
        sta $02
        stx $04
        sty $05
        jsr drawTile
        ldx $04
        ldy $05
        ; Clear redraw flag
        lda Level,y
        eor #NeedsRedrawMask
        sta Level,y

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
;------------------------------------------------------------------------------
drawTile:
        ; Pick out active flag
        lda $02
        and #ActiveTileMask
        sta $fa

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
        lda maskLeft, X
        sta $f8
        lda $fa
        bne +
        lda #0
        jmp ++
+       lda activeMaskLeft, X
++      sta $f9

        ldy #$00    ; Initialize Y to 0 for the first byte of the 8x8 box
-       lda ($fd),Y ; Load byte from screen buffer
        and $f8     ; Mask out bits for first 8x8 box
        ora ($fb),Y ; Load byte from tile data and OR it in
        eor $f9     ; XOR with active mask to invert bits if active
        sta ($fd),Y ; Store byte back to screen buffer
        iny         ; Increment Y to move to next byte in the 8x8 box
        cpy #$08    ; Check if we've processed all 8 bytes of the 8x8 box
        bcc -       ; Loop back if not done

        ; Mask out second 8x8 box and draw partial tile
        lda maskRight, X
        sta $f8
        lda $fa
        bne +
        lda #0
        jmp ++
+       lda activeMaskRight, X
++      sta $f9

        ldy #$08    ; Initialize Y to 8 for the first byte of the second 8x8 box
-       lda ($fd),y ; Load byte from screen buffer
        and $f8     ; Mask out bits for second 8x8 box
        ora ($fb),Y ; Load byte from tile data and OR it in
        eor $f9     ; XOR with active mask to invert bits if active
        sta ($fd),Y ; Store byte back to screen buffer
        iny         ; Increment Y to move to next byte in the second 8x8 box
        cpy #$10    ; Check if we've processed all 8 bytes of the second 8x8 box
        bcc -       ; Loop back if not done

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
UndoBuffer = Level + $0100
UndoBufferEnd = UndoBuffer + $0100

; Assert that the buffer fits before the VIC-II screen area
!if UndoBufferEnd > $A000 {
    !error "Out of memory"
}