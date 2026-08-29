#!/usr/bin/env bash
# ★RETIRED (v10 2026-08-29): governor 폐지 — 감시 대상(book_state↔governor verdict 정합) 소멸.
#   승계 = PreToolUse book_write_guard.sh (BOOK 정본 직접 편집 + legacy book_state 재기입 차단).
#   파일 사료 존치. 재열람 = git pre-v10-2layer.
# (v8.2.1 HOOK-P0-1) bare python3 → $QVEST_PY_BIN (Windows Store 스텁 fail-open 방지)
if [ -z "${QVEST_PY_BIN:-}" ]; then
  QVEST_PY_BIN="${QVEST_PY:-}"; QVEST_PY_BIN="${QVEST_PY_BIN//\//}"
  { [ -n "$QVEST_PY_BIN" ] && [ -x "$QVEST_PY_BIN" ]; } || QVEST_PY_BIN="/c/Users/99922/OneDrive/Quant_Module_Moltbot/.venv_qvest_ml/Scripts/python.exe"
  [ -x "$QVEST_PY_BIN" ] || QVEST_PY_BIN="$(command -v python.exe 2>/dev/null || echo python3)"
  export QVEST_PY_BIN
fi
# governor_concord_certifier.sh — v1.2 Governor Concord Certifier (Positive Hook + 1 Hard Block)
#
# Charter §10 Governor Concord Certification System.
# 이벤트: PostToolUse[Write|Edit] matcher: book_state.json
#
# Positive certifier 동작:
#   - Match (book_state ↔ governor_admission verdict): governor_concord_certificate 발급
#   - Mismatch + waiver 5-row 명시: governor_concord_with_waiver_certificate 발급
#   - Mismatch + waiver 부재: certificate 미발급 + governance_log "concord_pending"
#
# Hard block 1건 (Charter §10 system integrity):
#   - book_state에 governor_admission.json 전무한 STR_id 추가 시 → decision:"block"
#     (admission graduation 단계 자체 우회 = system integrity 위협)
#
# Reference violation: STR_1715 OVERRIDE_005/006 — Governor Option B Probe 10pct → User OVERRIDE 100%

set -euo pipefail
trap 'echo "{}"; exit 0' ERR

INPUT=$(cat)
TOOL=$(printf '%s' "$INPUT" | "$QVEST_PY_BIN" -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_name",""))' 2>/dev/null || echo "")
FILE_PATH=$(printf '%s' "$INPUT" | "$QVEST_PY_BIN" -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("file_path",""))' 2>/dev/null || echo "")

if [[ "$TOOL" != "Write" && "$TOOL" != "Edit" ]]; then echo '{}'; exit 0; fi
if [[ ! "$FILE_PATH" =~ book_state\.json$ ]]; then echo '{}'; exit 0; fi
if [[ ! -f "$FILE_PATH" ]]; then echo '{}'; exit 0; fi

# WT mailbox root 추론 (book_state.json 위치 기준 상위 mailbox 디렉토리)
BS_DIR=$(dirname "$FILE_PATH")
WT_ROOT=""
# Production: qepm/mailbox/governor/book_state.json → qepm/mailbox/worktask/
if [[ "$BS_DIR" =~ /qepm/mailbox/governor$ ]]; then
  WT_ROOT="${BS_DIR%/governor}/worktask"
fi
# Fallback: BS_DIR 부모에 worktask 폴더 존재 시 (test 환경 + 일반 mailbox 구조)
if [[ -z "$WT_ROOT" ]] || [[ ! -d "$WT_ROOT" ]]; then
  PARENT_DIR=$(dirname "$BS_DIR")
  if [[ -d "$PARENT_DIR/worktask" ]]; then
    WT_ROOT="$PARENT_DIR/worktask"
  fi
fi
LOG="/tmp/governor_concord_certifier.log"

VERDICT=$("$QVEST_PY_BIN" <<PYEOF 2>>"$LOG"
import json, os, glob, datetime, sys

try:
    with open("$FILE_PATH") as f:
        bs = json.load(f)
except Exception as e:
    print(f"PARSE_FAIL:{e}")
    sys.exit(0)

admitted_ids = bs.get("admitted_ids", []) or []
weights = bs.get("book_weights", {}) or {}
wt_root = "$WT_ROOT"

# 1. STR별 latest governor_admission verdict 조회
def find_latest_admission(str_id, wt_root):
    if not wt_root or not os.path.isdir(wt_root):
        return None, None
    candidates = []
    for wt_dir in sorted(glob.glob(os.path.join(wt_root, "WT-*"))):
        ga_path = os.path.join(wt_dir, "governor_admission.json")
        if not os.path.exists(ga_path):
            continue
        try:
            with open(ga_path) as f:
                ga = json.load(f)
        except Exception:
            continue
        if ga.get("str_id") == str_id:
            candidates.append((ga.get("generated_at", ""), wt_dir, ga))
    if not candidates:
        return None, None
    candidates.sort(reverse=True)
    return candidates[0][1], candidates[0][2]

# 2. user_override 또는 waiver 5-row 명시 확인
override_blocks = [k for k in bs.keys() if k.startswith("user_override_")]
latest_override = None
if override_blocks:
    latest_override_key = sorted(override_blocks)[-1]
    raw_override = bs.get(latest_override_key, {})
    # user_override_log = list of dict entries (override history) → take last dict entry
    # user_override_NNN_directive = direct dict
    if isinstance(raw_override, list):
        for entry in reversed(raw_override):
            if isinstance(entry, dict):
                latest_override = entry
                break
    elif isinstance(raw_override, dict):
        latest_override = raw_override

waiver_required_keys = [
    "stress_negative_acknowledged",
    "lockbox_divergence_acknowledged",
    "ax_triangulation_2of3_acknowledged",
    "tdc_diversification_forfeit_acknowledged",
    "to_marginal_acknowledged"
]
def has_waiver_5row(override_block):
    if not override_block or not isinstance(override_block, dict):
        return False
    # waiver_5row 객체 또는 trade_off_accepted_by_user list 둘 다 허용
    waiver_obj = override_block.get("risk_waiver_5row") or override_block.get("waiver_5row") or {}
    if isinstance(waiver_obj, dict):
        return all(waiver_obj.get(k, False) for k in waiver_required_keys)
    return False

# 3. 각 admitted_id verdict 비교
results = []
hard_block_str = None
for str_id in admitted_ids:
    wt_dir, ga = find_latest_admission(str_id, wt_root)
    if ga is None:
        # Hard block 1건: governor_admission.json 전무 → admission graduation 우회
        hard_block_str = str_id
        break
    admitted_scenario = ga.get("admission_scenario", "")
    allocation_decided = ga.get("allocation_decided", {})
    expected_weight = allocation_decided.get(str_id) if isinstance(allocation_decided, dict) else None
    actual_weight = weights.get(str_id, None)
    is_match = (expected_weight is not None and actual_weight is not None
                and abs(expected_weight - actual_weight) < 0.01)
    results.append({
        "str_id": str_id,
        "admitted_scenario": admitted_scenario,
        "expected_weight": expected_weight,
        "actual_weight": actual_weight,
        "match": is_match,
        "wt_dir": wt_dir
    })

if hard_block_str:
    print(f"HARD_BLOCK:{hard_block_str}")
    sys.exit(0)

if not results:
    print("NO_ADMITTED_IDS")
    sys.exit(0)

# 4. 종합 판정
all_match = all(r["match"] for r in results)
waiver_present = has_waiver_5row(latest_override)

if all_match:
    cert_type = "governor_concord_certificate"
    cert_data = {
        "issued": True,
        "concord_type": "match",
        "all_admitted_match": True,
        "details": results,
        "issued_at": datetime.datetime.now().astimezone().isoformat(timespec='seconds'),
        "issued_by": "governor_concord_certifier.sh v1.2",
        "charter_ref": "v1.2 §10 Governor Concord Certificate"
    }
elif waiver_present:
    cert_type = "governor_concord_with_waiver_certificate"
    cert_data = {
        "issued": True,
        "concord_type": "with_waiver",
        "all_admitted_match": False,
        "details": results,
        "waiver_5row_present": True,
        "override_id": latest_override.get("decision", "") if latest_override else "",
        "issued_at": datetime.datetime.now().astimezone().isoformat(timespec='seconds'),
        "issued_by": "governor_concord_certifier.sh v1.2",
        "charter_ref": "v1.2 §10 Governor Concord (waiver)"
    }
else:
    cert_type = "governor_concord_certificate_pending"
    cert_data = {
        "issued": False,
        "concord_type": "pending",
        "all_admitted_match": False,
        "details": results,
        "waiver_5row_present": False,
        "remediation": "waiver 5-row 명시 (stress_negative / lockbox_divergence / ax_triangulation_2of3 / tdc_diversification_forfeit / to_marginal) 후 governor_concord_with_waiver_certificate 발급",
        "logged_at": datetime.datetime.now().astimezone().isoformat(timespec='seconds'),
        "logged_by": "governor_concord_certifier.sh v1.2",
        "charter_ref": "v1.2 §10"
    }

cert_path = os.path.join("$BS_DIR", cert_type + ".json")
with open(cert_path, "w") as f:
    json.dump(cert_data, f, indent=2, ensure_ascii=False)

print(f"OK:{cert_type}")
PYEOF
)

echo "[$(date -Iseconds)] verdict=$VERDICT" >> "$LOG"

# Hard block: governor_admission.json 전무한 STR
if [[ "$VERDICT" =~ ^HARD_BLOCK: ]]; then
  STR_ID="${VERDICT#HARD_BLOCK:}"
  BLOCK_REASON="ADMISSION_GRADUATION_BYPASS (Charter §10 hard block): book_state.json admit하려는 STR=$STR_ID 의 governor_admission.json이 전무. PG admission gate 자체 우회. Governor pg1_admission() 통과 후 재시도."
  echo "{\"decision\":\"block\",\"reason\":\"$BLOCK_REASON\"}"
  exit 0
fi

# Positive guidance
case "$VERDICT" in
  OK:governor_concord_certificate)
    echo "{}"
    ;;
  OK:governor_concord_with_waiver_certificate)
    echo "{}"
    ;;
  OK:governor_concord_certificate_pending)
    echo "{}"
    ;;
  *)
    echo '{}'
    ;;
esac
