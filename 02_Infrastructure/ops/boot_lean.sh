#!/bin/bash
#==============================================================================
# boot_lean.sh — Qvest 부팅 (2026-08-23 신설 · 2026-09-05 v10 mode 정합 · 2026-10-13 v10.01 프로그램 줄)
#   상태 8줄만 출력(Data · Queue · Last · Book · Alerts/Budget · Programs · Resume · Infra). 검사 0 · 수리 0 · R 실행 0 · 테스트 0 · 백그라운드 0 · 항상 exit 0.
#   (Infra = 2026-11-08 — 매일 점검 기록 .cache/machine/infra_currency_<HOST>.json 을 읽기만 · 네트워크 0)
#   (v10.2 사다리 = 2026-11-11 — Programs 줄 꼬리 '| 사다리: …'(상설 판 · 강화 사슬 · 사슬 틱 · 결과 원장 · 팩터 DB 판 표식) + Last 줄 '원장 다음 탐침' · 읽기만)
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
PROJECT="$CLAUDE_PROJECT_DIR" PY="$CLAUDE_PROJECT_DIR/.venv_qvest_ml/Scripts/python.exe" "$PY" - <<'PYEOF' 2>/dev/null || printf 'Data: ?\nQueue: ?\nLast: ?\nBook: ?\nAlerts/Budget: ? (status 산출 실패 — venv python 확인)\nPrograms: ?\nResume: ?\n'
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
# ★부팅 메모(2026-11-10 H2 감사 2단계 · 출력 불변) — ① 의 세 계산(rawdata 스키마 · 팩터 IC 이름 집합 · 퀀티 최신성)은 pyarrow 가져오기 +
#   parquet 읽기로 부팅의 절반 이상을 썼다(부하 중 실측: 가져오기 2.0 s · IC 열 읽기 3.0 s). 결과를 원천 파일 지문(경로 · mtime_ns · 크기 ·
#   퀀티 최신성은 오늘 날짜까지)을 키로 .cache/boot_memo.json 에 적어 두고, 지문이 같으면 그 결과를 쓴다(같은 입력 → 같은 결과).
#   지문이 하나라도 다르거나 · 파일이 없거나 · 메모를 못 읽으면 원래 계산(예외도 원래대로 전파 → S/try 가 받는다). 실패 결과(예외 ·
#   퀀티 'NA')는 적지 않는다 — 일시 오류를 굳히지 않는다. 끄기: QVEST_BOOT_MEMO=0. 검사: 08_Tests/ops/test_boot_lean_memo.sh
_MEMO_P=R(".cache","boot_memo.json"); _MEMO_ON=os.environ.get("QVEST_BOOT_MEMO","1")!="0"
_memo=(S(lambda: json.load(open(_MEMO_P,encoding="utf-8")),{}) if _MEMO_ON else {}) or {}
if not isinstance(_memo,dict): _memo={}
_memo_dirty=[False]
def MEMO(key,paths,fn,keep=lambda v: True):
    if not _MEMO_ON: return fn()
    try: fp=[[p,os.stat(p).st_mtime_ns,os.stat(p).st_size] for p in paths]
    except Exception: return fn()
    e=_memo.get(key)
    if isinstance(e,dict) and e.get("fp")==fp and "v" in e: return e["v"]
    v=fn()
    if keep(v): _memo[key]={"fp":fp,"v":v}; _memo_dirty[0]=True
    return v
_nm=S(lambda: set(MEMO("rawdata_schema_names",[R(".cache","rawdata.parquet")],lambda: list(__import__("pyarrow.parquet",fromlist=["x"]).read_schema(R(".cache","rawdata.parquet")).names))))
mem="K200/KQ150 "+("?" if _nm is None else ("OK" if {"K200","KQ150"}<=_nm else "부재"))
# ★팩터 배출 격차 (2026-09-01) — emission_guard 는 매 빌드 돌고 있었는데 **소비자가 없어서**
#   registry 373 중 42종이 조용히 빠진 걸 아무도 못 봤다. 차단이 아니라 표면화다.
#   등재 N − IC 보유 N − 선언(expected_absent) N. 격차가 0 이면 조용하다.
def _fgap():
    try:
        reg=json.load(io.open(R(".cache","factor_db","factor_registry.json"),encoding="utf-8"))
        ic=set(MEMO("factor_ic_names",[R(".cache","factor_db","factor_ic_monthly.parquet")],lambda: list(set(__import__("pyarrow.parquet",fromlist=["x"]).read_table(R(".cache","factor_db","factor_ic_monthly.parquet"),columns=["Factor_Name"])["Factor_Name"].to_pylist()))))
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
# ★부팅 규칙(2026-10-17 도훈 "부팅시점에 최신화 안되어있으면 퀀티로그인해서 최신화" · 결정 BOOT-QW-LOGIN-REFRESH-20261017) —
#   퀀티 최신성 = 벤치 최신일 vs KRX 직전 거래일(06_Registry/krx_holidays.json · 오프라인 · 미수록 해 = ?).
#   퀀티 단일에선 캘린더도 퀀티가 늘리므로 위 감사(캘린더 기준)로는 퀀티 정체가 안 보인다 — 이 칸이 그것을 보인다.
def _qwcur():
    try:
        _td=dt.date.today()
        def _bc():
            import sys as _s; _s.path.insert(0, R("02_Infrastructure","data")); import krx_holidays as _kh
            r=_kh.bench_currency(_td, allow_fetch=False)   # 판정 정본(ensure_data_current 와 같은 함수)
            # 정확히 date 인 칸만 iso 로 적는다(그 밖 타입 = 'r' 원값 · 그런 결과는 메모하지 않는다 — 아래 keep)
            return [x.isoformat() if type(x) is dt.date else x for x in r]+[["d" if type(x) is dt.date else ("s" if x is None or isinstance(x,str) else "r") for x in r]]
        # 메모 지문 = krx_holidays.py 의 ROOT(QM_ROOT 또는 그 파일 기준 프로젝트)로 본 벤치 · 휴장일 등록부 + 판정 코드 자체 + 오늘
        _kr=os.environ.get("QM_ROOT") or P
        _v=MEMO("bench_currency|"+_td.isoformat(),[os.path.join(_kr,".cache","benchmark.parquet"),os.path.join(_kr,"06_Registry","krx_holidays.json"),R("02_Infrastructure","data","krx_holidays.py")],_bc,keep=lambda v: v[0]!="NA" and "r" not in v[3])
        st, bm, exp = [dt.date.fromisoformat(x) if f=="d" else x for x,f in zip(_v[:3],_v[3])]
        if st == "NA": return ("퀀티 ?(%s)" % exp, False)
        if st == "1": return ("★퀀티 미최신 %s<%s" % (bm.strftime("%m-%d"), exp.strftime("%m-%d")), True)
        return ("퀀티 %s ✓" % bm.strftime("%m-%d"), False)
    except Exception:
        return ("퀀티 ?", False)
_qw, _qwb = _qwcur()
o.append("Data: 키캐시 %d/4%s · audit %s · rawdata %s · bench %s · %s · %s · %s%s"%(4-len(bad)," ["+", ".join(bad)+"]" if bad else " OK",ra,HH(AG(".cache/rawdata.parquet")),HH(AG(".cache/benchmark.parquet")),mem,_fgap(),_qw,"  → 부팅 규칙: bash 02_Infrastructure/ops/ensure_data_current.sh (백그라운드 · 퀀티 로그인 · 최신화)" if _qwb else ("  → bash 02_Infrastructure/data/daily_refresh.sh" if bad else "")))
# ② Queue — 미소비 논문 수(비숫자면 UNREPORTED, 0 으로 접지 않음) + frontier open 상위 2
#   ★v10 (2026-08-29): 강화 원장 active(L1 n/25 · L2 무한) + data-pipeline open 병기 (fail-soft ?)
# (2026-11-10 H2 감사 2단계) 자식 파이썬(기동 0.5~0.8 s) 대신 같은 프로세스에서 모듈을 불러 CLI 와 같은 일을 한다 — `alpha-pending <dir>`
#   의 표준 출력 = 모듈 실행 중 찍힌 것 + len(pend) 한 줄(정상) · 원장 손상(LedgerUnreadable)이나 그 밖의 예외 = 그때까지 찍힌 것뿐
#   (CLI 는 숫자를 내지 않고 rc 3 · 트레이스백은 stderr). 그 출력을 그대로 모아 strip 하므로 q 판정(숫자 · UNREPORTED)이 같다.
#   sys.path[0] = ops 폴더(CLI 와 같은 형제 모듈 해석) · stdout 은 잡아 두고 되돌린다. 끄기: QVEST_BOOT_INPROC=0(구 자식 프로세스).
def _alpha_pending_out():
    import importlib.util as _iu, contextlib as _cl
    _od=R("02_Infrastructure","ops"); _buf=io.StringIO()
    sys_path_saved=list(__import__("sys").path); __import__("sys").path.insert(0,_od)
    try:
        with _cl.redirect_stdout(_buf):
            try:
                _sp=_iu.spec_from_file_location("research_pool_predicates",os.path.join(_od,"research_pool_predicates.py"))
                _m=_iu.module_from_spec(_sp); _sp.loader.exec_module(_m)
                print(len(_m.alpha_pending(R("stage_artifacts","paper_recharge"))))
            except (Exception, SystemExit):
                pass
    finally:
        __import__("sys").path[:]=sys_path_saved
    return _buf.getvalue().strip()
import io
# (11-10 검토 2차) 시간 상한 복구 — 구 자식 프로세스 경로의 90초 상한이 같은 프로세스 전환으로 사라져, 파일 읽기 하나가 막히면
#   (OneDrive 주문형 자리표시 · 동기화 잠금) 부팅 전체가 출력 0 으로 멈췄다. 데몬 스레드로 돌리고 상한(기본 90초 = 구 상한 그대로 ·
#   QVEST_BOOT_QUEUE_TIMEOUT_S)을 넘으면 UNREPORTED 로 접고 나머지 줄을 낸다. 멈춘 스레드가 잡아 둔 표준 출력은 되돌린다.
def _alpha_pending_guarded():
    import threading as _th, sys as _sys
    _orig=_sys.stdout; _box=[""]
    def _run(): _box[0]=_alpha_pending_out()
    _t=_th.Thread(target=_run,daemon=True); _t.start()
    _t.join(float(os.environ.get("QVEST_BOOT_QUEUE_TIMEOUT_S","90") or 90))
    if _t.is_alive():
        _sys.stdout=_orig
        return ""
    return _box[0] or ""
_r=S(_alpha_pending_guarded) if os.environ.get("QVEST_BOOT_INPROC","1")!="0" else S(lambda: subprocess.run([PY,R("02_Infrastructure","ops","research_pool_predicates.py"),"alpha-pending",R("stage_artifacts","paper_recharge")],capture_output=True,text=True,timeout=90).stdout.strip())
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
    # ★예산은 entry 별이다 (2026-09-07 · "칸 수는 격자·원장에서 세라"): B1 설계가 격자를 늘리면 entry.max_attempts(실측 30)가
    #   루트 상한(25)과 갈린다. 루트를 읽으면 부팅이 20/25 라고 말하는데 실제 예산은 30 이었다. entry 값 우선 · 없으면 루트.
    #   검사: 08_Tests/ops/test_boot_lean_rf_budget.R (이 블록을 패턴 추출해 격리 원장에 대고 실행 · 변이 대조)
    e=act[-1]; mx=e.get("max_attempts") or d.get("max_attempts")
    dep=S(lambda: int((e.get("parent") or {}).get("depth")))
    return "%d(%s %s/%s%s)"%(len(act),str(e.get("base_id") or "?")[-24:],
        e.get("attempts_used") if e.get("attempts_used") is not None else "?",
        mx if mx else "∞"," ·승격d%d"%dep if dep else "")
dp=S(lambda: str(sum(1 for e in ((J("06_Registry/data_pipeline_queue.json") or {}).get("entries") or []) if (e.get("status") if isinstance(e,dict) else None)=="open")),"?")
# ★레인 틱 나이 (2026-11-10 전수점검) — 디스패처가 멈추면 _status.json 은 마지막 값 그대로 남는다. 11-07~11-10 레인이 71시간 멈춘
#   동안 부팅은 '레인 슬롯 0/3' 만 보였다(정상처럼 읽힌다). 틱 시각(at · 못 읽으면 파일 mtime)이 문턱보다 오래되면 '★틱 N 전(레인 정지?)' 를 붙인다.
#   문턱 = 구성요소 감시 정의의 replication_lane/lane_alive.max_age_h(06_Registry/superfan_components.json) — 숫자를 여기 따로 두지 않는다.
#   문턱이나 시각을 못 읽으면 '틱 ?' — 조용히 정상으로 접지 않는다. 검사: 08_Tests/ops/test_boot_lean_lane_tick.R (블록 추출 · 픽스처 · 돌연변이)
def LANE_TICK(ss,now=None):
    th=S(lambda: [float(r["max_age_h"]) for c in ((J("06_Registry/superfan_components.json") or {}).get("components") or [])
                  if c.get("id")=="replication_lane" for r in (c.get("rules") or []) if r.get("id")=="lane_alive"][0])
    t=S(lambda: dt.datetime.strptime(str(ss.get("at")),"%Y-%m-%dT%H:%M:%S%z").timestamp())
    if t is None: t=S(lambda: os.path.getmtime(R("06_Registry","replication_slots","_status.json")))
    if th is None or t is None: return " · 틱 ?"
    ah=((time.time() if now is None else now)-t)/3600.0
    return (" · ★틱 %s 전(레인 정지?)"%HH(ah)) if ah>th else ""
# ★무인 러너 핸드오프 노출 (2026-08-30) — cleaner 선례: 기계가 남긴 대기 상태를 부팅이 보여야
#   세션이 소비한다. 텔레그램만 쓰면 놓쳤을 때 어디서도 안 보인다. 0 이면 표기하지 않는다(소음 방지).
def PEND():
    z=[]
    r=J("06_Registry/replication_request.json")
    if r and (r.get("status")=="pending"):
        z.append("★충실구현 대기 1(%s)"%str(((r.get("paper") or {}).get("paper_title") or "?"))[:28])
    # ★다중 슬롯(2026-10-20 · WP3) — 디스패처(rf_replication_slots.py tick)가 매 틱 쓰는 요약. 파일이 없으면(구판 단일 슬롯) 표기 없음
    ss=J("06_Registry/replication_slots/_status.json")
    if ss and isinstance(ss.get("slots"),list):
        bz=sum(1 for x in ss["slots"] if isinstance(x,dict) and x.get("status") in ("pending","in_progress","failed_needs_session"))
        at=ss.get("attention") or []
        z.append("레인 슬롯 %d/%d%s%s%s"%(bz,len(ss["slots"]),(" · GPU 임대 "+str(ss.get("lease_holder") or "?")) if ss.get("lease")=="held" else "",
                                     (" · ★확인 %d"%len(at)) if at else "",S(lambda: LANE_TICK(ss)," · 틱 ?")))
    aq=J("06_Registry/grade_a_queue.json")
    na=sum(1 for e in ((aq or {}).get("entries") or []) if (e.get("status") if isinstance(e,dict) else None)=="awaiting_judge")
    if na: z.append("★A등급 대기 %d(Judge/BOOK confirm)"%na)
    # (v10.01 · 2026-10-13) 구 '결합후보 n' · '★결합검토 의무 n/3' 표시는 결합 레인(rf_combination_*)과 함께 퇴역 —
    #   논문 간 결합은 리서치 프로그램 P4_ASSEMBLY 가 맡는다(Programs 줄).
    # 공리 리뷰(건식) 미소비 보고서 — 기계가 산출하고 세션이 판단한다(cleaner 선례).
    #   반증 축적분은 자동 deprecate 되지 않는다(metric_type=estimated 는 human-review 강제).
    rv=sorted(glob.glob(R("qepm","memory","axioms","review_log","dryrun","review_dryrun_*.json")))
    if rv:
        age=(time.time()-os.path.getmtime(rv[-1]))/86400.0
        if age<=8: z.append("공리리뷰 %s(%.0f일)"%(os.path.basename(rv[-1])[14:22],age))
    return (" | "+" · ".join(z)) if z else ""
# ★v10.01 (2026-10-13): 1계층 고정 격자 강화는 퇴역 — L1 원장은 소비 기록(active 즉시 park)이라 표시하지 않는다. L2 강화만.
o.append("Queue: alpha-pending %s · %s | 강화 L2 %s active · data-pipe %s%s"%(q," / ".join(fq) if fq else "frontier open 0",RF(2),dp,S(PEND,"")))
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
# ★v10.2 결과 원장(2026-11-11 · 사다리 루프 6항 '닫으면 남긴다') — 06_Registry/round_outcomes.jsonl(writer = round_core v1/outcomes.R · 추가 전용) 을
#   읽기만 한다. 의미는 outcomes.R 그대로: 빈 줄 제외 · 격리 줄(kind quarantine 의 line_md5 = 원래 줄 UTF-8 md5) 제외 · 격리 안 된 판독 불가 줄 = 멈춤('?') ·
#   schema round_outcome_v1 만 · kind 없음 = round · 열린 탐침 = rc_open_probes(ref '<round_id>#<번호>' 가 probe_consumed 에 없는 것 · tau_clean 없음).
#   반환 = None(원장 없음 · 첫 닫기 전) · dict · 예외(→ S 가 False = '?'). Last 줄(최근 닫힌 라운드의 첫 열린 탐침) · 사다리 꼬리가 같은 판독을 쓴다.
#   검사: 08_Tests/scenarios/test_scn_boot_ladder.sh (f)
def _OUTCOMES(p=None):
    import hashlib
    p=p or R("06_Registry","round_outcomes.jsonl")
    if not os.path.exists(p): return None
    L=[s for s in open(p,encoding="utf-8").read().split("\n") if s.strip()]
    qd=set()
    for s in L:
        if '"kind":"quarantine"' in s:
            x=S(lambda: json.loads(s))
            if isinstance(x,dict) and x.get("schema")=="round_outcome_v1" and x.get("kind")=="quarantine":
                v=x.get("line_md5"); qd.update(str(i) for i in (v if isinstance(v,list) else [v]) if i is not None)
    if qd: L=[s for s in L if hashlib.md5(s.encode("utf-8")).hexdigest() not in qd]
    out=[json.loads(s) for s in L]          # 격리 안 된 판독 불가 줄 = 예외(조용히 건너뛰지 않는다)
    out=[x for x in out if isinstance(x,dict) and x.get("schema")=="round_outcome_v1"]
    kd=lambda x: "round" if x.get("kind") is None else x.get("kind")
    rounds=[x for x in out if kd(x)=="round"]
    used={str(x.get("ref")) for x in out if kd(x)=="probe_consumed"}
    op=[]
    for r in rounds:
        pr=r.get("probes"); pr=pr if isinstance(pr,list) else ([] if pr is None else [pr])
        for i,t in enumerate(pr,1):
            ref="%s#%d"%(r.get("round_id"),i)
            if ref not in used: op.append((ref,str(r.get("round_id")),str(t)))
    return {"n":len(rounds),"open":op,"last":rounds[-1] if rounds else None}
_OC=S(_OUTCOMES,False)
def _last_probe(oc):
    if not isinstance(oc,dict) or not oc.get("last"): return ""
    rid=str(oc["last"].get("round_id"))
    for ref,r,t in oc["open"]:
        if r==rid: return ' · 원장 다음 탐침 "%s"'%t[:60]
    return ""
o.append("Last: [%s] %s %s (%s) · next %s%s"%(_md,c.get("l_code") or "?",c.get("grade") or "?",_ag,str(npb or "?")[:80],S(lambda: _last_probe(_OC),"")))
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
# (2026-11-10 H2 감사 2단계) 등록된 command 값만 센다 — 구판은 settings.json 원문 전체를 훑어 설명문(_doc_*) 속 시험 경로
#   (08_Tests/hooks/test_hook_powershell_coverage)까지 세어 `hooks 14/13` 오탐을 냈다. 모집단 = hooks.<이벤트>[].hooks[].command 안의
#   02_Infrastructure/hooks/<이름>.sh. 검사: 08_Tests/ops/test_boot_lean_memo.sh H 축
hk=S(lambda: len({m for G in json.load(open(R(".claude","settings.json"),encoding="utf-8"))["hooks"].values() for g in G for h in (g.get("hooks") or []) for m in re.findall(r"02_Infrastructure/hooks/([A-Za-z0-9_.-]+\.sh)",str(h.get("command") or ""))}))
# ★세션 전사 폴더의 이름은 '세션이 실제로 연 경로'에서 만들어진다(예: G--OneDrive-Quant-Module-Moltbot). 부팅의 P(정본 경로)로 이름을
#   만들면 여는 경로가 다른 기계(메인 PC = G: 드라이브)에서 폴더를 못 찾아 게이지가 늘 '?' 였다(2026-11-10 전수점검).
#   프로젝트 폴더명 꼬리로 끝나는 폴더들에서 가장 최근 전사를 고른다(워크트리 세션 폴더는 꼬리가 달라 빠진다).
def CTX(base=None):
    tail=re.sub(r"[^A-Za-z0-9]","-",os.path.basename(P.replace("\\","/").rstrip("/")))
    base=base or os.path.join(os.path.expanduser("~"),".claude","projects")
    p=max([f for d in glob.glob(os.path.join(base,"*"+tail)) for f in glob.glob(os.path.join(d,"*.jsonl"))],key=os.path.getmtime)
    for ln in open(p,encoding="utf-8",errors="replace"):
        j=json.loads(ln) if ln.strip()[:1]=="{" else {}
        if j.get("type")=="assistant":
            u=(j.get("message") or {}).get("usage") or {}
            return sum(int(u.get(k) or 0) for k in ("input_tokens","cache_creation_input_tokens","cache_read_input_tokens"))
o.append("Alerts/Budget: open %s · %s · built %s | CLAUDE.md %s · rules %s · hooks %s · ctx %s"%(op,today_txt,bt,BG(S(lambda: os.path.getsize(R("CLAUDE.md"))),8192),BG(rb,25600),BG(hk,13),BG(S(CTX),50000)))
# ⑥ Programs — v10.01 1계층 리서치 프로그램 등록부(06_Registry/research_programs.json · writer = 02_Infrastructure/programs/program_registry.R).
#   **읽기만**. 부팅 계약(R 0)이라 pr_status_lines 를 부르지 않고 같은 필드를 한 줄로 접는다:
#   측정 계약 완료 n/N(남은 id) | 프로그램별 상태(재료·라운드가 있으면 수). 구 Director(rf_director.R — 고정 격자 진단)는 러너와 함께 퇴역.
#   판독 실패는 0 으로 접지 않고 '?(<원인>)' — 빈 등록부와 못 읽은 등록부는 다른 사실이다. 부팅은 계속.
#   검사: 08_Tests/ops/test_boot_lean_programs_line.R (블록 패턴 추출 · 픽스처 · 돌연변이).
def PROGRAMS():
    p=R("06_Registry","research_programs.json")
    if not os.path.exists(p): return "Programs: ?(등록부 부재)"
    try: d=json.load(io.open(p,encoding="utf-8-sig"))
    except Exception as e: return "Programs: ?(파손 JSON %s)"%type(e).__name__
    if not isinstance(d,dict) or d.get("schema")!="research_programs_v1":
        return "Programs: ?(schema %s)"%(str(d.get("schema"))[:24] if isinstance(d,dict) else type(d).__name__)
    mc=(d.get("measurement_contract") or {}).get("items")
    pg=d.get("programs")
    if not isinstance(mc,list) or not isinstance(pg,list): return "Programs: ?(items/programs 형식)"
    nd=sum(1 for m in mc if isinstance(m,dict) and m.get("status")=="done")
    todo=[str(m.get("id") or "?") for m in mc if isinstance(m,dict) and m.get("status")!="done"]
    ps=[]
    for g in pg:
        if not isinstance(g,dict): continue
        nq=len(g.get("queue") or []); nr=len(g.get("rounds") or [])
        ps.append("%s %s%s"%(str(g.get("id") or "?").split("_")[0],g.get("status") or "?",
                              "(재료 %d·라운드 %d)"%(nq,nr) if (nq or nr) else ""))
    # 미분류 재료(검증기가 라우터 분류 없이 보류한 측정 재료 · paper_routing.unrouted · 2026-10-14) — 있을 때만 붙인다(세션 분류 대기)
    un=(d.get("paper_routing") or {}).get("unrouted") if isinstance(d.get("paper_routing"),dict) else None
    nu=len(un) if isinstance(un,list) else 0
    return "Programs: 측정계약 %d/%d%s | %s%s"%(nd,len(mc)," (남은 "+" ".join(todo)+")" if todo else "",
                                            " · ".join(ps) if ps else "프로그램 0", " · 미분류 재료 %d"%nu if nu else "")
# ⑥-b 대기 결정 — 결정 대기 레지스터 부기 (P3-07 · 2026-09-23 플랜 qvest-1-drifting-eclipse). **읽기만** — writer =
#   reinforce_ledger.R::dr_open/dr_resolve(원자 쓰기 · owner 만 resolve). 새 줄을 만들지 않고 Programs 줄 끝에 붙는다(v10.01 · 구 Director 줄).
#   ★왜: R1 → l2_auto.enabled → director.act 사슬이 2계층 A 경로·자기개선 채점기를 막는데 부팅 어디에도 안 보였다(감사 D7-04·D8-05).
#   status=="open" 만 센다(resolved 를 세면 이미 끝난 결정이 최고령으로 떠 대기가 영원히 안 줄어든다).
#   차단 = open 항목의 blocks "lane:" 을 막는 항목 수 내림차순(동률은 오래된 항목 순) 상위 3 + 나머지 수.
#   읽기 실패는 0 으로 접지 않고 '?(<원인>)' — 빈 레지스터와 못 읽은 레지스터는 다른 사실이다. 부팅은 계속.
#   검사: 08_Tests/ops/test_decision_register.R (블록 패턴 추출 · status 필터 제거/'?'→0 돌연변이 red).
def DECISIONS():
    import datetime as _dm
    p=R("06_Registry","decision_register.json")
    if not os.path.exists(p): return " · 대기결정 ?(레지스터 부재)"
    try: d=json.load(io.open(p,encoding="utf-8-sig"))
    except Exception as e: return " · 대기결정 ?(파손 JSON %s)"%type(e).__name__
    if not isinstance(d,dict) or d.get("schema")!="decision_register_v1":
        return " · 대기결정 ?(schema %s)"%(str(d.get("schema"))[:24] if isinstance(d,dict) else type(d).__name__)
    it=d.get("items")
    if not isinstance(it,list): return " · 대기결정 ?(items 형식)"
    op=[x for x in it if isinstance(x,dict) and x.get("status")=="open"]
    if not op: return " · 대기결정 0"
    def _od(x):
        try: return _dm.date.fromisoformat(str(x.get("opened_at") or "")[:10])
        except Exception: return None
    op.sort(key=lambda x:(_od(x) or _dm.date.max,str(x.get("id") or "")))
    a0=_od(op[0]); ag="?" if a0 is None else str((_dm.date.today()-a0).days)
    cnt={}
    for x in op:
        bl=x.get("blocks"); bl=[bl] if isinstance(bl,str) else (bl if isinstance(bl,list) else [])
        for b in bl:
            b=str(b)
            if b.startswith("lane:") and b[5:].strip(): cnt[b[5:].strip()]=cnt.get(b[5:].strip(),0)+1
    ln=sorted(cnt,key=lambda k:-cnt[k])
    lanes=("·".join(ln[:3])+(" +%d"%(len(ln)-3) if len(ln)>3 else "")) if ln else "없음"
    return " · 대기결정 %d · 최고령 %s(%sd) · 차단 %s"%(len(op),op[0].get("id") or "?",ag,lanes)
# ⑥-c 사다리(v10.2 · 2026-11-11 도훈 "qvest 부팅 시퀀스도 v10.2 에 대응되게") — Programs 줄 꼬리 ' | 사다리: …'. 새 줄을 만들지 않는다(8줄 계약).
#   **읽기만**(R 0 · 쓰기 0). 정의는 실행기와 같다 — 하나라도 어긋나면 부팅과 틱이 다른 판 · 사슬을 본다:
#   상설 판 = 02_Infrastructure/ops/standing_board_run.sh '등록된 상설 판' 절(사양 "standing": true · 최상위 round_id = 디렉터리 이름 ·
#     stage_artifacts/programs/<program>/<round_id>/prereg.json 존재 — 없으면 '미등록' · 판 폴더 tick_hold = 보류 표시). 항목 상태 = round_core v1/standing.R::rc_standing_items 사건 의미
#     (enqueue 가 항목을 만들고 measure · verdict 가 붙는다 · 통과 = verdict.qualify true · 대기 = .rcs_pending · 실패 상한 = 코어 상수 RC_STANDING_MAX_FAILS 를
#     소스에서 읽는다 — 못 읽으면 '대기 ?'). 원장 사슬(schema · prev = 앞 줄 md5)이 끊겼으면 코어가 읽기를 거부하므로 '?(원장 사슬 끊김)'.
#   강화 사슬 = 02_Infrastructure/ops/chain_tick.sh 0단계(P4_ASSEMBLY/<사슬>/chain_spec.json · '_' 폴더 제외 · 원장 첫 줄 chain_registered ·
#     마지막 줄 chain_closed = 닫힘 · tick_hold = 보류 표시). 생성 차단 = 틱 장부 .cache/chain_tick/state/<chain_id>.json 의 gen_blocked(02_Infrastructure/programs/chain_tick.R).
#   틱 = 06_Registry/chain_tick.json enabled · 결과 원장 = _OUTCOMES(위) · 팩터 DB 판 표식 = 06_Registry/factor_db_vintage.json 마지막 완료 수리(completed_at 비움 = 진행 중).
#   판독 실패는 0 으로 접지 않고 '?' — 없는 것과 못 읽은 것은 다른 사실이다. 검사: 08_Tests/scenarios/test_scn_boot_ladder.sh (픽스처 · 돌연변이)
def _LD_BOARD(lp,mf):
    import hashlib
    if not os.path.exists(lp): return {"n":0,"q":0,"p":0,"age":None}
    t=open(lp,encoding="utf-8").read()
    L=t.split("\n") if t else []
    if t.endswith("\n"): L=L[:-1]
    prev="genesis"; recs=[]
    for s in L:
        r=S(lambda: json.loads(s))
        if not isinstance(r,dict) or r.get("schema")!="rc_standing_ledger_v1" or r.get("prev")!=prev: return "?(원장 사슬 끊김)"
        recs.append(r); prev=hashlib.md5(s.encode("utf-8")).hexdigest()
    I={}
    for r in recs:
        ev=r.get("event"); cd=r.get("code")
        if ev=="enqueue":
            if not isinstance(cd,str) or not cd: return "?(항목 코드 없음)"
            I[cd]={"src":r.get("source_results"),"v":r.get("verdict"),"m":[]}
        elif ev in ("measure","verdict") and isinstance(cd,str) and cd in I:
            if ev=="measure": I[cd]["m"].append(r)
            else: I[cd]["v"]=r
    def _ln(v): return 0 if v is None else (len(v) if isinstance(v,(list,dict)) else 1)
    def _mok(m): return m.get("ok") is True and m.get("fp_same") is True
    def _dfr(m):
        d=m.get("deferred"); d=(d[0] if d else None) if isinstance(d,list) else d
        return d=="refresh_lock"
    def _pend(it):
        if it["v"] is not None or it["src"] is not None or any(_mok(m) for m in it["m"]): return False
        if it["m"] and _ln(it["m"][-1].get("r2"))>0: return False
        return sum(1 for m in it["m"] if not _mok(m) and _ln(m.get("r2"))==0 and not _dfr(m))<mf
    at=S(lambda: dt.datetime.strptime(str(recs[-1].get("at")),"%Y-%m-%dT%H:%M:%S%z").timestamp()) if recs else None
    return {"n":len(I),"q":sum(1 for it in I.values() if isinstance(it["v"],dict) and it["v"].get("qualify") is True),
            "p":"?" if mf is None else sum(1 for it in I.values() if _pend(it)),"age":None if at is None else (time.time()-at)/3600.0}
def _LD_BOARDS():
    mf=S(lambda: int(re.search(r"(?m)^RC_STANDING_MAX_FAILS <- (\d+)L?",open(R("04_Research","programs","_lib","round_core","v1","standing.R"),encoding="utf-8").read()).group(1)))
    reg=[]; un=[]; ur=0
    for sp in sorted(glob.glob(R("04_Research","programs","*","*","round_spec.json"))):
        t=S(lambda: open(sp,encoding="utf-8",errors="replace").read())
        if t is None: ur+=1; continue
        ls=t.split("\n"); d=os.path.dirname(sp); rid=os.path.basename(d)
        if not any(re.search(r'"standing"[ \t\r\f\v]*:[ \t\r\f\v]*true',x) for x in ls): continue
        if not any(re.match(r'  "round_id"[ \t\r\f\v]*:[ \t\r\f\v]*"%s"'%re.escape(rid),x) for x in ls): continue
        pg=[m.group(1) for m in (re.match(r'  "program"[ \t\r\f\v]*:[ \t\r\f\v]*"([^"]*)"',x) for x in ls) if m]
        prog=(pg[0] if pg else "") or os.path.basename(os.path.dirname(d))
        tag=rid.split("_")[0]
        if not os.path.isfile(R("stage_artifacts","programs",prog,rid,"prereg.json")): un.append(tag); continue   # 등록 전(사전등록 정본 없음)
        b=S(lambda: _LD_BOARD(R("stage_artifacts","programs",prog,rid,"standing_ledger.jsonl"),mf),"?(원장 판독 불가)")
        hold=" ·보류" if os.path.exists(os.path.join(d,"tick_hold")) else ""          # 세션 보류(standing_board_run.sh — 그 판의 무인 틱이 멈춰 있다 · 2026-11-11)
        reg.append("%s %s%s"%(tag,b if isinstance(b,str) else "항목 %d·통과 %d·대기 %s%s"%(b["n"],b["q"],b["p"],"" if b["age"] is None else "·"+HH(b["age"])+" 전"),hold))
    parts=reg+["%s 미등록"%x for x in un]+(["사양 판독 불가 %d"%ur] if ur else [])
    return "상설 판 %d%s"%(len(reg),"(%s)"%" / ".join(parts) if parts else "")
def _LD_CHAINS():
    op=[]; nc=0; gb=0; gq=0
    for sp in sorted(glob.glob(R("04_Research","programs","P4_ASSEMBLY","*","chain_spec.json"))):
        d=os.path.dirname(sp); cid=os.path.basename(d)
        if cid.startswith("_"): continue
        lp=os.path.join(d,"chain_steps.jsonl")
        if not os.path.isfile(lp): continue
        t=S(lambda: open(lp,"rb").read().decode("utf-8","replace"))
        if t is None: op.append("%s ?(원장 판독 불가)"%cid); continue
        L=t.split("\n") if t else []
        if t.endswith("\n"): L=L[:-1]
        if not L or '"event":"chain_registered"' not in L[0]: continue                  # 등록 전 사슬 판
        if '"event":"chain_closed"' in L[-1]: nc+=1; continue
        hold=" ·보류" if os.path.exists(os.path.join(d,"tick_hold")) else ""
        try:
            rr=[json.loads(s) for s in L if s.strip()]
            ks=[int(r["k"]) for r in rr if r.get("event")=="step_open"]
            at=S(lambda: dt.datetime.strptime(str(rr[-1].get("at")),"%Y-%m-%dT%H:%M:%S%z").timestamp())
            op.append("%s k%d %s%s%s"%(cid,max(ks) if ks else 0,rr[-1].get("event") or "?","" if at is None else " "+HH((time.time()-at)/3600.0)+" 전",hold))
        except Exception:
            op.append("%s ?(원장 판독 불가)%s"%(cid,hold))
        sf=R(".cache","chain_tick","state",cid+".json")
        if os.path.exists(sf):
            st=S(lambda: json.load(open(sf,encoding="utf-8")))
            if not isinstance(st,dict): gq+=1
            elif st.get("gen_blocked") is True: gb+=1
    return "사슬 %d%s%s%s"%(len(op),"(%s)"%" / ".join(op) if op else ""," · 닫힘 %d"%nc if nc else "",
                          (" · ★생성 차단 %d"%gb if gb else "")+(" · 틱 장부 ? %d"%gq if gq else ""))
def _LD_TICK():
    d=J("06_Registry/chain_tick.json")
    en=d.get("enabled") if isinstance(d,dict) else None
    return "틱 켜짐" if en is True else ("틱 꺼짐" if en is False else "틱 ?")
def _LD_OUT(oc):
    if oc is None: return "결과 원장 없음(첫 닫기 전)"
    if not isinstance(oc,dict): return "결과 원장 ?(판독 불가)"
    return "결과 원장 %d건 · 열린 탐침 %d"%(oc["n"],len(oc["open"]))
def _LD_FDV():
    p=R("06_Registry","factor_db_vintage.json")
    if not os.path.exists(p): return "팩터DB ?(원장 부재)"
    E=json.load(open(p,encoding="utf-8-sig"))["entries"]
    dn=[dt.datetime.fromisoformat(str(e["completed_at"])) for e in E if e.get("completed_at") is not None]
    ip=sum(1 for e in E if e.get("completed_at") is None)
    return ("팩터DB 수리 %s"%max(dn).strftime("%m-%d") if dn else "팩터DB 수리 없음")+(" · 수리 진행 중 %d"%ip if ip else "")
def LADDER():
    return " | 사다리: "+" · ".join([S(_LD_BOARDS,"상설 판 ?"),S(_LD_CHAINS,"사슬 ?"),S(_LD_TICK,"틱 ?"),S(lambda: _LD_OUT(_OC),"결과 원장 ?"),S(_LD_FDV,"팩터DB ?")])
o.append(S(PROGRAMS,"Programs: ?(표시 예외)")+S(DECISIONS," · 대기결정 ?(표시 예외)")+S(LADDER," | 사다리: ?(표시 예외)"))
# ⑦ Resume(2026-10-15 도훈 "세션이 예기치않게 종료됐을 때 새로운 세션에서도 이 프로세스가 이어질 수 있도록") —
#   진행 중 작업(06_Registry/session_resume.json · writer = programs/session_resume.py) 최신 1건의 단계 · 다음 할 일 +
#   등록부에서 등록됐지만 끝나지 않은 라운드(저널과 별개 자동 신호). 로직은 도구 한 곳(boot_line) — 여기서는 불러 쓰기만.
def RESUME():
    import importlib.util as _iu
    _sp=_iu.spec_from_file_location("session_resume",R("02_Infrastructure","programs","session_resume.py"))
    _m=_iu.module_from_spec(_sp); _sp.loader.exec_module(_m)
    return _m.boot_line(P)
o.append(S(RESUME,"Resume: ?(표시 예외)"))
# ⑧ Infra(2026-11-08 도훈 "부팅 시에 점검해서 R, 파이썬 버전, 각종 패키지 등 인프라 최신화 시킬 수 있도록") —
#   매일 05:40 예약 작업 Qvest_InfraCurrency(기계마다)가 쓴 .cache/machine/infra_currency_<HOST>.json 을 읽기만 한다(부팅에서 네트워크 0).
#   표시 규칙 단일 출처 = 02_Infrastructure/ops/infra_currency.py::infra_line(오래됨 · 보류 · 고정 라운드 판정 포함).
def INFRA():
    import importlib.util as _iu
    _sp=_iu.spec_from_file_location("infra_currency",R("02_Infrastructure","ops","infra_currency.py"))
    _m=_iu.module_from_spec(_sp); _sp.loader.exec_module(_m)
    f=R(".cache","machine","infra_currency_%s.json"%os.environ.get("COMPUTERNAME","unknown").upper())
    return _m.infra_line(json.load(open(f,encoding="utf-8")) if os.path.exists(f) else None)
o.append(S(INFRA,"Infra: ?(표시 예외)"))
# (v10.01 · 2026-10-13) 구 ⑦ Rules(방향 규칙 일간 채점 — 디렉터 입력)는 디렉터와 함께 퇴역.
# 부팅 메모 기록(바뀐 것이 있을 때만 · 원자적 교체 · 실패해도 출력 불변)
def _memo_write():
    t=_MEMO_P+".tmp%d"%os.getpid()
    with open(t,"w",encoding="utf-8") as fh: json.dump(_memo,fh)
    os.replace(t,_MEMO_P)
if _memo_dirty[0]: S(_memo_write)
print("\n".join(o))
PYEOF
mkdir -p "$PROJECT/.cache" 2>/dev/null || true
printf '{"ts":"%s","ts_epoch":%s,"boot_fails":0,"mode":"lean"}\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$(date +%s)" > "$PROJECT/.cache/boot_stamp.json" 2>/dev/null || true
exit 0
