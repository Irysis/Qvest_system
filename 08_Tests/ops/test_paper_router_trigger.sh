#!/usr/bin/env bash
#==============================================================================
# test_paper_router_trigger.sh — 논문 라우터 트리거 축 위반 주입
#------------------------------------------------------------------------------
# 신설 2026-08-02. 대상 = 02_Infrastructure/ops/paper_router_run.sh 트리거 판정
#
# ★왜: 2026-08-02 recharge 는 mcp_status=mcp_ok · mcp_candidates=38 로 정상 수집했으나
#   후보가 전부 이미 registry 에 있어 downloaded=0 이었다(skipped_duplicate_or_registered=53).
#   라우터는 downloaded 만 보므로 "새 논문 없음"으로 skip → **38편이 좌초**.
#   downloaded 는 "PDF 를 새로 받았나"이지 "라우팅할 재료가 있나"가 아니다.
#   산출물(mcp_candidates)과 소비 흔적(route JSON)을 직접 보도록 고쳤고,
#   이 검사는 그 축이 되살아나지 않는지 + 오탐이 되지 않는지 양방향으로 시험한다.
#
# 무인 스케줄러 경로라 검사가 없으면 조용히 되돌아간다.
# 실행: bash 08_Tests/ops/test_paper_router_trigger.sh
#==============================================================================
set -uo pipefail

ROOT="${CLAUDE_PROJECT_DIR:-${QM_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/../.." && pwd)}}"
ROOT="${ROOT//\\//}"
SRC="$ROOT/02_Infrastructure/ops/paper_router_run.sh"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL  %s — %s\n' "$1" "${2:-}"; }
[ -f "$SRC" ] || { echo "라우터 부재: $SRC"; exit 1; }

# 트리거 판정 로직만 격리 재현 (claude·네트워크 미호출)
decide() { # $1=DL $2=MC $3=route_exists(0/1) $4=curated $5=backlog
  local DL="$1" MC="$2" RT="$3" CUR="$4" BK="$5" UNROUTED=0
  if [ "$MC" -gt 0 ] && [ "$RT" -eq 0 ]; then UNROUTED=1; fi
  if [ "$DL" -eq 0 ] && [ "$UNROUTED" -eq 0 ] && [ "$CUR" -eq 0 ] && [ -z "$BK" ]; then
    echo "skip"; else echo "trigger"; fi
}

echo "=== test_paper_router_trigger (트리거 축 위반 주입) ==="
echo "--- A. 실사고 재현: downloaded=0 이지만 candidates>0 · 미라우팅 ---"
r=$(decide 0 38 0 0 "")
[ "$r" = "trigger" ] && ok "A1 ★downloaded=0 · mcp_candidates=38 · route JSON 없음 → trigger (좌초 방지)" \
  || bad "A1 미라우팅 후보 포착" "got $r — 38편이 다시 좌초한다"

echo "--- B. 오탐 방지: 이미 라우팅됐으면 다시 돌지 않는다 ---"
r=$(decide 0 38 1 0 "")
[ "$r" = "skip" ] && ok "B1 route JSON 존재 → skip (매일 재라우팅 안 함)" \
  || bad "B1 재라우팅 억제" "got $r — 소비 흔적이 있는데도 반복 실행"

echo "--- C. 기존 축 회귀 (수리가 종전 동작을 깨지 않았나) ---"
r=$(decide 5 0 0 0 ""); [ "$r" = "trigger" ] && ok "C1 downloaded>0 → trigger(종전 축 유지)" || bad "C1 downloaded 축" "got $r"
r=$(decide 0 0 0 1 ""); [ "$r" = "trigger" ] && ok "C2 curated_pending → trigger" || bad "C2 curated 축" "got $r"
r=$(decide 0 0 0 0 "20260801"); [ "$r" = "trigger" ] && ok "C3 backlog → trigger" || bad "C3 backlog 축" "got $r"

echo "--- D. 음성 통제: 진짜 아무것도 없으면 skip ---"
r=$(decide 0 0 0 0 "")
[ "$r" = "skip" ] && ok "D1 재료·소비대상 전무 → skip (무조건 trigger 하는 검사가 아님)" \
  || bad "D1 음성 통제" "got $r"

echo "--- E. 구현 동기: 라우터 본체가 실제로 이 축을 갖고 있나 ---"
grep -q "UNROUTED_TODAY" "$SRC" && ok "E1 라우터에 UNROUTED_TODAY 축 존재" || bad "E1 축 부재" "수리가 되돌려졌다"
grep -q "mcp_candidates=" "$SRC" && ok "E2 mcp_candidates 를 STAMP 에서 읽는다" || bad "E2 candidates 축 부재" ""

echo
printf 'PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
printf '{"test":"paper_router_trigger","pass":%d,"fail":%d,"total":%d}\n' "$PASS" "$FAIL" "$((PASS+FAIL))"
[ "$FAIL" -eq 0 ] || exit 1
