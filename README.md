# Zapple-II

**CP/M programs on an Apple IIe Z80 SoftCard, using ProDOS files instead of CP/M disks.**

Zapple-II is a collection of tools and software for running Z80 programs on an Apple II with a Microsoft Z80 SoftCard (or compatible card). Its main component, **BP/M**, is a CP/M 2.2-compatible environment that runs on top of **ProDOS 8**.

This is not a Z80 CPU emulator: CP/M programs execute on the real Z80 processor on the SoftCard. BP/M implements the CP/M **CCP**, **BDOS**, and much of the **BIOS** interface, translating CP/M file operations into ProDOS calls handled by the Apple II's 6502. CP/M drive letters refer to ProDOS subdirectories, so there is no need to use CP/M-formatted floppy disks.

The current **AUX56** implementation uses the Apple IIe's auxiliary memory to provide a 55.5 KB Transient Program Area (TPA) CP/M memory configuration (55.5 KiB available between `$0100` and `$DEFF`). It supports real-world applications including WordStar, Turbo Pascal, and Microsoft BASIC.

## Requirements

- An **Apple IIe with 128 KB RAM** (or a compatible emulation with auxiliary RAM).
- A **Microsoft Z80 SoftCard** or compatible Z80 card, currently configured for **slot 4**.
- **ProDOS 8**, with **BASIC.SYSTEM** if launching from the ProDOS BASIC prompt.
- A ProDOS volume containing the Zapple-II files and the CP/M drive directories.

The AUX56 version requires the auxiliary RAM available on a 128 KB Apple IIe. Development and testing have been carried out in **MAME**; hardware and other emulator configurations may need adjustments.

## Quick start

1. Boot **ProDOS 8**. The included `zapple2.po` is a ProDOS disk image; depending on the version of the image, you may need to boot ProDOS from another disk or device first.
2. Make the Zapple-II volume or directory your current **ProDOS prefix**, so `SOFTCARD65` can find `SOFTCARD80.BIN`.
3. From **BASIC.SYSTEM**, start the system with:

   ```text
   -SOFTCARD65
   ```

4. `SOFTCARD65` loads the Z80 code and hands control to the SoftCard. You should see the BP/M startup message followed by a CP/M-style prompt:

   ```text
   BP/M AUX TPA 44K
   A>
   ```

5. Enter CCP commands or launch `.COM` programs by name. The `.COM` extension is optional when starting a program:

   ```text
   A>DIR
   A>MBASIC
   A>WS
   A>TURBO
   ```

6. To leave BP/M and return to the ProDOS program selector, enter `BYE` and confirm with `Y`:

   ```text
   A>BYE
   Y/N? Y
   ```

### Drives and files

BP/M maps CP/M drive letters to directories on a normal ProDOS volume:

| CP/M drive | ProDOS directory | Example file |
| --- | --- | --- |
| `A:` | `A/` | `A/WS.COM` |
| `B:` | `B/` | `B/TEST.TXT` |
| `C:` | `C/` | `C/MBASIC.COM` |

The mapping supports drive letters `A:` through `P:` when the corresponding directories exist. Relative paths use the active ProDOS volume/prefix; if no prefix is set, BP/M looks for an appropriate volume containing a drive directory.

Files remain ordinary ProDOS files. BP/M exposes them through CP/M's 8.3 filename and 128-byte record conventions. Copy programs and their associated data/overlay files into the appropriate ProDOS directory. For example, WordStar uses `WS.COM` together with its `.OVR` files.

## CCP commands

BP/M includes its own small **Console Command Processor (CCP)**. Commands are case-insensitive.

| Command | Description | Example |
| --- | --- | --- |
| `DIR [filespec]` | List files on the current drive or matching a filename pattern; four columns | `DIR A:*.COM` |
| `TYPE filespec` | Display a text file | `TYPE README.TXT` |
| `ERA filespec` | Delete file(s); wildcard deletions require confirmation | `ERA *.BAK` |
| `REN new=old` | Rename a file; destination name comes first | `REN NEW.TXT=OLD.TXT` |
| `SAVE n filespec` | Save `n` 256-byte pages of auxiliary TPA memory starting at `$0100` (0–175 pages) | `SAVE 175 SNAP.COM` |
| `A:` … `P:` | Change the default CP/M drive | `B:` |
| `TERM SOROC` | Select Soroc IQ-120-style terminal emulation | `TERM SOROC` |
| `TERM VIDEX` | Select Videx/VideoTerm-style terminal emulation | `TERM VIDEX` |
| `BYE` | Exit BP/M to ProDOS after confirmation | `BYE` |
| `program [args]` | Load and run a CP/M `.COM` file, passing its arguments through the CP/M command tail/FCBs | `WS TEST.TXT` |

`DIR` and `ERA` support CP/M-style `?` and `*` filename wildcards. Be careful with `ERA`, especially with wildcard patterns.

`TERM` is a **built-in command**; a separate `TERM.COM` is no longer needed. The latest 6502 driver is set up to start in **Soroc mode** by default, although you can change modes whenever you like.

**`SAVE` in AUX56:** `SAVE n filespec` writes the contents of **auxiliary RAM**, where the last `.COM` program ran, beginning at Z80 `$0100`. Each page is 256 bytes; the maximum is 222 pages = 55.5KiB (`$0100–$DEFF`). For example, `SAVE 222 SNAP.COM` saves the entire available TPA, and `SAVE 1 FIRST.BIN` saves its first page. `SAVE` does **not** save the resident main-memory BDOS or the auxiliary CP/M page zero. The data is whatever remains in auxiliary memory from the previous transient, including any changes it made. Loading another `.COM` program overwrites that memory; save immediately after the program you want to capture. `SAVE` writes binary data; use a fresh filename, since ProDOS may reject creation if the file already exists.

### Some things to try

```text
A>DIR
A>DIR B:
A>DIR A:*.COM
A>TYPE B:NOTES.TXT
A>B:
B>DIR
B>A:
A>REN NEW.TXT=OLD.TXT
A>TERM VIDEX
A>TERM SOROC
A>WS TEST.TXT
```

Utilities such as `PIP`, `STAT`, `ASM`, `DDT`, and `ZSID` are external CP/M programs, not built-in CCP commands. They must be present as `.COM` files on a mapped drive.

## CP/M programs

The following applications and utilities are known to work, or have been used in the course of BP/M development. The exact version and terminal configuration can matter.

| Program | Purpose / notes |
| --- | --- |
| **MBASIC** | Microsoft BASIC interpreter; runs with BP/M's Apple II terminal support. |
| **ASM** | Digital Research's CP/M 8080 assembler. |
| **ZSID** | Z80-oriented symbolic debugger. |
| **DDT** | Digital Research's CP/M debugger. |
| **TE** | Full-screen text editor; works with the terminal emulation. |
| **WordStar 3.3** | Full-screen word processor; a generic CP/M release works with Soroc terminal support. Other machine-specific installations may need adjustment. |
| **Turbo Pascal 3** | Integrated Pascal editor/compiler; tested compiling to memory and generating standalone `.COM` executables that run from the CCP. |
| **SuperCalc 1.12** | Spreadsheet; tested basic function and loading of sample files. |
| **dBase II v2.4** | Database management system; tested opening and browsing existing files, creating a new file. |
| **PIP** | CP/M file copier; tested copying entire directories, including large files. |
| **STAT** | Drive/file status utility. |
| **DUMP** | Hex dump utility. |
| **NSWEEP** | Interactive file-management utility. |
| **BASIC/5** | Processor Technology SOL-20 BASIC/5; example code is included in this repository. |

WordStar and Turbo Pascal use full-screen control sequences, so a suitable terminal configuration is important. **Soroc** is the recommended starting point for the tested versions.

## How BP/M works

The implementation has two cooperating pieces:

- **`SOFTCARD65`** is the 6502-side ProDOS SYS loader and backend. It loads the Z80 image, switches between the 6502 and Z80 as required, performs ProDOS MLI operations, and implements the direct 80-column console driver.
- **`SOFTCARD80.BIN`** is the Z80-side operating system: CP/M-compatible BDOS/BIOS services, a small CCP, ProDOS file translation, and auxiliary-memory program loading.

In the AUX56 configuration, transient `.COM` programs execute in auxiliary memory at `$0100–$DEFF`. Most BP/M resident code stays in main memory. A small **Language Card gateway** switches between the transient's auxiliary-memory context and the resident BDOS/BIOS code, including marshalling file control blocks and DMA buffers across memory banks.

A typical file operation follows this path:

```text
CP/M application on the Z80 (AUX RAM)
          |
          v
       CP/M BDOS
          |
          v
 AUX / MAIN memory gateway
          |
          v
 6502 backend -> ProDOS MLI -> ProDOS file
```

This approach avoids maintaining a separate CP/M disk filesystem and lets the Z80 programs share ordinary ProDOS storage. There is some overhead: CP/M's 128-byte record operations and cross-processor handoffs can make file I/O slower than native ProDOS software.

## Building from source

Prebuilt binaries and the disk image are provided in the repository. **Ensure your disk image contains the current AUX56 binaries** if you want the 44 KB configuration; older images/builds may contain an earlier version of BP/M.

The main development sources are:

- `SOFTCARD80.ASM` — Z80 BDOS, BIOS, CCP and auxiliary-memory support.
- `SOFTCARD65.S` — 6502 ProDOS loader and terminal/backend driver.
- `z80asm/` — Udo Munk's Z80 assembler (also builds on Linux).
- `z80as/` — alternative Mark Williams Z80 cross-assembler sources/tools.
- `zapple2.po` — ProDOS disk image.

### Z80 side

The Z80 code is assembled using **Udo Munk's Z80asm**, version 1.1. Under Linux, from the source directory, the basic invocation is:

```sh
z80asm softcard80.asm
```

Place the resulting Z80 binary on the ProDOS volume as **`SOFTCARD80.BIN`** (with the appropriate ProDOS binary file type/load address). The SoftCard configuration assumes that image is loaded into the Apple II's memory at `$1000`.

Be aware that this older assembler treats only the first **eight characters of symbol names** as significant. The Z80 sources therefore avoid long, colliding labels.

### 6502 side

The 6502 code is assembled with **Merlin 32** (the original project uses Merlin 8 v2.58). The resulting **SYS** program is `SOFTCARD65`. Preserve its ProDOS file type when moving it to a disk image; it must be launchable by BASIC.SYSTEM's `-SOFTCARD65` command.

The 6502 and Z80 sources both assume **SoftCard slot 4**. A different slot requires corresponding changes to the SoftCard address constants, and an appropriate rebuild.

The repository also contains the older Z80 assembler toolchain and the Processor Technology BASIC/5 example. See their source directories for further detail.

## Status and limitations

BP/M is a working **CP/M 2.2-compatible environment**, not a byte-for-byte reproduction of Digital Research CP/M. In particular:

- There is **no conventional CP/M disk image or sector-level disk BIOS**; BDOS file calls are translated to ProDOS operations. Programs that bypass BDOS to access disk sectors may not work.
- Disk metadata, allocation vectors, and file attributes are synthetic approximations where CP/M and ProDOS differ.
- File-name rules and some less-common BDOS/BIOS operations are not fully implemented.
- File I/O works, but it can be **slow**, especially for programs that make many small record transfers.
- Terminal compatibility depends on the installed application's expected control sequences.
- The 56KB memory configuration requires auxiliary RAM and is distinct from earlier 32KB releases.

Successful application startup is not a substitute for checking important output files. Keep backups when testing programs that make extensive or random-access changes to data.

## Background

Zapple-II started as an experiment in running Z80 code under ProDOS, with 6502-hosted assemblers and a small CP/M BDOS compatibility layer. Over time it has grown into **BP/M**, a usable ProDOS-backed CP/M environment with its own CCP, auxiliary-memory TPA, terminal drivers, and support for substantial CP/M applications.

**Source:** [github.com/bobbimanners/Zapple-II](https://github.com/bobbimanners/Zapple-II)  
**License:** [BSD 2-Clause](LICENSE)
