# Zapple-II / BP/M build
# GNU Make; preserves the ProDOS file type + load-address suffixes used by Cadius.

# Tools (override on the command line or in the environment).
MERLIN32 ?= merlin32
Z80ASM   ?= ./z80asm/z80asm
CADIUS   ?= cadius
MAME     ?= mame

# Sources and generated binaries.
SRC65       ?= softcard65.asm
SRC80       ?= softcard80.asm
RAW65       := softcard65
RAW80       := softcard80.bin
PRODOS65    := SOFTCARD65\#ff2000
PRODOS80    := SOFTCARD80.BIN\#041000

# ProDOS image and volume name.
DISK_IMAGE  ?= zapple2.po
DISK_VOLUME ?= ZAPPLE2

# Keep the MAME setup from the original build script.
MAME_MACHINE     ?= apple2ee
MAME_SLOTS       ?= -sl4 softcard -sl7 cffa202
MAME_HARD1       ?= h1-backup-220908.po
MAME_HARD2       ?= $(DISK_IMAGE)
MAME_RUN_FLAGS   ?= -w
MAME_DEBUG_FLAGS ?= -debug -w
MAME_EXTRA       ?=

.DEFAULT_GOAL := all
.PHONY: all z80 6502 disk run debug mame clean help

# `make` assembles both CPUs and updates the disk; it does not start MAME.
all: disk

z80: $(PRODOS80)
6502: $(PRODOS65)

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

# Update a temporary COPY of the ProDOS image, then publish it only after
# both Cadius operations succeed. Retain the .po extension for Cadius.
# Tracking the image itself as the target makes `make disk` incremental.
disk: $(DISK_IMAGE)

$(DISK_IMAGE): $(PRODOS65) $(PRODOS80)
	echo 'Creating $@ with Cadius...'
	$(CADIUS) createvolume "$@" "$(DISK_VOLUME)" 800KB
	$(CADIUS) createfolder "$@" "/$(DISK_VOLUME)/A"
	$(CADIUS) createfolder "$@" "/$(DISK_VOLUME)/B"
	$(CADIUS) createfolder "$@" "/$(DISK_VOLUME)/C"
	$(CADIUS) createfolder "$@" "/$(DISK_VOLUME)/D"
	$(CADIUS) createfolder "$@" "/$(DISK_VOLUME)/E"
	cd cpm-apps/CPM-2.2 && $(CADIUS) addfolder "../../$@" "/$(DISK_VOLUME)/A" .
	cd cpm-apps/Utils && $(CADIUS) addfolder "../../$@" "/$(DISK_VOLUME)/B" .
	cd cpm-apps/TP3 && $(CADIUS) addfolder "../../$@" "/$(DISK_VOLUME)/B" .
	cd cpm-apps/WS3 && $(CADIUS) addfolder "../../$@" "/$(DISK_VOLUME)/B" .
	$(CADIUS) addfile "$@" "/$(DISK_VOLUME)" "$(PRODOS65)"
	$(CADIUS) addfile "$@" "/$(DISK_VOLUME)" "$(PRODOS80)"

# The original script launched MAME with its debugger enabled.
# `make run` launches without -debug; `make debug` (or `make mame`) matches it.
run: disk
	$(MAME) $(MAME_RUN_FLAGS) $(MAME_MACHINE) $(MAME_SLOTS) -hard1 "$(MAME_HARD1)" -hard2 "$(MAME_HARD2)" $(MAME_EXTRA)

debug: disk
	$(MAME) $(MAME_DEBUG_FLAGS) $(MAME_MACHINE) $(MAME_SLOTS) -hard1 "$(MAME_HARD1)" -hard2 "$(MAME_HARD2)" $(MAME_EXTRA)

mame: debug

# Never delete the source files, ProDOS image, or hard-disk images.
clean:
	rm -f "$(PRODOS65)" "$(PRODOS80)" "$(RAW65)" "$(RAW80)" _FileInformation.txt

help:
	@printf '%s\n' \
	  'make          Assemble both CPUs and update zapple2.po (only if changed)' \
	  'make z80      Assemble softcard80.asm only' \
	  'make 6502     Assemble softcard65.asm only' \
	  'make disk     Update the ProDOS image from changed binaries' \
	  'make run      Update image, then launch MAME without debugger' \
	  'make debug    Update image, then launch MAME with -debug -w' \
	  'make mame     Alias for make debug (original script behavior)' \
	  'make clean    Remove generated binaries; preserve disk images'
