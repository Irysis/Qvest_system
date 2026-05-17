"""Export DPL test_weights.pkl → test_weights_long.csv for R Forge artifacts builder."""
import pickle, pandas as pd
from pathlib import Path
STAGE = Path("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot/stage_artifacts/WT_D20260517_001")
with open(STAGE / "test_weights.pkl", "rb") as f:
    blob = pickle.load(f)
rows = []
for sd, dat in blob["all_test_weights"].items():
    for tk, w, sc in zip(dat["tickers"], dat["w"], dat["scores"]):
        if w > 1e-10 or abs(sc) > 1e-10:
            rows.append({"sig_date": sd, "Ticker": tk, "w_dpl": float(w),
                         "score_raw": float(sc)})
df = pd.DataFrame(rows)
df.to_csv(STAGE / "test_weights_long.csv", index=False)
print(f"saved: {STAGE/'test_weights_long.csv'} rows={len(df)}")
print(f"sig_dates={df['sig_date'].nunique()} tickers={df['Ticker'].nunique()}")
print(df.head(10).to_string())
