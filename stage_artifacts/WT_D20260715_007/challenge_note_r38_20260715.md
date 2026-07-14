# Challenge Note — R38 insider SAFE 청산-타이밍 대칭검정 (WT-D20260715_007 / FQ-052)

**Self-Adversarial Challenge (v8.2, Opus 4.8 native).** finalize 직전 자체 적대검증.
verdict: `asymmetric_benign_risk_sticky` (수익 premium 청산 시 복귀 / 위험 protection 점착 / hangover 없음).
성격: monitoring 진단 (자본/sizing 아님). config_hash=7d9d5f1a7ccfa754.

판정 어휘: 아래는 "종결"이 아니라 config-scoped 능력확립 + 프론티어. No Silent Override — 각 concern 분류 기록.

---

## Concern 1 [HIGH] — EXIT 표본 희소 + 수익축 무유의. "sticky"가 point-estimate 노이즈일 수 있다.
- MID EXIT n=115 name-months, 월별-paired 공통월 47개. held EXIT n=29. 얇다.
- 수익축 핵심 t 전부 무유의: MID ENTRY vs OFF t=+1.05 · EXIT vs OFF t=+1.57 · EXIT vs SUSTAIN t=+0.69. 유의는 SUSTAIN(t=+3.63)뿐.
- 위험축 "sticky"(EXIT downside −0.069 > OFF −0.086, tail 5.2% < 7.9%)는 **유의검정이 아닌 점추정 순서**에 의존.

**분류: PARTIAL (인정).** 처리:
1. verdict를 "sticky_safe_full"(수익+위험 점착)에서 **`asymmetric_benign_risk_sticky`로 하향** — 수익 premium은 복귀(무유의)임을 명시. 과대주장 제거.
2. 위험축 stickiness는 유의성 주장 아님 — **상태 간 downside/tail 단조순서**(OFF > ENTRY > SUSTAIN ≈ EXIT protection)라는 정성 패턴으로만 소비. 이 순서는 lag1 스트레스(SUSTAIN t +3.63→+3.40 robust) + held 확증(EXIT vs OFF t=+2.28 독립 유의)으로 보강.
3. 최종 주장 범위를 **"청산=위험재상승 아님(no hangover)"으로 한정** — "청산 후에도 양성 알파"로 확대 금지. monitoring 라벨 강도 하향(SAFE→SAFE_FADING) 권고이지 자본 규칙 아님.

## Concern 2 [HIGH] — 검열편향(survivorship): 위험한 청산은 패널에서 사라져 측정 불가.
- "EXIT"은 flag-off **다음 달에도 패널 잔존**을 요구(연속 hold_ym + Ret_1m 존재). flag-off과 동시에 상장폐지·유동성 붕괴·유니버스 이탈한 종목은 **검열** → 최악 청산이 표본에서 제외 → EXIT 안전성 상향편의 가능.
- 즉 "no hangover"는 **여전히 투자가능한 종목 조건부**.

**분류: PARTIAL (정당한 한계).** 처리:
1. 주장에 **조건부 라벨 명시**: "청산 후에도 *북에 잔존하는* 종목은 위험재상승 없음". 북 이탈(폐지/유동성) 종목의 청산 위험은 **본 검정 범위 밖**.
2. monitoring 함의 정합: tripwire의 실제 use-case = "보유 중인데 SAFE flag이 꺼진 종목" → 관측 가능 서브셋과 정확히 일치. 검열된 catastrophic exit은 별도 tripwire(유동성·폐지 경보)의 몫 — insider SAFE tripwire의 소관 아님.
3. **next_probe P1로 승계**: flag-off 후 다중월(t+1..t+3) 추적 + 패널이탈 종목을 "worst-case 대입(−100% 혹은 last-price)" 로 검열 스트레스 → 검열편향 정량.

## Concern 3 [MED] — 다중대조 + R33/R34 재확인 혼입. 신규성은 EXIT뿐.
- ENTRY/SUSTAIN/EXIT × {raw,exc} × {ALL,MID,held} = 다수 look. 독자가 marginal t 하나를 과독할 위험.
- SUSTAIN t=+3.63은 사실상 R33/R34 진입 SAFE의 재확인 — 본 라운드 novel = EXIT 거동뿐.

**분류: REBUTTAL (근거 제시) + 부분 인정.**
- 근거: selection_type=**chain**(가설주도 고정 config, DSR 게이트 부적용 — measurement-graduation §3). NB_THR=1.0은 R33 frozen(sweep 아님), 상태기계·dur버킷·문턱 전부 사전등록(prereg_r38.json, hash 고정). n_trials=1.
- verdict는 **단일 t가 아닌 순서 패턴 + 3중 robustness**(lag1 + held 확증 + ALL/MID 일관)에 의존. 어떤 EXIT 수익 대조도 t=2 미달임을 명시(과독 방지).
- 부분 인정: novel 기여를 **EXIT 거동으로 명확히 한정**하고, SUSTAIN 유의는 "기존 R33/R34 확인(신규 아님)"으로 라벨.

## Concern 4 [MED→framing] — 수익 SAFE는 전이현상이 아니라 "지속-클러스터" 현상.
- ENTRY(t+1.05)도 EXIT(t+1.57)도 무유의, SUSTAIN(t+3.63)만 유의 → 수익 premium은 **flag이 켜지는/꺼지는 순간이 아니라 flag이 지속되는 상태**에서만 신뢰.
- P2 duration이 이를 지지: MID d1 vs OFF t=+0.05(무), d2_3 t=+2.38, d4plus t=+3.04 — 지속할수록 신뢰↑. freshness slope(dur→ret) t=−1.32 무유의 → "신선도 절벽" 없음.

**분류: ACCEPT into framing (프레이밍 강화).** 처리:
- 최종 서술을 "SAFE 수익 신호 = **지속(SUSTAIN) 클러스터 현상**, 진입/청산 순간 이벤트 아님"으로 정립. monitoring 함의: **1개월 단발 flag보다 지속 flag을 SAFE로 신뢰**, 청산은 완만한 강도하향으로 처리(즉시 danger 전환 아님).

---

## 합리화 자동검증 (PIT 금지표현 self-scan)
"미미·관행·보수적이면·대부분 동일·영향 없음" 미사용. 무유의 t는 "무유의"로 명시(유의 위장 없음). 검열편향을 "미미"로 넘기지 않고 next_probe로 승계. verdict 하향(sticky_full→benign_risk_sticky)은 Concern 1 수용의 실 반영.

## 종합
- **severity HIGH 2건(표본희소·검열편향) — 둘 다 PARTIAL 인정 → 주장범위 축소(monitoring·조건부·순서패턴)로 처리.** Q-Lead escalate 트리거(HIGH≥5 / AX hard FAIL≥3 / PIT C1) 미해당.
- AX-008 3-source: self-adversarial(본 note) + held 확증(독립 서브셋) 정합. forge 불요(canonical 진단, 자본 아님).
- 최종 판정 신뢰: **"청산은 위험재상승 아님(robust) + 수익 premium은 지속-클러스터 현상(robust) + 청산 시 premium 완만복귀"** — 이 3점은 표본·검열 한계 하에서도 순서패턴·lag1·held로 지지. "청산 후 양성 알파"·"자본 기여"는 주장 안 함.
