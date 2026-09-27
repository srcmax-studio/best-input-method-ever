#!/bin/zsh
set -euo pipefail

repo_dir="${0:A:h:h}"
"$repo_dir/Scripts/build.sh"
source_app="$repo_dir/build/EnglishHanZi.app"
destination_dir="$HOME/Library/Input Methods"
destination_app="$destination_dir/EnglishHanZi.app"
mkdir -p "$destination_dir"

# Replacing a running IME bundle in place is unsafe; terminate our own process first.
pkill -x EnglishHanZi 2>/dev/null || true
ditto "$source_app" "$destination_app"
"$destination_app/Contents/MacOS/EnglishHanZi" --register
echo "Installed to $destination_app"
echo "Choose 英译中文 from the macOS input menu. Run --select on the installed binary to switch immediately."
