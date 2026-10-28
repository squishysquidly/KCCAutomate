# Shared worker contract v1

This is the phase-one foundation for native workers. The installed Windows app
still uses its existing C#/PowerShell path. `app/shared/contracts.py` contains
the executable reference validators and a pure settings importer, using only
Python's standard library and Python 3.8-compatible syntax. It executes no tools,
registers no tasks, and writes no settings. No Linux worker is shipped yet.

## Versioning and settings

`schemaVersion: 1` versions the settings and receipt objects. `protocolVersion: 1`
versions the request/event exchange. These are independent of KCCAutomate's app
version and the selected KCC version. Reject unknown major schema versions and unknown
operational fields rather than silently discarding them. Extension/preferences
data belongs in `extensions`; it must never become executable worker options.

The complete settings example is [settings-v1.example.json](examples/settings-v1.example.json).
Its required sections are:

| Section | Meaning |
| --- | --- |
| `targetId` | One exact target from the upstream-bounded platform inventory; membership does not mean native certification. |
| `folders` | Native absolute `incoming`, `converted`, `originals`, `working` paths, all separate and non-nested. |
| `tools` | `kcc`, `djxl`, `kindlegen`, `sevenZip`: null when unconfigured, otherwise a full `program` path and `prefixArgs` array. |
| `conversion` | The existing reader/image options, retaining their current names and values. |
| `workflow` | Input formats, quiet period, duplicate action, output naming, JXL and cleanup retention. |
| `folderRules` | Ordered, first-match rules containing Pattern, PatternSyntax, PresetName and Options snapshots. |
| `schedule` | Daily HH:mm Times, WakeComputer and `Activation: manual`; this is a requested configuration, not proof that a task is installed. |
| `extensions` | Preserved non-operational data, including the original Windows settings object during import. |

The optional boolean `conversion.ScribeCompatibility` defaults to false. When
enabled for KS with MOBI/EPUB, effective conversion uses KS1860, cropping 0
and JPEG instead of forced PNG; the stored image choices remain unchanged.
The same optional field is allowed in folder-rule Options. Item state
`stopped` maps to Windows `Stopped` and remains eligible for retry.

An optional `bundling` object adds enabled, targetSourcePages,
chapterPageThreshold, maxOutputMiB and holdShortGroups. Absence means grouping
is off. Defaults are false, 200, 100, 350 and false respectively. Source pages
are counted before spread splitting. This is volume-sized chapter grouping,
not an assertion of official published volume boundaries. Maximum output size
is an application budget, not a certified device limit. Existing published
groups remain frozen as new chapters arrive or grouping targets change.
Optional combineVolumes (false) and volumeTargetSourcePages (600) extend this
object for whole-volume grouping. Groups never mix chapters with volumes, cut
a unit, or guess ambiguous volume ranges. Remainders are converted each scan
unless the user explicitly holds them. These source-page budgets are separate
from the converted-byte limit.

An optional organization object contains titleStyle (Original, SeriesFirst,
NumberFirst or Clean), coverNumberBadge (false) and seriesAliases (original-to-short-name
mapping). NumberFirst affects Title sorting across all series; thumbnail
appearance still depends on reader firmware. Cover art is placed below a new
number strip without rewriting originals.

Clean retains a marked filename through its v/ch number (including an existing
range) and discards trailing release information. Explicit filename volume/chapter
markers and their title/number take priority over inferred page-count types and
conflicting metadata. Without a marker, existing metadata/page inference applies.
Implementations must preserve this behavior or explicitly reject the active option.

An optional originalHandling object contains action (Archive by default, or
Delete) and deleteConfirmed (false). Delete requires an actual true boolean,
verifies source/output hashes immediately before removing converted inputs,
and preserves unselected files. The unused originals path may be empty in
Delete mode. Archive requires all four separate locations as before. Preview
never removes files. The importer preserves these optional Windows preferences.
Future platform adapters must implement active options or reject them
explicitly; accepting them while silently using other behavior is invalid.

Tool prefixes support an interpreter/script or documented launcher without
constructing a shell command. An argument array is mandatory. The future
execution adapter must independently approve the actual tool, version and target;
a valid path or successful contract validation does not grant that approval.

Keep defaults identical to the current app: KS, MOBI, manga reading/enlargement
on, cropping 0, splitter 0, stretching/autolevel off, JXL preparation on,
CBZ-only input, Review duplicate policy, 30-minute quiet period and daily
08:00/14:00/20:00 checks. Gamma 0 means no explicit gamma argument.

Successful scratch cleanup is always enabled after published-output verification,
independently of `AutoCleanup`. That existing preference controls optional expiry
of successful logs/compact attempt markers and unsuccessful attempts, using
`SuccessRetentionDays` and `FailureRetentionDays`. Completion receipts are kept.

`import_windows_settings` returns a new object. It preserves unknown preferences,
does not mutate the supplied object, retains paths verbatim, maps the older
OverwriteConverted preference when DuplicateAction is absent, and requires
review of unsupported versions or rule options. Preserve backtick escaping and
case-insensitive Windows `-like` matching under `powershell-like-v1`; do not
silently reinterpret existing rules with Python fnmatch. New `glob-v1` rules
match the entire slash-separated logical path using `*`, `?` and character
classes, case-sensitively; `*` can cross a slash. Rule order remains first-match.
The next worker must implement both modes before accepting imported rules.

The future filesystem migration must validate this returned object, keep a
recoverable copy of the old files, and require an explicit user action before
writing configuration or activating a schedule. Import alone has no side effects.

## Requests and results

See [request-v1.example.json](examples/request-v1.example.json) and
[events-v1.example.json](examples/events-v1.example.json). The worker entry
point will accept `--request <UTF-8 JSON file>`; the command is inside that file.
There is no arbitrary shell-command field. Required request fields are
protocolVersion, requestId, command and the complete settings object.

| Command | Required behavior |
| --- | --- |
| `preview` | Read queue/library state without conversion, directory creation, archival, receipt changes or schedule changes. Return items through events. |
| `run` | Process eligible books; an absent selection means the normal scan. |
| `check-tools` | Report the required tool and folder readiness, distinguishing startup checks from an actual conversion test. |
| `cleanup` | Apply configured attempt retention; never remove originals, converted books or receipts. |
| `stop` | Require the owned runId and request a cooperative stop after the active operation. Never accept a PID to kill an unrelated process. |

An explicit selection is allowed only on run: nonempty relativePaths and an
optional duplicateActionOverride. Paths are logical Incoming-relative paths
using forward slashes. Reject absolute paths, parent traversal and empty
selections. A one-run override never changes saved policy. Resolve selected
paths against the real Incoming directory before touching files.

Stdout is UTF-8 JSON Lines: one complete event per line, with protocolVersion,
requestId, runId, sequence (starting at 1), timestampUtc, type and data. The
currently specified event types are item, progress and result. Item states
are machine-readable codes from ITEM_STATES; UI labels and translations remain
outside the worker contract. Converter text/diagnostics go to stderr/logs,
never into stdout as unframed text.

A completed exchange has exactly one terminal result as its last event. Its
status and process exit code must agree:

| Status | Exit code |
| --- | --- |
| completed | 0 |
| failed (including unresolved output conflicts) | 1 |
| stopped cooperatively | 2 |
| busy / lock held | 3 |
| rejected request/settings/version | 4 |
| tools-unready (whole-command prerequisite failure) | 5 |

Per-book missing tools during a scan can produce failed items while other
eligible books continue. Waiting or deliberately skipped items do not alone
make the scan fail. A lost process with no valid terminal result is an
interrupted exchange, not success. Status counts describe outcomes, and
converted/archived counts can overlap for a book completed during that run.

The current PowerShell worker still returns its own legacy codes and prints
`@@MF:` records. Do not change it merely to satisfy the new protocol. A future
bridge must retain its raw exit code/diagnostics while normalizing results;
the replay corpus records windowsExitCode and workerExitCode separately.

## Receipts and path boundaries

The new [receipt example](examples/receipt-v1.example.json) identifies the
source by logical relative path, size and SHA-256, includes an
effectiveSettingsSha256, and lists every nonempty output with relative path,
size and SHA-256. The worker computes the settings digest over canonical JSON
of the effective conversion/workflow options, including the selected rule and
preprocessing version. Do not include schedule/UI preferences or assume hosts
can derive the same digest from their own numeric serialization.

A structurally valid receipt is not sufficient to archive a source: verify
source identity, all outputs, effective options and the batch snapshot against
the actual filesystem. Preserve existing Windows receipt files; an adapter
must revalidate them or request conversion rather than blindly promoting old
arrays into trusted new receipts. Publish a receipt only after output hashes
match. Originals move only after every selected input in the batch is complete.

Lexical validation is deliberately filesystem-independent. Before mutation,
the actual worker must resolve symlinks/reparse points, detect aliases and
volume-specific case rules, check access, acquire a real lock, and verify
containment again. POSIX paths refer to mounted shares, not raw Windows UNC
paths. Do not lowercase physical POSIX paths. Cross-volume archival must copy,
verify, recheck the source snapshot and only then remove the source.

## Reusable behavior corpus

[behavior-v1.json](behavior-v1.json) contains language-neutral fixture recipes,
settings, operations and expected outcomes. Paths inside a scenario use `/`;
the adapter materializes them under a unique disposable root. CBZ recipes
contain a tiny dummy image entry; fake converters test orchestration, not
ebook validity, rendering or native platform readiness.

`Test-BehaviorParity.ps1` runs the real current Windows worker against fifteen
scenarios and sixteen runs: format order/archive merges, partial failure and
receipt retry, Review, KeepBoth, Skip, read-only preview, quiet period, empty
selection, missing JXL decoder, multipart review, stop-before-run, unsupported
formats, a zero converter exit with no output, first-match folder rules/naming,
and multiple inputs targeting one output. Assertions check final trees,
queue states, converter order, and source/existing-file hashes. Future Linux
adapters must consume this same corpus and its canonical workerExitCode values.

Run `Test-PlatformFoundation.ps1` for validators/import/inventory tests and
`Test-BehaviorParity.ps1` on Windows for the replay. Neither test accesses a real
book folder, creates an actual scheduled task, downloads KCC, or certifies an OS.
