#!/bin/bash
# src/{ko,en}/*.html → {ko,en}/*.png (1206x2622). 디자인은 ../vialive 의 app-screenshots kit/style.css 를 그대로 씀
# 사용법: AppStoreScreenshots/render.sh [번호]   예: render.sh 02 (없으면 전부)
set -euo pipefail
dir=$(cd "$(dirname "$0")" && pwd)
chrome="/c/Program Files/Google/Chrome/Application/chrome.exe"
for source in "$dir"/src/{ko,en}/${1:-}*.html; do
  lang=$(basename "$(dirname "$source")")
  out="$dir/$lang/$(basename "${source%.html}").png"
  mkdir -p "$dir/$lang"
  "$chrome" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=1 \
    --window-size=1206,2622 --virtual-time-budget=8000 --allow-file-access-from-files \
    --screenshot="$(cygpath -w "$out")" "file:///$(cygpath -m "$source")" 2>/dev/null
  echo "$out"
done
