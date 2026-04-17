#!/bin/bash
#==============================================================================
# cleanup.sh — 작업폴더 위생 관리
# Usage: bash 02_Infrastructure/cleanup.sh [--dry-run|--execute]
# Default: --dry-run (리포트만, 삭제 없음)
#==============================================================================

source "$(dirname "${BASH_SOURCE[0]:-$0}")/resolve_project.sh"
cd "$PROJECT"

MODE="${1:---dry-run}"
TOTAL_COUNT=0
TOTAL_BYTES=0

log() { echo "[cleanup] $1"; }

count_and_delete() {
  local label="$1"
  shift
  local files=("$@")
  local count=${#files[@]}
  local bytes=0

  if [ "$count" -eq 0 ] || [ ! -e "${files[0]}" ]; then
    return
  fi

  for f in "${files[@]}"; do
    [ -f "$f" ] && bytes=$((bytes + $(stat -f%z "$f" 2>/dev/null || stat -c%s "$f" 2>/dev/null || echo 0)))
  done

  TOTAL_COUNT=$((TOTAL_COUNT + count))
  TOTAL_BYTES=$((TOTAL_BYTES + bytes))
  local mb=$((bytes / 1024 / 1024))

  if [ "$MODE" = "--execute" ]; then
    for f in "${files[@]}"; do
      [ -f "$f" ] && rm -f "$f"
    done
    log "$label: ${count}건 삭제 (${mb}MB)"
  else
    log "$label: ${count}건 대상 (${mb}MB)"
  fi
}

log "=== Cleanup $(date '+%Y-%m-%d %H:%M') — $MODE ==="

# 1. Rplots.pdf (프로젝트 전체, 01_Literature/05_Production 제외)
mapfile -t RPLOTS < <(find "$PROJECT" -name "Rplots.pdf" -not -path "*/01_Literature/*" -not -path "*/05_Production/*" -type f 2>/dev/null)
count_and_delete "Rplots.pdf" "${RPLOTS[@]}"

# 2. /tmp 로그 (7일+)
mapfile -t TMPLOGS < <(find /tmp -maxdepth 1 -name "qm_*.log" -mtime +7 -type f 2>/dev/null)
count_and_delete "/tmp 로그 (7일+)" "${TMPLOGS[@]}"

# 3. Research 로그 (30일+)
mapfile -t RLOGS < <(find "$PROJECT/04_Research/logs" -name "*.log" -mtime +30 -type f 2>/dev/null)
count_and_delete "Research 로그 (30일+)" "${RLOGS[@]}"

# 4. Mailbox DONE (14일+)
mapfile -t DONE < <(find "$PROJECT/qepm/mailbox" -name "DONE_*" -mtime +14 -type f 2>/dev/null)
count_and_delete "Mailbox DONE (14일+)" "${DONE[@]}"

# 5. Mailbox processed (14일+)
mapfile -t PROC < <(find "$PROJECT/qepm/mailbox" -path "*/processed/*" -mtime +14 -type f 2>/dev/null)
count_and_delete "Mailbox processed (14일+)" "${PROC[@]}"

# 6. .cache 백업 (3일+)
mapfile -t BACKUPS < <(find "$PROJECT/.cache" -name "*_backup_*" -mtime +3 -type f 2>/dev/null)
count_and_delete ".cache 백업 (3일+)" "${BACKUPS[@]}"

# 7. .cache 빈 하위폴더 제거
if [ "$MODE" = "--execute" ]; then
  EMPTY_DIRS=$(find "$PROJECT/.cache" -maxdepth 1 -type d -empty 2>/dev/null | wc -l)
  find "$PROJECT/.cache" -maxdepth 1 -type d -empty -delete 2>/dev/null
  [ "$EMPTY_DIRS" -gt 0 ] && log ".cache 빈 폴더: ${EMPTY_DIRS}건 삭제"
else
  EMPTY_DIRS=$(find "$PROJECT/.cache" -maxdepth 1 -type d -empty 2>/dev/null | wc -l)
  [ "$EMPTY_DIRS" -gt 0 ] && log ".cache 빈 폴더: ${EMPTY_DIRS}건 대상"
fi

# 8. .cache 고아 파일 (참조 코드 없는 잔재)
ORPHANS=(
  "$PROJECT/.cache/unused_high_icir_factors.csv"
  "$PROJECT/.cache/stage0_pass_factors.json"
  "$PROJECT/.cache/regime_research_turb_corr.rds"
  "$PROJECT/.cache/regime_research_novel_corr.rds"
  "$PROJECT/.cache/regime_research_endo_corr.rds"
  "$PROJECT/.cache/pg2_artifact_STR_1555.rds"
  "$PROJECT/.cache/pg1_artifact_STR_1555.rds"
  "$PROJECT/.cache/pg1_artifact_STR_1550.rds"
  "$PROJECT/.cache/pg0_artifact_STR_1555.rds"
  "$PROJECT/.cache/pg0_artifact_STR_1550.rds"
  "$PROJECT/.cache/factor_ic_summary_v2.csv"
  "$PROJECT/.cache/factor_synergy_pairs_v2.csv"
)
EXISTING_ORPHANS=()
for f in "${ORPHANS[@]}"; do [ -f "$f" ] && EXISTING_ORPHANS+=("$f"); done
count_and_delete ".cache 고아 파일" "${EXISTING_ORPHANS[@]}"

# 9. 디스크 리포트
log "=== 폴더별 용량 ==="
du -sh "$PROJECT"/0*/ "$PROJECT"/.cache/ 2>/dev/null | sort -rh

TOTAL_MB=$((TOTAL_BYTES / 1024 / 1024))
log "=== 합계: ${TOTAL_COUNT}건, ${TOTAL_MB}MB ($MODE) ==="
