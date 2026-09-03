#!/usr/bin/env bash
# ★RETIRED (v10 2026-09-03) — S0 Debate 상태머신 = pre-v9 S0~S7 스테이지 기계. v10 은 충실구현
#   (run_paper_replication) + QEPM(WT-R) 만 쓰므로 소비 경로가 소멸했다. 등록 이력 0(MANIFEST 36 밖).
#   required_roles 에 governor(v10 폐지) 포함. ★00_Lawbook/DEPRECATION.md 의 'v8.2 범위 밖 유지' 판정을
#   v10 2026-09-03 에 철회한 항목이다. 재열람 = git 태그 pre-v10-2layer.
#   ★telegram_async.sh 는 .env 토큰으로 api.telegram.org 를 curl 직접 호출한다 — v10 '텔레그램 =
#     tg_agent_brief() 단일 진입' 규칙 위반 경로이며 telegram_direct_call_guard(Rscript 페이로드만 스캔)의 사각. 재사용 금지.
# telegram_async.sh — 텔레그램 non-blocking 발송 (Phase C3.5 split)
# 사용: source "$SCRIPT_DIR/s0_enforcer/telegram_async.sh"; tg_notify "메시지"
#
# .env에서 TG_BOT_TOKEN / TG_CHAT_ID 로드 (hardcoded 금지).
# 4096자 제한 자동 분할. curl은 () & 서브쉘로 critical path 영향 0.

if [ -z "${DIR:-}" ]; then
  DIR=$(ls -d /c/Users/99922/OneDrive/Quant_Module_Moltbot /mnt/c/Users/99922/OneDrive/Quant_Module_Moltbot /g/Quant_Module_Moltbot /mnt/g/Quant_Module_Moltbot /mnt/c/Users/*/OneDrive/바탕\ 화면/Quant_Module_Moltbot 2>/dev/null | head -1 || echo "$PWD")
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
