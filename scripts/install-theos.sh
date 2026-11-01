#!/usr/bin/env bash
set -euo pipefail

if [ -d "$HOME/theos" ]; then
  echo "Theos already exists at $HOME/theos"
  exit 0
fi

git clone --recursive https://github.com/theos/theos.git "$HOME/theos"
echo
echo 'Add this to ~/.bashrc:'
echo 'export THEOS="$HOME/theos"'
echo 'export PATH="$THEOS/bin:$PATH"'
echo
echo "Theos cloned. You still need to install/configure an iOS SDK for Theos."
