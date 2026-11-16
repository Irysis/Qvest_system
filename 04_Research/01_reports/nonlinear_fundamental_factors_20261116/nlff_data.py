"""nlff_data.py — 비선형 재무 팩터(NLFF) 입력 패널 · 표적 · 위생 유니버스.

PIT 규칙(pit.md C1 · C4 · C10 · C14 와 같은 뜻):
  · 입력 값 = 결정일(월말 신호일) t 에 Factor_Date <= t 인 마지막 행(fund_access.R::fa_latest 와 같은 규칙 · 항목마다 따로) ·
    묵은 값 거르기 = Period_Date >= t − 15개월(분기) / 24개월(연간).
  · 위생 유니버스 = 그날 표식(관리 · 거래정지 · 불성실공시) 0 · 20일 평균 거래대금(t−1) >= liq_min · 전날 수정 종가 >= price_floor
    (measurement_axis.R::ma_membership 과 같은 식 · 값은 constraint_defaults.json 에서 읽는다).
  · 단면 변환(순위 · 평균 차감)은 같은 달 단면 안에서만. 전 표본 통계 없음.
  · 표적마다 '실현일'(avail) 열을 둔다 — 학습은 avail <= 재학습일 인 표본만(nlff_run.py 가 단정).
  · 자가 시험 pit_selftest_features: 미래 행을 잘라낸 원천으로 다시 만든 입력이 원래 입력과 비트 단위로 같아야 한다.
"""
from __future__ import annotations

import json
import os
import zlib
from pathlib import Path

import numpy as np
import pandas as pd
import pyarrow as pa
import pyarrow.compute as pc
import pyarrow.dataset as ds
import pyarrow.parquet as pq

HERE = Path(__file__).resolve().parent


def project_root() -> Path:
    r = os.environ.get("QM_ROOT", "").strip()
    if r and Path(r).exists():
        return Path(r.replace("\\", "/"))
    return HERE.parents[2]


ROOT = project_root()


def load_cfg() -> dict:
    with open(HERE / "nlff_config.json", encoding="utf-8") as f:
        return json.load(f)


def p(rel: str) -> Path:
    return ROOT / rel


# ---------------------------------------------------------------------------------------------- 측정 축(위생) 설정
def axis_params(cfg: dict) -> dict:
    cd = json.load(open(p(cfg["paths"]["constraint_defaults"]), encoding="utf-8"))
    ma = cd["measurement_axis"]
    ep = ma["epochs"][ma["active"]]
    node = cd
    for k in ep["liq_min_key"].split("."):
        node = node[k]
    liq = float(node)
    pf = ep.get("price_floor") or {}
    if pf and (pf.get("basis") != "adjusted_close" or int(pf.get("lag_days", -1)) != 1):
        raise RuntimeError("[nlff] price_floor 형식이 measurement_axis.R 과 다르다 — 지원 안 함")
    flags = list(ep["excluded_flags"])
    if sorted(flags) != sorted(["AdminStock", "TradingHalt", "UnfaithfulDisc"]):
        raise RuntimeError("[nlff] 위생 표식이 표준 3종과 다르다")
    return {"epoch": ma["active"], "liq_min": liq, "price_min": float(pf["min_won"]) if pf else float("nan"),
            "flags": flags, "start": ep["start_date"]}


# ---------------------------------------------------------------------------------------------- 월말 신호일
def month_ends(cfg: dict, start: str, end: str) -> np.ndarray:
    """RAWDATA 거래일 중 달마다 마지막 날. 마지막(진행 중) 달은 뺀다. start/end = 'YYYY-MM'."""
    d = pq.read_table(p(cfg["paths"]["rawdata"]), columns=["Date"]).column(0)
    u = np.unique(d.to_numpy(zero_copy_only=False).astype("datetime64[D]"))
    s = pd.Series(u)
    ym = s.dt.year * 100 + s.dt.month
    me = s.groupby(ym).max()
    if len(me) and me.index[-1] == ym.iloc[-1]:
        last = me.iloc[-1]
        if (last + pd.offsets.MonthEnd(0)) - last > pd.Timedelta(days=3):   # 달 끝 3일 전보다 이른 마지막 거래일 = 진행 중인 달
            me = me.iloc[:-1]
    lo = int(start.replace("-", "")[:6]); hi = int(end.replace("-", "")[:6])
    me = me[(me.index >= lo) & (me.index <= hi)]
    return me.to_numpy().astype("datetime64[D]")


def _days(a) -> np.ndarray:
    return np.asarray(a).astype("datetime64[D]").astype(np.int64)


# ---------------------------------------------------------------------------------------------- 입력 항목 목록
def feature_spec(cfg: dict) -> dict:
    fc = cfg["features"]
    rep = json.load(open(p(".cache/fundamental_caches_report.json"), encoding="utf-8"))
    derived = list(rep["derived_items"])
    excl = set(fc["exclude_level_items"]) | set(fc["exclude_duplicates"].keys())
    dvars = [x for x in derived if x.startswith("d_")]
    base = [x for x in derived if x not in excl and not x.startswith("d_")]
    slog = list(fc["signed_log_raw"])
    label_items = ["NetIncomeParent", "NetIncome", "TotalAssets"]
    q_items = sorted(set(base) | set(dvars) | set(slog) | set(label_items) | {"Lag_TotalAssets"})
    feats = base + ["dA_" + x[2:] for x in dvars] + ["sl_" + x for x in slog] + list(fc["annual_items"])
    return {"q_items": q_items, "a_items": list(fc["annual_items"]), "base": base, "dvars": dvars, "slog": slog,
            "features": feats}


def all_tickers(cfg: dict) -> list[str]:
    pf = pq.ParquetFile(p(cfg["paths"]["fund_q"]))
    s = set()
    for i in range(pf.metadata.num_row_groups):
        s.update(pc.unique(pf.read_row_group(i, columns=["Ticker"]).column(0)).to_pylist())
    return sorted(s)


# ---------------------------------------------------------------------------------------------- as-of 조밀 배열
def _read_long(path: Path, lo: str, hi: str, items: list[str], truncate_day: int | None) -> pd.DataFrame:
    dset = ds.dataset(str(path), format="parquet")
    flt = (ds.field("Ticker") >= lo) & (ds.field("Ticker") <= hi) & ds.field("Item").isin(items)
    t = dset.to_table(columns=["Ticker", "Item", "Period_Date", "Factor_Date", "Value"], filter=flt)
    df = pd.DataFrame({
        "Ticker": t.column("Ticker").to_numpy(zero_copy_only=False),
        "Item": t.column("Item").to_numpy(zero_copy_only=False),
        "pd": _days(t.column("Period_Date").to_numpy(zero_copy_only=False)),
        "fd": _days(t.column("Factor_Date").to_numpy(zero_copy_only=False)),
        "v": t.column("Value").to_numpy(zero_copy_only=False).astype(np.float64),
    })
    if truncate_day is not None:                        # 자가 시험: 결정일 뒤에 쓸 수 있게 된 행을 원천에서 잘라낸다
        df = df[df["fd"] <= truncate_day]
    return df


def asof_dense(df: pd.DataFrame, tickers: list[str], items: list[str], me_days: np.ndarray, stale_months: int):
    """(종목, 항목, 월) 조밀 배열 — 값 V(float32) · 기간 말 P(일수) · Factor_Date F(일수).
    월 m 의 값 = Factor_Date <= ME[m] 인 마지막 행(같은 종목 · 항목 안에서 Factor_Date 는 기간 순으로 엄격히 증가 — 캐시의 날짜 순서 계약)."""
    nT, nI, M = len(tickers), len(items), len(me_days)
    V = np.full((nT * nI, M), np.nan, np.float32)
    P = np.full((nT * nI, M), -1, np.int32)
    F = np.full((nT * nI, M), -1, np.int32)
    if len(df):
        tk = pd.Categorical(df["Ticker"], categories=tickers).codes.astype(np.int64)
        it = pd.Categorical(df["Item"], categories=items).codes.astype(np.int64)
        fd = df["fd"].to_numpy(); m = np.searchsorted(me_days, fd, side="left")   # 그 행을 처음 쓸 수 있는 월말(ME >= Factor_Date)
        ok = (tk >= 0) & (it >= 0) & (m < M) & np.isfinite(df["v"].to_numpy())
        tk, it, m, fd = tk[ok], it[ok], m[ok], fd[ok]
        v = df["v"].to_numpy()[ok]; pdd = df["pd"].to_numpy()[ok]
        row = tk * nI + it
        order = np.lexsort((fd, m, row))
        row, m, fd, v, pdd = row[order], m[order], fd[order], v[order], pdd[order]
        last = np.ones(len(row), bool)
        last[:-1] = (row[1:] != row[:-1]) | (m[1:] != m[:-1])                       # 같은 칸에 여럿이면 가장 늦은 Factor_Date
        row, m, fd, v, pdd = row[last], m[last], fd[last], v[last], pdd[last]
        V[row, m] = v; P[row, m] = pdd; F[row, m] = fd
    # 앞으로 채우기(값이 생긴 뒤 다음 값이 생길 때까지)
    has = F >= 0
    idx = np.where(has, np.arange(M, dtype=np.int32)[None, :], -1).astype(np.int32)
    np.maximum.accumulate(idx, axis=1, out=idx)
    got = idx >= 0
    idx0 = np.where(got, idx, 0)
    r = np.arange(nT * nI)[:, None]
    V = np.where(got, V[r, idx0], np.nan).astype(np.float32)
    P = np.where(got, P[r, idx0], -1).astype(np.int32)
    F = np.where(got, F[r, idx0], -1).astype(np.int32)
    # 묵은 값 거르기: 기간 말 < 결정일 − stale_months 개월
    min_pd = _days((pd.DatetimeIndex(me_days) - pd.DateOffset(months=stale_months)).to_numpy())
    stale = P < min_pd[None, :]
    V[stale] = np.nan; P[stale] = -1; F[stale] = -1
    # PIT 단정: 쓰인 모든 값의 Factor_Date <= 그 월말
    me_i = me_days.astype(np.int64)
    viol = (F >= 0) & (F > me_i[None, :])
    if viol.any():
        raise AssertionError(f"[nlff PIT] as-of 위반 {int(viol.sum())}칸 — Factor_Date > 결정일")
    return V.reshape(nT, nI, M), P.reshape(nT, nI, M), F.reshape(nT, nI, M)


def build_chunk(cfg: dict, spec: dict, tickers: list[str], me: np.ndarray, truncate_day: int | None = None) -> pd.DataFrame:
    """종목 묶음 하나의 월별 입력 패널(넓은 표) + 이익 변화 표적(y_earn · avail_earn)."""
    me_days = me.astype(np.int64)
    lo, hi = tickers[0], tickers[-1]
    st = cfg["staleness_months"]
    LQ = _read_long(p(cfg["paths"]["fund_q"]), lo, hi, spec["q_items"], truncate_day)
    LQ = LQ[LQ["Ticker"].isin(tickers)]
    items = spec["q_items"]
    V, P, F = asof_dense(LQ, tickers, items, me_days, int(st["q"]))
    ix = {k: i for i, k in enumerate(items)}
    nT, M = len(tickers), len(me_days)
    cols: dict[str, np.ndarray] = {}
    for x in spec["base"]:
        cols[x] = V[:, ix[x], :]
    lagTA = V[:, ix["Lag_TotalAssets"], :]
    with np.errstate(divide="ignore", invalid="ignore"):
        for d in spec["dvars"]:
            cols["dA_" + d[2:]] = np.where(lagTA > 0, V[:, ix[d], :] / lagTA, np.nan).astype(np.float32)
        for s in spec["slog"]:
            x = V[:, ix[s], :]
            cols["sl_" + s] = (np.sign(x) * np.log1p(np.abs(x))).astype(np.float32)
    if spec["a_items"]:
        LA = _read_long(p(cfg["paths"]["fund_a"]), lo, hi, spec["a_items"], truncate_day)
        LA = LA[LA["Ticker"].isin(tickers)]
        VA, _, _ = asof_dense(LA, tickers, spec["a_items"], me_days, int(st["a"]))
        for j, a in enumerate(spec["a_items"]):
            cols[a] = VA[:, j, :]
    out = pd.DataFrame({k: v.reshape(-1) for k, v in cols.items()})
    out.insert(0, "Ticker", np.repeat(np.array(tickers, dtype=object), M))
    out.insert(0, "Date", np.tile(me, nT))
    # ---- 이익 변화 표적(earn): 결정일에 쓰인 순이익 기간 P0 → 4분기 뒤 기간 P1 의 TTM 순이익 · 실현일 = P1 행 Factor_Date ----
    vP, vN = V[:, ix["NetIncomeParent"], :], V[:, ix["NetIncome"], :]
    use_par = np.isfinite(vP)
    P0 = np.where(use_par, P[:, ix["NetIncomeParent"], :], P[:, ix["NetIncome"], :]).reshape(-1)
    item0 = np.where(use_par, "NetIncomeParent", "NetIncome").reshape(-1)
    pdates = pd.to_datetime(np.where(P0 >= 0, P0, 0).astype("datetime64[D]"))
    ym0 = (pdates.year * 12 + pdates.month).to_numpy()
    q = pd.DataFrame({"Ticker": out["Ticker"].to_numpy(), "Item": item0, "ym0": ym0, "ok": P0 >= 0})
    tab = LQ[LQ["Item"].isin(["NetIncomeParent", "NetIncome", "TotalAssets"])].copy()
    pdt = pd.to_datetime(tab["pd"].to_numpy().astype("datetime64[D]"))
    tab["ym"] = (pdt.year * 12 + pdt.month).to_numpy()
    # 같은 기간 행이 여럿이면 가장 먼저 쓸 수 있게 된 값(Factor_Date 최소) — 순서를 정해 결정적으로 고른다
    tab = tab.sort_values(["Ticker", "Item", "ym", "fd"], kind="mergesort").drop_duplicates(["Ticker", "Item", "ym"], keep="first")
    ni = tab[tab["Item"] != "TotalAssets"][["Ticker", "Item", "ym", "v", "fd"]]
    ta = tab[tab["Item"] == "TotalAssets"][["Ticker", "ym", "v"]].rename(columns={"v": "ta0", "ym": "ym0"})
    q = q.merge(ni.rename(columns={"ym": "ym0", "v": "ni0", "fd": "fd0"}), on=["Ticker", "Item", "ym0"], how="left")
    q["ym1"] = q["ym0"] + 12
    q = q.merge(ni.rename(columns={"ym": "ym1", "v": "ni1", "fd": "fd1"}), on=["Ticker", "Item", "ym1"], how="left")
    q = q.merge(ta, on=["Ticker", "ym0"], how="left")
    good = q["ok"].to_numpy() & np.isfinite(q["ni1"].to_numpy()) & np.isfinite(q["ni0"].to_numpy()) & (q["ta0"].to_numpy() > 0)
    y = np.where(good, (q["ni1"].to_numpy() - q["ni0"].to_numpy()) / np.where(good, q["ta0"].to_numpy(), 1.0), np.nan)
    av = np.where(good, q["fd1"].to_numpy(), -1).astype(np.int64)
    if truncate_day is None:   # 표적 방향 단정: 실현일은 결정일보다 뒤(미래 기간 값이 결정일에 이미 쓸 수 있었다면 as-of 가 그 값을 골랐을 것)
        dd = _days(out["Date"].to_numpy())
        bad = good & (av <= dd)
        if bad.any():
            raise AssertionError(f"[nlff PIT] earn 표적 실현일 <= 결정일 {int(bad.sum())}행")
    out["y_earn"] = y.astype(np.float32)
    out["avail_earn"] = np.where(good, av, -1)
    feats = [c for c in spec["features"] if c in out.columns]
    keep = out[feats].notna().any(axis=1).to_numpy()
    return out.loc[keep].reset_index(drop=True)


def pit_selftest_features(cfg: dict, spec: dict, tickers: list[str], me: np.ndarray, full: pd.DataFrame, n_months: int = 3) -> dict:
    """미래 행 잘라내기 불변성: 월 t 의 입력 = '원천을 Factor_Date <= t 로 잘라 다시 만든 입력' 과 같아야 한다."""
    feats = [c for c in spec["features"] if c in full.columns]
    picks = me[np.linspace(len(me) // 3, len(me) - 1, n_months).astype(int)]
    checked = 0
    for t in picks:
        tr = build_chunk(cfg, spec, tickers, me[me <= t], truncate_day=int(t.astype(np.int64)))
        a = tr[tr["Date"] == t].set_index("Ticker")[feats].sort_index()
        b = full[full["Date"] == t].set_index("Ticker")[feats].sort_index()
        b = b.reindex(a.index)
        eq = np.array_equal(a.to_numpy(np.float32), b.to_numpy(np.float32), equal_nan=True)
        if not eq or len(a) != (full["Date"] == t).sum():
            raise AssertionError(f"[nlff PIT] 잘라내기 불변성 실패 — {t}")
        checked += len(a)
    return {"months": [str(x) for x in picks], "rows_checked": int(checked), "pass": True}


# ---------------------------------------------------------------------------------------------- 가격 쪽: 위생 · 표적
def price_panel(cfg: dict, me: np.ndarray, ax: dict, horizon: int = 12, chunk: int = 600) -> pd.DataFrame:
    """월말 행마다 위생 멤버 여부 · 로그 시가총액 · 향후 12개월 KOSPI200 대비 초과 수익 · 관리종목 지정 사건(+ 실현일).
    메모리 절약: 종목 묶음(chunk)마다 따로 읽고 계산한다(모든 계산이 종목 안 시계열이라 묶음과 무관)."""
    start = pd.Timestamp(me[0]) - pd.Timedelta(days=60)
    dset = ds.dataset(str(p(cfg["paths"]["rawdata"])), format="parquet")
    dflt = ds.field("Date") >= pa.scalar(start.date(), pa.date32())
    tks = sorted(pc.unique(dset.to_table(columns=["Ticker"], filter=dflt).column(0)).to_pylist())
    all_me = month_ends(cfg, "1990-01", "2099-12").astype("datetime64[s]")   # 지평 끝 계산용 달력(표적용 · 성과 계산 아님)
    bench = bench_logcum(cfg)
    out = []
    for i in range(0, len(tks), chunk):
        part = tks[i:i + chunk]
        t = dset.to_table(columns=["Date", "Ticker", "Close", "Vol", "Size", "Ret", "AdminStock", "TradingHalt", "UnfaithfulDisc"],
                          filter=dflt & ds.field("Ticker").isin(part))
        out.append(_price_chunk(cfg, t.to_pandas(), me, ax, horizon, all_me, bench))
        del t
    return pd.concat(out, ignore_index=True)


def bench_logcum(cfg: dict) -> pd.DataFrame:
    """공표 KOSPI200(등급 벤치와 같은 지수 · .cache/benchmark.parquet::BM_Ret) 누적 로그 수익 — 표적(초과 수익) 계산용.
    같은 구간 복리 = exp(bcl(끝) − bcl(시작)) − 1 (시작일 다음 거래일부터 끝일까지의 일별 수익 곱)."""
    b = pd.read_parquet(p(cfg["paths"]["benchmark"]), columns=["Date", "BM_Ret"])
    b["Date"] = pd.to_datetime(b["Date"]).astype("datetime64[s]")
    b = b.sort_values("Date").drop_duplicates("Date", keep="last").reset_index(drop=True)
    b["bcl"] = np.log1p(b["BM_Ret"].fillna(0.0)).cumsum()
    return b[["Date", "bcl"]]


def _bench_at(bench: pd.DataFrame, d: np.ndarray, max_gap_days: int = 7) -> np.ndarray:
    """날짜 d 의 벤치 누적 로그 수익(그날 또는 직전 벤치 거래일). 직전 값이 max_gap_days 보다 오래되면 NaN(벤치 결측 = 표적 없음)."""
    bd = bench["Date"].to_numpy().astype("datetime64[s]")
    d = np.asarray(d).astype("datetime64[s]")
    i = np.searchsorted(bd, d, side="right") - 1
    ok = (i >= 0) & ~np.isnat(d)
    i0 = np.where(ok, i, 0)
    gap = (d - bd[i0]).astype("timedelta64[D]").astype(np.int64)
    return np.where(ok & (gap <= max_gap_days), bench["bcl"].to_numpy()[i0], np.nan)


def _price_chunk(cfg: dict, D: pd.DataFrame, me: np.ndarray, ax: dict, horizon: int, all_me: np.ndarray,
                 bench: pd.DataFrame) -> pd.DataFrame:
    D["Date"] = D["Date"].astype("datetime64[s]")
    D.sort_values(["Ticker", "Date"], inplace=True, kind="mergesort")
    D.reset_index(drop=True, inplace=True)
    g = D.groupby("Ticker", sort=False)
    w = int(cfg["universe"]["adv_window_days"])
    tv = D["Close"] * D["Vol"]
    D["adv_l1"] = tv.groupby(D["Ticker"], sort=False).transform(lambda s: s.rolling(w, min_periods=w).mean().shift(1))
    D["close_l1"] = g["Close"].shift(1)
    mem = (D["adv_l1"] >= ax["liq_min"]).fillna(False)
    for fl in ax["flags"]:
        mem &= D[fl].isna() | (D[fl] == 0)
    if np.isfinite(ax["price_min"]):
        mem &= (D["close_l1"] >= ax["price_min"]).fillna(False)
    D["member"] = mem
    D["cl"] = np.log1p(D["Ret"].fillna(0.0)).groupby(D["Ticker"], sort=False).cumsum()
    D["ca"] = (D["AdminStock"] == 1).astype(np.int32).groupby(D["Ticker"], sort=False).cumsum()
    meT = pd.DatetimeIndex(me).as_unit("s")
    E = D[D["Date"].isin(meT)][["Date", "Ticker", "member", "Size", "cl", "ca"]].copy()
    E = E[E["member"]].drop(columns="member")
    # 지평 끝 = 12번째 다음 월말
    pos = np.searchsorted(all_me, E["Date"].to_numpy().astype("datetime64[s]"))
    endpos = pos + horizon
    E["t_end"] = np.where(endpos < len(all_me), all_me[np.minimum(endpos, len(all_me) - 1)], np.datetime64("NaT"))
    has_end = E["t_end"].notna()
    R = D[["Date", "Ticker", "cl", "ca"]].rename(columns={"Date": "d_end", "cl": "cl_end", "ca": "ca_end"})
    Q = E[has_end].sort_values("t_end")
    Q = pd.merge_asof(Q, R.sort_values("d_end"), left_on="t_end", right_on="d_end", by="Ticker", direction="backward")
    live = Q["d_end"] > Q["Date"]                       # 결정일 뒤 거래가 하나라도 있어야 표적이 있다
    # ret 표적 = 시장 대비 초과 수익(도훈 11-16): 종목 12개월 앞 단순 수익 − 같은 구간 KOSPI200 단순 수익.
    # 구간 = 결정일 다음 거래일 ~ 종목 끝일(d_end · 상장폐지면 마지막 거래일) — 벤치도 같은 시작 · 끝일로 복리.
    b0 = _bench_at(bench, Q["Date"].to_numpy()); b1 = _bench_at(bench, Q["d_end"].to_numpy())
    Q["y_ret"] = np.where(live, np.expm1(Q["cl_end"] - Q["cl"]) - np.expm1(b1 - b0), np.nan)
    Q["y_dist"] = np.where(live, (Q["ca_end"] - Q["ca"] > 0).astype(np.float32), np.nan)
    E = E.merge(Q[["Date", "Ticker", "y_ret", "y_dist"]], on=["Date", "Ticker"], how="left")
    E["avail_h"] = E["t_end"]
    E["logsize"] = np.log(E["Size"].where(E["Size"] > 0))
    return E[["Date", "Ticker", "logsize", "y_ret", "y_dist", "avail_h"]]


def ticker_fold(tickers: pd.Series, k: int, salt: str = "") -> np.ndarray:
    return np.array([zlib.crc32((salt + t).encode()) % k for t in tickers], dtype=np.int16)


def rank_centered(df: pd.DataFrame, cols: list[str], by: str = "Date") -> pd.DataFrame:
    """월별 단면 순위 → (−1, 1): (순위 − 0.5) / n × 2 − 1 · 결측은 결측 그대로(같은 달 단면 안에서만)."""
    g = df.groupby(by, sort=False)[cols]
    r = g.rank(method="average")
    n = g.transform("count")
    return ((r - 0.5) / n * 2.0 - 1.0).astype(np.float32)
