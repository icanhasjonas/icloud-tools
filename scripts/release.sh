#!/bin/bash
# Usage: scripts/release.sh <version> [--dry-run]
#
# Preflight -> test -> bump -> universal build -> package -> commit/tag/push
# -> GitHub release with binary asset -> homebrew tap formula.
# --dry-run stops after packaging, prints the formula, and restores Version.swift.
set -euo pipefail

VERSION="${1:?usage: release.sh <version> [--dry-run]}"
DRY_RUN=0
[ "${2:-}" = "--dry-run" ] && DRY_RUN=1

REPO="icanhasjonas/icloud-tools"
VERSION_FILE="Sources/icloud/Version.swift"
DIST=".build/dist"
ASSET="icloud-${VERSION}-macos-universal.tar.gz"

die() { echo "error: $*" >&2; exit 1; }
step() { printf '\033[1m==> %s\033[0m\n' "$*"; }

cd "$(git rev-parse --show-toplevel)"

step "preflight"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "version must be X.Y.Z, got '$VERSION'"
[ "$(git branch --show-current)" = "main" ] || die "not on main"
[ -z "$(git status --porcelain)" ] || die "working tree not clean"
git rev-parse -q --verify "refs/tags/v${VERSION}" >/dev/null && die "tag v${VERSION} exists locally"
git fetch -q origin main --tags
git ls-remote --exit-code --tags origin "v${VERSION}" >/dev/null 2>&1 && die "tag v${VERSION} exists on origin"
[ "$(git rev-list --count HEAD..origin/main)" = "0" ] || die "main is behind origin/main, pull first"
gh auth status >/dev/null 2>&1 || die "gh not authenticated"

step "test"
swift test

restore_version() { git checkout -q -- "$VERSION_FILE"; }
step "bump ${VERSION}"
echo "let version = \"${VERSION}\"" > "$VERSION_FILE"
[ "$DRY_RUN" = 1 ] && trap restore_version EXIT

step "build universal (arm64 + x86_64)"
swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/icloud"
lipo "$BIN" -verify_arch arm64 x86_64 || die "binary is not universal"
[ "$("$BIN" --version)" = "$VERSION" ] || die "binary reports $("$BIN" --version), expected $VERSION"

step "package ${ASSET}"
rm -rf "$DIST" && mkdir -p "$DIST/stage"
cp "$BIN" LICENSE "$DIST/stage/"
tar -czf "$DIST/$ASSET" -C "$DIST/stage" icloud LICENSE
SHA256=$(shasum -a 256 "$DIST/$ASSET" | cut -d' ' -f1)
echo "$DIST/$ASSET  sha256 ${SHA256}"

if [ "$DRY_RUN" = 1 ]; then
    step "dry run: formula that would be published"
    DRY_RUN=1 scripts/update-formula.sh "$VERSION" "$SHA256"
    echo "dry run complete, nothing committed or pushed"
    exit 0
fi

step "commit + tag + push"
git add "$VERSION_FILE"
git commit -qm "Bump version to ${VERSION}"
git tag "v${VERSION}"
git push -q origin main "v${VERSION}"

step "GitHub release v${VERSION}"
gh release create "v${VERSION}" "$DIST/$ASSET" --repo "$REPO" --title "v${VERSION}" --generate-notes

step "homebrew tap"
scripts/update-formula.sh "$VERSION" "$SHA256"

echo "released v${VERSION}: brew upgrade icloud-tools"
