#==============================================================================
# causal_apt.py - Causal ML (Double ML) + Asset Pricing Trees (KR, long-only)
#
# Two coherent parts (the family the mandate cited):
#   (A) DML factor VALIDATION: partial-out cross-fit estimate of each characteristic's
#       causal effect on forward return, controlling for all other chars. Month-clustered
#       t-stat -> robust (non-spurious) char ranking. Directly addresses the IPCA failure
#       (noise/spurious composite). Train-only (PIT) + OOS sign-stability check.
#   (B) Asset Pricing Trees factor CONSTRUCTION: gradient-boosted trees model the nonlinear
#       conditional mean E[r | chars] (interactions a linear/IPCA model misses). Walk-forward
#       -> per-stock monthly score -> long-only top-N (measured by canonical_screen_bt).
#       Two variants: all chars vs DML-robust chars (does causal selection help OOS?).
#
# Note: full recursive P-Tree (Bryzgalova-Pelger-Zhu) basis-portfolio splitting is a future
# refinement; here APT = boosted-tree conditional mean on (causally-validated) chars, which
# captures the nonlinear-interaction claim and is deployable long-only.
#
# Env: CAPT_PANEL CAPT_OUT CAPT_MIN_TRAIN CAPT_REFIT CAPT_ROBUST_T CAPT_SEED
# Run: $env:PYTHONUTF8="1"; .venv_qvest_ml/Scripts/python.exe -u 02_Infrastructure/ml_pipeline/causal_apt.py
#==============================================================================
import os, json, time
import numpy as np
import pandas as pd
from sklearn.ensemble import HistGradientBoostingRegressor
from sklearn.model_selection import KFold
from scipy.stats import spearmanr

ROOT = os.environ.get("CLAUDE_PROJECT_DIR") or os.environ.get("QM_ROOT") or "G:/Quant_Module_Moltbot"
PANEL = os.environ.get("CAPT_PANEL", f"{ROOT}/stage_artifacts/WT_CA/panel_kr30/charpanel.parquet")
OUT   = os.environ.get("CAPT_OUT",   f"{ROOT}/stage_artifacts/WT_CAUSAL/kr30")
MIN_TRAIN = int(os.environ.get("CAPT_MIN_TRAIN", "60"))
REFIT     = int(os.environ.get("CAPT_REFIT", "12"))
ROBUST_T  = float(os.environ.get("CAPT_ROBUST_T", "2.0"))
SEED = int(os.environ.get("CAPT_SEED", "42"))
os.makedirs(OUT, exist_ok=True)
np.random.seed(SEED)
print(f"[capt] panel={PANEL} out={OUT} min_train={MIN_TRAIN} refit={REFIT} robust_t={ROBUST_T}", flush=True)


def load_panel():
    df = pd.read_parquet(PANEL)
    meta = {"Date", "YearMonth", "Ticker", "ret_fwd1m", "period_class"}
    chars = [c for c in df.columns if c not in meta]
    if "D02_Beta" in df.columns:
        df["betasq"] = df["D02_Beta"] ** 2; chars.append("betasq")
    if "Q05_Accrual" in df.columns:
        df["absacc"] = df["Q05_Accrual"].abs(); chars.append("absacc")
    for c in ["betasq", "absacc"]:
        if c in df.columns:
            g = df.groupby("YearMonth")[c]
            df[c] = ((df[c] - g.transform("mean")) / (g.transform("std") + 1e-9)).fillna(0.0)
    df["Date"] = pd.to_datetime(df["Date"])
    df = df.sort_values(["YearMonth", "Ticker"]).reset_index(drop=True)
    return df, chars


def _hgb():
    return HistGradientBoostingRegressor(max_depth=3, max_iter=200, learning_rate=0.05,
                                         l2_regularization=1.0, random_state=SEED)


def dml_validate(df, chars):
    """Cross-fit DML on TRAIN: per-char causal effect (month-clustered t)."""
    tr = df[df.period_class == "train"].copy()
    months_tr = tr["YearMonth"].values
    Y = tr["ret_fwd1m"].to_numpy()
    X_all = tr[chars].to_numpy()
    kf = KFold(n_splits=5, shuffle=True, random_state=SEED)
    rows = []
    for j, ch in enumerate(chars):
        D = tr[ch].to_numpy()
        Xmj = np.delete(X_all, j, axis=1)            # all other chars
        Yhat = np.zeros_like(Y); Dhat = np.zeros_like(D)
        for tr_idx, te_idx in kf.split(Xmj):
            my = _hgb().fit(Xmj[tr_idx], Y[tr_idx]); Yhat[te_idx] = my.predict(Xmj[te_idx])
            md = _hgb().fit(Xmj[tr_idx], D[tr_idx]); Dhat[te_idx] = md.predict(Xmj[te_idx])
        Yr, Dr = Y - Yhat, D - Dhat
        denom = float(np.sum(Dr * Dr))
        if denom <= 0:
            rows.append({"char": ch, "theta": None, "t": None}); continue
        theta = float(np.sum(Dr * Yr) / denom)
        # month-clustered SE (sandwich): sum_g (Dr_g' e_g)^2 / denom^2 ; e = Yr - theta*Dr
        e = Yr - theta * Dr
        s = Dr * e
        cl = pd.Series(s).groupby(months_tr).sum().to_numpy()
        var = float(np.sum(cl ** 2)) / (denom ** 2)
        se = np.sqrt(var) if var > 0 else np.nan
        t = theta / se if se and se == se and se > 0 else np.nan
        rows.append({"char": ch, "theta": theta, "se": float(se) if se == se else None,
                     "t": float(t) if t == t else None})
    res = pd.DataFrame(rows)
    # OOS sign-stability: per-month IC of char on val+lockbox
    oos = df[df.period_class != "train"]
    sign_ok = {}
    for ch in chars:
        ics = oos.groupby("YearMonth").apply(
            lambda g: spearmanr(g[ch], g["ret_fwd1m"]).correlation if len(g) >= 10 else np.nan)
        ics = ics.dropna()
        sign_ok[ch] = float(np.nanmean(ics)) if len(ics) else None
    res["oos_ic_mean"] = res["char"].map(sign_ok)
    res["robust"] = res.apply(
        lambda r: bool(r["t"] is not None and abs(r["t"]) >= ROBUST_T
                       and r["oos_ic_mean"] is not None
                       and np.sign(r["theta"]) == np.sign(r["oos_ic_mean"])), axis=1)
    res = res.sort_values("t", key=lambda s: s.abs(), ascending=False).reset_index(drop=True)
    return res


def to_xy(df, chars):
    months = sorted(df["YearMonth"].unique())
    by = {ym: g for ym, g in df.groupby("YearMonth")}
    return months, by


def apt_walkforward(df, chars, tag):
    months = sorted(df["YearMonth"].unique())
    by = {ym: g for ym, g in df.groupby("YearMonth")}
    rows, ics = [], []
    i = MIN_TRAIN
    t0 = time.time()
    while i < len(months):
        tr_ms = months[:i]
        bl_ms = months[i:i + REFIT]
        tr = pd.concat([by[m] for m in tr_ms])
        model = _hgb().fit(tr[chars].to_numpy(), tr["ret_fwd1m"].to_numpy())
        for m in bl_ms:
            g = by[m]
            sc = model.predict(g[chars].to_numpy())
            rr = g["ret_fwd1m"].to_numpy()
            if len(rr) >= 10:
                ic = spearmanr(sc, rr).correlation
                if ic == ic: ics.append(ic)
            for tk, s, d in zip(g["Ticker"].to_numpy(), sc, g["Date"].to_numpy()):
                rows.append((d, tk, float(s)))
        print(f"[capt:apt:{tag}] trained {len(tr_ms)}m -> scored through {bl_ms[-1]}", flush=True)
        i += REFIT
    sc = pd.DataFrame(rows, columns=["Date", "Ticker", "score"])
    sc.to_parquet(f"{OUT}/apt_scores_{tag}.parquet", index=False)
    ics = np.array(ics)
    return {"tag": tag, "n_chars": len(chars), "n_oos_months": int(sc["Date"].nunique()),
            "oos_rank_ic_mean": float(np.nanmean(ics)) if len(ics) else None,
            "oos_icir": float(np.nanmean(ics) / (np.nanstd(ics) + 1e-9)) if len(ics) else None,
            "elapsed_s": round(time.time() - t0, 1)}


def main():
    df, chars = load_panel()
    print(f"[capt] panel {len(df)} rows, {df['YearMonth'].nunique()} months, {len(chars)} chars", flush=True)

    print("[capt] (A) DML factor validation ...", flush=True)
    dml = dml_validate(df, chars)
    dml.to_csv(f"{OUT}/dml_validation.csv", index=False)
    robust = dml[dml["robust"]]["char"].tolist()
    print(f"[capt] DML robust chars (|t|>={ROBUST_T} & OOS sign match): {robust}", flush=True)
    print(dml[["char", "theta", "t", "oos_ic_mean", "robust"]].head(15).to_string(), flush=True)

    print("[capt] (B) APT walk-forward (all chars) ...", flush=True)
    diag_all = apt_walkforward(df, chars, "all")
    diag_rob = None
    if len(robust) >= 3:
        print("[capt] (B) APT walk-forward (DML-robust chars) ...", flush=True)
        diag_rob = apt_walkforward(df, robust, "robust")

    json.dump({"dml_robust_chars": robust, "apt_all": diag_all, "apt_robust": diag_rob,
               "all_chars": chars, "panel": PANEL, "robust_t": ROBUST_T},
              open(f"{OUT}/causal_diag.json", "w"), indent=2, default=str)
    print("[capt] DONE -> " + f"{OUT}/causal_diag.json", flush=True)


if __name__ == "__main__":
    main()
