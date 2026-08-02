# Challenge Note — WT-D20260802_022 (Self-Adversarial Challenge, v8.2)

**작성**: alpha-research agent, finalize 직전 자체 적대검증 (Charter §8 No Silent Override)
**판정 요약**: 실코드 full-path ΔIR **−0.1489** (paired NW t −1.976, n=256) → 사전등록 기준 **WITHDRAW (실배치 상신 철회)**. 진단 7 arm 전부 음수.

---

## C1. "부호 반전이 배제-문턱 프레임 차이(스크린 후보 풀 vs Iter31 후보 풀) 탓 아닌가?" → **REBUTTAL**

- **학술**: Bali-Cakici-Whitelaw 2011 JFE — MAX 프리미엄은 소형·비유동 구간에 집중. 문턱 프레임이 아니라 *어느 종목에 무게가 실리는가*가 효과 크기를 지배한다는 문헌 구조와 정합.
- **선행 실측 (L-code 계보)**: WT-D20260802_014/016 (hypothesis_index 등재) — 동일 규칙·동일 X=10%.
- **정량 3축**:
  1. **decomp 통제 실측**: *내 문턱 프레임 그대로*(동일 excl map·동일 하네스) 가중 규칙만 cap_norm(Size)으로 바꾸면 ΔIR **+0.1579** — WT-014의 +0.1692를 재현. 문턱 프레임은 부호를 바꾸지 못함. 부호 반전 축 = **가중 규칙** (`wt022_decomp_table.csv`).
  2. **기전 직접 측정**: 배제된 base top-20 종목의 익월 수익 3.28%/월 vs 대체 종목 2.12%/월 — 스프레드 +1.16%/월 (NW t 1.54, n=248). rank-tilt에서 배제 대상이 최고 가중 종목이라 평균 손실 직결.
  3. **tier 귀속**: Δ기여 OTHER −4.46%/yr vs MEGA+MID +1.0%/yr — cap_norm에서는 배제 대상(소형)이 사실상 무게 0이라 평균 손실 없이 분모(변동성)만 줄어 IR 상승 (capnorm ΔIR +0.158인데 paired t −0.25 = 분모 효과).

## C2. "GATE B의 m4 6개월 불일치·2-3 ret 편차(max 0.008)는 측정 오염 아닌가?" → **PARTIAL (문서화 수용, spec 변경 없음)**

- 인정: 저장 기록(07-02 vintage)과 6개월 불일치 실재 (2008-01/03/04·2009-06·2012-01/02).
- 보완: 전 건이 `WT-D20260430_001_m4_extended.csv`의 08-02 재생성 귀속(입력 vintage) — 배선 무결은 β 269/269 일치 + GATE A 5.13e-16으로 입증. **m4는 양팔 동일 스칼라 곱**이라 paired Δ의 부호·판정에 영향 없음. 사전등록 gate B 분류("입력 vintage 갱신 → 측정 유효 지속") 이행.

## C3. "배제-대체 스프레드 t 1.54는 유의 미달 — '승자 컷' 단정 과도 아닌가?" → **PARTIAL (표현 한정 수용)**

- 인정: 종목 스프레드 단독으로는 유의 미달 → 산출물에 "승자 표지(유의 미달, FM 확정 대기)"로 기재, np1(FM interaction 검정)을 확정 절차로 사전 지정.
- 판정 자체는 종목 스프레드가 아니라 **포트 수준 paired t −1.976**과 사전 고정 ΔIR 기준에 근거 — 기전 서술과 판정 근거를 분리했다.

## C4. "capnorm 재현이 +0.158인데 paired t는 −0.25 — WT-014의 +0.169(t +1.565)와 질이 다르다. 재현이라 부를 수 있나?" → **PARTIAL**

- 인정: ΔIR 크기·부호는 재현되나 평균 효과는 재현 안 됨(내 재현은 분모 효과 우세). 잔여 축 = 점수 소스(cleanT1 d0-매핑 vs production 패널 sig-매핑)·수익 윈도우(d0월말 vs 첫거래일). 이 잔여 축은 미분해 — 한계로 명시.
- 단 본 라운드의 질문("실코드에서 필터가 도움되나")에는 영향 없음: 실코드 config에서 음수는 어느 분해 축에서도 흔들리지 않음 (tilt 계열 전 config·EW까지 음수).

## C5. PIT 방어 상태 — **방어 완료**

- max5 = WT-010 동결 패널(재계산 없음), 창 종점 d0 < 첫 매수일 구조 보장, `assert_overlay_pit` 256/256 PASS.
- **위반 주입 테스트**: 컷오프를 홀딩월 말로 주입 → stop() 발화 확인 (가드 생존, GATE C).
- lag1 스트레스: −0.210 (더 나쁨) — 동월 누출로 편익이 생긴 구조 아님 (편익 자체가 없음).
- β_R05 expanding past-only q20 (C1) — production forward 코드의 full-sample q20은 미사용 (backtest 재현은 run_layer5 expanding 경로).

## C6. 자기합리화 스캔 → **해당 없음**

answer-principles 회피표현 목록(pit.md 금지 표현 조항의 5개 관용구)을 본 라운드 산출물 전체에서 검사 — 사용 0건. 근사 프레임과의 괴리는 축소·완곡 없이 부호 반전(+0.277 IR 낙관 편의)으로 정면 보고.

---

## AX-008 Triangulation

- Self-Adversarial(본 문서) = 1 source 이행. forge 계약 빌드는 비대상(Δ 판정 라운드, 신규 전략 아님 — graduation 비대상), architect 비대상. 판정은 사전등록 기준의 기계 적용.

## Escalation 체크

- HIGH severity concern: 0건 / AX axiom hard FAIL: 0건 / PIT C1(lockbox·lookahead) 위반: 0건 → Q-Lead escalate 불요.

## 계통 교훈 (이 라운드의 본체)

**ΔIR은 base의 가중 규칙에 조건부인 국소량이다.** size-weighted 스크린에서 검증된 필터는 rank-weighted book에 이식되지 않는다 — "어느 base 위에서 잰 개선인가"를 판정문에 항상 병기할 것. WT-016의 parity STOP(cor 0.668)이 이 계층 차이의 조기 경보였고, §7b(production 코드 = incumbent base 권위)가 오배치를 차단했다.
