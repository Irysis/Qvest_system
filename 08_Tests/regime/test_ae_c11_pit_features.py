"""test_ae_c11_pit_features.py — AE(D3 게이트) 특성 패널의 C11 가용시점 결합 검사 (2026-09-24 신설 · S5).

대상:
  02_Infrastructure/regime/ae_pit_features.py   (가용시점 결합 빌더 · 표식)
  02_Infrastructure/regime/ae_regime_monthly.py  (운영 러너 — 동결 원본 exec 뒤 build_panel 1함수 교체)
  02_Infrastructure/regime/ae_regime_backfill.py (백필기 — 같은 빌더 · 수리 전 판 기존 행과 섞지 않음)
근거: 04_Research/01_reports/pit_c11_20260924/PIT_C11_verdict_20260924.md V-03·V-02 · ② 계열별 규약
      결정 PIT-C11-REMEDIATION(안 B) · PIT-C11-CONVENTIONS ①(DEXKOUS → ECOS 731Y001)

## 무엇을 재는가 (양방향)
A. 빌더 양성 대조 — 합성 픽스처(값 = 관측일 서수라 결합된 관측일이 값에서 그대로 읽힌다):
   기대값은 판정서 ②에서 손으로 유도했다(NFCI 라벨+6 · STLFSI4 라벨+7 · VIX 다음 한국 거래일 · ECOS lag 0).
B. 위반 주입(빨개져야 한다): 구판 merge_asof(라벨 결합) · 1행 lag · DEXKOUS 경로 · 표식 변조 · 결합 함수 같은 날짜 변조.
C. 러너 통합(sandbox · 실모델 · EPOCHS 만 1로): 주입된 빌더가 **실제로 소비**되는가(빌더를 구판으로 바꾸면 ae_seq
   가 달라진다) · 산출 표식 · 수리 전 판 발행본과의 parity 차단(C11 전환 표지) · ECOS 없는 핀 거부.
D. 백필기: 수리 전 판 기존 행과 섞지 않는다 · 표식 행 위에서는 백필 행도 표식을 단다.
E. 실데이터(읽기 전용): 핀 r1 + 라이브 ECOS 로 빌드 → 자기 검사 0 위반 · 구판 빌더는 위반 다수.

## 실행
  .venv_qvest_ml/Scripts/python.exe 08_Tests/regime/test_ae_c11_pit_features.py
운영 산출물 미접촉(쓰기 = tempfile 디렉터리만 · 실데이터 축은 읽기 전용). 네트워크 미사용.
"""
from __future__ import annotations

import datetime as dt
import os
import shutil
import sys
import tempfile
import traceback

# ── 인터프리터 자기해결 — 배터리는 pandas/torch 없는 python 으로 돈다 (test_ae_monthly_plumbing.py 선례) ──
#   ★없다고 SKIP 하지 않는다 — SKIP 은 '통과'와 겉보기가 같다.
try:
    import pandas as _probe  # noqa: F401
    import torch as _probe_t  # noqa: F401
except ImportError:
    _self_root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    _venv = ""
    for _cand in (_self_root, os.environ.get("CLAUDE_PROJECT_DIR", ""), os.environ.get("QM_ROOT", "")):
        if not _cand:
            continue
        _p = os.path.join(_cand.replace("\\", "/"), ".venv_qvest_ml", "Scripts", "python.exe")
        if os.path.exists(_p):
            _venv = _p
            break
    if _venv and os.environ.get("_AEC11_REEXEC") != "1":
        import subprocess
        sys.exit(subprocess.call([_venv, os.path.abspath(__file__)] + sys.argv[1:],
                                 env=dict(os.environ, _AEC11_REEXEC="1")))
    raise

import numpy as np
import pandas as pd
import pyarrow.parquet as pq

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
REG = os.path.join(ROOT, "02_Infrastructure", "regime")
FROZEN = os.path.join(ROOT, "stage_artifacts", "WT_D20260718_007", "ae_regime_extend.py")
if not os.path.isfile(os.path.join(REG, "ae_pit_features.py")):
    print(f"PROJECT_ROOT 해석 실패 — ae_pit_features.py 없음 (self={ROOT})")
    sys.exit(2)
sys.path.insert(0, REG)
sys.path.insert(0, os.path.join(ROOT, "02_Infrastructure", "data"))
_CWD0 = os.getcwd()
_QM0 = os.environ.get("QM_ROOT")
import fred_availability as fa  # noqa: E402
import ae_pit_features as aepf  # noqa: E402
import ae_regime_monthly as aem  # noqa: E402  (import 시 os.chdir(QM_ROOT) — 아래에서 되돌린다)
os.chdir(_CWD0)

FEATS = ["VIX", "Term_Spread", "KRW_USD", "US_10Y_Yield", "US_2Y_Yield", "StL_Fin_Stress", "Chi_Fin_Cond"]
DAILY_US = ["VIX", "Term_Spread", "US_10Y_Yield", "US_2Y_Yield"]
WEEKLY = ["StL_Fin_Stress", "Chi_Fin_Cond"]
KEY = aepf.rules_regime_key()

PASS, FAIL = 0, 0
FAILS = []


def chk(name, cond, detail=""):
    global PASS, FAIL
    if cond:
        PASS += 1
        print(f"  PASS  {name}" + (f"  — {detail}" if detail else ""))
    else:
        FAIL += 1
        FAILS.append(name)
        print(f"  ★FAIL {name}  {detail}")


def raises(fn, exc=Exception, contains=None):
    try:
        fn()
    except exc as e:  # noqa: BLE001
        return contains is None or contains in str(e)
    except SystemExit as e:
        return exc is SystemExit and (contains is None or str(e.code) == str(contains))
    return False


def ordv(d):
    return float(pd.Timestamp(d).toordinal())


def ofv(v):
    return pd.Timestamp(dt.date.fromordinal(int(round(v))))


# ── 합성 픽스처 ─────────────────────────────────────────────────────────────────
#   값 = 관측일 서수 → 결합된 관측일을 값에서 역산한다. KRW_USD(와이드 = DEXKOUS)는 서수+0.25, ECOS 는 +0.5.
KR_HOLIDAYS = {pd.Timestamp("2008-02-06"), pd.Timestamp("2008-02-07"), pd.Timestamp("2008-02-08")}


def make_fixture(root, start="2003-01-01", end="2010-06-30", seed=7):
    os.makedirs(root, exist_ok=True)
    kr = [d for d in pd.bdate_range(start, end) if d not in KR_HOLIDAYS]
    rng = np.random.default_rng(seed)
    ret = rng.normal(0.0003, 0.012, len(kr))
    close = 1000.0 * np.cumprod(1 + ret)
    pd.DataFrame({"Date": [d.date() for d in kr], "BM_Close": close, "BM_Ret": ret}).to_parquet(
        os.path.join(root, "benchmark.parquet"), index=False)
    us = list(pd.bdate_range(start, end))
    fr = pd.DataFrame({"Date": [d.date() for d in us]})
    for f in DAILY_US:
        fr[f] = [ordv(d) for d in us]
    fr["KRW_USD"] = [ordv(d) + 0.25 for d in us]
    for f in WEEKLY:
        fr[f] = [ordv(d) if d.weekday() == 4 else np.nan for d in us]
    fr.to_parquet(os.path.join(root, "fred_macro_wide.parquet"), index=False)
    pd.DataFrame({"Date": [d.date() for d in kr], "KRW_USD": [ordv(d) + 0.5 for d in kr]}).to_parquet(
        os.path.join(root, aepf.ECOS_KRW_FILE), index=False)
    return kr


def legacy_panel(root, feats=FEATS):
    """구판(동결 원본 build_panel) 재현 — 라벨 결합. 돌연변이·대조용."""
    fr = pq.read_table(os.path.join(root, "fred_macro_wide.parquet")).to_pandas()
    fr["Date"] = pd.to_datetime(fr["Date"])
    sp = aepf.build_kr_spine(os.path.join(root, "benchmark.parquet"))
    m = pd.merge_asof(sp, fr[["Date"] + feats].sort_values("Date"), on="Date", direction="backward")
    cols = aepf.KR_FEATS + feats
    m[cols] = m[cols].ffill()
    return m.dropna(subset=cols).reset_index(drop=True)


def independent_violations(panel, feats, cal):
    """독립 검산 — 값에서 관측일을 역산해 S0 규칙으로 가용일을 다시 잰다(빌더 코드를 거치지 않는다)."""
    n = 0
    for f in feats:
        if f == "KRW_USD":
            continue
        obs = [ofv(v).date() for v in panel[f]]
        rows = [d.date() for d in panel["Date"]]
        n += len(fa.fred_join_violations(rows, obs, f, mode="decision_close", kr_calendar=cal))
    return n


def row(panel, d):
    r = panel[panel["Date"] == pd.Timestamp(d)]
    assert len(r) == 1, f"픽스처 행 없음 {d}"
    return r.iloc[0]


# ══ A. 빌더 양성 대조 ═══════════════════════════════════════════════════════════
def axis_a(tmp):
    print("── A. 빌더 양성 대조 (합성 · 판정서 ② 손 유도 기대값) ──")
    fx = os.path.join(tmp, "fxA")
    kr = make_fixture(fx)
    cal = sorted(set(d.date() for d in kr))
    m, fc = aepf.build_pit_panel(os.path.join(fx, "fred_macro_wide.parquet"), os.path.join(fx, "benchmark.parquet"),
                                 os.path.join(fx, aepf.ECOS_KRW_FILE), FEATS)
    chk("A0 반환형 = (panel, feat_cols) · feat_cols = KR 4 + 해외 7(동결 원본 순서)",
        fc == aepf.KR_FEATS + FEATS and all(c in m.columns for c in fc))
    # 주간 — 라벨 금 2008-03-07: NFCI 가용 목 03-13(+6) · STLFSI4 가용 금 03-14(+7)
    r12, r13, r14 = row(m, "2008-03-12"), row(m, "2008-03-13"), row(m, "2008-03-14")
    chk("A1 NFCI 수 03-12 행 = 전주 라벨 02-29 (03-07분은 목 03-13 공표 전)",
        ofv(r12["Chi_Fin_Cond"]) == pd.Timestamp("2008-02-29"), str(ofv(r12["Chi_Fin_Cond"]).date()))
    chk("A2 NFCI 목 03-13 행 = 라벨 03-07 (라벨+6 가용)",
        ofv(r13["Chi_Fin_Cond"]) == pd.Timestamp("2008-03-07"), str(ofv(r13["Chi_Fin_Cond"]).date()))
    chk("A3 STLFSI4 목 03-13 행 = 02-29 · 금 03-14 행 = 03-07 (라벨+7 가용)",
        ofv(r13["StL_Fin_Stress"]) == pd.Timestamp("2008-02-29")
        and ofv(r14["StL_Fin_Stress"]) == pd.Timestamp("2008-03-07"),
        f"{ofv(r13['StL_Fin_Stress']).date()} / {ofv(r14['StL_Fin_Stress']).date()}")
    # 일간 미국 — 미국 d 종가는 한국 d+1 부터
    r07, r10 = row(m, "2008-03-07"), row(m, "2008-03-10")
    chk("A4 VIX 한국 금 03-07 행 = 미국 목 03-06 · 한국 월 03-10 행 = 미국 금 03-07",
        ofv(r07["VIX"]) == pd.Timestamp("2008-03-06") and ofv(r10["VIX"]) == pd.Timestamp("2008-03-07"))
    # 한국 연휴(02-06~08) 뒤 첫 거래일 02-11: 미국 02-08(금)까지 가용
    r211 = row(m, "2008-02-11")
    chk("A5 한국 연휴 뒤 02-11 행 = 미국 02-08 (가용일은 한국 거래일 격자에서 잰다)",
        ofv(r211["VIX"]) == pd.Timestamp("2008-02-08"), str(ofv(r211["VIX"]).date()))
    # 원/달러 — ECOS(서수+0.5), DEXKOUS(서수+0.25) 아님, lag 0
    krw_frac = (m["KRW_USD"] - np.floor(m["KRW_USD"])).round(3)
    chk("A6 원/달러 = ECOS 731Y001 (전 행 +0.5 표지) · DEXKOUS 값 0행",
        bool((krw_frac == 0.5).all()), f"{int((krw_frac == 0.25).sum())}행 DEXKOUS")
    chk("A7 원/달러 lag 0 — 한국 t 행 = ECOS t 값",
        bool((m["KRW_USD"].apply(lambda v: pd.Timestamp(dt.date.fromordinal(int(np.floor(v))))) == m["Date"]).all()))
    chk("A8 행 불변식 — 해외 관측 가용일 최대 ≤ 한국 행 날짜(전 행)",
        bool((m["c11_row_avail_max"] <= m["Date"]).all()))
    nv = independent_violations(m, FEATS, cal)
    chk("A9 독립 검산(값→관측일 역산 → S0 규칙) 위반 0", nv == 0, f"{nv}")
    # 최대성: 가용한 관측 중 최신인가 — 주간은 가용 라벨이 하나 더 있으면 안 된다
    ok_max = True
    for f in WEEKLY:
        rid = "NFCI" if f == "Chi_Fin_Cond" else "STLFSI4"
        labs = [d for d in pd.bdate_range("2003-01-01", "2010-06-30") if d.weekday() == 4]
        av = fa.fred_avail_date(rid, [d.date() for d in labs], kr_calendar=cal)
        pairs = [(pd.Timestamp(a), l) for a, l in zip(av, labs) if a is not None]
        for d in pd.to_datetime(["2008-03-12", "2008-03-13", "2008-03-14", "2009-06-30"]):
            want = max(l for a, l in pairs if a <= d)
            ok_max &= ofv(row(m, d)[f]) == want
    chk("A10 최대성 — 결합값이 '그 날 가용한 최신 라벨'(주간 2계열 × 4일)", ok_max)
    return fx, cal, m


# ══ B. 위반 주입 ════════════════════════════════════════════════════════════════
def axis_b(fx, cal, m):
    print("── B. 위반 주입 (빨개져야 한다) ──")
    lg = legacy_panel(fx)
    nv_lg = independent_violations(lg, FEATS, cal)
    chk("B1 ★구판 라벨 결합(merge_asof) → 독립 검산이 위반을 잡는다", nv_lg > 0, f"{nv_lg}행")
    r = row(lg, "2008-03-12")
    chk("B1b 구판은 수 03-12 에 공표 전 NFCI(라벨 03-07)를 싣는다 — 판정서 V-03 기전 재현",
        ofv(r["Chi_Fin_Cond"]) == pd.Timestamp("2008-03-07"))
    # 1행 lag (한국 격자에서 shift 1) — 주간 공표 지연을 못 덮는다
    lg1 = lg.copy()
    for f in FEATS:
        lg1[f] = lg[f].shift(1)
    lg1 = lg1.dropna(subset=FEATS).reset_index(drop=True)
    nv1 = independent_violations(lg1, WEEKLY, cal)
    chk("B2 ★'1행 lag' 로 때운 판 → 주간 계열 위반이 남는다(판정서 ⓑ '1행 lag 는 부족')", nv1 > 0, f"{nv1}행")
    # 결합 함수 자체를 같은 날짜 결합으로 변조 → 빌더의 자기 검사가 거부해야 한다
    orig = fa.fred_asof_join

    def same_day(kr_dates, series, series_id, mode="decision_close", **kw):
        s = series.sort_values("Date")
        dd = pd.DataFrame({"kr_date": pd.to_datetime(kr_dates)})
        j = pd.merge_asof(dd, s.rename(columns={"Date": "obs_date"}).assign(kr_date=lambda x: x["obs_date"]),
                          on="kr_date", direction="backward")
        return pd.DataFrame({"value": j["Value"], "obs_date": j["obs_date"], "avail_date": j["obs_date"]})
    try:
        aepf.fa.fred_asof_join = same_day
        hit = raises(lambda: aepf.build_pit_panel(os.path.join(fx, "fred_macro_wide.parquet"),
                                                  os.path.join(fx, "benchmark.parquet"),
                                                  os.path.join(fx, aepf.ECOS_KRW_FILE), FEATS),
                     aepf.AEPitError, "★C11")
    finally:
        aepf.fa.fred_asof_join = orig
    chk("B3 ★결합 함수를 같은 날짜 결합으로 변조 → 빌더 자기 검사(fred_join_violations)가 거부", hit)
    # DEXKOUS 경로 — 원천 교체를 지우면 규칙 파일이 거부한다
    saved = dict(aepf.SOURCE_OVERRIDES)
    try:
        aepf.SOURCE_OVERRIDES.clear()
        hit = raises(lambda: aepf.build_pit_panel(os.path.join(fx, "fred_macro_wide.parquet"),
                                                  os.path.join(fx, "benchmark.parquet"), None, FEATS),
                     aepf.AEPitError, "DEXKOUS")
    finally:
        aepf.SOURCE_OVERRIDES.update(saved)
    chk("B4 ★원/달러 원천 교체를 지우면(DEXKOUS 경로) 결합 거부 — prohibited(PIT-C11-CONVENTIONS ①)", hit)
    chk("B5 ECOS 파일 없는 핀 → 거부(수리 전 핀)",
        raises(lambda: aepf.build_pit_panel(os.path.join(fx, "fred_macro_wide.parquet"),
                                            os.path.join(fx, "benchmark.parquet"),
                                            os.path.join(fx, "nope.parquet"), FEATS), aepf.AEPitError, "ECOS"))
    # 표식 — 정상은 통과, 변조는 거부
    dec = pd.DataFrame({"decision_date": pd.to_datetime(["2008-04-01", "2008-05-01"]),
                        "last_feat_date": pd.to_datetime(["2008-03-31", "2008-04-30"])})
    st = aepf.stamp(dec, m, KEY)
    chk("B6 양성 — 표식 4열 · info_cutoff = last_feat · is_c11_stamped(KEY)",
        aepf.is_c11_stamped(st, KEY) and bool((st["c11_info_cutoff"] == st["last_feat_date"]).all()))
    bad = m.copy()
    bad.loc[bad["Date"] == pd.Timestamp("2008-03-31"), "c11_row_avail_max"] = pd.Timestamp("2008-04-02")
    chk("B7 ★패널 행 가용일을 결정 뒤로 변조 → stamp 거부",
        raises(lambda: aepf.stamp(dec, bad, KEY), aepf.AEPitError, "★C11"))
    chk("B8 ★구판 패널(c11_row_avail_max 없음)로 표식 시도 → 거부(가용시점 결합 미경유)",
        raises(lambda: aepf.stamp(dec, legacy_panel(fx), KEY), aepf.AEPitError, "★C11"))
    chk("B9 is_c11_stamped — 표식 없음·다른 epoch 는 거짓",
        (not aepf.is_c11_stamped(dec)) and (not aepf.is_c11_stamped(st, "c11_avail:other:00000000")))


# ══ C. 러너 통합 (sandbox · 실모델 · EPOCHS=1) ════════════════════════════════════
class RunnerSandbox:
    def __init__(self, tmp, name):
        self.root = os.path.join(tmp, name)

    def __enter__(self):
        os.makedirs(os.path.join(self.root, "stage_artifacts", "WT_D20260718_007"), exist_ok=True)
        self.pin = os.path.join(self.root, ".cache", "pins", "ae_monthly_test").replace("\\", "/")
        make_fixture(self.pin, start="2003-01-01", end="2009-12-30")
        dec = pd.date_range("2008-01-01", "2009-12-01", freq="MS")
        pd.DataFrame({"decision_date": dec}).to_parquet(
            os.path.join(self.pin, "carrier_STR_1715_AR_on_M4_R05_overlay_PG2.parquet"), index=False)
        self.out = os.path.join(self.root, aem.OUT)
        self._src = aem.load_frozen_source
        src = open(FROZEN, encoding="utf-8").read()
        assert "EPOCHS=25;" in src, "동결 원본 상수 줄 변경 — 픽스처 가정 무효"
        fast = src.replace("EPOCHS=25;", "EPOCHS=1;", 1)
        aem.load_frozen_source = lambda: fast
        os.environ["QM_ROOT"] = self.root          # ★동결 원본 exec 의 os.chdir(QM_ROOT) 를 sandbox 로
        os.chdir(self.root)
        return self

    def run(self, *args):
        old = sys.argv
        sys.argv = ["ae_regime_monthly.py"] + list(args)
        try:
            return aem.main()
        except SystemExit as e:
            return e.code
        finally:
            sys.argv = old
            os.chdir(self.root)

    def __exit__(self, *a):
        aem.load_frozen_source = self._src
        if _QM0 is None:
            os.environ.pop("QM_ROOT", None)
        else:
            os.environ["QM_ROOT"] = _QM0
        os.chdir(_CWD0)
        return False


def axis_c(tmp):
    print("── C. 러너 통합 (sandbox · 동결 원본 exec · EPOCHS=1) ──")
    with RunnerSandbox(tmp, "runC") as sb:
        rc = sb.run("--as-of", "2010-01-01", "--pin-dir", sb.pin)
        chk("C1 최초 생성 exit 0", rc == 0, f"rc={rc}")
        out = pq.read_table(sb.out).to_pandas() if os.path.exists(sb.out) else pd.DataFrame()
        chk("C2 ★산출 전 행 C11 표식(현행 epoch) · 2010-01-01 결정행 포함",
            len(out) > 0 and aepf.is_c11_stamped(out, KEY)
            and (pd.to_datetime(out["decision_date"]) == pd.Timestamp("2010-01-01")).any(), f"{len(out)}행")
        chk("C3 c11_info_cutoff < decision_date · fred_avail_max ≤ last_feat (전 행)",
            len(out) > 0 and bool((pd.to_datetime(out["c11_info_cutoff"]) < pd.to_datetime(out["decision_date"])).all())
            and bool((pd.to_datetime(out["c11_fred_avail_max"]) <= pd.to_datetime(out["last_feat_date"])).all()))
        pit_out = out.copy()
        # C4 주입이 실제로 소비되는가 — 빌더를 구판(라벨 결합)으로 바꾼 판은 ae_seq 가 달라야 한다
        orig = aepf.build_pit_panel

        def legacy_builder(fred, bench, ecos, feats, **kw):
            p = legacy_panel(os.path.dirname(fred), feats)
            p["c11_row_avail_max"] = p["Date"]          # 표식만 흉내(값은 구판) — ae_seq 차이로 소비를 가린다
            return p, aepf.KR_FEATS + list(feats)
        try:
            aepf.build_pit_panel = legacy_builder
            os.remove(sb.out)
            rc2 = sb.run("--as-of", "2010-01-01", "--pin-dir", sb.pin)
        finally:
            aepf.build_pit_panel = orig
        lg = pq.read_table(sb.out).to_pandas() if os.path.exists(sb.out) else pd.DataFrame()
        diff = int((~np.isclose(lg["ae_seq"].values, pit_out["ae_seq"].values)).sum()) if len(lg) == len(pit_out) else -1
        chk("C4 ★주입 실증 — 빌더를 구판으로 바꾸면 ae_seq 가 달라진다(동결 원본이 교체된 빌더를 소비)",
            rc2 == 0 and diff > 0, f"rc={rc2} · 변경 {diff}/{len(pit_out)}행")
        # C5 수리 전 판 발행본 위에서의 재계산 → parity 차단 + C11 전환 표지
        legacy_out = pit_out.drop(columns=aepf.PROVENANCE_COLS).copy()
        legacy_out = legacy_out[pd.to_datetime(legacy_out["decision_date"]) < pd.Timestamp("2010-01-01")]
        legacy_out["fire_seq"] = 1 - legacy_out["fire_seq"]      # 판정이 갈린 발행본(수리 전 판) 흉내
        legacy_out.to_parquet(sb.out, index=False)
        ok, note = aem.parity_check(sb.out, pit_out.assign(decision_date=pd.to_datetime(pit_out["decision_date"])))
        chk("C5 ★수리 전 판 발행본 → parity 차단 · 원인 표지 '★C11 전환'", (not ok) and "★C11 전환" in note, note[:120])
        rc3 = sb.run("--as-of", "2010-01-01", "--pin-dir", sb.pin)
        # 발행본에 2010-01 행이 없으므로 재계산 경로 → 판정 변경 → exit 1 · 발행본 보존
        kept = pq.read_table(sb.out).to_pandas()
        chk("C6 ★러너 exit 1 · 발행본 무변경(침묵 덮어쓰기 없음) · .parity_reject 보존",
            rc3 == 1 and len(kept) == len(legacy_out) and os.path.exists(sb.out + ".parity_reject"), f"rc={rc3}")
        ok2, note2 = aem.parity_check(sb.out + ".parity_reject",
                                      pit_out.assign(decision_date=pd.to_datetime(pit_out["decision_date"])))
        chk("C7 양성 — 표식 판끼리 동일하면 parity 통과 · C11 전환 표지 없음", ok2 and "★C11 전환" not in note2)
        # C8 ECOS 없는 핀 → exit 2 (수리 전 핀 거부)
        os.remove(os.path.join(sb.pin, aepf.ECOS_KRW_FILE))
        os.remove(sb.out)
        rc4 = sb.run("--as-of", "2010-01-01", "--pin-dir", sb.pin)
        chk("C8 ★ECOS 없는 핀(수리 전 판) → exit 2", rc4 == 2, f"rc={rc4}")
    return pit_out


# ══ D. 백필기 ═══════════════════════════════════════════════════════════════════
def axis_d(tmp, stamped_rows):
    print("── D. 백필기 (수리 전 판 기존 행과 섞지 않는다) ──")
    root = os.path.join(tmp, "runD")
    pin = os.path.join(root, "pin").replace("\\", "/")
    make_fixture(pin, start="2000-01-03", end="2009-12-30")
    pd.DataFrame({"decision_date": pd.date_range("2004-01-01", "2009-12-01", freq="MS")}).to_parquet(
        os.path.join(pin, "carrier_STR_1715_AR_on_M4_R05_overlay_PG2.parquet"), index=False)
    os.makedirs(os.path.join(root, "stage_artifacts", "WT_D20260718_007"), exist_ok=True)
    shutil.copy2(FROZEN, os.path.join(root, "stage_artifacts", "WT_D20260718_007", "ae_regime_extend.py"))
    out = os.path.join(root, "stage_artifacts", "WT_D20260718_007", "ae_regime_signal_ext.parquet")
    os.environ["QM_ROOT"] = root
    os.chdir(root)
    try:
        import importlib
        if "ae_regime_backfill" in sys.modules:
            bf = importlib.reload(sys.modules["ae_regime_backfill"])
        else:
            import ae_regime_backfill as bf
        bf.EPOCHS = 1

        def run(*args):
            old = sys.argv
            sys.argv = ["ae_regime_backfill.py"] + list(args)
            try:
                bf.main()
                return 0
            except SystemExit as e:
                return e.code
            finally:
                sys.argv = old
                os.chdir(root)
        legacy = stamped_rows.drop(columns=aepf.PROVENANCE_COLS)
        legacy.to_parquet(out, index=False)
        rc = run("--pin-dir", pin)
        chk("D1 ★기존 행이 수리 전 판(표식 없음) → exit 2 · 섞지 않음",
            rc == 2 and len(pq.read_table(out).to_pandas()) == len(legacy), f"rc={rc}")
        stamped_rows.to_parquet(out, index=False)
        rc = run("--pin-dir", pin)
        got = pq.read_table(out).to_pandas()
        new = got[pd.to_datetime(got["decision_date"]) < pd.Timestamp("2008-01-01")]
        chk("D2 표식 기존 행 위 백필 → exit 0 · 신규 2004~2007 행 전부 표식 · info_cutoff < decision",
            rc == 0 and len(new) > 0 and aepf.is_c11_stamped(new, KEY)
            and bool((pd.to_datetime(new["c11_info_cutoff"]) < pd.to_datetime(new["decision_date"])).all()),
            f"rc={rc} · 신규 {len(new)}행")
        old = got[pd.to_datetime(got["decision_date"]) >= pd.Timestamp("2008-01-01")].reset_index(drop=True)
        chk("D3 기존 행 바이트 불변(V1 parity 는 표식 열 포함 전 열)",
            len(old) == len(stamped_rows) and bool(
                (old["ae_seq"].values == stamped_rows.sort_values("decision_date")["ae_seq"].values).all()))
        os.remove(os.path.join(pin, aepf.ECOS_KRW_FILE))
        stamped_rows.to_parquet(out, index=False)
        chk("D4 ★ECOS 없는 핀 → exit 2", run("--pin-dir", pin) == 2)
    finally:
        if _QM0 is None:
            os.environ.pop("QM_ROOT", None)
        else:
            os.environ["QM_ROOT"] = _QM0
        os.chdir(_CWD0)


# ══ E. 실데이터 (읽기 전용) ═════════════════════════════════════════════════════
def axis_e():
    print("── E. 실데이터 (핀 r1 + 라이브 ECOS · 읽기 전용) ──")
    pin = os.path.join(ROOT, ".cache", "pins", "WT-D20260718_007_r1")
    ecos = os.path.join(ROOT, ".cache", aepf.ECOS_KRW_FILE)
    need = [os.path.join(pin, "fred_macro_wide.parquet"), os.path.join(pin, "benchmark.parquet"), ecos]
    miss = [p for p in need if not os.path.exists(p)]
    if miss:
        # worktree 등 데이터 없는 트리 — 합성 축(A~D)이 계약을 잰다. 실데이터 축만 미측정으로 적는다.
        print(f"  (E 미측정 — 실데이터 부재: {miss[0]})")
        return
    m, _ = aepf.build_pit_panel(need[0], need[1], ecos, FEATS)
    cal = sorted(set(d.date() for d in aepf.build_kr_spine(need[1])["Date"]))
    nv = 0
    for f in [x for x in FEATS if x != "KRW_USD"]:
        ok = m[f"_obs_{f}"].notna()
        nv += len(fa.fred_join_violations([d.date() for d in m.loc[ok, "Date"]],
                                          [d.date() for d in m.loc[ok, f"_obs_{f}"]], f,
                                          mode="decision_close", kr_calendar=cal))
    chk("E1 실데이터 PIT 빌드 — 해외 6계열 결합쌍 위반 0", nv == 0, f"{len(m)}행 · 위반 {nv}")
    fr = pq.read_table(need[0]).to_pandas()
    fr["Date"] = pd.to_datetime(fr["Date"])
    sp = aepf.build_kr_spine(need[1])
    lg = pd.merge_asof(sp, fr[["Date"] + FEATS].sort_values("Date"), on="Date", direction="backward")
    nlab = {}
    for f in ["VIX", "StL_Fin_Stress", "Chi_Fin_Cond"]:
        s = fr[["Date", f]].dropna().sort_values("Date")
        j = pd.merge_asof(sp[["Date"]], s.rename(columns={"Date": "obs"}).assign(Date=lambda x: x["obs"]),
                          on="Date", direction="backward").dropna()
        nlab[f] = len(fa.fred_join_violations([d.date() for d in j["Date"]], [d.date() for d in j["obs"]], f,
                                              mode="decision_close", kr_calendar=cal))
    chk("E2 ★구판 라벨 결합은 실데이터에서 위반 다수(VIX·STLFSI4·NFCI 각각 > 0)",
        all(v > 0 for v in nlab.values()), str(nlab))
    r = m[m["Date"] == pd.Timestamp("2026-07-01")]
    chk("E3 실례 — 2026-07-01 행 STLFSI4 = 라벨 06-19(06-26 공표분 · 06-26 라벨은 07-03 가용)",
        len(r) == 1 and str(r["_obs_StL_Fin_Stress"].iloc[0])[:10] == "2026-06-19",
        str(r["_obs_StL_Fin_Stress"].iloc[0])[:10] if len(r) else "행 없음")


def main() -> int:
    print("=" * 78)
    print("test_ae_c11_pit_features — AE 특성 C11 가용시점 결합(빌더·러너·백필기)")
    print("=" * 78)
    tmp = tempfile.mkdtemp(prefix="aec11_")
    try:
        try:
            fx, cal, m = axis_a(tmp)
            axis_b(fx, cal, m)
        except Exception as e:  # noqa: BLE001
            chk("A/B 축 예외 없이 완주", False, f"{type(e).__name__}: {e}")
            traceback.print_exc()
        stamped = None
        try:
            stamped = axis_c(tmp)
        except Exception as e:  # noqa: BLE001
            chk("C 축 예외 없이 완주", False, f"{type(e).__name__}: {e}")
            traceback.print_exc()
        try:
            if stamped is not None and len(stamped):
                axis_d(tmp, stamped)
            else:
                chk("D 축 전제(C 산출) 확보", False, "C 축 산출 없음")
        except Exception as e:  # noqa: BLE001
            chk("D 축 예외 없이 완주", False, f"{type(e).__name__}: {e}")
            traceback.print_exc()
        try:
            axis_e()
        except Exception as e:  # noqa: BLE001
            chk("E 축 예외 없이 완주", False, f"{type(e).__name__}: {e}")
            traceback.print_exc()
    finally:
        os.chdir(_CWD0)
        shutil.rmtree(tmp, ignore_errors=True)
    print("-" * 78)
    print(f"  {PASS}/{PASS + FAIL} PASS" + (f" · ★실패: {', '.join(FAILS)}" if FAILS else ""))
    print('{"test":"ae_c11_pit_features","pass":%d,"fail":%d,"total":%d,"skipped":0}' % (PASS, FAIL, PASS + FAIL))
    return 0 if FAIL == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
