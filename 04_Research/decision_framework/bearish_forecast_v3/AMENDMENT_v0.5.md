# v3 Plan AMENDMENT v0.5 — Paper Verification Findings + Phase 5 Entry Re-examination

**작성**: 2026-05-24 KST Session 84
**Owner**: Q-Lead (도훈 mandate)
**대상**: `PLAN.md` v0.4 (2026-05-24)
**상태**: **DRAFT for 도훈 confirm** (PLAN.md 직접 수정 전 review 단계)
**Trigger**: Phase 1 deep read 6편 + Q-Lead direct B1 read 1편 = 7편 verification 결과 **사실 오류 12건 검출**

---

## Section A: Executive Summary

Phase 1 paper survey 진행 중 PLAN.md v0.4 본문에 인용된 paper 정량/methodology에서 **12건 사실 오류** 발견. 가장 중요한 3건은:

1. **B1 KOSPI paper "Neural Portfolio annual 36.4% / SR 0.91" — paper에 portfolio backtest 결과 자체가 없음**. paper는 distributional eval (LPS/CRPS/PIT) + VaR backtest만. 완전 misattribution.
2. **B1 LSTM architecture / sequence length 잘못 인용** — paper actual은 3-layer 128/64/32 (v0.4 "2-layer hidden=64"), seq=10 (v0.4 "60-120 sliding").
3. **C2 Neural Lévy paper portfolio Sharpe 추정 인용 시** — paper actual은 Sharpe ≈ 0, IR ≈ -1.0 vs SPY (Section 10 trading mechanics 한계 명시). v0.4가 만약 high Sharpe로 기술했다면 B1과 동일 hallucination 패턴.

**결론**: PLAN.md v0.4는 **paper-direct verification 없이 작성됨** (chain of cites 또는 AI-generated summary일 가능성). Phase 5 (모델 implementation) 진입 전 **Plan v0.5 정정 + 도훈 confirm 필수**.

**Source files**:
- `00_literature/paper_deep_read_subagent_output.md` (596줄, 6편)
- `00_literature/paper_summary.md` (Q-Lead B1)

---

## Section B: 12 Factual Errors + Corrections

### B.1 B1 — Michańków 2025 "KOSPI DNN" arxiv 2508.18921

| # | v0.4 본문 | Paper actual | 정정안 |
|---|---|---|---|
| **E01** | "Neural Portfolio annual 36.4%, Sharpe 0.91 (OOS 2020-2024)" §1.5.4 | **paper에 portfolio backtest 자체 없음**. Distributional eval (LPS/CRPS/PIT) + VaR backtest (Kupiec/Christoffersen/McNeil-Frey) only | **§1.5.4에서 Neural Portfolio 인용 전체 제거**. 정량 인용은 LPS/CRPS/VaR exceedance % 사용. KOSPI LSTM-SSTD LPS=1.2847, CRPS=0.5165, VaR 1% LSTM-STD 0.84%. |
| **E02** | "LSTM 2-layer hidden=64 → FC(4)" §1.5.2 | **3-layer 128/64/32 + dense output** | "**LSTM 3-layer 128/64/32 → FC(p)** where p ∈ {2, 3, 4} (param count per distribution)" |
| **E03** | "Lookback 60-120 거래일 sliding" §1.5.2 | **Sequence length = 10 (Table 1 paper)** | "**Sequence length 10 (paper baseline)**. v3 hyperparameter expansion 시 {10, 20, 30, 60, 90, 120} 비교 권장." |
| **E04** | "CRPS 4-15% 개선 vs GARCH (지수별)" §1.5.4 | paper Table 5는 **VaR exceedance만 vs GARCH 비교**. CRPS는 DNN 내부 비교만 (Table 2). | "**KOSPI LSTM-SSTD CRPS 0.5165 vs CNN-N 0.5285 (-2.3%); 6 indices별 LSTM-SSTD best in LPS/CRPS. GARCH 비교는 VaR exceedance % only**" |
| **E05** | "KOSPI skewed Student-t best fit (S&P/DAX/Nikkei 대비 left tail 강함)" §1.5.4 | LSTM-SSTD가 LPS/CRPS best는 맞음. 다만 **PIT p-value 모든 KOSPI model rejection (calibration imperfect)** — paper에 "left tail 강함" 직접 언급 없음 | "**KOSPI LSTM-SSTD best by LPS/CRPS. PIT calibration imperfect (모든 model p<0.05 reject)**. KOSPI 특유 left tail asymmetry 주장은 secondary inference, paper-stated 아님" |

### B.2 B5 — NGBoost Duan 2020 ICML arxiv 1910.03225

| # | v0.4 본문 | Paper actual | 정정안 |
|---|---|---|---|
| **E06** | "ML benchmark (UCI tabular) NLL 5-15% 개선 vs Gaussian baseline" §1.5.4 | UCI 9 dataset best case **0~10%** (Boston -0.8% / Wine +2.2% / Protein +2.8% / Yacht +83%(outlier) / Year 0%) | "**UCI tabular NLL: 9 dataset 중 NGBoost best 4-5 cases (Energy/Yacht/Wine/Protein). 개선 폭 0~10% (Yacht outlier 제외). 5-15% over-statement**" |
| **E07** | "KR 직접 검증 없음 (v3가 첫 KR 적용)" §1.5.2 | **paper는 healthcare(survival) + weather 응용 강조. 금융 dataset 자체 없음 (UCI tabular only)** | 유지 + 보강: "**paper에 금융 시계열 적용 없음. KR equity 적용은 모두 extrapolation. i.i.d. assumption (paper Section 5 미해결) — temporal CV + purging/embargo 별도 implementation 필요**" |
| **E08** | "Architecture: Tree depth=4-6, M=300-500 boosting rounds" §1.5.2 | paper hyperparameter sweep: tree depth {3,4,5,6}, n_estimators {500, 1000, 2000}, learning_rate {0.001, 0.01, 0.1} (Table 3 area) | "**Tree depth {3,4,5,6}, n_estimators {500-2000}, η {0.001, 0.01, 0.1}, distribution {Normal, Lognormal, Laplace, Exponential}**. Paper baseline은 Normal + n_est=500" |

### B.3 C2 — Neural Lévy SDE 2025 arxiv 2509.01041

| # | v0.4 본문 | Paper actual | 정정안 |
|---|---|---|---|
| **E09** | "Bates 2008 jump 정합" §1.5 / Section 1.1 | **paper는 Merton 1976 + Kou 2002 + CGMY 2002 인용**. Bates 2008 직접 인용 없음 | "**jump distribution: Merton 1976 (Gaussian mix) / Kou 2002 (double exponential) / CGMY 2002 (Lévy)** 지원. Bates 2008 인용 paper 본문 부재" |
| **E10** | (만약) "Cross-sectional equity 적용 결과" 또는 specific Sharpe 인용 §1.1 | paper actual cross-sectional **US S&P 500 (500 stocks, 2005-2024)**, portfolio Sharpe ≈ 0, IR ≈ -1.0 vs SPY (Section 10) | "**US S&P 500 500 stocks, 2005-2024, test 2020-2024. NLL 1D +5.77% / 1W +3.60% / 1W CRPS +14.36% vs best baseline. Portfolio Sharpe ≈ 0, IR ≈ -1.0 (paper Section 10 trading mechanics 한계 명시) — distributional forecast 우수하나 trading rule 미흡**. KR 적용 결과 paper 자체에 없음" |

### B.4 F1 — Conformal TS Forecasting 2025 arxiv 2511.13608

| # | v0.4 본문 | Paper actual | 정정안 |
|---|---|---|---|
| **E11** | "non-exchangeable time series" §1.1 / "Conformal post-hoc Distribution-free coverage 보장" §1.5.5 | paper actual: **simulated AR(1) / ARMA(1,1) / GARCH(1,1) / mean-shift DGP만**. real-world stock data 결과 없음. β-mixing slack theorem 명시 | "**4 family CP for non-exchangeable TS (Weighted CP / EnbPI / ACI / Block CP). Coverage theorem β-mixing slack: ε_train = β(i-n_train) (Theorem A.4.1). 본 paper simulation only (AR/ARMA/GARCH + mean shift). real-world stock 결과 paper 부재 — KR 적용은 extrapolation**" |

### B.5 A1 — Vulnerable Growth 2019 AER

| # | v0.4 본문 | Paper actual | 정정안 |
|---|---|---|---|
| **E12** | "US GDP GaR 정통 — 5%/25%/50%/75% quantile penalized regression" §1.1 | framework 일치. **specific Tables 3-4 numeric quantile coefficients ACCESS_FAIL** (paywalled). **US만**, KR/다른 국가 결과 paper에 없음 | "**Adrian-Boyarchenko-Giannone 2019 AER 109(4) — US GDP GaR framework: Q_{y_{t+h}}(τ\|x_t) = β_0(τ) + β_1(τ)y_t + β_2(τ)NFCI_t. τ ∈ {0.05, 0.25, 0.5, 0.75, 0.95}. 1973Q1-2015Q4 US sample. KR/cross-country 결과는 IMF subsequent 확장 paper (별도 cite)**. **specific β coefficients v3 plan 인용 시 university library access 필요**" |

### B.6 E5 — Christoffersen cite 명확화

| # | v0.4 본문 | Paper actual | 정정안 |
|---|---|---|---|
| **E13** | "Christoffersen 2009 RFS" §1.1 / §3.3 | **가장 널리 인용되는 VaR backtest framework은 Christoffersen 1998 IER "Evaluating Interval Forecasts"** (UC/Independence/CC tests). 2009 RFS paper 별도 존재 가능 (review 또는 extension). v0.4 정확히 어떤 paper 참조 명확화 필요 | "**Christoffersen 1998 IER (Evaluating Interval Forecasts)** UC/Markov-Independence/CC tests. **2009 RFS는 별도 review/extension paper일 수 있음 — v0.5에서 인용 paper 명확 확정 필요**" |

### B.7 E6 — Gneiting-Raftery 2007 KR 적용 없음 (cosmetic)

| # | v0.4 본문 | Paper actual | 정정안 |
|---|---|---|---|
| **E14** | (v0.4가 specific KR empirical numbers 인용 시) §3.3 | paper는 **review/theory + sea-level pressure 6 month case study만**. KR empirical 결과 없음 | "**Gneiting-Raftery 2007 JASA review/theory paper. CRPS 정의 (Eq 20-21), Log score (Eq 19), Energy score (Eq 22), interval score (Eq 43)**. KR empirical numbers는 별도 source 필요" |

---

## Section C: Phase 5 Entry Criteria 재검토

### C.1 Plan v0.4 §3.2 Cycle 51 lesson checklist 진행 상황

- ✅ `02_Infrastructure/sanity_checks/bear_date_audit.R` 4/4 PASS (Session 84, 2026-05-24 16:09 KST)
- ✅ `02_Infrastructure/validation/pit_enforcement.R::validate_label_direction()` PASS (forward 100%, COVID asserted, n_sample=100)
- ⚠️ `.claude/rules/data_table_shift_convention.md` 정합 — **신규 코드 작성 시 review 의무 (Phase 5a-1 코딩 단계)**
- ⏸️ AX-008 Verification Triangulation (Forge + Codex + Architect 2/3 PASS) — **Phase 5a-1 실증 단계에서 적용**

### C.2 신규 Entry Criteria (v0.5 추가 권장)

본 12건 paper verification 결과 기반:

| Criterion | 기준 | 이유 |
|---|---|---|
| **CR-V01** | Plan v0.5 amendment 도훈 confirm | E01-E14 정정 반영된 plan baseline 필요 |
| **CR-V02** | B1 Phase 5a-1 spec = **paper actual (3-layer 128/64/32, seq=10)** | Reproduce는 paper 정합. v3 plan author 추정 spec 사용 시 reproduce 무효 |
| **CR-V03** | Hyperparameter expansion 범위는 **paper baseline에서 시작** | paper baseline 먼저 reproduce → 그 위에 expand. 처음부터 expand 시 reproduce 의미 상실 |
| **CR-V04** | NGBoost 시계열 적용 시 purging/embargo 5-fold CV 명시 | paper i.i.d. assumption — 시계열 적용 시 별도 처리 |
| **CR-V05** | Linear Pool ensemble weight 결정 시 **per-component validation CRPS 의무 보고** | v0.4 §5.4.3 Geweke-Amisano 이미 명시 — 강화 |
| **CR-V06** | Paper-cite 정량 보고 시 **paper-direct verification 또는 ACCESS_FAIL 명시** | 본 12건 같은 hallucination 재발 방지 |

### C.3 Phase 5 entry "신규 GO/NOGO" 결정 path

```
Plan v0.5 amendment 작성 (현재 단계)
   ↓
도훈 confirm checkpoint (★ 현 단계 mandate 확인)
   ↓
GO 결정 시:
   Phase 2 paper_summary.md 통합 (B1 + 6편 subagent 통합)
   ↓
   Phase 3 paradigm_matrix.md + v3_algorithm_shortlist.md (paper actual spec 정합)
   ↓
   Phase 4 final 도훈 confirm + Plan v1.0 baseline
   ↓
   Phase 5a-1 B1 reproduce (paper 3-layer 128/64/32 / seq=10 / 6 model 비교)
   ↓
   Phase 5a-2 B5 NGBoost prototype (UCI baseline → KR equity 확장)
   ↓
   ...

NOGO 결정 시:
   v0.4 본문 인용 hallucination 패턴 다른 plans에도 검토 (메모리 + 다른 plan files)
   대안 paradigm 재검토 (도훈 mandate 변경 가능)
```

### C.4 Risk Assessment (v0.5 vs v0.4)

| Risk | v0.4 risk level | v0.5 권장 mitigation |
|---|---|---|
| R5 5-seed inflation | Medium → **유지** | 15-seed strict + paired bootstrap CI 유지 (도훈 mandate 정합) |
| **R13 신규 Paper hallucination risk** | **HIGH** (E01-E14) | Phase 5a 진입 전 **모든 인용 정량 paper-direct verification 의무** |
| **R14 신규 Architecture mismatch** | HIGH (E02, E03) | Phase 5a-1 prototype 시작 시 paper exact spec 따름 (3-layer 128/64/32 seq=10) |
| R12 Ensemble diversity | Medium → **유지** | Spearman ρ < 0.8 (v0.4 §5.4.4 강화 유지) |
| R8 Lock-in 변경 옵션 포기 | Medium | Phase 5a-1 reproduce 실패 시 변경 trigger 명문화 유지 |

---

## Section D: Plan v0.5 Amendment 적용 권장 순서

1. **즉시 (Q-Lead 본 task)**: 본 AMENDMENT_v0.5.md 작성 ✓ 완료
2. **도훈 confirm**: 본 amendment review + GO/NOGO 결정
3. **GO 시 (Q-Lead 본 task 후속)**:
   - PLAN.md §1.5.2 / §1.5.4 / §1.5.5 / §3.3 / §5.3.4 본문 정정 → PLAN.md v0.5 저장
   - paper_summary.md 6편 subagent 통합 + 정정사항 반영
   - paradigm_matrix.md + v3_algorithm_shortlist.md 작성 (Phase 3)
4. **NOGO 시**: 메모리 commit (recurring hallucination lesson) + 도훈 alternative path 결정

---

## Section E: Memory 적립 권장 (recurring lesson)

본 paper-direct verification 결과는 단발성 plan 정정이 아닌 **plan authoring 방법론 lesson**으로 메모리 적립 권장:

- **메모리 type**: `feedback` (recurring lesson)
- **rule**: Plan / methodology 작성 시 paper 인용 정량은 paper-direct verification 의무. Chain of cites 또는 AI-generated summary 단독 사용 금지.
- **Why**: Plan v0.4 작성 시 12건 hallucination 검출 (Session 84). 가장 critical하게 portfolio Sharpe/CAGR이 paper에 없는 수치로 인용됨. 후속 Phase 5 implementation에서 reproduce 무효 위험.
- **How to apply**: 모든 paper-cite 정량은 (1) paper-direct read or (2) "verify 안 됨 (가정)" 명시. specific numbers 인용 시 paper Section/Table 명시. specific architecture 인용 시 paper Figure/Table 명시.

---

## Change log

- **2026-05-24 Session 84** (본 amendment 작성) — Phase 1 deep read 7편 (Q-Lead B1 + subagent 6편) 완료 후 v0.4 본문 12건 사실 오류 검출. Plan v0.5 amendment draft 작성. 도훈 confirm 대기.
