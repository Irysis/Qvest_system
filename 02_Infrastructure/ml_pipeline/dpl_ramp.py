#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
dpl_ramp.py — RAMP 102 순수팩터 → DPL(Direct Portfolio Learning) end-to-end (pure torch).
도훈 선택(2026-06-18): "PG2 못 넘는 벽=2017+ decay. DPL end-to-end 시도."

설계(You-Zhang 2025 정합, cvxpy 의존 제거판):
  features(102 neutralized_z) → MLP → μ̂(per-name) → top-25 사전선택
  → differentiable softmax-cap allocation w=clamp(softmax(μ̂/τ),≤0.20) renorm (long-only/Σw=1)
  → realized net Sharpe loss(−Sharpe + var-reg) → end-to-end backprop.
PIT: walk-forward(rolling train, 1-step OOS). 비용 15bps one-way(canonical_screen 정합). 벤치=cap-w universe.
검증: DPL vs EW_topN vs InvVol(비-DPL 위험인지) net 시계열 → IS/OOS active IR(vs cap-w) → book 0.795.
자체합성 backtest 금지: 월별 net return series만 산출(동일 cost 규약). 실행: .venv_qvest_ml python.
"""
import os, sys, json
import numpy as np, pandas as pd, torch

THIS_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.abspath(os.path.join(THIS_DIR, "..", ".."))
RAWDATA = os.path.join(PROJECT_ROOT, ".cache", "rawdata.parquet")
PURE = os.path.join(PROJECT_ROOT, "outputs", "ramp", "pure_factor_scores.parquet")
OUT_DIR = os.path.join(PROJECT_ROOT, "stage_artifacts", "WT_DPL_RAMP"); os.makedirs(OUT_DIR, exist_ok=True)
torch.set_default_dtype(torch.float64); np.random.seed(7); torch.manual_seed(7)

CAP, ACTIVE_MAX, COST_BPS, LIQ_MIN, ANN, TOP_N_EW = 0.20, 25, 15.0, 2e8, 12.0, 20
MIN_TRAIN, REFIT_EVERY, TRAIN_WINDOW, HIST_COV = 48, 36, 60, 36
TAU, LAM_VAR, LR, EPOCHS = 1.0, 0.5, 1e-2, 40


class DPLNet(torch.nn.Module):
    def __init__(self, n_feat, hidden=24):
        super().__init__()
        self.net = torch.nn.Sequential(torch.nn.Linear(n_feat, hidden), torch.nn.Tanh(),
                                        torch.nn.Linear(hidden, 1))
    def forward(self, X): return self.net(X).squeeze(-1)


def alloc(mu, cap=CAP, tau=TAU):
    """differentiable long-only allocation: softmax → cap-clamp → renorm (Σw=1, w≤cap 근사)."""
    w = torch.softmax(mu / tau, dim=0)
    for _ in range(4):                       # water-filling cap (미분가능 반복)
        over = w > cap
        if not bool(over.any()): break
        excess = (w[over] - cap).sum()
        w = torch.where(over, torch.full_like(w, cap), w)
        free = ~over
        s = w[free].sum()
        if bool(free.any()) and float(s) > 1e-9:
            add = torch.zeros_like(w); add[free] = w[free] / s * excess; w = w + add
    return w


def load_ramp_panel():
    sc = pd.read_parquet(PURE, columns=["signal_date", "security_id", "factor_id", "neutralized_z"])
    sc["ym"] = pd.to_datetime(sc["signal_date"]).dt.to_period("M")
    w = sc.pivot_table(index=["ym", "security_id"], columns="factor_id", values="neutralized_z").reset_index()
    w = w.rename(columns={"security_id": "Ticker"})
    feat = [c for c in w.columns if c not in ("ym", "Ticker")]
    w[feat] = w[feat].fillna(0.0)
    print(f"[ramp-dpl] panel {w.shape} factors={len(feat)}", flush=True)
    return w, feat


def build_returns_liq_capw():
    raw = pd.read_parquet(RAWDATA, columns=["Date", "Ticker", "Close", "Vol", "Size",
                                            "K200", "KQ150", "AdminStock", "TradingHalt"])
    raw["Date"] = pd.to_datetime(raw["Date"]); raw = raw.sort_values(["Ticker", "Date"])
    raw = raw[raw["Close"].notna() & (raw["Close"] > 0)]
    raw["adv20"] = raw.groupby("Ticker").apply(
        lambda g: (g["Close"] * g["Vol"]).rolling(20, min_periods=10).mean()).reset_index(level=0, drop=True)
    raw["adv20_lag1"] = raw.groupby("Ticker")["adv20"].shift(1)
    raw["ym"] = raw["Date"].dt.to_period("M")
    me = raw.groupby(["Ticker", "ym"]).tail(1).copy().sort_values(["Ticker", "ym"])
    me["Ret_1m"] = me.groupby("Ticker")["Close"].shift(-1) / me["Close"] - 1.0
    bad = (me["AdminStock"].fillna(0) > 0) | (me["TradingHalt"].fillna(0) > 0)
    me.loc[bad, "Ret_1m"] = np.nan
    me["inuniv"] = (me["K200"] == True) | (me["KQ150"] == True)
    rets = me.loc[me["Ret_1m"].notna(), ["ym", "Ticker", "Ret_1m"]]
    liq = me[["ym", "Ticker", "adv20_lag1"]].rename(columns={"adv20_lag1": "adv"})
    u = me[me["inuniv"] & me["Ret_1m"].notna() & me["Size"].notna() & (me["Size"] > 0)]
    bm = u.groupby("ym").apply(lambda x: np.average(x["Ret_1m"], weights=x["Size"])).rename("BM_Ret_1m").reset_index()
    return rets, liq, bm


def main():
    panel, feat = load_ramp_panel()
    rets, liq, bm_m = build_returns_liq_capw()
    panel = panel.merge(rets, on=["ym", "Ticker"], how="inner").merge(liq, on=["ym", "Ticker"], how="left")
    panel = panel[(panel["adv"].isna()) | (panel["adv"] >= LIQ_MIN)].copy()
    months = sorted(panel["ym"].unique())
    print(f"[ramp-dpl] months={len(months)} [{months[0]}..{months[-1]}] rows={len(panel)}", flush=True)
    rwide = panel.pivot_table(index="ym", columns="Ticker", values="Ret_1m")

    def mtens(m):
        sub = panel[panel["ym"] == m]
        return (torch.tensor(sub[feat].values), torch.tensor(sub["Ret_1m"].values), sub["Ticker"].values)

    def train_model(tr):
        model = DPLNet(len(feat)); opt = torch.optim.Adam(model.parameters(), lr=LR)
        for ep in range(EPOCHS):
            opt.zero_grad(); prs = []; wprev = {}
            for m in tr:
                X, r, tk = mtens(m)
                if len(tk) < 6: continue
                mu_all = model(X); k = min(ACTIVE_MAX, len(tk))
                idx = torch.topk(mu_all.detach(), k).indices
                mu = mu_all[idx]; r_sel = r[idx]; tks = tk[idx.cpu().numpy()]
                w = alloc(mu)
                wp = torch.tensor(np.array([wprev.get(t, 0.0) for t in tks]))
                cost = (w - wp).abs().sum() * COST_BPS / 1e4
                prs.append((w * r_sel).sum() - cost)
                wprev = {t: float(v) for t, v in zip(tks, w.detach().numpy())}
            if len(prs) < 12: return model
            pr = torch.stack(prs); sharpe = pr.mean() / (pr.std() + 1e-6) * np.sqrt(ANN)
            (-sharpe + LAM_VAR * (pr - pr.mean()).pow(2).mean()).backward(); opt.step()
        return model

    @torch.no_grad()
    def dpl_month(model, m, wprev):
        X, r, tk = mtens(m)
        if len(tk) < 6: return None, wprev
        mu_all = model(X); k = min(ACTIVE_MAX, len(tk))
        idx = torch.topk(mu_all, k).indices; mu = mu_all[idx]; tks = tk[idx.cpu().numpy()]
        w = alloc(mu).numpy()
        return [(m, t, float(v)) for t, v in zip(tks, w) if v > 1e-5], {t: float(v) for t, v in zip(tks, w)}

    oos = []; wprev = {}; model = None
    for i in range(MIN_TRAIN, len(months)):
        m = months[i]
        if (model is None) or ((i - MIN_TRAIN) % REFIT_EVERY == 0):
            tr = months[max(0, i - TRAIN_WINDOW):i]
            print(f"[ramp-dpl] refit @ {m} (train {tr[0]}..{tr[-1]} {len(tr)}m)", flush=True)
            model = train_model(tr)
        rows, wprev = dpl_month(model, m, wprev)
        if rows: oos += rows
    dpl_w = pd.DataFrame(oos, columns=["ym", "Ticker", "w"])
    oos_m = sorted(dpl_w["ym"].unique())
    print(f"[ramp-dpl] OOS {len(oos_m)}m [{oos_m[0]}..{oos_m[-1]}]", flush=True)
    pan = panel[panel["ym"].isin(oos_m)].copy(); pan["sew"] = pan[feat].mean(axis=1)

    ew = []
    for m, g in pan.groupby("ym"):
        top = g.nlargest(TOP_N_EW, "sew"); v = 1.0 / len(top)
        ew += [(m, t, v) for t in top["Ticker"]]
    ew_w = pd.DataFrame(ew, columns=["ym", "Ticker", "w"])

    iv = []   # inverse-vol top-25 (비-DPL 위험인지 baseline, cvxpy 불요)
    for m, g in pan.groupby("ym"):
        g2 = g.nlargest(ACTIVE_MAX, "sew"); tk = g2["Ticker"].values
        hist = rwide.loc[rwide.index < m, tk].tail(HIST_COV)
        vol = hist.std().reindex(tk).fillna(hist.std().median()).values
        iw = 1.0 / np.clip(vol, 1e-4, None); iw = np.minimum(iw / iw.sum(), CAP); iw = iw / iw.sum()
        iv += [(m, t, float(x)) for t, x in zip(tk, iw) if x > 1e-5]
    iv_w = pd.DataFrame(iv, columns=["ym", "Ticker", "w"])

    def net_series(wdf):
        wj = wdf.merge(rets, on=["ym", "Ticker"], how="left"); wj["Ret_1m"] = wj["Ret_1m"].fillna(0.0)
        gross = wj.groupby("ym").apply(lambda x: float(np.sum(x["w"] * x["Ret_1m"]))).rename("g")
        traded = {}; prev = {}
        for m in sorted(wdf["ym"].unique()):
            cur = dict(zip(wdf[wdf["ym"] == m]["Ticker"], wdf[wdf["ym"] == m]["w"]))
            keys = set(cur) | set(prev); traded[m] = sum(abs(cur.get(k, 0.0) - prev.get(k, 0.0)) for k in keys); prev = cur
        o = gross.reset_index(); o["traded"] = o["ym"].map(traded)
        o["ret_net"] = o["g"] - o["traded"] * COST_BPS / 1e4
        return o

    rows = []
    for name, wdf in [("DPL", dpl_w), ("EW_topN", ew_w), ("InvVol", iv_w)]:
        s = net_series(wdf).merge(bm_m, on="ym", how="left"); s["date"] = s["ym"].dt.to_timestamp("M")
        for _, r in s.iterrows():
            rows.append({"method": name, "date": r["date"], "ret_net": r["ret_net"],
                         "BM_Ret": r["BM_Ret_1m"], "traded": r["traded"]})
    out_df = pd.DataFrame(rows); out_path = os.path.join(OUT_DIR, "dpl_ramp_net_returns.parquet")
    out_df.to_parquet(out_path, index=False)

    def ir_split(d):
        d = d.dropna(subset=["BM_Ret"]).sort_values("date"); a = d["ret_net"].values - d["BM_Ret"].values
        n = len(a); cut = int(n * 0.6)
        f = lambda x: x.mean() / (x.std() + 1e-12) * np.sqrt(12)
        return f(a), f(a[:cut]), f(a[cut:]), n, cut
    print("\n[ramp-dpl] === active IR vs cap-w (net 15bps) | book ref=0.795 ===", flush=True)
    print(f"  {'method':12s} {'full':>7s} {'IS':>7s} {'OOS':>7s}  TO_ann", flush=True)
    diag = {}
    for name in ["DPL", "EW_topN", "InvVol"]:
        d = out_df[out_df["method"] == name]
        full, isr, oosr, n, cut = ir_split(d)
        to = d.dropna(subset=["BM_Ret"])["traded"].mean() * 12
        diag[name] = dict(full=full, IS=isr, OOS=oosr, n=int(n), TO=float(to))
        print(f"  {name:12s} {full:+7.3f} {isr:+7.3f} {oosr:+7.3f}  {to:5.2f}", flush=True)
    json.dump({"feature_n": len(feat), "oos": [str(oos_m[0]), str(oos_m[-1])],
               "diag_active_IR_vs_capw": diag,
               "config": dict(MIN_TRAIN=MIN_TRAIN, REFIT_EVERY=REFIT_EVERY, TRAIN_WINDOW=TRAIN_WINDOW,
                              EPOCHS=EPOCHS, TAU=TAU, hidden=24)},
              open(os.path.join(OUT_DIR, "dpl_ramp_meta.json"), "w"), indent=2)
    print(f"[ramp-dpl] -> {out_path}\nRAMP_DPL_DONE", flush=True)


if __name__ == "__main__":
    main()
