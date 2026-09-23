"""test_naver_benchmark_confirmed_cutoff.py — 네이버 벤치 경로 마감 가드 (2026-09-23 실사고 재발 방지)

실사고: 절전 뒤 따라잡기 실행(14:21, 장중)이 `end_date = datetime.now()` 로 진행 중 봉 1120.74 를
  09-23 종가로 붙였다 → 국면·P3 전파(09-10 에도 동일). RAWDATA 경로에는 이미 16시 가드가 있었다.
재는 것:
  A. 양성 대조 — 16:40 에는 당일 행이 붙는다
  B. 위반 주입 — 14:25 에는 당일 행이 **붙지 않는다**(검증 모드 비교에서도 제외)
  C. 돌연변이 — 가드를 끈 판(CONFIRM_HOUR=0)은 14:25 에 당일 행을 붙인다 → A/B 가 판별력 있음
  D. 규칙 단일성 — CONFIRM_HOUR 가 trading_calendar.R:311 의 `hour >= 16` 과 같은 값
운영 파일 무접촉: BM_PATH·fetch·경보 함수를 전부 임시로 교체한다(경보 기본 인자가 정의 시점에 묶이므로 함수 자체를 교체).
"""
import os, re, sys, shutil, tempfile
from datetime import datetime
from pathlib import Path

ROOT = Path(os.environ.get("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
sys.path.insert(0, str(ROOT / "02_Infrastructure" / "data"))
import pandas as pd  # noqa: E402
import naver_benchmark_update as NB  # noqa: E402

P = F = 0
def ok(m):
    global P; P += 1; print(f"  OK   {m}")
def ng(m, d=""):
    global F; F += 1; print(f"  FAIL {m} — {d}")

real = pd.read_parquet(ROOT / ".cache" / "benchmark.parquet")
real["Date"] = pd.to_datetime(real["Date"])
real = real.sort_values("Date").reset_index(drop=True)
TODAY = real["Date"].iloc[-1]                     # 픽스처의 '당일' = 실제 마지막 확정일(값이 진짜라 트립와이어가 통과)
base = real[real["Date"] < TODAY].copy()          # 캐시 = 당일 직전까지
fixture = real[["Date", "BM_Close"]].rename(columns={"BM_Close": "Close"}).tail(60).reset_index(drop=True)

tmp = Path(tempfile.mkdtemp())
alerts = []
NB.fetch_naver_kospi = lambda s, e, symbol="KPI200": fixture.copy()   # 네트워크 없음 — 픽스처(실제 값) 그대로
NB.BA.write_alert = lambda *a, **k: alerts.append(a[0] if a else "?")
NB.BA.clear_alert = lambda *a, **k: None

def run_at(hh, mm, mutate_hour=None):
    p = tmp / f"bm_{hh}{mm}_{mutate_hour}.parquet"
    base.to_parquet(p)
    NB.BM_PATH = p
    old = NB.CONFIRM_HOUR
    if mutate_hour is not None:
        NB.CONFIRM_HOUR = mutate_hour
    try:
        rc = NB.run(None, None, do_append=True, backup=False, quiet=True,
                    now=datetime(TODAY.year, TODAY.month, TODAY.day, hh, mm))
    finally:
        NB.CONFIRM_HOUR = old
    out = pd.read_parquet(p); out["Date"] = pd.to_datetime(out["Date"])
    return rc, TODAY in set(out["Date"])

print("=== A. 양성 대조 — 마감 후(16:40) 당일 행 추가 ===")
rc, has = run_at(16, 40)
ok(f"A1 16:40 → 당일 {TODAY.date()} 추가(rc={rc})") if has and rc == 0 else ng("A1 마감 후 추가 실패", f"rc={rc} has={has}")

print("=== B. 위반 주입 — 장중(14:25) 당일 행 차단 ===")
rc, has = run_at(14, 25)
ok(f"B1 14:25 → 당일 행 미추가(rc={rc})") if (not has) and rc == 0 else ng("B1 ★장중 봉이 종가로 붙었다", f"rc={rc} has={has}")
c = NB.confirmed_cutoff(datetime(TODAY.year, TODAY.month, TODAY.day, 14, 25))
ok(f"B2 확정 상한 = 전일({c.date()})") if c < TODAY else ng("B2 상한", str(c))

print("=== C. 돌연변이 — 가드 끈 판은 장중에 붙인다(판별력) ===")
rc, has = run_at(14, 25, mutate_hour=0)
ok("C1 CONFIRM_HOUR=0 돌연변이는 14:25 에 당일 행을 붙인다 → B1 이 가드를 재고 있다") if has else ng("C1 판별력 없음", f"rc={rc} has={has}")

print("=== D. 규칙 단일성 — trading_calendar.R:311 과 같은 시각 ===")
tc = (ROOT / "02_Infrastructure" / "data" / "trading_calendar.R").read_text(encoding="utf-8")
m = re.search(r"hour\s*>=\s*(\d+)\s*&&\s*today\s*%in%\s*cal\$Date", tc)
if m and int(m.group(1)) == NB.CONFIRM_HOUR:
    ok(f"D1 CONFIRM_HOUR={NB.CONFIRM_HOUR} == trading_calendar.R 규칙 {m.group(1)}")
else:
    ng("D1 두 규칙이 갈렸다", f"py={NB.CONFIRM_HOUR} R={m.group(1) if m else '찾지 못함'}")

shutil.rmtree(tmp, ignore_errors=True)
print(f"\n합계: 통과 {P} · 실패 {F}")
print('{"test":"naver_benchmark_confirmed_cutoff","pass":%d,"fail":%d,"total":%d}' % (P, F, P + F))
sys.exit(1 if F else 0)
