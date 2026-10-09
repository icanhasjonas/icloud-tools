#!/bin/bash
# Usage: scripts/update-formula.sh <version> [sha256]
# Without sha256, downloads the release asset and hashes it.
# DRY_RUN=1 prints the formula instead of pushing it to the tap.
set -euo pipefail

VERSION="${1:?usage: update-formula.sh <version> [sha256]}"
REPO="icanhasjonas/icloud-tools"
TAP_REPO="icanhasjonas/homebrew-tap"
FORMULA_PATH="Formula/icloud-tools.rb"
ASSET_URL="https://github.com/${REPO}/releases/download/v${VERSION}/icloud-${VERSION}-macos-universal.tar.gz"

SHA256="${2:-}"
if [ -z "$SHA256" ]; then
    echo "fetching ${ASSET_URL}..."
    SHA256=$(curl -fsSL "${ASSET_URL}" | shasum -a 256 | cut -d' ' -f1) \
        || { echo "error: release asset for v${VERSION} not found"; exit 1; }
fi

FORMULA='class IcloudTools < Formula
  desc "CLI for managing iCloud Drive files (replacement for brctl download/evict)"
  homepage "https://github.com/'"${REPO}"'"
  url "'"${ASSET_URL}"'"
  sha256 "'"${SHA256}"'"
  license "MIT"

  depends_on macos: :sonoma

  conflicts_with "icloudpd", because: "both install an `icloud` binary"

  def install
    bin.install "icloud"
    generate_completions_from_executable(bin/"icloud", "--generate-completion-script")
  end

  test do
    assert_equal "'"${VERSION}"'", shell_output("#{bin}/icloud --version").strip
  end
end'

if [ "${DRY_RUN:-0}" = 1 ]; then
    echo "${FORMULA}"
    exit 0
fi

echo "updating tap formula..."
FILE_SHA=$(gh api "repos/${TAP_REPO}/contents/${FORMULA_PATH}" --jq '.sha')
gh api --method PUT "repos/${TAP_REPO}/contents/${FORMULA_PATH}" \
    -f message="icloud-tools ${VERSION}" \
    -f content="$(printf '%s\n' "${FORMULA}" | base64)" \
    -f sha="${FILE_SHA}" \
    --silent

echo "homebrew-tap updated to v${VERSION}"
