#!/usr/bin/env bash
#==============================================================================
# update_research_philosophy.sh — Helper wrapper (도훈 mandate 2026-05-16)
#
# 1-command Research Philosophy amendment with 5-axis ingest automation + 5 safety mechanisms.
#
# Usage:
#   bash update_research_philosophy.sh --action add_principle \
#       --principle-id P8 --principle-name "Causal Inference for Alpha" \
#       --citation "Pearl 2009; Athey 2017 PNAS" \
#       --agents "alpha-research,risk-research,judge" [--dry-run]
#
#   bash update_research_philosophy.sh --action amend_principle \
#       --principle-id P2 --new-citation "Jensen-Kelly 2024 update"
#
#   bash update_research_philosophy.sh --action deprecate_principle \
#       --principle-id P4 --replaced-by P8
#
#   bash update_research_philosophy.sh --action verify_only [--principle-id P8]
#
#   bash update_research_philosophy.sh --action rollback
#
# Safety mechanisms (5):
#   1. Lock file (/tmp/qvest_research_philosophy_update.lock)
#   2. Atomic 5-axis update (temp → rename pattern via R)
#   3. Git baseline auto-commit (rollback safe)
#   4. Idempotent (skip if already ingested)
#   5. grep 5-axis verification (FAIL → auto git revert)
#
# Output: stdout progress + qepm/observability/research_philosophy_update_log.jsonl
#==============================================================================
set -euo pipefail

# Resolve project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
R_SCRIPT="$SCRIPT_DIR/update_research_philosophy.R"

# Pre-check
if [ ! -f "$R_SCRIPT" ]; then
  echo "❌ R script not found: $R_SCRIPT" >&2
  exit 1
fi

# Pre-check: working dir
cd "$PROJECT_ROOT"

# Banner
cat <<'EOF'
═══════════════════════════════════════════════════
   Research Philosophy Update Helper v1.0
   도훈 mandate 2026-05-16 — 5-axis ingest 자동화
═══════════════════════════════════════════════════
EOF

# Show args
echo "Invocation: $0 $@"
echo ""

# Delegate to R
Rscript --no-save --no-restore "$R_SCRIPT" "$@"
RC=$?

if [ $RC -eq 0 ]; then
  echo ""
  echo "✅ Helper completed successfully (exit $RC)"
  echo "📚 Log: qepm/observability/research_philosophy_update_log.jsonl"
else
  echo ""
  echo "❌ Helper failed (exit $RC)"
  echo "   Use '--action rollback' to revert if needed."
  exit $RC
fi
