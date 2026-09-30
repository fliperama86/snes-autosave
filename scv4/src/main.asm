; Super Castlevania IV (Anniversary Collection ROMs) - battery save patch.
;
; Progress is spread over WRAM: block $86, quest $88, lives $7C, extra-life
; counter $7E, subweapon $8E, multi-shot $90, whip $92, timer/hearts/health
; $13F0-$13F5, score $1F40-$1F43, event flags $1600-$1605 and a 64-byte
; table at $19C0 that new game clears.
;
; Saving: every block entry (game mode 4 -> 5, after the block is set up and
; faded in): block ends, deaths, continues. Skipped in the attract demo
; ($4A = 1), and on block 1-1-1 of the first quest while a game started with
; START has not yet left it, so a new game does not overwrite a save until
; the player reaches the next block.
;
; Loading goes through CONTINUE: after the name, the password grid opens
; filled with the password for the saved stage, computed by the game's own
; routines for the name just entered. Confirming it unchanged restores the
; full saved state at the end of the game's setup, including the exact block
; and everything the password drops (lives, hearts, health, whip, subweapon,
; multi-shot, score). A typed password works as in the original game.
;
; SRAM layout (8 KB at $70:0000):
;   two slots at $700000 and $700100, written alternately:
;     +0 "SCV4"  +4 sequence  +6 sum16 of data  +8 data (!DATALEN bytes)
;   $700300  prefilled grid (16 cells), $700310 prefill flag
;   $700312  resume flag, $700314 temp words
;   $70031A  fresh flag: a START game still in block 1-1-1

lorom

if stringsequal("!REGION", "us")
    !SAVE_SITE    = $8095FB   ; STZ $13C0 : INC $70 (mode 4 -> 5)
    !INIT_END     = $80952A   ; INC $70 : STZ $72 (end of new-game setup)
    !GRID_INIT    = $838272   ; STZ $1E80 : INC $1C00 (grid entry state 4)
    !GRID_ACCEPT  = $838347   ; LDA #$0004 : STA $32 (grid accepted, state 8)
    !PW_BUILD     = $8384DE   ; $1C10-13 = [$86, $88, checksum] from name
    !PW_EXPAND    = $838549   ; $1C10-13 -> cells $1C20-2F (unmasked)
    !RTL83        = $8278     ; an RTL in bank $83
    !STAGE_START  = $81FBAC   ; byte table: block -> first block of its stage
elseif stringsequal("!REGION", "jp")
    ; same code at the same addresses; only the tables moved
    !SAVE_SITE    = $8095FB
    !INIT_END     = $80952A
    !GRID_INIT    = $838272
    !GRID_ACCEPT  = $838347
    !PW_BUILD     = $8384DE
    !PW_EXPAND    = $838549
    !RTL83        = $8278
    !STAGE_START  = $81FBA2
else
    error "REGION must be us or jp"
endif

!SLOT0    = $700000
!SLOT1    = $700100
!SLOTSTEP = $0100
!PREFILL  = $700300
!PFLAG    = $700310
!RESUME   = $700312
!TMP      = $700314
!TMP2     = $700316
!TMP3     = $700318
!FRESH    = $70031A

; ---- header: ROM + RAM + battery, 8 KB SRAM ----
org $00FFD6
    db $02
org $00FFD8
    db $03

; ---- hooks (all sites run with 16-bit A/X/Y and D = 0) ----
org !SAVE_SITE
    jsl save_hook
    nop
org !INIT_END
    jsl resume_hook
org !GRID_INIT
    jsl pw_open
    nop
    nop
org !GRID_ACCEPT
    jsl pw_accept
    nop

; ---- new code at the end of the last bank (unused $FF run) ----
org $9FF400

; WRAM regions that make up a save, as (address, length) pairs in bank $7E.
regions:
    dw $007C, 4               ; lives, extra-life counter
    dw $0086, 4               ; block, quest
    dw $008E, 6               ; subweapon, multi-shot, whip
    dw $13F0, 6               ; timer, hearts, health
    dw $1F40, 4               ; score
    dw $1600, 6               ; event flags
    dw $19C0, 64              ; table cleared by new game
    dw $0000
!DATALEN = 4+4+6+6+4+6+64

; Block entry: save unless in the demo or at the start of a fresh game.
save_hook:
    php
    rep #$30
    pha
    phx
    phy
    phb
    lda.l $7E004A
    bne .skip
    lda.l $7E0086
    ora.l $7E0088
    bne .save
    lda.l !FRESH
    bne .skip
.save
    lda #$0000
    sta.l !FRESH
    jsr do_save
.skip
    plb
    ply
    plx
    pla
    plp
    stz $13C0
    inc $70
    rtl

; Copy the regions between WRAM and SRAM data at offset Y (bank $70).
; save: WRAM -> SRAM. Returns Y past the data. 16-bit A/X/Y.
save_regions:
    ldx #$0000
.next
    lda.l regions,x
    beq .done
    sta.l !TMP2               ; WRAM address
    lda.l regions+2,x
    dec a
    sta.l !TMP3               ; length - 1
    phx
    lda.l !TMP2
    tax
    lda.l !TMP3
    phb
    db $54,$70,$7E            ; MVN $7E -> $70 (X src, Y dst)
    plb
    plx
    inx
    inx
    inx
    inx
    bra .next
.done
    rts

; restore: SRAM data at offset X (bank $70) -> WRAM.
restore_regions:
    txy                       ; Y walks the SRAM data
    ldx #$0000
.next
    lda.l regions,x
    beq .done
    sta.l !TMP2
    lda.l regions+2,x
    dec a
    sta.l !TMP3
    phx
    tya
    tax                       ; X = SRAM source
    lda.l !TMP2
    tay                       ; Y = WRAM destination
    lda.l !TMP3
    phb
    db $54,$7E,$70            ; MVN $70 -> $7E
    plb
    txy                       ; SRAM source continues
    plx
    inx
    inx
    inx
    inx
    bra .next
.done
    rts

; Write the live state into the older SRAM slot. 16-bit A/X/Y.
do_save:
    jsr find_newest
    bcs .have
    ldx #$0000
    lda #$0000
    bra .write
.have
    lda.l !SLOT0+4,x
    inc a
    pha
    txa
    eor #!SLOTSTEP
    tax
    pla
.write
    sta.l !TMP
    lda #$0000
    sta.l !SLOT0+0,x          ; invalidate the target slot first
    sta.l !SLOT0+2,x
    lda.l !TMP
    sta.l !SLOT0+4,x
    phx
    txa
    clc
    adc.w #!SLOT0+8
    tay
    jsr save_regions
    plx
    jsr slot_sum
    sta.l !SLOT0+6,x
    lda #$4353                ; "SC"
    sta.l !SLOT0+0,x
    lda #$3456                ; "V4"
    sta.l !SLOT0+2,x
    rts

; X = slot offset. Returns A = 16-bit byte sum of the slot data, X kept.
slot_sum:
    phx
    lda #$0000
    sta.l !TMP
    ldy.w #!DATALEN
.loop
    lda.l !SLOT0+8,x
    and #$00FF
    clc
    adc.l !TMP
    sta.l !TMP
    inx
    dey
    bne .loop
    plx
    lda.l !TMP
    rts

; X = slot offset. Carry set if the slot holds a valid save.
slot_valid:
    lda.l !SLOT0+0,x
    cmp #$4353
    bne .no
    lda.l !SLOT0+2,x
    cmp #$3456
    bne .no
    jsr slot_sum
    cmp.l !SLOT0+6,x
    bne .no
    sec
    rts
.no
    clc
    rts

; Carry set and X = offset of the newest valid slot; carry clear if none.
find_newest:
    ldx #$0000
    jsr slot_valid
    bcc .only1
    ldx #!SLOTSTEP
    jsr slot_valid
    bcc .pick0
    lda.l !SLOT1+4
    sec
    sbc.l !SLOT0+4
    beq .pick0
    bmi .pick0
    ldx #!SLOTSTEP
    sec
    rts
.pick0
    ldx #$0000
    sec
    rts
.only1
    ldx #!SLOTSTEP
    jmp slot_valid

; Password grid opens: if a save exists, fill the grid with the password for
; the saved stage and quest under the name just entered, and remember it.
pw_open:
    php
    rep #$30
    pha
    phx
    phy
    phb
    lda #$0000
    sta.l !PFLAG
    sta.l !RESUME
    jsr find_newest
    bcc .out
    lda.l $7E0086             ; keep the live block and quest
    pha
    lda.l $7E0088
    pha
    lda.l !SLOT0+8+4,x        ; saved block (data offset 4)
    and #$00FF
    phx
    tax
    lda.l !STAGE_START,x
    and #$00FF
    sta.l $7E0086
    plx
    lda.l !SLOT0+8+6,x        ; saved quest
    sta.l $7E0088
    pea $0101                 ; the routines read tables through DB = $01
    plb
    plb
    jsr build_pw
    pla
    sta.l $7E0088
    pla
    sta.l $7E0086
    sep #$20
    ldx #$000F
.cells
    lda.l $7E1C20,x
    and #$03
    sta.l $7E1C20,x
    sta.l !PREFILL,x
    dex
    bpl .cells
    rep #$20
    lda #$0001
    sta.l !PFLAG
.out
    plb
    ply
    plx
    pla
    plp
    stz $1E80
    inc $1C00
    rtl

; Run the game's password builder and expander (JSR $84DE, JSR $8549 in
; bank $83) from this bank.
build_pw:
    phk
    pea.w .r1-1
    pea.w !RTL83-1
    jml !PW_BUILD
.r1
    phk
    pea.w .r2-1
    pea.w !RTL83-1
    jml !PW_EXPAND
.r2
    rep #$30
    rts

; Grid accepted (valid password). If it is the unchanged prefilled grid,
; flag a resume for the end of the game's setup.
pw_accept:
    php
    rep #$30
    pha
    phx
    lda.l !PFLAG
    beq .out
    lda #$0000
    sta.l !PFLAG
    ldx #$000E
.cmp
    lda.l $7E1C20,x
    and #$0303
    cmp.l !PREFILL,x
    bne .out
    dex
    dex
    bpl .cmp
    lda #$0001
    sta.l !RESUME
.out
    plx
    pla
    plp
    lda #$0004
    sta $32
    rtl

; End of new-game setup (START, or a password from CONTINUE). Mark a START
; game as fresh. After a flagged resume from CONTINUE, restore the full
; saved state; the block's own setup follows.
resume_hook:
    phx
    phy
    lda.l $7E1E02             ; menu item: 0 = START, 1 = CONTINUE
    and #$00FF
    cmp #$0001
    lda #$0000
    bcs .cont
    inc a
.cont
    sta.l !FRESH
    lda.l !RESUME
    beq .out
    lda #$0000
    sta.l !RESUME
    lda.l $7E1E02             ; menu item: 1 = CONTINUE
    cmp #$0001
    bne .out
    phb
    jsr find_newest
    bcc .none
    txa
    clc
    adc.w #!SLOT0+8
    tax
    jsr restore_regions
    lda #$0000
    sta.l $7E13E8             ; keep the saved timer (no reload from table)
.none
    plb
.out
    ply
    plx
    inc $70
    stz $72
    rtl
