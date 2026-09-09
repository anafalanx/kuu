# kuu -- built with GNU make from the project's own toolchain in .tools.
#
#   make            build build/kuu.exe
#   make test       build, then run the test suite with the built kuu
#   make clean      remove build/
#
# The compiler is the MSYS2 UCRT64 gcc copied into .tools (docs/toolchain.md).
# Its compiler proper loads libgmp and friends from ucrt64\bin, which the
# driver does not add to the search path, so PATH is set here.  Nothing in
# this file runs kuu to build kuu: the build is make and gcc, the tests are Lua.

# Recipes run under cmd.exe whatever shell invoked make, so they behave the
# same from PowerShell, cmd, and Git Bash.
SHELL       := cmd.exe
.SHELLFLAGS := /c

TOOLS     := .tools/msys2/ucrt64
TOOLS_WIN := $(subst /,\,$(CURDIR)/$(TOOLS))
CC        := $(TOOLS_WIN)\bin\gcc.exe
export PATH := $(TOOLS_WIN)\bin;$(PATH)$(Path)

BUILD      := build
LUA_SRC    := vendor/lua-5.5.1/src
YYJSON_SRC := vendor/yyjson-0.12.0
HOST_SRC   := src
OUT        := $(BUILD)/kuu.exe

# Vendored Lua and yyjson compile as C with their own minimal flags, never the
# authored warning gate.  luaconf.h derives LUA_USE_WINDOWS from _WIN32 itself.
VENDOR_FLAGS := -std=gnu99 -O2 -ffunction-sections -fdata-sections

# The host is C23 under the els method's warning set, and warnings are errors.
HOST_FLAGS := -std=c23 -O2 -Wall -Wextra -Wpedantic -Wformat=2 -Wundef -Werror \
              -DUNICODE -D_UNICODE -D_WIN32_WINNT=0x0A00 \
              -ffunction-sections -fdata-sections \
              -I$(LUA_SRC) -I$(YYJSON_SRC) -I$(HOST_SRC)

# wmain entry, libgcc and winpthread static, unused sections dropped, symbols
# stripped.  The C runtime stays the system's ucrtbase.dll; bcrypt is Windows'.
LINK_FLAGS := -municode -static -static-libgcc -Wl,--gc-sections -s
LINK_LIBS  := -lbcrypt -lwinhttp

# Test fixtures: small C programs the suite drives as children.
FIXTURE_SRC := test/fixtures
FIXTURES    := $(BUILD)/test/http_fixture.exe

LUA_C    := $(filter-out $(LUA_SRC)/lua.c $(LUA_SRC)/luac.c,$(wildcard $(LUA_SRC)/*.c))
LUA_O    := $(patsubst $(LUA_SRC)/%.c,$(BUILD)/obj/lua/%.o,$(LUA_C))
YYJSON_O := $(BUILD)/obj/vendor/yyjson.o
HOST_C   := $(wildcard $(HOST_SRC)/*.c)
HOST_O   := $(patsubst $(HOST_SRC)/%.c,$(BUILD)/obj/host/%.o,$(HOST_C))

# The payload: kuu's own Lua and the manual, turned into C by tools/embed.c
# (compiled here, run by make; kuu is never used to build kuu).
EMBED      := $(BUILD)/embed.exe
PAYLOAD_IN := $(wildcard lua/*.lua) $(wildcard docs/*.md)
PAYLOAD_C  := $(BUILD)/gen/payload.c
PAYLOAD_O  := $(BUILD)/obj/gen/payload.o

.PHONY: all test clean
all: $(OUT)

$(OUT): $(HOST_O) $(LUA_O) $(YYJSON_O) $(PAYLOAD_O)
	$(CC) $(LINK_FLAGS) -o $@ $^ $(LINK_LIBS)
	@echo built $@

$(BUILD)/obj/lua/%.o: $(LUA_SRC)/%.c | $(BUILD)/obj/lua
	$(CC) $(VENDOR_FLAGS) -MMD -MP -c $< -o $@

$(YYJSON_O): $(YYJSON_SRC)/yyjson.c $(YYJSON_SRC)/yyjson.h | $(BUILD)/obj/vendor
	$(CC) $(VENDOR_FLAGS) -c $< -o $@

$(BUILD)/obj/host/%.o: $(HOST_SRC)/%.c | $(BUILD)/obj/host
	$(CC) $(HOST_FLAGS) -MMD -MP -c $< -o $@

$(EMBED): tools/embed.c | $(BUILD)
	$(CC) -std=c23 -O1 -Wall -Wextra -Werror -o $@ $<

$(PAYLOAD_C): $(EMBED) $(PAYLOAD_IN) | $(BUILD)/gen
	$(subst /,\,$(EMBED)) $@ lua docs

$(PAYLOAD_O): $(PAYLOAD_C) $(HOST_SRC)/payload.h | $(BUILD)/obj/gen
	$(CC) -std=c23 -O1 -I$(HOST_SRC) -c $< -o $@

$(BUILD)/test/%.exe: $(FIXTURE_SRC)/%.c | $(BUILD)/test
	$(CC) -std=c23 -O1 -Wall -Wextra -Werror -D_WIN32_WINNT=0x0A00 -o $@ $< -lws2_32

$(BUILD) $(BUILD)/gen $(BUILD)/test $(BUILD)/obj/lua $(BUILD)/obj/host $(BUILD)/obj/vendor $(BUILD)/obj/gen:
	@if not exist "$(subst /,\,$@)" mkdir "$(subst /,\,$@)"

.PHONY: fixtures
fixtures: $(FIXTURES)

test: $(OUT) $(FIXTURES)
	$(subst /,\,$(OUT)) test\run.lua

clean:
	@if exist $(BUILD) rmdir /s /q $(BUILD)

-include $(LUA_O:.o=.d) $(HOST_O:.o=.d)
