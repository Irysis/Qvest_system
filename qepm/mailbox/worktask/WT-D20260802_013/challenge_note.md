# Challenge Note — WT-D20260802_013 (Self-Adversarial, v8.2)

**작성**: alpha-research, finalize 직전 (2026-08-02). Charter §8 No Silent Override.
**실측 요약**: primary paired t **+1.717** (< 2.0 사전등록 문턱) / placebo 5시드 t = {+2.06, +2.80, +2.49, +1.87, +2.53} (mean 2.348, sd 0.378) / vol-적재 cor(PATHQ, D03z) = **-0.060** (t -2.70) / RESID vs PATHQ paired t = -0.015 (mean d -0.018%/yr, self-cor 0.974) / 부기간 +3.20 / -0.33 / +0.27 / F2 재검 t +1.92.

## C1 — "사전등록 label('vol-tilt 아티팩트 확정')과 실측 기전이 불일치한데, 사후 재해석 아닌가" [PARTIAL]

- **의사결정은 사전등록 그대로 집행**: paired t +1.717 < 2.0 → **교체 근거 미완성, 교체안 상정하지 않음**. 문턱·판정 규칙 변경 0.
- 단 label 문구 "vol-tilt 아티팩트 확정"의 *기전 귀속*은 사전등록에 포함된 통제(vol_loading_quantification·orthogonality_check·placebo)가 직접 반증:
  - PATHQ의 D03z 적재 = Spearman **-0.060** (부호가 저변동 반대 — 저변동 tilt 자체가 없음)
  - 잔차화가 팩터를 사실상 못 바꿈 (self-cor 0.974, RESID vs PATHQ paired t -0.015)
  - RESID standalone PORT_t +2.14 ≥ PATHQ +2.05 (성과가 "죽지" 않음)
- 이것은 성과 재해석이 아니라 **사전등록된 통제의 판정 결과**다. 문턱 판정(교체 불가)과 기전 귀속(vol 아님 → 취약통계+pre2015 편중)을 분리 보고한다. 합리화 자기검증: "미미/관행" 어휘 불사용 — 전 수치 명기.

## C2 — "원판 +2.03 자체가 취약 통계였다는 placebo 증거를 정면 인정하라" [ACCEPT]

- placebo(노이즈 잔차화 = PATHQ의 미소 섭동) paired t가 **1.87~2.80 (sd 0.378)** 산포 — top-25 멤버십의 사소한 jitter만으로 판정 문턱(2.0)을 넘나든다.
- 따라서 WT-009의 +2.028은 "문턱 충족"이 아니라 **문턱 근방의 단일 draw**였다고 보는 것이 정확. RESID +1.717은 placebo 범위 하단 밖(min 1.866)이므로 D03-상관 성분의 소폭 기여(placebo mean 대비 -0.63t)는 실재하나, 주 결론은 "교체 판정을 지지할 강건성이 원판에 없었다".
- **처리**: 교체안 반대 근거로 채택. next_probe에 soft-membership/멤버십-부트스트랩 paired 분포 프레임 등재.

## C3 — "pre-2015 편중이 잔차화 후에도 잔존 — 개선분은 역사 수익이다" [ACCEPT]

- RESID 부기간: **+3.20 / -0.33 / +0.27** (post-2017 +0.18) — WT-009 원판(+2.84/-0.85/+0.96)과 동일 패턴. placebo 5시드 전부 동형(+2.55~+3.44 / 음수 / +0.86~+1.47).
- 잔차화와 무관한 구조적 특성 = **decay-pattern**. 2015년 이후 paired 개선은 통계적으로 0과 구분 불가. 교체했더라도 현대 국면 기여는 근거 없음 — 교체 반대의 독립 제2 근거.

## C4 — "F2 재검 +1.92를 '미지지'로 단정하는 것도, '지지'로 파는 것도 과도" [PARTIAL]

- 원판 t +1.05 → 잔차판 +1.92로 개선 (RESID top-25의 jump-기여 0.313 vs base 0.336). 문턱(2.0) 미달이므로 SUPPORTED 선언 불가하나, "경로-질 차별화 완전 부재" 단정도 실측과 안 맞음.
- **처리**: borderline 정직 기록. jump-share를 명시 팩터로 직접 설계하는 mechanism-direct probe를 next_probe로 등재 (PATHQ의 암묵 전달 대신).

## C5 — "회전 증분" [documented]

- RESID 793%/yr (base 722 / PATHQ 789) — 상한 11.0x(1100%) 이내이나 base 대비 +71%p. 교체 반대 결론으로 소멸되는 이슈이나 기록 의무 이행.

## C6 — "lag1 감쇠가 누출 지문인가" [REBUTTAL]

- RESID +2.14 → lag1 +1.70 (-21%). 근거: ① WT-009 실측에서 base M01도 lag1 -46% 감쇠 (모멘텀 계열 공통 신호 감쇠 — 학술: Jegadeesh-Titman 1993의 신호 신선도 의존) ② 잔차판 감쇠(-21%)가 오히려 완만 — 차등 누출이면 잔차판이 더 급락해야 함 ③ 정량 3축: 감쇠율 비교(-21% vs -44~-46%) / 입력 전량 WT-009 승계(재계산 0) / 잔차화는 동월 CS 연산(시계열 미참조). 동월 누출 지문 없음.

## C7 — "Spearman 직교성 불완전 (-0.039)" [documented]

- 월별 OLS는 Pearson-직교 — Spearman 잔여 -0.039 (원판 -0.060 대비 축소). 순위-기반 잔여 상관은 선형 잔차화의 알려진 한계. 적재 자체가 |0.06|이라 판정 영향 없음 (판정은 문턱 미달로 이미 확정).

## 합리화 자기검증 (auto-detection)

answer-principles 회피표현 조항 및 pit.md 금지 표현 목록의 전 패턴에 대해 본문 사용 여부 점검 — 해당 없음 (전 판단이 실측 수치 명기로 뒷받침됨). C1의 기전 재귀속은 사전등록 통제 수치(-0.060, 0.974, -0.015)로 뒷받침 — 성과 참조 재해석 아님.

## Escalation 판정

HIGH severity < 5 · AX hard FAIL 0 · PIT C1 위반 0 → Q-Lead 자동 escalate 비발동. 판별 결과는 정상 보고 경로.
