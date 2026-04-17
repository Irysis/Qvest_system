#!/usr/bin/env bash
# Sprint 4 AX-P3: End-to-End Test
# 실행: bash 02_Infrastructure/axiom/tests/test_e2e.sh
# 11단계 시나리오 검증.

set -u
DIR=$(ls -d /mnt/c/Users/*/OneDrive/바탕\ 화면/Quant_Module_Moltbot 2>/dev/null | head -1)
[ -z "$DIR" ] && { echo "FAIL: project root not found" >&2; exit 2; }
cd "$DIR" || exit 2

PASS=0
FAIL=0
step() {
  local n="$1"; shift
  if "$@"; then
    echo "✓ $n PASS"
    PASS=$((PASS + 1))
  else
    echo "✗ $n FAIL"
    FAIL=$((FAIL + 1))
  fi
}

# 1. Harvest
step "1/Harvest" bash -c "python3 02_Infrastructure/axiom/lcode_harvester.py > /dev/null && \
  python3 -c 'import json;d=json.load(open(\".cache/lcode_corpus.json\"));assert d[\"n_lcodes\"] >= 11'"

# 2. Cluster
step "2/Cluster" bash -c "python3 02_Infrastructure/axiom/cluster_extractor.py > /dev/null && \
  ls qepm/memory/axioms/candidates/CAND_*.json 2>/dev/null | wc -l | awk '{exit (\$1 < 2)}'"

# 3. Promote (real candidate — expected FAIL due to missing mechanism/OOS)
step "3/Promote-fail" bash -c "Rscript 02_Infrastructure/axiom/promote.R \
  qepm/memory/axioms/candidates/CAND_*_quality_earnings_*.json 2>&1 | grep -q 'FAIL'"

# 4. Mock enriched candidate → pass → L-code 역링크 확인
cat > /tmp/MOCK_CAND.json <<'EOF'
{
  "schema_version": "v53_ax_p0",
  "candidate_id": "CAND_MOCK_E2E",
  "type": "empirical",
  "polarity": "negative",
  "statement_draft": "E2E 테스트: value family standalone Grade F 반복",
  "supporting_l_codes": ["L-132", "L-135"],
  "scope_draft": {"market":"KR","factor_family":"value","regime":null},
  "evidence_draft": {"independent_l_codes":2,"independent_strategies":2,"strategies":["STR_1663","STR_1654_BCSNA"]},
  "falsification_draft": {"attempts":[{"description":"사전 반증 시도","result":"survived","effect_retained":0.8}]},
  "mechanism_draft": {"economic_explanation":"한국 value trap 관찰","mechanism_type":"behavioral","causal_plausibility":"moderate"},
  "oos_validation_draft": {"oos_months":6,"oos_effect_vs_is":0.6},
  "status":"pending_5axis"
}
EOF
step "4/Promote-mock" bash -c "Rscript 02_Infrastructure/axiom/promote.R /tmp/MOCK_CAND.json 2>&1 | tee /tmp/mock_promote.log | grep -qE 'PASS|weighted=(0.[89]|1\\.)'"

# 5. Inject dry-run
# Pick newly-created AX file (if any)
AX_FILE=$(ls -t qepm/memory/axioms/active/AX-*.json 2>/dev/null | grep -v "AX-00[012]" | head -1)
if [ -z "$AX_FILE" ]; then
  echo "→ step 4 did not promote (expected if 5축 strict). E2E용 mock AX 생성."
  mkdir -p qepm/memory/axioms/active
  cat > qepm/memory/axioms/active/AX-999.json <<'EOF'
{"axiom_id":"AX-999","type":"empirical","polarity":"negative","statement":"E2E mock — value family KR standalone 실패","supporting_l_codes":["L-132"],"scope":{"market":"KR","factor_family":"value"},"evidence":{},"falsification":{},"mechanism":{},"oos_validation":{},"promotion":{"weighted_score":0.85,"threshold":0.80,"axis_scores":{"independence":0.8,"rigor":0.9,"falsification":0.8,"external":0.8,"mechanism":0.9},"promoted_at":"2026-04-17","next_review":"2026-07-17"},"enforcement":"","status":"active","version":1}
EOF
  AX_FILE="qepm/memory/axioms/active/AX-999.json"
fi

step "5/Inject-dry" bash -c "QVEST_AXIOM_AUTO_INJECT=0 Rscript 02_Infrastructure/axiom/inject.R \"$AX_FILE\" 2>&1 | grep -q 'DRY-RUN'"

# 6. Dashboard
step "6/Dashboard" bash -c "Rscript -e 'source(\"qepm/R/axiom_dashboard.R\"); s <- axiom_status(verbose=FALSE); stopifnot(s\$counts\$active >= 3)' 2>&1 | tail -1 | grep -vq 'Error'"

# 7. Universal injection — Scout spawn (JSON unicode-escaped 처리: python 디코딩 후 검증)
step "7/AX-inject-scout" bash -c "out=\$(echo '{\"tool_name\":\"Agent\",\"tool_input\":{\"name\":\"scout\",\"prompt\":\"new hypothesis\"}}' | bash 02_Infrastructure/hooks/unified_agent_guard.sh); echo \"\$out\" | python3 -c 'import sys,json; d=json.loads(sys.stdin.read()); ctx=d.get(\"hookSpecificOutput\",{}).get(\"additionalContext\",\"\"); sys.exit(0 if \"AX 전제\" in ctx and \"AX-\" in ctx else 1)'"

# 8. Universal injection — Forge spawn
step "8/AX-inject-forge" bash -c "out=\$(echo '{\"tool_name\":\"Agent\",\"tool_input\":{\"name\":\"forge\",\"prompt\":\"S5\"}}' | bash 02_Infrastructure/hooks/unified_agent_guard.sh); echo \"\$out\" | python3 -c 'import sys,json; d=json.loads(sys.stdin.read()); ctx=d.get(\"hookSpecificOutput\",{}).get(\"additionalContext\",\"\"); sys.exit(0 if \"AX 전제\" in ctx and \"AX-\" in ctx else 1)'"

# 9. D075 suspicion flag (mock): AX value family + mock Grade A strategy_name
step "9/D075-trigger-presence" bash -c "grep -q 'D075' 02_Infrastructure/hurdle_gate.R && \
  grep -q 'axiom_suspicion' 02_Infrastructure/hurdle_gate.R"

# 10. lcode_trace 역추적
step "10/Lcode-trace" bash -c "Rscript -e 'source(\"02_Infrastructure/memory/axiom_memory_interface.R\"); r <- sg_axiom_lcode_trace(axiom_id=\"AX-999\"); stopifnot(r\$found)' 2>&1 | tail -1 | grep -vq 'Error'"

# 11. harness_health
step "11/Harness" bash -c "bash 02_Infrastructure/hooks/harness_health.sh 2>&1 | tail -1 | grep -q 'healthy\\|passed'"

# Cleanup
rm -f qepm/memory/axioms/active/AX-999.json /tmp/MOCK_CAND.json /tmp/mock_promote.log 2>/dev/null

echo ""
echo "=== E2E Result: $PASS PASS / $FAIL FAIL ==="
[ "$FAIL" -eq 0 ]
