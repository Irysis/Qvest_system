"""aif_nl_frame.py — 2단계 걸음 0: 자료 준비 · 수식형 신규 식의 값 · 후보 통계 · 해마다의 대표 팩터(FOLLOWUP_PLAN.md '걸음 0').

네 부분(부분마다 판 표식으로 끝난 것은 건너뛴다):
  ext     틀 확장 — 신호일 시가총액 · 20일 거래대금 · KOSPI200 / KOSDAQ150 편입 · 규모와 유동성 3분위(멤버 안) + 보유월의 거래정지 · 폐지 점검표
  newf    수식형 신규 식(체계적 열거 · 특징 부스팅이 해마다 뽑은 식)을 전 기간에 다시 계산해 멤버 안 순위로 저장 + 네 조건 개수 점수
          식은 그 생성기가 그때까지의 자료로 뽑은 것이므로, 어느 해의 후보에는 그해 12월까지 뽑힌 식만 넣는다(first_year).
  stats   후보 전체(1단계 원자료 특성 335 + 기존 팩터 282 + 신규 식)의 달별 순위 IC · 채움 비율 · 5분위 상하 수익 차이
          수익 차이는 대표를 묶는 데만 쓰는 선정용 통계다(성과 수치가 아니다 — 성과는 R 측정기가 잰다).
  select  해마다 12월에 그때까지의 값으로: 자격(IC 36개월 이상 · 최근 36개월 채움 60% 이상) → 방향을 맞춘 ICIR 순으로 훑으며
          앞선 대표와 수익 차이 상관이 0.5 이상이면 그 묶음에 넣고 아니면 새 대표 → 대표 40개까지.
          방향 = 기존 팩터는 등록부 방향(저장된 순위가 이미 그 방향) · 나머지는 그때까지의 IC 부호. 손으로 뒤집지 않는다.
          두 층(도훈 11-23 '두 층 나누기'): 대표(기본층)는 일반 특성(기존 팩터 DB + 1단계 원자료 특성)에서만 뽑는다. 수식형 신규 식은 식 안에 꺾임 ·
          상호작용 · 두 특성의 결합이 이미 들어 있어 기준 모형의 자리에 두지 않고, 자격을 갖춘 것을 '얹는 층 후보'로 따로 적는다 —
          얹을 식은 걸음 1 에서 기본층의 선형 + 제곱 모형이 남긴 고유수익을 더 설명하는 것만 고른다(상한 10 · py/aif_nlfactor.py).
산출(.cache/aif_research/followup/): frame_ext.npz · features/newf.* · cand/{candidates.json · ic.npy · cov.npy · ls.npy} · select/representatives.json
      + results/followup/{halt_delist_check.csv · representatives.csv} · stage_summary_nl_frame.json(텔레그램 결과 통)
실행: python py/aif_nl_frame.py [--force] [--only ext|newf|stats|select] [--check]     (감시 셸: ops/aif_run.py --track followup --job nl_frame --stage nl_frame)
"""
import argparse
import csv
import hashlib
import os
import re
import sys
import time
import warnings

import numpy as np
from scipy.stats import rankdata

import aif_common as ac
from aif_enumerate import Y_ITEMS, Compact, formula_text, load_fund, signals_for
from aif_fboost import BLOCKS, op_text, op_value
from aif_features import FeatureStore

VERSION = 1
SELECT_VERSION = 2                                                      # 2 = 두 층(기본층 대표는 일반 특성에서만 · 수식형 신규 식은 얹는 층 후보)
BASE_EXCLUDE = ("newf", "cat")                                          # 기본층에서 빼는 묶음 — 수식형 신규 식(얹는 층) · 범주형 표시(두 값뿐이라 노출의 제곱 성분이 없다)
MIN_IC_MONTHS, MIN_COVER, COVER_WINDOW, BURN_YEARS = 36, 0.60, 36, 5      # 1단계 체계적 열거와 같은 자격 · 예열(계획 걸음 0)
TOP_Q, MIN_SIDE = 0.2, 5                                                # 5분위(1단계 측정과 같은 분위 수) · 한쪽에 종목이 이만큼은 있어야 수익 차이를 낸다
CORR_CUT, MAX_REP, MIN_OVERLAP = 0.5, 40, 24                            # 계획: 상관 0.5 로 묶고 대표는 40개까지 · 상관은 겹치는 달이 2년 이상일 때만(Q 가 정한 값)
COND4 = [("val", "v_dp", 1), ("fund", "q_NetShareIssuance", -1), ("existing", "Q03_ROA", 1), ("existing", "Q07_Earnings_Stability", 1)]
RAW_BLOCKS = [b for b in BLOCKS if b != "existing"]                     # 1단계 원자료 특성 335개


def FU(*parts):
    return ac.out("followup", *parts)


def _md5(path):
    with open(path, "rb") as fh:
        return hashlib.md5(fh.read()).hexdigest()[:12]


def _save_npy(path, arr):
    def w(p):
        with open(p, "wb") as fh:
            np.save(fh, arr)
    ac.write_atomic(path, w)


def _save_npz(path, **arr):
    def w(p):
        with open(p, "wb") as fh:
            np.savez(fh, **arr)
    ac.write_atomic(path, w)


# ── ext: 틀 확장 ─────────────────────────────────────────────────────────────
def _tercile(x, mem):
    """멤버 안 3분위(0 = 아래 · 2 = 위 · 멤버가 아니거나 값이 없으면 −1). 달마다 그 달의 횡단면만 쓴다."""
    o = np.full(x.shape, -1, dtype=np.int8)
    for s in range(x.shape[0]):
        k = mem[s] & np.isfinite(x[s])
        if k.sum() >= 30:
            o[s, k] = np.searchsorted(np.quantile(x[s, k], [1 / 3, 2 / 3]), x[s, k], side="right")
    return o


def halt_check(f):
    """보유월(신호 다음 달)에 멤버 종목의 수익 행이 빠졌거나 거래정지였던 종목-달을 센다. 측정기는 행이 없는 날을 수익 0 으로 둔다 — 그 크기를 본다."""
    import datetime as dt

    import pyarrow.parquet as pq
    t = pq.read_table(ac.root() + "/" + ac.cfg()["paths"]["rawdata"], columns=["Date", "Ticker", "TradingHalt"],
                      filters=[("Date", ">=", dt.date.fromisoformat(str(f.dates[0])))])
    di = f.date_index(t.column("Date").to_numpy(zero_copy_only=False).astype("datetime64[D]"))
    tk = t.column("Ticker").dictionary_encode().combine_chunks()
    ti = f.ticker_index(tk.dictionary.to_pylist())[tk.indices.to_numpy(zero_copy_only=False)]
    halt = np.nan_to_num(t.column("TradingHalt").to_numpy(zero_copy_only=False).astype(np.float64)) > 0.5
    del t
    ok = (di >= 0) & (ti >= 0)
    P = np.zeros((f.nd, f.nt), dtype=bool)
    H = np.zeros((f.nd, f.nt), dtype=bool)
    P[di[ok], ti[ok]] = True
    H[di[ok & halt], ti[ok & halt]] = True
    last = np.where(P.any(0), f.nd - 1 - np.argmax(P[::-1], axis=0), -1)          # 종목마다 마지막으로 행이 있는 날
    fwd = f.fwd(1)
    is_end = np.datetime64(ac.cfg()["measure"]["is_end"], "D")
    rows, agg = {}, np.zeros(4)
    for s in range(f.ns):
        if not f.hold_ok[s]:
            continue
        a, b, m = int(f.hold_a[s]), int(f.hold_b[s]), f.mem[s]
        nrow = P[a:b + 1][:, m].sum(0)
        norow = nrow == 0
        part = (nrow > 0) & (nrow < b - a + 1)
        hl = H[a:b + 1][:, m].any(0)
        gone = (last[m] < b) & (last[m] >= f.sig_idx[s]) & (last[m] < f.nd - 6)   # 보유월 안에서 행이 끝나고 다시 나타나지 않는다(자료 끝 6일은 뺀다)
        y = int(str(f.sig_dates[s])[:4])
        r = rows.setdefault(y, np.zeros(5, dtype=np.int64))
        r += np.array([m.sum(), norow.sum(), part.sum(), hl.sum(), gone.sum()])
        if f.sig_dates[s] <= is_end:                                              # 수익 비교는 IS 구간만(선정용이 아닌 자료 점검)
            fw = np.asarray(fwd[s])[m].astype(np.float64)
            bad = part | hl
            agg += np.array([np.nansum(fw[bad]), np.isfinite(fw[bad]).sum(), np.nansum(fw[~bad & ~norow]), np.isfinite(fw[~bad & ~norow]).sum()])
    os.makedirs(ac.results("followup"), exist_ok=True)
    with open(ac.results("followup", "halt_delist_check.csv"), "w", newline="", encoding="utf-8-sig") as fh:
        w = csv.writer(fh)
        w.writerow(["year", "member_months", "no_rows_in_hold", "partial_rows", "halt_flag_days", "rows_end_in_hold", "share_partial_or_halt", "share_rows_end"])
        for y in sorted(rows):
            n, nr, pt, hl, gn = rows[y]
            w.writerow([y, n, nr, pt, hl, gn, round((pt + hl) / max(n, 1), 5), round(gn / max(n, 1), 5)])
    tot = np.sum(list(rows.values()), axis=0)
    return {"member_months": int(tot[0]), "no_rows_in_hold": int(tot[1]), "partial_rows": int(tot[2]), "halt_flag": int(tot[3]), "rows_end_in_hold": int(tot[4]),
            "is_mean_fwd1_partial_or_halt": float(agg[0] / agg[1]) if agg[1] else None, "is_mean_fwd1_normal": float(agg[2] / agg[3]) if agg[3] else None}


def part_ext(f, store, force):
    p, fp = FU("frame_ext.npz"), "%s|ext%d" % (f.meta.get("rawdata_tag"), VERSION)
    if not force and ac.load_ckpt(p, fp) is not None:
        ac.log("ext — 이미 끝남(건너뜀)")
        return ac.read_json(FU("frame_ext.json")) or {}
    raw, pn = store.open("price", "raw")
    cat, cn = store.open("cat", "raw")
    lcap = np.asarray(raw[:, :, pn.index("p_size")], dtype=np.float32)            # 로그 시가총액(신호일)
    lamt = np.asarray(raw[:, :, pn.index("p_amt_20")], dtype=np.float32)          # 로그 거래대금(20일)
    k200 = np.asarray(cat[:, :, cn.index("cat_k200")]) > 0.5
    kq150 = np.asarray(cat[:, :, cn.index("cat_kq150")]) > 0.5
    size3, liq3 = _tercile(lcap, f.mem), _tercile(lamt, f.mem)
    hc = halt_check(f)
    _save_npz(p, fp=fp, log_cap=lcap, log_amt20=lamt, k200=k200, kq150=kq150, size3=size3, liq3=liq3)
    info = {"at": ac._now(), "fp": fp, "arrays": "log_cap · log_amt20 · k200 · kq150 · size3 · liq3 — 모두 [신호 × 종목] · 신호일 값",
            "members_avg": float(f.mem.sum(1).mean()), "k200_or_kq150_members_avg": float(((k200 | kq150) & f.mem).sum(1).mean()),
            "k200_avg": float(k200.sum(1).mean()), "kq150_avg": float(kq150.sum(1).mean()), "halt_check": hc}
    ac.write_json(info, FU("frame_ext.json"))
    ac.log("ext 끝 — 멤버 평균 %.0f · 지수 편입 멤버 평균 %.0f · 보유월에 행이 일부 빠지거나 정지 %d · 행이 끝남 %d (종목-달 %d)",
           info["members_avg"], info["k200_or_kq150_members_avg"], hc["partial_rows"] + hc["halt_flag"], hc["rows_end_in_hold"], hc["member_months"])
    return info


# ── newf: 수식형 신규 식의 값 ────────────────────────────────────────────────
def parse_fboost(text, names):
    """특징 부스팅의 식 글 → (연산, a, b). 글을 다시 만들어 같은지 확인한다."""
    for pat, op in ((r"max\((.+), (.+)\)", "max"), (r"min\((.+), (.+)\)", "min"), (r"(.+) \(단 (.+) > 중앙\)", "a_if_b_pos"), (r"(.+) × (.+)", "mul"), (r"(.+) − (.+)", "sub")):
        m = re.fullmatch(pat, text)
        if m and m.group(1) in names and m.group(2) in names and op_text(op, m.group(1), m.group(2)) == text:
            return op, m.group(1), m.group(2)
    raise RuntimeError("식을 풀지 못했다: %s" % text)


def read_selected(gen):
    with open(ac.results("stage3_%s" % gen, "selected_formulas.csv"), encoding="utf-8-sig") as fh:
        return list(csv.DictReader(fh))


def gather_ranks(store, cp, want):
    """필요한 특성의 멤버 안 순위를 멤버 칸 배열 [칸 × 특성]로 모은다(묶음 파일을 달 순서로 한 번씩만 읽는다). want = [(묶음, 이름)]."""
    f = cp.f
    X = np.full((cp.n, len(want)), np.nan, dtype=np.float32)
    for b in sorted({b for b, _ in want}):
        rk, nm = store.open(b, "rank")
        cols = [(j, nm.index(n)) for j, (bb, n) in enumerate(want) if bb == b]
        dst, src = [j for j, _ in cols], [k for _, k in cols]
        for s in range(f.ns):
            a, e = cp.seg[s], cp.seg[s + 1]
            if e > a:
                X[a:e, dst] = np.asarray(rk[s])[cp.J[a:e]][:, src]
    return X


def part_newf(f, store, fstore, cp, force):
    en_rows, fb_rows = read_selected("enumerate"), read_selected("fboost")
    fp = "%s|newf%d|%s|%s" % (f.meta.get("rawdata_tag"), VERSION, _md5(ac.results("stage3_enumerate", "selected_formulas.csv")), _md5(ac.results("stage3_fboost", "selected_formulas.csv")))
    info = fstore.info("newf")
    if not force and info and info.get("fp") == fp:
        ac.log("newf — 이미 끝남(건너뜀) · 식 %d개", info["n_features"])
        return info
    base_names = {}
    for b in BLOCKS:
        for n in store.info(b)["names"]:
            base_names.setdefault(n, b)                                           # 이름 → 묶음(이름은 묶음 사이에 겹치지 않는다 — 겹치면 앞 묶음)
    first = {}                                                                    # 식 → 처음 뽑힌 해
    for r in en_rows:
        k = ("EN", r["formula"])
        first[k] = min(first.get(k, 9999), int(r["year_selected"]))
    for r in fb_rows:
        k = ("FB", r["formula"])
        first[k] = min(first.get(k, 9999), int(r["year_selected"]))
    en = sorted(t for g, t in first if g == "EN")
    fb = sorted(t for g, t in first if g == "FB")
    names = ["EN:" + t for t in en] + ["FB:" + t for t in fb] + ["COND4"]
    mm = fstore.create("newf", names, "rank")

    # 체계적 열거 — 식 글을 후보 목록(분자 · 형태 · 분모)에 맞춰 재무 값으로 다시 계산한다
    sig = ac.read_json(ac.out("enumerate", "signals.json"))["signals"]
    by_text = {}
    for s in sig:
        by_text.setdefault(formula_text(s["form"], s["x"], s["y"]), s)
    miss = [t for t in en if t not in by_text]
    if miss:
        raise RuntimeError("열거 식을 후보 목록에서 찾지 못했다: %s" % miss[:3])
    need = [by_text[t] for t in en]
    items = sorted({s["x"] for s in need} | {s["y"] for s in need if s["y"] in Y_ITEMS})
    cur, lag, qtr = load_fund(cp, items)
    ix = {k: i for i, k in enumerate(items)}
    raw, pn = store.open("price", "raw")
    cap = np.exp(np.asarray(raw[:, :, pn.index("p_size")], dtype=np.float64))
    s12 = cp.S - 12
    Y = {y: (cur[ix[y]], lag[ix[y]], qtr[ix[y]]) for y in items if y in Y_ITEMS}
    Y["MKTCAP"] = (cap[cp.S, cp.J].astype(np.float32), np.where(s12 >= 0, cap[np.maximum(s12, 0), cp.J], np.nan).astype(np.float32), None)
    del cap, raw
    for k, s in enumerate(need):
        xs = (cur[ix[s["x"]]], lag[ix[s["x"]]], qtr[ix[s["x"]]])
        v = None
        for fm, yn, val in signals_for(xs, {s["y"]: Y[s["y"]]} if s["y"] else {}, [s["form"]] if s["y"] else []):
            if fm == s["form"] and yn == s["y"]:
                v = val
        if v is None:
            raise RuntimeError("식 값을 다시 만들지 못했다: %s" % s)
        mm[cp.S, cp.J, k] = cp.rank_pm1(v)
        if (k + 1) % 20 == 0 or k + 1 == len(need):
            ac.stage_unit(1 + k + 1, "열거 식 %d / %d" % (k + 1, len(need)))
    del cur, lag, qtr

    # 특징 부스팅 — 순위 특성 둘의 연산
    ops = [parse_fboost(t, base_names) for t in fb]
    want = sorted({(base_names[a], a) for _, a, _ in ops} | {(base_names[b], b) for _, _, b in ops} | {(b, n) for b, n, _ in COND4})
    wi = {n: j for j, (_, n) in enumerate(want)}
    X = gather_ranks(store, cp, want)
    k0 = len(en)
    for k, (op, a, b) in enumerate(ops):
        mm[cp.S, cp.J, k0 + k] = cp.rank_pm1(op_value(op, X[:, wi[a]], X[:, wi[b]]))
        if (k + 1) % 40 == 0 or k + 1 == len(ops):
            ac.stage_unit(1 + len(need) + k + 1, "부스팅 식 %d / %d" % (k + 1, len(ops)))
    # 네 조건 개수 점수 — 좋은 쪽(멤버 안 중앙보다 위 · 순발행은 아래)에 있는 조건의 수. 넷 가운데 값이 있는 것이 셋 미만이면 결측
    C = np.stack([np.where(np.isfinite(X[:, wi[n]]), (d * X[:, wi[n]] > 0).astype(np.float32), np.nan) for _, n, d in COND4], axis=1)
    cnt = np.where(np.isfinite(C).sum(1) >= 3, np.nansum(C, axis=1), np.nan)
    mm[cp.S, cp.J, len(names) - 1] = cp.rank_pm1(cnt)
    fill = [float(np.isfinite(mm[:, :, k])[f.mem].mean()) for k in range(len(names))]
    fstore.commit("newf", mm, names, {"fp": fp, "first_year": [first[("EN", t)] for t in en] + [first[("FB", t)] for t in fb] + [0],
                                      "source": "체계적 열거 %d개(재무 값으로 다시 계산) · 특징 부스팅 %d개(순위 특성의 쌍 연산) · 네 조건 개수 점수" % (len(en), len(fb)),
                                      "asof": "값은 신호일까지의 자료 · 식의 선택 시점은 first_year(그해 12월 신호부터 후보)", "fill_members": dict(zip(names, [round(x, 4) for x in fill])),
                                      "cond4": "배당수익률 · 순발행(낮은 쪽) · ROA · 이익 안정 가운데 멤버 안 중앙보다 좋은 쪽에 있는 것의 수(값 셋 이상일 때) — 원 연구는 평균 기준, 여기서는 순위라 중앙 기준"}, "rank")
    ac.log("newf 끝 — 열거 %d · 부스팅 %d · 조건 개수 1 · 채움 중앙값 %.2f", len(en), len(fb), float(np.median(fill)))
    return fstore.info("newf")


# ── stats: 후보의 달별 IC · 채움 · 수익 차이 ──────────────────────────────────
def month_stats(X, fw):
    """X [멤버 × 후보](멤버 안 순위 · 결측 NaN) · fw [멤버](다음 달 수익) → IC · 채움 · 상하 5분위 수익 차이(후보마다)."""
    fin = np.isfinite(X)
    cov = fin.mean(0)
    ok = fin & np.isfinite(fw)[:, None]
    n = ok.sum(0)
    with np.errstate(invalid="ignore", divide="ignore"), warnings.catch_warnings():
        warnings.simplefilter("ignore", RuntimeWarning)                  # 그 달 값이 하나도 없는 후보의 '빈 조각 평균' 경고
        xr = rankdata(np.where(ok, X, np.nan), axis=0, nan_policy="omit")
        yr = rankdata(np.where(ok, fw[:, None], np.nan), axis=0, nan_policy="omit")
        xr -= np.nanmean(xr, axis=0)
        yr -= np.nanmean(yr, axis=0)
        ic = np.nansum(xr * yr, axis=0) / np.sqrt(np.nansum(xr * xr, axis=0) * np.nansum(yr * yr, axis=0))
        ic = np.where(n >= 30, ic, np.nan)
        fz = np.where(np.isfinite(fw), fw, 0.0)
        top, bot = ok & (X >= 1 - 2 * TOP_Q), ok & (X <= -(1 - 2 * TOP_Q))
        nt_, nb_ = top.sum(0), bot.sum(0)
        ls = (fz @ top) / nt_ - (fz @ bot) / nb_
        ls = np.where((nt_ >= MIN_SIDE) & (nb_ >= MIN_SIDE), ls, np.nan)
    return ic.astype(np.float32), cov.astype(np.float32), ls.astype(np.float32)


def part_stats(f, store, fstore, cp, force):
    nf = fstore.info("newf")
    fp = "%s|stats%d|%s" % (f.meta.get("rawdata_tag"), VERSION, nf["fp"])
    meta = ac.read_json(FU("cand", "candidates.json"))
    if not force and meta and meta.get("fp") == fp and os.path.exists(FU("cand", "ls.npy")):
        ac.log("stats — 이미 끝남(건너뜀) · 후보 %d개", len(meta["names"]))
        return meta
    srcs = [(store, b) for b in RAW_BLOCKS] + [(store, "existing"), (fstore, "newf")]
    opened = [(st.open(b, "rank"), b) for st, b in srcs]
    names = [n for (_, nm), _ in opened for n in nm]
    src = [b for (_, nm), b in opened for _ in nm]
    first = [0] * (len(names) - nf["n_features"]) + list(nf["first_year"])
    C = len(names)
    IC, COV, LS = (np.full((C, f.ns), np.nan, dtype=np.float32) for _ in range(3))
    fwd = f.fwd(1)
    t0 = time.time()
    for s in range(f.ns):
        a, e = cp.seg[s], cp.seg[s + 1]
        if e - a < 30:
            continue
        J = cp.J[a:e]
        X = np.concatenate([np.asarray(rk[s])[J] for (rk, _), _ in opened], axis=1)
        IC[:, s], COV[:, s], LS[:, s] = month_stats(X, np.asarray(fwd[s])[J].astype(np.float64))
        if (s + 1) % 12 == 0 or s + 1 == f.ns:
            ac.stage_unit(s + 1, "%s 까지 후보 통계" % str(f.sig_dates[s])[:7])
    os.makedirs(FU("cand"), exist_ok=True)
    for nm, arr in (("ic", IC), ("cov", COV), ("ls", LS)):
        _save_npy(FU("cand", nm + ".npy"), arr)
    meta = {"fp": fp, "at": ac._now(), "names": names, "src": src, "first_year": first, "n": C, "seconds": round(time.time() - t0, 1),
            "note": "ic = 달별 순위 IC(멤버 · 다음 1개월 수익) · cov = 멤버 채움 비율 · ls = 순위 상위 20% − 하위 20% 의 다음 달 평균 수익(선정용 통계)"}
    ac.write_json(meta, FU("cand", "candidates.json"))
    ac.log("stats 끝 — 후보 %d개 · %.0f초", C, time.time() - t0)
    return meta


# ── select: 해마다의 대표 팩터 ────────────────────────────────────────────────
def pair_corr(A):
    """행마다 계열(결측 NaN) → 겹치는 달만으로 낸 상관 행렬과 겹치는 달 수."""
    M = np.isfinite(A).astype(np.float64)
    Z = np.where(np.isfinite(A), A, 0.0).astype(np.float64)
    n = M @ M.T
    sx, sy, sxy, sxx, syy = Z @ M.T, M @ Z.T, Z @ Z.T, (Z * Z) @ M.T, M @ (Z * Z).T
    with np.errstate(invalid="ignore", divide="ignore"):
        c = (n * sxy - sx * sy) / np.sqrt((n * sxx - sx * sx) * (n * syy - sy * sy))
    return c, n


def part_select(f, force):
    meta = ac.read_json(FU("cand", "candidates.json"))
    fp = "%s|select%d" % (meta["fp"], SELECT_VERSION)
    old = ac.read_json(FU("select", "representatives.json"))
    if not force and old and old.get("fp") == fp:
        ac.log("select — 이미 끝남(건너뜀)")
        return old
    IC, COV, LS = (np.load(FU("cand", n + ".npy")) for n in ("ic", "cov", "ls"))
    names, src, first = meta["names"], np.array(meta["src"]), np.array(meta["first_year"])
    base_src = ~np.isin(src, BASE_EXCLUDE)                               # 기본층에 들 수 있는 후보(일반 특성)
    years, dec = ac.december_signals(f, BURN_YEARS)
    out, rows = {}, []
    for n, y in enumerate(years):
        sY = dec[y]
        ic, ls = IC[:, :sY], LS[:, :sY]                                  # 다음 달 수익이 그 12월 신호일까지 실현된 달만
        cnt = np.isfinite(ic).sum(1)
        with np.errstate(invalid="ignore", divide="ignore"), warnings.catch_warnings():
            warnings.simplefilter("ignore", RuntimeWarning)
            mu, sd = np.nanmean(ic, 1), np.nanstd(ic, 1, ddof=1)
            icir = mu / sd
        cover = COV[:, max(0, sY - COVER_WINDOW):sY].mean(1)
        d = np.where(src == "existing", 1.0, np.sign(mu))               # 기존 팩터 = 등록부 방향 · 나머지 = 그때까지의 IC 부호
        elig = (cnt >= MIN_IC_MONTHS) & (cover >= MIN_COVER) & (np.isfinite(ls).sum(1) >= MIN_IC_MONTHS) & (first <= y) & np.isfinite(icir) & (d * icir > 0)
        pool = np.nonzero(elig & (src == "newf"))[0]                     # 얹는 층 후보 — 같은 자격을 갖춘 수식형 신규 식(선정은 걸음 1)
        idx = np.nonzero(elig & base_src)[0]
        idx = idx[np.argsort(-(d * icir)[idx])]
        c, ov = pair_corr(ls[idx] * d[idx][:, None])
        leaders, member_of = [], {}
        for i in range(len(idx)):
            best = None
            for li in leaders:
                if ov[i, li] >= MIN_OVERLAP and np.isfinite(c[i, li]) and c[i, li] >= CORR_CUT and (best is None or c[i, li] > c[i, best]):
                    best = li
            if best is None:
                leaders.append(i)
                member_of[i] = [i]
            else:
                member_of[best].append(i)
        reps = []
        for rank, li in enumerate(leaders[:MAX_REP]):
            k = int(idx[li])
            reps.append({"cand": k, "name": names[k], "src": str(src[k]), "direction": int(d[k]), "icir": round(float(icir[k]), 4), "ic_mean": round(float(mu[k]), 4),
                         "months": int(cnt[k]), "cover": round(float(cover[k]), 3), "cluster_size": len(member_of[li]),
                         "cluster_top": [names[int(idx[j])] for j in member_of[li][1:6]]})
            rows.append({"year_selected": y, "used_from": str(f.sig_dates[sY]), "layer": "base", "rank": rank + 1, "name": names[k], "source": str(src[k]), "direction": int(d[k]),
                         "icir_asof": round(float(icir[k]), 3), "ic_mean_asof": round(float(mu[k]), 4), "months": int(cnt[k]), "cluster_size": len(member_of[li])})
        out[str(y)] = {"signal": str(f.sig_dates[sY]), "eligible": int(len(idx)), "clusters": len(leaders), "reps": reps,
                       "overlay_pool": [{"cand": int(k), "name": names[int(k)]} for k in pool]}
        ac.stage_unit(n + 1, "%d년 말 — 기본층 자격 %d · 묶음 %d · 대표 %d · 얹는 층 후보 %d" % (y, len(idx), len(leaders), len(reps), len(pool)))
    res = {"fp": fp, "at": ac._now(), "years": out, "layers": "reps = 기본층(일반 특성) · overlay_pool = 얹는 층 후보(자격을 갖춘 수식형 신규 식 — 선정은 걸음 1)",
           "params": {"MIN_IC_MONTHS": MIN_IC_MONTHS, "MIN_COVER": MIN_COVER, "CORR_CUT": CORR_CUT, "MAX_REP": MAX_REP, "MIN_OVERLAP": MIN_OVERLAP, "TOP_Q": TOP_Q,
                      "BASE_EXCLUDE": list(BASE_EXCLUDE)}}
    ac.write_json(res, FU("select", "representatives.json"))
    os.makedirs(ac.results("followup"), exist_ok=True)
    with open(ac.results("followup", "representatives.csv"), "w", newline="", encoding="utf-8-sig") as fh:
        w = csv.DictWriter(fh, fieldnames=list(rows[0].keys()))
        w.writeheader()
        w.writerows(rows)
    return res


def check(f, fstore, cp):
    """다시 계산한 식으로 1단계 합성을 다시 만들어 저장된 값과 견준다(식 풀이와 값 계산이 같은지)."""
    import pyarrow.parquet as pq
    rk, names = fstore.open("newf", "rank")
    ok = True
    for gen, tag, fac in (("enumerate", "EN:", "ENUM_EB20"), ("fboost", "FB:", "FBOOST_C20")):
        rows = read_selected(gen)
        t = pq.read_table(ac.out("factors", fac + ".parquet")).to_pandas()
        S = np.full((f.ns, f.nt), np.nan, dtype=np.float64)
        si = np.searchsorted(f.sig_dates, t["Date"].to_numpy().astype("datetime64[D]"))
        S[si, f.ticker_index(t["Ticker"].tolist())] = t["Raw_Value"].to_numpy()
        _, dec = ac.december_signals(f, BURN_YEARS)
        worst = 0.0
        for y in sorted({int(r["year_selected"]) for r in rows})[::5]:                # 다섯 해에 하나씩
            pk = [r for r in rows if int(r["year_selected"]) == y]
            s0 = dec[y]
            for s in (s0, min(s0 + 11, f.ns - 1)):
                J = cp.J[cp.seg[s]:cp.seg[s + 1]]
                R = np.asarray(rk[s])[J]                                              # 그 달 멤버의 식 값 전부(한 번만 읽는다)
                M = np.stack([R[:, names.index(tag + r["formula"])] * int(r["direction"]) for r in pk])
                comp = np.where(np.isfinite(M).mean(0) >= 0.5, np.nanmean(np.where(np.isfinite(M), M, 0.0), 0), np.nan)
                both = np.isfinite(comp) & np.isfinite(S[s, J])
                same_na = bool((np.isfinite(comp) == np.isfinite(S[s, J])).all())
                dmax = float(np.abs(comp[both] - S[s, J][both]).max()) if both.any() else float("nan")
                worst = max(worst, dmax if np.isfinite(dmax) else 9.0)
                ok = ok and same_na and dmax < 1e-4
        ac.log("점검 %s — 저장된 합성과의 최대 차이 %.2e", fac, worst)
    return ok


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--only", choices=["ext", "newf", "stats", "select"])
    ap.add_argument("--check", action="store_true", help="다시 계산한 식으로 1단계 합성(ENUM_EB20 · FBOOST_C20)을 다시 만들어 저장분과 견준다")
    a = ap.parse_args()
    if ac.track() != "followup":                                                # 2단계 줄이 아니면 1단계의 상태 파일에 이 단계를 적게 된다(도는 중인 1단계 작업의 진행 표시가 깨진다)
        raise RuntimeError("[aif] 2단계 줄로만 띄운다 — ops/aif_run.py --track followup 또는 AIF_TRACK=followup")
    ac.low_priority()
    f = ac.Frame()
    store, fstore = FeatureStore(f), FeatureStore(f, FU("features"))
    cp = Compact(f)
    run = lambda k: a.only in (None, k)                                           # noqa: E731
    info = {}
    if run("ext"):
        ac.stage_begin("nl_frame", 1, "부분", 0.0, 0.10)
        info["ext"] = part_ext(f, store, a.force)
        ac.stage_unit(1, "틀 확장 끝")
    if run("newf"):
        nu = len({r["formula"] for r in read_selected("enumerate")}) + len({r["formula"] for r in read_selected("fboost")})
        ac.stage_begin("nl_frame", nu + 1, "식", 0.10, 0.55)
        info["newf"] = part_newf(f, store, fstore, cp, a.force)
    if a.check:
        if not check(f, fstore, cp):
            raise RuntimeError("[aif] 다시 계산한 식이 1단계 합성과 맞지 않는다")
    if run("stats"):
        ac.stage_begin("nl_frame", f.ns, "달", 0.55, 0.90)
        info["stats"] = part_stats(f, store, fstore, cp, a.force)
    if run("select"):
        years, _ = ac.december_signals(f, BURN_YEARS)
        ac.stage_begin("nl_frame", len(years), "해", 0.90, 1.0)
        res = part_select(f, a.force)
        ext = ac.read_json(FU("frame_ext.json")) or {}
        hc = ext.get("halt_check") or {}
        ys = sorted(res["years"])
        nrep = [len(res["years"][y]["reps"]) for y in ys]
        srcn = {}
        for y in ys:
            for r in res["years"][y]["reps"]:
                g = "기존 팩터 DB" if r["src"] == "existing" else "1단계 원자료 특성"
                srcn[g] = srcn.get(g, 0) + 1
        last = res["years"][ys[-1]]
        npool = [len(res["years"][y]["overlay_pool"]) for y in ys]
        lines = ["후보 %d개(1단계 원자료 특성 335 · 기존 팩터 282 · 수식형 신규 식과 조건 개수 점수 %d) 가운데 해마다 기본층 대표를 일반 특성에서만 뽑았습니다(두 층 — 도훈 11-23)" % (
                     len(ac.read_json(FU("cand", "candidates.json"))["names"]), (fstore.info("newf") or {}).get("n_features", 0)),
                 "선정 해 %s~%s · 해마다 대표 %d~%d개 · 자격을 갖춘 일반 특성 %d~%d개 · 묶음 %d~%d개" % (ys[0], ys[-1], min(nrep), max(nrep), min(res["years"][y]["eligible"] for y in ys),
                                                                                        max(res["years"][y]["eligible"] for y in ys), min(res["years"][y]["clusters"] for y in ys), max(res["years"][y]["clusters"] for y in ys)),
                 "대표의 출처(해마다 뽑힌 수의 합) — " + " · ".join("%s %d" % kv for kv in sorted(srcn.items(), key=lambda kv: -kv[1])),
                 "얹는 층 후보(자격을 갖춘 수식형 신규 식) 해마다 %d~%d개 — 얹을 식은 걸음 1 에서 기본층 모형이 남긴 고유수익을 더 설명하는 것만 고릅니다(상한 10)" % (min(npool), max(npool)),
                 "%s년 말 대표 상위 다섯 — %s" % (ys[-1], " · ".join(r["name"][:28] for r in last["reps"][:5])),
                 "보유월 자료 점검 — 멤버 종목-달 %s 가운데 수익 행이 일부 빠지거나 정지 표시 %s · 보유월에 행이 끝난 것 %s" % (
                     format(hc.get("member_months", 0), ","), format(hc.get("partial_rows", 0) + hc.get("halt_flag", 0), ","), format(hc.get("rows_end_in_hold", 0), ","))]
        ac.write_json({"at": ac._now(), "title": "걸음 0 — 자료 준비 · 신규 식 값 · 대표 팩터", "lines": lines, "charts": [], "chart_names": []}, FU("stage_summary_nl_frame.json"))
        ac.stage_end(done=True)
        ac.log("select 끝 — 선정 %d해 · 대표 %d~%d개", len(ys), min(nrep), max(nrep))
    return 0


if __name__ == "__main__":
    sys.exit(main())
