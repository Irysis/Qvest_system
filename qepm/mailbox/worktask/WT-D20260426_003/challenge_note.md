# WT-D20260426_003 Iter 9 — Alpha Challenge Note

## Summary
**Verdict**: ALPHA NOT MET. Sprint Iter 7+8+9 연속 graduation FAIL. Sprint 종결 권고 (또는 ML/nonlinear pivot).

**Codex Stance**: REJECT (alpha critic round, gpt-5.5 xhigh).
**Q-Lead Self-Assessment**: REJECT (자체 정량 진단과 일치).

## Iter 9 Hypothesis
KR market에서 Growth (forecast revision + actuals YoY) × Investor_Flow (외인+기관 net buy intensity) cross-family residualized interaction이 monthly 1M horizon에서 graduation-level alpha (rank_IC ≥ 0.04, ICIR ≥ 0.20, Harvey t ≥ 3.0, DSR ≥ 0.5) 생성한다.

## Key Findings (정직)

### 1) Composite alpha graduation FAIL (8 gates 중 1 PASS)
| Gate | Threshold | Iter 9 actual | Pass |
|------|-----------|---------------|------|
| rank_IC | ≥ 0.04 | 0.0025 | FAIL |
| ICIR | ≥ 0.20 | 0.027 | FAIL |
| Harvey t | ≥ 3.0 | 0.350 | FAIL |
| DSR | ≥ 0.5 | 0.199 | FAIL |
| Subperiod sign consistency | ≥ 0.50 | 0.33 | FAIL |
| Standalone SR proxy | ≥ 1.0 | 0.093 | FAIL |
| 5-spec Harvey PASS | ≥ 4/5 | 0/5 | FAIL |
| TDC vs STR_1700 | < 0.30 | 0.243 | **PASS** |

오직 TDC PASS → cross-family orthogonality 입증. 그러나 alpha 자체 미입증으로 ensemble candidate 부적격.

### 2) Component IC decomposition (핵심 발견)
| Component | Mean IC | t-stat | ICIR |
|-----------|---------|--------|------|
| growth_z (3-axis: GR06+GR01+C17) | +0.0141 | +2.03 | 0.157 |
| flow_resid_z (3-axis: INV02+INV04+INV08) | **-0.0154** | **-2.23** | -0.172 |
| interact_z (sign(growth)*\|flow\|) | +0.0105 | +1.52 | 0.118 |

**KR post-flow reversal 입증** (Lee-Liu 2014 후속 패턴): Foreign + Institutional 60d net buy 종목이 다음달 underperform — Iter 9 가설의 "flow → 정보 우위 alpha" KR top-universe 60d horizon에서 invalid. C13 강제 (Z_Score_Aligned only) 하에 flow signal direction 변경 불가.

**Composite cancellation**: growth (+0.014) + flow_resid (-0.015) → 거의 zero. Naïve linear additive composite가 두 source를 상쇄.

### 3) Regime decomposition
| Regime | N | rank_IC | ICIR | Note |
|--------|---|---------|------|------|
| BULL | 85 | +0.024 | **+0.272** | Growth+Flow positive (가설 부분 입증) |
| NORMAL | 60 | -0.020 | -0.211 | flow reversal dominate |
| CAUTION | 23 | -0.017 | -0.204 | flow reversal dominate |
| CRISIS | (n=0 active) | NA | NA | cash sleeve, alpha=0 |

BULL only sub-strategy ICIR=0.272, IC=+0.024 (t≈2.5 borderline). 그러나 active period 35% 만, standalone PG candidate 부적격.

### 4) Subperiod regression (factor decay)
| Period | n | rank_IC | ICIR |
|--------|---|---------|------|
| 2008-2014 | 60 | +0.012 | +0.119 |
| 2015-2019 | 43 | -0.009 | -0.112 |
| 2020-2023 | 30 | -0.020 | -0.266 |

**2015년부터 sign reversal** — recent 8년 negative drift. 가설은 2008-14 historical에서만 부분 입증, 2015+ in-sample에서 no edge.

### 5) Data gap acknowledged
INV13_Foreign_Resid_Individual_*은 **daily-only factor** (monthly Factor DB 부재). v2에서 INV02+INV04+INV08 monthly composite로 fallback. Residualization은 동일하게 적용했으나 daily-resolution 손실. Factor DB pipeline upgrade로 INV13 monthly aggregation 추가 시 재시도 가치 있음.

## AX Compliance (Pass)
- AX-003 (KR value EP_STANDALONE): EXCLUSION ✓ (no value)
- AX-004 (single quality_profitability): EXCLUSION ✓ (Growth + Flow cross-family)
- AX-005 (BAB single-sleeve top20): EXCLUSION ✓ (no low-beta)
- AX-007: EXCEPTION#1 multi-sleeve ✓ (Alpha sleeve 80/50/0% + Cash overlay 20/50/100% regime-conditional)
- AX-002 (process honesty): PASS ✓ — flow_resid_z negative IC를 "in spirit" 합리화 없이 정직 보고 + L-210 적립 권고

## Codex Critic Round (REJECT — 자체 진단과 일치)
- **Weakest assumption**: "BULL-regime or nonlinear ML version of Growth × Investor_Flow remains worth pursuing despite full-sample rank_IC 0.0025, ICIR 0.027, negative NORMAL/CAUTION, negative flow component."
- **C1 (HIGH)**: Alpha evidence is economically and statistically dead — 8/8 gates FAIL except TDC.
- **C2 (HIGH)**: Subperiod sign consistency 0.33 → factor decay, not stable KR alpha.
- **Unresolved**: BULL-only ICIR 0.272 sector-neutral 후 robustness 미검증; INV02/04/08 monthly fallback이 daily INV13 proxy로 적합한지 검증 부재.

## Sprint Termination Recommendation

### L-210 candidate lesson
"L-210: KR top-universe (n=500, liq 50M won, monthly 1M horizon) cross-family Growth (GR01/GR06/C17) × Investor_Flow (INV02/INV04/INV08) 60d-horizon residualized: linear additive composite 50/30/20 weight으로 alpha 부재. Flow component KR post-flow reversal 패턴 (Lee-Liu 2014)으로 negative IC (-0.015, t=-2.23). Growth modest positive (+0.014, t=2.03). Composite cancellation. 2015+ subperiod sign reversal — factor decay. Sprint Iter 7+8+9 연속 fail (Liquidity_Risk × 2 + Growth×Flow × 1) — KR top-universe simple linear composite alpha discovery 한계 명백."

### Pivot options
1. **ML sizing**: XGBoost/RF + Walk-forward 12M training. (Growth_z, Flow_z, Interact_z, regime, size, sector → 1M return). Linear cancellation 회피, nonlinear interaction 추출.
2. **BULL-only sub-strategy**: regime-restricted active. Sector-neutral robustness 검증 후 BULL-only diversifier 가능성. 그러나 35% active로 PG primary 부적격.
3. **Skewness Forensics × CFO accrual**: Iter 8 alpha agent alternative 잔여 (Chen-Hong-Stein 2001 + Sloan 1996 cross-family).
4. **Factor DB upgrade**: INV13 monthly aggregation 추가 후 재시도.

## Final Decision
- alpha_package emit (graduation FAIL 명시)
- Codex round REJECT 보존
- challenge_flags 7건 명시 (RF-A1 / GRADUATION_FAIL / FLOW_REVERSAL_KR / COMPOSITE_CANCELLATION / DATA_GAP_DAILY_ONLY / REGIME_PARTIAL_ALPHA / TDC_PASS / SPRINT_TERMINATION_RECOMMENDED)
- 상태 전이: SPEC_APPROVED → ALPHA_DONE (Risk/Optimizer agent로 진행 가능 — Q-Lead 결정 사항)
- ensemble_candidate = N (alpha 자체 미입증)
- graduation = N

## 합리화 표현 회피 확인
사용한 표현 검증:
- "in spirit" : 미사용 ✓
- "영향 미미" : 미사용 ✓
- "관행적 허용" : 미사용 ✓
- "보수적이면 괜찮다" : 미사용 ✓
- "대부분 결과 동일" : 미사용 ✓
- "이미 반영되어 있었을 것" : 미사용 ✓
- "백테스트 기간이 충분히 길어서 상쇄" : 미사용 ✓

모든 gate FAIL 명시 + 정직 component decomposition + KR post-flow reversal 학술 인용 + L-210 candidate emit. Common Charter 원칙 8 (No Silent Override) 준수.
