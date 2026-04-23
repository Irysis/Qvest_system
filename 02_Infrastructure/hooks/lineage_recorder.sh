#!/usr/bin/env bash
# lineage_recorder.sh — Artifact lineage 자동 기록 (Level 2)
# v6.1 R11 P7 Lineage
#
# 이벤트: PostToolUse[Write] on {alpha,risk,optimization}_package.json
# 목적: 각 package 저장 시 artifact_lineage.json에 엔트리 append
#       git commit + input hash + seed + method_selected 수집

set -euo pipefail
trap 'exit 0' ERR

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("file_path",""))' 2>/dev/null || echo "")

case "$FILE_PATH" in
  */alpha_package.json|*/risk_package.json|*/optimization_package.json|*/execution_package.json)
    WT_ID=$(echo "$FILE_PATH" | grep -oE 'WT-[DP][0-9]{8}_[0-9]{3}|WT[0-9]{8}_[0-9]{3}' | head -1 || echo "")
    [[ -z "$WT_ID" ]] && exit 0

    PKG_TYPE=$(basename "$FILE_PATH" .json)

    DIR=$(ls -d /mnt/c/Users/*/OneDrive/바탕\ 화면/Quant_Module_Moltbot 2>/dev/null | head -1 || echo "$PWD")
    LINEAGE="$DIR/qepm/mailbox/worktask/$WT_ID/artifact_lineage.json"

    # Git commit
    GIT_SHA=$(cd "$DIR" && git rev-parse HEAD 2>/dev/null || echo "unknown")
    GIT_DIRTY=$(cd "$DIR" && [ -z "$(git status --porcelain 2>/dev/null)" ] && echo "false" || echo "true")

    # File hash
    PKG_HASH=$(sha256sum "$FILE_PATH" 2>/dev/null | cut -d' ' -f1 || echo "unknown")

    TS=$(date -Iseconds)

    # Append (atomic-ish via python merge)
    python3 <<PYEOF
import json, os
lineage_path = r'''$LINEAGE'''
wt_id = "$WT_ID"
pkg_type = "$PKG_TYPE"

try:
    if os.path.exists(lineage_path):
        with open(lineage_path) as f:
            lineage = json.load(f)
    else:
        lineage = {"task_id": wt_id, "schema_version": "v1.0", "entries": []}

    entry = {
        "package_type": pkg_type,
        "created_at": "$TS",
        "git_commit": "$GIT_SHA",
        "git_dirty": $GIT_DIRTY,
        "file_path": "$FILE_PATH",
        "file_hash_sha256": "$PKG_HASH",
        "recorded_by": "lineage_recorder_hook"
    }
    lineage.setdefault("entries", []).append(entry)
    lineage["last_updated"] = "$TS"

    with open(lineage_path, 'w') as f:
        json.dump(lineage, f, indent=2, ensure_ascii=False)
except Exception as e:
    with open('/tmp/qvest_lineage_errors.log', 'a') as f:
        f.write(f"$TS | $WT_ID | $PKG_TYPE | {e}\n")
PYEOF
    ;;
esac

exit 0
