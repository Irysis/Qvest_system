
# dnn_rolling.py - RP_AUTO_COMBO_combo_1403_8125_2002_069 (Abe & Nakagawa 2020, Table 2 DNN5).
# Numerics, hyper-parameters and cache key are byte-identical to RP_AUTO_2002_06975 rev3 (audited edition);
# only cache_read walks extra read-only directories. Written by engine.R on every run; do not edit.
import os
os.environ.setdefault("OMP_NUM_THREADS", "1")
os.environ.setdefault("MKL_NUM_THREADS", "1")
import sys
import math
import time
import hashlib
import numpy as np
import pandas as pd
import pyarrow as pa
import pyarrow.parquet as pq
import torch
import torch.nn as nn
from concurrent.futures import ProcessPoolExecutor

CODE_VERSION = "RP_AUTO_2002_06975/dnn_rolling/rev3"   # part of every cache key; bump only if fit_predict numerics change
HIDDEN = [300, 300, 150, 150, 50]          # Table 2 DNN5 hidden layers
DROPOUT = [0.50, 0.50, 0.30, 0.30, 0.10]   # Table 2 DNN5 dropout rates
EPOCHS = 20                                # Table 2 DNN5 epochs
BATCH = 500                                # paper: mini-batch size 500
LR = 1e-3                                  # not stated -> TensorFlow Adam default
BN_EPS = 1e-3                              # not stated -> TensorFlow batch_normalization default
BN_MOMENTUM = 0.01                         # TensorFlow decay 0.99 == torch momentum 0.01
DEVICE = "cuda" if torch.cuda.is_available() else "cpu"
P = {}             # per-process panel arrays (filled by load_panel in every worker)
CACHE_DIR = None   # writable cache (this strategy directory)
RO_DIRS = []       # read-only sibling caches (never written)


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
    # same seed use, same init order, same cpu-generated batch order on any device
    torch.manual_seed(seed)
    gen = torch.Generator()
    gen.manual_seed(seed)
    model = DNN(X.shape[1]).to(DEVICE)
    opt = torch.optim.Adam(model.parameters(), lr=LR)
    lossf = nn.MSELoss()
    Xt = torch.from_numpy(X).to(DEVICE)
    yt = torch.from_numpy(y).to(DEVICE)
    n = Xt.shape[0]
    steps = 0
    skipped = 0
    last = float("nan")
    model.train()
    for _ in range(EPOCHS):
        perm = torch.randperm(n, generator=gen)      # cpu generator -> same batch order on any device
        for b in range(0, n, BATCH):
            idx = perm[b:b + BATCH]
            if idx.numel() < 2:            # batch norm needs at least 2 rows (declared)
                skipped += 1
                continue
            idx = idx.to(DEVICE)
            opt.zero_grad()
            loss = lossf(model(Xt[idx]), yt[idx])
            loss.backward()
            opt.step()
            steps += 1
            last = float(loss.item())
    model.eval()
    with torch.no_grad():
        pred = model(torch.from_numpy(Xp).to(DEVICE)).cpu().numpy()
    return pred, steps, skipped, last


def feature_names(schema_names):
    return [c for c in schema_names if c[0] == "x" and c[1:].isdigit()]


def load_panel(path, cache_dir, ro_dirs):
    global P, CACHE_DIR, RO_DIRS
    torch.set_num_threads(1)
    t = pq.read_table(path)
    feats = feature_names(t.column_names)
    X = np.empty((t.num_rows, len(feats)), dtype=np.float32)
    for j, c in enumerate(feats):
        X[:, j] = t.column(c).to_pandas().to_numpy(dtype=np.float64)
    y = t.column("y").to_pandas().to_numpy(dtype=np.float64).astype(np.float32)
    lab = t.column("lab_i").to_pandas().to_numpy(dtype=np.float64)
    lab = np.where(np.isnan(lab), -1.0, lab).astype(np.int32)
    di = t.column("di").to_pandas().to_numpy(dtype=np.int64).astype(np.int32)
    tk = t.column("Ticker").to_pandas().to_numpy().astype(str)
    P = dict(X=X, y=y, lab=lab, di=di, tk=tk, feats=feats)
    CACHE_DIR = cache_dir
    RO_DIRS = list(ro_dirs)


def select(task):
    k, pred_i, u_i, smin_i, smax_i, seed = task
    di = P["di"]
    y = P["y"]
    m_tr = (di >= smin_i) & (di <= smax_i) & (~np.isnan(y))
    m_pr = di == pred_i
    X = np.ascontiguousarray(P["X"][m_tr])
    yy = np.ascontiguousarray(y[m_tr])
    Xp = np.ascontiguousarray(P["X"][m_pr])
    tk = P["tk"][m_pr]
    lab = P["lab"][m_tr]
    n_days = int(np.unique(di[m_tr]).size) if X.shape[0] else 0
    max_lab = int(lab.max()) if X.shape[0] else -1
    return X, yy, Xp, tk, n_days, max_lab


def cache_key(task, X, y, Xp, tk):
    k, pred_i, u_i, smin_i, smax_i, seed = task
    h = hashlib.sha1()
    h.update(CODE_VERSION.encode("ascii"))
    spec = "|%d|%d|%d|%d|%d|%s|%s|%d|%d|%r|%r|%r|%s" % (pred_i, u_i, smin_i, smax_i, seed, HIDDEN, DROPOUT, EPOCHS, BATCH, LR, BN_EPS, BN_MOMENTUM, ",".join(P["feats"]))
    h.update(spec.encode("ascii"))
    h.update(X.tobytes())
    h.update(y.tobytes())
    h.update(Xp.tobytes())
    h.update("|".join(tk.tolist()).encode("utf-8"))
    return h.hexdigest()


def cache_read(key):
    # writable cache first, then the read-only sibling caches (same key = same inputs, same numerics)
    for d in [CACHE_DIR] + RO_DIRS:
        p = os.path.join(d, key + ".npz")
        if not os.path.exists(p):
            continue
        try:
            z = np.load(p, allow_pickle=False)
            return dict(score=z["score"].astype(np.float64), tk=z["tk"].astype(str), steps=int(z["steps"]),
                        skipped=int(z["skipped"]), last_loss=float(z["last_loss"]), secs=float(z["secs"]),
                        device=str(z["device"]), source=str(z["source"]), cache_dir=d)
        except Exception:
            continue
    return None


def cache_write(key, score, tk, steps, skipped, last_loss, secs, device, source):
    p = os.path.join(CACHE_DIR, key + ".npz")
    tmp = os.path.join(CACHE_DIR, "%s.%d.tmp.npz" % (key, os.getpid()))
    np.savez(tmp, score=np.asarray(score, dtype=np.float64), tk=np.asarray(tk, dtype=str),
             steps=np.int64(steps), skipped=np.int64(skipped), last_loss=np.float64(last_loss),
             secs=np.float64(secs), device=np.str_(device), source=np.str_(source))
    os.replace(tmp, p)


def run_task(task):
    k, pred_i, u_i, smin_i, smax_i, seed = task
    X, y, Xp, tk, n_days, max_lab = select(task)
    diag = dict(k=k, pred_i=pred_i, u_i=u_i, smin_i=smin_i, smax_i=smax_i,
                n_train=int(X.shape[0]), n_days=n_days, max_lab_i=max_lab, n_pred=int(Xp.shape[0]),
                steps=0, skipped=0, last_loss=float("nan"), secs=0.0, source="none", device=DEVICE)
    if X.shape[0] == 0 or Xp.shape[0] == 0:
        return k, None, diag
    if max_lab > u_i:
        raise RuntimeError("PIT: a training label is realized after the update day (max_lab_i %d > u_i %d)" % (max_lab, u_i))
    key = cache_key(task, X, y, Xp, tk)
    hit = cache_read(key)
    src = "cache"
    if hit is not None and (len(hit["score"]) != len(tk) or not np.array_equal(hit["tk"], tk)):
        hit = None
    if hit is not None and hit["cache_dir"] != CACHE_DIR:
        src = "cache_ro"
    if hit is None:
        t0 = time.time()
        pred, steps, skipped, last = fit_predict(X, y, Xp, seed)
        secs = time.time() - t0
        cache_write(key, pred, tk, steps, skipped, last, secs, DEVICE, "train")
        hit = dict(score=pred.astype(np.float64), steps=steps, skipped=skipped, last_loss=last, secs=secs, device=DEVICE)
        src = "train"
    out = pd.DataFrame({"pred_i": np.repeat(pred_i, len(tk)), "Ticker": tk, "Score": hit["score"]})
    diag.update(steps=hit["steps"], skipped=hit["skipped"], last_loss=hit["last_loss"], secs=hit["secs"],
                source=src, device=hit["device"])
    return k, out, diag


def synthetic_check(seed, m):
    # positive control: a known rank-target structure must be learned by the same fit_predict routine
    rng = np.random.default_rng(seed)
    n, npred = 20000, 5000
    X = rng.uniform(0.0, 1.0, size=(n, m)).astype(np.float32)
    w = rng.normal(size=m).astype(np.float32)
    f = X @ w + 0.5 * np.sin(6.0 * X[:, 0])
    y = (pd.Series(f).rank(method="average") / n).to_numpy(dtype=np.float32)
    Xp = rng.uniform(0.0, 1.0, size=(npred, m)).astype(np.float32)
    fp = Xp @ w + 0.5 * np.sin(6.0 * Xp[:, 0])
    pred, steps, skipped, last = fit_predict(X, y, Xp, seed)
    rho = float(pd.Series(pred).corr(pd.Series(fp), method="spearman"))
    return rho, steps


def count_npz(d):
    try:
        return len([f for f in os.listdir(d) if f.endswith(".npz") and ".tmp." not in f])
    except Exception:
        return 0


def main():
    rd = sys.argv[1]
    cd = sys.argv[2]
    cap = int(sys.argv[3]) if len(sys.argv) > 3 else 32
    ro = [d for d in sys.argv[4:] if os.path.isdir(d) and os.path.abspath(d) != os.path.abspath(cd)]
    os.makedirs(cd, exist_ok=True)
    panel_path = os.path.join(rd, "panel.parquet")
    sched_path = os.path.join(rd, "schedule.parquet")
    pred_path = os.path.join(rd, "pred.parquet")
    diag_path = os.path.join(rd, "diag.parquet")
    for p in (pred_path, diag_path):
        if os.path.exists(p):
            os.remove(p)
    sched = pq.read_table(sched_path).to_pandas()
    m = len(feature_names(pq.read_schema(panel_path).names))
    torch.set_num_threads(1)
    t0 = time.time()
    rho, steps = synthetic_check(int(sched["seed"].iloc[0]) + 7, m)
    print("[dnn] positive control (synthetic rank target, %d inputs): spearman %.3f after %d steps (%.0fs, device %s)" % (m, rho, steps, time.time() - t0, DEVICE), flush=True)
    if not rho > 0.8:
        print("[dnn] positive control FAILED - the training loop does not learn a known structure; aborting", flush=True)
        sys.exit(3)
    tasks = [tuple(int(v) for v in row) for row in sched[["k", "pred_i", "u_i", "smin_i", "smax_i", "seed"]].to_numpy()]
    # processing order rotated by a per-run offset: concurrent runs (lane re-spawn) start on different months and
    # meet through the shared cache instead of training the same months twice; every month's result is order-independent
    off = int(hashlib.sha1(os.path.basename(rd).encode("utf-8")).hexdigest(), 16) % len(tasks)
    tasks = tasks[off:] + tasks[:off]
    ncpu = os.cpu_count() or 2
    workers = max(1, min(cap, 8 if DEVICE == "cuda" else 32, ncpu - 1))
    n_cached = count_npz(cd)
    n_ro = sum(count_npz(d) for d in ro)
    print("[dnn] %d months | inputs %d | device %s | %d worker processes (1 torch thread each, %d logical cpus) | torch %s | cache entries %d (+%d in %d read-only sibling dirs) | start offset %d" % (
        len(tasks), m, DEVICE, workers, ncpu, torch.__version__, n_cached, n_ro, len(ro), off), flush=True)
    outs = []
    diags = []
    t1 = time.time()
    done = 0
    n_tr = 0
    n_ca = 0
    n_ro_hit = 0
    tr_secs = []
    with ProcessPoolExecutor(max_workers=workers, initializer=load_panel, initargs=(panel_path, cd, ro)) as ex:
        for k, out, diag in ex.map(run_task, tasks, chunksize=1):
            diags.append(diag)
            if out is not None:
                outs.append(out)
            done += 1
            if diag["source"] == "train":
                n_tr += 1
                tr_secs.append(diag["secs"])
            elif diag["source"] == "cache":
                n_ca += 1
            elif diag["source"] == "cache_ro":
                n_ro_hit += 1
            if done <= 3 or done % 12 == 0 or done == len(tasks):
                rem = len(tasks) - done
                eta = (rem * (sum(tr_secs) / len(tr_secs)) / workers / 60.0) if tr_secs else 0.0
                print("[dnn]   %d/%d months | trained %d cache %d sibling-cache %d | n_train %d | steps %d | loss %.4f | %.1f min elapsed | eta %.0f min if all remaining train" % (
                    done, len(tasks), n_tr, n_ca, n_ro_hit, diag["n_train"], diag["steps"], diag["last_loss"], (time.time() - t1) / 60.0, eta), flush=True)
    if not outs:
        print("[dnn] no predictions produced", flush=True)
        sys.exit(4)
    pred = pd.concat(outs, ignore_index=True)
    pq.write_table(pa.Table.from_pandas(pred, preserve_index=False), pred_path)
    dg = pd.DataFrame(diags)
    dg["synthetic_rho"] = rho
    dg["workers"] = workers
    dg["ncpu"] = ncpu
    dg["n_inputs"] = m
    pq.write_table(pa.Table.from_pandas(dg, preserve_index=False), diag_path)
    print("[dnn] done: %d prediction rows over %d months (trained %d, cache %d, sibling-cache %d) in %.1f min" % (
        len(pred), len(outs), n_tr, n_ca, n_ro_hit, (time.time() - t1) / 60.0), flush=True)


if __name__ == "__main__":
    main()

