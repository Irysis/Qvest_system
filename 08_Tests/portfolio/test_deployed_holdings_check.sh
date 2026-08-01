#!/usr/bin/env bash
# test_deployed_holdings_check.sh — 배포 홀딩 제약 검사기 위반 주입 테스트
#
# 대상: 02_Infrastructure/validation/deployed_holdings_check.py
#
# 왜: 이 검사기는 월간 리밸 Gate C 직후에 도는 마지막 방어선이다. 검사기가 죽으면
#     "전부 OK" 와 "아무것도 안 잼" 이 겉보기에 같다 — 2026-08-01 실측으로 확인된 계통
#     (파일 존재/mtime/프로세스명 검사가 각각 형식·신호일·인자를 재지 못했다).
#     그래서 양성 대조만이 아니라 **일부러 틀린 입력을 넣어 발화하는지**를 고정한다.
#
# 픽스처는 tempdir 에만 만든다 — 05_Production 실산출을 건드리지 않는다.
set -uo pipefail

_SELF="${BASH_SOURCE[0]:-$0}"; _SELF_DIR="$(cd "$(dirname "$_SELF")" && pwd)"
PROJ="${CLAUDE_PROJECT_DIR:-${QM_ROOT:-}}"
if [ -z "$PROJ" ] || [ ! -f "$PROJ/02_Infrastructure/hooks/qvest_hook_router.py" ]; then
  PROJ="$(cd "$_SELF_DIR/../.." && pwd)"
fi
PROJ="${PROJ//\\//}"
export QM_ROOT="$PROJ"

CHK="$PROJ/02_Infrastructure/validation/deployed_holdings_check.py"
PY="$PROJ/.venv_qvest_ml/Scripts/python.exe"
[ -x "$PY" ] || PY="$(command -v python3 || command -v python)"

PASS=0; FAIL=0
chk(){ local n="$1" exp="$2" got="$3"
  if [ "$exp" = "$got" ]; then PASS=$((PASS+1)); echo "  ok   $n"
  else FAIL=$((FAIL+1)); echo "  FAIL $n (기대=$exp 실제=$got)"; fi; }

TD="$(mktemp -d 2>/dev/null || echo "${TMPDIR:-/tmp}/dhc_$$")"; mkdir -p "$TD"
cleanup(){ rm -rf "$TD"; }
trap cleanup EXIT   # ★함수 프레임 아님(스크립트 최상위) — bash trap 은 발화한다(R on.exit 금칙과 무관)

# ── 픽스처: 규약을 만족하는 base 홀딩/매니페스트 + 전월본 ────────────────────
"$PY" - "$TD" <<'PYEOF'
import json, sys, csv, os
TD = sys.argv[1]
def write(name, rows):
    with open(os.path.join(TD, name), "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f); w.writerow(["rank","Ticker","Name","Sector","Weight"])
        for i, (t, wt) in enumerate(rows): w.writerow([i, t, f"N{t}", "테스트", wt])
# invested 0.30 = gate 1.00 x beta 0.30 · 주식 10종(각 0.03) · CASH 0.70
cur = [("CASH", 0.70)] + [(f"A{i:06d}", 0.03) for i in range(1, 11)]
write("cur.csv", cur)
# 전월: 다른 비중(지문이 달라야 정상)
prev = [("CASH", 0.70)] + [(f"A{i:06d}", 0.03 if i != 1 else 0.029) for i in range(1, 11)]
prev[1] = ("A000001", 0.029); prev.append(("A000011", 0.001))
write("prev.csv", prev)
man = {
  "strategy": "TEST", "as_of": "2026-08-01",
  "overlays": {"m4_scalar": 1.0, "ae_fire_seq": 1, "m4_ae_gate": 1.0,
               "beta_R05_V5": {"value": 0.30, "regime": "CRISIS", "R05_z_avg": -0.35}},
  "invested": 0.30, "cash_pct": 0.70, "n_equity": 10,
  "pit": {"no_future_reference": True, "ae_last_feat": "2026-06-30", "ae_pit_ok": True},
}
json.dump(man, open(os.path.join(TD, "man.json"), "w", encoding="utf-8"), ensure_ascii=False)
PYEOF

run(){ "$PY" "$CHK" --as-of "${AS_OF:-2026-08-01}" --holdings "$1" --manifest "$2" \
        ${3:+--prev-holdings "$3"} --skip-liquidity >/dev/null 2>&1; echo $?; }

echo "── T0 양성 대조 (규약 만족 → PASS) ───────────────────────────────────────"
chk "T0 정상 입력은 통과" "0" "$(run "$TD/cur.csv" "$TD/man.json" "$TD/prev.csv")"

echo "── T1~T4 홀딩 제약 위반 주입 ─────────────────────────────────────────────"
"$PY" - "$TD" <<'PYEOF'
import pandas as pd, os, sys
TD = sys.argv[1]; h = pd.read_csv(os.path.join(TD, "cur.csv"))
# 종목수: 26종으로
ex = pd.DataFrame({"rank": range(90, 106), "Ticker": [f"X{i:05d}" for i in range(16)],
                   "Name": "주입", "Sector": "t", "Weight": 0.001})
a = pd.concat([h, ex], ignore_index=True); a.loc[a.Ticker == "CASH", "Weight"] = 0.70 - 0.001*16
a.to_csv(os.path.join(TD, "v_names.csv"), index=False)
b = h.copy(); b.loc[b.Ticker == "A000002", "Weight"] = -0.01
b.loc[b.Ticker == "CASH", "Weight"] = 0.74
b.to_csv(os.path.join(TD, "v_neg.csv"), index=False)
c = h.copy(); c.loc[c.Ticker == "A000003", "Weight"] = 0.35
c.loc[c.Ticker == "CASH", "Weight"] = 0.70 - 0.32
c.to_csv(os.path.join(TD, "v_ub.csv"), index=False)
d = h.copy(); d.loc[d.Ticker == "CASH", "Weight"] = 0.60
d.to_csv(os.path.join(TD, "v_sum.csv"), index=False)
PYEOF
chk "T1 종목수 25 초과 검거"  "1" "$(run "$TD/v_names.csv" "$TD/man.json" "$TD/prev.csv")"
chk "T2 음수 비중 검거"        "1" "$(run "$TD/v_neg.csv"   "$TD/man.json" "$TD/prev.csv")"
chk "T3 개별 상한 초과 검거"   "1" "$(run "$TD/v_ub.csv"    "$TD/man.json" "$TD/prev.csv")"
chk "T4 Sum(w)!=1 검거"        "1" "$(run "$TD/v_sum.csv"   "$TD/man.json" "$TD/prev.csv")"

echo "── T5~T9 매니페스트 위반 주입 ────────────────────────────────────────────"
"$PY" - "$TD" <<'PYEOF'
import json, os, sys
TD = sys.argv[1]; base = json.load(open(os.path.join(TD, "man.json"), encoding="utf-8"))
def put(name, mut):
    m = json.loads(json.dumps(base)); mut(m)
    json.dump(m, open(os.path.join(TD, name), "w", encoding="utf-8"), ensure_ascii=False)
put("m_asof.json",  lambda m: m.__setitem__("as_of", "2026-07-01"))
put("m_zna.json",   lambda m: m["overlays"]["beta_R05_V5"].__setitem__("R05_z_avg", None))
put("m_beta.json",  lambda m: m["overlays"]["beta_R05_V5"].__setitem__("value", 0.85))
put("m_gate.json",  lambda m: m["overlays"].__setitem__("m4_ae_gate", 0.70))
put("m_aepit.json", lambda m: m["pit"].__setitem__("ae_pit_ok", False))
PYEOF
chk "T5 as_of 불일치 검거"          "1" "$(run "$TD/cur.csv" "$TD/m_asof.json"  "$TD/prev.csv")"
chk "T6 R05_z 결측(폴백) 검거"      "1" "$(run "$TD/cur.csv" "$TD/m_zna.json"   "$TD/prev.csv")"
chk "T7 beta 규칙표 위반 검거"      "1" "$(run "$TD/cur.csv" "$TD/m_beta.json"  "$TD/prev.csv")"
chk "T8 게이트 규칙 불일치 검거"    "1" "$(run "$TD/cur.csv" "$TD/m_gate.json"  "$TD/prev.csv")"
chk "T9 AE PIT 위반 검거"           "1" "$(run "$TD/cur.csv" "$TD/m_aepit.json" "$TD/prev.csv")"

echo "── T10~T12 조용한 재출력 / 부재 ──────────────────────────────────────────"
chk "T10 전월과 지문 동일 검거"  "1" "$(run "$TD/cur.csv" "$TD/man.json" "$TD/cur.csv")"
chk "T11 홀딩 부재는 2"          "2" "$(run "$TD/nope.csv" "$TD/man.json" "$TD/prev.csv")"
chk "T12 매니페스트 부재는 2"    "2" "$(run "$TD/cur.csv" "$TD/nope.json" "$TD/prev.csv")"

echo "── T13 음성 통제: 검사기가 무조건 FAIL 을 뱉는 게 아님 ───────────────────"
# T0 이 이미 PASS 이지만, 전월 미지정(경고만)에서도 hard FAIL 이 아님을 확인한다 —
# 경고와 실패를 구분하지 못하면 게이트로 쓸 수 없다.
chk "T13 전월 미지정은 WARN(통과)" "0" "$(run "$TD/cur.csv" "$TD/man.json")"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
echo "{\"test\":\"deployed_holdings_check\",\"pass\":$PASS,\"fail\":$FAIL,\"total\":$((PASS+FAIL))}"
[ "$FAIL" -eq 0 ] || exit 1
