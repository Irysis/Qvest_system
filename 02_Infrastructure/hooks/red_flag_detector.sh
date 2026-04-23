#!/usr/bin/env bash
# red_flag_detector.sh — Red Flag 자동 감지 + challenge_flags 주입 (Level 2 soft gate)
#
# 이벤트: PostToolUse[Write]
# 목적: 3-package 저장 후 red_flag_rules.md 기준 자동 scan
#
# CRITICAL은 worktask_constraint_enforcer.sh가 사전 block
# HIGH/MEDIUM는 challenge_flags 자동 주입 + /tmp/worktask_alerts.log 기록

set -euo pipefail
trap 'exit 0' ERR

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("file_path",""))' 2>/dev/null || echo "")

# 대상 파일
case "$FILE_PATH" in
  */alpha_package.json|*/risk_package.json|*/optimization_package.json)
    ;;
  *)
    exit 0
    ;;
esac

python3 <<PYEOF 2>/dev/null
import json, os, time, sys

fp = "$FILE_PATH"
try:
    with open(fp) as f:
        pkg = json.load(f)
except Exception:
    sys.exit(0)

flags = []
pkg_type = None

# Alpha Agent Red Flags
if "alpha_vector" in pkg:
    pkg_type = "alpha"
    d = pkg.get("diagnostics", {})
    specs = pkg.get("factor_specs", [])

    # RF-A1: 논문 단독 근거
    ref_counts = [len(s.get("references", [])) for s in specs]
    if all(c <= 2 for c in ref_counts) and d.get("subperiod_stability", 1) < 0.5:
        flags.append("RF-A1_HIGH: 논문 단독 근거 + subperiod unstable")

    # RF-A3: 최근 3년만 성과
    if d.get("subperiod_stability", 1) < 0.4:
        flags.append("RF-A3_HIGH: subperiod_stability < 0.4")

    # RF-A4: Sector-neutral 후 붕괴
    rank_ic = d.get("rank_ic", 0)
    post_n_ic = d.get("post_neutralization_ic", rank_ic)
    if rank_ic > 0 and post_n_ic < 0.3 * rank_ic:
        flags.append("RF-A4_HIGH: Sector-neutral 후 IC 70%+ 감소")

# Risk Agent Red Flags
elif "factor_covariance_ref" in pkg:
    pkg_type = "risk"
    d = pkg.get("diagnostics", {})
    rs = pkg.get("risk_summary", {})

    # RF-R2: Covariance ill-conditioned
    if d.get("condition_number", 0) > 500:
        flags.append(f"RF-R2_HIGH: condition_number {d.get('condition_number'):.1f} > 500")

    # RF-R4: Stress 정책 초과
    st = rs.get("stress_tests", {})
    if st.get("market_down_5", 0) < -0.08:
        flags.append(f"RF-R4_HIGH: market_down_5 {st.get('market_down_5')} < -8%")

# Optimizer Agent Red Flags
elif "method_selected" in pkg or "target_weights" in pkg:
    pkg_type = "optimizer"
    tw = pkg.get("target_weights", {})
    bc = pkg.get("binding_constraints", [])

    # RF-O2: 낮은 순알파
    ear = pkg.get("expected_active_return", 0)
    cost = pkg.get("estimated_cost", 0)
    if cost > 0 and ear < cost * 2:
        flags.append(f"RF-O2_HIGH: expected_active_return {ear:.4f} < cost*2 ({cost*2:.4f})")

    # RF-O3: 미세 리밸런싱
    to = pkg.get("turnover", 0)
    if 0 < to < 0.02:
        flags.append(f"RF-O3_MEDIUM: turnover {to:.4f} < 0.02")

    # RF-O1: Binding constraints 많음
    if len(bc) >= 5:
        flags.append(f"RF-O1_HIGH: binding_constraints {len(bc)}개 - 제약 타이트")

# Flag 주입
if flags:
    existing = pkg.get("challenge_flags", [])
    pkg["challenge_flags"] = list(set(existing + flags))
    with open(fp, 'w') as f:
        json.dump(pkg, f, indent=2, ensure_ascii=False)

    # Alert 로그
    with open("/tmp/worktask_alerts.log", "a") as f:
        ts = time.strftime('%Y-%m-%dT%H:%M:%S')
        for flag in flags:
            f.write(f"{ts} | {pkg_type} | {fp} | {flag}\n")

    # stderr에 간단 출력 (Q-Lead 시각화용)
    print(f"[RED_FLAG] {pkg_type}: {len(flags)} flag(s) injected", file=sys.stderr)
    for flag in flags:
        print(f"  - {flag}", file=sys.stderr)
PYEOF

exit 0
