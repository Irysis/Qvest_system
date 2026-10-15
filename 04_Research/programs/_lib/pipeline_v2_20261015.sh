#!/usr/bin/env bash
# 10-15 재시작 파이프라인 v2(도훈 "코드 리뷰 및 수정부터 진행하고 재시작해줘" · "병렬로") — 성능 수정판 코드로 남은 측정·평가를 끝낸다.
#   ⓪ Rcpp 사전 컴파일(빌드 캐시 1회 생성 — 병렬 워커의 동시 컴파일 경합 방지)
#   ① 측정 3-way 병렬(xargs -P 3): P3R01 E1 K2~K4 · E2 K1~K5(DB 팩터 없음) → P0R01 E3 C0~C6(DB 팩터 3~4종)
#      ‖ 팩터×월 파티션 캐시 프리페치(E3 · C4 · C5 · C6 이 쓰는 DB 팩터 5종 · 3-way) — E3 셀은 프리페치 완료 센티널 뒤에 시작
#   ② P0R01 셀 평가 샤딩 병렬(eval_parallel.sh · K=auto) + 종합 판정 → P2R02 · P1R01 평가 ‖ P3R01 셀 평가 샤딩 병렬 + 종합 판정
#   ③ P3R02 재핀 센티널(p3r02_repinned.done — 세션이 사전등록 v5 재핀 뒤 생성) 대기 → pipeline.done(대기 중인 P3R02 measure.sh 가 인계)
# 센티널 = _lib/night_state/<단계>.done · 로그 = _lib/pipeline_v2.log(detached_env.sh 래퍼가 기록)
set -u
ROOT=/c/Users/99922/OneDrive/Quant_Module_Moltbot
cd $ROOT || exit 2
export QM_ROOT=C:/Users/99922/OneDrive/Quant_Module_Moltbot CLAUDE_PROJECT_DIR=C:/Users/99922/OneDrive/Quant_Module_Moltbot
LIB=$ROOT/04_Research/programs/_lib; ST=$LIB/night_state; mkdir -p $ST
P0D=04_Research/programs/P0_FRONTIER/P0R01_feasibility_map
P3D=04_Research/programs/P3_CONSTRUCTION/P3R01_construction_map
P3PRE=stage_artifacts/programs/P3_CONSTRUCTION/P3R01_construction_map/prereg.json
ts() { date +%F' '%T; }

echo "== $(ts) ⓪ Rcpp 사전 컴파일 =="
Rscript -e 'setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot"); suppressMessages({source("02_Infrastructure/config.R"); source("02_Infrastructure/backtest_harness.R"); source("02_Infrastructure/strategy_analyzer.R")})' \
  > $LIB/v2_rcpp_precompile.log 2>&1
echo "== $(ts) ⓪ rc=$? =="

echo "== $(ts) ① 측정 3-way 병렬 + 파티션 캐시 프리페치 =="
( printf "%s\n" M01_Mom_12_1 V10_FCF_Yield M08_Residual_Mom D03_RealVol Q08_Composite_Quality |
    xargs -P 3 -I{} Rscript $LIB/fdb_partcache_prefetch.R {} 200001 > $LIB/v2_prefetch.log 2>&1
  touch $ST/v2_prefetch.done; echo "== $(ts) 프리페치 끝 ==" ) &
PF=$!
m() {
  local c=$1
  case $c in
    P0R01_E3_*) until [ -f $ST/v2_prefetch.done ]; do sleep 10; done
                Rscript $ROOT/$P0D/measure_cell.R $c 2>&1 | grep -E "^\[측정\]|Error|에러|멈" | sed "s/^/[$c] /" ;;
    P3R01_*)    Rscript $LIB/measure_round_cell.R "$P3D" "$P3PRE" $c 2>&1 | grep -E "^\[측정\]|Error|에러" | sed "s/^/[$c] /" ;;
  esac
}
export -f m; export ROOT LIB ST P0D P3D P3PRE
printf "%s\n" P3R01_E1_K2 P3R01_E1_K3 P3R01_E1_K4 P3R01_E2_K1 P3R01_E2_K2 P3R01_E2_K3 P3R01_E2_K4 P3R01_E2_K5 \
              P0R01_E3_C0 P0R01_E3_C1 P0R01_E3_C2 P0R01_E3_C3 P0R01_E3_C4 P0R01_E3_C5 P0R01_E3_C6 | xargs -P 3 -I{} bash -c 'm {}'
wait $PF
touch $ST/v2_measured.done $ST/p3_measured.done
echo "== $(ts) ① 측정 끝 =="

echo "== $(ts) ② P0R01 셀 평가(샤딩 병렬) + 종합 판정 =="
bash $LIB/eval_parallel.sh $P0D/evaluate.R auto $P0D/evaluate
touch $ST/p0_cells_evaluated.done $ST/p0_evaluated.done
echo "== $(ts) ② P2R02 · P1R01 평가 ‖ P3R01 셀 평가(샤딩 병렬) + 종합 판정 =="
( for r in P2_DEFENSE/P2R02_device_cross_engine P1_RETURN/P1R01_engine_qualification; do
    d=$ROOT/04_Research/programs/$r
    Rscript $d/evaluate.R > $d/evaluate.log 2>&1; echo "rc=$?" >> $d/evaluate.log
  done
  touch $ST/p2r02_evaluated.done $ST/p1r01_evaluated.done ) &
LT=$!
bash $LIB/eval_parallel.sh $P3D/evaluate.R auto $P3D/evaluate
touch $ST/p3r01_evaluated.done
wait $LT
echo "== $(ts) ② 평가 끝 =="

echo "== $(ts) ③ P3R02 재핀 센티널 대기 =="
until [ -f $ST/p3r02_repinned.done ]; do sleep 30; done
touch $ST/pipeline.done
echo "== $(ts) 파이프라인 v2 끝 → P3R02 measure.sh 인계 =="
