# Zapple-II

**A CP/M-compatible, multitasking operating environment for the Apple IIe, running as a ProDOS application.**

Zapple-II runs real Z80 CP/M programs on a Microsoft Z80 SoftCard (or compatible card), but stores their files in **ordinary ProDOS directories** rather than CP/M disk images. The 6502 handles ProDOS and Apple II hardware; the Z80 runs the command processor, CP/M-compatible BDOS/BIOS services, and applications.

Zapple-II supports **fast tab switching and cooperative multitasking**, with up to **16 independent application sessions** depending on the installed auxiliary memory. Each tab has its own program state and text screen. It also supports an **Uthernet-II (W5100)** card for TCP/IP networking, including Telnet, FTP, HTTP, DNS, ping, DHCP and remote CP/M command sessions.

It is **not a Z80 emulator**. The applications execute on the SoftCard's physical Z80 processor. Many unmodified CP/M 2.2 programs work, including WordStar, Turbo Pascal, MBASIC, SuperCalc and dBase II.

> Zapple-II is a CP/M-compatible implementation, not Digital Research CP/M itself. In particular, it presents a CP/M file interface on top of ProDOS; it does not emulate CP/M disk hardware.

## Contents

- [Hardware requirements](#hardware-requirements)
- [Download and run](#download-and-run)
- [Configuration: ZAPPLE2.CNF](#configuration-zapple2cnf)
- [Features](#features)
- [Built-in commands](#built-in-commands)
- [Tab management and process lifecycle](#tab-management-and-process-lifecycle)
- [Multitasking](#multitasking)
- [Networking](#networking)
- [NETCCP: Telnet server](#netccp-telnet-server)
- [CP/M application compatibility](#cpm-application-compatibility)
- [Theory of operation](#theory-of-operation)
- [Building from source](#building-from-source)
- [Limitations and notes](#limitations-and-notes)

## Hardware requirements

**Required:**

- **Apple IIe** with at least **128 KiB RAM** and auxiliary memory/80-column capability (or a suitably configured emulator).
- **Microsoft Z80 SoftCard** or compatible Z80 card. The standard configuration uses **slot 4**.
- **ProDOS 8** and a readable ProDOS volume containing the Zapple-II loader, Z80 image and CP/M files. `BASIC.SYSTEM` is used for the launch instructions below.

**Recommended or optional:**

- **Applied Engineering RamWorks** or compatible bank-switched auxiliary RAM to enable **multiple independent tabs**. Zapple-II detects available banks on startup and adjusts its tab count. Ordinary 128 KiB auxiliary RAM supports the basic single-session environment; more physical banks provide additional sessions, up to 16.
- A hard disk, CompactFlash or other ProDOS mass-storage solution. The bundled image is intended for use as a ProDOS hard-disk volume.
- **Uthernet-II**, with a **W5100** Ethernet controller, in **slot 5** for network features. Networking is optional; the CP/M environment also runs in MAME configurations without a W5100.
- **VEDRIVE** if you want ProDOS network volumes. VEDRIVE and Zapple-II can share the W5100 when the sockets and network configuration are managed carefully; see [Coexisting with VEDRIVE](#coexisting-with-vedrive).

The tab maximum is **not** equivalent to the number of RamWorks banks: some banks are reserved for saved screens and other bookkeeping. The startup banner reports the detected bank and tab counts.

## Download and run

Source code and the current ProDOS disk image are in this repository:

**[github.com/bobbimanners/Zapple-II](https://github.com/bobbimanners/Zapple-II)**

1. Obtain the repository or download its **`zapple2.po`** ProDOS disk image. The disk image contains the loader, Z80 system image and a collection of CP/M programs.
2. Attach or copy the image to a ProDOS-compatible storage device, or use it as a hard-disk image in MAME. Boot **ProDOS 8**.
3. Set the ProDOS **current prefix** to the directory containing `SOFTCARD65`, `SOFTCARD80.BIN` and, if used, `ZAPPLE2.CNF`.
4. From the `BASIC.SYSTEM` prompt, start Zapple-II:

   ```text
   -SOFTCARD65
   ```

5. Zapple-II loads the Z80 environment, reports its RamWorks configuration and starts an independent command processor in tab 0:

   ```text
   A>DIR
   A>MBASIC
   A>WS
   ```

   The exact startup banner and available programs depend on the image version.

To return to ProDOS, type `BYE` and confirm the prompt. It is best to close files and exit running applications before leaving.

### Drives and files

By default, CP/M drives `A:` through `P:` correspond to same-named subdirectories under the current ProDOS prefix:

| CP/M drive | Default ProDOS directory | Example |
| --- | --- | --- |
| `A:` | `A/` | `A/CCP.COM` |
| `B:` | `B/` | `B/FTP.COM` |
| `C:` | `C/` | `C/MBASIC.COM` |
| `P:` | `P/` | `P/NOTES.TXT` |

`A:` is the **fixed system/recovery drive**, from which Zapple-II reloads `CCP.COM`. You may remap **any of `B:` through `P:`** to absolute ProDOS directories using `ZAPPLE2.CNF`; the current implementation supports **up to five simultaneous remappings**. Unmapped letters keep their default directories.

Files are ordinary ProDOS files accessed through CP/M-style 8.3 names, FCBs and 128-byte records. Put any program's companion overlays and data files in accessible directories, just as you would on a CP/M system.

## Configuration: ZAPPLE2.CNF

`ZAPPLE2.CNF` is an optional, plain-text configuration file read **at startup**, relative to the **current ProDOS prefix**. The loader reads **up to 1,024 bytes**. If no DNS is supplied, the current kernel defaults to `1.1.1.1`. Use uppercase section/key names, no spaces around `=`, and keep the file short. Blank lines and lines beginning with `;` or `#` are ignored.

Example:

```ini
[NETWORK]
ENABLED=1
SLOT=5
RESET=0
IP=192.168.10.10
NM=255.255.255.0
GW=192.168.10.1
DNS=192.168.10.1
MAC=02:5A:50:50:4C:45

[SYSTEM]
SOFTCARD=4

[DRIVES]
; A: is fixed; at most five drives B:..P: may be mapped.
B=/ZAPPLE2/UTILS
C=/ZAPPLE2/WORK
;O=/NETVOL/CPM
;P=/NETVOL/SHARED
```

### `[NETWORK]`

| Key | Meaning |
| --- | --- |
| `ENABLED=0/1` | Enable processing of W5100 network startup settings. |
| `SLOT=5` | Uthernet-II slot. **Currently fixed at slot 5** in the networking implementation. |
| `RESET=0/1` | Whether the loader initializes/resets the W5100 at boot. **`0` leaves the chip and existing sockets untouched**; **`1` resets it** and programs the static configuration. |
| `IP=` | Static IPv4 address for the Apple II. |
| `NM=` | IPv4 subnet mask. |
| `GW=` | Default gateway. |
| `DNS=` | Default DNS resolver used by Zapple-II network clients. |
| `MAC=` | Ethernet MAC address, e.g. `02:5A:50:50:4C:45`. Make it unique on your LAN. |

**Important:** `RESET=1` resets the W5100 and terminates **all** its existing sockets, including those used by VEDRIVE. Use `RESET=0` when another ProDOS network component has already configured the card. With `RESET=0`, the file can still supply Zapple-II's DNS setting and drive mappings, but the boot loader does **not** rewrite the W5100's IP configuration.

### `[SYSTEM]`

| Key | Meaning |
| --- | --- |
| `SOFTCARD=4` | Physical slot of the Z80 SoftCard. Slot 4 is the normal configuration; do not assign the SoftCard to slot 5 when the W5100 uses it. |

`SOFTCARD` and the network `SLOT` are **different** settings. The latter refers to Uthernet-II.

### `[DRIVES]`

Map a CP/M drive to an existing **absolute ProDOS directory**:

```ini
[DRIVES]
B=/ZAPPLE2/UTILS
D=/ZAPPLE2/WORDSTAR
O=/NETVOL/CPM
P=/NETVOL/SHARED
```

Rules:

- `A:` cannot be remapped: it must remain available for `A:CCP.COM`.
- Any of `B:`–`P:` may be remapped, with **at most five active mappings** in the current build.
- Use an absolute ProDOS pathname beginning with `/`, at most **42 characters**, with **no trailing slash**.
- Directories/volumes must exist and be accessible to ProDOS; mappings do **not** mount volumes themselves.
- Mappings are **global across tabs**, take effect on cold startup, and do not affect unmapped drives.
- A network-backed mapping works only if a separate ProDOS driver such as VEDRIVE has already made the corresponding volume available.

For example, if `O=/NETVOL/CPM`, programs accessing `O:FILE.TXT` use a regular ProDOS pathname on `/NETVOL`; Zapple-II doesn't need a special network filesystem or CP/M disk driver.

## Features

- **CP/M 2.2-compatible environment** with its own CCP and BDOS/BIOS interfaces.
- **Real Z80 execution** on the Microsoft SoftCard; no Z80 instruction emulation.
- **55.5 KiB AUX transient program area (TPA)** for CP/M `.COM` applications, from Z80 `$0100` through `$DEFF`.
- **Up to 16 tabs**, subject to installed auxiliary/RamWorks memory, each preserving its program, registers, stack, command-processor state and display.
- **Near-instant tab switching** using Open-Apple shortcuts or `TAB` commands.
- **Cooperative multitasking** at BDOS/BIOS service boundaries, including console-input-aware scheduling and fairer interactive scheduling when remote users are connected.
- **Per-tab command history** (10 entries), with arrow-key and WordStar-style line editing.
- **Per-tab CP/M drive and user area**, with ordinary CP/M drive letters `A:`–`P:` and users `0`–`15`.
- **ProDOS-backed files**, including sequential and random-record access, with a small pathname-keyed ProDOS file-handle cache.
- **Remappable B:–P:** (any five at once), including directories on VEDRIVE volumes.
- **Per-drive ProDOS device caching** for `STAT` free-space queries, without noisy `ON_LINE` enumeration of floppy devices. Free space describes the underlying ProDOS volume, not a directory quota.
- **Direct 80-column display** with Soroc, VT100, H19/H89 and VT52 terminal support.
- **Network applications** built around the W5100, including a kernel-managed resident Telnet server.
- **One-shot, manually invoked DHCP**; no boot-time DHCP daemon or background lease-renewal task.
- **Task cleanup:** `TAB KILL` discards a non-current tab's execution context and reclaims its resources without rebooting the whole machine.

## Built-in commands

The **CCP (Console Command Processor)** is loaded as `A:CCP.COM`. Commands are case-insensitive. The commands below are built into the command processor or provided through its resident kernel services; utilities such as `PIP`, `STAT` and network `.COM` programs are **external**, not CCP built-ins.

| Command | Description | Example |
| --- | --- | --- |
| `HELP` | List available commands and editing keys. | `HELP` |
| `DIR [filespec]` | List files; supports `*`, `?` and drive-qualified patterns. | `DIR B:*.COM` |
| `TYPE filespec` | Display a text file. | `TYPE NOTES.TXT` |
| `ERA filespec` | Delete file(s); wildcard deletion asks for confirmation. | `ERA *.BAK` |
| `REN new=old` | Rename a file (**destination first**). | `REN NEW.TXT=OLD.TXT` |
| `USER [0..15]` | Show or set the current CP/M user area. | `USER 3` |
| `A:` … `P:` | Select the current CP/M drive. | `D:` |
| `SAVE n filespec` | Save `n` pages of the previous transient's AUX TPA; each page is 256 bytes. Maximum `222` pages. | `SAVE 4 TEST.COM` |
| `CLS` | Clear/home the terminal. | `CLS` |
| `TERM mode` | Select terminal mode: `SOROC`, `VT100`, `H19`, `H89` or `VT52`. | `TERM VT100` |
| `BANKS` | Show detected auxiliary banks and available tabs. | `BANKS` |
| `CACHE` | Show file-handle cache statistics. | `CACHE` |
| `CACHE RESET` | Clear cache statistics. | `CACHE RESET` |
| `HIST` | Show recent commands for the current tab. | `HIST` |
| `TAB` / `TAB LIST` | List visited tabs, active programs and task states. | `TAB LIST` |
| `TAB HELP` | Short tab-command reference. | `TAB HELP` |
| `TAB n` / `TAB SWITCH n` | Switch to tab `n` (`0`–`9`, `A`–`F`). | `TAB 2` |
| `TAB n SUSPEND` | Stop scheduling a background tab. | `TAB 2 SUSPEND` |
| `TAB n RESUME` | Make a suspended tab runnable again. | `TAB 2 RESUME` |
| `TAB n EXCLUSIVE` | Suspend other tabs and run/switch to tab `n`. | `TAB 2 EXCLUSIVE` |
| `TAB n KILL` | Destroy an **inactive** tab's execution context and release its resources. | `TAB 2 KILL` |
| `XSUB` | Allow CP/M SUBMIT jobs to control transient programs. | `XSUB` |
| `BYE` | Exit Zapple-II and return to ProDOS after confirmation. | `BYE` |
| `program [args]` | Find and run a CP/M `.COM` file; `.COM` is optional. | `WS LETTER.TXT` |

For `TAB`, the action-first form also works, e.g. `TAB KILL 2` or `TAB SUSPEND 2`.

### Command-line editing

The CCP's editor supports the Apple II arrow keys and familiar WordStar controls:

| Key | Action |
| --- | --- |
| Left/right arrows or `^S` / `^D` | Move within the line. |
| Up/down arrows or `^E` / `^X` | Previous/next history entry. |
| `^G` | Delete character. |
| `^Q^S` / `^Q^D` | Beginning/end of line. |
| `^Y` | Clear the line. |
| `^C` | Cancel the current command line. |

History is maintained separately for each tab; the most recent **10 commands** are retained for recall.

## Tab management and process lifecycle

A **tab** is an independent CP/M session: its own AUX memory bank, running program or CCP, screen, drive/user selection and command history. Tab numbers are hexadecimal (`0`–`F`), although the actual available range is determined at boot.

### Switching tabs

- **Open-Apple + `0`–`9` / `A`–`F`** selects a specific tab, if available.
- **Open-Apple + left/right arrow** cycles through the available tabs.
- From the CCP, `TAB n` or `TAB SWITCH n` selects a tab.

Switching away **does not terminate** an application. Its execution state and screen are saved, and the program continues when scheduled or resumed.

### Starting and ending a program

1. A tab is first opened with an independent `A:CCP.COM` command processor.
2. Launching a `.COM` program replaces the command processor as that tab's running transient.
3. When the program terminates normally, the supervisor starts a fresh CCP in the **same tab**.
4. A suspended task retains its existing execution context until resumed or killed.
5. `TAB n KILL`, issued **from another tab**, destroys the target's saved context, releases its owned networking resources and marks the tab unused. Selecting that tab later creates a fresh CCP session.

`TAB LIST` identifies visited tabs and reports their programs and state. It is useful for finding a misbehaving task before killing it.

> `TAB KILL` is deliberately different from sending Ctrl-C or asking an application to exit: it discards the saved task instead of depending on that program's cleanup code. It cannot undo external writes or repair corruption of shared kernel memory. Nor can a strictly non-yielding foreground program be preempted without reaching a point where the system can take control.

### Suspended and exclusive execution

`TAB n SUSPEND` keeps a background tab intact but removes it from normal scheduling. `TAB n RESUME` returns it to the runnable set. `TAB n EXCLUSIVE` suspends all other tabs and gives the selected tab exclusive execution until you resume others.

You cannot kill or suspend the **currently active tab** from within itself; switch to another tab first.

## Multitasking

Zapple-II uses **cooperative, non-preemptive multitasking**. There is no timer interrupt, MMU or hardware task scheduler. Instead, the resident supervisor takes opportunities to switch between saved Z80 contexts when a program enters a supported **BDOS/BIOS service** or waits for console input.

In broad terms:

1. Each tab's transient executes in its own RamWorks auxiliary memory bank.
2. A call into the operating system crosses a small AUX/main-memory gateway.
3. The supervisor saves the caller's registers, stack and relevant state at safe boundaries.
4. Another runnable tab can execute; background tasks receive shorter service-call quanta than the physical foreground session.
5. When a Telnet client is actively connected to NETCCP, the scheduler gives connected remote sessions and the physical foreground comparable interactive quanta (32 service calls), while ordinary background work retains its lower share.
6. A task waiting for a character can be parked, allowing other tasks to run rather than blocking the entire system.

This is enough for multiple ordinary CP/M programs to make progress without changes to the applications themselves. It also makes task cleanup relatively robust, because switching normally occurs at well-defined OS entry points.

**Limits:** CPU-bound code that never calls BDOS/BIOS may monopolize the processor; direct hardware access, self-modifying code outside the transient's permitted memory, or corruption of shared OS memory can defeat isolation. There is **no memory protection**.

## Networking

Networking requires a **W5100-based Uthernet-II** in slot 5. Zapple-II uses the W5100's hardware TCP/UDP sockets, shared between its applications and resident network services. Configuration can be supplied at boot through `ZAPPLE2.CNF` and changed interactively with supported utilities.

### Network client programs

These are separate CP/M `.COM` utilities (typically available on drive `B:` in the bundled image), not built-in CCP commands:

| Program | Purpose / notes |
| --- | --- |
| `IPCONFIG` | Show or set IP address, mask, gateway and DNS in the running system. Changes are not written back to `ZAPPLE2.CNF`. |
| `PING a.b.c.d` | Send four ICMP echo requests to a **numeric IPv4** address. |
| `NSLOOKUP` | Query DNS using the configured resolver. |
| `TELNET` | Outbound Telnet client, with hostname resolution and command-line server/port support. |
| `FTP` | Interactive FTP client with `get`, `put`, `dir`, `cd`, `bin`/`ascii` and related commands. |
| `WGET` | HTTP downloader; prompts for a **case-sensitive URL** and destination filename. |
| `BROWSE` | Small, text-mode HTTP browser with a pager, links and basic redirect handling. |
| `NETSTAT` | Display W5100 socket state, ownership and resident listener information. |
| `DHCP` | One-shot DHCPv4 client. Run manually to discover an address, gateway, subnet mask and DNS. |
| `NETCCP [port]` | Start a kernel-resident Telnet listener; see the next section. |

**HTTP clients are plain HTTP, not HTTPS browsers**; they have the constraints of lightweight retro-computing tools and limited RAM. Likewise, FTP and Telnet traffic is unencrypted. Use services you trust.

### DHCP

`DHCP.COM` implements the standard **DISCOVER → OFFER → REQUEST → ACK** exchange, then programs the W5100's network address and updates Zapple-II's shared DNS setting.

```text
B>DHCP
```

It is intentionally **manual**: there is no automatic boot DHCP, background renewal service or persistent change to `ZAPPLE2.CNF`. The client checks that **no W5100 socket is in use** before reconfiguring the interface, and refuses to proceed if VEDRIVE or another application already owns a socket. Run it before establishing other network sessions. A DHCP lease is temporary; long-running systems would eventually need another renewal/acquisition.

### Coexisting with VEDRIVE

**VEDRIVE is a ProDOS network block-device driver, not a Zapple-II CP/M network client.** It can make a remote ProDOS volume appear to the Apple II as an ordinary local ProDOS volume. Zapple-II can then use that volume through its normal ProDOS filesystem interface.

For coexistence:

1. Let VEDRIVE establish its network connection and ProDOS volume as usual.
2. Set `RESET=0` in `ZAPPLE2.CNF` so the Zapple-II loader **does not reset** the W5100 or overwrite VEDRIVE's settings.
3. Ensure Zapple-II network clients use sockets **not already occupied** by VEDRIVE. The kernel manages socket allocation; the usual VEDRIVE setup uses W5100 socket 3.
4. Optionally map a CP/M drive onto the VEDRIVE volume:

   ```ini
   [DRIVES]
   O=/NETVOL/CPM
   ```

5. Use CP/M commands such as `O:` and `DIR`. File I/O is translated into normal ProDOS operations, so applications need no special networking support.

**Do not** use `RESET=1` or run DHCP while VEDRIVE has active sockets. Each W5100 has only **four hardware sockets**; sharing must be deliberate. Also avoid concurrently modifying the same files from multiple applications.

### Free space on remapped drives

CP/M programs such as `STAT` obtain synthetic allocation-vector/DPB information based on the underlying ProDOS volume. Zapple-II caches the relevant **ProDOS device per CP/M drive on first use** and reads that volume's bitmap for space calculations. It does **not** perform an `ON_LINE` scan across every physical drive. The device identity is cached; **free-space figures themselves are not cached**. Figures remain approximate because CP/M allocation units and ProDOS allocation units differ.

## NETCCP: Telnet server

`NETCCP.COM` turns an available tab into a **remotely accessible CP/M command session**. The listener is managed by the **resident kernel**, not by a `.COM` program sitting in a blocking receive loop. That distinction allows remote clients to disconnect and reconnect while the tab remains usable and the listener survives.

From a dedicated tab:

```text
B>NETCCP
```

The default TCP port is **2323**. You can instead choose a port explicitly:

```text
B>NETCCP 2324
```

Connect from another machine on the LAN with an ordinary Telnet client:

```sh
telnet <apple-ip> 2323
```

The connection presents a CP/M CCP prompt. From there you can run commands and suitable terminal programs, including full-screen software configured for the negotiated terminal mode. In particular, VT100-capable applications can be used over the network.

**Session lifecycle:**

- `NETCCP` requests a free socket and starts a persistent listener assigned to its tab.
- On connection, the kernel links that socket to the tab's console input/output and runs a fresh `A:CCP.COM` as necessary.
- On remote disconnect, the kernel re-arms the listener for another connection; it does **not** repeatedly launch `NETCCP.COM`.
- **`TAB n KILL` from another tab stops that tab's listener**, closes its network resources and discards its session.
- Multiple listeners may coexist, normally on different ports, subject to available tabs and W5100 sockets. VEDRIVE and outgoing clients reduce the remaining socket capacity.

**Security warning:** NETCCP has **no login, password or access controls**. A client that can reach the listening TCP port can use the CP/M shell and its accessible files. Keep it on a **trusted, isolated LAN**; do not port-forward it or expose it to the public internet. Telnet also carries all traffic in clear text.

## CP/M application compatibility

Zapple-II targets CP/M 2.2 applications that use the documented BDOS/BIOS interfaces, with a large AUX transient program area and terminal compatibility modes. Tested or exercised programs include:

| Application | Notes |
| --- | --- |
| **WordStar 3.3 / 4** | Full-screen word processing; configuration and terminal settings matter. |
| **Microsoft MBASIC** | BASIC interpreter. |
| **BBC BASIC** | CP/M version supported by the AUX environment. |
| **Turbo Pascal 3** | Editor, compiler and `.COM` output. |
| **SuperCalc** | Spreadsheet. |
| **dBase II** | Database operations; some workflows remain less thoroughly exercised than basic file access. |
| **Microsoft FORTRAN-80** | Compiler/runtime use. |
| **PIP, STAT, ASM, DDT, ZSID** | Standard CP/M utilities and developer tools. |
| **NSWEEP** | Interactive file manager. |
| **SLOPTRIS** | Small CP/M Tetris, written for Zapple-II's terminal support. |

Compatibility is intentionally broad but not universal. Applications that require particular disk-controller commands, CP/M disk-sector layouts, undocumented BIOS behaviour or direct hardware access may not work. Some older software also assumes a 40-column console or a particular Soroc/Videx/VT100 terminal configuration.

For important data, retain backups and verify resulting files, especially after testing unfamiliar applications.

## Theory of operation

### The 6502/Z80 dance

Zapple-II consists of two closely coupled parts:

- **`SOFTCARD65`** — a 6502 ProDOS **SYS** application and resident hardware backend. It opens `ZAPPLE2.CNF`, loads `SOFTCARD80.BIN`, initializes the console and carries out ProDOS MLI operations for the Z80 environment.
- **`SOFTCARD80.BIN`** — the Z80 resident kernel: CP/M-compatible BDOS/BIOS services, filesystem translation, the AUX memory gateway, tab/process supervisor, scheduler and network services. The interactive CCP lives separately as **`A:CCP.COM`**.

The Microsoft SoftCard makes the Apple II's memory visible to the Z80 through a hardware address translation and hands the bus between the two processors. Zapple-II uses that mechanism to execute ordinary Z80 code, briefly switch to the 6502 to perform an Apple II/ProDOS service, then return to the Z80.

A typical file operation looks like this:

```text
CP/M application (.COM)          Z80, selected AUX/RamWorks bank
           |
           |  CALL 0005h  (BDOS function, FCB, DMA)
           v
AUX gateway / CP/M BDOS          Z80, resident MAIN memory
           |
           |  marshal AUX pointers, FCBs and 128-byte records
           v
Z80-to-6502 handoff             SoftCard hardware / shared command area
           |
           v
6502 ProDOS backend             ProDOS 8 MLI (OPEN, READ, WRITE, etc.)
           |
           v
Ordinary ProDOS file            local or VEDRIVE-backed volume
           |
           +---- results return through the gateway to the Z80 app
```

This design avoids maintaining a CP/M allocation-based disk filesystem or sector-level disk drivers. The price is translation overhead: CP/M 128-byte records, auxiliary-memory copies, ProDOS calls and processor handoffs make some I/O slower than on a native ProDOS program.

### Memory maps

These are **conceptual runtime maps**, not a complete symbol-by-symbol linker map. The resident implementation has many small fixed regions and hardware windows; consult `softcard80.asm` and `softcard65.asm` for exact addresses before changing code.

**Z80-visible CP/M and transient layout (AUX56):**

```text
Z80 address
$FFFF +-------------------------------+
      | AUX language-card / gateway  |
      | upper memory and stubs       |
$DF00 +-------------------------------+
      | Transient program area (TPA) |
      | selected RamWorks AUX bank   |
      | application code/data/stack  |
$0100 +-------------------------------+
      | CP/M page zero               |
      | BDOS jump at $0005           |
      | FCBs at $005C / $006C        |
      | default DMA at $0080         |
$0000 +-------------------------------+
```

The available application space is **`$0100–$DEFF` inclusive (55.5 KiB)**. Each runnable tab owns a corresponding AUX memory bank; the operating system's main resident implementation is outside the tab's switchable transient memory.

**Principal Z80 resident MAIN-memory areas (selected):**

| Z80 address | Role |
| --- | --- |
| `$0000–$00FF` | CP/M-compatible page zero and OS entry vectors. |
| `$0100–$01DE` | Startup code plus five 44-byte tagged drive-mapping records (mount table starts at `$0103`). |
| `$01DF–$01E2` | Boot-supplied DNS resolver bytes. |
| `$0200` onward | RamWorks bank selection/detection and tab-control routines. |
| `$0400` onward | Tab management, cooperative scheduling and saved task state. |
| `$4000` onward | Resident command/service code, network and filesystem bridges, task support. |
| `$7000` onward | AUX BDOS translation and staging machinery. |
| `$8100` onward | Main CP/M BDOS implementation. |
| `$A200` area | ProDOS file-handle cache. |
| `$DE00/$DF00` | Language-card BDOS/BIOS gateway entry region used by AUX transients. |

Some of these addresses refer to **resident MAIN bank** code while the transient sees **AUX** storage at the same logical Z80 address. That distinction is central to the design.

**6502 / Apple II side (selected):**

| 6502 address | Role |
| --- | --- |
| `$0006–$0009`, `$00EB…` | Shared command/register/handoff fields. |
| `$0800–$0BFF` | ProDOS OPEN I/O buffer during loading/operation. |
| `$0C00–$0CDB` | Temporary five-entry mount staging during startup. |
| `$1000` area | Initial load destination of the Z80 binary (SoftCard address mapping applies). |
| `$2000` | `SOFTCARD65` SYS loader's assembly origin. |
| `$B800` onward | Relocated 6502 console and service backend. |
| `$BF00` | ProDOS MLI entry point. |
| `$C400` | Default SoftCard slot-4 I/O interface. |
| Slot 5 I/O | Uthernet-II W5100 access. |

The startup parser reads `ZAPPLE2.CNF` into **temporary 6502 memory** before the Z80 image is loaded, stages drive mapping and DNS information, and copies that information into fixed Z80 MAIN locations as part of initialization.

### Tab storage and display

A tab contains more than a program counter: its execution context, stack, AUX memory bank, drive/user state, console state and screen must survive a switch. Zapple-II uses available RamWorks banks both for **live transient memory** and for **screen snapshots**. Screen-snapshot banks are reserved separately from program banks, so the maximum number of simultaneously available tabs is lower than the physical bank count.

The Apple IIe's physical 80-column screen belongs to whichever tab is visible. On a switch, the system saves/restores the relevant text-page and terminal state, preserving full-screen application displays. Network consoles are independently redirected through the resident network service rather than taking over the physical display.

### Why task killing usually works

Because each application's transient state resides primarily in its own AUX bank, killing an inactive tab can **drop that bank's live context** and release associated kernel resources without executing any instruction from the failed application. The other tabs and resident operating system can often continue unharmed. This is robust *by design*, but it is not protected-mode isolation: shared-memory corruption, unfinished external writes and programs that never yield remain real limitations.

## Building from source

The repository's **GNU Makefile** builds the two CPUs' binaries, `CCP.COM`, network tools and a ProDOS disk image. On a Linux development machine you will typically need:

- **Merlin32** for `softcard65.asm` (6502 code).
- **Udo Munk's `z80asm` 1.1** for `softcard80.asm`, `CCP.asm` and CP/M applications built from source.
- **Cadius** to construct/populate the ProDOS disk image.
- **MAME**, optionally, for emulated testing.

Common targets:

```sh
make 6502            # build SOFTCARD65
make z80             # build SOFTCARD80.BIN
make ccp             # build A:CCP.COM
make disk            # rebuild the ProDOS .po image
make run             # launch MAME without debugger
make debug           # launch MAME with debugger
make help            # show build targets
```

`make` normally builds the complete disk image. The Makefile can also rebuild individual network tools (`make telnet`, `make netccp`, `make ping`, etc.). `DHCP.COM` can be built and added separately if its source/target is present in your checkout.

**Build notes:** Udo Munk's assembler treats only the first **eight characters of a symbol** as significant; take care with long labels. CP/M `.COM` binaries require the normal 0100h-origin format used by the Makefile. Preserve ProDOS file types when importing `SOFTCARD65` (SYS) and `SOFTCARD80.BIN` (BIN). After changing the loader or kernel, ensure you actually boot the newly rebuilt disk image.

## Limitations and notes

- CP/M compatibility is at the **BDOS/BIOS/application** level, not a cycle-accurate recreation of every CP/M machine or disk controller.
- The filesystem is **ProDOS**, with CP/M-compatible metadata and allocation information synthesized as needed. `STAT` reports underlying volume free space approximately, not the capacity of a mapped subdirectory.
- Applications can corrupt their **own** memory and potentially shared state; tabs do not have hardware-enforced isolation.
- Scheduling is cooperative. Infinite CPU loops that never yield cannot be reliably interrupted.
- Network services share only four W5100 sockets. VEDRIVE may occupy one. Boot-time W5100 resets and DHCP reconfiguration must be avoided while other users of the chip are active.
- Telnet/FTP/HTTP are **unencrypted**; NETCCP has **no authentication**. Keep remote shell access on a trusted network.
- Drive mappings are limited to **five active entries** in the current build, and A: is intentionally fixed.
- Some CP/M software requires a particular terminal configuration or depends on undocumented hardware and disk behaviour. Compatibility is necessarily application-specific.

## License

Zapple-II is distributed under the repository's [BSD 2-Clause license](LICENSE).
