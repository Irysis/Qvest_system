#!/usr/bin/env bash
# install_hook_guard.sh — SessionEnd 자동 커밋 · 푸시 훅에 'OneDrive 동기화 안정' 가드를 끼운다 (멱등 · 2026-11-01)
#   bash install_hook_guard.sh [--uninstall] [hooks_dir]
# 대상: auto_commit_on_stop.sh · auto_push_on_stop.sh — 둘 다 첫 `git rev-parse --git-dir ... || { echo '{}'; exit 0; }`
#   줄 바로 뒤(작업 트리 · 저장소 확인 직후, 어떤 git 쓰기보다 앞)에 표식 블록을 넣는다. 파일의 줄 끝(CRLF)을 따른다.
# 왜 스크립트인가: 두 기계가 같은 훅 파일을 OneDrive 로 공유하는데, 메인 PC 의 사본이 노트북의 최신 판(10-20 WP4)보다
#   늦게 도착할 수 있다 — 어느 판이 오든 같은 블록을 같은 자리에 끼울 수 있어야 한다.
# 끼운 뒤 bash -n 문법 검사 — 실패하면 원본으로 되돌린다. 가드 본체 = qvest_machine.sh settled.
set -u
MODE=install
[ "${1:-}" = "--uninstall" ] && { MODE=uninstall; shift; }
HOOKS="${1:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/../../hooks" && pwd)}"
ANCHOR="git rev-parse --git-dir >/dev/null 2>&1 || { echo '{}'; exit 0; }"
OPEN='# >>> QVEST_MACHINE_SETTLE >>>'
CLOSE='# <<< QVEST_MACHINE_SETTLE <<<'
BLOCK="$(mktemp)"; trap 'rm -f "$BLOCK" "$BLOCK".*' EXIT
cat > "$BLOCK" <<'EOF'
# >>> QVEST_MACHINE_SETTLE >>> (2026-11-01 두 대 운용 — 02_Infrastructure/ops/machine/qvest_machine.sh settled)
# 공유 저장소(OneDrive)가 다 내려오지 않았으면 커밋 · 푸시하지 않는다: .git 클라우드 전용 파일 · OneDrive 충돌 사본
#   (main-<기계명> 등) · 대량 삭제(작업 트리 동기화 중) · 기계별 보류 표식(.cache/machine/hold_<HOST>) 중 하나라도 있으면
#   SKIP_UNSETTLED. 반쯤 받은 트리를 커밋하면 다른 기계의 작업을 지우는 커밋이 되고, 낡은 ref 위 커밋은 충돌 사본을 만든다.
#   검사 격리용 우회 = QVEST_SETTLE_CHECK=0. 끼우기 · 빼기 = ops/machine/install_hook_guard.sh [--uninstall].
_qm_sh="$(dirname "${BASH_SOURCE[0]:-$0}")/../ops/machine/qvest_machine.sh"
if [ "${QVEST_SETTLE_CHECK:-1}" != "0" ] && [ -f "$_qm_sh" ]; then
  _qm_res="$(bash "$_qm_sh" settled "$PROJECT" 2>/dev/null)" || { echo "$TS SKIP_UNSETTLED ${_qm_res:-unknown}" >> "$LOG"; echo '{}'; exit 0; }
fi
# <<< QVEST_MACHINE_SETTLE <<<
EOF

rc=0
for h in auto_commit_on_stop.sh auto_push_on_stop.sh; do
  f="$HOOKS/$h"
  if [ ! -f "$f" ]; then echo "MISSING $f"; rc=1; continue; fi
  cp "$f" "$BLOCK.bak"
  if [ "$MODE" = "uninstall" ]; then
    grep -qF "$OPEN" "$f" || { echo "ABSENT  $h"; continue; }
    awk -v o="$OPEN" -v c="$CLOSE" '{ l = $0; sub(/\r$/, "", l) } index(l, o) == 1 { skip = 1 } !skip { print } index(l, c) == 1 { skip = 0 }' \
      "$f" > "$BLOCK.new"
  else
    if grep -qF "$OPEN" "$f"; then echo "ALREADY $h"; continue; fi
    if ! tr -d '\r' < "$f" | grep -qxF "$ANCHOR"; then echo "NO_ANCHOR $h — 끼울 자리를 못 찾음(수동 확인)"; rc=1; continue; fi
    awk -v a="$ANCHOR" -v blk="$BLOCK" '
      { l = $0; cr = ""; if (sub(/\r$/, "", l)) cr = "\r"; print }
      !done && l == a { while ((getline b < blk) > 0) print b cr; done = 1 }' "$f" > "$BLOCK.new"
  fi
  cat "$BLOCK.new" > "$f"
  if bash -n "$f" 2>"$BLOCK.err"; then
    echo "$( [ "$MODE" = uninstall ] && echo REMOVED || echo INSTALLED ) $h"
  else
    cat "$BLOCK.bak" > "$f"; echo "SYNTAX_FAIL $h — 되돌림: $(head -c 300 "$BLOCK.err")"; rc=1
  fi
done
exit $rc
