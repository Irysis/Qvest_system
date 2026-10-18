# pc_run_one.py - run the DT_2002_06975 positive control (synthetic_check) of ONE extracted python source on CPU only.
#   usage: python pc_run_one.py <module.py> <seed> <m> [--set NAME=VALUE ...]
#   prints one JSON line (the synthetic_check result + device facts). GPU is never touched:
#   CUDA_VISIBLE_DEVICES=-1 is forced before torch is imported (an empty value is dropped by Windows process spawning),
#   and the run aborts unless torch reports no CUDA device and the module chose DEVICE == "cpu".
#   --set overrides a module constant after import (rehearsal of the synthetic constants only; the registered test uses none).
import os
os.environ["CUDA_VISIBLE_DEVICES"] = "-1"
os.environ.setdefault("OMP_NUM_THREADS", "1")
os.environ.setdefault("MKL_NUM_THREADS", "1")
import sys
import json
import time
import importlib.util


def main():
    path, seed, m = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
    sets = {}
    rest = sys.argv[4:]
    for i, a in enumerate(rest):
        if a == "--set":
            k, v = rest[i + 1].split("=", 1)
            sets[k] = v
    import torch
    if torch.cuda.is_available() or torch.cuda.device_count() != 0:
        print(json.dumps({"error": "cuda visible - refusing to run (GPU is reserved for the lane)"}), flush=True)
        sys.exit(2)
    spec = importlib.util.spec_from_file_location("dt_pc_mod", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    if mod.DEVICE != "cpu":
        print(json.dumps({"error": "module DEVICE %s != cpu" % mod.DEVICE}), flush=True)
        sys.exit(2)
    for k, v in sets.items():
        old = getattr(mod, k)
        setattr(mod, k, type(old)(float(v)) if isinstance(old, (int, float)) else v)
    torch.set_num_threads(1)
    t0 = time.time()
    res = mod.synthetic_check(seed, m)
    res.update(seed=seed, m=m, secs=round(time.time() - t0, 1), device=mod.DEVICE, torch=torch.__version__,
               threads=torch.get_num_threads(), overrides=sets, module=os.path.basename(path),
               PC_N=mod.PC_N, PC_NPRED=mod.PC_NPRED, PC_F_SD=mod.PC_F_SD)
    print(json.dumps(res), flush=True)


if __name__ == "__main__":
    main()
