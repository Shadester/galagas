# Amiga Galaga: m68k-elf-gcc (Homebrew: m68k-elf-gcc m68k-elf-binutils; Arch: the AUR, tools/setup-linux.sh) -> raw image -> ADF
CC = m68k-elf-gcc
EXTRA_CFLAGS =
EXTRA_ASFLAGS =
CFLAGS = -m68000 -O3 -ffreestanding -fno-pic -Wall -Wextra -Wno-unused-parameter -I ../psp -I src -isystem src/inc $(EXTRA_CFLAGS)
BUILD = build
OBJ = $(BUILD)/hw.o $(BUILD)/main.o $(BUILD)/video.o $(BUILD)/audio.o $(BUILD)/game.o $(BUILD)/libc.o $(BUILD)/fast.o

all: $(BUILD)/galaga.adf

$(BUILD):
	mkdir -p $(BUILD)

$(BUILD)/%.o: src/%.c $(wildcard src/*.h) ../psp/game.c ../psp/game.h | $(BUILD)
	$(CC) $(CFLAGS) -c -o $@ $<

# the rules are the hot code: speed before size
$(BUILD)/game.o: CFLAGS += -O3

$(BUILD)/%.o: src/%.s | $(BUILD)
	m68k-elf-as -m68000 --register-prefix-optional $(EXTRA_ASFLAGS) -o $@ $<

$(BUILD)/game.elf: $(OBJ) link.ld
	$(CC) -m68000 -nostdlib -T link.ld -o $@ $(OBJ) -lgcc -Wl,-Map=$(BUILD)/game.map

$(BUILD)/game.bin: $(BUILD)/game.elf
	m68k-elf-objcopy -O binary $< $@

$(BUILD)/boot.bin: $(BUILD)/boot.o
	m68k-elf-objcopy -O binary -j .text $< $@

# the AGA data: only an AGA machine reads it (the bootblock)
$(BUILD)/aga.bin: tools/gen_assets.py tools/art.py | $(BUILD)
	python3 tools/gen_assets.py --aga $@

$(BUILD)/galaga.adf: $(BUILD)/boot.bin $(BUILD)/game.bin $(BUILD)/aga.bin tools/make_adf.py
	python3 tools/make_adf.py $(BUILD)/boot.bin $(BUILD)/game.bin $(BUILD)/aga.bin $@

clean:
	rm -rf $(BUILD)

.PHONY: all clean

# docs/galaga.adz: the ADF, gzipped (vAmigaWeb plays it from a link)
web: $(BUILD)/galaga.adf
	python3 -c "import gzip,sys; open('docs/galaga.adz','wb').write(gzip.compress(open('$(BUILD)/galaga.adf','rb').read(), 9, mtime=0))"
	@ls -l docs/galaga.adz

.PHONY: web

# WHDLoad: the game built for it (hw.s: quit key, no cache), two Slaves (OCS 512 KB, AGA 1 MB) as hunk files, and the executable for the hard disk
WHD = build/whd
ifeq ($(BUILD),build)
$(WHD)/game.bin: $(wildcard src/*.c src/*.s src/*.h) ../psp/game.c tools/gen_assets.py tools/art.py
	$(MAKE) BUILD=$(WHD) EXTRA_CFLAGS=-DWHDLOAD EXTRA_ASFLAGS="--defsym WHDLOAD=1 --defsym NOCACHE=1" $(WHD)/game.bin $(WHD)/aga.bin
	touch $@
endif

$(WHD)/%.slave: src/whdload.s tools/make_hunk.py | $(WHD)/game.bin
	m68k-elf-as -m68000 --register-prefix-optional $(if $(findstring AGA,$*),--defsym AGA=1 --defsym AGABASE=0x80000) -o $(WHD)/$*.o $<
	m68k-elf-objcopy -O binary -j .text $(WHD)/$*.o $(WHD)/$*.bin
	python3 tools/make_hunk.py $(WHD)/$*.bin $@

whd: $(WHD)/Galaga.slave $(WHD)/GalagaAGA.slave
.PHONY: whd

# build/Galaga: the program for a hard disk (src/exe.s holds the game and the AGA data)
$(BUILD)/Galaga: src/exe.s $(BUILD)/game.bin $(BUILD)/aga.bin tools/make_hunk.py
	m68k-elf-as -m68000 --register-prefix-optional -o $(BUILD)/exe.o $<
	m68k-elf-objcopy -O binary -j .text $(BUILD)/exe.o $(BUILD)/exe.bin
	python3 tools/make_hunk.py $(BUILD)/exe.bin $@

exe: $(BUILD)/Galaga
.PHONY: exe
