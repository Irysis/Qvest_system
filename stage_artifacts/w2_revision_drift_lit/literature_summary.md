# Analyst Forecast Revision Drift — 문헌 재검증 (Track A)

**작성**: 2026-07-02 (도훈 지시, W2 근거 확정)
**목적**: 딥리서치에서 verify 미완이던 analyst-revision drift claim(SSRN 370425 등) 실존·수치·부호·horizon 확인. W2(earnings@3M lead) 레버의 이론적 토대 점검.
**검증 방법**: WebSearch + WebFetch (jina 유료 게이트로 스칼라 API 미가용 → 공개 abstract/summary/RePEc/저자 PDF 경유). 원문 표(테이블)의 셀 단위 수치는 페이월/PDF 인코딩으로 일부 미확보 — **미확인 항목 명시**.

---

## Claim 1 — Gleason-Lee 2003 (Accounting Review 78, 193-225; SSRN 370425)

**"Analyst Forecast Revisions and Market Price Discovery"**, Cristi A. Gleason & Charles M.C. Lee.

### 실존
✅ **확인**. SSRN abstract_id=370425 (제목 "Analyst Forecast Revisions and Market Price Discovery"). 저널: The Accounting Review, Vol 78, No 1 (2003), pp. 193-225. (별도 워킹버전 SSRN 303980 "…Market Price Formation" 존재 = 같은 저자 계열 논문.)

### 핵심 주장 (검증 결과)
1. **혁신(innovation) vs herding 리비전 — 부호·크기 확인 ✅**:
   시장은 "새 정보를 담은 리비전(high-innovation revision)"과 "단지 컨센서스 쪽으로 이동하는 리비전(low-innovation/herding revision)"을 **충분히 구분하지 못한다**. 그 결과 **high-innovation 리비전에서 post-revision drift(PFRD)가 더 크다**. → *"고혁신 리비전 drift가 크다"* claim 성립.
2. **저커버리지·저가시성 강화 확인 ✅**:
   - **낮은 애널리스트 커버리지** 종목에서 가격조정이 더 느리고 불완전 → **drift 더 큼**.
   - **저명(celebrity, II All-Star) 애널리스트**의 리비전은 조정이 빠르고 완전 / 무명이지만 정확한(WSJ Earnings-Estimator) 애널리스트는 느림. → *"저커버리지·저가시성서 drift 강하다"* claim 성립.
   - 요약(다중 소스 일치): *"High-innovation revisions, lack of analyst visibility, and lower analyst coverage at the firm level are associated with larger magnitudes of post-forecast revision drift."*

### 부호·horizon·수치
- **부호**: 양(+). 리비전 방향으로의 후속 drift(상향 리비전 → 후속 (+)수익).
- **Horizon**: ⚠️ **정확한 개월수 원문 테이블 미확보**. Gleason-Lee 계열은 통상 리비전 후 **다음 어닝 발표(≈1분기)까지 지속**되는 drift를 분석 프레임으로 씀(하단 Claim 2와 정합). "1M/3M/6M 중 어디 최강"의 셀 단위 수치는 **미확인(honest)**.
- **크기**: ⚠️ hedge-portfolio return %의 정확한 수치는 페이월로 **미확보**. cross-sectional 변동(커버리지·혁신도별)이 주 결과이며 헤드라인 스프레드 %는 원문 표 참조 필요.

**판정**: 메커니즘(혁신>herding, 저커버리지 강화)·부호는 **명확히 확인**. 정확한 horizon 개월수·크기 %는 미확인(원문 테이블 필요).

---

## Claim 2 — Post-Forecast Revision Drift + Revision Momentum (JBFA 2020)

**"Analyst Underreaction and the Post-Forecast Revision Drift"**, Po-Chang Chen, Ganapathi S. Narayanamoorthy, Theodore Sougiannis, Hui Zhou. JBFA 2020, Vol 47(9-10), pp. 1151-1181. (SSRN 2578757)

### 실존
✅ **확인**. Journal of Business Finance & Accounting 2020, 47(9-10):1151-1181. (도훈 배경노트의 "Post-Forecast Revision Drift (JBFA 2020)" 정확히 이 논문.)

### 핵심 주장 (검증 결과)
1. **개별 애널리스트 리비전의 양의 시리얼 상관(momentum) 확인 ✅**:
   *"positive serial correlation (momentum) in individual analysts' revisions to their earnings forecasts"* — 선행연구 재확인.
2. **revision momentum이 drift 크기 예측 확인 ✅**:
   revision momentum과 PFRD 간 **양의 연관**(indirect + direct test 둘 다). streak/연속성이 클수록 후속 drift 큼.
3. **메커니즘 = 애널리스트 자신의 underreaction ✅**:
   투자자 underreaction만이 아니라 **애널리스트 리비전 과정 자체의 지연조정**이 PFRD의 중요 기여자. → "다음 리비전이 같은 방향으로 이어짐 = 지속신호"의 이론 근거.
4. **horizon**: drift는 뉴스 성격·정보환경과 함께 변동. ⚠️ "다음 어닝 catalyst까지 지속"의 명시적 개월수는 abstract 레벨서 **미확정** — PFRD 문헌 관행상 리비전 후 다음 분기 어닝까지(≈1분기/3M) 흡수. 셀 단위 수치 **미확보**.

**판정**: **revision streak/momentum이 drift를 예측한다 + 지속성이 핵심**이라는 W2 S1(innovrev의 streak 성분)의 직접 이론근거 **확인**. horizon 정확 수치 미확인.

---

## Claim 3 — Da-Schaumburg 2011 (JFM 14, 161-192)

**"Relative valuation and analyst target price forecasts"**, Zhi Da & Ernst Schaumburg. Journal of Financial Markets, Vol 14(1), Feb 2011, pp. 161-192.

### 실존
✅ **확인**. JFM 14(1):161-192, 2011. 저자 PDF: academicweb.nd.edu/~zda/TargetPrice.pdf.

### 핵심 주장 (검증 결과)
1. **섹터-상대 TP implied return(TPER) long-short = 알파, raw는 무정보 ✅ (부호 명확)**:
   - 12개월 목표가 대비 현재가로 TPER 계산 → **섹터(산업) 내** 최고 TPER long / 최저 short. → **유의한 abnormal return + 거래비용 후에도 유효**(S&P 500).
   - **결정적**: TPER을 **전체 종목 횡단(across all stocks)으로 랭크하면 유의성 소멸**. **섹터 내(within-industry) 랭크만 알파**. → 우리 S2_tpsect 설계(WICS 섹터중립 z)의 정확한 문헌 사상.
2. **왜 섹터-상대만 되나 (메커니즘) ✅**:
   애널리스트는 자기가 커버하는 **산업 내 종목의 fundamental 이탈 식별엔 전문성**이 있으나, **산업 systematic risk / factor risk premium 지식은 부족**. → raw TPER엔 애널리스트가 못 잡는 산업/팩터 리스크프리미엄 노이즈가 섞임 → 섹터중립이 이를 제거.
3. **target price가 recommendation/EPS보다 fundamental value의 직접 척도** — TP를 신호축으로 쓴 근거.

### 부호·horizon·수치
- **부호**: 양(+). 섹터 내 고-TPER이 후속 outperform.
- **Horizon**: ⚠️ 다중소스 요약에 **"주로 발표 후 1개월(1M)에서 유의, 섹터 내 정렬 시에만"**이라는 진술 있음(2차 요약 레벨) — **1M-concentrated**로 시사되나 원문 표 셀은 **미확보**. (raw TP는 무정보, 섹터-상대만 1M 알파.)
- **크기 (확보됨) ✅**: **월간 스프레드 Sharpe ≈ 0.41, 5-factor alpha ≈ 0.67%/월**(2차 요약 인용, 원표 대조 권장). 표본기간 1997-2004. 섹터분류 **GICS 9-sector이 FF10/1-digit SIC보다 우월**.

**판정**: 섹터-상대만 알파·raw 무정보의 **부호·메커니즘 명확 확인**. horizon(1M 집중 시사)·크기(월 SR 0.41/α 0.67%)는 2차소스 레벨 확보(원표 대조 필요).

---

## Claim 4 — Revision drift horizon 구조 (1M / 3M / 6M 어디 최강)

### 문헌 종합
- **Da-Schaumburg (TP 섹터상대)**: **1M 집중** 시사 — 발표 후 1개월에 유의, 그 후 소멸(단 섹터 내만). TP는 빠르게 반영.
- **EPS revision drift (Gleason-Lee / Chen-2020 PFRD)**: **리비전 후 다음 어닝 발표(≈1분기/3M)까지 지속**되는 것이 표준 프레임. revision momentum(streak)이 다음 리비전·drift를 예측 → **다중-월(1~3M) 지속**. Womack(1996) recommendation drift는 **최대 6M**(단 recommendation ≠ EPS/TP).
- **정리**: 신호축마다 최적 horizon이 다름 —
  - **EPS 리비전 / 컨센서스 지속성 신호 → 1~3M(다음 어닝까지) 지속형** (streak·momentum이 강화).
  - **TP 섹터상대 → 1M 집중, 빠른 소멸형**.
  - **recommendation → 최대 6M(가장 느림)**.

⚠️ "우리 내부 earnings@3M lead"의 3M이 문헌의 EPS-drift 다음-분기 프레임과 **개념적으로 정합**(리비전→다음 어닝 catalyst). 단 문헌은 대부분 US·L/S·quarterly-formation이고, 셀 단위 "3M이 1M보다 강하다"의 직접 US 수치는 **미확인**.

---

## 종합 — 문헌 claim별 확인표

| # | Claim | 실존 | 부호 | 메커니즘 | Horizon | 크기(수치) |
|---|---|---|---|---|---|---|
| 1 | Gleason-Lee: 혁신>herding, 저커버리지 강화 | ✅ | + | ✅ 명확 | ⚠️ 다음 어닝(≈분기) 프레임, 셀 미확보 | ⚠️ 미확보(페이월) |
| 2 | JBFA2020: revision momentum이 drift 예측 | ✅ | + | ✅ 애널리스트 underreaction | ⚠️ 다음 어닝까지, 셀 미확정 | ⚠️ 미확보 |
| 3 | Da-Schaumburg: 섹터상대 TP=알파, raw=무정보 | ✅ | + | ✅ 산업내 전문성 有/산업리스크 지식 無 | ⚠️ 1M 집중 시사 | ✅ 월 SR 0.41, α 0.67%/월(2차) |
| 4 | Horizon: EPS 1~3M / TP 1M / rec 6M | ✅(종합) | + | 신호축별 상이 | EPS 다음분기(3M 개념정합) | — |

**정직 라벨**: 4개 claim 모두 **실존·부호·메커니즘 확인**. **미확인 = 원문 테이블 셀 단위 (a) Gleason-Lee/JBFA2020 정확 horizon 개월수 (b) hedge-portfolio return %** — jina 스칼라 유료게이트 + 페이월로 미접근. 억지 정합 없이 "메커니즘·부호는 확인, 정밀 수치는 미확인"으로 보고.

---

## 출처
- Gleason-Lee 2003: SSRN 370425 (papers.ssrn.com/sol3/papers.cfm?abstract_id=370425); The Accounting Review 78:193-225; Semantic Scholar 03a27df9...
- Chen-Narayanamoorthy-Sougiannis-Zhou 2020: JBFA 47(9-10):1151-1181; SSRN 2578757; RePEc bla/jbfnac/v47y2020i9-10p1151-1181
- Da-Schaumburg 2011: JFM 14(1):161-192; academicweb.nd.edu/~zda/TargetPrice.pdf; RePEc eee/finmar/v14y2011i1p161-192
- Womack 1996 (recommendation drift up to 6M): 2차 인용(quantseeker.com)
- Decay 맥락: PEAD review (ScienceDirect S2214635020303750); Grinblatt "Analyst Bias and Mispricing" (NBER w31094)
