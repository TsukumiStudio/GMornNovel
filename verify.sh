#!/bin/sh
# 別名の配置先・Godot キャッシュなし・ゲーム側の素材なしでも動くことを確かめる。
set -eu
addon_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
godot_bin=${GODOT_BIN:-$(command -v godot)}
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT
mkdir -p "$work_dir/addons/renamed_novel"
cp "$addon_dir"/*.gd "$addon_dir"/*.tscn "$addon_dir/plugin.cfg" "$work_dir/addons/renamed_novel/"
printf 'config_version=5\n[application]\nconfig/features=PackedStringArray("4.7")\n' > "$work_dir/project.godot"
# assert で止まった Godot は終了しないので、時間で切る。
perl -e 'alarm shift; exec @ARGV' 20 "$godot_bin" --headless --path "$work_dir" \
  --script addons/renamed_novel/verify.gd > "$work_dir/verify.log" 2>&1 || {
  cat "$work_dir/verify.log"
  exit 1
}
cat "$work_dir/verify.log"
if grep -E 'SCRIPT ERROR:|ERROR:|WARNING:' "$work_dir/verify.log"; then exit 1; fi
grep -q 'GMORN NOVEL VERIFY: PASS' "$work_dir/verify.log"
