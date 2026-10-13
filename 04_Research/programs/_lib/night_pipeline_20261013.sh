#!/usr/bin/env bash
# 10-13 밤 파이프라인(도훈 "밤새서 모두 완성해놔") — 메모리 경합을 피하는 순서:
#   ① P0R01 측정 끝 대기 → ② P0R01 칸 평가(단일 프로세스 · 위생 raw 1회 적재)
#   ③ P3R01 측정(3병렬)과 나란히: P0R01 종합 판정 → P2R02 · P1R01 평가(가벼움)
#   ④ P3R01 측정 끝 → P3R01 평가 → 표식 파일
# 각 단계 끝에 표식 파일(_lib/night_state/<단계>.done)을 남긴다 — 세션이 보고 · 텔레그램을 단계별로 낸다.
set -u
ROOT=/c/Users/99922/OneDrive/Quant_Module_Moltbot
cd $ROOT || exit 2
export QM_ROOT=C:/Users/99922/OneDrive/Quant_Module_Moltbot
ST=$ROOT/04_Research/programs/_lib/night_state; mkdir -p $ST
P0D=$ROOT/04_Research/programs/P0_FRONTIER/P0R01_feasibility_map
P3D=04_Research/programs/P3_CONSTRUCTION/P3R01_construction_map
P3PRE=stage_artifacts/programs/P3_CONSTRUCTION/P3R01_construction_map/prereg.json
ts() { date +%F' '%T; }
echo "== $(ts) ① P0 측정 끝 대기 =="
until grep -q "전체 끝" "$P0D/measure_all.log" 2>/dev/null; do sleep 30; done
touch $ST/p0_measured.done
echo "== $(ts) ② P0 칸 평가 =="
Rscript $P0D/evaluate.R --cells-only > $P0D/evaluate_cells.log 2>&1; echo "rc=$?" >> $P0D/evaluate_cells.log
touch $ST/p0_cells_evaluated.done
echo "== $(ts) ③ P3 측정(백그라운드) + P0 종합 · P2R02 · P1R01 평가 =="
m() { Rscript $ROOT/04_Research/programs/_lib/measure_round_cell.R "$P3D" "$P3PRE" "$1" 2>&1 | grep -E "^\[측정\]|Error|에러" | sed "s/^/[$1] /"; }
export -f m; export ROOT P3D P3PRE
( printf "%s\n" P3R01_E1_K1 P3R01_E1_K2 P3R01_E1_K3 P3R01_E1_K4 P3R01_E1_K5 \
                P3R01_E2_K1 P3R01_E2_K2 P3R01_E2_K3 P3R01_E2_K4 P3R01_E2_K5 | xargs -P 3 -I{} bash -c 'm {}' > $ROOT/$P3D/measure_all.log 2>&1
  echo "== $(ts) P3 측정 전체 끝 ==" >> $ROOT/$P3D/measure_all.log; touch $ST/p3_measured.done ) &
P3PID=$!
Rscript $P0D/evaluate.R > $P0D/evaluate.log 2>&1; echo "rc=$?" >> $P0D/evaluate.log; touch $ST/p0_evaluated.done
Rscript $ROOT/04_Research/programs/P2_DEFENSE/P2R02_device_cross_engine/evaluate.R > $ROOT/04_Research/programs/P2_DEFENSE/P2R02_device_cross_engine/evaluate.log 2>&1
echo "rc=$?" >> $ROOT/04_Research/programs/P2_DEFENSE/P2R02_device_cross_engine/evaluate.log; touch $ST/p2r02_evaluated.done
Rscript $ROOT/04_Research/programs/P1_RETURN/P1R01_engine_qualification/evaluate.R > $ROOT/04_Research/programs/P1_RETURN/P1R01_engine_qualification/evaluate.log 2>&1
echo "rc=$?" >> $ROOT/04_Research/programs/P1_RETURN/P1R01_engine_qualification/evaluate.log; touch $ST/p1r01_evaluated.done
echo "== $(ts) ④ P3 측정 대기 =="
wait $P3PID
Rscript $ROOT/$P3D/evaluate.R > $ROOT/$P3D/evaluate.log 2>&1; echo "rc=$?" >> $ROOT/$P3D/evaluate.log
touch $ST/p3r01_evaluated.done
echo "== $(ts) 파이프라인 끝 =="
touch $ST/pipeline.done
