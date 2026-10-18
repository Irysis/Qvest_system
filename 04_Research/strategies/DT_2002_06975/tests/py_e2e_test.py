# py_e2e_test.py - end-to-end test of the embedded DT python (dnn_rolling.py written by engine_<rule>.R) on a tiny synthetic panel. CPU only.
#   A. in-process: load_panel / select / cache_key / run_task / cache_read / rearrange / PIT assertion
#      - first run_task = train + cache write (npz: raw score n x 3, cross_rate, code_version); second = cache hit, identical output
#      - cache key changes with one feature byte / with the seed; differs from the rev3 mean-target spec; rev3-format npz (n x 1) is never a hit
#      - rearrange: known crossings -> sorted heads + crossing share; label realized after the update day -> RuntimeError (PIT)
#   B. subprocess: the full script main() on the tiny panel (positive control included, ~100 s on CPU) -> rc 0, pred.parquet columns,
#      diag pc_* / code_version / cache_key / cross_rate; a second run is served from the cache with identical predictions
#   usage: python py_e2e_test.py       exit 0 = all assertions hold
import os
os.environ["CUDA_VISIBLE_DEVICES"] = "-1"
os.environ.setdefault("OMP_NUM_THREADS", "1")
os.environ.setdefault("MKL_NUM_THREADS", "1")
import sys
import json
import time
import shutil
import hashlib
import subprocess
import importlib.util
import numpy as np
import pandas as pd
import pyarrow as pa
import pyarrow.parquet as pq

HERE = os.path.dirname(os.path.abspath(__file__))
DT_DIR = os.path.dirname(HERE)
OUT = os.path.join(HERE, "_out", "py_e2e")
sys.path.insert(0, HERE)
import pc_mutation_test as H   # noqa: E402  (extract_py)

CHECKS = []


def chk(name, ok, detail=""):
    CHECKS.append(dict(name=name, ok=bool(ok), detail=str(detail)))
    print("[py-e2e] %-4s %s%s" % ("OK" if ok else "FAIL", name, (" - " + str(detail)) if detail else ""), flush=True)


def build_panel(path, seed=11, n_days=60, n_tk=30, m=31):
    rng = np.random.default_rng(seed)
    rows = []
    tks = ["A%06d" % (100000 + i) for i in range(n_tk)]
    for d in range(1, n_days + 1):
        X = rng.uniform(0, 1, size=(n_tk, m))
        f = X[:, :5].sum(axis=1) + 0.3 * rng.normal(size=n_tk)
        y = pd.Series(f).rank(method="average").to_numpy() / n_tk
        lab = np.full(n_tk, d + 5, dtype=float)
        if d > n_days - 5:                                     # last 5 days: label not realized yet
            y[:] = np.nan
            lab[:] = np.nan
        df = pd.DataFrame(X, columns=["x%02d" % (j + 1) for j in range(m)])
        df.insert(0, "Ticker", tks)
        df.insert(0, "di", np.int32(d))
        df["y"] = y
        df["lab_i"] = pd.array(np.where(np.isnan(lab), pd.NA, lab), dtype="Int32")
        rows.append(df)
    P = pd.concat(rows, ignore_index=True)
    pq.write_table(pa.Table.from_pandas(P, preserve_index=False), path)
    return P


def main():
    shutil.rmtree(OUT, ignore_errors=True)
    os.makedirs(OUT, exist_ok=True)
    src = H.extract_py(os.path.join(DT_DIR, "engine_Q50.R"))
    mod_path = os.path.join(OUT, "dnn_rolling.py")
    with open(mod_path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(src)
    import torch
    if torch.cuda.is_available():
        print("[py-e2e] cuda visible - refusing to run", flush=True)
        sys.exit(2)
    spec = importlib.util.spec_from_file_location("dt_e2e_mod", mod_path)
    M = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(M)
    chk("module DEVICE = cpu", M.DEVICE == "cpu", M.DEVICE)
    chk("CODE_VERSION / TAUS / N_OUT", M.CODE_VERSION == "DT_2002_06975/dnn_quantile/rev1" and M.TAUS == [0.1, 0.5, 0.9] and M.N_OUT == 3)

    # ---- A. in-process ----
    rdA = os.path.join(OUT, "runA")
    cdA = os.path.join(OUT, "cacheA")
    os.makedirs(rdA, exist_ok=True)
    os.makedirs(cdA, exist_ok=True)
    panel = os.path.join(rdA, "panel.parquet")
    build_panel(panel)
    M.load_panel(panel, cdA)
    torch.set_num_threads(1)
    t1 = (1, 50, 50, 1, 45, 20020698)
    k, out1, d1 = M.run_task(t1)
    cols = ["pred_i", "Ticker", "q10_raw", "q50_raw", "q90_raw", "q10", "q50", "q90"]
    chk("run_task #1 trains (source = train)", d1["source"] == "train", d1["source"])
    chk("run_task output columns / rows", list(out1.columns) == cols and len(out1) == 30, list(out1.columns))
    q = out1[["q10", "q50", "q90"]].to_numpy()
    raw = out1[["q10_raw", "q50_raw", "q90_raw"]].to_numpy()
    chk("rearranged heads ordered q10 <= q50 <= q90", bool(np.all(np.diff(q, axis=1) >= 0)))
    chk("rearranged = row sort of raw", np.array_equal(q, np.sort(raw, axis=1)))
    cr = float(np.mean(np.any(np.diff(raw, axis=1) < 0, axis=1)))
    chk("diag cross_rate = crossing share of raw heads", d1["cross_rate"] == cr, "%.4f" % cr)
    X, y, Xp, tk, nd, ml = M.select(t1)
    key = M.cache_key(t1, X, y, Xp, tk)
    chk("diag cache_key = cache_key(task, X, y, Xp, tk)", d1["cache_key"] == key and len(key) == 40)
    z = np.load(os.path.join(cdA, key + ".npz"), allow_pickle=False)
    chk("npz: score n x 3 raw + cross_rate + code_version",
        z["score"].shape == (30, 3) and np.array_equal(z["score"], raw) and float(z["cross_rate"]) == cr and str(z["code_version"]) == M.CODE_VERSION)
    k, out2, d2 = M.run_task(t1)
    chk("run_task #2 = cache hit, identical output", d2["source"] == "cache" and out1.equals(out2))
    X2 = X.copy()
    X2[3, 7] = np.float32(X2[3, 7] + 0.001)
    chk("cache key changes with one feature value", M.cache_key(t1, X2, y, Xp, tk) != key)
    chk("cache key changes with the seed", M.cache_key((1, 50, 50, 1, 45, 20020699), X, y, Xp, tk) != key)
    h = hashlib.sha1()                                          # rev3 mean-target key (old CODE_VERSION, no LOSS/TAUS/OUT suffix)
    h.update("RP_AUTO_2002_06975/dnn_rolling/rev3".encode("ascii"))
    spec3 = "|%d|%d|%d|%d|%d|%s|%s|%d|%d|%r|%r|%r|%s" % (50, 50, 1, 45, 20020698, M.HIDDEN, M.DROPOUT, M.EPOCHS, M.BATCH, M.LR, M.BN_EPS, M.BN_MOMENTUM, ",".join(M.P["feats"]))
    h.update(spec3.encode("ascii"))
    h.update(X.tobytes()); h.update(y.tobytes()); h.update(Xp.tobytes()); h.update("|".join(tk.tolist()).encode("utf-8"))
    chk("quantile key != rev3 mean-target key for the same inputs", h.hexdigest() != key)
    bogus = os.path.join(cdA, "f" * 40 + ".npz")               # rev3-format entry (score n x 1) must never be a hit
    np.savez(bogus, score=np.zeros(30), tk=np.asarray(tk, dtype=str), steps=np.int64(1), skipped=np.int64(0), last_loss=np.float64(0),
             secs=np.float64(0), device=np.str_("cpu"), source=np.str_("train"))
    chk("rev3-format npz (n x 1, no code_version) -> cache_read None", M.cache_read("f" * 40) is None)
    rr, cc = M.rearrange(np.array([[0.3, 0.2, 0.5], [0.1, 0.2, 0.3], [0.9, 0.5, 0.1], [0.2, 0.2, 0.2]]))
    chk("rearrange known case (crossing 2/4)", np.array_equal(rr, np.array([[0.2, 0.3, 0.5], [0.1, 0.2, 0.3], [0.1, 0.5, 0.9], [0.2, 0.2, 0.2]])) and cc == 0.5)
    try:
        M.run_task((3, 50, 44, 1, 45, 20020700))               # max_lab_i 50 > u_i 44
        pit_raised = False
    except RuntimeError as e:
        pit_raised = "PIT" in str(e)
    chk("PIT assertion: label realized after the update day -> RuntimeError", pit_raised)

    # ---- B. subprocess: the full script main() twice ----
    py = sys.executable
    env = dict(os.environ)
    env["CUDA_VISIBLE_DEVICES"] = "-1"
    env["PYTHONUTF8"] = "1"
    cdB = os.path.join(OUT, "cacheB")
    preds = []
    for run in ("run_20261018_000001_1", "run_20261018_000002_2"):
        rd = os.path.join(OUT, run)
        os.makedirs(rd, exist_ok=True)
        shutil.copy(panel, os.path.join(rd, "panel.parquet"))
        sched = pd.DataFrame({"k": [1, 2], "pred_i": [50, 60], "u_i": [50, 55], "smin_i": [1, 6], "smax_i": [45, 50],
                              "seed": [20020698, 20020699]}).astype("int64")
        pq.write_table(pa.Table.from_pandas(sched, preserve_index=False), os.path.join(rd, "schedule.parquet"))
        shutil.copy(mod_path, os.path.join(rd, "dnn_rolling.py"))
        t0 = time.time()
        p = subprocess.run([py, os.path.join(rd, "dnn_rolling.py"), rd, cdB, "2"], capture_output=True, text=True, env=env)
        log = p.stdout + p.stderr
        with open(os.path.join(OUT, run + ".log"), "w", encoding="utf-8") as fh:
            fh.write(log)
        chk("%s main() rc 0 (%.0fs)" % (run, time.time() - t0), p.returncode == 0, "rc %d %s" % (p.returncode, log[-300:] if p.returncode else ""))
        if p.returncode != 0:
            continue
        pr = pq.read_table(os.path.join(rd, "pred.parquet")).to_pandas()
        dg = pq.read_table(os.path.join(rd, "diag.parquet")).to_pandas()
        need = ["pc_raw_rho10", "pc_raw_rho50", "pc_raw_rho90", "pc_raw_cov10", "pc_raw_cov90", "pc_rea_rho10", "pc_rea_rho50", "pc_rea_rho90",
                "pc_rea_cov10", "pc_rea_cov90", "pc_cross_rate", "pc_steps", "pc_pass", "code_version", "cache_key", "cross_rate", "n_inputs"]
        chk("%s pred.parquet columns / rows" % run, list(pr.columns) == cols and len(pr) == 60)
        chk("%s diag columns (pc_* · code_version · cache_key · cross_rate)" % run, all(c in dg.columns for c in need), [c for c in need if c not in dg.columns])
        chk("%s positive control passed in main() (pc_pass, %d steps)" % (run, int(dg["pc_steps"].iloc[0])),
            bool(dg["pc_pass"].iloc[0]) and int(dg["pc_steps"].iloc[0]) == 4000 and "positive control (heteroscedastic synthetic" in log)
        chk("%s code_version recorded" % run, set(dg["code_version"]) == {M.CODE_VERSION})
        srcs = sorted(dg["source"].tolist())
        chk("%s month sources %s" % (run, srcs), srcs == (["train", "train"] if run.endswith("_1") else ["cache", "cache"]))
        preds.append(pr.sort_values(["pred_i", "Ticker"]).reset_index(drop=True))
    if len(preds) == 2:
        chk("second run (cache) predictions identical to the first", preds[0].equals(preds[1]))
    ok = all(c["ok"] for c in CHECKS)
    for d in ("runA", "cacheA", "cacheB", "run_20261018_000001_1", "run_20261018_000002_2"):   # panels / caches - keep only logs + module
        shutil.rmtree(os.path.join(OUT, d), ignore_errors=True)
    with open(os.path.join(HERE, "_out", "py_e2e_results.json"), "w", encoding="utf-8") as fh:
        json.dump(dict(ok=ok, n=len(CHECKS), n_ok=sum(c["ok"] for c in CHECKS), checks=CHECKS, device="cpu (CUDA_VISIBLE_DEVICES=-1)",
                       at=time.strftime("%Y-%m-%dT%H:%M:%S")), fh, indent=2, ensure_ascii=False)
    print("[py-e2e] %s - %d/%d checks" % ("OK" if ok else "FAIL", sum(c["ok"] for c in CHECKS), len(CHECKS)), flush=True)
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
