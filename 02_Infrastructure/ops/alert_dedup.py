"""alert_dedup.py — 무인 경보 발신처들이 함께 읽는 '원인 하나 = 하루 한 통' 저장소 (2026-11-10 감사 레인 B · 같은 날 2차 수리).

왜: SKILL qvest-telegram §0.4 '평상 무음 · 실패는 1회 · 같은 원인 반복 발송 금지' 의 집행. 실측 11-07~11-10 보관 18통 중 9통이
  실패 알림이었고, 같은 원인(예약 작업 Qvest_MorningBrief 종료)이 Superfan 감시(11:17)와 task_health 경보(12:01)로 두 통 갔다.
  발신처는 각자 1일 1회 스로틀을 가졌지만 서로를 몰랐다 — 이 저장소가 그 공유 면이다.
  ★억제는 fail-open 이 아니어야 한다 — 아무도 안 보낸 원인이 '이미 보냄'으로 남으면 진짜 경보가 조용히 묻힌다(2차 수리의 이유).

원인 키 규약
  task:<예약 작업 이름>          예약 작업의 '실행 실패'(종료 코드 · 강제 종료 · 미실행 · 정체) — 발신처 간에 접는 유일한 부류.
                                 task_health 와, 그 작업의 실행 자체를 재는 Superfan 규칙(규칙 필드 cause = "task_run")이 같은 키를 쓴다.
  task_health:digest             task_health 로그 요약 줄(Superfan 'scheduler' 구성요소의 키 · task_health 는 보조로 잡는다)
  sf:<구성요소>:<규칙>:<이상 키>  그 밖의 Superfan 이상(팩터 DB 빌드 게이트 · BOOK 시가평가 신선도 · 단계 실패 등 구성요소 고유 검사)
  '~' 로 시작하는 키 = 보조 키 — 잡기는 하되 '새 원인' 판정에는 세지 않는다.

두 단계(claim → confirm) — 2차 수리
  claim   : 오늘 확정(confirmed)된 키 = 억제(DUP · 건수만) · 오늘 다른 발신처가 잡고 아직 확정 전(claimed) = 억제하되 '양보'
            (그 발신처가 보내거나 놓을 때까지 · 호출자는 settled() 로 다시 본다) · 같은 발신처가 잡아 둔 미확정 키 · 오래된 미확정 키
            (CLAIM_STALE_SEC) = 다시 잡는다(앞 실행이 죽었다) · 없거나 다른 날 = 새로 잡는다.
            주 키 중 새로 잡은 것이 없으면 보조 키도 새로 만들지 않는다(보내지 않을 실행이 미확정 보조 키를 남기지 않게).
  confirm : 발송 성사 뒤 확정한다(이 상태만 '오늘 보냄'이다).
  release : 발송 실패 때 내가 잡은 미확정 키를 **완전히** 놓는다(건수 깎기 아님 — 1차판은 count>1 이면 키를 남겨, DUP 로 물러난
            발신처가 있던 날 아무도 안 보낸 원인이 '이미 보냄'으로 남았다). 확정된 키는 놓지 않는다(보낸 것을 되돌릴 수 없다).
  settled : '키 K 에 양보'한 발신처가 다시 볼 때 — K 가 그 날 이후 확정된 적이 있으면 참(확정 시각은 날을 넘겨 남긴다).
  resolve : 원인이 풀리면(다음 정상 실행) 키를 지운다 — 같은 날 재발도 다시 1통.
  resolve-healthy: scheduler_task_health.json 에서 '경보 뒤에 실제로 건강하게 다시 돈' 작업 · 꺼진 작업의 task:<이름> 키만 지운다
            (rc 0 이어도 정체 · 다음 실행 없음이면 안 지운다 — 1차판은 rc 0 만 보고 지워 같은 정체 경보가 실행마다 나갔다).
  날짜 = 로컬 달력일(QVEST_ALERT_DEDUP_NOW 'YYYY-MM-DD HH:MM' 으로 고정 가능 · 시험용).
저장 = <루트>/.cache/alert_dedup.json (재정의 QVEST_ALERT_DEDUP_PATH) · 쓰기 = 잠금 디렉터리 + 원자 교체. 판독 실패 = 빈 저장소(= 보내는 쪽,
  fail-open 아님: 경보를 놓치지 않는 쪽으로 기운다).

CLI(표준 라이브러리만):
  python alert_dedup.py claim --source S --summary "…" KEY [KEY …]   → stdout 'NEW k1 k2' 또는 'DUP' · 종료 0
  python alert_dedup.py confirm --source S KEY [KEY …] | release [--source S] KEY [KEY …] | resolve KEY [KEY …]
  python alert_dedup.py resolve-healthy --health PATH | show
"""
import argparse, datetime as dt, io, json, os, socket, sys, tempfile, time

SCHEMA = "alert_dedup_v1"

# 미확정(claimed) 키를 '잡은 프로세스가 죽었다'로 보고 다음 claim 이 가져가는 나이(초).
#   근거(실제 주기 · 상한): 발신 중인 claim 의 최대 수명 —
#     · Superfan 감시 = 예약 작업 Qvest_SuperfanWatch 1시간 간격(작업 XML Interval PT1H) · 실행 상한 ExecutionTimeLimit PT20M(1200초 뒤 OS 가 죽인다)
#       · 발신 subprocess timeout 300초(superfan_watch.py _send)
#     · task_health 발신 = tg_agent_brief 의 전역 직렬 잠금 대기 상한 timeout_sec = 900초(telegram_notify.R tg_with_serial_lock) + 발송
#   ∴ 살아 있는 발신은 1200초를 넘기지 못한다 → 1800초(잠금 stale_sec 1800 과 같은 값)를 넘긴 미확정 키는 죽은 보유자다.
#     그리고 1800초 < Superfan 다음 실행(3600초)이라, 보유자가 죽어도 그다음 시간 실행이 반드시 다시 잡는다.
CLAIM_STALE_SEC = int(os.environ.get("QVEST_ALERT_DEDUP_CLAIM_STALE_SEC", "1800"))
PRUNE_DAYS = 8                                                         # 날짜 · 확정 시각이 모두 8일 넘은 항목은 걷는다(주간 작업 주기 7일 + 1)


def _root():
    here = os.path.dirname(os.path.abspath(__file__))
    return os.path.dirname(os.path.dirname(here))


def store_path(root=None):
    return os.environ.get("QVEST_ALERT_DEDUP_PATH") or os.path.join(root or _root(), ".cache", "alert_dedup.json")


def machine_name():
    """측정 기계 이름 — scheduler_task_health.sh 가 health json 의 measured_on 에 쓰는 것과 같은 식."""
    return os.environ.get("COMPUTERNAME") or socket.gethostname() or "?"


def _now():
    s = os.environ.get("QVEST_ALERT_DEDUP_NOW", "").strip()
    return dt.datetime.strptime(s, "%Y-%m-%d %H:%M") if s else dt.datetime.now()


def _ts(s):
    try:
        return dt.datetime.strptime(str(s)[:19], "%Y-%m-%dT%H:%M:%S")
    except Exception:
        return None


def _load(p):
    try:
        with io.open(p, encoding="utf-8") as f:
            d = json.load(f)
        if d.get("schema") == SCHEMA and isinstance(d.get("causes"), dict):
            return d
    except Exception:
        pass
    return {"schema": SCHEMA, "causes": {}}


class _Lock:
    """잠금 디렉터리(mkdir 원자성) — 동시 발신처(StrandedRepairs 의 task_health · SuperfanWatch)가 서로의 쓰기를 덮지 않게.
    120초 넘은 잠금은 죽은 보유자로 보고 걷는다(쓰기 한 번 = 수 ms)."""
    def __init__(self, p):
        self.d = p + ".lock"

    def __enter__(self):
        os.makedirs(os.path.dirname(self.d) or ".", exist_ok=True)
        for _ in range(200):
            try:
                os.mkdir(self.d); return self
            except FileExistsError:
                try:
                    if time.time() - os.path.getmtime(self.d) > 120:
                        os.rmdir(self.d); continue
                except OSError:
                    pass
                time.sleep(0.05)
        return self                                                     # 잠금 실패여도 진행(경보를 막지 않는다)

    def __exit__(self, *a):
        try:
            os.rmdir(self.d)
        except OSError:
            pass


def _prune(C, now):
    lim = (now - dt.timedelta(days=PRUNE_DAYS)).strftime("%Y-%m-%d")
    for k in [k for k, e in C.items() if max(str(e.get("date") or ""), str(e.get("last_confirmed_at") or "")[:10]) < lim]:
        C.pop(k, None)


def _save(p, d):
    os.makedirs(os.path.dirname(p), exist_ok=True)
    _prune(d["causes"], _now())
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(p), prefix=".alert_dedup_", suffix=".json")
    with io.open(fd, "w", encoding="utf-8") as f:
        json.dump(d, f, ensure_ascii=False, indent=1)
    os.replace(tmp, p)


def _state(e):
    """판 표식 없는 1차판 항목 = 확정으로 읽는다(1차판은 잡는 즉시 '보냄'이었다 — 그날 하루분만 남는다)."""
    return e.get("state") or "confirmed"


def _stub(e):
    """키를 놓거나 지울 때 — 확정 이력(last_confirmed_at)이 있으면 그것만 남긴다(양보한 발신처의 settled 판독용)."""
    lc = e.get("last_confirmed_at") or (e.get("confirmed_at") if _state(e) == "confirmed" else None) \
        or (e.get("first_at") if not e.get("state") else None)
    return {"date": "", "state": "released", "last_confirmed_at": lc} if lc else None


def claim_ex(keys, source, summary="", path=None):
    """반환 = {'new': 새로 잡은 주 키, 'yield': 새로 못 잡은 주 키(확정됨 · 다른 발신처가 미확정으로 보유)}.
    new 가 비면 = 보내지 않는다. 다른 발신처 보유 중이면 호출자는 yield 키를 적어 두고 다음 실행에 settled() 로 다시 본다."""
    p = path or store_path(); now = _now(); today = now.strftime("%Y-%m-%d"); ts = now.strftime("%Y-%m-%dT%H:%M:%S")
    new, yld, plan = [], [], []
    with _Lock(p):
        d = _load(p); C = d["causes"]
        for k in keys:
            aux = k.startswith("~"); k0 = k[1:] if aux else k
            if not k0:
                continue
            e = C.get(k0)
            if e and e.get("date") == today:
                st = _state(e)
                ca = _ts(e.get("claimed_at") or e.get("last_at"))
                retake = st == "claimed" and (e.get("owner") == source or ca is None or (now - ca).total_seconds() > CLAIM_STALE_SEC)
                plan.append((k0, aux, "retake" if retake else "dup", e))
            else:
                plan.append((k0, aux, "fresh", e))
        any_new = any(act in ("retake", "fresh") and not aux for _, aux, act, _ in plan)
        for k0, aux, act, e in plan:
            if act == "dup" or (aux and not any_new):
                if e and e.get("date") == today:
                    e["count"] = int(e.get("count", 1)) + 1; e["last_at"] = ts
                    if source not in e.setdefault("sources", []):
                        e["sources"].append(source)
                if not aux:
                    yld.append(k0)
                continue
            if act == "retake":
                e.update({"state": "claimed", "owner": source, "claimed_at": ts, "last_at": ts, "count": int(e.get("count", 1)) + 1})
                if source not in e.setdefault("sources", []):
                    e["sources"].append(source)
            else:
                C[k0] = {"date": today, "state": "claimed", "owner": source, "claimed_at": ts, "first_at": ts, "last_at": ts,
                         "count": 1, "sources": [source], "summary": summary[:200],
                         "last_confirmed_at": (e or {}).get("last_confirmed_at")}
            if not aux:
                new.append(k0)
        _save(p, d)
    return {"new": new, "yield": yld}


def claim(keys, source, summary="", path=None):
    """반환 = 새로 잡은 주 키 목록(비면 = 같은 원인이 오늘 이미 나갔거나 다른 발신처가 보내는 중 → 보내지 않는다). 보조 키('~')는 잡되 세지 않는다."""
    return claim_ex(keys, source, summary, path)["new"]


def confirm(keys, source="", path=None):
    """발송 성사 뒤 — 그 키들을 오늘 확정한다(없으면 확정 항목을 만든다: 보낸 사실이 정본이다)."""
    p = path or store_path(); now = _now(); today = now.strftime("%Y-%m-%d"); ts = now.strftime("%Y-%m-%dT%H:%M:%S")
    with _Lock(p):
        d = _load(p); C = d["causes"]
        for k in keys:
            k0 = k.lstrip("~")
            if not k0:
                continue
            e = C.get(k0)
            if not e or e.get("date") != today:
                e = C[k0] = {"date": today, "first_at": ts, "last_at": ts, "count": 1, "sources": [source] if source else [], "summary": ""}
            e.update({"state": "confirmed", "confirmed_at": ts, "last_confirmed_at": ts, "confirmed_by": source or e.get("owner")})
        _save(p, d)


def release(keys, path=None, source=None):
    """발송 실패 — 내가 잡은(source 가 주어지면 그 발신처가 보유한) 미확정 키를 완전히 놓는다. 확정된 키 · 남이 보유한 키는 건드리지 않는다."""
    p = path or store_path()
    with _Lock(p):
        d = _load(p); C = d["causes"]
        for k in keys:
            k0 = k.lstrip("~"); e = C.get(k0)
            if not e or _state(e) != "claimed" or (source and e.get("owner") != source):
                continue
            s = _stub(e)
            if s:
                C[k0] = s
            else:
                C.pop(k0, None)
        _save(p, d)


def settled(keys, since_date, path=None):
    """양보한 키들이 since_date('YYYY-MM-DD') 이후 모두 확정된 적이 있나(= 그 원인은 누군가 보냈다). 판독 실패 = 거짓(다시 시도하는 쪽)."""
    try:
        C = _load(path or store_path())["causes"]
    except Exception:
        return False
    for k in keys:
        if k.startswith("~"):
            continue
        e = C.get(k) or {}
        lc = str(e.get("last_confirmed_at") or "")[:10]
        if _state(e) == "confirmed" and e.get("date"):
            lc = max(lc, str(e["date"]))
        if not lc or lc < since_date:
            return False
    return True


def resolve(keys, path=None):
    p = path or store_path(); n = 0
    with _Lock(p):
        d = _load(p); C = d["causes"]
        for k in keys:
            k0 = k.lstrip("~"); e = C.get(k0)
            if e is None or e.get("state") == "released":
                continue
            s = _stub(e)
            if s:
                C[k0] = s
            else:
                C.pop(k0, None)
            n += 1
        if n:
            _save(p, d)
    return n


def _healthy_after_alert(t, entry, stale_names):
    """그 작업이 경보(원인 키를 잡은 시각) **뒤에** 실제로 건강하게 다시 돌았나 — 판정이 경보 판정(scheduler_task_health.sh)과 같은 기준."""
    name = t.get("task")
    if name in stale_names:
        return False
    if (t.get("state") or "").strip() == "Running" or t.get("rc_label") in ("never_run", "still_running"):
        return False
    try:
        if int(t.get("rc") or 0) != 0:
            return False
    except (TypeError, ValueError):
        return False
    ms, ag = t.get("max_stale_days"), t.get("age_days")
    if ms and ag is not None and ag > ms:                                       # 나이 초과 정체
        return False
    if t.get("time_scheduled") and (t.get("state") or "").strip() != "Disabled" and not (t.get("next_run") or ""):
        return False                                                            # 다음 실행 없음(트리거 만료)
    lr, fa = _ts(t.get("last_run")), _ts(entry.get("first_at") or entry.get("claimed_at"))
    return lr is not None and fa is not None and lr > fa                        # 경보 뒤의 실행이어야 '다시 돌았다'


def resolve_healthy(health_path, path=None):
    """task_health 산출에서 경보 뒤 건강하게 다시 돈 작업 · 꺼진 작업 → task:<이름> 해소. 판독 실패 · 다른 기계 측정 = 아무것도 지우지 않는다."""
    try:
        with io.open(health_path, encoding="utf-8-sig") as f:
            h = json.load(f)
        tasks = h.get("tasks") or []
        if isinstance(tasks, dict):
            tasks = [tasks]
    except Exception:
        return 0
    if h.get("measured_on") and h.get("measured_on") != machine_name():
        return 0                                                                # 다른 기계가 잰 상태로 이 기계의 키를 지우지 않는다
    v = h.get("verdict") or {}
    stale_names = {str(x).split("(")[0] for x in (v.get("stale") or []) + (v.get("failed_new") or []) + (v.get("failed_known") or [])
                   + (v.get("in_flight") or [])}
    p = path or store_path()
    C = _load(p)["causes"]
    ks = []
    for t in tasks:
        name = t.get("task")
        e = C.get("task:%s" % name) if name else None
        if not e or e.get("state") == "released":
            continue
        if t.get("enabled") is False or _healthy_after_alert(t, e, stale_names):
            ks.append("task:%s" % name)
    return resolve(ks, path) if ks else 0


def main(argv=None):
    ap = argparse.ArgumentParser()
    sp = ap.add_subparsers(dest="cmd", required=True)
    c = sp.add_parser("claim"); c.add_argument("--source", required=True); c.add_argument("--summary", default=""); c.add_argument("keys", nargs="+")
    cf = sp.add_parser("confirm"); cf.add_argument("--source", default=""); cf.add_argument("keys", nargs="+")
    rl = sp.add_parser("release"); rl.add_argument("--source", default=None); rl.add_argument("keys", nargs="+")
    s = sp.add_parser("resolve"); s.add_argument("keys", nargs="+")
    h = sp.add_parser("resolve-healthy"); h.add_argument("--health", required=True)
    sp.add_parser("show")
    a = ap.parse_args(argv)
    if a.cmd == "claim":
        new = claim(a.keys, a.source, a.summary)
        print(("NEW " + " ".join(new)) if new else "DUP")
    elif a.cmd == "confirm":
        confirm(a.keys, a.source)
    elif a.cmd == "release":
        release(a.keys, source=a.source)
    elif a.cmd == "resolve":
        print(resolve(a.keys))
    elif a.cmd == "resolve-healthy":
        print(resolve_healthy(a.health))
    else:
        print(json.dumps(_load(store_path()), ensure_ascii=False, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
