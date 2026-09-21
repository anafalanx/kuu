# Step 20 — reconstruction, verified backup and uncertain publication

Status: **complete**. The [reconstruction guide](../docs/reconstruction.md)
distinguishes a complete retained cache, currently reachable pinned upstream
bytes and independently retained verified backups. It contains two complete
project modules and a local restore/backup driver, executed by the tests.

Restore checks independently reviewed archive pins, platform/layout receipts
and payload hashes before publishing a new installation. It inspects the
entire owned stage before clearing readonly, preserves other flags and refuses
links. Backup rehashes copied archives and retains the reviewed pin. Original
cache bytes and attributes remain unchanged. Primary and cleanup failures are
reported separately with the exact leftover staging path.

Publication reconciliation uses a project adapter, not a new built-in client.
It records intent before the sole permitted upload, retains the journal after
uncertainty, checks release/name/asset identity, state, size and digest, and
rehashes a downloaded copy before returning confirmation. It neither deletes
remote assets nor retries uploads automatically. Each invocation has bounded
operation counts; adapter timeouts cover full pagination/redirect operations.
The guide explains client-key TLS diagnostics and API limits with primary
Microsoft/GitHub references. Tests do not publish anything or use a live remote.

- Normal combined checks: **161 passed, 0 failed in 26.3 s**, covering
  `reconstruction cleanup_recipe native_helper docs bundle`:
  [log](../build/step20-tests.log).
- ASAN reconstruction/cleanup: **78 passed, 0 failed in 4.9 s**:
  [log](../build/step20-asan.log). Reconstruction adds **57 checks**.
- Tests use actual ZIP/TAR archives, missing/altered caches, incompatible pins,
  malformed receipts, wrong payloads, real junctions/hardlinks, and scoped
  readonly normalization. An independently retained disposable backup restores
  an installation after the original cache becomes unavailable.
- Mock remote cases cover accepted timeout, persisted retry protection,
  incomplete lookups, metadata and asset-ID conflicts, missing digests,
  corrupt downloaded bytes, raised adapter failures and dual cleanup failures.
- Independent review corrected lost upload diagnostics and cleanup bypass
  after raised download errors before acceptance. Native hardlink setup uses
  a small `CreateHardLinkW` mode in the existing reader fixture; no PowerShell
  dependency was added. All published Lua blocks check without warnings.
- [Build](../build/step20-build.log), [bundle](../build/step20-bundle.log),
  test registration and adoption/cleanup/index crosslinks are integrated;
  **56 embedded manual pages**.

Archive trust is explicit: post-extraction checks are not a sandbox. Reviewed
packages must not create aliases outside fresh staging; recursive failure
cleanup can affect shared hardlink attributes. The normalizer rejects aliases
before changing any staged flags. Tests prove its refusal and preservation,
not containment against hostile extraction or concurrent path replacement.
Backup fixtures use separate directories, not a simulated storage failure.
Journal confirmation records a past verified result; fresh return values are
authoritative. Atomic local publication is not a crash-durability guarantee.

Runtime SHA-256:
`b4fd817a81fff6e997176ec7ff020458b1bf971f43fffb46e27d9e11fbcda9f5`.
Started approximately **19:48 UTC**, accepted **19:58 UTC**, 2026-09-21:
about **10 minutes**, against **25–45 minutes**, with independent review in
parallel. Milestone 4 is accepted. Step 21's full integration gate follows.
