#!/usr/bin/env bash
# covariance_freshness_gate.sh — Stale covariance cache 경고 (Level 2)
# v6.1 R6
#
# 이벤트: PreToolUse[Read] on .cache/covariance/*.parquet
# 목적: stale cache 사용 시 warn + Optimizer 재추정 요청
#
# SLA: 30일 경과 시 stale. Regime 변경 시도 stale.
# Meta sidecar file (*.meta.json)의 covariance_asof + regime_tag로 판정.

set -euo pipefail
trap 'echo "{\"decision\":\"allow\"}"; exit 0' ERR

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("file_path",""))' 2>/dev/null || echo "")

case "$FILE_PATH" in
  *.cache/covariance/*.parquet)
    META="${FILE_PATH%.parquet}.meta.json"
    if [[ ! -f "$META" ]]; then
      # 메타 없음 → 구식 캐시 → warn
      echo '{"decision":"allow","reason":"covariance_meta_missing (pre-v6.1 legacy cache)"}'
      exit 0
    fi

    python3 <<PYEOF
import json, os
from datetime import date, datetime

meta_path = r'''$META'''

try:
    with open(meta_path, 'r') as f:
        meta = json.load(f)
except Exception as e:
    print(json.dumps({"decision":"allow","reason":f"meta_unreadable: {e}"}))
    exit(0)

asof = meta.get('covariance_asof', '')
sla = int(meta.get('freshness_sla_days', 30))
regime_cached = meta.get('regime_tag', 'unknown')

try:
    asof_date = datetime.strptime(asof, "%Y-%m-%d").date()
except Exception:
    print(json.dumps({"decision":"allow","reason":"asof_unparseable"}))
    exit(0)

age = (date.today() - asof_date).days

# Current regime (if .cache/regime_current.json exists)
regime_current = None
regime_path = '.cache/regime_current.json'
if os.path.exists(regime_path):
    try:
        regime_current = json.load(open(regime_path)).get('regime_tag')
    except Exception:
        pass

warnings = []
if age > sla:
    warnings.append(f"stale_age_{age}d_sla_{sla}d")
if regime_current and regime_cached != regime_current:
    warnings.append(f"regime_mismatch_cached_{regime_cached}_current_{regime_current}")

if warnings:
    # Write warn log
    with open('/tmp/qvest_cov_freshness.log', 'a') as f:
        f.write(f"{datetime.now().isoformat()} | {meta_path} | {'; '.join(warnings)}\n")
    print(json.dumps({
        "decision": "allow",
        "reason": f"COV_STALE_WARN: {'; '.join(warnings)} — Optimizer 재추정 권장"
    }))
else:
    print(json.dumps({"decision":"allow","reason":"cov_fresh"}))
PYEOF
    ;;
  *)
    echo '{"decision":"allow"}'
    ;;
esac
