# pc_mutation_test.py - DT_2002_06975 positive control + mutation test (design 3.3, registration rehearsal). CPU only.
#
#   1. extract the python source (.PY_SRC raw string) from an engine file (default engine_template.R - every generated engine
#      carries the identical .PY_SRC, template_diff_check.R proves it)
#   2. build 4 mutants by SOURCE TEXT substitution (never deparse): each `old` must occur exactly once in the extracted source,
#      the substitution must take effect (mutant != source, `new` present, `old` gone) - otherwise the test itself fails
#        pinball_sign_flip : residual u = q - y instead of y - q        (heads learn tau -> 1 - tau)
#        head_swap         : loss taus reversed (column 0 trained as 0.9) (0.1 <-> 0.9)
#        mse_revert        : loss = mean(u^2)                            (every head = conditional mean)
#        width_not_learned : every head = q50 head + its own learned constant (no width signal)
#   3. run synthetic_check(seed, m=31) for the correct source and each mutant on every seed in a separate CPU-only process
#      (pc_run_one.py forces CUDA_VISIBLE_DEVICES=-1 and refuses to run if CUDA is visible)
#   4. assert: the correct source passes on every seed and every mutant fails on every seed; write tests/_out/pc_mutation_results.json
#   exit code 0 = all assertions hold, 1 = an assertion failed, 2 = harness error
#
#   usage: python pc_mutation_test.py [--engine PATH] [--seeds 20020705,20020706,20020707] [--jobs 5] [--set NAME=VALUE ...]
#   seed 20020705 = the production positive-control seed (schedule seed of month k = 1 = 20020697 + 1, plus 7 - engine main()).
import os
import sys
import json
import time
import subprocess
from concurrent.futures import ThreadPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))
DT_DIR = os.path.dirname(HERE)
PY = sys.executable
M_INPUTS = 31

MUTATIONS = [
    ("pinball_sign_flip",
     "u = yt[idx].unsqueeze(1) - model(Xt[idx])",
     "u = model(Xt[idx]) - yt[idx].unsqueeze(1)"),
    ("head_swap",
     "tau_t = torch.tensor(TAUS, dtype=torch.float32",
     "tau_t = torch.tensor(TAUS[::-1], dtype=torch.float32"),
    ("mse_revert",
     "loss = torch.mean(u * (tau_t - (u < 0).float()))",
     "loss = torch.mean(u * u)"),
    ("width_not_learned",
     "        return self.net(x)\n",
     "        return self.net(x)[:, 1:2] + (self.net[-1].bias - self.net[-1].bias[1])\n"),
]


def extract_py(engine_path):
    with open(engine_path, "rb") as fh:
        txt = fh.read().decode("utf-8")
    start_tok = '.PY_SRC <- r"---(\n'
    end_tok = '\n)---"\n'
    if txt.count(start_tok) != 1 or txt.count(end_tok) != 1:
        raise RuntimeError("PY_SRC delimiters not found exactly once in %s" % engine_path)
    a = txt.index(start_tok) + len(start_tok)
    b = txt.index(end_tok)
    # byte-exact copy of what engine.R writes: the raw string content ("\n" + body + "\n") plus writeLines()' final newline
    return "\n" + txt[a:b] + "\n\n"


def make_mutants(src):
    out = {}
    for name, old, new in MUTATIONS:
        n_old = src.count(old)
        if n_old != 1:
            raise RuntimeError("mutation %s: target text occurs %d times (must be exactly 1): %r" % (name, n_old, old))
        mut = src.replace(old, new, 1)
        if mut == src or new not in mut or old in mut:
            raise RuntimeError("mutation %s: substitution did not take effect" % name)
        out[name] = mut
    return out


def run_one(path, seed, sets):
    cmd = [PY, os.path.join(HERE, "pc_run_one.py"), path, str(seed), str(M_INPUTS)]
    for s in sets:
        cmd += ["--set", s]
    env = dict(os.environ)
    env["CUDA_VISIBLE_DEVICES"] = "-1"
    env["OMP_NUM_THREADS"] = "1"
    env["MKL_NUM_THREADS"] = "1"
    p = subprocess.run(cmd, capture_output=True, text=True, env=env, cwd=HERE)
    lines = [ln for ln in p.stdout.splitlines() if ln.startswith("{")]
    if p.returncode != 0 or not lines:
        return {"error": "rc %d" % p.returncode, "stderr": p.stderr[-2000:], "stdout": p.stdout[-2000:]}
    return json.loads(lines[-1])


def main():
    args = sys.argv[1:]
    engine = os.path.join(DT_DIR, "engine_template.R")
    seeds = [20020705, 20020706, 20020707]
    jobs = 5
    sets = []
    out_dir = os.path.join(HERE, "_out")
    i = 0
    while i < len(args):
        if args[i] == "--engine":
            engine = args[i + 1]; i += 2
        elif args[i] == "--seeds":
            seeds = [int(s) for s in args[i + 1].split(",")]; i += 2
        elif args[i] == "--jobs":
            jobs = int(args[i + 1]); i += 2
        elif args[i] == "--set":
            sets.append(args[i + 1]); i += 2
        elif args[i] == "--out":
            out_dir = args[i + 1]; i += 2
        else:
            raise SystemExit("unknown argument %s" % args[i])
    engine, out_dir = os.path.abspath(engine), os.path.abspath(out_dir)
    os.makedirs(os.path.join(out_dir, "py"), exist_ok=True)
    src = extract_py(engine)
    variants = {"correct": src}
    variants.update(make_mutants(src))
    paths = {}
    for name, code in variants.items():
        p = os.path.join(out_dir, "py", "dnn_quantile_%s.py" % name)
        with open(p, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(code)
        paths[name] = p
    t0 = time.time()
    tasks = [(name, seed) for name in variants for seed in seeds]
    with ThreadPoolExecutor(max_workers=jobs) as ex:
        res = list(ex.map(lambda t: (t[0], t[1], run_one(paths[t[0]], t[1], sets)), tasks))
    table = {}
    for name, seed, r in res:
        table.setdefault(name, {})[str(seed)] = r
    errors = []
    for name, seed, r in res:
        if "error" in r:
            errors.append("%s seed %d: harness error %s %s" % (name, seed, r["error"], r.get("stderr", "")[-400:]))
            continue
        if name == "correct" and not r["pass"]:
            errors.append("correct source FAILED the positive control on seed %d" % seed)
        if name != "correct" and r["pass"]:
            errors.append("mutant %s PASSED the positive control on seed %d (control has no power against it)" % (name, seed))

    def fmt(r):
        if "error" in r:
            return "ERROR"
        return ("pass=%-5s raw rho10 %.3f rho50 %.3f rho90 %.3f cov10 %.3f cov90 %.3f | rea rho10 %.3f rho50 %.3f rho90 %.3f cov10 %.3f cov90 %.3f | cross %.4f | %ss"
                % (r["pass"], r["raw_rho10"], r["raw_rho50"], r["raw_rho90"], r["raw_cov10"], r["raw_cov90"],
                   r["rea_rho10"], r["rea_rho50"], r["rea_rho90"], r["rea_cov10"], r["rea_cov90"], r["cross_rate"], r["secs"]))
    for name in variants:
        for seed in seeds:
            print("[pc] %-18s seed %d  %s" % (name, seed, fmt(table[name][str(seed)])), flush=True)
    summary = dict(engine=os.path.relpath(engine, DT_DIR).replace("\\", "/"), seeds=seeds, m=M_INPUTS, overrides=sets,
                   mutations=[dict(name=n, old=o, new=w) for n, o, w in MUTATIONS],
                   correct_pass_all=all(table["correct"][str(s)].get("pass") is True for s in seeds),
                   mutants_fail_all={n: all(table[n][str(s)].get("pass") is False for s in seeds) for n, _, _ in MUTATIONS},
                   results=table, errors=errors, wall_secs=round(time.time() - t0, 1),
                   device="cpu (CUDA_VISIBLE_DEVICES=-1)", generated_at=time.strftime("%Y-%m-%dT%H:%M:%S"))
    tag = "" if not sets else "_" + "_".join(s.replace("=", "-") for s in sets)
    with open(os.path.join(out_dir, "pc_mutation_results%s.json" % tag), "w", encoding="utf-8") as fh:
        json.dump(summary, fh, indent=2)
    if errors:
        print("[pc] FAIL:\n  " + "\n  ".join(errors), flush=True)
        sys.exit(1)
    print("[pc] OK - correct source passes on %d seeds, %d/%d mutants fail on every seed (%.0fs wall)"
          % (len(seeds), sum(summary["mutants_fail_all"].values()), len(MUTATIONS), time.time() - t0), flush=True)


if __name__ == "__main__":
    main()
