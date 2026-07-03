# DVAA_DVFS_ETF 강화방향 리서치

**작성**: 2026-06-13 (Q, ultracode 멀티에이전트 워크플로우 wf_d7b2537a-ce3 — 에이전트 28개: 감사 5 + 제안 5렌즈 + 병합 1 + 적대검증 16 + 완결성 비평 1)
**대상**: `05_Production/3,Asset_Allocation/3-1.DVAA/DVAA_DVFS_ETF.R` (글로벌 ETF 17종 월간 VAA + EGARCH 변동성 오버레이, 실계좌 운용)
**원칙**: 05_Production 무수정(read-only). 모든 수정·실험은 `04_Research/dvaa_dvfs_revalidation/` 사본에서. 본 보고서의 수치는 (코드 line) 또는 (문헌 보고치) 라벨 — 실행 검증 미수행 항목은 "mechanical inference(미실행)" 명시.

---

## 0. 한 줄 결론

**성능 강화보다 측정 진실성 복원이 선행이다.** 백테스트의 2007~2014 구간은 데이터 결함(역방향 채움)으로 신뢰 불가이고, EGARCH 오버레이는 타이밍 정렬 오류 + fail-unsafe 구조로 설계 취지(전술적 위기 감지)가 무력화된 상태다. P0 결함 수정 3건 → 강화 실험 arms(신호/필터/배분) → sweep 선언 + DSR/walk-forward 심판 프로토콜의 3단 로드맵을 제시한다. 운용 즉시 적용 가능한 무수정 레버는 트랜치 분할 집행(M12)과 SHV→현금 매핑(M11-B) 2건.

---

## 1. 라이브-결함 triage (도훈 의사결정 최우선 표)

실계좌 가동 중이므로 "지금 매월 라이브 신호를 오염시키는 결함"과 "과거 측정만 오염시키는 결함"을 분리한다.

### 1-A. 지금 라이브 신호를 오염시키는 결함 (수동 개입 검토 대상)

| ID | 결함 | 위치 | 영향 |
|---|---|---|---|
| F-02/DVFS-05 | **EGARCH 학습창이 직전월말(ep[i-1])에서 끝남** — "1-step 예측"이 의사결정 시점 기준 약 1개월 전 날짜를 타깃. 최근 1개월 수익률 정보 통째 폐기 | line 220 | 2020-02형 월중 급락을 당월 결정에 반영 못함 — 위기 감지가 정의상 한 달 지각. PIT 위반은 아님(오히려 보수적)이나 오버레이 존재 이유 무력화 |
| DVFS-02 | **GARCH 적합 실패 시 무조건 'Stable'** (fail-unsafe) — 소표본 MLE 비수렴은 변동성 국면 전환기에 더 빈발하므로 정확히 필요한 시점에 무경보 | lines 203, 218-233 | 침묵 실패. signal_history로 실패율 추적도 불가(Predicted_Vol NA로만 간접 식별) |
| DVFS-01 | **EGARCH(1,1) 120 obs 적합** — 문헌 권장 GARCH(1,1) 최소 500 obs(Hwang & Valls Pereira 2006, EJF — EGARCH 전용 임계는 미확인 외삽 라벨)의 1/4. Spike 판정이 추정 노이즈 지배 | line 143, 220-221 | 매월 트리거 신뢰성 저하 |
| F-03 | 인라인 주석 뒤바뀜(코드는 정상: bull 0.99/bear 0.90) — 향후 "주석에 맞춰 코드 수정"하는 2차 사고 위험 | lines 194, 197 | 운용자 오독 위험 (코드 동작 자체는 설계의도 정합) |
| F-08 | **정본 미확정**: B=11(메인) vs B=10(Debuging), EGARCH vs GJR, fallback worst-safe vs TLT | line 142 vs Debuging line 18 | 어느 파라미터가 운용 정본인지 파일만으로 판별 불가 |
| F-13/critic | rugarch solver='hybrid' 비결정성 + yahoo 조정종가 소급 재조정 + from 미지정(quantmod 기본 2007-01-01) | lines 106-112 | 라이브 신호 재현성 훼손 — 같은 날 두 번 돌리면 신호가 다를 수 있음 |

### 1-B. 과거 측정만 오염 (백테스트 신뢰성)

| ID | 결함 | 위치 | 영향 |
|---|---|---|---|
| F-01/DVFS-11/A-1 | **[critical] na.locf0(fromLast=TRUE) 역방향 채움** — 상장 전 구간을 미래 첫 가격으로 채워 가짜 무변동 시계열 생성. PDBC 2014-11-07 상장(yfinance 실측) → **7.85년 가짜**, ACWX 2008-04 → 1.25년, EMB 2007-12 → 0.96년, HYG 2007-04 → 0.27년 | line 112 | 모멘텀 0 → 위기 달 top4 진입 가능 + ERC cov 특이행렬(zero-vol 자산 극단 가중) + breadth 부풀림 + NAV에 0% 수익 직접 지급. **top4 진입·ERC 지배는 mechanical inference(미실행)** — `wts_DVAA_DVFS.xlsx`에서 2014-11 이전 PDBC 보유월 존재 여부로 즉시 실측 판정 가능 |
| critic | **mid-series 결측 역채움 = 1일 look-ahead**: 시계열 중간 결측일도 익일 가격으로 채워져 결측일 수익이 하루 앞당겨 실현 | line 112 동일 기제 | M01 수리 시 pre-inception 마스킹과 별도로 처리 필요(전방 na.locf만 허용) |
| F-09 | 비용모델: turnover=양레그 합산 |Δw|×fee 0.002 → **전면 전환 1회 ≈40bps, Risk-On↔Off 왕복 ≈80bps**. 최초 진입비용 누락, `prod(1+net)-1` 자체합성(표시용) | lines 320-331 | 휩쏘 빈도에 따라 연 1%+ 누수 가능(빈도는 signal_history 실측 필요) |
| F-04 | 당일 종가 신호 + 같은 종가 체결 가정 — **한국 거주자에게 t+1 체결은 민감도가 아니라 물리적 기본값**(미국 장 마감 후 주문은 익일) | lines 163-167, 298 | 백테스트-실계좌 괴리 1차 원인 후보. base-case를 t+1 체결로 재정의 검토 (critic 지적) |
| F-10/F-11 | 타 머신 setwd 하드코딩, 미정의 VAA_ETF 참조(line 443), signal_history export 첫 행(2007-12) off-by-one 누락 | lines 106, 443, 378-381 | 단독 실행 불가 + 보고 결손 |

### 1-C. 백테스트 신뢰구간 결론 (A-5, **데이터-무결성 한정** 라벨)

- **2008-01~2009-04**: ACWX+EMB+HYG 12개월 모멘텀 윈도우 잔존 오염 + PDBC — **불신, 인용 금지**. 이 전략의 존재 이유인 2008 GFC 방어 성과는 가짜 데이터 위에서 산출된 값.
- **2009-04~2015-10**: PDBC 1종 오염 — 부분 신뢰.
- **2015-11월말 리밸런스 이후**: 전 자산 실데이터 — 단, 이는 데이터 무결성 한정이며 GARCH stale window·fail-unsafe·비용 결함은 전 구간 지속. 선택편의 관점에서는 3계층(pre-2017-07 VAA 논문 공개 이전 / ~오버레이 작성 / post-작성) 추가 라벨 필요.
- 인용 가능한 무결 위기 표본 = **2020-03, 2022 단 2회**. 통계 검정력 본질 부족 — 은폐가 아닌 정직 보고 대상(AX-000).

---

## 2. 설계 일탈 사실 (버그는 아니나 전략 행태를 지배 — 도훈 의도 확인 필요)

1. **F-05: breadth 허들이 VAA 원전과 본질적으로 다름** — 원전(Keller & Keuning 2017, SSRN 3002624)은 offensive 유니버스 한정 "모멘텀≤0 자산 수"(절대), 본 구현은 "최고 안전자산 모멘텀 미만"(상대)을 안전자산 포함 17열 전체에서 카운트(lines 247-249). 금 +30% 랠리 국면(2024~25)엔 멀쩡한 주식 전부가 카운트되어 b 포화 → 만성 Risk-Off 단일 안전자산 100%. Risk-On top4 후보에도 채권/금 전부 포함(setdiff가 SHV만 제외, line 286).
2. **F-06: '진짜 위기' 판정 후 강제 Risk-On** — Spike+10일 하락+ADX>20 판정 후에도 평균모멘텀≥0이면 VAA Risk-Off를 뒤집고 Risk-On(line 273). 폭락 초입(2008-01, 2020-02류)엔 후행 모멘텀이 아직 양수인 게 일반적이라 최악 시점에 위험자산 배분. **단, 비평 결과 이것은 "미문서화 버그"가 아니라 헤더 Tactical Rule 2(lines 15-17)에 명문화된 설계 의도("위험자산 모멘텀 양수 + 안전자산 스파이크 = 로테이션")와 VAA 철학의 충돌** — 수리 전 도훈 의도 확인이 선행조건. 발동 이력은 signal_history에서 `GARCH_Signal=1 ∧ Final_Decision=Risk-On ∧ Market_Trend<0 ∧ ADX>20`으로 실측 가능.
3. **DVFS-04: 검정통계량-기준분포 불일치** — 1일 조건부 예측 vol을 "120일 평활 실현 vol 분포"의 분위수와 비교 → 명목 1%/10% 임계가 실제 트리거율과 무관한 미정의 값. 0.99/0.90 캘리브레이션 근거 소멸.
4. **DVFS-03: 측정대상이 매월 바뀌는 스플라이스 지표** — "직전월 보유 안전자산 1종"의 vol을 감시(GLD↔TIP↔TLT 교체). 트리거 빈도가 시스템 위험이 아니라 "지난달 뭘 들고 있었나"에 의존. Risk-On top4로 들어간 금/채권도 '안전자산 보유'로 오인(F-12).
5. **DVFS-06/07: 자유 파라미터 ≥15개 vs 월간 결정 ~220회·위기 표본 ~6회**(사건 목록 미확정 라벨) + 동일 디렉토리에 하이퍼파라미터만 다른 형제 변형 7+종(B=10/11, EGARCH/GJR/SVL, cov창 1/3개월, 가중 원전/커스텀)이 풀샘플 stratStats로 비교·선택돼 온 구조 — measurement-graduation §3 기준 **sweep 분류**. 재검증 시 DSR≥0.5 HARD + n_trials 등재 의무.

---

## 3. 문헌 핵심 시사점 (강화방향의 근거)

1. **Keller 계열의 진화 방향은 '복잡도 축소'** — VAA(2017) → DAA(2018, canary 2종 분리: VAA-G12 OS CF 60.8%→28.8%, R 10.1%→12.9% [문헌 보고치, DAA 논문 Fig 7a PDF 추출 — 재확인 권장]) → BAA(2022, 방어 top-3 분산) → HAA(2023, TIP 단일 canary, turnover 472%→275%). 본 전략(EGARCH+동적분위수+SMA200+ADX 4중 오버레이)은 **역방향**.
2. **Keller 자신의 보고치가 IS→OS 감쇠를 보여줌**: VAA-G12 R 20.9%→10.1%, MDD 5.8%→13.1% (IS Dec70–Dec93 / OS Dec93–Mar18). 본 전략 IS 수치도 같은 디레이팅을 기대치로.
3. **GARCH의 한계효용은 작다**: historical vol ≈ GARCH (Poon & Granger 2003 JEL, 93편 메타), HAR-RV/단순 RV가 ARCH계열 능가(Corsi 2009 계열), vol-managed 알파도 실시간 구현에서 소멸(Cederburg et al. 2020 JFE, 103전략). EGARCH 우위 실증은 주식 leverage effect 기반(Hansen & Lunde 2005)인데 적용 대상이 안전자산(금은 inverted leverage 보고 다수) — 선택 근거 약함.
4. **안전자산 vol spike 가설 자체는 사례 실증 있음**: flight-to-safety 실재(Baele et al. 2020 RFS), 2020-03 dash-for-cash(NY Fed) — 문제는 가설이 아니라 추정 방법(EGARCH-120)과 false positive(2013 taper: 채권 vol 급등 + S&P +32.4%).
5. **Rebalance Timing Luck**: 월말 단일 시점 + 고턴오버 = RTL 고위험군. Keller BAA 8-트랜치 실증: 평균 13.9%→14.2%, 결과 표준편차 약 2/3 감소 (AllocateSmartly, 문헌 보고치). **변형 간 성과차가 RTL 잡음보다 작으면 변별 불가** — 모든 A/B 비교에 RTL 통제 필수.
6. **2022 실패 모드**: TAA 집계 MDD −12.1%(과거 약세장 −2.8~−7.1% 대비 악화) — 원인은 방어 전환 시 장기 국채 선택(채권-주식 동반 하락). 본 전략 Risk-Off 풀에 TLT 포함 = 동일 노출. HAA의 TIP canary가 문헌 제시 해법.

---

## 4. 강화방향 16건 (적대검증 전원 'modify' 조건부 생존 — 검증 조건 포함 채택)

> 전 제안 공통: `04_Research/dvaa_dvfs_revalidation/` 사본에서만 구현. 모든 ablation arm은 M13 프로토콜(trial 등재 + DSR + RTL 통제) 경유. 기대효과는 방향성만(실측 전 수치 창작 금지).

### P0 — 선행 결함수정 (이것 없이는 어떤 A/B 비교도 무효)

- **M01. 가용성 마스킹 + 재측정 기준선(DVFS_remeasure)** — line 112 역채움 제거(mid-series는 전방 na.locf만), 리밸런스 시점별 eligible 집합(12개월 NA-free)으로 모멘텀/breadth/cov 한정, breadth 분모는 `sum(b)/length(eligible) > B/18`(전 자산 가용 시 b>11과 정확 등가 — /17형은 조용한 룰 변경이라 기각), cov complete.obs + ERC tryCatch→inverse-vol fallback, 가격 스냅샷 csv 고정. 원본 로직 재현 런(contaminated)과 diff로 PDBC 보유월 오염 실측. 회계 레이어에서만 상장 전 셀 0 치환(신호 레이어는 NA 보존).
- **M02. EGARCH 타이밍 정렬 + fail-unsafe 수리** — 학습창 `(ep[i]-119):ep[i]`로 당김(PIT 무결 유지), 분위수도 `[1:ep[i]]` 일관화. 적합 실패 시 120일 realized vol fallback(20일 창은 분포 불일치로 기각 — like-for-like 비교 필수) + `fit_status` 컬럼 신설. 제어흐름은 "fit 성공→ugarchforecast / fallback→RV 경로" 명시 분기(스케치 그대로는 크래시 — 검증 시 지적).
- **M03. 비용·측정 계약 정합** — fee 의미("레그당 20bps, 전면 전환 1회 0.4%") 명문화 + 최초 진입비용 보정 + `Return.cumulative` 교체 + **한국 양도세 22%(기본공제 250만, 당해연도 전량 실현 = 과세이연 0) 세후 트랙**(metric_type='estimated') + build_bt_result 브릿지(어댑터 필수: DAILY_NAV_DT/strategy_xts/bm_xts/HOLDINGS_LOG 구성 — 직접 호출은 에러). **critic 추가**: 미국 배당 원천징수 15%(HYG/EMB/TLT 고분배 자산 상시 보유 — 연 수십 bps 체계적 과대계상 가능)를 세후 트랙에 포함할 것.

### P1 — 핵심 강화 (레이어별 ablation arms)

| ID | 레이어 | 내용 | 핵심 근거 | 필수 수정조건(검증 결과) |
|---|---|---|---|---|
| M04 | 신호 | breadth 원전 복원 — offensive 한정 절대모멘텀(≤0) 카운트. B는 원전 비례(4~5) 사전등록 | F-05, 원전 SSRN 3002624 | 원전 G12 breadth는 GLD/TLT/HYG/LQD 포함 — "절대·ex-SHV 17종" arm 추가(4-arm). 원전 수치와 직접 비교는 불성립(가중·top4 ERC·유니버스 상이) — sanity-check 한정 |
| M05 | 배분 | 이진 P_wt → 원전 graded CF=b/B + no-trade 밴드(τ≈0.10, |Δw|>0.05) | DVFS-08(전환 1회 40bps), DAA 보고치, 사내 선례 DVAA.R P_wt=0.6 | graded는 '비용 절감'이 아닌 '익스포저 변경'으로 재라벨 — b 분포 실측 선행, 평균 CF +20%p↑면 단독 채택 금지(M04와 동시 도입 arm 주력). 히스테리시스는 graded와 양립 불가 — 별도 arm 분리. 밴드는 weight row 누락 방식(drift 자연 반영)으로 구현 |
| M06 | 신호 | DAA식 canary — EEM+AGG 13612W (+TIP 단일 arm, HAA 스펙). 4-arm: 내부 breadth / canary 단독 / max-앙상블 / TIP | DAA SSRN 3212862. **EEM·AGG·TIP 전부 2003년 상장 — 2008 구간 유일하게 오염 없는 위기신호(신호-레이어 한정)** | TIP-canary 신호-보유 결합(방어 풀에 TIP 존재) 사전 확정. 결합규칙 max 단일 사전 고정. CF=50% 부분방어 상태의 구현 명세 선행 |
| M07 | 신호·필터 | '진짜 위기' 분기 수리(F-06) — mom_avg≥0이면 강제 Risk-On 대신 VAA 신호 존중 + 판정 모멘텀 offensive 한정. 2차 게이트 교체 arm: ADX/10일 → SPY<SMA200 + HY OAS(FRED BAMLH0A0HYM2, t-1) | F-06, DVFS-10, Gilchrist & Zakrajšek 2012 | **헤더 Rule 2가 이 동작을 설계 의도로 명문화 — 도훈 의도 확인이 hard precondition**. 신규 상호작용(Risk-Off 대상 = Spike 발생 자산 동일 가능) 로깅 의무 |
| M08 | 필터 | EGARCH-120 → 무추정 EWMA(λ=0.94 고정)/RV-비율 + 기준분포를 동일 통계량으로 일치 | DVFS-01/02/04, Poon & Granger 2003 | 3-arm{EGARCH(M02 수리 후)/EWMA/무필터}에서 EGARCH arm에도 기준분포 수리 적용(미적용 시 효과 귀속 불가). EWMA burn-in ~60obs 제외. (a)/(b) 택일 사전등록 |
| M10 | 배분 | ERC cov 63일→252일 + Ledoit-Wolf 수축 (`RiskPortfolios::covEstimation type='lw'`). 대안 arm: inverse-vol | DVFS-09, MRT 2010 | 2×2 분해(윈도우×추정기)로 교락 해소. M01 마스킹 하드 전제. inverse-vol은 '동치'가 아닌 '추정-free 벤치마크'로 재라벨 |
| M11 | 배분·실행 | 방어 레그: 단일 안전자산 100% → BAA식 top-3 of {GLD,TIP,TLT,IEF,SHV} + SHV 절대필터. **레버 B(무수정 즉시)**: SHV 신호 시 실제로는 현금/RP 보유(왕복 레그비용·과세 이벤트 제거) | BAA SSRN 4166845, 2022 실패 모드 | AGG 민감도(1.10→0.83) 인용은 오용이라 제거(offensive canary 증거임). 풀/top-N grid search 금지(BAA 규약 그대로 1회 수입). 레버 B는 신호-보유 매핑 문서화 필수(M15 가짜 슬리피지 방지) |
| M12 | 실행 | **트랜치 분할 집행(production 무수정 즉시 적용)** — 실계좌 2트랜치부터(월말 + 월중), RTL 분산 ≈1/N 축소 | Hoffstein 2019 JII + AllocateSmartly BAA 8-트랜치(표준편차 2/3 감소) | ep를 거래일 평행이동(`ep+k`)으로 구성(weekly endpoints는 모멘텀 정의 변형 — 기각). offset=0 parity 테스트 통과 후 실자본. 트랜치별 별도 기록 hard requirement |
| M13 | 거버넌스 | **형제 변형 공정 트라이얼** — trial_registry.csv(DVFS/DVAA_ETF/Bayesian/VAAA/Debuging 2종 포함 ≥8행), 공통 러너 + 동일 스냅샷·비용·리밸일, 오프셋 {0,5,10,15} RTL 밴드, DSR≥0.5 HARD(n_trials는 하한 라벨) | DVFS-07, measurement-graduation §3, Bailey & LdP 2014 | essence_score()는 bt_result 필수 — standalone `.essence_dsr()` 직접 호출 + DSR 적용 시계열(절대 vs SPY-active) 사전 고정. RTL 밴드는 하한 추정 라벨, 비-GARCH 변형 오프셋 ≥8 확대. **critic: DVAA_DVFS_GARCH_Debuging.R 등재 누락 — 포함할 것** |
| M14 | 거버넌스·필터 | **오버레이 한계기여 검증** — 사다리 ablation{무필터/SMA200-only/EWMA/현행 4중} + walk-forward 파라미터 재선택 + oos_retention v2(anchored 3분할) + 위기 LOCO + holdout 사전등록(`build_holdout_interval()`+`save_holdout_interval()` — register_* 함수는 부존재) | DVFS-06, Cederburg 2020, Zakamulin 2014, Faber 2007 기준선 | 미입증 시 필터 제거 + TIP canary를 최소 대체로. '입증 실패'와 '부재 입증' 구분 보고(검정력 부족 — 위기 2회). WF는 EGARCH fit 사전계산 캐시(~660 fits) 설계 의무. **critic: AX-001 조건부 평가(crisis_alpha + Core 대비 MDD 완화) 프레임 병용 — 전기간 SR 단독 판정 금지** |
| M15 | 실행·거버넌스 | **라이브 모니터링(무수정)** — 기존 signal_history/wts xlsx 소비층 신설: fit 실패율(MNAR 검정), 실제 트리거율 vs 명목, |b−B|≤1 휩쏘 노출 + flip×0.4% 비용, F-06 발동 월 전수(Market_Trend<0 ∧ ADX>20 조건 추가 필수 — 가짜위기 분기와 혼재 방지), 가격 스냅샷 신호-flip 탐지(가격-레벨 diff는 배당 재조정 false alarm — 신호-레벨 규약), 체결 슬리피지 → M03 비용 가정 환류, holdout q05 침범 시 tg_agent_brief() alert | DVFS-02/04/08, F-06/11/13, live_track 선례(STR_1715) | — |

### P2 — 탐색적 (P0·P1 결과 확인 후)

- **M09. 필터 측정대상 교체** — 보유의존 스플라이스 → 안전자산 3종 vol z-score 평균(공통성분) + Mahalanobis turbulence(Kritzman & Li 2010) 보조 트리거(진단 산출부터, 게이트화는 기여 입증 후). 신규 파라미터 ~6개 — IS-only 1회 동결 + LOCO. M08과 결합 권장.
- **M16. 모멘텀 스펙 앙상블** — {현행 (6,6,6,1) / 원전 13612W (12,4,2,1) / 13612U 균등} 3스펙 + rank-ensemble arm. 윈도우 `(ep[i-k]+1):ep[i]` 정정은 전 arm 공통 적용(귀속 교란 방지). 기시도 trial(DVAA_ETF_test.R의 13612W+vol조정) n_trials 포함.

### 상호 배타/의존 관계 요약

```
M01 ──(하드 전제)──> 모든 실험
M02, M03 ──(기준선)──> M13, M14
배타 arms: {M04 절대 breadth ↔ 현행 상대 허들}, {M05 graded ↔ 이진}, {M06 canary ↔ 내부 breadth},
          {M08 EWMA ↔ EGARCH유지 ↔ 무필터(M14)}, {M07-B SMA200+OAS ↔ 현행 ADX/10일}, {M10 LW-252d ↔ 63d ↔ inverse-vol}
즉시 적용(무수정·실험 불요): M12(트랜치), M11-레버B(SHV→현금), M15(모니터링)
심판: 모든 arm은 M13 등재 + DSR + RTL 밴드, 오버레이 존치는 M14가 판정
```

---

## 5. 비평(critic)이 식별한 잔여 갭 — 후속 조사 큐

본 리서치가 다루지 못한 영역(정직 보고):

1. **KRW 기준통화/FX 레이어 전면 부재** — Absolute_Defense의 SHV 100%는 USD 무위험일 뿐 KRW 기준 환노출 100%. "위기 시 원화 약세 → USD 현금이 KRW 기준 자연 헤지"라는 핵심 상호작용(2008/2020), 환헤지 트랙, KRW 평가 성과 트랙 미검토. **후속 조사 1순위.**
2. **미국 배당 원천징수 15%** — M03 세후 트랙에 편입 필요(상기 반영).
3. **t+1 체결 = 운용 기본값** — 민감도가 아니라 base-case 재정의 사안(상기 1-B 반영).
4. **벤치마크 적합성** — 글로벌 멀티에셋을 SPY 단일 BM으로 채점하면 portfolio_alpha_t가 자산군 베타에 지배. 60/40 또는 EW-유니버스 passive 병기 필요.
5. **검정력 사전 추정 부재** — 청정 위기 2회 표본에서 M14가 '판정 불능'으로 끝날 시나리오의 의사결정 규칙(예: 판정 불능 시 단순화 우선 원칙) 사전 합의 필요.
6. **글로벌 n_trials 예산·의존성 DAG 미산출** — 16건의 arm 합산은 수십 개. M13 등재 시 통합표 작성 필요.
7. 미감사 코드 영역: line 190 기본 분위수 0.95(제3의 임계 — SMA NA 시 무음 발동), ADX 미조정 OHLC vs 본체 조정가 혼용, lines 452-459 stale 시각화 블록.

---

## 6. 권장 실행 순서 (도훈 결정 사항 포함)

**즉시 (실험 불요, production 무수정):**
1. M12 트랜치 2분할 집행 + M11-레버B(SHV 신호 시 현금 보유) — 운용 레이어 매핑만.
2. M15 모니터링 스크립트 — 특히 **F-06 발동 월 전수 목록**과 **wts xlsx의 2014-11 이전 PDBC 보유월 확인**(F-01 오염 실재의 즉시 판정).

**도훈 confirm 필요 (리서치 착수 전):**
- (a) F-05 상대 허들·전 자산 top4가 의도된 설계인가, VAA 원전 일탈인가?
- (b) F-06/헤더 Rule 2 "위기 중 로테이션"이 유지할 설계 철학인가?
- (c) 운용 정본 파라미터(B=11 vs 10, EGARCH vs GJR, fallback) 확정.
- (d) production 파일의 주석 오기(lines 194/197)·헤더(FYF, GJR 표기) 수동 정정 여부 — 05_Production read-only이므로 도훈 직접.

**리서치 1차 사이클 (사본):** M01 → M02·M03 → 원본 재현 parity → 오염 실측 보고 (여기서 2008 방어 성과가 크게 바뀌면 전략 서사 재평가).
**2차 사이클:** M04/M05/M06/M07/M08/M10/M11-A arms → M13 프로토콜 심판 → M14 오버레이 존치 판정 → 생존판 holdout 사전등록.
**후속 조사:** KRW/FX 레이어(§5-1), 벤치마크 재정의(§5-4).

---

## 7. 도훈 confirm 반영 — 로드맵 재배선 (2026-06-13 2차, 워크플로우 wf_92c2037d-b47)

도훈 mandate 3건 결정 → 16건 로드맵 재배선 + 적대검증(4 에이전트). interpretation_verdict = **sound(보정 3건 필수)**.

### 7-1. 도훈 결정 → 코드 의미 (line 근거)

| 결정 | 코드 의미 | 영향 |
|---|---|---|
| **허들은 의도** | line 247-249 상대 허들(`b = cum_wm < cum_wm[,cash]`, 안전자산 포함 17열, 금 랠리 만성 Risk-Off 포함) **함수형 동결** | M04(절대모멘텀 원전 복원) 철회 |
| **위기 중 로테이션 X, 월간리밸 확정** | line 273 `ifelse(risky_mom_avg<0, "Absolute_Defense", "Risk-On")`의 **else(강제 Risk-On) 가지 단일 제거** — 헤더 Tactical Rule 2(line 15-17 Inter-Asset Rotation)의 유일한 구현 지점이자 F-06 역설의 본체 | M07 수리 A mandate 확정 |
| **B=11 정본, 디버그 무시** | 메인(B=11/EGARCH/worst-safe) 정본. 디버그 2종 운용 비교 제외 | F-08 해소, M14 B격자 제거 |

### 7-2. 확정 로드맵 델타

- **WITHDRAW**: M04 함수형 복원(offensive 절대모멘텀 b≤0 + 유니버스 분리 + {상대↔절대} 3-arm) — 도훈 결정 1과 정면 배치.
- **STRENGTHEN**: 
  - **M07 수리 A** — line 273 else 가지 외과적 제거(아래 코드). 선택적 제안 → mandate 확정. hard precondition('도훈 의도 확인')이 결정 2로 충족.
  - **M13** — 디버그 2종은 `operational_candidate=FALSE`(운용 제외)이나 `selection_surface=TRUE`(과거 sweep 흔적 잔존) 2층 라벨. **결정 3을 n_trials 축소 근거로 인용 금지**(measurement-graduation §3 흔적부정=AX-002 회피). selection_type='sweep' 유지(chain 미승격 — 자격요건 ①진단기록 ②IS-only ③holdout 증빙 부재).
- **REPOSITION**: 
  - M07 수리 B(2차 게이트 SMA200+HY OAS 교체) — 철회 아님, 게이트가 Absolute_Defense 발동조건으로 존치되므로 실측 ablation arm으로 강등.
  - M05 graded CF — 유지하되 금 랠리 b 포화구간은 CF=1로 이진과 동일(의도 비왜곡 확인). 'M04와 동시도입' 조항은 M04 철회로 무효 → 동결 상대 허들 b 위 단독 측정.
  - M06 canary — 'canary 단독 대체' arm 철회(동결 내부 breadth 치환=결정 1 충돌) → {내부 breadth / max-앙상블 보강 / TIP 보조} 3-arm. canary는 '대체'가 아닌 '병렬 보조'로 재라벨(2008 청정 위기신호 가치 유지).
  - M14 — B격자 {9,10,11,12} 제거(B 외 분위수·ADX·lookback·window·top-N만 walk-forward 재선택). arm3 '현행 4중'을 '로테이션 제거된 3-출력 필터'로 재정의. **'오버레이 존치 확정 시' 조건부**(아래 confirm 1에 종속).
- **UNCHANGED**: M01/M02/M03(P0 — 결정 3건과 직교, 모든 b-의존 arm의 하드 전제로 잔존 — 결정 1이 면죄하지 않음), M11(방어 레그 — Absolute_Defense 존치로 SHV 100% 경로 살아있음), M16(모멘텀 가중 다수결은 line 175이지 b 정의가 아니라 breadth 동결과 직교).

### 7-2b. 도훈 2차 결정 (2026-06-13, AskUserQuestion 해소)

- **오버레이 범위 = 로테이션만 제거 (오버레이 존치)** → EGARCH Spike 감지·Absolute_Defense(SHV 100% 방어) 존치. 오버레이 한계기여는 M14가 실측 판정. M14 reposition의 '오버레이 존치 조건부'가 **충족**으로 확정 — M14 사다리 ablation 유효.
- **M07 else 방어강도 = 안A (VAA P_wt 존중)** → '진짜 위기'에서 risky_mom_avg≥0이면 표준 VAA 결정(P_wt 기반 Risk-Off/On). 아래 7-3 코드 안A 확정.
- **파생 hard precondition**: 안A는 `risky_mom_avg`(line 271)를 분기 입력으로 **유지**하므로(risky_mom_avg<0 → Absolute_Defense), F-01 가짜0 자산이 이 평균을 오염시킴 → **M01 데이터 마스킹이 이 분기 정확성에도 선행조건**. (안B였다면 risky_mom_avg를 안 써서 무관했을 사안.) risky_mom_avg를 offensive 13종으로 좁히는 건은 별도 ablation arm으로 두되, 1차 디폴트는 현행 16종 + M01 가짜0 제거.

### 7-3. M07 수리 A 코드 — 안A 확정 (04_Research 사본 — 05_Production 무수정)

```r
# 변경 전 (line 268-273)
if (is_trend_negative && is_trend_strong) {
  risky_mom_avg <- mean(as.numeric(cum_wm[, setdiff(symbols_DVFS, cash_asset)]), na.rm = TRUE)
  final_decision <- ifelse(risky_mom_avg < 0, "Absolute_Defense", "Risk-On")  # ★ else=로테이션
}
# 변경 후 (안A — VAA 신호 존중)
if (is_trend_negative && is_trend_strong) {
  risky_mom_avg <- mean(as.numeric(cum_wm[, setdiff(symbols_DVFS, cash_asset)]), na.rm = TRUE)
  final_decision <- ifelse(risky_mom_avg < 0, "Absolute_Defense",
                           ifelse(P_wt == 1, "Risk-Off", "Risk-On"))  # 강제 Risk-On 제거
}
```
순효과: final_decision 도메인 {Risk-On, Risk-Off, Absolute_Defense} 3값 유지(line 304 match 무변). 제거되는 건 'Spike∧추세확인∧mom≥0 → 위험자산 top4 100% 회전' 단일 상태 전이뿐.

### 7-4. 코드 사실 정정 (검증이 잡은 세 재평가 공통 오류)

**line 248 `b <- cum_wm < cum_wm[,cash]`에서 구조적 자기제외(x<x=FALSE)되는 자산은 SHV가 아니라 line 247의 best-safe 안전자산(GLD/TIP/TLT 중 최고 모멘텀, 변수 `cash`)이다.** SHV(`cash_asset`)는 모멘텀≈무위험금리라 거의 항상 `cum_wm[,cash]` 미만 → b에 거의 상수 +1로 **정상 산입**(자기제외 아님). 직전 보고서/제안의 M04' 산술위생 스케치(`setdiff(colnames, cash_asset)`=SHV 제외)와 'B 재캘리 17→16' 서술은 이 구조와 비일관 → **M04' 위생 대상·B 재캘리 모집단은 도훈 confirm 전 코드 확정 금지**.

### 7-5. 도훈 confirm 현황

1. **[해소 ✓]** EGARCH 오버레이 전체 존치 여부 → **로테이션만 제거, 오버레이 존치** 확정(7-2b).
2. **[해소 ✓]** M07 else 방어강도 → **안A(VAA P_wt 존중)** 확정(7-2b).
3. M04' 산술위생 대상·B 재캘리 모집단(7-4) — '의도 변경 없음, 산술 정합만' 라벨로 confirm 후 코드. **[대기]**
4. M13 디버그 trial 적격 — selection_surface 잔존(보수적)이 디폴트. 도훈 개발노트/커밋이 chain 자격요건 충족 시 chain 승격·DSR HARD→advisory 가능(도훈만 판정).
5. line 175 모멘텀 가중 (6,6,6,1)/19 동결 여부 — 결정 3은 B·EGARCH·fallback만 정본 확정, 가중치 미포함. M16 앙상블 자유도(디폴트 '열림').
6. 벤치마크 적합성 — SPY 단일 BM은 portfolio_alpha_t가 자산군 베타 지배. M13 DSR/PORT_t 적용 active series의 BM(SPY vs 60/40 vs EW-passive)이 graduation HARD(PORT_t 2.95) 판정 좌우 — 자본 게이트 전 확정 필요.
7. t+1 체결 base-case — 한국 거주자에게 물리적 기본값. 모든 재검증 arm 공통 전제. **디폴트 t+1로 진행 예정**(반대 시 회신).

### 7-6. 잔존 라이브 리스크 (결정 2가 해소하지 않음)

DVFS-02 fail-unsafe(GARCH 적합 실패 시 무조건 'Stable', line 203/218-233)는 오버레이 존치 시 잔존 — 로테이션 폐기와 무관. M02 수리 + M15 fit_status 추적 필요.

---

## 부록: 산출물 위치

- 워크플로우 전체 결과(JSON, 299KB): `C:\Users\99922\AppData\Local\Temp\claude\...\tasks\w1ly8h9ge.output`
- 추출본(감사 42 findings + 문헌 30 items + 제안 16 + 비평): `.cache/dvaa_wf_extract.md`
- 패밀리 지도: VAA.R/DVAA.R(엑셀 인덱스, 필터 없음/부분방어 0.6) → DVAA_ETF.R(직계 부모) → **DVFS(EGARCH+ADX)** / VAAA.R(자기참조 SVL+안전바스켓) / DVAA_Bayesian_ETF.R(PCA+SVL 듀얼트리거) / DVAA_ETF_test.R(13612W+vol조정+DBC). 기시도 영역: PCA 리스크지수·Bayesian SVL·불확실성 듀얼트리거·안전바스켓·SMA200 crash-gate·위험조정 모멘텀·부분방어. **미시도: breadth 원전 복원·상장일 마스킹·EWMA 단순화·canary·트랜칭·거버넌스 일체** — 본 보고서 제안과 정합.
