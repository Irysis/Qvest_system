#!/usr/bin/env bash
# P2R05 데이터 지문(판본 비교 · 성과 수치 없음 · P2R04 fingerprint.sh 승계 — 2026-10-18) — measure.sh(칸마다 시작 · 종료) · warm_cache.sh(워밍 시작 · 끝) ·
#   precheck.R(--warm-check · 기록) · evaluate.R(평가 시점)이 같은 정의를 쓴다.
#   equality  = 묶음 판정 대상(rules.vintage_group · P2R04 그대로): 측정이 읽는 원천 — RAWDATA(위생 표식 · 유니버스 포함) · 벤치 · 재무 원값 · 컨센서스 폴더 ·
#               팩터 DB 월 스냅샷(E3 기존 팩터 · LV 저변동 팩터의 원천) · 팩터 레지스트리 · 빌드 해시 · 팩터 IC 월간 이력(방향 원천 · P2R04 판단 T1 C-034).
#               팩터 DB 폴더의 실행 중 캐시(ic_direction_cache_v1 · _asof · _rebuild_z_markers)는 측정 중에도 쓰이므로 넣지 않는다(넣으면 같은 판본인데 지문이 갈린다).
#   record    = 기록만: DNN 예측 캐시 — 평균 표적(RP_AUTO_2002_06975 · RX0 · W2 · LV) + ★P2R05 분위 캐시(DT_2002_06975/_work/cache) · 분위 예측표(_work/qpred) +
#               ★재시드 RX0S 캐시(DT_2002_06975/rx0s/_work/cache — 구현이 작업 디렉터리 .WD 를 따로 둔다 · 매니페스트 rx0s.work_dir).
#               갱신 뒤 새 달은 측정 중에 캐시가 채워지므로 판본 비교에 쓰지 않는다.
#   dnn_input = ★P2R05 추가 — DNN 학습 입력의 판본(엔진이 읽는 원천만: RAWDATA · 재무 원값 · 컨센서스 폴더 · equality 의 부분집합 · 같은 줄 형식).
#               워밍 센티널 신선도 단정(precheck.R --warm-check)의 기준 — 팩터 DB 만 바뀐 갱신은 분위 캐시를 낡게 하지 않는다(DNN 은 팩터 DB 를 읽지 않는다).
#               측정 축 설정(constraint_defaults.json)은 운영 경로 핀(precheck)이 따로 막는다.
# 사용: bash fingerprint.sh [equality|record|dnn_input]
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
    d "$ROOT/04_Research/strategies/RP_AUTO_2002_06975/_work/cache"
    d "$ROOT/04_Research/strategies/DT_2002_06975/_work/cache"
    d "$ROOT/04_Research/strategies/DT_2002_06975/_work/qpred"
    d "$ROOT/04_Research/strategies/DT_2002_06975/rx0s/_work/cache" ;;
  dnn_input)
    f "$ROOT/.cache/RAWDATA.parquet" "$ROOT/.cache/fundamental_merged.parquet"
    d "$ROOT/.cache/consensus" ;;
  *) echo "usage: fingerprint.sh [equality|record|dnn_input]" >&2; exit 2 ;;
esac
