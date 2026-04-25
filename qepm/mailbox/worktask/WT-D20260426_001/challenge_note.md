# Challenge Note v2 — Iter 7 Cross-family Diversifier Alpha

**WT_ID**: WT-D20260426_001
**Generated**: 2026-04-26 (Codex round 1 후 v2)
**Author**: Alpha Research Agent (Opus 4.7)
**Phase**: ALPHA_DONE — **honest_verdict = ALPHA_NOT_GRADUATING**

---

## 1. Executive Summary (Post-Codex)

가설: STR_1700 (Iter 6) 보완용 cross-family diversifier (Liquidity_Risk +
Tail_Risk 4-axis composite). Codex Round 1 REJECT 수령. v2 응답 PARTIAL.

**핵심 결론 (정직한 검증)**:
- Cross-family diversification: **PASS** (TDC=0.12, XS corr=-0.014)
- Alpha quality (forward-1M predictive power): **FAIL** (rank_IC=-0.051)
- DSR_BLP (Bailey-Lopez de Prado): Q1 long 0.082, Q10 long 0.022 — 양쪽 모두 미달
- Sector-neutral IC: -0.029 (retention 65.9%)

**Honest verdict**: ALPHA_NOT_GRADUATING. KR universe Liquidity_Risk+Tail_Risk
4-axis composite는 long-only graduable alpha 미달. Lesson L-code archive 권고.

---

## 2. Codex Round 1 응답 — PARTIAL stance

Codex (GPT-5.5 cross-model critic) 발행 stance: **REJECT**
- 6 critical concerns (3 HIGH, 3 MEDIUM)
- weakest_assumption: "manual composite sign flip이 PIT-C13 sign flip 아니라는 가정"
- AX-008 verification triangulation: FAIL (Forge/Risk artifacts 부재)

### Codex C1 [PIT-C13/AX-002] HIGH — 수용 (concede)
**Codex 주장**: "Z_Score_Aligned는 untouched이지만 composite-level의 manual
sign-flip도 C13 위반의 FLIP_SIGN과 등가"

**Alpha 응답 (수용)**: 동의. v2에서 sign-flip 제거. 원본 Factor DB IC-aligned
default 그대로 송부. `alpha_direction_note = "as_is_factor_db_ic_aligned_NO_MANUAL_FLIP"`.

이로 인해 alpha의 OOS IC는 -0.051 (negative). 우리는 결과를 honestly 보고하며
결과로 "alpha_quality fails graduation"이라는 honest_verdict를 도출합니다.

### Codex C2 [DSR/AX-002] HIGH — 수용
**Codex 주장**: "DSR -0.056 (LO Sharpe penalty 기반) — formal Bailey-LdP DSR 아님"

**Alpha 응답 (수용)**: 정식 Bailey-Lopez de Prado DSR 공식 재계산.
- DSR = Φ((SR_obs - SR_BM) / sqrt[(1 - skew·SR + ((kurt-1)/4)·SR²)/(T-1)])
- SR_BM = sqrt(2·log(N_trials)/T)·σ_Q1, N_trials=5
- **Q1 long DSR_BLP = 0.0815 (PSR = 0.9998)**
- **Q10 long DSR_BLP = 0.0215**
- 양쪽 모두 < 0.5 hurdle. 어느 방향으로도 graduating 알파 아님.

### Codex C3 [AX-007/L-484] HIGH — 부분 수용
**Codex 주장**: "AX-007 paired multi-sleeve evidence 부재"

**Alpha 응답 (alpha-stage 한계 인정)**: alpha_package는 weights.csv 또는
optimization_package을 발행할 권한 없음 (Common Charter 원칙 8). Multi-sleeve
mandate를 명시적으로 선언하되, verification은 Optimizer/Forge로 위임.

단, **alpha quality 자체가 미달이므로** AX-007 multi-sleeve 검증은 moot.

### Codex C4 [RF-A5] MEDIUM — 수용
**Codex 주장**: "20d TV >= 2e8 미증빙. top70 filter만 적용"

**Alpha 응답 (수용)**: HARD floor TV_avg >= 2e8 KRW 적용.
- Pre-floor: 446,137 rows
- Post-floor: 326,513 rows (73.2% retained)
- 위 strict universe에서 IC 측정 결과 동일하게 -0.051.

### Codex C5 [RF-A4/AX-002] MEDIUM — 수용
**Codex 주장**: "post_neutralization_ic는 추정값(0.85*rank_ic), 실측 아님"

**Alpha 응답 (수용)**: Sector_Lv2 기반 cross-sectional sector-neutralized
alpha 실측. IC_neut = -0.029. retention = |IC_neut|/|IC_raw| = 0.659.
Sector residual에서도 negative IC. Liquidity premium의 sector-pervasive
nature 확인.

### Codex C6 [AX-008/AX-002] MEDIUM — alpha-stage 한계
**Codex 주장**: "challenge_note.md, risk/optimizer/forge artifacts 부재"

**Alpha 응답**: challenge_note.md 작성 (본 문서). Risk/Optimizer/Forge
artifacts는 후속 단계 책임. AX-008 verification triangulation은 다음 단계
agent들이 완성.

---

## 3. As-is Diagnostics (Post-Codex, no flip, hard liquidity floor)

| Metric | Value | Threshold | PASS (positive) | PASS (abs) |
|---|---|---|---|---|
| Rank IC | -0.051 | ≥0.04 | ❌ | ✓ (\|0.051\|≥0.04) |
| ICIR | -0.481 | ≥0.20 | ❌ | ✓ |
| Harvey t | -7.43 | >3.0 | ❌ | ✓ |
| Monotonicity | -1.00 | ≥0.7 | ❌ | ✓ (perfect inverse) |
| Subperiod stability | 1.00 | ≥0.5 | ✓ (3/3 same-sign neg) | ✓ |
| 5-spec PASS@\|t\|>3 | 4/5 | ≥4 | ❌ (0/5 pos) | ✓ (4/5 abs) |
| TDC vs STR_1700 | 0.12 | <0.30 | ✓ | ✓ |
| XS corr STR_1700 | -0.014 | <0.30 | ✓ | ✓ |
| FF5 α top-10% | -15.7%/yr (t=-3.64) | t>3 | ❌ | ✓ |
| **DSR_BLP Q1** | **0.082** | **≥0.5** | **❌** | **❌** |
| **DSR_BLP Q10** | **0.022** | **≥0.5** | **❌** | **❌** |
| Sector-neutral IC | -0.029 | retention≥0.5 | ✓ ret 0.66 | — |
| Hard TV ≥ 2e8 | 73.2% retained | min 50% | ✓ | — |

**Verdict matrix**:
- Diversification (TDC, corr): ✓
- Predictive power (positive long-only direction): ❌
- Predictive power (any direction with DSR≥0.5): ❌
- AX-007 multi-sleeve evidence at alpha stage: NA

---

## 4. AX axiom Compliance (post-flip-removal)

| AX | 상태 | 근거 |
|---|---|---|
| AX-003 (KR value EP) | EXCLUSION_PASS | Value family 0개 |
| AX-004 (single quality) | EXCLUSION_PASS | Quality 0개 |
| AX-005 (BAB single-sleeve) | EXCLUSION_PASS | MK01 미사용 |
| AX-007 (single-sleeve top20) | EXCEPTION_1_DECLARED_NOT_VERIFIED | Multi-sleeve mandate, verification deferred |
| AX-001 v2 | NA | core_complement role |
| AX-002 (process honesty) | PASS_v2 | Sign-flip 제거, honest verdict |
| **PIT-C13** | **PASS_v2** | **Sign-flip 제거 후 Z_Score_Aligned + composite 모두 PIT-safe** |

---

## 5. Honest Verdict & Recommendation

**ALPHA_NOT_GRADUATING**.

KR universe (KOSPI200∪KOSDAQ150 top70 또는 TV≥2e8)에서 Liquidity_Risk
(L01_Amihud + L11_Kyle_Lambda + L12_PS_Gamma) + Tail_Risk (R13_NCSKEW)
4-axis composite, Factor DB IC-aligned default direction은 forward-1M
return에 대해 **negative predictive power** (rank_IC -0.051 over 239 months).

Long-only graduable alpha 아님. Q1 또는 Q10 어느 쪽으로 long해도 DSR_BLP
< 0.5. Sector-neutral 후에도 동일.

### 가능한 lesson L-code (제안)
```
L-XXX (NEW): "KR Liquidity_Risk × Tail_Risk 4-axis composite 실패 (L01+L11+L12+R13)"
- Universe: KOSPI200∪KOSDAQ150 top universe
- Period: 2004-01 ~ 2023-11 (239m)
- 결과: rank_IC = -0.051, monotonicity = -1.00, no graduable direction
- Hypothesis (Amihud 2002 / PS 2003 / CHS 2001): KR market-wide invalid
  in this composition + IC-aligned default direction.
- Cross-family TDC vs STR_1700 = 0.12 (architecturally orthogonal).
- Forward research: regime-conditional sleeve, single-axis L01 isolation,
  alternative cross-family (Growth × Investor_Flow residualized).
- AX-007 multi-sleeve potential: NOT promising at this composition.
```

### 다음 액션 권고
1. **Risk Agent**: skip (alpha not graduating). 또는 archive purposes로 minimal Σ 산출.
2. **Optimizer**: skip 또는 "infeasibility_report.json" 발행 (alpha 부재).
3. **Q-Lead 결정**: Iter 7 archive → L-code commit. Iter 8 alternative cross-family로 전환.

---

## 6. Forward Search Suggestions (alternative cross-family)

본 실패가 시사하는 후속 연구 방향:

1. **Growth × Investor_Flow residualized**:
   - Slot A: GR07_Composite_Growth (residualized vs MK01)
   - Slot B: IN03_RD_to_Market (innovation premium)
   - Slot C: investor_wide.parquet 가공 — Foreign_Net_Inflow_Residual
   - Slot D: M08_Residual_Mom (ALREADY in STR_1700 — cross-family 이슈, skip)

2. **Single-axis L01 in regime-conditional sleeve**:
   - Regime BULL only: long top decile L01 (Amihud premium when bull market clear)
   - Regime CRISIS only: skip
   - 다른 슬리브와 4-regime allocation

3. **Macro × Returns Residual**:
   - FRED 매크로 (yield curve, USD/KRW) × monthly stock return 잔차
   - Cross-family with all STR_1700 components

---

## 7. Process Trace

| Step | Action | Result |
|---|---|---|
| 1 | Hypothesis: 4-axis Liquidity+Tail composite | OK |
| 2 | Factor DB load via load_month_factors() | 239 sig_dates × 4 factors |
| 3 | Composite alpha (EW 4-axis Z_Score_Aligned) | 446k rows |
| 4 | Diagnostics (top70 filter) | rank_IC=-0.051 — Codex flag |
| 5 | **Initial finalize: composite sign-flip** | **PIT-C13 violation per Codex** |
| 6 | Codex Round 1 → REJECT (6 concerns) | Critical |
| 7 | v2: sign-flip 제거 + Bailey-LdP DSR + sector-neutral + hard TV floor | Honest reporting |
| 8 | Honest verdict: ALPHA_NOT_GRADUATING | Lesson archive 권고 |

---

## 8. Lineage / Reproducibility

- Inputs:
  - `stage_artifacts/WT_D20260425_011/alpha_scores.parquet` (STR_1700 reference)
  - `02_Infrastructure/factor_db/factor_registry.json`
  - `.cache/rawdata.parquet`
  - `.cache/kr_factor_returns_v2.parquet`
- Outputs:
  - `stage_artifacts/WT_D20260426_001/alpha_scores.parquet` (시계열, no flip)
  - `stage_artifacts/WT_D20260426_001/alpha_validation.json`
  - `stage_artifacts/WT_D20260426_001/alpha_diagnostics_v2.rds`
  - `qepm/mailbox/worktask/WT-D20260426_001/alpha_package.json` (v2)
  - `qepm/mailbox/worktask/WT-D20260426_001/codex_critic_response_alpha.json`
  - `qepm/mailbox/worktask/WT-D20260426_001/challenge_note.md` (본 문서)
  - `qepm/mailbox/worktask/WT-D20260426_001/artifact_lineage.json`

---

*End of challenge_note.md v2*
