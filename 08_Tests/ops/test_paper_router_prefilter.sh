#!/bin/bash
# test_paper_router_prefilter.sh — 논문 라우터 '신규 paper_key 0' 사전 필터 (v10 2026-09-02)
#
# 왜 있나 (도훈 지목 2026-09-02): arXiv MCP 는 고정 30쿼리·recency 0 재크롤이라 매일 같은 243편이
#   재부상한다. 구판 라우터는 'discovery 있고 route 없음 = 미소비' 만 보고 매일 claude -p(≈5분)를 띄워
#   전건 redundant 판정 + [1계층] 논문 트리아지 1건 + 완주 알림 1건 = 정보량 0 메시지 2건/일.
#   실측 09-02: 후보 243 → paper_key 재도출 신규 0(route 이력 243/243 · registry 228).
#
# 검사 축 (양방향 — 양성 대조 없는 계기는 방어선으로 세지 않는다):
#   A. 후보 전건 기존 키 → claude 미호출 · route 스텁(generated_by=prefilter) 기록 · 로그 'prefilter: … 전건'
#   B. 신규 키 1건 포함 → 필터 통과('신규 paper_key 1건') · 스텁 없음 · (가짜) claude 호출됨   ← 양성 대조
#   C. DRYRUN=1 → 스텁을 쓰지 않는다(DRYRUN 테스트 3종이 stage_artifacts 를 오염하지 않게)
#   D. 정적: 완주 알림 기본 off(QVEST_RUN_NOTIFY:-0) · mode_queue_axis_audit 호출 제거 · 표제 [무인]
#
# 격리: 픽스처 루트(marker + paper_id_norm.py 사본 + prompt 사본) · QM_ROOT/CLAUDE_PROJECT_DIR 로 앵커 ·
#   가짜 claude 를 PATH 선두에 · 자격증명 사전점검은 env 토큰(값은 픽스처 문자열)으로 통과 · 텔레그램 무발송
#   (QVEST_UNATTENDED 미설정 → 마커만). 실행: bash 08_Tests/ops/test_paper_router_prefilter.sh
set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$(cd "$SELF_DIR/../.." && pwd)"
SRC="$ROOT/02_Infrastructure/ops/paper_router_run.sh"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); echo "  PASS  $1"; }
ng(){ FAIL=$((FAIL+1)); echo "  FAIL  $1 :: $2"; }
fin(){ echo; printf 'PASS=%d FAIL=%d\n' "$PASS" "$FAIL"; printf '{"test":"paper_router_prefilter","pass":%d,"fail":%d,"total":%d}\n' "$PASS" "$FAIL" "$((PASS+FAIL))"; [ "$FAIL" -eq 0 ] || exit 1; exit 0; }

[ -f "$SRC" ] || { echo "  SKIP  라우터 부재"; printf '{"test":"paper_router_prefilter","pass":0,"fail":0,"total":0,"skipped":1,"skips":[{"axis":"ALL","reason":"라우터 부재","missing":"%s"}]}\n' "$SRC"; exit 0; }

PY=""
for c in "${QVEST_PY:-}" "$ROOT/.venv_qvest_ml/Scripts/python.exe" "/c/Users/99922/AppData/Local/Programs/Python/Python312/python.exe"; do
  c="${c//\\//}"
  [ -n "$c" ] && [ -x "$c" ] && "$c" -c 'import json' >/dev/null 2>&1 && { PY="$c"; break; }
done
[ -n "$PY" ] || { echo "  SKIP  python 부재"; printf '{"test":"paper_router_prefilter","pass":0,"fail":0,"total":0,"skipped":1,"skips":[{"axis":"ALL","reason":"python 부재","missing":"python"}]}\n'; exit 0; }

echo "=== test_paper_router_prefilter (신규 0 사전 필터 · 양방향) ==="
echo "--- D. 정적 축 ---"
grep -q 'generated_by' "$SRC" && ok "D1 사전 필터 블록 존재(route 스텁 generated_by)" || ng "D1 필터 부재" "수리가 되돌려졌다"
grep -q 'QVEST_RUN_NOTIFY:-0' "$SRC" && ok "D2 완주 알림 기본 off(트리아지 텔레그램과 이중 제거)" || ng "D2 알림 기본값" "QVEST_RUN_NOTIFY 기본이 1 — 정보량 0 메시지 재발"
grep -q '"\$_pbx" "\$_AX"' "$SRC" && ng "D3 mode_queue_axis_audit 호출 잔존" "폐지 레인 검사가 매일 '대상 큐 없음' 을 찍는다" || ok "D3 mode_queue_axis_audit 호출 제거"
grep -q '\[무인\] 스케줄러 경보' "$SRC" && ok "D4 경보 표제 계층 태그 [무인]" || ng "D4 표제" "§5.6b 태그 없음"

TODAY=$(date +%Y%m%d)
mkfx() {   # $1=픽스처 루트  $2=신규 후보 포함(0/1)
  local T="$1" novel="$2"
  mkdir -p "$T/02_Infrastructure/hooks" "$T/02_Infrastructure/ops" "$T/06_Registry" "$T/stage_artifacts/paper_recharge" "$T/.cache/scheduler_logs" "$T/bin" "$T/.venv_qvest_ml/Scripts"
  : > "$T/02_Infrastructure/hooks/qvest_hook_router.py"        # 루트 marker (resolve_project.sh)
  cp "$ROOT/02_Infrastructure/ops/paper_id_norm.py" "$T/02_Infrastructure/ops/"
  cp "$ROOT/02_Infrastructure/ops/paper_router_prompt.md" "$T/02_Infrastructure/ops/"
  printf '[{"arxiv_id":"2211.04695","title":"Known Paper A","paper_key":"axv:2211.04695"}]\n' > "$T/06_Registry/paper_registry.json"
  if [ "$novel" = "1" ]; then
    printf '{"date":"%s","candidates":[{"arxiv_id":"2211.04695","paper_key":"axv:2211.04695","title":"Known Paper A"},{"arxiv_id":"2509.00001","paper_key":"axv:2509.00001","title":"Brand New Paper"}]}\n' "$TODAY" > "$T/stage_artifacts/paper_recharge/mcp_discovery_${TODAY}.json"
    printf 'downloaded=0\nmcp_candidates=2\n' > "$T/stage_artifacts/paper_recharge/paper_recharge_${TODAY}.done"
  else
    printf '{"date":"%s","candidates":[{"arxiv_id":"2211.04695","paper_key":"axv:2211.04695","title":"Known Paper A"}]}\n' "$TODAY" > "$T/stage_artifacts/paper_recharge/mcp_discovery_${TODAY}.json"
    printf 'downloaded=0\nmcp_candidates=1\n' > "$T/stage_artifacts/paper_recharge/paper_recharge_${TODAY}.done"
  fi
  # 가짜 claude — 호출 흔적만 남긴다
  printf '#!/bin/bash\necho called > "%s/claude_called"\nexit 0\n' "$T" > "$T/bin/claude"; chmod +x "$T/bin/claude"
}
run_router() {  # $1=픽스처  $2=추가 env(문자열)
  local T="$1"; shift
  ( cd "$T" && env QM_ROOT="$T" CLAUDE_PROJECT_DIR="$T" QVEST_PY="$PY" \
        QVEST_PAPER_ROUTER_ENABLE=1 QVEST_RUN_NOTIFY=0 QVEST_UNATTENDED=0 \
        CLAUDE_CODE_OAUTH_TOKEN="fixture-token-not-real" PATH="$T/bin:$PATH" "$@" \
        bash "$SRC" ) >/dev/null 2>&1
}
LOGF() { echo "$1/.cache/scheduler_logs/paper_router_${TODAY}.log"; }

echo "--- A. 후보 전건 기존 키 → claude 미호출 · 스텁 기록 ---"
TA="$(mktemp -d)"; mkfx "$TA" 0; run_router "$TA"
[ -f "$TA/claude_called" ] && ng "A1 claude 호출됨" "신규 0 인데 LLM 트리아지가 떴다(매일 5분·메시지 2건 재발)" || ok "A1 claude 미호출"
RJ="$TA/stage_artifacts/paper_recharge/alpha_search_route_${TODAY}.json"
if [ -f "$RJ" ] && "$PY" -c "
import json,io,sys; d=json.load(io.open(sys.argv[1],encoding='utf-8'))
assert d.get('generated_by')=='prefilter' and d['counts_by_route']['skip']==1 and d['counts_by_route']['replication']==0
p=d['papers'][0]; assert p['route']=='skip' and p['paper_key']=='axv:2211.04695' and p.get('verdict')=='redundant'" "$RJ" 2>/dev/null; then
  ok "A2 route 스텁(generated_by=prefilter · skip 1 · verdict redundant) — 내일 백로그 축이 재소비하지 않는다"
else ng "A2 스텁" "route JSON 부재 또는 스키마 불일치: $(head -c 300 "$RJ" 2>/dev/null)"; fi
grep -q 'prefilter: 후보 1 전건 기존 paper_key' "$(LOGF "$TA")" 2>/dev/null && ok "A3 로그에 사유 명시" || ng "A3 로그" "$(tail -3 "$(LOGF "$TA")" 2>/dev/null | tr '\n' ' ')"
rm -rf "$TA"

echo "--- B. 양성 대조: 신규 키 1건 → 필터 통과 · 스텁 없음 · claude 호출 ---"
TB="$(mktemp -d)"; mkfx "$TB" 1; run_router "$TB"
grep -q 'prefilter: 신규 paper_key 1건' "$(LOGF "$TB")" 2>/dev/null && ok "B1 신규 1건 계수" || ng "B1 계수" "$(grep prefilter "$(LOGF "$TB")" 2>/dev/null | tail -2 | tr '\n' ' ')"
# 스텁은 신규가 있으면 쓰지 않는다(claude 가 route 를 쓴다). 가짜 claude 는 route 를 안 쓰므로 파일 부재가 정상.
if [ -f "$TB/stage_artifacts/paper_recharge/alpha_search_route_${TODAY}.json" ] && grep -q '"generated_by": "prefilter"' "$TB/stage_artifacts/paper_recharge/alpha_search_route_${TODAY}.json"; then
  ng "B2 신규 있는데 스텁 기록" "신규 논문이 redundant 로 닫힌다 — 필터가 삭제 방향으로 새는 결함"
else ok "B2 신규 있으면 스텁 없음"; fi
[ -f "$TB/claude_called" ] && ok "B3 claude 트리아지 호출됨 (양성 대조 — 필터가 신규를 막지 않는다)" \
  || ng "B3 claude 미호출" "신규가 있는데도 LLM 이 안 떴다: $(tail -4 "$(LOGF "$TB")" 2>/dev/null | tr '\n' ' ')"
rm -rf "$TB"

echo "--- C. DRYRUN=1 → 스텁 미기록 ---"
TC="$(mktemp -d)"; mkfx "$TC" 0; run_router "$TC" QVEST_PAPER_ROUTER_DRYRUN=1
[ -f "$TC/stage_artifacts/paper_recharge/alpha_search_route_${TODAY}.json" ] && ng "C1 DRYRUN 에서 스텁 기록" "DRYRUN 테스트가 stage_artifacts 를 오염한다" || ok "C1 DRYRUN 에서 스텁 없음"
grep -q 'DRYRUN' "$(LOGF "$TC")" 2>/dev/null && ok "C2 DRYRUN 경로 유지" || ng "C2 DRYRUN" "$(tail -2 "$(LOGF "$TC")" 2>/dev/null | tr '\n' ' ')"
rm -rf "$TC"

fin
