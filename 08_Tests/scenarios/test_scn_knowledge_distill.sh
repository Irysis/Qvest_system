#!/usr/bin/env bash
#==============================================================================
# test_scn_knowledge_distill.sh — 주간 증류 재료가 v10.2 학습 고리를 싣는가 (감사 레인 K · 2026-11-10)
#   격리: 임시 루트(QVEST_CD_ROOT) · 운영 pending · 원장 무쓰기 · LLM · 텔레그램 없음(materials 만 부른다).
#   D1 승격 기계 퇴역(axiom_engine_status.promotion_enabled=false) → §1b 학습 고리(라운드 · 탐침) 실림 · §3 DIST 초안 0건(퇴역) · DIST id 없음
#   D2 [양성 대조] 상태 파일 없음 → 종전 동작(DIST 후보 실림) — 분기가 실제로 갈린다
#   D3 결과 원장 손상 줄 → 재료는 만들어지고 '원장 손상' 경고가 실린다(조용히 넘기지 않는다)
#   D4 열린 탐침 = 이어받은 것 제외
#   D5 증류 프롬프트가 퇴역 분기를 안다(② 건너뛰기 · 의무 절 = 학습 고리)
#   D6 (11-10(2) 감사 U11) 결과 원장 = 설계 입력과 같은 규율 — 격리 · 처방 입력 미통과 줄은 누계 · 열린 탐침 · 글에서 빠지고 건수 경고
#   D7 (11-10(2) 감사 U11) 프롬프트 의무 절이 재료에 없는 지표(걸음 채택률)를 요구하지 않는다 · '미측정' 지시
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
# (11-10(2) 감사 U11) 계기는 결과 원장을 round_core v1 공용 읽기(설계 입력과 같은 규율 · τ_D = behavior_card.json::tau_d)로만 읽는다
mkdir -p "$T/04_Research/programs/_lib/round_core/v1"
for f in util.R standing.R outcomes.R; do cp "$REPO/04_Research/programs/_lib/round_core/v1/$f" "$T/04_Research/programs/_lib/round_core/v1/"; done
cp "$REPO/06_Registry/behavior_card.json" "$T/06_Registry/"
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

echo "[D6] 결과 원장 = 설계 입력과 같은 규율(격리 · 처방 입력 미통과 줄 제외 · 11-10(2) 감사 U11)"
cat > "$T/06_Registry/round_outcomes.jsonl" <<EOF
{"schema":"round_outcome_v1","kind":"round","at":"$NOW","program":"P2_DEFENSE","round_id":"P2R90","template":"p2_device","n_cells":2,"n_variants":1,"probes":["탐침 하나","탐침 둘"],"lessons":["교훈"],"r7":"noise"}
{"schema":"round_outcome_v1","kind":"probe_consumed","at":"$NOW","ref":"P2R90#1","by":"P2R91","program":"P2_DEFENSE"}
{"schema":"round_outcome_v1","kind":"round","at":"$NOW","program":"P4_ASSEMBLY","round_id":"P4C97","template":"p4_chain","n_cells":2,"n_variants":1,"probes":["미통과 탐침 하나","미통과 탐침 둘"],"lessons":["전기간 A등급 후보 · 2023~2025 시험 창 Calmar 0.41"],"r7":"noise"}
EOF
QL='{"schema":"round_outcome_v1","kind":"round","at":"'"$NOW"'","program":"P2_DEFENSE","round_id":"P2R98","template":"p2_device","n_cells":2,"n_variants":1,"probes":["격리 탐침 하나","격리 탐침 둘"],"lessons":["격리 교훈"],"r7":"noise"}'
printf '%s\n' "$QL" >> "$T/06_Registry/round_outcomes.jsonl"
QM="$(printf '%s' "$QL" | md5sum | cut -d' ' -f1)"
printf '%s\n' '{"schema":"round_outcome_v1","kind":"quarantine","at":"'"$NOW"'","line_no":4,"line_md5":"'"$QM"'","reason":"시험 — 격리","copy":"x"}' >> "$T/06_Registry/round_outcomes.jsonl"
mat "$T/m6.txt"; M6="$T/m6.txt"
grep -q "닫힌 라운드 누계 1" "$M6" && ok "D6a 미통과 · 격리 줄은 닫힌 라운드 누계에 안 든다" || ng "D6a 누계" "$(grep -n '학습 고리' "$M6" | head -2)"
grep -q "열린 탐침 P4C97" "$M6" || grep -q "열린 탐침 P2R98" "$M6" && ng "D6b 미통과 · 격리 줄 탐침 제외" "$(grep -n '열린 탐침' "$M6")" || ok "D6b 미통과 · 격리 줄의 탐침은 열린 탐침에 안 실린다"
grep -q "열린 탐침 P2R90#2" "$M6" && ok "D6c 깨끗한 줄의 열린 탐침은 그대로" || ng "D6c 깨끗한 탐침" "$(grep -n '열린 탐침' "$M6")"
grep -q "격리 1 · 처방 입력 검사 미통과 1(P4C97)" "$M6" && ok "D6d 뺀 줄 건수 경고(격리 1 · 미통과 1)" || ng "D6d 뺀 줄 경고" "$(head -c 400 "$M6")"
grep -q "A등급\|시험 창 Calmar" "$M6" && ng "D6e 미통과 줄 글이 재료에 실렸다" || ok "D6e 미통과 줄의 글(등급 · 시험 창 수치)은 재료에 없다"

echo "[D7] 증류 프롬프트 — 재료에 없는 지표를 의무 절에서 요구하지 않는다(11-10(2) 감사 U11)"
OBL="$(sed -n '/의무 절 2개/,/(b) 이번 주/p' "$RUN")"
[ -n "$OBL" ] && ! printf '%s' "$OBL" | grep -q "걸음 채택률" && ok "D7a 의무 절 (a) 에 재료 밖 '걸음 채택률' 없음" || ng "D7a 의무 절" "$(printf '%s' "$OBL" | head -3)"
printf '%s' "$OBL" | grep -q "재료에 없는 지표" && printf '%s' "$OBL" | grep -q "미측정" && ok "D7b 재료에 없는 지표 = '미측정' 지시" || ng "D7b 미측정 지시"
grep -q "재료에 없다: 계산 · 추정하지 말고" "$M6" && ok "D7c 재료 §1b 자체에도 같은 안내" || ng "D7c 재료 안내"

echo "{\"test\":\"test_scn_knowledge_distill\",\"pass\":$PASS,\"fail\":$FAIL,\"total\":$((PASS+FAIL))}"
[ "$FAIL" -eq 0 ]
