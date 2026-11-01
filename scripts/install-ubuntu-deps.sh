#!/usr/bin/env bash
set -euo pipefail

sudo apt update
sudo apt install -y \
  git make perl python3 curl wget ca-certificates \
  clang llvm lld libplist-utils \
  fakeroot dpkg-dev xz-utils unzip

echo
echo "Ubuntu build dependencies installed."
echo "Next: install Theos and an iOS SDK, then run:"
echo "  make package"
