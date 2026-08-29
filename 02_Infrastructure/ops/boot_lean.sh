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
# alerts digest — 부재/6h 초과 시 1회만 갱신 (foreground, fail-soft, 수리 아님)
#   ★24h → 6h (2026-08-24 v9.2 S1e): 아침 09~10시 무인 사고가 저녁 부팅에 안 보이는
#     창을 닫는다. 2026-08-23 에 무인 3단계가 동시에 죽었는데 그날 어떤 부팅도 그 사실을
#     표면화하지 못한 이유가 이 24h 창이었다.
DG="$PROJECT/.cache/alerts_digest.md"
DG_AGE=$(( ( $(date +%s) - $(stat -c %Y "$DG" 2>/dev/null || echo 0) ) / 3600 ))
if [ ! -f "$DG" ] || [ "$DG_AGE" -ge 6 ]; then
  bash "$PROJECT/02_Infrastructure/ops/alerts_digest_build.sh" >/dev/null 2>&1 || true
fi
PROJECT="$CLAUDE_PROJECT_DIR" PY="$CLAUDE_PROJECT_DIR/.venv_qvest_ml/Scripts/python.exe" "$PY" - <<'PYEOF' 2>/dev/null || printf 'Data: ?\nQueue: ?\nLast: ?\nBook: ?\nAlerts/Budget: ? (status 산출 실패 — venv python 확인)\n'
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
#   ★v10 (2026-08-29): 강화 원장 active(L1 n/20 · L2 무한) + data-pipeline open 병기 (fail-soft ?)
_r=S(lambda: subprocess.run([PY,R("02_Infrastructure","ops","research_pool_predicates.py"),"alpha-pending",R("stage_artifacts","paper_recharge")],capture_output=True,text=True,timeout=90).stdout.strip())
q=_r if (_r or "").isdigit() else "UNREPORTED"; fq=[]
for e in ((J("06_Registry/alpha_frontier_queue.json") or {}).get("entries") or []):
    st=str(e.get("status") or ""); ow=str(e.get("owner") or "")
    if st=="parked" or not (st=="open" or ("open" in st and "dohoon_decision" not in ow)): continue
    fq.append("%s · %s"%(e.get("id") or "?",str(e.get("title") or "")[:50]))
    if len(fq)>=2: break
def RF(l):
    d=J("06_Registry/reinforce_ledger_l%d.json"%l)
    if not d: return "?"
    return str(sum(1 for e in (d.get("entries") or []) if (e.get("status") if isinstance(e,dict) else None)=="active"))
dp=S(lambda: str(sum(1 for e in ((J("06_Registry/data_pipeline_queue.json") or {}).get("entries") or []) if (e.get("status") if isinstance(e,dict) else None)=="open")),"?")
o.append("Queue: alpha-pending %s · %s | 강화 L1 %s·L2 %s active · data-pipe %s"%(q," / ".join(fq) if fq else "frontier open 0",RF(1),RF(2),dp))
# ③ Last — 최신 alpha-search L-code (다음 라운드의 출발점)
g=sorted(glob.glob(R("stage_artifacts","l_code","alpha_search","l_code_*.json")),key=os.path.getmtime)
c=(J(g[-1]) or {}) if g else {}
npb=c.get("next_probe"); npb=npb[0] if isinstance(npb,list) and npb else npb
o.append("Last: %s %s · next %s"%(c.get("l_code") or "?",c.get("grade") or "?",str(npb or "?")[:80]))
# ④ Book — ★v10 정본 = 06_Registry/book/book_registry.json (governor/book_state 폐지)
b=J("06_Registry/book/book_registry.json") or {}
ents=[e for e in (b.get("entries") or []) if isinstance(e,dict)]
act=[e for e in ents if e.get("status")=="active"]
lt=act[-1] if act else None
o.append("Book: %d entries (%d active)%s — book_registry.json 정본(writer 경유·도훈 confirm)"%(
    len(ents),len(act),
    (" · 최신 %s %s %s (트래킹 %s)"%(lt.get("book_id"),str(lt.get("strategy_id"))[:34],lt.get("grade"),
     str((lt.get("tracking") or {}).get("last_nav_date") or "미실행"))) if lt else ""))
# ⑤ Alerts/Budget — digest 헤더 + v9 예산 4종
_hd=S(lambda: open(R(".cache","alerts_digest.md"),encoding="utf-8").readline(),"") or ""
_m=S(lambda: re.search(r"open=(\d+).*?built=(\S+?)\s*-->",_hd))
op=_m.group(1) if _m else "?"; bt=HH(S(lambda: (dt.datetime.now()-dt.datetime.fromisoformat(_m.group(2))).total_seconds()/3600.0)) if _m else "?"
# ★오늘자 무인 러너 경보 — 생산자(alerts_digest_build.sh) 헤더에서 **읽기만** 한다.
#   R 실행 0 · 수리 0 규약 불변. 2026-08-23 에 무인 3단계가 동시 사망했는데 그날 어떤
#   부팅도 그것을 말하지 않았다 — 5번째 줄의 내용만 바꿔 그 침묵을 닫는다.
_t=S(lambda: re.search(r"today=(\d+)\s+comps=(\S*)",_hd))
_tn=_t.group(1) if _t else "?"; _tc=(_t.group(2) if _t else "") or "none"
today_txt=("★오늘 %s [%s]"%(_tn,_tc)) if _tn not in ("0","?") else ("오늘 %s"%_tn)
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
o.append("Alerts/Budget: open %s · %s · built %s | CLAUDE.md %s · rules %s · hooks %s · ctx %s"%(op,today_txt,bt,BG(S(lambda: os.path.getsize(R("CLAUDE.md"))),8192),BG(rb,25600),BG(hk,12),BG(S(CTX),50000)))
print("\n".join(o))
PYEOF
mkdir -p "$PROJECT/.cache" 2>/dev/null || true
printf '{"ts":"%s","ts_epoch":%s,"boot_fails":0,"mode":"lean"}\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$(date +%s)" > "$PROJECT/.cache/boot_stamp.json" 2>/dev/null || true
exit 0
