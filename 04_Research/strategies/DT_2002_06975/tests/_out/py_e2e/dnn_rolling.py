
## >>> DT_ZONE py_ident orig=430-430
# dnn_rolling.py - DT_2002_06975 dnn_quantile rev1 (3 quantile heads on Abe & Nakagawa 2020 Table 2 DNN5). Written by engine_<rule>.R on every run; do not edit.
## <<< DT_ZONE py_ident
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

## >>> DT_ZONE py_const orig=446-446
CODE_VERSION = "DT_2002_06975/dnn_quantile/rev1"   # part of every cache key; rule-independent (all 7 rule engines share one trained prediction per month)
TAUS = [0.1, 0.5, 0.9]                     # quantile heads P10/P50/P90 on one shared body (design 3.3)
N_OUT = len(TAUS)                          # output units = heads
LOSS_NAME = "pinball_mean"                 # (1/3) sum_tau mean rho_tau(y - q_tau), rho_tau(u) = u (tau - 1{u<0})
# positive control (heteroscedastic synthetic, design 3.3) - sample sizes and the centre/width ratio are fixed by the
# registration rehearsal (tests/pc_mutation_test.py, CPU, 2026-10-18; thresholds = design 3.3):
#   PC_N 20000 (rev3 size) under-trains the 0.9 head with this routine (3/3 seeds fail: spearman q90 0.49-0.67) -> 100000:
#   correct code 9/9 seeds pass (spearman >= 0.975, hit q10 0.092-0.120, q90 0.889-0.909); the width-not-learned mutant
#   stays at spearman q10 <= 0.634 / q90 <= 0.541 (population spearman(m, l) ~ 0.56 at PC_F_SD 0.5) -> fails on every seed.
PC_N = 100000                              # training rows (20 epochs x 200 mini-batches = 4000 steps, same fit_predict)
PC_NPRED = 5000                            # holdout rows (rev3 size)
PC_F_SD = 0.5                              # sd of the centre f (width g = 0.25 + 2 X2 has sd(g z_0.1) = 0.740)
PC_RHO_MIN = 0.8                           # spearman threshold (rev3 positive-control threshold, inherited)
PC_COV10 = (0.05, 0.15)                    # holdout hit-rate band for the 0.1 head
PC_COV90 = (0.85, 0.95)                    # holdout hit-rate band for the 0.9 head
## <<< DT_ZONE py_const
HIDDEN = [300, 300, 150, 150, 50]          # Table 2 DNN5 hidden layers
DROPOUT = [0.50, 0.50, 0.30, 0.30, 0.10]   # Table 2 DNN5 dropout rates
EPOCHS = 20                                # Table 2 DNN5 epochs
BATCH = 500                                # paper: mini-batch size 500
LR = 1e-3                                  # not stated -> TensorFlow Adam default
BN_EPS = 1e-3                              # not stated -> TensorFlow batch_normalization default
BN_MOMENTUM = 0.01                         # TensorFlow decay 0.99 == torch momentum 0.01
DEVICE = "cuda" if torch.cuda.is_available() else "cpu"
P = {}             # per-process panel arrays (filled by load_panel in every worker)
CACHE_DIR = None


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
## >>> DT_ZONE py_head orig=470-470
        layers.append(self.linear(prev, N_OUT))   # 3 heads on the shared body: output unit j <-> TAUS[j] (same init rule)
## <<< DT_ZONE py_head
        self.net = nn.Sequential(*layers)

    @staticmethod
    def linear(fan_in, fan_out):
        lin = nn.Linear(fan_in, fan_out)
        sd = math.sqrt(2.0 / fan_in)       # paper: tf.truncated_normal, mean 0, std sqrt(2/M), M = fan-in
        nn.init.trunc_normal_(lin.weight, mean=0.0, std=sd, a=-2.0 * sd, b=2.0 * sd)
        nn.init.zeros_(lin.bias)
        return lin

    def forward(self, x):
## >>> DT_ZONE py_forward orig=482-482
        return self.net(x)
## <<< DT_ZONE py_forward


def fit_predict(X, y, Xp, seed):
    # same seed use, same init order, same cpu-generated batch order on any device
    torch.manual_seed(seed)
    gen = torch.Generator()
    gen.manual_seed(seed)
    model = DNN(X.shape[1]).to(DEVICE)
    opt = torch.optim.Adam(model.parameters(), lr=LR)
## >>> DT_ZONE py_loss_def orig=492-492
    tau_t = torch.tensor(TAUS, dtype=torch.float32, device=DEVICE).unsqueeze(0)   # 1 x 3: column j of the output is trained as TAUS[j]
## <<< DT_ZONE py_loss_def
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
## >>> DT_ZONE py_loss_step orig=509-509
            u = yt[idx].unsqueeze(1) - model(Xt[idx])            # residual y - q_tau (batch x 3)
            loss = torch.mean(u * (tau_t - (u < 0).float()))     # composite pinball (Koenker & Bassett 1978; equal weights, Zou & Yuan 2008)
## <<< DT_ZONE py_loss_step
            loss.backward()
            opt.step()
            steps += 1
            last = float(loss.item())
    model.eval()
    with torch.no_grad():
        pred = model(torch.from_numpy(Xp).to(DEVICE)).cpu().numpy()
    return pred, steps, skipped, last

## >>> DT_ZONE py_rearrange orig=+518

def rearrange(raw):
    # row-wise monotone rearrangement (Chernozhukov, Fernandez-Val & Galichon 2010, Econometrica 78(3)): sorted heads q10 <= q50 <= q90.
    # crossing rate = share of rows whose raw heads are not non-decreasing (recorded before the rearrangement).
    raw = np.asarray(raw, dtype=np.float64)
    cross = float(np.mean(np.any(np.diff(raw, axis=1) < 0.0, axis=1))) if raw.shape[0] else float("nan")
    return np.sort(raw, axis=1), cross

## <<< DT_ZONE py_rearrange

def feature_names(schema_names):
    return [c for c in schema_names if c[0] == "x" and c[1:].isdigit()]


def load_panel(path, cache_dir):
    global P, CACHE_DIR
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
## >>> DT_ZONE py_cache_key orig=+561
    spec += "|LOSS=%s|TAUS=%s|OUT=%d" % (LOSS_NAME, ",".join("%g" % t for t in TAUS), N_OUT)   # quantile target: never collides with a mean-target key
## <<< DT_ZONE py_cache_key
    h.update(spec.encode("ascii"))
    h.update(X.tobytes())
    h.update(y.tobytes())
    h.update(Xp.tobytes())
    h.update("|".join(tk.tolist()).encode("utf-8"))
    return h.hexdigest()


## >>> DT_ZONE py_cache_io orig=570-589
def cache_read(key):
    # npz = raw head outputs score (n x 3, before the rearrangement) + crossing rate + code version
    p = os.path.join(CACHE_DIR, key + ".npz")
    if not os.path.exists(p):
        return None
    try:
        z = np.load(p, allow_pickle=False)
        score = z["score"].astype(np.float64)
        if score.ndim != 2 or score.shape[1] != N_OUT or str(z["code_version"]) != CODE_VERSION:
            return None
        return dict(score=score, tk=z["tk"].astype(str), steps=int(z["steps"]),
                    skipped=int(z["skipped"]), last_loss=float(z["last_loss"]), secs=float(z["secs"]),
                    device=str(z["device"]), source=str(z["source"]), cross_rate=float(z["cross_rate"]))
    except Exception:
        return None


def cache_write(key, score, tk, steps, skipped, last_loss, secs, device, source, cross_rate):
    p = os.path.join(CACHE_DIR, key + ".npz")
    tmp = os.path.join(CACHE_DIR, "%s.%d.tmp.npz" % (key, os.getpid()))
    np.savez(tmp, score=np.asarray(score, dtype=np.float64), tk=np.asarray(tk, dtype=str),
             steps=np.int64(steps), skipped=np.int64(skipped), last_loss=np.float64(last_loss),
             secs=np.float64(secs), device=np.str_(device), source=np.str_(source),
             cross_rate=np.float64(cross_rate), code_version=np.str_(CODE_VERSION))
    os.replace(tmp, p)
## <<< DT_ZONE py_cache_io


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
## >>> DT_ZONE py_run_task_tail orig=605-617
    if hit is not None and (hit["score"].shape != (len(tk), N_OUT) or not np.array_equal(hit["tk"], tk)):
        hit = None
    if hit is None:
        t0 = time.time()
        pred, steps, skipped, last = fit_predict(X, y, Xp, seed)
        secs = time.time() - t0
        pred = np.asarray(pred, dtype=np.float64).reshape(len(tk), N_OUT)
        cross0 = rearrange(pred)[1]
        cache_write(key, pred, tk, steps, skipped, last, secs, DEVICE, "train", cross0)
        hit = dict(score=pred, steps=steps, skipped=skipped, last_loss=last, secs=secs, device=DEVICE, cross_rate=cross0)
        src = "train"
    raw = hit["score"]
    q, cross = rearrange(raw)
    if not (cross == hit["cross_rate"]):
        raise RuntimeError("crossing rate recomputed from the cached raw heads differs from the stored one (%r vs %r)" % (cross, hit["cross_rate"]))
    out = pd.DataFrame({"pred_i": np.repeat(pred_i, len(tk)), "Ticker": tk,
                        "q10_raw": raw[:, 0], "q50_raw": raw[:, 1], "q90_raw": raw[:, 2],
                        "q10": q[:, 0], "q50": q[:, 1], "q90": q[:, 2]})
    diag.update(steps=hit["steps"], skipped=hit["skipped"], last_loss=hit["last_loss"], secs=hit["secs"],
                source=src, device=hit["device"], cross_rate=cross, cache_key=key)
    return k, out, diag
## <<< DT_ZONE py_run_task_tail


## >>> DT_ZONE py_synth orig=620-632
def synthetic_check(seed, m):
    # positive control (design 3.3): a heteroscedastic synthetic y = f + g * eps must be learned by the same fit_predict routine.
    #   X ~ U(0,1)^m . f = PC_F_SD * (f0 - mean f0) / sd(f0), f0 = X w + 0.5 sin(6 X1) (rev3 centre form; mean/sd from the training draw)
    #   g = 0.25 + 2 X2 (width signal, 9x range) . eps ~ N(0,1).
    #   Training y and holdout labels go to the rank scale (0, 1] through the training-sample empirical CDF Fhat; truth on that
    #   scale: m = Fhat(f), l = Fhat(f + g z_0.1), u = Fhat(f + g z_0.9). The width dominates the order of l and u, so a model
    #   whose heads are q50 + constant fails the l / u spearman.
    #   pass = on the raw heads AND on the rearranged heads: spearman(q50, m), spearman(q10, l), spearman(q90, u) > PC_RHO_MIN and
    #   holdout hit rates P(y <= q10) in PC_COV10, P(y <= q90) in PC_COV90 (raw heads catch head swaps / sign flips that the sort hides).
    rng = np.random.default_rng(seed)
    n, npred = PC_N, PC_NPRED
    X = rng.uniform(0.0, 1.0, size=(n, m)).astype(np.float32)
    w = rng.normal(size=m).astype(np.float64)
    Xp = rng.uniform(0.0, 1.0, size=(npred, m)).astype(np.float32)
    e = rng.normal(size=n)
    ep = rng.normal(size=npred)
    f0 = X.astype(np.float64) @ w + 0.5 * np.sin(6.0 * X[:, 0].astype(np.float64))
    mu0 = float(np.mean(f0))
    sd0 = float(np.std(f0))

    def centre(Z):
        z = Z.astype(np.float64)
        return PC_F_SD * ((z @ w + 0.5 * np.sin(6.0 * z[:, 0])) - mu0) / sd0

    def width(Z):
        return 0.25 + 2.0 * Z[:, 1].astype(np.float64)

    f, g = centre(X), width(X)
    fp, gp = centre(Xp), width(Xp)
    ys = np.sort(f + g * e)

    def fhat(v):
        return np.searchsorted(ys, v, side="right") / float(n)

    y = fhat(f + g * e).astype(np.float32)
    yh = fhat(fp + gp * ep)
    z10 = -1.2815515655446004                  # standard normal 10% quantile (z_0.9 = -z_0.1)
    truth = (fhat(fp + gp * z10), fhat(fp), fhat(fp - gp * z10))
    raw, steps, skipped, last = fit_predict(X, y, Xp, seed)
    raw = np.asarray(raw, dtype=np.float64).reshape(npred, N_OUT)
    rea, cross = rearrange(raw)
    res = dict(steps=int(steps), cross_rate=cross, last_loss=float(last))
    ok = True
    for tag, Q in (("raw", raw), ("rea", rea)):
        for j, nm in enumerate(("10", "50", "90")):
            rho = float(pd.Series(Q[:, j]).corr(pd.Series(truth[j]), method="spearman"))
            res["%s_rho%s" % (tag, nm)] = rho
            ok = ok and (rho > PC_RHO_MIN)
        c10 = float(np.mean(yh <= Q[:, 0]))
        c90 = float(np.mean(yh <= Q[:, 2]))
        res["%s_cov10" % tag] = c10
        res["%s_cov90" % tag] = c90
        ok = ok and (PC_COV10[0] <= c10 <= PC_COV10[1]) and (PC_COV90[0] <= c90 <= PC_COV90[1])
    res["pass"] = bool(ok)
    return res
## <<< DT_ZONE py_synth


def main():
    rd = sys.argv[1]
    cd = sys.argv[2]
    cap = int(sys.argv[3]) if len(sys.argv) > 3 else 32
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
## >>> DT_ZONE py_main_pc orig=651-655
    pc = synthetic_check(int(sched["seed"].iloc[0]) + 7, m)
    print("[dnn] positive control (heteroscedastic synthetic, %d inputs, train %d / holdout %d): raw heads spearman q10 %.3f q50 %.3f q90 %.3f, hit q10 %.3f q90 %.3f | rearranged spearman q10 %.3f q50 %.3f q90 %.3f, hit q10 %.3f q90 %.3f | crossing %.4f | %d steps (%.0fs, device %s)" % (
        m, PC_N, PC_NPRED, pc["raw_rho10"], pc["raw_rho50"], pc["raw_rho90"], pc["raw_cov10"], pc["raw_cov90"],
        pc["rea_rho10"], pc["rea_rho50"], pc["rea_rho90"], pc["rea_cov10"], pc["rea_cov90"], pc["cross_rate"], pc["steps"], time.time() - t0, DEVICE), flush=True)
    if not pc["pass"]:
        print("[dnn] positive control FAILED - the training loop does not learn the known conditional quantiles; aborting", flush=True)
        sys.exit(3)
## <<< DT_ZONE py_main_pc
    tasks = [tuple(int(v) for v in row) for row in sched[["k", "pred_i", "u_i", "smin_i", "smax_i", "seed"]].to_numpy()]
    # processing order rotated by a per-run offset: concurrent runs (lane re-spawn) start on different months and
    # meet through the shared cache instead of training the same months twice; every month's result is order-independent
    off = int(hashlib.sha1(os.path.basename(rd).encode("utf-8")).hexdigest(), 16) % len(tasks)
    tasks = tasks[off:] + tasks[:off]
    ncpu = os.cpu_count() or 2
    workers = max(1, min(cap, 8 if DEVICE == "cuda" else 32, ncpu - 1))
    n_cached = len([f for f in os.listdir(cd) if f.endswith(".npz") and ".tmp." not in f])
    print("[dnn] %d months | inputs %d | device %s | %d worker processes (1 torch thread each, %d logical cpus) | torch %s | cache entries %d | start offset %d" % (
        len(tasks), m, DEVICE, workers, ncpu, torch.__version__, n_cached, off), flush=True)
    outs = []
    diags = []
    t1 = time.time()
    done = 0
    n_tr = 0
    n_ca = 0
    tr_secs = []
    with ProcessPoolExecutor(max_workers=workers, initializer=load_panel, initargs=(panel_path, cd)) as ex:
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
            if done <= 3 or done % 12 == 0 or done == len(tasks):
                rem = len(tasks) - done
                eta = (rem * (sum(tr_secs) / len(tr_secs)) / workers / 60.0) if tr_secs else 0.0
                print("[dnn]   %d/%d months | trained %d cache %d | n_train %d | steps %d | loss %.4f | %.1f min elapsed | eta %.0f min if all remaining train" % (
                    done, len(tasks), n_tr, n_ca, diag["n_train"], diag["steps"], diag["last_loss"], (time.time() - t1) / 60.0, eta), flush=True)
    if not outs:
        print("[dnn] no predictions produced", flush=True)
        sys.exit(4)
    pred = pd.concat(outs, ignore_index=True)
    pq.write_table(pa.Table.from_pandas(pred, preserve_index=False), pred_path)
    dg = pd.DataFrame(diags)
## >>> DT_ZONE py_main_diag orig=695-695
    for kk in ("raw_rho10", "raw_rho50", "raw_rho90", "raw_cov10", "raw_cov90",
               "rea_rho10", "rea_rho50", "rea_rho90", "rea_cov10", "rea_cov90", "cross_rate", "steps"):
        dg["pc_" + kk] = pc[kk]
    dg["pc_pass"] = bool(pc["pass"])
    dg["code_version"] = CODE_VERSION
    dg["cache_key"] = dg["cache_key"].fillna("").astype(str) if "cache_key" in dg.columns else ""
## <<< DT_ZONE py_main_diag
    dg["workers"] = workers
    dg["ncpu"] = ncpu
    dg["n_inputs"] = m
    pq.write_table(pa.Table.from_pandas(dg, preserve_index=False), diag_path)
    print("[dnn] done: %d prediction rows over %d months (trained %d, cache %d) in %.1f min" % (
        len(pred), len(outs), n_tr, n_ca, (time.time() - t1) / 60.0), flush=True)


if __name__ == "__main__":
    main()

