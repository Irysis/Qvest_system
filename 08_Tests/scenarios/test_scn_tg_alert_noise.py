"""test_scn_tg_alert_noise.py — 무인 경보 소음 정책 시나리오 시험 (2026-11-10 감사 레인 B · SKILL qvest-telegram §0.4 집행)

임시 루트에 실제 코드 사본(superfan_watch.py · alert_dedup.py · _sched_failure_classify.sh · superfan_notify.R 은 실제 경로 그대로)을 두고
돌린다. 발신은 전부 모의(QVEST_SUPERFAN_NOTIFY_CMD · QVEST_SCHED_ALERT_RSCRIPT) · 렌더 확인만 QVEST_TG_DRY_RUN=1 + 가짜 토큰. 네트워크 0.

  D 같은 원인 두 발신처 → 1통 (task_health 경보가 먼저 → Superfan 아침 체인은 억제 · 같은 날 task_health 재발도 억제)
  X 꺼진 구성요소 무경보(작업 Disabled → 신선도 규칙 안 잼) · 대조: 켜진 작업의 같은 규칙은 경보 · 작업 미수록 = 경보(fail-closed)
  B 본문 = 요약 한 문장 + 위치 · 로그 원문 줄(가짜 비밀 포함) 없음 — superfan_notify.R 실제 렌더(dry run)
  P 사유별 문구(267014 · 종료 코드 · 한 번도 안 돎 · 다음 실행 없음)
  R 원인 해소(다음 정상 실행) 뒤 재발 → 다시 1통
  Q sched_alert_emit 의 값 전달 = 환경변수(따옴표 · 백슬래시가 든 detail 이 그대로 · R 구문 무결)
  L 아침 1계층 상태 칸 — 판독 불가 칸이 체인을 죽이지 않음(정적)
  M 가드마다 소스 텍스트 치환 돌연변이 1개(치환 성사 단정 → 대응 축이 빨개짐)
마지막 줄 = {"test":...,"pass":N,"fail":N,"total":N}
"""
import io, json, os, re, shutil, subprocess, sys, tempfile

REAL = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PY = sys.executable
BASH = r"C:\Program Files\Git\bin\bash.exe" if os.name == "nt" else "bash"
P = F = 0


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


def mk_root(mut=None):
    """임시 루트 — 코드 사본 + 합성 등록부 · 작업 상태 · 로그. mut = {상대경로: (찾을 문자열, 바꿀 문자열)}."""
    T = tempfile.mkdtemp(prefix="scn_noise_").replace("\\", "/")
    for rel in ("02_Infrastructure/programs/superfan_watch.py", "02_Infrastructure/ops/alert_dedup.py",
                "02_Infrastructure/ops/_sched_failure_classify.sh", "02_Infrastructure/ops/scheduler_task_health.sh"):
        dst = os.path.join(T, rel); os.makedirs(os.path.dirname(dst), exist_ok=True); shutil.copyfile(os.path.join(REAL, rel), dst)
    for rel, (a, b) in (mut or {}).items():
        p = os.path.join(T, rel); s = io.open(p, encoding="utf-8", newline="").read()
        n = s.count(a)
        if n < 1:
            raise SystemExit("돌연변이 치환 실패: %s :: %r" % (rel, a[:60]))
        io.open(p, "w", encoding="utf-8", newline="").write(s.replace(a, b))
    os.makedirs(os.path.join(T, ".cache/scheduler_alerts"), exist_ok=True)
    reg = {"schema": "superfan_components_v1", "default_max_event_age_h": 48, "doc": "test", "components": [
        {"id": "morning_chain", "name": "아침 체인", "dossier": "x", "sched_task": "Qvest_MorningBrief",
         "rules": [{"id": "done_today", "kind": "expect_today", "file": "logs/morning_run.log", "after": "11:00",
                    "pattern": "morning_run done @ {dow} {mon} {dd2}", "severity": "fail"},
                   {"id": "run_alerts", "kind": "log_patterns", "files": "logs/morning_run.log",
                    "patterns": [{"severity": "fail", "regex": "Execution halted", "label": "R 오류"}]}]},
        {"id": "replication_lane", "name": "충실구현 레인", "dossier": "x", "sched_task": "Qvest_ReinforceAutoLoop",
         "rules": [{"id": "lane_alive", "kind": "freshness", "file": "logs/reinforce_auto_{YYYYMMDD}.log", "max_age_h": 8, "severity": "fail"}]},
        {"id": "lane_on", "name": "켜진 레인(대조)", "dossier": "x", "sched_task": "Qvest_OnTask",
         "rules": [{"id": "lane_alive", "kind": "freshness", "file": "logs/on_{YYYYMMDD}.log", "max_age_h": 8, "severity": "fail"}]},
        {"id": "lane_unknown", "name": "미수록 작업(대조)", "dossier": "x", "sched_task": "Qvest_NotInHealth",
         "rules": [{"id": "lane_alive", "kind": "freshness", "file": "logs/unk_{YYYYMMDD}.log", "max_age_h": 8, "severity": "fail"}]},
        {"id": "free", "name": "독립 구성요소", "dossier": "x",
         "rules": [{"id": "f", "kind": "json_field", "file": "state.json", "path": "status", "bad_values": ["failed"], "severity": "fail"}]}]}
    wr(os.path.join(T, "06_Registry/superfan_components.json"), json.dumps(reg, ensure_ascii=False))
    health = {"tasks": [{"task": "Qvest_MorningBrief", "enabled": True, "rc": 267014, "rc_label": "terminated_by_user_or_limit"},
                        {"task": "Qvest_ReinforceAutoLoop", "enabled": False, "rc": 0},
                        {"task": "Qvest_OnTask", "enabled": True, "rc": 0}]}
    wr(os.path.join(T, "06_Registry/scheduler_task_health.json"), json.dumps(health))
    wr(os.path.join(T, "logs/morning_run.log"), "================ morning_run @ Tue Nov 10 07:10:15 2026 (trigger=cron) ================\n")
    wr(os.path.join(T, "state.json"), json.dumps({"status": "failed"}))
    # 모의 발신기 — payload 를 보관하고 구성요소마다 ok
    wr(os.path.join(T, "mock_notify.py"),
       "import json,sys,os\np=json.load(open(sys.argv[1],encoding='utf-8'))\n"
       "d=os.path.join(os.path.dirname(os.path.abspath(__file__)),'sent');os.makedirs(d,exist_ok=True)\n"
       "n=len(os.listdir(d));json.dump(p,open(os.path.join(d,'%03d.json'%n),'w',encoding='utf-8'),ensure_ascii=False)\n"
       "[print('SFN\\t%s\\tok'%g['component']) for g in p['groups']]\n")
    # 모의 Rscript(sched_alert_emit) — 받은 환경변수를 한 줄 JSON 으로 남긴다
    wr(os.path.join(T, "mock_rscript.sh"),
       "#!/bin/bash\n\"%s\" -c \"import json,os;print(json.dumps({k:os.environ.get(k,'') for k in ('SA_COMP','SA_REASON','SA_DETAIL','SA_SUMMARY')},ensure_ascii=False))\" >> \"%s/sched_sent.jsonl\"\n"
       % (PY.replace("\\", "/"), T))
    return T


def env(T, now="2026-11-10 11:30"):
    e = dict(os.environ)
    e.update({"QVEST_SUPERFAN_NOW": now, "QVEST_ALERT_DEDUP_NOW": now, "QVEST_ALERT_DEDUP_PATH": T + "/.cache/alert_dedup.json",
              "QVEST_SUPERFAN_NOTIFY_CMD": "%s %s/mock_notify.py" % (PY.replace("\\", "/"), T),
              "QVEST_SCHED_ALERT_RSCRIPT": T + "/mock_rscript.sh", "QVEST_PY": PY.replace("\\", "/"),
              "QVEST_UNATTENDED": "1", "BASE": T, "TG_BOT_TOKEN": "TEST_TOKEN_NOT_REAL", "TG_CHAT_ID": "0"})
    for k in ("QVEST_SUPERFAN_REGISTRY_PATH", "QVEST_SUPERFAN_WATCH_PATH", "QVEST_SUPERFAN_TASK_HEALTH_PATH", "QVEST_NO_ALERT"):
        e.pop(k, None)
    return e


def watch(T, now="2026-11-10 11:30"):
    r = subprocess.run([PY, T + "/02_Infrastructure/programs/superfan_watch.py", "scan", "--notify"], capture_output=True,
                       text=True, encoding="utf-8", errors="replace", env=env(T, now), timeout=120)
    return r.stdout + r.stderr


def emit(T, keys, detail="실패: Qvest_MorningBrief(terminated_by_user_or_limit)", now="2026-11-10 12:01", reason="scheduled_task_unhealthy"):
    sh = ('. "%s/02_Infrastructure/ops/_sched_failure_classify.sh"; sched_alert_emit task_health %s "$D" "%s" "요약 한 문장"'
          % (T, reason, keys))
    e = env(T, now); e["D"] = detail; e["TODAY"] = now[:10].replace("-", "")
    subprocess.run([BASH, "-c", sh], env=e, capture_output=True, timeout=120)


def sent_payloads(T):
    d = os.path.join(T, "sent")
    return [json.load(io.open(os.path.join(d, f), encoding="utf-8")) for f in sorted(os.listdir(d))] if os.path.isdir(d) else []


def sent_comps(T):
    return [g["component"] for p in sent_payloads(T) for g in p["groups"]]


def sched_sent(T):
    p = os.path.join(T, "sched_sent.jsonl")
    return [json.loads(l) for l in io.open(p, encoding="utf-8")] if os.path.exists(p) else []


# ── D 같은 원인 두 발신처 ────────────────────────────────────────────────────
print("== D 같은 원인 두 발신처 → 1통 ==")
T = mk_root()
emit(T, "task:Qvest_MorningBrief ~task_health:digest")
chk("D1 task_health 경보 1통(모의 Rscript 호출)", len(sched_sent(T)) == 1, str(sched_sent(T)))
watch(T)
chk("D2 같은 원인 Superfan 아침 체인은 억제(발신 0)", "morning_chain" not in sent_comps(T), str(sent_comps(T)))
W = json.load(io.open(T + "/.cache/superfan_watch.json", encoding="utf-8"))
sup = [a for a in W["anomalies"].values() if a["component"] == "morning_chain" and (a.get("notified") or {}).get("suppressed") == "dedup"]
chk("D3 억제된 이상은 '알림 완료(중복)'로 표식(다음 시간 재시도 없음)", len(sup) >= 1, "")
watch(T, "2026-11-10 12:30")
chk("D4 다음 시간 스캔도 재발신 없음", "morning_chain" not in sent_comps(T), str(sent_comps(T)))
emit(T, "task:Qvest_MorningBrief", reason="other_reason_same_cause")
chk("D5 같은 날 다른 사유 문자열이라도 같은 원인 키면 억제", len(sched_sent(T)) == 1, str(len(sched_sent(T))))
dd = json.load(io.open(T + "/.cache/alert_dedup.json", encoding="utf-8"))["causes"].get("task:Qvest_MorningBrief", {})
chk("D6 억제는 건수만 올린다(count ≥ 3 · 발신처 2종)", dd.get("count", 0) >= 3 and len(dd.get("sources", [])) >= 2, str(dd))

# ── X 꺼진 구성요소 ─────────────────────────────────────────────────────────
print("== X 꺼진 구성요소 무경보 · 대조 ==")
op = [a for a in W["anomalies"].values() if a["status"] == "open"]
chk("X1 Disabled 작업(ReinforceAutoLoop)의 신선도 이상 없음", not any(a["component"] == "replication_lane" for a in op), "")
chk("X2 대조: 켜진 작업의 같은 규칙은 이상 + 발신", any(a["component"] == "lane_on" for a in op) and "lane_on" in sent_comps(T), str(sent_comps(T)))
chk("X3 작업 미수록 = 켜진 것으로(fail-closed) → 발신", "lane_unknown" in sent_comps(T), str(sent_comps(T)))

# ── B 본문 ──────────────────────────────────────────────────────────────────
print("== B 본문 = 요약 + 위치 · 원문 줄 없음 ==")
SECRET = "api_key=SECRETVALUE123"
with io.open(T + "/logs/morning_run.log", "a", encoding="utf-8") as f:
    f.write("[2026-11-10 12:40:00] Error: %s Execution halted\n" % SECRET)
TB = mk_root(); shutil.copyfile(T + "/logs/morning_run.log", TB + "/logs/morning_run.log")
wr(TB + "/06_Registry/scheduler_task_health.json", json.dumps({"tasks": []}))
watch(TB, "2026-11-10 12:45")
pl = sent_payloads(TB)
an = [a for p in pl for g in p["groups"] if g["component"] == "morning_chain" for a in g["anomalies"]]
raw = json.dumps([a.get("summary", "") + a.get("where", "") for a in an], ensure_ascii=False)
chk("B1 요약 · 위치에 로그 원문(가짜 비밀) 없음", SECRET not in raw and len(an) >= 1, "")
chk("B2 요약 한 문장 · 위치 필드", any(a.get("summary") and a.get("where") == "logs/morning_run.log" for a in an), str(an)[:200])
# 실제 superfan_notify.R 렌더(dry run · 가짜 토큰)
pfile = TB + "/payload.json"; io.open(pfile, "w", encoding="utf-8").write(json.dumps(pl[0], ensure_ascii=False))
renv = env(TB); renv.update({"QVEST_TG_DRY_RUN": "1", "QM_ROOT": REAL.replace("\\", "/"), "QVEST_TG_ARCHIVE_DIR": TB + "/arch",
                             "R_ENVIRON_USER": TB + "/empty.Renviron", "QVEST_TG_SERIAL_LOCK": "false"})
wr(TB + "/empty.Renviron", "")
rr = subprocess.run(["Rscript", "--no-save", REAL + "/02_Infrastructure/programs/superfan_notify.R", pfile], capture_output=True,
                    text=True, encoding="utf-8", errors="replace", env=renv, timeout=180, cwd=REAL)
out = rr.stdout + rr.stderr
chk("B3 렌더 본문에 원문 · 비밀 없음", SECRET not in out and "dry_run output" in out, out[-300:])
chk("B4 렌더 본문에 '위치' 와 요약", "위치 logs/morning_run.log" in out and "사건이 기록됨" in out, out[-300:])

# ── P 사유별 문구 ───────────────────────────────────────────────────────────
print("== P 사유별 문구 ==")
def phrase(T, tok):
    src = io.open(T + "/02_Infrastructure/ops/scheduler_task_health.sh", encoding="utf-8").read()
    fn = src[src.index("_th_phrase() {"):src.index("\n}\n", src.index("_th_phrase() {")) + 3]
    r = subprocess.run([BASH, "-c", fn + '\n_th_phrase "$1"', "_", tok], capture_output=True, text=True, encoding="utf-8")
    return r.stdout.strip()
ph = {t: phrase(T, t) for t in ("Qvest_MorningBrief(terminated_by_user_or_limit)", "Qvest_DailyRefresh(exit_1)",
                                "Qvest_WeeklyCleaner(한 번도 안 돎 — 감시 첫 관측 11-01 뒤 10일>9)", "Qvest_X(다음 실행 없음 — 트리거 만료)")}
v = list(ph.values())
chk("P1 267014 = 시간 상한 강제 종료 문구", "강제 종료" in v[0] and "267014" in v[0], v[0])
chk("P2 종료 코드 문구", "종료 코드 1" in v[1], v[1])
chk("P3 한 번도 안 돎 문구", "한 번도 실행되지 않음" in v[2], v[2])
chk("P4 다음 실행 없음 문구", "다음 실행 예정이 없음" in v[3], v[3])
chk("P5 '정지했습니다' 일반 문구 제거(발신기 기본값 · 주석 제외)", not any("사유로 정지했습니다" in l for l in io.open(REAL + "/02_Infrastructure/ops/_sched_failure_classify.sh", encoding="utf-8").read().splitlines() if not l.lstrip().startswith("#")), "")

# ── R 해소 뒤 재발 ──────────────────────────────────────────────────────────
print("== R 원인 해소 뒤 재발 → 다시 1통 ==")
wr(T + "/06_Registry/scheduler_task_health.json", json.dumps({"tasks": [{"task": "Qvest_MorningBrief", "enabled": True, "rc": 0}]}))
subprocess.run([PY, T + "/02_Infrastructure/ops/alert_dedup.py", "resolve-healthy", "--health", T + "/06_Registry/scheduler_task_health.json"],
               env=env(T), capture_output=True, timeout=60)
emit(T, "task:Qvest_MorningBrief", now="2026-11-10 18:00")
chk("R1 정상 실행으로 해소된 뒤 같은 날 재발 → 다시 1통", len(sched_sent(T)) == 2, str(len(sched_sent(T))))

# ── Q 값 전달 ───────────────────────────────────────────────────────────────
print("== Q 값 전달 = 환경변수 ==")
TQ = mk_root(); tricky = 'He said "x" \\ back $HOME `id`'
emit(TQ, "task:Qx", detail=tricky)
s = sched_sent(TQ)
chk("Q1 detail 이 바뀌지 않고 그대로(셸 · R 해석 없음)", len(s) == 1 and s[0]["SA_DETAIL"] == tricky, str(s))
chk("Q2 요약 인자 전달", len(s) == 1 and s[0]["SA_SUMMARY"] == "요약 한 문장", str(s))

# ── L 아침 상태 칸(정적) ─────────────────────────────────────────────────────
print("== L 아침 1계층 상태 ==")
ls = io.open(REAL + "/02_Infrastructure/ops/morning_steps/l1_status_send.R", encoding="utf-8").read()
mb = io.open(REAL + "/02_Infrastructure/ops/morning_briefing.sh", encoding="utf-8").read()
chk("L1 칸마다 tryCatch → '판독 불가'", ls.count(".cell({") >= 7, str(ls.count(".cell({")))
chk("L2 무음 발송(mute = TRUE) · 정본 발송기", "mute = TRUE" in ls and "tg_agent_brief(" in ls, "")
chk("L3 아침 체인 배선 + fail-soft", "l1_status_send.R" in mb and "[5c] l1_status 실패 (fail-soft)" in mb, "")
chk("L4 성과 지표 이름 미기재(CAGR · Calmar · Sharpe · 수익률)", not re.search(r"CAGR|Calmar|Sharpe|수익률", ls.split("lines <- l1_status_lines()")[0]), "")

# ── M 돌연변이 ──────────────────────────────────────────────────────────────
print("== M 돌연변이(가드마다 1개) ==")
TM = mk_root({"02_Infrastructure/ops/_sched_failure_classify.sh": ('if [ "$_cl" = "DUP" ]; then', 'if false; then')})
emit(TM, "task:Qvest_MorningBrief"); emit(TM, "task:Qvest_MorningBrief", reason="again")
chk("M1 중복 억제 제거 사본 → D5 축이 빨개짐(2통)", len(sched_sent(TM)) == 2, str(len(sched_sent(TM))))
TM = mk_root({"02_Infrastructure/programs/superfan_watch.py": ('if off and r["kind"] in STALENESS_KINDS:', 'if False and r["kind"] in STALENESS_KINDS:')})
watch(TM)
chk("M2 꺼짐 가드 제거 사본 → X1 축이 빨개짐(꺼진 레인 발신)", "replication_lane" in sent_comps(TM), str(sent_comps(TM)))
TM = mk_root({"02_Infrastructure/programs/superfan_watch.py": ("s = \"로그에 '%s' 사건이 기록됨\" % (ev.get(\"label\") or rule)", "s = t")})
shutil.copyfile(TB + "/logs/morning_run.log", TM + "/logs/morning_run.log"); wr(TM + "/06_Registry/scheduler_task_health.json", json.dumps({"tasks": []}))
watch(TM, "2026-11-10 12:45")
chk("M3 요약 대신 원문 사본 → B1 축이 빨개짐(비밀 노출)", SECRET in json.dumps([a.get("summary", "") for p in sent_payloads(TM) for g in p["groups"] for a in g["anomalies"]], ensure_ascii=False), "")
TM = mk_root({"02_Infrastructure/ops/scheduler_task_health.sh": ('이 실행 시간 상한(또는 수동 중지)으로 강제 종료됨(267014)', '상태 이상')})
chk("M4 사유 문구 제거 사본 → P1 축이 빨개짐", "강제 종료" not in phrase(TM, "Qvest_MorningBrief(terminated_by_user_or_limit)"), "")
TM = mk_root({"02_Infrastructure/ops/alert_dedup.py": ('return resolve(ks, path) if ks else 0', 'return 0')})
emit(TM, "task:Qvest_MorningBrief")
wr(TM + "/06_Registry/scheduler_task_health.json", json.dumps({"tasks": [{"task": "Qvest_MorningBrief", "enabled": True, "rc": 0}]}))
subprocess.run([PY, TM + "/02_Infrastructure/ops/alert_dedup.py", "resolve-healthy", "--health", TM + "/06_Registry/scheduler_task_health.json"],
               env=env(TM), capture_output=True, timeout=60)
emit(TM, "task:Qvest_MorningBrief", now="2026-11-10 18:00")
chk("M5 해소 제거 사본 → R1 축이 빨개짐(재발 억제됨)", len(sched_sent(TM)) == 1, str(len(sched_sent(TM))))

print(json.dumps({"test": "scn_tg_alert_noise", "pass": P, "fail": F, "total": P + F}))
sys.exit(1 if F else 0)
