#!/usr/bin/env bash
#==============================================================================
# [6/6] K200 일간 위험 브리핑 — 본 모형 H1 · P3 비교 기록
#   2026-11-14 도훈 결정 K200-RISK-H1-REPLACE-P3-20261114 ("즉시 교체 — 다음 아침 브리핑부터 H1 본 모형 ·
#   이상 입력 점검 포함 · P3 는 비교용"). 검증 = 04_Research/01_reports/k200_risk_accuracy_20261113(9799b31e8).
#
#   6a  P3 추론(601 · 비교 기록 · 코드 무변경)       → P3_daily.parquet · P3_latest.json
#   6a' P3 실현값 채움(구 체인 인라인 그대로)
#   6h  H1 추론 + 입력 · 출력 점검(602 --live)        → H1_daily.parquet · H1_latest.json · H1_guard_latest.json
#   6b  발송 원천 결정 + 본문 · 차트(603)              → morning_brief/<기준일>/brief.md · *.png · brief_meta.json
#       (H1 | H1 차단이면 P3 대체 | 둘 다 안 되면 수치 보류) · 603 이 죽으면 구 P3 브리핑(600)으로 대신 만든다
#   6b' 9분면 대시보드(613) — P3 대체 · 구 방식일 때만(H1 은 λ · ν 가 재추정 창 상수라 9분면 축이 맞지 않는다)
#   6c  발송(p3_brief_send.R — brief_meta.json 의 사진 · 설명을 따른다)
#   구 [6/6] 블록(P3 단일 · 601 → 600 → 613 → 발송)은 morning_briefing.sh 의 git 2026-11-14 이전 판.
#
# 시험: K200_BRIEF_SANDBOX=<폴더> — 예측은 <폴더>/daily_predictions, 브리핑은 <폴더>/morning_brief 에만 쓴다.
#       발송은 미리보기(K200_BRIEF_DRYRUN=1) · 613 생략. 폴더에 P3_daily.parquet · H1_* 사본을 먼저 넣어 둔다.
#==============================================================================
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]:-$0}")/../resolve_project.sh"
P2_BF_DIR="$BASE/04_Research/decision_framework/bearish_forecast_v3"
P2_PY=""
for _c in "$BASE/.venv_qvest_ml/Scripts/python.exe" "$BASE/.venv_qvest_ml/bin/python"; do
  [ -x "$_c" ] && P2_PY="$_c" && break
done
if [[ ! -x "$P2_PY" || ! -d "$P2_BF_DIR" ]]; then
  echo "[6/6] SKIP — venv or v3 dir missing"
  exit 0
fi

SANDBOX="${K200_BRIEF_SANDBOX:-}"
if [ -n "$SANDBOX" ]; then
  PRED_DIR="$SANDBOX/daily_predictions"; BRIEF_ROOT="$SANDBOX/morning_brief"
  mkdir -p "$PRED_DIR" "$BRIEF_ROOT"
  export K200_BRIEF_DRYRUN=1 K200_BRIEF_ROOT="$BRIEF_ROOT"
  echo "[6/6] SANDBOX=$SANDBOX (발송 미리보기 · 613 생략)"
else
  PRED_DIR="$P2_BF_DIR/03_models/daily_predictions"; BRIEF_ROOT="$P2_BF_DIR/03_models/morning_brief"
fi

cd "$P2_BF_DIR"
# 기준일 = 벤치 최신 종가일([2026-06-01 fix] 601 기본 경로가 하루 묵는 문제 — 구 체인과 같은 추출)
ASOF_BM=$("$P2_PY" -c "import pandas as pd; print(pd.to_datetime(pd.read_parquet('$BASE/.cache/benchmark.parquet', columns=['Date'])['Date']).max().date())" 2>/dev/null)

# 6a. P3 추론(비교 기록)
if [[ -n "$ASOF_BM" ]]; then
  echo "[6a] P3 601 inference --asof $ASOF_BM (비교 기록)"
  "$P2_PY" scripts/601_daily_inference.py --model P3 --asof "$ASOF_BM" --output "$PRED_DIR" 2>&1 | tail -5
else
  echo "[6a] ASOF_BM 추출 실패 — P3 기본 경로 · 이후 구 P3 브리핑 경로"
  "$P2_PY" scripts/601_daily_inference.py --model P3 --output "$PRED_DIR" 2>&1 | tail -5
fi
# 6a'. P3 y_actual backfill (이전 forecast row 의 realized 1d return 채움, 도훈 mandate 2026-05-28 — 구 체인 인라인 그대로 · 경로만 PRED_DIR)
"$P2_PY" -c "
import pandas as pd, numpy as np, sys, os
sys.path.insert(0, '$P2_BF_DIR/03_models')
import p1_hansen_skewt as HSK
p3_path = '$PRED_DIR/P3_daily.parquet'
p3 = pd.read_parquet(p3_path); p3['Date'] = pd.to_datetime(p3['Date']); p3 = p3.sort_values('Date').reset_index(drop=True)
bm = pd.read_parquet('$BASE/.cache/benchmark.parquet'); bm['Date'] = pd.to_datetime(bm['Date']); bm = bm.sort_values('Date').reset_index(drop=True)
bm['log_ret'] = np.log(bm['BM_Close']).diff() * 100
fwd_map = bm.assign(ret_fwd=bm.log_ret.shift(-1)).set_index('Date')['ret_fwd'].to_dict()
n_filled = 0
for i, row in p3.iterrows():
    if pd.isna(row['y_actual']) and row['Date'] in fwd_map:
        fwd = fwd_map[row['Date']]
        if pd.notna(fwd):
            p3.loc[i, 'y_actual'] = fwd
            try:
                pit = HSK.pit_per_obs(np.array([fwd]), np.array([row['mu']]), np.array([row['sigma']]), np.array([row['nu']]), np.array([row['lam']]))[0]
                p3.loc[i, 'pit'] = pit
            except Exception: pass
            n_filled += 1
p3.to_parquet(p3_path)
print(f'[y_actual backfill] {n_filled} rows filled')
" 2>&1 | tail -2

SRC="legacy"
if [[ -n "$ASOF_BM" ]]; then
  # 6h. H1 추론 + 점검
  echo "[6h] H1 602 inference --live --asof $ASOF_BM"
  "$P2_PY" scripts/602_h1_daily_inference.py --live --asof "$ASOF_BM" --out "$PRED_DIR" 2>&1 | tail -8
  echo "[6h] 602 rc=${PIPESTATUS[0]}"
  # 6b. 발송 원천 결정 + 브리핑
  "$P2_PY" scripts/603_k200_brief.py --asof "$ASOF_BM" --pred-dir "$PRED_DIR" --out-root "$BRIEF_ROOT" 2>&1 | grep -v "Glyph\|UserWarning" | sed -n '1,12p'
  BR_RC=${PIPESTATUS[0]}
  echo "[6b] 603 rc=$BR_RC"
  if [ "$BR_RC" = "0" ]; then
    SRC=$("$P2_PY" -c "import json; print(json.load(open(r'$BRIEF_ROOT/$ASOF_BM/brief_meta.json', encoding='utf-8'))['source'])" 2>/dev/null || echo "legacy")
  fi
fi
if [ "$SRC" = "legacy" ]; then
  echo "[6b] ⚠ 603 실패 · 기준일 없음 → 구 P3 브리핑(600)으로 대신 만든다"
  "$P2_PY" scripts/600_morning_brief.py --predictions "$PRED_DIR/P3_daily.parquet" --output "$BRIEF_ROOT" 2>&1 | grep -v "Glyph\|UserWarning" | tail -3
fi
echo "[6b] 발송 원천 = $SRC"

# 6b'. 9분면 대시보드 — P3 대체 · 구 방식일 때만 (613 은 운영 P3_daily · 운영 morning_brief 고정 경로 — 시험에서는 생략)
if [[ "$SRC" = "P3" || "$SRC" = "legacy" ]]; then
  if [ -z "$SANDBOX" ]; then
    cd "$BASE"
    Rscript "$BASE/04_Research/decision_framework/bearish_forecast_v3/scripts/613_p3_9quad_riskpro.R" 2>&1 | tail -2 || true
  else
    echo "[6b'] SANDBOX — 613 생략"
  fi
fi

# 6c. 텔레그램 발송 (latest brief) — 외부화 2026-06-13 (한글/이모지 인라인 -e 깨짐 해소)
cd "$BASE"
if [ -z "$SANDBOX" ]; then
  Rscript --no-save -e 'source("02_Infrastructure/ops/morning_steps/p3_brief_send.R")' >> /tmp/qm_morning.log 2>&1
  echo "[6c] 발송 단계 끝(상세 = /tmp/qm_morning.log)"
else
  Rscript --no-save -e "source('${K200_SENDER:-02_Infrastructure/ops/morning_steps/p3_brief_send.R}')" 2>&1 | grep -v "^Warning message\|incomplete final line\|^In readLines"
fi
