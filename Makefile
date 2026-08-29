# Makefile for C64 Hello World Example
# Requires: ACME assembler, c1541, and VICE (x64sc)

.PHONY: all clean run

# File names
ASM_FILE = src\shifty.asm
PRG_FILE = bin\shifty.prg
DISK_FILE = bin\shifty.d64

# Build target
all: $(DISK_FILE)

# Assemble the program with ACME
$(PRG_FILE): $(ASM_FILE)
	acme -f cbm -o $(PRG_FILE) $(ASM_FILE)

# Create D64 disk image and add the PRG file
$(DISK_FILE): $(PRG_FILE)
	c1541 -format "shifty,01" d64 $(DISK_FILE)
	c1541 -attach $(DISK_FILE) -write $(PRG_FILE) shifty

# Run the program in VICE
run: $(DISK_FILE)
	x64sc $(DISK_FILE)

# Clean build artifacts
clean:
	del /q $(PRG_FILE) $(DISK_FILE)

# Build and run
demo: clean all run
