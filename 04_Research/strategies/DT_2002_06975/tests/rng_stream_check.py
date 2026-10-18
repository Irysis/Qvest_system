# rng_stream_check.py - common-random-number facts between the mean engine (RP_AUTO_2002_06975 engine.R rev3) and the quantile engine
#   (DT engine_Q50.R) at the same seed, measured on CPU only (judgment Superfan T1 C-20261018-054 (0); no common-RNG change is made).
#   fit_predict order (both): torch.manual_seed(seed) -> gen = torch.Generator(); gen.manual_seed(seed) -> DNN(m) built on CPU -> .to(DEVICE)
#   -> per step: perm from gen (batch order) ; dropout masks from the default generator of the tensor's device.
#   measured here: hidden-layer init equal? output-layer init equal? CPU generator state after init equal? how many extra uniform draws?
#   batch order equal? CPU dropout masks equal? + RX0S (engine_RX0S.R = rev3 with seed base 20261018) positive control on CPU.
#   CUDA is NOT measured (GPU reserved for the lane); the CUDA statement in the output is a code-structure deduction.
#   usage: python rng_stream_check.py      writes tests/_out/rng_stream_facts.json ; exit 0 = every measured fact as recorded
import os
os.environ["CUDA_VISIBLE_DEVICES"] = "-1"
os.environ.setdefault("OMP_NUM_THREADS", "1")
os.environ.setdefault("MKL_NUM_THREADS", "1")
import sys
import json
import time
import importlib.util
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
DT_DIR = os.path.dirname(HERE)
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(DT_DIR)))
OUT = os.path.join(HERE, "_out", "rng")
sys.path.insert(0, HERE)
import pc_mutation_test as H   # noqa: E402


def load(src_engine, name):
    os.makedirs(OUT, exist_ok=True)
    p = os.path.join(OUT, name + ".py")
    with open(p, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(H.extract_py(src_engine))
    spec = importlib.util.spec_from_file_location(name, p)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def main():
    import torch
    import torch.nn as nn
    if torch.cuda.is_available():
        print("cuda visible - refusing", flush=True)
        sys.exit(2)
    Mm = load(os.path.join(ROOT, "04_Research", "strategies", "RP_AUTO_2002_06975", "engine.R"), "mean_rev3")
    Mq = load(os.path.join(DT_DIR, "engine_Q50.R"), "quantile_rev1")
    Mr = load(os.path.join(DT_DIR, "rx0s", "engine_RX0S.R"), "rx0s_rev3")
    torch.set_num_threads(1)
    facts = {}
    seed = 20020698                                             # month k = 1 seed of the mean engine / quantile engine
    m = 31

    def build(M):
        torch.manual_seed(seed)
        gen = torch.Generator()
        gen.manual_seed(seed)
        net = M.DNN(m)
        return net, gen, torch.get_rng_state().clone()

    nm, gm, sm = build(Mm)
    nq, gq, sq = build(Mq)
    lm = [x for x in nm.net if isinstance(x, nn.Linear)]
    lq = [x for x in nq.net if isinstance(x, nn.Linear)]
    facts["n_linear_layers"] = [len(lm), len(lq)]
    facts["hidden_init_equal"] = bool(all(torch.equal(a.weight, b.weight) and torch.equal(a.bias, b.bias) for a, b in zip(lm[:-1], lq[:-1])))
    facts["output_layer_shapes"] = [list(lm[-1].weight.shape), list(lq[-1].weight.shape)]
    facts["output_row0_equal"] = bool(torch.equal(lm[-1].weight[0], lq[-1].weight[0]))
    facts["cpu_rng_state_after_init_equal"] = bool(torch.equal(sm, sq))
    extra = None
    for k in range(0, 2001):                                    # extra float32 uniform draws that carry the mean state to the quantile state
        torch.set_rng_state(sm)
        if k:
            torch.empty(k).uniform_()
        if torch.equal(torch.get_rng_state(), sq):
            extra = k
            break
    facts["extra_cpu_uniform_draws_by_quantile_init"] = extra   # unit = one float32 element of torch.empty(k).uniform_() (implementation-specific)

    def units(fn):                                              # consumption of one init op in the same unit (search up to 3000)
        torch.manual_seed(123); s0 = torch.get_rng_state().clone()
        fn(); s1 = torch.get_rng_state().clone()
        for kk in range(0, 3001):
            torch.set_rng_state(s0)
            if kk:
                torch.empty(kk).uniform_()
            if torch.equal(torch.get_rng_state(), s1):
                return kk
        return None
    import math

    def tn(r):
        def f():
            t = torch.empty(r, 50); sd = math.sqrt(2.0 / 50); nn.init.trunc_normal_(t, mean=0.0, std=sd, a=-2 * sd, b=2 * sd)
        return f
    facts["units_linear_50x1_construction"] = units(lambda: nn.Linear(50, 1))
    facts["units_linear_50x3_construction"] = units(lambda: nn.Linear(50, 3))
    facts["units_trunc_normal_1x50"] = units(tn(1))
    facts["units_trunc_normal_3x50"] = units(tn(3))
    pm = torch.randperm(10000, generator=gm)
    pq_ = torch.randperm(10000, generator=gq)
    facts["batch_order_equal"] = bool(torch.equal(pm, pq_))
    # CPU dropout masks: same hidden weights, same input, train mode, each from its own post-init CPU state
    x = torch.from_numpy(np.random.default_rng(1).uniform(0, 1, size=(500, m)).astype(np.float32))
    nm.train(); nq.train()
    torch.set_rng_state(sm); hm = nm.net[:-1](x)
    torch.set_rng_state(sq); hq = nq.net[:-1](x)
    facts["cpu_first_step_hidden_output_equal"] = bool(torch.equal(hm, hq))
    torch.set_rng_state(sm); hq_aligned = nq.net[:-1](x)        # same hidden net, quantile model fed the mean model's RNG state
    facts["cpu_hidden_output_equal_when_rng_state_aligned"] = bool(torch.equal(hm, hq_aligned))
    facts["model_built_on"] = "cpu (DNN(m) then .to(DEVICE) in fit_predict)"
    facts["cuda_deduction_unmeasured"] = ("on CUDA, init draws come from the CPU generator (model built on CPU) while dropout masks come from the CUDA "
                                          "generator, which torch.manual_seed(seed) seeds and init does not touch; both models issue the same dropout calls "
                                          "(5 hidden dropout layers, same batch shapes, same step count) -> by code structure the CUDA dropout stream is the "
                                          "same for RX0 and the quantile model at the same seed. Not measured (GPU reserved).")
    # RX0S: rev3 positive control at the new seed (first month seed 20261018 + 1, + 7 as in main())
    t0 = time.time()
    rho_r, steps_r = Mr.synthetic_check(20261018 + 1 + 7, m)
    facts["rx0s_code_version"] = Mr.CODE_VERSION
    facts["rx0s_positive_control_seed"] = 20261018 + 1 + 7
    facts["rx0s_positive_control_spearman_cpu"] = round(float(rho_r), 4)
    facts["rx0s_positive_control_pass_cpu"] = bool(rho_r > 0.8)
    facts["rx0s_positive_control_secs"] = round(time.time() - t0, 1)
    rho_o, _ = Mm.synthetic_check(20020698 + 7, m)
    facts["rev3_positive_control_spearman_cpu_original_seed"] = round(float(rho_o), 4)
    facts["device"] = "cpu (CUDA_VISIBLE_DEVICES=-1)"
    facts["torch"] = torch.__version__
    for k_, v_ in facts.items():
        print("[rng] %-48s %s" % (k_, v_), flush=True)
    ok = (facts["hidden_init_equal"] and not facts["output_row0_equal"] and not facts["cpu_rng_state_after_init_equal"] and extra is not None and extra > 0 and
          facts["batch_order_equal"] and not facts["cpu_first_step_hidden_output_equal"] and facts["cpu_hidden_output_equal_when_rng_state_aligned"] and
          facts["rx0s_positive_control_pass_cpu"] and facts["rx0s_code_version"] == "RP_AUTO_2002_06975/dnn_rolling/rev3")
    facts["ok"] = bool(ok)
    with open(os.path.join(HERE, "_out", "rng_stream_facts.json"), "w", encoding="utf-8") as fh:
        json.dump(facts, fh, indent=2)
    print("[rng] %s" % ("OK - facts as recorded" if ok else "UNEXPECTED - see facts"), flush=True)
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
