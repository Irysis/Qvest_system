"""test_ae_monthly_c11_recompute.py — AE 월간 러너의 C11 2단계 준비 검사 (오프라인 · 모델 미실행)

대상: `02_Infrastructure/regime/ae_regime_monthly.py`
신설: 2026-09-24 — 결정 PIT-C11-AE-1003("AE 전 이력 재산출을 10-01 전에 선행 → 10-03 정상 실행").

## 무엇을 재는가
1. **핀 PIT 절단** — 예약 실행(매월 3일 09:00)의 라이브 원천에는 결정일 이후 관측이 있다. 구판은 통째로 복사해
   `fr.max() >= as_of` PIT 검사에 걸려 exit 3(러너 exit 19)로 멈췄다. 신판은 Date 축 원천을 Date < as_of 로 절단한다.
2. **핀 완결성** — 태그가 있어도 PIN_SOURCES(ECOS 포함)가 빠진 핀은 재사용하지 않는다(재발행 = --repin-stale).
3. **--recompute** — 기존 결정일 행이 있어도 전 이력을 재계산(사유 필수 · 최신 결정일 한정).
4. **범위 가드** — 과거 결정일 + 핀 전진 거부(절단이 뒤 결정들의 창을 자른다).
5. **dry-run 무기록** — parity 수용·재계산 감사 기록은 실제 교체 때만.

## 검출력 (돌연변이)
MUT-1 구판 복사(절단 없음) → 같은 입력에서 main 이 exit 3(10-03 정지 재현) · MUT-2 구판 재사용(완결성 무검사) →
ECOS 없는 핀을 그대로 돌려준다 · MUT-3 dry-run 기록(구판 순서) → 감사 파일이 생긴다.

## 방식
LSTM 은 돌리지 않는다 — `run_walkforward` 를 산출 파일만 쓰는 스텁으로 바꾸고, 표식(aepf.stamp)은 **실함수**를
합성 패널에 건다. 운영 산출물 미접촉(전부 tmpdir). 실행: .venv_qvest_ml/Scripts/python.exe 08_Tests/regime/test_ae_monthly_c11_recompute.py
"""
from __future__ import annotations

import os
import shutil
import sys
import tempfile
import traceback

try:
    import pandas as _probe  # noqa: F401
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
    if _venv and os.environ.get("_AEC11R_REEXEC") != "1":
        import subprocess
        sys.exit(subprocess.call([_venv, os.path.abspath(__file__)] + sys.argv[1:],
                                 env=dict(os.environ, _AEC11R_REEXEC="1")))
    raise

import pandas as pd
import pyarrow as pa
import pyarrow.parquet as pq

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
MARKER = "02_Infrastructure/regime/ae_regime_monthly.py"
if not os.path.isfile(os.path.join(ROOT, MARKER)):
    print(f"PROJECT_ROOT 해석 실패 — 표지 {MARKER} 없음 (self={ROOT})")
    sys.exit(2)
sys.path.insert(0, os.path.join(ROOT, "02_Infrastructure", "regime"))
_cwd0 = os.getcwd()
import ae_regime_monthly as ae      # noqa: E402  (import 시 os.chdir(QM_ROOT))
import ae_pit_features as aepf      # noqa: E402

AS_OF = pd.Timestamp("2026-10-01")
KEY = ae.KEY


def _write_dates(path, first, last, extra_cols=("v",)):
    d = pd.bdate_range(start=pd.Timestamp(first), end=pd.Timestamp(last))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    cols = {"Date": pa.array(d.date, type=pa.date32())}
    for c in extra_cols:
        cols[c] = pa.array([float(i) for i in range(len(d))], type=pa.float64())
    pq.write_table(pa.table(cols), path)


def _max_date(path):
    return pd.to_datetime(pq.read_table(path, columns=["Date"]).to_pandas()["Date"]).max()


def _md5(p):
    import hashlib
    return hashlib.md5(open(p, "rb").read()).hexdigest()


class Sandbox:
    """tmp 루트 — 라이브 원천이 결정일(10-01) **뒤**(10-02)까지 있다 = 10-03 09:00 예약 실행의 실제 모양."""

    def __init__(self, live_last="2026-10-02", mod=None):
        self.live_last = live_last
        self.m = mod or ae

    def __enter__(self):
        m = self.m
        # 경로 길이(Windows 260자) — 긴 TMPDIR(세션 스크래치)에서는 짧은 기저로
        _base = tempfile.gettempdir() if len(tempfile.gettempdir()) <= 60 else os.path.join(os.environ.get("SystemDrive", "C:") + os.sep, "tmp")
        os.makedirs(_base, exist_ok=True)
        self.tmp = tempfile.mkdtemp(prefix="aec11r_", dir=_base)
        self.old_sources = dict(m.PIN_SOURCES)
        self.old_rwf = m.run_walkforward
        self.old_copy = getattr(m, "_pin_copy", None)   # 구판(수리 전)에는 없다 — 검사가 red 로 보고하게
        os.chdir(self.tmp)
        _write_dates(".cache/fred_macro_wide.parquet", "2026-06-01", self.live_last, ("VIX",))
        _write_dates(".cache/benchmark.parquet", "2026-06-01", self.live_last, ("BM_Close",))
        _write_dates(".cache/ecos.parquet", "2026-06-01", self.live_last, ("KRW_USD",))
        pq.write_table(pa.table({"decision_date": pa.array([pd.Timestamp("2026-08-01").date()], type=pa.date32())}),
                       ".cache/carrier.parquet")
        with open(".cache/pr.csv", "w", encoding="utf-8") as f:
            f.write("a,b\n1,2\n")
        m.PIN_SOURCES = {
            "fred_macro_wide.parquet": ".cache/fred_macro_wide.parquet",
            "benchmark.parquet": ".cache/benchmark.parquet",
            "carrier_STR_1715_AR_on_M4_R05_overlay_PG2.parquet": ".cache/carrier.parquet",
            "period_returns_layer5.csv": ".cache/pr.csv",
            aepf.ECOS_KRW_FILE: ".cache/ecos.parquet",
        }
        os.makedirs(".cache/pins", exist_ok=True)
        os.makedirs(os.path.dirname(m.OUT), exist_ok=True)
        self.calls = []
        return self

    def __exit__(self, *a):
        self.m.PIN_SOURCES = self.old_sources
        self.m.run_walkforward = self.old_rwf
        if self.old_copy is not None:
            self.m._pin_copy = self.old_copy
        os.chdir(_cwd0)
        shutil.rmtree(self.tmp, ignore_errors=True)
        return False

    def write_out(self, decisions, fire=1):
        dd = pd.to_datetime(decisions)
        df = pd.DataFrame({KEY: dd, "fire_seq": fire, "exposure_seq": 0.7 if fire else 1.0,
                           "last_feat_date": dd - pd.Timedelta(days=1), "ae_seq": 1.0, "tau_seq": 0.5})
        df.to_parquet(ae.OUT, index=False)

    def stub(self, fire=1):
        """run_walkforward 스텁 — 모델 없이 산출 모양만. 호출 인자(결정목록·핀)를 기록. 표식은 실함수(aepf.stamp)가 붙인다."""
        box = self

        def _rwf(decisions, pin_dir, out_path):
            box.calls.append({"decisions": list(decisions), "pin_dir": pin_dir,
                              "pin_fred_max": _max_date(os.path.join(pin_dir, "fred_macro_wide.parquet"))})
            dd = pd.to_datetime(decisions)
            lf = pd.to_datetime([pd.bdate_range(end=d - pd.Timedelta(days=1), periods=1)[0] for d in dd])
            pd.DataFrame({KEY: dd, "fire_seq": fire, "exposure_seq": 0.7 if fire else 1.0, "last_feat_date": lf,
                          "ae_seq": 1.0, "tau_seq": 0.5}).to_parquet(out_path, index=False)
            days = pd.bdate_range("2026-06-01", "2026-09-30")
            return pd.DataFrame({"Date": days, "c11_row_avail_max": days, "c11_vintage_unresolved": ""})
        self.m.run_walkforward = _rwf


def run_main(*args, mod=None):
    old = sys.argv
    sys.argv = ["ae_regime_monthly.py"] + list(args)
    try:
        return (mod or ae).main()
    except SystemExit as e:
        return e.code
    finally:
        sys.argv = old


def legacy_pin_copy(src, dst, as_of, base):
    """구판 복사 재현(절단 없음) — 돌연변이용."""
    shutil.copy2(src, dst)
    return {"basename": base, "md5": _md5(dst), "size_bytes": os.path.getsize(dst), "source": src}


CASES = []


def case(name):
    def deco(fn):
        CASES.append((name, fn))
        return fn
    return deco


# ══ 1. 핀 PIT 절단 ═══════════════════════════════════════════════════════════
@case("T1  ★라이브가 결정일 뒤까지 있어도 핀은 Date < as_of 로 절단된다 (FRED·벤치·ECOS) · 나머지는 원본 그대로")
def _():
    with Sandbox() as s:
        d = ae.advance_pin(AS_OF)
        for b in ("fred_macro_wide.parquet", "benchmark.parquet", aepf.ECOS_KRW_FILE):
            mx = _max_date(os.path.join(d, b))
            assert mx < AS_OF, f"{b} 핀 max {mx.date()} >= as_of"
        assert _md5(os.path.join(d, "carrier_STR_1715_AR_on_M4_R05_overlay_PG2.parquet")) == _md5(".cache/carrier.parquet")
        assert _md5(os.path.join(d, "period_returns_layer5.csv")) == _md5(".cache/pr.csv")
        import json
        man = json.load(open(os.path.join(d, "manifest.json"), encoding="utf-8"))
        tr = {f["basename"]: f.get("truncated") for f in man["files"]}
        assert tr["fred_macro_wide.parquet"]["rows_dropped"] == 2 and tr["fred_macro_wide.parquet"]["pin_max"] == "2026-09-30", tr
        assert tr["carrier_STR_1715_AR_on_M4_R05_overlay_PG2.parquet"] is None
    return "FRED/벤치/ECOS 핀 max 09-30 (라이브 10-02) · carrier·pr md5 동일 · manifest 절단 기록(2행)"


@case("T2  ★10-03 예약 경로 재현 — 당월 행 없는 AE 월간 실행이 PIT 검사(fr.max)를 통과해 재계산까지 간다")
def _():
    with Sandbox() as s:
        s.write_out(["2026-08-01", "2026-09-01"])
        s.stub()
        rc = run_main("--as-of", "2026-10-01", "--advance-pin")
        assert rc == 0, f"rc={rc} (구판이면 3 = 러너 exit 19)"
        assert s.calls and s.calls[0]["pin_fred_max"] < AS_OF, s.calls
        assert s.calls[0]["decisions"] == ["2026-08-01", "2026-09-01", "2026-10-01"], s.calls[0]["decisions"]
        out = pq.read_table(ae.OUT).to_pandas()
        assert aepf.is_c11_stamped(out) and (pd.to_datetime(out[KEY]) == AS_OF).any()
    return "rc 0 · 핀 FRED max 09-30 · 결정 3건 재계산 · 표식 실함수 통과 · 10-01 행 생성"


@case("MUT-1  ★검출력: 구판 복사(절단 없음)는 같은 입력에서 exit 3 — 10-03 정지(러너 exit 19) 재현")
def _():
    with Sandbox() as s:
        s.write_out(["2026-08-01", "2026-09-01"])
        s.stub()
        ae._pin_copy = legacy_pin_copy
        rc = run_main("--as-of", "2026-10-01", "--advance-pin")
        assert rc == 3, f"rc={rc} — 돌연변이가 PIT 검사에 안 걸림(검사 무효)"
        assert not s.calls, "구판인데 재계산까지 감"
    return "구판: exit 3(fr.max 10-02 >= 10-01) → 신판: T2 통과"


# ══ 2. 핀 완결성 ═════════════════════════════════════════════════════════════
def _make_pin_without_ecos(tag, last="2026-09-30"):
    d = os.path.join(".cache/pins", tag)
    os.makedirs(d, exist_ok=True)
    _write_dates(os.path.join(d, "fred_macro_wide.parquet"), "2026-06-01", last, ("VIX",))
    _write_dates(os.path.join(d, "benchmark.parquet"), "2026-06-01", last, ("BM_Close",))
    shutil.copy2(".cache/carrier.parquet", os.path.join(d, "carrier_STR_1715_AR_on_M4_R05_overlay_PG2.parquet"))
    shutil.copy2(".cache/pr.csv", os.path.join(d, "period_returns_layer5.csv"))
    open(os.path.join(d, "manifest.json"), "w", encoding="utf-8").write('{"tag":"%s"}' % tag)
    return d


@case("T3  ★ECOS 없는 기존 핀(날짜는 신선) → 재사용 거부 exit 2 · --repin-stale 로만 이관·재발행(ECOS 포함)")
def _():
    with Sandbox() as s:
        old = _make_pin_without_ecos("ae_monthly_202610")
        ok, _n = ae.pin_freshness(old, AS_OF)
        assert ok, "픽스처 오류 — 날짜상 신선해야 완결성 축만 시험된다"
        try:
            ae.advance_pin(AS_OF)
            raise AssertionError("ECOS 없는 핀이 재사용됨")
        except SystemExit as e:
            assert e.code == 2, e.code
        got = ae.advance_pin(AS_OF, repin_stale="TEST: C11 이전 핀(ECOS 부재)")
        assert os.path.exists(os.path.join(got, aepf.ECOS_KRW_FILE))
        arch = [x for x in os.listdir(".cache/pins") if x.startswith("ae_monthly_202610.stale_")]
        assert len(arch) == 1 and "TEST: C11 이전 핀" in open(".cache/pins/ae_monthly_repin.jsonl", encoding="utf-8").read()
    return "재사용 거부(2) → 사유 제시 시 이관 1 + 감사 기록 + ECOS 포함 재발행"


@case("MUT-2  ★검출력: 구판 재사용(신선도만)은 ECOS 없는 핀을 돌려준다 → main 에서 뒤늦게 exit 2")
def _():
    with Sandbox() as s:
        old = _make_pin_without_ecos("ae_monthly_202610")
        fresh, _n = ae.pin_freshness(old, AS_OF)
        legacy_reuse = old if fresh else None       # 구판 규칙: 신선하면 재사용
        assert legacy_reuse and not os.path.exists(os.path.join(legacy_reuse, aepf.ECOS_KRW_FILE)), "돌연변이 무효"
    return "구판: ECOS 없는 핀 재사용 → 신판: T3 에서 사유 없는 재사용 차단"


# ══ 3. --recompute · 범위 가드 ════════════════════════════════════════════════
@case("T4  ★결정일 행이 있으면 기본은 생략(0) · --recompute '<사유>' 면 전 이력 재계산 + 기록")
def _():
    with Sandbox() as s:
        s.write_out(["2026-08-01", "2026-09-01", "2026-10-01"])
        s.stub()
        rc0 = run_main("--as-of", "2026-10-01", "--advance-pin")
        assert rc0 == 0 and not s.calls, f"생략 경로가 재계산함 rc={rc0}"
        rc1 = run_main("--as-of", "2026-10-01", "--advance-pin", "--recompute", "TEST 재산출",
                       "--accept-parity", "TEST C11")
        assert rc1 == 0 and len(s.calls) == 1, f"rc={rc1} calls={len(s.calls)}"
        assert s.calls[0]["decisions"] == ["2026-08-01", "2026-09-01", "2026-10-01"]
        rec = open(ae.OUT + ".recompute.jsonl", encoding="utf-8").read()
        assert "TEST 재산출" in rec and "c11_avail:" in rec
    return "생략(0·스텁 미호출) → --recompute: 3건 재계산 · recompute.jsonl(사유·epoch)"


@case("T5  ★--recompute 는 최신 결정일 한정 · 과거 결정일 + 핀 전진 거부 · 빈 사유 거부 (전부 exit 2)")
def _():
    with Sandbox() as s:
        s.write_out(["2026-08-01", "2026-09-01", "2026-10-01"])
        s.stub()
        r1 = run_main("--as-of", "2026-09-01", "--advance-pin", "--recompute", "TEST")
        s.write_out(["2026-08-01", "2026-10-01"])
        r2 = run_main("--as-of", "2026-09-01", "--advance-pin")
        r3 = run_main("--as-of", "2026-10-01", "--recompute", " ")
        assert (r1, r2, r3) == (2, 2, 2) and not s.calls, (r1, r2, r3, len(s.calls))
    return "비최신 recompute 2 · 과거 끼워넣기+전진 2 · 빈 사유 2 · 재계산 0건"


# ══ 4. dry-run 무기록 ═════════════════════════════════════════════════════════
@case("T6  ★dry-run 은 parity 수용·재계산 감사 기록을 쓰지 않는다 · 실제 교체 때만 기록")
def _():
    with Sandbox() as s:
        s.write_out(["2026-08-01", "2026-09-01", "2026-10-01"], fire=0)      # 발행본 fire 0 → 재계산 fire 1 = parity 차단
        s.stub(fire=1)
        aud = ae.OUT + ".parity_override.jsonl"
        rc = run_main("--as-of", "2026-10-01", "--advance-pin", "--recompute", "TEST", "--accept-parity", "TEST C11", "--dry-run")
        assert rc == 0 and not os.path.exists(aud) and not os.path.exists(ae.OUT + ".recompute.jsonl"), \
            f"rc={rc} dry-run 이 기록을 남김"
        assert int(pq.read_table(ae.OUT).to_pandas()["fire_seq"].iloc[0]) == 0, "dry-run 이 발행본을 바꿈"
        rc2 = run_main("--as-of", "2026-10-01", "--advance-pin", "--recompute", "TEST", "--accept-parity", "TEST C11")
        assert rc2 == 0 and os.path.exists(aud) and "TEST C11" in open(aud, encoding="utf-8").read()
        rc3 = run_main("--as-of", "2026-10-01", "--advance-pin", "--recompute", "TEST")
        assert rc3 == 0, f"동일 판정 재계산은 parity 통과여야 rc={rc3}"
        s.write_out(["2026-08-01", "2026-09-01", "2026-10-01"], fire=0)
        rc4 = run_main("--as-of", "2026-10-01", "--advance-pin", "--recompute", "TEST")
        assert rc4 == 1 and os.path.exists(ae.OUT + ".parity_reject"), f"--accept-parity 없이 판정 변경 → 1 이어야 rc={rc4}"
    return "dry-run 무기록 · 실교체 기록 · 판정 불변 통과 · 판정 변경+무수용 = exit 1(.parity_reject)"


@case("MUT-3  ★검출력: dry-run 분기를 걷어낸 배포 텍스트(구판 동작)는 같은 입력에서 dry-run 감사 기록을 남긴다")
def _():
    import importlib.util
    src = open(os.path.join(ROOT, MARKER), encoding="utf-8").read()
    needle = '        if a.dry_run:\n            print(f"[ae-monthly] ★parity 수용 예정'
    assert src.count(needle) == 1, "신판 표지(dry-run 분기) 부재 — 돌연변이 수술 불가"
    mut = src.replace(needle, '        if False:\n            print(f"[ae-monthly] ★parity 수용 예정', 1)
    tdir = tempfile.mkdtemp(prefix="aec11r_mut_")      # 모듈 사본 1개 — 경로 짧음
    mp = os.path.join(tdir, "ae_regime_monthly_mut3.py")
    open(mp, "w", encoding="utf-8").write(mut)
    spec = importlib.util.spec_from_file_location("ae_regime_monthly_mut3", mp)
    mm = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mm)
    try:
        with Sandbox(mod=mm) as s:
            s.write_out(["2026-08-01", "2026-09-01", "2026-10-01"], fire=0)
            s.stub(fire=1)
            rc = run_main("--as-of", "2026-10-01", "--advance-pin", "--recompute", "TEST", "--accept-parity", "TEST C11",
                          "--dry-run", mod=mm)
            wrote = os.path.exists(mm.OUT + ".parity_override.jsonl")
    finally:
        shutil.rmtree(tdir, ignore_errors=True)
    assert rc == 0 and wrote, f"돌연변이가 dry-run 에서 기록 안 함(rc={rc}) — 검사 무효"
    return "돌연변이: dry-run 에서 parity_override.jsonl 생성 → 신판: T6 첫 단언 통과(무기록)"


def main() -> int:
    print("=" * 78)
    print("test_ae_monthly_c11_recompute — 핀 PIT 절단 · 완결성 · --recompute · dry-run 무기록")
    print("=" * 78)
    npass, fails = 0, []
    for name, fn in CASES:
        try:
            note = fn()
            npass += 1
            print(f"  PASS  {name}\n          {note}")
        except BaseException as e:      # SystemExit 포함 — 케이스 밖으로 새지 않게
            fails.append((name, e))
            print(f"  ★FAIL {name}\n          {type(e).__name__}: {e}")
            traceback.print_exc()
        finally:
            os.chdir(_cwd0)
    print("-" * 78)
    print(f"  {npass}/{len(CASES)} PASS")
    if fails:
        print("  ★실패:", ", ".join(n for n, _ in fails))
    print('{"test":"ae_monthly_c11_recompute","pass":%d,"fail":%d,"total":%d,"skipped":0}'
          % (npass, len(fails), npass + len(fails)))
    return 0 if not fails else 1


if __name__ == "__main__":
    sys.exit(main())
