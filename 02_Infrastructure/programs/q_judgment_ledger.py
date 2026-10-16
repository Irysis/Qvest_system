"""Q 판단 원장(Superfan 감사 · 논쟁 · 2026-10-15 도훈 지시) — 06_Registry/q_judgment_ledger.json 의 유일한 writer.

왜: 도훈 "Q 자율 판단 체계가 설계 의도대로 돌아가는지 감사하는 외부감시자(Superfan) — Q 의 모든 판단을 모니터링해서 검증 ·
  Q 와 논쟁 · 병목이 아니라 Q 가 제대로 기능하게 돕는다". 판단이 기록돼야 감사할 수 있다 — Q 는 자율 판단 체계
  (00_Lawbook/specs/q_autonomy_decision_framework.md)가 다스리는 판단을 내릴 때마다 여기에 1건 남기고, Superfan 은 그 기록을
  검토해 도전을 남기며, Q 는 응답한다(수용 = 무엇을 바꿨나 · 반박 = 근거). 규약 = 00_Lawbook/specs/superfan_protocol.md.

병목 방지는 writer 가 강제한다(규약 §4):
  · 등급 = stop(절대 규칙 위반 — 규칙 id 필수 · 그 결과의 사용만 보류) · challenge(응답 필수 · 응답 전에도 Q 는 진행) ·
    note(응답 불필요) · endorse(체계대로였음 확인 — 유지할 판단).
  · stop · challenge 는 대안 · 반증 조건 필수(대안 없는 반대 금지) · 리뷰 1건당 stop+challenge ≤ 5.
  · 재반박(counter)은 도전 1건당 1회 · 그 뒤 불일치 = disagreement 로 닫고 Q 판단 유지(stop 은 예외 — 수용 · 철회 · 도훈 판정만).
  · Superfan 은 결정 기록부에 쓰지 않는다(상신권 없음) — stop 불일치의 도훈 판정은 Q 가 dr_open 한 id 를 escalated 로 남긴다.

사용(저장소 루트 · 표준 라이브러리만):
  python 02_Infrastructure/programs/q_judgment_ledger.py record --op OP-… --kind <종류> --summary … --rationale …
         [--ref "§2-3 병목" …] [--evidence 경로 …] [--alt 대안 …] [--expect "검증 가능한 기대"] [--confidence 0.6] [--supersedes J-…]
  python … pending [--json]                        # 미검토 판단 + 응답 대기 도전(Superfan 입력 · Q 할 일)
  python … review --trigger T1|T2|T3|T4 --file 리뷰.md [--scope J-… …]   # 리뷰 등록 → R-id (scope 판단 = reviewed)
  python … raise  --review R-… --target J-…|SYSTEM --grade stop|challenge|note|endorse --claim …
         [--evidence …] [--rule PIT-C1|AXIS|TAU_D|…] [--alternative …] [--falsifier …]
  python … respond --id C-… --kind accept|rebut --text … [--change "바꾼 것"]      # Q
  python … counter --id C-… --text …                                              # Superfan(1회)
  python … settle  --id C-… --kind disagreement|withdrawn|escalated --text … [--dr 결정기록부id]
  python … outcome --id C-… --kind vindicated|refuted|moot --text …               # 뒤에 온 증거로 채점
  python … stats [--json] | show [--open] | boot-fragment
경로 재정의(검사 · 양성 대조용): 환경변수 QVEST_JUDGMENT_LEDGER_PATH.
"""
import argparse, datetime as dt, io, json, os, re, sys, tempfile

SCHEMA = "q_judgment_ledger_v1"
KINDS = ("round_selection", "candidate_selection", "design", "verdict", "escalation", "no_escalation",
         "stop_continue", "harness_change", "priority", "ops", "other")
GRADES = ("stop", "challenge", "note", "endorse")
RESPONSE_REQUIRED = ("stop", "challenge")
CAP_PER_REVIEW = 5                         # 리뷰 1건당 stop + challenge 상한(규약 §4 — 소음이 병목이 되지 않게)
TRIGGERS = ("T1", "T2", "T3", "T4")
ROLES = {"judgment": TRIGGERS, "philosophy": ("P1", "P2", "P3", "P4")}   # 판단 Superfan · 철학 Superfan(2026-10-16) — 구성요소 Superfan 은 감시기(superfan_watch.py)를 쓴다
DIRECTIONS = ("toward", "neutral", "away", "na")                        # 철학 방향 판정(P2 필수)
# 절대 규칙(CLAUDE.md 절대 규칙 · lean-loop '하지 않는 것' · pit.md) — 'stop' 은 이 목록에 걸릴 때만
ABSOLUTE_RULES = tuple(["PIT-C%d" % i for i in range(1, 16)] + [
    "AXIS",             # 고정 축(롱온리 · ≤25종 · 15bps · LIQ 2e8 · 측정 축 epoch)
    "TAU_D",            # 정보 경계 — 처방 · 선택 · 교훈에 2023~ 성과 사용
    "R2",               # 결과를 본 뒤 사전등록 변경
    "DOHOON_DECISION",  # dohoon_decision 임의 착수 · 상신 의무 항목 단독 결정
    "AX-008",           # R 계약 밖 수치(손계산 · 기억 속 수치) 인용
    "PROD_WRITE",       # 05_Production 수정
    "LIT_WRITE",        # 01_Literature 수정
    "HARDCODE",         # 근거 없는 수치 하드코딩(충실구현 · 판정 서술)
    "JUDGE_BEFORE_A",   # Grade A 전 Judge 스폰
    "BOOK_AUTO",        # BOOK 자동 등록
])
OPEN_STATES = ("open", "rebutted", "countered")   # 아직 끝나지 않은 도전
CLOSED_STATES = ("accepted", "disagreement", "withdrawn", "escalated", "closed_note")


def _root():
    here = os.path.dirname(os.path.abspath(__file__))
    return os.path.dirname(os.path.dirname(here))


def ledger_path(root=None):
    p = os.environ.get("QVEST_JUDGMENT_LEDGER_PATH")
    return p if p else os.path.join(root or _root(), "06_Registry", "q_judgment_ledger.json")


def _now():
    return dt.datetime.now().astimezone().strftime("%Y-%m-%dT%H:%M:%S%z")


def load(path):
    if not os.path.exists(path):
        return {"schema": SCHEMA, "updated_at": None, "judgments": [], "reviews": [], "challenges": []}
    with io.open(path, encoding="utf-8-sig") as f:
        d = json.load(f)
    if not isinstance(d, dict) or d.get("schema") != SCHEMA:
        raise ValueError("schema %r" % (d.get("schema") if isinstance(d, dict) else type(d).__name__))
    for k in ("judgments", "reviews", "challenges"):
        d.setdefault(k, [])
    return d


def save(path, d):
    d["updated_at"] = _now()
    os.makedirs(os.path.dirname(path), exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix=".q_judgment_ledger_", suffix=".tmp", dir=os.path.dirname(path))
    with io.open(fd, "w", encoding="utf-8") as f:
        json.dump(d, f, ensure_ascii=False, indent=1)
    os.replace(tmp, path)                      # 원자적 교체(부분 쓰기 없음)


def _die(msg):
    raise SystemExit("[q_judgment_ledger] " + msg)


def _next_id(items, prefix):
    day = dt.datetime.now().strftime("%Y%m%d")
    pat = re.compile(r"^%s-%s-(\d+)$" % (prefix, day))
    n = max([int(m.group(1)) for m in (pat.match(x.get("id", "")) for x in items) if m] + [0])
    return "%s-%s-%03d" % (prefix, day, n + 1)


def _find(items, iid, what):
    for x in items:
        if x.get("id") == iid:
            return x
    _die("%s 없음: %s" % (what, iid))


def _nonempty(v, name):
    if v is None or not str(v).strip():
        _die("%s 필수(비어 있음)" % name)
    return str(v).strip()


def cmd_record(a, d):
    if a.kind not in KINDS:
        _die("판단 종류 어휘 밖: %s (허용 %s)" % (a.kind, ", ".join(KINDS)))
    if a.confidence is not None and not (0.0 <= a.confidence <= 1.0):
        _die("confidence 는 0~1")
    j = {"id": _next_id(d["judgments"], "J"), "at": _now(), "op": a.op or "", "kind": a.kind,
         "summary": _nonempty(a.summary, "--summary"), "rationale": _nonempty(a.rationale, "--rationale"),
         "framework_refs": a.ref or [], "evidence": a.evidence or [], "alternatives": a.alt or [],
         "expectation": a.expect or "", "confidence": a.confidence, "status": "open", "reviews": [],
         "supersedes": a.supersedes or None, "superseded_by": None}
    if a.supersedes:
        old = _find(d["judgments"], a.supersedes, "대체 대상 판단")
        old["superseded_by"] = j["id"]
    d["judgments"].append(j)
    return j["id"]


def cmd_review(a, d):
    role = a.role or "judgment"
    if role not in ROLES:
        _die("역할 어휘 밖: %s (허용 %s)" % (role, ", ".join(ROLES)))
    if a.trigger not in ROLES[role]:
        _die("역할 %s 의 트리거 어휘 밖: %s (허용 %s)" % (role, a.trigger, ", ".join(ROLES[role])))
    if a.direction is not None and (role != "philosophy" or a.direction not in DIRECTIONS):
        _die("방향 판정은 철학 리뷰에만 · 어휘 %s" % ", ".join(DIRECTIONS))
    if role == "philosophy" and a.trigger == "P2" and a.direction is None:
        _die("철학 P2(판정) 리뷰는 --direction 필수(toward · neutral · away · na)")
    scope = a.scope or []
    for jid in scope:
        _find(d["judgments"], jid, "판단")
    r = {"id": _next_id(d["reviews"], "R"), "at": _now(), "role": role, "trigger": a.trigger, "scope": scope,
         "file": _nonempty(a.file, "--file"), "round": a.round or None, "direction": a.direction, "challenges": []}
    for jid in scope:
        j = _find(d["judgments"], jid, "판단")
        j["status"] = "reviewed"; j.setdefault("reviews", []).append(r["id"])
    d["reviews"].append(r)
    return r["id"]


def cmd_raise(a, d):
    r = _find(d["reviews"], a.review, "리뷰")
    if a.grade not in GRADES:
        _die("등급 어휘 밖: %s" % a.grade)
    if a.target != "SYSTEM":
        _find(d["judgments"], a.target, "대상 판단")
    claim = _nonempty(a.claim, "--claim")
    if a.grade in RESPONSE_REQUIRED:
        _nonempty(a.alternative, "--alternative(stop · challenge 는 대안 필수 — 대안 없는 반대 금지)")
        _nonempty(a.falsifier, "--falsifier(stop · challenge 는 반증 조건 필수 — 무엇을 보면 Superfan 이 틀린 것인가)")
        n = sum(1 for cid in r["challenges"]
                for c in d["challenges"] if c["id"] == cid and c["grade"] in RESPONSE_REQUIRED)
        if n >= CAP_PER_REVIEW:
            _die("리뷰 %s 의 stop+challenge 상한 %d 초과 — 영향 순으로 골라 나머지는 note 로" % (r["id"], CAP_PER_REVIEW))
    if a.grade == "stop":
        if a.rule not in ABSOLUTE_RULES:
            _die("stop 은 절대 규칙 위반에만 — --rule 이 %s 중 하나여야 한다(받음 %r)" % ("|".join(ABSOLUTE_RULES), a.rule))
    elif a.rule and a.rule not in ABSOLUTE_RULES:
        _die("--rule 어휘 밖: %s" % a.rule)
    c = {"id": _next_id(d["challenges"], "C"), "at": _now(), "review": r["id"], "target": a.target, "grade": a.grade,
         "rule": a.rule or None, "claim": claim, "evidence": a.evidence or [], "alternative": a.alternative or "",
         "falsifier": a.falsifier or "",
         "status": "open" if a.grade in RESPONSE_REQUIRED else "closed_note",
         "role": r.get("role", "judgment"), "hold_request": bool(a.hold),
         "responses": [], "outcome": None, "outcome_note": None}
    d["challenges"].append(c)
    r["challenges"].append(c["id"])
    return c["id"]


def _resp(c, by, kind, text, **kw):
    e = {"at": _now(), "by": by, "kind": kind, "text": text}
    e.update({k: v for k, v in kw.items() if v})
    c["responses"].append(e)


def cmd_respond(a, d):
    c = _find(d["challenges"], a.id, "도전")
    if c["status"] not in ("open", "countered"):
        _die("응답할 수 없는 상태: %s (%s)" % (c["id"], c["status"]))
    text = _nonempty(a.text, "--text")
    if a.kind == "accept":
        ch = _nonempty(a.change, "--change(수용 = 무엇을 바꿨나)")
        _resp(c, "Q", "accept", text, change=ch); c["status"] = "accepted"
    elif a.kind == "rebut":
        if c["status"] == "countered":
            _die("재반박 뒤 재응답은 없다 — settle(disagreement · escalated)로 닫는다: %s" % c["id"])
        _resp(c, "Q", "rebut", text); c["status"] = "rebutted"
    else:
        _die("응답 종류 어휘 밖: %s" % a.kind)


def cmd_counter(a, d):
    c = _find(d["challenges"], a.id, "도전")
    if c["status"] != "rebutted":
        _die("재반박은 Q 가 반박한 도전에만: %s (%s)" % (c["id"], c["status"]))
    if any(r.get("kind") == "counter" for r in c["responses"]):
        _die("재반박은 도전 1건당 1회: %s" % c["id"])
    _resp(c, "Superfan", "counter", _nonempty(a.text, "--text")); c["status"] = "countered"


def cmd_settle(a, d):
    c = _find(d["challenges"], a.id, "도전")
    if c["status"] not in OPEN_STATES:
        _die("이미 닫힌 도전: %s (%s)" % (c["id"], c["status"]))
    text = _nonempty(a.text, "--text")
    if a.kind == "disagreement":
        if c["grade"] == "stop":
            _die("stop 은 이견으로 닫지 않는다 — 수용(respond accept) · 철회(withdrawn) · 도훈 판정(escalated --dr)만: %s" % c["id"])
        if c["status"] not in ("rebutted", "countered"):
            _die("이견은 Q 반박 뒤에만: %s (%s)" % (c["id"], c["status"]))
    elif a.kind == "escalated":
        _nonempty(a.dr, "--dr(Q 가 dr_open 한 결정 기록부 id)")
    elif a.kind != "withdrawn":
        _die("종결 종류 어휘 밖: %s" % a.kind)
    _resp(c, "Q" if a.kind != "withdrawn" else "Superfan", a.kind, text, dr=a.dr)
    c["status"] = a.kind


def cmd_outcome(a, d):
    c = _find(d["challenges"], a.id, "도전")
    if a.kind not in ("vindicated", "refuted", "moot"):
        _die("결과 어휘 밖: %s" % a.kind)
    if c["grade"] not in RESPONSE_REQUIRED:
        _die("결과 채점은 stop · challenge 만: %s" % c["id"])
    c["outcome"] = a.kind; c["outcome_note"] = _nonempty(a.text, "--text"); c["outcome_at"] = _now()


def pending(d):
    js = [j for j in d["judgments"] if j.get("status") == "open" and not j.get("superseded_by")]
    cs = [c for c in d["challenges"] if c.get("status") in OPEN_STATES]
    return js, cs


def stats(d):
    C = d["challenges"]
    sc = [c for c in C if c["grade"] in RESPONSE_REQUIRED]
    by = lambda key, val: sum(1 for c in sc if c.get(key) == val)
    decided = [c for c in sc if c["status"] in ("accepted", "disagreement", "withdrawn", "escalated", "rebutted")]
    scored = [c for c in sc if c.get("outcome") in ("vindicated", "refuted")]
    return {
        "judgments": len(d["judgments"]),
        "judgments_reviewed": sum(1 for j in d["judgments"] if j.get("status") == "reviewed"),
        "reviews": len(d["reviews"]),
        "by_grade": {g: sum(1 for c in C if c["grade"] == g) for g in GRADES},
        "open": sum(1 for c in sc if c["status"] in OPEN_STATES),
        "open_stop": sum(1 for c in sc if c["status"] in OPEN_STATES and c["grade"] == "stop"),
        "accepted": by("status", "accepted"), "rebutted_or_disagreed": by("status", "rebutted") + by("status", "disagreement"),
        "withdrawn": by("status", "withdrawn"), "escalated": by("status", "escalated"),
        "acceptance_rate": (round(by("status", "accepted") / len(decided), 3) if decided else None),
        "vindicated": by("outcome", "vindicated"), "refuted": by("outcome", "refuted"),
        "hit_rate": (round(by("outcome", "vindicated") / len(scored), 3) if scored else None),
        "by_role": {ro: sum(1 for c in C if c.get("role", "judgment") == ro) for ro in ROLES},
        "holds_open": sum(1 for c in C if c.get("hold_request") and c["status"] in OPEN_STATES),
        "direction": [{"at": r["at"][:16], "round": r.get("round"), "direction": r.get("direction")}
                      for r in d["reviews"] if r.get("role") == "philosophy" and r.get("direction")],
    }


def boot_fragment(root=None):
    """부팅 Resume 줄 꼬리 — 비어 있으면 ''(소음 없음) · 판독 실패는 0 으로 접지 않는다."""
    try:
        d = load(ledger_path(root))
    except Exception as e:
        return "Superfan ?(원장 판독 실패 %s)" % type(e).__name__
    js, cs = pending(d)
    n_q = sum(1 for c in cs if c["status"] in ("open", "countered"))        # Q 차례(응답 · 종결)
    n_stop = sum(1 for c in cs if c["status"] in ("open", "countered") and c["grade"] == "stop")
    n_s = sum(1 for c in cs if c["status"] == "rebutted")                    # Superfan 차례(재반박 1회 또는 철회)
    parts = []
    if n_q:
        parts.append("Q 응답 대기 %d%s" % (n_q, (" (정지 %d)" % n_stop) if n_stop else ""))
    if n_s:
        parts.append("Superfan 차례 %d" % n_s)
    if js:
        parts.append("미검토 판단 %d" % len(js))
    n_hold = sum(1 for c in cs if c.get("hold_request"))
    if n_hold:
        parts.append("보류 요청 %d" % n_hold)
    return ("Superfan: " + " · ".join(parts)) if parts else ""


def show(d, only_open=False):
    L = ["# Q 판단 원장 · Superfan (%s)" % _now()[:16], ""]
    s = stats(d)
    L.append("- 판단 %d(검토 %d) · 리뷰 %d · 도전 %s · 응답 대기 %d(정지 %d) · 수용률 %s · 적중(사후) %s/%s" % (
        s["judgments"], s["judgments_reviewed"], s["reviews"], s["by_grade"], s["open"], s["open_stop"],
        s["acceptance_rate"], s["vindicated"], s["vindicated"] + s["refuted"]))
    js, cs = pending(d)
    L += ["", "## 응답 대기 도전"]
    L += ["- %s [%s%s] → %s · %s · 대안: %s · 상태 %s" % (c["id"], c["grade"], ("·" + c["rule"]) if c.get("rule") else "",
                                                     c["target"], c["claim"], c.get("alternative") or "—", c["status"])
          for c in cs] or ["- 없음"]
    L += ["", "## 미검토 판단"]
    L += ["- %s [%s] %s" % (j["id"], j["kind"], j["summary"]) for j in js] or ["- 없음"]
    if not only_open:
        L += ["", "## 최근 판단(10)"]
        L += ["- %s [%s · %s] %s" % (j["id"], j["kind"], j["status"], j["summary"]) for j in d["judgments"][-10:]] or ["- 없음"]
        L += ["", "## 최근 도전(10)"]
        L += ["- %s [%s] %s → %s · %s" % (c["id"], c["grade"], c["target"], c["status"], c["claim"][:120]) for c in d["challenges"][-10:]] or ["- 없음"]
    return "\n".join(L)


def main(argv=None):
    ap = argparse.ArgumentParser(prog="q_judgment_ledger")
    sp = ap.add_subparsers(dest="cmd", required=True)
    r = sp.add_parser("record"); r.add_argument("--op"); r.add_argument("--kind", required=True)
    r.add_argument("--summary", required=True); r.add_argument("--rationale", required=True)
    r.add_argument("--ref", action="append"); r.add_argument("--evidence", action="append"); r.add_argument("--alt", action="append")
    r.add_argument("--expect"); r.add_argument("--confidence", type=float); r.add_argument("--supersedes")
    p = sp.add_parser("pending"); p.add_argument("--json", action="store_true")
    v = sp.add_parser("review"); v.add_argument("--trigger", required=True); v.add_argument("--file", required=True)
    v.add_argument("--scope", nargs="*"); v.add_argument("--role"); v.add_argument("--direction"); v.add_argument("--round")
    x = sp.add_parser("raise"); x.add_argument("--review", required=True); x.add_argument("--target", required=True)
    x.add_argument("--grade", required=True); x.add_argument("--claim", required=True); x.add_argument("--evidence", action="append")
    x.add_argument("--rule"); x.add_argument("--alternative"); x.add_argument("--falsifier")
    x.add_argument("--hold", action="store_true")   # 보류 요청(철학 Superfan — 조립 · A 후보 · BOOK 전 도훈 확인 필요)
    q = sp.add_parser("respond"); q.add_argument("--id", required=True); q.add_argument("--kind", required=True)
    q.add_argument("--text", required=True); q.add_argument("--change")
    k = sp.add_parser("counter"); k.add_argument("--id", required=True); k.add_argument("--text", required=True)
    s = sp.add_parser("settle"); s.add_argument("--id", required=True); s.add_argument("--kind", required=True)
    s.add_argument("--text", required=True); s.add_argument("--dr")
    o = sp.add_parser("outcome"); o.add_argument("--id", required=True); o.add_argument("--kind", required=True); o.add_argument("--text", required=True)
    st = sp.add_parser("stats"); st.add_argument("--json", action="store_true")
    sh = sp.add_parser("show"); sh.add_argument("--open", action="store_true")
    sp.add_parser("boot-fragment")
    a = ap.parse_args(argv)
    if a.cmd == "boot-fragment":
        print(boot_fragment()); return 0
    path = ledger_path()
    d = load(path)
    if a.cmd == "pending":
        js, cs = pending(d)
        if a.json:
            print(json.dumps({"judgments": js, "challenges": cs}, ensure_ascii=False, indent=1))
        else:
            print("미검토 판단 %d · 응답 대기 도전 %d" % (len(js), len(cs)))
            for j in js: print("  %s [%s] %s" % (j["id"], j["kind"], j["summary"]))
            for c in cs: print("  %s [%s] → %s (%s) %s" % (c["id"], c["grade"], c["target"], c["status"], c["claim"][:100]))
        return 0
    if a.cmd == "stats":
        s = stats(d)
        print(json.dumps(s, ensure_ascii=False, indent=1) if a.json else " · ".join("%s=%s" % kv for kv in s.items()))
        return 0
    if a.cmd == "show":
        print(show(d, only_open=a.open)); return 0
    fn = {"record": cmd_record, "review": cmd_review, "raise": cmd_raise, "respond": cmd_respond,
          "counter": cmd_counter, "settle": cmd_settle, "outcome": cmd_outcome}[a.cmd]
    out = fn(a, d)
    save(path, d)
    print("[q_judgment_ledger] %s %s" % (a.cmd, out or getattr(a, "id", "")))
    return 0


if __name__ == "__main__":
    sys.exit(main())
