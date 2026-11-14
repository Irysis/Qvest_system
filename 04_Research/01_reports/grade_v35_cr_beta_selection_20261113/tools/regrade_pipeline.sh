#!/usr/bin/env bash
# 등급 v3.5 재채점 파이프라인 — 사전등록 부록 1 §2 를 그대로 돈다(쓰기 1회 · 원인 기록 · 같은 데이터 시점 v3.4 ↔ v3.5 드라이런 · 쓰기 전 데이터 시점 대조).
#   1) v3.4 계약 사본 루트 = 지금 HEAD 에서 등급 규칙 6파일만 교체 전 커밋(PRE_COMMIT)으로 되돌린 사본(+ .cache 정션) — 규칙 밖 코드는 운영과 같다
#   2) 저장 기록 전수 → 대상 목록(규칙 범위 ∪ 요인 낡음 ∪ 교체 걸친 불완전 ∪ 실데이터 음성 대조 52)
#   3) 같은 목록을 v3.4(사본) · v3.5(운영) 계약으로 드라이런(동시 · 쓰기 없음)
#   4) 두 드라이런의 요인 md5 · RAWDATA 크기@시각이 같고 지금 값과도 같은지 대조 → 다르면 멈춘다(드라이런부터 다시)
#   5) 재채점 도구 드라이런(--dirs) → 6) --write 는 인자 'write' 를 줄 때만(쓰기 직전 데이터 시점을 한 번 더 대조)
# 사용: bash tools/regrade_pipeline.sh <tag> [write]
#   실행 위치 무관 · 결과 = 보고서 폴더 data/ · 로그 = 스크래치 · 끝나면 build_report.R 로 표 · 그림
set -euo pipefail
TAG=${1:?tag}; MODE=${2:-dry}
RW="G:/OneDrive/Quant_Module_Moltbot"; R=/g/OneDrive/Quant_Module_Moltbot
D="$R/04_Research/01_reports/grade_v35_cr_beta_selection_20261113"; DW="$RW/04_Research/01_reports/grade_v35_cr_beta_selection_20261113"
SPW="${V35_SCRATCH:?스크래치 폴더(V35_SCRATCH · 윈도 경로)}"; SP=$(cygpath -u "$SPW")
PRE_COMMIT=ac77e59df   # 교체 직전 HEAD(등급 규칙 6파일 = 사전등록 기준 md5)
RULES=(02_Infrastructure/contracts/grade_v3.R 02_Infrastructure/contracts/matched_controls.R 02_Infrastructure/contracts/essence_score.R
       02_Infrastructure/contracts/diagnosis_packet.R 06_Registry/grade_v3.json 06_Registry/matched_controls.json)
declare -A V34=([02_Infrastructure/contracts/grade_v3.R]=b7ebf22339434bb4b5dae8f4824687ff [02_Infrastructure/contracts/matched_controls.R]=1b9d8152255231b2e77401f598bbcf14
  [02_Infrastructure/contracts/essence_score.R]=484a0e4645071d4034353009d03498ae [02_Infrastructure/contracts/diagnosis_packet.R]=a9dfc1abdf719304f99b6b96bdad3a63
  [06_Registry/grade_v3.json]=97f8b60c71445a99203b9ad2135560a5 [06_Registry/matched_controls.json]=f0cf960ab0e6ecebd9c336e61d2b86a7)
LOG="$SP/regrade_${TAG}.log"; : > "$LOG"
say() { echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG"; }
[ -s "$SP/empty.Renviron" ] || : > "$SP/empty.Renviron"
vint() { python -I -c "
import json,os,sys
r=sys.argv[1]; m=json.load(open(os.path.join(r,'.cache','kr_factor_returns_meta.json'),encoding='utf-8'))['monthly']['content_md5']
import datetime
def v(f):
    st=os.stat(os.path.join(r,'.cache',f)); return '%d@%s'%(st.st_size, datetime.datetime.fromtimestamp(st.st_mtime).strftime('%Y-%m-%dT%H:%M:%S'))
print(m, v('RAWDATA.parquet'), v('benchmark.parquet'))" "$RW"; }

if [ "$MODE" != "writeonly" ]; then
  ## 1) v3.4 계약 사본 루트
  M34="$SP/m34_$TAG"; M34W="$SPW/m34_$TAG"
  if [ -e "$M34/.cache" ]; then MSYS_NO_PATHCONV=1 cmd /c rmdir "$(cygpath -w "$M34/.cache")" >/dev/null; fi   # 정션 먼저(지우기가 정션 너머로 가지 않게)
  rm -rf "$M34"; mkdir -p "$M34"
  git -C "$R" archive HEAD | tar -x -C "$M34"
  for f in "${RULES[@]}"; do git -C "$R" show "$PRE_COMMIT:$f" > "$M34/$f"
    got=$(md5sum "$M34/$f" | cut -c1-32); [ "$got" = "${V34[$f]}" ] || { say "ABORT v3.4 사본 $f md5 $got ≠ ${V34[$f]}"; exit 2; }; done
  MSYS_NO_PATHCONV=1 cmd /c mklink /J "$(cygpath -w "$M34/.cache")" "$(cygpath -w "$R/.cache")" >/dev/null   # /J 를 경로로 바꾸지 않게
  [ -f "$M34/.cache/RAWDATA.parquet" ] || { say "ABORT .cache 정션 실패"; exit 2; }
  say "v3.4 사본 루트 $M34W(HEAD $(git -C "$R" rev-parse --short HEAD) + 규칙 6파일 = $PRE_COMMIT)"
  ## 2) 전수 · 대상
  python -I "$D/tools/census_regrade_set.py" "$R" "$TAG" | tee -a "$LOG"
  if [ -n "${V35_LIMIT:-}" ]; then head -n "$V35_LIMIT" "$D/data/dirs_regrade_$TAG.txt" > "$D/data/dirs_regrade_$TAG.tmp" && mv -f "$D/data/dirs_regrade_$TAG.tmp" "$D/data/dirs_regrade_$TAG.txt"; say "리허설 — 대상 앞 $V35_LIMIT 건만"; fi
  V0=$(vint); say "데이터 시점(드라이런 전) $V0"
  ## 3) 짝 드라이런(동시)
  ( cd "$M34" && QM_ROOT="$M34W" CLAUDE_PROJECT_DIR="$M34W" R_ENVIRON_USER="$SPW/empty.Renviron" \
      Rscript "$DW/tools/dryrun_contract.R" "$M34W" "$RW" "$DW/data/dirs_regrade_$TAG.txt" "$DW/data/dryrun_v34_$TAG.csv" v34 > "$SP/dry34_$TAG.log" 2>&1 ) &
  P34=$!
  ( cd "$R" && QM_ROOT="$RW" CLAUDE_PROJECT_DIR="$RW" R_ENVIRON_USER="$SPW/empty.Renviron" \
      Rscript "$DW/tools/dryrun_contract.R" "$RW" "$RW" "$DW/data/dirs_regrade_$TAG.txt" "$DW/data/dryrun_v35_$TAG.csv" v35 > "$SP/dry35_$TAG.log" 2>&1 ) &
  P35=$!
  rc34=0; rc35=0; wait $P34 || rc34=$?; wait $P35 || rc35=$?
  tail -2 "$SP/dry34_$TAG.log" | tee -a "$LOG"; tail -2 "$SP/dry35_$TAG.log" | tee -a "$LOG"
  [ $rc34 -eq 0 ] && [ $rc35 -eq 0 ] || { say "ABORT 드라이런 실패 rc34=$rc34 rc35=$rc35"; exit 3; }
  V1=$(vint); say "데이터 시점(드라이런 뒤) $V1"
  [ "$V0" = "$V1" ] || { say "ABORT 드라이런 중 데이터 시점이 바뀌었다 — 다시"; exit 4; }
  echo "$V1" > "$D/data/vintage_$TAG.txt"
  ## 5) 재채점 도구 드라이런(--dirs · 자료 계기 켬)
  ( cd "$R" && R_ENVIRON_USER="$SPW/empty.Renviron" QM_ROOT="$RW" CLAUDE_PROJECT_DIR="$RW" \
      Rscript 02_Infrastructure/programs/grade_v3_backfill.R --workers 6 --dirs "$DW/data/dirs_regrade_$TAG.txt" --out "$DW/data/backfill_$TAG" > "$SP/backfill_dry_$TAG.log" 2>&1 ) || { say "ABORT 재채점 드라이런 실패"; tail -5 "$SP/backfill_dry_$TAG.log" | tee -a "$LOG"; exit 5; }
  grep -E "^\[backfill\]" "$SP/backfill_dry_$TAG.log" | tail -8 | tee -a "$LOG"
fi
if [ "$MODE" = "write" ] || [ "$MODE" = "writeonly" ]; then
  V2=$(vint); V1=$(cat "$D/data/vintage_$TAG.txt")
  [ "$V1" = "$V2" ] || { say "ABORT 쓰기 직전 데이터 시점이 드라이런 때와 다르다($V1 → $V2) — 드라이런부터 다시"; exit 6; }
  say "쓰기 — 데이터 시점 같음($V2)"
  ( cd "$R" && R_ENVIRON_USER="$SPW/empty.Renviron" QM_ROOT="$RW" CLAUDE_PROJECT_DIR="$RW" \
      Rscript 02_Infrastructure/programs/grade_v3_backfill.R --workers 6 --dirs "$DW/data/dirs_regrade_$TAG.txt" --out "$DW/data/backfill_$TAG" --write > "$SP/backfill_write_$TAG.log" 2>&1 ) || { say "ABORT 재채점 쓰기 실패"; tail -8 "$SP/backfill_write_$TAG.log" | tee -a "$LOG"; exit 7; }
  grep -E "^\[backfill\]" "$SP/backfill_write_$TAG.log" | tail -10 | tee -a "$LOG"
  python -I "$D/tools/census_regrade_set.py" "$R" post | tee -a "$LOG"
fi
say "끝 ($MODE)"
