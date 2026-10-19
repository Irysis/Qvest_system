#!/usr/bin/env bash
# round_core v1 · 데이터 지문(판본 비교 · 성과 수치 없음) — P2R04 fingerprint.sh 일반화. 실행기(round.sh)가 칸마다 측정 시작 · 끝에 쓴다.
#   equality = 판본 판정 대상(측정이 읽는 원천): RAWDATA · 벤치 · 재무 원값 · 팩터 레지스트리 · 빌드 해시 · 팩터 IC 월간 이력 · 컨센서스 ·
#              팩터 DB 월 스냅샷. 실행 중 캐시(ic_direction_cache_v1 · _asof · _rebuild_z_markers)는 넣지 않는다(같은 판본인데 지문이 갈린다).
#   record   = 기록만: 엔진 캐시 디렉터리(인자로 받는다 — 캐시 워밍으로 측정 중 채워지므로 판본 비교에 쓰지 않는다).
# 사용: bash fingerprint.sh equality | bash fingerprint.sh record <캐시 디렉터리...>
ROOT=${QM_ROOT_POSIX:-/c/Users/99922/OneDrive/Quant_Module_Moltbot}
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
    shift; for c in "$@"; do d "$ROOT/$c"; done ;;
  *) echo "usage: fingerprint.sh equality | record <dir...>" >&2; exit 2 ;;
esac
