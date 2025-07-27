# Pattern rule for assembly to object
$(BINDIR)/%.o: $(SRCDIR)/%.asm $(INCLUDES)
	$(AS) $(ASFLAGS) -I$(SRCDIR) -o $@ $# Makefile for x64 Assembly CRUD API

AS = nasm
ASFLAGS = -f elf64
LD = ld
LDFLAGS = 

SRCDIR = src
BINDIR = cgi-bin

# Source files
SOURCES = init_shm.asm list_users.asm get_user.asm create_user.asm update_user.asm delete_user.asm

# Object files
OBJECTS = $(SOURCES:%.asm=$(BINDIR)/%.o)

# Executables
EXECUTABLES = $(SOURCES:%.asm=$(BINDIR)/%)

# Include files
INCLUDES = $(SRCDIR)/shared.inc $(SRCDIR)/macros.inc

.PHONY: all clean

all: $(BINDIR) $(EXECUTABLES)

$(BINDIR):
	mkdir -p $(BINDIR)

# Pattern rule for assembly to object
$(BINDIR)/%.o: $(SRCDIR)/%.asm $(INCLUDE)
	$(AS) $(ASFLAGS) -I$(SRCDIR) -o $@ $<

# Pattern rule for object to executable
$(BINDIR)/%: $(BINDIR)/%.o
	$(LD) $(LDFLAGS) -o $@ $<
	chmod +x $@

clean:
	rm -rf $(BINDIR)/*.o $(BINDIR)/init_shm $(BINDIR)/list_users $(BINDIR)/get_user $(BINDIR)/create_user $(BINDIR)/update_user $(BINDIR)/delete_user

# Initialize shared memory
init: $(BINDIR)/init_shm
	$(BINDIR)/init_shm