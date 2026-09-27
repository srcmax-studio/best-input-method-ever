#!/bin/zsh
set -euo pipefail

repo_dir="${0:A:h:h}"
app="$repo_dir/build/EnglishHanZi.app"
binary="$app/Contents/MacOS/EnglishHanZi"

"$repo_dir/Scripts/build.sh" >/dev/null
[[ "$(sqlite3 "$app/Contents/Resources/lexicon.sqlite3" 'PRAGMA integrity_check')" == "ok" ]]

expect_first() {
  local command="$1" word="$2" expected="$3" actual
  actual="$("$binary" "$command" "$word" | head -n 1 | cut -f 2)"
  if [[ "$actual" != "$expected" ]]; then
    print -u2 "FAIL: $word expected $expected, got $actual"
    exit 1
  fi
  print "PASS: $word → $actual"
}

expect_first --lookup hello 你好
expect_first --lookup computer 電腦
expect_first --lookup software 軟體
expect_first --lookup good-morning 早上好
expect_first --lookup how-are-you 你好嗎
expect_first --lookup book 書
expect_first --lookup hel 你好
expect_first --lookup cats 貓
expect_first --lookup i 我
expect_first --lookup it 它
expect_first --lookup where 哪裡
expect_first --lookup can 能
expect_first --lookup are 是
expect_first --lookup-simplified apple 苹果
expect_first --lookup-simplified good-morning 早上好

if "$binary" --lookup zzyqxx >/dev/null; then
  print -u2 'FAIL: unknown query produced candidates'
  exit 1
fi
print 'PASS: unknown query remains raw English'
codesign --verify --deep --strict "$app"
print 'All dictionary and bundle checks passed.'
