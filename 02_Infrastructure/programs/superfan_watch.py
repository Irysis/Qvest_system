"""구성요소 Superfan 감시기(2026-10-16 도훈 지시) — .cache/superfan_watch.json(운영 캐시) 의 유일한 writer.

왜: 도훈 "1개 컴포넌트 - 1개 에이전트 매칭 · 특정 대상의 광팬처럼 해당 컴포넌트에서 발생하는 모든 로그 · 에러 · 상태 변화를
  실시간으로 추적하고 분석하여 문제를 빠르게 해결하도록 돕는다 — superfan 에이전트에 이런 성격도 녹여줘".
  추적(감시)은 이 결정론 감시기가 한다(LLM 비용 0 · 수 초). 이상이 잡힌 구성요소만 그 구성요소의 전담 Superfan
  (.claude/agents/superfan.md 역할 B)을 띄워 원인을 진단하고 수리안을 낸다. 규약 = 00_Lawbook/specs/superfan_protocol.md §10.

구성요소 정의 = 06_Registry/superfan_components.json(사람이 편집 · 이 감시기가 검증). 규칙 종류:
  log_patterns  — 로그의 **새 줄만**(파일별 바이트 오프셋) 정규식 대조 · 심각도 fail/warn · 블록 제외(예: trigger=test 머리 아래 줄)
  freshness     — 파일 갱신 나이 > max_age_h 면 이상(파일 없음도 이상)
  expect_today  — 평일(선택) after 시각이 지났는데 오늘 날짜가 든 완료 표식 줄이 없으면 이상
  json_field    — JSON 상태 파일의 필드 값이 bad_values 중 하나면 이상
  (v10.2 · 2026-11-10 — 아래 셋은 기존 넷으로 못 잰다: 줄 단위 원장의 내용 · 두 파일 대조 · git 이력이 필요하다. 대상 파일이 없으면 무음)
  jsonl_ledger  — 추가 전용 JSONL 원장(round_core 상설 판 standing_ledger.jsonl · 강화 사슬 chain_steps.jsonl). check =
                  chain(줄마다 prev = 앞 줄 UTF-8 바이트 md5 · 첫 줄 'genesis' — 가벼운 재검사이지 rc_p4_steps_verify 의 재구현이 아니다) |
                  event_age(events 의 마지막 'at' 이 max_age_h 보다 오래됨 · edition_field 가 있으면 프로그램 폴더마다 가장 높은 판만) |
                  pending(open_event 뒤 같은 match_field 의 close_event 가 max_age_h 넘게 없음 · terminal_event 가 있으면 닫힌 원장 = 무음)
  ledger_covers — 완료 요약(summaries · ok_field ∈ ok_values)이 원장(ledger)의 마지막 완료 시각보다 새로운데 원장에 그 결정 id 가 없음
  ledger_activity — JSON 원장의 마지막 기록 시각이 max_age_h 보다 오래됐는데 그 뒤 git 커밋이 있음(git 실패 = 무음)
  새 세 종류는 숫자 문턱마다 max_age_h_source(근거 문구)를 요구한다.
이상은 (구성요소 · 규칙 · 정규화 문구)로 묶는다(숫자 → # · 공백 압축) — 같은 증상이 반복되면 count 만 오른다.
확인(ack)한 이상이 **새 줄에서 다시 나오면 재개방**한다(재발 = 아직 고장).

사용(저장소 루트 · 표준 라이브러리만):
  python 02_Infrastructure/programs/superfan_watch.py scan [--component id] [--quiet]
  python … show [--open] | brief --component id | boot-fragment
  python … ack --key K --kind fixed|known|noise --note "…"
경로 재정의(검사용): QVEST_SUPERFAN_REGISTRY_PATH · QVEST_SUPERFAN_WATCH_PATH · 기준 시각 QVEST_SUPERFAN_NOW("YYYY-MM-DD HH:MM").
"""
import argparse, datetime as dt, glob, hashlib, io, json, os, re, sys, tempfile

SCHEMA_REG = "superfan_components_v1"
SCHEMA_WATCH = "superfan_watch_v1"
RULE_KINDS = ("log_patterns", "freshness", "expect_today", "json_field", "jsonl_ledger", "ledger_covers", "ledger_activity")
JSONL_CHECKS = ("chain", "event_age", "pending")
SEVERITIES = ("fail", "warn")
FIRST_SCAN_BYTES = 2_000_000        # 처음 보는 로그는 끝 2MB 부터(과거 전부를 이상으로 쏟지 않게 · 최근 이력은 잡는다)
MAX_SCAN_BYTES = 20_000_000         # 한 번에 읽는 새 바이트 상한(거대 로그 보호 — 넘으면 끝 부분만 · 건너뜀을 기록)
TAIL_FOR_EXPECT = 3_000_000         # expect_today 는 파일 끝 3MB 에서 찾는다
MON = ("Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec")
DOW = ("Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun")


def _root():
    here = os.path.dirname(os.path.abspath(__file__))
    return os.path.dirname(os.path.dirname(here))


def registry_path(root=None):
    return os.environ.get("QVEST_SUPERFAN_REGISTRY_PATH") or os.path.join(root or _root(), "06_Registry", "superfan_components.json")


def watch_path(root=None):
    """감시 상태(오프셋 · 이상 상태)는 운영 캐시다 — .cache(git 제외)에 둔다. 서술형 이력은 구성요소 dossier 가 정본이다.
    10-16 에 등록부(06_Registry) 대신 .cache 를 고른 이유('스캔마다 동기화가 일어나지 않는다' — 도훈 질의 '10분 간격 이유'
    검토)는 2026-11-03 부터 참이 아니다: .cache 정션을 없애고 OneDrive 안 실제 폴더로 옮겨 두 기계가 공유한다(스캔마다 이 파일이 올라간다)."""
    return os.environ.get("QVEST_SUPERFAN_WATCH_PATH") or os.path.join(root or _root(), ".cache", "superfan_watch.json")


def _now():
    s = os.environ.get("QVEST_SUPERFAN_NOW")
    if s:
        return dt.datetime.strptime(s, "%Y-%m-%d %H:%M").astimezone()
    return dt.datetime.now().astimezone()


def _iso(t):
    return t.strftime("%Y-%m-%dT%H:%M:%S%z")


def _die(msg):
    raise SystemExit("[superfan_watch] " + msg)


def _read_json(path, default=None):
    if not os.path.exists(path):
        if default is not None:
            return default
        _die("파일 없음: %s" % path)
    with io.open(path, encoding="utf-8-sig") as f:
        return json.load(f)


def _save(path, d):
    d["updated_at"] = _iso(_now())
    os.makedirs(os.path.dirname(path), exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix=".superfan_watch_", suffix=".tmp", dir=os.path.dirname(path))
    with io.open(fd, "w", encoding="utf-8") as f:
        json.dump(d, f, ensure_ascii=False, indent=1)
    os.replace(tmp, path)


def _abs(root, p):
    p = os.path.expandvars(os.path.expanduser(p))
    return p if os.path.isabs(p) else os.path.join(root, p)


def _expand(root, pattern, now):
    """{YYYYMMDD} = 오늘 · 어제 둘 다(자정 넘긴 로그) · 와일드카드는 glob."""
    out = []
    days = [now, now - dt.timedelta(days=1)] if "{YYYYMMDD}" in pattern else [now]
    for t in days:
        p = _abs(root, pattern.replace("{YYYYMMDD}", t.strftime("%Y%m%d")))
        out += sorted(glob.glob(p)) if any(ch in p for ch in "*?[") else [p]
    seen = []
    for p in out:
        if p not in seen:
            seen.append(p)
    return seen


def _need_age(r, cid, rid):
    """v10.2 새 규칙 종류의 숫자 문턱 = 근거 문구와 함께만(근거 없는 숫자 거부 — round_core rules.R 의 basis/value_ref 원칙과 같은 뜻)."""
    e = []
    if not isinstance(r.get("max_age_h"), (int, float)) or isinstance(r.get("max_age_h"), bool) or r["max_age_h"] <= 0:
        e.append("%s/%s: max_age_h(양수) 필수" % (cid, rid))
    if not str(r.get("max_age_h_source") or "").strip():
        e.append("%s/%s: max_age_h_source(문턱 근거 문구) 필수" % (cid, rid))
    return e


def validate_registry(reg):
    e = []
    if not isinstance(reg, dict) or reg.get("schema") != SCHEMA_REG:
        return ["schema != %s" % SCHEMA_REG]
    ids = []
    for c in reg.get("components", []):
        cid = c.get("id", "")
        if not re.match(r"^[a-z][a-z0-9_]*$", cid):
            e.append("구성요소 id 형식: %r" % cid)
        ids.append(cid)
        if not c.get("name") or not c.get("dossier"):
            e.append("%s: name · dossier 필수" % cid)
        for fk, ty in (("sched_task", str), ("cause_key", str), ("notify", bool)):     # 경보 소음 정책 필드(2026-11-10)
            if fk in c and not isinstance(c[fk], ty):
                e.append("%s: %s 형식(%s)" % (cid, fk, ty.__name__))
        if c.get("notify") is False and not str(c.get("notify_reason") or "").strip():
            e.append("%s: notify=false 면 notify_reason(누가 대신 보내나) 필수" % cid)
        for r in c.get("rules", []):
            k = r.get("kind")
            rid = r.get("id", "")
            if "cause" in r:                                                 # 원인 키 부류(2026-11-10 2차)
                if r["cause"] not in CAUSE_CLASSES:
                    e.append("%s/%s: cause 어휘 밖 %r(task_run|own)" % (cid, rid, r["cause"]))
                elif r["cause"] == "task_run" and not c.get("sched_task"):
                    e.append("%s/%s: cause=task_run 은 구성요소 sched_task 필요" % (cid, rid))
            if k not in RULE_KINDS:
                e.append("%s: 규칙 종류 어휘 밖 %r" % (cid, k)); continue
            if not rid:
                e.append("%s: 규칙 id 없음" % cid)
            if k == "log_patterns":
                if not r.get("files"):
                    e.append("%s/%s: files 없음" % (cid, rid))
                for p in r.get("patterns", []):
                    if p.get("severity") not in SEVERITIES:
                        e.append("%s/%s: 심각도 어휘 밖 %r" % (cid, rid, p.get("severity")))
                    try:
                        re.compile(p.get("regex", ""))
                    except re.error as ex:
                        e.append("%s/%s: 정규식 오류 %s" % (cid, rid, ex))
                for x in r.get("exclude", []):
                    try:
                        re.compile(x)
                    except re.error as ex:
                        e.append("%s/%s: exclude 정규식 오류 %s" % (cid, rid, ex))
                if "max_event_age_h" in r and not isinstance(r["max_event_age_h"], (int, float)):
                    e.append("%s/%s: max_event_age_h 는 숫자" % (cid, rid))
                for k2 in ("skip_block_header", "block_header"):
                    if r.get(k2):
                        try:
                            re.compile(r[k2])
                        except re.error as ex:
                            e.append("%s/%s: %s 정규식 오류 %s" % (cid, rid, k2, ex))
            elif k == "freshness":
                if not r.get("file") or not isinstance(r.get("max_age_h"), (int, float)):
                    e.append("%s/%s: file · max_age_h 필수" % (cid, rid))
            elif k == "expect_today":
                if not r.get("file") or not r.get("pattern") or not re.match(r"^\d{2}:\d{2}$", r.get("after", "")):
                    e.append("%s/%s: file · pattern · after(HH:MM) 필수" % (cid, rid))
            elif k == "json_field":
                if not r.get("file") or not r.get("path") or not isinstance(r.get("bad_values"), list):
                    e.append("%s/%s: file · path · bad_values 필수" % (cid, rid))
            elif k == "jsonl_ledger":
                ck = r.get("check")
                if not r.get("files") or ck not in JSONL_CHECKS:
                    e.append("%s/%s: files · check(%s) 필수" % (cid, rid, "|".join(JSONL_CHECKS)))
                if ck == "event_age" and not (isinstance(r.get("events"), list) and r["events"]):
                    e.append("%s/%s: event_age 는 events 목록 필수" % (cid, rid))
                if ck == "pending" and not all(r.get(x) for x in ("open_event", "close_event", "match_field")):
                    e.append("%s/%s: pending 은 open_event · close_event · match_field 필수" % (cid, rid))
                if ck in ("event_age", "pending"):
                    e += _need_age(r, cid, rid)
            elif k == "ledger_covers":
                if not r.get("summaries") or not r.get("ledger") or not r.get("ok_field") or not isinstance(r.get("ok_values"), list) or not r.get("id_field"):
                    e.append("%s/%s: summaries · ledger · ok_field · ok_values · id_field 필수" % (cid, rid))
                for x in r.get("exclude", []):
                    try:
                        re.compile(x)
                    except re.error as ex:
                        e.append("%s/%s: exclude 정규식 오류 %s" % (cid, rid, ex))
            elif k == "ledger_activity":
                if not r.get("file"):
                    e.append("%s/%s: file 필수" % (cid, rid))
                e += _need_age(r, cid, rid)
            if k != "log_patterns" and r.get("severity") not in SEVERITIES:
                e.append("%s/%s: 심각도 어휘 밖 %r" % (cid, rid, r.get("severity")))
    dup = sorted({x for x in ids if ids.count(x) > 1})
    if dup:
        e.append("구성요소 id 중복: %s" % ", ".join(dup))
    return e


def _norm(text):
    t = re.sub(r"\d{4}-\d{2}-\d{2}[T ]?\d{0,2}:?\d{0,2}:?\d{0,2}", "<t>", text)
    t = re.sub(r"\d+(\.\d+)?", "#", t)
    return re.sub(r"\s+", " ", t).strip()[:240]


def _key(cid, rid, text):
    return hashlib.sha1(("%s|%s|%s" % (cid, rid, _norm(text))).encode("utf-8")).hexdigest()[:12]


def _record(W, cid, rid, sev, text, evidence, now, from_new_lines, event_time=None):
    """이상 1건 갱신 — 같은 키면 count · last_seen 만. 확인(acked) · 만료(expired)된 이상이 새 사건(새 로그 줄)으로 다시 나오면 재개방.
    해소(resolved)는 상태형 규칙이 정상 복귀했다는 뜻이므로, 그 뒤 같은 상태가 다시 잡히면 새 일화다 — 새 줄 여부와 무관하게 재개방한다
    (2026-11-10: 상태형 규칙은 from_new_lines 가 늘 거짓이라 해소 뒤 재발이 'seen' 으로 묻혀 알림이 영영 가지 않았다).
    확인(acked)한 상태가 그대로 이어지는 것은 재개방하지 않는다(정상 복귀를 거쳐야 새 일화)."""
    k = _key(cid, rid, text)
    A = W.setdefault("anomalies", {})
    a = A.get(k)
    ts = _iso(now)
    et = _iso(event_time) if event_time is not None else None
    if a is None:
        A[k] = {"key": k, "component": cid, "rule": rid, "severity": sev, "text": text[:400], "evidence": evidence,
                "first_seen": ts, "last_seen": ts, "event_time": et, "count": 1, "status": "open", "reopened": 0, "ack": None}
        return "new"
    a["last_seen"] = ts; a["count"] += 1; a["text"] = text[:400]; a["evidence"] = evidence
    if et:
        a["event_time"] = et
    if a["status"] == "resolved" or (a["status"] in ("acked", "expired") and from_new_lines):
        a["status"] = "open"; a["reopened"] += 1
        return "reopened"
    return "seen"


def _flag(W, events, cid, rid, sev, text, evidence, now, from_new_lines=False, event_time=None):
    """이상 기록 + 새 · 재개방이면 사건 줄을 남긴다(규칙 종류 공통)."""
    st = _record(W, cid, rid, sev, text, evidence, now, from_new_lines, event_time)
    if st != "seen":
        events.append("%s [%s] %s %s: %s" % (cid, sev, st, rid, text[:160]))


_TS_ISO = re.compile(r"(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2})(?::(\d{2}))?")
_TS_C = re.compile(r"\b(%s) (%s) +(\d{1,2}) (\d{2}):(\d{2}):(\d{2})\s+(?:[A-Z]{2,5}\s+)?(\d{4})\b" % ("|".join(DOW), "|".join(MON)))


def _line_time(ln, tz):
    """줄에 박힌 사건 시각(ISO 'YYYY-MM-DD HH:MM' · C 로캘 'Fri Oct 16 07:10:02 2026') — 없으면 None."""
    m = _TS_ISO.search(ln)
    if m:
        try:
            return dt.datetime(*(int(x) for x in m.groups()[:5]), int(m.group(6) or 0), tzinfo=tz)
        except ValueError:
            pass
    m = _TS_C.search(ln)
    if m:
        try:
            return dt.datetime(int(m.group(7)), MON.index(m.group(2)) + 1, int(m.group(3)), int(m.group(4)), int(m.group(5)), int(m.group(6)), tzinfo=tz)
        except ValueError:
            pass
    return None


def _file_date(path, tz):
    m = re.search(r"(20\d{2})(\d{2})(\d{2})", os.path.basename(path))
    if m:
        try:
            return dt.datetime(int(m.group(1)), int(m.group(2)), int(m.group(3)), tzinfo=tz)
        except ValueError:
            return None
    return None


def _rel(root, path):
    try:
        rp = os.path.relpath(path, root)
        return path.replace("\\", "/") if rp.startswith("..") else rp.replace("\\", "/")
    except ValueError:                                           # 다른 드라이브
        return path.replace("\\", "/")


def _paths(root, files, now):
    out = []
    for f in (files if isinstance(files, list) else [files]):
        for p in _expand(root, f, now):
            if p not in out:
                out.append(p)
    return out


def _scan_log_rule(root, W, cid, r, now, events):
    offs = W.setdefault("offsets", {})
    for path in _paths(root, r["files"], now):
        if not os.path.exists(path):
            continue
        key = _rel(root, path)
        okey = "%s/%s|%s" % (cid, r["id"], key)                 # 읽은 위치는 구성요소 · 규칙별 — 같은 로그를 여러 팬이 따로 본다
        size = os.path.getsize(path)
        o = offs.get(okey)
        if o is None:
            start = max(0, size - FIRST_SCAN_BYTES)
        else:
            start = o if o <= size else 0                    # 잘림 · 교체 → 처음부터
        if size - start > MAX_SCAN_BYTES:
            events.append("%s: %s 새 바이트 %d > 상한 — 끝 %d 바이트만 읽음" % (cid, os.path.basename(path), size - start, MAX_SCAN_BYTES))
            start = size - MAX_SCAN_BYTES
        aligned = start == 0 or (o is not None and start == o)   # 저장된 오프셋은 항상 줄 경계다
        if start >= size:
            offs[okey] = size
            continue
        with io.open(path, "rb") as f:
            f.seek(start)
            raw = f.read(size - start)
        if not aligned:                                      # 줄 중간에서 시작 — 첫 조각은 버린다
            nl = raw.find(b"\n")
            if nl < 0:
                offs[okey] = start; continue                  # 줄 끝이 아직 없다 — 다음 스캔에서
            start += nl + 1; raw = raw[nl + 1:]
        cut = raw.rfind(b"\n")                               # 끝이 줄 중간이면 그 조각은 다음 스캔으로 미룬다
        if cut < 0:
            offs[okey] = start; continue
        body = raw[:cut + 1]
        offs[okey] = start + cut + 1
        text = body.decode("utf-8", errors="replace")
        hdr = re.compile(r["block_header"]) if r.get("block_header") else None
        skip_hdr = re.compile(r["skip_block_header"]) if r.get("skip_block_header") else None
        excl = [re.compile(x) for x in r.get("exclude", [])]
        skipping = False
        pats = [(p["severity"], re.compile(p["regex"]), p.get("label", "")) for p in r.get("patterns", [])]
        max_age = dt.timedelta(hours=float(r["max_event_age_h"]))
        ctx = _file_date(path, now.tzinfo)              # 날짜형 파일 이름이면 그 날로 시작 · 이후 줄 · 블록 머리의 시각이 덮는다
        for ln in text.splitlines():
            t = _line_time(ln[:48], now.tzinfo)                # 줄 머리의 시각만 문맥으로(본문에 인용된 옛 시각이 문맥을 끌고 가지 않게)
            if t is not None:
                ctx = t
            if hdr is not None and hdr.search(ln):
                skipping = bool(skip_hdr.search(ln)) if skip_hdr is not None else False
                continue
            if skipping or any(x.search(ln) for x in excl):
                continue
            for sev, rx, label in pats:
                if rx.search(ln):
                    if ctx is not None and now - ctx > max_age:
                        break                               # 문턱보다 오래된 사건 — 세지 않는다(처음 스캔이 읽는 과거 이력)
                    if ctx is None and o is None:
                        break                               # 처음 스캔에서 시각을 모르는 줄 — 과거일 수 있어 세지 않는다
                    _flag(W, events, cid, r["id"], sev, ln.strip(), {"file": key, "label": label}, now, True,
                          event_time=ctx if ctx is not None else now)
                    break


def _scan_freshness(root, W, cid, r, now, events):
    if r.get("weekdays_only") and now.weekday() >= 5:
        return
    have = [p for p in _paths(root, r["file"], now) if os.path.exists(p)]   # 날짜형 · 와일드카드면 그중 가장 최근 파일
    if not have:
        msg = "파일 없음: %s" % r["file"]
    else:
        age_h = (now.timestamp() - max(os.path.getmtime(p) for p in have)) / 3600.0
        if age_h <= float(r["max_age_h"]):
            _clear(W, cid, r["id"], now); return
        msg = "갱신 %.0f시간 전(문턱 %s시간): %s" % (age_h, r["max_age_h"], r["file"])
    _flag(W, events, cid, r["id"], r["severity"], msg, {"file": r["file"]}, now)


def _clear(W, cid, rid, now):
    """상태형 규칙(신선도 · 완료 표식 · JSON 필드)이 정상으로 돌아오면 그 규칙의 열린 이상을 자동 해소한다."""
    for a in W.get("anomalies", {}).values():
        if a["component"] == cid and a["rule"] == rid and a["status"] in ("open", "acked"):
            a["status"] = "resolved"; a["resolved_at"] = _iso(now)


def _fmt_today(pattern, now):
    return (pattern.replace("{YYYY-MM-DD}", now.strftime("%Y-%m-%d")).replace("{dow}", DOW[now.weekday()])
            .replace("{mon}", MON[now.month - 1]).replace("{dd2}", "%2d" % now.day))


def _scan_expect_today(root, W, cid, r, now, events):
    if r.get("weekdays_only") and now.weekday() >= 5:
        return
    hh, mm = map(int, r["after"].split(":"))
    if (now.hour, now.minute) < (hh, mm):
        return
    path = _expand(root, r["file"], now)[0]
    needle = _fmt_today(r["pattern"], now)
    found = False
    if os.path.exists(path):
        size = os.path.getsize(path)
        with io.open(path, "rb") as f:
            f.seek(max(0, size - TAIL_FOR_EXPECT))
            found = needle in f.read().decode("utf-8", errors="replace")
    if found:
        _clear(W, cid, r["id"], now); return
    msg = "%s 이후 오늘 완료 표식 없음: '%s' (%s)" % (r["after"], needle, r["file"])
    _flag(W, events, cid, r["id"], r["severity"], msg, {"file": r["file"]}, now)


def _walk(obj, parts):
    if not parts:
        return [obj]
    if isinstance(obj, list):
        return [v for x in obj for v in _walk(x, parts)]
    if isinstance(obj, dict) and parts[0] in obj:
        return _walk(obj[parts[0]], parts[1:])
    return []


def _scan_json_field(root, W, cid, r, now, events):
    path = _abs(root, r["file"])
    try:
        vals = _walk(_read_json(path), r["path"].split("."))
    except Exception as ex:
        vals = ["?(판독 실패 %s)" % type(ex).__name__]
    bad = [v for v in vals if (isinstance(v, str) and (v in r["bad_values"] or v.startswith("?(")))]
    if not bad:
        _clear(W, cid, r["id"], now); return
    msg = "%s.%s = %s" % (r["file"], r["path"], ", ".join(sorted(set(map(str, bad)))))
    _flag(W, events, cid, r["id"], r["severity"], msg, {"file": r["file"]}, now)


# ── v10.2 규칙 종류(2026-11-10) — 상설 판 · 강화 사슬 원장 · 팩터 DB 판 표식 · 판단 원장 ─────────────────────────────
def _settle(W, cid, rid, now, keep):
    """여러 대상(파일)을 보는 상태형 규칙 — 이번 스캔에 다시 잡히지 않은 이상만 해소한다(한 파일이 정상이 됐다고 다른 파일의 이상을 닫지 않는다)."""
    for a in W.get("anomalies", {}).values():
        if a["component"] == cid and a["rule"] == rid and a["status"] in ("open", "acked") and a["key"] not in keep:
            a["status"] = "resolved"; a["resolved_at"] = _iso(now)


def _flag_all(W, events, cid, r, now, bad):
    keep = set()
    for text, ev in bad:
        _flag(W, events, cid, r["id"], r["severity"], text, ev, now)
        keep.add(_key(cid, r["id"], text))
    _settle(W, cid, r["id"], now, keep)


def _parse_at(s, tz):
    if not isinstance(s, str) or not s.strip():
        return None
    s = s.strip()
    for f in ("%Y-%m-%dT%H:%M:%S%z", "%Y-%m-%dT%H:%M%z"):
        try:
            return dt.datetime.strptime(s, f)
        except ValueError:
            pass
    try:
        t = dt.datetime.fromisoformat(s)
        return t if t.tzinfo else t.replace(tzinfo=tz)
    except ValueError:
        return None


def _jsonl(path):
    """줄 원문 바이트(빈 줄 제외 · 끝 CR 제거 — R readLines + nzchar 와 같은 줄) · 파싱 결과(실패 = None)."""
    with io.open(path, "rb") as f:
        raw = f.read()
    lines = [b.rstrip(b"\r") for b in raw.split(b"\n")]
    lines = [b for b in lines if b]
    recs = []
    for b in lines:
        try:
            x = json.loads(b.decode("utf-8"))
            recs.append(x if isinstance(x, dict) else None)
        except Exception:
            recs.append(None)
    return lines, recs


def _scan_jsonl_ledger(root, W, cid, r, now, events):
    ck = r["check"]
    files = [p for p in _paths(root, r["files"], now) if os.path.exists(p)]
    data = {p: _jsonl(p) for p in files}
    if ck == "event_age" and r.get("edition_field"):
        # 판 승계 — 같은 프로그램 폴더(원장의 두 단계 위)에서 가장 높은 판만 본다(옛 판은 새 항목을 받지 않는 게 정상)
        best = {}
        for p in files:
            ed = max([x.get(r["edition_field"]) for x in data[p][1] if x and isinstance(x.get(r["edition_field"]), (int, float))] or [-1])
            g = os.path.dirname(os.path.dirname(p))
            if g not in best or ed > best[g][0]:
                best[g] = (ed, p)
        files = [v[1] for v in best.values()]
    bad = []
    lim = dt.timedelta(hours=float(r.get("max_age_h", 0) or 0))
    for p in files:
        rel = _rel(root, p)
        lines, recs = data[p]
        if ck == "chain":
            prev, brk = "genesis", []
            for i, b in enumerate(lines):
                x = recs[i]
                if x is None or x.get("prev") != prev or (r.get("schema") and x.get("schema") != r["schema"]):
                    brk.append(i + 1)
                prev = hashlib.md5(b).hexdigest()
            if brk:
                bad.append(("원장 해시 사슬 끊김(줄 %s%s · 전 %d줄) — 추가 전용 위반 · 이 원장은 더 쓰이지 않는다: %s"
                            % (",".join(map(str, brk[:5])), " …" if len(brk) > 5 else "", len(lines), rel), {"file": rel}))
        elif ck == "event_age":
            ts = [_parse_at(x.get("at"), now.tzinfo) for x in recs if x and x.get("event") in r["events"]]
            ts = [t for t in ts if t is not None]
            what = "/".join(r["events"])
            if not ts:                                                     # 원장은 있는데 그 사건이 한 번도 없다 — 원장 첫 기록부터 잰다
                ts0 = [t for t in (_parse_at(x.get("at"), now.tzinfo) for x in recs if x) if t is not None]
                if not ts0:
                    bad.append(("원장 시각 판독 불가: %s" % rel, {"file": rel})); continue
                last, what = min(ts0), what + " 없음 · 원장 첫 기록"
            else:
                last = max(ts)
            if now - last > lim:
                bad.append(("마지막 %s %.0f시간 전(문턱 %s시간): %s" % (what, (now - last).total_seconds() / 3600.0, r["max_age_h"], rel), {"file": rel}))
        elif ck == "pending":
            if r.get("terminal_event") and any(x and x.get("event") == r["terminal_event"] for x in recs):
                continue                                                   # 닫힌 원장
            opened, closed = {}, set()
            for x in recs:
                if not x:
                    continue
                m = str(x.get(r["match_field"]))
                if x.get("event") == r["open_event"]:
                    opened[m] = _parse_at(x.get("at"), now.tzinfo)
                elif x.get("event") == r["close_event"]:
                    closed.add(m)
            for m, t in sorted(opened.items()):
                if m in closed:
                    continue
                if t is None:
                    bad.append(("열린 %s %s=%s 시각 판독 불가: %s" % (r["open_event"], r["match_field"], m, rel), {"file": rel}))
                elif now - t > lim:
                    bad.append(("%s %s=%s 가 %s 없이 %.0f시간(문턱 %s시간): %s" % (r["open_event"], r["match_field"], m, r["close_event"],
                                                                          (now - t).total_seconds() / 3600.0, r["max_age_h"], rel), {"file": rel}))
    _flag_all(W, events, cid, r, now, bad)


_ID_TOKEN = re.compile(r"[A-Za-z0-9][A-Za-z0-9_\-]*")


def _summary_time(path, s, r, tz):
    """요약의 완료 시각 = 시작 표지(stamp) + 소요(seconds) — 없으면 파일 수정 시각."""
    tf = r.get("time_from") or {}
    try:
        t = dt.datetime.strptime(str(s.get(tf["stamp_field"])), tf["stamp_format"]).replace(tzinfo=tz)
        if tf.get("plus_seconds_field") and isinstance(s.get(tf["plus_seconds_field"]), (int, float)):
            t += dt.timedelta(seconds=float(s[tf["plus_seconds_field"]]))
        return t
    except Exception:
        return dt.datetime.fromtimestamp(os.path.getmtime(path)).astimezone(tz)


def _scan_ledger_covers(root, W, cid, r, now, events):
    lp = _abs(root, r["ledger"])
    L = _read_json(lp, default={}) if os.path.exists(lp) else None
    entries = (L or {}).get(r.get("ledger_list", "entries"), []) if L is not None else []
    tfield = r.get("ledger_time_field", "completed_at")
    done = [t for t in (_parse_at(e.get(tfield), now.tzinfo) for e in entries if isinstance(e, dict)) if t is not None]
    last = max(done) if done else None
    ids = set()
    for e in entries:
        if isinstance(e, dict):
            for f in r.get("ledger_id_fields", ["id", "decision"]):
                ids.update(_ID_TOKEN.findall(str(e.get(f) or "")))
    excl = [re.compile(x) for x in r.get("exclude", [])]
    bad = []
    for p in _paths(root, r["summaries"], now):
        if not os.path.exists(p) or any(x.search(os.path.basename(p)) for x in excl):
            continue
        try:
            s = _read_json(p)
        except Exception:
            continue                                                       # 쓰는 중 · 깨진 요약은 판정하지 않는다(다음 스캔)
        if not isinstance(s, dict) or str(s.get(r["ok_field"])) not in [str(v) for v in r["ok_values"]]:
            continue
        t = _summary_time(p, s, r, now.tzinfo)
        if last is not None and t <= last:
            continue
        sid = str(s.get(r["id_field"]) or "").strip()
        rel = _rel(root, p)
        if L is None:
            bad.append(("판 표식 원장 없음 — 완료된 수리 요약이 있다: %s" % rel, {"file": rel}))
        elif not sid:
            bad.append(("완료된 수리 요약에 결정 id(%s) 없음 — 판 표식 원장에 못 잇는다: %s" % (r["id_field"], rel), {"file": rel}))
        elif sid not in ids:
            bad.append(("수리 '%s' 완료(%s)가 판 표식 원장의 마지막 완료(%s)보다 새로운데 원장에 그 결정 id 가 없다 — 원장 한 줄 누락: %s"
                        % (sid, _iso(t)[:16], _iso(last)[:16] if last else "없음", rel), {"file": rel, "ledger": r["ledger"]}))
    _flag_all(W, events, cid, r, now, bad)


def _git_commits_since(repo, since):
    import subprocess
    try:
        p = subprocess.run(["git", "-C", repo, "log", "--since=%s" % since.strftime("%Y-%m-%dT%H:%M:%S%z"), "--format=%h"],
                           capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=60)
        if p.returncode != 0:
            return None
        return sum(1 for ln in p.stdout.splitlines() if ln.strip())
    except Exception:
        return None


def _all_times(obj, keys, tz, out):
    if isinstance(obj, dict):
        for k, v in obj.items():
            if k in keys and isinstance(v, str):
                t = _parse_at(v, tz)
                if t is not None:
                    out.append(t)
            else:
                _all_times(v, keys, tz, out)
    elif isinstance(obj, list):
        for v in obj:
            _all_times(v, keys, tz, out)


def _scan_ledger_activity(root, W, cid, r, now, events):
    path = _abs(root, r["file"])
    if not os.path.exists(path):
        _clear(W, cid, r["id"], now); return                              # 원장이 없으면 무음
    d = _read_json(path)
    ts = []
    _all_times({k: d.get(k) for k in r.get("collections", ["judgments", "reviews", "challenges"])}, set(r.get("time_keys", ["at", "outcome_at"])), now.tzinfo, ts)
    if not ts:
        _clear(W, cid, r["id"], now); return
    last = max(ts)
    age_h = (now - last).total_seconds() / 3600.0
    if age_h <= float(r["max_age_h"]):
        _clear(W, cid, r["id"], now); return
    n = _git_commits_since(_abs(root, r.get("git_repo") or "."), last)
    if not n:                                                              # 커밋 0 = 쉰 것 · git 실패 = 모름(무음)
        _clear(W, cid, r["id"], now); return
    msg = "%s 마지막 기록 %s(%.0f시간 전 · 문턱 %s시간) — 그 뒤 저장소 커밋 %d건: 판단 기록 누락 의심" % (r["file"], _iso(last)[:16], age_h, r["max_age_h"], n)
    _flag(W, events, cid, r["id"], r["severity"], msg, {"file": r["file"], "commits_since": n}, now)


# ── 경보 소음 정책(2026-11-10 감사 레인 B · SKILL qvest-telegram §0.4 '평상 무음 · 실패는 1회 · 같은 원인 반복 발송 금지' 집행) ──────
#   ① 꺼진 것은 '낡음 · 정지'를 알리지 않는다 — 구성요소의 sched_task(예약 작업)가 task_health 산출(06_Registry/scheduler_task_health.json)에서
#      enabled = false 면 신선도 · 완료 표식 규칙을 재지 않는다(실측: 꺼진 ReinforceAutoLoop 의 로그 '파일 없음' 35회 · 2통).
#      판독 실패 · 작업 미수록 · 다른 기계가 잰 측정 · 낡은 측정(TASK_HEALTH_MAX_AGE_H) = 켜진 것으로 본다(경보 쪽 · fail-closed · 2026-11-10 2차).
#   ② 원인 하나 = 하루 한 통 — 원인 키를 ops/alert_dedup.py 저장소에 이상마다 잡는다(_anom_keys: 실행 실패 규칙(cause = task_run) = 'task:<작업>'
#      (task_health 경보와 같은 키) · cause_key 가 있으면 그 키 · 그 밖 = 'sf:<구성요소>:<규칙>:<이상 키>'). 확정(발송 성사) 뒤에만 '오늘 보냄' ·
#      못 잡은 이상은 '키 K 에 양보'로 적고 K 가 확정되지 않았으면 다음 실행에 다시 잡는다 · 발신 실패면 잡은 키를 완전히 놓는다.
#   ③ notify = false 구성요소는 기록만(다른 발신처가 같은 사실을 보내는 경우).
STALENESS_KINDS = ("freshness", "expect_today")


# task_health 측정을 '꺼짐' 판정에 믿는 최대 나이(시간). 근거 = task_health 실행 주기: Qvest_StrandedRepairs 12:00 · 20:00
#   (scheduler/Qvest_StrandedRepairs.bat · bootstrap.sh 4i '수집 담체') + 아침 체인 [0.7](morning_run.sh · 07:10 · 주말 · 실패일엔 빠질 수 있다).
#   가장 긴 정상 간격 = 20:00 → 다음 날 12:00 = 16시간(아침 체인이 빠진 날) · +1시간 여유(StrandedRepairs 앞 단계 · 수집 시간) = 17.
#   그보다 오래된 측정은 '모름' — 꺼짐을 믿지 않고 규칙을 잰다(억제는 fail-open 금지).
TASK_HEALTH_MAX_AGE_H = float(os.environ.get("QVEST_SUPERFAN_TASK_HEALTH_MAX_AGE_H", "17"))


def _machine():
    """측정 기계 이름 — scheduler_task_health.sh 의 measured_on 과 같은 식(alert_dedup.machine_name)."""
    import socket
    return os.environ.get("COMPUTERNAME") or socket.gethostname() or "?"


def _task_states(root, now=None):
    """{작업 이름: enabled(bool)} — task_health 산출에서. ★이 기계에서(measured_on) 최근에(measured_at ≤ TASK_HEALTH_MAX_AGE_H) 잰 것만 믿는다.
    판독 실패 · 기계 표식 없음 · 다른 기계 · 낡음 · 미래 시각 = {}(= 모두 켜진 것으로 · 억제하지 않는다 · fail-closed)."""
    p = os.environ.get("QVEST_SUPERFAN_TASK_HEALTH_PATH") or os.path.join(root, "06_Registry", "scheduler_task_health.json")
    try:
        with io.open(p, encoding="utf-8-sig") as f:
            h = json.load(f)
        if h.get("measured_on") != _machine():
            return {}
        ma = dt.datetime.strptime(str(h.get("measured_at"))[:19], "%Y-%m-%dT%H:%M:%S")
        nl = (now or _now()).replace(tzinfo=None)
        age_h = (nl - ma).total_seconds() / 3600.0
        if not (-0.25 <= age_h <= TASK_HEALTH_MAX_AGE_H):
            return {}
        tasks = h.get("tasks") or []
        if isinstance(tasks, dict):
            tasks = [tasks]
        return {t["task"]: (t.get("enabled") is not False) for t in tasks if t.get("task")}
    except Exception:
        return {}


def _task_disabled(states, name):
    return bool(name) and states.get(name) is False


def _dedup_path(root):
    """공유 저장소 경로. 감시 상태 경로를 재정의한 실행(시험)은 그 옆에 둔다 — 시험이 운영 저장소에 원인 키를 잡지 않게."""
    if os.environ.get("QVEST_ALERT_DEDUP_PATH"):
        return os.environ["QVEST_ALERT_DEDUP_PATH"]
    if os.environ.get("QVEST_SUPERFAN_WATCH_PATH"):
        return os.path.join(os.path.dirname(os.path.abspath(os.environ["QVEST_SUPERFAN_WATCH_PATH"])), "alert_dedup.json")
    return os.path.join(root, ".cache", "alert_dedup.json")


def _dedup():
    sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "ops"))
    try:
        import alert_dedup
        if os.environ.get("QVEST_SUPERFAN_NOW") and not os.environ.get("QVEST_ALERT_DEDUP_NOW"):
            os.environ["QVEST_ALERT_DEDUP_NOW"] = os.environ["QVEST_SUPERFAN_NOW"]   # 같은 기준 시각(시험)
        return alert_dedup
    except Exception:
        return None
    finally:
        sys.path.pop(0)


CAUSE_CLASSES = ("task_run", "own")


def _rule_of(comp, rid):
    return next((r for r in comp.get("rules", []) if r.get("id") == rid), {})


def _anom_keys(comp, a):
    """이상 하나의 원인 키(2026-11-10 2차) — '무엇이 실패했는가'까지 가른다.
    ① 규칙 cause = "task_run"(그 예약 작업의 실행 자체를 재는 규칙 — 로그가 안 갱신됨 · 완료 표식 없음) 이고 구성요소에 sched_task 가 있으면
       'task:<작업>' — task_health 의 실행 실패 경보와 같은 키(발신처 간에 접는 유일한 부류).
    ② 구성요소 cause_key(예: scheduler = task_health:digest — task_health 요약 줄 자체를 보는 구성요소) 가 있으면 그 키.
    ③ 그 밖(팩터 DB 빌드 게이트 · BOOK 시가평가 · 단계 실패 등 구성요소 고유 검사) = 'sf:<구성요소>:<규칙>:<이상 키>' — 같은 작업을 공유해도 자기 키.
    1차판은 sched_task 가 있으면 구성요소 · 규칙과 무관하게 'task:<작업>' 하나라, 작업을 공유하는 구성요소의 다른 실패가 서로를 묻었다."""
    r = _rule_of(comp, a.get("rule"))
    if r.get("cause") == "task_run" and comp.get("sched_task"):
        return ["task:%s" % comp["sched_task"]]
    if comp.get("cause_key"):
        return [comp["cause_key"]]
    return ["sf:%s:%s:%s" % (comp.get("id", a.get("component")), a.get("rule"), a["key"])]


def _cause_keys(comp, anoms):
    """여러 이상의 원인 키 합집합(순서 보존)."""
    out = []
    for a in anoms:
        for k in _anom_keys(comp, a):
            if k not in out:
                out.append(k)
    return out


def _summary(a, reg_comp=None):
    """알림 본문용 요약 한 문장 — 로그 원문 줄을 싣지 않는다(비밀 값 · 덤프 차단). 위치는 따로."""
    ev = a.get("evidence") or {}
    rule = a.get("rule", "")
    kind = ""
    for r in (reg_comp or {}).get("rules", []):
        if r.get("id") == rule:
            kind = r.get("kind", "")
    t = a.get("text") or ""
    if kind == "log_patterns":
        s = "로그에 '%s' 사건이 기록됨" % (ev.get("label") or rule)
    elif kind == "freshness":
        m = re.match(r"갱신 (\d+)시간 전\(문턱 ([\d.]+)시간\)", t)
        s = ("로그 갱신이 %s시간째 없음(문턱 %s시간)" % m.groups()) if m else ("기다리는 로그 파일이 아직 없음" if t.startswith("파일 없음") else "로그 신선도 이상")
    elif kind == "expect_today":
        m = re.match(r"(\d\d:\d\d) 이후", t)
        s = "오늘 %s 이후에도 완료 표식이 없음" % (m.group(1) if m else "정해진 시각")
    elif kind == "json_field":
        s = "상태 파일 값이 실패 상태임(%s)" % (t.split(" = ", 1)[-1][:60])
    else:
        s = re.sub(r"\s+", " ", t)[:120]
    return s


def scan(root=None, only=None):
    root = root or _root()
    reg = _read_json(registry_path(root))
    errs = validate_registry(reg)
    if errs:
        _die("구성요소 정의 검증 실패: " + " | ".join(errs))
    W = _read_json(watch_path(root), default={"schema": SCHEMA_WATCH, "updated_at": None, "offsets": {}, "anomalies": {}, "components": {}})
    if W.get("schema") != SCHEMA_WATCH:
        _die("감시 상태 schema 불일치")
    now = _now(); events = []
    dflt = float(reg.get("default_max_event_age_h", 48))
    fn = {"log_patterns": _scan_log_rule, "freshness": _scan_freshness, "expect_today": _scan_expect_today, "json_field": _scan_json_field,
          "jsonl_ledger": _scan_jsonl_ledger, "ledger_covers": _scan_ledger_covers, "ledger_activity": _scan_ledger_activity}
    states = _task_states(root, now)
    for c in reg["components"]:
        if only and c["id"] != only:
            continue
        rules = [dict(r, max_event_age_h=r.get("max_event_age_h", dflt)) if r["kind"] == "log_patterns" else r for r in c.get("rules", [])]
        off = _task_disabled(states, c.get("sched_task"))
        for r in rules:
            if off and r["kind"] in STALENESS_KINDS:          # ① 꺼진 작업의 낡음 · 미완료는 재지 않고 열린 것은 해소
                _clear(W, c["id"], r["id"], now)
                continue
            try:
                fn[r["kind"]](root, W, c["id"], r, now, events)
            except Exception as ex:                                    # 규칙 하나의 실패가 감시 전체를 멈추지 않게 — 그 자체를 이상으로
                _flag(W, events, c["id"], r.get("id", "?"), "warn", "감시 규칙 실행 실패 %s: %s" % (type(ex).__name__, ex), {}, now)
        W.setdefault("components", {})[c["id"]] = dict({"last_scan": _iso(now)}, **({"disabled_task": c["sched_task"]} if off else {}))
        # ② 해소 — 구성요소 고유 키(sf:…)는 그 이상이 정상 복귀(resolved)하면 지운다(같은 날 재발도 다시 1통).
        #    task:<작업> 키는 task_health 가 그 작업이 경보 뒤 건강하게 다시 돌았을 때 지운다(scheduler_task_health.sh · resolve-healthy) ·
        #    구성요소 cause_key 는 그 발신처 몫이라 여기서 안 지운다.
        if not c.get("cause_key"):
            gone = [k for a in W.get("anomalies", {}).values()
                    if a["component"] == c["id"] and a["status"] == "resolved" and a.get("resolved_at") == _iso(now)
                    for k in _anom_keys(c, a) if k.startswith("sf:")]
            dd = _dedup() if gone else None
            if dd:
                try:
                    dd.resolve(gone, path=_dedup_path(root))
                except Exception:
                    pass
        # 사건형(로그) 이상의 만료 — 마지막 사건이 문턱보다 오래되면 열린 목록에서 뺀다(같은 사건이 다시 나오면 재개방)
        log_rules = {r["id"]: float(r["max_event_age_h"]) for r in rules if r["kind"] == "log_patterns"}
        for a in W.get("anomalies", {}).values():
            if a["component"] == c["id"] and a["rule"] in log_rules and a["status"] == "open" and a.get("event_time"):
                et = dt.datetime.strptime(a["event_time"], "%Y-%m-%dT%H:%M:%S%z")
                if now - et > dt.timedelta(hours=log_rules[a["rule"]]):
                    a["status"] = "expired"; a["expired_at"] = _iso(now)
    _save(watch_path(root), W)
    return W, events


def open_anoms(W):
    return [a for a in W.get("anomalies", {}).values() if a["status"] == "open"]


# ── 무인 알림(도훈 2026-10-16 승인 — ① 1시간 결정론 감시 + ③ 감시기가 직접 보내는 텔레그램 · 야간 무음 · 사건당 1통) ──────────
#   대상 = 열린 'fail' 이상 중 아직 안 알린 것(재발로 재개방되면 다시 1통). 'warn' 은 알리지 않는다(부팅 줄 · 세션에서 본다).
#   구성요소마다 1통(같은 실행에서 같은 구성요소의 새 이상은 한 통에 묶는다). 23:00~06:59 은 무음(채팅에는 남고 알림 소리만 없다).
#   발신 = 02_Infrastructure/programs/superfan_notify.R(정본 발송기 tg_agent_brief) — 보낸 것이 확인된 구성요소만 '알림 완료' 표식(실패면 다음 시간에 다시).
NOTIFY_SEV = ("fail",)
QUIET_HOURS = (23, 7)


def pending_notify(W):
    out = []
    for a in W.get("anomalies", {}).values():
        if a["status"] != "open" or a["severity"] not in NOTIFY_SEV:
            continue
        n = a.get("notified")
        if n is None or int(n.get("reopened", 0)) < int(a.get("reopened", 0)):
            out.append(a)
    return out


def _send(root, payload):
    """payload → 발신기(기본 Rscript superfan_notify.R · 검사 주입 QVEST_SUPERFAN_NOTIFY_CMD). 반환 = {구성요소: 보냄 여부}."""
    fd, p = tempfile.mkstemp(prefix="superfan_notify_", suffix=".json")
    with io.open(fd, "w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False)
    cmd = os.environ.get("QVEST_SUPERFAN_NOTIFY_CMD", "").split() or ["Rscript", os.path.join(root, "02_Infrastructure", "programs", "superfan_notify.R")]
    import subprocess
    try:
        r = subprocess.run(cmd + [p], capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=300)
        out = r.stdout or ""
        # ★발신기 stderr(발송기 거부 문구 · R 오류)를 버리지 않는다 — 버리면 실패가 'rc=0 · 발신 실패' 한 줄로만 남아 원인을 못 본다
        #   (판단 Superfan T1 C-20261017-036: 16회 연속 실패 · 원인 문구 0). 예약 작업 로그(superfan_watch.log)로 간다.
        err = (r.stderr or "").strip()
        if r.returncode != 0 or err:
            sys.stderr.write("[superfan_watch] 발신기 rc=%s%s\n" % (r.returncode, ("\n" + err[-2000:]) if err else ""))
    except Exception as ex:                                            # 발신 실패 = 아무것도 보내지 않은 것으로(다음 시간에 다시)
        out = ""; sys.stderr.write("[superfan_watch] 발신 실패 %s: %s\n" % (type(ex).__name__, ex))
    finally:
        try:
            os.remove(p)
        except OSError:
            pass
    res = {}
    for ln in out.splitlines():
        f = ln.split("\t")
        if len(f) == 3 and f[0] == "SFN":
            res[f[1]] = (f[2].strip() == "ok")
    return res


def notify(root, W, now, baseline=False):
    """보낼 이상을 구성요소별로 묶어 발신 · 보낸 것만 표식. baseline = 지금 열린 것을 보내지 않고 '알린 것'으로 표식(처음 켤 때 옛 이상 소음 방지)."""
    pend = pending_notify(W)
    if baseline:
        if not pend:
            return []
        for a in pend:
            a["notified"] = {"at": _iso(now), "reopened": int(a.get("reopened", 0)), "baseline": True}
        return [("baseline", len(pend), None)]
    reg = _read_json(registry_path(root)) or {}
    comps = {c["id"]: c for c in reg.get("components", [])}
    names = {c["id"]: c.get("name", c["id"]) for c in reg.get("components", [])}
    dd = _dedup(); sent = []; claimed = {}
    # ★양보 재시도는 '새로 보낼 것'이 없는 실행에서도 본다(2026-11-10 2차 · 시나리오 S4d) — 양보한 이상은 이미 표식(notified)이 있어
    #   pending_notify 에 다시 나오지 않는다. 여기서 '보낼 것 없음'으로 먼저 돌아가면, 양보 상대가 발송에 실패하고 놓은 원인을
    #   아무도 다시 잡지 않는다(그 원인은 그날 0통 — 억제의 fail-open).
    pend = pend + _yield_retry(W, comps, dd, root, pend)
    if not pend:
        return []
    groups = {}
    for a in pend:
        groups.setdefault(a["component"], []).append(a)
    mute = now.hour >= QUIET_HOURS[0] or now.hour < QUIET_HOURS[1]
    # ③ notify = false → 보내지 않고 표식만(다른 발신처가 같은 사실을 보낸다 · 다시 시도하지 않는다).
    # ② 원인 키는 이상마다 잡는다(2026-11-10 2차) — 새로 잡은 키가 있는 이상만 보내고, 못 잡은 이상은 '키 K 에 양보'로만 적는다
    #    (알림 완료로 굳히지 않는다: 다음 실행에 K 가 그 날 이후 확정돼 있지 않으면 다시 잡는다 — _yield_retry).
    for cid in sorted(groups):
        c = comps.get(cid, {"id": cid}); L = groups[cid]
        if c.get("notify") is False:
            for a in L:
                a["notified"] = {"at": _iso(now), "reopened": int(a.get("reopened", 0)), "suppressed": "notify_off"}
            sent.append((cid, len(L), "notify_off"))
            del groups[cid]
            continue
        if dd is None:
            continue                                                   # 저장소 모듈 없음 = 보낸다(경보를 놓치지 않는 쪽)
        keep, yielded = [], []
        for a in L:
            keys = _anom_keys(c, a)
            try:
                r = dd.claim_ex(keys, source="superfan:%s" % cid, summary=_summary(a, c), path=_dedup_path(root))
            except Exception:
                keep.append(a); continue                               # 저장소 실패 = 보낸다
            if r["new"]:
                keep.append(a)
                claimed.setdefault(cid, [])
                claimed[cid] += [k for k in keys if not k.startswith("~") and k not in claimed[cid]]
            else:
                yielded.append(a)
                a["notified"] = {"at": _iso(now), "reopened": int(a.get("reopened", 0)), "suppressed": "dedup",
                                 "yield_keys": [k for k in keys if not k.startswith("~")], "yield_date": now.strftime("%Y-%m-%d")}
        if yielded:
            sent.append((cid, len(yielded), "dedup"))
        if keep:
            groups[cid] = keep
        else:
            del groups[cid]
    if not groups:
        return sent
    # text(원문)은 감시기 내부 payload 에만 남는다(임시 파일 · 발신 뒤 삭제) — 발신기 본문은 summary · where 만 쓴다(superfan_notify.R).
    keys = ("key", "rule", "text", "count", "first_seen", "last_seen", "event_time", "reopened")
    payload = {"at": _iso(now), "mute": mute,
               "groups": [{"component": cid, "name": names.get(cid, cid),
                           "anomalies": [dict({k: a.get(k) for k in keys}, summary=_summary(a, comps.get(cid)),
                                              where=(a.get("evidence") or {}).get("file") or "")
                                         for a in sorted(L, key=lambda x: x["last_seen"])]}
                          for cid, L in sorted(groups.items())]}
    res = _send(root, payload)
    for cid, L in sorted(groups.items()):
        if res.get(cid):
            for a in L:
                a["notified"] = {"at": _iso(now), "reopened": int(a.get("reopened", 0)), "mute": mute}
            if dd is not None and claimed.get(cid):
                try:
                    dd.confirm(claimed[cid], source="superfan:%s" % cid, path=_dedup_path(root))   # 발송 성사 → 확정(이것만 '오늘 보냄')
                except Exception:
                    pass
        elif dd is not None and claimed.get(cid):
            try:   # 발신 실패 — 내가 잡은 미확정 키를 완전히 놓는다(다른 발신처 · 다음 시간 실행이 다시 보낼 수 있게)
                dd.release(claimed[cid], path=_dedup_path(root), source="superfan:%s" % cid)
            except Exception:
                pass
        sent.append((cid, len(L), bool(res.get(cid))))
    return sent


def _yield_retry(W, comps, dd, root, pend):
    """'키 K 에 양보'한 이상 중 K 가 양보한 날 이후 확정된 적이 없는 것 — 다시 잡을 후보(양보 상대가 발송에 실패했거나 죽었다).
    양보 표식 없는 1차판 'dedup' 표식은 지금 계산한 키 · 표식 날짜로 본다(1차판에선 아무도 안 보낸 원인이 이 표식 뒤에 묻혔을 수 있다)."""
    if dd is None:
        return []
    have = {id(a) for a in pend}; out = []
    for a in W.get("anomalies", {}).values():
        n = a.get("notified") or {}
        if (id(a) in have or a["status"] != "open" or a["severity"] not in NOTIFY_SEV or n.get("suppressed") != "dedup"
                or int(n.get("reopened", 0)) < int(a.get("reopened", 0))):
            continue
        c = comps.get(a["component"], {"id": a["component"]})
        if c.get("notify") is False:
            continue
        keys = n.get("yield_keys") or [k for k in _anom_keys(c, a) if not k.startswith("~")]
        since = n.get("yield_date") or str(n.get("at") or "")[:10]
        try:
            if dd.settled(keys, since, path=_dedup_path(root)):
                continue
        except Exception:
            pass                                                       # 판독 실패 = 다시 시도하는 쪽
        out.append(a)
    return out


def boot_fragment(root=None):
    """부팅 Resume 줄 꼬리 — 열린 이상이 없으면 ''(소음 없음) · 판독 실패는 0 으로 접지 않는다(스캔은 하지 않는다 — 읽기만)."""
    try:
        W = _read_json(watch_path(root), default={"schema": SCHEMA_WATCH, "anomalies": {}})
        if W.get("schema") != SCHEMA_WATCH:
            raise ValueError("schema")
    except Exception as e:
        return "Superfan 감시 ?(상태 판독 실패 %s)" % type(e).__name__
    op = open_anoms(W)
    if not op:
        return ""
    nf = sum(1 for a in op if a["severity"] == "fail")
    comps = []
    for a in sorted(op, key=lambda a: (a["severity"] != "fail", a["component"])):
        if a["component"] not in comps:
            comps.append(a["component"])
    return "Superfan 감시: 이상 %d%s — %s" % (len(op), (" (실패 %d)" % nf) if nf else "", " · ".join(comps[:4]) + (" 외" if len(comps) > 4 else ""))


def show(W, only_open=False, root=None):
    reg = _read_json(registry_path(root or _root()), default={"components": []})
    names = {c["id"]: c.get("name", c["id"]) for c in reg.get("components", [])}
    L = ["# 구성요소 Superfan 감시 (%s · 상태 갱신 %s)" % (_iso(_now())[:16], (W.get("updated_at") or "?")[:16]), ""]
    for cid in [c["id"] for c in reg.get("components", [])]:
        an = [a for a in W.get("anomalies", {}).values() if a["component"] == cid and (a["status"] == "open" or not only_open)]
        st = "이상 %d" % sum(1 for a in an if a["status"] == "open") if an else "정상"
        L.append("## %s — %s · %s · 마지막 스캔 %s" % (cid, names.get(cid, cid), st, (W.get("components", {}).get(cid, {}).get("last_scan") or "—")[:16]))
        for a in sorted(an, key=lambda a: (a["status"] != "open", a["severity"] != "fail", a["last_seen"]), reverse=False):
            L.append("- `%s` [%s · %s] %s ×%d · 처음 %s · 마지막 %s%s" % (a["key"], a["severity"], a["status"], a["text"][:200], a["count"],
                                                                a["first_seen"][5:16], a["last_seen"][5:16],
                                                                (" · 확인: " + a["ack"]["note"]) if a.get("ack") else ""))
    return "\n".join(L)


def brief(W, cid, root=None):
    root = root or _root()
    reg = _read_json(registry_path(root))
    c = next((x for x in reg["components"] if x["id"] == cid), None)
    if c is None:
        _die("구성요소 없음: %s" % cid)
    an = [a for a in W.get("anomalies", {}).values() if a["component"] == cid and a["status"] == "open"]
    out = {"component": c, "open_anomalies": an, "dossier": c["dossier"]}
    return json.dumps(out, ensure_ascii=False, indent=1)


def ack(W, key, kind, note):
    a = W.get("anomalies", {}).get(key)
    if a is None:
        _die("이상 없음: %s" % key)
    if kind not in ("fixed", "known", "noise"):
        _die("확인 종류 어휘 밖: %s" % kind)
    if not (note or "").strip():
        _die("--note 필수(무엇을 했나 · 왜 괜찮은가)")
    a["status"] = "acked"; a["ack"] = {"kind": kind, "note": note.strip(), "at": _iso(_now())}
    # '고쳤다(fixed)' 확인 = 원인 해소 — 공유 저장소의 그 원인 키를 지운다(같은 날 재발도 다시 1통 · 2026-11-10 경보 소음 정책 ②).
    #   known · noise 는 원인이 살아 있다는 뜻이라 지우지 않는다.
    if kind == "fixed":
        dd = _dedup()
        if dd is not None:
            try:
                comps = {c["id"]: c for c in (_read_json(registry_path()) or {}).get("components", [])}
                dd.resolve(_anom_keys(comps.get(a["component"], {"id": a["component"]}), a), path=_dedup_path(_root()))
            except Exception:
                pass


def main(argv=None):
    ap = argparse.ArgumentParser(prog="superfan_watch")
    sp = ap.add_subparsers(dest="cmd", required=True)
    s = sp.add_parser("scan"); s.add_argument("--component"); s.add_argument("--quiet", action="store_true")
    s.add_argument("--notify", action="store_true"); s.add_argument("--baseline", action="store_true")
    sh = sp.add_parser("show"); sh.add_argument("--open", action="store_true")
    b = sp.add_parser("brief"); b.add_argument("--component", required=True)
    k = sp.add_parser("ack"); k.add_argument("--key", required=True); k.add_argument("--kind", required=True); k.add_argument("--note", required=True)
    sp.add_parser("boot-fragment"); sp.add_parser("validate")
    a = ap.parse_args(argv)
    if a.cmd == "boot-fragment":
        print(boot_fragment()); return 0
    if a.cmd == "validate":
        errs = validate_registry(_read_json(registry_path()))
        print("OK" if not errs else "\n".join(errs)); return 0 if not errs else 1
    if a.cmd == "scan":
        W, ev = scan(only=a.component)
        op = open_anoms(W)
        if not a.quiet or ev:
            print("[superfan_watch] 스캔 — 새 · 재개방 %d · 열린 이상 %d(실패 %d)" % (len(ev), len(op), sum(1 for x in op if x["severity"] == "fail")))
            for e in ev[:40]:
                print("  " + e)
        if a.notify or a.baseline:
            sent = notify(_root(), W, _now(), baseline=a.baseline)
            _save(watch_path(), W)
            for cid, n, ok in sent:
                if cid == "baseline":
                    print("[superfan_watch] 알림 기준선 — 지금 열린 실패 %d건은 보내지 않고 '알림 완료'로 표식" % n)
                elif ok in ("dedup", "notify_off"):
                    print("[superfan_watch] 알림 억제(%s) — %s %d건 · %s" % (ok, cid, n,
                          "같은 원인을 오늘 이미 보냄" if ok == "dedup" else "다른 발신처가 보내는 구성요소"))
                else:
                    print("[superfan_watch] 알림 %s — %s %d건" % ("보냄" if ok else "발신 실패(다음 시간에 다시)", cid, n))
        return 0
    W = _read_json(watch_path(), default={"schema": SCHEMA_WATCH, "anomalies": {}, "components": {}})
    if a.cmd == "show":
        print(show(W, only_open=a.open)); return 0
    if a.cmd == "brief":
        print(brief(W, a.component)); return 0
    if a.cmd == "ack":
        ack(W, a.key, a.kind, a.note); _save(watch_path(), W)
        print("[superfan_watch] ack %s" % a.key); return 0
    return 0


if __name__ == "__main__":
    sys.exit(main())
