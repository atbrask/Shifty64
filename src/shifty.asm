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
PushableMask      = %10000000 ; bit 7 of tile
NeedsRedrawMask   = %01000000 ; bit 6 of tile
ActiveTileMask    = %00100000 ; bit 5 of tile
InactiveTileMask  = %11011111 ; everything except bit 5 of tile
TileIndexMask     = %00011111 ; bits 0-4 of tile (This port assumes a max of 16 tile types due to memory layout)

; Direction encoding:
; bit 0: Axis (0: X, 1: Y)
; bit 1: Sign of direction along axis (0: positive, 1: negative)
DirectionSignBit  = %00000010
DirectionAxisBit  = %00000001
DirectionRight    = %00000000
DirectionUp       = %00000001
DirectionLeft     = %00000010
DirectionDown     = %00000011

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
        ; Push the player's initial position onto the stack
        lda PlayerPos
        sta CurrentTile
        pha
        lda #$01
        sta StackDepth

moveSearchLoop:
        lda CurrentTile
        ldx PlayerMoveDir
        jsr tryGetNeighborAddress
        sta CurrentTile
        bcc +
        jmp moveFoundSolid ; handle out of bounds as solid

+       tay
        lda Level, y

        ; Check if the tile is pushable
        cmp #PushableMask
        bcs moveFoundPushable

        and #TileIndexMask

        cmp #TileDoorOpen_Index
        beq moveFoundOpenDoor

        ; Check for solid tiles
        cmp #TileWallBrick_Index
        beq moveFoundSolid

        cmp #TileDoorClosed_Index
        beq moveFoundSolid

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
        lda StackDepth
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
        sta HeadTile
        dec StackDepth
        bne +
        jmp setCarryAndReturn
+       cmp #$ff
        bne +
        pla ; Remember that $ff implies a second stack entry to discard
        jmp skipDirectionChangeSentinelsLoop
        
        ; Now we are on the first non-direction change tile
	; If it is pushable, it should go in the hole

+       tay
        lda Level, y
        cmp #PushableMask
        bcs +
        jmp moveCancel; If it is not pushable, we cannot move into the hole

        ; Head was a pushable, so it should go in the hole (remove both)

	; Test if head was a goal
+       and #TileIndexMask
        cmp #TileGoal_Index
        bne +
        jsr removeGoal
+       ldy CurrentTile
        jsr undoSaveTile
        ; swap CurrentTile and HeadTile
        ldy HeadTile
        lda CurrentTile
        sta HeadTile
        sty CurrentTile
        jsr undoSaveTile
        lda #(TileEmpty_Index | NeedsRedrawMask)
        ldy HeadTile
        sta Level, y
        ldy CurrentTile
        sta Level, y
        jmp movePerform

moveFoundPushable:
        ; it's a pushable, so push it (^;
        lda CurrentTile
	pha
	inc StackDepth
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
        sta CurrentTile ; update current tile to the popped value
        dec StackDepth
        beq setCarryAndReturn

        ; We must check if this is a real position or a search direction change
        cmp #$ff
        bne notDirectionChangeSentinel
        pla
        sta PlayerMoveDir ; update the direction of movement to the popped value
        jmp perpArrowSearchLoop

notDirectionChangeSentinel:
        tay
        lda Level, y
        and #TileIndexMask

        ; Test for goal
        cmp #TileGoal_Index
        bne notGoal
        jsr removeGoal
        jmp movePerform

notGoal:
        eor #TileRightArrow_Index
        cmp #$04
        bcs perpArrowSearchLoop

        ; At this point, it is an arrow
        sta ArrowDirection

        ; If along the same movement axis, keep looping
        eor PlayerMoveDir
        clc
        ror
        bcc perpArrowSearchLoop ; If the arrow is not perpendicular, continue searching

        ; The found arrow is perpendicular
        ldy CurrentTile
        lda Level, y
        ora #(ActiveTileMask | NeedsRedrawMask)
        sta Level, y

        ; Push search direction and sentinel onto the stack
        lda PlayerMoveDir
        pha
        lda #$ff
        pha
        inc StackDepth

        lda ArrowDirection
        sta PlayerMoveDir ; update the direction of movement to the found arrow's direction

        jmp moveSearchLoop

moveCancel:
      	; Cancel the move, since we found a solid
        ; Unwind the stack
        ldy CurrentTile
        lda Level, y
        and InactiveTileMask
        ora NeedsRedrawMask
        sta Level, y

        pla
        sta CurrentTile
        dec StackDepth
        bne moveCancel

setCarryAndReturn:
        sec
        rts

movePerform:
        pla
        sta HeadTile
        cmp #$ff ; Detect search direction sentinel
        bne +
        pla
        jmp decrementAndLoop

        ; HeadTile = closest tile from player (from the stack)
        ; CurrentTile = furthest tile from player

        ; Write from closest pos (HeadTile) to furthest pos (CurrentTile)
+       tay
        lda Level, y
        ldy CurrentTile
        cmp Level, y
        beq tileDidntChange
        jsr undoSaveTile
        ora #NeedsRedrawMask
        and #InactiveTileMask
        ldy CurrentTile
        sta Level, y

tileDidntChange:
        lda CurrentTile
        ldx HeadTile
        sta HeadTile
        stx CurrentTile

decrementAndLoop:
        ; Decrement and loop until B hits 0
        dec StackDepth
        bne movePerform
        
       	; [HL] = original player position before the move
	; Clear foreground tile on the starting position, the player just moved away from this tile.
        ldy CurrentTile
        jsr undoSaveTile
        lda #(TileEmpty_Index | NeedsRedrawMask)
        sta Level, y

        ; Update player facing direction
        ldy HeadTile
        lda Level, y
        and #%11111100
        ora PlayerMoveDir
        sta Level, y

        jsr undoEndMoveRecord
        clc ; clear carry bit to indicate that the move was performed successfully
        rts

undoEndMoveRecord:
        ldy UndoBufferAt
        lda UndoEntryCount
        sta UndoBuffer, y
        iny
        lda #$ff
        sta UndoBuffer, y
        iny
        sty UndoBufferAt

        ; Search ahead to see if we truncated the oldest move record,
	; and if we did, disable that move record by clearing the FF sentinel
        lda #$00
        sta SearchDistance
        lda UndoBuffer, y
searchSentinel:
        cmp #$ff
        beq foundSentinel
        inc SearchDistance
        beq oldestRecordNotTruncated
        iny
        lda UndoBuffer, y
        jmp searchSentinel

foundSentinel:
        ; points at oldest move record sentinel
	dey
	; points at oldest move record entry count

        ; If oldest move record entry count exceeds the search distance
        lda UndoBuffer, y
        clc
        adc UndoBuffer, y
        cmp SearchDistance
        bcc oldestRecordNotTruncated

        ; The oldest record has been truncated, so we must clear its
	; sentinel to 0 to disable it.
        iny
        lda #$00
        sta UndoBuffer, y

oldestRecordNotTruncated:
        lda #$00
        sta UndoEntryCount
        rts

; Y = tile offset
undoSaveTile:
        ; preserve A
        sta $ff
        ; preserve Y
        sty $fe
        tya
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

        ; restore Y, A, and return
        lda $ff
        ldy $fe
        rts

removeGoal:
        ldy CurrentTile
        jsr undoSaveTile
        lda #TileEmpty_Index
        sta Level, y

        ; Decrease number of targets and check if it was the last one
        dec MissingTargets
        bne end

        ; If it was the last target, open all doors
        ldy #$c0
openDoorsLoop:
        dey
        lda Level, y
        and #TileIndexMask
        cmp #TileDoorClosed_Index
        bne notClosedDoor
        ; Open the closed door
        jsr undoSaveTile
        lda #(TileDoorOpen_Index | NeedsRedrawMask)
        sta Level, y
notClosedDoor:
        cpy #$00
        bne openDoorsLoop
end:
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

        ; Read tile type
        lda ($fb),Y
        and #%00011111

        ; Compressed data offset += 1
        iny
        sty $fd

        ; Apply tile properties
        tay
        lda TileInfoFromTileIndexMap, y

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

undoClear:
        lda #$00
        sta UndoEntryCount
        sta UndoBufferAt
        ldy #$00
loopUndoClear:
        sta UndoBuffer, y
        dey
        bne loopUndoClear
        rts

undo:
        ldy UndoBufferAt
        dey
        lda UndoBuffer, y
        cmp #$ff
        bne undoEnd ; Undo buffer empty

        lda #$00
        sta UndoBuffer, y ; Clear move record being un-done

        dey
        lda UndoBuffer, y ; entry count
        sta $fe
undoLoop:
        dey
        lda UndoBuffer, y ; tile info
        ora #NeedsRedrawMask
        tax
        dey
        sty $ff
        lda UndoBuffer, y ; tile pos
        tay
        txa
        sta Level, y
        ldy $ff

        dec $fe
        bne undoLoop

        sty UndoBufferAt
undoEnd:
        rts


readInput:
        jsr KERNAL_READ_KEY

        ; No input, return with carry set
        beq noInput

        cmp #KEY_RESTART_LEVEL
        bne notRestart
        lda CurrentLevelIndex ; TODO This is undefined before starting the game, so we need to handle that case
        jsr gotoLevel
        jsr draw
        sec
        rts
notRestart:
        cmp #KEY_QUIT_TO_TITLE
        bne notQuit
        jmp gameTitle
notQuit:
        cmp #KEY_UNDO
        bne notUndo
        jsr undo
        jsr draw
        sec
        rts
notUndo:
        cmp #KEY_UP
        bne notUp
        lda #DirectionUp
        sta PlayerMoveDir
        clc
        rts
notUp:
        cmp #KEY_DOWN
        bne notDown
        lda #DirectionDown
        sta PlayerMoveDir
        clc
        rts
notDown:
        cmp #KEY_LEFT
        bne notLeft
        lda #DirectionLeft
        sta PlayerMoveDir
        clc
        rts
notLeft:
        cmp #KEY_RIGHT
        bne noInput
        lda #DirectionRight
        sta PlayerMoveDir
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

        ; reset level variables
        sty MissingTargets
        sty PlayerPos
nextRow:
        ; offset in row
        ldx #00
nextTile:
	; While we are looping over every tile in the level, keep track of
	; - PlayerPosition
	; - Missing shooting targets
        lda Level,y
        and #TileIndexMask
        cmp #TileGoal_Index
        bne notTarget
        inc MissingTargets
notTarget:
        eor #TileBoxKidRight_Index
        cmp #$04
        bcs notThePlayer
        sty PlayerPos
notThePlayer:
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
        lda #$00
        sta VIC_BORDER_COLOR
        lda #$00
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
        lda #$00 ; Screen colors: 4b foreground + 4b background
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

SearchDistance: !byte 0
ArrowDirection: !byte 0
StackDepth: !byte 0
CurrentTile: !byte 0
HeadTile: !byte 0

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