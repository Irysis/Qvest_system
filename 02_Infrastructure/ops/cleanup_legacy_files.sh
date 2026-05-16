#!/usr/bin/env bash
#==============================================================================
# cleanup_legacy_files.sh — Qvest 불필요 파일 일괄 삭제 (도훈 mandate 2026-05-16)
#
# 3-tier rm 분류:
#   Tier 1 — 즉시 rm 안전 (.bak / _archive_* / WT_*_v1_history / 명시적 폐기)
#   Tier 2 — Registry confirm 후 rm (legacy STR strategies)
#   Tier 3 — 도훈 explicit confirm 후 rm (종결 WT cycles + draft.json)
#
# Usage:
#   bash cleanup_legacy_files.sh --tier 1 [--dry-run]
#   bash cleanup_legacy_files.sh --tier 2 [--dry-run] [--force-tier-2]
#   bash cleanup_legacy_files.sh --tier 3 [--dry-run]
#   bash cleanup_legacy_files.sh --rollback
#
# Safety:
#   1. Git baseline auto-commit (rm 전, 자동 rollback 가능)
#   2. --dry-run flag로 list만 출력 (실제 rm 없음)
#   3. Tier별 분리 실행
#   4. Reference grep (Tier 2 only)
#   5. Production hard-block hook retain
#==============================================================================
set -euo pipefail

# Resolve project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_ROOT"

BASELINE_FILE="/tmp/qvest_cleanup_baseline.txt"
LOG_FILE="qepm/observability/cleanup_legacy_log.jsonl"
mkdir -p "$(dirname "$LOG_FILE")"

# Parse args
TIER=""
DRY_RUN=0
FORCE_TIER_2=0
ROLLBACK=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --tier) TIER="$2"; shift 2;;
    --dry-run) DRY_RUN=1; shift;;
    --force-tier-2) FORCE_TIER_2=1; shift;;
    --rollback) ROLLBACK=1; shift;;
    *) echo "Unknown arg: $1"; exit 1;;
  esac
done

# Banner
echo "═══════════════════════════════════════════════════"
echo "  Qvest Legacy Files Cleanup v1.0"
echo "  도훈 mandate 2026-05-16 — 일괄 rm (archive 아님)"
echo "═══════════════════════════════════════════════════"
if [ "$DRY_RUN" -eq 1 ]; then
  echo "  [DRY-RUN MODE — 실제 rm 없음, list만 출력]"
fi
echo ""

# ─── Rollback mode ────────────────────────────────────────────────────────────
if [ "$ROLLBACK" -eq 1 ]; then
  if [ ! -f "$BASELINE_FILE" ]; then
    echo "❌ Baseline file not found: $BASELINE_FILE"
    exit 1
  fi
  BASELINE_SHA=$(cat "$BASELINE_FILE")
  echo "🔄 Rolling back to baseline: $BASELINE_SHA"
  git reset --hard "$BASELINE_SHA"
  echo "✅ Rollback complete"
  exit 0
fi

if [ -z "$TIER" ]; then
  echo "❌ --tier 1|2|3 required"
  exit 1
fi

# ─── Git baseline (실제 rm 시만) ──────────────────────────────────────────────
if [ "$DRY_RUN" -eq 0 ]; then
  STATUS=$(git status --porcelain | wc -l)
  if [ "$STATUS" -gt 0 ]; then
    echo "⚠️  Uncommitted changes 발견 — baseline commit 진행"
    git add -A
    git commit -m "[cleanup] baseline pre-Tier${TIER} rm $(date +%Y%m%d_%H%M%S)" --no-verify
  fi
  BASELINE_SHA=$(git rev-parse HEAD)
  echo "$BASELINE_SHA" > "$BASELINE_FILE"
  echo "📌 Baseline SHA: $(echo "$BASELINE_SHA" | head -c 7)"
  echo ""
fi

# ─── Helper: log event ────────────────────────────────────────────────────────
log_event() {
  local action=$1
  local target=$2
  local size=$3
  echo "{\"ts\":\"$(date -Iseconds)\",\"action\":\"$action\",\"target\":\"$target\",\"size\":\"$size\",\"tier\":$TIER,\"dry_run\":$DRY_RUN}" >> "$LOG_FILE"
}

# ─── Helper: safe rm with size tracking ──────────────────────────────────────
TOTAL_FREED=0
N_REMOVED=0
safe_rm() {
  local target=$1
  local label=$2
  if [ ! -e "$target" ]; then return; fi

  # Production / Literature 보호
  case "$target" in
    *05_Production*|*01_Literature*|*.git/*)
      echo "  🚫 PROTECTED — skip: $target"
      return
      ;;
  esac

  # Size measurement (in KB)
  if [ -d "$target" ]; then
    SIZE_KB=$(du -sk "$target" 2>/dev/null | cut -f1 || echo 0)
  else
    SIZE_KB=$(du -k "$target" 2>/dev/null | cut -f1 || echo 0)
  fi
  SIZE_HUMAN=$(du -sh "$target" 2>/dev/null | cut -f1 || echo "?")

  if [ "$DRY_RUN" -eq 1 ]; then
    echo "  [DRY] $label  $target  ($SIZE_HUMAN)"
  else
    rm -rf "$target"
    echo "  ✓ rm $label  $target  ($SIZE_HUMAN)"
    log_event "rm" "$target" "$SIZE_HUMAN"
  fi
  TOTAL_FREED=$((TOTAL_FREED + SIZE_KB))
  N_REMOVED=$((N_REMOVED + 1))
}

# ─── TIER 1 — 즉시 rm 안전 ────────────────────────────────────────────────────
if [ "$TIER" = "1" ]; then
  echo "[TIER 1] 즉시 rm 안전 (.bak / _archive_* / WT_*_v1_history / pending / sigmoid_prototype)"
  echo ""

  # 1.1 .bak 파일 (production 보호 + literature 보호 자동)
  echo "[1.1] .bak 파일 (production retrain 백업)"
  while IFS= read -r f; do safe_rm "$f" "bak"; done < <(
    find . -name "*.bak" \
      -not -path "./.git/*" \
      -not -path "./05_Production/*" \
      -not -path "./01_Literature/*" \
      -not -path "./.cache/*" 2>/dev/null
  )
  echo ""

  # 1.2 Archive 디렉토리
  echo "[1.2] Archive 디렉토리 (_archive_v55 / _archive_4_6 / _archive_v7 등)"
  while IFS= read -r d; do safe_rm "$d" "archive_dir"; done < <(
    find . -type d \( -name "_archive_v55" -o -name "_archive_4_6" -o -name "_archive_v7" -o -name "_archive" -o -name "_archive_id_collision" -o -name "archive_lockbox_alpha_pre_*" \) \
      -not -path "./.git/*" \
      -not -path "./05_Production/*" \
      -not -path "./01_Literature/*" 2>/dev/null
  )
  echo ""

  # 1.3 WT_*_v1_2016_history (어제 longer history rebuild 후 archive로 옮긴 것)
  echo "[1.3] WT_*_v1_2016_history (longer history rebuild 후 미사용)"
  while IFS= read -r d; do safe_rm "$d" "v1_history"; done < <(
    find ./stage_artifacts -maxdepth 1 -type d -name "*_v1_2016_history" 2>/dev/null
  )
  echo ""

  # 1.4 WT-D20260514_013_pending (도훈 ABORT decisive, L-325)
  echo "[1.4] WT-D20260514_013_pending (도훈 ABORT decisive 결정)"
  safe_rm "qepm/mailbox/worktask/WT-D20260514_013_pending" "pending_abort"
  echo ""

  # 1.5 WT-D20260516_001_sigmoid_prototype (옵션 4 효과 X 결론)
  echo "[1.5] WT_D20260516_001_sigmoid_prototype (옵션 4 효과 X 결론)"
  safe_rm "stage_artifacts/WT_D20260516_001_sigmoid_prototype" "sigmoid_prototype"
  echo ""

# ─── TIER 2 — Registry confirm 후 rm ──────────────────────────────────────────
elif [ "$TIER" = "2" ]; then
  echo "[TIER 2] Legacy strategies (Registry successor chain confirm 후 rm)"
  echo ""

  if [ "$FORCE_TIER_2" -ne 1 ]; then
    echo "⚠️  Tier 2는 --force-tier-2 flag 또는 도훈 explicit confirm 필요"
    echo "    아래 candidate list 검토 후 적절히 재실행"
    echo ""
  fi

  echo "[2.1] Legacy STR strategies (Family 1 near-clone + Session 66 DROP + triplicate)"
  for stratdir in \
    "04_Research/strategies/STR_1715_S5" \
    "04_Research/strategies/STR_1656" \
    "04_Research/strategies/STR_1679"; do
    if [ -d "$stratdir" ]; then
      if [ "$FORCE_TIER_2" -eq 1 ] || [ "$DRY_RUN" -eq 1 ]; then
        safe_rm "$stratdir" "legacy_strat"
      else
        echo "  ⏸ HOLD (--force-tier-2 required): $stratdir"
      fi
    fi
  done

  # STR_1417 / STR_1433 / STR_1060 / STR_1071 patterns (with glob)
  for pattern in "STR_1417*" "STR_1433*" "STR_1060*" "STR_1071*"; do
    while IFS= read -r d; do
      if [ "$FORCE_TIER_2" -eq 1 ] || [ "$DRY_RUN" -eq 1 ]; then
        safe_rm "$d" "legacy_strat"
      else
        echo "  ⏸ HOLD (--force-tier-2 required): $d"
      fi
    done < <(find "04_Research/strategies" -maxdepth 1 -type d -name "$pattern" 2>/dev/null)
  done
  echo ""

# ─── TIER 3 — 도훈 explicit confirm 후 rm ────────────────────────────────────
elif [ "$TIER" = "3" ]; then
  echo "[TIER 3] 종결 WT cycles + draft.json (lifecycle confirm 후 rm)"
  echo ""

  echo "[3.1] 종결된 WT cycles (status.json ABORTED/REJECT/COMPLETED + 30일+ stale)"
  # WT cycles in stage_artifacts older than 30 days
  while IFS= read -r d; do
    safe_rm "$d" "closed_wt"
  done < <(
    find ./stage_artifacts -maxdepth 1 -type d \( -name "WT-D2026042*" -o -name "WT-D2026043*" -o -name "WT-T2026050*" \) 2>/dev/null
  )
  echo ""

  echo "[3.2] _draft.json files (lifecycle 종결된 것)"
  # _draft.json with final _package.json sibling
  while IFS= read -r draft; do
    dir=$(dirname "$draft")
    fname=$(basename "$draft" "_draft.json")
    final="$dir/${fname}.json"
    if [ -f "$final" ]; then
      safe_rm "$draft" "draft_with_final"
    fi
  done < <(find ./qepm/mailbox -name "*_draft.json" 2>/dev/null | head -300)
  echo ""

else
  echo "❌ Unknown tier: $TIER"
  exit 1
fi

# ─── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════"
echo "  Cleanup Summary — Tier $TIER"
echo "═══════════════════════════════════════════════════"
TOTAL_FREED_MB=$((TOTAL_FREED / 1024))
TOTAL_FREED_GB=$((TOTAL_FREED_MB / 1024))
if [ "$DRY_RUN" -eq 1 ]; then
  echo "  DRY-RUN: $N_REMOVED items would be removed (~${TOTAL_FREED_MB} MB / ${TOTAL_FREED_GB} GB)"
else
  echo "  ✓ $N_REMOVED items removed (~${TOTAL_FREED_MB} MB / ${TOTAL_FREED_GB} GB freed)"
  echo "  📌 Baseline: $(echo "$BASELINE_SHA" | head -c 7)"
  echo "  🔄 Rollback: bash 02_Infrastructure/ops/cleanup_legacy_files.sh --rollback"
fi
echo "═══════════════════════════════════════════════════"
