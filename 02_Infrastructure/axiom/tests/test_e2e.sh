#!/usr/bin/env bash
# v8.0 axiom engine E2E smoke (Windows-native, 3-mode 2-tier r7-복원)
# 실행: bash 02_Infrastructure/axiom/tests/test_e2e.sh
#
# ⚠ 이 스모크는 **격리 테스트가 아니라 파이프라인 1회전**이다 (2026-07-25 판정, 도훈 승인).
#   실행하면 실환경 산출물이 실제로 갱신된다:
#     - lcode_harvester.py  → .cache/lcode_corpus.json (재생성 캐시)
#     - cluster_extractor.py → qepm/memory/axioms/candidates/CAND_*.json (파생 지식)
#   정리·복원 로직은 없다.
#
#   격리하지 않기로 한 근거:
#     (1) 검증 대상 자체가 "실제 데이터로 파이프라인이 도는가"다. 격리하면 검증이 사라진다.
#     (2) harvester 는 --out 을 줘도 **정본 .cache/lcode_corpus.json 을 항상 함께 갱신**한다
#         (lcode_harvester.py 의 --out 도움말에 명시). 즉 부분 격리가 설계상 불가.
#     (3) CAND_* 는 원천(L-code corpus)에서 결정론적으로 재계산되는 파생물이라
#         '파괴'가 아니라 '재계산'이다.
#   따라서 남는 위험은 손실이 아니라 **타이밍**이다 — 다른 세션이 CAND 상태를 관측 중일 때
#   이 스모크를 돌리면 그 관측과 어긋날 수 있다. 병렬 세션에서는 실행 전 확인할 것.
#   (읽기-오염은 없다: 자기가 생성한 산출물을 자기가 확인하는 구조 — 운영 상태에 의존하지 않음)
set -u
DIR=$(ls -d /c/Users/99922/OneDrive/Quant_Module_Moltbot /mnt/c/Users/99922/OneDrive/Quant_Module_Moltbot /g/Quant_Module_Moltbot /mnt/g/Quant_Module_Moltbot 2>/dev/null | head -1)
[ -z "$DIR" ] && DIR="G:/Quant_Module_Moltbot"
cd "$DIR" || exit 2
export CLAUDE_PROJECT_DIR="$DIR" PYTHONUTF8=1
PY="${QVEST_PY:-C:/Users/99922/AppData/Local/Programs/Python/Python312/python.exe}"
RS="${QVEST_RSCRIPT:-C:/Program Files/R/R-4.5.2/bin/Rscript.exe}"
pass=0; fail=0
ok(){ echo "  PASS $1"; pass=$((pass+1)); }
no(){ echo "  FAIL $1"; fail=$((fail+1)); }

echo "=== v8.0 axiom E2E (3-mode 2-tier r7) ==="

echo "1. harvest (mode + construction + metric_type)"
"$PY" 02_Infrastructure/axiom/lcode_harvester.py >/dev/null 2>&1
[ -f .cache/lcode_corpus.json ] && ok "corpus written" || no "corpus written"
AS=$("$PY" -c "import json;print(json.load(open('.cache/lcode_corpus.json',encoding='utf-8'))['mode_distribution'].get('alpha_search',0))" 2>/dev/null)
[ "${AS:-0}" -ge 20 ] 2>/dev/null && ok "alpha_search>=20 ($AS)" || no "alpha_search>=20 ($AS)"

echo "2. input gate (validate blocks -2028%p)"
"$RS" 02_Infrastructure/axiom/lcode_schema.R 2>&1 | grep -q PASS && ok "schema selftest" || no "schema selftest"

echo "3. cluster (mode-partition)"
"$PY" 02_Infrastructure/axiom/cluster_extractor.py >/dev/null 2>&1
ls qepm/memory/axioms/candidates/CAND_*alpha_search* >/dev/null 2>&1 && ok "alpha_search CAND" || no "alpha_search CAND"

echo "4. promote INV-4 (raw stub -> FAIL hurdle)"
CAND=$(ls qepm/memory/axioms/candidates/CAND_*alpha_search*momentum*.json 2>/dev/null | head -1)
if [ -n "$CAND" ]; then
  "$RS" 02_Infrastructure/axiom/promote.R "$CAND" 2>&1 | grep -q "FAIL" && ok "raw stub FAIL (hurdle)" || no "raw stub FAIL"
else no "alpha_search momentum CAND missing"; fi

echo "5. promote_global / rollback / weekly_report loaded"
"$RS" 02_Infrastructure/axiom/promote_global.R 2>&1 | grep -q "Loaded" && ok "promote_global" || no "promote_global"
"$RS" 02_Infrastructure/axiom/axiom_rollback.R 2>&1 | grep -q "Loaded" && ok "rollback" || no "rollback"
"$RS" 02_Infrastructure/axiom/axiom_weekly_report.R 2>&1 | grep -q "weekly_report\]" && ok "weekly_report" || no "weekly_report"

echo "6. health gate (mode-local recursive, hard 0)"
"$RS" 02_Infrastructure/memory/memory_knowledge_health.R 2>&1 | grep -q "Hard fails: 0" && ok "health hard 0" || no "health hard 0"

echo "7. dashboard (recursive, active>=8)"
DA=$("$RS" -e 'source("qepm/R/axiom_dashboard.R");cat(axiom_status(FALSE)$counts$active)' 2>/dev/null | tail -1)
[ "${DA:-0}" -ge 8 ] 2>/dev/null && ok "dashboard active>=8 ($DA)" || no "dashboard active ($DA)"

echo "=== $pass PASS / $fail FAIL ==="
[ "$fail" -eq 0 ]
