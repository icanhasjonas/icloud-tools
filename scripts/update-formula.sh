#!/bin/bash
set -euo pipefail

VERSION="${1:?usage: update-formula.sh <version>}"
REPO="icanhasjonas/icloud-tools"
TAP_REPO="icanhasjonas/homebrew-tap"
FORMULA_PATH="Formula/icloud-tools.rb"
TARBALL_URL="https://github.com/${REPO}/archive/refs/tags/v${VERSION}.tar.gz"

echo "fetching tarball sha256 for v${VERSION}..."
SHA256=$(curl -sL "${TARBALL_URL}" | shasum -a 256 | cut -d' ' -f1)

if [ -z "$SHA256" ] || [ "$SHA256" = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" ]; then
    echo "error: empty tarball -- tag v${VERSION} not found on GitHub"
    exit 1
fi

echo "sha256: ${SHA256}"

FORMULA='class IcloudTools < Formula
  desc "CLI for managing iCloud Drive files (replacement for brctl download/evict)"
  homepage "https://github.com/'"${REPO}"'"
  url "'"${TARBALL_URL}"'"
  sha256 "'"${SHA256}"'"
  license "MIT"

  depends_on xcode: ["16.0", :build]
  depends_on :macos

  def install
    system "swift", "build", "-c", "release", "--disable-sandbox"
    bin.install ".build/release/icloud"
  end

  test do
    assert_match "Manage iCloud Drive", shell_output("#{bin}/icloud --help")
  end
end'

echo "updating tap formula..."

# Base64 encode for GitHub API
ENCODED=$(echo -n "${FORMULA}" | base64)

# Get current file SHA (needed for update)
FILE_SHA=$(gh api "repos/${TAP_REPO}/contents/${FORMULA_PATH}" --jq '.sha')

gh api --method PUT "repos/${TAP_REPO}/contents/${FORMULA_PATH}" \
    -f message="Update icloud-tools to ${VERSION}" \
    -f content="${ENCODED}" \
    -f sha="${FILE_SHA}" \
    --silent

echo "homebrew-tap updated to v${VERSION}"
