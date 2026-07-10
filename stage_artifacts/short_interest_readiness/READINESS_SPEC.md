# 공매도잔고(short interest) QEPM Readiness Spec — FQ-003

**작성**: 2026-07-10 (Q-Lead) · **상태**: 데이터 랜딩 대기 (도훈 export) · **SOT**: `06_Registry/alpha_frontier_queue.json` FQ-003

## 0. 왜 이 lane (가설·envelope)
KR 공매도제약(2020-03~2021-05 부분·2023-11~2025 전면·평시 기관/외국인 한정)으로 고-공매도-수요 종목 과대평가가 차익거래로 미해소(Miller 1977 divergence-of-opinion + short constraint). → **long-only가 고-공매도잔고 종목을 회피/저비중하는 exclusion 신호로 하베스트**. 무제약 시장은 short-side라 long-only 미하베스트인데, KR 제약이 이를 long-only-먹을수있게 만듦. hypothesis_index **virgin(0 매치)**. envelope-안(타 투자자 short를 *신호*로 소비, 우리 포트는 long-only 유지 — constraint_firewall 무관).

## 1. 데이터 취득 (도훈 작업) — 확정 경로
- ❌ KRX 공식 OPEN API(구 data-dbg.krx.co.kr /srt/* · 신 openapi.krx.co.kr) 둘 다 공매도 서비스 부재(2026-07-10 재확인).
- ❌ KRX MDC(MDCSTAT300)·공매도종합포털 = 로그인 게이트(자율 불가).
- ✅ **권장 = QuantiWise export** (도훈 이미 사용·기존 인제스트 파이프). 1회 로그인으로 FQ-005 crowding(신용/대차) 동시 취득.
- ✅ 대안 = 공매도종합포털(short.krx.co.kr) bulk 다운로드.

### 필요 export 규격 (이대로 뽑아주시면 바로 측정)
| 항목 | 값 |
|---|---|
| 유니버스 | KOSPI200 ∪ KOSDAQ150 (넓게 전종목이어도 무방 — 인제스트서 필터) |
| 필드 | **공매도 잔고수량 + 공매도 잔고비중(잔고/상장주식수)** 필수. 가능하면 대차잔고·신용융자잔고 병행(FQ-005) |
| 기간 | 2016-06 ~ 현재 (공매도잔고공시 규정 시작점) |
| 주기 | **일별(daily) 권장**, monthly도 가능 |
| 포맷 | CSV/parquet, 컬럼 `Date, Ticker, ShortBalanceQty, ShortBalanceRatio[, LendingBalance, CreditBalance]` (컬럼명 달라도 됨 — 매핑함) |
| 시점 | 공시 T+2 보고 → **잔고 as-of 날짜와 공시(가용) 날짜 구분 필수** (PIT C4/C11) |

## 2. PIT 규칙 (랜딩 시 적용)
- **C11 데이터 시간축**: 공매도잔고는 보고의무 T+2. 신호 사용 시점 = 잔고 as-of가 아니라 **공시 가용일**. 홀딩월 시작 전 가용분만(C5 오버레이 타이밍 정합 — overlay_pit_guard 경유).
- **C4/C14**: 잔고 as-of ≤ sig_date, Usable_Date ≤ sig_date.
- **C6**: 상장폐지·거래정지 종목 survivorship 처리.
- 신호 방향 검증: score→forward-ret IC 부호(고잔고=저수익 예상이면 exclusion 방향 정상) — `bear_date_audit.R` 등가 forward-label 검증 PASS 의무.

## 3. 온보딩 (적재=선언, reference-factor-onboarding-interface)
데이터 랜딩 시: `add_factor(name="SI01_Short_Balance_Ratio", ...)` 선언 → builder 자동계산 → scoped backfill. 코어 수정 불필요. 신호 변형 후보:
- SI01 잔고비중 level (고잔고 exclusion)
- SI02 잔고비중 Δ (급증 신호)
- SI03 잔고비중 z-score (횡단 정규화)
- (crowding) 신용/대차 병행 시 composite

## 4. 측정 계획 (랜딩 시 QEPM discovery WT)
1. canonical_screen_bt **dual_basis**(cap-w + EW-유니버스) — SI를 exclusion(고잔고 저비중/제외)으로 소비한 top-25 long-only. cap-w PORT_t = 자본 권위.
2. cap-tier 진단(diag_cap_tier) — SI 신호가 어느 tier에 국소하나(오늘 확립: 배포권 대형주 엣지 ~t0.5).
3. book-marginal: 현 book(STR_1715 score_eff)과 직교성 + ΔIR.
4. 게이트: HARD 3종(PORT_t 2.95·oos 0.7·calmar 0.64). placebo·lag1·holdout.
5. Self-Adversarial: short-constraint 레짐 편중(2023-25 전면금지 구간이 신호를 과대평가하나) 자가점검.

## 5. 리스크·caveat (사전 기록)
- 데이터 depth 2016-06~ = 10년, post-2017 감쇠 구간과 겹침 → EW-대비 진단 병기 필수.
- 공매도 전면금지 구간(2023-11~2025)엔 신규 공매도잔고 형성 제약 → 신호 stale 가능. 구간별 분리 측정.
- short-side 견인 신호를 long-only exclusion으로 전환하는 것이라 IC→PORT_t 전이 벽 적용 대상 — 통과 미보장(정직).
