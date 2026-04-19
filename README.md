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

```bash
git clone https://github.com/icanhasjonas/icloud-tools.git
cd icloud-tools
swift build -c release
cp .build/release/icloud ~/.local/bin/
```

Requires macOS 14+ and Swift 6.0+.

## Usage

### Status

Show iCloud status for files. Defaults to `~/Library/Mobile Documents/com~apple~CloudDocs/`.

```bash
icloud status                    # list iCloud Drive root
icloud status ~/Desktop          # specific directory
icloud status -r Documents/      # recursive
icloud status --cloud            # only cloud-only files
icloud status --local            # only local files
icloud status --sort size        # sort by size
```

Output uses ANSI colors: green = local, dim = cloud, yellow = syncing, cyan P = pinned.

### Download (coming soon)

```bash
icloud download file.pdf         # download and wait
icloud download -r Documents/    # download entire directory
icloud download --no-wait *.pdf  # trigger and exit
```

### Evict (coming soon)

```bash
icloud evict file.pdf            # free local copy
icloud evict -r old-projects/    # evict entire directory
icloud evict --min-size 100MB    # only large files
```

### Pin / Unpin (coming soon)

```bash
icloud pin important.pdf         # keep downloaded, prevent auto-eviction
icloud unpin important.pdf       # allow system to evict on disk pressure
```

### Watch (coming soon)

```bash
icloud watch                     # live sync activity monitor
```

## How It Works

- **Download:** `FileManager.startDownloadingUbiquitousItem(at:)` triggers async download; `NSFileCoordinator` blocks until complete for `--wait` mode.
- **Evict:** `FileManager.evictUbiquitousItem(at:)` makes files cloud-only.
- **Status:** `URLResourceValues` for download status, file size, allocated size. Dataless files have `fileAllocatedSize == 0`.
- **Pin:** Sets `com.apple.fileprovider.pinned#PX` xattr (value `0x31`) -- the same mechanism Finder uses for "Keep Downloaded".

No private APIs. No entitlements. Just Foundation.

## Limitations

- No per-byte download progress. APFS uses atomic extent swaps, so `fileAllocatedSize` jumps from 0 to full on completion. The tool shows file-level progress (done/not-done) for batch downloads.
- Only works on files under `~/Library/Mobile Documents/`. Desktop/Documents folders only apply if they're synced to iCloud Drive.

## License

MIT
