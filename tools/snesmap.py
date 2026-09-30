"""SNES address <-> ROM file offset helpers (headerless images)."""


def rom_offset(addr, hirom=False):
    bank, lo = addr >> 16, addr & 0xFFFF
    if hirom:
        return ((bank & 0x3F) << 16) | lo
    if lo < 0x8000:
        raise ValueError(f"${addr:06X} is not ROM in LoROM")
    return ((bank & 0x7F) << 15) | (lo - 0x8000)


def snes_addr(off, hirom=False):
    if hirom:
        return 0xC00000 | off
    return 0x800000 | ((off >> 15) << 16) | 0x8000 | (off & 0x7FFF)
