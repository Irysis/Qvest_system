# challenge_note.md — WT-D20260802_003 Self-Adversarial Challenge (v8.2)

**작성**: Alpha Research Agent, 2026-08-02 (finalize 직전 자체 적대검증 — Charter §8 No Silent Override)
**대상**: `alpha_package.json` (W_portt — trailing ICIR top-20 선별 × clip-at-zero trailing PORT_t 정렬 가중)

## 자기 비평 5건 + 분류

### C1. 저장 파생 패널 소비 = 동월 look-ahead 실사고 클래스 (2026-07-14 재발 위험) — **REBUTTAL**
- **제기**: trailing 가중 재료 `r6_factor_deployzone_active.parquet`는 저장 파생 패널. 07-14 실사고(저장 패널 동월 vintage → PORT_t 2.08× 부풀림)와 같은 부류 아닌가. placebo/OOS는 이 오염을 못 잡는다.
- **반박 근거 (학술 1 + L-code 1 + 정량 3축)**:
  - 학술: Newey-West (1987) NW lag-3 추정 경로는 07-14 사고와 무관 — 사고 판별 도구는 lag-stress + vintage 통제 (메모리 project-stored-panel-samemonth-lookahead 확립 프로토콜을 그대로 적용).
  - L-code: L-RAMP-20260711_200226 — 패널 자체가 canonical parity 검증 산출물(당월-only score→fwd 구조 명시).
  - 정량 3축: ① **구조적 lag** — anchor a의 소비 창 [a−36, a−1]의 말단 월 active는 anchor 시점에 실현 완료(동월 겹침 0) ② **lag-1 스트레스 무붕괴** — paired 2.569 → 2.481, PORT_t 1.338 → 1.314 (누출이면 붕괴 패턴; BearProb 사고에서 개선 전량 소멸했던 것과 대조) ③ **provenance** — 07-14 재빌드 byte-parity(#76) + z-score는 load_month_factors parity max|d|=0.
- **처리**: alpha_package `self_pit_check` + CF-4에 기록. 추가 조치 없음.

### C2. "가중 개선"은 위장 선별(membership) 효과 아닌가 — **PARTIAL**
- **제기**: clip-at-zero가 팩터를 0으로 만들면 그것은 가중이 아니라 soft-선별이다. 그러면 "가중 slot에서 정렬이 유효"라는 기전 주장이 무너지고 R6(선별 효과)의 재탕이 된다.
- **부분 인정 + 보완 자료**: θ 희소성 실측 — zero-θ **median 1/20** (mean 3.68), 즉 membership은 대부분 보존되고 개선의 주채널은 **intensity**(유효 팩터수 n_eff 13.1 vs EW 20). 단 일부 anchor에서 max 17 클립 = 국소적 선별화 혼입은 인정. 또한 양-θ 집합 vs Ppure 풀 Jaccard 0.34 (풀 자체 0.32) — Ppure membership으로의 수렴이 아님을 확인. **일부 변경**: 기전 서술을 "intensity 주채널 + 국소적 membership 혼입"으로 한정(alpha_validation verdict, CF-5).

### C3. paired 유의를 "양성"으로 프레이밍 = 과대포장 위험 — **ACCEPT**
- **제기**: 절대수준 1.338은 HARD 2.95·천장 2.937에 크게 미달, oos −0.407은 무조건 FAIL 구간. paired +2.57만 앞세우면 자본 오판 유도.
- **수정 반영**: ① 판정 라벨을 "기전 양성 + graduation FAIL + config-scoped negative(천장 미달)"로 고정 ② CF-1/CF-2 = HIGH ③ 텔레그램 헤드라인에 "천장 미달(1.34<2.94)" 병기 ④ selection_objective 수치는 전부 `metric_type="canonical_screen"` (graduation 선언 없음 — 권위는 forge).

### C4. selection_type=chain 라벨 — 4 arm 열거는 sweep 아닌가 — **PARTIAL**
- **제기**: 변형 4종을 열거 측정했으니 sweep(DSR HARD) 아닌가.
- **부분 인정 + 보완**: 사전등록(config hash 동결 `fdc9d20beea412de`)에서 **W_portt 단독을 유일 채택후보로 지정**, famfix/icir/ivar는 대조군(채택 불가) — argmax 선택 행위 없음 → chain 요건 충족(iteration 자체가 없는 1-shot A/B, OOS 반복조회 없음). 보완: DSR을 진단 산출하고 **n_trials=4 패널티 병기**(raw 1.33 / penalized 1.13), n_trials 회계를 package에 기록. substrate가 P-pure 계보와 공유되는 점도 명시(계보 33 trial 별도 표기).

### C5. trailing-정렬 가중 = factor momentum 유형 — DIST-AR-007(factor-of-factors momentum NULL) 재위반 아닌가 — **PARTIAL**
- **제기**: R13에서 감쇠-선별이 FM으로 수렴·붕괴했다. 가중 slot의 trailing 정렬도 같은 함정.
- **부분 인정**: post-2017 실측 약화(post17 cap-w t −1.05, subperiod IC 중기 침하 0.018)는 이 우려와 정합 — `regime_scope.weakens_or_reverses_in`에 리더십 반전 국면을 명시 반영. 단 전기간 paired +2.57은 R10의 W_factor null과 달리 유의 — "FM이라 무조건 null"은 기각(선별 slot과 가중 slot의 비대칭이 본 라운드의 발견). INV-7: FM-계열 한계는 config-scoped로만 소비.

## 합리화 자기검증
- answer-principles 회피표현 조항의 금지 목록 전수 대조 — 본문·패키지에 해당 표현 사용 없음 확인 (목록 리터럴 인용은 grep 검출기 오탐을 유발해 생략 — 정본 목록은 `.claude/rules/answer-principles.md` 참조).
- 미측정 항목 정직 라벨 2건: ① redundancy active-cor vs Ppure — 러너가 Ppure pr 시계열을 RES에만 저장(결함 인지, 빌더에서 NA + "검증 안 됨" 라벨, risk 단계 재측정 TBD) ② post_neutralization_ic 미수행(사유 기재).
- 2026-06 신호월(7월 폭락 수익)은 신호달력 말단 제약으로 측정 미포함 — 명시 기록(validation.measurement).

## Escalation 판정
- HIGH severity = 2건 (< 5) / AX axiom hard FAIL = 0 / PIT C1(lockbox·lookahead) 위반 = 0 → **Q-Lead 자동 escalate 불요**.

## AX-008 Triangulation 지위
- 본 self-adversarial = 3-source 중 1. Forge(재측정)·Architect는 후속 단계 소관 — 본 패키지는 screening 실측 단계로 2/3 요건은 graduation 시점 적용.
