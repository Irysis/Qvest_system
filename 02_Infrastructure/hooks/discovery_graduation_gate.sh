#!/usr/bin/env bash
# discovery_graduation_gate.sh — Discovery → Deployment 전환 검증 (Level 3)
# v6.1 R1+R13
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

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("file_path",""))' 2>/dev/null || echo "")
CONTENT=$(echo "$INPUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("content",""))' 2>/dev/null || echo "")

# Deployment WT request.json만 검증
case "$FILE_PATH" in
  */WT-P*/request.json)
    python3 <<PYEOF
import json, os, sys

try:
    req = json.loads('''$CONTENT''')
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

with open(alpha_path) as f:
    alpha_pkg = json.load(f)
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
        with open(forge_path) as f: forge_pkg = json.load(f)
    except Exception:
        forge_pkg = {}

def num(v, d=None):
    return v if isinstance(v, (int, float)) else d

thr_pa  = criteria.get("min_portfolio_alpha_t_nw", 2.95)
thr_dsr = criteria.get("min_deflated_sharpe_ratio", criteria.get("min_dsr", 0.5))

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
if dsr is not None and dsr < thr_dsr:
    if is_sweep:
        hard_fail.append(f"DSR {dsr:.3f}<{thr_dsr:.2f} (sweep)")
    else:
        advisory_fail.append(f"DSR {dsr:.3f}<{thr_dsr:.2f} (chain/단일 — non-block)")

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
    # 통과(advisory fail은 차단 안 함). v8.x: rank-IC 약해도 forge PORT_t/DSR 충족이면 graduation.
    print(json.dumps({}))
PYEOF
    ;;
  *)
    echo '{}'
    ;;
esac
