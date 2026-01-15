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
CFLAGS = -O2 -Wall -Wextra -Wno-unused-parameter

# Include paths
CFLAGS += -I$(ERTS_INCLUDE_DIR)
CFLAGS += -Ic_src/odpi/include

# Platform-specific settings
ifeq ($(UNAME_S),Darwin)
	# macOS
	LDFLAGS = -dynamiclib -undefined dynamic_lookup
	NIF_EXT = .so
else ifeq ($(UNAME_S),Linux)
	# Linux
	CFLAGS += -fPIC
	LDFLAGS = -shared
	NIF_EXT = .so
else
	# Windows (MinGW)
	LDFLAGS = -shared
	NIF_EXT = .dll
endif

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
