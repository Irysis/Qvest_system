#!/usr/bin/env python
"""book_rebalance_preflight.py — BOOK 코드별 리밸런싱 사전 점검 (운영 정본).

**왜 신설인가** (2026-08-30 도훈 지시 "BOOK 코드별로 리밸런싱 표준화"):
BOOK 전략마다 필요한 코드·데이터·오버레이가 다르다. 그런데 지금까지는 리밸을 돌릴 때마다
사람이 기억에 의존해 러너를 호출했고, 그 결과 같은 날 세 가지 침묵 결함이 한꺼번에 드러났다:

  ① QuantiWise 다운로드는 성공했는데 **적재가 안 돼** 컨센서스·유니버스·수급이
     2026-07-24 에 정지. Gate A(원천 상태파일)와 Gate B(팩터DB 앵커)가 **둘 다 통과**했다 —
     앵커는 주가 축(API 경로·신선)이 채우기 때문이다. 영향: 20종 중 9종 교체.
  ② AE 국면 신호 생산자에 **호출자가 0건**이라 신호가 2026-08-01 에 정지. 소비자는
     직전 달을 조용히 재사용했고 PIT 가드는 오래될수록 더 잘 통과해 못 잡았다.
  ③ m4 BOCPD 팔이 271개월 내내 **0회 발화**. 규칙대로 도는 코드라 "정상"으로 보였다.

세 결함의 공통 기전은 하나다 — **잴 것을 안 재고 재기 쉬운 것을 쟀다.**
이 검사기는 그 셋을 각각 다른 축으로 잡는다:

  축 A. 신선도를 **소비면**에서 잰다 (원천 상태파일·mtime 아님. 실제로 읽히는 파케이의
        max(Date)). 미측정은 미달로 접지 않고 UNREADABLE 로 따로 보고한다 —
        '못 읽음'과 '낡음'이 같은 색이면 다음 사람이 원인을 게이트에서 찾는다.
  축 B. 각 입력의 **생산자가 리밸 경로에 배선돼 있는지** 선언과 대조한다. 배선 없는
        생산자는 사람이 기억해야 하고, 기억은 한 달을 못 간다.
  축 C. 각 오버레이 팔의 **역사 발화율**을 센다. `expect_alive: true` 인데 0회면
        그 팔은 죽은 것이다 — 경고가 없다는 사실은 팔이 살아 있다는 증거가 아니다.

★fail-closed: 판정 불가는 통과가 아니다. 사양 부재·패널 판독 실패는 BLOCK 으로 센다.

사용:
  python book_rebalance_preflight.py --book-id BOOK_0001 --as-of 2026-09-01
  python book_rebalance_preflight.py --book-id BOOK_0001 --as-of 2026-09-01 --json

종료코드: 0 GO / 1 BLOCK(차단 사유 있음) / 2 사양·환경 오류
"""
from __future__ import annotations

import argparse
import io
import json
import os
import sys

import pandas as pd
import pyarrow.parquet as pq

ROOT = os.environ.get("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot").replace("\\", "/")
os.chdir(ROOT)
SPEC = "02_Infrastructure/book/rebalance_spec.json"


def die(code: int, msg: str):
    print(f"[preflight] ERROR {msg}")
    sys.exit(code)


def _read_dates(path: str, col: str):
    """parquet 의 날짜열. 판독 실패는 None (=미측정 — '신선함'으로 접지 않는다)."""
    try:
        return pd.to_datetime(pq.read_table(path, columns=[col]).to_pandas()[col])
    except Exception:
        return None


def _prev_business_day(ts: pd.Timestamp) -> pd.Timestamp:
    d = ts - pd.Timedelta(days=1)
    while d.weekday() >= 5:
        d -= pd.Timedelta(days=1)
    return d


def _fmt(v, path: str) -> str:
    return path.replace("{as_of}", v["as_of"]).replace(
        "{as_of_compact}", v["as_of_compact"]).replace(
        "{sig_ym}", v["sig_ym"])


def check_inputs(spec, ctx):
    """축 A + 축 B — 소비면 신선도 · 생산자 배선."""
    rows = []
    for inp in spec["inputs"]:
        path = _fmt(ctx, inp["path"])
        rec = {"id": inp["id"], "path": path, "role": inp.get("role", ""),
               "wired": bool(inp.get("wired_in_runner")),
               "producer": inp.get("producer", ""),
               "manual_cmd": _fmt(ctx, inp.get("manual_cmd", "")) if inp.get("manual_cmd") else "",
               "known_defect": inp.get("known_defect", "")}
        if not os.path.exists(path):
            rec.update(verdict="MISSING", detail="파일 부재")
            rows.append(rec); continue
        d = _read_dates(path, inp["date_col"])
        if d is None or not len(d):
            rec.update(verdict="UNREADABLE", detail=f"{inp['date_col']} 판독 불가(미측정 — 미달과 구분)")
            rows.append(rec); continue
        mx = d.max()
        rec["max_date"] = str(mx.date())
        mode = inp["mode"]
        if mode == "decision":
            # 결정일 행이 **정확히** 있어야 한다. 직전 달 재사용을 신선함으로 읽지 않는다.
            n = int((d == ctx["as_of_ts"]).sum())
            rec["rows_at_as_of"] = n
            rec.update(verdict="OK" if n >= 1 else "STALE",
                       detail=f"as_of 행 {n}건 (패널 최대 {mx.date()})")
        elif mode == "anchor":
            want = ctx["sig_date"]
            rec.update(verdict="OK" if str(mx.date()) == want else "STALE",
                       detail=f"앵커 {mx.date()} (기대 {want})")
        else:  # data
            ref = ctx["baseline"]
            lag = int((ref - mx).days)
            rec["lag_days"] = lag
            tol = int(inp.get("max_lag_days", 7))
            rec.update(verdict="OK" if lag <= tol else "STALE",
                       detail=f"lag {lag}일 (관용 {tol}일, 기준선 {ref.date()})")
        rows.append(rec)
    return rows


def check_overlays(spec, ctx, panels):
    """축 C — 오버레이 팔의 역사 발화율 + as_of 시점 값."""
    rows = []
    for ov in spec["overlays"]:
        rec = {"id": ov["id"], "role": ov.get("role", ""),
               "expect_alive": bool(ov.get("expect_alive", True)),
               "note": ov.get("note", "")}
        pid = ov["panel"]
        path = panels.get(pid)
        if not path or not os.path.exists(path):
            rec.update(verdict="UNREADABLE", detail=f"패널 부재({pid})")
            rows.append(rec); continue
        try:
            df = pq.read_table(path).to_pandas()
            dc = ov["date_col"]
            df[dc] = pd.to_datetime(df[dc])
            df = df.drop_duplicates(dc).sort_values(dc)
            fire = df.eval(ov["fire_expr"])
        except Exception as e:
            rec.update(verdict="UNREADABLE", detail=f"{type(e).__name__}: {e}")
            rows.append(rec); continue
        n, k = len(df), int(fire.sum())
        rec.update(months=n, fired=k, rate=round(k / n * 100, 1) if n else 0.0)
        cur = df[df[dc] == ctx["as_of_ts"]]
        rec["at_as_of"] = (bool(fire[cur.index[0]]) if len(cur) and cur.index[0] in fire.index
                           else None)
        if rec["expect_alive"] and k == 0:
            rec.update(verdict="DEAD",
                       detail=f"{n}개월 내내 0회 발화 — 살아 있다는 증거가 없다")
        elif (not rec["expect_alive"]) and k > 0:
            rec.update(verdict="REVIVED",
                       detail=f"죽어 있어야 할 조건이 {k}회 발화 — 구판 회귀 의심")
        else:
            rec.update(verdict="OK", detail=f"{k}/{n} 발화 ({rec['rate']}%)")
        rows.append(rec)
    return rows


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--book-id", required=True)
    ap.add_argument("--as-of", required=True, help="홀딩월 1일 (예: 2026-09-01)")
    ap.add_argument("--json", action="store_true", help="기계 판독용 JSON 출력")
    a = ap.parse_args()

    if not os.path.exists(SPEC):
        die(2, f"사양 부재: {SPEC}")
    obj = json.load(io.open(SPEC, encoding="utf-8-sig"))
    spec = next((s for s in obj["specs"] if s["book_id"] == a.book_id), None)
    if spec is None:
        ids = ", ".join(s["book_id"] for s in obj["specs"])
        die(2, f"사양에 {a.book_id} 없음 — 등재된 book_id: {ids}. "
               f"신규 BOOK 은 {SPEC} 에 먼저 사양을 적어야 리밸이 표준화된다.")

    as_of = pd.Timestamp(a.as_of)
    if as_of.day != 1:
        die(2, f"--as-of 는 홀딩월 1일이어야 함: {a.as_of}")
    sig_ts = as_of - pd.Timedelta(days=1)
    # sig_date = 전월 마지막 **거래일**. benchmark 가 거래일 캘린더 단일 권위다.
    bd = _read_dates(".cache/benchmark.parquet", "Date")
    if bd is None:
        die(2, "benchmark.parquet 판독 불가 — 거래일 판정 불가(fail-closed)")
    in_m = bd[bd.dt.strftime("%Y%m") == sig_ts.strftime("%Y%m")]
    if not len(in_m):
        die(2, f"sig month {sig_ts.strftime('%Y%m')} 의 거래일이 benchmark 에 없음")
    ctx = {"as_of": a.as_of, "as_of_ts": as_of,
           "as_of_compact": as_of.strftime("%Y%m%d"),
           "sig_ym": sig_ts.strftime("%Y%m"),
           "sig_date": str(in_m.max().date()),
           "baseline": _prev_business_day(as_of)}

    inputs = check_inputs(spec, ctx)
    panels = {i["id"]: _fmt(ctx, i["path"]) for i in spec["inputs"]}
    overlays = check_overlays(spec, ctx, panels)

    blocks = [r for r in inputs if r["verdict"] in ("STALE", "MISSING", "UNREADABLE")]
    dead = [r for r in overlays if r["verdict"] in ("DEAD", "REVIVED", "UNREADABLE")]
    verdict = "GO" if not blocks else "BLOCK"

    if a.json:
        print(json.dumps({"book_id": a.book_id, "as_of": a.as_of, "verdict": verdict,
                          "sig_date": ctx["sig_date"], "inputs": inputs,
                          "overlays": overlays}, ensure_ascii=False, indent=2, default=str))
        return 0 if verdict == "GO" else 1

    print(f"===== BOOK 리밸 사전점검 | {a.book_id} | as_of={a.as_of} =====")
    print(f"  전략: {spec['strategy_id']}  ·  sig_date={ctx['sig_date']}  ·  기준선={ctx['baseline'].date()}")
    print(f"\n-- 축 A/B: 입력 신선도(소비면) + 생산자 배선 --")
    for r in inputs:
        mark = {"OK": "OK  ", "STALE": "STALE", "MISSING": "MISS", "UNREADABLE": "UNRD"}[r["verdict"]]
        wire = "배선O" if r["wired"] else "배선X"
        print(f"  [{mark}] {r['id']:18s} {wire}  {r.get('detail','')}")
        if r["verdict"] != "OK" and r.get("manual_cmd"):
            print(f"          → 선행 실행: {r['manual_cmd']}")
        if r["verdict"] != "OK" and r.get("known_defect"):
            print(f"          ※ {r['known_defect']}")
    print(f"\n-- 축 C: 오버레이 팔 생존 (역사 발화율) --")
    for r in overlays:
        mark = {"OK": "OK  ", "DEAD": "DEAD", "REVIVED": "REVIV", "UNREADABLE": "UNRD"}[r["verdict"]]
        cur = {True: "발화", False: "미발화", None: "as_of행없음"}[r.get("at_as_of")]
        print(f"  [{mark}] {r['id']:22s} {r.get('detail','')}  · as_of {cur}")
        if r["verdict"] != "OK" and r.get("note"):
            print(f"          ※ {r['note']}")

    print(f"\n===== 판정: {verdict} =====")
    if blocks:
        print("  차단 사유(입력):")
        for r in blocks:
            print(f"    · {r['id']} — {r['detail']}")
        print("  ★낡은 입력으로 리밸을 돌리지 않는다. 위 선행 실행 명령을 먼저 돌릴 것.")
    if dead:
        print("  ⚠오버레이 경고(차단 아님 — 사람 판단):")
        for r in dead:
            print(f"    · {r['id']} — {r['detail']}")
    if verdict == "GO":
        print(f"  실행: {_fmt(ctx, spec['runner']['cmd'])}")
    return 0 if verdict == "GO" else 1


if __name__ == "__main__":
    sys.exit(main())
