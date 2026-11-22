"""aif_common.py — AI 팩터 연구(독립 연구) 파이썬 공통 층: 경로 · 설정 · 공통 틀 · 상태 파일 · 확정 저장.

공통 틀(Frame)은 R 측정기(aif_market)가 내보낸 것(run/03_export_frame.R)을 그대로 읽는다 —
거래일 · 종목 순서 · 월말 신호일 · 유니버스 멤버 표 · 앞으로의 수익이 측정기와 같다. 파이썬은 유니버스를 다시 판정하지 않는다.
포트폴리오 수익은 파이썬에서 만들지 않는다(팩터 점수만 내고, 성과는 R 측정기가 Return.portfolio 로 잰다).
상태 파일(status.json)의 필드는 R 쪽 aif_status.R 과 같다.
"""
import ctypes
import datetime as dt
import json
import os
import sys

import numpy as np

AIF_DIR_REL = "04_Research/01_reports/ai_factor_research_20261122"


def root():
    r = os.environ.get("AIF_ROOT") or os.environ.get("QM_ROOT") or ""
    if not r or not os.path.isdir(os.path.join(r, "02_Infrastructure")):
        raise RuntimeError("[aif] 저장소 루트를 찾지 못했다(AIF_ROOT 또는 QM_ROOT)")
    return r.replace("\\", "/").rstrip("/")


def rdir():
    return root() + "/" + AIF_DIR_REL


_CFG = None


def cfg():
    global _CFG
    if _CFG is None:
        with open(rdir() + "/aif_config.json", encoding="utf-8") as fh:
            _CFG = json.load(fh)
    return _CFG


SMOKE = {"on": False}          # 시험 실행 — 산출을 "<이름>_smoke" 폴더로 돌린다(본 실행의 체크포인트 · 팩터 파일을 건드리지 않는다)


def smoke_name(name):
    return name + "_smoke" if SMOKE["on"] else name


def out(*parts):
    return "/".join([root(), cfg()["paths"]["out_cache"], *parts])


def results(*parts):
    return "/".join([root(), cfg()["paths"]["results"], *parts])


def log(msg, *a):
    print("[aif %s] %s" % (dt.datetime.now().strftime("%H:%M:%S"), msg % a if a else msg), flush=True)


def write_atomic(path, write_fn):
    """임시 파일에 쓰고 이름을 바꾼다(쓰다 끊겨도 반쪽 파일이 남지 않는다)."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    write_fn(tmp)
    os.replace(tmp, path)
    return path


def write_json(obj, path):
    def w(p):
        with open(p, "w", encoding="utf-8") as fh:
            json.dump(obj, fh, ensure_ascii=False, indent=2, default=str)
    return write_atomic(path, w)


def load_ckpt(path, fp):
    """체크포인트(npz)를 읽어 dict 로 돌려준다 — 파일이 없거나 판 표식(fp)이 다르면 None.
    파일은 읽자마자 닫는다(윈도에서는 열려 있는 파일을 덮어쓸 수 없어, 열어 둔 채 다시 쓰면 확정 저장이 실패한다)."""
    if not os.path.exists(path):
        return None
    try:
        with np.load(path, allow_pickle=True) as z:
            if str(z["fp"]) != fp:
                return None
            return {k: z[k] for k in z.files}
    except Exception:  # noqa: BLE001 — 깨진 체크포인트는 없는 것으로 본다
        return None


def read_json(path, default=None):
    try:
        with open(path, encoding="utf-8") as fh:
            return json.load(fh)
    except Exception:  # noqa: BLE001 — 없거나 쓰는 중인 파일
        return default


def low_priority():
    """프로세스 우선순위를 '보통 이하'로 낮춘다(감시 셸이 이미 낮춰 띄우지만, 직접 띄울 때도 같게)."""
    try:
        k = ctypes.WinDLL("kernel32")
        k.GetCurrentProcess.restype = ctypes.c_void_p                  # 가짜 핸들(-1)이 64비트에서 잘리지 않게 형을 밝힌다
        k.SetPriorityClass.argtypes = [ctypes.c_void_p, ctypes.c_uint32]
        k.SetPriorityClass(k.GetCurrentProcess(), 0x00004000)          # BELOW_NORMAL_PRIORITY_CLASS
    except Exception:  # noqa: BLE001
        pass


def threads():
    return int(os.environ.get("AIF_THREADS", "1"))


# ── 상태 파일 ────────────────────────────────────────────────────────────────
def _now():
    return dt.datetime.now().strftime("%Y-%m-%d %H:%M:%S")


def status_read():
    return read_json(out("status.json"), {"stage_progress": {}}) or {"stage_progress": {}}


def status_set(**kw):
    st = status_read()
    for k, v in kw.items():
        if v is None:
            st.pop(k, None)
        else:
            st[k] = v
    st["updated_at"] = _now()
    write_json(st, out("status.json"))
    return st


def stage_begin(key, unit_total, unit_name, part_from=0.0, part_to=1.0):
    if SMOKE["on"]:                                       # 시험 실행은 진행 상태를 바꾸지 않는다
        return
    st = status_read()
    sp = st.get("stage_progress") or {}
    sp[key] = max(float(sp.get(key) or 0), part_from)
    started = st.get("stage_started_at") if st.get("stage_key") == key and st.get("stage_started_at") else _now()
    status_set(stage_key=key, stage_state="running", wait_reason=None, error=None, unit_done=0, unit_total=int(unit_total), unit_name=unit_name,
               detail=None, part_from=part_from, part_to=part_to, threads=threads(), stage_started_at=started, run_started_at=_now(),
               stage_progress=sp, pid=os.getpid())


def stage_unit(unit_done, detail=None):
    if SMOKE["on"]:
        return
    st = status_read()
    key = st.get("stage_key")
    a, b = float(st.get("part_from") or 0), float(st.get("part_to") or 1)
    f = a + (b - a) * unit_done / max(1, int(st.get("unit_total") or 1))
    sp = st.get("stage_progress") or {}
    sp[key] = min(1.0, max(float(sp.get(key) or 0), f))
    status_set(unit_done=int(unit_done), detail=detail, stage_state="running", stage_progress=sp)


def stage_end(done=True):
    if SMOKE["on"]:
        return
    st = status_read()
    key = st.get("stage_key")
    sp = st.get("stage_progress") or {}
    sp[key] = 1.0 if done else float(st.get("part_to") or 1)
    status_set(stage_state="done" if done else "running", stage_progress=sp, detail=None)


# ── 공통 틀 ──────────────────────────────────────────────────────────────────
class Frame:
    """R 이 내보낸 공통 틀. 배열은 모두 행 우선 · float32(결측 = NaN). 큰 것은 memmap 으로 연다."""

    def __init__(self, path=None):
        import pandas as pd
        p = path or out("frame")
        meta = read_json(p + "/frame.json")
        if not meta:
            raise RuntimeError("[aif] 공통 틀이 없다 — run/03_export_frame.R 을 먼저 돌린다: " + p)
        self.path, self.meta = p, meta
        self.nd, self.nt, self.ns = int(meta["n_days"]), int(meta["n_tickers"]), int(meta["n_signals"])
        self.dates = pd.read_csv(p + "/dates.csv")["Date"].to_numpy().astype("datetime64[D]")
        self.tickers = pd.read_csv(p + "/tickers.csv")["Ticker"].astype(str).to_list()
        sg = pd.read_csv(p + "/signals.csv")
        self.sig_dates = sg["sig_date"].to_numpy().astype("datetime64[D]")
        self.sig_idx = sg["sig_idx"].to_numpy().astype(np.int64)          # dates 안 위치(0 부터)
        self.hold_a, self.hold_b = sg["hold_a"].to_numpy().astype(np.int64), sg["hold_b"].to_numpy().astype(np.int64)
        self.hold_ok = sg["hold_ok"].to_numpy().astype(bool)
        if len(self.dates) != self.nd or len(self.tickers) != self.nt or len(self.sig_dates) != self.ns:
            raise RuntimeError("[aif] 공통 틀의 크기가 설명 파일과 다르다")
        self.tix = {t: j for j, t in enumerate(self.tickers)}
        self.mem = np.fromfile(p + "/mem.u8", dtype=np.uint8).reshape(self.ns, self.nt).astype(bool)

    def fwd(self, h):
        return np.memmap(self.path + "/fwd_%d.f32" % h, dtype="<f4", mode="r", shape=(self.ns, self.nt))

    def ret_daily(self):
        return np.memmap(self.path + "/ret_daily.f32", dtype="<f4", mode="r", shape=(self.nd, self.nt))

    def bm_daily(self):
        return np.fromfile(self.path + "/bm_daily.f32", dtype="<f4")

    def date_index(self, d):
        """날짜 배열 → dates 안 위치(없으면 -1)."""
        d = np.asarray(d).astype("datetime64[D]")
        i = np.searchsorted(self.dates, d)
        i = np.clip(i, 0, self.nd - 1)
        return np.where(self.dates[i] == d, i, -1)

    def ticker_index(self, t):
        return np.fromiter((self.tix.get(x, -1) for x in t), dtype=np.int64, count=len(t))


def rank_pm1(x, mask=None):
    """횡단면 순위 → (−1, 1). x = [행 × 종목] · 행마다 유한값(그리고 mask)만 순위 · 동순위 평균 · 나머지 NaN."""
    from scipy.stats import rankdata
    x = np.asarray(x, dtype=np.float64)
    ok = np.isfinite(x) if mask is None else (np.isfinite(x) & mask)
    o = np.full(x.shape, np.nan, dtype=np.float32)
    for i in range(x.shape[0]):
        k = ok[i]
        n = int(k.sum())
        if n >= 2:
            o[i, k] = (2.0 * (rankdata(x[i, k], method="average") - 1.0) / (n - 1.0) - 1.0).astype(np.float32)
        elif n == 1:
            o[i, k] = 0.0
    return o


def rank_ic(score, fwd, mask, min_n=30):
    """달별 순위 IC(스피어먼). score · fwd · mask = [신호 × 종목]. 종목 수가 min_n 미만인 달은 NaN."""
    from scipy.stats import rankdata
    ns = score.shape[0]
    ic = np.full(ns, np.nan)
    for s in range(ns):
        k = mask[s] & np.isfinite(score[s]) & np.isfinite(fwd[s])
        if int(k.sum()) >= min_n:
            a, b = rankdata(score[s, k]), rankdata(fwd[s, k])
            a -= a.mean()
            b -= b.mean()
            den = np.sqrt((a * a).sum() * (b * b).sum())
            ic[s] = (a * b).sum() / den if den > 0 else np.nan
    return ic


def december_signals(frame, burn_years):
    """해마다 12월 신호의 위치 dict[해] 와, 첫 burn_years 해를 예열로 둔 뒤의 선택 해 목록.
    선택 해 Y 의 12월 신호일에 그때까지의 자료로 고르고, 그 신호(12월 말) ~ 다음 해 11월 말 신호에 쓴다."""
    ym = [(int(str(d)[:4]), int(str(d)[5:7])) for d in frame.sig_dates]
    dec = {y: s for s, (y, m) in enumerate(ym) if m == 12}
    first = min(y for y, _ in ym)
    return [y for y in sorted(dec) if y >= first + burn_years - 1], dec


def save_factor_panel(path, name, score, frame, mask=None):
    """팩터 점수 [신호 × 종목] → 측정기가 읽는 긴 표(Date · Ticker · Factor_Name · Raw_Value) parquet."""
    import pyarrow as pa
    import pyarrow.parquet as pq
    k = np.isfinite(score) if mask is None else (np.isfinite(score) & mask)
    si, ti = np.nonzero(k)
    tk = np.asarray(frame.tickers, dtype=object)
    tab = pa.table({"Date": pa.array(frame.sig_dates[si].astype("datetime64[ms]")), "Ticker": pa.array(tk[ti], type=pa.string()),
                    "Factor_Name": pa.array([name] * len(si), type=pa.string()), "Raw_Value": pa.array(score[si, ti].astype(np.float64))})
    return write_atomic(path, lambda p: pq.write_table(tab, p, compression="zstd"))


if __name__ == "__main__":
    f = Frame()
    log("공통 틀 — 거래일 %d · 종목 %d · 신호 %d · 멤버 평균 %.0f", f.nd, f.nt, f.ns, f.mem.sum(1).mean())
    sys.exit(0)
