# NES Galaga: ca65 / ld65 (cc65 suite). MMC1 (SNROM): build/galaga.nes
LD65 = ld65
CA65 = ca65 -g --cpu 6502 -I src -I ../lynx/src/game
BUILD ?= build
OBJ = $(BUILD)/game.o $(BUILD)/tables.o
TARGET = $(BUILD)/galaga.nes

all: $(TARGET)

$(BUILD)/%.o: src/%.s $(wildcard src/*.inc src/*.s src/game/*.s gfx/*) | $(BUILD)
	$(CA65) $(CAFLAGS) -o $@ $<

$(TARGET): $(OBJ) nes.cfg
	$(LD65) -C nes.cfg -m $(BUILD)/galaga.map -Ln $(BUILD)/galaga.lbl --dbgfile $(BUILD)/galaga.dbg -o $@ $(OBJ)

$(BUILD):
	mkdir -p $(BUILD)

clean:
	rm -rf build

.PHONY: all clean
