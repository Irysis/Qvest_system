#!/usr/bin/env bash
#==============================================================================
# test_scn_knowledge_distill.sh — 주간 증류 재료가 v10.2 학습 고리를 싣는가 (감사 레인 K · 2026-11-10)
#   격리: 임시 루트(QVEST_CD_ROOT) · 운영 pending · 원장 무쓰기 · LLM · 텔레그램 없음(materials 만 부른다).
#   D1 승격 기계 퇴역(axiom_engine_status.promotion_enabled=false) → §1b 학습 고리(라운드 · 탐침) 실림 · §3 DIST 초안 0건(퇴역) · DIST id 없음
#   D2 [양성 대조] 상태 파일 없음 → 종전 동작(DIST 후보 실림) — 분기가 실제로 갈린다
#   D3 결과 원장 손상 줄 → 재료는 만들어지고 '원장 손상' 경고가 실린다(조용히 넘기지 않는다)
#   D4 열린 탐침 = 이어받은 것 제외
#   D5 증류 프롬프트가 퇴역 분기를 안다(② 건너뛰기 · 의무 절 = 학습 고리)
#==============================================================================
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LIB="$REPO/02_Infrastructure/ops/cleaner_distill_lib.R"
[ -f "$LIB" ] || { echo "코드 루트 해석 실패: $REPO"; exit 1; }
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); echo "  OK   $1"; }
ng(){ FAIL=$((FAIL+1)); echo "  FAIL $1 — ${2:-}"; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/06_Registry" "$T/.cache" "$T/02_Infrastructure/memory" "$T/04_Research/01_reports/weekly"
cp "$REPO/06_Registry/cleaner_protected_paths.json" "$T/06_Registry/"
cp "$REPO/02_Infrastructure/memory/knowledge_loop_metrics.R" "$T/02_Infrastructure/memory/"
cat > "$T/.cache/cleaner_pending.json" <<'EOF'
{"schema":"cleaner_pending_v2","week_of":"2026-W46","status":"awaiting_distill","distill_status":"pending",
 "sweep_deleted_n":0,"inventory":{"stage_artifacts_new":{"n":0},"new_lcodes":{"n":0},"git_log_7d":{"n_commits":1}},
 "axiom_candidates":{"n_pending":5,"activated_axioms":[],"held_axioms":[]}}
EOF
cat > "$T/06_Registry/distilled_knowledge.json" <<'EOF'
{"entries":[{"dist_id":"DIST-KD-001","status":"pending_5axis","n_supporting":3,"polarity":"negative","statement_draft":"d","supporting_l_codes":[]}]}
EOF
NOW="$(date +%Y-%m-%dT%H:%M:%S)+0900"
cat > "$T/06_Registry/round_outcomes.jsonl" <<EOF
{"schema":"round_outcome_v1","kind":"round","at":"$NOW","program":"P2_DEFENSE","round_id":"P2R90","template":"p2_device","n_cells":2,"n_variants":1,"probes":["탐침 하나","탐침 둘"],"lessons":["교훈"],"r7":"noise"}
{"schema":"round_outcome_v1","kind":"probe_consumed","at":"$NOW","ref":"P2R90#1","by":"P2R91","program":"P2_DEFENSE"}
EOF
mat(){ QVEST_CD_ROOT="$T" QM_ROOT="$T" CLAUDE_PROJECT_DIR="$T" R_ENVIRON_USER="$T/.Renviron_empty" Rscript "$LIB" materials "$1" >/dev/null 2>&1; }
: > "$T/.Renviron_empty"

echo "[D1] 퇴역 상태"
echo '{"promotion_enabled": false}' > "$T/06_Registry/axiom_engine_status.json"
mat "$T/m1.txt"; M="$T/m1.txt"
[ -s "$M" ] && ok "D1a 재료 생성" || ng "D1a 재료 생성" "빈 파일"
grep -q "## 1b. v10.2 학습 고리" "$M" && grep -q "닫힌 라운드 누계 1" "$M" && ok "D1b §1b 학습 고리(라운드 누계 1)" || ng "D1b §1b" "$(grep -n '1b\|학습 고리' "$M" | head -3)"
grep -q "DIST 초안 대상 0건 (퇴역" "$M" && ok "D1c §3 DIST 초안 0건(퇴역)" || ng "D1c §3 퇴역 안내"
grep -q "DIST-KD-001" "$M" && ng "D1d DIST id 없음" "퇴역인데 DIST 후보가 실렸다" || ok "D1d DIST id 없음"

echo "[D4] 열린 탐침"
grep -q "열린 탐침 P2R90#2" "$M" && ! grep -q "열린 탐침 P2R90#1" "$M" && ok "D4 이어받은 P2R90#1 제외 · #2 실림" || ng "D4 열린 탐침" "$(grep -n '열린 탐침' "$M")"

echo "[D2] 양성 대조 — 상태 파일 없음"
rm -f "$T/06_Registry/axiom_engine_status.json"
mat "$T/m2.txt"
grep -q "DIST-KD-001" "$T/m2.txt" && ok "D2 종전 동작 — DIST 후보 실림(분기가 실제로 갈린다)" || ng "D2 종전 동작" "DIST 후보 없음"

echo "[D3] 결과 원장 손상"
echo '{"promotion_enabled": false}' > "$T/06_Registry/axiom_engine_status.json"
printf '%s\n' '{"schema":"round_outcome_v1","kind":"round",' >> "$T/06_Registry/round_outcomes.jsonl"
mat "$T/m3.txt"
[ -s "$T/m3.txt" ] && grep -q "원장 손상 줄: outcomes 1" "$T/m3.txt" && ok "D3 손상 1줄 경고 · 재료는 생성" || ng "D3 손상 경고" "$(head -c 300 "$T/m3.txt")"

echo "[D5] 증류 프롬프트"
RUN="$REPO/02_Infrastructure/ops/cleaner_distill_run.sh"
grep -q "이 절 전체를 건너뛰고" "$RUN" && grep -q "학습 고리 현황" "$RUN" && ok "D5 프롬프트 = ② 퇴역 건너뛰기 · 의무 절 학습 고리" || ng "D5 프롬프트"

echo "{\"test\":\"test_scn_knowledge_distill\",\"pass\":$PASS,\"fail\":$FAIL,\"total\":$((PASS+FAIL))}"
[ "$FAIL" -eq 0 ]
