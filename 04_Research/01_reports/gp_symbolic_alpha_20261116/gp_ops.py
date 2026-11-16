"""gp_ops.py — 연산자 집합 · 수식 정규화 · 평가기 (gpa_v2 · 2026-11-16)

수식 표현 = 중첩 튜플: 단말 = 문자열(필드 이름) · 창 = int · 노드 = (연산자, 자식...).
  예) ("ts_corr", ("cs_rank","volume"), "close", 10)  ==  ts_corr(cs_rank(volume), close, 10)

연산자(문헌 기준점: Kakushadze 2016 '101 Formulaic Alphas' 부록 A 함수 정의 · AlphaGen(Yu et al. KDD 2023) 표 4):
  단면 단항  neg abs slog ssqrt cs_rank cs_zscore     — 그날 행(단면)만 본다
  이항      add sub mul div                         — 원소별
  시계열 단항 ts_mean ts_std ts_rank ts_min ts_max ts_delta ts_delay ts_decay_linear (x, d)
  시계열 이항 ts_corr ts_cov (x, y, d)
PIT: 모든 시계열 연산 = 같은 종목의 t, t−1, …, t−d+1 행만(뒤쪽 창 · 미래 shift 없음). 단면 연산 = 그 날짜 행만.
  자가 시험 = gp_selftest.py(미래 행을 무작위로 바꿔도 과거 행 값이 비트 단위로 같아야 한다).
극단치(README §극단치): 나눗셈 분모 |x| < eps → NA(1 로 바꾸지 않는다) · slog = sign·log1p|x| · ssqrt = sign·sqrt|x| ·
  거듭제곱 연산자 없음(mul 중첩만 · mul 뒤 단면 윈저가 상한) · 노드 출력의 비유한값 → NA · mul · div · ts_delta 출력은 날짜별 1/99 윈저.
"""
from __future__ import annotations

import hashlib
from collections import OrderedDict

import bottleneck as bn
import numpy as np

from gp_data import cs_winsor

F32 = np.float32

UNARY = ("neg", "abs", "slog", "ssqrt", "cs_rank", "cs_zscore")
BINARY = ("add", "sub", "mul", "div")
TS_UNARY = ("ts_mean", "ts_std", "ts_rank", "ts_min", "ts_max", "ts_delta", "ts_delay", "ts_decay_linear")
TS_BINARY = ("ts_corr", "ts_cov")
COMMUTATIVE = {"add", "mul", "ts_corr", "ts_cov"}
# 그날 단면에서 엄격 증가(순위 보존) — 뿌리에 있으면 상위 25종 선택 · 순위 IC 가 같다 → 정규화 때 벗긴다
ROOT_MONOTONE = {"cs_rank", "cs_zscore", "slog", "ssqrt"}
ODD = {"slog", "ssqrt"}  # f(−x) = −f(x)

_CFG = {"min_frac": 0.75, "eps": 1e-10, "q": (0.01, 0.99), "winsor_after": {"mul", "div", "ts_delta"},
        "log_terms": set(), "log_levels": {"LogSize", "LogFloatCap", "LogAmount"}, "row_const": {"LogBMRet"}}


def configure(grammar: dict) -> None:
    _CFG["min_frac"] = float(grammar["ts_min_count_frac"])
    _CFG["eps"] = float(grammar["div_eps"])
    _CFG["q"] = tuple(grammar["winsor_q"])
    _CFG["winsor_after"] = set(grammar["winsor_after"])
    _CFG["log_terms"] = set(grammar.get("terminals_log", []))
    dg = grammar.get("degenerate", {})
    _CFG["log_levels"] = set(dg.get("ssqrt_on_log_level", _CFG["log_levels"]))
    _CFG["row_const"] = set(dg.get("row_constant_terminal", _CFG["row_const"]))


def _mc(d: int) -> int:
    return max(2, int(np.ceil(_CFG["min_frac"] * d)))


def _fin(a: np.ndarray) -> np.ndarray:
    a = np.asarray(a, dtype=F32)
    a[~np.isfinite(a)] = np.nan
    return a


# ---------------------------------------------------------------- 원소별 · 단면
def op_neg(x): return -x
def op_abs(x): return np.abs(x)
def op_slog(x): return np.sign(x) * np.log1p(np.abs(x))
def op_ssqrt(x): return np.sign(x) * np.sqrt(np.abs(x))
def op_add(x, y): return x + y
def op_sub(x, y): return x - y
def op_mul(x, y):
    with np.errstate(over="ignore", invalid="ignore"):
        return (x.astype(np.float64) * y).astype(F32)


def op_div(x, y):
    with np.errstate(divide="ignore", invalid="ignore", over="ignore"):
        out = x.astype(np.float64) / y
    out[np.abs(y) < _CFG["eps"]] = np.nan
    return out.astype(F32)


def op_cs_rank(x):
    """그날 단면 백분위 순위(동률 = 평균 순위) ∈ (0, 1]."""
    r = bn.nanrankdata(x, axis=1)
    n = np.sum(np.isfinite(x), axis=1, keepdims=True)
    with np.errstate(invalid="ignore", divide="ignore"):
        return (r / n).astype(F32)


def op_cs_zscore(x):
    """단면 z — 그날 1/99 윈저 뒤 평균 · 표준편차(한 종목 극단치가 다른 종목 z 를 눌러 버리지 않게)."""
    x = cs_winsor(x, _CFG["q"])
    m = bn.nanmean(x, axis=1)[:, None]
    s = bn.nanstd(x, axis=1)[:, None]
    with np.errstate(invalid="ignore", divide="ignore"):
        out = (x - m) / s
    out[~(s > 0).repeat(x.shape[1], axis=1)] = np.nan
    return out


# ---------------------------------------------------------------- 시계열(뒤쪽 창 · axis=0 = 날짜)
def op_ts_mean(x, d): return bn.move_mean(x, d, min_count=_mc(d), axis=0)
def op_ts_std(x, d): return bn.move_std(x.astype(np.float64), d, min_count=_mc(d), axis=0).astype(F32)
def op_ts_min(x, d): return bn.move_min(x, d, min_count=_mc(d), axis=0)
def op_ts_max(x, d): return bn.move_max(x, d, min_count=_mc(d), axis=0)
def op_ts_rank(x, d):
    """창 안에서 오늘 값의 순위 — bottleneck move_rank(−1~1) 를 (0,1] 로 옮긴다(오늘 값이 NaN 이면 NaN)."""
    return ((bn.move_rank(x, d, min_count=_mc(d), axis=0) + 1.0) / 2.0).astype(F32)


def op_ts_delay(x, d):
    out = np.full_like(x, np.nan)
    if d < x.shape[0]:
        out[d:] = x[:-d]
    return out


def op_ts_delta(x, d): return x - op_ts_delay(x, d)


def op_ts_decay_linear(x, d):
    """가중 이동평균, 가중치 d, d−1, …, 1(오늘 = d) · 결측은 빼고 가중치 재정규화(Kakushadze 2016 decay_linear).
    누적합 두 개로 O(T·N): Σ_{j∈창} (d − (t − j)) x_j = (d − t) Σ x_j + Σ j·x_j."""
    T = x.shape[0]
    fin = np.isfinite(x)
    xv = np.where(fin, x, 0.0).astype(np.float64)
    w1 = fin.astype(np.float64)
    j = np.arange(T, dtype=np.float64)[:, None]

    def wsum(v):
        c0 = np.cumsum(v, axis=0)
        c1 = np.cumsum(v * j, axis=0)
        s0 = c0.copy(); s1 = c1.copy()
        s0[d:] -= c0[:-d]; s1[d:] -= c1[:-d]
        return (d - j) * s0 + s1
    num = wsum(xv)
    den = wsum(w1)
    cnt = bn.move_sum(w1, d, min_count=1, axis=0)
    with np.errstate(invalid="ignore", divide="ignore"):
        out = num / den
    out[~(cnt >= _mc(d))] = np.nan
    return out.astype(F32)


def _pair(x, y):
    m = np.isfinite(x) & np.isfinite(y)
    return np.where(m, x, np.nan).astype(np.float64), np.where(m, y, np.nan).astype(np.float64)


def op_ts_cov(x, y, d):
    a, b = _pair(x, y)
    mc = _mc(d)
    ma = bn.move_mean(a, d, min_count=mc, axis=0); mb = bn.move_mean(b, d, min_count=mc, axis=0)
    mab = bn.move_mean(a * b, d, min_count=mc, axis=0)
    return (mab - ma * mb).astype(F32)


def op_ts_corr(x, y, d):
    a, b = _pair(x, y)
    mc = _mc(d)
    # 창 안 중심화(수준이 큰 계열의 상쇄 오차를 줄이려 float64 · 표준편차는 bottleneck)
    sa = bn.move_std(a, d, min_count=mc, axis=0); sb = bn.move_std(b, d, min_count=mc, axis=0)
    ma = bn.move_mean(a, d, min_count=mc, axis=0); mb = bn.move_mean(b, d, min_count=mc, axis=0)
    mab = bn.move_mean(a * b, d, min_count=mc, axis=0)
    with np.errstate(invalid="ignore", divide="ignore"):
        r = (mab - ma * mb) / (sa * sb)
    r[~((sa > 1e-12 * (np.abs(ma) + 1)) & (sb > 1e-12 * (np.abs(mb) + 1)))] = np.nan
    return np.clip(r, -1, 1).astype(F32)


COL_BLOCK = 1024   # 시계열 연산은 종목(열)마다 독립 → 열 묶음으로 나눠 float64 임시 배열의 메모리 정점을 줄인다(값은 같다)


def _colchunk(fn, n_series):
    def run(*args):
        xs, rest = args[:n_series], args[n_series:]
        N = xs[0].shape[1]
        if N <= COL_BLOCK:
            return np.asarray(fn(*xs, *rest), dtype=F32)
        out = np.empty(xs[0].shape, dtype=F32)
        for j in range(0, N, COL_BLOCK):
            out[:, j:j + COL_BLOCK] = fn(*[np.asarray(x[:, j:j + COL_BLOCK]) for x in xs], *rest)
        return out
    run.__name__ = fn.__name__
    return run


OPS = {k: globals()["op_" + k] for k in UNARY + BINARY}
OPS.update({k: _colchunk(globals()["op_" + k], 1) for k in TS_UNARY})
OPS.update({k: _colchunk(globals()["op_" + k], 2) for k in TS_BINARY})
ARITY = {**{k: 1 for k in UNARY}, **{k: 2 for k in BINARY}, **{k: 2 for k in TS_UNARY}, **{k: 3 for k in TS_BINARY}}


# ---------------------------------------------------------------- 정규화 · 해시
class Degenerate(Exception):
    """상수 · 항등으로 무너지는 수식(sub(x,x) · div(x,x) · ts_corr(x,x,d) …) — 시행으로 세지 않고 무효 기록."""


def to_str(e) -> str:
    if isinstance(e, tuple):
        return e[0] + "(" + ",".join(to_str(c) for c in e[1:]) + ")"
    return str(e)


def canon(e, root: bool = True):
    """동치 수식 정규화 — 같은 값(또는 같은 상위 25종)을 내는 표기를 한 표기로 모은다."""
    if not isinstance(e, tuple):
        return e
    op = e[0]
    ch = [canon(c, root=False) for c in e[1:]]
    # 규칙
    if op == "neg" and isinstance(ch[0], tuple) and ch[0][0] == "neg":
        return ch[0][1] if not root else canon(ch[0][1], root=True)
    if op == "abs" and isinstance(ch[0], tuple) and ch[0][0] in ("abs", "neg"):
        return canon(("abs", ch[0][1]), root)   # abs(abs x) = abs(neg x) = abs x
    if op in ODD and isinstance(ch[0], tuple) and ch[0][0] == "neg":
        return canon(("neg", (op, ch[0][1])), root)
    if op in ("cs_rank", "cs_zscore") and isinstance(ch[0], tuple) and ch[0][0] in ("cs_rank", "cs_zscore"):
        if op == "cs_rank" or ch[0][0] == "cs_zscore":   # rank(rank x)=rank x · rank(z x)=rank x · z(z x)=z x
            return canon((op, ch[0][1]), root)
    if op in ("ts_rank", "cs_rank", "ts_min", "ts_max") and isinstance(ch[0], tuple) and ch[0][0] in ODD:
        # 엄격 증가 변환 아래의 순위 · 최솟값 위치는 같다: rank(slog x) = rank(x) · ts_rank(ssqrt x, d) = ts_rank(x, d)
        if op in ("ts_rank", "cs_rank"):
            return canon((op, ch[0][1], *ch[1:]), root)
    # 로그 단말 위 이중 변환(gpa_v2 · README §2): slog(Log*) = 로그의 로그 · 수익률형은 log1p|x| ≈ |x|(작은 x) → 거의 항등
    #   ssqrt(로그 수준 LogSize · LogFloatCap · LogAmount) = 좁은 범위(≈ 20~35)에서 거의 선형 → 둘 다 무효(시행으로 세지 않음)
    if op == "slog" and not isinstance(ch[0], tuple) and ch[0] in _CFG["log_terms"]:
        raise Degenerate("slog(log terminal)")
    if op == "ssqrt" and not isinstance(ch[0], tuple) and ch[0] in _CFG["log_levels"]:
        raise Degenerate("ssqrt(log level)")
    # 날마다 모든 종목이 같은 값인 단말(LogBMRet)에 단면 연산 = 상수
    if op in ("cs_rank", "cs_zscore") and _terms(ch[0]) <= _CFG["row_const"]:
        raise Degenerate("cs op on row-constant")
    if op in ("sub", "div") and to_str(ch[0]) == to_str(ch[1]):
        raise Degenerate(op + "(x,x)")
    if op in ("ts_corr", "ts_cov") and to_str(ch[0]) == to_str(ch[1]):
        raise Degenerate(op + "(x,x,d)")
    if op in COMMUTATIVE:
        n_ser = 2
        ser = sorted(ch[:n_ser], key=to_str)
        ch = ser + ch[n_ser:]
    out = (op, *ch)
    if root:
        while isinstance(out, tuple) and out[0] in ROOT_MONOTONE:
            out = out[1]
        # 뿌리 neg 아래의 단조 증가 변환도 순서를 바꾸지 않는다: neg(rank x) ~ neg(x)
        while isinstance(out, tuple) and out[0] == "neg" and isinstance(out[1], tuple) and out[1][0] in ROOT_MONOTONE:
            out = ("neg", out[1][1])
        if isinstance(out, tuple) and out[0] == "neg" and isinstance(out[1], tuple) and out[1][0] == "neg":
            out = out[1][1]
        if not isinstance(out, tuple) and isinstance(out, int):
            raise Degenerate("window-only")
        if _terms(out) <= _CFG["row_const"]:
            raise Degenerate("row-constant signal")   # 단면 순위가 전부 동률 — 신호가 아니다
    return out


def _terms(e) -> set:
    if isinstance(e, tuple):
        out = set()
        for c in e[1:]:
            out |= _terms(c)
        return out
    return set() if isinstance(e, int) else {e}


def h(e) -> str:
    return hashlib.sha1(to_str(e).encode()).hexdigest()[:16]


def nodes(e) -> int:
    return 1 + sum(nodes(c) for c in e[1:]) if isinstance(e, tuple) else 1


def depth(e) -> int:
    # 창(int)은 깊이에 넣지 않는다(연산자의 인자)
    if not isinstance(e, tuple):
        return 0
    return 1 + max([depth(c) for c in e[1:] if not isinstance(c, int)] or [0])


def skeleton(e) -> str:
    """구조(연산 골격) — 단말은 종류(P=가격 · F=재무), 창은 W 로 지운다. 해 간 '같은 연산 구조 유지율'용."""
    if isinstance(e, tuple):
        return e[0] + "(" + ",".join(skeleton(c) for c in e[1:]) + ")"
    if isinstance(e, int):
        return "W"
    return "F" if str(e).startswith("fr_") else "P"


# ---------------------------------------------------------------- 평가기(부분식 캐시)
class Evaluator:
    """패널 필드 위에서 수식을 평가. 정규화된 부분식 문자열을 키로 LRU 캐시(메모리 상한 MB)."""

    def __init__(self, fields: dict, cache_mb: float = 500.0):
        self.f = fields
        self.cache = OrderedDict()
        self.cache_bytes = 0
        self.cap = cache_mb * 2**20
        self.hits = 0
        self.miss = 0

    def _put(self, k, v):
        if v.nbytes > self.cap / 4:
            return
        self.cache[k] = v
        self.cache_bytes += v.nbytes
        while self.cache_bytes > self.cap and self.cache:
            _, old = self.cache.popitem(last=False)
            self.cache_bytes -= old.nbytes

    def eval(self, e):
        if not isinstance(e, tuple):
            return self.f[e]
        k = to_str(e)
        if k in self.cache:
            self.cache.move_to_end(k)
            self.hits += 1
            return self.cache[k]
        self.miss += 1
        op = e[0]
        args = [self.eval(c) if not isinstance(c, int) else c for c in e[1:]]
        with np.errstate(all="ignore"):
            out = _fin(OPS[op](*args))
        if op in _CFG["winsor_after"]:
            out = cs_winsor(out, _CFG["q"])
        self._put(k, out)
        return out

    def eval_rows(self, e, rows):
        """수식 값을 지정 행(월말)만 돌려준다(전체 평가 후 행 추출 — 시계열 연산은 전체 이력이 필요)."""
        return self.eval(e)[rows]
