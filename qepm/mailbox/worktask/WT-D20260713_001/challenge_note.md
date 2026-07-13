# challenge_note — WT-D20260713_001 R17 (Self-Adversarial Challenge, v8.2)

**대상**: 보유 데이터 신규 팩터 3종 (F-A 텍스트유사도 / F-B 제출지연 / F-C insider공시량 급변)
**방식**: Opus 4.8 native adversarial (외부 Codex 없음). finalize 직전 약점 자가제기 → 분류 → 근거.
**전제 사실(실측)**: 3종 모두 cap-w PORT_t < 2.95, placebo p<0.05 통과 0건. survivors 0.

---

## Concern 1 [HIGH] — F-A 유사도 = '기업 안정성' 프록시(Size/age confound)인가
**제기**: MD&A 문구가 안 바뀌는 기업은 크고 오래된 안정 기업일 수 있다 → 유사도는 Size/age를 재측정하는 것.
**처리 = ACCEPT(moot)**. Size-partial 잔차 재스크리닝 cap-w PORT_t = **0.56** (raw 0.72). 즉 Size 제거 후에도 신호 부재 — F-A는 애초에 유효 신호가 없어 confound로 귀속할 것이 없다. 부호분해(cos-only 0.67 / jac-only 0.67, cos-jac cor 0.86)로 blending-artifact도 배제. **결론: confound 여부와 무관하게 prereg-sign null**. 별도 발견: 부호반전(low-sim long) cap-w 1.38·EW-uni 0.33 — CMN 방향의 KR 반전 가능성이나 **post-hoc·sub-threshold**로 next_probe.
**합리화 자기검증**: "미미/관행" 미사용. 0.56은 실측.

## Concern 2 [HIGH] — F-B 제출지연 = 단순 소형주 프록시인가
**제기**: 늦게 제출하는 기업은 소형·자원부족 기업 → delay z는 Size의 대리.
**처리 = PARTIAL**. Size-partial cap-w PORT_t = **1.10** (raw 1.29). 신호가 Size 제거 후에도 **방향·크기 대부분 생존**(1.29→1.10, ~15% 감소) → 순수 소형주 프록시 아님, Size-독립 성분 실재. 단 전체가 1.29≪2.95로 약하고 placebo p=0.135(비유의). **분포 실측 정정**: delay 중앙값 −1일(대부분 마감 직전 제출), 13.6%만 지연 → F-B는 사실상 '조기성 스프레드'(−41~0일)를 측정. 방향(조기=long) 일관·EW post2017 +0.80. **결론: Size-무관 성분 있으나 신호 자체가 약함**(소형주 문제 아닌 신호강도 문제).
**합리화 자기검증**: prior earliness FAIL을 "게이트 폐지로 무효"라 편하게 넘기지 않고 canonical 재측정 실측치(1.29)로 '약함'을 직접 제시.

## Concern 3 [HIGH] — F-C = 단순 이벤트-노이즈 / insider lane 중복인가
**제기**: (a) 공시 건수 YoY 급변은 방향성 없는 노이즈. (b) insider_activity 원천이 insider lane(WT-005)과 공유 → 중복.
**처리 = ACCEPT**. placebo p=**0.22**(비유의) → 신호-수익 링크가 순열과 구분 안 됨 = 노이즈 확증. IS 0.13 / OOS 1.45 불안정(OOS 단독 견인). turnover **4.87**(분기 count 급변이 보유를 뒤집어 비용 과다). 중복 우려: F-C는 **count(활동강도)**로 WT-005의 **net-buy magnitude** 및 L-AR-20260710_234439의 **정정 빈도**와 구성상 구분되나(방향·크기 아님), Size-partial 0.88·mega_w 0.10(3종 최대)로 대형 insider-활동 기업 틸트 존재. **결론: 이벤트-노이즈 확증(placebo)**. 정직 재라벨(전체공시 아님, insider-only)도 명시.
**합리화 자기검증**: "노이즈지만 방향은 맞다" 식 변호 회피 — placebo가 못 넘김을 그대로 수용.

## Concern 4 [MEDIUM] — F-A section_head가 원문 유사도를 왜곡(boilerplate 상향편의)
**제기**: section_head는 MD&A '개요' 도입부(≤8000자) — 정형 문구가 지배해 모든 기업 유사도가 인위적으로 높아 판별력 소실.
**처리 = PARTIAL(REBUTTAL 근거 병기)**. sim 중앙값 0.41(0~1 스프레드 실재, 상단 포화 아님) → 판별력 완전소실은 아님. 단 full MD&A(≤40000자)는 미보존 → head 한정을 metric_type·scope에 정직 라벨. **결론: 부분 인정 — 원문 전체 유사도는 재추출(쿼터 필요) next_probe**. 근거: L-code(Phase A text arc), 정량(sim 분포 0.001/0.41/1), 학술(CMN 2020은 10-K 전문 사용 — head-only는 근사).

## Concern 5 [MEDIUM] — sweep 3종 다중검정 미보정으로 최선(F-B)이 우연 상향?
**제기**: 3 trial 중 최댓값을 고르면 우연 상향. n_trials=3 DSR 보정 안 하면 낙관.
**처리 = ACCEPT**. selection_type=sweep 명시, DSR 산출(E[max_3 z]=0.853). 그러나 애초 best조차 1.29≪2.95 + placebo 비유의 → 다중검정 보정 전에 이미 미달. **결론: 보정 필요성은 인정하나 결론 불변(전부 negative)**.

---

## 종합
- **HIGH severity 개수 = 3** (< 5 escalate 문턱). **AX axiom hard FAIL = 0**. **PIT C1(lockbox/lookahead) 위반 = 0**(API 0·text_cache read-only·신호는 rcept月+1 PIT C5 준수). → **Q-Lead auto-escalate 미발동**.
- No Silent Override 준수: 모든 concern ACCEPT/PARTIAL 분류 + 실측근거. survivors 0을 완화·미화하지 않음.
- 판정 어휘: config-scoped negative + 프론티어 표시. 종결어휘 없음. next_probe 5건(≥2 요건 충족).
- AX-008 3-source: 본 self-adversarial = 1 source (Forge/Architect 미투입 — alpha 단계 screening, forge는 후속 판정 시).
