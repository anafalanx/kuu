# Step 19 — verified native helpers and local shortcuts

Status: **complete**. The [native-helper guide](../docs/native-helper.md)
contains a tested cache module and manifest. A small project-owned
[Shell Link writer](../examples/shell_link.c) keeps the target, working
directory and argument values separate, with Windows CRT argument encoding.
It stages a complete link and publishes without replacing an existing path.
The Lua recipe atomically replaces only its explicitly owned local outputs.

Cache identity binds source, actual build-module bytes/flags, the complete
reviewed toolchain lockfile and verified compiler-driver bytes. Every reuse
validates the receipt and executable hash. Corrupt entries fail closed;
compilation and sharing failures preserve the previous installed helper.
The stable installed helper and pinned project compiler have literal tool
declarations. The trusted toolchain closure and exclusive-maintenance boundary
are explicit; this does not authenticate a maliciously rewritten whole project.

The first integration run exposed the pinned linker's refusal of a Unicode
absolute output filename. Compilation now uses the owned staging directory
as cwd and ASCII relative source/output operands. The unchanged Unicode
checkout test passes, including an empty inherited PATH. The initial run also
caught a generated manual count after a concurrent final test edit; generation
was repeated after the files were frozen. These were corrected before acceptance.

- Final normal regression: **133 passed, 0 failed in 16.3 s**, covering
  `native_helper editor_recipe cleanup_recipe docs bundle`:
  [log](../build/step19-tests-final.log).
- Final ASAN: **51 passed, 0 failed in 11.9 s**, covering helper and cleanup:
  [log](../build/step19-asan.log). The new helper case contributes **32 checks**.
- Fresh and moved disposable checkouts target their own runtime. Independent
  COM readback and actual child execution verify cwd and exact empty, spaced,
  quoted, backslash, Unicode and separator arguments. Tests also exercise
  input/recipe/toolchain changes, damaged receipts, damaged executable bytes,
  failed compilation and a real sharing denial.
- Native strict compilation and standalone GCC analysis passed for writer
  and reader. Independent smoke also covered long arguments, exit code 23,
  overwrite refusal and junction target preservation:
  [evidence](../build/shell-link-agent-38361df1d02b3483).
- Independent native review found no acceptance blocker. First path-validation
  errors are now captured before later Win32 calls can overwrite diagnostics.
  Kuu is instrumented in the ASAN run; the separately compiled helper is not.
- [Build](../build/step19-build.log), [bundle](../build/step19-bundle.log),
  test registration, manual crosslinks and order are integrated; **55 pages**.
  The static-analysis target now also covers authored `examples/*.c`.

Runtime SHA-256:
`e37392a882999c2d36f7a34710919528d8e407d43b16202be0eaeb939189dbb5`.
Tests alias this repository's pinned compiler tree into owned fixtures; the
production recipe requires the adopting project's provisioned toolchain.
No machine compiler, desktop shortcut or FlowNet file was changed.

Started after Step 18 at approximately **19:39 UTC**, accepted approximately
**19:48 UTC** on 2026-09-21: about **9 minutes**, against **30–60 minutes**.
Implementation and independent review ran in parallel. Step 20 follows.
