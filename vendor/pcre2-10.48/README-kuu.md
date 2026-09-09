# PCRE2 10.48 in kuu

The 8-bit library of PCRE2 10.48 (2026-08-31), taken from the release
tarball `pcre2-10.48.tar.gz`, SHA-256
`ebcc25aadf2a51fa1fefa9b8bc9e7a79b3dae86870a0f1152a22e42befd46888`, from
https://github.com/PCRE2Project/pcre2/releases. Licence: BSD-3-Clause with the
PCRE2 exception, in `LICENCE.md`; authors in `AUTHORS.md`.

What is here and what changed:

- `src/`: the library sources only. Left out: `pcre2test`, `pcre2grep`,
  `pcre2demo`, `pcre2posix`, `pcre2_dftables`, the fuzz support, the JIT test,
  the EBCDIC tables, and the autotools and CMake inputs.
- `src/pcre2.h`: a copy of `pcre2.h.generic`, unchanged.
- `src/pcre2_chartables.c`: a copy of `pcre2_chartables.c.dist`, unchanged.
- `src/config.h`: `config.h.generic` with `SUPPORT_UNICODE`, `SUPPORT_PCRE2_8`,
  `HAVE_STDINT_H`, `HAVE_INTTYPES_H`, and `HAVE_WINDOWS_H` defined, and
  `NEWLINE_DEFAULT` set to 5 (ANYCRLF), so that a newline is CR, LF, or CRLF,
  as Windows text has it. No JIT.

The Makefile compiles it as C with `-DHAVE_CONFIG_H -DPCRE2_CODE_UNIT_WIDTH=8
-DPCRE2_STATIC`, under the vendor flags, never the authored warning gate.
