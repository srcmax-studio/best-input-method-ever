#!/bin/zsh
set -euo pipefail

repo_dir="${0:A:h:h}"
app_path="$repo_dir/build/EnglishHanZi.app"
contents="$app_path/Contents"
binary="$contents/MacOS/EnglishHanZi"
resources="$contents/Resources"

if [[ ! -f "$repo_dir/Resources/lexicon.sqlite3" ]]; then
  python3 "$repo_dir/Tools/build_dictionary.py"
fi

mkdir -p "$contents/MacOS" "$resources" "$repo_dir/build/tools"
clang -std=gnu11 -fobjc-arc -fmodules -O2 -Wall -Wextra \
  -Wno-unused-parameter \
  -framework Cocoa -framework InputMethodKit -framework Carbon -framework CoreFoundation -lsqlite3 \
  "$repo_dir/Sources/EnglishHanZi/main.m" \
  "$repo_dir/Sources/EnglishHanZi/Lexicon.m" \
  "$repo_dir/Sources/EnglishHanZi/InputController.m" \
  -o "$binary"
clang -std=gnu11 -fobjc-arc -fmodules -O2 -framework Cocoa \
  "$repo_dir/Tools/make_icon.m" -o "$repo_dir/build/tools/make_icon"
"$repo_dir/build/tools/make_icon" "$repo_dir/Resources/InputMethodIcon.png"
cp "$repo_dir/Resources/InputMethodIcon.png" "$resources/InputMethodIcon.png"
cp "$repo_dir/Resources/Info.plist" "$contents/Info.plist"
cp "$repo_dir/Resources/lexicon.sqlite3" "$resources/lexicon.sqlite3"
cp "$repo_dir/Resources/ECDICT-LICENSE.txt" "$resources/ECDICT-LICENSE.txt"
codesign --force --sign "${CODESIGN_IDENTITY:--}" "$app_path"
plutil -lint "$contents/Info.plist"
echo "Built $app_path"
