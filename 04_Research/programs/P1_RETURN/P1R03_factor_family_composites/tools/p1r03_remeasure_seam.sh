#!/usr/bin/env bash
# P1R03 15칸 재측정 — 03-30 이음매 정정 뒤(RAWDATA · FF 요인 · 202611 · IC · 결합용 뷰 재빌드 뒤)
#   정본 셀 워커 그대로(rf_cell_worker.R → run_paper_replication → essence) · 사양 md5 = 사전등록 값 단정(R2) ·
#   닫힌 라운드의 results/ 는 건드리지 않는다 — 출력 = remeasure_seam_20261113/results/ · 모듈 풀 등재 끔(QVEST_RP_REGISTER=0 — 풀 교체는 따로)
#   측정 러너 규약: 배리어 held 면 기다린다(최대 30분) · 메모리 10GB 미만이면 기다린다 · 칸은 하나씩(셀 워커 정점 7.45GB).
set -u
ROOT="C:/Users/99922/OneDrive/Quant_Module_Moltbot"; cd "$ROOT" || exit 2
RD=04_Research/programs/P1_RETURN/P1R03_factor_family_composites
OUT=$RD/remeasure_seam_20261113/results; mkdir -p "$OUT"
ORDER="${P1R03_RM_ORDER:-FGROW FREGI FTECH FLIQU FRISK FCROW FVALU FLEVE FINVE FMOME FQUAL FACCR FCONS FDEFE TOTAL}"
ts() { date '+%F %T'; }
for c in $ORDER; do
  code="P1R03_${c}_C0"; spec="$RD/specs/${code}.json"; out="$OUT/${code}.json"
  if [ -f "$out" ] && grep -q '"ok": true' "$out"; then echo "[rm] $code 이미 있음 — 건너뜀"; continue; fi
  want=$(python -c "import json;p=json.load(open('$RD/prereg.json',encoding='utf-8'));print([c['md5'] for c in p['cells'] if c['code']=='$code'][0])")
  have=$(md5sum "$spec" | cut -c1-32)
  if [ "$want" != "$have" ]; then echo "[rm] $code 사양 md5 불일치(사전등록 $want · 지금 $have) — 측정하지 않는다"; exit 3; fi
  w=0; while :; do
    bash 02_Infrastructure/ops/refresh_barrier.sh status >/dev/null 2>&1; rb=$?
    mg=$(powershell.exe -NoProfile -NonInteractive -Command "[math]::Floor((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory/1MB)" 2>/dev/null | tr -d '\r\n ')
    if [ "$rb" = "0" ] && [ -n "$mg" ] && [ "$mg" -ge 10 ] 2>/dev/null; then break; fi
    [ "$w" -ge 1800 ] && { echo "[rm] 대기 상한(배리어 rc=$rb · 가용 ${mg:-?}GB) — 중단"; exit 6; }
    echo "[rm] 대기(배리어 rc=$rb · 가용 ${mg:-?}GB) $(ts)"; sleep 60; w=$((w + 60))
  done
  echo "[rm] $code 측정 시작 $(ts) · 가용 ${mg}GB"
  QVEST_RP_NO_FACTOR_ANALYSIS=1 QVEST_RP_REGISTER=0 QVEST_RP_NO_LCODE=1 \
    Rscript 02_Infrastructure/ops/rf_cell_worker.R "$spec" 1 "$code" "$out" > "$OUT/${code}.log" 2> "$OUT/${code}.err.log"
  rc=$?
  g=$(python -c "import json;d=json.load(open('$out',encoding='utf-8'));print(d.get('ok'),d.get('grade'),d.get('artifacts','')[-22:])" 2>/dev/null)
  echo "[rm] $code rc=$rc · $g · $(ts)"
done
echo "[rm] 끝 $(ts)"
