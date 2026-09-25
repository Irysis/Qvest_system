"""fred_availability.py — 해외(FRED)·ECOS 시계열 가용시점 층 (PIT C11 · 안 B · S0 기반) — Python 동등판.

R 정본 = 02_Infrastructure/data/fred_availability.R . 같은 규칙 파일(06_Registry/fred_availability_rules.json)을
읽고 같은 알고리즘을 한 줄씩 대응시켜 같은 결과를 낸다(08_Tests/data/test_fred_availability.R 가 R↔py 를
전수 교차 검사). 근거 = 04_Research/01_reports/pit_c11_20260924/PIT_C11_verdict_20260924.md §② ·
decision_register PIT-C11-REMEDIATION · PIT-C11-CONVENTIONS. 이 파일에는 규칙 수치가 없다(하드코딩 금지).

핵심은 표준 라이브러리만 쓴다(QVEST_PY 에 pandas/pyarrow 가 없다). pandas DataFrame 을 넘기면
DataFrame 으로 돌려주고, 달력 기본 로더만 pyarrow 또는 pandas 가 필요하다(없으면 kr_calendar 주입).

인터페이스(R 과 같은 이름):
    fred_avail_rules(rules_path=None) -> dict
    fred_series_rule(series_id, rules=None) -> dict              미등록·금지 = FredAvailError
    fred_kr_calendar(path=None) -> list[date]
    fred_avail_date(series_id, obs_date, kr_calendar=None, rules=None) -> date | list[date|None]
    fred_avail_annotate(series, series_id, kr_calendar=None, rules=None, date_col="Date")
    fred_decision_date(kr_dates, mode, kr_calendar=None) -> list[date|None]
    fred_asof_join(kr_dates, series, series_id, mode="decision_close", kr_calendar=None, rules=None,
                   date_col="Date", value_col="Value", extend_calendar=True)
        -> list[dict] 또는 DataFrame(kr_date, decision_date, value, obs_date, avail_date, avail_basis,
                                      series_id, mode, vintage, vintage_resolved)
    fred_join_violations(kr_date, obs_date, series_id, mode="decision_close", kr_calendar=None, rules=None)
    fred_avail_rules_meta(rules_path=None) -> dict(version, md5, path, regime_key)

mode: "decision_close"(형태 a·c: avail ≤ 한국 d) | "exposure_return"(형태 b: avail ≤ 한국 t 직전 거래일).
"""
from __future__ import annotations

import bisect
import datetime as _dt
import hashlib
import json
import os
import sys

__all__ = [
    "FredAvailError", "fred_avail_rules", "fred_series_rule", "fred_kr_calendar", "fred_avail_date",
    "fred_avail_annotate", "fred_decision_date", "fred_asof_join", "fred_join_violations",
    "fred_avail_rules_meta",
]


class FredAvailError(ValueError):
    """가용시점 층의 fail-closed 거부(규칙 없음·금지 계열·규칙 파일 오류·모호한 입력)."""


_BOUND_PARAMS = {
    "kr_trading_days_after": ("n",),
    "label_plus_days": ("days",),
    "month_nth_kr_trading_day": ("month_offset", "n"),
    "month_day": ("month_offset", "day"),
    "us_release": (),
}
_RELEASE_PARAMS = {
    "label_plus_days": ("days",),
    "month_nth_weekday": ("month_offset", "weekday", "nth"),
    "us_business_days_after": ("n",),
    "month_nth_us_business_day": ("month_offset", "n"),
}
_CACHE: dict = {}


# ── 루트 ──────────────────────────────────────────────────────────────────────
def _norm(p):
    return str(p).replace("\\", "/")


def _code_root():
    o = os.environ.get("FRED_AVAIL_ROOT", "")
    if o:
        return _norm(o)
    here = os.path.abspath(__file__)
    if os.path.exists(here):
        return _norm(os.path.dirname(os.path.dirname(os.path.dirname(here))))
    r = os.environ.get("QM_ROOT", "")
    if r:
        return _norm(r)
    raise FredAvailError("[fred_avail] 코드 루트 미해석 — FRED_AVAIL_ROOT 또는 QM_ROOT")


def _data_root():
    o = os.environ.get("FRED_AVAIL_DATA_ROOT", "")
    if o:
        return _norm(o)
    r = os.environ.get("QM_ROOT", "")
    if r:
        return _norm(r)
    return _code_root()


# ── 날짜 ──────────────────────────────────────────────────────────────────────
def _to_ord(x):
    """date/datetime/'YYYY-MM-DD'/pandas Timestamp/numpy datetime64 → 서수(int). 결측 → None."""
    if x is None:
        return None
    if isinstance(x, float) and x != x:
        return None
    if isinstance(x, _dt.datetime):
        return x.date().toordinal()
    if isinstance(x, _dt.date):
        return x.toordinal()
    if hasattr(x, "to_pydatetime"):
        try:
            if x != x:  # NaT
                return None
        except Exception:
            pass
        return x.to_pydatetime().date().toordinal()
    s = str(x)[:10]
    if s in ("NaT", "nan", "None", "NA", ""):
        return None
    return _dt.date.fromisoformat(s).toordinal()


def _od(o):
    return None if o is None else _dt.date.fromordinal(o)


def _iso_wday(o):
    return _dt.date.fromordinal(o).isoweekday()  # 월=1 … 일=7


def _month_first(o, offset):
    d = _dt.date.fromordinal(o)
    m2 = d.month + int(offset)
    y2 = d.year + (m2 - 1) // 12
    m2 = (m2 - 1) % 12 + 1
    return _dt.date(y2, m2, 1).toordinal()


def _month_last(first):
    return _month_first(first, 1) - 1


def _nth_wday(first, wday_iso, nth):
    w = _iso_wday(first)
    if nth > 0:
        return first + ((wday_iso - w) % 7) + 7 * (nth - 1)
    last = _month_last(first)
    return last - ((_iso_wday(last) - wday_iso) % 7)


def _ymd(y, m, d):
    return _dt.date(int(y), int(m), int(d)).toordinal()


# ── 미국 연방 공휴일(5 U.S.C. §6103) + 추가 휴무 ─────────────────────────────────
def _observed(o):
    w = _iso_wday(o)
    return o - 1 if w == 6 else (o + 1 if w == 7 else o)


def _us_holidays(years, us):
    out = set()
    for y in years:
        f = lambda m: _ymd(y, m, 1)  # noqa: E731
        h = [_observed(_ymd(y, 1, 1))]
        if y >= us["mlk_from"]:
            h.append(_nth_wday(f(1), 1, 3))
        h.append(_nth_wday(f(2), 1, 3))
        h.append(_nth_wday(f(5), 1, -1))
        if y >= us["juneteenth_from"]:
            h.append(_observed(_ymd(y, 6, 19)))
        h.append(_observed(_ymd(y, 7, 4)))
        h.append(_nth_wday(f(9), 1, 1))
        h.append(_nth_wday(f(10), 1, 2))
        h.append(_observed(_ymd(y, 11, 11)))
        h.append(_nth_wday(f(11), 4, 4))
        h.append(_observed(_ymd(y, 12, 25)))
        out.update(h)
    out.update(us["extra"])
    return out


def _us_hol_set(lo, hi, us):
    y0 = _dt.date.fromordinal(lo).year - 1
    y1 = _dt.date.fromordinal(hi).year + 1
    key = ("ushol", y0, y1, tuple(sorted(us["extra"])), us["mlk_from"], us["juneteenth_from"])
    if key not in _CACHE:
        _CACHE[key] = frozenset(_us_holidays(range(y0, y1 + 1), us))
    return _CACHE[key]


def _is_us_bday(o, hol):
    return _iso_wday(o) <= 5 and o not in hol


def _us_roll(o, hol):
    for _ in range(40):
        if _is_us_bday(o, hol):
            return o
        o += 1
    raise FredAvailError("[fred_avail] 미국 영업일 탐색 실패")


def _us_bdays_after(o, n, hol):
    for _ in range(int(n)):
        o = _us_roll(o + 1, hol)
    return o


# ── 한국 거래일 위치(0-based, cal = 서수 오름차순) ────────────────────────────────
def _pick(cal, i):
    return cal[i] if 0 <= i < len(cal) else None


def _kr_gt(x, cal):
    return _pick(cal, bisect.bisect_right(cal, x))


def _kr_ge(x, cal):
    return _pick(cal, bisect.bisect_left(cal, x))


def _kr_nth_after(x, n, cal):
    if n == 0:
        return _kr_ge(x, cal)
    return _pick(cal, bisect.bisect_right(cal, x) + n - 1)


# ── 규칙 로드·검증 ─────────────────────────────────────────────────────────────
def _int_param(b, p, ctx, lo=None):
    v = b.get(p)
    if isinstance(v, bool) or not isinstance(v, (int, float)) or v != v or v != int(v) or (lo is not None and v < lo):
        raise FredAvailError(f"[fred_avail] 규칙 파일 오류: {ctx} — 정수 파라미터 '{p}' 누락/부적합")
    return int(v)


def _validate(raw, path):
    if raw.get("schema") != "fred_availability_rules/v1":
        raise FredAvailError(f"[fred_avail] 규칙 파일 schema 불일치: {path}")
    if not isinstance(raw.get("version"), str) or not raw["version"]:
        raise FredAvailError(f"[fred_avail] version 누락: {path}")
    ser = raw.get("series")
    if not isinstance(ser, list) or not ser:
        raise FredAvailError(f"[fred_avail] series 비어 있음: {path}")
    index = {}
    for i, s in enumerate(ser):
        sid = s.get("id")
        if not isinstance(sid, str) or not sid:
            raise FredAvailError(f"[fred_avail] series[{i + 1}] id 누락")
        st = s.get("status")
        if st not in ("active", "prohibited"):
            raise FredAvailError(f"[fred_avail] {sid}: status 는 active|prohibited (받음: {st})")
        if st == "active":
            bs = s.get("bounds")
            if not isinstance(bs, list) or not bs:
                raise FredAvailError(f"[fred_avail] {sid}: active 인데 bounds 없음")
            for k, b in enumerate(bs, start=1):
                ctx = f"{sid}.bounds[{k}]"
                ty = b.get("type")
                if ty not in _BOUND_PARAMS:
                    raise FredAvailError(f"[fred_avail] 규칙 파일 오류: {ctx} — 알 수 없는 bound type '{ty}'")
                if not isinstance(b.get("basis"), str) or not b["basis"]:
                    raise FredAvailError(f"[fred_avail] {ctx} — basis(근거) 누락")
                for p in _BOUND_PARAMS[ty]:
                    _int_param(b, p, ctx, lo=0)
                if ty == "us_release":
                    r = b.get("release")
                    if not isinstance(r, dict) or r.get("kind") not in _RELEASE_PARAMS:
                        raise FredAvailError(f"[fred_avail] {ctx} — release.kind 부적합")
                    for p in _RELEASE_PARAMS[r["kind"]]:
                        _int_param(r, p, ctx + ".release", lo=0)
                    if r["kind"] == "month_nth_weekday":
                        w = _int_param(r, "weekday", ctx, lo=1)
                        if w > 7:
                            raise FredAvailError(f"[fred_avail] {ctx} — weekday 는 ISO 1..7")
                    if b.get("kr_rule", "strictly_after") not in ("strictly_after", "on_or_after"):
                        raise FredAvailError(f"[fred_avail] {ctx} — kr_rule 부적합")
                    if "us_holiday_roll" in b and not isinstance(b["us_holiday_roll"], bool):
                        raise FredAvailError(f"[fred_avail] {ctx} — us_holiday_roll 은 bool")
            for k, o in enumerate(s.get("release_overrides") or [], start=1):
                try:
                    ok = (isinstance(o.get("source"), str) and bool(o["source"])
                          and _to_ord(o.get("obs")) is not None and _to_ord(o.get("us_release")) is not None)
                except Exception:
                    ok = False
                if not ok:
                    raise FredAvailError(f"[fred_avail] {sid}.release_overrides[{k}] — obs/us_release/source 부적합")
        keys = [sid] + [a for a in (s.get("aliases") or []) if a != sid]
        dup = [k for k in keys if k in index]
        if dup:
            raise FredAvailError(f"[fred_avail] 계열 키 충돌: {','.join(dup)} (id/aliases 는 전역 유일)")
        for k in keys:
            index[k] = i
    uc = raw.get("us_calendar") or {}
    try:
        extra = frozenset(_to_ord(e["date"]) for e in (uc.get("extra_closures") or []))
    except Exception as e:  # noqa: BLE001
        raise FredAvailError("[fred_avail] us_calendar.extra_closures 날짜 부적합") from e
    with open(path, "rb") as fh:
        md5 = hashlib.md5(fh.read()).hexdigest()
    return {
        "raw": raw, "path": _norm(path), "version": raw["version"], "index": index,
        "us": {"mlk_from": int(uc.get("mlk_from_year", 1986)),
               "juneteenth_from": int(uc.get("juneteenth_from_year", 2021)),
               "extra": extra},
        "md5": md5,
    }


def fred_avail_rules(rules_path=None):
    p = rules_path or os.path.join(_code_root(), "06_Registry", "fred_availability_rules.json")
    if not os.path.exists(p):
        raise FredAvailError(f"[fred_avail] 규칙 파일 없음(fail-closed): {p}")
    st = os.stat(p)
    key = ("rules", os.path.abspath(p), st.st_size, st.st_mtime_ns)
    if key in _CACHE:
        return _CACHE[key]
    with open(p, encoding="utf-8") as fh:
        raw = json.load(fh)
    R = _validate(raw, p)
    _CACHE[key] = R
    return R


def _rules(rules):
    if rules is None:
        return fred_avail_rules()
    if isinstance(rules, str):
        return fred_avail_rules(rules)
    if isinstance(rules, dict) and "index" in rules:
        return rules
    raise FredAvailError("[fred_avail] rules 인자는 None·경로·fred_avail_rules() 결과여야 한다")


def fred_series_rule(series_id, rules=None):
    R = _rules(rules)
    if not isinstance(series_id, str) or not series_id:
        raise FredAvailError("[fred_avail] series_id 는 문자열 1개")
    i = R["index"].get(series_id)
    if i is None:
        raise FredAvailError(f"[fred_avail] 규칙 없는 계열 '{series_id}' — 결합 거부(fail-closed). 규칙 파일: {R['path']}")
    s = R["raw"]["series"][i]
    if s.get("status") != "active":
        rep = s.get("replacement") or ""
        raise FredAvailError(
            f"[fred_avail] 계열 '{series_id}'(={s['id']}) 사용 금지 — {s.get('prohibition_basis', 'status!=active')}"
            + (f" · 대체 계열 id = '{rep}'" if rep else ""))
    return s


def fred_kr_calendar(path=None):
    p = path or os.environ.get("FRED_AVAIL_CALENDAR_PATH") or os.path.join(_data_root(), ".cache", "trading_calendar.parquet")
    if not os.path.exists(p):
        raise FredAvailError(f"[fred_avail] 한국 거래일 달력 없음: {p} — kr_calendar 를 주입하라")
    st = os.stat(p)
    key = ("cal", os.path.abspath(p), st.st_size, st.st_mtime_ns)
    if key in _CACHE:
        return list(_CACHE[key])
    try:
        import pyarrow.parquet as pq  # noqa: WPS433
        vals = pq.read_table(p, columns=["Date"]).column("Date").to_pylist()
    except ImportError:
        try:
            import pandas as pd  # noqa: WPS433
            vals = list(pd.read_parquet(p, columns=["Date"])["Date"])
        except ImportError as e:
            raise FredAvailError("[fred_avail] 달력 로드에 pyarrow/pandas 필요 — kr_calendar 를 주입하라") from e
    ords = sorted({o for o in (_to_ord(v) for v in vals) if o is not None})
    if not ords:
        raise FredAvailError(f"[fred_avail] 달력이 비어 있음: {p}")
    _CACHE[key] = tuple(ords)
    return [_dt.date.fromordinal(o) for o in ords]


def _cal(kr_calendar):
    if kr_calendar is None:
        kr_calendar = fred_kr_calendar()
    ords = [_to_ord(x) for x in kr_calendar]
    if not ords or any(o is None for o in ords):
        raise FredAvailError("[fred_avail] kr_calendar 가 비었거나 결측 포함")
    return sorted(set(ords))


# ── bound 계산 ────────────────────────────────────────────────────────────────
def _bound(b, o, cal, R, hol_hi):
    ty = b["type"]
    if ty == "kr_trading_days_after":
        return _kr_nth_after(o, int(b["n"]), cal)
    if ty == "label_plus_days":
        return _kr_ge(o + int(b["days"]), cal)
    if ty == "month_nth_kr_trading_day":
        ms = _month_first(o, int(b["month_offset"]))
        return _pick(cal, bisect.bisect_left(cal, ms) + int(b["n"]) - 1)
    if ty == "month_day":
        ms = _month_first(o, int(b["month_offset"]))
        me = _month_last(ms)
        return _kr_ge(min(ms + int(b["day"]) - 1, me), cal)
    if ty == "us_release":
        r = b["release"]
        hol = hol_hi()
        k = r["kind"]
        if k == "label_plus_days":
            rel = o + int(r["days"])
        elif k == "month_nth_weekday":
            rel = _nth_wday(_month_first(o, int(r["month_offset"])), int(r["weekday"]), int(r["nth"]))
        elif k == "us_business_days_after":
            rel = _us_bdays_after(o, int(r["n"]), hol)
        elif k == "month_nth_us_business_day":
            ms = _month_first(o, int(r["month_offset"]))
            rel = _us_bdays_after(ms - 1, int(r["n"]), hol)
        else:  # 검증에서 막힘
            raise FredAvailError(f"[fred_avail] release.kind 부적합: {k}")
        if b.get("us_holiday_roll", False):
            rel = _us_roll(rel, hol)
        if b.get("kr_rule", "strictly_after") == "on_or_after":
            return _kr_ge(rel, cal)
        return _kr_gt(rel, cal)
    raise FredAvailError(f"[fred_avail] 알 수 없는 bound type: {ty}")


def _avail_core(s, obs, cal, R):
    n = len(obs)
    avail = [None] * n
    basis = ["rule"] * n
    valid = [o for o in obs if o is not None and o >= cal[0]]
    if not valid:
        return avail, basis
    lo, hi = min(valid), max(valid) + 400
    hol_cache = {}

    def hol_hi():
        if "h" not in hol_cache:
            hol_cache["h"] = _us_hol_set(lo, hi, R["us"])
        return hol_cache["h"]

    ov = {}
    for x in s.get("release_overrides") or []:
        ov[_to_ord(x["obs"])] = _to_ord(x["us_release"])
    for i, o in enumerate(obs):
        if o is None or o < cal[0]:
            continue
        if o in ov:
            basis[i] = "override"          # R 과 같게: 가용일이 NA 여도 basis 는 override
        m = None
        dead = False
        for b in s["bounds"]:
            v = _bound(b, o, cal, R, hol_hi)
            if v is None:
                dead = True                # NA 전파 = fail-closed (R pmax 와 같다)
                break
            m = v if m is None else max(m, v)
        if dead:
            continue
        if o in ov:
            v = _kr_gt(_us_roll(ov[o], hol_hi()), cal)
            if v is None:
                continue
            m = max(m, v)
        avail[i] = m
    return avail, basis


def _scalar_or_list(x):
    if isinstance(x, (str, _dt.date)) or not hasattr(x, "__iter__"):
        return [x], True
    return list(x), False


def fred_avail_date(series_id, obs_date, kr_calendar=None, rules=None):
    R = _rules(rules)
    s = fred_series_rule(series_id, R)
    cal = _cal(kr_calendar)
    xs, scalar = _scalar_or_list(obs_date)
    av, _ = _avail_core(s, [_to_ord(x) for x in xs], cal, R)
    out = [_od(a) for a in av]
    return out[0] if scalar else out


def _weekday(o):
    return _iso_wday(o) <= 5


def _extend_cal(cal, kd):
    mx = cal[-1]
    ex = sorted({k for k in kd if k is not None and k > mx and _weekday(k)})
    return (sorted(set(cal) | set(ex)) if ex else cal), ex


def _decision_int(kd, mode, cal):
    if mode == "decision_close":
        return list(kd)
    if mode != "exposure_return":
        raise FredAvailError("[fred_avail] mode 는 decision_close|exposure_return")
    mx = cal[-1]
    calset = set(cal)
    bad = [k for k in kd if k is not None and ((k <= mx and k not in calset) or (k > mx and not _weekday(k)))]
    if bad:
        raise FredAvailError("[fred_avail] exposure_return: 한국 거래일이 아닌 kr_date — "
                             + ",".join(str(_od(b)) for b in bad[:5]) + " (수익 r_t 는 거래일에만 존재)")
    return [None if k is None else _pick(cal, bisect.bisect_right(cal, k - 1) - 1) for k in kd]


def fred_decision_date(kr_dates, mode, kr_calendar=None):
    cal = _cal(kr_calendar)
    kd = [_to_ord(x) for x in kr_dates]
    cal, _ = _extend_cal(cal, kd)
    return [_od(d) for d in _decision_int(kd, mode, cal)]


def _columns(series, date_col, value_col):
    """series → (dates, values, id_columns dict). DataFrame · dict of lists · list of (date, value)."""
    if hasattr(series, "columns"):  # pandas DataFrame
        cols = list(series.columns)
        for c in (date_col, value_col):
            if c not in cols:
                raise FredAvailError(f"[fred_avail] 열 없음: {c}")
        ids = {c: list(series[c]) for c in ("Series_ID", "Series") if c in cols}
        return list(series[date_col]), list(series[value_col]), ids
    if isinstance(series, dict):
        for c in (date_col, value_col):
            if c not in series:
                raise FredAvailError(f"[fred_avail] 열 없음: {c}")
        ids = {c: list(series[c]) for c in ("Series_ID", "Series") if c in series}
        return list(series[date_col]), list(series[value_col]), ids
    pairs = list(series)
    return [p[0] for p in pairs], [p[1] for p in pairs], {}


def _series_check(ids, s, series_id):
    ok_names = {s["id"], s.get("name"), *(s.get("aliases") or [])}
    for col, vals in ids.items():
        u = {v for v in vals if v is not None and not (isinstance(v, float) and v != v)}
        if len(u) > 1:
            raise FredAvailError(f"[fred_avail] series 에 계열이 섞임({col}: {sorted(map(str, u))[:5]}) — 한 계열만 넘겨라")
        if len(u) == 1:
            (v,) = u
            if v not in ok_names:
                raise FredAvailError(f"[fred_avail] series 의 {col}='{v}' 가 요청 계열 '{series_id}'(={s['id']})와 다름")


def _is_na(v):
    if v is None:
        return True
    try:
        return v != v
    except Exception:  # noqa: BLE001
        return False


def fred_avail_annotate(series, series_id, kr_calendar=None, rules=None, date_col="Date"):
    R = _rules(rules)
    s = fred_series_rule(series_id, R)
    cal = _cal(kr_calendar)
    if hasattr(series, "columns"):
        if date_col not in series.columns:
            raise FredAvailError(f"[fred_avail] 열 없음: {date_col}")
        _series_check({c: list(series[c]) for c in ("Series_ID", "Series") if c in series.columns}, s, series_id)
        av, basis = _avail_core(s, [_to_ord(x) for x in series[date_col]], cal, R)
        out = series.copy()
        out["avail_date"] = [_od(a) for a in av]
        out["avail_basis"] = basis
        return out
    rows = [dict(r) for r in series]
    av, basis = _avail_core(s, [_to_ord(r.get(date_col)) for r in rows], cal, R)
    for r, a, b in zip(rows, av, basis):
        r["avail_date"] = _od(a)
        r["avail_basis"] = b
    return rows


def _join_idx(dec, obs, av):
    """R .fa_join_idx 와 한 줄씩 대응. 반환 = 원본 인덱스 또는 None."""
    ok = [i for i in range(len(av)) if av[i] is not None and obs[i] is not None]
    if not ok:
        return [None] * len(dec)
    o = sorted(ok, key=lambda i: (av[i], obs[i]))
    A, src = [], []
    m = None
    for i in o:
        m = obs[i] if m is None else max(m, obs[i])
        if obs[i] == m:
            A.append(av[i])
            src.append(i)
    out = []
    for d in dec:
        if d is None:
            out.append(None)
            continue
        j = bisect.bisect_right(A, d)
        out.append(src[j - 1] if j > 0 else None)
    return out


def fred_asof_join(kr_dates, series, series_id, mode="decision_close", kr_calendar=None, rules=None,
                   date_col="Date", value_col="Value", extend_calendar=True):
    if mode not in ("decision_close", "exposure_return"):
        raise FredAvailError("[fred_avail] mode 는 decision_close|exposure_return")
    R = _rules(rules)
    s = fred_series_rule(series_id, R)
    dates, values, ids = _columns(series, date_col, value_col)
    _series_check(ids, s, series_id)
    obs, val = [], []
    for d, v in zip(dates, values):
        od = _to_ord(d)
        if od is None or _is_na(v):
            continue
        obs.append(od)
        val.append(v)
    if len(set(obs)) != len(obs):
        raise FredAvailError(f"[fred_avail] {s['id']}: 같은 관측일이 2행 이상 — 결합 모호(fail-closed)")
    kd = [_to_ord(x) for x in kr_dates]
    cal = _cal(kr_calendar)
    extended = []
    if extend_calendar:
        cal, extended = _extend_cal(cal, kd)
    av, basis = _avail_core(s, obs, cal, R)
    dec = _decision_int(kd, mode, cal)
    js = _join_idx(dec, obs, av)
    resolved = (s.get("vintage") or {}).get("revisions", "possible") == "none_known"
    rows = []
    for k, d, j in zip(kd, dec, js):
        rows.append({
            "kr_date": _od(k), "decision_date": _od(d),
            "value": None if j is None else val[j],
            "obs_date": None if j is None else _od(obs[j]),
            "avail_date": None if j is None else _od(av[j]),
            "avail_basis": None if j is None else basis[j],
            "series_id": s["id"], "mode": mode, "vintage": "latest", "vintage_resolved": resolved,
        })
    meta = {"rules_version": R["version"], "rules_md5": R["md5"],
            "calendar_extended": [_od(e) for e in extended]}
    if hasattr(series, "columns"):
        import pandas as pd  # noqa: WPS433
        df = pd.DataFrame(rows)
        df.attrs.update(meta)
        return df
    return _Rows(rows, meta)


class _Rows(list):
    """list[dict] + .attrs(rules_version·rules_md5·calendar_extended) — R attr 대응."""

    def __init__(self, rows, attrs):
        super().__init__(rows)
        self.attrs = attrs


def fred_join_violations(kr_date, obs_date, series_id, mode="decision_close", kr_calendar=None, rules=None):
    if mode not in ("decision_close", "exposure_return"):
        raise FredAvailError("[fred_avail] mode 는 decision_close|exposure_return")
    R = _rules(rules)
    s = fred_series_rule(series_id, R)
    kd = [_to_ord(x) for x in kr_date]
    ob = [_to_ord(x) for x in obs_date]
    if len(kd) != len(ob):
        raise FredAvailError("[fred_avail] kr_date 와 obs_date 길이 다름")
    cal, _ = _extend_cal(_cal(kr_calendar), kd)
    dec = _decision_int(kd, mode, cal)
    av, _ = _avail_core(s, ob, cal, R)
    out = []
    for i, (k, d, o, a) in enumerate(zip(kd, dec, ob, av), start=1):
        if o is None:
            continue
        if d is None:
            why = "decision_date_unresolved"
        elif a is None:
            why = "avail_unresolved(fail-closed)"
        elif a > d:
            why = "obs_not_yet_available"
        else:
            continue
        out.append({"row": i, "kr_date": _od(k), "decision_date": _od(d), "obs_date": _od(o),
                    "avail_date": _od(a), "reason": why, "series_id": s["id"], "mode": mode})
    return out


def fred_avail_rules_meta(rules_path=None):
    R = fred_avail_rules(rules_path)
    return {"version": R["version"], "md5": R["md5"], "path": R["path"],
            "regime_key": f"c11_avail:{R['version']}:{R['md5'][:8]}"}


# ── 교차 검사용 CLI (R 검사가 호출) ──────────────────────────────────────────────
def _parity(in_path, out_path):
    with open(in_path, encoding="utf-8") as fh:
        q = json.load(fh)
    rules = fred_avail_rules(q["rules_path"])
    cal = [_dt.date.fromisoformat(x) for x in q["calendar"]]
    res = {"meta": fred_avail_rules_meta(q["rules_path"]), "avail": [], "join": [], "errors": []}
    for a in q.get("avail", []):
        av, basis = _avail_core(fred_series_rule(a["series"], rules), [_to_ord(x) for x in a["obs"]], _cal(cal), rules)
        res["avail"].append({"series": a["series"], "avail": [None if v is None else str(_od(v)) for v in av],
                             "basis": basis})
    for jq in q.get("join", []):
        rows = fred_asof_join(jq["kr_dates"], {"Date": jq["obs"], "Value": jq["values"]}, jq["series"],
                              mode=jq["mode"], kr_calendar=cal, rules=rules)
        res["join"].append({"series": jq["series"], "mode": jq["mode"],
                            "obs_date": [None if r["obs_date"] is None else str(r["obs_date"]) for r in rows],
                            "decision_date": [None if r["decision_date"] is None else str(r["decision_date"]) for r in rows],
                            "value": [r["value"] for r in rows]})
    for sid in q.get("expect_error", []):
        try:
            fred_series_rule(sid, rules)
            res["errors"].append({"series": sid, "raised": False})
        except FredAvailError:
            res["errors"].append({"series": sid, "raised": True})
    with open(out_path, "w", encoding="utf-8") as fh:
        json.dump(res, fh, ensure_ascii=False)


if __name__ == "__main__":
    if len(sys.argv) == 4 and sys.argv[1] == "--parity":
        _parity(sys.argv[2], sys.argv[3])
        sys.exit(0)
    print("usage: fred_availability.py --parity <in.json> <out.json>", file=sys.stderr)
    sys.exit(2)
