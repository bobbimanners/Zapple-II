# BP/M AUX56 — first integrated experimental build

**Status: experimental Z80 source; static layout checks passed. Not assembled with Udo Munk Z80asm or tested in MAME/hardware.** Back up the working AUX44 build and your ProDOS disk image before trying this. No SOFTCARD65 changes are required (continue using the existing Soroc-default, cursor-fixed driver).

This is a **first integration attempt** after the independently tested LC2.COM experiment. Its aim is a larger ordinary CP/M 2.2 transient program area without moving the ProDOS-backed BDOS or CCP out of main memory.

## TPA and gateway

| Z80 logical address | Physical storage | Use |
|---|---|---|
| `$0000–$00FF` | AUX ordinary RAM | CP/M page zero, FCBs, DMA |
| `$0100–$AFFF` | AUX ordinary RAM | Original 44K address window |
| `$B000–$DEFF` | AUX Language Card, bank 2/common | Additional 11.75 KiB |
| `$DF00–$DFFF` | AUX Language Card, bank 2/common | BDOS entry, BIOS table, switching code |
| `$E000–$EFFF` | Apple II I/O / slot space | Not usable RAM |
| `$F300` | AUX ordinary Apple `$0300` | Synthetic 15-byte CP/M DPB |
| `$F800–$FFFF` | AUX ordinary Apple `$0800–$0FFF` | Synthetic 2K allocation vector |

The TPA is `$0100–$DEFF` inclusive: **56,832 bytes (55.5 KiB)**. The sign-on banner reports 55K because it truncates to whole KiB.

## How the new gateway works

The user's `.COM` executes with normal RAMRD/RAMWRT=AUX, ALTZP=AUX, and Language Card bank 2 active. Its `CALL 0005H` goes to the public BDOS entry at `$DF00` in AUX LC. The LC gateway sets ordinary RAM mapping to MAIN and jumps to `AXGATE` in **ordinary MAIN RAM at `$7A00`**. That bridge saves the auxiliary SP, selects MAIN ALTZP, restores the resident main SP, and invokes the existing BDOS dispatcher.

After the call, it restores the AUX LC bank 2/ALTZP, original SP and returned A/HL, then jumps to a small **AUX LC** return stub. Only that LC stub selects ordinary RAMRD/RAMWRT back to AUX before `RET` to the transient. This avoids switching instruction fetches out from under running code.

Main-memory wrappers around auxiliary reads copy FCBs, data records and strings whether the buffers fall in conventional auxiliary RAM or the auxiliary LC range. The synthetic DPB and allocation vector can no longer live at B100/B800, since those addresses are now in the TPA.

## Memory preservation

During an AUX56 program the kernel uses spare **MAIN ordinary RAM** for snapshots:

| MAIN Z80 region | Saved state |
|---|---|
| `$2000–$27FF` | AUX `$F800–$FFFF` metadata area |
| `$2800–$280F` | AUX `$F300–$F30F` metadata area |
| `$3000–$3FFF` | Complete 4K MAIN LC bank 2 |
| `$4000–$6FFF` | Complete 12K AUX LC bank 2 + common area (also reused for 12K MAIN LC preservation during CCP `SAVE`) |

These are restored after the transient returns, including on handled loader errors. The **other** 4K LC bank is not modified. The persistent main resident BDOS and ProDOS I/O buffers remain in their previous locations.

**Important:** If a resident `/RAM` driver or other ProDOS component actively uses AUX LC while the program runs, accesses during BDOS calls could interfere. Test without `/RAM` and other auxiliary-memory resident drivers. Copy-on-entry/restore-on-exit alone does **not** provide concurrent ownership of AUX LC.

## Building

Replace your `softcard80.asm` with the supplied `softcard80-aux56.asm`, retain the existing SOFTCARD65, assemble using your normal Udo Munk Z80asm build, and put the updated Z80 image on a **backed-up** ProDOS test image. Alternatively, review `bpm-aux56.patch` against `softcard80-aux44-save44-plus-bdos.asm` (your AUX44 SAVE fix plus BDOS 11/12 fixes). The patch is for human review if your local source has diverged.

`python3 test_hi56_layout.py` checks HI56 payload placement across the B000 boundary.

`python3 check_aux56.py` does a heuristic **static** check for segment capacities, first-eight-character label collisions, the embedded gateway size and relative jumps. It is **not** a substitute for a real assembler or MAME test.

## Test sequence

Please **cold-boot** after installing the new binary. Start small:

```
A>HELLO44
A>WBOOT44
A>HI9000
A>HI56
```

The new `HI56.COM` is about 47 KiB on disk, jumps from `$0100` to Z80 `$B900` in **AUX Language Card RAM**, and prints through ordinary BDOS function 9:

```
HI56: executing from AUX LC at B900h; BDOS 9 PASS
```

Only if that succeeds should you try existing programs such as `AUXSRCH`, `AUXFS`, `TE`, `PIP`, `MBASIC`, `STAT`, WordStar and Turbo Pascal. Large file operations and the terminal should be exercised again after the memory-system changes.

If the machine freezes or prints garbage, **reset the emulator** before further testing. A crash during ALTZP/LC transitions can leave ProDOS with the wrong memory configuration.

## Deferred work / caveats

* **`SAVE` is deliberately still limited to 175 pages** (44K ordinary AUX region). The AUX LC is restored after programs exit, so the classic `SAVE` command cannot yet retrieve transient LC contents. A full 55.5 KiB SAVE requires a separate persistent snapshot design.
* `BYE` and all existing interactive CCP commands should remain unchanged, but they require regression testing.
* This is source only, with a new diagnostic COM; do **not** call it a verified working AUX56 release before assembly and real MAME testing.
* No sector-level CP/M BIOS disk services have been added; file I/O remains through the existing ProDOS-backed BDOS.
