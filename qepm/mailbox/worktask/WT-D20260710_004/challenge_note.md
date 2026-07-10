# Challenge Note — WT-D20260710_004 Stage A (TIMESTRUCT, 무선택 진단)

Self-Adversarial Challenge (v8.2, Opus 4.8 native adversarial). finalize 직전 약점 자가제기.
Spec sha256 `bd7ecd9362d6c8fccca869124118d85b85b3405c8c3b7a186ebf51eaa04d38a1` 동결 후 0-trial 측정. 어떤 config도 선택 안 함.

## 자기 비평 (devil's advocate) — 제기 concern + 처리

### C1 [PARTIAL] value-innovation age 는 내생 proxy
`|Δz|>τ` refresh 정의는 "값이 크게 움직였다"이지 "새 정보가 도착했다"가 아니다. 특히 fundamental(V02_EP)의 진짜 fresh는 earnings Usable_Date 인데 proxy 가 오분류하면 실재 이질성을 null 쪽으로 희석할 수 있다.
- **처리**: 3개 **독립** age 조작화가 전부 null — ① value-innovation(τ=0.5 **및** 1.0), ② 외생 DART 이벤트-나이(공시 rcept_dt = 진짜 timestamp), ③ A2 보유-tenure(모호성 없음). 세 축 수렴 null 은 단일 proxy 잡음에 robust. 잔여 gap: factor 의 진짜 earnings-Usable_Date age 를 직접 쓰진 않음(치명적 아님).

### C2 [ACCEPT] A2 aggregate contrib 유의성은 book-구성 아티팩트
A2 aggregate `contrib_diff` nw_t (capw 2.61 / ew 3.40)를 "freshness 엣지"로 오독할 수 있다.
- **처리**: 이는 count 아티팩트다 — book 의 77.7%가 fresh 종목(avg 보유나이 1.88m)이라 fresh 가 총 기여 크게 나올 뿐. **binding 검정 = per-name diff (−0.323, null)**. 보고서·JSON analyst_notes 에 명시 경고. aggregate 수치를 freshness 근거로 인용 금지.

### C3 [PARTIAL] DART 음(−) active = cap-w/size confound 가능
buyback 종목이 K200∪KQ150 에서 대형주 skew → 2015+ mega 레짐에서 cap-w 벤치 대비 구조적 음 active 일 수 있음(기확립 사실). "buyback = 나쁜 신호"로 단정 위험.
- **처리**: 방향 단정 안 함. 결론 = "**favorable fresh-buyback 엣지 미검출**; 방향 mildly 음·insignificant; size-matched control 전엔 hard 방향 기각 유보". census 는 게이트 열지만 방향 증거는 unfavorable/inconclusive.

### C4 [ACCEPT] A3 MEGA/MID age-cell n=1 → KA3 판정 불신
MEGA/MID 는 월 10/20 종목뿐 → 단일 age bucket 에 ≥8 종목 드묾 → cell n_months=1 다수. `KA3_fresh_ic_by_tier` MEGA=0.2727 은 1-month noise.
- **처리**: KA3 를 **under-powered/inconclusive** 로 격하(clean FALSE 아님). robust 판독은 OTHER pool(n=256): 0-1m IC 0.047 ≈ 4m+ 0.0445 → age 이질성 없음. 기확립 cap-tier 국소화(알파 OTHER>30) 불변.

### C5-PROCESS [ACCEPT] census 856 → 81 (self-adversarial 이 버그 적발)
A5(b) census 를 처음 856 으로 산출. 독립 적대 cross-check(explicit loop) 가 81 산출 → 불일치.
- **처리**: `pm[, ev_age_m := {...ev[Ticker==Ticker[i]]...}, by=Ticker]` 의 data.table by-group scoping 버그 발견 — `Ticker[i]` 가 pm 그룹이 아닌 **ev 컬럼**으로 resolve. rolling-join(carried `matched_ev` 컬럼) 으로 수정 후 재검증 == 81. **A1-DART 도 동반 수정**(허위 −2.213 → 0.261, 무의미). factor A1/A2/A3/A4/integrity 는 ev_age_m 미사용 → 영향 없음. 타임스탬프 무결성 검증이 census 무결성까지 잡아낸 사례.

## Self-rationalization auto-detection
"미미/관행적/보수적이면 OK/대부분 동일" 로 null 을 무마하지 않음. 모든 null 은 NW-t 로 측정 + 다중 조작화 수렴. 통과.

## AX-008 Verification Triangulation (3-source 중 self-adversarial)
- integrity spot-check: FRESH load_month_factors vs panel.rds Spearman cor = **1.0** 4/4 date → 소급/개정 없음.
- lag1 stress: 전 계열 실행 완료 — fresh IC 하락은 예상(t−1 신호로 t+1 예측 = 1개월 손실), fresh 우위 미발생.
- 독립 재현: A5 census 81 을 2개 코드 경로(rolling-join / explicit-loop)로 일치 확인.

## Escalation
trigger 미발화(HIGH-sev≥5 없음 / axiom hard FAIL≥3 없음 / PIT C1 위반 없음). Q-Lead escalate 불요. 정상 보고.

## 결론 (무선택)
가설 핵심(전이 벽의 **샘플링-아티팩트 성분**) = Stage A 에서 **기각**. B2(staggered fresh-cohort standalone) = KA1(이질성 없음) + KA4(경제성 미달) 이중 봉쇄. B1 PROMOTE = census 형식상 통과(81≥60, 단 33개사·thin)이나 A1-DART 방향 미지지 → 저 EV. B1 VETO = 데이터 미가용(도훈 회부 (i)). 어떤 config 도 선택하지 않음(0 trial).
