# challenge_note — WT-D20260808_002 (M26_Revenue_Mom 증분 판정)

Self-Adversarial Challenge (v8.2, Codex Round 대체). finalize 직전 자체 적대검증.
분류 = ACCEPT (명백 위반 → spec 수정) / PARTIAL (부분 인정 → 보완) / REBUTTAL (근거 제시 후 반박).

---

## A1 [HIGH] 전이 벽 — 재료 자격 통과, 자본 자격 크게 미달 → **ACCEPT**

- 실측: 증분 FMB NW3 t **+2.555** (문턱 2.0 통과) 이나 cap-w canonical PORT_t **+1.544** « HARD 2.95.
  잔차(3종 통제) 표현도 +1.443. EW-유니버스 대비 +2.041 (p 0.041) 로 상승하나 여전히 미달.
- `oos_retention_approx` **0.123** — measurement-graduation §3 의 "<0.5 무조건 FAIL" 대역.
- 처분: 판정을 **재료 자격(MATERIAL_QUALIFIED) 단독**으로 못박고 자본 자격은 어떤 형태로도 주장하지 않음.
  사전등록의 MATERIAL_QUALIFIED action 문구("다음 단계는 canonical_screen_bt 경유 PORT_t 측정이며
  자본 자격은 HARD 3종 별도")를 그대로 이행한 결과이며 문턱 변경 없음.
- ★EW-대비가 2.04 로 살아나는 것을 "벤치 아티팩트"로 읽고 싶은 유혹이 있으나, 2.04 역시 2.95 미달이므로
  아티팩트 보정만으로 자본 자격에 도달하지 않는다. 이 유혹을 명시적으로 기각한다.

## A2 [HIGH] 나의 초안이 "2017년 이후 감쇠 확정"으로 갈 뻔했다 → **ACCEPT (자기 정정)**

- 부기간 점추정은 단조 하락: 2003-2009 연 +3.58% → 2010-2016 +1.82% → 2017-2026 +0.99%.
  t 도 1.97 → 1.67 → 0.88. 이대로면 "post-2017 감쇠"로 서술하기 쉽다.
- 그러나 **각 구간 자체 sd 로 필요 효과크기를 계산하니 3구간 전부 관측 < 필요**:
  2003-2009 필요 연 4.53% vs 관측 3.58% / 2010-2016 필요 2.47% vs 1.82% / 2017-2026 필요 2.63% vs 0.99%
  ⇒ 전부 `INCONCLUSIVE_UNDERPOWERED`.
- 처분: "감쇠 확정" 서술 금지. 보고문은 "점추정 단조 하락 관측 + 3구간 전부 검정력 미달 ⇒ 감쇠 주장 불가"로 고정.
  EW-diag 의 `post2017_t 0.406` 도 n=115 저검정력이라 같은 규율 적용.
- 근거: [[project-conditional-splits-destroy-power-20260808]] (분할 3/3 붕괴 실측).

## A3 [HIGH] lag1 유지율 0.23 — 승계 가설의 path 서술과 실측이 어긋남 → **PARTIAL**

- 승계 path: "매출 전망 개정 → 후속 1~3개월에 걸쳐 EPS 후속 개정·실적 확인으로 가격 반영".
- 실측 A: 반증 관측(전파)은 **t+3 까지 유의** — M26(t)→C02(t+1) rho +0.0998 (t_NW3 +16.71),
  (t+2) +0.0732 (+12.69), (t+3) +0.0542 (+9.49). 전파 자체는 확인됨(기전 반증 안 됨).
- 실측 B: 그런데 **수익 예측력은 1개월 내 소진** — t-1 신호를 쓰면 t +2.555 → +0.60 (유지율 0.23).
- 모순: 전파가 3개월 지속되면 수익 예측력도 어느 정도 지속돼야 한다는 것이 path 의 함의인데 그렇지 않다.
  대안 해석 = 63일 창 중 **최신 개정분만** 가격 정보이고 stale 부분은 이미 반영됨.
- 처분: **승계분을 수정하지 않는다**(Charter 원칙 8). 대신 재설계 요청 항목으로 기록하고
  `alpha_package.hypothesis.inheritance_note` 에 승계 사실을 명시. path 재정식화는 alpha-hypothesis 소관.
- ★lag1 붕괴를 look-ahead 징후로 읽을 수 있는가: 구조적으로 배제된다(신호창 종점 = 신호월 거래일 월말,
  수익창 = (그 월말, +1개월] — 비중첩). 남은 축은 A5 의 sub-daily 가용성뿐이며 그건 별도로 대응했다.

## A4 [MEDIUM] "이익 3종 위의 증분" 프레이밍 과장 → **ACCEPT**

- 통제 3종 중 유의한 것은 **C02_EPS_Chg_1m 단독**(t +2.71). C01_SUE t **-0.04**, C04_ESBR t **+0.49**.
- 즉 이 설계에서 실질 통제는 1종이며, "3종 위"라는 서술은 통제의 강도를 과장한다.
- 처분: `alpha_package.primary.effective_control_note` 에 명기. 보고문에서도 "실질 통제 = C02 단독" 병기.
- ★단 이것이 "북이 C01/C04 를 안 쓴다"는 뜻은 아니다 — 북에서의 소비 형태(가중·결합·다른 horizon)는
  optimizer 소관이고 본 회귀는 등가중 z 선형 통제일 뿐이다. 이 구별을 넘어서 주장하지 않는다.

## A5 [MEDIUM→부분 해소] 컨센서스 same-day vintage → **PARTIAL, 실측으로 대응**

- registry 가 자인: `availability.rule = "T-1"` 인데 `known_discrepancy` = 코드 강제점은 `Date <= sig_d`
  (same-day 허용), 제공 시각 메타 부재로 당일값 사용 미검증.
- 정적검증기(`ast_verify.py`)는 이 33종에 보수 가용시점 `sig_date + 1d` 를 적용 ⇒ 최초 패키지가
  **FAIL_LOOKAHEAD 로 차단**됐다. ★후보 고유 결함이 아니다 — 같은 33종에 북 incumbent
  C01_SUE·C02_EPS_Chg_1m·C04_ESBR 이 전부 포함된다(registry 전수 실측).
- 대응: AST 에 `TS_LAG` 를 **선언만** 하는 것은 거짓 선언이므로 **실제로 늦춰서 재측정**했다.
  T+1 실행앵커(체결 = 익월 첫 거래일 종가 → 그 다음달 첫 거래일 종가, `align_signal_return_ym(off=+1,
  realized_month)`) ⇒ **t +2.305 · 유지율 0.90 · 282개월** 로 문턱 위 생존.
  통제도 동반 감소(C02 2.71→2.23)해 상대 구조는 보존.
- 잔여: 원천 컨센서스 `Date <= sig_d - 1` strict 재빌드 A/B 는 미실시 → FQ 등재.
- ★"영향 미미"·"관행적 허용" 류로 넘기지 않았음을 자기확인. 넘기는 대신 재측정했다.

## A6 [MEDIUM] cap-tier OTHER 87.9% 를 "소형 편중"으로 읽을 뻔함 → **REBUTTAL (자기 반박)**

- 실측: 보유 비중 MEGA 4.18% / MID 7.92% / OTHER 87.90%. gross 기여 연 MEGA 0.60% / MID 1.84% / OTHER 17.42%.
- 초안은 이를 "신호가 중·소형에 국소화"로 읽었으나 **대조가 없다**: tier 정의상 MEGA=시총 1-10위,
  MID=11-30위이므로 유니버스 342종 중 312종이 OTHER 다. top-25 를 무작위로 뽑아도 OTHER 가 압도한다.
- 처분: "편중" 주장 철회. `challenge_flags` 에 `[INFO] 편중 증거가 아님 — 대조 없는 해석 금지` 로 기록.
- 근거: [[feedback-sliding-window-before-bucket-claims]] (구간 주장 전 대조 의무) 계통.

## A7 [MEDIUM] turnover 11.74/yr — Implementation Discipline 기준선 초과 → **ACCEPT (기록)**

- canonical top-25 EW 기준 연 회전율 11.74 (잔차 표현 12.61). research_philosophy ⑥ 기준선 11.0/yr 초과.
- 처분: 기록만. 회전율 저감은 optimizer/construction 소관이며 alpha 단계에서 손대면 역할 경계 침범.

## A8 [MEDIUM] 나의 census 스크립트가 registry 조회에서 오답을 냈다 → **ACCEPT (자기 검거·정정)**

- 최초 census 가 "C14_Revenue_Surprise registry 미등재 / M26 미등재"를 출력했다. **오답이다.**
- 원인: registry 는 **팩터명이 곧 최상위 키**인 flat dict 인데, 내 `getid()` 가 entry 안의 `name` 필드
  (= "Revenue Surprise" 같은 표시명)를 먼저 집어 키와 다른 값을 반환했다.
- 정정: 키로 직접 조회하는 별도 스크립트(`np_registry_entries.R`)로 재측정 ⇒ **둘 다 등재 확인**
  (C 계열 19종 전부 등재). 제안서는 정정된 사실로 작성.
- 계통: "존재 검사로 정체 검사 대체" — [[feedback-identify-before-existence-check]].
  ★이번에도 **음성 주장("미등재")이 오답**이었다. 음성 비율 보고를 특히 의심하라는 규약이 재확인됨.

## A9 [FORMAT] 승계 falsification 의 형식 재배치 → **PARTIAL (고지)**

- `alpha_hypothesis.json` 은 `falsification` 을 object(`observable`/`field_dictionary_refs`/`reject_if`)로
  담았으나 schema·`ast_spec_gate` 는 `field` 참조를 갖는 **배열**을 요구한다(불일치 시 block).
- 처분: 문자열 내용은 **그대로 보존**하고 배열 원소로 재배치만 했다(`observable`/`reject_if` 원문 유지 +
  `inherited_refs` 로 원 refs 보존). 의미 재작성 아님 — `hypothesis.inheritance_note` 에 명시.
- 이 형식 불일치 자체는 alpha-hypothesis 산출 계약의 결함이므로 재설계 요청 항목에 포함.

## A10 [PROCESS] AST 리프 선언형 오류 2건 → **ACCEPT (게이트가 검거)**

1. `toJSON(auto_unbox=TRUE)` 가 길이-1 배열을 스칼라로 접어 `regime_scope.weakens_or_reverses_in` 이
   "빈 배열"로 읽혀 게이트 block. → `as.list()` 로 수정.
2. 리프를 `{"leaf":"M26_Revenue_Mom"}` 로 썼으나 `ast_verify` 계약은 `{"leaf":"REGISTRY","factor":...}`.
   → FAIL_CONTRACT advisory 수신 후 수정.
- ★두 건 모두 **내가 스스로 발견한 게 아니라 게이트가 잡았다.** 게이트를 우회하지 않고 실제로 통과시킨 것이
  본 라운드의 검증 자산이다.

---

## 합리화 자기검사 (auto RE-VIEW 트리거)

금칙 표현 목록은 `.claude/rules/pit.md` "금지 표현" 절 5종 + `answer-principles.md` "회피 표현 grep" 절을
정본으로 참조한다(본 문서는 목록을 재기입하지 않는다 — 재기입 자체가 탐지기를 오발화시킨다).
자체 점검 결과 **전 항목 미사용 확인**.
- A5 에서 same-day vintage 를 무해하다고 넘길 수 있었으나 넘기지 않고 T+1 재측정으로 대응.
- A2 에서 부기간 하락을 "감쇠"로 단정할 수 있었으나 검정력 계산으로 자기 기각.
- A6 에서 tier 비중을 "편중"으로 읽을 수 있었으나 대조 부재를 확인하고 철회.
- VIF 설명에 "관행 문턱"이라는 단어가 있으나 "관행 문턱이 아니라 진단 기준선"이라고 **명시적으로 부정**한
  용법이므로 회피 표현이 아님.

## Q-Lead escalate 판정

- HIGH severity 건수 = **3** (A1/A2/A3) < 5 → 자동 escalate 트리거 미발화.
- AX axiom hard FAIL = 0. AX-001 은 detected_family 가 defense 가 아니어서 비적용(scope 선언 기록).
- PIT C1(lockbox·lookahead) 위반 = 없음. A5 의 정적검증 FAIL_LOOKAHEAD 는 **재측정으로 해소**했고
  최종 게이트 `{}` 통과 + 위반 주입 테스트로 게이트의 차단 실효 확인.
- ⇒ **escalate 불요**. 단 A3(가설 path 재정식화)·A9(falsification 형식 계약)는 alpha-hypothesis
  재설계 요청 항목으로 Q-Lead 에 전달.

## AX-008 Verification Triangulation

- source 1 = Self-Adversarial (본 문서) — 수행.
- source 2 = 기계 게이트 `ast_spec_gate.sh` + `ast_verify.py` 정적검증 — 통과(위반 주입 대조 포함).
- source 3 = forge — 미수행(본 라운드는 재료 자격까지, forge 사이클 미소비).
- ⇒ 3-source 중 2 PASS 충족.
