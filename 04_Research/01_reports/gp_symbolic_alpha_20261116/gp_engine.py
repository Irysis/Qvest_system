"""gp_engine.py — DEAP 강타입 유전 프로그래밍 1회 진화 + 시행 원장 (gpa_v1 · 2026-11-16)

DEAP(Fortin et al. 2012, JMLR 13:2171-2175) PrimitiveSetTyped — 형 P(패널) · W(창). 창은 W 단말(고정 후보)로만 들어가
  문법이 'ts_mean(x, 37)' 같은 임의 창 · 창 자리에 패널이 오는 수식을 원천 차단한다.
평가: DEAP 개체 → 튜플 → 정규화(gp_ops.canon) → 해시. 같은 해시는 다시 평가하지 않는다(적합도 재사용 · 원장 1행).
원장(jsonl): 고유 수식마다 1행(첫 평가 세대 · 출신 · 해시 · 보유 지문 · 학습/검증 지표 · 적합도) + 세대 요약 행.
"""
from __future__ import annotations

import json
import operator
import random
import time

import numpy as np
from deap import base, creator, gp, tools

import gp_ops as O
from gp_fitness import metrics, std_corr


class P:  # 패널 형
    pass


class W:  # 창 형
    pass


def build_pset(cfg):
    G = cfg["grammar"]
    D = cfg["data"]
    ps = gp.PrimitiveSetTyped("MAIN", [], P)
    for k in G["unary"]:
        ps.addPrimitive(lambda *a: None, [P], P, name=k)
    for k in G["binary"]:
        ps.addPrimitive(lambda *a: None, [P, P], P, name=k)
    for k in G["ts_unary"]:
        ps.addPrimitive(lambda *a: None, [P, W], P, name=k)
    for k in G["ts_binary"]:
        ps.addPrimitive(lambda *a: None, [P, P, W], P, name=k)
    terms = list(G["terminals_log"]) + ["fr_" + k for k in D["fund_ratios"]]
    for t in terms:
        ps.addTerminal(t, P, name=t)
    for w in G["windows"]:
        ps.addTerminal(int(w), W)   # 이름 없이 = 값이 int 로 남는다(이름을 주면 DEAP 가 값을 이름 문자열로 바꾼다)
    return ps


def _generate(pset, min_, max_, condition, type_=None):
    """DEAP gp.generate 와 같되, 기본형이 없는 형(W)은 깊이와 상관없이 단말을 고른다(원판은 IndexError)."""
    if type_ is None:
        type_ = pset.ret
    expr = []
    height = random.randint(min_, max_)
    stack = [(0, type_)]
    while stack:
        depth, t = stack.pop()
        if condition(height, depth) or not pset.primitives[t]:
            expr.append(random.choice(pset.terminals[t]))
        else:
            prim = random.choice(pset.primitives[t])
            expr.append(prim)
            for arg in reversed(prim.args):
                stack.append((depth + 1, arg))
    return expr


def gen_full(pset, min_, max_, type_=None):
    return _generate(pset, min_, max_, lambda h, d: d == h, type_)


def gen_grow(pset, min_, max_, type_=None):
    return _generate(pset, min_, max_, lambda h, d: d == h or (d >= min_ and random.random() < pset.terminalRatio), type_)


def gen_half(pset, min_, max_, type_=None):
    return (gen_grow if random.random() < 0.5 else gen_full)(pset, min_, max_, type_)


def cx_one_point(ind1, ind2):
    """DEAP gp.cxOnePoint 와 같되 공통 형 집합을 이름순 목록으로 — 원판은 set(형 클래스)에서 random.choice 라
    프로세스마다(해시 씨앗 · 클래스 주소) 결과가 달라진다(재현 실패 실측: 같은 씨앗 133 vs 140 고유 수식)."""
    if len(ind1) < 2 or len(ind2) < 2:
        return ind1, ind2
    t1, t2 = {}, {}
    for i, n in enumerate(ind1[1:], 1):
        t1.setdefault(n.ret, []).append(i)
    for i, n in enumerate(ind2[1:], 1):
        t2.setdefault(n.ret, []).append(i)
    common = sorted(set(t1) & set(t2), key=lambda t: t.__name__)
    if common:
        ty = random.choice(common)
        i1, i2 = random.choice(t1[ty]), random.choice(t2[ty])
        s1, s2 = ind1.searchSubtree(i1), ind2.searchSubtree(i2)
        ind1[s1], ind2[s2] = ind2[s2], ind1[s1]
    return ind1, ind2


def to_tuple(ind):
    """DEAP 전위 표기 → 중첩 튜플."""
    it = iter(ind)

    def rec():
        n = next(it)
        if isinstance(n, gp.Terminal):
            return n.value
        return (n.name, *[rec() for _ in range(n.arity)])
    return rec()


def from_tuple(e, pset):
    """중첩 튜플 → DEAP 개체(이어 받기 · 초기 개체 주입)."""
    prims = {p.name: p for lst in pset.primitives.values() for p in lst}
    terms = {}
    for lst in pset.terminals.values():
        for t in lst:
            terms[t.value] = t
    out = []

    def rec(x):
        if isinstance(x, tuple):
            out.append(prims[x[0]]); [rec(c) for c in x[1:]]
        else:
            out.append(terms[x])
    rec(e)
    return creator.Individual(out)


def _setup_creator():
    if not hasattr(creator, "FitnessMax"):
        creator.create("FitnessMax", base.Fitness, weights=(1.0,))
    if not hasattr(creator, "Individual"):
        creator.create("Individual", gp.PrimitiveTree, fitness=creator.FitnessMax)


class Evolution:
    """한 창(해 · 절차 변형)의 진화. panel = 창 끝에서 자른 패널(그 뒤 데이터 없음)."""

    def __init__(self, cfg, panel, train_m, val_m, ledger_fh, tag: dict, evo_cfg: dict, seed: int, cache_mb: float):
        _setup_creator()
        self.cfg, self.p, self.tm, self.vm = cfg, panel, train_m, val_m
        self.led, self.tag, self.E = ledger_fh, tag, evo_cfg
        self.rng_seed = seed
        self.pset = build_pset(cfg)
        self.ev = O.Evaluator(panel.fields, cache_mb)
        self.memo = {}           # 해시 → (적합도, 레코드)
        self.signals = {}        # 해시 → 월말 신호(M,N) — 선택 단계 상관 계산용(상위만 남김)
        self.n_seen = 0
        self.n_degenerate = 0
        self.n_over_limit = 0
        G = cfg["grammar"]
        self.max_depth, self.max_nodes = G["max_depth"], G["max_nodes"]
        tb = base.Toolbox()
        tb.register("expr", gen_half, pset=self.pset, min_=G["init_depth"][0], max_=G["init_depth"][1])
        tb.register("individual", tools.initIterate, creator.Individual, tb.expr)
        tb.register("population", tools.initRepeat, list, tb.individual)
        tb.register("select", tools.selTournament, tournsize=evo_cfg["tournament"])
        tb.register("mate", cx_one_point)
        tb.register("expr_mut", gen_full, min_=0, max_=2)
        tb.register("mut_sub", gp.mutUniform, expr=tb.expr_mut, pset=self.pset)
        tb.register("mut_node", gp.mutNodeReplacement, pset=self.pset)
        self.tb = tb

    # ------------------------------------------------------------ 평가
    def _limits_ok(self, e):
        return O.depth(e) <= self.max_depth and O.nodes(e) <= self.max_nodes

    def evaluate(self, ind, gen, origin):
        raw = to_tuple(ind)
        self.n_seen += 1
        F = self.cfg["fitness"]
        try:
            c = O.canon(raw)
        except O.Degenerate as ex:
            self.n_degenerate += 1          # 퇴화 수식 = 시행 아님(원장 행 없음 · 세대 요약에 개수만)
            return F["invalid_fitness"], None
        if not self._limits_ok(raw):
            self.n_over_limit += 1
            return F["invalid_fitness"], None
        hh = O.h(c)
        if hh in self.memo:
            return self.memo[hh][0], hh
        t0 = time.perf_counter()
        rec = {"type": "trial", **self.tag, "gen": gen, "origin": origin, "hash": hh, "expr": O.to_str(c),
               "expr_raw": O.to_str(raw), "skeleton": O.skeleton(c), "nodes": O.nodes(c), "depth": O.depth(c)}
        if not isinstance(c, tuple) and c not in self.p.fields:
            fit = F["invalid_fitness"]; rec.update(status="invalid", reason="terminal")
        else:
            try:
                X = self.ev.eval(c)
                S = X[self.p.me_idx]
                mt = metrics(self.p, S, self.tm, self.cfg["portfolio"])
                mv = metrics(self.p, S, self.vm, self.cfg["portfolio"])
                rho, rho_all = std_corr(self.p, S, self.tm)
                rec.update(train=mt, val=mv, std_corr_max=rho, std_corr=rho_all)
                if mt["coverage"] < F["coverage_min"] or not np.isfinite(mt.get("alpha_ir", np.nan)):
                    fit = F["invalid_fitness"]; rec["status"] = "low_coverage" if mt["coverage"] < F["coverage_min"] else "no_metric"
                else:
                    fit = (mt["alpha_ir"] - F["parsimony_per_node"] * O.nodes(c)
                           - F["std_factor_corr_penalty"] * max(0.0, rho - F["std_factor_corr_free"]))
                    rec["status"] = "ok"
            except Exception as ex:  # 수치 실패 = 무효 기록(조용히 버리지 않는다)
                fit = F["invalid_fitness"]; rec.update(status="error", reason=repr(ex)[:200])
        rec["fitness"] = float(fit)
        rec["eval_ms"] = round((time.perf_counter() - t0) * 1000, 1)
        self.memo[hh] = (float(fit), rec)
        self.led.write(json.dumps(clean(rec), ensure_ascii=False, default=_js) + "\n")
        return float(fit), hh

    def _eval_pop(self, pop, gen, origin):
        n_new0 = len(self.memo)
        for ind in pop:
            if not ind.fitness.valid:
                f, hh = self.evaluate(ind, gen, getattr(ind, "origin", origin))
                ind.fitness.values = (f,)
                ind.hash = hh
        return len(self.memo) - n_new0

    # ------------------------------------------------------------ 진화
    def run(self, inherited=()):
        random.seed(self.rng_seed)
        E = self.E
        Pn, Gn = E["population"], E["generations"]
        n_inh = min(len(inherited), int(round(self.cfg["walkforward"]["inherit_frac"] * Pn)))
        pop = []
        for e in list(inherited)[:n_inh]:
            ind = from_tuple(e, self.pset); ind.origin = "inherited"; pop.append(ind)
        rest = self.tb.population(n=Pn - len(pop))
        for ind in rest:
            ind.origin = "init"
        pop += rest
        hof = tools.HallOfFame(E["hall_of_fame"])
        t0 = time.perf_counter()
        nn = self._eval_pop(pop, 0, "init")
        hof.update(pop)
        self._gen_summary(0, pop, nn, t0)
        for g in range(1, Gn + 1):
            off = [self.tb.clone(i) for i in self.tb.select(pop, len(pop) - len(hof))]
            for i in range(1, len(off), 2):
                if random.random() < E["p_crossover"]:
                    off[i - 1], off[i] = self.tb.mate(off[i - 1], off[i])
                    del off[i - 1].fitness.values, off[i].fitness.values
            for i in range(len(off)):
                if random.random() < E["p_mutation"]:
                    m = self.tb.mut_sub if random.random() < 0.7 else self.tb.mut_node
                    off[i], = m(off[i])
                    del off[i].fitness.values
            for o in off:
                o.origin = "offspring"
            nn = self._eval_pop(off, g, "offspring")
            pop = off + [self.tb.clone(h_) for h_ in hof]   # 엘리트 = 명예의 전당
            hof.update(pop)
            self._gen_summary(g, pop, nn, t0)
        return hof

    def _gen_summary(self, g, pop, n_new, t0):
        fits = [i.fitness.values[0] for i in pop]
        rec = {"type": "gen_summary", **self.tag, "gen": g, "pop": len(pop), "n_new_unique": n_new,
               "n_unique_total": len(self.memo), "n_seen_total": self.n_seen,
               "n_degenerate_total": self.n_degenerate, "n_over_limit_total": self.n_over_limit,
               "fit_max": float(np.max(fits)), "fit_median": float(np.median(fits)),
               "cache_mb": round(self.ev.cache_bytes / 2**20), "elapsed_s": round(time.perf_counter() - t0, 1)}
        self.led.write(json.dumps(clean(rec), ensure_ascii=False) + "\n")
        self.led.flush()


def clean(o):
    """NaN · inf → null(엄격 JSON)."""
    if isinstance(o, dict):
        return {k: clean(v) for k, v in o.items()}
    if isinstance(o, (list, tuple)):
        return [clean(v) for v in o]
    if isinstance(o, (float, np.floating)):
        return float(o) if np.isfinite(o) else None
    if isinstance(o, np.integer):
        return int(o)
    return o


def _js(o):
    if isinstance(o, (np.floating,)):
        return None if not np.isfinite(o) else float(o)
    if isinstance(o, (np.integer,)):
        return int(o)
    return str(o)
