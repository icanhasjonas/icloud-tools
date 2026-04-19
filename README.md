# icloud

CLI tool for managing iCloud Drive files on macOS.

Apple removed `brctl download` and `brctl evict` in macOS Sonoma 14+, and `fileproviderctl materialize` in 14.4. No replacement CLI shipped. This tool fills the gap using Foundation APIs that still work from unsigned binaries -- no entitlements, no code signing, no sandbox.

## Why

- **rsync deadlocks** on dataless (cloud-only) files: `mmap: Resource deadlock avoided`. You need to download first.
- **No CLI to batch-download** a directory before going offline.
- **No CLI to see** what's local vs cloud-only, or what's eating disk.
- **No CLI to evict** files and free space.
- **"Keep Downloaded" (pin)** is Finder-only -- no CLI equivalent existed until now.

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

Symlinked paths (e.g. `~/.icloud -> ~/Library/Mobile Documents/com~apple~CloudDocs/`) are resolved automatically.

### Move

Move files with download-first semantics. Dataless files are downloaded before moving, preventing the rsync mmap deadlock.

```bash
icloud mv file.pdf ~/Desktop/       # move single file
icloud mv a.pdf b.pdf dest/         # move multiple into directory
icloud mv -v old.pdf new.pdf        # verbose with sizes
icloud mv -f src.pdf existing.pdf   # force overwrite (atomic backup+restore)
icloud mv -n src.pdf existing.pdf   # skip if exists
icloud mv -d src.pdf dest/          # dry-run preview
icloud mv --json src.pdf dest/      # NDJSON output
```

`-f` moves the existing destination to a hidden backup, runs the operation, then removes the backup on success. If the operation fails the backup is restored. If restore itself fails the path to the surviving backup is reported in the error.

### Copy

Copy files with download-first semantics. Same flags as `mv`, plus `-r` for directories.

```bash
icloud cp file.pdf ~/Desktop/       # copy single file
icloud cp -r Documents/ ~/backup/   # recursive directory copy
icloud cp -v -f *.pdf dest/         # verbose, force overwrite
icloud cp -d src.pdf dest/          # dry-run preview
icloud cp --json src.pdf dest/      # NDJSON output
```

### Download

Triggers iCloud download and waits for completion. Files that are mid-download or dataless-but-marked-local are waited on correctly, not skipped.

```bash
icloud download file.pdf               # download and wait
icloud download -rv Documents/         # recursive + verbose
icloud download --dry-run -r .         # preview, no download
icloud download --timeout 60 big.zip   # override per-file timeout (default 300s)
icloud download --json *.pdf           # NDJSON output
```

### Evict

Makes files cloud-only by removing the local copy. Pinned files are skipped; unpin first.

```bash
icloud evict file.pdf            # free local copy
icloud evict -rv old-projects/   # recursive + verbose
icloud evict --dry-run -r .      # preview without evicting
icloud evict --json big.zip      # NDJSON output
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

## JSON Output

All commands support `--json`. Status outputs pretty JSON with file metadata and summary. Move/copy output NDJSON (one JSON object per line per operation) for streaming/piping.

```bash
# Pretty JSON status
icloud status --json | jq '.summary'

# NDJSON operations
icloud cp --json *.pdf dest/ | jq -c '{name: .source, status: .status}'
```

## How It Works

- **Status:** `URLResourceValues` for download status, file size, allocated size. Dataless files have `fileAllocatedSize == 0`.
- **Download:** `FileManager.startDownloadingUbiquitousItem(at:)` triggers async download with polling until complete.
- **Evict:** `FileManager.evictUbiquitousItem(at:)` makes files cloud-only.
- **Pin:** Sets `com.apple.fileprovider.pinned#PX` xattr (value `0x31`) -- the same mechanism Finder uses for "Keep Downloaded".
- **Move/Copy:** Downloads dataless files first, then performs the operation via FileManager.

No private APIs. No entitlements. Just Foundation.

## Limitations

- No per-byte download progress. APFS uses atomic extent swaps, so `fileAllocatedSize` jumps from 0 to full on completion. The tool shows file-level progress (done/not-done) for batch downloads.
- Only works on files under `~/Library/Mobile Documents/`. Desktop/Documents folders only apply if they're synced to iCloud Drive.

## License

MIT
