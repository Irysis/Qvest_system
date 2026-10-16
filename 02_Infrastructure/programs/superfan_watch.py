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
RULE_KINDS = ("log_patterns", "freshness", "expect_today", "json_field")
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
    """감시 상태(오프셋 · 이상 상태)는 운영 캐시다 — .cache(= C:/qm_cache 정션 · OneDrive 미동기화)에 둔다.
    등록부(06_Registry)에 두면 스캔마다 동기화가 일어난다(2026-10-16 도훈 질의 '10분 간격 이유' 검토에서 정정).
    서술형 이력은 구성요소 dossier 가 정본이다."""
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
        for r in c.get("rules", []):
            k = r.get("kind")
            rid = r.get("id", "")
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
    """이상 1건 갱신 — 같은 키면 count · last_seen 만. 확인(acked) · 만료(expired) · 해소(resolved)된 이상이 새 사건으로 다시 나오면 재개방."""
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
    if a["status"] in ("acked", "expired", "resolved") and from_new_lines:
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
    fn = {"log_patterns": _scan_log_rule, "freshness": _scan_freshness, "expect_today": _scan_expect_today, "json_field": _scan_json_field}
    for c in reg["components"]:
        if only and c["id"] != only:
            continue
        rules = [dict(r, max_event_age_h=r.get("max_event_age_h", dflt)) if r["kind"] == "log_patterns" else r for r in c.get("rules", [])]
        for r in rules:
            try:
                fn[r["kind"]](root, W, c["id"], r, now, events)
            except Exception as ex:                                    # 규칙 하나의 실패가 감시 전체를 멈추지 않게 — 그 자체를 이상으로
                _flag(W, events, c["id"], r.get("id", "?"), "warn", "감시 규칙 실행 실패 %s: %s" % (type(ex).__name__, ex), {}, now)
        W.setdefault("components", {})[c["id"]] = {"last_scan": _iso(now)}
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


def main(argv=None):
    ap = argparse.ArgumentParser(prog="superfan_watch")
    sp = ap.add_subparsers(dest="cmd", required=True)
    s = sp.add_parser("scan"); s.add_argument("--component"); s.add_argument("--quiet", action="store_true")
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
