#!/usr/bin/env bash
## FC 엔진(자체 사양 30 — T0 15 + T1 15) 기저 신호 캐시 시각 점검(코어 v4 알려진 한계 F-5 · P1R04 DESIGN §8):
##   캐시 키(rf_base_cache_key)에 결합용 뷰 · IC 원장이 없다 → 뷰 · IC 빌드보다 앞서 만든 FC 캐시는 적중하면 낡은 입력이다.
##   기준 시각 = max(뷰 fc_meta.json built_at · IC 원장 mtime · 팩터 DB build_hash.txt mtime). 그보다 앞선 FC 캐시 = 옮길 대상.
##   사용: bash fc_cache_check.sh            → 목록만(읽기)
##         bash fc_cache_check.sh --apply    → 99_Archive/p1r04_stale_base_cache_<시각>/ 로 옮긴다(삭제 없음 · 99_Archive 는 git 밖)
set -u
ROOT=/c/Users/99922/OneDrive/Quant_Module_Moltbot; cd "$ROOT" || exit 2
APPLY=0; [ "${1:-}" = "--apply" ] && APPLY=1
VB=$(grep -o '"built_at": *"[^"]*"' .cache/factor_combinable/fc_meta.json | head -1 | sed -E 's/.*"([^"]*)"$/\1/')
VT=$(date -d "$(echo "$VB" | sed -E 's/T/ /; s/\+0900$//')" +%s) || { echo "뷰 built_at 판독 불가: $VB"; exit 3; }
IT=$(stat -c %Y .cache/factor_db/factor_ic_monthly.parquet) || exit 3
BT=$(stat -c %Y .cache/factor_db/build_hash.txt) || exit 3
TH=$VT; [ "$IT" -gt "$TH" ] && TH=$IT; [ "$BT" -gt "$TH" ] && TH=$BT
echo "기준: 뷰 $VB · IC $(date -d @"$IT" '+%F %T') · 팩터 DB build_hash $(date -d @"$BT" '+%F %T') ($(cat .cache/factor_db/build_hash.txt)) → 기준 $(date -d @"$TH" '+%F %T')"
n=0; old=0; DEST=99_Archive/p1r04_stale_base_cache_$(date +%Y%m%d_%H%M%S)
for d in 04_Research/strategies/FC_FAM_* 04_Research/strategies/FC_TOTAL_*; do
  [ -f "$d/engine.R" ] || continue
  p=$(md5sum "$d/engine.R" | cut -c1-12)
  for f in .cache/rf_base_signal/base_v3_${p}_*.rds; do
    [ -f "$f" ] || continue
    n=$((n+1)); t=$(stat -c %Y "$f")
    if [ "$t" -lt "$TH" ]; then old=$((old+1)); echo "  낡음 $(basename "$d") $(date -d @"$t" '+%F %T') $(basename "$f")"
      if [ "$APPLY" = "1" ]; then mkdir -p "$DEST" && mv "$f" "$DEST/" || { echo "옮기기 실패: $f"; exit 4; }; fi
    else echo "  새것 $(basename "$d") $(date -d @"$t" '+%F %T') $(basename "$f")"; fi
  done
done
echo "FC 캐시 $n · 기준보다 앞선 것 $old$( [ "$APPLY" = "1" ] && [ "$old" -gt 0 ] && echo " → $DEST 로 옮김")"
