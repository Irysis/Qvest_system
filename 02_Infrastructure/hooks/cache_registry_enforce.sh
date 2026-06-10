#!/bin/bash

trap 'echo "{}"; exit 0' ERR
#==============================================================================
# Cache Registry Enforce — PreToolUse[Write|Edit] (도훈 mandate 2026-05-15)
#
# 영구 보호망 L4: 신규 .cache/*.parquet 작성 코드 발견 시 registry entry 강제
# write_parquet/fwrite/saveRDS 대상 .cache/ 경로가 registry에 없으면 advisory.
# 도훈 인지 + 추가 mandate 시 hard block 검토.
#==============================================================================

INPUT=$(cat)
source "$(dirname "${BASH_SOURCE[0]:-$0}")/_shared_parse.sh"

if [ "$TOOL_NAME" != "Write" ] && [ "$TOOL_NAME" != "Edit" ]; then
  echo '{}'; exit 0
fi

LOG="/tmp/cache_registry_enforce.log"
DIR=$(ls -d /c/Users/99922/OneDrive/Quant_Module_Moltbot /mnt/c/Users/99922/OneDrive/Quant_Module_Moltbot /g/Quant_Module_Moltbot /mnt/g/Quant_Module_Moltbot /mnt/c/Users/*/OneDrive/바탕\ 화면/Quant_Module_Moltbot 2>/dev/null | head -1)
[ -z "$DIR" ] && { echo '{}'; exit 0; }

REGISTRY="$DIR/02_Infrastructure/data/cache_registry.json"
[ ! -f "$REGISTRY" ] && { echo '{}'; exit 0; }

# Only check R/Python source files (writers)
case "$FILE_PATH" in
  *.R|*.r|*.py) ;;
  *) echo '{}'; exit 0;;
esac

# Detect new .cache write patterns
HAS_WRITE=$(echo "$CONTENT" | grep -cE "(write_parquet|fwrite|saveRDS|write\.csv|arrow::write_parquet).*\.cache/")
[ "$HAS_WRITE" -eq 0 ] && { echo '{}'; exit 0; }

NEW_CACHE_PATHS=$(echo "$CONTENT" | grep -oE '\.cache/[a-zA-Z0-9_/-]+\.(parquet|csv|rds)' | sort -u | head -10)
[ -z "$NEW_CACHE_PATHS" ] && { echo '{}'; exit 0; }

UNREGISTERED=""
while IFS= read -r path; do
  [ -z "$path" ] && continue
  if ! grep -q "\"$path\"" "$REGISTRY"; then
    UNREGISTERED="${UNREGISTERED} $path"
  fi
done <<< "$NEW_CACHE_PATHS"

[ -z "$UNREGISTERED" ] && { echo '{}'; exit 0; }

echo "$(date +%H:%M:%S) UNREGISTERED_WRITE: $FILE_PATH writes to$UNREGISTERED" >> "$LOG"

printf '{}' "$FILE_PATH" "$UNREGISTERED"
exit 0
