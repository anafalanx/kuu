# kuu -- built with GNU make from the project's own toolchain in .tools.
#
#   make            build build/kuu.exe
#   make test       build, then run the test suite with the built kuu
#   make analyze    run GCC static analysis on authored native code
#   make fuzz       run deterministic parser fuzzing (FUZZ cases per seed)
#   make gate       run test, analyze, fuzz, and soak in that order
#   make asan       build with the test-only CLANG64 toolchain and run the suite
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
PCRE2_SRC  := vendor/pcre2-10.48/src
HOST_SRC   := src
OUT        := $(BUILD)/kuu.exe
OUT_WIN    := $(subst /,\,$(OUT))

# The version, read from src/kuu.h, so the resource and the release tag say
# what --version says.
VERSION := $(word 3,$(subst ",,$(shell findstr /B /C:"#define KUU_VERSION " src\kuu.h)))

# Vendored Lua and yyjson compile as C with their own minimal flags, never the
# authored warning gate.  luaconf.h derives LUA_USE_WINDOWS from _WIN32 itself.
VENDOR_FLAGS := -std=gnu99 -O2 -ffunction-sections -fdata-sections

# PCRE2, the 8-bit library without JIT, with kuu's config.h (vendor/pcre2-10.48/README-kuu.md).
PCRE2_FLAGS := $(VENDOR_FLAGS) -DHAVE_CONFIG_H -DPCRE2_CODE_UNIT_WIDTH=8 -DPCRE2_STATIC -I$(PCRE2_SRC)

# The host is C23 under the els method's warning set, and warnings are errors.
HOST_FLAGS := -std=c23 -O2 -Wall -Wextra -Wpedantic -Wformat=2 -Wundef -Werror \
              -DUNICODE -D_UNICODE -D_WIN32_WINNT=0x0A00 \
              -DPCRE2_CODE_UNIT_WIDTH=8 -DPCRE2_STATIC \
              -ffunction-sections -fdata-sections \
              -I$(LUA_SRC) -I$(YYJSON_SRC) -I$(PCRE2_SRC) -I$(HOST_SRC)

# wmain entry, libgcc and winpthread static, unused sections dropped, symbols
# stripped.  The C runtime stays the system's ucrtbase.dll; bcrypt is Windows'.
LINK_FLAGS := -municode -static -static-libgcc -Wl,--gc-sections -s
LINK_LIBS  := -lbcrypt -lwinhttp -liphlpapi -lws2_32 -ladvapi32 -lwintrust -lcrypt32 -lwevtapi

# Test fixtures: small C programs the suite drives as children.
FIXTURE_SRC := test/fixtures
FIXTURES    := $(BUILD)/test/http_fixture.exe $(BUILD)/test/reg_fixture.exe $(BUILD)/test/http_error_fixture.exe $(BUILD)/test/limits_fixture.exe $(BUILD)/test/pty_fixture.exe

LUA_C    := $(filter-out $(LUA_SRC)/lua.c $(LUA_SRC)/luac.c,$(wildcard $(LUA_SRC)/*.c))
LUA_O    := $(patsubst $(LUA_SRC)/%.c,$(BUILD)/obj/lua/%.o,$(LUA_C))
YYJSON_O := $(BUILD)/obj/vendor/yyjson.o
PCRE2_C  := $(wildcard $(PCRE2_SRC)/pcre2_*.c)
PCRE2_O  := $(patsubst $(PCRE2_SRC)/%.c,$(BUILD)/obj/pcre2/%.o,$(PCRE2_C))
HOST_C   := $(wildcard $(HOST_SRC)/*.c)
HOST_O   := $(patsubst $(HOST_SRC)/%.c,$(BUILD)/obj/host/%.o,$(HOST_C))
ANALYZE_O := $(patsubst $(HOST_SRC)/%.c,$(BUILD)/analyze/%.o,$(HOST_C))

# The payload: kuu's own Lua and the manual, turned into C by tools/embed.c
# (compiled here, run by make; kuu is never used to build kuu).
EMBED      := $(BUILD)/embed.exe
PAYLOAD_DIRS := lua lua/cmd lua/fs lua/sync lua/net lua/svc lua/sched lua/pty docs
PAYLOAD_DIRS := $(foreach dir,$(PAYLOAD_DIRS),$(if $(wildcard $(dir)/.),$(dir)))
PAYLOAD_IN := $(foreach dir,$(PAYLOAD_DIRS),$(wildcard $(dir)/*.lua) $(wildcard $(dir)/*.md))
PAYLOAD_C  := $(BUILD)/gen/payload.c
PAYLOAD_O  := $(BUILD)/obj/gen/payload.o

# The version resource: tools/versionrc.c reads kuu.h and writes the .rc,
# windres compiles it, so the file's properties agree with --version.
WINDRES    := $(TOOLS_WIN)\bin\windres.exe
VERSIONRC  := $(BUILD)/versionrc.exe
VERSION_RC := $(BUILD)/gen/version.rc
VERSION_O  := $(BUILD)/obj/gen/version.o

.PHONY: all test clean
all: $(OUT)

$(OUT): $(HOST_O) $(LUA_O) $(YYJSON_O) $(PCRE2_O) $(PAYLOAD_O) $(VERSION_O)
	$(CC) $(LINK_FLAGS) -o $@ $^ $(LINK_LIBS)
	@echo built $@

$(BUILD)/obj/pcre2/%.o: $(PCRE2_SRC)/%.c | $(BUILD)/obj/pcre2
	$(CC) $(PCRE2_FLAGS) -MMD -MP -c $< -o $@

$(VERSIONRC): tools/versionrc.c $(HOST_SRC)/kuu.h | $(BUILD)
	$(CC) -std=c23 -O1 -Wall -Wextra -Werror -I$(HOST_SRC) -o $@ $<

$(VERSION_RC): $(VERSIONRC) | $(BUILD)/gen
	$(subst /,\,$(VERSIONRC)) $@

$(VERSION_O): $(VERSION_RC) | $(BUILD)/obj/gen
	$(WINDRES) -O coff -o $@ $<

$(BUILD)/obj/lua/%.o: $(LUA_SRC)/%.c | $(BUILD)/obj/lua
	$(CC) $(VENDOR_FLAGS) -MMD -MP -c $< -o $@

$(YYJSON_O): $(YYJSON_SRC)/yyjson.c $(YYJSON_SRC)/yyjson.h | $(BUILD)/obj/vendor
	$(CC) $(VENDOR_FLAGS) -c $< -o $@

$(BUILD)/obj/host/%.o: $(HOST_SRC)/%.c | $(BUILD)/obj/host
	$(CC) $(HOST_FLAGS) -MMD -MP -c $< -o $@

# Analyze without optimization so GCC retains the paths it needs to inspect.
# Separate objects keep this gate independent of the normal optimized build.
$(BUILD)/analyze/%.o: $(HOST_SRC)/%.c | $(BUILD)/analyze
	$(CC) $(filter-out -O2,$(HOST_FLAGS)) -O0 -fanalyzer -MMD -MP -c $< -o $@

.PHONY: analyze
analyze: $(ANALYZE_O)
	@echo native static analysis passed

$(EMBED): tools/embed.c | $(BUILD)
	$(CC) -std=c23 -O1 -Wall -Wextra -Werror -o $@ $<

$(PAYLOAD_C): $(EMBED) $(PAYLOAD_IN) | $(BUILD)/gen
	$(subst /,\,$(EMBED)) $@ $(PAYLOAD_DIRS)

$(PAYLOAD_O): $(PAYLOAD_C) $(HOST_SRC)/payload.h | $(BUILD)/obj/gen
	$(CC) -std=c23 -O1 -I$(HOST_SRC) -c $< -o $@

$(BUILD)/test/http_error_fixture.exe: $(FIXTURE_SRC)/http_error_fixture.c $(HOST_SRC)/http_error.c $(HOST_SRC)/http_error.h $(HOST_SRC)/wintext.c | $(BUILD)/test
	$(CC) -std=c23 -O1 -Wall -Wextra -Werror -D_WIN32_WINNT=0x0A00 -I$(HOST_SRC) -o $@ $(FIXTURE_SRC)/http_error_fixture.c $(HOST_SRC)/http_error.c $(HOST_SRC)/wintext.c

$(BUILD)/test/parser_fuzz.exe: $(FIXTURE_SRC)/parser_fuzz.c $(HOST_SRC)/cmdline.c $(HOST_SRC)/cmdline.h $(HOST_SRC)/wintext.c $(HOST_SRC)/wintext.h | $(BUILD)/test
	$(CC) $(HOST_FLAGS) -static -o $@ $(FIXTURE_SRC)/parser_fuzz.c $(HOST_SRC)/cmdline.c $(HOST_SRC)/wintext.c -lshell32

$(BUILD)/test/%.exe: $(FIXTURE_SRC)/%.c | $(BUILD)/test
	$(CC) -std=c23 -O1 -Wall -Wextra -Werror -D_WIN32_WINNT=0x0A00 -o $@ $< -lws2_32

$(BUILD) $(BUILD)/analyze $(BUILD)/gen $(BUILD)/test $(BUILD)/obj/lua $(BUILD)/obj/host $(BUILD)/obj/vendor $(BUILD)/obj/pcre2 $(BUILD)/obj/gen:
	@if not exist "$(subst /,\,$@)" mkdir "$(subst /,\,$@)"

.PHONY: fixtures
fixtures: $(FIXTURES)

test: $(OUT) $(FIXTURES)
	$(subst /,\,$(OUT)) test\run.lua

clean:
	@if exist $(BUILD) rmdir /s /q $(BUILD)

-include $(LUA_O:.o=.d) $(HOST_O:.o=.d) $(PCRE2_O:.o=.d) $(ANALYZE_O:.o=.d)

# Deterministic, bounded parser fuzzing, with a single-seed replay option.
FUZZ ?= 10000
FUZZ_SEED ?=
.PHONY: fuzz
fuzz: $(OUT) $(BUILD)/test/parser_fuzz.exe
	$(subst /,\,$(OUT)) test\fuzz.lua $(FUZZ) $(FUZZ_SEED)

# Soak: kuu under volume for SOAK seconds (default 60), on demand, with the fixture.
SOAK ?= 60
.PHONY: soak
soak: $(OUT) $(FIXTURES)
	$(subst /,\,$(OUT)) test\soak.lua $(SOAK)

# Recursive makes deliberately serialize the gates even under `make -j gate`:
# test and soak share scratch files and must never run alongside one another.
.PHONY: gate
gate:
	$(MAKE) test
	$(MAKE) analyze
	$(MAKE) fuzz
	$(MAKE) soak

# AddressSanitizer is an independent, test-only CLANG64 build. Every host and
# vendored object is instrumented; no production object or executable is reused.
# The plain C payload/resource generators remain built by GCC, never by kuu.
CLANG_TOOLS := .tools/msys2/clang64
CLANG_WIN := $(subst /,\,$(CURDIR)/$(CLANG_TOOLS))
CLANG := $(CLANG_WIN)\bin\clang.exe
ASAN_DIR := $(BUILD)/asan
ASAN_OUT := $(BUILD)/kuu-asan.exe
ASAN_FLAGS := -O1 -g -fsanitize=address -fno-omit-frame-pointer -fno-optimize-sibling-calls
ASAN_HOST_FLAGS := $(filter-out -O2,$(HOST_FLAGS)) $(ASAN_FLAGS)
ASAN_VENDOR_FLAGS := $(filter-out -O2,$(VENDOR_FLAGS)) $(ASAN_FLAGS)
ASAN_PCRE2_FLAGS := $(filter-out -O2,$(PCRE2_FLAGS)) $(ASAN_FLAGS)
ASAN_HOST_O := $(patsubst $(HOST_SRC)/%.c,$(ASAN_DIR)/obj/host/%.o,$(HOST_C))
ASAN_LUA_O := $(patsubst $(LUA_SRC)/%.c,$(ASAN_DIR)/obj/lua/%.o,$(LUA_C))
ASAN_YYJSON_O := $(ASAN_DIR)/obj/vendor/yyjson.o
ASAN_PCRE2_O := $(patsubst $(PCRE2_SRC)/%.c,$(ASAN_DIR)/obj/pcre2/%.o,$(PCRE2_C))
ASAN_PAYLOAD_C := $(ASAN_DIR)/gen/payload.c
ASAN_PAYLOAD_O := $(ASAN_DIR)/obj/gen/payload.o
ASAN_VERSION_RC := $(ASAN_DIR)/gen/version.rc
ASAN_VERSION_O := $(ASAN_DIR)/obj/gen/version.o

# GCC accepts these va_list wrappers; Clang wants printf annotations on their
# entire call chains. Keep that compiler-specific diagnostic out of those two
# ASAN objects while retaining the production warning gate unchanged.
$(ASAN_DIR)/obj/host/err.o $(ASAN_DIR)/obj/host/program.o: ASAN_HOST_FLAGS += -Wno-missing-format-attribute -Wno-format-nonliteral

$(ASAN_DIR)/obj/host/%.o: $(HOST_SRC)/%.c | $(ASAN_DIR)/obj/host
	$(CLANG) $(ASAN_HOST_FLAGS) -MMD -MP -c $< -o $@

$(ASAN_DIR)/obj/lua/%.o: $(LUA_SRC)/%.c | $(ASAN_DIR)/obj/lua
	$(CLANG) $(ASAN_VENDOR_FLAGS) -MMD -MP -c $< -o $@

$(ASAN_YYJSON_O): $(YYJSON_SRC)/yyjson.c $(YYJSON_SRC)/yyjson.h | $(ASAN_DIR)/obj/vendor
	$(CLANG) $(ASAN_VENDOR_FLAGS) -c $< -o $@

$(ASAN_DIR)/obj/pcre2/%.o: $(PCRE2_SRC)/%.c | $(ASAN_DIR)/obj/pcre2
	$(CLANG) $(ASAN_PCRE2_FLAGS) -MMD -MP -c $< -o $@

$(ASAN_PAYLOAD_C): $(EMBED) $(PAYLOAD_IN) | $(ASAN_DIR)/gen
	$(subst /,\,$(EMBED)) $@ $(PAYLOAD_DIRS)

$(ASAN_PAYLOAD_O): $(ASAN_PAYLOAD_C) $(HOST_SRC)/payload.h | $(ASAN_DIR)/obj/gen
	$(CLANG) -std=c23 $(ASAN_FLAGS) -I$(HOST_SRC) -c $< -o $@

$(ASAN_VERSION_RC): $(VERSIONRC) | $(ASAN_DIR)/gen
	$(subst /,\,$(VERSIONRC)) $@

$(ASAN_VERSION_O): $(ASAN_VERSION_RC) | $(ASAN_DIR)/obj/gen
	$(WINDRES) -O coff -o $@ $<

$(ASAN_DIR)/gen $(ASAN_DIR)/obj/host $(ASAN_DIR)/obj/lua $(ASAN_DIR)/obj/vendor $(ASAN_DIR)/obj/pcre2 $(ASAN_DIR)/obj/gen:
	@if not exist "$(subst /,\,$@)" mkdir "$(subst /,\,$@)"

$(ASAN_OUT): $(ASAN_HOST_O) $(ASAN_LUA_O) $(ASAN_YYJSON_O) $(ASAN_PCRE2_O) $(ASAN_PAYLOAD_O) $(ASAN_VERSION_O)
	$(CLANG) $(ASAN_FLAGS) -municode -o $@ $^ $(LINK_LIBS)

.PHONY: asan
asan: $(ASAN_OUT) $(FIXTURES)
	set "PATH=$(CLANG_WIN)\bin;$(PATH)" && set "KUU_TEST_ASAN=1" && $(subst /,\,$(ASAN_OUT)) test\run.lua

-include $(ASAN_HOST_O:.o=.d) $(ASAN_LUA_O:.o=.d) $(ASAN_PCRE2_O:.o=.d)

# ---- release: sign, hash, publish -- make, cmd, and plain C tools; never kuu --------------
# The certificate is selected by thumbprint and the signature timestamped by
# Certum; after signing, the signature is verified and the leaf checked to be
# issued to the expected name.  The sidecar is written by tools/sha256sum.c.
# Signing needs the owner's SimplySign session, so the owner runs `make release`.
SIGNTOOL  ?= C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\signtool.exe
SIGN_SHA1 ?= fff5468e3b61a5c466fc5a07a7bb9fd2b9975b4b
SIGN_NAME ?= Open Source Developer Vincent Vercauteren
TIMESTAMP ?= http://time.certum.pl
GH        ?= gh
SHA256SUM := $(BUILD)/sha256sum.exe

$(SHA256SUM): tools/sha256sum.c | $(BUILD)
	$(CC) -std=c23 -O1 -Wall -Wextra -Werror -o $@ $< -lbcrypt

SIGNED    := $(BUILD)/kuu.exe.signed

# The stamp makes signing idempotent: a signed executable is not signed again
# until it is rebuilt.
$(SIGNED): $(OUT)
	"$(SIGNTOOL)" sign /fd sha256 /sha1 $(SIGN_SHA1) /tr $(TIMESTAMP) /td sha256 $(OUT_WIN)
	"$(SIGNTOOL)" verify /pa /all $(OUT_WIN)
	"$(SIGNTOOL)" verify /pa /v $(OUT_WIN) | findstr /C:"Issued to: $(SIGN_NAME)" > nul
	@echo signed $(OUT) as $(SIGN_NAME)> $@
	@type $(subst /,\,$@)

.PHONY: sign release publish
sign: $(SIGNED)

$(BUILD)/kuu.exe.sha256: $(SIGNED) $(SHA256SUM)
	$(subst /,\,$(SHA256SUM)) $(OUT_WIN) > $@
	@type $(subst /,\,$@)

release: $(BUILD)/kuu.exe.sha256

# The release is bound to the commit this tree was built from: the tag lands
# on HEAD, never on whatever the remote default branch points at, and a tree
# with uncommitted changes is refused.  HEAD must already be pushed.
GIT_HEAD  := $(shell git rev-parse HEAD)
GIT_DIRTY := $(shell git status --porcelain)

publish: gate
	$(if $(GIT_DIRTY),$(error the tree has uncommitted changes; commit and push before publishing))
	$(MAKE) release
	$(GH) release create $(VERSION) $(OUT) $(BUILD)/kuu.exe.sha256 --target $(GIT_HEAD) --title "kuu $(VERSION)" --generate-notes
