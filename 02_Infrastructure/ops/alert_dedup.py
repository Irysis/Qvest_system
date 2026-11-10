"""alert_dedup.py — 무인 경보 발신처들이 함께 읽는 '원인 하나 = 하루 한 통' 저장소 (2026-11-10 감사 레인 B).

왜: SKILL qvest-telegram §0.4 '평상 무음 · 실패는 1회 · 같은 원인 반복 발송 금지' 의 집행. 실측 11-07~11-10 보관 18통 중 9통이
  실패 알림이었고, 같은 원인(예약 작업 Qvest_MorningBrief 종료)이 Superfan 감시(11:17)와 task_health 경보(12:01)로 두 통 갔다.
  발신처는 각자 1일 1회 스로틀을 가졌지만 서로를 몰랐다 — 이 저장소가 그 공유 면이다.

원인 키 규약
  task:<예약 작업 이름>     예약 작업 하나의 실패(task_health · 그 작업에 묶인 Superfan 구성요소가 같은 키를 쓴다)
  task_health:digest        task_health 로그 요약 줄(Superfan 'scheduler' 구성요소의 키 · task_health 는 보조로 잡는다)
  sf:<구성요소>:<이상 키>   예약 작업에 묶이지 않은 Superfan 이상
  '~' 로 시작하는 키 = 보조 키 — 잡기는 하되 '새 원인' 판정에는 세지 않는다.

동작
  claim  : 오늘 날짜로 아직 없는 키면 새로 잡고(=보낼 원인) · 이미 오늘 있으면 count · sources 만 올린다(=억제).
  release: 발송 실패 때 방금 잡은 키를 되돌린다(다음 실행이 다시 보낼 수 있게).
  resolve: 원인이 풀리면(다음 정상 실행) 키를 지운다 — 같은 날 재발도 다시 1통.
  resolve-healthy: scheduler_task_health.json 에서 정상(rc 0) · 꺼진 작업의 task:<이름> 키를 지운다.
  날짜 = 로컬 달력일(QVEST_ALERT_DEDUP_NOW 'YYYY-MM-DD HH:MM' 으로 고정 가능 · 시험용).
저장 = <루트>/.cache/alert_dedup.json (재정의 QVEST_ALERT_DEDUP_PATH) · 쓰기 = 잠금 디렉터리 + 원자 교체. 판독 실패 = 빈 저장소(= 보내는 쪽, fail-open 아님:
  경보를 놓치지 않는 쪽으로 기운다).

CLI(표준 라이브러리만):
  python alert_dedup.py claim --source S --summary "…" KEY [KEY …]   → stdout 'NEW k1 k2' 또는 'DUP' · 종료 0
  python alert_dedup.py release KEY [KEY …] | resolve KEY [KEY …] | resolve-healthy --health PATH | show
"""
import argparse, datetime as dt, io, json, os, sys, tempfile, time

SCHEMA = "alert_dedup_v1"


def _root():
    here = os.path.dirname(os.path.abspath(__file__))
    return os.path.dirname(os.path.dirname(here))


def store_path(root=None):
    return os.environ.get("QVEST_ALERT_DEDUP_PATH") or os.path.join(root or _root(), ".cache", "alert_dedup.json")


def _now():
    s = os.environ.get("QVEST_ALERT_DEDUP_NOW", "").strip()
    return dt.datetime.strptime(s, "%Y-%m-%d %H:%M") if s else dt.datetime.now()


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


def _save(p, d):
    os.makedirs(os.path.dirname(p), exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(p), prefix=".alert_dedup_", suffix=".json")
    with io.open(fd, "w", encoding="utf-8") as f:
        json.dump(d, f, ensure_ascii=False, indent=1)
    os.replace(tmp, p)


def claim(keys, source, summary="", path=None):
    """반환 = 새로 잡은 주 키 목록(비면 = 같은 원인이 오늘 이미 나갔다 → 보내지 않는다). 보조 키('~')는 잡되 세지 않는다."""
    p = path or store_path(); now = _now(); today = now.strftime("%Y-%m-%d"); ts = now.strftime("%Y-%m-%dT%H:%M:%S")
    new = []
    with _Lock(p):
        d = _load(p); C = d["causes"]
        for k in keys:
            aux = k.startswith("~"); k0 = k[1:] if aux else k
            if not k0:
                continue
            e = C.get(k0)
            if e and e.get("date") == today:
                e["count"] = int(e.get("count", 1)) + 1; e["last_at"] = ts
                if source not in e.setdefault("sources", []):
                    e["sources"].append(source)
            else:
                C[k0] = {"date": today, "first_at": ts, "last_at": ts, "count": 1, "sources": [source], "summary": summary[:200]}
                if not aux:
                    new.append(k0)
        _save(p, d)
    return new


def release(keys, path=None):
    p = path or store_path()
    with _Lock(p):
        d = _load(p)
        for k in keys:
            e = d["causes"].get(k.lstrip("~"))
            if e and int(e.get("count", 1)) <= 1:
                d["causes"].pop(k.lstrip("~"), None)
            elif e:
                e["count"] = int(e["count"]) - 1
        _save(p, d)


def resolve(keys, path=None):
    p = path or store_path(); n = 0
    with _Lock(p):
        d = _load(p)
        for k in keys:
            if d["causes"].pop(k.lstrip("~"), None) is not None:
                n += 1
        if n:
            _save(p, d)
    return n


def resolve_healthy(health_path, path=None):
    """task_health 산출의 정상(rc 0 · 실행 중 아님) · 꺼진 작업 → task:<이름> 해소. 판독 실패 = 아무것도 지우지 않는다."""
    try:
        with io.open(health_path, encoding="utf-8") as f:
            tasks = json.load(f).get("tasks") or []
    except Exception:
        return 0
    ks = ["task:%s" % t.get("task") for t in tasks
          if t.get("task") and ((t.get("enabled") is False) or (int(t.get("rc") or 0) == 0 and t.get("rc_label") != "never_run"))]
    return resolve(ks, path) if ks else 0


def main(argv=None):
    ap = argparse.ArgumentParser()
    sp = ap.add_subparsers(dest="cmd", required=True)
    c = sp.add_parser("claim"); c.add_argument("--source", required=True); c.add_argument("--summary", default=""); c.add_argument("keys", nargs="+")
    for nm in ("release", "resolve"):
        s = sp.add_parser(nm); s.add_argument("keys", nargs="+")
    h = sp.add_parser("resolve-healthy"); h.add_argument("--health", required=True)
    sp.add_parser("show")
    a = ap.parse_args(argv)
    if a.cmd == "claim":
        new = claim(a.keys, a.source, a.summary)
        print(("NEW " + " ".join(new)) if new else "DUP")
    elif a.cmd == "release":
        release(a.keys)
    elif a.cmd == "resolve":
        print(resolve(a.keys))
    elif a.cmd == "resolve-healthy":
        print(resolve_healthy(a.health))
    else:
        print(json.dumps(_load(store_path()), ensure_ascii=False, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
