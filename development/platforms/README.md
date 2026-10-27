# Platform inventory

The machine-readable [inventory](inventory.v1.json) contains exactly the seven
KCC target families in the agreed plan. [Pinned evidence](kcc-12.0.0-evidence.json)
records the upstream 12.0.0 source commit, exact release asset URLs/SHA-256
digests and build-recipe source hashes reviewed on 2026-10-24. These are public
metadata/build-definition observations; no new native KCC binary was executed.

Only the existing Windows AMD64 approval policy remains active in the app.
Other rows are candidates, not approved converters. Even the existing Windows
row has no new formal native certification record: current user experience and
offline fixtures are distinct from a documented OS/CPU acceptance run.

| Target | Observed upstream build inputs | Still needs native evidence |
| --- | --- | --- |
| Linux x86_64 | Linux matrix has x86_64; Python/Qt are distribution packages rather than locked runtime versions. | CLI entry point; ELF/libc/CPU floor; helpers; actual output. First priority. |
| Linux aarch64 | Same Linux recipe, aarch64 runner/build. | Native ARM CLI/helpers, loader baseline and outputs. |
| Windows x86_64 | Modern Windows recipe selects Python 3.11; approved c2e AMD64 asset is recorded. | Full native certification of OS/prerequisites/helpers and actual outputs. |
| Windows ARM64 | Same modern recipe has Windows ARM runner and separate ARM64 c2e asset. | Native CLI/helpers and installer/scheduler acceptance; no inherited x64 approval. |
| macOS Intel | Modern recipe targets 14.0; another legacy recipe targets 10.14 with Python 3.11.9 and separate requirements. | Actual DMG Mach-O architecture/minimum OS; legacy recipe alone does not establish the asset's floor. |
| macOS ARM64 | Modern macOS recipe includes the ARM runner; deployment target is 14.0 in the inspected source. | Actual bundled runtime/OS floor; c2e and compiler requirements, including any translation. |
| Windows 7 legacy | Separate recipe selects Python 3.8 and legacy requirements; GUI release asset has no CPU suffix. | PE architecture, usable legacy CLI path, helpers and complete Windows 7 SP1 tests. |

Recipes include mutable/unpinned package inputs. A recipe setting is not proof
of the exact dependencies inside a released binary. Before approval, inspect
the downloaded binaries and record their real minimum OS/runtime requirements.
Do not infer 32-bit Linux from x86 or 32-bit macOS from an i386 filename.

For each candidate, fill certification fields only after maintaining evidence:
nativeVerified, minimumOs, Linux libc/loader baseline where applicable, exact
CLI argv, helperVersions, testedFormats and links to native test reports.
Keep failure/blocker information when a candidate does not pass. Do not let an
upstream release automatically overwrite the app's converter policy.

The next implementation stage is the Linux x86_64 worker. Resolve an actual
approved c2e invocation before building a UI around an assumed AppImage CLI.
Windows 7 findings are tracked in the [audit](WINDOWS7-AUDIT.md).
