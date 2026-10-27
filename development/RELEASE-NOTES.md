# KCCAutomate 0.1.19

The first update from **0.1.18**, bringing the current book-organization and
application improvements together in one release.

## Organize books for your reader

- Optionally combine short CBZ chapters or complete volumes into fewer books,
  with configurable page targets and a converted-size budget. Units stay whole,
  and short leftovers can convert on the current scan.
- Create readable filenames and embedded book titles using v/ch numbering,
  removing leading square-bracketed tags and trailing release information.
- Shorten matching series folders in Converted, and define optional short series
  names with paired original/shortened-name fields.
- Use the containing series folder for inputs named only v1, v2 or ch001,
  retaining artist/collection folders above each series.
- Add an optional chapter/volume number strip above the cover artwork, and
  choose series-first or number-first titles for easier library sorting.
- Detect naming collisions before conversion, including when different releases
  shorten to the same filename or folder.

## Original handling and application polish

- Moving verified originals to Originals remains the default. Users can instead
  explicitly acknowledge permanent removal after conversion verification;
  failed, skipped and unconverted inputs are retained.
- The supplied transparent artwork is embedded in the application, setup,
  uninstaller and shortcuts. Targeted Windows icon refreshes help replaced
  executables display the current artwork.
- Existing Simple/Advanced views, guided tool setup, saved settings, scheduling,
  duplicate policies and local/network folder support remain available.

## Installation and compatibility

Download **KCCAutomate-Setup.exe** for installation, or extract
**KCCAutomate-Windows.zip** for portable use, from the
[GitHub releases page](https://github.com/squishysquidly/KCCAutomate/releases).
Both downloads are listed in **SHA256SUMS**.

Updates from 0.1.18 preserve the established runtime file set, settings and
installation mode. KCC and its dependencies remain separately obtained tools;
the currently verified KCC CLI is **12.0.0**. The Windows build has not gained
Linux, macOS or Windows 7 certification. The shared platform foundation is in
place; the next platform implementation is the Linux x86_64 conversion worker.

See the [user guide](../README.md) for installation, usage and settings, and the
[current status](ROADMAP.md) for remaining validation and planned work.
