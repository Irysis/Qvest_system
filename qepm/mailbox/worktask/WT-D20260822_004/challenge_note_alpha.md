# Self-Adversarial Challenge — WT-D20260822_004 alpha-research (FQ-244 결합 규칙 마디)

finalize 직전 자가 적대검증 (v8.2 — Codex Round 대체, Opus 5-native adversarial reasoning).
대상 = alpha_package.json / alpha_validation.json 의 판정 **NON_ML_COMBINATION_POWERED_NULL** 과 그 지지 증거.
축 = 측정·판정 축 (가설설계 축은 challenge_note_hypothesis.md 소관, 재검 안 함 — 승계).

분류 규약: ACCEPT(명백 위반 → spec 수정) / PARTIAL(부분 인정 + 보완) / REBUTTAL(근거: 학술 + L-code + 정량 3축).

---

## A1 [powered-null 자격] MATERIAL 8.22%p/yr 문턱이 자의적으로 높아 null 을 '효과없음' 으로 과잉 승격한 것 아닌가 — **PARTIAL**

- 제기: "powered null" 라벨은 CI95 상단 < MATERIAL 이어야 성립하는데, MATERIAL 을 "PORT_t 를 2.95 로 올리는 데 필요한 증분"(=8.22%p)으로 잡으면 문턱이 커서 웬만한 CI 상단은 다 그 아래로 떨어진다. 즉 라벨이 문턱 설계의 산물일 수 있다.
- 판정: PARTIAL.
  - 인정 부분: MATERIAL 을 "벽을 넘기는 데 필요한 효과" 로 정의한 것은 **하나의 선택**이고, 만약 "실무적으로 의미있는 최소 개선(예: 연 +2%p)" 으로 잡으면 C1 의 CI95 상단 +3.01 은 그 문턱을 넘어 UNDERPOWERED 로 재라벨될 수 있다. 문턱 선택이 라벨을 가른다는 지적은 옳다.
  - 그러나 라벨을 지탱하는 것은 MATERIAL 단독이 아니다 — **ORACLE_K node headroom PORT_t 4.29 (paired t +4.29)** 가 독립 증거다. 이 마디에서 완전예지 {K 중 고르기} 상한이 4.29 로 벽 2.95 를 넘으므로, 창이 짧아서 못 넘는 게 아니다. 즉 "이 창에서 도달 가능한데 처치가 못 갔다" 는 결론은 MATERIAL 문턱과 **독립적으로** ORACLE_K 로 성립한다.
  - 보완 반영: alpha_package 에 라벨 두 겹으로 병기 — (i) MATERIAL=8.22 기준 POWERED_NULL (ii) 실무 문턱 2%p 기준이면 C1 은 UNDERPOWERED 경계(CI 상단 3.01). 처분은 어느 문턱에서도 동일(자본 후보 아님) 이나 **"효과없음 강도" 는 문턱 종속**임을 명시. degenerate implied_t_own=2.000 은 이미 PREREG 에서 자기적발됐고 판정에 안 씀.

## A2 [ORACLE_K 가 상한을 과대평가] node headroom 4.29 는 완전예지라 실제 도달가능 상한을 부풀린 것 아닌가 — **REBUTTAL**

- 제기: ORACLE_K 는 매월 선별 K=5 중 **실현** 차월 rank-IC 최대 팩터를 완전예지로 고른다. 미래를 알고 고른 값이므로 이걸 "도달 가능 상한" 이라 부르면 과대평가고, C1/C2 의 null 을 "창은 충분한데 처치가 못 감" 으로 몰아가는 편향이다.
- 판정: REBUTTAL.
  1. **학술**: Grinold-Kahn(1999) 의 fundamental law — TC(transfer coefficient) 상한은 정보의 완전 실현 시 IR 이며, oracle 은 정의상 "이 마디가 담을 수 있는 정보의 물리적 상한" 이다. 상한은 과대평가가 아니라 **상한의 정의** 그 자체다. 논점은 "C1 이 상한에 못 미친다" 가 아니라 "**창이 상한 도달을 원리적으로 막지 않는다**" 이고, 후자만 주장했다.
  2. **L-code**: measurement-graduation.md §3 (2026-08-22 신설) 이 "2.95 미달 보고 시 창-도달가능 상한을 양성 대조로 병기" 를 의무화했고, 그 근거(FQ-234 에서 실현 rank-IC 0.041 신호의 양성 대조가 131개월 창에서 PORT_t 1.674 에 그침 = 창이 원리적 불가)를 명시한다. 본 라운드 ORACLE_K=4.29 > 2.95 는 **정확히 그 반대 경우** — 창이 불가가 아님을 실증. 규약이 요구한 병기를 정확히 수행.
  3. **정량 3축**: (a) ORACLE_FWD(완전 예지 top-25) = PORT_t 30.0 — 진짜 물리 상한. (b) ORACLE_K = 4.29 — {K 중 고르기} 족 상한(결합 마디의 실질 여유폭). (c) 실제 arm C0/C1/C2 = 0.95/0.88/0.81. (b) 와 (c) 의 간극이 결합 마디의 미소진 여유폭이고, 그 여유폭은 **팩터 *선택*(어느 K 를 고르나)에 있지 결합 *규칙*(어떻게 뭉치나)에 없다** — C1/C2 가 규칙만 바꿔서는 4.29 근처에 못 감. 이것은 상한 과대가 아니라 병목이 규칙 아닌 선택에 있다는 직접 증거.

## A3 [R3 연결 절단이 진짜 절단인가, 검정력 부족인가] gap t=+0.25 는 "격차 없음" 이 아니라 "못 잼" 일 수 있다 — **PARTIAL**

- 제기: R3 는 solo-advocate vs consensus 편입 종목의 fwd_ret 격차를 재는데, t=+0.25 (연 +1.48%p) 를 "연결 절단" 으로 읽었다. 그러나 이 격차 계열 자체의 검정력을 안 쟀다 — 격차가 0 근방인 게 "정말 없다" 인지 "이 n 으로는 -2.01 도 +2 도 다 못 잡는다" 인지 불명.
- 판정: PARTIAL.
  - 인정: R3 격차 계열의 MDE 를 별도로 사전등록 안 했다. 엄밀히는 R3 의 null 도 검정력 라벨이 필요하다.
  - 완화 근거: 관측 격차는 **부호가 예측과 반대**(+1.48%p, solo 가 오히려 더 벌었다)이다. FQ-116 예측은 solo 가 **덜** 벌어야(격차 음수) 하는데 부호 자체가 뒤집혔다. "검정력 부족" 은 부호가 맞는데 크기가 작을 때의 변명이고, 부호 역전은 그 변명이 안 통한다. 게다가 R1b(solo advocate PORT_t -0.28 ≥ pool -0.35)가 **독립 경로로 같은 결론**(전이-음성 집중 미수송)을 준다 — 두 독립 관측이 같은 방향이라 R3 단독 검정력 우려가 판정을 뒤집지 못한다.
  - 보완 반영: alpha_package R3 항에 "부호 역전 + R1b 독립 정합" 을 명시하고, "R3 격차 계열 자체의 formal MDE 는 미산출(한계)" 을 정직 기록. next_probe 에 등재.

## A4 [C2 의 null 이 R2 미이동에 오염] C2 는 매개변수를 안 움직였는데(0.938배) 그 null 을 기전 증거로 쓰면 안 되는 것 아닌가 — **ACCEPT (라벨 분리 반영)**

- 제기: R2 에서 C1 은 solo-advocate 를 0.688배로 억제(매개 이동)했으나 C2 는 0.938배로 사실상 안 움직였다(NO_MEDIATOR_MOVEMENT). C2 의 성과 null 을 "유계화가 무익" 의 증거로 쓰면 "처치가 애초에 작동 안 함" 과 "작동했는데 효과 없음" 을 혼동한다.
- 판정: ACCEPT.
  - p5_emit.R val$falsification_measured$R2 는 이미 이를 구분해 기록했다("C1 은 매개 이동, C2 는 미이동 — 두 arm 의 null 은 같은 무게가 아니다"). 이를 alpha_package verdict 층으로 승격.
  - 반영: verdict 를 arm-별로 분리 — **C1 = 매개 이동 확인 + 성과 null = '연결 절단'(기전의 mediator→loss 링크가 본 풀에 부재)**. **C2 = 매개 미이동 = 처치 강도 부족(clip c=2.0 이 약함)으로 판정 정보량 감쇠, 기전 반증 증거로 약함**. 두 null 을 하나의 "유계화 무익" 으로 뭉치지 않는다.

## A5 [C0 벤치 basis 종속] PORT_t 0.947 은 IKS200 기준인데 EW-유니버스 기준이면 2.09 다. 벽 미달 판정이 벤치 선택의 아티팩트 아닌가 — **REBUTTAL**

- 제기: dual-basis 진단상 C0 는 IKS200 0.947 / parent 1.491 / EW-uni 2.088. 벽 2.95 미달을 IKS200 로만 판정하면 벤치 핸디캡의 산물일 수 있다(v8.3 dual-basis 기각-전-확인 의무).
- 판정: REBUTTAL.
  1. **학술/규약**: measurement-graduation.md §3 은 HARD 판정 basis 를 cap-w 벤치 단일 권위로 못박되, 기각 전 EW-유니버스·cap-tier 확인을 의무화한다. 본 라운드는 **판정이 basis 불변**임을 실측했다(paired Δt ~ 1e-17, C1/C2/C3 전부).
  2. **L-code**: canonical_screen_bt.R 의 basis_channels 진단(2026-08-09) 이 EW-유니버스 t 확대가 부호 무관 se 배율(x1.37) 이지 알파 증거가 아님을 명문화. 즉 EW-uni 2.09 를 "진짜 t" 로 읽는 것 자체가 금지된 오독.
  3. **정량 3축**: (a) C0 수준값은 basis 종속(0.947/1.491/2.088) 이나 (b) **처치 효과(paired C1-C0, C2-C0)는 basis 불변**(벤치가 차분에서 상쇄, Δt 1e-17). 즉 "C1/C2 가 C0 를 못 이긴다" 는 판정은 어느 벤치에서도 동일. (c) post2017 EW-uni t 도 arm 간 순서 불변. ⇒ 본 라운드의 **판정 대상은 arm 간 차이지 C0 의 절대 수준이 아니므로** basis 논쟁과 원천적으로 독립.

## A6 [LEAK1 양성 대조 실패가 하네스 무능을 의미] 사전등록 양성 대조 LEAK1(t=0.67 < 2.0)가 미통과 = 이 하네스가 개선을 못 잡는다 = 모든 null 이 무의미 — **REBUTTAL**

- 제기: PREREG controls.positive_control 이 LEAK1(입력 z 1개월 누출) 을 "이 하네스가 개선을 검출할 수 있음의 실증" 으로 지정했는데 실측 t=0.67 로 미통과. 그럼 이 하네스는 애초에 어떤 개선도 못 잡는 게 아닌가 → 전 arm null 은 검출 무능의 반영.
- 판정: REBUTTAL.
  1. **정량 3축 (핵심)**: 양성 대조는 **2겹**이었고 LEAK1 은 그중 약한 개입이다. (a) ORACLE_FWD paired t=30.0 통과 (b) ORACLE_K paired t=4.29 통과 (c) LEAK1 t=0.67 미통과. **결합 입력 z 를 1개월 앞당기는 것(LEAK1)은 *수익*을 누출하는 게 아니라 팩터값 vintage 만 바꾸는 약한 개입** — z(t+1) 이 fwd_ret(t) 를 예측하는 힘은 애초에 크지 않다. 반면 ORACLE 은 수익 자체를 안다. 하네스가 "진짜 큰 개선(ORACLE)" 은 t=30/4.29 로 확실히 잡으므로 검출 무능이 아니다.
  2. **L-code**: measurement-graduation §3 병기 의무는 "창-도달가능 상한" 을 요구하고 그 정본 눈금이 ORACLE 류다. LEAK1 은 보조 vintage 프로브이지 창-도달가능성의 정본 눈금이 아니다(PREREG basis_of_choice 도 ORACLE 을 정본으로 씀).
  3. **정보로 전환**: LEAK1 실패는 "하네스 무능" 이 아니라 **"이 마디의 vintage 축(정보 신선도)도 약한 지렛대"** 라는 독립 정보다. vintage monotonicity(LAG1 -2.44 / C0 0 / LEAK1 +1.00, 스팬 3.44%p, 단조)가 이를 뒷받침 — 하네스는 정보량에 방향 정확히 반응한다(단조), 단 그 반응 크기가 |t|<2. 반영: alpha_package controls 에 이 재해석을 명시(이미 val 에 있음, 승격).

## A7 [KQ150 소급 투영 오염] 08-22 KQ150 백필 결함(퇴출 미기록)이 본 판정을 오염 — **PARTIAL (진단 병기 + 방향 무해 논증)**

- 제기: 오늘(08-22) 실측된 KQ150 멤버십 백필 결함(2015-07 이전 편입 22/퇴출 0, 단조포함)은 universe=K200∪KQ150 ∧ 2015-07 이전을 포함하는 전 라운드에 파급이고, 본 라운드 창은 2008-03~ 라 정확히 그 구간을 포함한다.
- 판정: PARTIAL.
  - 인정: pre-2015-07 부분표본(n=88)은 그 편향에 노출된다. 이를 진단 병기로만 두고 국면 주장으로 승격하지 않았다(PREREG R_SUB caveat 자구 준수).
  - 방향 무해 논증: (i) 편향은 **하방/중립**(퇴출 미기록 = 살아남은 종목이 명부에 과다 = 만약 방향 있다면 성과 과대) 이나, (ii) 본 라운드 판정 대상은 **arm 간 paired 차이**이고 편향은 **전 arm 공통 유니버스**에 걸리므로 차분에서 대부분 상쇄된다(C0/C1/C2/C3 가 같은 오염 명부를 공유). (iii) R_SUB 실측상 pre/post 어느 부분표본도 |t|<2.0 로 결론(자본 후보 아님)이 부분표본 분할에 불변.
  - 보완 반영: alpha_package 에 known_contamination 필드로 KQ150 백필 결함을 명시하고, "paired 설계라 arm-공통 유니버스 오염은 차분 상쇄, 단 pre-2015-07 절대 수준값은 신뢰 안 함" 을 기록. next_probe 에 "clean 유니버스(퇴출 기록 복원) 재측정" 등재.

## 합리화 어휘 자가 스캔

answer-principles / pit.md 회피표현 목록(자체 재인용은 검사 훅 발화를 유발하므로 리터럴 생략) 대조 — 본문·산출물에 해당 계열(축소/합리화 어구) 사용 **없음**. A1 의 대안 문턱(연 2%p) 병기는 회피가 아니라 라벨을 두 겹으로 명시한 것이다. c=2.0 단일점의 용량-반응 미측정(C2 강도 부족)은 A4 에서 **한계로 명시**(축소 서술 아님).

## Q-Lead escalate trigger 점검

- HIGH severity ≥ 5? — 아니오 (ACCEPT 1 · PARTIAL 3 · REBUTTAL 3, 전부 판정 무변경 + 라벨 정밀화).
- AX axiom hard FAIL ≥ 3? — 아니오 (AX-000 정직보고 준수 · AX-002 하네스-내 실측 · C0 parity 4e-9 재현으로 프로세스 무결).
- PIT C1(lockbox/lookahead) 위반? — 아니오 (LAG1 PIT 스트레스 부호 유지, 동월 누출 징후 부재 · load_month_factors 경유 C15 · 선별 walk-forward anchor<hold C1).
- ⇒ **자동 escalate 불요**. 정상 발행.

## 결론

verdict = **NON_ML_COMBINATION_POWERED_NULL** 유지. 약점 7건 중:
- ACCEPT 1 (A4 — C1/C2 null 무게 분리, verdict 층 반영)
- PARTIAL 3 (A1 라벨 두 겹 · A3 R3 검정력 한계 명시 + R1b 독립정합 · A7 KQ150 오염 진단병기+방향무해)
- REBUTTAL 3 (A2 ORACLE_K 상한 정의 · A5 basis 불변 · A6 LEAK1 = 약한 개입, ORACLE 이 정본 양성대조)

핵심 강건성: 반증 축(R1b·R3)이 성과 측정 **전에** 답을 확정했고(mediator→loss 링크가 본 풀에 부재), primary 의 powered null 이 그 예측과 정합. 성과 null 을 사후 합리화한 구조가 아니다. C0 parity 4e-9 로 하네스 무결 실증. 자본 자격 주장 없음(metric_type=canonical_screen_diag 전면).
