#!/usr/bin/env bash
# alpha_discovery_certifier.sh — v1.2 Charter §10 Positive Certifier (L2)
#
# Charter §10 Alpha Discovery Certification System.
# 이벤트: PostToolUse[Write] matcher: alpha_package.json
# 동작: 발급 조건 충족 시 sibling file `alpha_discovery_certificate.json` 자동 발급.
#       미충족 시 미발급 (block 아님). passive deny via certificate 부재 → PG1 admission 자격 박탈.
#
# 발급 조건 (4종 AND):
#   1. alpha_inheritance_cor < 0.95
#   2. mechanism_cited 길이 ≥ 50 chars (hypothesis_summary 또는 factor_specs[].economic_rationale)
#   3. factor_specs.length ≥ 1
#   4. harvey_t_specs_pass_count ≥ 3
#
# Reference: STR_1715 OVERRIDE_006 사후 — alpha_inheritance_cor=1.0이 "alpha discovery"로 framing되어 PG1 통과한 사고 차단.

set -euo pipefail
trap 'echo "{\"decision\":\"allow\"}"; exit 0' ERR

INPUT=$(cat)
TOOL=$(printf '%s' "$INPUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_name",""))' 2>/dev/null || echo "")
FILE_PATH=$(printf '%s' "$INPUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("file_path",""))' 2>/dev/null || echo "")

# alpha_package.json만 처리
if [[ "$TOOL" != "Write" && "$TOOL" != "Edit" ]]; then echo '{"decision":"allow"}'; exit 0; fi
if [[ ! "$FILE_PATH" =~ alpha_package\.json$ ]]; then echo '{"decision":"allow"}'; exit 0; fi
if [[ ! -f "$FILE_PATH" ]]; then echo '{"decision":"allow"}'; exit 0; fi

WT_DIR=$(dirname "$FILE_PATH")
CERT_PATH="$WT_DIR/alpha_discovery_certificate.json"
LOG="/tmp/alpha_discovery_certifier.log"

# Self-trigger 방지: 이미 certificate file 존재 시 skip
if [[ -f "$CERT_PATH" ]]; then
  echo '{"decision":"allow"}'
  exit 0
fi

# request.json에서 wt_type 확인
REQ_PATH="$WT_DIR/request.json"
WT_TYPE="discovery"
if [[ -f "$REQ_PATH" ]]; then
  WT_TYPE=$(python3 -c "import json; print(json.load(open('$REQ_PATH')).get('wt_type','discovery'))" 2>/dev/null || echo "discovery")
fi

# sizing_only / hyperparameter_sweep은 certificate 발급 *불필요* (정상 동작)
if [[ "$WT_TYPE" == "sizing_only" || "$WT_TYPE" == "hyperparameter_sweep" ]]; then
  echo "[$(date -Iseconds)] $WT_TYPE WT — certificate skip (Role Card 정상)" >> "$LOG"
  echo '{"decision":"allow"}'
  exit 0
fi

# 발급 조건 검증 (Python)
VERDICT=$(python3 <<PYEOF 2>>"$LOG"
import json, sys, datetime

try:
    with open("$FILE_PATH") as f:
        pkg = json.load(f)
except Exception as e:
    print(f"PARSE_FAIL:{e}")
    sys.exit(0)

diag = pkg.get("diagnostics", {})
cor = diag.get("alpha_inheritance_cor", None)
harvey_pass = diag.get("harvey_t_specs_pass_count", 0)

# factor_specs 신규 갯수
factor_specs = pkg.get("factor_specs", [])
n_factor = len(factor_specs) if isinstance(factor_specs, list) else 0

# mechanism citation 길이
mechanism = ""
if factor_specs and isinstance(factor_specs, list):
    for fs in factor_specs:
        if isinstance(fs, dict):
            mechanism += " " + str(fs.get("economic_rationale", ""))
            mechanism += " " + str(fs.get("formula", ""))
hypothesis_summary = pkg.get("hypothesis_summary", "")
mechanism = (mechanism + " " + str(hypothesis_summary)).strip()
mechanism_len = len(mechanism)

# 4-condition check
issues = []
if cor is None:
    issues.append("alpha_inheritance_cor 필드 부재")
elif cor >= 0.95:
    issues.append(f"alpha_inheritance_cor={cor:.4f} >= 0.95 (parent와 동일, sizing/sweep 의심)")
if mechanism_len < 50:
    issues.append(f"mechanism citation 길이 {mechanism_len} < 50 chars")
if n_factor < 1:
    issues.append(f"factor_specs 수 {n_factor} < 1")
if harvey_pass < 3:
    issues.append(f"harvey_t_specs_pass_count={harvey_pass} < 3")

if not issues:
    # ISSUE certificate
    cert = {
        "issued": True,
        "wt_id": pkg.get("task_id", ""),
        "inheritance_cor_actual": cor,
        "inheritance_cor_max": 0.95,
        "mechanism_cited_chars": mechanism_len,
        "factor_specs_new_count": n_factor,
        "harvey_t_specs_pass_count": harvey_pass,
        "issued_at": datetime.datetime.now().astimezone().isoformat(timespec='seconds'),
        "issued_by": "alpha_discovery_certifier.sh v1.2",
        "charter_ref": "v1.2 §10 Alpha Discovery Certification System",
        "non_issuance_reason": None
    }
    with open("$CERT_PATH", "w") as f:
        json.dump(cert, f, indent=2, ensure_ascii=False)
    print("ISSUED")
else:
    # NON-ISSUE certificate (passive deny 명시)
    cert = {
        "issued": False,
        "wt_id": pkg.get("task_id", ""),
        "inheritance_cor_actual": cor,
        "inheritance_cor_max": 0.95,
        "mechanism_cited_chars": mechanism_len,
        "factor_specs_new_count": n_factor,
        "harvey_t_specs_pass_count": harvey_pass,
        "issued_at": datetime.datetime.now().astimezone().isoformat(timespec='seconds'),
        "issued_by": "alpha_discovery_certifier.sh v1.2",
        "charter_ref": "v1.2 §10",
        "non_issuance_reason": " | ".join(issues),
        "remediation": "alpha agent rerun: cor < 0.95 + mechanism >= 50 chars + factor_specs >= 1 + harvey_t pass >= 3"
    }
    with open("$CERT_PATH", "w") as f:
        json.dump(cert, f, indent=2, ensure_ascii=False)
    print("NOT_ISSUED")
PYEOF
)

echo "[$(date -Iseconds)] WT_DIR=$WT_DIR verdict=$VERDICT" >> "$LOG"

# Positive guidance message (block 아님)
if [[ "$VERDICT" == "ISSUED" ]]; then
  echo "{\"decision\":\"allow\",\"warning\":\"✓ alpha_discovery_certificate ISSUED — PG1 admission 자격 인증\"}"
elif [[ "$VERDICT" == "NOT_ISSUED" ]]; then
  echo "{\"decision\":\"allow\",\"warning\":\"alpha_discovery_certificate NOT_ISSUED — PG1 admission 자격 박탈 (passive deny). alpha_discovery_certificate.json 참조하여 remediation\"}"
else
  echo "{\"decision\":\"allow\"}"
fi
