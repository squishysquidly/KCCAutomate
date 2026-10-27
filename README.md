# KCCAutomate

Automatically turn any comics or manga placed in the a watch folder into books for your e-reader,
then keep the original files in a separate folder.

**[Download the latest published version from Releases](https://github.com/squishysquidly/KCCAutomate/releases)**

Choose **KCCAutomate-Setup.exe** for installation, or **KCCAutomate-Windows.zip**
for the portable version. Open the release's **Assets** list to find them.
The repository's **Code → Download ZIP** is source code; use a release asset
when you want to run the app.

The current build is **0.1.19**, for **Windows**. Linux and macOS support are
planned. KCCAutomate uses [Kindle Comic Converter (KCC)](https://github.com/ciromattia/kcc)
for conversion; you obtain KCC and any required tools separately during setup.

**0.1.19 is the first update from 0.1.18.** It brings chapter/volume grouping,
clearer book and series-folder names, optional numbered covers, original-handling
choices and the application icon. See the [0.1.19 release overview](https://github.com/squishysquidly/KCCAutomate/blob/main/development/RELEASE-NOTES.md).

## Why use it?

KCCAutomate was created for my ease of use, but figured others would like it too. 
I have a kindle, which means no .cbz for me. KCC allows for conversion, but it's a very manual process.
I also have an RSS feed, among other methods, and download manga automatically.
So, now I have a incoming/watch folder the RSS feed places the manga, and now 
an app which automatically runs and converts into whatever format I need. So now, I have
kindle friendly manga I can delete when done but still have the original files stored.

It's the workflow which works for me, so hopefully it'll be helpful to someone else as well.

```text
RSS/downloader or manually added books
                 |
                 v
         Incoming/Watch folder
                 |
        scheduled conversion
                 |
        +--------+---------+
        v                  v
    Converted          Originals
  reader-ready books   original-format files
```

This also works for manually downloaded books, a shared family comic folder,
or a local/network library you process in batches. Folder structure is retained.

## Install and complete setup

1. Download a build from [Releases](https://github.com/squishysquidly/KCCAutomate/releases).
2. Run **KCCAutomate-Setup.exe**, or extract the entire portable ZIP and open
   **KCCAutomate.exe** inside it. Keep the portable files together.
3. Follow guided setup: choose your reader, output format and reading direction,
   then connect the tools you need.
4. Optionally test a small book. The test converts a copy, keeping your selected
   original and normal library folders unchanged. Inspect the result on your reader.
5. Choose automatic check times if wanted, review the folders and usage notes,
   then select **Finish & save**.

The installer installs for your Windows account under
`%LOCALAPPDATA%\Programs\KCCAutomate`. Installed settings and managed tools
are under `%LOCALAPPDATA%\KCCAutomate`. The portable version keeps its settings
and tools in its own `data` folder. Windows 11 is the current tested platform.

### Tools setup will explain

| Tool | When you need it | Where to get it |
| --- | --- | --- |
| **KCC command-line converter** | All conversions. The latest verified compatible version for this build is **12.0.0**. | [KCC releases](https://github.com/ciromattia/kcc/releases): find 12.0.0 and download `tool_cli_c2e_12.0.0_AMD64.exe`; renaming it to `kcc-c2e.exe` is also supported. |
| **KindleGen** | MOBI output, including any MOBI folder presets. | Install [Amazon Kindle Previewer](https://kdp.amazon.com/en_US/help/topic/G202131170), then let setup check its usual folders. An existing working `kindlegen.exe` is fine. [KCC's KindleGen guide](https://github.com/ciromattia/kcc/wiki/Installation#kindlegen) explains manual locations. |
| **JPEG XL decoder (`djxl.exe`)** | Comics containing JXL image pages, if JPEG XL support is enabled. | [Windows libjxl releases](https://github.com/libjxl/libjxl/releases). Setup accepts an extracted decoder or a Windows ZIP/7z package. |
| **7-Zip (`7z.exe`)** | Importing a .7z JXL tool package and some comic archive support. | [Official 7-Zip downloads](https://www.7-zip.org/). Setup first looks for and tests an existing installation. |

Use KCC's **c2e command-line** file, rather than `kcc.exe`, the graphical KCC
download, or `kcc-c2c.exe`. The verified standalone Windows CLI includes Python
and its Python libraries; you do not need to install Python separately for it.

KCC is downloaded by you from its GitHub releases page. Setup automatically
checks your selection and copies selected tools, their required companions
and licence material into KCCAutomate's storage. Original downloads are kept.
Green checks mean the tools passed their startup checks; trying a real book
is still the best way to verify your complete setup.

The KindleGen page checks likely Previewer folders automatically. If missing,
follow the Amazon link, install Previewer, then click **Press this after
installing**. If still missing, use the manual or illustrated instructions.

JXL packages are imported selectively: the decoder, companion libraries and
licences are kept, while extra utilities and sample images are skipped. This
can take a minute or two. **Continue** can also take time while tools are copied
and checked again. KindleGen and JXL pages are skipped when your choices do
not need them.

## Understand your folders

| Folder | What happens there |
| --- | --- |
| **Incoming/Watch** | Place completed original comics/manga here. Loose books and series subfolders are supported. |
| **Converted** | Reader-ready output appears here. Input subfolders are retained; Clean filename also shortens matching series folder names. |
| **Originals** | Original-format files move here after successful conversion and verification of their batch. |
| **Working** | Temporary conversion files, logs and completion records. |

Setup creates default book folders under **Documents\KCCAutomate** for an
installed app, or **data\Books** for a portable app. Existing saved locations
are retained. In **Folders & tools**, choose different local folders or UNC
network paths and click **Create & check folders**.

Keep all four folders separate; none may be inside another. Working can be
on the same network share as your books, so processing can stay there too.
The Windows account running the task needs access to the selected locations.

Originals is your retained source library. Matching archived filenames are
replaced during later successful batches; other archived files are kept.
Keep an independent backup if you need previous versions of those files.

Keeping originals is the default. In **Conversion → After successful conversion**,
you may instead select **Permanently delete converted originals** and acknowledge
the warning. This bypasses the Recycle Bin and leaves no original-format backup.
Only converted input files with verified output are removed, after their source
hashes are checked against the scan. A failed/incomplete batch stays in Incoming;
unconverted files such as notes and unsupported formats are always retained.
The Originals folder is unused in this mode. Preview never removes anything.

## Everyday use

Automatic Workflow:
1. Point your downloader to save completed books only to your Incoming/Watch folder.
2. Let the scheduler you setup run at it's scheduled time, or open the app and select **Run now**
4. Find reader-ready files in Converted and copy them to your e-reader.
5. Review the queue's attention items and **Activity** if anything fails.
   
Manual Workflow:
1. Add completed books to your Incoming/Watch folder manually.
2. Use **Preview queue** to inspect what will happen without converting or moving books.
3. Choose **Run now**, or let your enabled schedule run the scan.
4. Find reader-ready files in Converted and copy them to your e-reader.
5. Review the queue's attention items and **Activity** if anything fails.

By default, only **CBZ** input is selected. Advanced settings can also enable
**PDF, EPUB, CBR and CB7**. CBZ books are processed before PDFs. A top-level
series folder is treated as a batch: its originals move only after all selected
books in that batch are successfully processed. Failed/incomplete batches stay
in Incoming; other batches can continue. Unsupported files alone are skipped.

### Readable titles and cover numbers

Choose **Conversion → Book title and filename → Clean filename (keep v/ch numbering)**
to remove leading square-bracketed release tags, keep the title through its
volume/chapter number and remove trailing release information. For example:

```text
The Hero and the Sage, Reincarnated and Engaged v01 (Digital-Compilation) (Square Enix) (DigitalMangaFan).cbz
→ The Hero and the Sage, Reincarnated and Engaged v01.mobi

[sunshine] Rainbows v1 [truth].cbz
→ Rainbows v1.mobi
```

The generated filename and embedded book title both use the clean name. Compact
`v01`/`ch001`, `Vol. 1`/`Ch. 1` and `Volume 1`/`Chapter 1` markers are supported,
including fractional chapters and ranges. Existing ranges such as `v01-02` keep
both numbers and convert separately. Multiple leading tags such as `[Group] [EN]`
are removed too. Brackets within a title and leading parentheses are preserved.
Without a clear v/ch marker, only complete leading bracketed tags are removed;
the remaining name is kept. An all-tag name is preserved to avoid an empty title.
Two releases cleaning to the same name are flagged for review.

If a CBZ is named only `v1`, `Vol. 2`, `ch001` or another supported number marker,
Clean filename adds the immediate containing series folder's title. For example:

```text
Artist/First Series/v1.cbz → Artist/First Series/First Series v1.mobi
Artist/Second Series/v1.cbz → Artist/Second Series/Second Series v1.mobi
```

This also works with CBZ output. Series-first and Number-first use the inferred
series title in their own numbering styles. Saved shortened names still apply,
and chapter/whole-volume grouping stays separate for each series folder. The
series folder takes priority over conflicting series metadata for these files;
a title already present in the filename takes priority over the folder. Leading
tags and recognized release suffixes are removed from an inferred folder title.
Artist/collection folders above it are retained. A loose `v1.cbz` in the watch
folder keeps its name; the app does not guess a series from the watch folder or
search upwards past an uninformative immediate parent. Original CBZ filenames
and archived folder names remain unchanged.

With Clean filename selected, matching series folders in Converted also use just
the series title. For example, `Series (Digital) (Publisher)/Series v01 (Digital).cbz`
becomes `Series/Series v01.mobi`. Leading `[release tags]` on matching series
folders are removed too. Saved shortened series names apply to the folder
as well as the book. Other parent/subfolders are retained; an unclear series match
keeps its existing folder name. This applies to new conversions, including grouped
chapters/volumes. Previously converted folders are not renamed automatically.
Originals retain their downloaded folder names.

These markers also determine grouping: `v` means volume and `ch` means chapter,
even if the page count suggests otherwise. An explicit volume marker takes
priority when a volume filename also lists internal chapter details. The title
and number in a marked filename take priority over conflicting ComicInfo values;
metadata and page-count inference remain available for names without a marker.
An individual unit above its grouping page target converts separately.
The existing **Keep original names** preference remains unchanged. Originals
retain their downloaded filenames and contents when archived.

In **Conversion**, choose **Series, then number** to keep a series together when
sorting by Title, or **Number, then series** to show the order before a long title.
Both the filename and embedded title are set during conversion. Number-first
sorting mixes different series under 001, 002, and so on; it does not create a
Kindle collection. Chapter navigation and reading direction are kept.

Under **Shorten really long series names (optional)**, enter the series title in
**Original long name** and your preferred shorter title in **Shortened name**.
Use the title without volume/chapter numbers or publisher/release tags. Leave the
two boxes empty if unused. **Add another series** adds another pair, and **Remove**
removes an extra pair. Saved pairs are loaded automatically. A cover-number option adds a contrasting
number strip above the cover artwork, preserving its proportions. Unsupported
cover-image codecs fall back to the original cover with a warning. The Kindle's
firmware still controls library thumbnail display. Existing books on the device
are not renamed or replaced automatically.

### Combine short chapters into longer books

In **Conversion**, enable **Combine short CBZ chapters into volume-sized books**.
Grouping is off by default, so existing settings keep their previous behavior.

- The starting target is **200 source pages**. The app stops before adding a
  chapter that would exceed the target; chapters are never cut to fill a book.
- Files with **100 or more source pages**, and filenames labelled Vol./Volume,
  stay separate. These adjustable thresholds are useful estimates, not a rule
  about every manga. A source image counts as one page before spread splitting.
- A **350 MiB converted-output budget** provides a second limit. If KCC splits
  a proposed bundle or its output exceeds the budget, the app retries with fewer
  whole chapters. A single chapter that cannot fit stays in Incoming with an
  explanation. This budget is not a claimed Kindle hardware maximum.
- Chapter numbers come from ComicInfo metadata or names such as `Series Ch. 001`.
  The app groups only the same series, folder and effective conversion settings.
  Duplicate numbers need attention; unclear numbers and short groups around
  missing chapters wait rather than guessing the order. Loose files with clear
  series/chapter names are supported too.
- Short leftover groups convert on each scan by default. Enable **Keep short
  leftover groups in Incoming** if you prefer to wait for more chapters instead.
  A folder containing pending chapters
  stays in Incoming until every selected input has verified output.

For example, four 60-page chapters create a 180-page book containing chapters
001-003 and a 60-page book containing chapter 004. With waiting enabled, chapter
004 stays for the next group instead. New arrivals never append to an
already published bundle. Changing grouping targets affects unconverted inputs;
changing image/conversion settings can require conversion again.

Bundles receive names and embedded titles such as **Series - Ch. 001-003**.
They are convenient reading groups and may not match official published volumes.
The first chapter supplies the cover: its ComicInfo FrontCover marker is used
when available, otherwise its first naturally sorted image. JPEG XL preparation
remains supported. Original CBZs retain their individual names and contents.
Use **Preview queue** to review group names and waiting reasons before running.

**Combine complete CBZ volumes** is a separate option, off by default. Its starting
page target is 600. For example, three 180-page volumes and a 500-page target
create one book containing volumes 001-002 (360 pages), then a separate volume 003.
If KCC would split a combined book, the app retries after removing the last whole
volume. Chapters and volumes never share a group. Unnumbered volumes and volumes
larger than the grouping page target convert separately. Previously published
groups remain stable; the app does not consolidate books already on your Kindle.

On a Kindle Scribe, create one **Collection** per series and add its converted
books, then open that collection and sort by Title. USB subfolders do not create
Kindle collections automatically. See [Amazon's Scribe guide](https://d1ergij2b6wmg5.cloudfront.net/kug/kindle_scribe_2024/v1/en-US/html/kug.html).
Cover images shown in the Kindle library still need testing on the actual reader;
see [KCC's cover guidance](https://github.com/ciromattia/kcc/wiki/Automatic-cover-upload).

### Automatic conversion while the app is closed

In **Schedule**, choose daily times and click **Save & enable schedule**.
Defaults are **08:00, 14:00 and 20:00**, with a **30-minute quiet period** after
files were last modified. Saving general settings alone does not update the
Windows task's check times; use the schedule action to apply changed times.

Windows runs the checks even when KCCAutomate is closed. Your account must
remain signed in; a locked screen is fine. The computer must be on and awake,
and the folders must be reachable. The wake option asks Windows to wake a
sleeping computer. A powered-off computer cannot run conversions.

Use **Disable schedule** to turn the task off. Reopening guided setup
without enabling a new schedule leaves an existing schedule unchanged.
For a portable installation, disable its schedule before moving the app folder,
then enable it again from the new location.

## Features and settings

**Simple view** contains everyday controls. **Advanced view** exposes additional
options without discarding values that are hidden in Simple view. Save changes
when you want future scheduled runs to use them.

| Feature | What you can customize |
| --- | --- |
| **Reader and output** | Device profile; MOBI (AZW3/Kindle compatible), EPUB, CBZ or PDF output. MOBI requires a compatible Kindle profile. |
| **Image options** | Right-to-left manga reading, page enlargement, spread handling, cropping, stretching, gamma, autolevel, contrast, colour, PNG and webtoon options. |
| **JPEG XL support** | Prepare JXL pages as PNG for conversion while keeping original archives unchanged. |
| **Chapter grouping** | Optional volume-sized CBZ bundles, source-page/chapter thresholds, converted-size budget and waiting/releasing short leftovers. |
| **Whole-volume grouping** | A separate page target; complete numbered volumes only, with shorter leftovers converted on each scan by default. |
| **Readable book labels** | Series-first or number-first embedded titles and filenames, short series aliases and optional cover-number strips. |
| **Original handling** | Keep originals in Originals by default, or acknowledge permanent deletion after verified conversion. Unconverted files remain in Incoming in deletion mode. |
| **Input formats** | Choose which file types a scan should process. |
| **Presets** | Save, apply, import or export conversion settings. Folder/tool locations remain separate. |
| **Folder rules** | Apply a named preset to matching relative paths, such as `Series A\*`. The first matching rule wins. |
| **Output naming** | Use a filename template with `{name}`, `{profile}` and `{format}`. |
| **Existing converted files** | Review conflicts, replace, keep both using numbered names, or skip while retaining Incoming originals. Selected retries can use a one-run choice. |
| **Queue and retries** | Inspect waiting, completed, failed and conflicting items; retry selected books after resolving a problem. |
| **Temporary-file cleanup** | Optionally remove old attempts. Default retention is 7 days for successful attempts and 30 for failed ones; originals and converted books are retained. |
| **Appearance and notifications** | Light/dark themes; notifications off, errors only or every check; optional quiet hours. |

For the detailed meaning of **KCC-specific image settings, profiles and output
formats**, use [KCC's documentation](https://github.com/ciromattia/kcc), its
[device profiles](https://github.com/ciromattia/kcc#profiles), and its
[command-line option reference](https://github.com/ciromattia/kcc#standalone-kcc-c2epy-usage).
Options depend on the KCC version; this app checks compatibility against its
verified version rather than automatically accepting a newer KCC release.

The initial manga settings use right-to-left reading, enlargement, no cropping,
and splitting of double-page spreads, with stretching and autolevel off. Change
these for your own books and inspect a sample before processing a large library.

**Stop after this file** requests a stop between conversion operations. It
allows the current file to finish and keeps pending originals in place.

## Updates

Use **Settings & updates → Check GitHub for updates**. App and JXL downloads
can be verified and applied through the app. KCC uses **Open KCC releases**;
download the verified compatible CLI yourself, then **Choose downloaded KCC**
to run guided setup with it. Your tools are not bundled in KCCAutomate releases.

The default app update source is this repository's published GitHub releases.
Pushing source changes alone does not publish an app update. Update backups
allow restoration of the previous app version.

## Troubleshooting

- **Nothing converted:** preview the queue; check selected input formats and
  whether files are still within the quiet period. Check folder access and the
  actual enabled schedule. Waiting books are checked on a later scan.
- **KCC fails its startup check:** choose the verified **12.0.0 c2e** Windows
  file from [KCC releases](https://github.com/ciromattia/kcc/releases). A missing
  Python module in a packaged converter calls for the correct CLI package.
- **KindleGen is missing:** install Previewer, use the post-install button,
  then the illustrated instructions or select your existing working compiler.
- **JXL tools take time:** allow the stated preparation/copy checks to finish.
  Keep DLLs and other companion files beside a manually selected decoder.
- **A local/network folder is unavailable:** open it in File Explorer using
  the same Windows account. Correct the path or permissions, then use the app's
  folder check. Choose separate folders rather than a drive/share root.
- **An existing book blocks conversion:** review the conflict and select the
  desired duplicate policy. Converted-output choices are separate from archive
  merging in Originals.
- **A book fails:** its original stays in Incoming. Read Activity and the
  relevant Working-folder logs, correct the cause, then retry it. Conversion
  failures do not silently archive unverified originals.

For workflow/app issues, [open a KCCAutomate issue](https://github.com/squishysquidly/KCCAutomate/issues).
For conversion-specific options and troubleshooting, start with
[KCC's repository and guides](https://github.com/ciromattia/kcc).

## Build from source

Most users only need a [release download](https://github.com/squishysquidly/KCCAutomate/releases).
If you want to compile or contribute, see the [development guide](https://github.com/squishysquidly/KCCAutomate/blob/main/development/README.md).
Build scripts, tests, installer source, release instructions and planning notes
live in `development/`; application source and runtime scripts live in `app/`.

## Credits and licence

KCCAutomate is by [squishysquidly](https://github.com/squishysquidly). It is an
independent automation app using [KCC](https://github.com/ciromattia/kcc), whose
conversion work makes this workflow possible. Credit belongs to Ciro Mattia
Gonano, Paweł Jastrzębski, Darodi, Alex Xu and the KCC contributors for their work.
KindleGen/Previewer, libjxl and 7-Zip remain their respective authors' tools.

KCCAutomate uses the **ISC licence**. [license.txt](license.txt) contains
the KCCAutomate copyright line together with the preserved KCC copyright and
permission notices. Third-party tools retain their own licences.
