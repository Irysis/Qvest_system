"""aif_nn.py — 단계 3 생성기 ④-2: 예측 모형 결합 2판 · 신경망 팔 + 두 팔의 평균.

구조와 학습 방법은 Gu, Kelly & Xiu (2020, RFS 33(5) https://doi.org/10.1093/rfs/hhaa009 · 본문 2.7절과 온라인 부록 표 A.5)의 NN3 를 따른다:
  은닉 32 · 16 · 8(ReLU) · 층마다 배치 정규화 · 가중치 L1 벌점 · Adam · 조기 종료(인내 5) · 씨앗 10개의 예측 평균 ·
  배치 10,000 · 최대 100에폭 · 격자 = 학습률 {0.001, 0.01} × L1 {1e-5, 1e-4, 1e-3}(검증 구간의 월별 순위 IC 로 고른다).
입력 · 표적 · 재학습 일정 · 학습/검증 나누기는 트리 팔(aif_tree.py)과 같다. 손실 = 순위 표적에 대한 제곱 오차.
산출: factors/NN_1M.parquet · NN_12M.parquet + 두 팔의 평균 ENS_1M.parquet · ENS_12M.parquet(트리 팔 예측이 있을 때 · 달마다 멤버 안 순위의 평균).
실행: python py/aif_nn.py [--target 1m|12m|both] [--force]   ((표적, 해) 하나 = 체크포인트 하나)
"""
import argparse
import os
import sys
import time

import numpy as np

import aif_common as ac
from aif_enumerate import Compact
from aif_features import FeatureStore
from aif_tree import BURN_YEARS, EMBARGO_M, VAL_FRAC, _nlff_automl, design, macro_z, target_rank

VERSION = 1
HIDDEN, N_SEEDS, BATCH, MAX_EPOCH, PATIENCE = (32, 16, 8), 10, 10000, 100, 5
GRID_LR, GRID_L1 = (0.001, 0.01), (1e-5, 1e-4, 1e-3)
SEED0 = 20261123
TARGETS = {"1m": {"h": 1, "name": "NN_1M", "tree": "TREE_1M", "ens": "ENS_1M", "quarter_only": False, "desc": "다음 1개월 수익 순위 예측(3층 신경망 · 씨앗 10개 평균)"},
           "12m": {"h": 12, "name": "NN_12M", "tree": "TREE_12M", "ens": "ENS_12M", "quarter_only": True, "desc": "향후 12개월 수익 순위 예측(3층 신경망 · 씨앗 10개 평균)"}}


def month_ic(p, y, m):
    """월별 순위 IC 평균(검증용). p · y · m = 1차원(예측 · 표적 · 달 번호)."""
    from scipy.stats import rankdata
    out = []
    for u in np.unique(m):
        k = m == u
        if k.sum() >= 30:
            a, b = rankdata(p[k]), rankdata(y[k])
            if a.std() > 0 and b.std() > 0:
                out.append(np.corrcoef(a, b)[0, 1])
    return float(np.mean(out)) if out else float("nan")


def train_one(Xtr, ytr, Xva, yva, mva, lr, l1, seed, dev):
    """한 씨앗 학습 — 검증 손실이 PATIENCE 에폭 동안 나아지지 않으면 멈추고 가장 좋았던 가중치를 돌려준다."""
    import torch
    import torch.nn as nn
    torch.manual_seed(seed)
    layers, d = [], Xtr.shape[1]
    for h in HIDDEN:
        layers += [nn.Linear(d, h), nn.BatchNorm1d(h), nn.ReLU()]
        d = h
    net = nn.Sequential(*layers, nn.Linear(d, 1)).to(dev)
    opt = torch.optim.Adam(net.parameters(), lr=lr)
    g = torch.Generator(device="cpu").manual_seed(seed)
    n = Xtr.shape[0]
    best, best_state, bad = float("inf"), None, 0
    for ep in range(MAX_EPOCH):
        net.train()
        perm = torch.randperm(n, generator=g).to(dev)
        for i in range(0, n, BATCH):
            idx = perm[i:i + BATCH]
            if idx.numel() < 2:
                continue
            opt.zero_grad(set_to_none=True)
            loss = torch.mean((net(Xtr[idx]).squeeze(1) - ytr[idx]) ** 2)
            loss = loss + l1 * sum(p.abs().sum() for nm, p in net.named_parameters() if nm.endswith("weight") and p.dim() == 2)
            loss.backward()
            opt.step()
        net.eval()
        with torch.no_grad():
            vl = float(torch.mean((net(Xva).squeeze(1) - yva) ** 2))
        if vl < best - 1e-7:
            best, bad = vl, 0
            best_state = {k: v.detach().clone() for k, v in net.state_dict().items()}
        else:
            bad += 1
            if bad >= PATIENCE:
                break
    net.load_state_dict(best_state)
    net.eval()
    return net, ep + 1


def predict(net, X, chunk=200000):
    import torch
    out = []
    with torch.no_grad():
        for i in range(0, X.shape[0], chunk):
            out.append(net(X[i:i + chunk]).squeeze(1).float().cpu().numpy())
    return np.concatenate(out) if out else np.zeros(0, dtype=np.float32)


def perm_importance(nets, Xva, yva, mva, names, top=30):
    """순열 중요도 — 검증 구간에서 특성 하나를 섞었을 때 월별 순위 IC 가 얼마나 떨어지는가(씨앗 평균 예측 기준)."""
    import torch
    base = month_ic(np.mean([predict(nt, Xva) for nt in nets], axis=0), yva, mva)
    g = torch.Generator(device="cpu").manual_seed(SEED0)
    perm = torch.randperm(Xva.shape[0], generator=g).to(Xva.device)
    drop = np.zeros(len(names))
    for j in range(len(names)):
        keep = Xva[:, j].clone()
        Xva[:, j] = keep[perm]
        drop[j] = base - month_ic(np.mean([predict(nt, Xva) for nt in nets], axis=0), yva, mva)
        Xva[:, j] = keep
    o = np.argsort(-drop)[:top]
    return base, [(names[i], round(float(drop[i]), 5)) for i in o]


def run_target(tk, cfg, X, xnames, Z, znames, cp, out_dir, fp, force, unit0, dev):
    import torch
    na, _ = _nlff_automl()
    f = cp.f
    h = cfg["h"]
    y = target_rank(cp, h)
    dates = f.sig_dates[cp.S]
    avail = f.sig_dates[np.minimum(cp.S + h, f.ns - 1)]
    usable = np.isfinite(y) & (cp.S + h <= f.ns - 1)
    if cfg["quarter_only"]:
        qm = np.isin(np.array([int(str(d)[5:7]) for d in f.sig_dates]), [3, 6, 9, 12])
        usable &= qm[cp.S]
    sel_years, dec = ac.december_signals(f, BURN_YEARS)
    pred = np.full(cp.n, np.nan, dtype=np.float32)
    logs, names = [], xnames + znames
    for n, yy in enumerate(sel_years):
        sY = dec[yy]
        nxt = list(range(sY, min(sY + 12, f.ns)))
        a1, b1 = cp.seg[nxt[0]], cp.seg[nxt[-1] + 1]
        ck = "%s/%s_%d.npz" % (out_dir, tk, yy)
        if os.path.exists(ck) and not force:
            z = np.load(ck, allow_pickle=True)
            if str(z["fp"]) == fp:
                pred[a1:b1] = z["pred"]
                logs.append(z["log"].item())
                ac.stage_unit(unit0 + n + 1, "%s %d년 재학습 — 저장분 사용" % (tk, yy))
                continue
        t0 = time.time()
        refit_cut = f.sig_dates[sY - EMBARGO_M]
        w = np.nonzero(usable & (avail <= refit_cut))[0]
        tr, va = na.time_split(dates[w], avail[w], VAL_FRAC, refit_cut)
        if tr is None or tr.sum() < 5000 or va.sum() < 1000:
            ac.log("%s %d — 표본이 모자라 건너뜀", tk, yy)
            continue
        zs = macro_z(Z, sY)
        T = lambda rows: torch.from_numpy(np.concatenate([X[rows], zs[cp.S[rows]]], axis=1)).to(dev)    # noqa: E731
        Xtr, Xva = T(w[tr]), T(w[va])
        ytr, yva_t = torch.from_numpy(y[w][tr]).to(dev), torch.from_numpy(y[w][va]).to(dev)
        yva, mva = y[w][va], cp.S[w][va]
        grid = []
        for lr in GRID_LR:
            for l1 in GRID_L1:
                net, ep = train_one(Xtr, ytr, Xva, yva_t, mva, lr, l1, SEED0, dev)
                grid.append({"lr": lr, "l1": l1, "val_ic": month_ic(predict(net, Xva), yva, mva), "epochs": ep})
                del net
        bestg = max(grid, key=lambda r: (r["val_ic"] if np.isfinite(r["val_ic"]) else -9))
        nets, eps = [], []
        for k in range(N_SEEDS):
            net, ep = train_one(Xtr, ytr, Xva, yva_t, mva, bestg["lr"], bestg["l1"], SEED0 + 1 + k, dev)
            nets.append(net)
            eps.append(ep)
        val_ic, imp = perm_importance(nets, Xva, yva, mva, names)
        del Xtr, Xva, ytr, yva_t
        Xp = T(np.arange(a1, b1))
        p = np.mean([predict(nt, Xp) for nt in nets], axis=0).astype(np.float32)
        del Xp, nets
        torch.cuda.empty_cache()
        pred[a1:b1] = p
        log = {"target": tk, "year": yy, "n_train": int(tr.sum()), "n_val": int(va.sum()), "grid": grid, "chosen": {"lr": bestg["lr"], "l1": bestg["l1"]},
               "val_ic_ensemble": round(val_ic, 5), "epochs": eps, "importance_top": imp, "seconds": round(time.time() - t0, 1),
               "vram_peak_gb": round(torch.cuda.max_memory_allocated() / 2 ** 30, 2) if dev == "cuda" else 0.0}

        def _save(path, p=p, log=log):
            with open(path, "wb") as fh:
                np.savez(fh, fp=fp, pred=p, log=np.array(log, dtype=object))
        ac.write_atomic(ck, _save)
        logs.append(log)
        ac.log("%s %d년 재학습 — 학습 %d · 검증 %d · 고른 학습률 %g · L1 %g · 검증 IC %.4f · %.0f초", tk, yy, log["n_train"], log["n_val"], bestg["lr"], bestg["l1"], val_ic, time.time() - t0)
        ac.stage_unit(unit0 + n + 1, "%s %d년 재학습 끝" % (tk, yy))
    S = np.full((f.ns, f.nt), np.nan, dtype=np.float32)
    S[cp.S, cp.J] = pred
    path = ac.out("factors") + "/%s.parquet" % cfg["name"]
    ac.save_factor_panel(path, cfg["name"], S, f)
    ac.write_json({"target": tk, "retrains": logs}, ac.results("stage3_nn", "retrain_log_%s.json" % tk))
    out = [{"id": cfg["name"], "path": path, "direction": 1, "method": "예측 모형 2판 · 신경망", "desc": cfg["desc"]}]
    tp = ac.out("factors") + "/%s.parquet" % cfg["tree"]
    if os.path.exists(tp):                                           # 두 팔의 평균 = 달마다 멤버 안 순위의 평균(둘 다 값이 있는 칸만)
        import pyarrow.parquet as pq
        t = pq.read_table(tp, columns=["Date", "Ticker", "Raw_Value"]).to_pandas()
        Tm = np.full((f.ns, f.nt), np.nan, dtype=np.float32)
        si = np.searchsorted(f.sig_dates, t["Date"].to_numpy().astype("datetime64[D]"))
        ti = f.ticker_index(t["Ticker"].to_list())
        Tm[si, ti] = t["Raw_Value"].to_numpy(dtype=np.float32)
        E = (ac.rank_pm1(S, f.mem) + ac.rank_pm1(Tm, f.mem)) / 2.0
        pe = ac.out("factors") + "/%s.parquet" % cfg["ens"]
        ac.save_factor_panel(pe, cfg["ens"], E, f)
        out.append({"id": cfg["ens"], "path": pe, "direction": 1, "method": "예측 모형 2판 · 두 팔 평균", "desc": "트리 AutoML 과 신경망 예측의 순위 평균"})
    return out, len(sel_years)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--target", default="both")
    ap.add_argument("--force", action="store_true")
    a = ap.parse_args()
    import torch
    ac.low_priority()
    dev = "cuda" if torch.cuda.is_available() else "cpu"
    torch.set_num_threads(ac.threads())
    f = ac.Frame()
    store = FeatureStore(f)
    cp = Compact(f)
    out_dir = ac.out("nn")
    for d in (out_dir, ac.results("stage3_nn"), ac.out("factors")):
        os.makedirs(d, exist_ok=True)
    ac.stage_begin("neural_net", 1, "준비", 0.0, 0.02)
    X, xnames = design(store, cp)
    Z = np.load(store.dir + "/macro_state.npy")
    znames = ac.read_json(store.dir + "/macro_state_meta.json")["names"]
    fp = "%s|v%d|%d|%d" % (f.meta.get("rawdata_tag"), VERSION, X.shape[1], Z.shape[1])
    tks = ["1m", "12m"] if a.target == "both" else [a.target]
    n_years = len({int(str(d)[:4]) for d in f.sig_dates}) - BURN_YEARS + 1
    ac.stage_begin("neural_net", n_years * len(tks), "재학습", 0.02, 0.9)
    ac.log("장치 %s · 입력 %d열 · 표본 %d칸", dev, X.shape[1] + Z.shape[1], cp.n)
    manifest, u0 = [], 0
    for tk in tks:
        m, k = run_target(tk, TARGETS[tk], X, xnames, Z, znames, cp, out_dir, fp, a.force, u0, dev)
        manifest += m
        u0 += k
    ac.write_json({"at": ac._now(), "stage": "neural_net", "factors": manifest,
                   "params": {"hidden": HIDDEN, "seeds": N_SEEDS, "batch": BATCH, "max_epoch": MAX_EPOCH, "patience": PATIENCE, "grid_lr": GRID_LR, "grid_l1": GRID_L1,
                              "_source": "Gu, Kelly & Xiu 2020 RFS 의 NN3(은닉 32-16-8 · 배치 정규화 · L1 · 조기 종료 · 씨앗 10개 · 배치 10,000 · 100에폭 · 학습률과 L1 격자) https://doi.org/10.1093/rfs/hhaa009"}},
                  ac.out("manifest_nn.json"))
    ac.stage_end(done=False)
    return 0


if __name__ == "__main__":
    sys.exit(main())
