#!/usr/bin/env bash
# 파이프라인 v2 후속(2026-10-15) — P3R02 측정(measure.sh · p3r02_measured.done) 뒤 셀 평가 샤딩 + 종합 판정.
#   measure.sh 는 측정만 한다(precheck → E1 쌍 → E2 쌍). 평가는 사전등록 v5 의 evaluate.R(실행 시 자기 md5 대조) 그대로.
set -u
ROOT=/c/Users/99922/OneDrive/Quant_Module_Moltbot
cd $ROOT || exit 2
export QM_ROOT=C:/Users/99922/OneDrive/Quant_Module_Moltbot CLAUDE_PROJECT_DIR=C:/Users/99922/OneDrive/Quant_Module_Moltbot
LIB=$ROOT/04_Research/programs/_lib; ST=$LIB/night_state
RDR=04_Research/programs/P3_CONSTRUCTION/P3R02_eigen_markowitz
echo "== $(date +%F' '%T) P3R02 측정 센티널 대기 =="
until [ -f $ST/p3r02_measured.done ]; do sleep 30; done
echo "== $(date +%F' '%T) P3R02 셀 평가(샤딩) + 종합 판정 =="
bash $LIB/eval_parallel.sh $RDR/evaluate.R auto $RDR/evaluate
rc=$?
[ $rc -eq 0 ] && touch $ST/p3r02_evaluated.done
echo "== $(date +%F' '%T) P3R02 평가 rc=$rc =="
