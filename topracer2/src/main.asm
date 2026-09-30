; Top Racer 2 (Japan, Piko Interactive 2018 reissue) - battery save patch.
;
; The championship state lives in two WRAM areas: the progress block
; $7E1CDB-$7E1DF2 and the standings table $7EF000-$7EF17F. The game already
; snapshots both before launching a race (routine $9F81A6), because the race
; engine reuses that RAM. This patch writes both areas to battery SRAM at two
; points: right after that pre-race snapshot, and right after a qualifying
; race has been fully applied (money, next race, then the championship points
; awarded by the results screens). The attract demo (flag bit 3 of $7E0022)
; never saves.
;
; Loading goes through the existing CONTINUE > PASSWORD screen: when a save
; exists the screen is prefilled with the saved game's password, and
; confirming it unchanged restores the full saved state (race within the
; country and all standings, which the password alone cannot hold). The
; restore is applied at the end of the championship setup that follows a
; password, since that setup resets the driver order and standings.
;
; SRAM layout (8 KB at $70:0000):
;   two slots at $700000 and $700400, written alternately:
;     +0 "TR2S"  +4 sequence  +6 sum16 of data  +8 data ($298 bytes)
;   $700800  prefilled password (22 bytes), $700816 prefill-from-save flag
;   $700818  temp words, $70081C resume flag
;   $701000  scratch copy of the live progress block

lorom

!SLOT0    = $700000
!SLOT1    = $700400
!DATALEN  = $0298
!BLKLEN   = $0118
!PREFILL  = $700800
!PFLAG    = $700816
!TMP      = $700818
!TMP2     = $70081A
!RESUME   = $70081C      ; 1 = saved game confirmed, restore it at game start
!RTL9F    = $8CDD        ; any $6B byte in bank $9F, used as an RTL trampoline

; ---- header: ROM + RAM + battery, 8 KB SRAM ----
org $00FFD6
    db $02
org $00FFD8
    db $03

; ---- hooks (all sites run with 16-bit A/X/Y) ----
org $9F8195              ; after JSR $81A6 (snapshot), replaces LDA $818000
    jsl save_hook

org $9F811F              ; qualified after a race: replaces JSR $E343 (results
    jsl post_race_hook   ; and standings screens, which award the points)
    db $EA,$EA           ; and LDA $1CE5

org $9FD0C3              ; password screen: replaces JSR $D7AE : LDA #$FFFF
    jsl pw_open
    db $EA,$EA

org $9FD414              ; password accepted: replaces STZ $1CE5 + clear loop
    jsl pw_accept
    db $EA,$EA,$EA,$EA,$EA,$EA,$EA,$EA,$EA,$EA,$EA,$EA,$EA
    assert pc() <= $9FD425

org $9F8098              ; championship setup: replaces the standings clear
    jsl resume_hook      ; loop and JMP $812A
    jmp $812A
    db $EA,$EA,$EA,$EA,$EA,$EA,$EA,$EA,$EA,$EA,$EA,$EA,$EA,$EA,$EA,$EA,$EA,$EA
    assert pc() == $9F80B1

org $9FDE78              ; new game setup: replaces LDX #$0028 : LDA #$0000
    jsl new_game_hook
    db $EA,$EA

; ---- new code in empty bank $AF ----
org $AF8000

save_hook:
    php
    rep #$30
    pha
    phx
    phy
    phb
    jsr do_save
    plb
    ply
    plx
    pla
    plp
    lda.l $818000
    rtl

post_race_hook:
    jsr call_results
    php
    rep #$30
    pha
    phx
    phy
    phb
    jsr do_save
    plb
    ply
    plx
    pla
    plp
    lda.l $7E1CE5            ; replaced instruction; flags feed the BNE after
    rtl

; Write the live championship state into the older SRAM slot.
do_save:
    lda.l $7E0022            ; bit 3 is set while the attract demo runs
    and #$0008
    bne .ret
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
    eor #$0400
    tax
    pla
.write
    sta.l !TMP2
    lda #$0000
    sta.l !SLOT0+0,x         ; invalidate the target slot first
    sta.l !SLOT0+2,x
    lda.l !TMP2
    sta.l !SLOT0+4,x
    phx
    phb
    txa
    clc
    adc #$0008
    tay
    ldx #$1CDB               ; progress block
    lda #!BLKLEN-1
    db $54,$70,$7E           ; MVN $7E -> $70
    ldx #$F000               ; standings table (Y continues after the block)
    lda #!DATALEN-!BLKLEN-1
    db $54,$70,$7E
    plb
    plx
    jsr slot_sum
    sta.l !SLOT0+6,x
    lda #$5254               ; "TR"
    sta.l !SLOT0+0,x
    lda #$5332               ; "2S"
    sta.l !SLOT0+2,x
.ret
    rts

; X = slot offset. Returns A = 16-bit byte sum of the slot data, X kept.
slot_sum:
    phx
    lda #$0000
    sta.l !TMP
    ldy #!DATALEN
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
    cmp #$5254
    bne .no
    lda.l !SLOT0+2,x
    cmp #$5332
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
    ldx #$0400
    jsr slot_valid
    bcc .pick0
    lda.l !SLOT1+4
    sec
    sbc.l !SLOT0+4
    beq .pick0
    bmi .pick0
    ldx #$0400
    sec
    rts
.pick0
    ldx #$0000
    sec
    rts
.only1
    ldx #$0400
    jmp slot_valid

; Emulate JSR $D7AE (password encoder, bank $9F) from this bank.
call_encoder:
    phk
    pea.w enc_ret-1
    pea.w !RTL9F-1
    jml $9FD7AE
enc_ret:
    rts

; Emulate JSR $E343 (results and standings screens) from this bank.
call_results:
    phk
    pea.w res_ret-1
    pea.w !RTL9F-1
    jml $9FE343
res_ret:
    rts

; Password screen opens: prefill with the saved game's password if any.
pw_open:
    jsr find_newest
    bcc .plain
    phx
    phb
    ldx #$1CDB               ; back up the live progress block
    ldy #$1000
    lda #!BLKLEN-1
    db $54,$70,$7E           ; MVN $7E -> $70
    plb
    plx
    phb
    txa                      ; put the saved block in place
    clc
    adc #$0008
    tax
    ldy #$1CDB
    lda #!BLKLEN-1
    db $54,$7E,$70           ; MVN $70 -> $7E
    plb
    jsr call_encoder
    phb
    ldx #$1000               ; restore the live progress block
    ldy #$1CDB
    lda #!BLKLEN-1
    db $54,$7E,$70
    plb
    ldx #$0000
.copy
    lda.l $7E1780,x
    sta.l !PREFILL,x
    inx
    inx
    cpx #$0016
    bne .copy
    lda #$0001
    sta.l !PFLAG
    bra .done
.plain
    lda #$0000
    sta.l !PFLAG
    jsr call_encoder
.done
    lda #$FFFF
    rtl

; Password accepted and decoded. Do the replaced work, then flag a resume if
; the confirmed password is the unchanged saved one.
pw_accept:
    lda #$0000
    sta.l $7E1CE5
    ldx #$0028
.clear
    sta.l $7E1DC3,x
    dex
    dex
    bne .clear
    lda #$0000
    sta.l !RESUME
    lda.l !PFLAG
    beq .out
    lda #$0000
    sta.l !PFLAG
    ldx #$0000
.cmp
    lda.l $7E1780,x
    cmp.l !PREFILL,x
    bne .out
    inx
    inx
    cpx #$0016
    bne .cmp
    lda #$0001
    sta.l !RESUME
.out
    lda #$0000
    tax
    rtl

; End of championship setup: do the replaced standings clear, then restore
; the full saved state if a resume was flagged.
resume_hook:
    lda #$0000
    ldx #$0000
.clear
    sta.l $7EF000,x
    inx
    inx
    cpx #$0100
    bne .clear
    lda.l !RESUME
    beq .out
    lda #$0000
    sta.l !RESUME
    jsr find_newest
    bcc .out
    phb
    txa
    clc
    adc #$0008
    tax
    ldy #$1CDB               ; progress block
    lda #!BLKLEN-1
    db $54,$7E,$70
    ldy #$F000               ; standings table (X continues after the block)
    lda #!DATALEN-!BLKLEN-1
    db $54,$7E,$70
    plb
.out
    lda #$0000
    rtl

; New game or country select: never resume.
new_game_hook:
    lda #$0000
    sta.l !RESUME
    ldx #$0028
    rtl
