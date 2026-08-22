# -*- coding: utf-8 -*-
"""
WT-D20260813_006 / FQ-234 Lane B — 월내 flow x 수익 경로 결합 피처 빌드
승계 설계: alpha_hypothesis.json 후보 C1 (하락일 개인 흡수 강도)

PIT 규약 (승계 + 저장소 컨벤션):
  - 신호일 d0 = 시장 월말 거래일. 홀딩월 = month(d0)+1. 컷오프 = 홀딩월 1일.
  - flow/price 는 **Date < d0** 만 사용 (compute_investor.R `inv[Date < sig_d]` 동일 = T+1 정산 lag).
  - 창 = 3개월 버킷 {m-2, m-1, m} 에서 d0 당일 관측 1건 제외 (충분통계 차감으로 정확 구현).

피처 (사전등록):
  PRIMARY  absorb      = -corr_win(Individual_d, Ret_d)      (높을수록 하락일 개인 흡수 강함)
  진단     absorb_share= 하락일 개인순매수 비중 - 상승일 비중 (설계 산문 정의)
  진단     absorb_1m   = 1개월 창 (회전 진단 전용)
  진단     absorb_resid= 시장수익 차감 (Ret - BM_Ret) 기준
  위반주입 absorb_naive= 창 {m-1, m, m+1} = 홀딩월 데이터 포함 (★고의 look-ahead, 판별력 실증용)
  통제     win_vol(창 내 일별수익 sd), log_size, indiv_level(= sum Individual / Size, F3 대조)
  기전     fwd_foreign_3m / fwd_inst_3m (m+1..m+3 순매수 / Size) — F1 반증 관측
"""
import sys, json
import numpy as np
import pandas as pd

sys.stdout.reconfigure(encoding="utf-8")
ROOT = r"C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUTDIR = f"{ROOT}/stage_artifacts/WT-D20260813_006"
START = "2004-08-01"          # 2005-01 첫 신호를 위한 warm-up
LOG = {}

print("[1] load RAWDATA", flush=True)
raw = pd.read_parquet(f"{ROOT}/.cache/RAWDATA.parquet",
                      columns=["Date", "Ticker", "K200", "KQ150", "Close", "Vol",
                               "Size", "Ret", "BM_Ret"])
raw["Date"] = pd.to_datetime(raw["Date"])
raw = raw[raw["Date"] >= START]
raw["univ"] = (raw["K200"].fillna(0) > 0) | (raw["KQ150"].fillna(0) > 0)
raw = raw[raw["univ"]].drop(columns=["K200", "KQ150", "univ"])
print("   universe rows:", len(raw), flush=True)

print("[2] load investor_wide", flush=True)
inv = pd.read_parquet(f"{ROOT}/.cache/investor_stock/investor_wide.parquet",
                      columns=["Date", "Ticker", "Foreign", "Individual", "Institutional"])
inv["Date"] = pd.to_datetime(inv["Date"])
inv = inv[inv["Date"] >= START]

df = raw.merge(inv, on=["Date", "Ticker"], how="inner")
LOG["merge_universe_rows"] = int(len(raw))
LOG["merge_joined_rows"] = int(len(df))
LOG["merge_join_rate"] = float(len(df) / len(raw))
print("   joined:", len(df), "rate", LOG["merge_join_rate"], flush=True)

df = df[np.isfinite(df["Ret"]) & np.isfinite(df["Individual"])]
df["ym"] = df["Date"].dt.to_period("M")

# ---- 시장 월말 거래일 (신호일 d0) ----
mend = df.groupby("ym")["Date"].max()
df["is_mend"] = df["Date"].values == mend.reindex(df["ym"]).values

# ---- 월별 충분통계 (x=Individual, y=Ret, yr=Ret-BM_Ret) ----
df["yr"] = df["Ret"] - df["BM_Ret"]
df["xy"] = df["Individual"] * df["Ret"]
df["xyr"] = df["Individual"] * df["yr"]
df["xx"] = df["Individual"] ** 2
df["yy"] = df["Ret"] ** 2
df["yryr"] = df["yr"] ** 2
df["dn_x"] = np.where(df["Ret"] < 0, df["Individual"], 0.0)     # 하락일 개인 순매수
df["up_x"] = np.where(df["Ret"] > 0, df["Individual"], 0.0)     # 상승일
df["abs_x"] = df["Individual"].abs()

AGG = dict(n=("Ret", "size"), Sx=("Individual", "sum"), Sy=("Ret", "sum"),
           Sxx=("xx", "sum"), Syy=("yy", "sum"), Sxy=("xy", "sum"),
           Syr=("yr", "sum"), Syryr=("yryr", "sum"), Sxyr=("xyr", "sum"),
           Sdn=("dn_x", "sum"), Sup=("up_x", "sum"), Sabs=("abs_x", "sum"),
           SFor=("Foreign", "sum"), SInst=("Institutional", "sum"))


def agg_stats(frame):
    g = frame.groupby(["Ticker", "ym"], observed=True).agg(**AGG).reset_index()
    return g


print("[3] monthly sufficient statistics", flush=True)
G = agg_stats(df)
L = agg_stats(df[df["is_mend"]])       # 월말 당일(d0) 관측 — 차감용
STATCOLS = [c for c in G.columns if c not in ("Ticker", "ym")]

# 월말 상태 패널(Size/Close/Vol at d0)
mend_panel = df[df["is_mend"]][["Ticker", "ym", "Date", "Size", "Close", "Vol"]].copy()

# ---- ym -> 정수 인덱스 ----
all_ym = pd.period_range(G["ym"].min(), G["ym"].max(), freq="M")
ym2i = {p: i for i, p in enumerate(all_ym)}
G["mi"] = G["ym"].map(ym2i)
L["mi"] = L["ym"].map(ym2i)
mend_panel["mi"] = mend_panel["ym"].map(ym2i)

tickers = pd.Index(sorted(df["Ticker"].unique()))
t2i = {t: i for i, t in enumerate(tickers)}
NT, NM = len(tickers), len(all_ym)
print("   tickers", NT, "months", NM, flush=True)

# ---- 조밀 배열 (Ticker x Month x stat) ----
A = {c: np.zeros((NT, NM), dtype=np.float64) for c in STATCOLS}
ti = G["Ticker"].map(t2i).to_numpy()
mi = G["mi"].to_numpy()
for c in STATCOLS:
    A[c][ti, mi] = G[c].to_numpy()
B = {c: np.zeros((NT, NM), dtype=np.float64) for c in STATCOLS}
ti2 = L["Ticker"].map(t2i).to_numpy()
mi2 = L["mi"].to_numpy()
for c in STATCOLS:
    B[c][ti2, mi2] = L[c].to_numpy()


def window_sum(mat, m, k, drop_last_day=False, offset=0):
    """신호월 m 기준 창 [m-k+1+offset .. m+offset] 합. drop_last_day=True 면 d0 당일 차감."""
    lo, hi = m - k + 1 + offset, m + offset
    if lo < 0 or hi >= NM:
        return None
    s = mat[:, lo:hi + 1].sum(axis=1)
    return s


def build_window(k, offset=0, drop_d0=True):
    """반환: dict of (NT x NM) 창 통계. offset=+1 이면 홀딩월 포함(위반 주입)."""
    out = {c: np.full((NT, NM), np.nan) for c in STATCOLS}
    for m in range(NM):
        lo, hi = m - k + 1 + offset, m + offset
        if lo < 0 or hi >= NM:
            continue
        for c in STATCOLS:
            s = A[c][:, lo:hi + 1].sum(axis=1)
            if drop_d0:
                s = s - B[c][:, m]        # 신호일 d0 당일 관측 제외 (strict Date < d0)
            out[c][:, m] = s
    return out


def corr_from(st, xkey="Sx", ykey="Sy", xxkey="Sxx", yykey="Syy", xykey="Sxy"):
    n = st["n"]
    with np.errstate(invalid="ignore", divide="ignore"):
        cov = st[xykey] - st[xkey] * st[ykey] / n
        vx = st[xxkey] - st[xkey] ** 2 / n
        vy = st[yykey] - st[ykey] ** 2 / n
        r = cov / np.sqrt(vx * vy)
    r[~np.isfinite(r)] = np.nan
    return r


print("[4] window stats", flush=True)
W3 = build_window(3, offset=0, drop_d0=True)         # PRIMARY
W1 = build_window(1, offset=0, drop_d0=True)         # 1개월 진단
WN = build_window(3, offset=1, drop_d0=False)        # ★위반 주입: 홀딩월(m+1) 포함

MIN_N = 40
MIN_N1 = 12

res = []
for name, st, minn in (("w3", W3, MIN_N), ("w1", W1, MIN_N1), ("naive", WN, MIN_N)):
    r_raw = corr_from(st)
    r_res = corr_from(st, ykey="Syr", yykey="Syryr", xykey="Sxyr")
    ok = st["n"] >= minn
    r_raw = np.where(ok, r_raw, np.nan)
    r_res = np.where(ok, r_res, np.nan)
    res.append((name, r_raw, r_res, st, ok))

# 하락/상승 배치 비중 차 (설계 산문 정의)
st3 = W3
with np.errstate(invalid="ignore", divide="ignore"):
    share_diff = (st3["Sdn"] - st3["Sup"]) / st3["Sabs"]
share_diff[~np.isfinite(share_diff)] = np.nan
share_diff = np.where(st3["n"] >= MIN_N, share_diff, np.nan)

# 창 내 일별수익 sd (통제)
with np.errstate(invalid="ignore", divide="ignore"):
    win_var = (st3["Syy"] - st3["Sy"] ** 2 / st3["n"]) / (st3["n"] - 1)
win_vol = np.sqrt(np.maximum(win_var, 0))
win_vol = np.where(st3["n"] >= MIN_N, win_vol, np.nan)

# 월간 flow level (F3 hidden-clone 대조) — 같은 창의 개인 순매수 합
indiv_level_raw = np.where(st3["n"] >= MIN_N, st3["Sx"], np.nan)

# 후속 3개월 flow (F1 기전 관측) — m+1..m+3
fwd_for = np.full((NT, NM), np.nan)
fwd_ins = np.full((NT, NM), np.nan)
for m in range(NM - 3):
    fwd_for[:, m] = A["SFor"][:, m + 1:m + 4].sum(axis=1)
    fwd_ins[:, m] = A["SInst"][:, m + 1:m + 4].sum(axis=1)

print("[5] assemble long panel", flush=True)
mp = mend_panel.copy()
mp["tix"] = mp["Ticker"].map(t2i)
r_by = {n: (a, b, st, ok) for n, a, b, st, ok in res}
ti_ = mp["tix"].to_numpy()
mi_ = mp["mi"].to_numpy()

mp["absorb"] = -r_by["w3"][0][ti_, mi_]
mp["absorb_resid"] = -r_by["w3"][1][ti_, mi_]
mp["absorb_1m"] = -r_by["w1"][0][ti_, mi_]
mp["absorb_naive"] = -r_by["naive"][0][ti_, mi_]
mp["absorb_share"] = share_diff[ti_, mi_]
mp["win_vol"] = win_vol[ti_, mi_]
mp["n_win"] = st3["n"][ti_, mi_]
mp["indiv_sum"] = indiv_level_raw[ti_, mi_]
mp["fwd_foreign_3m"] = fwd_for[ti_, mi_]
mp["fwd_inst_3m"] = fwd_ins[ti_, mi_]
mp["indiv_level"] = mp["indiv_sum"] / mp["Size"].replace(0, np.nan)
mp["fwd_foreign_3m_n"] = mp["fwd_foreign_3m"] / mp["Size"].replace(0, np.nan)
mp["fwd_inst_3m_n"] = mp["fwd_inst_3m"] / mp["Size"].replace(0, np.nan)
mp["log_size"] = np.log(mp["Size"].replace(0, np.nan))

out = mp[["Date", "Ticker", "ym", "absorb", "absorb_resid", "absorb_1m", "absorb_naive",
          "absorb_share", "win_vol", "n_win", "indiv_level", "log_size",
          "fwd_foreign_3m_n", "fwd_inst_3m_n", "Size"]].copy()
out["ym"] = out["ym"].astype(str)
out = out[out["Date"] >= "2004-12-01"]

LOG["panel_rows"] = int(len(out))
LOG["panel_date_min"] = str(out["Date"].min().date())
LOG["panel_date_max"] = str(out["Date"].max().date())
LOG["absorb_nonnull"] = int(out["absorb"].notna().sum())
LOG["absorb_nonnull_frac"] = float(out["absorb"].notna().mean())
LOG["absorb_describe"] = {k: float(v) for k, v in out["absorb"].describe().items()}
LOG["absorb_naive_nonnull"] = int(out["absorb_naive"].notna().sum())
LOG["n_months"] = int(out["Date"].nunique())

out.to_parquet(f"{OUTDIR}/absorb_panel.parquet", index=False)
with open(f"{OUTDIR}/01_build_log.json", "w", encoding="utf-8") as f:
    json.dump(LOG, f, ensure_ascii=False, indent=1)
print(json.dumps(LOG, ensure_ascii=False, indent=1))
