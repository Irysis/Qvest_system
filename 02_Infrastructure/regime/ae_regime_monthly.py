#!/usr/bin/env python
"""ae_regime_monthly.py — D3 게이트용 AE 신호 월간 배관 (운영 정본).

**왜 신설인가**: 원본 `stage_artifacts/WT_D20260718_007/ae_regime_extend.py` 는 실험 런의
일회성 확장기다 — `EXTRA_DECISIONS=["2026-06-01","2026-07-01"]` 하드코딩이라 그대로 호출하면
**동일 223행을 재생산하는 침묵 no-op** 이 된다. 그리고 그 디렉토리는 감사 증거로 동결이라
고쳐 쓸 수 없다(artifact-storage.md ①). 따라서 운영 스크립트를 여기 둔다.

**해결하는 결함** (2026-08-01 감사 실측):
  - AE 신호에 **생산자가 아예 없었다** — 예약작업 0건, `.sh/.ps1/.xml` 참조 0건.
    `D3_SWAPIN_READINESS.md §3` 이 "월간 배관 배선"을 미완으로 명시.
  - 생산 R(`forward_weights_R05_noLayer4_M4gAE.R:51`)은 AS_OF 행이 없으면 **조용히 직전 달
    행을 재사용**한다. PIT 가드(`last_feat < AS_OF`)는 낡음을 구조적으로 못 잡는다.
    실측: 2026-08-01 배포가 decision 2026-07-01(last_feat 2026-06-30) = **32일 묵은 AE** 를 썼다.
    (그 달은 m4 미발화라 gate=1.00 → 비중값 영향 0이었으나, m4 발화월이면 30% de-risk 오판)

**재-핀 정책 = (c) 핀 전진 + 전량 재계산 + 동결-이력 parity 게이트**:
  - (a) 단순 재-핀은 위험 — 라이브 FRED 가 **과거를 개정**한다(실측: `StL_Fin_Stress` 1,303셀
    2000-01-14부터, `Chi_Fin_Cond` 206셀). mu/sd/Xz 가 이동해 과거 결정이 바뀔 수 있다.
  - (b) 핀 고정은 성립 불가 — 핀 패널이 2026-07-16 에서 끝나 이후 모든 결정이 같은 end 인덱스를
    잡아 `ae_seq` 가 상수로 동결되고, loose==strict 가 되어 스크립트 자체의 look-ahead A/B
    계측기까지 침묵한다.
  - → 핀은 전진시키되, **이미 발행된 행이 하나라도 바뀌면 중단**한다(parity 게이트).
    "과거는 안 바뀔 것"이라는 믿음을 "안 바뀌었음을 확인"으로 바꾼다.

사용:
  python ae_regime_monthly.py --as-of 2026-09-01 [--pin-dir <dir>] [--dry-run]
  (--as-of 의 **당월 1일**이 결정일. holding month = month(decision_date), offset 0 — 실측 정렬.
   원본 헤더의 "holding = decision월+1" 표기는 오기다.)

종료코드: 0 정상 / 1 parity 위반(과거 행 변경) / 2 입력·환경 오류 / 3 PIT 위반
"""
from __future__ import annotations

import argparse
import os
import sys

import numpy as np
import pandas as pd
import pyarrow.parquet as pq

ROOT = os.environ.get("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot").replace("\\", "/")
os.chdir(ROOT)

# 원본과 동일한 상수 — 변경 금지(모델 정합). 원본: stage_artifacts/WT_D20260718_007/ae_regime_extend.py
SEED = 20260718
OUT = "stage_artifacts/WT_D20260718_007/ae_regime_signal_ext.parquet"   # 예외 등재된 운영 소비 신호
DEFAULT_PIN = ".cache/pins/WT-D20260718_007_r1"
SRC = "stage_artifacts/WT_D20260718_007/ae_regime_extend.py"            # 동결 원본(읽기만)

KEY = "decision_date"
# ── parity 2계층 (2026-08-01 도훈 A안 승인) ────────────────────────────────
#   실측 근거: 핀 07-16→07-24 전진 시 FRED 과거 개정 1,544셀(StL_Fin_Stress 1,303 등)로
#   ae_seq 221/223행 · tau_seq 223/223행이 이동했으나, **fire_seq·exposure_seq 는 0/223 불변**
#   (Δ 중앙값 +0.0000 · 최대 0.0465 vs 임계 ~1.05 → 발화/미발화 뒤집힘 0건).
#   → 점수 미세 이동으로 배관을 막으면 AE 가 영구 동결된다(신선도 상실이 더 큰 위험).
#     대신 **판정이 바뀌는 순간에는 여전히 멈춘다** — 게이트를 없앤 게 아니라 조인 것.
DECISION_COLS = ["fire_seq", "exposure_seq", "last_feat_date"]   # 변경 = hard block
SCORE_COLS = ["ae_seq", "tau_seq"]                               # 변경 = 로그만 (크기 보고)


# 핀 전진용 라이브 원본 (2026-08-01 실측으로 확인한 경로)
PIN_SOURCES = {
    "fred_macro_wide.parquet": ".cache/fred_macro_wide.parquet",
    "benchmark.parquet": ".cache/benchmark.parquet",
    "carrier_STR_1715_AR_on_M4_R05_overlay_PG2.parquet":
        "06_Registry/book_carrier/carrier_STR_1715_AR_on_M4_R05_overlay_PG2.parquet",
    "period_returns_layer5.csv":
        "05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/"
        "04_backtest_results/period_returns_layer5.csv",
}
FROZEN_PIN = DEFAULT_PIN   # r1 = D3 졸업 근거 핀. 절대 덮지 않는다.


def die(code: int, msg: str):
    print(f"[ae-monthly] ERROR {msg}")
    sys.exit(code)


def advance_pin(as_of: pd.Timestamp) -> str:
    """월별 새 핀 태그를 만들어 라이브 원본을 복사한다.

    ★r1(`WT-D20260718_007_r1`)은 D3 졸업 근거라 **덮지 않는다** — 새 태그를 만든다.
    ★왜 전진이 필요한가: 핀을 고정하면 패널 종점(2026-07-16) 이후 모든 결정이 같은 end
      인덱스를 잡아 ae_seq 가 상수로 얼어붙고, loose==strict 가 되어 스크립트 자체의
      look-ahead A/B 계측기까지 침묵한다(실측 확인).
    ★왜 위험한가: 라이브 FRED 는 **과거를 개정**한다. 2026-08-01 실측 — 핀(07-16) 대비
      라이브(07-24) 사이 공통 8,220일 구간에서 1,544셀 변경. StL_Fin_Stress 1,303셀
      (2000-01-14부터) · Chi_Fin_Cond 206셀 — 둘 다 AE 입력 피처다.
      그래서 전진 자체는 허용하되 **parity 게이트가 반드시 뒤를 막는다**.
    """
    tag = f"ae_monthly_{as_of.strftime('%Y%m')}"
    tag_dir = os.path.join(".cache/pins", tag)
    if os.path.isdir(tag_dir) and os.path.exists(os.path.join(tag_dir, "manifest.json")):
        print(f"[ae-monthly] 핀 {tag} 이미 존재 — 재사용 (핀은 태그당 불변)")
        return tag_dir
    os.makedirs(tag_dir, exist_ok=True)
    import hashlib
    import json
    import shutil
    files = []
    for base, src in PIN_SOURCES.items():
        if not os.path.exists(src):
            die(2, f"핀 원본 부재: {src} (기대 basename {base})")
        dst = os.path.join(tag_dir, base)
        shutil.copy2(src, dst)
        raw = open(dst, "rb").read()
        files.append({"basename": base, "md5": hashlib.md5(raw).hexdigest(),
                      "size_bytes": len(raw), "source": src})
    json.dump({"tag": tag,
               "created_at": as_of.strftime("%Y-%m-%d") + " (AS_OF 기준)",
               "provenance": f"월간 리밸 핀 전진 — 라이브 원본 복사. 동결 근거핀({FROZEN_PIN}) 미변경. "
                             f"과거 개정 검출은 parity 게이트가 담당.",
               "files": files},
              open(os.path.join(tag_dir, "manifest.json"), "w", encoding="utf-8"),
              ensure_ascii=False, indent=2)
    print(f"[ae-monthly] 핀 전진 → {tag} ({len(files)}파일 복사)")
    return tag_dir


def load_frozen_source() -> str:
    """동결 원본을 읽어 문자열로 반환. 수정하지 않는다."""
    if not os.path.exists(SRC):
        die(2, f"원본 부재: {SRC}")
    return open(SRC, encoding="utf-8").read()


def run_walkforward(decisions: list[str], pin_dir: str, out_path: str):
    """원본 로직을 그대로 실행하되 결정목록·핀·출력만 주입.

    동결 원본을 텍스트로 읽어 상수 3개만 치환 후 exec 한다 — 로직 복사본을 만들면
    원본과 갈라져 '어느 쪽이 정본인가' 문제가 생긴다(오늘 2-3/2-4 미러에서 sha1 대조가
    필요했던 이유와 같은 계통). 치환은 상수 라인 3개로 한정한다.
    """
    src = load_frozen_source()
    subs = [
        ('EXTRA_DECISIONS=["2026-06-01","2026-07-01"]',
         f'EXTRA_DECISIONS={decisions!r}'),
        ('PIN=".cache/pins/WT-D20260718_007_r1"',
         f'PIN={pin_dir!r}'),
        (f'OUT="{OUT}"', f'OUT={out_path!r}'),
    ]
    for old, new in subs:
        if old not in src:
            die(2, f"원본에서 치환 대상을 찾지 못함(원본 변경 의심): {old[:48]}...")
        src = src.replace(old, new, 1)

    # 연도 루프 상한 하드코딩 제거 — 원본 `range(OOS_START_YEAR,2027)` 은 2027년 결정을
    # **조용히 건너뛴다**(yr_dec 이 비어 행이 안 생기고 오류도 없음).
    max_year = max(pd.Timestamp(d).year for d in decisions)
    src = src.replace("for year in range(OOS_START_YEAR,2027):",
                      f"for year in range(OOS_START_YEAR,{max_year + 1}):", 1)

    g = {"__name__": "__ae_monthly__"}
    exec(compile(src, SRC, "exec"), g)      # noqa: S102 — 동결 원본 로직 재사용이 목적
    g["main"]()


def _changed(o: pd.DataFrame, n: pd.DataFrame, common, col):
    """공통 행에서 col 이 바뀐 인덱스 + 변화 크기."""
    a, b = o.loc[common, col], n.loc[common, col]
    if pd.api.types.is_numeric_dtype(a):
        af, bf = a.astype(float), b.astype(float)
        bad = common[~np.isclose(af, bf, rtol=1e-9, atol=1e-12, equal_nan=True)]
        mx = float(np.nanmax(np.abs(bf - af))) if len(bad) else 0.0
    else:
        bad = common[a.astype(str).values != b.astype(str).values]
        mx = float("nan")
    return bad, mx


def parity_check(old_path: str, new_df: pd.DataFrame) -> tuple[bool, str]:
    """2계층 parity — 판정(DECISION_COLS)이 바뀌면 중단, 점수(SCORE_COLS)는 로그만.

    "과거는 안 바뀔 것"이라는 믿음을 "무엇이 얼마나 바뀌었는지 측정"으로 바꾼다.
    """
    if not os.path.exists(old_path):
        return True, "기존 파일 없음 — parity 대조 생략(최초 생성)"
    o = pq.read_table(old_path).to_pandas().set_index(KEY)
    n = new_df.set_index(KEY)
    common = o.index.intersection(n.index)
    if len(common) == 0:
        return True, "공통 결정일 없음"

    hard = []
    for c in DECISION_COLS:
        if c not in o.columns or c not in n.columns:
            continue
        bad, _ = _changed(o, n, common, c)
        if len(bad):
            ex = ", ".join(str(pd.Timestamp(x).date()) for x in bad[:4])
            hard.append(f"{c}: {len(bad)}행 (예: {ex})")

    soft = []
    for c in SCORE_COLS:
        if c not in o.columns or c not in n.columns:
            continue
        bad, mx = _changed(o, n, common, c)
        if len(bad):
            soft.append(f"{c} {len(bad)}/{len(common)}행(최대 Δ{mx:.4f})")

    note = f"과거 {len(common)}행 · 판정 " + ("★변경 " + " / ".join(hard) if hard else "불변")
    if soft:
        note += " · 점수 " + ", ".join(soft) + " (FRED 과거 개정 반영 — A안 채택으로 통과)"
    return (not hard), note


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--as-of", required=True, help="홀딩월 1일 (예: 2026-09-01). 결정일 = 이 날짜")
    ap.add_argument("--pin-dir", default=None,
                    help="핀 디렉토리 명시. 미지정 시 --advance-pin 여부에 따라 결정")
    ap.add_argument("--advance-pin", action="store_true",
                    help="라이브 원본으로 월별 새 핀을 만들어 사용 (r1 동결 유지). "
                         "리밸런싱 배선의 기본 경로 — 도훈 지시 2026-08-01")
    ap.add_argument("--dry-run", action="store_true", help="산출만 하고 기존 파일 미교체")
    a = ap.parse_args()

    as_of = pd.Timestamp(a.as_of)
    if as_of.day != 1:
        die(2, f"--as-of 는 월 1일이어야 함 (holding month = month(decision_date), offset 0): {a.as_of}")
    dec_str = as_of.strftime("%Y-%m-%d")

    # 이미 그 결정일이 있으면 재계산 불필요 — 다만 '있다'를 신선함으로 착각하지 않도록 값을 보여준다.
    if os.path.exists(OUT):
        cur = pq.read_table(OUT).to_pandas()
        cur[KEY] = pd.to_datetime(cur[KEY])
        if (cur[KEY] == as_of).any():
            r = cur[cur[KEY] == as_of].iloc[0]
            print(f"[ae-monthly] 결정일 {dec_str} 이미 존재 — fire_seq={int(r['fire_seq'])} "
                  f"last_feat={pd.Timestamp(r['last_feat_date']).date()} (재계산 생략)")
            return 0
        print(f"[ae-monthly] 기존 max decision_date = {cur[KEY].max().date()} → {dec_str} 추가")

    if a.pin_dir:
        pin_dir = a.pin_dir
    elif a.advance_pin:
        pin_dir = advance_pin(as_of)
    else:
        pin_dir = DEFAULT_PIN
        print(f"[ae-monthly] 동결 핀 사용 ({pin_dir}) — 신선도 한계 있음. "
              f"리밸런싱 경로는 --advance-pin 을 쓴다")
    for f in ("fred_macro_wide.parquet", "benchmark.parquet",
              "carrier_STR_1715_AR_on_M4_R05_overlay_PG2.parquet"):
        p = os.path.join(pin_dir, f)
        if not os.path.exists(p):
            die(2, f"핀 파일 부재: {p}")
    fr = pd.to_datetime(pq.read_table(os.path.join(pin_dir, "fred_macro_wide.parquet"),
                                      columns=["Date"]).to_pandas()["Date"])
    print(f"[ae-monthly] 핀 = {pin_dir} · FRED max {fr.max().date()}")
    if fr.max() >= as_of:
        die(3, f"PIT: 핀 FRED({fr.max().date()})가 결정일({dec_str}) 이후까지 있음 — 미래참조")

    # 기존 결정 + 신규 1건을 전량 재계산 (원본은 carrier 결정목록에 EXTRA 를 union)
    existing = []
    if os.path.exists(OUT):
        e = pq.read_table(OUT, columns=[KEY]).to_pandas()[KEY]
        existing = [pd.Timestamp(x).strftime("%Y-%m-%d") for x in pd.to_datetime(e)]
    decisions = sorted(set(existing + [dec_str]))
    print(f"[ae-monthly] 결정목록 {len(decisions)}건 (신규 {dec_str}) — 전량 재계산")

    tmp = OUT + ".new"
    run_walkforward(decisions, pin_dir, tmp)
    if not os.path.exists(tmp):
        die(2, "재계산 산출물 미생성")

    new = pq.read_table(tmp).to_pandas()
    new[KEY] = pd.to_datetime(new[KEY])

    # ── PIT hard fail (원본은 print 만 하고 통과시킨다) ──────────────────────
    bad = int((pd.to_datetime(new["last_feat_date"]) >= new[KEY]).sum())
    if bad:
        os.remove(tmp)
        die(3, f"PIT 위반 {bad}행 (last_feat_date >= decision_date) — 원본은 경고만 했으나 여기서 차단")
    print(f"[ae-monthly] PIT self-check 통과 (위반 0행)")

    # ── parity 게이트 ────────────────────────────────────────────────────────
    ok, note = parity_check(OUT, new)
    print(f"[ae-monthly] parity: {note}")
    if not ok:
        keep = OUT + ".parity_reject"
        os.replace(tmp, keep)
        die(1, f"과거 발행 행이 변경됨 — 교체 중단. FRED 과거 개정 의심. "
               f"재계산본 보존: {keep} (개정 시리즈 특정 후 사람 판단)")

    if a.dry_run:
        print(f"[ae-monthly] dry-run — 교체 안 함. 산출: {tmp}")
        return 0

    os.replace(tmp, OUT)
    r = new[new[KEY] == as_of]
    if len(r):
        r = r.iloc[0]
        print(f"[ae-monthly] 갱신 완료 — {dec_str}: fire_seq={int(r['fire_seq'])} "
              f"ae_seq={float(r['ae_seq']):.4f} tau={float(r['tau_seq']):.4f} "
              f"last_feat={pd.Timestamp(r['last_feat_date']).date()}")
    else:
        die(2, f"신규 결정일 {dec_str} 이 산출물에 없음 — 채점 실패(패널 범위 확인)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
