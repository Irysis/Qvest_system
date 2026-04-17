# sweep v3 Pass 2 — Execution Plan (11건 동적 재검증)

- **세션**: 66
- **작성자**: Judge teammate
- **작성일**: 2026-04-17
- **근거**: Q-Lead 우선순위 지시 (team-lead message, Task #13 refined)
- **선행 조건**: Forge H_1676/H_1682 S1 완료 (Task #4 우선 처리 후 착수)
- **목표**: SR >= 1.2 clean 전략 5~7건 확보 → PG 편입 풀 확장 → Sharpe 2.0 경로

## 1. 3-Tier 우선순위 + 검증 심도

### Tier 1 최우선 (3건) — Sharpe gap 해소 핵심
**검증 심도**: Full Gate 0~6 + DSR(n_trials=400) + FF5 alpha t + rolling 3Y SR + Role Honesty + LOO 4회

| # | 전략 | 명목 SR | 명목 MDD | 예상 SR contrib | 특이사항 |
|---|------|--------|---------|-----------------|---------|
| 1 | STR_1439 | 1.532 | 19.17 | +0.10~0.15 | novelty 10, 재활성화 1순위 |
| 2 | STR_1435_5sleeve_dd620_repair | 1.378 | 27.37 | +0.08~0.12 | core/5sleeve |
| 3 | STR_1060_brk02_no_short_dd | 1.333 | 24.81 | +0.08~0.12 | 낮은 MDD 선호 |

### Tier 2 중간 (4건) — PG 편입 잠재 후보
**검증 심도**: Full Gate 0~6 + DSR + Role Honesty (rolling 3Y SR 생략 가능)

| # | 전략 | 명목 SR | 명목 MDD | 예상 SR contrib |
|---|------|--------|---------|-----------------|
| 4 | STR_1417_5sleeve_mrs3545 | 1.361 | 30.61 | +0.05~0.08 |
| 5 | STR_1562_gerber_dcc_hrp_c11fix | 1.333 | 31.78 | +0.08~0.12 |
| 6 | STR_1433_consgate_c11fix_dd722 | 1.329 | 24.35 | +0.08~0.12 |
| 7 | STR_1071_noShortDD_mrs1225 | 1.297 | 22.72 | +0.07~0.10 |

### Tier 3 후순위 (4건) — Fail fast
**검증 심도**: PIT 재검증 + DSR + Role Honesty만 (Gate 2/Gate 4 rolling SR 생략)

| # | 전략 | 명목 SR | 명목 MDD | 이유 |
|---|------|--------|---------|------|
| 8 | STR_1631_SYN_05_2002_icwt_scoretilt_bimonthly | 1.194 | 33.13 | 이미 PG2 편입 — role_honesty + DSR만 |
| 9 | STR_686_ms_d70m30_vt | 1.116 | 36.5 | MDD 36.5 > 30 |
| 10 | STR_1469_cons4f_5sleeve | 1.021 | 29.76 | SR < 1.1 |
| 11 | STR_1393_esbr_sue_adaptive | 0.942 | 35.69 | 최하위 (SR < 1.0, MDD > 35) |

## 2. PIT 최우선 점검 (Q-Lead 강조)

C5 / C9 / C10 / C11 이 4항목이 Sharpe 과대추정 최대 리스크.

| 코드 | 검출 대상 | 권장 코드 패턴 |
|------|----------|----------------|
| C5 | overlay 당일 값 사용 | `overlay_signal <- shift(raw_signal, n=1, type='lag')` |
| C9 | VT/DD same-day circular | `dd_lag <- c(0, dd_pct[-n]); vol_lag <- c(vol[1], head(vol,-1))` |
| C10 | liquidity filter 당일 거래량 | `adv20 <- shift(frollmean(Value_Traded, n=20), n=1, type='lag')` |
| C11 | MRS/FRED month-end timing | `regime_engine_v7` 경유 또는 `shift(mrs, n=1, type='lag')` |

## 3. 실행 프로토콜 (각 전략 단위)

```r
# 0. 사전 점검
setwd(file.path("04_Research/strategies", strategy_dir))
run_all_path <- file.path(getwd(), "run_all.R")

# Gate 0: PIT C1~C15
source("02_Infrastructure/validation/lookahead_detector.R")
pit_result <- detect_lookahead(run_all_path)
# 기대: violations == character(0)

# Gate 1: 구현 (N<=20, 15bps, 유동성 2억+)
# run_all.R 코드 파싱 + performance.json 확인

# Gate 2: 견고성 LOO 4회 (Tier 1 only)
# 2008/2020/2011/2018 각 1개씩 제외한 4개 시나리오 재실행

# Gate 3: 성과 hurdle v2.2
source("02_Infrastructure/hurdle_gate.R")
hurdle_result <- calculate_hurdle(performance_json)

# Gate 4: 통계
source("02_Infrastructure/validation/statistical_defense.R")
dsr_result <- compute_dsr(sharpe = SR, n_trials = 400, T = 252*20)
# FF5 alpha t-stat (regression vs Fama-French 5 factors)
# rolling 3Y SR <= 0.3 check (ALPHA DECAY)

# Gate 5: 다양성
source("02_Infrastructure/strategy_analyzer.R")
corr_result <- analyze_strategy(strategy_path)
# max_abs_corr: <0.3 (A_NOVEL) or <0.5 (표준)

# Gate 6: Role Honesty
source("02_Infrastructure/validation/role_honesty_audit.R")
rh_result <- role_honesty_audit(strategy_id, claimed_role, active_pool)
```

## 4. 산출물 스펙 (전략별)

**per-strategy**: `stage_artifacts/judge_sweep_v3_{strategy_id}_verdict.json`

```json
{
  "strategy_id": "STR_1439",
  "tier": 1,
  "v2_grade": "A",
  "v3_grade": "A" | "A_NOVEL" | "B" | "REJECT" | "ARCHIVE",
  "v3_verdict": "VALIDATED_CORE" | "VALIDATED_DIVERSIFIER" | "VALIDATED_DEFENSE" | "REJECT",
  "gate_results": {
    "gate_0_pit": {"pass": true, "violations": []},
    "gate_1_impl": {"pass": true, "n_holdings": 20, "commission": 0.0015, "liq_threshold": 2e8},
    "gate_2_robustness": {"pass": true, "loo_2008": 1.45, "loo_2020": 1.50, "loo_2011": 1.52, "loo_2018": 1.48},
    "gate_3_perf": {"pass": true, "sr": 1.532, "cagr": 21.5, "mdd": -19.17},
    "gate_4_stat": {"pass": true, "dsr": 0.62, "ff5_alpha_t": 3.2, "rolling_3y_sr": 0.45},
    "gate_5_diversity": {"pass": true, "max_abs_corr": 0.28},
    "gate_6_role_honesty": {"pass": true, "claimed_role": "diversifier", "audit_result": "CONFIRMED"}
  },
  "sr_contrib_estimated": 0.13,
  "pg_candidate_level": "PG1" | "PG2" | "PG3",
  "pit_violations_detail": {},
  "notes": "..."
}
```

**aggregate**: `stage_artifacts/judge_sweep_v3_pass2_<timestamp>.json`

```json
{
  "report_type": "JUDGE_SWEEP_V3_PASS2_DYNAMIC",
  "timestamp": "2026-04-17T...",
  "total": 11,
  "tier_1_pass": 0,  // 목표 >=2
  "tier_2_pass": 0,  // 목표 >=2
  "tier_3_pass": 0,  // 목표 >=1
  "total_pass": 0,   // 목표 5~7
  "pit_clean_rate": 0.0,     // 목표 >=90%
  "role_honesty_pass_rate": 0.0,  // 목표 100%
  "dsr_0_5_rate": 0.0,       // 목표 >=80%
  "ff5_t_2_rate": 0.0,       // 목표 >=70%
  "validated_core": [],
  "validated_diversifier": [],
  "validated_defense": [],
  "rejected": [],
  "sharpe_gap_contribution": {
    "estimated_sr_boost": 0.25,  // 실측 후 갱신
    "post_blend_sr": 1.52,
    "remaining_gap_to_2_0": 0.48
  }
}
```

## 5. 병렬 실행 전략

Q-Lead의 병렬 에이전트 실행 규칙 (RAM 80% 이하):

- **배치 1 (Tier 1, 3건)**: STR_1439 + STR_1435 + STR_1060 — Agent 3개 병렬 스폰
- **배치 2 (Tier 2, 4건)**: STR_1417_5sleeve + STR_1562 + STR_1433 + STR_1071 — Agent 4개 병렬 스폰
- **배치 3 (Tier 3, 4건)**: STR_1631_SYN_05_2002 + STR_686 + STR_1469 + STR_1393 — Agent 4개 병렬 스폰

배치 간 직렬 진행 (RAM 여유 확인 후 배치 2/3 착수). 총 3~5시간 예상.

**각 Agent 스폰 지시 (Q-Lead 권한)**:
- 스폰 시 본 execution plan 참조
- 전략별 verdict JSON + 통합 요약 반환 요청

## 6. Tier별 Fail/Pass 기준

### Tier 1 Fail 조건 (즉시 REJECT)
- Gate 0 PIT violation >= 1
- Gate 1 N > 20
- Gate 3 hard_fail (MDD > 45%)
- Gate 4 DSR < 0.3
- Gate 4 FF5 alpha t < 2.0
- Gate 6 Role Honesty AUDIT FAIL (위장 탐지)

### Tier 2 Fail 조건
- Tier 1과 동일 + Gate 5 max_abs_corr >= 0.7

### Tier 3 Fail 조건 (fail fast)
- Gate 0 PIT violation >= 1 (즉시 종료, 이후 Gate skip)
- Gate 4 DSR < 0.3
- Gate 6 Role Honesty FAIL

## 7. L-code 적립 계획 (Pass 2 완료 시)

- **L-149**: sweep v3 Pass 2 동적 재검증 결과 교훈. Tier별 pass rate + PIT 위반 패턴 + Sharpe 기여도 실측 vs 예측 비교.
- **L-150 (조건부)**: Role Honesty 위장 탐지 패턴 (Tier 1/2에서 1건 이상 위장 발각 시).
- **L-151 (조건부)**: DSR < 0.3 전략 패턴 (Harvey t>3.0 미달 사례).

## 8. 실행 착수 조건

- **조건 A**: Task #4 (H_1676/H_1682 S6 Gate 0~6) 완료 — Judge 본연 작업
- **조건 B**: Forge S1 완료 + Judge inbox에 TODO_S6_H_1676/H_1682 push 확인
- **조건 C**: RAM 80% 이하 (Agent 3~4개 병렬 허용)

모두 충족 시 Pass 2 배치 1부터 착수. 현재 조건 A/B 미충족 — Forge S1 완료 대기.
