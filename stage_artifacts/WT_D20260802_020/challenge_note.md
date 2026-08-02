# Challenge Note — WT-D20260802_020 (Self-Adversarial, v8.2)

**작성 시점**: finalize 직전 (alpha_package 발행 전). Charter §8 No Silent Override.
**대상 산출물**: MAX5 종목-레벨 crash 예측력 실측 (FM 사전등록 단일 primary, n_trials=1)

---

## C1 [HIGH] — "동일창 통제에서 증분 소멸 — 헤드라인 t 13.1은 창 미스매치의 산물 아닌가"

**우려**: primary FM t +13.15는 252d 창 위험 축(D01/D02/D03/D45 전부 252d lookback, compute_defense.R 실측 확인) 대비 증분이다. 동일 63d 창 vol63+dsd63 통제(사전등록 병기 진단)에서는 b +0.0086, t +0.95로 소멸. "MAX5가 crash를 예측한다"는 서사가 "짧은 창 변동성이 crash를 예측한다"의 재포장일 수 있다.

**분류: ACCEPT (해석 제약 — spec 변경 아님)**. 사전등록 primary의 질문 자체가 "기존 위험 축(mandate 4축) 통제 후 증분"이었고 그 답은 t 13.1로 실재한다. 그러나 증분의 *정체*는 MAX5 고유의 lottery 정보가 아니라 **63d 최근창 꼬리-변동성 정보**임이 동일창 진단으로 확정됐다. 모든 산출물(package·validation·제안서·텔레그램)의 헤드라인을 "MAX5 고유 예측력"이 아닌 "현행 252d 위험 축에 부재한 단기창 정보"로 고정한다. risk 제안서에 "max5 불요 — vol63/dsd63이 더 싼 등가물" 명시.

## C2 [HIGH] — "crash 발생률 예측 ≠ 평균수익 예측 — alpha_vector 오소비 위험"

**우려**: top-decile MAX5의 익월 수익 스프레드는 0과 구분 불가(−0.05%/월, NW t −0.12). 이 신호를 alpha_vector(기대 초과수익)로 소비하면 계약 위반적 오용 — 랭킹 소비는 WT-010에서 이미 canonical PORT_t −1.616 전이 실패 실측.

**분류: ACCEPT**. alpha_vector에 "risk-axis indicator — 평균수익 기대값 아님(스프레드 t −0.12), 랭킹/선별 소비 금지" 명시 라벨 + confidence 상한 0.6 + challenge_flags 등재. 검증된 소비면은 ①crash 발생률(위험모델 진단) ②포트 노출 tripwire(monitoring)뿐.

## C3 [MEDIUM] — "CRISIS 셀 n=13, t 2.33 — 저검정력 셀로 긴장 해소를 선언해도 되는가"

**우려**: 사전등록 긴장(p2)의 해소가 CRISIS 셀(n=13월)의 b_max5 t 2.33에 기대고 있다.

**분류: PARTIAL**. 셀 단독으로는 약하다 — 그러나 해소 논거는 CRISIS 셀 단독이 아니라 구조 전체다: ①4국면 전부 b_max5 양수(t 2.33~13.44, 방향 일관) ②양측 꼬리 분해가 국면별로 정합(CAUTION boom_lift +7.4pp t 4.17, ret_spread +1.76%/월 t +2.08 — 배제가 스트레스 국면에서 손해인 이유를 발생률-평균 분리로 설명) ③WT-014의 CRISIS 역효과(t −1.78)와 본 라운드 CRISIS 발생률 양수(t +3.89)가 동시에 성립함을 같은 데이터에서 확인. 셀 크기는 모든 표에 병기. 국면 합산 재구획은 사후 선택이라 미실행.

## C4 [MEDIUM] — "'위험 축에 없는 정보' 주장 과대 — DB에 이미 단기창 vol 팩터 존재"

**우려**: factor DB에는 D34_RealVol_21d·D42_EWMA_Vol 등 단기창 변동성 팩터가 이미 등재되어 있다(본 라운드 통제 미포함 — mandate 지정 4축만 통제). "위험모델에 없는 정보"가 아니라 "이번 통제 집합에 없는 정보"일 수 있다.

**분류: PARTIAL**. 통제 집합은 request가 지정한 축(변동성 D03/D01·하방편차 D45·베타 D02) 그대로이며 사전등록대로 수행 — 판정 유효. 그러나 일반화 서술은 절제한다: "252d 표준 위험 축 대비 증분"으로 한정하고, DB-native 단기 vol 통제 재시험을 next_probe 1로 등재. 제안서에도 "신규 팩터 추가 전에 기존 D34/D42 배선 검토가 선행"으로 명시.

## C5 [MEDIUM] — "승계 패널 결함 2건이 본 측정을 오염시키지 않았나"

**우려**: 측정 중 발견한 결함 — (a) screen_inputs bench 최종 라벨월(d0=2026-06-30)이 패널 빌드일(07-14) 절단 부분월(−0.2001 vs 전월 정본 −0.2363), (b) bench가 정본 일간 BM_Ret 복리와 35개월에서 1%p 초과 괴리(worst 2026-03-31, 4.49pp — 벤치 2소스 계보).

**분류: REBUTTAL (본 측정 비오염) + 플래그 보고**. 근거 3축(정량): ①primary 라벨은 벤치 무관여 종목 횡단면이고, 라벨 방향은 독립 일간 재계산과 cor 전체 1.0000/월중앙 1.0000/월최악 1.0000 (n_pairs 79,719) ②위반 주입(동월 라벨)시 검증기 cor 0.0052로 FAIL 발화 — 검사 실효 실증 ③표본은 d0 ≤ 2026-03-31로 부분월(2026-06-30) 비포함, 포트 진단(부수)의 worst월은 tail 미분류(FALSE) 확인. 방법론 준거: Fama-MacBeth(1973) 횡단면 회귀는 벤치마크 시계열 비소비. 계보: [[project-benchmark-two-source-divergence-20260802]] + [[reference-benchmark-iks200-bug-fix]] — 기지 사건 계보의 미수리 표면으로 플래그 전달(동결 승계 자산의 재빌드는 WT-014 anchor parity 계약과 충돌 — 소유 라운드/인프라 큐 소관, 침묵 수리 안 함).

## C6 [LOW] — "winsor 3sd가 최극단 복권형 신호를 깎아 예측력을 과소/과대 왜곡"

**분류: PARTIAL(보수 방향 실증)**. 십분위 발생률이 3.9%→21.6%로 단조 — 신호 정보 소실 없음. winsor는 z 안정화 목적이고 top-decile 지정은 분위 기반이라 극단값 절단의 영향이 구조적으로 제한됨.

## C7 [LOW] — "생존편향 — 상폐 직전 종목의 라벨 결측"

**분류: ACCEPT(한계 병기)**. 라벨 결측 0.02% 정량 기록. 방향은 crash 탐지 하향(실제 예측력을 낮춰 보이게 하는 쪽) — 결론(양성)에 불리한 방향의 편의로 결론을 뒤집지 않음.

---

## 합리화 자기검증

answer-principles 회피표현 조항의 금지 표현 목록 전체를 본 노트·validation·package 본문에서 스캔 — 비사용 확인(목록 자체의 재인용도 하지 않는다). C5-REBUTTAL은 학술 준거(Fama-MacBeth 1973) + 계보 참조 + 정량 3축 요건 충족. HIGH 2건은 모두 ACCEPT(산출물 서사·라벨 수정 반영)로 처리 — escalate 요건(HIGH ≥5 / AX hard FAIL ≥3 / PIT C1 위반) 비해당.
