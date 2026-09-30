#!/usr/bin/env python3
"""Minimal 65816 disassembler for a headerless SNES ROM.

  dis.py <rom> <addr> [count=40] [--m 0|1] [--x 0|1] [--hirom]

addr is a SNES address in hex (e.g. 9FD7AE). --m/--x give the starting
accumulator/index width (1 = 8-bit); REP/SEP after that are tracked
linearly, so a width is only right until the first branch target that is
entered with other flags. Data is decoded as code: check alignment.
"""
import argparse
from snesmap import rom_offset

OPS = {}
def op(code, mn, mode): OPS[code] = (mn, mode)
table = """
00 BRK imm8;01 ORA dxi;02 COP imm8;03 ORA sr;04 TSB dp;05 ORA dp;06 ASL dp;07 ORA dil;08 PHP imp;09 ORA immm;0A ASL acc;0B PHD imp;0C TSB abs;0D ORA abs;0E ASL abs;0F ORA long
10 BPL rel;11 ORA dix;12 ORA di;13 ORA srix;14 TRB dp;15 ORA dpx;16 ASL dpx;17 ORA dily;18 CLC imp;19 ORA absy;1A INC acc;1B TCS imp;1C TRB abs;1D ORA absx;1E ASL absx;1F ORA longx
20 JSR abs;21 AND dxi;22 JSL long;23 AND sr;24 BIT dp;25 AND dp;26 ROL dp;27 AND dil;28 PLP imp;29 AND immm;2A ROL acc;2B PLD imp;2C BIT abs;2D AND abs;2E ROL abs;2F AND long
30 BMI rel;31 AND dix;32 AND di;33 AND srix;34 BIT dpx;35 AND dpx;36 ROL dpx;37 AND dily;38 SEC imp;39 AND absy;3A DEC acc;3B TSC imp;3C BIT absx;3D AND absx;3E ROL absx;3F AND longx
40 RTI imp;41 EOR dxi;42 WDM imm8;43 EOR sr;44 MVP bm;45 EOR dp;46 LSR dp;47 EOR dil;48 PHA imp;49 EOR immm;4A LSR acc;4B PHK imp;4C JMP abs;4D EOR abs;4E LSR abs;4F EOR long
50 BVC rel;51 EOR dix;52 EOR di;53 EOR srix;54 MVN bm;55 EOR dpx;56 LSR dpx;57 EOR dily;58 CLI imp;59 EOR absy;5A PHY imp;5B TCD imp;5C JML long;5D EOR absx;5E LSR absx;5F EOR longx
60 RTS imp;61 ADC dxi;62 PER rell;63 ADC sr;64 STZ dp;65 ADC dp;66 ROR dp;67 ADC dil;68 PLA imp;69 ADC immm;6A ROR acc;6B RTL imp;6C JMP ind;6D ADC abs;6E ROR abs;6F ADC long
70 BVS rel;71 ADC dix;72 ADC di;73 ADC srix;74 STZ dpx;75 ADC dpx;76 ROR dpx;77 ADC dily;78 SEI imp;79 ADC absy;7A PLY imp;7B TDC imp;7C JMP absxi;7D ADC absx;7E ROR absx;7F ADC longx
80 BRA rel;81 STA dxi;82 BRL rell;83 STA sr;84 STY dp;85 STA dp;86 STX dp;87 STA dil;88 DEY imp;89 BIT immm;8A TXA imp;8B PHB imp;8C STY abs;8D STA abs;8E STX abs;8F STA long
90 BCC rel;91 STA dix;92 STA di;93 STA srix;94 STY dpx;95 STA dpx;96 STX dpy;97 STA dily;98 TYA imp;99 STA absy;9A TXS imp;9B TXY imp;9C STZ abs;9D STA absx;9E STZ absx;9F STA longx
A0 LDY immx;A1 LDA dxi;A2 LDX immx;A3 LDA sr;A4 LDY dp;A5 LDA dp;A6 LDX dp;A7 LDA dil;A8 TAY imp;A9 LDA immm;AA TAX imp;AB PLB imp;AC LDY abs;AD LDA abs;AE LDX abs;AF LDA long
B0 BCS rel;B1 LDA dix;B2 LDA di;B3 LDA srix;B4 LDY dpx;B5 LDA dpx;B6 LDX dpy;B7 LDA dily;B8 CLV imp;B9 LDA absy;BA TSX imp;BB TYX imp;BC LDY absx;BD LDA absx;BE LDX absy;BF LDA longx
C0 CPY immx;C1 CMP dxi;C2 REP imm8;C3 CMP sr;C4 CPY dp;C5 CMP dp;C6 DEC dp;C7 CMP dil;C8 INY imp;C9 CMP immm;CA DEX imp;CB WAI imp;CC CPY abs;CD CMP abs;CE DEC abs;CF CMP long
D0 BNE rel;D1 CMP dix;D2 CMP di;D3 CMP srix;D4 PEI dp;D5 CMP dpx;D6 DEC dpx;D7 CMP dily;D8 CLD imp;D9 CMP absy;DA PHX imp;DB STP imp;DC JML absil;DD CMP absx;DE DEC absx;DF CMP longx
E0 CPX immx;E1 SBC dxi;E2 SEP imm8;E3 SBC sr;E4 CPX dp;E5 SBC dp;E6 INC dp;E7 SBC dil;E8 INX imp;E9 SBC immm;EA NOP imp;EB XBA imp;EC CPX abs;ED SBC abs;EE INC abs;EF SBC long
F0 BEQ rel;F1 SBC dix;F2 SBC di;F3 SBC srix;F4 PEA abs;F5 SBC dpx;F6 INC dpx;F7 SBC dily;F8 SED imp;F9 SBC absy;FA PLX imp;FB XCE imp;FC JSR absxi;FD SBC absx;FE INC absx;FF SBC longx
"""
for chunk in table.replace("\n", ";").split(";"):
    chunk = chunk.strip()
    if chunk:
        c, mn, mode = chunk.split()
        op(int(c, 16), mn, mode)

FMT = {
    "imp": (0, "{mn}"), "acc": (0, "{mn} A"), "imm8": (1, "{mn} #${v:02X}"),
    "dp": (1, "{mn} ${v:02X}"), "dpx": (1, "{mn} ${v:02X},X"), "dpy": (1, "{mn} ${v:02X},Y"),
    "dxi": (1, "{mn} (${v:02X},X)"), "dix": (1, "{mn} (${v:02X}),Y"), "di": (1, "{mn} (${v:02X})"),
    "dil": (1, "{mn} [${v:02X}]"), "dily": (1, "{mn} [${v:02X}],Y"), "sr": (1, "{mn} ${v:02X},S"),
    "srix": (1, "{mn} (${v:02X},S),Y"), "abs": (2, "{mn} ${v:04X}"), "absx": (2, "{mn} ${v:04X},X"),
    "absy": (2, "{mn} ${v:04X},Y"), "ind": (2, "{mn} (${v:04X})"), "absxi": (2, "{mn} (${v:04X},X)"),
    "absil": (2, "{mn} [${v:04X}]"), "long": (3, "{mn} ${v:06X}"), "longx": (3, "{mn} ${v:06X},X"),
    "bm": (2, "{mn} ${a:02X},${b:02X}"), "rel": (1, None), "rell": (2, None),
}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("rom"); ap.add_argument("addr"); ap.add_argument("count", nargs="?", type=int, default=40)
    ap.add_argument("--m", type=int, default=1); ap.add_argument("--x", type=int, default=1)
    ap.add_argument("--hirom", action="store_true")
    a = ap.parse_args()
    rom = open(a.rom, "rb").read()
    pc, m, x = int(a.addr, 16), a.m, a.x
    for _ in range(a.count):
        o = rom_offset(pc, a.hirom)
        c = rom[o]
        mn, mode = OPS[c]
        if mode == "immm": ln = 1 if m else 2; fmt = "{mn} #${v:0%dX}" % (ln * 2)
        elif mode == "immx": ln = 1 if x else 2; fmt = "{mn} #${v:0%dX}" % (ln * 2)
        else: ln, fmt = FMT[mode]
        raw = rom[o:o + 1 + ln]
        v = int.from_bytes(raw[1:], "little") if ln else 0
        if mode == "rel":
            t = (pc & 0xFF0000) | ((pc + 2 + (v - 256 if v > 127 else v)) & 0xFFFF)
            s = f"{mn} ${t:06X}"
        elif mode == "rell":
            t = (pc & 0xFF0000) | ((pc + 3 + (v - 65536 if v > 32767 else v)) & 0xFFFF)
            s = f"{mn} ${t:06X}"
        elif mode == "bm":
            s = f"{mn} ${raw[1]:02X},${raw[2]:02X}   ; dst bank ${raw[1]:02X}, src bank ${raw[2]:02X}"
        else:
            s = fmt.format(mn=mn, v=v)
        if mn == "REP":
            if v & 0x20: m = 0
            if v & 0x10: x = 0
        if mn == "SEP":
            if v & 0x20: m = 1
            if v & 0x10: x = 1
        print(f"{pc:06X}  {raw.hex(' '):<12} {s:<22} ; m{m}x{x}")
        pc = (pc & 0xFF0000) | ((pc + 1 + ln) & 0xFFFF)


main()
