#!/usr/bin/env bash
#==============================================================================
# artifact_placement_guard.sh — PreToolUse[Write|Edit] 산출물 저장위치 advisory 가드
#
# (2026-07-04 파일위생 mandate — artifact-storage.md 집행 1선)
# **advisory warn only — block 절대 금지.** 위반 감지 시 additionalContext로
# 경고만 주입하고 항상 allow. 강제는 일간 감사(artifact_hygiene_audit.R)와
# 사람 판단이 담당.
#
# 감지 3종 (artifact-storage.md):
#  (a) 프로젝트 루트 직하 신규 파일/디렉토리 생성
#      허용: §2 고정 13항목 + ARTIFACTS.md/CHANGELOG.md/CLAUDE.md/INDEX.md + dot항목
#  (b) 02_Infrastructure 하위 '_' 접두 신규 파일 생성 (§3 — 인프라 코드전용)
#  (c) results/output 명명 산출물성 파일(.R/.py/.json/.csv/.parquet/.rds/.txt 등)을
#      4대 산출물 존(stage_artifacts/outputs/06_Registry/04_Research) 밖에 신규 생성 (§1)
#
# 출력: {"additionalContext":"..."} (advisory) 또는 {} (무경고)
# 등록: policies/router_dispatch.json (Write/Edit, soft_fail true)
#==============================================================================
trap 'echo "{}"; exit 0' ERR
export PYTHONUTF8=1

# 공용 python 해석 (bare python3 = Windows Store 스텁 회피) — resolve-only 재사용
QVEST_PARSE_RESOLVE_ONLY=1; source "$(dirname "${BASH_SOURCE[0]:-$0}")/_shared_parse.sh"; unset QVEST_PARSE_RESOLVE_ONLY

INPUT=$(cat)

# 프로젝트 루트 해석 (axiom_context_inject.sh 패턴 — native 경로 우선, 백슬래시 정규화)
DIR="${CLAUDE_PROJECT_DIR:-${QM_ROOT:-}}"
DIR="${DIR//\\//}"
if [ -z "$DIR" ] || [ ! -d "$DIR" ]; then
  DIR=$(ls -d /c/Users/99922/OneDrive/Quant_Module_Moltbot /mnt/c/Users/99922/OneDrive/Quant_Module_Moltbot 2>/dev/null | head -1 || echo "$PWD")
fi

printf '%s' "$INPUT" | QVG_ROOT="$DIR" "$QVEST_PY_BIN" -c "
import json, os, re, sys
sys.stdout.reconfigure(encoding=\"utf-8\", errors=\"replace\")

def allow():
    print(\"{}\"); sys.exit(0)

try:
    d = json.loads(sys.stdin.buffer.read().decode(\"utf-8\", \"replace\"))
except Exception:
    allow()
if d.get(\"tool_name\", \"\") not in (\"Write\", \"Edit\"):
    allow()
ti = d.get(\"tool_input\") or {}
fp = (ti.get(\"file_path\") or \"\").replace(\"\\\\\", \"/\")
if not fp:
    allow()

def norm(p):
    m = re.match(r\"^/([a-zA-Z])/(.+)$\", p)          # MSYS /c/... -> C:/...
    if m:
        p = m.group(1).upper() + \":/\" + m.group(2)
    if re.match(r\"^[a-zA-Z]:\", p):                   # 드라이브 문자 대문자화
        p = p[0].upper() + p[1:]
    return p.rstrip(\"/\")

root = norm((os.environ.get(\"QVG_ROOT\") or \"\").replace(\"\\\\\", \"/\"))
fpn  = norm(fp)
if not root or not fpn.lower().startswith(root.lower() + \"/\"):
    allow()                                            # 프로젝트 밖 (scratchpad 등) — 무관
rel   = fpn[len(root) + 1:]
parts = rel.split(\"/\")
base  = parts[-1]
new_file = not os.path.exists(fpn)

ALLOW_ROOT = {
    \"00_Lawbook\", \"01_Literature\", \"02_Infrastructure\", \"03_Universe\",
    \"04_Research\", \"05_Production\", \"06_Registry\", \"08_Tests\",
    \"outputs\", \"qepm\", \"stage_artifacts\",
    \"ARTIFACTS.md\", \"CHANGELOG.md\", \"CLAUDE.md\", \"INDEX.md\"}
ZONES4 = (\"stage_artifacts/\", \"outputs/\", \"06_Registry/\", \"07_Registry/\", \"04_Research/\")
UNDERSCORE_OK = {\"_shared_parse.sh\", \"_shared_prefix.md\"}

warns = []
top = parts[0]

# (a) 루트 직하 무허가 항목 (신규 루트 파일 + 무허가 루트 디렉토리 경유 쓰기)
if not top.startswith(\".\") and top not in ALLOW_ROOT:
    warns.append(\"(a) 루트 직하 무허가 항목 [\" + top + \"] — 루트는 13항목+INDEX/ARTIFACTS로 고정(artifact-storage.md par.2). 신규 루트 항목 생성 금지 — 저장 4원칙 중 하나로 분류하세요.\")

# (b) 02_Infrastructure 하위 '_' 접두 신규 파일 (par.3 — 인프라 코드전용)
if (top == \"02_Infrastructure\" and new_file and base.startswith(\"_\")
        and base not in UNDERSCORE_OK and not base.startswith(\"__\")
        and \"__pycache__\" not in rel and \"/_archive\" not in rel):
    warns.append(\"(b) 02_Infrastructure에 underscore 접두 1회용 파일 [\" + rel + \"] 생성 — 인프라 존은 재사용 코드 전용(artifact-storage.md par.3). 실험 소속이면 stage_artifacts/<mode>/<run_id>/, 스크래치면 .cache/scratch/ 사용.\")

# (c) 산출물성 명명(results/output) 파일을 4대 존 밖에 신규 생성 (par.1)
if new_file and not rel.startswith(ZONES4) and top not in (\"qepm\",) and not top.startswith(\".\"):
    stem = re.sub(r\"\\.[A-Za-z0-9]+$\", \"\", base)
    ext_ok = re.search(r\"\\.(json|csv|parquet|rds|rdata|txt|log|md|r|py)$\", base, re.I)
    tok_ok = re.search(r\"(^|[._-])(results?|outputs?)($|[._-])\", stem, re.I)
    if ext_ok and tok_ok:
        warns.append(\"(c) 산출물성 파일 [\" + rel + \"] 이 4대 산출물 존 밖 — 실험 런=stage_artifacts/<mode>/<run_id>/ · canonical 데이터=outputs/<pipeline>/ · 상태/큐=06_Registry/ · 사람용 보고서=04_Research/<topic>/ 중 하나로 저장하세요(artifact-storage.md par.1).\")

if not warns:
    allow()
msg = (\"[artifact-placement advisory — 차단 아님] 저장위치 규칙 위반 의심 \"
       + str(len(warns)) + \"건:\\n- \" + \"\\n- \".join(warns)
       + \"\\n규칙 SOT: 02_Infrastructure/docs/rules/artifact-storage.md (par.1 저장 4원칙 / par.2 루트 고정 / par.3 인프라 코드전용). \"
       + \"의도된 예외라면 그대로 진행하되, 신규 루트 항목은 도훈 confirm + 문서 개정이 선행되어야 합니다.\")
print(json.dumps({\"additionalContext\": msg}, ensure_ascii=False))
" 2>/dev/null || echo "{}"
exit 0
