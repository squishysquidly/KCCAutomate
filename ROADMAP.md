# KCCAutomate priorities

One improvement per build, with a review between builds. Original priority
numbers are noted where helpful; the current order is below.

1. **0.3.0 — Guided first-run setup: implemented.** Reader, local or remote
   folders, tool discovery, optional test conversion and opt-in scheduling.
2. **0.4.0 — Simple and Advanced views: implemented.** Persistent view selection,
   everyday controls, advanced sections and preservation of settings and drafts.
3. **0.5.0 — Duplicate handling: implemented (original priority 5).** Review,
   replace, keep both, or skip existing output; scoped queue retries; verified
   numbered output; clear conflicts for inputs targeting the same name.
4. **0.6.0 — Setup clarity and managed tool imports: implemented by request.**
   Clear folder/format labels, tool checklist, version/dependency guidance,
   ZIP/7z JXL import and verified tool copies inside KCCAutomate's storage.
   **0.6.1 refinement:** exact approved CLI download, verified bundled Python
   guidance, pinned KCC updates and version checks for scheduled conversions.
   Automatic default-folder creation, live tool checks, tested 7-Zip detection
   and KindleGen V2.0 banner/help compatibility are included in that refinement.
5. **Next — Tray controls (original priority 7).** Quick access to progress,
   stop-after-file and opening the app. Deliver as its own build.

After duplicate handling and tray controls, reassess potential improvements
before starting more work from the backlog.

## Deferred

- **Archive versioning (original priority 6): skip for now.** Existing archive
  merge behavior is retained. No archive-history feature is being built.
- **Sample-page visual preview (original priority 3): moved down.** Lower
  priority, after the active work and reassessment.
- **Network retries (original priority 4): bottom of the backlog.** Local drives
  are equally supported. A startup availability check for all four saved folders
  is included in 0.5.0; it reports inaccessible paths and provides a manual
  recheck. Automatic reconnection and retry controls are not currently planned.

Automated tests use disposable fixtures and converter doubles. Real converter,
network-credential and normal Windows installation checks remain manual
acceptance steps before publication.
