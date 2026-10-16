"""세션 재개 상태(작업 연속성 · 2026-10-15 도훈 지시) — 06_Registry/session_resume.json 의 유일한 writer.

왜: 세션이 예기치 않게 끝나도 다음 세션의 Q 가 '무엇을 · 어디까지 · 다음에 무엇을' 하던 중이었는지 그대로 이어받게 한다.
  자동 기억(메모리 카드)은 사실 · 교훈을 남기지만 진행 중 작업의 단계 · 다음 명령 · 백그라운드 프로세스는 남기지 않는다.
  부팅(/qvest · boot_lean.sh)이 7번째 줄 `Resume:` 로 진행 중 작업을 보여 주고, 계층 질문 첫 선택지 '이전 세션 리서치 재개'가
  `show` 브리핑으로 이어진다.

사용(저장소 루트 · 표준 라이브러리만):
  python 02_Infrastructure/programs/session_resume.py begin  --id OP-… --title … --goal … --step "S1=제목" … [--context 경로 …] [--next …]
  python … step   --id OP-… --step S1 --status in_progress|done|failed|skipped [--note …] [--artifact 경로 …]
  python … next   --id OP-… --text "다음 세션이 바로 할 일(명령 · 파일)"
  python … bg     --id OP-… --what … [--log 경로] [--sentinel 경로] [--pid N]
  python … decide --id OP-… --text "도훈 결정 대기 항목(결정 기록부 id)"
  python … resolve --id OP-… --text "대기 항목 앞부분" --outcome "결정 내용"   # 결정이 나면 대기에서 뺀다
  python … note   --id OP-… --text "짧은 진행 기록"
  python … done   --id OP-… --outcome …     |   abandon --id OP-… --reason …
  python … show   [--id OP-…]               # 재개 브리핑(markdown) — 진행 중 전체 또는 1건
  python … boot-line                        # 부팅 Resume 줄(읽기 전용)
경로 재정의(검사용): 환경변수 QVEST_SESSION_RESUME_PATH.
"""
import argparse, datetime as dt, io, json, os, sys, tempfile

SCHEMA = "session_resume_v1"
STATUS_OP = ("in_progress", "blocked", "done", "abandoned")
STATUS_STEP = ("pending", "in_progress", "done", "failed", "skipped")
HISTORY_KEEP = 30


def _root():
    here = os.path.dirname(os.path.abspath(__file__))
    return os.path.dirname(os.path.dirname(here))


def state_path(root=None):
    p = os.environ.get("QVEST_SESSION_RESUME_PATH")
    return p if p else os.path.join(root or _root(), "06_Registry", "session_resume.json")


def _now():
    return dt.datetime.now().astimezone().strftime("%Y-%m-%dT%H:%M:%S%z")


def load(path):
    if not os.path.exists(path):
        return {"schema": SCHEMA, "updated_at": None, "operations": [], "history": []}
    with io.open(path, encoding="utf-8-sig") as f:
        d = json.load(f)
    if not isinstance(d, dict) or d.get("schema") != SCHEMA:
        raise ValueError("schema %r" % (d.get("schema") if isinstance(d, dict) else type(d).__name__))
    d.setdefault("operations", []); d.setdefault("history", [])
    return d


def save(path, d):
    d["updated_at"] = _now()
    os.makedirs(os.path.dirname(path), exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix=".session_resume_", suffix=".tmp", dir=os.path.dirname(path))
    with io.open(fd, "w", encoding="utf-8") as f:
        json.dump(d, f, ensure_ascii=False, indent=1)
    os.replace(tmp, path)                      # 원자적 교체(부분 쓰기 없음)


def _op(d, oid):
    for o in d["operations"]:
        if o.get("id") == oid:
            return o
    raise SystemExit("[session_resume] 작업 없음: %s" % oid)


def _log(o, text):
    o.setdefault("log", []).append({"at": _now(), "text": text})
    o["log"] = o["log"][-40:]
    o["updated_at"] = _now()


def cmd_begin(a, d):
    if any(o.get("id") == a.id for o in d["operations"]):
        raise SystemExit("[session_resume] 이미 있는 작업 id: %s" % a.id)
    steps = []
    for s in a.step or []:
        sid, _, title = s.partition("=")
        if not sid.strip() or not title.strip():
            raise SystemExit("[session_resume] --step 형식은 'S1=제목': %r" % s)
        steps.append({"id": sid.strip(), "title": title.strip(), "status": "pending", "note": "", "artifacts": [], "updated_at": None})
    o = {"id": a.id, "title": a.title, "goal": a.goal or "", "status": "in_progress", "started_at": _now(), "updated_at": _now(),
         "steps": steps, "next_action": a.next or "", "context_files": a.context or [], "background": [], "decisions": [], "log": []}
    _log(o, "시작")
    d["operations"].append(o)


def cmd_step(a, d):
    o = _op(d, a.id)
    if a.status not in STATUS_STEP:
        raise SystemExit("[session_resume] 단계 상태 어휘 밖: %s" % a.status)
    st = next((s for s in o["steps"] if s["id"] == a.step), None)
    if st is None:
        st = {"id": a.step, "title": a.title or a.step, "status": "pending", "note": "", "artifacts": [], "updated_at": None}
        o["steps"].append(st)
    st["status"] = a.status; st["updated_at"] = _now()
    if a.note: st["note"] = a.note
    if a.artifact: st["artifacts"] = sorted(set(st.get("artifacts", []) + a.artifact))
    _log(o, "%s → %s%s" % (a.step, a.status, (" · " + a.note) if a.note else ""))


def cmd_next(a, d):
    o = _op(d, a.id); o["next_action"] = a.text; _log(o, "다음: " + a.text[:120])


def cmd_bg(a, d):
    o = _op(d, a.id)
    o["background"].append({"what": a.what, "log": a.log or "", "sentinel": a.sentinel or "", "pid": a.pid, "at": _now()})
    o["background"] = o["background"][-10:]
    _log(o, "백그라운드: " + a.what)


def cmd_decide(a, d):
    o = _op(d, a.id)
    if a.text not in o["decisions"]:
        o["decisions"].append(a.text)
    _log(o, "결정 대기: " + a.text[:120])


def cmd_resolve(a, d):
    o = _op(d, a.id)
    hit = [x for x in o["decisions"] if x == a.text or x.startswith(a.text)]
    if not hit:
        raise SystemExit("[session_resume] 대기 결정 없음: %r (대기 %s)" % (a.text, o["decisions"]))
    o["decisions"] = [x for x in o["decisions"] if x not in hit]
    _log(o, "결정 해소: %s → %s" % (" · ".join(hit)[:100], a.outcome[:120]))


def cmd_note(a, d):
    _log(_op(d, a.id), a.text)


def _close(d, oid, status, text):
    o = _op(d, oid); o["status"] = status; _log(o, "%s: %s" % (status, text))
    d["operations"] = [x for x in d["operations"] if x.get("id") != oid]
    d["history"] = (d["history"] + [{"id": oid, "title": o.get("title"), "status": status, "outcome": text,
                                      "started_at": o.get("started_at"), "finished_at": _now()}])[-HISTORY_KEEP:]


def _progress(o):
    st = o.get("steps") or []
    n = len(st); k = sum(1 for s in st if s.get("status") in ("done", "skipped"))
    cur = next((s for s in st if s.get("status") == "in_progress"), None) or next((s for s in st if s.get("status") == "pending"), None)
    return k, n, cur


def _open_rounds(root):
    """등록부에서 '등록됐지만 끝나지 않은' 라운드 — 저널에 안 적었어도 보이게(자동 신호)."""
    p = os.path.join(root, "06_Registry", "research_programs.json")
    try:
        with io.open(p, encoding="utf-8-sig") as f:
            r = json.load(f)
        out = []
        for pg in r.get("programs", []):
            for rd in pg.get("rounds", []) or []:
                if isinstance(rd, dict) and rd.get("status") == "registered":
                    out.append(str(rd.get("round_id")))
        return out
    except Exception as e:  # 읽기 실패는 0 으로 접지 않는다
        return ["?(%s)" % type(e).__name__]


def _superfan_fragment(root):
    """Superfan 대기 상태 — 판단 원장(q_judgment_ledger.py) · 구성요소 감시(superfan_watch.py)의 boot_fragment.
    없으면 '' · 실패는 0 으로 접지 않는다(그 도구 이름과 예외 종류를 보인다)."""
    import importlib.util
    out = []
    for mod, label in (("q_judgment_ledger", "Superfan"), ("superfan_watch", "Superfan 감시")):
        try:
            p = os.path.join(os.path.dirname(os.path.abspath(__file__)), mod + ".py")
            spec = importlib.util.spec_from_file_location(mod, p)
            m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
            f = m.boot_fragment(root)
        except Exception as e:
            f = "%s ?(%s)" % (label, type(e).__name__)
        if f:
            out.append(f)
    return " | ".join(out)


def boot_line(root=None):
    root = root or _root()
    try:
        d = load(state_path(root))
    except Exception as e:
        return "Resume: ?(상태 파일 판독 실패 %s)" % type(e).__name__
    ops = [o for o in d["operations"] if o.get("status") in ("in_progress", "blocked")]
    rounds = _open_rounds(root)
    rtxt = (" | 열린 라운드 " + " · ".join(rounds[:4]) + (" +%d" % (len(rounds) - 4) if len(rounds) > 4 else "")) if rounds else ""
    sf = _superfan_fragment(root)
    rtxt += (" | " + sf) if sf else ""
    if not ops:
        return "Resume: 진행 중 작업 없음" + rtxt
    ops.sort(key=lambda o: o.get("updated_at") or "", reverse=True)
    o = ops[0]; k, n, cur = _progress(o)
    nx = (o.get("next_action") or "").replace("\n", " ")
    more = (" (외 %d건)" % (len(ops) - 1)) if len(ops) > 1 else ""
    return "Resume: %s %s · 단계 %d/%d%s · 다음: %s · 갱신 %s%s%s" % (
        o["id"], o.get("title", ""), k, n, (" «" + cur["title"] + "»") if cur else "",
        (nx[:90] + "…") if len(nx) > 90 else (nx or "?"), (o.get("updated_at") or "?")[5:16].replace("T", " "), more, rtxt)


def show(root=None, oid=None):
    root = root or _root()
    d = load(state_path(root))
    ops = [o for o in d["operations"] if (oid is None or o.get("id") == oid)]
    L = ["# 세션 재개 브리핑 (%s)" % _now()[:16], ""]
    if not ops:
        L.append("진행 중 작업 없음.")
    for o in ops:
        k, n, cur = _progress(o)
        L += ["## %s — %s" % (o["id"], o.get("title", "")), "",
              "- 상태: %s · 단계 %d/%d · 시작 %s · 갱신 %s" % (o.get("status"), k, n, o.get("started_at"), o.get("updated_at")),
              "- 목표: %s" % (o.get("goal") or "—"),
              "- **다음 할 일**: %s" % (o.get("next_action") or "—"), ""]
        mark = {"done": "✅", "in_progress": "▶", "pending": "·", "failed": "✗", "skipped": "↷"}
        for s in o.get("steps", []):
            L.append("  %s %s %s%s%s" % (mark.get(s.get("status"), "?"), s["id"], s.get("title", ""),
                                        (" — " + s["note"]) if s.get("note") else "",
                                        (" [" + ", ".join(s.get("artifacts", [])[:4]) + "]") if s.get("artifacts") else ""))
        if o.get("context_files"):
            L += ["", "- 먼저 읽을 것: " + " · ".join(o["context_files"])]
        if o.get("background"):
            L += ["- 백그라운드: " + " · ".join("%s(로그 %s · 센티널 %s)" % (b["what"], b.get("log") or "—", b.get("sentinel") or "—") for b in o["background"][-4:])]
        if o.get("decisions"):
            L += ["- 도훈 결정 대기: " + " · ".join(o["decisions"])]
        if o.get("log"):
            L += ["- 최근 기록: " + " | ".join("%s %s" % (x["at"][5:16].replace("T", " "), x["text"]) for x in o["log"][-5:])]
        L.append("")
    rounds = _open_rounds(root)
    if rounds:
        L.append("열린 라운드(등록부 · 저널과 별개 자동 신호): " + " · ".join(rounds))
    sf = _superfan_fragment(root)
    if sf:
        L.append(sf + " — 상세: python -X utf8 02_Infrastructure/programs/q_judgment_ledger.py show --open (규약 00_Lawbook/specs/superfan_protocol.md)")
    if d.get("history"):
        L.append("최근 종료 작업: " + " · ".join("%s(%s)" % (h["id"], h["status"]) for h in d["history"][-5:]))
    return "\n".join(L)


def main(argv=None):
    ap = argparse.ArgumentParser(prog="session_resume")
    sp = ap.add_subparsers(dest="cmd", required=True)
    b = sp.add_parser("begin"); b.add_argument("--id", required=True); b.add_argument("--title", required=True)
    b.add_argument("--goal"); b.add_argument("--step", action="append"); b.add_argument("--context", action="append"); b.add_argument("--next")
    s = sp.add_parser("step"); s.add_argument("--id", required=True); s.add_argument("--step", required=True)
    s.add_argument("--status", required=True); s.add_argument("--note"); s.add_argument("--title"); s.add_argument("--artifact", action="append")
    for nm in ("next", "decide", "note"):
        x = sp.add_parser(nm); x.add_argument("--id", required=True); x.add_argument("--text", required=True)
    g = sp.add_parser("bg"); g.add_argument("--id", required=True); g.add_argument("--what", required=True)
    g.add_argument("--log"); g.add_argument("--sentinel"); g.add_argument("--pid", type=int)
    rs = sp.add_parser("resolve"); rs.add_argument("--id", required=True); rs.add_argument("--text", required=True)
    rs.add_argument("--outcome", required=True)
    dn = sp.add_parser("done"); dn.add_argument("--id", required=True); dn.add_argument("--outcome", required=True)
    ab = sp.add_parser("abandon"); ab.add_argument("--id", required=True); ab.add_argument("--reason", required=True)
    sh = sp.add_parser("show"); sh.add_argument("--id")
    sp.add_parser("boot-line")
    a = ap.parse_args(argv)
    if a.cmd == "boot-line":
        print(boot_line()); return 0
    if a.cmd == "show":
        print(show(oid=a.id)); return 0
    path = state_path()
    d = load(path)
    {"begin": cmd_begin, "step": cmd_step, "next": cmd_next, "bg": cmd_bg, "decide": cmd_decide, "resolve": cmd_resolve,
     "note": cmd_note}.get(a.cmd, lambda *_: None)(a, d)
    if a.cmd == "done": _close(d, a.id, "done", a.outcome)
    if a.cmd == "abandon": _close(d, a.id, "abandoned", a.reason)
    save(path, d)
    print("[session_resume] %s %s" % (a.cmd, getattr(a, "id", "")))
    return 0


if __name__ == "__main__":
    sys.exit(main())
