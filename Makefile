# NIF Makefile
NIF_NAME = inexora_nif

PREFIX_DIR = $(patsubst $(shell pwd)/%,%,$(MIX_APP_PATH))/priv
BUILD_DIR  = $(patsubst $(shell pwd)/%,%,$(MIX_APP_PATH))/obj

SRC_DIR = c_src
ODPIC_SRC_DIR = $(SRC_DIR)/odpi/src
# ODPIC_SRC_DIR = $(SRC_DIR)/odpi/embed
ODPIC_INC_DIR = $(SRC_DIR)/odpi/include

vpath %.c $(SRC_DIR) $(ODPIC_SRC_DIR)
vpath %.h $(SRC_DIR) $(ODPIC_INC_DIR) $(ODPIC_SRC_DIR)

CFLAGS = -Wall -Wextra
ifeq ($(MIX_ENV),dev)
  CFLAGS += -g
else
  CFLAGS += -O2
endif
CFLAGS += -I$(ERTS_INCLUDE_DIR)
CFLAGS += -I$(SRC_DIR)
CFLAGS += -I$(ODPIC_INC_DIR)
LDFLAGS = -lpthread

SOURCES = $(notdir $(wildcard $(SRC_DIR)/*.c))
SOURCES += $(notdir $(wildcard $(ODPIC_SRC_DIR)/*.c))
HEADERS = $(notdir $(wildcard $(SRC_DIR)/*.h))
HEADERS += $(notdir $(wildcard $(ODPIC_SRC_DIR)/*.h))
HEADERS += $(notdir $(wildcard $(ODPIC_INC_DIR)/*.h))
OBJECTS = $(SOURCES:%.c=$(BUILD_DIR)/%.o)
LIB_NAME = $(NIF_NAME).so

KERNEL_NAME := $(shell uname -s)
ifneq ($(CROSSCOMPILE),)
  CFLAGS += -fPIC -fvisibility=hidden
  LDFLAGS += -fPIC -shared
else
  ifeq ($(KERNEL_NAME), Linux)
    CFLAGS += -fPIC -fvisibility=hidden
    LDFLAGS += -fPIC -shared
  endif
  ifeq ($(KERNEL_NAME), Darwin)
    CFLAGS += -fPIC
    LDFLAGS += -dynamiclib -undefined dynamic_lookup
    LDFLAGS += -Wl,-rpath,/usr/local/lib
    LDFLAGS += -Wl,-rpath,/opt/instantclient
  endif
  ifeq (MINGW, $(findstring MINGW,$(KERNEL_NAME)))
    CFLAGS += -fPIC
    LDFLAGS += -fPIC -shared
    LIB_NAME = $(NIF_NAME).dll
  endif
  ifeq ($(KERNEL_NAME), $(filter $(KERNEL_NAME),OpenBSD FreeBSD NetBSD))
    CFLAGS += -fPIC
    LDFLAGS += -fPIC -shared
  endif
endif

.PHONY: called_from_make nif

called_from_make:
	mix compile

nif: $(PREFIX_DIR) $(BUILD_DIR) $(PREFIX_DIR)/$(LIB_NAME)

$(PREFIX_DIR) $(BUILD_DIR):
	mkdir -p $@

$(BUILD_DIR)/%.o: %.c $(HEADERS)
	@echo " CC $<"
	@$(CC) -c $(ERL_CFLAGS) $(CFLAGS) $< -o $@

$(PREFIX_DIR)/$(LIB_NAME): $(OBJECTS)
	@echo " LD $@"
	@$(CC) $(LDFLAGS) -o $@ $^
