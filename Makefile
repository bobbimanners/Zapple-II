# Zapple-II / BP/M build
# GNU Make; preserves the ProDOS file type + load-address suffixes used by Cadius.

# Tools (override on the command line or in the environment).
MERLIN32 ?= merlin32
Z80ASM   ?= ./z80asm/z80asm
CADIUS   ?= cadius
MAME     ?= mame

# Sources and generated binaries.
CCP_SRC     ?= CCP.asm
CCP_RAW     := CCP.bin
CPM_CCP     := cpm-apps/CPM-2.2/CCP.COM
TELNET_SRC  ?= telnet.asm
TELNET_RAW  := telnet.bin
CPM_TELNET  := cpm-apps/Utils/TELNET.COM
NETCCP_SRC  ?= netccp.asm
NETCCP_RAW  := netccp.bin
CPM_NETCCP  := cpm-apps/Utils/NETCCP.COM
PING_SRC    ?= ping.asm
PING_RAW    := ping.bin
CPM_PING    := cpm-apps/Utils/PING.COM
IPCONFIG_SRC ?= ipconfig.asm
IPCONFIG_RAW := ipconfig.bin
CPM_IPCONFIG := cpm-apps/Utils/IPCONFIG.COM
NETSTAT_SRC ?= netstat.asm
NETSTAT_RAW := netstat.bin
CPM_NETSTAT := cpm-apps/Utils/NETSTAT.COM
BROWSE_SRC  ?= browse.asm
BROWSE_RAW  := browse.bin
CPM_BROWSE  := cpm-apps/Utils/BROWSE.COM
WGET_SRC    ?= wget.asm
WGET_RAW    := wget.bin
CPM_WGET    := cpm-apps/Utils/WGET.COM
FTP_SRC     ?= ftp.asm
FTP_RAW     := ftp.bin
CPM_FTP     := cpm-apps/Utils/FTP.COM
NSLOOKUP_SRC ?= nslookup.asm
NSLOOKUP_RAW := nslookup.bin
CPM_NSLOOKUP := cpm-apps/Utils/NSLOOKUP.COM
SLOPTRIS_SRC ?= sloptris.asm
SLOPTRIS_RAW := sloptris.bin
CPM_SLOPTRIS := cpm-apps/Games/SLOPTRIS.COM
SRC65       ?= softcard65.asm
SRC80       ?= softcard80.asm
RAW65       := softcard65
RAW80       := softcard80.bin
CFGFILE     := zapple2.cnf
PRODOS65    := SOFTCARD65\#ff2000
PRODOS80    := SOFTCARD80.BIN\#041000

# ProDOS image and volume name.
DISK_IMAGE  ?= zapple2.po
DISK_VOLUME ?= ZAPPLE2

# Keep the MAME setup from the original build script.
MAME_MACHINE     ?= apple2ee
MAME_SLOTS       ?= -sl1 parallel -sl1:parallel:prn ap2000 -sl2 ssc -sl4 softcard -sl7 cffa202 -aux rw3
MAME_HARD1       ?= $(DISK_IMAGE)
MAME_HARD2       ?= 
MAME_RUN_FLAGS   ?= -w
MAME_DEBUG_FLAGS ?= -debug -w
MAME_EXTRA       ?=

.DEFAULT_GOAL := all
.PHONY: all z80 6502 ccp telnet netccp netstat ping ipconfig wget browse ftp nslookup sloptris disk run debug mame clean help

# `make` assembles both CPUs and CCP, then updates the disk; it does not start MAME.
all: disk

z80: $(PRODOS80)
6502: $(PRODOS65)
ccp: $(CPM_CCP)
telnet: $(CPM_TELNET)
netccp: $(CPM_NETCCP)
netstat: $(CPM_NETSTAT)
ping: $(CPM_PING)
ipconfig: $(CPM_IPCONFIG)
wget: $(CPM_WGET)
browse: $(CPM_BROWSE)
ftp: $(CPM_FTP)
nslookup: $(CPM_NSLOOKUP)
sloptris: $(CPM_SLOPTRIS)

# Merlin32 names its output after the source basename without an extension.
# Move it to Cadius's <filename>#<type><load-address> convention.
$(PRODOS65): $(SRC65)
	@echo 'Assembling 6502: $<'
	@rm -f "$(RAW65)"
	$(MERLIN32) "$<"
	@test -f "$(RAW65)" || { echo 'Error: Merlin32 did not create $(RAW65)' >&2; exit 1; }
	mv -f "$(RAW65)" "$@"

# Udo Munk z80asm v1.1 uses -o<filename> (with no separating space).
$(PRODOS80): $(SRC80)
	@echo 'Assembling Z80: $<'
	@rm -f "$(RAW80)"
	$(Z80ASM) -o$(RAW80) "$<"
	@test -f "$(RAW80)" || { echo 'Error: Z80asm did not create $(RAW80)' >&2; exit 1; }
	mv -f "$(RAW80)" "$@"

# Udo Munk's Z80ASM writes an origin record (FF 00 01 for ORG 0100H)
# before the actual image. A CP/M .COM must start with the code at 0100H,
# so verify and strip those three bytes before putting it on drive A.
$(CPM_CCP): $(CCP_SRC)
	@echo 'Assembling CP/M CCP: $<'
	@mkdir -p "$(dir $@)"
	@rm -f "$(CCP_RAW)"
	$(Z80ASM) -o$(CCP_RAW) "$<"
	@test -f "$(CCP_RAW)" || { echo 'Error: Z80asm did not create $(CCP_RAW)' >&2; exit 1; }
	@test "$$(head -c 3 "$(CCP_RAW)" | od -An -tx1 | tr -d ' \n')" = ff0001 || { echo 'Error: unexpected CCP binary header (expected FF 00 01)' >&2; exit 1; }
	@tail -c +4 "$(CCP_RAW)" > "$@.tmp" && mv -f "$@.tmp" "$@"
	@rm -f "$(CCP_RAW)"

# TELNET lives with the CP/M utilities on drive B. As for CCP, Udo Munk's
# assembler prepends FF 00 01 for ORG 0100H; strip it to make a raw .COM.
$(CPM_TELNET): $(TELNET_SRC)
	@echo 'Assembling CP/M TELNET: $<' 
	@mkdir -p "$(dir $@)"
	@rm -f "$(TELNET_RAW)"
	$(Z80ASM) -o$(TELNET_RAW) "$<"
	@test -f "$(TELNET_RAW)" || { echo 'Error: Z80asm did not create $(TELNET_RAW)' >&2; exit 1; }
	@test "$$(head -c 3 "$(TELNET_RAW)" | od -An -tx1 | tr -d ' \n')" = ff0001 || { echo 'Error: unexpected TELNET binary header (expected FF 00 01)' >&2; exit 1; }
	@tail -c +4 "$(TELNET_RAW)" > "$@.tmp" && mv -f "$@.tmp" "$@"
	@rm -f "$(TELNET_RAW)"

# NETCCP lives on CP/M drive B alongside TELNET and the other utilities.
# Like TELNET, strip Z80ASM's FF 00 01 origin record to make a .COM.
$(CPM_NETCCP): $(NETCCP_SRC)
	@echo 'Assembling CP/M NETCCP: $<'
	@mkdir -p "$(dir $@)"
	@rm -f "$(NETCCP_RAW)"
	$(Z80ASM) -o$(NETCCP_RAW) "$<"
	@test -f "$(NETCCP_RAW)" || { echo 'Error: Z80asm did not create $(NETCCP_RAW)' >&2; exit 1; }
	@test "$$(head -c 3 "$(NETCCP_RAW)" | od -An -tx1 | tr -d ' \n')" = ff0001 || { echo 'Error: unexpected NETCCP binary header (expected FF 00 01)' >&2; exit 1; }
	@tail -c +4 "$(NETCCP_RAW)" > "$@.tmp" && mv -f "$@.tmp" "$@"
	@rm -f "$(NETCCP_RAW)"

# NETSTAT follows TELNET/NETCCP exactly: assemble to netstat.bin,
# validate Udo Munk's FF 00 01 origin record, then strip it for .COM.
$(CPM_NETSTAT): $(NETSTAT_SRC)
	@echo 'Assembling CP/M NETSTAT: $<'
	@mkdir -p "$(dir $@)"
	@rm -f "$(NETSTAT_RAW)"
	$(Z80ASM) -o$(NETSTAT_RAW) "$<"
	@test -f "$(NETSTAT_RAW)" || { echo 'Error: Z80asm did not create $(NETSTAT_RAW)' >&2; exit 1; }
	@test "$$(head -c 3 "$(NETSTAT_RAW)" | od -An -tx1 | tr -d ' \n')" = ff0001 || { echo 'Error: unexpected NETSTAT binary header (expected FF 00 01)' >&2; exit 1; }
	@tail -c +4 "$(NETSTAT_RAW)" > "$@.tmp" && test -s "$@.tmp" && mv -f "$@.tmp" "$@"
	@rm -f "$(NETSTAT_RAW)"

# Phase 6K utilities use the SAME Udo Munk origin-header convention.
$(CPM_PING): $(PING_SRC)
	@echo 'Assembling CP/M PING: $<' 
	@mkdir -p "$(dir $@)"
	@rm -f "$(PING_RAW)"
	$(Z80ASM) -o$(PING_RAW) "$<"
	@test -f "$(PING_RAW)" || { echo 'Error: z80asm did not create $(PING_RAW)' >&2; exit 1; }
	@test "$$(head -c 3 "$(PING_RAW)" | od -An -tx1 | tr -d ' \n')" = ff0001 || { echo 'Error: bad PING origin header' >&2; exit 1; }
	@tail -c +4 "$(PING_RAW)" > "$@.tmp" && test -s "$@.tmp" && mv -f "$@.tmp" "$@"
	@rm -f "$(PING_RAW)"

$(CPM_IPCONFIG): $(IPCONFIG_SRC)
	@echo 'Assembling CP/M IPCONFIG: $<' 
	@mkdir -p "$(dir $@)"
	@rm -f "$(IPCONFIG_RAW)"
	$(Z80ASM) -o$(IPCONFIG_RAW) "$<"
	@test -f "$(IPCONFIG_RAW)" || { echo 'Error: z80asm did not create $(IPCONFIG_RAW)' >&2; exit 1; }
	@test "$$(head -c 3 "$(IPCONFIG_RAW)" | od -An -tx1 | tr -d ' \n')" = ff0001 || { echo 'Error: bad IPCONFIG origin header' >&2; exit 1; }
	@tail -c +4 "$(IPCONFIG_RAW)" > "$@.tmp" && test -s "$@.tmp" && mv -f "$@.tmp" "$@"
	@rm -f "$(IPCONFIG_RAW)"

# WGET also lives with the CP/M utilities on drive B. As for CCP, Udo Munk's
# assembler prepends FF 00 01 for ORG 0100H; strip it to make a raw .COM.
$(CPM_WGET): $(WGET_SRC)
	@echo 'Assembling CP/M WGET: $<' 
	@mkdir -p "$(dir $@)"
	@rm -f "$(WGET_RAW)"
	$(Z80ASM) -o$(WGET_RAW) "$<"
	@test -f "$(WGET_RAW)" || { echo 'Error: Z80asm did not create $(WGET_RAW)' >&2; exit 1; }
	@test "$$(head -c 3 "$(WGET_RAW)" | od -An -tx1 | tr -d ' \n')" = ff0001 || { echo 'Error: unexpected WGET binary header (expected FF 00 01)' >&2; exit 1; }
	@tail -c +4 "$(WGET_RAW)" > "$@.tmp" && mv -f "$@.tmp" "$@"
	@rm -f "$(WGET_RAW)"

# BROWSE uses the same FF 00 01 stripping as WGET.
$(CPM_BROWSE): $(BROWSE_SRC)
	@echo 'Assembling CP/M BROWSE: $<' 
	@mkdir -p "$(dir $@)"
	@rm -f "$(BROWSE_RAW)"
	$(Z80ASM) -o$(BROWSE_RAW) "$<"
	@test -f "$(BROWSE_RAW)" || { echo 'Error: Z80asm did not create $(BROWSE_RAW)' >&2; exit 1; }
	@test "$$(head -c 3 "$(BROWSE_RAW)" | od -An -tx1 | tr -d ' \n')" = ff0001 || { echo 'Error: unexpected BROWSE binary header (expected FF 00 01)' >&2; exit 1; }
	@tail -c +4 "$(BROWSE_RAW)" > "$@.tmp" && mv -f "$@.tmp" "$@"
	@rm -f "$(BROWSE_RAW)"


# FTP and NSLOOKUP live beside TELNET/WGET on CP/M drive B.
# Strip Udo Munk Z80ASM's FF 00 01 origin header from each .COM.
$(CPM_FTP): $(FTP_SRC)
	@echo 'Assembling CP/M FTP: $<'
	@mkdir -p "$(dir $@)"
	@rm -f "$(FTP_RAW)"
	$(Z80ASM) -o$(FTP_RAW) "$<"
	@test -f "$(FTP_RAW)" || { echo 'Error: Z80asm did not create $(FTP_RAW)' >&2; exit 1; }
	@test "$$(head -c 3 "$(FTP_RAW)" | od -An -tx1 | tr -d ' \n')" = ff0001 || { echo 'Error: unexpected FTP binary header (expected FF 00 01)' >&2; exit 1; }
	@tail -c +4 "$(FTP_RAW)" > "$@.tmp" && mv -f "$@.tmp" "$@"
	@rm -f "$(FTP_RAW)"

$(CPM_NSLOOKUP): $(NSLOOKUP_SRC)
	@echo 'Assembling CP/M NSLOOKUP: $<'
	@mkdir -p "$(dir $@)"
	@rm -f "$(NSLOOKUP_RAW)"
	$(Z80ASM) -o$(NSLOOKUP_RAW) "$<"
	@test -f "$(NSLOOKUP_RAW)" || { echo 'Error: Z80asm did not create $(NSLOOKUP_RAW)' >&2; exit 1; }
	@test "$$(head -c 3 "$(NSLOOKUP_RAW)" | od -An -tx1 | tr -d ' \n')" = ff0001 || { echo 'Error: unexpected NSLOOKUP binary header (expected FF 00 01)' >&2; exit 1; }
	@tail -c +4 "$(NSLOOKUP_RAW)" > "$@.tmp" && mv -f "$@.tmp" "$@"
	@rm -f "$(NSLOOKUP_RAW)"

# SLOPTRIS lives on CP/M drive J (Games).
# Assemble to .bin, validate FF 00 01 header, then strip to .COM.
$(CPM_SLOPTRIS): $(SLOPTRIS_SRC)
	@echo 'Assembling CP/M SLOPTRIS: $<'
	@mkdir -p "$(dir $@)"
	@rm -f "$(SLOPTRIS_RAW)"
	$(Z80ASM) -o$(SLOPTRIS_RAW) "$<"
	@test -f "$(SLOPTRIS_RAW)" || { echo 'Error: Z80asm did not create $(SLOPTRIS_RAW)' >&2; exit 1; }
	@test "$$(head -c 3 "$(SLOPTRIS_RAW)" | od -An -tx1 | tr -d ' \n')" = ff0001 || { echo 'Error: unexpected SLOPTRIS binary header (expected FF 00 01)' >&2; exit 1; }
	@tail -c +4 "$(SLOPTRIS_RAW)" > "$@.tmp" && mv -f "$@.tmp" "$@"
	@rm -f "$(SLOPTRIS_RAW)"

# Track every file imported by addfolder, not just the tools built here.
# Tracking the directories themselves also catches newly added/deleted files.
# GNU Make re-evaluates this list each invocation.
CPM_APP_DIRS := $(addprefix cpm-apps/,CPM-2.2 Utils TP3 WS3 Supercalc AztecC dBase-II HiTechC Fortran-80 Games BBC_BASIC WS4)
CPM_FILES := $(shell find $(CPM_APP_DIRS) -type f ! -name '*.raw' ! -name '*.tmp' 2>/dev/null)
PRODOS_FILES := $(wildcard prodos.242/PRODOS* prodos.242/BASIC*)
DISK_INPUTS := $(PRODOS65) $(PRODOS80) $(CPM_CCP) $(CPM_TELNET) $(CPM_NETCCP) $(CPM_NETSTAT) $(CPM_PING) $(CPM_IPCONFIG) \
               $(CPM_WGET) $(CPM_BROWSE) $(CPM_FTP) $(CPM_NSLOOKUP) $(CPM_SLOPTRIS) $(CFGFILE) \
               $(PRODOS_FILES) $(CPM_APP_DIRS) $(CPM_FILES) Makefile

# Build a complete NEW image next to the destination. Cadius requires the .po
# suffix; only publish it if *every* import succeeds. A failed build leaves the
# prior image intact. The absolute path works from addfolder's subdirectories.
disk: $(DISK_IMAGE)

$(DISK_IMAGE): $(DISK_INPUTS)
	@echo 'Creating $@ with Cadius (atomic update)...'
	@mkdir -p "$(dir $@)"
	@set -eu; \
	  tmp="$(abspath $@).tmp.po"; \
	  trap 'rm -f "$$tmp"' EXIT HUP INT TERM; \
	  rm -f "$$tmp"; \
	  $(CADIUS) createvolume "$$tmp" "$(DISK_VOLUME)" 4096KB; \
	  $(CADIUS) addfile "$$tmp" "/$(DISK_VOLUME)" prodos.242/PRODOS*; \
	  $(CADIUS) addfile "$$tmp" "/$(DISK_VOLUME)" "$(PRODOS65)"; \
	  $(CADIUS) addfile "$$tmp" "/$(DISK_VOLUME)" prodos.242/BASIC*; \
	  $(CADIUS) addfile "$$tmp" "/$(DISK_VOLUME)" "$(PRODOS80)"; \
	  $(CADIUS) addfile "$$tmp" "/$(DISK_VOLUME)" "$(CFGFILE)"; \
	  for drive in A B C D E F G H I J K L M N O P; do \
	    $(CADIUS) createfolder "$$tmp" "/$(DISK_VOLUME)/$$drive"; \
	  done; \
	  for entry in A:CPM-2.2 B:Utils C:TP3 D:WS3 E:Supercalc F:AztecC \
	               G:dBase-II H:HiTechC I:Fortran-80 J:Games K:BBC_BASIC L:WS4; do \
	    drive=$${entry%%:*}; appdir=$${entry#*:}; \
	    (cd "cpm-apps/$$appdir" && $(CADIUS) addfolder "$$tmp" "/$(DISK_VOLUME)/$$drive" .); \
	  done; \
	  mv -f "$$tmp" "$@"

# The original script launched MAME with its debugger enabled.
# `make run` launches without -debug; `make debug` (or `make mame`) matches it.
run: disk
	$(MAME) $(MAME_RUN_FLAGS) $(MAME_MACHINE) $(MAME_SLOTS) -hard1 "$(MAME_HARD1)" -hard2 "$(MAME_HARD2)" $(MAME_EXTRA)

debug: disk
	$(MAME) $(MAME_DEBUG_FLAGS) $(MAME_MACHINE) $(MAME_SLOTS) -hard1 "$(MAME_HARD1)" -hard2 "$(MAME_HARD2)" $(MAME_EXTRA)

mame: debug

# Never delete the source files, ProDOS image, or hard-disk images.
clean:
	rm -f "$(PRODOS65)" "$(PRODOS80)" "$(RAW65)" "$(RAW80)" "$(CPM_CCP)" "$(CCP_RAW)" "$(CPM_TELNET)" "$(TELNET_RAW)" "$(CPM_NETCCP)" "$(NETCCP_RAW)" "$(CPM_NETSTAT)" "$(NETSTAT_RAW)" "$(CPM_NETSTAT).tmp" "$(CPM_PING)" "$(PING_RAW)" "$(CPM_IPCONFIG)" "$(IPCONFIG_RAW)" "$(CPM_WGET)" "$(WGET_RAW)" "$(CPM_BROWSE)" "$(BROWSE_RAW)" "$(CPM_FTP)" "$(FTP_RAW)" "$(CPM_NSLOOKUP)" "$(NSLOOKUP_RAW)" "$(CPM_SLOPTRIS)" "$(SLOPTRIS_RAW)" "$(CPM_SLOPTRIS).tmp" _FileInformation.txt

help:
	@printf '%s\n' \
	  'make          Assemble both CPUs + CCP + TELNET + NETCCP + NETSTAT + WGET + BROWSE + FTP + NSLOOKUP + PING + IPCONFIG + SLOPTRIS; update zapple2.po if changed' \
	  'make z80      Assemble softcard80.asm only' \
	  'make 6502     Assemble softcard65.asm only' \
	  'make ccp      Assemble CCP.asm to cpm-apps/CPM-2.2/CCP.COM' \
	  'make telnet   Assemble TELNET.asm to cpm-apps/Utils/TELNET.COM' \
	  'make netccp   Assemble NETCCP.asm to cpm-apps/Utils/NETCCP.COM' \
	  'make netstat  Assemble netstat.asm to cpm-apps/Utils/NETSTAT.COM' \
	  'make ping     Assemble ping.asm to cpm-apps/Utils/PING.COM' \
	  'make ipconfig Assemble ipconfig.asm to cpm-apps/Utils/IPCONFIG.COM' \
	  'make browse   Assemble browse.asm to cpm-apps/Utils/BROWSE.COM' \
	  'make wget     Assemble wget.asm to cpm-apps/Utils/WGET.COM' \
	  'make ftp      Assemble ftp.asm to cpm-apps/Utils/FTP.COM' \
	  'make nslookup Assemble NSLOOKUP.asm to cpm-apps/Utils/NSLOOKUP.COM' \
	  'make sloptris Assemble SLOPTRIS.ASM to cpm-apps/Games/SLOPTRIS.COM' \
	  'make disk     Atomically update the ProDOS image when inputs change' \
	  'make run      Update image, then launch MAME without debugger' \
	  'make debug    Update image, then launch MAME with -debug -w' \
	  'make mame     Alias for make debug (original script behavior)' \
	  'make clean    Remove generated binaries (including CCP/TELNET/NETCCP/NETSTAT/WGET/BROWSE/FTP/NSLOOKUP/PING/IPCONFIG/SLOPTRIS.COM); preserve disk images'
