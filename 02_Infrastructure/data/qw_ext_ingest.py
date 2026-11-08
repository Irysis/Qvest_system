"""qw_ext_ingest.py — 등록부(qw_updatefile_registry.json) group=ext 질의서의 범용 적재기.

왜(2026-11-08 · BUILD_20261108.md §2 · PLAN §3.6): glossary 코드로 만든 새 질의서(03_Universe/Update_File_ext/*.xlsx)는
  기존 Update_File 적재기(incremental_update_file.R — DB 이름 정확 일치 디스패치)에 등록되지 않는다. DB마다 적재기를 손으로 쓰지 않고,
  등록부의 시트 → 출력 대응만 보고 같은 규칙으로 싣는다.

판독(템플릿 OHLCVS_update.xlsx 와 같은 배치 · 11-08 실측): 행 8 = 종목 코드(배열 수식 결과) · B10 = 항목 코드 · 행 14 = 항목명 ·
  행 15~ = 데이터(A열 날짜). B6 = 'CPD-1TD [YYYYMMDD]'(애드인이 해석한 종료일 · 미해석 = 그 시트는 조회되지 않았다).

관문(하나라도 걸리면 그 DB는 적재 0 · 상태만 기록 · rc 3):
  G1 모든 질의 시트의 B6 괄호가 해석됐고 서로 같다 — 11-08 실사고: 중복 로그인으로 6시트 중 3시트만 조회된 DB가 저장됐다.
  G2 시트마다 B10 = 등록부 item_code · 데이터 마지막 날짜 = B6 괄호(질의 창이 끝까지 왔다).
  G3 날짜별 채움 수 / 직전 W 날짜 채움 중앙값 ≥ 문턱. 문턱 = min(0.5, 그 출력 기존 이력의 최근 1년 최저 비율) — 이력이 없으면 0.5.
     창 **끝** 쪽의 미달 날짜는 '미공표'로 보고 잘라낸다(공표 지평선 — 잔고 T+2 등 · 다음 밤 다시 받는다). 창 **가운데** 미달은 거부.
     zero_ok_calendar(공매도 금지 기간 등)에 든 날짜는 채움 검사에서 뺀다(파일이 없으면 예외 없음).
병합: 출력별 긴 표(Date · Ticker · Value · first_fetched_at · last_fetched_at). 받은 창(첫 날 ~ 공표 지평선)의 날짜는 전 종목 교체 —
  같은 (Date, Ticker) 는 first_fetched_at 을 보존한다(퀀티엔 빈티지가 없다 — 첫 수급 시각 = 의사 빈티지 · 정정 폭을 재는 재료).
원자 쓰기(tmp → os.replace). 금지: RAWDATA · 핵심 Update_File · 가용일 계산(관측 라벨만 싣는다 — 가용 규칙은 소비 쪽).
종료 코드: 0 적재 · 2 새것 없음(DB가 마지막 처리 뒤 바뀌지 않음) · 3 관문 거부 · 1 오류(등록 안 된 xlsx 가 Update_File_ext 에 있으면 1).

사용: python qw_ext_ingest.py [--book NAME] [--xlsx PATH(--initial 구간 DB)] [--root ROOT] [--force]
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import statistics
import sys
from pathlib import Path

ROOT_DEFAULT = Path(os.environ.get("QM_ROOT") or Path(__file__).resolve().parents[2])
W_MEDIAN = 20          # 직전 W 날짜 중앙값 — 기존 Universe_Support 적재기와 같은 창(incremental_update_file.R 채움 관문)
HIST_LOOKBACK = 250    # '최근 1년' 거래일 수(문턱 산출 창)
THR_CAP = 0.5          # 기존 적재기와 같은 상한 규약(min(0.5, 항목 1년 최저))
B6_RX = re.compile(r"\[(\d{8})\]")


def _now() -> str:
    return dt.datetime.now().isoformat(timespec="seconds")


def _to_date(v):
    if v is None or v == "":
        return None
    if isinstance(v, dt.datetime):
        return v.date()
    if isinstance(v, dt.date):
        return v
    if isinstance(v, (int, float)):           # Excel serial
        return (dt.datetime(1899, 12, 30) + dt.timedelta(days=float(v))).date()
    s = str(v).strip()
    for f in ("%Y-%m-%d", "%Y%m%d", "%Y/%m/%d"):
        try:
            return dt.datetime.strptime(s[:10], f).date()
        except ValueError:
            pass
    return None


def _num(v):
    if v is None or v == "":
        return None
    if isinstance(v, (int, float)):
        return float(v)
    try:
        return float(str(v).replace(",", ""))
    except ValueError:
        return None


def parse_book(xlsx: Path, sheets: list[str]) -> dict:
    """{sheet: {b6, b10, name14, codes, rows:[(date, [values])]}} — openpyxl read_only, handle closed."""
    import openpyxl
    wb = openpyxl.load_workbook(xlsx, read_only=True, data_only=True)
    out = {}
    try:
        names = set(wb.sheetnames)
        for s in sheets:
            if s not in names:
                raise ValueError(f"sheet '{s}' missing in {xlsx.name}")
            ws = wb[s]
            b6 = b10 = None
            codes, name14, rows = [], [], []
            for i, r in enumerate(ws.iter_rows(min_row=1, values_only=True), start=1):
                if i == 6:
                    b6 = r[1] if len(r) > 1 else None
                elif i == 8:
                    codes = [str(c).strip() if c not in (None, "") else "" for c in r[1:]]
                    while codes and codes[-1] == "":
                        codes.pop()
                elif i == 10:
                    b10 = r[1] if len(r) > 1 else None
                elif i == 14:
                    name14 = [x for x in r[1:1 + len(codes)]]
                elif i >= 15:
                    d = _to_date(r[0] if r else None)
                    if d is None:
                        break                      # 빈 날짜 = 데이터 끝
                    rows.append((d, [_num(x) for x in r[1:1 + len(codes)]]))
            bad = [c for c in codes if c == ""]
            if bad:
                raise ValueError(f"{s}: blank code inside row 8")
            if len(set(codes)) != len(codes):
                raise ValueError(f"{s}: duplicate ticker in row 8")
            out[s] = {"b6": b6, "b10": b10, "name14": next((x for x in name14 if x), None), "codes": codes, "rows": rows}
    finally:
        wb.close()
    return out


def _load_calendar(root: Path, rel: str | None):
    if not rel:
        return []
    p = root / rel
    if not p.exists():
        return []
    try:
        d = json.loads(p.read_text(encoding="utf-8"))
        return [(_to_date(w["from"]), _to_date(w["to"])) for w in d.get("windows", [])]
    except Exception:
        return []


def _in_cal(d, cal) -> bool:
    return any(a and b and a <= d <= b for a, b in cal)


def _hist_threshold(existing_fill: dict) -> tuple[float, str]:
    """기존 출력의 날짜별 채움 → 최근 1년 날짜별 (채움 / 직전 W 중앙값)의 최저 → min(0.5, 그 값)."""
    ds = sorted(existing_fill)
    ratios = []
    for i in range(W_MEDIAN, len(ds)):
        prev = [existing_fill[x] for x in ds[i - W_MEDIAN:i]]
        med = statistics.median(prev) if prev else 0
        if med > 0:
            ratios.append(existing_fill[ds[i]] / med)
    ratios = ratios[-HIST_LOOKBACK:]
    if not ratios:
        return THR_CAP, "no history -> cap"
    low = min(ratios)
    return min(THR_CAP, low), f"history low {low:.3f} over {len(ratios)}d"


def gate_and_window(sheet: str, p: dict, reg_sheet: dict, existing_fill: dict, cal) -> tuple[list, str]:
    """반환 (싣을 행 목록, 사유). 거부면 ([], '거부 사유')."""
    rows = p["rows"]
    if not rows:
        return [], "no data rows"
    fills = [(d, sum(1 for v in vals if v is not None)) for d, vals in rows]
    thr, why = _hist_threshold(existing_fill)
    hist = sorted(existing_fill.items())
    seq = [f for _, f in hist[-W_MEDIAN:] if f > 0]
    # 이력이 없으면(첫 적재) 받은 창 자체의 채움 중앙값을 기준으로 쓴다 — 기준이 비면 끝 쪽 부분 채움일이 실려
    # 다음 밤 앵커(최신일+1)가 다시 받지 않는 영구 결손이 된다.
    ref0 = statistics.median([f for _, f in fills if f > 0]) if any(f > 0 for _, f in fills) else 0
    ok = []
    for d, f in fills:
        med = statistics.median(seq) if seq else ref0
        good = (med == 0 or f / med >= thr or _in_cal(d, cal))
        ok.append(good)
        if good and f > 0:
            seq = (seq + [f])[-W_MEDIAN:]
    # 끝 쪽 미달 = 미공표(지평선 자르기) · 가운데 미달 = 거부
    last_good = max((i for i, g in enumerate(ok) if g), default=-1)
    if last_good < 0:
        return [], f"G3 every date below fill threshold {thr:.3f} ({why})"
    inner_bad = [rows[i][0] for i in range(last_good) if not ok[i]]
    if inner_bad:
        return [], f"G3 fill below threshold {thr:.3f} inside window on {inner_bad[:3]} ({why})"
    cut = len(rows) - 1 - last_good
    return rows[:last_good + 1], f"thr {thr:.3f} ({why}) · horizon {rows[last_good][0]}" + (f" · cut {cut} trailing unpublished" if cut else "")


def ingest_book(root: Path, book: dict, xlsx: Path | None, force: bool, state: dict) -> int:
    import pyarrow as pa
    import pyarrow.parquet as pq

    path = xlsx or (root / book["path"])
    if not path.exists():
        print(f"[ext-ingest] {book['name']}: book missing {path}")
        return 1
    mtime = path.stat().st_mtime
    bstate = state.setdefault(book["name"], {})
    if xlsx is None and not force and bstate.get("book_mtime") == mtime:
        print(f"[ext-ingest] {book['name']}: unchanged since last ingest — nothing new")
        return 2
    sheets = [s["sheet"] for s in book["sheets"]]
    parsed = parse_book(path, sheets)
    # G1 — 모든 시트 B6 해석 · 동일
    b6s = {}
    for s in sheets:
        m = B6_RX.search(str(parsed[s]["b6"] or ""))
        b6s[s] = m.group(1) if m else None
    unresolved = [s for s, v in b6s.items() if v is None]
    if unresolved or len(set(b6s.values())) != 1:
        msg = f"G1 Period(To) unresolved or unequal: {b6s}"
        print(f"[ext-ingest] {book['name']}: REFUSE {msg}")
        bstate.update({"gate": "refused", "reason": msg, "run_at": _now()})
        return 3
    to = _to_date(next(iter(b6s.values())))
    plan = {}
    for rs in book["sheets"]:
        s = rs["sheet"]; p = parsed[s]
        # G2 — 항목 코드 · 창 끝
        if str(p["b10"] or "").strip() != rs["item_code"]:
            msg = f"G2 {s}: B10 '{p['b10']}' != registry {rs['item_code']}"
            print(f"[ext-ingest] {book['name']}: REFUSE {msg}")
            bstate.update({"gate": "refused", "reason": msg, "run_at": _now()})
            return 3
        if p["rows"] and p["rows"][-1][0] != to:
            msg = f"G2 {s}: last data date {p['rows'][-1][0]} != Period(To) {to}"
            print(f"[ext-ingest] {book['name']}: REFUSE {msg}")
            bstate.update({"gate": "refused", "reason": msg, "run_at": _now()})
            return 3
        out = root / rs["output"]
        existing = pq.read_table(out) if out.exists() else None
        ex_fill = {}
        if existing is not None and existing.num_rows:
            cnt = {}
            for d, v in zip(existing.column("Date").to_pylist(), existing.column("Value").to_pylist()):
                if v is not None:
                    cnt[d] = cnt.get(d, 0) + 1
            ex_fill = cnt
        cal = _load_calendar(root, rs.get("zero_ok_calendar"))
        rows, why = gate_and_window(s, p, rs, ex_fill, cal)
        if not rows:
            print(f"[ext-ingest] {book['name']}: REFUSE {s}: {why}")
            bstate.update({"gate": "refused", "reason": f"{s}: {why}", "run_at": _now()})
            return 3
        if rs.get("item_name") and p["name14"] and str(p["name14"]).strip() != rs["item_name"]:
            print(f"[ext-ingest] {book['name']}: WARN {s} row-14 name '{p['name14']}' != registry '{rs['item_name']}' (vendor rename or code error)")
        plan[s] = (rs, p, rows, existing, why)
    # 병합 · 원자 쓰기(관문을 모두 통과한 뒤에만 쓴다 — DB 단위 원자성)
    now = _now()
    for s, (rs, p, rows, existing, why) in plan.items():
        out = root / rs["output"]
        out.parent.mkdir(parents=True, exist_ok=True)
        lo, hi = rows[0][0], rows[-1][0]
        first_seen = {}
        keep_d, keep_t, keep_v, keep_f, keep_l = [], [], [], [], []
        if existing is not None and existing.num_rows:
            ed = existing.column("Date").to_pylist(); et = existing.column("Ticker").to_pylist(); ev = existing.column("Value").to_pylist()
            ef = existing.column("first_fetched_at").to_pylist(); el = existing.column("last_fetched_at").to_pylist()
            for d, t, v, f, l in zip(ed, et, ev, ef, el):
                if lo <= d <= hi:
                    first_seen[(d, t)] = f
                else:
                    keep_d.append(d); keep_t.append(t); keep_v.append(v); keep_f.append(f); keep_l.append(l)
        n_new = 0
        for d, vals in rows:
            for t, v in zip(p["codes"], vals):
                if v is None:
                    continue
                keep_d.append(d); keep_t.append(t); keep_v.append(v)
                keep_f.append(first_seen.get((d, t), now)); keep_l.append(now); n_new += 1
        tbl = pa.table({"Date": pa.array(keep_d, pa.date32()), "Ticker": pa.array(keep_t, pa.string()), "Value": pa.array(keep_v, pa.float64()),
                        "first_fetched_at": pa.array(keep_f, pa.string()), "last_fetched_at": pa.array(keep_l, pa.string())})
        tbl = tbl.sort_by([("Date", "ascending"), ("Ticker", "ascending")])
        tmp = out.with_suffix(out.suffix + ".tmp")
        pq.write_table(tbl, tmp)
        os.replace(tmp, out)
        bstate.setdefault("outputs", {})[s] = {"item_code": rs["item_code"], "name14": p["name14"], "window": [str(lo), str(hi)],
                                                "rows_window": n_new, "rows_total": tbl.num_rows, "gate": why, "run_at": now}
        print(f"[ext-ingest] {book['name']}/{s}: {lo}..{hi} rows {n_new} (total {tbl.num_rows}) · {why}")
    if xlsx is None:
        bstate["book_mtime"] = mtime
    bstate.update({"gate": "ok", "reason": "", "run_at": now, "period_to": str(to)})
    return 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--book")
    ap.add_argument("--xlsx", help="--initial: 구간 이력 DB(같은 시트 · 고정 B5/B6)")
    ap.add_argument("--root", default=str(ROOT_DEFAULT))
    ap.add_argument("--registry")
    ap.add_argument("--state")
    ap.add_argument("--force", action="store_true")
    a = ap.parse_args()
    root = Path(a.root)
    reg = json.loads(Path(a.registry or root / "02_Infrastructure/data/qw_updatefile_registry.json").read_text(encoding="utf-8"))
    books = [b for b in reg["books"] if b.get("group") == "ext" and b.get("layout") == "ts"]
    # Update_File_ext 의 등록 안 된 xlsx = 오류(조용히 버리지 않는다 — PLAN F5)
    ext_dir = root / reg.get("ext_dir", "03_Universe/Update_File_ext")
    known = {Path(b["path"]).name.lower() for b in books}
    if ext_dir.exists():
        stray = [p.name for p in ext_dir.glob("*.xlsx") if not p.name.startswith(("~$", "~build_")) and p.name.lower() not in known]
        if stray:
            print(f"[ext-ingest] ERROR unregistered workbook(s) in {ext_dir}: {stray}")
            return 1
    if a.book:
        books = [b for b in books if b["name"] == a.book]
        if not books:
            print(f"[ext-ingest] unknown ext book {a.book}")
            return 1
    stp = Path(a.state or root / ".cache/qw_ext/_ingest_state.json")
    state = json.loads(stp.read_text(encoding="utf-8")) if stp.exists() else {}
    rcs = []
    for b in books:
        try:
            rcs.append(ingest_book(root, b, Path(a.xlsx) if a.xlsx else None, a.force, state))
        except Exception as e:  # noqa: BLE001
            print(f"[ext-ingest] {b['name']}: ERROR {e}")
            state.setdefault(b["name"], {}).update({"gate": "error", "reason": str(e), "run_at": _now()})
            rcs.append(1)
    stp.parent.mkdir(parents=True, exist_ok=True)
    tmp = stp.with_suffix(".tmp")
    tmp.write_text(json.dumps(state, ensure_ascii=False, indent=1, default=str), encoding="utf-8")
    os.replace(tmp, stp)
    if 1 in rcs:
        return 1
    if 3 in rcs:
        return 3
    return 0 if 0 in rcs else 2


if __name__ == "__main__":
    sys.exit(main())
