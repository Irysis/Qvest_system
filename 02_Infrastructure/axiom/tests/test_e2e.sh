#!/usr/bin/env bash
# v8.0 axiom engine E2E smoke (Windows-native, 3-mode 2-tier r7-복원)
# 실행: bash 02_Infrastructure/axiom/tests/test_e2e.sh
set -u
DIR=$(ls -d /g/Quant_Module_Moltbot /mnt/g/Quant_Module_Moltbot 2>/dev/null | head -1)
[ -z "$DIR" ] && DIR="G:/Quant_Module_Moltbot"
cd "$DIR" || exit 2
export CLAUDE_PROJECT_DIR="$DIR" PYTHONUTF8=1
PY="${QVEST_PY:-C:/Users/User/anaconda3/python.exe}"
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
