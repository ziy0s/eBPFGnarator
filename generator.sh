#!/bin/bash

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}"
echo "  ╔══════════════════════════════════════╗"
echo "  ║     eBPF Project Scaffolder          ║"
echo "  ╚══════════════════════════════════════╝"
echo -e "${NC}"

# Get project name
read -p "Project name: " projectName

# Validate project name
if ! echo "$projectName" | grep -qE '^[a-z][a-z0-9_]*$'; then
    echo -e "${RED}ERROR:${NC} Project name must start with a lowercase letter"
    echo "       and contain only lowercase letters, numbers, underscores."
    echo "       Example: fileguard, rootkit_detector"
    exit 1
fi

# Get path
read -p "Setup path [default ./]: " Path
if [ -z "$Path" ]; then
    Path="./"
fi

# Fix path: ensure trailing slash
Path="${Path%/}"
Dir="$Path/$projectName"

# Check if directory already exists
if [ -d "$Dir" ]; then
    echo -e "${RED}ERROR:${NC} Directory '$Dir' already exists."
    exit 1
fi

# Check required tools
echo ""
echo -e "${BLUE}Checking required tools...${NC}"
MISSING=0
for tool in clang bpftool gcc; do
    if command -v $tool &> /dev/null; then
        echo -e "  ${GREEN}✓${NC} $tool found"
    else
        echo -e "  ${RED}✗${NC} $tool NOT found"
        MISSING=1
    fi
done

if [ $MISSING -eq 1 ]; then
    echo -e "${RED}ERROR:${NC} Install missing tools first."
    exit 1
fi

# Create directory structure
echo ""
echo -e "${BLUE}Creating project structure...${NC}"
mkdir -p "$Dir/src"
echo -e "  ${GREEN}✓${NC} $Dir/src/"

# Generate vmlinux.h
echo -e "  ${YELLOW}→${NC} Generating vmlinux.h..."
bpftool btf dump file /sys/kernel/btf/vmlinux format c > "$Dir/src/vmlinux.h" 2>/dev/null
echo -e "  ${GREEN}✓${NC} vmlinux.h"

# Generate shared header
cat > "$Dir/src/$projectName.h" <<EOF
#ifndef __${projectName^^}_H
#define __${projectName^^}_H



#endif /* __${projectName^^}_H */
EOF
echo -e "  ${GREEN}✓${NC} src/$projectName.h"

# Generate BPF program
cat > "$Dir/src/$projectName.bpf.c" <<EOF
#include "vmlinux.h"
#include <bpf/bpf_helpers.h>
#include <bpf/bpf_tracing.h>
#include <bpf/bpf_core_read.h>
#include "$projectName.h"

char LICENSE[] SEC("license") = "GPL";

EOF
echo -e "  ${GREEN}✓${NC} src/$projectName.bpf.c"

# Generate user-space loader
cat > "$Dir/src/main.c" <<EOF
#include <bpf/libbpf.h>
#include "$projectName.h"
#include "$projectName.skel.h"

EOF
echo -e "  ${GREEN}✓${NC} src/main.c"

# Generate Makefile
cat > "$Dir/Makefile" <<EOF
# Production eBPF build system for $projectName

# Tools
CLANG    ?= clang
BPFTOOL  ?= bpftool
CC       ?= gcc
STRIP    ?= strip

# Project
APP      := $projectName
SRC_DIR  := src
BPF_SRC  := \$(SRC_DIR)/\$(APP).bpf.c
BPF_OBJ  := \$(APP).bpf.o
SKEL     := \$(SRC_DIR)/\$(APP).skel.h
USER_SRC := \$(SRC_DIR)/main.c
OUTPUT   := \$(APP)

# BPF compilation flags
BPF_CFLAGS := -O2 -g -target bpf \\
    -D__TARGET_ARCH_x86 \\
    -I\$(SRC_DIR) \\
    -I/usr/local/include

# User-space compilation flags
USER_CFLAGS := -O2 -g -Wall \\
    -I\$(SRC_DIR) \\
    -I/usr/local/include

# Linker flags
LIBBPF_STATIC := \$(shell find /usr/local -name libbpf.a 2>/dev/null | head -n 1)
ifeq (\$(LIBBPF_STATIC),)
    LDFLAGS := -L/usr/local/lib -L/usr/local/lib64 -lbpf -lelf -lz
else
    LDFLAGS := \$(LIBBPF_STATIC) -lelf -lz
endif

# Default target
all: \$(OUTPUT)

# Step 1: Generate vmlinux.h
\$(SRC_DIR)/vmlinux.h:
	@echo "=== Generating vmlinux.h ==="
	\$(BPFTOOL) btf dump file /sys/kernel/btf/vmlinux format c > \$@

# Step 2: Compile BPF program
\$(BPF_OBJ): \$(BPF_SRC) \$(SRC_DIR)/vmlinux.h \$(SRC_DIR)/\$(APP).h
	@echo "=== Compiling BPF program ==="
	\$(CLANG) \$(BPF_CFLAGS) -c \$< -o \$@

# Step 3: Generate skeleton
\$(SKEL): \$(BPF_OBJ)
	@echo "=== Generating skeleton ==="
	\$(BPFTOOL) gen skeleton \$< > \$@

# Step 4: Compile user-space program
\$(OUTPUT): \$(USER_SRC) \$(SKEL) \$(SRC_DIR)/\$(APP).h
	@echo "=== Compiling user-space loader ==="
	\$(CC) \$(USER_CFLAGS) \$< -o \$@ \$(LDFLAGS)

# Run
run: \$(OUTPUT)
	sudo ./\$(OUTPUT)

# Clean
clean:
	rm -f \$(BPF_OBJ) \$(SKEL) \$(OUTPUT)

# Install
install: \$(OUTPUT)
	install -m 755 \$(OUTPUT) /usr/local/bin/\$(OUTPUT)

# Generate skeleton first time
skel: \$(SKEL)

.PHONY: all run clean install skel
EOF
echo -e "  ${GREEN}✓${NC} Makefile"

# Generate .gitignore
cat > "$Dir/.gitignore" <<EOF
*.o
*.skel.h
vmlinux.h
$projectName
package.json
.vscode/
.idea/
*.swp
EOF
echo -e "  ${GREEN}✓${NC} .gitignore"

# Generate README.md
cat > "$Dir/README.md" <<EOF
# $projectName

eBPF program built with libbpf.

## Build
\`\`\`bash
make
\`\`\`

## Run
\`\`\`bash
make run
\`\`\`

## Clean
\`\`\`bash
make clean
\`\`\`
EOF
echo -e "  ${GREEN}✓${NC} README.md"

# Initialize git
cd "$Dir"
git init -q 2>/dev/null
git add . 2>/dev/null
git commit -q -m "Initial eBPF project scaffold for $projectName" 2>/dev/null
cd - > /dev/null
echo -e "  ${GREEN}✓${NC} Git repository initialized"

# Done
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  Project '$projectName' is ready!        ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo -e "  cd $Dir"
echo -e "  make"
echo -e "  sudo ./$projectName"
echo ""