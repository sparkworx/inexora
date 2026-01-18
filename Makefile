# Makefile for Inexora NIF
# Compiles ODPI-C and NIF bindings

# Erlang paths
ERTS_INCLUDE_DIR ?= $(shell erl -noshell -eval "io:format(\"~ts/erts-~ts/include/\", [code:root_dir(), erlang:system_info(version)]), halt().")
ERL_INTERFACE_INCLUDE_DIR ?= $(shell erl -noshell -eval "io:format(\"~ts\", [code:lib_dir(erl_interface, include)]), halt().")
ERL_INTERFACE_LIB_DIR ?= $(shell erl -noshell -eval "io:format(\"~ts\", [code:lib_dir(erl_interface, lib)]), halt().")

# Platform detection
UNAME_S := $(shell uname -s)

# Compiler settings
CC ?= cc
BASE_CFLAGS = -O2 -Wall -Wextra -Wno-unused-parameter

# Include paths
BASE_CFLAGS += -I$(ERTS_INCLUDE_DIR)
BASE_CFLAGS += -Ic_src/odpi/include

# Platform-specific settings
ifeq ($(UNAME_S),Darwin)
	# macOS
	BASE_LDFLAGS = -dynamiclib -undefined dynamic_lookup
	BASE_LDFLAGS += -L/usr/local/lib -Wl,-rpath,/usr/local/lib
	NIF_EXT = .so
else ifeq ($(UNAME_S),Linux)
	# Linux
	BASE_CFLAGS += -fPIC
	BASE_LDFLAGS = -shared
	NIF_EXT = .so
else
	# Windows (MinGW)
	BASE_LDFLAGS = -shared
	NIF_EXT = .dll
endif

# Allow extending flags via environment or command line
# Usage: make EXTRA_CFLAGS="-fsanitize=address -g" EXTRA_LDFLAGS="-fsanitize=address"
EXTRA_CFLAGS ?=
EXTRA_LDFLAGS ?=
CFLAGS = $(BASE_CFLAGS) $(EXTRA_CFLAGS)
LDFLAGS = $(BASE_LDFLAGS) $(EXTRA_LDFLAGS)

# Source files
NIF_SRC = c_src/inexora_nif.c
ODPI_SRC = c_src/odpi/embed/dpi.c

# Output
PRIV_DIR = priv
NIF_TARGET = $(PRIV_DIR)/inexora_nif$(NIF_EXT)

# Build targets
all: $(PRIV_DIR) $(NIF_TARGET)

$(PRIV_DIR):
	mkdir -p $(PRIV_DIR)

$(NIF_TARGET): $(NIF_SRC) $(ODPI_SRC)
	$(CC) $(CFLAGS) -o $@ $^ $(LDFLAGS)

clean:
	rm -rf $(PRIV_DIR)
	rm -f c_src/*.o

.PHONY: all clean
