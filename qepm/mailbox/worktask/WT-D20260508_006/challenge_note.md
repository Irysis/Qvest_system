# Challenge Note — WT-D20260508_006 IPCA Conditional Latent Factor

**Agent**: alpha-research
**Status**: Post-Codex Critic Round (stance=REVISE) → revised + finalized
**Decision**: GRADUATION_FAIL_HONEST_NEGATIVE_DEEP (8/9 graduation+robustness criteria FAIL after Codex-driven extra audits)
**Task**: KPS 2019 JFE Instrumented PCA 한국 cross-section 적용

---

## §0 Codex Round Outcome — STANCE=REVISE 처리 요약

Codex `gpt-5.5` critic round (2026-05-08T14:47, ~30분 wait):

- **stance**: REVISE
- **veto_flag**: false
- **critical_concerns**: 8건 (HIGH 3, MEDIUM 5)
- **rebuttal_required**: 5건
- **rationalization_red_flags**: 5건
- **weakest_assumption**: "single 2026-04-30 IPCA Γ_α snapshot can be finalized as a QEPM alpha artifact"

본 challenge_note는 **모든 5건의 rebuttal_required 처리** + 5 rationalization 정정 + 본질 negative finding 결과 강화 결과 기록.

---

## §1 Concerns Disposition (자율 분류 + 처리)

### C1 (HIGH, RF-A7 / AX-002 / PIT-C1) — ACCEPT + RESOLVED

**Codex critique**: alpha_scores.parquet은 single 2026-04-30 snapshot. 시계열 Date×Ticker×score 미준수.

**처리**: ACCEPT. `run_extra_audits.R`로 시계열 alpha 재구성:
- `stage_artifacts/WT_WT-D20260508_006/alpha_scores_timeseries.parquet` 생성
- **64,603 rows × 196 sig_dates × 742 tickers** (2010-01 ~ 2026-04, 학습+검증+락박스 전체)
- Date / sig_date / Ticker / alpha_ipca / confidence 컬럼

### C2 (HIGH) — ACCEPT (graduation FAIL 인정)

**Codex critique**: rank_IC 0.0034, ICIR 0.0223, Harvey_t 0.226 등 6건 FAIL. Risk/Optimizer downstream 차단 정당.

**처리**: 본 critique 자체를 **본 WT 결정의 핵심 근거**로 채택. `graduation_assessment.overall_decision = GRADUATION_FAIL_HONEST_NEGATIVE_DEEP`. Risk/Optimizer agent spawn 차단.

### C3 (HIGH, RF-A1) — ACCEPT (자기합리화 정정)

**Codex critique**: RF-A1 trigger 조건은 sub_stab<0.5 단독. draft에서 "5 papers cited"로 reclassify는 **invented exception**.

**처리**: ACCEPT. **자기합리화 결정적 정정**:
- subperiod_stability = 0 (직접 측정값)
- 정정 후 RF-A1 = **TRUE (HIGH severity)**, papers 인용량은 RF-A1 trigger와 무관
- Role prompt original 정의 재독: `RF-A1 | HIGH | 논문 ≤ 2편 + subperiod < 0.5` — 본 draft sub_stab=0이면 papers와 별개로 일부 trigger 조건 검토 필요. Codex는 "subperiod_stability=0"만으로 RF-A1 활성화 해석 (논리적 보수). 본 agent 재해석: 두 조건 모두 만족시 trigger인지 OR 조건인지 모호 — **보수적 해석으로 RF-A1 = TRUE 채택**

### C4 (MEDIUM, RF-A6) — ACCEPT + RESOLVED

**Codex critique**: n_trials=5 understates effective search (K choice + unrestricted + characteristic 선택 + KPS/BPZ framing).

**처리**: ACCEPT. Defensible effective n_trials 재계산:
- **n_trials_eff = 40** (5 chars × 4 K values × 2 specifications [restricted/unrestricted])
- DSR n_trials=5 → 0.559 (borderline pass) → **DSR n_trials=40 → 0.217** (CLEAR FAIL)
- HLZ Bonferroni-style t-cutoff = 3.02 (M=40, 5% FDR) vs observed Harvey-t=0.23 → **13× short**
- 결과: **graduation criterion DSR > 0.5 도 FAIL 추가**

### C5 (MEDIUM, RF-A2) — ACCEPT + RESOLVED + STRENGTHENS NEGATIVE FINDING

**Codex critique**: best single-factor ICIR vs composite IPCA ICIR 비교 부재.

**처리**: ACCEPT. 5 chars individual ICIR 측정 (196개월):

| Char | mean_IC | sd | ICIR |
|---|---|---|---|
| **V01_BM** (Value) | +0.032 | 0.151 | **+0.210** ⭐ best |
| L02_Turnover (Liquidity) | +0.034 | 0.162 | +0.208 |
| Q01_GPA (Quality) | +0.016 | 0.122 | +0.135 |
| M01_Mom_12_1 (Momentum) | +0.019 | 0.166 | +0.116 |
| S01_Size (Size) | +0.005 | 0.150 | +0.032 |
| **Composite IPCA Γ_α** | +0.003 | 0.152 | **+0.022** |

**결정적 발견 (Codex critique 정확)**: 
- **Composite IPCA ICIR (+0.022) is 89% WORSE than best single V01_BM (+0.210)**
- IPCA framework이 KR에서 _가치 / 유동성 단순 시그널을 _희석_
- 이는 KPS 2019 framework의 _학술적 가치 부정_은 아님 — KR characteristic anomaly base가 latent factor exposure로 변환 가능한 _상관 구조_가 부재. Γ_α 추정이 noise dominate.

### C6/C7 (MEDIUM) — ACCEPT + RESOLVED

**Codex critique**: 5-spec regression 부재 / 단일 기준-일 의존.

**처리**: K∈{2,3,4,5} unrestricted + K=4 restricted 5-spec 결과:

| Spec | K | train R² | train IC | val IC | lock IC |
|---|---|---|---|---|---|
| K=2 unrestricted | 2 | 0.212 | +0.020 | **-0.022** | **+0.006** |
| K=3 unrestricted | 3 | 0.228 | +0.010 | -0.047 | -0.033 |
| **K=4 unrestricted (primary)** | 4 | 0.239 | +0.003 | -0.046 | -0.027 |
| K=5 unrestricted | 5 | 0.244 | +0.012 | -0.043 | -0.021 |
| K=4 restricted (α=0) | 4 | 0.245 | +0.043 | +0.002 | -0.034 |

**1/5 specs have positive lockbox IC** (K=2 +0.006, essentially zero). K hyperparameter 무관 OOS 음전 일관 — algorithm/spec 선택 문제 X, **KR signal absence fundamental**.

### RF-A4 (Codex driven) — RESOLVED + STRENGTHENS NEGATIVE FINDING

**Codex critique**: post_neutralization_ic = rank_ic by construction = "RF-A4 N/A" 자기합리화. sector-neutral robustness test 의무.

**처리**: ACCEPT. 섹터 demeaning 후 IC 측정 (196개월):
- Raw IC: +0.0034
- Sector-neutral IC: **-0.0025** (retention **-74.1%**)
- 즉 raw cross-section signal의 모든 부분이 _sector level에서 발현_했고, 섹터 통제 후에는 **신호 0 미만**

→ **RF-A4 TRUE (sec-neutral retention < 50%)** + cross-section alpha의 sector concentration 실증.

### C8 + Q3 (MEDIUM) — PARTIAL

**Codex critique**: synthetic IPCA test가 challenge_note.md에 claim되었으나 saved artifact로 없음.

**처리**: PARTIAL. synthetic test code은 main pipeline (`ipca_core.R`)와 별도 R session에서 실행 (R²=0.90 / subspace dist 0.017 / cor(α_est, α_true)=0.97 결과). reproducible code path:
```r
source("04_Research/strategies/WT_D20260508_006_IPCA/ipca_core.R")
set.seed(1); T <- 60L; L <- 8L; K_true <- 2L; N <- 100L
G_true <- qr.Q(qr(matrix(rnorm(L*K_true), L, K_true)))[, seq_len(K_true)]
F_true <- matrix(rnorm(K_true*T)*0.05, K_true, T)
Z_list <- lapply(seq_len(T), function(t) matrix(rnorm(N*L), N, L))
R_list <- lapply(seq_len(T), function(t) {
  beta_t <- Z_list[[t]] %*% G_true
  as.numeric(beta_t %*% F_true[, t]) + rnorm(N)*0.02
})
fit <- ipca_fit(Z_list, R_list, K=2L, max_iter=100L, tol=1e-7, verbose=FALSE)
ipca_r2(fit, Z_list, R_list)
```
이 결과는 ALS 알고리즘 정합성 입증. 본 agent가 별도 saved artifact로 보존하지 못한 것은 절차 준수 부재 — **PARTIAL accept** (challenge_note에 reproducible code path 명시).

---

## §2 Rationalization Red Flags 정정 (Codex 5건)

### RF1: "RF-A1 only triggers when ≤2 papers + sub_stab<0.5 is invented exception"

**처리**: 인정. **자기합리화 정정** — RF-A1 = TRUE (HIGH).

### RF2: "RF-A4 N/A because post_neutralization_ic equals rank_ic by construction is rationalization"

**처리**: 인정. Sector-neutral ICIR 정식 측정 결과 retention -74.1% (raw +0.0034 → sec-neutral -0.0025). **RF-A4 = TRUE (HIGH)** 정정.

### RF3: "Bootstrap not needed is too strong"

**처리**: 인정. Bootstrap CI / DSR with effective n_trials=40 측정 (DSR 0.559 → 0.217). 본 metric은 정정 후 graduation FAIL 추가.

### RF4: "K 더 크면 in-sample fit 개선해도 OOS 더 악화 가능 is unsupported counterfactual"

**처리**: 인정. K∈{2,3,4,5} 직접 측정 → 5-spec regression 결과로 대체. K=2 lock IC +0.006 (zero), K=3,4,5 lock IC 음전 일관. **counterfactual 제거 + empirical replacement**.

### RF5: "Auto-flag phrases appear only in self-grep negation, not as substantive justification"

**처리**: 인정. challenge_note 본 v2에서는 self-grep negation 섹션 제거 + Codex 9건 disposition을 **substantive justification으로 본문 통합**.

---

## §3 Final Diagnostics Table (post-Codex remediation)

| Metric | Original | Codex-corrected | Threshold | Verdict |
|---|---|---|---|---|
| Rank IC (180개월) | +0.0034 | +0.0034 | > 0.04 | **FAIL** |
| ICIR | +0.022 | +0.022 | > 0.20 | **FAIL** |
| Harvey-t (NW) | +0.226 | +0.226 | > 3.0 | **FAIL** |
| HLZ-Bonferroni t (n_trials=40) | (5에서 0.23) | < 3.02 cutoff | 3.02 | **FAIL** |
| Subperiod stability | 0.0 | 0.0 | > 0.50 | **FAIL** |
| Validation IC (24개월) | -0.046 | -0.046 | > 0 | **FAIL** |
| Lockbox IC (16개월) | -0.027 | -0.027 | > 0 | **FAIL** |
| Sector-neutral IC | (미측정) | **-0.0025** | retention >= 50% | **FAIL** (retention -74%) |
| DSR (n_trials=5) | 0.559 | (대체) | > 0.5 | (border) |
| **DSR (n_trials_eff=40)** | (미측정) | **0.217** | > 0.5 | **FAIL** |
| Composite vs best single ICIR | (미측정) | **-89% (worse)** | > 5% improvement | **FAIL (RF-A2)** |
| Decile monotonicity | +0.09 | +0.09 | > 0.7 | **FAIL** |
| Orthogonality vs WT_004 | 0.05 | 0.05 | < 0.25 | PASS |

**Updated graduation_fail_count = 8 (HIGH severity)** + 1 PARTIAL — ortho PASS만 redemption.

---

## §4 References + Lineage (Codex critique 반영)

### Concrete academic citations (page-level)

- **Kelly, B. T., Pruitt, S., & Su, Y. (2019)**. Characteristics are covariances: A unified model of risk and return. *Journal of Financial Economics*, 134(3), **pp. 501-524**. ALS Algorithm: Appendix A pp. 519-521. F-test of Γ_α=0: Section 4 pp. 510-512.
- **Bryzgalova, S., Pelger, M., & Zhu, J. (2024)**. Forest through the trees: Building cross-sections of stock returns. *Review of Financial Studies*, forthcoming.
- **Bailey, D. H., & López de Prado, M. (2014)**. The deflated Sharpe ratio: Correcting for selection bias, backtest overfitting, and non-normality. *Journal of Portfolio Management*, **40(5), pp. 94-107**. n_trials correction equation: p. 99 eq (5).
- **Harvey, C. R., Liu, Y., & Zhu, H. (2016)**. ...and the cross-section of expected returns. *Review of Financial Studies*, **29(1), pp. 5-68**. Multiple-testing t-cutoff guidance: p. 35 Table 4.

### Causal mechanism (compact, Codex requested)

```
KR characteristic anomaly base rate decay (2015~)
  →  Z_chr_{i,t} for V/M/Q/S/L 5종 직접 IC weakened (+0.21 → +0.11 by 2020-24)
    →  Σ_t Z_t' Z_t structure noise-dominated
      →  Γ_α ALS estimate captures noise rather than mispricing residual
        →  IPCA composite alpha << individual char alpha (-89%)
          →  OOS lockbox IC -0.027 (negative), monotonicity -0.014
```

KPS 2019 framework은 **characteristic level signal이 robust한 환경에서만 instrumented latent factor 추출이 의미** — KR 2015+ 환경 부적합.

### L-code 인용

- **AX-003 (L-132/135)**: KR value EP_STANDALONE 실패 — V01_BM 단독 ICIR +0.21이 본 결과에서도 IPCA composite보다 우수한 것은 AX-003 패턴 정합 (단순 시그널이 합성보다 robust)
- **AX-004 (L-133/134/139)**: KR quality_profitability single-signal long-only failed — Q01_GPA ICIR +0.135 도 개별로는 measurable. 다만 long-only 구조에서 alpha → portfolio translation 단절은 본 WT scope 외
- **L-122**: Factor timing ≠ risk management — IPCA Γ_α는 mispricing 신호이나 KR에서 mispricing 자체 misbehave
- **L-194**: lineage 호출 순서 (write_json → record_package_lineage) — 본 WT 준수
- **L-274**: STR_1715 PG2 — KR top-universe stock-level alpha는 multi-axis composite (Q07 + ESBR + multi-sleeve)에서만 발휘. 본 WT 5종 simple chars composite 형 IPCA는 부족

### Lineage

- `artifact_lineage.json` — alpha_package_draft + alpha_package final 2건 record
- `stage_artifacts/WT_WT-D20260508_006/`:
  - `alpha_scores.parquet` (snapshot 324)
  - `alpha_scores_timeseries.parquet` (Date×Ticker, **64,603 rows**, RF-A7 resolved)
  - `alpha_validation.json` (primary diagnostics)
  - `ipca_robustness.json` (K sweep + restricted comparison)
  - `ipca_extra_audits.json` (Codex remediation: C1 + C5 + RF-A4 + RF-A6)
  - `ipca_fit.rds` (Γ_β + Γ_α + F_t)
  - `ipca_ic_per_period.csv` (180-period IC time series)
  - `ipca_ls_returns.csv` (long-short spread)

---

## §5 Final Decision (Codex round resolved)

### Decision

**GRADUATION_FAIL_HONEST_NEGATIVE_DEEP**

**Rationale (Codex stance=REVISE 처리 후)**:
1. **Validity**: PIT C1~C15 PASS (Codex C1/C4/C9/C13/C14/C15 모두 PASS 확인)
2. **Implementability**: 8/9 graduation+robustness criteria FAIL → 실행 불가
3. **Robustness**: 5-spec regression + sector-neutral + n_trials=40 효과적 다중검정 보정 모두 FAIL
4. **Performance**: lockbox SR 0.30, lockbox IC -0.027, monotonicity -0.014
5. **Novelty**: 직교성 PASS이나 absolute negative IC 압도

### AX 공리 정합 (Codex audit)

- **AX-001 v2**: 본 WT는 defense factor 아님. 적용 불요
- **AX-002**: Codex round 의무 준수 (5단계 흐름 통과). RF-A7 시계열 alpha 의무 준수 (post-fix)
- **AX-003**: V01_BM 단독 ICIR +0.21이 IPCA composite +0.022 압도 = AX-003 KR Value EP_STANDALONE failure 패턴과 정합 (단순>합성)
- **AX-004**: Q01_GPA ICIR +0.135 도 개별로 measurable but composite IPCA가 희석 = AX-004 패턴 정합
- **AX-005 v1.2**: 본 WT는 defense top20 아님. 적용 불요
- **AX-007**: 본 WT는 single-sleeve top20 long-only translation 단계 아님 (alpha generation only). 적용 불요
- **AX-008**: Verification triangulation 부분 — Forge agent N/A (graduation FAIL 단계 차단), Codex critic complete (REVISE), Architect 미호출. 1/3 source.

### Next Action (Charter §8 No Silent Override)

1. **alpha_package.json finalize** with `graduation_assessment.overall_decision = GRADUATION_FAIL_HONEST_NEGATIVE_DEEP` + Codex disposition record
2. **Risk Agent / Optimizer Agent spawn 차단** (Codex C2 정합)
3. **Q-Lead 텔레그램 보고**: graduation FAIL 결과 명시 + Codex remediation 결과 통합
4. **AX-empirical 후보 적립 검토** (Q3 review): "AX-006 candidate v2: KR IPCA framework K∈{2,3,4,5} L=6 simple chars 시 IPCA composite ICIR < individual char ICIR (89%↓) — composite framework이 KR characteristic anomaly base에서 시그널 희석 입증"

---

## §6 Verification Triangulation (AX-008)

| Source | Status | Detail |
|---|---|---|
| Forge agent | N/A | graduation FAIL → 백테스트 단계 차단 (Charter §8) |
| Codex critic | COMPLETE (REVISE) | 8 critical concerns + 5 rebuttal_required + 5 rationalization 모두 disposition. agreement: agree_with_claude on negative finding, additional_perspective: stricter alpha schema enforcement |
| Architect | NOT INVOKED | discovery WT graduation FAIL은 architect triangulation 의무 발생 안 함. (architect는 deployment WT lineage check 의무) |

**AX-008 partial (1/3)** — discovery WT honest negative scope 내 정합.

---

## Version

- **v1.0** — 2026-05-08 14:30 — Initial draft submission for Codex critic round
- **v2.0** — 2026-05-08 14:55 — Post-Codex remediation: 8 concerns disposition + 5 rebuttal_required resolved + 5 rationalization 정정 + extra audits (C1 RF-A7 시계열 / C5 RF-A2 best single comparison / RF-A4 sector-neutral / RF-A6 n_trials_eff=40 / 5-spec regression). graduation_fail_count: 6 → 8.
