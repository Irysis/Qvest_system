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

**★PIT C11 수리 (2026-09-24 · 판정서 V-03 · 결정 PIT-C11-REMEDIATION 안 B · 1단계 코드)**:
  동결 원본의 `build_panel()`(ae_regime_extend.py:34-48)은 해외 특성을 **미국 관측일(라벨)** 로 붙였다
  (`merge_asof(..., on="Date")`) — 한국 d 행에 미국 d 종가와 공표 전 주간값(STLFSI4 +7일·NFCI +6일)이 실렸다.
  이 러너는 이제 원본을 exec 한 뒤 **`build_panel` 한 함수만** `ae_pit_features.build_pit_panel` 로 바꿔 끼운다
  (모델·학습·채점·tau 는 원본 그대로). 해외 특성은 기반(S0) 도우미 `fred_asof_join(mode="decision_close")`
  로만 결합되고, 원/달러는 DEXKOUS(prohibited) 대신 ECOS 731Y001(핀의 `ecos_krw_usd.parquet`) 을 쓴다
  (결정 PIT-C11-CONVENTIONS ①). 동결 원본 파일은 **수정하지 않는다**(artifact-storage.md ①ⓒ — 감사 증거는
  '수리 전 판이 무엇이었나'의 기록이다).
  산출 행에는 C11 표식 4열(c11_feat_join · c11_regime_key · c11_fred_avail_max · c11_info_cutoff)이 붙는다.
  ★전환 효과: 기존 발행 행은 수리 전 판이라 다음 실행의 전량 재계산이 판정(fire_seq)을 바꾸면 parity 게이트가
  **막는다**(exit 1). 그것이 맞다 — 오염 이력의 침묵 덮어쓰기도, 오염 이력 위 신규 행 이어붙이기도 하지 않는다.
  2단계 재산출(결정 PIT-C11-BOOK0001)에서 사람이 `--accept-parity '<사유>'` 로 넘긴다.

**★C11 2단계 준비 (2026-09-24 · 결정 PIT-C11-AE-1003 "AE 전 이력 재산출을 10-01 전에 선행 → 10-03 정상 실행")**:
  ① **핀 PIT 절단** — 월간 예약 실행은 매월 3일 09:00(noLayer4_Monthly_PaperTracking)이라 라이브 FRED 에 이미
     결정일(as_of) 이후 관측이 있다. 구판 advance_pin 은 라이브를 **통째로** 복사했고, 아래 `fr.max() >= as_of`
     PIT 검사가 그 핀을 막아(exit 3 → 러너 exit 19) 당월 행이 사전 생성되지 않은 달은 **예약 경로가 완주할 수 없었다**
     (2026-09 는 08-30 수동 사전 생성이라 가려졌다). 핀은 '결정 시점에 알 수 있었던 것'이어야 하므로 Date 축 원천
     (FRED 와이드 · 벤치마크 · ECOS 원/달러)을 **Date < as_of 로 절단해** 복사한다. 관측일 >= as_of 인 해외 관측은
     가용일이 as_of 이후라(가용일 >= 관측일) 결정 창에 들어갈 수 없으므로 절단은 PIT 상 무손실이다. PIT 검사는 그대로 둔다
     (--pin-dir 로 넘긴 사람 핀에는 여전히 이빨이다).
  ② **핀 완결성** — 태그가 있어도 PIN_SOURCES 중 빠진 파일이 있으면(C11 이전에 뜬 핀 = ECOS 부재) 재사용하지 않는다.
     재발행은 낡은 핀과 같은 경로(--repin-stale '<사유>' — 지우지 않고 이관 + 감사 기록)로만.
  ③ **--recompute '<사유>'** — 결정일 행이 이미 있으면 재계산을 생략하는 규칙을, 사유를 남기고 넘는다(최신 결정일 한정).
     전 이력 C11 재산출(parity 차단은 여전히 --accept-parity 로 따로 넘긴다 — 두 사람 판단을 합치지 않는다).
  ④ 과거 결정일 삽입(as_of < 기존 최대 결정일) + 핀 전진 = 거부 — 절단(as_of)이 뒤 결정들의 창을 자른다.
  ⑤ --dry-run 은 감사 기록(parity_override · recompute jsonl)을 쓰지 않는다(구판은 dry-run 에서도 override 를 적었다).

종료코드: 0 정상 / 1 parity 위반(과거 행 변경) / 2 입력·환경 오류 / 3 PIT 위반
"""
from __future__ import annotations

import argparse
import os
import sys

import numpy as np
import pandas as pd
import pyarrow.parquet as pq

_REGIME_DIR = os.path.dirname(os.path.abspath(__file__))
if _REGIME_DIR not in sys.path:
    sys.path.insert(0, _REGIME_DIR)
import ae_pit_features as aepf  # noqa: E402  (C11 가용시점 결합 — 해외 특성의 유일한 결합 경로)

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
    # 2026-08-02 정리 2단계: 2-1 정적 사본(철거 대상) → WT-H rerun 정본(매월 재생성)
    "period_returns_layer5.csv":
        "qepm/mailbox/worktask/WT-H20260513_001/output/period_returns_layer5.csv",
    # 2026-09-24 PIT C11: 원/달러 특성 원천 = ECOS 731Y001 (DEXKOUS prohibited · PIT-C11-CONVENTIONS ①)
    aepf.ECOS_KRW_FILE: ".cache/ecos_krw_usd.parquet",
}
FROZEN_PIN = DEFAULT_PIN   # r1 = D3 졸업 근거 핀. 절대 덮지 않는다.


def _now_stamp() -> str:
    """이관 디렉토리 접미사용 타임스탬프. 모델 입력이 아니라 **파일명 유일화**에만 쓴다."""
    from datetime import datetime
    return datetime.now().strftime("%Y%m%d_%H%M%S")


def die(code: int, msg: str):
    print(f"[ae-monthly] ERROR {msg}")
    sys.exit(code)


# ── 핀 신선도 (2026-08-30 신설) ───────────────────────────────────────────────
#   "존재한다" 를 "쓸 수 있다" 로 읽지 않기 위한 축. 아래 advance_pin 참조.
#   ★문턱 14일은 실측으로 재단했다(2026-08-30). 두 양을 갈라야 한다:
#     · **원천의 발행지연**(정상) — 결정일에 정직하게 뜬 핀도 FRED 주간계열 때문에 뒤진다.
#       실측: 2026-08-01 에 뜬 `ae_monthly_202608` 핀 = FRED lag 7d · benchmark lag 0d.
#     · **핀의 낡음**(결함) — 실측: 조기 생성된 `ae_monthly_202609` = FRED 35d · bench 28d.
#     7 로 두면 정상 핀이 경계에 정확히 걸려 오탐이 난다. 14 는 정상(7)에 2배 여유를 주고
#     결함(28~35)을 2배 차로 막는다. 한 달 선행 생성은 어떤 원천 지연으로도 설명되지 않는다.
PIN_FRESHNESS_TOL_DAYS = 14
#   Date 축이 있는 핀 파일만 검사한다. carrier/period_returns 는 월 단위 스냅샷이라
#   일 단위 신선도 축이 성립하지 않는다(검사하면 상시 오탐).
PIN_FRESHNESS_FILES = ("fred_macro_wide.parquet", "benchmark.parquet")
#   ★핀 PIT 절단 대상(2026-09-24) — 특성 패널을 만드는 **일간 Date 축** 원천만. carrier(결정목록)·period_returns 는
#   특성이 아니고 Date 축도 아니라 그대로 복사한다. 목록 밖 파일에 Date 열이 있어도 건드리지 않는다(명시 목록).
PIN_TRUNCATE_FILES = ("fred_macro_wide.parquet", "benchmark.parquet", aepf.ECOS_KRW_FILE)


def _pin_copy(src: str, dst: str, as_of: pd.Timestamp, base: str) -> dict:
    """핀 원천 1개를 복사한다. PIN_TRUNCATE_FILES 는 **Date < as_of** 행만(결정 시점 정보집합) — 스키마·메타데이터 보존.

    반환 = manifest 항목(절단 기록 포함). 절단 대상인데 Date 열이 없으면 거부(무엇을 잘랐는지 모르는 핀은 뜨지 않는다).
    """
    import hashlib
    import shutil
    rec = {"basename": base, "source": src}
    if base in PIN_TRUNCATE_FILES:
        t = pq.read_table(src)
        if "Date" not in t.column_names:
            die(2, f"핀 절단 대상 {base} 에 Date 열이 없다({src}) — 결정 시점 절단 불가, 핀을 뜨지 않는다")
        d = pd.to_datetime(t.column("Date").to_pandas())
        keep = (d < as_of).to_numpy()
        import pyarrow as pa
        t2 = t.filter(pa.array(keep))
        pq.write_table(t2, dst)
        rec["truncated"] = {"rule": "Date < as_of", "as_of": as_of.strftime("%Y-%m-%d"),
                            "rows_source": int(t.num_rows), "rows_kept": int(t2.num_rows),
                            "rows_dropped": int(t.num_rows - t2.num_rows),
                            "source_max": str(d.max().date()) if len(d) else None,
                            "pin_max": str(d[keep].max().date()) if keep.any() else None}
    else:
        shutil.copy2(src, dst)
    raw = open(dst, "rb").read()
    rec["md5"] = hashlib.md5(raw).hexdigest()
    rec["size_bytes"] = len(raw)
    return rec


def _max_date(path: str) -> pd.Timestamp | None:
    """parquet 의 Date 최대값. 판독 불가면 None (=미측정, '신선함'으로 접지 않는다)."""
    try:
        d = pd.to_datetime(pq.read_table(path, columns=["Date"]).to_pandas()["Date"])
        return d.max() if len(d) else None
    except Exception:
        return None


def pin_freshness(pin_dir: str, as_of: pd.Timestamp) -> tuple[bool, str]:
    """핀이 **결정일 시점에 구할 수 있었던 만큼** 신선한지 판정한다.

    ★왜 (2026-08-30 실측 · 도훈 지시):
      `advance_pin` 은 태그가 있으면 무조건 재사용했다("핀은 태그당 불변"). 그런데
      `ae_monthly_202609` 핀이 **2026-08-01 22:33 에 미리 만들어져** FRED 2026-07-24 ·
      benchmark 2026-07-31 로 굳어 있었다 — 9월 결정이 7월 피처를 쓴다.
      재현성을 지키려던 규칙이 **신선도를 죽인 것**이다. 조기 생성본 보존:
      `.cache/pins/ae_monthly_202609.premature_minted_20260801`.
      관련 카드: feedback-a-gate-blocking-a-correction-looks-like-one-blocking-corruption

    ★기준선은 '오늘'이 아니라 **as_of 직전의 라이브 최대일**이다. 이렇게 잡아야
      (a) 조기 생성 핀은 반드시 걸리고 (b) 같은 달 안의 정당한 재실행은 통과한다
      (핀도 라이브도 기준선이 as_of 로 고정돼 시간이 지나도 값이 안 변한다).
      '오늘'을 기준선으로 쓰면 월중 재실행이 매번 빨개진다 — 그건 낡음이 아니다.
    """
    stale, seen = [], []
    for base in PIN_FRESHNESS_FILES:
        pin_max = _max_date(os.path.join(pin_dir, base))
        live_src = PIN_SOURCES.get(base)
        live_all = _max_date(live_src) if live_src and os.path.exists(live_src) else None
        if pin_max is None:
            stale.append(f"{base}: 핀 판독 불가")
            continue
        if live_all is None:
            seen.append(f"{base} 핀 {pin_max.date()} (라이브 판독 불가 — 대조 생략)")
            continue
        # PIT: 결정일 이후 관측은 애초에 쓸 수 없었으므로 기준선에서 잘라낸다.
        try:
            d = pd.to_datetime(pq.read_table(live_src, columns=["Date"]).to_pandas()["Date"])
            live_ref = d[d < as_of].max()
        except Exception:
            live_ref = None
        if live_ref is None or pd.isna(live_ref):
            seen.append(f"{base} 핀 {pin_max.date()} (as_of 이전 라이브 없음 — 대조 생략)")
            continue
        lag = int((live_ref - pin_max).days)
        seen.append(f"{base} 핀 {pin_max.date()} vs 가용 {live_ref.date()} (lag {lag}d)")
        if lag > PIN_FRESHNESS_TOL_DAYS:
            stale.append(f"{base}: 핀 {pin_max.date()} < 가용 {live_ref.date()} ({lag}일 낡음)")
    note = " · ".join(seen) if seen else "검사 대상 없음"
    return (not stale), (note if not stale else note + " || ★낡음: " + " / ".join(stale))


def advance_pin(as_of: pd.Timestamp, repin_stale: str | None = None) -> str:
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
        # ★"존재한다" 를 "쓸 수 있다" 로 읽지 않는다 — 재사용 전에 신선도를 재는 게 계약이다.
        fresh, note = pin_freshness(tag_dir, as_of)
        # ★완결성(2026-09-24 C11): PIN_SOURCES 가 요구하는 파일이 전부 있어야 재사용한다. C11 이전에 뜬 핀은
        #   ECOS 원/달러가 없어 뒤에서 exit 2 로 죽는다 — 여기서 같은 재발행 경로(사유 필수)로 돌린다.
        missing = [b for b in PIN_SOURCES if not os.path.exists(os.path.join(tag_dir, b))]
        if fresh and not missing:
            print(f"[ae-monthly] 핀 {tag} 이미 존재 — 재사용 (신선도 OK: {note})")
            return tag_dir
        if missing:
            note = f"{note} || ★필수 파일 부재: {', '.join(missing)} (C11 이전 핀)"
        print(f"[ae-monthly] ★핀 {tag} 사용 불가 — {note}")
        if not repin_stale:
            die(2, f"낡은 핀 재사용 거부: {tag_dir}\n"
                   f"  {note}\n"
                   f"  조기 생성된 핀은 재현성이 아니라 **낡음의 고정**이다. 둘 중 하나를 택할 것:\n"
                   f"    (a) --repin-stale '<사유>'  낡은 핀을 보존 이관하고 라이브로 재발행\n"
                   f"    (b) --pin-dir <dir>         쓸 핀을 명시 지정")
        # 재발행 경로 — 낡은 핀을 지우지 않고 이관한다(감사 흔적 보존).
        import json as _json
        import shutil as _sh
        keep = f"{tag_dir}.stale_{_now_stamp()}"
        _sh.move(tag_dir, keep)
        aud = os.path.join(".cache/pins", "ae_monthly_repin.jsonl")
        with open(aud, "a", encoding="utf-8") as fh:
            fh.write(_json.dumps({"as_of": as_of.strftime("%Y-%m-%d"), "tag": tag,
                                  "stale_note": note, "reason": repin_stale,
                                  "archived_to": keep.replace("\\", "/")},
                                 ensure_ascii=False) + "\n")
        print(f"[ae-monthly] ★낡은 핀 이관 → {keep} (사유: {repin_stale})")
        print(f"[ae-monthly]   기록: {aud}")
    # ── ★라이브 원천 신선도 게이트 (2026-08-30 신설 — 도훈 지적) ────────────────
    #   위 pin_freshness 는 '핀 vs 라이브' 비교라 **라이브 자체가 낡으면 구조적으로 눈이 먼다**
    #   (핀==라이브 → lag 0 → 통과). 새로 뜨는 핀도 같은 구멍을 물려받는다: 낡은 라이브를
    #   복사해 놓고 "방금 만들었으니 신선"이라고 읽게 된다.
    #   ⇒ 복사 **전에** 원천이 결정일 기준으로 전진해 있는지 절대 축으로 잰다.
    #   근거 카드: feedback-freshness-must-be-measured-at-the-consumption-panel
    #     ("다운로드 성공을 적재 성공으로 읽으면 한 달 정지가 게이트 둘을 통과한다")
    #   기준선 = as_of 직전 영업일(월~금). 원천의 발행지연은 PIN_FRESHNESS_TOL_DAYS 가 흡수한다.
    ref = (as_of - pd.Timedelta(days=1))
    while ref.weekday() >= 5:
        ref -= pd.Timedelta(days=1)
    src_stale = []
    for base in PIN_FRESHNESS_FILES:
        src = PIN_SOURCES.get(base)
        if not src or not os.path.exists(src):
            src_stale.append(f"{base}: 라이브 원천 부재({src})")
            continue
        mx = _max_date(src)
        if mx is None:
            src_stale.append(f"{base}: 라이브 원천 판독 불가({src})")
            continue
        lag = int((ref - mx).days)
        print(f"[ae-monthly] 원천 {base}: max {mx.date()} vs 기준 {ref.date()} (lag {lag}d)")
        if lag > PIN_FRESHNESS_TOL_DAYS:
            src_stale.append(f"{base}: {mx.date()} — 기준 {ref.date()} 대비 {lag}일 낡음")
    if src_stale:
        die(2, "라이브 원천이 낡아 핀을 뜨지 않는다 (낡음을 핀으로 굳히지 않는다):"
               + "".join(chr(10) + "    · " + x for x in src_stale)
               + chr(10) + "  조치: 데이터 리프레시를 먼저 돌릴 것 — "
                 "bash 02_Infrastructure/data/daily_refresh.sh"
               + chr(10) + "  (월간 리밸 경로에서는 run_nolayer4_monthly.sh [0] 이 이걸 자동 수행한다. "
                 "이 게이트가 걸렸다면 그 리프레시가 실제로는 전진하지 못했다는 뜻이다.)")

    import json
    for base, src in PIN_SOURCES.items():          # 원본 부재는 디렉토리를 만들기 **전에** 거부(반쯤 뜬 핀 방지)
        if not os.path.exists(src):
            die(2, f"핀 원본 부재: {src} (기대 basename {base})")
    os.makedirs(tag_dir, exist_ok=True)
    files = []
    for base, src in PIN_SOURCES.items():
        files.append(_pin_copy(src, os.path.join(tag_dir, base), as_of, base))
    json.dump({"tag": tag,
               "created_at": as_of.strftime("%Y-%m-%d") + " (AS_OF 기준)",
               "provenance": f"월간 리밸 핀 전진 — 라이브 원본 복사(Date 축 원천 {list(PIN_TRUNCATE_FILES)} 은 "
                             f"Date < AS_OF 절단 = 결정 시점 정보집합). 동결 근거핀({FROZEN_PIN}) 미변경. "
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
    """원본 로직을 그대로 실행하되 결정목록·핀·출력만 주입 + ★특성 패널 빌더 1함수 교체(C11).

    동결 원본을 텍스트로 읽어 상수 3개만 치환 후 exec 한다 — 로직 복사본을 만들면
    원본과 갈라져 '어느 쪽이 정본인가' 문제가 생긴다(오늘 2-3/2-4 미러에서 sha1 대조가
    필요했던 이유와 같은 계통). 치환은 상수 라인 3개로 한정한다.
    ★2026-09-24 PIT C11: exec 뒤 `build_panel` 만 `ae_pit_features.build_pit_panel` 로 바꾼다(모델·학습·
      채점은 원본). 반환 = 그 패널(산출 행 C11 표식용).
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

    # ── ★PIT C11 (2026-09-24): build_panel **한 함수만** 가용시점 결합판으로 교체 ──────────
    #   원본 main 은 build_panel() 을 전역 이름으로 부르므로(원본 :110) 여기서 바꾼 함수가 불린다.
    #   원본의 RNG 소비는 모델 생성·학습에서만 일어나고 build_panel 은 RNG 를 쓰지 않는다 — 교체가 스트림
    #   위치를 옮기지 않는다. 핀 경로(FRED·BENCH)는 위 치환으로 이미 주입된 원본 전역을 그대로 읽는다.
    for _k in ("build_panel", "FRED", "BENCH", "FRED_FEATS", "main"):
        if _k not in g:
            die(2, f"원본에서 '{_k}' 를 찾지 못함(원본 변경 의심) — C11 결합을 끼울 수 없다")
    built = {}
    ecos = os.path.join(pin_dir, aepf.ECOS_KRW_FILE)

    def _pit_build_panel():
        panel, feat_cols = aepf.build_pit_panel(g["FRED"], g["BENCH"], ecos, list(g["FRED_FEATS"]))
        built["panel"] = panel
        return panel, feat_cols

    g["build_panel"] = _pit_build_panel
    try:
        g["main"]()
    except aepf.AEPitError as e:
        die(3 if "★C11" in str(e) else 2, str(e))
    if "panel" not in built:
        die(2, "C11 패널 빌더가 호출되지 않았다 — 원본 main 이 build_panel 을 부르지 않음(원본 변경 의심)")
    return built["panel"]


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
    # ★C11 전환 표지 — 기존 발행본이 수리 전 판(관측일 결합·DEXKOUS)이면 차이의 원인은 '개정'이 아니라
    #   시간축 수리다. 게이트는 그대로 막고(판정 변경 = hard) 원인만 정확히 적는다.
    if not aepf.is_c11_stamped(o.reset_index()):
        note += (" · ★C11 전환: 기존 발행 행은 수리 전 판(해외 특성 관측일 결합·DEXKOUS)이다 — 차이는 FRED 개정이 "
                 "아니라 시간축 수리 몫이다. 2단계 재산출(결정 PIT-C11-BOOK0001)에서 --accept-parity '<사유>'")
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
    ap.add_argument("--repin-stale", default=None, metavar="REASON",
                    help="이미 있는 월별 핀이 **낡았을 때** 사유를 적어 재발행한다. "
                         "낡은 핀은 지우지 않고 <tag>.stale_<ts> 로 이관하고 "
                         ".cache/pins/ae_monthly_repin.jsonl 에 사유를 남긴다. "
                         "사유 없이는 못 쓴다(손으로 핀을 지우면 '누가 왜'가 사라진다). "
                         "★신선한 핀에는 아무 영향 없다 — 재사용 경로가 그대로 우선한다.")
    ap.add_argument("--accept-parity", default=None, metavar="REASON",
                    help="parity 게이트가 잡은 과거 판정 변경을 **사유를 적어** 수용한다. "
                         "게이트가 요구하는 '개정 시리즈 특정 후 사람 판단'을 손으로 파일을 "
                         "덮는 대신 감사 가능한 경로로 남기기 위한 것. 사유 없이는 못 쓴다. "
                         "★PIT 위반(exit 3)에는 적용되지 않는다 — 그건 여전히 무조건 차단.")
    ap.add_argument("--recompute", default=None, metavar="REASON",
                    help="결정일 행이 이미 있어도 **전 이력을 재계산**한다(사유 필수 · 최신 결정일 한정). "
                         "C11 2단계 전 이력 재산출(결정 PIT-C11-AE-1003)용. parity 차단은 여전히 --accept-parity 로 "
                         "따로 넘긴다. 기록 = <OUT>.recompute.jsonl (dry-run 은 기록 안 함).")
    a = ap.parse_args()
    for _flag, _val in (("--recompute", a.recompute), ("--accept-parity", a.accept_parity),
                        ("--repin-stale", a.repin_stale)):
        if _val is not None and not str(_val).strip():
            die(2, f"{_flag} 에는 사유 문자열이 필요하다(빈 사유 금지)")

    as_of = pd.Timestamp(a.as_of)
    if as_of.day != 1:
        die(2, f"--as-of 는 월 1일이어야 함 (holding month = month(decision_date), offset 0): {a.as_of}")
    dec_str = as_of.strftime("%Y-%m-%d")

    # 이미 그 결정일이 있으면 재계산 불필요 — 다만 '있다'를 신선함으로 착각하지 않도록 값을 보여준다.
    cur_max = None
    if os.path.exists(OUT):
        cur = pq.read_table(OUT).to_pandas()
        cur[KEY] = pd.to_datetime(cur[KEY])
        cur_max = cur[KEY].max() if len(cur) else None
        if (cur[KEY] == as_of).any():
            r = cur[cur[KEY] == as_of].iloc[0]
            print(f"[ae-monthly] 결정일 {dec_str} 이미 존재 — fire_seq={int(r['fire_seq'])} "
                  f"last_feat={pd.Timestamp(r['last_feat_date']).date()}"
                  + (" → ★--recompute: 전 이력 재계산" if a.recompute else " (재계산 생략)"))
            if not a.recompute:
                if not aepf.is_c11_stamped(cur[cur[KEY] == as_of]):
                    # 이미 발행된 달의 재실행 — 값은 바꾸지 않는다(발행 기록). 다만 침묵하지도 않는다.
                    print(f"[ae-monthly] ★C11 미해소 행 — {dec_str} 행은 수리 전 판(해외 특성 관측일 결합·DEXKOUS)이다. "
                          f"재산출은 2단계(결정 PIT-C11-BOOK0001): --recompute '<사유>' --accept-parity '<사유>'")
                return 0
        else:
            print(f"[ae-monthly] 기존 max decision_date = {cur[KEY].max().date()} → {dec_str} 추가")
    # ★재계산 범위 가드 — 핀 절단(Date < as_of)은 as_of 뒤 결정들의 창을 자른다. 과거 결정일 끼워넣기 + 핀 전진,
    #   또는 최신이 아닌 결정일의 전 이력 재계산은 뒤 결정을 조용히 낡게 만든다 → 거부.
    if a.recompute and (cur_max is None or as_of != cur_max):
        die(2, f"--recompute 는 최신 결정일({None if cur_max is None else cur_max.date()})에만 — 요청 {dec_str}")
    if a.advance_pin and cur_max is not None and as_of < cur_max:
        die(2, f"과거 결정일 {dec_str} < 기존 최대 {cur_max.date()} + --advance-pin 거부 — 핀 절단(Date < as_of)이 "
               f"뒤 결정들의 특성 창을 자른다. 과거 달 보충은 그 시점 핀을 --pin-dir 로")

    if a.pin_dir:
        pin_dir = a.pin_dir
    elif a.advance_pin:
        pin_dir = advance_pin(as_of, repin_stale=a.repin_stale)
    else:
        pin_dir = DEFAULT_PIN
        print(f"[ae-monthly] 동결 핀 사용 ({pin_dir}) — 신선도 한계 있음. "
              f"리밸런싱 경로는 --advance-pin 을 쓴다")
    for f in ("fred_macro_wide.parquet", "benchmark.parquet",
              "carrier_STR_1715_AR_on_M4_R05_overlay_PG2.parquet", aepf.ECOS_KRW_FILE):
        p = os.path.join(pin_dir, f)
        if not os.path.exists(p):
            die(2, f"핀 파일 부재: {p}"
                   + (" — C11 수리 이후 원/달러 특성은 핀의 ECOS 731Y001 을 쓴다(DEXKOUS prohibited). "
                      "수리 전에 뜬 핀이다: --advance-pin(새 달) 또는 ECOS 를 담은 핀을 --pin-dir 로"
                      if f == aepf.ECOS_KRW_FILE else ""))
    fr = pd.to_datetime(pq.read_table(os.path.join(pin_dir, "fred_macro_wide.parquet"),
                                      columns=["Date"]).to_pandas()["Date"])
    print(f"[ae-monthly] 핀 = {pin_dir} · FRED max {fr.max().date()}")
    # 어느 경로로 고른 핀이든 신선도를 **보고**한다. (--pin-dir/동결핀은 사람의 명시 선택이라
    #  차단하지 않는다 — 다만 침묵시키지도 않는다. 낡음은 로그에 반드시 남는다.)
    _fresh, _fnote = pin_freshness(pin_dir, as_of)
    print(f"[ae-monthly] 핀 신선도: {'OK' if _fresh else '★낡음'} — {_fnote}")
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
    panel = run_walkforward(decisions, pin_dir, tmp)
    if not os.path.exists(tmp):
        die(2, "재계산 산출물 미생성")

    new = pq.read_table(tmp).to_pandas()
    new[KEY] = pd.to_datetime(new[KEY])

    # ── PIT hard fail (원본은 print 만 하고 통과시킨다) ──────────────────────
    bad = int((pd.to_datetime(new["last_feat_date"]) >= new[KEY]).sum())
    if bad:
        os.remove(tmp)
        die(3, f"PIT 위반 {bad}행 (last_feat_date >= decision_date) — 원본은 경고만 했으나 여기서 차단")
    # ── ★C11 표식 + 검사 (2026-09-24): 창에 실린 해외 관측의 가용일이 전부 last_feat_date 이하인가 ──
    try:
        new = aepf.stamp(new, panel, aepf.rules_regime_key())
    except aepf.AEPitError as e:
        os.remove(tmp)
        die(3, str(e))
    new.to_parquet(tmp, index=False)
    print(f"[ae-monthly] PIT self-check 통과 (위반 0행) · C11 표식 {aepf.FEAT_JOIN} "
          f"key={new['c11_regime_key'].iloc[0]} · info_cutoff 최대 "
          f"{pd.Timestamp(new['c11_info_cutoff'].max()).date()}")

    # ── parity 게이트 ────────────────────────────────────────────────────────
    ok, note = parity_check(OUT, new)
    print(f"[ae-monthly] parity: {note}")
    if not ok and not a.accept_parity:
        keep = OUT + ".parity_reject"
        os.replace(tmp, keep)
        die(1, f"과거 발행 행이 변경됨 — 교체 중단. FRED 과거 개정 의심. "
               f"재계산본 보존: {keep} (개정 시리즈 특정 후 사람 판단)")
    import json as _json
    if not ok:
        # ★수용 경로 — 게이트를 끄는 게 아니라 '누가 왜 넘겼는지'를 남긴다.
        #   손으로 .parity_reject 를 OUT 에 복사하면 이 기록이 안 남는다. 그래서 여기 둔다.
        #   ★dry-run 은 교체하지 않으므로 '수용'도 일어나지 않았다 — 기록하지 않는다(구판은 dry-run 에서도 적었다).
        _aud = OUT + ".parity_override.jsonl"
        if a.dry_run:
            print(f"[ae-monthly] ★parity 수용 예정(dry-run — 기록 안 함) — 사유: {a.accept_parity}")
        else:
            with open(_aud, "a", encoding="utf-8") as fh:
                fh.write(_json.dumps({"as_of": dec_str, "note": note,
                                      "reason": a.accept_parity,
                                      "recompute": a.recompute,
                                      "pin_dir": pin_dir.replace("\\", "/")},
                                     ensure_ascii=False) + "\n")
            print(f"[ae-monthly] ★parity 수용 — 사유: {a.accept_parity}")
            print(f"[ae-monthly]   기록: {_aud}")

    if a.dry_run:
        print(f"[ae-monthly] dry-run — 교체 안 함. 산출: {tmp}")
        return 0

    if a.recompute:
        with open(OUT + ".recompute.jsonl", "a", encoding="utf-8") as fh:
            fh.write(_json.dumps({"as_of": dec_str, "reason": a.recompute, "parity_ok": bool(ok), "note": note,
                                  "n_decisions": int(len(new)), "pin_dir": pin_dir.replace("\\", "/"),
                                  "c11_regime_key": str(new["c11_regime_key"].iloc[0]) if len(new) else None},
                                 ensure_ascii=False) + "\n")
        print(f"[ae-monthly] ★전 이력 재계산 기록: {OUT}.recompute.jsonl (사유: {a.recompute})")
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
