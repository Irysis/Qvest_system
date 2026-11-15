#!/usr/bin/env bash
# P1R03 영향 7칸 재측정 — 이음매 D1(가격 수준 23팩터 연속 가격 · 202603~202611 · IC · 결합용 뷰 · FF UMD) 뒤 (2026-11-14)
#   정본 셀 워커 그대로(rf_cell_worker.R → run_paper_replication → essence) · 사양 md5 = 사전등록 값 단정(R2) ·
#   닫힌 라운드의 results/ 는 건드리지 않는다 — 출력 = remeasure_d1_20261114/results/ · 모듈 풀 등재 끔(QVEST_RP_REGISTER=0 — 풀 교체는 따로)
#   측정 러너 규약: 배리어 held 면 기다린다(최대 30분) · 가용 메모리 − 셀 워커 예상 정점(7.45GB) ≥ 여유(memory_policy.json::reserve_gb)일 때만 출발한다(공통 관문 tools/p1r03_rm_gate.sh · 도훈 11-15 MEMORY-USE-90PCT-20261115) · 칸은 하나씩.
set -u
ROOT="C:/Users/99922/OneDrive/Quant_Module_Moltbot"; cd "$ROOT" || exit 2
RD=04_Research/programs/P1_RETURN/P1R03_factor_family_composites
. "$RD/tools/p1r03_rm_gate.sh" || exit 2   # 출발 관문(배리어 free ∧ 가용 − 정점 ≥ 여유)
OUT=$RD/remeasure_d1_20261114/results; mkdir -p "$OUT"
ORDER="${P1R03_RM_ORDER:-FMOME FTECH FVALU FDEFE FLIQU FCROW TOTAL}"   # 23팩터의 등록부 category(모멘텀 7 · 기술적 12 · 밸류 · 방어 · 유동성 · 쏠림 각 1) + 토탈
ts() { date '+%F %T'; }
for c in $ORDER; do
  code="P1R03_${c}_C0"; spec="$RD/specs/${code}.json"; out="$OUT/${code}.json"
  if [ -f "$out" ] && grep -q '"ok": true' "$out"; then echo "[rm] $code 이미 있음 — 건너뜀"; continue; fi
  want=$(python -c "import json;p=json.load(open('$RD/prereg.json',encoding='utf-8'));print([c['md5'] for c in p['cells'] if c['code']=='$code'][0])")
  have=$(md5sum "$spec" | cut -c1-32)
  if [ "$want" != "$have" ]; then echo "[rm] $code 사양 md5 불일치(사전등록 $want · 지금 $have) — 측정하지 않는다"; exit 3; fi
  p1r03_rm_gate_wait; gr=$?; [ "$gr" = "0" ] || exit "$gr"
  echo "[rm] $code 측정 시작 $(ts) · 가용 ${mg}GB"
  QVEST_RP_NO_FACTOR_ANALYSIS=1 QVEST_RP_REGISTER=0 QVEST_RP_NO_LCODE=1 \
    Rscript 02_Infrastructure/ops/rf_cell_worker.R "$spec" 1 "$code" "$out" > "$OUT/${code}.log" 2> "$OUT/${code}.err.log"
  rc=$?
  g=$(python -c "import json;d=json.load(open('$out',encoding='utf-8'));print(d.get('ok'),d.get('grade'),d.get('artifacts','')[-22:])" 2>/dev/null)
  echo "[rm] $code rc=$rc · $g · $(ts)"
done
echo "[rm] 끝 $(ts)"
