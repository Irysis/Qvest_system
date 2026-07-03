"""
334_leading_multiseed.py — multi-seed robustness of the h=21 paper_only vs with_leading
forward bear catch. Single-seed skewed-t CNN is unstable (v0.6 R17); confirm whether the
leading-credit CRPS improvement + COVID P(-10%) lift are real or seed-noise, and re-check
discrimination (COVID percentile vs model's own test P(-10%) distribution) per seed.

도훈 mandate 2026-06-26.
"""
from __future__ import annotations
import importlib.util, json, sys
from pathlib import Path
import numpy as np, pandas as pd, torch, yaml

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
def _load(n,p):
    s=importlib.util.spec_from_file_location(n,p); m=importlib.util.module_from_spec(s); s.loader.exec_module(m); return m
M331=_load("m331", str(ROOT/"scripts"/"331_b1_macro_features.py"))
M333=_load("m333", str(ROOT/"scripts"/"333_b1_leading_macro.py"))
VARBT=_load("vb", str(ROOT/"04_evaluation"/"var_backtest.py"))

SEEDS=[0,1,2,3,4]
COVID=pd.Timestamp("2020-02-19")

def one(cfg, df, feats, device, seed, horizon=21):
    X,y,dates=M331.build_sequences(df, cfg["training"]["sequence_length"], feats, f"ret_fwd_{horizon}d")
    wins=M331.walk_forward(len(X), train_min=cfg["walk_forward"]["train_min"], test=cfg["walk_forward"]["test_window"])
    preds=[]
    for tr,te in wins:
        th,_=M331.train_eval(X[:tr],y[:tr],X[tr:te],y[tr:te],"skewed_t",cfg,device,seed=seed)
        ev=M331.evaluate(th,y[tr:te],"skewed_t")
        preds.append(pd.DataFrame({"Date":pd.to_datetime(dates[tr:te]),"y_actual":y[tr:te],
            "crps":ev["crps_per_obs"],"p10":ev["p_minus_10"]}))
    full=pd.concat(preds,ignore_index=True)
    crps=float(full["crps"].mean())
    # COVID
    diffs=(full["Date"]-COVID).abs(); row=full.iloc[diffs.idxmin()]
    cov_p=float(row["p10"]); cov_pct=float((full["p10"]<=cov_p).mean()*100)
    return crps, cov_p, cov_pct, float(full["p10"].mean())

def main():
    cfg=yaml.safe_load(open(ROOT/"config"/"b1_macro_ext.yaml"))
    device=torch.device("cpu")
    df,lead_cols,old_cols=M333.load_with_leading(cfg)
    base=["log_ret","gkyz_252"]
    sets={"paper_only":base, "with_leading":base+lead_cols}
    res={k:{"crps":[],"covid_p10":[],"covid_pct":[],"mean_p10":[]} for k in sets}
    for seed in SEEDS:
        for name,feats in sets.items():
            c,cp,cpct,mp=one(cfg,df,feats,device,seed)
            res[name]["crps"].append(c); res[name]["covid_p10"].append(cp*100)
            res[name]["covid_pct"].append(cpct); res[name]["mean_p10"].append(mp*100)
            print(f"seed={seed} {name:14s} CRPS={c:.4f} COVID_P(-10%)={cp*100:.2f}% pct={cpct:.1f} mean_p10={mp*100:.2f}%")
    print("\n"+"="*80)
    print(f"{'set':14s} {'CRPS mean±sd':18s} {'COVID P(-10%)':16s} {'COVID pct':12s} {'mean P(-10%)':12s}")
    for name in sets:
        r=res[name]
        print(f"{name:14s} {np.mean(r['crps']):.4f}±{np.std(r['crps']):.4f}   "
              f"{np.mean(r['covid_p10']):.2f}±{np.std(r['covid_p10']):.2f}%   "
              f"{np.mean(r['covid_pct']):.1f}±{np.std(r['covid_pct']):.1f}   "
              f"{np.mean(r['mean_p10']):.2f}%")
    json.dump(res, open(ROOT/"03_models"/"b1_leading_macro"/"multiseed_h21.json","w"), indent=2)
    print("\nsaved multiseed_h21.json")

if __name__=="__main__":
    main()
