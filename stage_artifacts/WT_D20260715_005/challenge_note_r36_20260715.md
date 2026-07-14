# Self-Adversarial Challenge — R36 insider tripwire coverage 확장 (WT-D20260715_005 / FQ-050)

**규약** (v8.2 Codex Round 대체 · Opus 4.8 native adversarial): finalize 직전 산출물을 스스로 적대 검증. 각 concern ACCEPT/PARTIAL/REBUTTAL 분류 + 근거 + self-rationalization 자기검증. Charter §8 No Silent Override.

**대상**: alpha_package/verdict.json (R36 3형태 coverage 확장 판정). **면 = monitoring (non-capital)** — 자본 게이트 무관, tripwire 임계 권고만.

---

## Concern 1 — 임계 완화의 다중검정 (task 지정 ①)
**적대 제기**: 4개 문턱/형태를 시험하고 완화형(F2)을 권고한다. cherry-pick·다중검정 오염 아닌가? 완화하면 t 가 오르니(F2 t+4.25 > F0 +3.36) 자기충족적 선택 아닌가?

**분류: PARTIAL**
- **인정**: 4-config 시험 노출은 사실. F2 의 gap_t 상승은 **상당부분 표본증가(월수 126→250) 아티팩트** — 이미 verdict 에 명시했으나 권고 논리가 t-비교에 기대는 인상 방지 강화 필요.
- **반박 근거**: (a) chain — 4개 **사전등록 고정 config**(prereg_r36.json hash 78164cf5), sweep-argmax 아님. (b) 권고 근거 = **모니터링 utility(coverage 126→250 armed months + 현북 활성화)** 이지 t-max 아님(t-max 라면 F3cut 5.14 를 골랐어야). (c) **placebo p=0 이 4형태 전부** — 완화형만이 아니라 모든 문턱에서 SAFE 구조(downside/vol/tail 개선)가 일관 = 우연-선택 아닌 robustness signature. (d) monitoring-face = DSR 게이트 non-binding(자본 아님).
- **보강**: verdict tripwire_recommendation.rationale 에 "gap_t 상승 = 표본 아티팩트, per-name 강화 아님" 명시 유지. 자본 주장 無.

## Concern 2 — 대형 tier 표본이 여전히 얇은가 (task 지정 ②)
**적대 제기**: coverage 확장의 명분은 "large-cap tier 표본 강화"였다. 표본은 3배 늘었으나 TOP30 SAFE t 는 완화 후에도 1.30(<2). 원래 목적(대형주 monitoring 신뢰) 미달 아닌가?

**분류: ACCEPT (핵심 한계로 수용)**
- **전면 인정**: TOP30(진짜 대형 30종) SAFE gap 은 4형태 전부 sub-threshold(F0 1.38 · F1 0.93 · F2 1.30 · F3cut 1.68, 전부 <2). 표본 744→2341(3.1x) 확장에도 mega-tier 신호 t 는 문턱 미달 잔존. **목적(대형 tier 신뢰 강화)은 표본 축에선 달성, 신호 축에선 미달.**
- **처리**: 이것을 **은폐 않고 core_finding_TOP30_thinness 로 격상** + R33 "large t=2.57" honest 교정(그건 large-TERCILE=상위 85종이지 mega-30 아님). recommendation.caveats 에 "TOP30 는 완화 후에도 sub-threshold — mega 보유엔 SAFE 신뢰 약함" 명기. next_probe #1 로 mega-thinness 진단(power vs signal-death) 착수 예약.
- **자기합리화 검사**: "미미/보수적이면 OK" 류로 TOP30 약함을 무마하지 않았는가? → 검사 결과 무마 없음. "경제적 +3.8~6.7%/yr 양수" 는 정량 사실 병기이지 t-미달 은폐 아님(t 명시).

## Concern 3 — 결합 신호(Form1)의 look-ahead (task 지정 ③)
**적대 제기**: INS02+INS03 결합(F1)이 recency(INS03)를 쓴다. recency = "최근 순매수" 라 미래-근접 정보로 timing leak 가능성 아닌가?

**분류: REBUTTAL (명시 근거)**
- **근거 1 (구조)**: INS03 는 INS01/INS02 와 **동일 signal_date(월말 m)→홀딩월(m+1) 정렬** — recency 는 signal_date 시점까지의 과거 순매수 최근성이지 미래 데이터 아님. PIT-clean by construction (C5).
- **근거 2 (실증)**: F1 lag1 스트레스 t=+3.12 (붕괴 아님) — 동월누출이면 flag 을 +1월 더 밀 때 붕괴해야 함. robust = leak 부재.
- **근거 3 (moot)**: F1 은 어차피 KILL(무이득, TOP30 t 0.93). look-ahead 여부와 무관하게 배선 금지 — 우려의 실질 영향 없음.

## Concern 4 — F2 gap_t 상승 = per-name 강화로 오독 위험 (self-generated)
**적대 제기**: 헤드라인이 "완화가 신호를 강화(t+3.36→+4.25)" 로 읽히면 과대보고.
**분류: ACCEPT** — verdict.forms.F2 + core_finding 에 "gap_ann 12.4%→9.0% 희석 · t 상승은 표본 아티팩트 · per-name 강화 아님" 3중 명시. 정직 prior("완화=표본↑ 신호 희석") 를 실측이 확증 — prior 대로 보고.

## Concern 5 — SAFE gap 이 인과인가, quality/beta 노출 아티팩트인가 (self-generated)
**적대 제기**: 임원 순매수 종목이 이미 저beta/고quality 라면 gap 은 factor 노출 잔여이지 insider 정보성 아님. size 만 통제(R33 t 5.22)했고 sector/quality/beta 미통제.
**분류: PARTIAL**
- **인정**: 본 라운드는 size(t-1) 프레임만. sector/quality/beta 잔여 confound 미격리 — R33 next_probe #3(sector-neutral) 계승 미완.
- **완화 근거**: monitoring-face 는 **SAFE 라벨(forward 안전)** 만 주장하지 orthogonal alpha 주장 아님 — factor 노출이 SAFE 의 *채널*이어도 tripwire 유효성엔 무해(무엇으로 SAFE 든 보유월 안전이면 monitoring 목적 충족). 단 "insider 고유 정보" 로 과대주장 금지.
- **처리**: next_probe 에 sector-neutral 잔류(FQ-050) 표기. verdict 에 "de-risk 채널 = insider 고유로 단정 안 함" 톤 유지.

---

## Self-Rationalization 자동검사 (measurement-graduation §금칙 grep)
스캔 대상: "미미 / 관행적 / 실무적 / 보수적이면 OK / 대부분 결과 동일 / 영향 미미".
- verdict/challenge 전문 grep → **0건**. TOP30 약함을 "미미" 로 무마하지 않고 t 수치 명시 + core_finding 격상. 완화 dilution 을 "관행적 허용" 없이 정량(12.4→9.0%) 보고. **합리화 회피 PASS.**

## Q-Lead escalation trigger 검사
- HIGH severity ≥5 → **No** (Concern 2 ACCEPT 는 한계-수용이지 위반 아님; 나머지 PARTIAL/REBUTTAL).
- AX axiom hard FAIL ≥3 → **No**.
- PIT C1(lockbox/lookahead) 위반 → **No** (C5 PIT-clean + lag1 robust 실증).
- **결론: escalation 불요.** monitoring-face 측정 + 한계 명시 판정.

## AX-008 Verification Triangulation
self-adversarial(본 note) = 3-source(Forge·Architect·Self-Adversarial) 중 1. 본 라운드는 non-capital monitoring 측정으로 forge backtest·architect 진단 미소환(자본 판정 아님). self-adversarial 단독 + parity 재현(F0=R33 정확 일치) + placebo/lag1 내부검증으로 무결성 확보. 자본 게이트 진입 시 3-source 재적용 의무.
