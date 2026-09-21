# Step 08 — file-attribute contract and independent Windows probes

Status: **complete**. The contract below was the implementation target for
Step 09; at the completion of Step 08 the functions were **not yet exposed by
kuu**. [Step 09 subsequently implemented them](step09-flownet-feedback-2026-09-21.md).
No production source, public API, release version or executable changed in this step. The
[sequential plan](plan-flownet-feedback-2026-09-15.md) retains Step 10 for
recursive cleanup. FlowNet was not modified or executed.

## Exact API for Step 09

```lua
local flags, err = fs.attributes(path [, { follow = false }])
-- on success:
-- {
--   attrs = integer,                  -- complete unsigned 32-bit Windows mask
--   readonly = boolean,
--   hidden = boolean,
--   system = boolean,
--   archive = boolean,
--   temporary = boolean,
--   not_content_indexed = boolean,
-- }

local ok, err = fs.set_attributes(path, patch [, { follow = false }])
-- true on success, for example:
assert(fs.set_attributes(path, { readonly = false, hidden = true }))
```

The bracketed syntax above denotes optional arguments, not runnable Lua.
`attrs` uses the same name and numerical mask representation as `fs.stat`.
All six named booleans are always present. The result is a detached snapshot;
changing its Lua fields changes nothing on disk.

Only the six named flags may appear in a patch. Omitted/nil fields preserve
the queried attributes; `false` clears a flag and `true` sets it. `attrs`,
`normal`, directory/reparse flags, compression, encryption, sparse allocation
and raw masks are not accepted mutation keys. Unrelated native bits are
preserved from the queried state. These APIs do not create paths, recurse,
change ACLs, create links or implement POSIX permission modes.

The target is a filesystem object: a file, directory or reparse object whose
opened handle is a disk-file handle. A successfully opened non-disk handle
returns `nil, FS badvalue`. Other unsupported objects/providers retain their
classified native failure. This is not a device-control API or a promise
that every cloud, network or custom reparse provider supports attribute writes.

### Argument validation

- `path` must actually be a Lua string containing a UTF-8 path; do not coerce
  numbers to path strings in these new APIs. Use the existing Windows path
  normalization and malformed/NUL-path handling afterward.
- `patch` is a required table; `{}` is valid. Options may be omitted or nil,
  otherwise they must be a table. The only option is `follow`.
- Read stored table entries directly. Do not consult `__index`, `__pairs` or
  other metatable behavior to obtain options/patch fields. Inherited fields
  are absent. No user callback runs after native resource acquisition.
- Keys must match exactly, including their Lua string length. Unknown keys,
  numeric keys and spellings such as `"hidden\0suffix"` raise **FS usage**.
  The raw inspection key `attrs` is therefore rejected in a setter patch.
- Every present flag and `follow` value must be an actual boolean. A number,
  string or table raises **FS badvalue**, rather than using Lua truthiness.
  A nil field is absent, so `follow=nil` uses the default.
- Wrong path, patch or options argument types use normal raised Lua argument errors, as
  existing native APIs do. Empty/NUL/refused path spellings raise **FS badvalue**;
  invalid UTF-8 raises **FS encoding** through the existing path helper
  (clarified during Step 09 implementation). Validate all argument structure before opening handles or
  allocating native path buffers that a Lua error could abandon.

No precedence is promised between multiple simultaneously invalid arguments.
Once validation succeeds, environmental failures return `nil, err` rather
than raising. This distinction follows kuu's existing filesystem conventions.

### Empty and unchanged patches

An empty patch opens and queries the selected object with
`FILE_READ_ATTRIBUTES`, then returns true without an attribute-set call. It
checks existence, link selection and metadata readability; **it does not
test write permission**.

A nonempty patch requests `FILE_READ_ATTRIBUTES | FILE_WRITE_ATTRIBUTES`,
even when the requested flags already match. After opening and querying,
an unchanged effective mask returns true without a setter call. Thus an
already-satisfied nonempty patch can fail for lack of write-attributes access,
while `{}` can succeed. No extra content-read or content-write rights are
requested.

### Links, directories and errors

Both functions default to **`follow=false` for the final path component**.
This selects the reparse object itself. `{follow=true}` selects its resolved
target. Existing `fs.stat` defaults remain unchanged. Linked ancestors may
still be traversed; final-component selection is not a containment boundary.
A failed nofollow operation never silently retries by following.

`temporary=true` on an opened object carrying `FILE_ATTRIBUTE_DIRECTORY`
returns **nil, FS badvalue**, rejecting the entire patch before any write.
This includes directory junctions and directory symlinks opened without
following, and directory targets opened with following. `temporary=false`
is permitted on directories. File attributes are separate from ACLs: a
directory's readonly flag is not a general write-permission mechanism, even
though it can prevent removal.

| Situation | Result |
|---|---|
| Successful getter | Seven-field table: `attrs` plus six booleans |
| Successful setter, including validated empty/unchanged patch | `true` |
| Missing ordinary path or missing ancestor | `nil, FS notfound` using existing native classification |
| Confirmed missing target of the followed final name-surrogate link | `nil, FS dangling`, subject to the diagnostic boundary below |
| Permission denial, write protection or native sharing/locking denial | `nil, FS access`; never relabel access denied as dangling |
| Directory with `temporary=true`, or successfully opened non-disk object | `nil, FS badvalue` |
| Other native failure | Existing `ku_fs_code` classification, commonly `FS oserror` |

Dangling detection is deliberately narrow: only after a followed open fails
with native `ERROR_FILE_NOT_FOUND` or `ERROR_PATH_NOT_FOUND`, attempt a
nofollow metadata query and verify that the final component has a
**name-surrogate reparse tag**. Classify as dangling only when that evidence
is available. Otherwise preserve the original native error. Save it before
diagnostic opens/queries/handle closing. A generic reparse bit alone is not
enough. This is best-effort diagnosis across separate observations, not an
identity guarantee in the presence of concurrent replacement; dangling
ancestors, unavailable network targets and provider-specific failures may
retain other classifications. Native error numbers remain in the existing
diagnostic message; this step does not introduce a new structured Win32 field.

## Native implementation boundaries

Use `OPEN_EXISTING`, `FILE_FLAG_BACKUP_SEMANTICS`, all three share flags, and
`FILE_FLAG_OPEN_REPARSE_POINT` when not following. Read `FILE_BASIC_INFO`,
compute the named-flag patch, and write through **the same handle**. This
keeps the update attached to that object if its path is renamed/replaced.
It does not atomically merge another process's simultaneous attribute patch;
unspecified-bit preservation refers to the queried state without a competing
attribute writer.

Normalize `FILE_ATTRIBUTE_NORMAL`: remove it when any other bit remains; use
NORMAL when the effective mask would otherwise be zero. Passing zero to the
native setter means *leave attributes unchanged*, not *clear all flags*.

For the write, create a fresh zero-initialized `FILE_BASIC_INFO` and assign
only `FileAttributes`. Do not copy the queried timestamps back. Zero time
fields avoid explicit timestamp assignment, so another handle's intervening
write time is not restored to a stale value. File contents remain unchanged.
Creation/access/write times were preserved in the quiet native fixture, but
the filesystem may naturally advance metadata `ChangeTime`; do not promise
that every timestamp stays fixed. `fs.stat().ctime` is creation time, not
native metadata change time.

Close handles and free buffers before raising or allocating Lua results.
Relevant source traps identified during review:

- `src/fs.c:69`, `opt_boolean`, accepts truthy non-booleans.
- `src/fs.c:439`, `open_or_fail`, can label any failed followed open as
  dangling whenever a nofollow read open succeeds; it is unsafe to reuse for
  a write-attributes request without narrowing its logic.
- `src/values.c:172`, `ku_check_options`, uses C-string comparison without
  checking Lua key length. The new parser needs exact raw keys/booleans.
- `src/fspath.c:177`, `ku_fs_code`, already defines the environmental error
  categories. Preserve those rather than inventing an attribute error domain.

These are Step 09 implementation constraints. General option-parser changes
across unrelated modules are not part of this contract step.

## Independent OS fixture matrix

The standalone [native probe](../test/fixtures/attributes_probe.c) calls
Windows directly and does not call a proposed kuu getter/setter. Ordinary
readback uses `GetFileAttributesExW`/`GetFileAttributesW`, distinct from the
handle setter; link identities/timestamps additionally use native handle
queries. Sparse state is created independently with `FSCTL_SET_SPARSE`.
ACLs apply only to newly created fixture objects and are restored. No parent
outside a newly created fixture is modified; retained fixtures are not
recursively deleted.

| Native case | Observed result | Step 09 obligation |
|---|---|---|
| Six named bits on an ordinary file | Each set and independently read back | Getter booleans/raw mask agree with independent setup; setter agrees with independent readback |
| Five applicable bits on a directory | Each set and read back | Same directory behavior; directory bit preserved |
| TEMPORARY on a directory | Error 87 | Preflight the entire patch and return FS badvalue without mutation |
| Zero mask versus NORMAL | Zero retains flags; NORMAL clears them | Clear the final mutable flag correctly |
| All mutable flags cleared on a directory/sparse file | DIRECTORY/SPARSE preserved | Preserve unexposed flags without pretending setter can create/remove sparse allocation |
| Attribute write with zero time fields | Bytes and creation/access/write times preserved; ChangeTime advanced | Do not copy or explicitly restore timestamps |
| Another handle changes write time before attribute set | New write time retained | No stale timestamp restoration |
| Object renamed and original name replaced while handle remains open | Only renamed original changes | Read/patch/write the same handle |
| Junction, nofollow | Link flag changes; target unchanged | Default selection modifies the link object |
| Junction, follow | Target changes; link unchanged | Explicit following selects target |
| Junction, nofollow TEMPORARY | Error 87; link and target unchanged | Directory-link validation |
| Junction target denies write attributes, link remains accessible | Followed open error 5 | Preserve FS access; never misclassify as dangling |
| Dangling junction | Nofollow read/write succeeds; follow fails with error 2 | Narrow missing-target diagnosis |
| Linked ancestor | Nofollow final component still reaches child through junction | Document boundary and test it |
| File, directory and dangling-file symlinks | **Three skips: creation denied with error 1314**, including unprivileged-create attempt | Separate real symlink tests on a capable host; do not count junction tests as symlink coverage |
| File denies write attributes | Metadata read still succeeds; write request fails with 5 | Empty patch needs only read access; nonempty patch needs write access |
| Child denies read attributes but parent permits listing | Attribute read still succeeds | A child-only ACL is not a reliable denied-read fixture |
| Owned parent denies listing and child denies read attributes | Read and read/write requests fail with 5 | Real getter denial fixture |
| Exclusive data handle | Attribute-only access still succeeds | Do not assume a data-sharing lock denies attribute requests |
| Missing path | Error 2 | FS notfound |
| Readonly directory removal | Error 5; succeeds after clearing readonly | Step 10 cleanup fix remains necessary |
| Unicode and extended 344-character path | Attribute updates/readback succeed | Use existing wide/extended path helpers |

Step 09 must additionally exercise Lua-only validation: wrong types,
nonboolean fields, unknown/numeric/embedded-NUL keys, inherited fields,
getter snapshot shape, empty/unchanged patches, and absence of partial
mutation on a rejected mixed patch. Real symlink cases stay conditional on
capability and must report an explicit skip if unavailable. Actual provider,
filesystem and ACL behavior remains the operating system's decision.

## Results and reproducibility

- GCC normal probe: **61 passed, 0 failed, 3 explicit symlink skips**.
- Clang AddressSanitizer + UndefinedBehaviorSanitizer probe: **61 passed,
  0 failed, the same 3 skips**, with no sanitizer diagnostics.
- Both compilers used `-Wall -Wextra -Werror`; no build warnings.
- Independent source/contract reviews checked link/ACL/error boundaries and
  corrected the initial child-only denied-read assumption. The first report
  is retained; it is superseded by the corrected fixture, not counted as a pass.
- Current kuu independently reproduced recursive removal failure on a readonly
  directory: `FS access`, native 5. Its child file had already been removed,
  while the root remained. This confirms Step 10's nontransactional cleanup
  contract. Clearing the owned directory's readonly bit allowed cleanup.

Evidence: [combined report and hashes](../build/step08-attributes-report.json),
[normal observations](../build/step08-attributes-probe.ndjson),
[sanitizer observations](../build/step08-attributes-probe-asan.ndjson),
[kuu cleanup reproduction](../build/step08-kuu-readonly.json),
[first probe](../build/step08-attributes-probe-first.ndjson),
[normal build log](../build/step08-attributes-build.log),
[sanitizer build log](../build/step08-attributes-asan-build.log).

Normal reproduction from the repository root (creates and retains a new owned
directory; no global compiler installation required):

```powershell
$env:PATH = (Resolve-Path '.tools/msys2/ucrt64/bin').Path + ';' + $env:PATH
& .tools/msys2/ucrt64/bin/gcc.exe -std=c11 -Wall -Wextra -Werror -O2 -municode `
    test/fixtures/attributes_probe.c -ladvapi32 -o build/attributes_probe.exe
if ($LASTEXITCODE -ne 0) { throw 'probe compilation failed' }
$probeRoot = Join-Path (Resolve-Path build).Path ('attributes-probe-' + [guid]::NewGuid().ToString('N'))
& .\build\attributes_probe.exe $probeRoot
if ($LASTEXITCODE -ne 0) { throw 'native contract probe failed' }
```

The sanitizer command substitutes `.tools/msys2/clang64/bin/clang.exe`, adds
that toolchain directory to PATH, uses `-g -O1 '-fsanitize=address,undefined'`
in place of `-O2`, and writes a separate executable/fixture.

Host: Windows 11 **25H2, build 26200.6899**, x64, unelevated, on the local
NTFS workspace. These are not independent Windows 11 23H2, SMB, ReFS or cloud
provider results. Symlink privilege/developer-mode settings were not changed.
The kuu runtime SHA-256 remains
`03e808952e60858ea233701d76d65e63be845e902e2e0b3654b75e3e2b5e5fd3`;
its focused regression suites from Step 07 remain applicable. This step adds
a standalone native fixture and design evidence, so no production rebuild,
manual regeneration or full runtime regression run is necessary.

The work began **2026-09-21 17:20:59 UTC** and took approximately **11 minutes**,
within the **10–20 minute** forecast. After reviewing the remaining scope,
Step 09 keeps its **40–75 minute** estimate: Lua validation/resource lifetime,
independent API integration tests, palette/manual updates and link failure
coverage still need implementation. Remaining Steps 09–21 total **5 h 35 min–
10 h 30 min** under the existing forecasts at Step 08 completion. Step 09 had
not started then; see its linked implementation report for the later result.

## Primary references checked

- [FILE_BASIC_INFO](https://learn.microsoft.com/en-us/windows/win32/api/winbase/ns-winbase-file_basic_info)
  and [native FILE_BASIC_INFORMATION](https://learn.microsoft.com/en-us/windows-hardware/drivers/ddi/wdm/ns-wdm-_file_basic_information): masks and timestamp meanings.
- [MS-FSA basic-information setter semantics](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-fsa/a36513b4-73c8-4888-ad29-8f3a196567e8): zero fields and directory TEMPORARY restriction.
- [CreateFile](https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-createfilea)
  and [access-right constants](https://learn.microsoft.com/en-us/windows/win32/fileio/file-access-rights-constants): rights, sharing and reparse selection.
- [MS-FSA access-check algorithm](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-fsa/82b364ce-6d7b-422f-8d88-4db32eea809a): parent-listing grant for child attribute reads.
- [Reparse operations](https://learn.microsoft.com/en-us/windows/win32/fileio/reparse-point-operations)
  and [name-surrogate tags](https://learn.microsoft.com/en-us/windows/win32/api/winnt/nf-winnt-isreparsetagnamesurrogate): nofollow selection and narrow link diagnosis.
- [CreateSymbolicLink](https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-createsymboliclinka): unprivileged-create option; unsupported privilege remains an explicit fixture limitation.
