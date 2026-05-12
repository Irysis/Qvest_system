# 5 Path 비교 평가 — 1순위 선정 근거 (한국 환경 정합 4번째 직교 알파 sleeve)

## 컨텍스트

- WT-D20260508_003 (VRP 4 sub-variants 정식) 도훈 명시 중단 (옵션 거래 X + KRX 옵션 chain 미가입)
- 선행 실패 3건: WT_001 VRP (lag-1 + ML leakage + anti-hedge) / WT_002 v4 ML (PIT-C1 lookahead) / WT_002 v5 (honest FAIL)
- 한국 주식 long-only mandate / 회전율 600% hurdle / SR target 2.0 vs PerfA 1.665 = gap 0.335

## 1순위: Path 1 — 거시 잔차 long-horizon (점수 27/30 = 0.900)

### 메커니즘
- ECOS 한국 거시 (M2 / 산업생산 / 환율 / 단기/장기금리) + FRED (TED / TS / DEFY) × KOSPI 잔차 → low-frequency 종목 cross-section
- 6~12m horizon → 회전율 자연 ≤300% (hurdle 600% 정합)
- 종목 단위 cross-section 추출 (single-sleeve 위반 회피)

### 학술 출처 3축
- Cooper-Gulen-Schill 2008 RFS — Asset growth × macro state cross-section
- Belo-Lin-Vitorino 2014 RFS — Brand capital macro state-dependent
- Asness-Moskowitz-Pedersen 2013 JF — Value and momentum everywhere (macro env)
- 한국 적용 사례: 이상혁 외 2018 KFA / Lee-Ohk 2014

### L-code 3축
- L-454: 한국 내부 데이터 > 글로벌 FRED. L2 Korean Internals cor=-0.46 > L1 Global -0.14 → ECOS 우선
- L-280: Cross-Asset TSMOM cross-section vs time-series 정의상 직교 → macro-residual도 같은 paradigm
- L-281: Hybrid 60/40 + managed futures 진화 → 4번째 source = macro-residual cross-section

### 정량 근거
- 한국 macro factor M21~M29 conditional ICIR 0.10~0.18 (Factor DB 실측, 313 factor 중)
- 잔차화 + 종목 cross-section 결합 시 ICIR boost 0.20~0.50 추정 (학술 baseline)
- Hybrid 3-source (STR_1715 + TSMOM + KR 10y bond) 대비 직교성 cor 0.10~0.25 추정 (낮음)
- 회전율 예상 150~300% (≤600% hurdle 정합)

### Cycle 1~3 함정 자연 회피
- WT_001 lag-1 autocor 0.404 → macro 6~12m horizon = autocor noise 자연 dilute
- WT_002 v4 PIT-C1 lookahead → t-1 shift + monthly aggregation 자연 회피
- WT_001 CRISIS regime cor(VRP, AR) +0.515 anti-hedge → macro 잔차는 cross-section 분포 변화 = anti-hedge 본질 X

### 점수 분해 (6 axis)
- ax1 한국 데이터 가용성: **5/5** (ECOS + FRED + Factor DB 즉시)
- ax2 학술 사례 충실도: **4/5** (3 RFS/JF 인용 + 한국 일부)
- ax3 예상 IC 정량: **3/5** (Factor DB conditional ICIR 0.10~0.18, 잔차화 boost 0.20~0.50 추정)
- ax4 회전율 hurdle 정합: **5/5** (예상 150~300% ≤ 600%)
- ax5 AX 공리 정합: **5/5** (single-sleeve 위반 사례 없음)
- ax6 인프라 부담: **5/5** (즉시 sprint 가능, 별도 인프라 0)

### 잔존 위험
- macro signal 자체 noisy (Mei-Wu 2014 노이즈 제거 의무)
- factor zoo overfitting (Harvey 2017 t>3.0 의무)
- conditional ICIR 0.10~0.18 약함 → 잔차화 + cross-section 결합으로 boost 의무

---

## 2순위: Path 2 — 위기 조건부 방어 (AX-001 v2) (점수 26/30 = 0.867)

### 메커니즘
- Q07 + D-family + multi-axis composite. crisis_alpha + Core 대비 MDD 완화 + bad/normal IC ratio
- multi-sleeve EXCLUSION 의무 (AX-005 v1.2 single-sleeve standalone 실패 인지)

### Path 1 대비 약점
- 이미 STR_1715 (Q07 활용) + KR 10y bond ETF가 defense source 차지 → '4번째 직교 sleeve' 목적과 정합 약함
- Path 1은 macro → cross-section = TSMOM 시계열 ≠ macro-residual 정통 4번째 source
- 회전율 200~400% (정합 약함, Path 1의 150~300% 우월)
- AX-005 v1.2 single-sleeve standalone 실패 위험 (L-136/140/165/166)

### 정량 근거
- Q07 stress ICIR +0.413 (L-121)
- D-family conditional crisis IC 0.10~0.20
- composite ICIR 0.20~0.30 추정

### 점수 분해
- ax1: 5 / ax2: 5 / ax3: 4 / ax4: 4 / ax5: 3 / ax6: 5 = 26

---

## 3~5순위 요약

### Path 4 다중 주파수 앙상블 (점수 21/30)
- 일간 + 월간 Factor DB 가용 / 학술 한국 적용 적음
- 회전율 hurdle 위험 (정상-only harvest 의무) / STR_1715 자체가 이미 monthly + M4 daily overlay 사용 → 직교성 모호
- ax4: 2 / ax3: 3

### Path 3 강화학습 state-space (점수 18/30)
- Python GPU 가용 / 한국 RL 학술 사례 적음
- WT_002 v4 ML residual trauma 재발 위험 highest (in-sample 0.30+ → OOS 0.05~0.15 우려)
- 회전율 통제 어려움 (RL action 자유도 ↑) / AX-002 reward shaping 위반 위험
- ax3: 2 / ax4: 2

### Path 5 대체 데이터 정서 (점수 14/30)
- 한국 뉴스 NLP 인프라 미구축 (별도 sprint) / 외부 데이터 fetch 의무
- 학술 한국 검증 사례 적음 / 'qepm 데이터 외부 전송 금지' (Prohibition #12) 정합 검토 의무
- ax6: 1 / ax2: 2

---

## 다음 단계 (도훈 결정 input only)

### 정식 WT 진입 권고: WT-D20260509_001 (Path 1)
- theme: Macro-residual cross-section long-horizon
- step_0_hypothesis required: ECOS + FRED 잔차화 spec / expected_role / why_now / core_reference / lesson_check (L-454 / L-119 / L-122)
- preliminary factor specs to explore (4건): M_RES_TED_residual / M_RES_M2_residual / M_RES_FX_residual / M_RES_TS_residual
- 직교성 target: rho < 0.25 vs Hybrid 3-source
- graduation criteria inherit: Harvey t>3.0 / DSR>0.5 / ICIR>0.20

### 본 mission 산출물
- `qepm/mailbox/research/exploration_5path_20260508/path_comparison.json` (5 path × 6 axis 정량표)
- `qepm/mailbox/research/exploration_5path_20260508/path_recommendation.md` (본 문서)
- 텔레그램 v6.2 brief (별도 발송)

### 본 mission 제외 사항
- factor specs 직접 작성 X
- weight 결정 X
- alpha_package 산출 X
- Codex Round 5단계 면제 (탐색 mission, 정식 WT 아님)
