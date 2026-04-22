#!/usr/bin/env bash
# telegram_async.sh — 텔레그램 non-blocking 발송 (Phase C3.5 split)
# 사용: source "$SCRIPT_DIR/s0_enforcer/telegram_async.sh"; tg_notify "메시지"
#
# .env에서 TG_BOT_TOKEN / TG_CHAT_ID 로드 (hardcoded 금지).
# 4096자 제한 자동 분할. curl은 () & 서브쉘로 critical path 영향 0.

if [ -z "${DIR:-}" ]; then
  DIR=$(ls -d /mnt/c/Users/*/OneDrive/바탕\ 화면/Quant_Module_Moltbot 2>/dev/null | head -1 || echo "$PWD")
fi
if [ -f "$DIR/.env" ]; then
  set -a; source "$DIR/.env" 2>/dev/null; set +a
fi
: "${TG_BOT_TOKEN:=}"
: "${TG_CHAT_ID:=}"

tg_notify() {
  local msg="$1"
  [ -z "$TG_BOT_TOKEN" ] || [ -z "$TG_CHAT_ID" ] && return 0
  (
    local len=${#msg}
    if [ "$len" -le 4000 ]; then
      curl -s "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
        -d "chat_id=${TG_CHAT_ID}" -d "parse_mode=" \
        --data-urlencode "text=$msg" > /dev/null 2>&1
    else
      local part1="${msg:0:3900}
...(계속)"
      local part2="(이어서)
${msg:3900}"
      curl -s "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
        -d "chat_id=${TG_CHAT_ID}" -d "parse_mode=" \
        --data-urlencode "text=$part1" > /dev/null 2>&1
      sleep 1
      curl -s "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
        -d "chat_id=${TG_CHAT_ID}" -d "parse_mode=" \
        --data-urlencode "text=$part2" > /dev/null 2>&1
    fi
  ) &
}
