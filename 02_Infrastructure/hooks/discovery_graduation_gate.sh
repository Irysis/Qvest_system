#!/usr/bin/env bash
# discovery_graduation_gate.sh — Discovery → Deployment 전환 검증 (Level 3)
# v6.1 R1+R13
# v8.2.1 (2026-07-03 아키텍처 감사 CAP-P0-1/MC-01/HOOK-P0-3/MC-04): bare python3 → QVEST_PY/venv 절대경로 +
#   HARD 게이트 3종 완성(portfolio_alpha_t_nw 2.95 · oos_retention 0.7(<0.5 무조건 block, band warn) ·
#   calmar 0.64, 전부 forge-authoritative + 미산출 fail-closed) + sweep인데 DSR 미산출 block.
#   문턱 SOT: .claude/rules/measurement-graduation.md §3 + constraint_defaults.json tier_graduation.
#
# 이벤트: PreToolUse[Write] on Deployment request.json
# 목적: Deployment WT 생성 시 discovery_of 참조 WT의 graduation_criteria 충족 여부 확인
#
# 우회 조건:
#   - discovery_of == null (명시적 직접 Deployment) → warn only
#   - graduation_criteria 미설정 → allow
#
# Block 조건:
#   - discovery_of 참조된 Discovery WT의 alpha_package가 graduation_criteria 미충족

set -euo pipefail
trap 'echo "{}"; exit 0' ERR
# (v8.1.2 2026-06-11) python text 레이어 인코딩 사고 방지 — stdin은 buffer 경유 UTF-8 명시 디코딩,
# stdout은 UTF-8 reconfigure. (cp949 환경에서 한글 content가 가드를 침묵 무력화하던 문제)
export PYTHONUTF8=1

# (v8.2.1 2026-07-03 감사 HOOK-P0-3) bare python3 금지 — Windows Store 스텁이 침묵 무력화.
# 해석 체인: QVEST_PY(User env) → venv .venv_qvest_ml → 시스템 Python312. 전부 부재 시
# graduation 대상 write(WT-P*/request.json)만 fail-closed block, 그 외 allow.
PY="${QVEST_PY:-}"
{ [ -n "$PY" ] && [ -x "$PY" ]; } || PY="C:/Users/99922/OneDrive/Quant_Module_Moltbot/.venv_qvest_ml/Scripts/python.exe"
[ -x "$PY" ] || PY="C:/Users/99922/AppData/Local/Programs/Python/Python312/python.exe"
if [ ! -x "$PY" ]; then
  INPUT=$(cat)
  if printf '%s' "$INPUT" | grep -q 'WT-P' && printf '%s' "$INPUT" | grep -q 'request\.json'; then
    echo '{"decision": "block", "reason": "discovery_graduation_gate: python 실행기 부재(QVEST_PY/venv/Python312 전부 미발견) — graduation 검증 불가 (fail-closed)"}'
  else
    echo '{}'
  fi
  exit 0
fi

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | "$PY" -c 'import json,sys; sys.stdout.reconfigure(encoding="utf-8",errors="replace"); d=json.loads(sys.stdin.buffer.read().decode("utf-8","replace")); print(d.get("tool_input",{}).get("file_path",""))' 2>/dev/null || echo "")
CONTENT=$(echo "$INPUT" | "$PY" -c 'import json,sys; sys.stdout.reconfigure(encoding="utf-8",errors="replace"); d=json.loads(sys.stdin.buffer.read().decode("utf-8","replace")); print(d.get("tool_input",{}).get("content",""))' 2>/dev/null || echo "")

# Deployment WT request.json만 검증
case "$FILE_PATH" in
  */WT-P*/request.json)
    # (v8.1.2) content는 env 경유 — heredoc 소스 보간('''...''')은 triple-quote/backslash content에서
    # python 소스가 깨져 ERR trap '{}' fail-open 되던 주입형 패턴
    DGG_CONTENT="$CONTENT" "$PY" <<PYEOF
import json, os, sys

try:
    req = json.loads(os.environ.get("DGG_CONTENT", ""))
except Exception as e:
    print(json.dumps({}))
    sys.exit(0)

if req.get("wt_type") != "deployment":
    print(json.dumps({}))
    sys.exit(0)

discovery_of = req.get("discovery_of")
if discovery_of is None:
    # 직접 Deployment (Discovery 없이) — warn only (새 전략 직접 편성 허용)
    print(json.dumps({}))
    sys.exit(0)

# Discovery WT 참조 존재 확인
wt_root = "qepm/mailbox/worktask"
disc_dir = os.path.join(wt_root, discovery_of)
if not os.path.isdir(disc_dir):
    print(json.dumps({
      "decision": "block",
      "reason": f"discovery_of 참조 WT 없음: {discovery_of}"
    }))
    sys.exit(0)

alpha_path = os.path.join(disc_dir, "alpha_package.json")
if not os.path.exists(alpha_path):
    print(json.dumps({
      "decision": "block",
      "reason": f"{discovery_of}/alpha_package.json 없음 — Discovery WT alpha 미완료"
    }))
    sys.exit(0)

# (v8.1.2) fail-closed + encoding 명시 — cp949 locale에서 한글 포함 alpha_package(실파일 95/112개)
# 읽기 실패가 ERR trap '{}' allow로 빠져 graduation HARD 게이트가 침묵 통과되던 결함 수리
try:
    with open(alpha_path, encoding="utf-8") as f:
        alpha_pkg = json.load(f)
except Exception as e:
    print(json.dumps({
      "decision": "block",
      "reason": f"{discovery_of}/alpha_package.json 읽기 실패({type(e).__name__}) — graduation 검증 불가 (fail-closed)"
    }))
    sys.exit(0)
diag = alpha_pkg.get("diagnostics", {})
criteria = req.get("graduation_criteria", {})

# v8.x WS2 재설계: HARD = forge-authoritative portfolio_alpha_t_nw + DSR.
# rank-IC 계열(rank_ic/icir/subperiod/harvey_t)은 ADVISORY(warn only, block 안 함) —
# long-only 실현 alpha와 어긋나 거짓통과/거짓탈락 유발(16후보 calibration 실증).
# portfolio_alpha_t는 alpha-stage proxy 금지 → forge_package(authoritative)에서만 읽음.
forge_path = os.path.join(disc_dir, "forge_package.json")
forge_pkg = {}
if os.path.exists(forge_path):
    try:
        with open(forge_path, encoding="utf-8") as f: forge_pkg = json.load(f)
    except Exception:
        forge_pkg = {}

def num(v, d=None):
    return v if isinstance(v, (int, float)) else d

thr_pa  = criteria.get("min_portfolio_alpha_t_nw", 2.95)
thr_dsr = criteria.get("min_deflated_sharpe_ratio", criteria.get("min_dsr", 0.5))
thr_oos = criteria.get("min_oos_retention", 0.7)
thr_cal = criteria.get("min_calmar", 0.64)
OOS_FLOOR = 0.5  # measurement-graduation §3 (2026-06-10 C1): <0.5 무조건 FAIL — 보강증거 무관

hard_fail, advisory_fail = [], []

# HARD 1 — portfolio-alpha t (forge-authoritative NW lag-3). forge 미완 시 block(검증 불가).
pa_t = num(forge_pkg.get("portfolio_alpha_t_nw_lag3"))
if pa_t is None:
    hard_fail.append(f"forge_package.portfolio_alpha_t_nw_lag3 미산출 — forge 백테 미완(authoritative 미검증)")
elif pa_t < thr_pa:
    hard_fail.append(f"portfolio_alpha_t_nw {pa_t:.2f}<{thr_pa:.2f} (forge-authoritative)")

# HARD 2 — DSR: sweep형 selection에서만 HARD (measurement-graduation §3, 도훈 mandate 2026-05-31/2026-06-10).
#   chain(가설주도 순차개선)/단일검증은 advisory 강등 — 과적합 방어는 oos_retention/holdout 담당.
sel = str(req.get("selection_type") or forge_pkg.get("selection_type") or alpha_pkg.get("selection_type") or "").lower()
ntr = num(forge_pkg.get("n_trials_cumulative"), num(criteria.get("n_trials_cumulative")))
is_sweep = sel == "sweep" or (sel != "chain" and ntr is not None and ntr > 1)
dsr = num(forge_pkg.get("deflated_sharpe_ratio"), num(diag.get("dsr"), num(diag.get("deflated_sharpe_ratio"))))
if dsr is None:
    if is_sweep:
        # (v8.2.1 감사 MC-04) sweep인데 DSR 미산출 = HARD 게이트 검증 불가 → fail-closed
        hard_fail.append("DSR 미산출인데 selection=sweep — sweep은 DSR HARD (fail-closed)")
elif dsr < thr_dsr:
    if is_sweep:
        hard_fail.append(f"DSR {dsr:.3f}<{thr_dsr:.2f} (sweep)")
    else:
        advisory_fail.append(f"DSR {dsr:.3f}<{thr_dsr:.2f} (chain/단일 — non-block)")

# HARD 3 — oos_retention (v8.2.1 감사 CAP-P0-1/MC-01 배선. measurement-graduation §3 C1):
#   ≥0.7 단독 PASS / <0.5 무조건 block / [0.5, 0.7) band = warn + 보강증거 2/3 요구
#   (① trailing-subwindow PORT_t>0 ② placebo p<0.05 ③ book-marginal ΔSR>0 ∧ |cor|<0.30 —
#   band 조건부 PASS 판정 권위는 essence_score.R, 훅은 non-block warn만). 미산출 = block(fail-closed).
oos = num(forge_pkg.get("oos_retention"))
if oos is None:
    hard_fail.append("forge_package.oos_retention 미산출 — 과적합 게이트 미검증 (fail-closed)")
elif oos < OOS_FLOOR:
    hard_fail.append(f"oos_retention {oos:.3f}<{OOS_FLOOR:.2f} (무조건 FAIL — §3 band 하한)")
elif oos < thr_oos:
    advisory_fail.append(
        f"oos_retention {oos:.3f} band [{OOS_FLOOR:.2f},{thr_oos:.2f}) — 보강증거 2/3"
        f"(trailing PORT_t>0 / placebo p<0.05 / book-marginal ΔSR>0∧|cor|<0.30) 조건부 PASS 필요"
        f" (essence_score 판정 권위, holdout은 증거 불가)")

# HARD 4 — calmar ≥ 0.64 (=16%/25%, CAGR16·MDD25 도출 위험조정 게이트. §3). 미산출 = block(fail-closed).
cal = num(forge_pkg.get("calmar"))
if cal is None:
    hard_fail.append("forge_package.calmar 미산출 — 위험조정 게이트 미검증 (fail-closed)")
elif cal < thr_cal:
    hard_fail.append(f"calmar {cal:.3f}<{thr_cal:.2f}")

# ADVISORY — rank-IC 계열 (block 안 함, warn 기록)
for ckey, dkey in [("min_rank_ic","rank_ic"),("min_icir","icir"),
                   ("min_subperiod_stability","subperiod_stability"),("min_harvey_t_stat","harvey_t_stat")]:
    if ckey in criteria:
        act = num(diag.get(dkey), 0.0)
        if act < criteria[ckey]:
            advisory_fail.append(f"{dkey}={act:.4f}<{criteria[ckey]:.4f}")

if hard_fail:
    reason = f"graduation HARD 미충족 ({discovery_of}): " + " | ".join(hard_fail)
    if advisory_fail:
        reason += " || advisory(non-block): " + " | ".join(advisory_fail)
    print(json.dumps({"decision": "block", "reason": reason}))
else:
    # 통과(advisory fail은 차단 안 함). v8.x: rank-IC 약해도 forge HARD(PORT_t/oos/calmar/DSR) 충족이면 graduation.
    # (v8.2.1) advisory warn은 stderr 기록 — oos band 보강증거 요구 등이 침묵 통과되지 않도록.
    if advisory_fail:
        print(f"[discovery_graduation_gate] WARN ({discovery_of}): " + " | ".join(advisory_fail),
              file=sys.stderr)
    print(json.dumps({}))
PYEOF
    ;;
  *)
    echo '{}'
    ;;
esac
