#!/usr/bin/env bash
#==============================================================================
# test_gate_a_state_read.sh — PG2 Gate A 상태 파일 판독의 양방향 검증
#
# 배경 (2026-08-29 실사고): qw_refresh_state.json 은 **PowerShell 이 쓰므로 BOM 이 붙는다**.
#   Gate A 는 `json.load(open(...))` 로 읽어 JSONDecodeError → `except: st={}` 로 접혔고,
#   그래서 상태가 신선하든 낡았든 **언제나 "5종 전부 미달"**을 보고했다.
#   실측: 파일에 20260731 5건이 멀쩡히 있는데 Gate A 는 전건 미달로 차단.
#   ⇒ 차단 자체는 맞았지만 **사유가 거짓**이었다. 게이트가 '못 읽음'과 '낡음'을 구분 못 하면
#     다음 사람이 원인을 원천이 아니라 게이트에서 찾는다(이 저장소 반복 부류).
#
# 계약 (판정 3분기가 실제로 갈리는가):
#   ① BOM 있는 신선한 상태 → ALLDONE      (구판은 여기서 INCOMPLETE 오보)
#   ② BOM 있는 낡은 상태   → INCOMPLETE   (진짜 미달 — 사유가 참)
#   ③ 파일 부재/파손       → UNREADABLE   (미달로 접지 않는다 — 미측정 ≠ 미달)
#==============================================================================
set -uo pipefail
QM="${QM_ROOT:-C:/Users/99922/OneDrive/Quant_Module_Moltbot}"
cd "$QM" || exit 9
# ★venv 고정 — QVEST_PY 는 pyarrow 없는 시스템 python 을 가리킬 수 있다(2026-08-29 실측:
#   QVEST_PY=…/Python312/python.exe → ModuleNotFoundError: pyarrow). 러너도 venv 를 쓴다.
PY="$QM/.venv_qvest_ml/Scripts/python.exe"
[ -f "$PY" ] || PY="${QVEST_PY:-python}"
"$PY" -c "import pyarrow" 2>/dev/null || { echo "XX pyarrow 없는 인터프리터 — 판정 불가(SKIP 아님)"; exit 9; }
RUNNER="02_Infrastructure/ops/run_pg2_rebalance_full.sh"
[ -f "$RUNNER" ] || { echo "XX 러너 부재"; exit 9; }

PASS=0; FAIL=0
ok(){ echo "  [PASS] $1"; PASS=$((PASS+1)); }
ng(){ echo "  [FAIL] $1"; FAIL=$((FAIL+1)); }

# 러너에서 Gate A 판정부(heredoc)를 그대로 추출 — 재구현하면 검사가 원본을 안 잰다
SNIP="$(mktemp /tmp/gateA_XXXX.py)"
awk '/^import json,os,pyarrow/{f=1} f{print} /^print\("ALLDONE/{if(f)exit}' "$RUNNER" > "$SNIP"
if [ ! -s "$SNIP" ]; then echo "XX Gate A 판정부 추출 실패 — 러너 구조 변경"; exit 9; fi

TMP_MSYS="$(mktemp -d)"; trap 'rm -rf "$TMP_MSYS" "$SNIP"' EXIT
mkdir -p "$TMP_MSYS/.cache"
cp ".cache/RAWDATA.parquet" "$TMP_MSYS/.cache/" 2>/dev/null || { echo "XX RAWDATA 사본 실패"; exit 9; }
# ★네이티브 경로로 변환 — MSYS 형(/tmp/…)을 python 소스 **문자열 리터럴**에 넣으면
#   FileNotFoundError 로 죽는다(env 로 넘길 때만 MSYS 가 자동 변환한다. 2026-08-29 실측).
TMP="$(cygpath -m "$TMP_MSYS" 2>/dev/null || echo "$TMP_MSYS")"
TARGET="$(QM_ROOT="$TMP" "$PY" -c "
import os, pyarrow.parquet as pq, pandas as pd
p = os.path.join(os.environ['QM_ROOT'], '.cache', 'RAWDATA.parquet')
print(pd.to_datetime(pq.read_table(p, columns=['Date']).to_pandas()['Date']).max().strftime('%Y%m%d'))")"
[ -n "$TARGET" ] || { echo "XX target 산출 실패 — 판정 불가"; exit 9; }

mkstate(){ # $1=ymd — BOM 붙여 쓴다(PowerShell 산출 재현)
  "$PY" - "$1" "$TMP/.cache/qw_refresh_state.json" <<'PYEOF'
import io, json, sys
ymd, path = sys.argv[1], sys.argv[2]
st = {n: {"ymd": ymd, "ts": "2026-01-01T00:00:00"} for n in
      ["Benchmark","OHLCVS","Universe_Support","Investor_Act","Consensus"]}
io.open(path, "w", encoding="utf-8-sig", newline="\r\n").write(json.dumps(st, indent=4))
PYEOF
}
run(){ QM_ROOT="$TMP" "$PY" "$SNIP" 2>/dev/null; }

echo "=== Gate A 상태 판독 3분기 (target=$TARGET) ==="

mkstate "$TARGET"
OUT="$(run)"
case "$OUT" in ALLDONE*) ok "① BOM+신선 → ALLDONE ($OUT)" ;;
  *) ng "① BOM+신선인데 ALLDONE 아님 → $OUT  (구판 BOM 결함 재발)" ;; esac

mkstate "19990101"
OUT="$(run)"
case "$OUT" in INCOMPLETE*) ok "② BOM+낡음 → INCOMPLETE (사유가 참)" ;;
  *) ng "② 낡은 상태를 못 잡음 → $OUT" ;; esac

rm -f "$TMP/.cache/qw_refresh_state.json"
OUT="$(run)"
case "$OUT" in UNREADABLE*) ok "③ 파일 부재 → UNREADABLE (미달로 접지 않음)" ;;
  *) ng "③ 부재를 미달/통과로 접음 → $OUT" ;; esac

printf '{"broken\n' > "$TMP/.cache/qw_refresh_state.json"
OUT="$(run)"
case "$OUT" in UNREADABLE*) ok "③ 파손 JSON → UNREADABLE" ;;
  *) ng "③ 파손을 미달/통과로 접음 → $OUT" ;; esac

echo "결과: PASS=$PASS FAIL=$FAIL"
echo "{\"test\":\"gate_a_state_read\",\"pass\":$PASS,\"fail\":$FAIL,\"total\":$((PASS+FAIL))}"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
