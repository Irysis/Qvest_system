"""test_ae_monthly_plumbing.py — AE 월간 배관의 위반 주입 검사 (오프라인)

대상: `02_Infrastructure/regime/ae_regime_monthly.py` (핀 신선도 · 라이브 원천 신선도)
      `02_Infrastructure/monitoring/run_nolayer4_monthly.sh` (배선 도달 · fail-closed)
신설: 2026-08-30 — PG2 9월 리밸에서 발견된 오버레이 배관 결함 ①·② 수리 동반.

## 무엇을 재는가
1. **핀 신선도** — 조기 생성된 불변 핀을 재사용하지 않는가(결함 ②).
2. **라이브 원천 신선도** — 낡은 원천을 복사해 새 핀으로 굳히지 않는가.
   (핀 신선도만으로는 구조적으로 못 잡는다: 핀==라이브면 lag 0 이라 통과한다.)
3. **배선 도달** — 생산자를 실제로 **부르는가**, 실패를 **삼키지 않는가**(결함 ①).

## 왜
- 결함 ①: `ae_regime_monthly.py` 는 D3 게이트용 AE 신호의 운영 정본인데 **어떤 실행기도
  부르지 않았다**(.sh/.ps1/예약작업 참조 0건). 신호가 2026-08-01 에 멈췄고 소비자는
  직전 달 행을 조용히 재사용했다. 2026-09 는 m4 미발화라 무해했을 뿐, m4 발화월
  (실측 37개월 중 36 = 97.3%)에는 30% de-risk 오판이 된다.
- 결함 ②: `advance_pin()` 은 태그가 있으면 무조건 재사용했다("핀은 태그당 불변").
  실측 — `ae_monthly_202609` 핀이 **2026-08-01 22:33 에 미리 만들어져** FRED 07-24 ·
  benchmark 07-31 로 굳어 있었다. 9월 결정이 7월 피처를 쓴다.
  재현성을 지키려던 규칙이 신선도를 죽였다.

## 검출력 실증 (돌연변이)
MUT-1 이 **구판 advance_pin**(무조건 재사용)을 같은 입력에 돌려 낡은 핀을 그대로 쓰는 것을
보인다. WIRE-MUT 는 AE 스텝을 지운 사본에서 배선 검사가 실제로 발화하는지 본다.
(양성 대조 없는 계기는 방어선으로 세지 않는다.)

## 실행
  .venv_qvest_ml/Scripts/python.exe 08_Tests/regime/test_ae_monthly_plumbing.py
네트워크 미사용. 운영 산출물 미접촉(전부 tmpdir).
"""
from __future__ import annotations

import os
import re
import shutil
import sys
import tempfile
import traceback

# ── 인터프리터 자기해결 — 배터리는 pandas 없는 python 으로 돈다 ────────────────
#   (test_benchmark_scale_seam.py 선례). ★없으면 SKIP 하지 않는다 —
#   SKIP 은 "통과했다"와 겉보기가 같고 그게 이 저장소가 반복 겪은 무음 사망의 형태다.
#   ★해석기 루트 ≠ 코드 루트 (2026-08-30 실측). venv 는 **main 체크아웃에만** 있고
#     worktree 에는 없다. self 루트만 보면 worktree 배터리에서 ModuleNotFoundError 로
#     죽어 UNMEASURED+FAILING 으로 계상된다 — 코드 결함이 아니라 앵커 오설정인데
#     "테스트 실패"로 읽힌다. ⇒ **검사 대상 코드는 self 트리**(아래 ROOT)에서,
#     **해석기는 어느 루트에서든** 찾는다. 두 축을 섞지 않는다.
#     카드: feedback-code-root-is-not-data-root
try:
    import pandas as _probe  # noqa: F401
except ImportError:
    _self_root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    _venv = ""
    for _cand in (_self_root, os.environ.get("CLAUDE_PROJECT_DIR", ""),
                  os.environ.get("QM_ROOT", "")):
        if not _cand:
            continue
        _p = os.path.join(_cand.replace("\\", "/"), ".venv_qvest_ml", "Scripts", "python.exe")
        if os.path.exists(_p):
            _venv = _p
            break
    if _venv and os.environ.get("_AEPLUMB_REEXEC") != "1":
        import subprocess
        # ★재실행 대상은 **이 파일의 절대경로** — self 트리의 코드를 계속 검사한다.
        sys.exit(subprocess.call([_venv, os.path.abspath(__file__)] + sys.argv[1:],
                                 env=dict(os.environ, _AEPLUMB_REEXEC="1")))
    raise

import pandas as pd
import pyarrow as pa
import pyarrow.parquet as pq

# ── 루트 앵커 = self 최우선 (r-portability.md ④-b) ────────────────────────────
#   테스트 러너는 자기가 실린 트리를 검사해야 한다. env 를 먼저 보면 worktree 에서 낸
#   초록이 main 의 코드를 검증하게 된다.
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
MARKER = "02_Infrastructure/regime/ae_regime_monthly.py"
if not os.path.isfile(os.path.join(ROOT, MARKER)):
    print(f"PROJECT_ROOT 해석 실패 — 표지 {MARKER} 없음 (self={ROOT})")
    sys.exit(2)

sys.path.insert(0, os.path.join(ROOT, "02_Infrastructure", "regime"))
_cwd_before = os.getcwd()
import ae_regime_monthly as ae     # noqa: E402  (import 시 os.chdir(QM_ROOT) 부작용 있음)

RUNNER = os.path.join(ROOT, "02_Infrastructure/monitoring/run_nolayer4_monthly.sh")
FULL = os.path.join(ROOT, "02_Infrastructure/ops/run_pg2_rebalance_full.sh")
AS_OF = pd.Timestamp("2026-09-01")
TOL = ae.PIN_FRESHNESS_TOL_DAYS


# ── 픽스처 ────────────────────────────────────────────────────────────────────
def _write_dates(path: str, last: str, n: int = 40) -> None:
    d = pd.bdate_range(end=pd.Timestamp(last), periods=n)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    pq.write_table(pa.table({"Date": pa.array(d.date, type=pa.date32()),
                             "v": pa.array(range(n), type=pa.float64())}), path)


class Sandbox:
    """tmp 루트에 .cache/pins 구조를 세우고 PIN_SOURCES 를 그쪽으로 돌린다."""

    def __init__(self, live_last: str = "2026-08-28"):
        self.live_last = live_last

    def __enter__(self):
        self.tmp = tempfile.mkdtemp(prefix="aeplumb_")
        self.old_cwd = os.getcwd()
        self.old_sources = dict(ae.PIN_SOURCES)
        os.chdir(self.tmp)
        for base in ("fred_macro_wide.parquet", "benchmark.parquet"):
            _write_dates(os.path.join(self.tmp, ".cache", base), self.live_last)
        # carrier / period_returns 는 신선도 축 밖이지만 복사 단계에서 존재해야 한다.
        _write_dates(os.path.join(self.tmp, ".cache", "carrier.parquet"), self.live_last)
        with open(os.path.join(self.tmp, ".cache", "pr.csv"), "w", encoding="utf-8") as f:
            f.write("a,b\n1,2\n")
        ae.PIN_SOURCES = {
            "fred_macro_wide.parquet": ".cache/fred_macro_wide.parquet",
            "benchmark.parquet": ".cache/benchmark.parquet",
            "carrier_STR_1715_AR_on_M4_R05_overlay_PG2.parquet": ".cache/carrier.parquet",
            "period_returns_layer5.csv": ".cache/pr.csv",
        }
        os.makedirs(os.path.join(self.tmp, ".cache", "pins"), exist_ok=True)
        return self

    def __exit__(self, *a):
        ae.PIN_SOURCES = self.old_sources
        os.chdir(self.old_cwd)
        shutil.rmtree(self.tmp, ignore_errors=True)
        return False

    def make_pin(self, tag: str, last: str) -> str:
        d = os.path.join(".cache/pins", tag)
        os.makedirs(d, exist_ok=True)
        for base in ("fred_macro_wide.parquet", "benchmark.parquet"):
            _write_dates(os.path.join(d, base), last)
        shutil.copy2(".cache/carrier.parquet",
                     os.path.join(d, "carrier_STR_1715_AR_on_M4_R05_overlay_PG2.parquet"))
        shutil.copy2(".cache/pr.csv", os.path.join(d, "period_returns_layer5.csv"))
        with open(os.path.join(d, "manifest.json"), "w", encoding="utf-8") as f:
            f.write('{"tag":"%s"}' % tag)
        return d


def legacy_advance_pin(as_of: pd.Timestamp) -> str:
    """구판(수리 전) 재현 — 태그가 있으면 **무조건** 재사용. 돌연변이용."""
    tag = f"ae_monthly_{as_of.strftime('%Y%m')}"
    tag_dir = os.path.join(".cache/pins", tag)
    if os.path.isdir(tag_dir) and os.path.exists(os.path.join(tag_dir, "manifest.json")):
        return tag_dir
    raise AssertionError("픽스처 오류 — 구판 경로에 핀이 없다")


# ── 케이스 등록 ───────────────────────────────────────────────────────────────
CASES = []


def case(name):
    def deco(fn):
        CASES.append((name, fn))
        return fn
    return deco


# ══ 1. 핀 신선도 (결함 ②) ════════════════════════════════════════════════════
@case('PIN-1  신선한 핀은 그대로 재사용 (차단이 정상 운용을 막지 않는다)')
def _():
    with Sandbox() as s:
        d = s.make_pin("ae_monthly_202609", "2026-08-28")
        got = ae.advance_pin(AS_OF)
        assert os.path.abspath(got) == os.path.abspath(d), f"재사용 안 함: {got}"
        assert not os.path.isdir(d + ".stale"), "신선한데 이관됨"
    return "핀 재사용 · 재발행 없음"


@case('PIN-2  ★조기 생성된 낡은 핀 → 재사용 거부 (exit 2)')
def _():
    with Sandbox() as s:
        s.make_pin("ae_monthly_202609", "2026-07-24")   # 실측 조기 생성본과 같은 날짜
        try:
            ae.advance_pin(AS_OF)
        except SystemExit as e:
            assert e.code == 2, f"exit {e.code} (기대 2)"
            return "차단됨 (FRED 2026-07-24 핀, 9월 결정)"
    raise AssertionError("낡은 핀이 재사용됨 — 신선도 게이트 사망")


@case('PIN-3  --repin-stale 사유 제시 → 이관 + 감사기록 + 재발행')
def _():
    with Sandbox() as s:
        s.make_pin("ae_monthly_202609", "2026-07-24")
        got = ae.advance_pin(AS_OF, repin_stale="테스트: 조기 생성 핀 교체")
        assert os.path.isfile(os.path.join(got, "manifest.json")), "재발행 안 됨"
        fresh, note = ae.pin_freshness(got, AS_OF)
        assert fresh, f"재발행본이 여전히 낡음: {note}"
        arch = [d for d in os.listdir(".cache/pins") if d.startswith("ae_monthly_202609.stale_")]
        assert len(arch) == 1, f"낡은 핀 이관본 {len(arch)}개 (1개여야) — 지웠으면 감사 흔적 소실"
        aud = ".cache/pins/ae_monthly_repin.jsonl"
        assert os.path.isfile(aud), "감사 기록 없음 — '누가 왜 넘겼는지'가 사라진다"
        assert "테스트: 조기 생성 핀 교체" in open(aud, encoding="utf-8").read(), "사유 미기록"
    return f"이관 {arch[0]} + jsonl 기록 + 신선 핀 재발행"


@case('PIN-4  문턱 실증 — 허용치 이내는 통과, 초과는 차단')
def _():
    ref = AS_OF - pd.Timedelta(days=1)
    while ref.weekday() >= 5:
        ref -= pd.Timedelta(days=1)
    inside = (ref - pd.Timedelta(days=TOL)).strftime('%Y-%m-%d')
    outside = (ref - pd.Timedelta(days=TOL + 6)).strftime('%Y-%m-%d')
    with Sandbox() as s:
        ok_in, n_in = ae.pin_freshness(s.make_pin("p_in", inside), AS_OF)
        ok_out, n_out = ae.pin_freshness(s.make_pin("p_out", outside), AS_OF)
    assert ok_in, f"허용치 이내({inside})가 차단됨 — 오탐: {n_in}"
    assert not ok_out, f"허용치 초과({outside})가 통과됨 — 문턱 무효: {n_out}"
    return f"tol={TOL}d · {inside} 통과 / {outside} 차단"


@case('MUT-1  ★검출력 실증: 구판은 같은 낡은 핀을 그대로 쓴다')
def _():
    with Sandbox() as s:
        d = s.make_pin("ae_monthly_202609", "2026-07-24")
        got = legacy_advance_pin(AS_OF)             # 구판 = 무조건 재사용
        assert os.path.abspath(got) == os.path.abspath(d), "구판 재현 실패 — 돌연변이 무효"
        stale, note = ae.pin_freshness(got, AS_OF)
        assert not stale, "픽스처가 낡지 않음 — 돌연변이 무효"
        blocked = False
        try:
            ae.advance_pin(AS_OF)
        except SystemExit:
            blocked = True
        assert blocked, "신판이 안 막음"
    return "구판: 재사용(무검사) → 신판: exit 2"


# ══ 2. 라이브 원천 신선도 (핀 신선도만으로는 못 잡는 축) ══════════════════════
@case('SRC-1  ★라이브 원천이 낡으면 새 핀을 뜨지 않는다 (낡음을 핀으로 굳히지 않음)')
def _():
    # 핀은 아예 없다 → 신규 발행 경로. 그런데 라이브가 한 달 낡았다.
    with Sandbox(live_last="2026-07-24") as s:
        try:
            ae.advance_pin(AS_OF)
        except SystemExit as e:
            assert e.code == 2, f"exit {e.code} (기대 2)"
            assert not os.path.isdir(".cache/pins/ae_monthly_202609"), \
                "차단했는데 핀 디렉토리가 생성됨"
            return "차단됨 + 핀 미생성 (라이브 2026-07-24)"
    raise AssertionError("낡은 라이브로 핀이 발행됨 — 이 축이 없으면 핀 신선도는 lag 0 으로 통과한다")


@case('SRC-2  ★이 축이 없으면 핀 신선도는 눈이 먼다 (구멍 실증)')
def _():
    # 낡은 라이브를 그대로 복사한 핀은 '핀 vs 라이브' 비교에서 lag 0 → 통과한다.
    with Sandbox(live_last="2026-07-24") as s:
        d = s.make_pin("ae_monthly_202609", "2026-07-24")
        ok, note = ae.pin_freshness(d, AS_OF)
    assert ok, "픽스처 오류 — 핀==라이브인데 핀 신선도가 걸렸다"
    return "핀==라이브(둘 다 07-24) → 핀 신선도 통과 = SRC-1 축이 필요한 이유"


@case('SRC-3  라이브가 신선하면 신규 핀 발행이 정상 진행된다')
def _():
    with Sandbox(live_last="2026-08-28") as s:
        got = ae.advance_pin(AS_OF)
        assert os.path.isfile(os.path.join(got, "manifest.json")), "핀 미발행"
        ok, note = ae.pin_freshness(got, AS_OF)
        assert ok, f"발행본이 낡음: {note}"
    return "신규 핀 발행 OK"


# ══ 3. 배선 도달 (결함 ①) ════════════════════════════════════════════════════
def _runner_text() -> str:
    return open(RUNNER, encoding="utf-8").read()


def _code_lines(text: str) -> list[str]:
    """주석 제거 — 수리 주석이 구판 패턴/스크립트명을 **인용**하므로 원문 검사는 자기 설명에 걸린다."""
    return [ln for ln in text.split("\n") if not ln.lstrip().startswith("#")]


@case('WIRE-1  ★러너가 ae_regime_monthly.py 를 실제로 부른다 (배포 생성기 앞에서)')
def _():
    code = _code_lines(_runner_text())
    calls = [i for i, ln in enumerate(code) if "ae_regime_monthly.py" in ln]
    assert calls, "생산자 호출 0건 — 만들고 안 부르면 신호는 조용히 멈춘다(결함 ① 그대로)"
    gen = [i for i, ln in enumerate(code) if "GEN_SCRIPT" in ln and "RSCRIPT" in ln]
    assert gen, "배포 생성기 호출 지점을 못 찾음 — 러너 구조 변경 의심"
    assert min(calls) < min(gen), \
        f"AE 갱신이 배포 생성기 뒤에 있다 (AE line {min(calls)} vs gen {min(gen)}) — 소비 후 갱신은 무의미"
    assert "--advance-pin" in _runner_text(), "--advance-pin 미사용 → 동결 핀으로 굳는다"
    return f"AE 호출(line {min(calls)}) < 생성기 호출(line {min(gen)}) · --advance-pin 사용"


@case('WIRE-2  ★fail-closed — AE 실패를 경고로 삼키지 않는다')
def _():
    t = _runner_text()
    i = t.index("ae_regime_monthly.py")
    seg = t[i:i + 2200]
    assert re.search(r"_aerc", seg), "종료코드를 받지 않음"
    swallow = re.search(r'ae_regime_monthly\.py[^\n]*\|\|\s*(echo|say|true)', t)
    assert not swallow, f"실패를 삼킴: {swallow.group(0)[:80]}"
    exits = re.findall(r"exit\s+(\d+)", seg)
    assert len(exits) >= 4, f"중단 분기 {len(exits)}개 — parity/입력/PIT/기타를 다 막지 못함"
    for token in ("124", "PIT"):
        assert token in seg, f"'{token}' 분기 없음"
    return f"rc 분기 + exit {sorted(set(exits))} (타임아웃·parity·입력·PIT 전부 중단)"


@case('WIRE-3  ★데이터 리프레시가 AE 갱신보다 앞에 있다 (도훈 지시)')
def _():
    code = _code_lines(_runner_text())
    ref = [i for i, ln in enumerate(code) if "daily_refresh.sh" in ln]
    aei = [i for i, ln in enumerate(code) if "ae_regime_monthly.py" in ln]
    assert ref, "예약 경로에 데이터 리프레시가 없다 — 낡은 캐시 위에서 전부 계산된다"
    assert min(ref) < min(aei), \
        f"리프레시가 AE 뒤에 있다 (refresh {min(ref)} vs AE {min(aei)}) — 핀이 낡은 원천을 굳힌다"
    assert "PG2_REFRESH_DONE" in _runner_text(), "중복 실행 방지 플래그 없음"
    full = open(FULL, encoding="utf-8").read()
    assert "PG2_REFRESH_DONE" in full, \
        "full 러너가 플래그를 안 내려보냄 → [0]/[1] 과 [2] 안에서 리프레시가 두 번 돈다"
    return f"refresh(line {min(ref)}) < AE(line {min(aei)}) · 상·하위 플래그 정합"


@case('WIRE-MUT  ★검출력 실증: AE 스텝을 지운 사본에서 WIRE-1 이 발화한다')
def _():
    stripped = "\n".join(ln for ln in _runner_text().split("\n")
                         if "ae_regime_monthly.py" not in ln)
    code = _code_lines(stripped)
    assert not [i for i, ln in enumerate(code) if "ae_regime_monthly.py" in ln], \
        "돌연변이 무효 — 지웠는데 여전히 검출됨"
    # 그리고 원본에서는 검출된다 = 검사가 살아 있다
    assert [i for i, ln in enumerate(_code_lines(_runner_text())) if "ae_regime_monthly.py" in ln], \
        "원본에서 미검출 — 검사기 사망"
    return "제거본 미검출 / 원본 검출 (검사가 실제로 배선을 본다)"


@case('WIRE-4  소비자 소스는 운영 정본을 가리킨다 (동결 실험본 ae_regime_extend.py 아님)')
def _():
    gen = open(os.path.join(ROOT, "02_Infrastructure/portfolio/forward_weights_D3_M4gAE.R"),
               encoding="utf-8").read()
    code = "\n".join(ln for ln in gen.split("\n") if not ln.lstrip().startswith("#"))
    assert "ae_regime_extend.py" not in code, \
        "부재 메시지가 동결 실험본을 가리킨다 — 그걸 부르면 같은 223행 재생산(침묵 no-op)"
    assert "ae_regime_monthly.py" in code, "운영 정본 안내가 없음"
    return "ae_regime_monthly.py 안내 · extend 참조 0"


def main() -> int:
    print("=" * 78)
    print("test_ae_monthly_plumbing — AE 월간 배관(핀 신선도 · 원천 신선도 · 배선)")
    print("=" * 78)
    npass, fails = 0, []
    for name, fn in CASES:
        try:
            note = fn()
            npass += 1
            print(f"  PASS  {name}\n          {note}")
        except Exception as e:
            fails.append((name, e))
            print(f"  ★FAIL {name}\n          {type(e).__name__}: {e}")
            traceback.print_exc()
        finally:
            os.chdir(_cwd_before)
    print("-" * 78)
    print(f"  {npass}/{len(CASES)} PASS")
    if fails:
        print("  ★실패:", ", ".join(n for n, _ in fails))
    print('{"test":"ae_monthly_plumbing","pass":%d,"fail":%d,"total":%d,"skipped":0}'
          % (npass, len(fails), npass + len(fails)))
    return 0 if not fails else 1


if __name__ == "__main__":
    sys.exit(main())
