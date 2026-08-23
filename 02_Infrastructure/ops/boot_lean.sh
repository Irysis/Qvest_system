#!/bin/bash
#==============================================================================
# boot_lean.sh — Qvest v9 "Lean Loop" 부팅 (2026-08-23)
#   상태 5줄만 출력. 검사 0 · 수리 0 · R 실행 0 · 테스트 0 · 백그라운드 0 · 항상 exit 0.
#   ★필드가 안 읽히면 '?' 로 두고 계속한다(fail-soft) — 부팅이 세션을 막지 않는다.
#   전수 점검(구 bootstrap.sh 전문)은 주간/수동 ops/health_full.sh 로 분리됐다.
#==============================================================================
source "$(dirname "${BASH_SOURCE[0]:-$0}")/resolve_project.sh"
cd "$PROJECT" || exit 0
export CLAUDE_PROJECT_DIR="$(cygpath -m "$PROJECT" 2>/dev/null || echo "$PROJECT")"
export QM_ROOT="${QM_ROOT:-$CLAUDE_PROJECT_DIR}"
export PYTHONUTF8=1
PY="$PROJECT/.venv_qvest_ml/Scripts/python.exe"
# alerts digest — 부재/24h 초과 시 1회만 갱신 (foreground, fail-soft, 수리 아님)
DG="$PROJECT/.cache/alerts_digest.md"
DG_AGE=$(( ( $(date +%s) - $(stat -c %Y "$DG" 2>/dev/null || echo 0) ) / 3600 ))
if [ ! -f "$DG" ] || [ "$DG_AGE" -ge 24 ]; then
  bash "$PROJECT/02_Infrastructure/ops/alerts_digest_build.sh" >/dev/null 2>&1 || true
fi
PROJECT="$CLAUDE_PROJECT_DIR" PY="$PY" "$PY" - <<'PYEOF' 2>/dev/null || printf 'Data: ?\nQueue: ?\nLast: ?\nBook: ?\nAlerts/Budget: ? (status 산출 실패 — venv python 확인)\n'
import json,os,re,glob,time,subprocess,datetime as dt
P=os.environ["PROJECT"]; PY=os.environ["PY"]; o=[]
R=lambda *a: os.path.join(P,*a)
def S(f,d=None):
    try: return f()
    except Exception: return d
J=lambda p,d=None: S(lambda: json.load(open(p if os.path.isabs(p) else R(p),encoding="utf-8-sig")),d)
AG=lambda p: S(lambda: (time.time()-os.path.getmtime(R(p)))/3600.0)
HH=lambda h: "?" if h is None else ("%.0fh"%h if h<72 else "%.0fd"%(h/24))
# ① Data — 키 캐시 severity + 감사 자신의 나이 + 원천 parquet mtime + 유니버스 열(schema만)
d=J("qepm/observability/cache_freshness_latest.json") or {}
sv={r.get("path"):r.get("severity") for r in (d.get("results") or [])}; bad=[]
for lab,cs in (("rawdata",(".cache/rawdata.parquet",".cache/RAWDATA.parquet")),("bench",(".cache/benchmark.parquet",)),("regime_daily_v2",(".cache/regime_daily_v2.parquet",)),("unified_regime",(".cache/unified_regime_signal.parquet",))):
    v=[sv[c] for c in cs if c in sv]; w=[x for x in v if x in ("WARN","CRITICAL")]
    if w or not v: bad.append(lab+":"+(w[0] if w else "부재"))
_h=S(lambda: (dt.datetime.now()-dt.datetime.fromisoformat(str(d.get("ran_at"))[:19])).total_seconds()/3600.0)
ra="?" if _h is None else HH(_h)+(" ★audit stale" if _h>36 else "")
_nm=S(lambda: set(__import__("pyarrow.parquet",fromlist=["x"]).read_schema(R(".cache","rawdata.parquet")).names))
mem="K200/KQ150 "+("?" if _nm is None else ("OK" if {"K200","KQ150"}<=_nm else "부재"))
o.append("Data: 키캐시 %d/4%s · audit %s · rawdata %s · bench %s · %s%s"%(4-len(bad)," ["+", ".join(bad)+"]" if bad else " OK",ra,HH(AG(".cache/rawdata.parquet")),HH(AG(".cache/benchmark.parquet")),mem,"  → bash 02_Infrastructure/data/daily_refresh.sh" if bad else ""))
# ② Queue — 미소비 논문 수(비숫자면 UNREPORTED, 0 으로 접지 않음) + frontier open 상위 2
_r=S(lambda: subprocess.run([PY,R("02_Infrastructure","ops","research_pool_predicates.py"),"alpha-pending",R("stage_artifacts","paper_recharge")],capture_output=True,text=True,timeout=90).stdout.strip())
q=_r if (_r or "").isdigit() else "UNREPORTED"; fq=[]
for e in ((J("06_Registry/alpha_frontier_queue.json") or {}).get("entries") or []):
    st=str(e.get("status") or ""); ow=str(e.get("owner") or "")
    if st=="parked" or not (st=="open" or ("open" in st and "dohoon_decision" not in ow)): continue
    fq.append("%s · %s"%(e.get("id") or "?",str(e.get("title") or "")[:50]))
    if len(fq)>=2: break
o.append("Queue: alpha-pending %s · %s"%(q," / ".join(fq) if fq else "frontier open 0"))
# ③ Last — 최신 alpha-search L-code (다음 라운드의 출발점)
g=sorted(glob.glob(R("stage_artifacts","l_code","alpha_search","l_code_*.json")),key=os.path.getmtime)
c=(J(g[-1]) or {}) if g else {}
npb=c.get("next_probe"); npb=npb[0] if isinstance(npb,list) and npb else npb
o.append("Last: %s %s · next %s"%(c.get("l_code") or "?",c.get("grade") or "?",str(npb or "?")[:80]))
# ④ Book — 자본 층 현재 편입 (쓰기는 도훈 수동)
b=J("qepm/mailbox/governor/book_state.json") or {}
ai=(b.get("admitted_ids") or ["?"])[0]; wv=(b.get("book_weights") or {}).get(ai)
o.append("Book: %s %s (%s~) — book_state.json 정본(도훈만 씀)"%(ai,("%.0f%%"%(float(wv)*100)) if wv is not None else "?%",str(b.get("updated_at") or "?")[:10]))
# ⑤ Alerts/Budget — digest 헤더 + v9 예산 4종
_m=S(lambda: re.search(r"open=(\d+)\s+built=(\S+)",open(R(".cache","alerts_digest.md"),encoding="utf-8").readline()))
op=_m.group(1) if _m else "?"; bt=HH(S(lambda: (dt.datetime.now()-dt.datetime.fromisoformat(_m.group(2))).total_seconds()/3600.0)) if _m else "?"
BG=lambda v,l: "%s/%s %s"%("?" if v is None else v,l,"?" if v is None else ("✓" if v<=l else "✗"))
def hasp(f):
    mm=re.match(r"---\s*\n(.*?)\n---",open(f,encoding="utf-8",errors="replace").read(2000),re.S)
    return bool(mm and re.search(r"^paths\s*:",mm.group(1),re.M))
rb=sum(os.path.getsize(f) for f in glob.glob(R(".claude","rules","*.md")) if not S(lambda: hasp(f),False))
hk=S(lambda: len(set(re.findall(r"hooks/([A-Za-z0-9_.-]+\.sh)",open(R(".claude","settings.json"),encoding="utf-8").read()))))
def CTX():
    p=max(glob.glob(os.path.join(os.path.expanduser("~"),".claude","projects",re.sub(r"[^A-Za-z0-9]","-",P),"*.jsonl")),key=os.path.getmtime)
    for ln in open(p,encoding="utf-8",errors="replace"):
        j=json.loads(ln) if ln.strip()[:1]=="{" else {}
        if j.get("type")=="assistant":
            u=(j.get("message") or {}).get("usage") or {}
            return sum(int(u.get(k) or 0) for k in ("input_tokens","cache_creation_input_tokens","cache_read_input_tokens"))
o.append("Alerts/Budget: open %s · built %s | CLAUDE.md %s · rules %s · hooks %s · ctx %s"%(op,bt,BG(S(lambda: os.path.getsize(R("CLAUDE.md"))),8192),BG(rb,25600),BG(hk,12),BG(S(CTX),50000)))
print("\n".join(o))
PYEOF
mkdir -p "$PROJECT/.cache" 2>/dev/null || true
printf '{"ts":"%s","ts_epoch":%s,"boot_fails":0,"mode":"lean"}\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$(date +%s)" > "$PROJECT/.cache/boot_stamp.json" 2>/dev/null || true
exit 0
