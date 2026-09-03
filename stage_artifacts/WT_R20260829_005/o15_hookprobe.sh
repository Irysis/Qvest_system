#!/usr/bin/env bash
# 훅 양방향 실증: 정상 통과 + 위반 주입 차단. ("경고 0" 만 보고 방어선이라 부르지 않는다)
set -u
ROOT=/c/Users/99922/OneDrive/Quant_Module_Moltbot
PKG="$ROOT/qepm/mailbox/worktask/WT-R20260829_005/optimization_package.json"
HOOK="$ROOT/02_Infrastructure/hooks/worktask_constraint_enforcer.sh"
PY="${QVEST_PY:-$ROOT/.venv_qvest_ml/Scripts/python.exe}"
[ -x "$PY" ] || PY=$(command -v python.exe)

probe () { # $1 = label, $2 = mutation mode
  PAYLOAD=$("$PY" - "$PKG" "$2" <<'PYEOF'
import json,sys
pkg=json.load(open(sys.argv[1],encoding="utf-8")); mode=sys.argv[2]
tw=pkg["target_weights"]
if mode=="names26":
    tw["ZZZ999"]=0.0; tw=dict(tw)
elif mode=="negative":
    k=list(tw)[0]; k2=list(tw)[1]; tw[k]=-0.01; tw[k2]=tw[k2]+0.01
elif mode=="sumne1":
    k=list(tw)[0]; tw[k]=tw[k]+0.05
pkg["target_weights"]=tw
out={"tool_name":"Write","tool_input":{"file_path":sys.argv[1],"content":json.dumps(pkg,ensure_ascii=False)}}
sys.stdout.write(json.dumps(out,ensure_ascii=False))
PYEOF
)
  RES=$(printf '%s' "$PAYLOAD" | bash "$HOOK" 2>/dev/null)
  echo "[$1] -> $RES"
}

probe "PASS(원본)"          none
probe "INJECT n=26"         names26
probe "INJECT w<0"          negative
probe "INJECT sum!=1"       sumne1
