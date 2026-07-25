#!/usr/bin/env bash
# handbook_facts_audit.sh — 시스템 핸드북 수치 자동 실측
#
# 목적: 핸드북(계층별 구조·성숙도 문서)의 모든 '수치·상태'를 매일 실측해 JSON으로 고정한다.
#   문제: 핸드북은 스냅샷이라 손으로 갱신해야 하고, 갱신을 잊으면 낡은 채 신뢰된다.
#         이 시스템은 스테일 문서로 사고가 난 이력이 있다(측정 vintage·멤버십 종점 등).
#   원칙: 서술(왜 그런 구조인가)은 수동, 수치(몇 개·언제까지·살았나)는 자동.
#         → 핸드북 갱신 시 재스캔 불필요. drift도 diff로 즉시 보임.
#
# 산출: 06_Registry/handbook_facts.json
#   생성 시각 + 계층별 실측치. 핸드북 재생성/검증의 단일 입력.
#
# 읽기 전용. 실패해도 exit 0 (무인 파이프라인 무중단).
#
# 사용:
#   bash 02_Infrastructure/ops/handbook_facts_audit.sh
#   bash 02_Infrastructure/ops/handbook_facts_audit.sh --diff    # 직전 산출과 변경분만 표시
#
# 2026-07-25 신규 (도훈 질문 "이 문서도 자동 업데이트 되나" → next_probe ③ 착수)

set -uo pipefail
PROJECT="${QM_ROOT:-${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}}"
cd "$PROJECT" 2>/dev/null || { echo "[facts] PROJECT 해석 실패" >&2; exit 0; }

OUT="$PROJECT/06_Registry/handbook_facts.json"
PREV="$PROJECT/.cache/handbook_facts_prev.json"
DO_DIFF=0
for a in "$@"; do [ "$a" = "--diff" ] && DO_DIFF=1; done
[ -f "$OUT" ] && cp "$OUT" "$PREV" 2>/dev/null

PY="${QVEST_PY:-}"
[ -z "$PY" ] && [ -x "$PROJECT/.venv_qvest_ml/Scripts/python.exe" ] && PY="$PROJECT/.venv_qvest_ml/Scripts/python.exe"

n() { printf '%s' "${1:-0}" | tr -d ' \n\r'; }
# JSON 배열/객체 엔트리 개수 (파이썬 없으면 0)
jcount() { # $1=file $2=key(옵션, 없으면 최상위 배열)
  [ -x "$PY" ] || { echo 0; return; }
  "$PY" -c "
import json,sys,io
try:
    d=json.load(io.open(r'''$1''',encoding='utf-8'))
    k='''${2:-}'''
    o=d.get(k) if k else d
    if o is None: o=d
    print(len(o) if hasattr(o,'__len__') else 0)
except Exception: print(0)
" 2>/dev/null || echo 0
}

# ── L1 데이터
RAW="$PROJECT/.cache/RAWDATA.parquet"
DATA_RAW_MB=0; [ -f "$RAW" ] && DATA_RAW_MB=$(( $(stat -c %s "$RAW" 2>/dev/null || echo 0) / 1048576 ))
FDB_M=$(ls "$PROJECT"/.cache/factor_db/* 2>/dev/null | wc -l); FDB_M=$(n "$FDB_M")
FDB_D=$(ls "$PROJECT"/.cache/factor_db_daily/* 2>/dev/null | wc -l); FDB_D=$(n "$FDB_D")
FDB_GB=$(du -sm "$PROJECT/.cache/factor_db" "$PROJECT/.cache/factor_db_daily" 2>/dev/null | awk '{s+=$1} END{printf "%.1f", s/1024}')
[ -z "$FDB_GB" ] && FDB_GB=0

# 팩터/방법론 등재 수
FACTORS=0; METHODS=0
if [ -x "$PY" ]; then
  FACTORS=$("$PY" -c "
import json,io
try:
    d=json.load(io.open(r'''$PROJECT/02_Infrastructure/factor_db/factor_registry.json''',encoding='utf-8'))
    f=d.get('factors',d)
    print(len(f) if hasattr(f,'__len__') else 0)
except Exception: print(0)" 2>/dev/null || echo 0)
  METHODS=$("$PY" -c "
import json,io
try:
    d=json.load(io.open(r'''$PROJECT/02_Infrastructure/factor_db/method_registry.json''',encoding='utf-8'))
    m=d.get('methods',d)
    print(len(m) if hasattr(m,'__len__') else 0)
except Exception: print(0)" 2>/dev/null || echo 0)
fi

# ── L3 훅: settings.json 스크립트 + 라우터 팬아웃
HOOK_DIRECT=$(grep -oE '[A-Za-z0-9_-]+\.(sh|py)' "$PROJECT/.claude/settings.json" 2>/dev/null | sort -u | wc -l); HOOK_DIRECT=$(n "$HOOK_DIRECT")
HOOK_FANOUT=$(grep -oE '"script"[[:space:]]*:[[:space:]]*"[^"]+"' "$PROJECT/02_Infrastructure/hooks/policies/router_dispatch.json" 2>/dev/null | sort -u | wc -l); HOOK_FANOUT=$(n "$HOOK_FANOUT")
HOOK_ONDISK=$(ls "$PROJECT"/02_Infrastructure/hooks/*.sh 2>/dev/null | wc -l); HOOK_ONDISK=$(n "$HOOK_ONDISK")
HOOK_TOTAL=$(( HOOK_DIRECT + HOOK_FANOUT ))
# 차단 가능 경로 = PreToolUse + Stop 중 '|| true' 없는 훅. PostToolUse는 도구가 이미 실행된 뒤라 구조상 차단 불가.
#   ⚠ grep -E 브래킷 안 '[^\n]' 은 "역슬래시·n 이 아닌 문자"로 해석돼 항상 빗나감(2026-07-25 오탐 0 실측) — 이름별 존재 확인으로 대체.
HOOK_BLOCKING=0
for _h in safety_guard telegram_direct_call_guard axiom_context_inject performance_realmeasure_gate research_continuity_guard qvest_hook_router; do
  grep -q "hooks/${_h}\." "$PROJECT/.claude/settings.json" 2>/dev/null && HOOK_BLOCKING=$((HOOK_BLOCKING + 1))
done

# ── L4/L5 절차·에이전트
SKILLS=$(ls -d "$PROJECT"/.claude/skills/*/ 2>/dev/null | wc -l); SKILLS=$(n "$SKILLS")
AGENTS=$(ls "$PROJECT"/.claude/agents/*.md 2>/dev/null | wc -l); AGENTS=$(n "$AGENTS")
COMMANDS=$(ls "$PROJECT"/.claude/commands/*.md 2>/dev/null | wc -l); COMMANDS=$(n "$COMMANDS")
SKILL_OFF=$(grep -oE '"[a-z-]+"[[:space:]]*:[[:space:]]*"off"' "$PROJECT/.claude/settings.json" 2>/dev/null | wc -l); SKILL_OFF=$(n "$SKILL_OFF")
SKILL_MANUAL=$(grep -oE '"[a-z-]+"[[:space:]]*:[[:space:]]*"user-invocable-only"' "$PROJECT/.claude/settings.json" 2>/dev/null | wc -l); SKILL_MANUAL=$(n "$SKILL_MANUAL")

# ── L2 계약·검증·테스트
CONTRACTS=$(ls "$PROJECT"/02_Infrastructure/contracts/*.R 2>/dev/null | wc -l); CONTRACTS=$(n "$CONTRACTS")
VALIDATION=$(ls "$PROJECT"/02_Infrastructure/validation/*.R "$PROJECT"/02_Infrastructure/validation/*.py 2>/dev/null | wc -l); VALIDATION=$(n "$VALIDATION")
TESTS=$(find "$PROJECT/08_Tests" -name "*.R" -o -name "*.py" -o -name "*.sh" 2>/dev/null | wc -l); TESTS=$(n "$TESTS")

# ── 지식 엔진
AX_ACTIVE=$(ls "$PROJECT"/qepm/memory/axioms/active/AX-*.json 2>/dev/null | wc -l); AX_ACTIVE=$(n "$AX_ACTIVE")
AX_CAND=$(ls "$PROJECT"/qepm/memory/axioms/candidates/*.json 2>/dev/null | wc -l); AX_CAND=$(n "$AX_CAND")
HYPO=$(jcount "$PROJECT/06_Registry/hypothesis_index.json" entries)
DIST=$(jcount "$PROJECT/06_Registry/distilled_knowledge.json" entries)
FRONTIER=$(jcount "$PROJECT/06_Registry/alpha_frontier_queue.json" entries)
PAPERS=$(jcount "$PROJECT/06_Registry/paper_registry.json")
STRATS=$(jcount "$PROJECT/06_Registry/strategy_registry.json")
LCODE=0
if [ -x "$PY" ]; then
  LCODE=$("$PY" -c "
import json,io
try:
    d=json.load(io.open(r'''$PROJECT/06_Registry/knowledge_index.json''',encoding='utf-8'))
    v=d.get('lcode_corpus',0)
    print(len(v) if hasattr(v,'__len__') else int(v))
except Exception: print(0)" 2>/dev/null || echo 0)
fi

# ── 운영 상태 (다른 감사기 산출 재사용 — 중복 측정 금지)
HYG_WARN="null"; [ -f "$PROJECT/06_Registry/hygiene_report.json" ] && \
  HYG_WARN=$(grep -oE '"n_warnings"[[:space:]]*:[[:space:]]*[0-9]+' "$PROJECT/06_Registry/hygiene_report.json" 2>/dev/null | grep -oE '[0-9]+$' | head -1)
[ -z "$HYG_WARN" ] && HYG_WARN="null"
STR_LOST="null"; STR_COLL="null"; STR_STALE="null"
if [ -f "$PROJECT/06_Registry/stranded_repairs.json" ]; then
  STR_LOST=$(grep -oE '"files_lost"[[:space:]]*:[[:space:]]*[0-9]+' "$PROJECT/06_Registry/stranded_repairs.json" | grep -oE '[0-9]+$' | head -1)
  STR_COLL=$(grep -oE '"collisions"[[:space:]]*:[[:space:]]*[0-9]+' "$PROJECT/06_Registry/stranded_repairs.json" | grep -oE '[0-9]+$' | head -1)
  STR_STALE=$(grep -oE '"stale_over_threshold"[[:space:]]*:[[:space:]]*[0-9]+' "$PROJECT/06_Registry/stranded_repairs.json" | grep -oE '[0-9]+$' | head -1)
fi
[ -z "$STR_LOST" ] && STR_LOST="null"; [ -z "$STR_COLL" ] && STR_COLL="null"; [ -z "$STR_STALE" ] && STR_STALE="null"

# ── 프로젝트 나이 (핸드백 Ch.00 — '3년' 오기 재발 방지: 항상 실측)
FIRST_CT=$(git -C "$PROJECT" log --reverse --format=%ct 2>/dev/null | head -1)
AGE_DAYS=0; [ -n "${FIRST_CT:-}" ] && AGE_DAYS=$(( ($(date +%s) - FIRST_CT) / 86400 ))
COMMITS=$(git -C "$PROJECT" rev-list --count HEAD 2>/dev/null || echo 0)
LIVE_TRACKS=$(ls -d "$PROJECT"/06_Registry/live_track/*/ 2>/dev/null | wc -l); LIVE_TRACKS=$(n "$LIVE_TRACKS")

mkdir -p "$(dirname "$OUT")"
cat > "$OUT" <<JSON
{
  "_doc": "시스템 핸드북 수치 자동 실측. 생성기 02_Infrastructure/ops/handbook_facts_audit.sh. 핸드북의 '서술'은 수동, '수치'는 본 파일이 단일 입력. 핸드북 갱신 시 재스캔 불필요 — 이 JSON과 대조만.",
  "generated_at": "$(date '+%Y-%m-%d %H:%M:%S')",
  "project": { "age_days": $AGE_DAYS, "commits": ${COMMITS:-0} },
  "layers": {
    "L1_data": {
      "rawdata_mb": $DATA_RAW_MB,
      "factordb_monthly_files": $FDB_M,
      "factordb_daily_files": $FDB_D,
      "factordb_total_gb": $FDB_GB,
      "factors_registered": ${FACTORS:-0},
      "methods_registered": ${METHODS:-0}
    },
    "L2_contract": { "contracts": $CONTRACTS, "validation_modules": $VALIDATION, "tests": $TESTS },
    "L3_hook": {
      "settings_scripts": $HOOK_DIRECT,
      "router_fanout": $HOOK_FANOUT,
      "distinct_total": $HOOK_TOTAL,
      "on_disk_sh": $HOOK_ONDISK,
      "blocking_paths": $HOOK_BLOCKING
    },
    "L4_procedure": { "skills": $SKILLS, "skills_off": $SKILL_OFF, "skills_manual_only": $SKILL_MANUAL, "commands": $COMMANDS },
    "L5_agent": { "agents": $AGENTS },
    "knowledge": {
      "axioms_active": $AX_ACTIVE, "axiom_candidates": $AX_CAND,
      "lcode_corpus": ${LCODE:-0}, "distilled": $DIST,
      "hypothesis_index": $HYPO, "frontier_queue": $FRONTIER,
      "papers": $PAPERS, "strategies": $STRATS
    },
    "ops": {
      "live_tracks": $LIVE_TRACKS,
      "hygiene_warnings": $HYG_WARN,
      "stranded_lost": $STR_LOST,
      "stranded_collisions": $STR_COLL,
      "stranded_stale_worktrees": $STR_STALE
    }
  }
}
JSON

echo "[$(date '+%F %T')] handbook facts — 훅 ${HOOK_TOTAL}(차단 ${HOOK_BLOCKING}) · 스킬 ${SKILLS} · 에이전트 ${AGENTS} · 팩터 ${FACTORS:-0} · 가설 ${HYPO} · L-code ${LCODE:-0} · 프론티어 ${FRONTIER} · 좌초 ${STR_LOST}"
echo "[facts] → $OUT"

# ── drift 표시: 직전 산출 대비 변경된 수치만
if [ "$DO_DIFF" -eq 1 ] && [ -f "$PREV" ] && [ -x "$PY" ]; then
  echo ""
  echo "[facts] 직전 대비 변경:"
  "$PY" - "$PREV" "$OUT" <<'PYEOF' 2>/dev/null || echo "  (비교 실패)"
import json,sys,io
def flat(o,p=""):
    r={}
    if isinstance(o,dict):
        for k,v in o.items():
            if k.startswith("_") or k=="generated_at": continue
            r.update(flat(v,f"{p}.{k}" if p else k))
    else: r[p]=o
    return r
a=flat(json.load(io.open(sys.argv[1],encoding='utf-8')))
b=flat(json.load(io.open(sys.argv[2],encoding='utf-8')))
ch=[(k,a.get(k),b[k]) for k in b if a.get(k)!=b[k]]
if not ch: print("  변경 없음")
for k,o,nv in sorted(ch): print(f"  {k}: {o} → {nv}")
PYEOF
fi

exit 0
