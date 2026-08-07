#!/usr/bin/env python
"""ae_seed_sensitivity_probe.py — D3 게이트 AE fire 판정의 seed(draw) 민감도 실측 (2026-08-08).

왜: 전기간 재계산 논의에서 "seed 하나 바뀌면 2008+ fire 가 바뀔 수 있다"는 사실이 드러났다.
  그게 백필 방식과 무관하게 **AE 신호 자체의 draw 민감성**이다 — 문턱 근방 단일 draw 취약
  ([[project-threshold-single-draw-fragility-20260802]]) 과 같은 부류. production D3 게이트가
  이 신호로 실제 자본 노출(0.70/1.00)을 정하므로 측정 신뢰 축이다.

설계: 연도별 재학습을 서로 다른 seed K개로 반복 → 그 연도 결정월들의 fire_seq 판정 일치율.
  - 진단량 = 월별 flip 률(다수결 대비 소수 판정 비율) + tau 대비 score 마진.
  - ★결론은 "어느 seed 가 옳나"가 아니다 — 판정이 draw 에 안정인가만 잰다.
  - 연도 선택: fire 발생/근방 연도(2008 GFC · 2020 COVID · 2025 현국면) + 무발화 대조(2015).
    전 연도 × 다수 seed 는 CPU 과대 — 판별에 필요한 최소 집합.
  - production 파일은 읽기만. 산출은 관측 전용 JSON.

출력: qepm/observability/ae_seed_sensitivity_20260808.json + stdout 표.
"""
from __future__ import annotations

import json
import os
import sys

import numpy as np
import pandas as pd
import pyarrow.parquet as pq
import torch
import torch.nn as nn

ROOT = os.environ.get("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot").replace("\\", "/")
os.chdir(ROOT)
torch.set_num_threads(1)

# 동결 원본 상수 verbatim (stage_artifacts/WT_D20260718_007/ae_regime_extend.py)
PIN = ".cache/pins/WT-D20260718_007_r1"
FRED = os.path.join(PIN, "fred_macro_wide.parquet")
BENCH = os.path.join(PIN, "benchmark.parquet")
SIGNAL = "stage_artifacts/WT_D20260718_007/ae_regime_signal_ext.parquet"
L = 60; FWD = 21; SMOOTH = 21; STRIDE = 3
D_HID = 16; D_LAT = 8; DROPOUT = 0.1
EPOCHS = 25; LR = 1e-3; WD = 1e-4; PATIENCE = 4; BATCH = 256
M4_FIRE_RATE = 0.12
FRED_FEATS = ["VIX", "Term_Spread", "KRW_USD", "US_10Y_Yield", "US_2Y_Yield",
              "StL_Fin_Stress", "Chi_Fin_Cond"]

PROBE_YEARS = [2008, 2015, 2020, 2025]     # fire 다발 2 + 무발화 대조 1 + 현국면 1
SEEDS = [11, 22, 33, 44, 55]               # 원본 SEED(20260718)와 독립 — "다른 draw" 5개


def build_panel():
    fr = pq.read_table(FRED).to_pandas(); fr["Date"] = pd.to_datetime(fr["Date"]); fr = fr.sort_values("Date")
    bm = pq.read_table(BENCH).to_pandas(); bm["Date"] = pd.to_datetime(bm["Date"]); bm = bm.sort_values("Date").reset_index(drop=True)
    c = bm["BM_Close"].astype(float).values
    bm["kret"] = bm["BM_Ret"].astype(float)
    bm["klog"] = np.log(c / np.roll(c, 1)); bm.loc[0, "klog"] = np.nan
    bm["kvol20"] = bm["kret"].rolling(20, min_periods=10).std()
    bm["kcum20"] = c / np.concatenate([np.full(20, np.nan), c[:-20]]) - 1.0
    bm["kcum60"] = c / np.concatenate([np.full(60, np.nan), c[:-60]]) - 1.0
    spine = bm[["Date", "kret", "klog", "kvol20", "kcum20", "kcum60"]].copy()
    m = pd.merge_asof(spine, fr[["Date"] + FRED_FEATS], on="Date", direction="backward")
    feat_cols = ["klog", "kvol20", "kcum20", "kcum60"] + FRED_FEATS
    m[feat_cols] = m[feat_cols].ffill()
    return m.dropna(subset=feat_cols).reset_index(drop=True), feat_cols


class SeqAE(nn.Module):
    def __init__(self, nfeat):
        super().__init__()
        self.enc = nn.GRU(nfeat, D_HID, batch_first=True)
        self.lat = nn.Linear(D_HID, D_LAT)
        self.dec_in = nn.Linear(D_LAT, D_HID)
        self.dec = nn.GRU(D_HID, D_HID, batch_first=True)
        self.out = nn.Linear(D_HID, nfeat)
        self.drop = nn.Dropout(DROPOUT)

    def forward(self, x):
        _, h = self.enc(x)
        z = self.lat(self.drop(h[-1]))
        d = self.dec_in(z).unsqueeze(1).repeat(1, x.size(1), 1)
        y, _ = self.dec(d)
        return self.out(y)


def make_seq_windows(end_idx_list, X):
    ws = [X[i - L + 1:i + 1] for i in end_idx_list if i - L + 1 >= 0]
    return (np.stack(ws).astype(np.float32), end_idx_list) if ws else (None, None)


def train_ae(model, Xtr, Xva):
    lossf = nn.MSELoss()
    opt = torch.optim.Adam(model.parameters(), lr=LR, weight_decay=WD)
    Xtr_t = torch.tensor(Xtr); Xva_t = torch.tensor(Xva)
    n = len(Xtr_t); best = np.inf; bad = 0; best_state = None
    for _ in range(EPOCHS):
        model.train(); perm = torch.randperm(n)
        for b in range(0, n, BATCH):
            idx = perm[b:b + BATCH]
            opt.zero_grad(); loss = lossf(model(Xtr_t[idx]), Xtr_t[idx]); loss.backward(); opt.step()
        model.eval()
        with torch.no_grad(): vl = lossf(model(Xva_t), Xva_t).item()
        if vl < best - 1e-6: best = vl; bad = 0; best_state = {k: v.clone() for k, v in model.state_dict().items()}
        else:
            bad += 1
            if bad >= PATIENCE: break
    if best_state: model.load_state_dict(best_state)
    model.eval(); return model


def recon_err_seq(model, W):
    with torch.no_grad():
        t = torch.tensor(W.astype(np.float32)); r = model(t)
        return ((r - t) ** 2).mean(dim=(1, 2)).numpy()


def main():
    panel, feat_cols = build_panel()
    nfeat = len(feat_cols)
    Xraw = panel[feat_cols].values.astype(np.float64)
    panel_dates = pd.to_datetime(panel["Date"]).values

    sig = pq.read_table(SIGNAL).to_pandas()
    sig["decision_date"] = pd.to_datetime(sig["decision_date"])
    prod = sig.set_index("decision_date")["fire_seq"].to_dict()

    results = []
    for year in PROBE_YEARS:
        boundary = np.datetime64(f"{year}-01-01")
        tr_idx = np.where(panel_dates < boundary)[0]
        if len(tr_idx) < 500:
            print(f"[{year}] 학습일 부족 — skip"); continue
        mu = Xraw[tr_idx].mean(0); sd = Xraw[tr_idx].std(0); sd[sd < 1e-8] = 1.0
        Xz = ((Xraw - mu) / sd).astype(np.float32)
        seq_end_tr = [i for i in tr_idx if i - L + 1 >= 0][::STRIDE]
        Wtr, _ = make_seq_windows(seq_end_tr, Xz)
        cut = np.datetime64(f"{year - 1}-01-01")
        fit_end = [i for i in seq_end_tr if panel_dates[i] < cut]
        val_end = [i for i in seq_end_tr if panel_dates[i] >= cut]
        if len(val_end) < 30 or len(fit_end) < 200:
            k = int(len(seq_end_tr) * 0.85); fit_end = seq_end_tr[:k]; val_end = seq_end_tr[k:]
        Wfit, _ = make_seq_windows(fit_end, Xz); Wval, _ = make_seq_windows(val_end, Xz)

        decs = sorted([d for d in prod if pd.Timestamp(d).year == year])
        per_seed = {}
        for sd_ in SEEDS:
            torch.manual_seed(sd_); np.random.seed(sd_)
            m = train_ae(SeqAE(nfeat), Wfit, Wval)
            e_is = recon_err_seq(m, Wtr)
            tau = float(np.quantile(e_is, 1.0 - M4_FIRE_RATE))
            fires = {}
            for d in decs:
                dd = np.datetime64(pd.Timestamp(d)); valid = np.where(panel_dates < dd)[0]
                if len(valid) < L: continue
                end = valid[-1]
                s = float(recon_err_seq(m, Xz[end - L + 1:end + 1][None, :, :])[0])
                fires[d] = dict(fire=int(s > tau), margin=(s - tau) / tau)
            per_seed[sd_] = dict(tau=tau, fires=fires)
            print(f"[{year} seed={sd_}] tau={tau:.4f} fires={sum(v['fire'] for v in fires.values())}/{len(fires)}")

        for d in decs:
            votes = [per_seed[s]["fires"][d]["fire"] for s in SEEDS if d in per_seed[s]["fires"]]
            margins = [per_seed[s]["fires"][d]["margin"] for s in SEEDS if d in per_seed[s]["fires"]]
            if not votes: continue
            agree = max(votes.count(0), votes.count(1)) / len(votes)
            results.append(dict(month=str(pd.Timestamp(d).date())[:7], year=year,
                                prod_fire=int(prod[d]), seed_votes_fire=sum(votes), n_seeds=len(votes),
                                agreement=round(agree, 2), unstable=agree < 1.0,
                                prod_matches_majority=int(prod[d]) == int(sum(votes) > len(votes) / 2),
                                margin_median=round(float(np.median(margins)), 3)))

    df = pd.DataFrame(results)
    n_unstable = int(df["unstable"].sum())
    n_prod_minority = int((~df["prod_matches_majority"]).sum())
    print(f"\n[요약] 검사 {len(df)}개월 · seed 간 불일치 월 {n_unstable} · production 판정이 seed 다수결과 다른 월 {n_prod_minority}")
    print(df.to_string(index=False))
    out = dict(date="2026-08-08", probe_years=PROBE_YEARS, seeds=SEEDS,
               n_months=len(df), n_unstable=n_unstable, n_prod_minority=n_prod_minority,
               note="관측 전용 — production 신호 파일 무변경. unstable = 5-seed 판정 불일치 존재",
               rows=results)
    os.makedirs("qepm/observability", exist_ok=True)
    with open("qepm/observability/ae_seed_sensitivity_20260808.json", "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=2)
    print("\n저장: qepm/observability/ae_seed_sensitivity_20260808.json")


if __name__ == "__main__":
    main()
