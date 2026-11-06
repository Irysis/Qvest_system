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
  축 B. 각 입력이 **러너 산출인지 외부 적재인지** 선언과 대조한다.
  축 C. 각 오버레이 팔의 **역사 발화율**을 센다. `expect_alive: true` 인데 0회면
        그 팔은 죽은 것이다 — 경고가 없다는 사실은 팔이 살아 있다는 증거가 아니다.

★경계 (도훈 지시 2026-08-30): **데이터 적재는 이 스킬 소관이 아니다.**
  QuantiWise/DART/MCP/API 적재는 데이터 리프레시 쪽이 소유한다 —
  신선도 판정 정본 `02_Infrastructure/ops/morning_steps/freshness_audit.R`,
  보장 진입점 `02_Infrastructure/ops/ensure_data_current.sh`.
  여기서는 **전제 충족 여부만 재고, 미달이면 중단해 그쪽으로 넘긴다.**
  리프레시 명령을 안내하거나 대신 실행하지 않는다(경계가 무너지면 같은 값을 두 곳에서
  만들게 되고, 두 곳에서 만든 값은 반드시 갈라진다).

★죽은 축은 차단이다 (같은 지시): "죽은 축이 있으면 전략 구현이 제대로 안 된 거니까
  넘어가지 말아야 해." 경고로 두면 '오버레이가 있다'는 서술만 남고 실제 보호는 없는
  전략이 배포된다. 알면서 두는 축은 사양에서 `expect_alive:false` 로 뒤집어 **회귀 감시**로
  전환하고 사유를 남긴다 — 조용한 통과는 없다.

★fail-closed: 판정 불가는 통과가 아니다. 사양 부재·패널 판독 실패는 BLOCK 으로 센다.

★러너 관문 모드 `--runner-gate` (2026-11-06 도훈 지시 "daily_refresh 돌리는 프로세스는 빼버려.
  이제 어차피 데이터 리프레시 때 퀀티 데이터들 다 업데이트하니까 필요없어"):
  리밸 러너는 이제 적재하지 않는다(구 [0] qw_refresh · [1] daily_refresh · [1b] sig 월 팩터DB 재빌드 제거).
  대신 러너가 이 모드를 불러 **이번 리밸이 읽을 원천이 sig 일까지 왔는지**만 소비면에서 잰다 —
  사양 `runner_gate` 블록이 무엇을 잴지 정한다. 관용(lag)이 아니라 sig 일 도달이다:
    ① [calendar] sig 일 = KRX 공식 휴장일 등록부 기준 as_of 직전 거래일(등록부 읽기만 · 받지 않는다).
       벤치 최대값에서 sig 일을 구하면 벤치가 낡을 때 sig 일도 같이 낡아 관문이 눈을 감는다(순환).
    ② [benchmark] 벤치의 sig 월 마지막 날 == ①.
    ③ [reach] runner_gate.sig_reach 의 파일마다 max(Date) ≥ sig 일 — 축마다 따로 잰다.
    ④ [anchor] sig 월 팩터DB 앵커 == sig 일.
  러너 산출 패널(m4 · AE · 알파 — decision 모드)은 여기서 재지 않는다(러너가 만들고 러너 게이트가 잰다).
  마지막 줄 = 'OK sig=…' 또는 'BAD [태그…] …' — 러너는 rc 0 ∧ 'OK ' 줄일 때만 지나간다.

사용:
  python book_rebalance_preflight.py --book-id BOOK_0001 --as-of 2026-09-01
  python book_rebalance_preflight.py --book-id BOOK_0001 --as-of 2026-09-01 --json
  python book_rebalance_preflight.py --book-id BOOK_0001 --as-of 2026-09-01 --runner-gate [--json]

종료코드: 0 GO(관문 OK) / 1 BLOCK(관문 BAD — 차단 사유 있음) / 2 사양·환경 오류
"""
from __future__ import annotations

import argparse
import glob
import io
import json
import os
import sys

import pandas as pd
import pyarrow.parquet as pq

ROOT = os.environ.get("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot").replace("\\", "/")
_HERE = os.path.dirname(os.path.abspath(__file__))       # chdir 전에 잡는다(상대 경로 호출 대비)
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
               "by_runner": bool(inp.get("produced_by_runner")),
               "producer": inp.get("producer", ""),
               "refresh_owner": inp.get("refresh_owner", "데이터 리프레시")}
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


def _krx_last_session_before(as_of_date):
    """KRX 공식 휴장일 등록부 기준 as_of 직전 거래일 — (date, None) 또는 (None, 사유).
    등록부는 읽기만 한다(allow_fetch=False) — 관문이 등록부를 고쳐 쓰지 않는다(갱신 = 데이터 리프레시 소관)."""
    sys.path.insert(0, os.path.join(_HERE, "..", "data"))
    try:
        import krx_holidays
        return krx_holidays.last_session_before(as_of_date, allow_fetch=False)
    except Exception as e:                       # 판정 불가 = 통과 아님(호출부가 BAD 로 적는다)
        return None, f"krx_holidays:{type(e).__name__}"


def runner_gate(spec, as_of: pd.Timestamp, as_json: bool) -> int:
    """러너 관문 — 검사만 · 갱신 없음 (머리말 '★러너 관문 모드' · 도훈 2026-11-06)."""
    rg = spec.get("runner_gate")
    if not rg:
        die(2, f"사양 {spec['book_id']} 에 runner_gate 없음 — 러너 관문이 무엇을 잴지 모른다(fail-closed)")
    col = rg.get("date_col", "Date")
    checks = []

    def add(tag, good, detail):
        checks.append({"check": tag, "ok": bool(good), "detail": detail})

    def dates(path, c):                          # 비어 있지 않은 날짜열 또는 None(=미측정 — 통과로 접지 않는다)
        d = _read_dates(path, c)
        d = d.dropna() if d is not None else None
        return d if d is not None and len(d) else None

    exp, why = _krx_last_session_before(as_of.date())
    sig = pd.Timestamp(exp) if exp is not None else None
    if sig is None:
        add("calendar", False, f"KRX 직전 거래일 판정 불가({why}) — 등록부 06_Registry/krx_holidays.json 은 데이터 리프레시 소관")
    else:
        add("calendar", True, f"sig {sig.date()} (KRX 등록부 · as_of {as_of.date()} 직전 거래일)")
        bd = dates(".cache/benchmark.parquet", "Date")
        in_m = bd[bd.dt.strftime("%Y%m") == sig.strftime("%Y%m")] if bd is not None else None
        if bd is None:
            add("benchmark", False, "benchmark.parquet 판독 불가(UNREADABLE)")
        elif not len(in_m):
            add("benchmark", False, f"벤치에 sig 월 거래일 없음(벤치 최대 {bd.max().date()})")
        else:
            last = in_m.max().normalize()
            add("benchmark", last == sig,
                f"벤치 sig 월 마지막 날 {last.date()}" + ("" if last == sig else
                f" ≠ sig {sig.date()} — " + ("벤치가 sig 일까지 오지 않았다" if last < sig
                                            else "등록부가 휴장으로 적은 날에 벤치 세션이 있다(등록부 확인)")))
        for ent in rg.get("sig_reach", []):
            skip = set(ent.get("skip", []))
            files = sorted(f.replace("\\", "/") for f in glob.glob(ent["glob"])
                           if os.path.basename(f) not in skip)
            if not files:
                add("reach", False, f"{ent['glob']}: 파일 없음(MISSING)")
            for f in files:
                d = dates(f, col)
                if d is None:
                    add("reach", False, f"{f}: {col} 판독 불가(UNREADABLE)")
                else:
                    mx = d.max().normalize()
                    add("reach", mx >= sig, f"{f}: max {mx.date()}" + ("" if mx >= sig else f" < sig {sig.date()}"))
        ap_ = _fmt({"as_of": str(as_of.date()), "as_of_compact": as_of.strftime("%Y%m%d"),
                    "sig_ym": sig.strftime("%Y%m")}, rg["anchor"])
        d = dates(ap_, col) if os.path.exists(ap_) else None
        if not os.path.exists(ap_):
            add("anchor", False, f"{ap_}: 파일 없음(MISSING)")
        elif d is None:
            add("anchor", False, f"{ap_}: {col} 판독 불가(UNREADABLE)")
        else:
            last = d.max().normalize()
            add("anchor", last == sig, f"{ap_}: 앵커 {last.date()} (기대 {sig.date()})")
    bad = [c for c in checks if not c["ok"]]
    tags = sorted({c["check"] for c in bad})
    sig_s = str(sig.date()) if sig is not None else "NA"
    line = (f"OK sig={sig_s} reach={sum(c['check'] == 'reach' for c in checks)}files anchor=ok"
            if not bad else
            f"BAD [{','.join(tags)}] " + " · ".join(c["detail"] for c in bad[:4])
            + (f" · 외 {len(bad) - 4}건" if len(bad) > 4 else "") + f" (sig={sig_s})")
    if as_json:
        print(json.dumps({"book_id": spec["book_id"], "as_of": str(as_of.date()), "mode": "runner_gate",
                          "verdict": "OK" if not bad else "BAD", "sig_date": sig_s, "checks": checks},
                         ensure_ascii=False, indent=2))
    else:
        for c in checks:
            print(f"  [{'OK ' if c['ok'] else 'BAD'}] {c['check']:9s} {c['detail']}")
        print(line)
    return 0 if not bad else 1


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--book-id", required=True)
    ap.add_argument("--as-of", required=True, help="홀딩월 1일 (예: 2026-09-01)")
    ap.add_argument("--json", action="store_true", help="기계 판독용 JSON 출력")
    ap.add_argument("--runner-gate", action="store_true",
                    help="러너 관문 — 원천의 sig 일 도달 · 앵커만 잰다(머리말 참조)")
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
    if a.runner_gate:
        return runner_gate(spec, as_of, a.json)
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
    # ★죽은 축은 경고가 아니라 차단이다 (도훈 지시 2026-08-30):
    #   "죽은 축 자체가 생기지 않도록 스킬로 구성하는 거야. 죽은 축이 있으면 전략 구현이
    #    제대로 안 된 거니까 넘어가지 말아야 해."
    #   구판은 이걸 경고로 뒀었다 — 그러면 '오버레이가 있다'는 서술만 남고 실제 보호는
    #   없는 전략이 그대로 배포된다(m4 BOCPD 팔 271개월 0회 발화가 그 실례).
    dead = [r for r in overlays if r["verdict"] in ("DEAD", "REVIVED", "UNREADABLE")]
    verdict = "GO" if not blocks and not dead else "BLOCK"

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
        src = "러너산출" if r["by_runner"] else "외부적재"
        print(f"  [{mark}] {r['id']:18s} {src}  {r.get('detail','')}")
        if r["verdict"] != "OK":
            print(f"          → 이관: {r['refresh_owner']} 소관 (이 스킬은 적재하지 않는다)")
    print(f"\n-- 축 C: 오버레이 팔 생존 (역사 발화율) --")
    for r in overlays:
        # ★살아 있는 팔과 '죽은 채로 감시 중인 팔'을 같은 색으로 찍지 않는다.
        #   둘 다 OK 로 보이면 "오버레이 7개 전부 정상"으로 읽히고, 그게 정확히
        #   이 검사기가 막으려는 착시다(구현 안 된 축이 서술로만 남는 것).
        if r["verdict"] == "OK" and not r["expect_alive"]:
            mark = "감시"
        else:
            mark = {"OK": "OK  ", "DEAD": "DEAD", "REVIVED": "REVIV", "UNREADABLE": "UNRD"}[r["verdict"]]
        cur = {True: "발화", False: "미발화", None: "as_of행없음"}[r.get("at_as_of")]
        print(f"  [{mark}] {r['id']:22s} {r.get('detail','')}  · as_of {cur}")
        if r.get("note") and (r["verdict"] != "OK" or not r["expect_alive"]):
            print(f"          ※ {r['note']}")

    print(f"\n===== 판정: {verdict} =====")
    if blocks:
        print("  차단 — 입력 신선도:")
        for r in blocks:
            print(f"    · {r['id']} ({r['refresh_owner']}) — {r['detail']}")
        print("  ★낡은 데이터로 리밸을 돌리지 않는다. 적재는 **데이터 리프레시 소관**이다 —")
        print("    보장 진입점 02_Infrastructure/ops/ensure_data_current.sh ·")
        print("    신선도 정본 02_Infrastructure/ops/morning_steps/freshness_audit.R")
    if dead:
        print("  차단 — 오버레이 축:")
        for r in dead:
            print(f"    · {r['id']} — {r['detail']}")
        print("  ★죽은 축은 전략 구현이 덜 된 것이다. 넘어가지 않는다.")
        print("    알면서 두는 축이면 사양에서 expect_alive:false 로 뒤집어 회귀 감시로")
        print("    전환하고 사유를 note 에 남길 것 — 조용히 통과시키지 않는다.")
    if verdict == "GO":
        print(f"  실행: {_fmt(ctx, spec['runner']['cmd'])}")
    return 0 if verdict == "GO" else 1


if __name__ == "__main__":
    sys.exit(main())
