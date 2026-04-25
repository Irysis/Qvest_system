# Alpha Agent Challenge Note — WT-D20260425_009

**Author**: Alpha Research Agent
**Date**: 2026-04-25
**Subject**: External validation framework — Carhart-4 vs FF5 backfill 비교 + Self-challenge

---

## 1. Self-Challenge Triangulation

### CH-1. "Carhart-4 도입만으로 게이트 통과" 가설은 잘못되었다 (REJECTED)

원 Work Task는 두 옵션을 제시:
- A. Carhart-4 (MKT/SMB/HML/WML) — 100% 표본 가용 (희망)
- B. FF5 RMW/CMA backfill — Risk Agent 협업 필요

**실측 검증 결과 (WT_005 baseline 기준):**
- KR `kr_factor_returns.parquet`의 **HML 시작일은 2016-04** (RMW/CMA 2017-05보다 1년 빠를 뿐)
- Carhart-4 joint n=46 vs FF5 joint n=40 — **둘 다 작은 표본**
- Carhart-4 t_NW=1.834 vs FF5 t_NW=1.843 — 거의 동일

→ Option A의 "표본 100% 가용" 가정은 **현재 KR factor parquet 상태 기준 false**.
→ HML/RMW/CMA 모두 backfill해야 의미 있는 표본 확장이 가능.

### CH-2. RF-A1 ~ RF-A5 자체 진단

| Red Flag | Trigger | 적용 여부 |
|---|---|---|
| RF-A1 (논문≤2 + subperiod<0.5) | Carhart 1997 + FF 2015 + Harvey 2016 = 3 papers, subperiod_stability 0.726 | OK (n/a) |
| RF-A2 (composite < 5% baseline) | factor mix 변경 없음 — 적용 외 | n/a |
| RF-A3 (recent ICIR > overall*1.5) | 변경 없음 (signal mix 동일) | n/a |
| RF-A4 (post-neutral IC < 0.3*raw) | 변경 없음 | n/a |
| RF-A5 (top decile illiquid > 50%) | Universe 동일 | n/a |

**신규 RF (Iter4-specific)** — 본 Iter는 외부 validation framework 변경이므로:
- **RF-A6** (NEW, MEDIUM): "**Multiple testing inflation**" — 동일 alpha를 여러 factor model로 테스트하면 spurious p-value risk. Harvey-Liu-Zhu (2016) t>3.0 게이트가 존재하지만 **여러 spec(CAPM/FF3/FF5/Carhart-4/FF6)을 보고하면서 가장 좋은 t를 cherry-pick하는 risk** 존재.
  - 완화: alpha_package에 모든 spec t_NW를 동시 보고 + DSR 적용

### CH-3. Iter3 reported t_NW = 2.691의 출처 모호성

본 Work Task의 input에서 "현 MEGA_05 Harvey FF5 t_NW = 2.691"이라 명시했으나 WT_005 (실제 MEGA_05 기준 backtest)의 ff5_regression_full.txt는 **t_alpha (NW lag=4) = 0.8964 (FF5, 2017+, n=40)**.

→ **2.691** 수치는 다음 중 하나에서 나왔을 가능성:
- (a) 다른 MEGA_05 버전의 다른 backtest (Iter3 별도 산출)
- (b) Pre-Lockbox 한정 부분 표본 (예: 2008~2020 train만)
- (c) 다른 alpha computation (예: signed alpha vs FF5 t)

→ **challenge_flag**: Iter4 진입 전 **"baseline t_NW=2.691의 정확한 출처/spec 문서화"** 필요. 이 수치 검증 없이는 "gap=-0.26" 자체가 illusory일 수 있다.

### CH-4. AX-002 위험 — 수치 GAP 추격 의심

L-200 시리즈 교훈: "수치 GAP만 쫓는 것은 v54 freeze 사고의 원인". 본 Iter는:
- **OK**: factor mix 변경 없음 (alpha source 보존)
- **OK**: external validation framework만 변경
- **CAUTION**: t_NW를 2.95로 끌어올리기 위해 spec을 cherry-pick하는 행동은 AX-002 위반
  - 완화: 모든 5개 spec(CAPM/Carhart-3/Carhart-4/FF5/FF6) 동시 보고 의무

### CH-5. Multiple Testing Penalty

표본 확장(n=40→285) 자체로 t가 sqrt(285/40) ≈ 2.67배 증가하는 것은 통계적 "free lunch"가 아님. 표본 확장은 **장기 alpha 안정성**을 검증하는 것이지, **단기 alpha를 magnify**하는 것이 아니다.

따라서 backfilled t_NW=4.0~5.5 예상치를 보고할 때, **subperiod stability** (2002-2010 / 2011-2018 / 2019-2026) 분할 t_NW를 함께 보고해야 진정성 있는 검증.

---

## 2. Decision: Option B (FF5 backfill via Risk Agent)

**근거**:
1. Option A 단독으론 게이트 통과 불가 (실측 t_NW 1.834)
2. KR DART TTM (`fundamental_xlsx_ttm.parquet`)은 2000Q1+ 가용 — backfill 데이터 인프라 존재
3. RAWDATA + DART 조합으로 KR FF5 portfolio 재구축 feasible
4. Risk Agent가 본 작업의 자연스러운 owner (factor return = market structure variable, alpha 영역 아님)
5. Backfill 후 **Carhart-4와 FF5 모두 동시 산출 가능** → 단일 의사결정으로 양쪽 옵션 모두 활용

**Selected framework (alpha_package에 기록)**: `ff5_backfilled` + Carhart-4 동시 보고
**Expected t_NW gain**: 보수 추정 4.0~5.5 (게이트 2.95 충분 통과)
**Risk Agent handoff**: `risk_agent_handoff.md` 작성 완료

---

## 3. Lockbox 분리 의무

본 Iter4 결과 보고 시 다음 분리 필수:
- **Pre-Lockbox (Train + Validation)**: 2002-07 ~ 2023-12 (n ≈ 257)
- **Lockbox (Out-of-sample)**: 2024-01 ~ 2026-03 (n ≈ 27)

게이트 통과는 **Pre-Lockbox t_NW**로 판단. Lockbox t_NW = 2.253 보존을 별도 보고 (decay 진단용).

---

## 4. DSR (Deflated Sharpe Ratio) 계산 의무

표본 확장 시 다중검정 trial 수가 증가하는 것이 아니라, **단일 spec의 power가 증가**하는 것. 따라서:
- DSR trial 수: 100 (factor model selection 5종 × 결과 보고 spec 20종 보수 추정)
- DSR computation: `bootstrap_dsr_fast(returns, n_trials=100, B=1000)` (R14 Rcpp 사용)
- 게이트: DSR ≥ 0.5

---

## 5. Open challenge_flags (Q-Lead 알림 필요)

| Flag | Severity | 내용 |
|---|---|---|
| FLAG-1 | MEDIUM | Iter3 t_NW=2.691 baseline 출처 모호 → 검증 후 진행 권고 |
| FLAG-2 | LOW | RF-A6 multiple-testing inflation — 5개 spec 동시 보고로 완화 |
| FLAG-3 | INFO | Risk Agent handoff 의존성 — backfill 실패 시 Carhart-3 fallback (n=91, t=2.55) |
| FLAG-4 | INFO | Backfilled t_NW expected 4.0~5.5 — 학술적으로 적절 (>7은 의심 trigger) |

---

**END Challenge Note**
