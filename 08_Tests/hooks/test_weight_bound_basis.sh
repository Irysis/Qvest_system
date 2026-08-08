#!/usr/bin/env bash
#==============================================================================
# test_weight_bound_basis.sh — deployed_holdings_check.py 개별상한 검사의 **차단 실효** 확인
#
# 계약: weight_bounds 상한(0.20)은 constraint_defaults.json::weight_bounds_basis="strategy_pre_cash"
#       — 즉 **현금 이전, 합=1 정규화된 전략 비중**에 적용된다.
#       배포 비중 = 전략비중 × invested 이므로, 배포 벡터에 그대로 0.20 을 걸면
#       invested<1 인 달에 상한이 비구속이 된다(2026-08-08 실측 정정 대상).
#
# 이 테스트가 재는 것:
#   ① 정상 산출물 → PASS (오탐 없음)
#   ② 전략기준 위반 주입(합=1 기준 0.25) → **FAIL 발화** (차단 실효)
#   ★③ 구판 로직(배포 비중 그대로 비교)이 같은 주입을 **놓치는지** — 수리의 효과 실증
#       (놓치지 않으면 수리가 무의미하므로 이 항목이 실패하면 설계를 재검토해야 한다)
#==============================================================================
set -uo pipefail
QM="${QM_ROOT:-C:/Users/99922/OneDrive/Quant_Module_Moltbot}"
cd "$QM" || exit 9
PY=".venv_qvest_ml/Scripts/python.exe"; [ -f "$PY" ] || PY=".venv_qvest_ml/bin/python"
[ -f "$PY" ] || { echo "XX venv python 부재 — 테스트 불가"; exit 9; }
CHK="02_Infrastructure/validation/deployed_holdings_check.py"
HD="05_Production/2.Factor_Model/2-4.STR_1715_on_M4gAE_R05_noLayer4_PG2/02_holdings_universe"
SRC="$HD/20260801_M4gAE_weights_cap_0p20.csv"
MAN="$HD/20260801_M4gAE_manifest.json"
[ -f "$SRC" ] && [ -f "$MAN" ] || { echo "XX 원본 산출물 부재"; exit 9; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok(){ echo "  [PASS] $1"; PASS=$((PASS+1)); }
ng(){ echo "  [FAIL] $1"; FAIL=$((FAIL+1)); }

run_chk(){ "$PY" "$CHK" --as-of 2026-08-01 --holdings "$1" --manifest "$MAN" --skip-liquidity 2>&1; }

echo "=== 개별상한 기준(strategy_pre_cash) 차단 실효 테스트 ==="

# ① 통제: 원본은 통과해야
OUT="$(run_chk "$SRC")"
if echo "$OUT" | grep -q "FAIL 상한 초과"; then ng "① 원본 정상분 — 오탐 발생"; else ok "① 원본 정상분 → 상한 FAIL 없음"; fi

# ② 위반 주입: 전략기준 0.25 (= 배포기준 0.25×invested)
INJ="$TMP/inject.csv"
"$PY" - "$SRC" "$INJ" <<'PYEOF'
import sys, pandas as pd
src, dst = sys.argv[1], sys.argv[2]
df = pd.read_csv(src)
eq = df.Ticker != "CASH"
inv = float(df.loc[eq, "Weight"].sum())
i = df.loc[eq, "Weight"].idxmax()
target_strategy = 0.25                      # 상한 0.20 을 25% 초과 (전략 기준)
delta = target_strategy*inv - df.at[i, "Weight"]
df.at[i, "Weight"] = target_strategy*inv    # 배포 기준으로는 0.25*inv (작은 값)
j = df.loc[eq & (df.index != i), "Weight"].idxmax()
df.at[j, "Weight"] = max(0.0, df.at[j, "Weight"] - delta)   # Σ 보존
df.to_csv(dst, index=False)
print(f"  (주입) 전략기준 {target_strategy:.4f} · 배포기준 {df.at[i,'Weight']:.6f} · invested {inv:.4f} · Σ {df.Weight.sum():.10f}")
PYEOF
OUT2="$(run_chk "$INJ")"
if echo "$OUT2" | grep -q "FAIL 상한 초과"; then ok "② 전략기준 0.25 주입 → 상한 FAIL 발화"; else ng "② 주입했는데 미발화 — 차단 실효 없음"; fi

# ★③ 구판 로직이 같은 주입을 놓치는지 (수리 효과 실증)
"$PY" - "$INJ" <<'PYEOF'
import sys, json, pandas as pd
df = pd.read_csv(sys.argv[1])
eq = df[df.Ticker != "CASH"]
with open("02_Infrastructure/worktask/constraint_defaults.json", encoding="utf-8-sig") as fh:
    hi = float(json.load(fh)["tier_soft_deployment"]["weight_bounds"][1])
legacy_over = int((eq.Weight > hi + 1e-9).sum())        # 구판: 배포 비중 그대로 비교
print(f"LEGACY_OVER={legacy_over}")
PYEOF
LEG=$("$PY" - "$INJ" <<'PYEOF'
import sys, json, pandas as pd
df = pd.read_csv(sys.argv[1]); eq = df[df.Ticker != "CASH"]
with open("02_Infrastructure/worktask/constraint_defaults.json", encoding="utf-8-sig") as fh:
    hi = float(json.load(fh)["tier_soft_deployment"]["weight_bounds"][1])
print(int((eq.Weight > hi + 1e-9).sum()))
PYEOF
)
if [ "$LEG" = "0" ]; then ok "③ 구판 로직은 같은 위반을 **놓침**(0건) → 수리가 실제 검출력을 추가"; \
  else ng "③ 구판도 잡음($LEG건) — 수리 효과 없음, 설계 재검토 필요"; fi

echo
echo "[결과] PASS $PASS / FAIL $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
echo "[OK] 상한 기준 strategy_pre_cash 차단 실효 확인"
