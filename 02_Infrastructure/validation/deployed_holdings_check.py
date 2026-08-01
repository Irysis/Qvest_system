#!/usr/bin/env python
"""deployed_holdings_check.py — 배포 홀딩 하드 제약 + 재계산 정합 상시 검증.

**왜 필요한가**: 월간 리밸 체인의 Gate C 는 "홀딩 CSV 가 생성됐고 5행 이상"만 본다
(`02_Infrastructure/ops/run_pg2_rebalance_full.sh`). 즉 **지난달 값이 그대로 재출력돼도 통과**하고,
하드 제약(25종·long-only·bounds·Sum(w)=1·유동성)은 배포 체인 어디서도 산출물에 대해 검사되지 않는다
(2026-08-01 감사: "4개 하드 제약이 '구성상 만족'일 뿐 어디서도 검증 0건").

이 검사기는 **존재가 아니라 내용**을 잰다. 파일이 생겼다 != 새로 계산됐다 != 제약을 만족한다.

제약 상수는 하드코딩하지 않고 `02_Infrastructure/worktask/constraint_defaults.json`
(`tier_soft_deployment`)에서 읽는다 — 정본이 둘이 되는 것을 막는다.

슬롯 무관: 2-3(noLayer4, invested = m4 x beta) / 2-4(M4gAE, invested = gate x beta) 양쪽
매니페스트 스키마를 처리한다.

사용:
  python deployed_holdings_check.py --as-of 2026-08-01 \
      --holdings <csv> --manifest <json> [--prev-holdings <csv>] [--skip-liquidity]

종료코드: 0 = PASS / 1 = hard FAIL / 2 = 산출물 부재·판독 불가
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys

import pandas as pd

ROOT = os.environ.get("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot").replace("\\", "/")
DEFAULTS = os.path.join(ROOT, "02_Infrastructure/worktask/constraint_defaults.json")
RAWDATA = os.path.join(ROOT, ".cache/rawdata.parquet")

TOL_W = 1e-9        # 개별 비중 상한 비교 허용오차
TOL_SUM = 1e-6      # Sum(w) 비교 허용오차


def load_constraints() -> dict:
    with open(DEFAULTS, encoding="utf-8-sig") as fh:
        d = json.load(fh)
    t = d["tier_soft_deployment"]
    return {
        "max_names": int(t["max_names"]),
        "w_lo": float(t["weight_bounds"][0]),
        "w_hi": float(t["weight_bounds"][1]),
        "long_only": bool(t["long_only"]),
        "sum_w": float(t["sum_weights_absolute"]),
        "liq_min": float(t["liquidity_min_won_20d_avg"]),
    }


def weight_fingerprint(df: pd.DataFrame) -> str:
    """CASH 제외 (Ticker, Weight) 정렬 지문. 재계산 여부 판정용."""
    eq = df[df.Ticker != "CASH"]
    body = ",".join(f"{t}:{w:.10f}" for t, w in sorted(zip(eq.Ticker, eq.Weight)))
    return hashlib.sha1(body.encode()).hexdigest()[:16]


def beta_rule_candidates(regime: str) -> list[float]:
    """beta_R05_V5 규칙표 역산 — regime 별 허용값.
    fcase(CRISIS&zlt 0.30, CRISIS 0.50, CAUTION&zlt 0.50, CAUTION 0.70,
          (BULL|NORMAL)&zlt 0.85, default 1.00)
    zlt 는 매니페스트에 없으므로 regime 이 허용하는 값 집합으로 판정한다.
    """
    table = {
        "CRISIS": [0.30, 0.50],
        "CAUTION": [0.50, 0.70],
        "BULL": [0.85, 1.00],
        "NORMAL": [0.85, 1.00],
    }
    return table.get(str(regime), [])


def liquidity_ok(tickers, as_of: pd.Timestamp, liq_min: float):
    """유동성: as_of 직전 30일 평균 거래대금 >= liq_min. (t-1 PIT — Date < as_of)"""
    import pyarrow.parquet as pq

    if not os.path.exists(RAWDATA):
        return None, "rawdata.parquet 부재 — 유동성 검사 불가"
    t = pq.read_table(RAWDATA, columns=["Date", "Ticker", "Close", "Vol"]).to_pandas()
    t["Date"] = pd.to_datetime(t["Date"])
    win = t[(t.Date >= as_of - pd.Timedelta(days=30)) & (t.Date < as_of)]
    if win.empty:
        return None, f"as_of 직전 30일 rawdata 없음 (max={t.Date.max().date()})"
    win = win.assign(TV=win.Close * win.Vol)
    atv = win.groupby("Ticker")["TV"].mean()
    held = [x for x in tickers if x != "CASH"]
    miss = [x for x in held if x not in atv.index]
    bad = [(x, float(atv[x])) for x in held if x in atv.index and atv[x] < liq_min]
    return (bad, miss), None


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--as-of", required=True)
    ap.add_argument("--holdings", required=True)
    ap.add_argument("--manifest", required=True)
    ap.add_argument("--prev-holdings", default=None,
                    help="전월 홀딩 CSV — 재계산 지문 대조용. 없으면 해당 검사 SKIP(경고).")
    ap.add_argument("--skip-liquidity", action="store_true")
    a = ap.parse_args()

    as_of = pd.Timestamp(a.as_of)
    C = load_constraints()

    if not os.path.exists(a.holdings):
        print(f"FAIL 홀딩 CSV 부재: {a.holdings}")
        return 2
    if not os.path.exists(a.manifest):
        print(f"FAIL 매니페스트 부재: {a.manifest}")
        return 2

    df = pd.read_csv(a.holdings)
    for col in ("Ticker", "Weight"):
        if col not in df.columns:
            print(f"FAIL 홀딩 CSV 컬럼 결손: {col} (있는 컬럼 {list(df.columns)})")
            return 2
    with open(a.manifest, encoding="utf-8-sig") as fh:
        man = json.load(fh)

    eq = df[df.Ticker != "CASH"].copy()
    cash_rows = df[df.Ticker == "CASH"]
    cash_w = float(cash_rows.Weight.iloc[0]) if len(cash_rows) else 0.0
    held = eq[eq.Weight > 0]

    fails, warns, oks = [], [], []

    def chk(cond, ok, bad, hard=True):
        (oks if cond else (fails if hard else warns)).append(ok if cond else bad)

    print("=" * 72)
    print(f"배포 홀딩 검증 — as_of={a.as_of}")
    print(f"  {os.path.relpath(a.holdings, ROOT) if a.holdings.startswith(ROOT) else a.holdings}")
    print("=" * 72)
    print(f"  총 행 {len(df)} (CASH {len(cash_rows)} + 주식 {len(eq)}) · 실질 보유 {len(held)}종")
    print(f"  현금 {cash_w:.4f} · 투자 {eq.Weight.sum():.6f} · Sum(w) {df.Weight.sum():.10f}")
    print(f"  최대 개별비중 {eq.Weight.max():.6f}  (상한 {C['w_hi']})")

    # ── 하드 제약 (constraint_defaults.json tier_soft_deployment) ───────────────
    # 종목수는 '행 수'가 아니라 '실질 보유(>0)'로 잰다 — Weight=0 행이 실려 나오는 것이 정상 동작이라
    # 행 수로 재면 보유하지 않는 종목까지 세게 된다(2026-07 실측: 20행 중 실질 14종).
    chk(len(held) <= C["max_names"],
        f"OK   실질 보유 {len(held)} <= {C['max_names']}",
        f"FAIL 실질 보유 {len(held)} > {C['max_names']}")
    chk(len(eq) <= C["max_names"],
        f"OK   주식 행수 {len(eq)} <= {C['max_names']}",
        f"FAIL 주식 행수 {len(eq)} > {C['max_names']}")
    if C["long_only"]:
        n_neg = int((df.Weight < C["w_lo"] - TOL_W).sum())
        chk(n_neg == 0, "OK   long-only (weights >= 0)", f"FAIL 음수 비중 {n_neg}건")
    n_over = int((eq.Weight > C["w_hi"] + TOL_W).sum())
    chk(n_over == 0, f"OK   개별 상한 <= {C['w_hi']}", f"FAIL 상한 초과 {n_over}건")
    chk(abs(df.Weight.sum() - C["sum_w"]) < TOL_SUM,
        f"OK   Sum(w) = {C['sum_w']}",
        f"FAIL Sum(w) = {df.Weight.sum():.10f} (기대 {C['sum_w']})")

    # ── 유동성 (t-1 PIT: Date < as_of) ─────────────────────────────────────────
    if a.skip_liquidity:
        warns.append("WARN 유동성 검사 SKIP (--skip-liquidity)")
    else:
        res, err = liquidity_ok(held.Ticker.tolist(), as_of, C["liq_min"])
        if err:
            warns.append(f"WARN 유동성 검사 불가 — {err}")
        else:
            bad, miss = res
            chk(not bad,
                f"OK   유동성 20d ATV >= {C['liq_min']:.0f} (보유 {len(held)}종)",
                f"FAIL 유동성 미달 {len(bad)}종: {[(t, f'{v:.3e}') for t, v in bad[:5]]}")
            if miss:
                warns.append(f"WARN 유동성 산출 불가 {len(miss)}종(거래 데이터 없음): {miss[:5]}")

    # ── 재계산 확정 (조용한 재출력 검거) ───────────────────────────────────────
    sha = weight_fingerprint(df)
    print(f"\n  비중 지문 {sha}")
    if a.prev_holdings and os.path.exists(a.prev_holdings):
        prev = pd.read_csv(a.prev_holdings)
        psha = weight_fingerprint(prev)
        chk(sha != psha,
            f"OK   비중 지문 변경  전월 {psha} -> {sha}",
            f"FAIL 비중 지문 전월과 동일 ({sha}) — 재계산되지 않고 재출력된 것")
        pe = set(prev[prev.Ticker != "CASH"].Ticker)
        ce = set(eq.Ticker)
        print(f"  종목 유지 {len(pe & ce)} / 신규 {len(ce - pe)} / 제외 {len(pe - ce)}")
        pc = prev[prev.Ticker == "CASH"]
        if len(pc):
            print(f"  현금 전월 {float(pc.Weight.iloc[0]):.4f} -> {cash_w:.4f}")
    else:
        warns.append("WARN 전월 홀딩 미지정/부재 — 재계산 지문 대조 SKIP (조용한 재출력 미검)")

    # ── 매니페스트 정합 ────────────────────────────────────────────────────────
    ov = man.get("overlays", {}) or {}
    b = ov.get("beta_R05_V5") or {}
    regime, beta, z = b.get("regime"), b.get("value"), b.get("R05_z_avg")
    m4 = ov.get("m4_scalar")
    gate = ov.get("m4_ae_gate")          # 슬롯 2-4(M4gAE)만 존재
    ae_fire = ov.get("ae_fire_seq")
    scaler = gate if gate is not None else m4      # invested 승수: 게이트 우선
    scaler_name = "m4_ae_gate" if gate is not None else "m4_scalar"

    print(f"\n  regime={regime} R05_z={z} beta={beta} {scaler_name}={scaler}"
          + (f" ae_fire={ae_fire}" if ae_fire is not None else ""))

    chk(str(man.get("as_of")) == a.as_of,
        f"OK   manifest as_of = {a.as_of}",
        f"FAIL manifest as_of = {man.get('as_of')} (기대 {a.as_of})")

    # R05_z_avg 결측 = factor_db 폴백(빈 당월 DB) 진입 신호. 그러면 zlt=False 로 beta 가
    # 기본값 1.00(=전액 투자)으로 기울어 **실패가 보수적이 아니라 위험한 방향**으로 간다.
    z_bad = z is None or (isinstance(z, float) and z != z)
    chk(not z_bad,
        "OK   R05_z_avg 유효 — factor_db 폴백 미진입",
        "FAIL R05_z_avg 결측 — 당월 빈 factor_db 폴백 의심 (beta 가 1.00=전액투자로 기울음)")

    cand = beta_rule_candidates(regime)
    chk(bool(cand) and beta in cand,
        f"OK   beta={beta} 가 regime={regime} 규칙표 {cand} 안에 있음",
        f"FAIL beta={beta} 가 regime={regime} 규칙표 {cand} 와 불일치")

    if scaler is not None and beta is not None:
        exp_inv = float(scaler) * float(beta)
        chk(abs(float(man.get("invested", -1)) - exp_inv) < TOL_SUM,
            f"OK   invested = {scaler_name} x beta = {exp_inv:.4f}",
            f"FAIL invested={man.get('invested')} != {scaler_name} x beta = {exp_inv:.4f}")
        chk(abs(cash_w - (1 - exp_inv)) < TOL_SUM,
            f"OK   cash = 1 - invested = {1 - exp_inv:.4f}",
            f"FAIL cash={cash_w:.4f} != {1 - exp_inv:.4f}")

    # 슬롯 2-4(M4gAE) 전용 — 게이트 규칙 재현
    if gate is not None:
        m4_fires = int(float(m4) < 0.999)
        exp_gate = 0.70 if (m4_fires == 1 and int(ae_fire or 0) == 1) else 1.00
        chk(abs(float(gate) - exp_gate) < TOL_W,
            f"OK   게이트 재현 m4_fires={m4_fires} & ae_fire={ae_fire} -> {exp_gate:.2f}",
            f"FAIL 게이트 {gate} != 규칙 재현값 {exp_gate:.2f}")
        pit = man.get("pit", {}) or {}
        chk(bool(pit.get("ae_pit_ok", False)),
            "OK   AE PIT (last_feat < as_of)",
            f"FAIL AE PIT 위반 — ae_last_feat={pit.get('ae_last_feat')}")

    if not bool((man.get("pit") or {}).get("no_future_reference", False)):
        warns.append("WARN manifest.pit.no_future_reference 가 참이 아님")

    nm = eq[eq.Name.isna() | (eq.Name.astype(str).str.strip() == "")] if "Name" in eq.columns else eq.iloc[0:0]
    if len(nm):
        warns.append(f"WARN Name/Sector 결손 {len(nm)}종: {sorted(nm.Ticker.tolist())}")

    print("\n" + "=" * 72)
    for x in oks:
        print(" ", x)
    for x in warns:
        print(" ", x)
    for x in fails:
        print(" ", x)
    print("=" * 72)
    print(f"판정: {'PASS' if not fails else 'FAIL'}  (hard {len(fails)} / warn {len(warns)})")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
