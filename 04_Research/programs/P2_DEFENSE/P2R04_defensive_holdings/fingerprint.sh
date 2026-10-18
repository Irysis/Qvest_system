#!/usr/bin/env bash
# P2R04 데이터 지문(판본 비교 · 성과 수치 없음 · P2R03 fingerprint.sh 그대로 — 2026-10-18) — measure.sh(칸마다 시작 · 종료) · evaluate.R(평가 시점)이 같은 정의를 쓴다.
#   equality = 묶음 판정 대상(rules.vintage_group): 측정이 읽는 원천 — RAWDATA(위생 표식 · 유니버스 포함) · 벤치 · 재무 원값 · 컨센서스 폴더 ·
#              팩터 DB 월 스냅샷(factor_db_YYYYMM.parquet — 이 라운드의 처치 원천) · 팩터 레지스트리 · 빌드 해시. 팩터 DB 폴더의 실행 중 캐시
#              (ic_direction_cache_v1 · _asof · _rebuild_z_markers)는 측정 중에도 쓰이므로 넣지 않는다(넣으면 같은 판본인데 지문이 갈린다).
#   ★P2R04 추가(판단 T1 C-20261018-034 · 측정 기계 보고): 팩터 IC 월간 이력(factor_ic_monthly.parquet)을 equality 에 넣는다 — 방어 틸트의
#              방향(Z_Score_Aligned = Z × as-of IC 부호)이 이 파일에서 오므로 이 라운드의 처치 입력이다(재생성되면 방향이 바뀔 수 있다).
#              방향 캐시(ic_direction_cache_v1)는 이 파일의 mtime · 크기로 키가 바뀌므로 파일 하나로 판본이 정해진다.
#   record   = 기록만: E2 · E3 공통 DNN 예측 캐시 — 갱신 뒤 새 달은 측정 중에 캐시가 채워지므로(캐시 워밍) 판본 비교에 쓰지 않는다.
# 사용: bash fingerprint.sh [equality|record]
ROOT=/c/Users/99922/OneDrive/Quant_Module_Moltbot
f() { stat -c '%n %s %Y' "$@" 2>&1 | sed "s#^$ROOT/##"; }
d() { local dir="$1"; shift
      find "$dir" "$@" -type f -printf '%s %T@\n' 2>/dev/null |
        awk -v n="${dir#$ROOT/}" '{c++; s+=$1; t=int($2); if (t>m) m=t} END {printf "%s/ files=%d bytes=%.0f max_mtime=%d\n", n, c, s, m}'; }
case "${1:-equality}" in
  equality)
    f "$ROOT/.cache/RAWDATA.parquet" "$ROOT/.cache/benchmark.parquet" "$ROOT/.cache/fundamental_merged.parquet" \
      "$ROOT/.cache/factor_db/factor_registry.json" "$ROOT/.cache/factor_db/build_hash.txt" "$ROOT/.cache/factor_db/factor_ic_monthly.parquet"
    d "$ROOT/.cache/consensus"
    d "$ROOT/.cache/factor_db" -maxdepth 1 -name 'factor_db_[0-9][0-9][0-9][0-9][0-9][0-9].parquet' ;;
  record)
    d "$ROOT/04_Research/strategies/RP_AUTO_2002_06975/_work/cache" ;;
  *) echo "usage: fingerprint.sh [equality|record]" >&2; exit 2 ;;
esac
