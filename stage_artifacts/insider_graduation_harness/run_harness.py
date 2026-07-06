#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""run_harness.py — DART 임원 순매수 졸업-테스트 하네스 오케스트레이터 (re-firable, idempotent).

한 번 호출로 전 파이프라인 실행:
  1. prep_market_monthly.py     — RAWDATA(daily) → 슬림 월별 시장입력 (R halt 회피)
  2. build_officer_netbuy_signal.py (PIT_LAG=1) — 신호 패널 (canonical)
  3. pit_audit.py               — anti-look-ahead 감사 (FAIL 시 중단)
  4. run_graduation_gate.R      — canonical screen + 졸업 게이트 (INTERIM/AUTHORITATIVE)
  5. lag1 스트레스              — PIT_LAG=2 재빌드+screen → 누출 여부(graceful degrade) 비교
  6. 원복                       — PIT_LAG=1 canonical 상태 복원

★ 재발화(re-fire): 다른 세션의 backfill 이 cache/monthly/*.parquet 를 확장하면
   이 스크립트를 다시 돌리기만 하면 최신 커버리지를 자동 소비 → 재판정. 멱등(idempotent).
   backfill 무접촉(읽기 전용). API/backfill 실행 없음.

산출: reports/graduation_gate_result.json (canonical) + reports/lag_stress_comparison.json.
환경: QM_ROOT, MIN_CONTIG_MONTHS(default 60).
"""
import os, sys, json, subprocess

R = os.environ.get("QM_ROOT", r"C:\Users\99922\OneDrive\Quant_Module_Moltbot")
HARN = os.path.join(R, "stage_artifacts", "insider_graduation_harness")
PY = os.environ.get("QVEST_PY", sys.executable)
RSCRIPT = "Rscript"

env_base = dict(os.environ, QM_ROOT=R, OMP_NUM_THREADS="1", R_DATATABLE_NUM_THREADS="1")


def run(cmd, env, label):
    print(f"\n=== [{label}] {' '.join(cmd)} ===")
    p = subprocess.run(cmd, env=env, cwd=R, capture_output=True, text=True)
    out = (p.stdout or "") + (p.stderr or "")
    for ln in out.splitlines():
        if any(t in ln for t in ("[build]", "[prep]", "[PIT", "[OK]", "[XX]", "verdict",
                                  "PORT_t", "ERROR", "Error", "wrote", "krw__", "nflow__")):
            print("  " + ln)
    if p.returncode != 0:
        print(f"  !! {label} returned {p.returncode}")
    return p.returncode, out


def read_gate():
    p = os.path.join(HARN, "reports", "graduation_gate_result.json")
    return json.load(open(p, encoding="utf-8")) if os.path.exists(p) else None


def main():
    # 1. prep market
    run([PY, os.path.join(HARN, "prep_market_monthly.py")], env_base, "prep_market")

    # 2. build canonical (PIT_LAG=1)
    e1 = dict(env_base, PIT_LAG="1")
    run([PY, os.path.join(HARN, "build_officer_netbuy_signal.py")], e1, "build_lag1")

    # 3. PIT audit — hard gate
    rc, _ = run([PY, os.path.join(HARN, "pit_audit.py")], e1, "pit_audit")
    if rc != 0:
        print("\n!! PIT AUDIT FAILED — 중단. 신호 무효 (look-ahead 의심).")
        sys.exit(1)

    # 4. graduation gate (canonical)
    run([RSCRIPT, os.path.join(HARN, "run_graduation_gate.R")], e1, "gate_lag1")
    gate1 = read_gate()

    # 5. lag stress (PIT_LAG=2): rebuild + screen, capture PORT_t
    e2 = dict(env_base, PIT_LAG="2")
    run([PY, os.path.join(HARN, "build_officer_netbuy_signal.py")], e2, "build_lag2")
    run([PY, os.path.join(HARN, "pit_audit.py")], e2, "pit_audit_lag2")
    run([RSCRIPT, os.path.join(HARN, "run_graduation_gate.R")], e2, "gate_lag2")
    gate2 = read_gate()

    # 6. restore canonical PIT_LAG=1
    run([PY, os.path.join(HARN, "build_officer_netbuy_signal.py")], e1, "restore_lag1")
    run([RSCRIPT, os.path.join(HARN, "run_graduation_gate.R")], e1, "restore_gate_lag1")
    gate1 = read_gate()  # canonical result on disk again

    # stress comparison: does PORT_t collapse when signal delayed +1 month?
    #   leakage signature = sharp PORT_t drop toward/below 0 (same-month info removed).
    #   graceful degrade (PORT_t stays positive/similar) = NO look-ahead.
    def pt(g, key):
        if not g:
            return None
        r = g["results"].get(key, {})
        return r.get("portfolio_alpha_t_nw_lag3")

    keys = ["krw__contiguous_run", "krw__combined_all", "nflow__contiguous_run", "nflow__combined_all"]
    stress = {}
    for k in keys:
        p1, p2 = pt(gate1, k), pt(gate2, k)
        collapse = (p1 is not None and p2 is not None and p1 > 0 and p2 < 0.5 * p1 and p2 < 0)
        stress[k] = {"port_t_lag1": p1, "port_t_lag2": p2,
                     "leakage_suspected": bool(collapse)}
    any_leak = any(v["leakage_suspected"] for v in stress.values())
    stress_out = {
        "test": "lag1_stress (PIT_LAG 1 vs 2)",
        "interpretation": ("신호를 1개월 추가 지연했을 때 PORT_t 가 붕괴(양→음)하면 동월 look-ahead 의심. "
                           "유지/완만저하 = 누출 없음(graceful degrade)."),
        "per_variant": stress,
        "any_leakage_suspected": any_leak,
        "verdict": "LEAKAGE_SUSPECTED" if any_leak else "NO_LEAKAGE_graceful_degrade",
    }
    json.dump(stress_out, open(os.path.join(HARN, "reports", "lag_stress_comparison.json"), "w",
                               encoding="utf-8"), ensure_ascii=False, indent=2)

    print("\n=== LAG STRESS (anti-look-ahead) ===")
    for k, v in stress.items():
        print(f"  {k:24s} PORT_t lag1={v['port_t_lag1']} lag2={v['port_t_lag2']} "
              f"leak={v['leakage_suspected']}")
    print(f"  verdict: {stress_out['verdict']}")
    print(f"\n[harness] canonical verdict_level = {gate1['verdict_level'] if gate1 else 'NA'} "
          f"(contig {gate1['coverage']['largest_contiguous_run_months'] if gate1 else 'NA'}"
          f"/{gate1['coverage']['min_contig_required'] if gate1 else 'NA'})")
    print("[harness] DONE. reports/graduation_gate_result.json + lag_stress_comparison.json")


if __name__ == "__main__":
    main()
