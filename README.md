# icloud

CLI tool for managing iCloud Drive files on macOS.

Apple removed `brctl download` and `brctl evict` in macOS Sonoma 14+, and `fileproviderctl materialize` in 14.4. No replacement shipped. This tool fills the gap using Foundation APIs that still work from unsigned binaries — no entitlements, no code signing, no sandbox.

## Why

- **rsync deadlocks** on dataless (cloud-only) files: `mmap: Resource deadlock avoided`. You need to download first.
- **No CLI to batch-download** a directory before going offline.
- **No CLI to see** what's local vs cloud-only, or what's eating disk.
- **No CLI to evict** files and free space.
- **"Keep Downloaded" (pin)** is Finder-only — no CLI equivalent existed until now.

## Install

### Homebrew

```bash
brew tap icanhasjonas/tap
brew install icloud-tools
```

### From source

```bash
git clone https://github.com/icanhasjonas/icloud-tools.git
cd icloud-tools
swift build -c release
cp .build/release/icloud ~/.local/bin/
```

Requires macOS 14+ and Swift 6.0+.

## Usage

### Status

Show iCloud status for files. Defaults to cwd if inside iCloud Drive, otherwise the iCloud Drive root.

```bash
icloud status                    # cwd or iCloud Drive root
icloud status ~/Desktop          # specific directory
icloud status -r Documents/      # recursive
icloud status --cloud            # only cloud-only files
icloud status --local            # only local files
icloud status --sort size        # sort by size
icloud status --json             # JSON output
icloud status -v                 # verbose (show resolved paths)
```

Output uses ANSI colors: green = local, dim = cloud/dir, yellow = syncing, cyan P = pinned.

Symlinked paths (e.g. `~/.icloud -> ~/Library/Mobile Documents/com~apple~CloudDocs/`) are resolved automatically and display paths preserve the symlink prefix you passed in.

### Move

Move files with download-first semantics. Dataless files are downloaded before moving, preventing the rsync mmap deadlock.

```bash
icloud mv file.pdf ~/Desktop/             # move single file
icloud mv a.pdf b.pdf dest/               # move multiple into directory
icloud mv -v dir/ dest/                   # verbose with per-file progress
icloud mv -f src.pdf existing.pdf         # force overwrite (atomic backup+restore)
icloud mv -n src.pdf existing.pdf         # skip if exists (no-clobber)
icloud mv -d src.pdf dest/                # dry-run preview
icloud mv -j 5 big-dir/ dest/             # 5 concurrent downloads (default 3)
icloud mv -t 300 huge.zip dest/           # raise baseline timeout to 5 min
icloud mv --json a b dest/ | jq -s .      # NDJSON -> array
```

**Force semantics (`-f`)**: the existing destination file is moved to a hidden backup, then the operation runs. On success, backup is removed. On failure, backup is restored. If restore itself fails, the error includes the surviving backup path.

**Merge semantics**: when you move a directory into another directory that already has a same-named subdirectory, contents **merge per-file**. Files present at the destination but not in the source are **never deleted**. Conflicts (same relative path) respect `-f` / `-n` just like single-file conflicts. **Directories at the destination are never deleted or replaced.** Attempting to replace a directory with a file errors out.

### Copy

Same flags as `mv`, plus `-r` for directories.

```bash
icloud cp file.pdf ~/Desktop/             # copy single file
icloud cp -r Documents/ ~/backup/         # recursive directory copy (merge into existing)
icloud cp -vf *.pdf dest/                 # verbose, force overwrite
icloud cp -d src.pdf dest/                # dry-run preview
icloud cp -j 10 huge/ dest/               # 10 concurrent downloads
icloud cp --json -r dir/ dest/ | jq -s .  # NDJSON -> array
```

### Download

Triggers iCloud download and waits for completion. Files that are mid-download or dataless-but-marked-local are waited on correctly, not skipped.

```bash
icloud download file.pdf               # download and wait
icloud download -rv Documents/         # recursive + verbose
icloud download --dry-run -r .         # preview, no download
icloud download -j 10 -r Documents/    # 10 concurrent downloads
icloud download -t 300 big.zip         # raise baseline timeout to 5 min
icloud download --json -r dir/ | jq -s .
```

### Evict

Makes files cloud-only by removing the local copy. Pinned files are skipped; unpin first.

```bash
icloud evict file.pdf            # free local copy
icloud evict -rv old-projects/   # recursive + verbose
icloud evict --dry-run -r .      # preview without evicting
icloud evict --json big.zip | jq -s .
```

### Pin / Unpin

`pin` sets the `com.apple.fileprovider.pinned#PX` xattr (same mechanism as Finder's "Keep Downloaded"). Pinned files are protected from automatic eviction on disk pressure and from `icloud evict`.

```bash
icloud pin important.pdf                     # single file
icloud pin -r Documents/                     # recursive
icloud pin --from-tag Green                  # all files with Finder tag "Green"
icloud pin --from-tag Green+Important -r .   # AND: both tags required
icloud pin --from-tag Red --from-tag Blue    # OR: either tag matches
icloud pin --dry-run --from-tag Green        # preview

icloud unpin important.pdf                   # allow system to evict
icloud unpin -r Documents/
icloud unpin --from-tag Green
```

Tag filters: repeat `--from-tag` for OR, use `+` inside one expression for AND.

## Parallel downloads & timeouts

`mv`, `cp`, and `download` all support:

- `-j, --max-concurrent <n>` — concurrent downloads. Default **3**. iCloud handles the concurrency on its end; we fire all `startDownloadingUbiquitousItem` calls and poll the batch.
- `-t, --timeout <sec>` — baseline timeout floor per file. Default **120**.

Effective per-file timeout = `max(baseline, sizeMB × 1.2)`:

| file size | effective timeout |
|-----------|-------------------|
| 1 MB      | 120 s (baseline)  |
| 100 MB    | 120 s             |
| 1 GB      | 20 min            |
| 2 GB      | 40 min            |
| 10 GB     | ~3 hours          |

One slow file doesn't stall the batch — each tracks its own deadline.

## Output modes

The same command picks a renderer based on how you invoke it:

| invocation                          | renderer         | example                                       |
|-------------------------------------|------------------|-----------------------------------------------|
| interactive terminal, no `-v`       | **TTYQuiet**     | `⇣ file (1 MB)` → `✓ file (2.3s)` → `src => dst` |
| interactive terminal, `-v`          | **TTYVerbose**   | per-file header + `  downloading...` + `  moved to …` |
| piped to another command (non-tty)  | **LineStream**   | `DL→ / DL✓ / MV✓ / CP✓` one line per event, grep-friendly |
| `--json`                            | **JSON (NDJSON)** | `{"event":"op.done","src":"…","dst":"…",…}` per line |

### The `=>` arrow

`MV✓ src => dst` and `src => dst` print **only after** post-op `fileExists` + size verification on the destination. If the destination is missing or size-mismatched, the tool emits `opFail` and throws. No lying success.

### JSON events

```bash
icloud mv --json a b dest/            # one NDJSON record per event
icloud mv --json a b dest/ | jq -s .  # slurp into an array
icloud cp --json -r dir/ dest/ | jq 'select(.event == "op.done")'
```

Event stream types: `phase.start`, `phase.end`, `discovered`, `download.start`, `download.tick`, `download.done`, `download.fail`, `op.done`, `op.fail`, `op.skipped`, `op.would`.

## How It Works

- **Status:** `URLResourceValues` for download status, file size, allocated size. Dataless files have `fileAllocatedSize == 0 && fileSize > 0`.
- **Download:** `FileManager.startDownloadingUbiquitousItem(at:)` triggers async download; we fire-and-poll all files in the batch concurrently.
- **Evict:** `FileManager.evictUbiquitousItem(at:)` makes files cloud-only.
- **Pin:** `setxattr` / `removexattr` for `com.apple.fileprovider.pinned#PX` (value `0x31`) — the same mechanism Finder uses for "Keep Downloaded".
- **Move/Copy:** downloads dataless files first (parallel, size-scaled timeout), then performs the operation. For directory-into-existing-directory, per-file merge with conflict handling. Destinations are stat'd post-op to verify existence and size before reporting success.

No private APIs. No entitlements. Just Foundation.

## Data-loss covenants

These are why the tool exists in its current shape:

1. **Never lie about success.** `=>` never prints without post-op verification.
2. **Never delete a destination directory.** `-f` only replaces at the file level.
3. **Never swallow syscall errors on the data path.** `setxattr`, `moveItem`, `copyItem`, enumeration, all check their returns.
4. **Download waits for all dataless states.** Not just `.cloud` — `.downloading` and dataless `.local` too.

30 unit tests pin these covenants. Run with `swift test`.

## Limitations

- No per-byte download progress. APFS uses atomic extent swaps, so `fileAllocatedSize` jumps from 0 to full on completion. The tool shows file-level progress (queued / downloading / downloaded) for batch downloads.
- Only works on files under `~/Library/Mobile Documents/`. Desktop/Documents folders only apply if they're synced to iCloud Drive.

## License

MIT
