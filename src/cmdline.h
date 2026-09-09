/*
 * cmdline.h -- Windows command-line quoting for kuu's launcher.
 *
 * Windows has no argv: a process receives one command-line string and parses
 * it back itself.  A PE target uses the CommandLineToArgvW convention, so kuu
 * quotes by the identical rules and the child sees exactly the argv the
 * program meant; no shell, no word splitting.
 *
 * A batch script (.bat/.cmd) is not a PE image: CreateProcess hands the line
 * to cmd.exe, whose parsing differs, so ordinary quoting is exploitable
 * (CVE-2024-24576, "BatBadBut").  Batch targets run through an explicitly and
 * defensively quoted cmd.exe instead.  This is machteld's implementation,
 * which ported Go's syscall.EscapeArg and Rust's std::process batch rules.
 *
 * Returned strings are malloc'd and NUL-terminated; the caller frees them.
 */
#ifndef KUU_CMDLINE_H
#define KUU_CMDLINE_H

/* Quote one argument by the CommandLineToArgvW rules. */
char *ku_escape_arg(const char *arg);

/* Space-join argv[0..argc), each argument quoted.  For PE targets. */
char *ku_make_cmdline(int argc, const char *const *argv);

/* True when the final path component ends in .bat or .cmd, any case. */
int ku_is_batch_target(const char *exe);

/* Build `cmd.exe /e:ON /v:OFF /d /c "<script> <args...>"` for a batch
 * script.  `args` are the script's arguments (argv[1:]).  Returns 0 and sets
 * *out on success; -1 with a static *error when a value cannot be made safe
 * (a quote or trailing backslash in the script path, a CR or LF anywhere). */
int ku_make_batch_cmdline(const char *script, int argc, const char *const *args,
                          char **out, const char **error);

#endif /* KUU_CMDLINE_H */
