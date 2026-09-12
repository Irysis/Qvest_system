
# dnn_rolling.py — RP_AUTO_2002_06975 (Abe & Nakagawa 2020, Table 2 DNN5). Written by engine.R on every run; do not edit.
import os
import sys
import math
import time
import numpy as np
import pandas as pd
import pyarrow as pa
import pyarrow.parquet as pq
import torch
import torch.nn as nn
from concurrent.futures import ProcessPoolExecutor

HIDDEN = [300, 300, 150, 150, 50]          # Table 2 DNN5 hidden layers
DROPOUT = [0.50, 0.50, 0.30, 0.30, 0.10]   # Table 2 DNN5 dropout rates
EPOCHS = 20                                # Table 2 DNN5 epochs
BATCH = 500                                # paper: mini-batch size 500
LR = 1e-3                                  # not stated -> TensorFlow Adam default
BN_EPS = 1e-3                              # not stated -> TensorFlow batch_normalization default
BN_MOMENTUM = 0.01                         # TensorFlow decay 0.99 == torch momentum 0.01
PANEL = None
FEATS = None


class DNN(nn.Module):
    def __init__(self, m):
        super().__init__()
        layers = []
        prev = m
        for h, p in zip(HIDDEN, DROPOUT):
            layers.append(self.linear(prev, h))
            layers.append(nn.BatchNorm1d(h, eps=BN_EPS, momentum=BN_MOMENTUM))
            layers.append(nn.ReLU())
            layers.append(nn.Dropout(p))
            prev = h
        layers.append(self.linear(prev, 1))
        self.net = nn.Sequential(*layers)

    @staticmethod
    def linear(fan_in, fan_out):
        lin = nn.Linear(fan_in, fan_out)
        sd = math.sqrt(2.0 / fan_in)       # paper: tf.truncated_normal, mean 0, std sqrt(2/M), M = fan-in
        nn.init.trunc_normal_(lin.weight, mean=0.0, std=sd, a=-2.0 * sd, b=2.0 * sd)
        nn.init.zeros_(lin.bias)
        return lin

    def forward(self, x):
        return self.net(x).squeeze(1)


def fit_predict(X, y, Xp, seed):
    torch.manual_seed(seed)
    gen = torch.Generator()
    gen.manual_seed(seed)
    model = DNN(X.shape[1])
    opt = torch.optim.Adam(model.parameters(), lr=LR)
    lossf = nn.MSELoss()
    Xt = torch.from_numpy(X)
    yt = torch.from_numpy(y)
    n = Xt.shape[0]
    steps = 0
    skipped = 0
    last = float("nan")
    model.train()
    for _ in range(EPOCHS):
        perm = torch.randperm(n, generator=gen)
        for b in range(0, n, BATCH):
            idx = perm[b:b + BATCH]
            if idx.numel() < 2:            # batch norm needs at least 2 rows (declared)
                skipped += 1
                continue
            opt.zero_grad()
            loss = lossf(model(Xt[idx]), yt[idx])
            loss.backward()
            opt.step()
            steps += 1
            last = float(loss.item())
    model.eval()
    with torch.no_grad():
        pred = model(torch.from_numpy(Xp)).numpy()
    return pred, steps, skipped, last


def load_panel(path):
    global PANEL, FEATS
    torch.set_num_threads(1)
    t = pq.read_table(path).to_pandas()
    FEATS = [c for c in t.columns if c[0] == "x" and c[1:].isdigit()]
    for c in FEATS:
        t[c] = t[c].astype(np.float32)
    PANEL = t


def run_task(task):
    k, pred_i, u_i, smin_i, smax_i, seed = task
    P = PANEL
    tr = P[(P["di"] >= smin_i) & (P["di"] <= smax_i) & P["y"].notna()]
    pr = P[P["di"] == pred_i]
    diag = dict(k=k, pred_i=pred_i, u_i=u_i, smin_i=smin_i, smax_i=smax_i,
                n_train=int(len(tr)), n_days=int(tr["di"].nunique()) if len(tr) else 0,
                max_lab_i=int(tr["lab_i"].max()) if len(tr) else -1,
                n_pred=int(len(pr)), steps=0, skipped=0, last_loss=float("nan"), secs=0.0)
    if len(tr) == 0 or len(pr) == 0:
        return k, None, diag
    if diag["max_lab_i"] > u_i:
        raise RuntimeError("PIT: a training label is realized after the update day (max_lab_i %d > u_i %d)" % (diag["max_lab_i"], u_i))
    X = tr[FEATS].to_numpy(dtype=np.float32)
    y = tr["y"].to_numpy(dtype=np.float32)
    Xp = pr[FEATS].to_numpy(dtype=np.float32)
    t0 = time.time()
    pred, steps, skipped, last = fit_predict(X, y, Xp, seed)
    out = pd.DataFrame({"pred_i": np.repeat(pred_i, len(pr)), "Ticker": pr["Ticker"].to_numpy(),
                        "Score": pred.astype(np.float64)})
    diag.update(steps=steps, skipped=skipped, last_loss=last, secs=time.time() - t0)
    return k, out, diag


def synthetic_check(seed):
    # positive control: a known rank-target structure must be learned by the same fit_predict routine
    rng = np.random.default_rng(seed)
    n, m, npred = 20000, 32, 5000
    X = rng.uniform(0.0, 1.0, size=(n, m)).astype(np.float32)
    w = rng.normal(size=m).astype(np.float32)
    f = X @ w + 0.5 * np.sin(6.0 * X[:, 0])
    y = (pd.Series(f).rank(method="average") / n).to_numpy(dtype=np.float32)
    Xp = rng.uniform(0.0, 1.0, size=(npred, m)).astype(np.float32)
    fp = Xp @ w + 0.5 * np.sin(6.0 * Xp[:, 0])
    pred, steps, skipped, last = fit_predict(X, y, Xp, seed)
    rho = float(pd.Series(pred).corr(pd.Series(fp), method="spearman"))
    return rho, steps


def main():
    wd = sys.argv[1]
    panel_path = os.path.join(wd, "panel.parquet")
    sched_path = os.path.join(wd, "schedule.parquet")
    pred_path = os.path.join(wd, "pred.parquet")
    diag_path = os.path.join(wd, "diag.parquet")
    for p in (pred_path, diag_path):
        if os.path.exists(p):
            os.remove(p)
    sched = pq.read_table(sched_path).to_pandas()
    torch.set_num_threads(1)
    t0 = time.time()
    rho, steps = synthetic_check(int(sched["seed"].iloc[0]) + 7)
    print("[dnn] positive control (synthetic rank target): spearman %.3f after %d steps (%.0fs)" % (rho, steps, time.time() - t0), flush=True)
    if not rho > 0.8:
        print("[dnn] positive control FAILED - the training loop does not learn a known structure; aborting", flush=True)
        sys.exit(3)
    tasks = [tuple(int(v) for v in row) for row in sched[["k", "pred_i", "u_i", "smin_i", "smax_i", "seed"]].to_numpy()]
    ncpu = os.cpu_count() or 2
    cap = int(sys.argv[2]) if len(sys.argv) > 2 else 4
    workers = max(1, min(cap, ncpu - 1))
    print("[dnn] %d months to fit, %d worker processes (1 torch thread each), torch %s" % (len(tasks), workers, torch.__version__), flush=True)
    outs = []
    diags = []
    t1 = time.time()
    done = 0
    with ProcessPoolExecutor(max_workers=workers, initializer=load_panel, initargs=(panel_path,)) as ex:
        for k, out, diag in ex.map(run_task, tasks, chunksize=1):
            diags.append(diag)
            if out is not None:
                outs.append(out)
            done += 1
            if done % 12 == 0 or done == len(tasks):
                print("[dnn]   %d/%d months | n_train %d | steps %d | loss %.4f | %.1f min elapsed" % (done, len(tasks), diag["n_train"], diag["steps"], diag["last_loss"], (time.time() - t1) / 60.0), flush=True)
    if not outs:
        print("[dnn] no predictions produced", flush=True)
        sys.exit(4)
    pred = pd.concat(outs, ignore_index=True)
    pq.write_table(pa.Table.from_pandas(pred, preserve_index=False), pred_path)
    dg = pd.DataFrame(diags)
    dg["synthetic_rho"] = rho
    pq.write_table(pa.Table.from_pandas(dg, preserve_index=False), diag_path)
    print("[dnn] done: %d prediction rows over %d months in %.1f min" % (len(pred), len(outs), (time.time() - t1) / 60.0), flush=True)


if __name__ == "__main__":
    main()

