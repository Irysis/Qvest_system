#!/bin/bash
#==============================================================================
# boot_lean.sh — Qvest v10.4 부팅 (2026-08-23 신설 · 2026-09-05 v10 mode 정합)
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
# ★팩터 배출 격차 (2026-09-01) — emission_guard 는 매 빌드 돌고 있었는데 **소비자가 없어서**
#   registry 373 중 42종이 조용히 빠진 걸 아무도 못 봤다. 차단이 아니라 표면화다.
#   등재 N − IC 보유 N − 선언(expected_absent) N. 격차가 0 이면 조용하다.
def _fgap():
    try:
        reg=json.load(io.open(R(".cache","factor_db","factor_registry.json"),encoding="utf-8"))
        import pyarrow.parquet as _pq
        ic=set(_pq.read_table(R(".cache","factor_db","factor_ic_monthly.parquet"),columns=["Factor_Name"])["Factor_Name"].to_pylist())
        ea=json.load(io.open(R("02_Infrastructure","factor_db","emission_expected_absent.json"),encoding="utf-8"))
        dec={e.get("factor") for e in (ea.get("expected_absent") or [])}
        # ★격차에서 빼야 하는 두 부류 (2026-09-01):
        #   deprecated = 승계돼서 **안 나오는 게 맞는** 팩터(C14→M26 · C17→M28)
        #   time_series = 시장수준이라 횡단면 IC 가 구조적으로 불가(RE*/CR03/M31 — 빌더 Coverage 규칙과 정합)
        dep={f for f,e in reg.items() if str(((e or {}).get("lifecycle") or {}).get("status"))=="deprecated"}
        axf=S(lambda: json.load(io.open(R("06_Registry","factor_panel_axis.json"),encoding="utf-8"))["factors"]) or {}
        ts={f for f,v in axf.items() if v.get("panel_axis")=="time_series"}
        miss=[f for f in reg if f not in ic and f not in dec and f not in dep and f not in ts]
        ax=S(lambda: json.load(io.open(R("06_Registry","factor_panel_axis.json"),encoding="utf-8"))["tally"])
        axs=(" · 축 %s"%("/".join("%s %d"%(k[:2],v) for k,v in sorted(ax.items())))) if ax else ""
        return "팩터 %d/%d%s%s"%(len([f for f in ic if f in reg]),len(reg),axs," · ★배출격차 %d"%len(miss) if miss else "")
    except Exception:
        return "팩터 ?"
import io
o.append("Data: 키캐시 %d/4%s · audit %s · rawdata %s · bench %s · %s · %s%s"%(4-len(bad)," ["+", ".join(bad)+"]" if bad else " OK",ra,HH(AG(".cache/rawdata.parquet")),HH(AG(".cache/benchmark.parquet")),mem,_fgap(),"  → bash 02_Infrastructure/data/daily_refresh.sh" if bad else ""))
# ② Queue — 미소비 논문 수(비숫자면 UNREPORTED, 0 으로 접지 않음) + frontier open 상위 2
#   ★v10 (2026-08-29): 강화 원장 active(L1 n/25 · L2 무한) + data-pipeline open 병기 (fail-soft ?)
_r=S(lambda: subprocess.run([PY,R("02_Infrastructure","ops","research_pool_predicates.py"),"alpha-pending",R("stage_artifacts","paper_recharge")],capture_output=True,text=True,timeout=90).stdout.strip())
q=_r if (_r or "").isdigit() else "UNREPORTED"; fq=[]
for e in ((J("06_Registry/alpha_frontier_queue.json") or {}).get("entries") or []):
    st=str(e.get("status") or ""); ow=str(e.get("owner") or "")
    if st=="parked" or not (st=="open" or ("open" in st and "dohoon_decision" not in ow)): continue
    fq.append("%s · %s"%(e.get("id") or "?",str(e.get("title") or "")[:50]))
    if len(fq)>=2: break
# ★강화 active 해상도 (2026-09-05) — 개수만으로는 lean-loop 입력 규칙("L1 에 active 가
#   있으면 그 강화가 우선")을 세션이 이행할 수 없다. 무엇을 이어받는지가 안 보였다.
#   n/max · base_id 꼬리 · 승격 depth 를 붙인다. active 0 이면 "0" 그대로(소음 없음).
def RF(l):
    d=J("06_Registry/reinforce_ledger_l%d.json"%l)
    if not d: return "?"
    act=[e for e in (d.get("entries") or []) if isinstance(e,dict) and e.get("status")=="active"]
    if not act: return "0"
    e=act[-1]; mx=d.get("max_attempts")
    dep=S(lambda: int((e.get("parent") or {}).get("depth")))
    return "%d(%s %s/%s%s)"%(len(act),str(e.get("base_id") or "?")[-24:],
        e.get("attempts_used") if e.get("attempts_used") is not None else "?",
        mx if mx else "∞"," ·승격d%d"%dep if dep else "")
dp=S(lambda: str(sum(1 for e in ((J("06_Registry/data_pipeline_queue.json") or {}).get("entries") or []) if (e.get("status") if isinstance(e,dict) else None)=="open")),"?")
# ★무인 러너 핸드오프 노출 (2026-08-30) — cleaner 선례: 기계가 남긴 대기 상태를 부팅이 보여야
#   세션이 소비한다. 텔레그램만 쓰면 놓쳤을 때 어디서도 안 보인다. 0 이면 표기하지 않는다(소음 방지).
def PEND():
    z=[]
    r=J("06_Registry/replication_request.json")
    if r and (r.get("status")=="pending"):
        z.append("★충실구현 대기 1(%s)"%str(((r.get("paper") or {}).get("paper_title") or "?"))[:28])
    aq=J("06_Registry/grade_a_queue.json")
    na=sum(1 for e in ((aq or {}).get("entries") or []) if (e.get("status") if isinstance(e,dict) else None)=="awaiting_judge")
    if na: z.append("★A등급 대기 %d(Judge/BOOK confirm)"%na)
    cc=J("06_Registry/combination_candidates.json")
    nc=len((cc or {}).get("candidates") or [])
    if nc: z.append("결합후보 %d"%nc)
    # ★결합 검토 '의무' (2026-09-05) — 후보 수(candidates)와 다른 양이다. lean-loop 는
    #   "논문 3편 소비마다 Q-Lead 가 결합 기회를 검토·기록"(착수 무관 의무)이라 못박는데,
    #   부팅은 후보 개수만 보여줘 의무가 발동해도 아무 데서도 안 보였다. 원장이 정본.
    _cr=(J("06_Registry/reinforce_ledger_l1.json") or {}).get("combination_review") or {}
    _ps=S(lambda: int(_cr.get("papers_since_last_review")))
    if _ps is not None and _ps>=3:
        z.append("★결합검토 의무 %d/3(최종 %s)"%(_ps,str(_cr.get("last_review_date") or "?")))
    # 공리 리뷰(건식) 미소비 보고서 — 기계가 산출하고 세션이 판단한다(cleaner 선례).
    #   반증 축적분은 자동 deprecate 되지 않는다(metric_type=estimated 는 human-review 강제).
    rv=sorted(glob.glob(R("qepm","memory","axioms","review_log","dryrun","review_dryrun_*.json")))
    if rv:
        age=(time.time()-os.path.getmtime(rv[-1]))/86400.0
        if age<=8: z.append("공리리뷰 %s(%.0f일)"%(os.path.basename(rv[-1])[14:22],age))
    return (" | "+" · ".join(z)) if z else ""
o.append("Queue: alpha-pending %s · %s | 강화 L1 %s·L2 %s active · data-pipe %s%s"%(q," / ".join(fq) if fq else "frontier open 0",RF(1),RF(2),dp,S(PEND,"")))
# ③ Last — 최신 리서치 1단위 L-code (다음 라운드의 출발점)
#   ★v10 mode 정합 (2026-09-05): 구판은 `alpha_search/` 한 폴더만 봤다. v10 의 리서치
#     1단위는 충실구현(`paper_replication/` — lean-loop 5단계가 명시한 mode)과 강화
#     (`reinforcement/`)로 옮겨갔는데 경로가 v9 에 고정돼 **12일째 같은 값**을 냈다.
#     세 mode 스키마는 동일(l_code·grade·next_probe) — 최신 하나를 mode 라벨과 함께 낸다.
#     alpha_search 는 사료로 남기되 계속 후보에 둔다(발행되면 그날 것이 최신이 된다).
_LM={"paper_replication":"RP","reinforcement":"RF","alpha_search":"AS"}
_g=[(f,m) for m in _LM for f in glob.glob(R("stage_artifacts","l_code",m,"l_code_*.json"))]
_g.sort(key=lambda t: os.path.getmtime(t[0]))
c=(J(_g[-1][0]) or {}) if _g else {}; _md=_LM[_g[-1][1]] if _g else "?"
_ag=HH(S(lambda: (time.time()-os.path.getmtime(_g[-1][0]))/3600.0)) if _g else "?"
npb=c.get("next_probe"); npb=npb[0] if isinstance(npb,list) and npb else npb
o.append("Last: [%s] %s %s (%s) · next %s"%(_md,c.get("l_code") or "?",c.get("grade") or "?",_ag,str(npb or "?")[:80]))
# ④ Book — ★v10 정본 = 06_Registry/book/book_registry.json (governor/book_state 폐지)
b=J("06_Registry/book/book_registry.json") or {}
ents=[e for e in (b.get("entries") or []) if isinstance(e,dict)]
act=[e for e in ents if e.get("status")=="active"]
lt=act[-1] if act else None
# ★리밸 사양 미작성 대기 (2026-08-30 도훈 지시 "등재되면 시그널 정도는") —
#   등재만 되고 사양이 없으면 /book-rebalance 가 rc=2 로 막힌다. 그 사실이 리밸을
#   시도할 때가 아니라 **부팅 때** 보여야 조용히 쌓이지 않는다. 사양이 생기면 자동 해소.
pend=(J("06_Registry/pending_rebalance_specs.json") or {}).get("items") or []
o.append("Book: %d entries (%d active)%s%s — book_registry.json 정본(writer 경유·도훈 confirm)"%(
    len(ents),len(act),
    (" · ★리밸사양 미작성 %d(%s)"%(len(pend),",".join(str(x.get("book_id")) for x in pend[:3]))) if pend else "",
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
o.append("Alerts/Budget: open %s · %s · built %s | CLAUDE.md %s · rules %s · hooks %s · ctx %s"%(op,today_txt,bt,BG(S(lambda: os.path.getsize(R("CLAUDE.md"))),8192),BG(rb,25600),BG(hk,13),BG(S(CTX),50000)))
print("\n".join(o))
PYEOF
mkdir -p "$PROJECT/.cache" 2>/dev/null || true
printf '{"ts":"%s","ts_epoch":%s,"boot_fails":0,"mode":"lean"}\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$(date +%s)" > "$PROJECT/.cache/boot_stamp.json" 2>/dev/null || true
exit 0
