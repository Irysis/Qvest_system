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

---

# Risk Research — Self-Adversarial Challenge (v8.2, 2026-08-02)

**대상**: risk_package.json (기전 진단 라운드 — Q-Lead 재정의: dossier 아닌 위험구조 설명). 산출 전 자기 적대검증 6건.

### R-C1. Σ conditioning — cond 645 > 500 failure rule 위반 — **ACCEPT (spec 수정 완료)**
- **제기**: Σ=BΩB'+D 초기 산출 cond 645.1 > 500 (Ω LW cond 1202 — MKT 분산 지배의 스케일 이질성 기전).
- **수정**: eigen-floor(target cond≤500) 적용 → cond **500.0**, PSD 유지, floored 6/348 고유값, 상대 Frobenius 변형 **0.00069**(구조 왜곡 정량 문서화). diagnostics 에 before/after 병기.

### R-C2. "가중 정렬 = 사실상 단일팩터 선택" 서술 강도 — **PARTIAL (서술 한정)**
- **제기**: cor(W_portt arm, C04 standalone)=0.66 은 완전 등가가 아니다(theta 시변 — 과거 앵커에선 타 팩터 지배 가능).
- **보완**: 등가성 주장을 **as_of 스냅샷 구조**(theta 89.1% / 분산점유 93.3% / n_eff 1.25)와 breadth 논리에 한정. 시계열 전체는 "수렴" 서술. 오히려 추가 실측이 논지를 강화: arm NW-t 1.338 < C04 단독 1.643 — 시변 theta 추적이 최강 단일팩터만도 못함(추적 지연 비용) = 가중 slot 의 breadth 이득이 0 임을 재확인.

### R-C3. Ppure 풀 상관(0.35) < ICIR 풀(0.625)이 window/선택-조건화 아티팩트 아닌가 — **REBUTTAL (3축)**
- (학술) 선택통계 tt=mean/sd 는 pairwise cor 를 목적함수로 갖지 않음 — 선택-조건화가 상관을 하향 편향시킬 기전 부재 (Grinold-Kahn FLOA: breadth 는 선택의 부산물).
- (정량) full-sample 에서도 0.474 vs 0.576 방향 유지, trailing-36 에서 0.351 vs 0.625 로 확대 — 두 윈도우 일관.
- (L-code) 선별 아크 R6 실측(paired +3.01, PORT_t-선별만 양성)과 정합 — 전이-생존 팩터가 실제로 이질적임을 독립 확인.

### R-C4. D fallback + missing z→0 중립 처리 — **PARTIAL (정량 문서화)**
- 42/348 종목 specific risk = universe median(0.0104/m) 대입(중앙값 = 무편향 중심 대입), missing z cells 279/6,264(4.5%)→0. package 에 카운트 기록. top-25 RC 재검은 next_probe 로 이관.

### R-C5. cap-w 벤치 = K200 Size-비례 근사 — **PARTIAL (proxy 라벨)**
- float 미조정·지수규칙 미복제 → `portfolio_basis` 에 proxy 성격 명시. 방향성(MEGA 가 cap-w active risk 지배)은 07-18 실 book 실측(0.969 괴리)과 동형 — 결론 강건.

### R-C6. crisis 에서 팩터 active 상관 하락(0.528 vs 0.590) — 통념 역방향 정직 보고
- 자산수익 상관은 위기 시 상승이 통설이나, 본 측정은 **active(벤치 대비) 시계열** — 위기 국면 팩터 분화(방어/공격 갈림)로 해석 가능. n_crisis=23 소표본 명시. 판정에 미사용(참고 진단).

## 합리화 자기검증
- 금지 패턴("미미/관행적/보수적이면 OK") 사용 없음 — R-C4 는 정량(42/348, 279/6264)으로 대체.
- Σ PD violation 없음(PSD TRUE, min eig > 0). 모든 수치 metric_type 라벨(canonical_screen 파생 / estimated / proxy / unavailable-EVT).

## Escalation 판정
- risk 자체 HIGH = 1건(RF-WT003-MECH — 기전 발견이지 결함 아님) < 5 / Σ PD violation 0 / PIT hard 위반 0 → **자동 escalate 불요**.

## AX-008 지위
- 본 self-adversarial = 3-source 중 1 (risk 절). Forge·Architect 는 후속 소관.
