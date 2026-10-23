# Manga conversion setup

For the new desktop app, use [README.md](README.md). The steps below describe
running the standalone script and configuring Task Scheduler manually.

The script uses KCC with exactly these arguments:

```text
--profile KS --format MOBI --manga-style --upscale --cropping 0 --splitter 0 --tempdir
```

## Install and check KCC

Install the Windows **c2e command-line build**, not only the graphical application,
in `C:\kindletomanga`. The script defaults to `C:\kindletomanga\kcc-c2e.exe`.
If the downloaded executable has a version in its name, rename it to
`kcc-c2e.exe`, or supply its actual path using `-KccExe`.
Keep any companion files supplied with the build. Make sure KindleGen is
available to this installation (normally supplied via Kindle Previewer).
Run the executable with `--help` to confirm your installed version accepts
the options above. Version 12.0.0 is the known working fallback reported for
this workflow; the v12.1.1 c2e build reported a missing PySide6 module. The
packaged Windows executable bundles Python, so a separate Python installation
does not repair missing modules inside that bundle. Test representative books
with any version before enabling automation.

## JPEG XL pages inside CBZs

Download `jxl-x64-windows-static.zip` from the official
[libjxl releases](https://github.com/libjxl/libjxl/releases).
Extract the tools, keeping any supplied companion files together. Place the
decoder at `C:\Program Files\KindleComicConverter\jxl\djxl.exe`, or supply
`-DjxlExe` with its actual location. Test it with `--help` first.

CBZs without `.jxl` entries pass through normally. Others are rebuilt in the
network attempt folder, with JXL pages decoded to PNG using `djxl`. Page paths,
other files, and ComicInfo.xml are retained; the source archive is untouched.
Decoder errors or duplicate page names stop the batch. PNG headers and decoder
exit codes are checked; test representative output on the Kindle too.
Prepared CBZs and page scratch files remain with attempt files for diagnosis.
This uses extra network space and time. The scheduler command does not change.

This update uses new completion receipts, so previously processed inputs are
rechecked. Existing differing MOBIs still trigger the normal collision error;
move a known incomplete output aside before reconverting it.

## Network layout

- Input: `\\192.168.7.223\mirror\manga_downloaded`
- Converted: `\\192.168.7.223\mirror\manga_kindle`
- Archived originals: `\\192.168.7.223\mirror\manga_sorted`
- Working files, logs, and completion receipts: `\\192.168.7.223\mirror\manga_automation_work`

Nested folders are preserved. Loose CBZs are also supported. A top-level
folder moves to the archive only when every CBZ inside it has converted.
Other files within that folder move with the originals. Loose non-CBZ files
and folders with no CBZs are left alone. Existing archive folders are merged:
matching files are overwritten, new files and folders are added, and archive-only
files are retained. All archive copies are hash-verified before removing the
incoming batch. File-versus-folder conflicts stop archival and retain the source.
Existing unrelated converted outputs are never overwritten.

The wrapper stages generated MOBIs on the share.
The converter receives a short output filename (`book.mobi`) to avoid passing
long manga titles to KindleGen. Published MOBIs regain the original CBZ stem,
including any suffix KCC adds for split output files.

KCC's `--tempdir` creates
its main extraction workspace beside the source, also on the share. Temporary
folders beginning `KCC-` at the input root are excluded. Do not name manga
folders with that prefix. External tools may independently use Windows temp.

Prefer downloading outside Incoming and moving completed batches into it.
The script skips batches containing recognized partial files or files modified
within 30 minutes and probes for open files. This is a safeguard, not proof
that a paused download is complete. Do not modify a batch during conversion.
On a failed batch, inspect `automation.log` and its job's `kcc.log`.
Valid receipts let retries skip already verified conversions. Failed attempts
and successful staging files are retained; they consume share space. Remove
old attempt subfolders only after verifying the resulting books; retain receipts.

## First test

Keep this script in a stable local folder. Open PowerShell and run:

```powershell
& 'C:\Users\Squishy\Documents\GitHub\KCCAutomate\Convert-Manga.ps1' -Preview
```

Preview only reads the input folder. Then test with copies of a small manga
batch, ideally while no other batches are in Incoming. A normal run processes
all eligible input, including moving originals:

```powershell
& 'C:\Users\Squishy\Documents\GitHub\KCCAutomate\Convert-Manga.ps1'
```

Check the MOBIs on the Scribe before relying on the workflow. Exit status and
hash checks establish successful production and transfer, not visual correctness.

## Task Scheduler

1. Open Task Scheduler and choose **Create Task**. Name it **Convert manga**.
2. Choose your Windows account with read/write access to the share. Select
   **Run whether user is logged on or not**. Leave **Do not store password**
   and **Run with highest privileges** unchecked. Save using your account
   password, not the Windows Hello PIN. Ensure the same account can access
   the share noninteractively; a drive letter or an interactive Explorer login
   alone is insufficient.
3. Add three daily triggers: **8:00 AM**, **2:00 PM**, and **8:00 PM**.
4. Add **Start a program**:

   Program:
   `C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe`

   Arguments:
   `-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "C:\Users\Squishy\Documents\GitHub\KCCAutomate\Convert-Manga.ps1"`

   Start in:
   `C:\Users\Squishy\Documents\GitHub\KCCAutomate`

5. Enable **Run task as soon as possible after a scheduled start is missed**.
   Set the existing-instance rule to **Do not start a new instance**. Optionally
   enable waking from sleep and adjust battery conditions. The PC must be on,
   and the share reachable. Review the task time limit for very large batches.
6. Run the saved task manually and inspect the network log. Test while signed
   out as well before considering unattended access verified.

The execution-policy bypass applies only to that PowerShell process and does
not change the machine's permanent policy. Organization policy may take priority.
These manual steps are for the standalone script. In the desktop app, scheduling
is installed only when explicitly enabled in guided setup or Schedule.
