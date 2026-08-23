#!/bin/bash
#==============================================================================
# alerts_digest_build.sh — 경보 마커 → .cache/alerts_digest.md 1파일 (v9, 2026-08-23)
#   생산자(scheduler_alerts · cleaner_pending · auto_commit_quarantine · cache_freshness ·
#   scheduler_task_health · stranded_repairs)는 각자 기록만 하고 읽는 쪽이 흩어져 있었다.
#   v9 는 부팅에서 전수 점검을 걷어내는 대신 **읽는 쪽을 1파일로 접는다**.
#   ★수리하지 않는다. 텔레그램도 보내지 않는다(WARN 수리는 도훈 지시 시 태스크 분리).
#   첫 줄 = <!-- open=N built=YYYY-MM-DDTHH:MM -->  (boot_lean.sh 는 이 헤더만 읽는다)
#==============================================================================
source "$(dirname "${BASH_SOURCE[0]:-$0}")/resolve_project.sh"
cd "$PROJECT" || exit 0
export CLAUDE_PROJECT_DIR="$(cygpath -m "$PROJECT" 2>/dev/null || echo "$PROJECT")"
export PYTHONUTF8=1
PY="$PROJECT/.venv_qvest_ml/Scripts/python.exe"
OUT="$PROJECT/.cache/alerts_digest.md"; BODY="$OUT.body.$$"; TMP="$OUT.tmp.$$"
mkdir -p "$PROJECT/.cache" 2>/dev/null || true
{
  echo "## scheduler — 무인 러너 경보 마커 (.cache/scheduler_alerts/*.alert)"
  SAS="$PROJECT/02_Infrastructure/ops/scheduler_alert_status.sh"
  if [ -f "$SAS" ]; then   # detail 모드(인자 없음)의 들여쓴 상세행만 항목으로 승격
    bash "$SAS" 2>/dev/null | sed -n 's/^  \(.*\)$/- \1/p'
  else
    ls "$PROJECT"/.cache/scheduler_alerts/*.alert 2>/dev/null | sed 's#.*/#- #'
  fi
  echo
  QVD_ROOT="$CLAUDE_PROJECT_DIR" "$PY" - <<'PYEOF' 2>/dev/null || echo "## (JSON 원장 섹션 생략 — venv python 부재)"
import json,os
P=os.environ.get("QVD_ROOT","."); o=[]
def J(p):
    try: return json.load(open(os.path.join(P,p),encoding="utf-8-sig"))
    except Exception: return None
def sec(t,it): o.append("## "+t); o.extend(it if it else ["(없음)"]); o.append("")
c=J(".cache/cleaner_pending.json") or {}; it=[]
if str(c.get("status"))=="awaiting_distill": it.append("- cleaner | 주간 증류 대기(awaiting_distill) — /cleaner")
if str(c.get("distill_status"))=="in_progress": it.append("- cleaner | 증류 claim in_progress (owner=%s · since %s)"%(c.get("distill_owner"),c.get("distill_claimed_at")))
sec("cleaner — 주간 증류 (.cache/cleaner_pending.json)",it)
g=J(".cache/auto_commit_quarantine.json"); it=[]
if g:
    for e in (g.get("quarantined") or g.get("dirs") or g.get("entries") or [])[:5]:
        if isinstance(e,dict): it.append("- git | auto-commit 격리 %s (%s건)"%(e.get("dir"),e.get("n_new")))
    if not it: it.append("- git | auto-commit 격리 원장 존재 (ts=%s) — 직접 확인"%g.get("ts"))
sec("git — auto-commit 격리 (.cache/auto_commit_quarantine.json)",it)
f=J("qepm/observability/cache_freshness_latest.json") or {}
it=["- data | CRITICAL %s (lag %s일)"%(r.get("path"),r.get("lag_used")) for r in (f.get("results") or []) if r.get("severity")=="CRITICAL"]
a=J(".cache/freshness_alert_state.json") or {}
if a.get("reason"): it.append("- data | freshness 경보 발신 %s (reason=%s)"%(a.get("last_sent_at"),a.get("reason")))
sec("data — 캐시 신선도 (cache_freshness_latest.json · freshness_alert_state.json)",it)
h=(J("06_Registry/scheduler_task_health.json") or {}).get("verdict") or {}
sec("scheduler health — 등록 작업 rc (06_Registry/scheduler_task_health.json)",
    ["- sched | %s: %s"%(k,x) for k in ("failed_new","failed_known","stale") for x in (h.get(k) or [])])
s=J("06_Registry/stranded_repairs.json") or {}; it=[]
for w in (s.get("worktrees") or []):
    n=w.get("lost"); n=len(n) if isinstance(n,list) else (n or 0)
    if n: it.append("- worktree | %s: main 미도달 %s건"%(w.get("worktree") or w.get("branch"),n))
it=it[:6]; co=s.get("collisions") or []
if co: it.append("- worktree | 동일 경로 충돌 %d건 (collisions)"%len(co))
sec("worktrees — 좌초 수리 (06_Registry/stranded_repairs.json)",it)
print("\n".join(o))
PYEOF
} > "$BODY" 2>/dev/null
N=$(grep -c '^- ' "$BODY" 2>/dev/null || echo 0)
{
  printf '<!-- open=%s built=%s -->\n' "$N" "$(date '+%Y-%m-%dT%H:%M')"
  echo "# Qvest 경보 digest (v9 lean — 읽는 쪽 1파일)"
  echo
  echo "> 생성 = ops/alerts_digest_build.sh (morning_run 완주 후 · boot_lean 24h 초과 시). **수리는 도훈 지시 시 태스크 분리** — 이 파일은 기록만 한다."
  echo
  cat "$BODY"
} > "$TMP" 2>/dev/null
mv -f "$TMP" "$OUT" 2>/dev/null || true
rm -f "$BODY" 2>/dev/null || true
exit 0
