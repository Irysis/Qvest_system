"""test_scn_tg_alert_dedup_e2e.py — 무인 경보 원인 키 2차 수리(2026-11-10) 운영 경로 시나리오 시험

임시 루트에 실제 코드 사본(scheduler_task_health.sh · _sched_failure_classify.sh · resolve_project.sh · alert_dedup.py · superfan_watch.py)을 두고
운영 진입점을 **끝까지** 돌린다 — scheduler_task_health.sh 전체(가짜 작업 목록 = QVEST_TH_COLLECTOR_CMD) · superfan_watch.py scan --notify.
발신은 전부 모의: task_health = QVEST_SCHED_ALERT_RSCRIPT(성공/실패 전환) · Superfan = QVEST_SUPERFAN_NOTIFY_CMD(성공/실패 전환) ·
생성 R 의 종료 코드 계약(S7)만 실제 Rscript + 임시 루트의 가짜 telegram_notify.R(R_ENVIRON_USER = 빈 파일 · QM_ROOT = 임시 루트). 네트워크 0 ·
운영 상태 파일 · .cache 무접촉(경로 전부 임시 루트).

  S1 정체 rc 0 · 트리거 만료 rc 0 작업 — task_health 세 번 → 정확히 1통 · 경보 뒤 건강하게 다시 돌면 해소 → 같은 날 새 실패 1통 더
  S2a task_health 발송 실패 → 같은 날 다음 실행이 다시 보냄(원인 키 놓음 + 기보고 원장 되돌림)
  S2b task_health 발송 실패 → 같은 날 Superfan 의 같은 원인 경보가 막히지 않음
  S2c 같은 키를 두 구성요소가 공유 · 대표 발송 실패 → release 가 키를 완전히 놓음 → task_health 가 보냄 → 다시 1통만(양보 · 확정)
  S3 작업을 공유하는 두 구성요소의 서로 다른 실패 → 2통(task_health 가 그 작업 키를 먼저 잡았어도)
  S4 같은 실패를 두 발신기가 봄 → 1통(양 순서) · 양보한 쪽은 상대가 놓으면 다시 잡음 · 죽은 보유자의 미확정 키는 다음 claim 이 가져감
  S5 꺼진 작업(이 기계 · 신선한 측정) → 0통
  S6 낡은 · 다른 기계 · 기계 표식 없는 측정 → 꺼짐을 믿지 않음(억제 안 함)
  S8 꺼짐 직접 조회(3차 · 11-10 저녁 오경보) — 측정 낡음 + 조회 '꺼짐' → 0통 · 조회 실패/응답 누락 + 측정 낡음 → 1통(fail-closed) ·
     조회 '켜짐' + 로그 낡음 → 1통 · 꺼짐 확인 → 열린 낡음 이상 해소 + 원인 키 해소 · 다음 실행 재개방 없음 · 다시 켜진 뒤 낡음 → 1통 더
  S7 생성 R — tg_agent_brief ok = FALSE 면 종료 코드 ≠ 0 → 셸이 키를 놓고 마커에 실패 표식 · ok = TRUE 면 확정
  M  수리마다 되돌린 돌연변이 사본(소스 텍스트 치환 · 치환 성사 단정) → 대응 시나리오가 빨개짐
마지막 줄 = {"test":...,"pass":N,"fail":N,"total":N}
"""
import datetime as dt, io, json, os, shutil, subprocess, sys, tempfile

REAL = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
REAL = os.environ.get("QVEST_E2E_CODE_ROOT") or REAL          # 수리 전 판 대조용(그 판의 코드 사본으로 같은 시나리오) — 평소엔 저장소
PY = sys.executable.replace("\\", "/")
BASH = r"C:\Program Files\Git\bin\bash.exe" if os.name == "nt" else "bash"
TODAY = dt.date.today().strftime("%Y-%m-%d")
ME = os.environ.get("COMPUTERNAME") or __import__("socket").gethostname()
P = F = 0
CODE = ("02_Infrastructure/programs/superfan_watch.py", "02_Infrastructure/ops/alert_dedup.py",
        "02_Infrastructure/ops/_sched_failure_classify.sh", "02_Infrastructure/ops/scheduler_task_health.sh",
        "02_Infrastructure/ops/resolve_project.sh")


def chk(nm, cond, why=""):
    global P, F
    if cond:
        P += 1; print("  PASS ", nm)
    else:
        F += 1; print("  FAIL ", nm, "::", why)


def wr(p, s):
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with io.open(p, "w", encoding="utf-8", newline="\n") as f:
        f.write(s)


def at(hm, day=None):
    return "%sT%s:00" % (day or TODAY, hm)


def mk_root(comps=(), mut=None):
    """임시 루트 — 코드 사본 + 합성 등록부 · 모의 발신기 · 가짜 수집기. mut = [(상대경로, 찾을 문자열, 바꿀 문자열)] — 치환 성사 단정."""
    T = tempfile.mkdtemp(prefix="scn_dd_e2e_").replace("\\", "/")
    for rel in CODE:
        dst = os.path.join(T, rel); os.makedirs(os.path.dirname(dst), exist_ok=True); shutil.copyfile(os.path.join(REAL, rel), dst)
    for rel, a, b in (mut or []):
        p = os.path.join(T, rel); s = io.open(p, encoding="utf-8", newline="").read()
        if s.count(a) < 1:
            raise SystemExit("돌연변이 치환 실패: %s :: %r" % (rel, a[:80]))
        io.open(p, "w", encoding="utf-8", newline="").write(s.replace(a, b))
        if io.open(p, encoding="utf-8", newline="").read().count(b) < 1:
            raise SystemExit("돌연변이 치환 미반영: %s" % rel)
    wr(T + "/02_Infrastructure/hooks/qvest_hook_router.py", "# 루트 표지(resolve_project.sh marker) — 시험 임시 루트\n")
    os.makedirs(T + "/.cache/scheduler_alerts", exist_ok=True)
    wr(T + "/06_Registry/superfan_components.json", json.dumps(
        {"schema": "superfan_components_v1", "default_max_event_age_h": 48, "doc": "test", "components": list(comps)}, ensure_ascii=False))
    wr(T + "/mode_rscript", "ok"); wr(T + "/mode_notify", "ok")
    # 모의 Rscript(task_health 발신) — 성공이면 sched_ok.jsonl · 실패면 sched_fail.jsonl 에 한 줄 + 종료 3
    wr(T + "/mock_rscript.sh",
       "#!/bin/bash\nm=$(cat '%s/mode_rscript')\n'%s' -c 'import json,os;print(json.dumps({k:os.environ.get(k,\"\") for k in (\"SA_COMP\",\"SA_REASON\",\"SA_DETAIL\")},ensure_ascii=False))' >> '%s/sched_'\"$m\"'.jsonl'\n"
       "[ \"$m\" = ok ] || exit 3\nexit 0\n" % (T, PY, T))
    # 모의 Superfan 발신기 — 모드 ok/fail · payload 보관
    wr(T + "/mock_notify.py",
       "import json,sys,os\nT=os.path.dirname(os.path.abspath(__file__))\nm=open(os.path.join(T,'mode_notify')).read().strip()\n"
       "p=json.load(open(sys.argv[1],encoding='utf-8'))\nd=os.path.join(T,'sent_'+m);os.makedirs(d,exist_ok=True)\n"
       "json.dump(p,open(os.path.join(d,'%03d.json'%len(os.listdir(d))),'w',encoding='utf-8'),ensure_ascii=False)\n"
       "[print('SFN\\t%s\\t%s'%(g['component'],m)) for g in p['groups']]\n")
    # 가짜 수집기(scheduler_task_health.ps1 대역) — fixture.json 을 산출 경로로 · measured_at = 시험 기준 시각
    wr(T + "/mock_collector.py",
       "import json,sys,os,io\nT=os.path.dirname(os.path.abspath(__file__))\nd=json.load(io.open(os.path.join(T,'fixture.json'),encoding='utf-8'))\n"
       "d['measured_at']=os.environ['QVEST_ALERT_DEDUP_NOW'].replace(' ','T')+':00'\n"
       "io.open(sys.argv[1],'w',encoding='utf-8').write(json.dumps(d,ensure_ascii=False))\n")
    wr(T + "/empty.Renviron", "")
    # 가짜 작업 스케줄러 조회(QVEST_SUPERFAN_TASK_QUERY_CMD) — 기본 'fail'(종료 2 = 직접 조회 실패 → task_health 산출로 물러남 · S1~S7 은 그 경로) ·
    # 'ok' = query_states.json 의 상태 · 'partial' = 첫 이름만 응답(누락 = 실패로 봐야 한다). 운영 스케줄러는 묻지 않는다.
    wr(T + "/mode_query", "fail"); wr(T + "/query_states.json", "{}")
    wr(T + "/mock_query.py",
       "import json,sys,os,io\nT=os.path.dirname(os.path.abspath(__file__))\nm=open(os.path.join(T,'mode_query')).read().strip()\n"
       "io.open(os.path.join(T,'query_calls.log'),'a',encoding='utf-8').write(' '.join(sys.argv[1:])+'\\n')\n"
       "if m=='fail': sys.exit(2)\nst=json.load(io.open(os.path.join(T,'query_states.json'),encoding='utf-8'))\n"
       "names=sys.argv[1:] if m=='ok' else sys.argv[1:2]\n"
       "[print('%s|%s'%(n,st.get(n,'Missing'))) for n in names]\n")
    return T


def env(T, hm):
    now = "%s %s" % (TODAY, hm)
    e = dict(os.environ)
    for k in ("QVEST_SUPERFAN_REGISTRY_PATH", "QVEST_SUPERFAN_WATCH_PATH", "QVEST_SUPERFAN_TASK_HEALTH_PATH", "QVEST_NO_ALERT",
              "QVEST_ALERT_FORCE", "QVEST_SUPERFAN_TASK_HEALTH_MAX_AGE_H", "QVEST_ALERT_DEDUP_CLAIM_STALE_SEC", "TODAY"):
        e.pop(k, None)
    e.update({"QVEST_SUPERFAN_NOW": now, "QVEST_ALERT_DEDUP_NOW": now, "QVEST_ALERT_DEDUP_PATH": T + "/.cache/alert_dedup.json",
              "QVEST_SUPERFAN_NOTIFY_CMD": "%s %s/mock_notify.py" % (PY, T), "QVEST_SCHED_ALERT_RSCRIPT": T + "/mock_rscript.sh",
              "QVEST_TH_COLLECTOR_CMD": "%s %s/mock_collector.py" % (PY, T), "QVEST_SUPERFAN_TASK_QUERY_CMD": "%s %s/mock_query.py" % (PY, T), "QVEST_PY": PY, "QVEST_UNATTENDED": "1",
              "BASE": T, "QM_ROOT": T, "CLAUDE_PROJECT_DIR": T, "PYTHONUTF8": "1", "R_ENVIRON_USER": T + "/empty.Renviron",
              "TG_BOT_TOKEN": "TEST_TOKEN_NOT_REAL", "TG_CHAT_ID": "0"})
    return e


def task(name, **kw):
    t = {"task": name, "state": "Ready", "enabled": True, "rc": 0, "rc_label": "ok", "last_run": at("00:05"), "age_days": 0.1,
         "max_stale_days": 2, "next_run": "2099-01-01T00:05:00", "time_scheduled": True}
    t.update(kw); return t


def fixture(T, tasks):
    wr(T + "/fixture.json", json.dumps({"schema_version": 2, "tasks": tasks}, ensure_ascii=False))


def th(T, hm, extra=None):
    e = env(T, hm); e.update(extra or {})
    r = subprocess.run([BASH, T + "/02_Infrastructure/ops/scheduler_task_health.sh", "--quiet"], env=e, capture_output=True,
                       text=True, encoding="utf-8", errors="replace", timeout=300)
    return r.stdout + r.stderr


def watch(T, hm):
    r = subprocess.run([PY, T + "/02_Infrastructure/programs/superfan_watch.py", "scan", "--notify"], env=env(T, hm),
                       capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=300)
    return r.stdout + r.stderr


def dd_cli(T, hm, *args):
    r = subprocess.run([PY, T + "/02_Infrastructure/ops/alert_dedup.py"] + list(args), env=env(T, hm), capture_output=True,
                       text=True, encoding="utf-8", errors="replace", timeout=60)
    return (r.stdout or "").strip()


def store(T):
    p = T + "/.cache/alert_dedup.json"
    return json.load(io.open(p, encoding="utf-8"))["causes"] if os.path.exists(p) else {}


def sched(T, mode="ok"):
    p = "%s/sched_%s.jsonl" % (T, mode)
    return [json.loads(l) for l in io.open(p, encoding="utf-8") if l.strip()] if os.path.exists(p) else []


def sf(T, mode="ok"):
    d = "%s/sent_%s" % (T, mode)
    return [g["component"] for f in sorted(os.listdir(d)) for g in json.load(io.open(os.path.join(d, f), encoding="utf-8"))["groups"]] \
        if os.path.isdir(d) else []


def set_mode(T, which, m):
    wr("%s/mode_%s" % (T, which), m)


def comp_fresh(cid, task_name, logrel, cause="task_run"):
    r = {"id": "alive", "kind": "freshness", "file": logrel, "max_age_h": 8, "severity": "fail"}
    if cause:
        r["cause"] = cause
    return {"id": cid, "name": cid, "dossier": "x", "sched_task": task_name, "rules": [r]}


# ── 시나리오(돌연변이 재사용을 위해 함수 · 반환 = 판정 dict) ──────────────────────────
def s1(mut=None):
    T = mk_root(mut=mut)
    fixture(T, [task("Qvest_Weekly", rc=0, last_run=at("08:00", "2026-01-01"), age_days=12.0, max_stale_days=9),
                task("Qvest_Loop", rc=0, last_run=at("11:00"), age_days=0.04, next_run=None)])
    for hm in ("12:00", "16:00", "20:00"):
        th(T, hm)
    n_stale = len(sched(T))
    # 경보 뒤 건강하게 다시 돎(20:40 실행 · 나이 정상 · 다음 실행 있음) → 해소
    fixture(T, [task("Qvest_Weekly", rc=0, last_run=at("20:40"), age_days=0.01, max_stale_days=9),
                task("Qvest_Loop", rc=0, last_run=at("20:40"), age_days=0.01)])
    th(T, "21:00")
    res = store(T)
    resolved = all((res.get(k) or {}).get("state") in (None, "released") for k in ("task:Qvest_Weekly", "task:Qvest_Loop"))
    fixture(T, [task("Qvest_Weekly", rc=2, rc_label="exit_2", last_run=at("21:30"), age_days=0.01, max_stale_days=9),
                task("Qvest_Loop", rc=0, last_run=at("20:40"), age_days=0.01)])
    th(T, "22:00")
    return {"n_stale": n_stale, "resolved": resolved, "n_total": len(sched(T)), "T": T}


def s2a(mut=None):
    T = mk_root(mut=mut)
    fixture(T, [task("Qvest_Daily", rc=2, rc_label="exit_2", last_run=at("00:05"))])
    set_mode(T, "rscript", "fail"); th(T, "12:00")
    key_after_fail = store(T).get("task:Qvest_Daily")
    set_mode(T, "rscript", "ok"); th(T, "20:00")
    return {"fail": len(sched(T, "fail")), "ok": len(sched(T)), "key_after_fail": key_after_fail,
            "confirmed": (store(T).get("task:Qvest_Daily") or {}).get("state") == "confirmed"}


def s2b(mut=None):
    T = mk_root([comp_fresh("dr", "Qvest_Daily", "logs/dr.log")], mut=mut)
    fixture(T, [task("Qvest_Daily", rc=2, rc_label="exit_2", last_run=at("00:05"))])
    set_mode(T, "rscript", "fail"); th(T, "12:00")
    watch(T, "12:20")                                                      # 20분 뒤(미확정 키가 남았다면 아직 '살아 있는 보유자' 나이)
    return {"sf": sf(T), "fail": len(sched(T, "fail"))}


def s2c(mut=None):
    T = mk_root([comp_fresh("c1", "Qvest_Shared", "logs/c1.log"), comp_fresh("c2", "Qvest_Shared", "logs/c2.log")], mut=mut)
    set_mode(T, "notify", "fail"); watch(T, "10:00")
    after_fail = store(T).get("task:Qvest_Shared")
    fixture(T, [task("Qvest_Shared", rc=2, rc_label="exit_2", last_run=at("09:00"))])
    th(T, "10:10")                                                         # 10분 뒤 — 놓지 않았다면 DUP
    n_th = len(sched(T))
    set_mode(T, "notify", "ok"); watch(T, "11:30")                         # task_health 가 확정 → 양보한 둘 다 다시 안 보냄
    return {"after_fail": after_fail, "n_th": n_th, "sf_ok": sf(T), "sf_fail": sf(T, "fail")}


def s3(mut=None):
    comps = [{"id": "daily_refresh", "name": "dr", "dossier": "x", "sched_task": "Qvest_DailyRefresh",
              "rules": [{"id": "run_failed", "kind": "log_patterns", "files": "logs/dr.log",
                         "patterns": [{"severity": "fail", "regex": "Done — ★실패", "label": "실패 스텝"}]}]},
             {"id": "factor_db", "name": "fdb", "dossier": "x", "sched_task": "Qvest_DailyRefresh",
              "rules": [{"id": "build_gate", "kind": "log_patterns", "files": "logs/dr.log",
                         "patterns": [{"severity": "fail", "regex": r"\[6a-gate\].*회귀 [1-9]", "label": "배출 회귀"}]}]},
             {"id": "book_tracking", "name": "book", "dossier": "x", "sched_task": "Qvest_MorningBrief",
              "rules": [{"id": "mtm_errors", "kind": "log_patterns", "files": "logs/mb.log",
                         "patterns": [{"severity": "fail", "regex": r"\[nolayer4-daily\].*실패", "label": "일별 평가 실패"}]}]}]
    T = mk_root(comps, mut=mut)
    fixture(T, [task("Qvest_DailyRefresh", rc=2, rc_label="exit_2", last_run=at("00:03")),
                task("Qvest_MorningBrief", rc=267014, rc_label="terminated_by_user_or_limit", last_run=at("07:10"))])
    th(T, "12:00")                                                         # task_health 가 두 작업 키를 먼저 잡고 보냄
    wr(T + "/logs/dr.log", "[%s 00:10:00] [6a-gate] 배출 회귀 3 — 거부\n[%s 00:40:00] === Daily Refresh v2 Done — ★실패 1스텝: [6a] @ x ===\n" % (TODAY, TODAY))
    wr(T + "/logs/mb.log", "[%s 07:30:00] [nolayer4-daily] 평가 실패 Error\n" % TODAY)
    watch(T, "12:30")
    return {"n_th": len(sched(T)), "sf": sorted(sf(T))}


def s4(mut=None):
    mc = [comp_fresh("morning_chain", "Qvest_MorningBrief", "logs/morning_run.log")]
    fx = [task("Qvest_MorningBrief", rc=267014, rc_label="terminated_by_user_or_limit", last_run=at("07:10"))]
    # 순서 1: task_health 먼저 → Superfan 양보
    T1 = mk_root(mc, mut=mut); fixture(T1, fx); th(T1, "12:01"); watch(T1, "12:30"); watch(T1, "13:30")
    # 순서 2: Superfan 먼저 → task_health DUP
    T2 = mk_root(mc, mut=mut); fixture(T2, fx); watch(T2, "11:17"); th(T2, "12:01"); th(T2, "20:00")
    # 양보 → 상대가 놓음 → 다시 잡음
    T3 = mk_root(mc, mut=mut)
    dd_cli(T3, "11:10", "claim", "--source", "sched:task_health", "task:Qvest_MorningBrief")
    watch(T3, "11:17"); y_first = len(sf(T3))
    dd_cli(T3, "11:20", "release", "--source", "sched:task_health", "task:Qvest_MorningBrief")
    watch(T3, "12:17"); y_after = len(sf(T3))
    # 죽은 보유자(09:00 claim · 확정도 놓기도 없음) → 11:17 Superfan 이 가져감
    T4 = mk_root(mc, mut=mut)
    dd_cli(T4, "09:00", "claim", "--source", "sched:task_health", "task:Qvest_MorningBrief")
    watch(T4, "11:17")
    return {"o1": (len(sched(T1)), sf(T1)), "o2": (len(sched(T2)), sf(T2)), "y_first": y_first, "y_after": y_after, "stale_take": sf(T4)}


def s5(mut=None):
    T = mk_root([comp_fresh("lane", "Qvest_Off", "logs/lane.log")], mut=mut)
    fixture(T, [task("Qvest_Off", state="Disabled", enabled=False, rc=0, last_run=at("08:00", "2026-01-01"), age_days=300.0)])
    th(T, "12:00")                                                         # 이 기계에서 잰 신선한 측정을 운영 경로로 쓴다
    h = json.load(io.open(T + "/06_Registry/scheduler_task_health.json", encoding="utf-8"))
    watch(T, "12:30")
    return {"n_th": len(sched(T)), "sf": sf(T), "measured_on": h.get("measured_on")}


def s6(mut=None):
    out = {}
    for case, patch in (("other_machine", {"measured_on": "OTHER-PC-" + ME}), ("old", {"measured_at": at("12:00", "2026-01-01")}),
                        ("no_machine", {"measured_on": None})):
        T = mk_root([comp_fresh("lane", "Qvest_Off", "logs/lane.log")], mut=mut)
        h = {"schema_version": 2, "measured_at": at("12:00"), "measured_on": ME,
             "tasks": [task("Qvest_Off", state="Disabled", enabled=False)]}
        h.update(patch)
        if h["measured_on"] is None:
            h.pop("measured_on")
        wr(T + "/06_Registry/scheduler_task_health.json", json.dumps(h))
        watch(T, "12:30")
        out[case] = sf(T)
    # 대조: 같은 기계 · 신선 → 억제
    T = mk_root([comp_fresh("lane", "Qvest_Off", "logs/lane.log")], mut=mut)
    wr(T + "/06_Registry/scheduler_task_health.json", json.dumps({"measured_at": at("12:00"), "measured_on": ME,
                                                                   "tasks": [task("Qvest_Off", state="Disabled", enabled=False)]}))
    watch(T, "12:30"); out["trusted"] = sf(T)
    return out


def s8(mut=None):
    """꺼짐 직접 조회 — task_health 산출은 낡았다(17시간 초과 · 같은 기계 · 꺼짐 표시)고 둔다: 판정은 조회만이 바꾼다."""
    out = {}
    def root():
        T = mk_root([comp_fresh("lane", "Qvest_Off", "logs/lane.log")], mut=mut)
        wr(T + "/06_Registry/scheduler_task_health.json", json.dumps({"measured_at": at("12:00", "2026-01-01"), "measured_on": ME,
                                                                       "tasks": [task("Qvest_Off", state="Disabled", enabled=False)]}))
        return T
    def ws(T):
        return json.load(io.open(T + "/.cache/superfan_watch.json", encoding="utf-8"))
    def q(T, mode, state=None):
        set_mode(T, "query", mode)
        if state:
            wr(T + "/query_states.json", json.dumps({"Qvest_Off": state}))
    # a 조회 = 꺼짐 · 측정 낡음 → 0통
    T = root(); q(T, "ok", "Disabled"); watch(T, "12:30")
    out["a"] = (sf(T), ws(T).get("task_state", {}).get("source"),
                os.path.exists(T + "/query_calls.log") and "Qvest_Off" in io.open(T + "/query_calls.log", encoding="utf-8").read())
    # b 조회 실패 · 측정 낡음 → 1통(fail-closed)
    T = root(); q(T, "fail"); watch(T, "12:30"); out["b"] = (sf(T), ws(T).get("task_state", {}).get("source"))
    # b2 응답 누락(다른 이름만) → 실패로 보고 물러남 → 1통
    T = mk_root([comp_fresh("lane", "Qvest_Off", "logs/lane.log"), comp_fresh("aaa", "Qvest_Aaa", "logs/aaa.log")], mut=mut)
    wr(T + "/query_states.json", json.dumps({"Qvest_Off": "Disabled", "Qvest_Aaa": "Disabled"})); set_mode(T, "query", "partial")
    watch(T, "12:30"); out["b2"] = sorted(sf(T))
    # c 조회 = 켜짐 · 로그 낡음 → 1통 → d 꺼짐 확인 → 해소 · 원인 키 해소 → e 다음 실행(여전히 꺼짐) 재개방 없음 → f 다시 켜짐 → 1통 더
    T = root(); q(T, "ok", "Ready"); watch(T, "12:30")
    out["c"] = sf(T); out["c_key"] = (store(T).get("task:Qvest_Off") or {}).get("state")
    q(T, "ok", "Disabled"); watch(T, "13:30")
    W = ws(T); an = [a for a in W["anomalies"].values() if a["component"] == "lane"]
    out["d"] = ([a["status"] for a in an], (store(T).get("task:Qvest_Off") or {}).get("state"), W.get("task_state", {}).get("source"))
    watch(T, "14:30"); W = ws(T)
    out["e"] = ([a["status"] for a in W["anomalies"].values() if a["component"] == "lane"], sf(T))
    q(T, "ok", "Ready"); watch(T, "15:30"); out["f"] = sf(T)
    return out


def s7(mut=None):
    """실제 Rscript 로 생성 R 을 돌린다 — 가짜 telegram_notify.R(임시 루트) 이 TG_MODE 대로 ok 를 돌려준다."""
    res = {}
    for mode in ("FALSE", "TRUE"):
        T = mk_root(mut=mut)
        wr(T + "/02_Infrastructure/telegram/telegram_notify.R",
           "tg_agent_brief <- function(...) { cat('FAKE_TG_CALLED\\n'); list(ok = %s, error = 'fake 429') }\n" % mode)
        sh = '. "%s/02_Infrastructure/ops/_sched_failure_classify.sh"; sched_alert_emit task_health rtest "detail" "task:Qx" "요약"; echo "RESULT=$SCHED_ALERT_LAST_RESULT"' % T
        e = env(T, "12:00"); e.pop("QVEST_SCHED_ALERT_RSCRIPT", None)
        r = subprocess.run([BASH, "-c", sh], env=e, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=300)
        mk = [f for f in os.listdir(T + "/.cache/scheduler_alerts") if f.startswith("task_health_rtest_")]
        mtxt = io.open(os.path.join(T + "/.cache/scheduler_alerts", mk[0]), encoding="utf-8").read() if mk else ""
        log = io.open(T + "/.cache/scheduler_alerts/_tg_alert_send.log", encoding="utf-8", errors="replace").read() \
            if os.path.exists(T + "/.cache/scheduler_alerts/_tg_alert_send.log") else ""
        res[mode] = {"result": (r.stdout or "").strip().splitlines()[-1:] , "key": store(T).get("task:Qx"),
                     "marker_failed": "send_failed=" in mtxt, "called": "FAKE_TG_CALLED" in log}
    return res


# ── 본 시험 ─────────────────────────────────────────────────────────────────
print("== S1 정체 rc 0 · 트리거 만료 rc 0 — 하루 1통 · 건강한 재실행 뒤 해소 ==")
r1 = s1()
chk("S1a 정체 · 트리거 만료(rc 0) 작업으로 task_health 3회 → 정확히 1통", r1["n_stale"] == 1, str(r1["n_stale"]))
chk("S1b 경보 뒤 건강하게 다시 돎 → 원인 키 해소", r1["resolved"], json.dumps(store(r1["T"]), ensure_ascii=False)[:300])
chk("S1c 해소 뒤 같은 날 새 실패 → 1통 더(합계 2)", r1["n_total"] == 2, str(r1["n_total"]))

print("== S2 발송 실패 ==")
r2a = s2a()
chk("S2a-1 발송 실패 → 원인 키를 완전히 놓음(저장소에 미확정 키 없음)", (r2a["key_after_fail"] or {}).get("state") in (None, "released"), str(r2a["key_after_fail"]))
chk("S2a-2 같은 날 다음 실행이 다시 보냄(실패 1 · 성공 1 · 확정)", r2a["fail"] == 1 and r2a["ok"] == 1 and r2a["confirmed"], str(r2a))
r2b = s2b()
chk("S2b task_health 발송 실패 → 같은 날 Superfan 의 같은 원인 경보가 나감", r2b["fail"] == 1 and r2b["sf"] == ["dr"], str(r2b))
r2c = s2c()
chk("S2c-1 공유 키 대표 발송 실패 → release 가 키를 완전히 놓음(건수 깎기 아님)", (r2c["after_fail"] or {}).get("state") in (None, "released"), str(r2c["after_fail"]))
chk("S2c-2 같은 날 task_health 가 그 원인을 보냄", r2c["n_th"] == 1, str(r2c))
chk("S2c-3 확정 뒤 양보한 두 구성요소는 다시 안 보냄(원인 1통)", r2c["sf_ok"] == [] and r2c["sf_fail"] == ["c1"], str(r2c))

print("== S3 작업을 공유하는 구성요소의 서로 다른 실패 ==")
r3 = s3()
chk("S3 task_health 가 작업 키를 먼저 잡아도 구성요소 고유 실패 3건은 각자 나감", r3["n_th"] == 1 and r3["sf"] == ["book_tracking", "daily_refresh", "factor_db"], str(r3))

print("== S4 같은 실패 · 두 발신기 ==")
r4 = s4()
chk("S4a task_health 먼저 → Superfan 양보(합계 1통 · 다음 시간도 0)", r4["o1"] == (1, []), str(r4["o1"]))
chk("S4b Superfan 먼저 → task_health 두 번 다 DUP(합계 1통)", r4["o2"] == (0, ["morning_chain"]), str(r4["o2"]))
chk("S4c 상대가 보내는 중(미확정)이면 양보(0통)", r4["y_first"] == 0, str(r4["y_first"]))
chk("S4d 상대가 놓으면 양보한 쪽이 다음 실행에 다시 잡아 보냄(1통)", r4["y_after"] == 1, str(r4["y_after"]))
chk("S4e 죽은 보유자(2시간 넘은 미확정 키) → 다음 claim 이 가져가 보냄", r4["stale_take"] == ["morning_chain"], str(r4["stale_take"]))

print("== S5 꺼진 작업 ==")
r5 = s5()
chk("S5a task_health 가 측정 기계를 기록", r5["measured_on"] == ME, str(r5["measured_on"]))
chk("S5b 꺼진 작업(이 기계 · 신선) → task_health 0통 · Superfan 0통", r5["n_th"] == 0 and r5["sf"] == [], str(r5))

print("== S6 믿을 수 없는 측정 = 억제하지 않음 ==")
r6 = s6()
chk("S6a 다른 기계가 잰 '꺼짐' → 억제 안 함(1통)", r6["other_machine"] == ["lane"], str(r6))
chk("S6b 낡은 측정(17시간 초과) → 억제 안 함(1통)", r6["old"] == ["lane"], str(r6))
chk("S6c 기계 표식 없는 측정 → 억제 안 함(1통)", r6["no_machine"] == ["lane"], str(r6))
chk("S6d 대조: 같은 기계 · 신선 → 억제(0통)", r6["trusted"] == [], str(r6))

print("== S8 꺼짐 직접 조회(측정 파일 신선도와 무관) ==")
r8 = s8()
chk("S8a 측정 낡음 + 직접 조회 '꺼짐' → 0통 · 근거 direct · 그 작업을 물었음", r8["a"] == ([], "direct", True), str(r8["a"]))
chk("S8b 직접 조회 실패 + 측정 낡음 → 1통(fail-closed · 근거 none)", r8["b"] == (["lane"], "none"), str(r8["b"]))
chk("S8b2 응답 누락(물은 이름 일부만) = 조회 실패 → 둘 다 경보", r8["b2"] == ["aaa", "lane"], str(r8["b2"]))
chk("S8c 직접 조회 '켜짐' + 로그 낡음 → 1통 · 원인 키 확정", r8["c"] == ["lane"] and r8["c_key"] == "confirmed", str(r8))
chk("S8d 꺼짐 확인 → 열린 낡음 이상 해소 · 원인 키 해소 · 근거 direct", r8["d"][0] == ["resolved"] and r8["d"][1] in (None, "released")
    and r8["d"][2] == "direct", str(r8["d"]))
chk("S8e 다음 실행(꺼짐 유지) → 재개방 없음 · 추가 발송 없음", r8["e"] == (["resolved"], ["lane"]), str(r8["e"]))
chk("S8f 다시 켜진 뒤 낡음 → 같은 날 1통 더(합계 2)", r8["f"] == ["lane", "lane"], str(r8["f"]))

print("== S7 생성 R 종료 코드 계약(실제 Rscript · 가짜 발송기) ==")
r7 = s7()
chk("S7a ok = FALSE → 결과 send_failed · 키 놓음 · 마커 실패 표식", r7["FALSE"]["called"] and r7["FALSE"]["result"] == ["RESULT=send_failed"]
    and (r7["FALSE"]["key"] or {}).get("state") in (None, "released") and r7["FALSE"]["marker_failed"], str(r7["FALSE"]))
chk("S7b ok = TRUE → 결과 sent · 키 확정 · 실패 표식 없음", r7["TRUE"]["called"] and r7["TRUE"]["result"] == ["RESULT=sent"]
    and (r7["TRUE"]["key"] or {}).get("state") == "confirmed" and not r7["TRUE"]["marker_failed"], str(r7["TRUE"]))

# ── M 돌연변이 — 수리를 되돌린 사본 ──────────────────────────────────────────────
print("== M 돌연변이(수리마다 1개 · 치환 성사 단정) ==")
DD, SH, CL, SW = CODE[1], CODE[3], CODE[2], CODE[0]
m = s2c([(DD, "            s = _stub(e)\n            if s:\n                C[k0] = s\n            else:\n                C.pop(k0, None)\n        _save(p, d)\n\n\ndef settled",
          "            if int(e.get(\"count\", 1)) > 1:\n                e[\"count\"] = int(e[\"count\"]) - 1; continue\n            C.pop(k0, None)\n        _save(p, d)\n\n\ndef settled")])
chk("M1 release = 건수 깎기(1차판) 사본 → S2c-2 빨강(task_health DUP · 0통)", m["n_th"] == 0, str(m))
m = s2b([(CL, 'release --source "sched:$comp" $ckeys >/dev/null 2>&1', 'true >/dev/null 2>&1')])
chk("M2 셸 발송 실패 release 제거 사본 → S2b 빨강(Superfan 양보 · 0통)", m["sf"] == [], str(m))
m = s2a([(SH, 'if [ "${SCHED_ALERT_LAST_RESULT:-}" = "send_failed" ]; then', 'if false; then')])
chk("M3 기보고 원장 되돌림 제거 사본 → S2a 빨강(다음 실행 기보고로 접힘 · 성공 0)", m["ok"] == 0, str(m))
m = s7([(CL, 'quit(save = "no", status = 3L)', 'invisible(NULL)')])
chk("M4 생성 R 실패 종료 제거 사본 → S7a 빨강(실패가 sent 로 · 키 확정)", m["FALSE"]["result"] == ["RESULT=sent"], str(m["FALSE"]))
m = s1([(DD, 'if t.get("enabled") is False or _healthy_after_alert(t, e, stale_names):',
         'if t.get("enabled") is False or (int(t.get("rc") or 0) == 0 and t.get("rc_label") != "never_run"):')])
chk("M5 resolve-healthy = rc 0 만(1차판) 사본 → S1a 빨강(실행마다 1통)", m["n_stale"] == 3, str(m["n_stale"]))
m = s3([(SW, '    if r.get("cause") == "task_run" and comp.get("sched_task"):', '    if comp.get("sched_task"):')])
chk("M6 작업 단위 원인 키(1차판) 사본 → S3 빨강(구성요소 고유 실패가 묻힘)", m["sf"] == [], str(m))
m = s4([(SW, "    have = {id(a) for a in pend}; out = []", "    return []\n    have = {id(a) for a in pend}; out = []")])
chk("M7 양보 재시도 제거 사본 → S4d 빨강(상대가 놓아도 0통)", m["y_after"] == 0, str(m["y_after"]))
m = s6([(SW, '        if h.get("measured_on") != _machine():\n            return {}', '        if False:\n            return {}')])
chk("M8 측정 기계 확인 제거 사본 → S6a 빨강(다른 기계 '꺼짐'으로 억제)", m["other_machine"] == [], str(m))
m = s6([(SW, "        if not (-0.25 <= age_h <= TASK_HEALTH_MAX_AGE_H):", "        if False:")])
chk("M9 측정 신선도 확인 제거 사본 → S6b 빨강(낡은 '꺼짐'으로 억제)", m["old"] == [], str(m))
m = s4([(DD, ' or (now - ca).total_seconds() > CLAIM_STALE_SEC)', ')')])
chk("M10 죽은 보유자 인계 제거 사본 → S4e 빨강(0통)", m["stale_take"] == [], str(m["stale_take"]))

m = s8([(SW, "    st, why = _task_states_direct(names)\n    if st is not None:", "    st, why = None, \"mutant\"\n    if st is not None:")])
chk("M11 직접 조회 제거 사본 → S8a 빨강(낡은 측정 = 모름 → 꺼진 작업 경보 1통)", m["a"][0] == ["lane"], str(m["a"]))
m = s8([(SW, "        if off_keys:\n            dd = _dedup()", "        if False:\n            dd = _dedup()")])
chk("M12 꺼짐 해소 때 원인 키 해소 제거 사본 → S8f 빨강(다시 켜진 뒤 낡음이 같은 날 원인 키에 접혀 0통)", m["f"] == ["lane"], str(m["f"]))
m = s8([(SW, "    if seen != set(names):", "    if False:")])
chk("M13 응답 누락 검사 제거 사본 → S8b2 빨강(빠진 이름이 '켜짐'으로 · 응답한 첫 이름(Qvest_Aaa · 꺼짐)만 억제 → lane 1통)", m["b2"] == ["lane"], str(m["b2"]))

print(json.dumps({"test": "scn_tg_alert_dedup_e2e", "pass": P, "fail": F, "total": P + F}))
sys.exit(1 if F else 0)
