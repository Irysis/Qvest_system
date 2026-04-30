# FER (Financial Engineering with R, 한글) — 적용 제외 사유 + 보존

> **Source**: 한글 금융공학 textbook (저자/출판 미확인). 748 pages. 원어 한국어.
> **추출 도구**: Hancom OpenDataLoader v2.4.0 (markdown 1.4MB)
> **작성일**: 2026-04-30 (Phase 3, textbook 흡수 plan)
> **결정**: **현 시스템 적용 제외, 보존만**

## 책 구조 (ToC 기반)

- 머릿글 / 차례 / 서론
- 금융경제학
- 금융파생상품의 가치평가 (맛보기)
- 자산가치평가의 근본적 정리
- 이항나무모형과 실물옵션
- 확률론의 기초
- 확률과정론의 기초
- 마팅게일의 기초
- 확률미적분의 기초
- 확률미분방정식의 기초
- Black-Scholes방정식
- 동치마팅게일측도
- 금융시계열분석 입문
- 참고 문헌 / 찾아보기

## 핵심 주제

**Derivatives pricing 중심**:
- Stochastic calculus (확률미적분)
- Stochastic differential equations (SDE)
- Martingale theory
- Black-Scholes equation
- Binomial tree pricing
- Real options

**금융시계열분석**: 입문 수준 (1 챕터)

## 적용 제외 사유

### 1. Domain Mismatch
본 Qvest 시스템은 **long-only equity portfolio** (KOSPI200 ∪ KOSDAQ150). FER은 **derivatives (옵션) pricing** 위주 — 본 시스템은 옵션 미사용.

### 2. Mechanism 비호환
FER 핵심:
- Itô calculus / SDE (continuous-time stochastic processes)
- Martingale measure (Q-measure 변환)
- Black-Scholes PDE solution

본 시스템 alpha:
- Cross-sectional rank-based factor (discrete-time monthly)
- Long-only equity weight allocation
- Regime-conditional cash overlay

→ **수학적 toolkit 자체가 다른 dimension** (continuous-time SDE vs discrete-time cross-section).

### 3. CLAUDE.md 정합
CLAUDE.md prohibitions §11: "논문 근거 없는 임의 실험 금지" + 본 시스템 mandate 정의 ("롱온리, 종목수 ≤ 20"). 옵션 strategy는 정의 외.

### 4. 인프라 부재
본 시스템에는 옵션 가격 데이터 / Greeks 계산 인프라 부재. FER 코드 reuse 시 별도 구축 필요 — 효익 < 비용.

## 보존 사유 (적용 외이지만 폐기 안 함)

### 추후 확장 시점
다음 시점에 재검토 가능:
1. **옵션 strategy 도입** (covered call / protective put / collar) — KR 시장 KOSPI200 옵션 활용
2. **Pure derivatives portfolio** 별도 시스템 구축
3. **Volatility risk premium harvesting** (variance swap, VIX trading) — KR 시장 KOSPI200 VKOSPI 활용

### 학술 이해 측면
- 금융공학 한글 reference로 도훈/Q-Lead의 학술 이해 배경 보존
- 금융시계열분석 입문 (1 챕터)는 alpha agent의 시계열 모델 이해 배경 — 단 FRM Pfaff Ch8 (rugarch) + NMF Ch14가 더 직접 적용 가능

## 결정

| 항목 | 결정 |
|---|---|
| 본 시스템 적용 | ❌ 제외 |
| 추출된 markdown 보존 | ✅ `/tmp/odl_books/fer/` (재 생성 가능, 원본 PDF 영구 보존) |
| Agent prompt reference 추가 | ❌ 미적용 (FRM/NMF만 추가) |
| L-code 적립 | ❌ 미적립 (적용 외 case) |
| 추후 재검토 trigger | 옵션 strategy 도입 결정 시 |

## 메모

- 원본 PDF: `01_Literature/3.Risk & Portfolio Management/Financial Engineering with R.pdf` (748p, 6.8MB)
- Hancom 추출: `/tmp/odl_books/fer/Financial Engineering with R.{md,txt}` (markdown 1.4MB, text 1.1MB)
- 추출 시간: ~12초 (한글 OCR 정확)
- 본 결정은 도훈 명시 "원서 지식 흡수 플랜" 의 Phase 3 산출 (2026-04-30)
