#!/usr/bin/env bash
#==============================================================================
# seam_repair_locked.sh — RAWDATA 이음매 소급 정정을 리프레시 배리어 writer 잠금 아래에서 (2026-11-13)
#
# 왜: seam_scale_repair.R --apply 는 .cache/RAWDATA.parquet 을 통째로 다시 쓴다. 측정 러너(round.sh · 충실구현 레인 · 사슬 틱)는
#   배리어(02_Infrastructure/ops/refresh_barrier.sh)를 읽고 기다린다 — 그래서 쓰는 동안 writer 잠금을 쥔다.
#   리프레시 잠금이 잡혀 있으면(적재 중) 시작하지 않는다(종료 10). 끝나면 독립 감사(CLI)로 저장본을 다시 잰다.
#
# 사용: bash 02_Infrastructure/data/seam_repair_locked.sh            # 건식(잠금 없이 · 미변경)
#       bash 02_Infrastructure/data/seam_repair_locked.sh --apply    # 실쓰기(잠금 아래)
# 종료: 0 정상 · 10 배리어 held · 11 잠금 획득 실패 · 1 정정 실패 · 3 정정 뒤 감사 경보(새 단절 · 경보일 남음)
#==============================================================================
set -u
ROOT="${QM_ROOT:-C:/Users/99922/OneDrive/Quant_Module_Moltbot}"; ROOT="${ROOT//\\//}"
cd "$ROOT" || exit 1
APPLY=0; [ "${1:-}" = "--apply" ] && APPLY=1
RS="Rscript"
if [ "$APPLY" != "1" ]; then
  "$RS" -e 'source("02_Infrastructure/data/seam_scale_repair.R")'; exit $?
fi
# shellcheck source=/dev/null
source 02_Infrastructure/ops/refresh_barrier.sh
rb_status
if [ "${RB_STATE:-}" = "held" ]; then rb_line; echo "[seam_repair_locked] 배리어 held — 적재 · 리프레시 중이라 시작하지 않는다"; exit 10; fi
rb_writer_acquire "seam_repair" || { echo "[seam_repair_locked] writer 잠금 획득 실패"; exit 11; }
trap 'rb_writer_release' EXIT
echo "[seam_repair_locked] writer 잠금 보유(pid $$) — $(date '+%F %T')"
QVEST_SEAM_REPAIR_LOCKED=1 "$RS" -e 'source("02_Infrastructure/data/seam_scale_repair.R")' --args --apply
rc=$?
if [ "$rc" != "0" ]; then echo "[seam_repair_locked] 정정 실패 rc=$rc"; exit 1; fi
"$RS" 02_Infrastructure/data/rawdata_seam_audit.R --label after_repair
arc=$?
echo "[seam_repair_locked] 정정 뒤 독립 감사 rc=$arc · 잠금 해제 — $(date '+%F %T')"
[ "$arc" = "0" ] && exit 0 || exit 3
