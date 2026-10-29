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
WGET_SRC    ?= wget.asm
WGET_RAW    := wget.bin
CPM_WGET    := cpm-apps/Utils/WGET.COM
FTP_SRC     ?= ftp.asm
FTP_RAW     := ftp.bin
CPM_FTP     := cpm-apps/Utils/FTP.COM
NSLOOKUP_SRC ?= nslookup.asm
NSLOOKUP_RAW := nslookup.bin
CPM_NSLOOKUP := cpm-apps/Utils/NSLOOKUP.COM
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
.PHONY: all z80 6502 ccp telnet wget ftp nslookup disk run debug mame clean help

# `make` assembles both CPUs and CCP, then updates the disk; it does not start MAME.
all: disk

z80: $(PRODOS80)
6502: $(PRODOS65)
ccp: $(CPM_CCP)
telnet: $(CPM_TELNET)
wget: $(CPM_WGET)
ftp: $(CPM_FTP)
nslookup: $(CPM_NSLOOKUP)

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

# Update a temporary COPY of the ProDOS image, then publish it only after
# both Cadius operations succeed. Retain the .po extension for Cadius.
# Tracking the image itself as the target makes `make disk` incremental.
disk: $(DISK_IMAGE)

$(DISK_IMAGE): $(PRODOS65) $(PRODOS80) $(CPM_CCP) $(CPM_TELNET) $(CPM_WGET) $(CPM_FTP) $(CPM_NSLOOKUP)
	echo 'Creating $@ with Cadius...'
	$(CADIUS) createvolume "$@" "$(DISK_VOLUME)" 4096KB
	$(CADIUS) addfile "$@" "/$(DISK_VOLUME)" prodos.242/PRODOS*
	$(CADIUS) addfile "$@" "/$(DISK_VOLUME)" "$(PRODOS65)"
	$(CADIUS) addfile "$@" "/$(DISK_VOLUME)" prodos.242/BASIC*
	$(CADIUS) addfile "$@" "/$(DISK_VOLUME)" "$(PRODOS80)"
	$(CADIUS) addfile "$@" "/$(DISK_VOLUME)" "$(CFGFILE)"
	$(CADIUS) createfolder "$@" "/$(DISK_VOLUME)/A"
	$(CADIUS) createfolder "$@" "/$(DISK_VOLUME)/B"
	$(CADIUS) createfolder "$@" "/$(DISK_VOLUME)/C"
	$(CADIUS) createfolder "$@" "/$(DISK_VOLUME)/D"
	$(CADIUS) createfolder "$@" "/$(DISK_VOLUME)/E"
	$(CADIUS) createfolder "$@" "/$(DISK_VOLUME)/F"
	$(CADIUS) createfolder "$@" "/$(DISK_VOLUME)/G"
	$(CADIUS) createfolder "$@" "/$(DISK_VOLUME)/H"
	$(CADIUS) createfolder "$@" "/$(DISK_VOLUME)/I"
	$(CADIUS) createfolder "$@" "/$(DISK_VOLUME)/J"
	$(CADIUS) createfolder "$@" "/$(DISK_VOLUME)/K"
	$(CADIUS) createfolder "$@" "/$(DISK_VOLUME)/L"
	$(CADIUS) createfolder "$@" "/$(DISK_VOLUME)/M"
	$(CADIUS) createfolder "$@" "/$(DISK_VOLUME)/N"
	$(CADIUS) createfolder "$@" "/$(DISK_VOLUME)/O"
	$(CADIUS) createfolder "$@" "/$(DISK_VOLUME)/P"
	cd cpm-apps/CPM-2.2 && $(CADIUS) addfolder "../../$@" "/$(DISK_VOLUME)/A" .
	cd cpm-apps/Utils && $(CADIUS) addfolder "../../$@" "/$(DISK_VOLUME)/B" .
	cd cpm-apps/TP3 && $(CADIUS) addfolder "../../$@" "/$(DISK_VOLUME)/C" .
	cd cpm-apps/WS3 && $(CADIUS) addfolder "../../$@" "/$(DISK_VOLUME)/D" .
	cd cpm-apps/Supercalc && $(CADIUS) addfolder "../../$@" "/$(DISK_VOLUME)/E" .
	cd cpm-apps/AztecC && $(CADIUS) addfolder "../../$@" "/$(DISK_VOLUME)/F" .
	cd cpm-apps/dBase-II && $(CADIUS) addfolder "../../$@" "/$(DISK_VOLUME)/G" .
	cd cpm-apps/HiTechC && $(CADIUS) addfolder "../../$@" "/$(DISK_VOLUME)/H" .
	cd cpm-apps/Fortran-80 && $(CADIUS) addfolder "../../$@" "/$(DISK_VOLUME)/I" .
	cd cpm-apps/Games && $(CADIUS) addfolder "../../$@" "/$(DISK_VOLUME)/J" .
	cd cpm-apps/BBC_BASIC && $(CADIUS) addfolder "../../$@" "/$(DISK_VOLUME)/K" .
	cd cpm-apps/WS4 && $(CADIUS) addfolder "../../$@" "/$(DISK_VOLUME)/L" .

# The original script launched MAME with its debugger enabled.
# `make run` launches without -debug; `make debug` (or `make mame`) matches it.
run: disk
	$(MAME) $(MAME_RUN_FLAGS) $(MAME_MACHINE) $(MAME_SLOTS) -hard1 "$(MAME_HARD1)" -hard2 "$(MAME_HARD2)" $(MAME_EXTRA)

debug: disk
	$(MAME) $(MAME_DEBUG_FLAGS) $(MAME_MACHINE) $(MAME_SLOTS) -hard1 "$(MAME_HARD1)" -hard2 "$(MAME_HARD2)" $(MAME_EXTRA)

mame: debug

# Never delete the source files, ProDOS image, or hard-disk images.
clean:
	rm -f "$(PRODOS65)" "$(PRODOS80)" "$(RAW65)" "$(RAW80)" "$(CPM_CCP)" "$(CCP_RAW)" "$(CPM_TELNET)" "$(TELNET_RAW)" "$(CPM_WGET)" "$(WGET_RAW)" "$(CPM_FTP)" "$(FTP_RAW)" "$(CPM_NSLOOKUP)" "$(NSLOOKUP_RAW)" _FileInformation.txt

help:
	@printf '%s\n' \
	  'make          Assemble both CPUs + CCP + TELNET + WGET + FTP + NSLOOKUP; update zapple2.po if changed' \
	  'make z80      Assemble softcard80.asm only' \
	  'make 6502     Assemble softcard65.asm only' \
	  'make ccp      Assemble CCP.asm to cpm-apps/CPM-2.2/CCP.COM' \
	  'make telnet   Assemble TELNET.asm to cpm-apps/Utils/TELNET.COM' \
	  'make wget     Assemble wget.asm to cpm-apps/Utils/WGET.COM' \
	  'make ftp      Assemble ftp.asm to cpm-apps/Utils/FTP.COM' \
	  'make nslookup Assemble NSLOOKUP.asm to cpm-apps/Utils/NSLOOKUP.COM' \
	  'make disk     Update the ProDOS image from changed binaries' \
	  'make run      Update image, then launch MAME without debugger' \
	  'make debug    Update image, then launch MAME with -debug -w' \
	  'make mame     Alias for make debug (original script behavior)' \
	  'make clean    Remove generated binaries (including CCP/TELNET/WGET/FTP/NSLOOKUP.COM); preserve disk images'
