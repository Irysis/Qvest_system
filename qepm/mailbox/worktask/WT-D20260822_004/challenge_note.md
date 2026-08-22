# challenge_note — WT-D20260822_004 (FQ-244 결합 규칙 마디)

**작성**: alpha-research · 2026-08-22 · finalize 직전 Self-Adversarial Challenge (v8.2, Codex Round 대체)
**대상**: `alpha_package.json` + `stage_artifacts/WT-D20260822_004/alpha_validation.json`
**규약**: Charter §8 No Silent Override — 승계분 수정 금지, 결함은 기록 + 재설계 요청. 합리화 어휘 자가스캔 포함.

---

## 0. 라운드 1급 결과 (검증 대상)

| 항목 | 값 | metric_type |
|---|---|---|
| 대조 C0 PORT_t (IKS200 cap-w) | **0.94741072** (FQ-237 공표 재현, Δ −4.19e-09) | canonical_screen |
| C1 rank 평균 − C0 | **−0.412 %p/yr · t −0.236 · CI95 [−3.84, +3.01]** | canonical_screen |
| C2 winsor-z − C0 | **−0.667 %p/yr · t −0.607 · CI95 [−2.82, +1.49]** | canonical_screen |
| C3 max-z − C0 (음성 대조) | **−3.976 %p/yr · t −2.077** | canonical_screen |
| MATERIAL (사전고정) | 8.2228 %p/yr | 사전등록 |
| 마디 여유폭 ORACLE_K | PORT_t **4.647** · paired **+13.69 %p/yr (t 4.29)** | canonical_screen (사후 진단) |

---

## 1. 자기 비평 7건 — 분류와 처리

### C-1 [HIGH] "C1 의 null 은 처치가 포트폴리오를 거의 안 바꿔서 나온 것 아닌가" → **REBUTTAL (실측)**

가장 날카로운 반론이었고, 제기 시점에 **나는 답을 갖고 있지 않았다**(스코어 rank 상관 0.911 만 알았고 top-25 명단 겹침을 재지 않았다). 근거 없이 방어하는 대신 재측정했다 (`p7_adversarial.R`).

| 대조 | top-25 Jaccard 중앙 | 월 교체 종목 |
|---|---|---|
| C0 vs C1 | 0.4706 | **9.0 / 25** |
| C0 vs C2 | 0.7857 | 3.0 / 25 |
| C0 vs C3 | 0.3889 | 11.0 / 25 |

C1 은 매월 25종 중 **9종을 갈아치운다**. 포트폴리오의 36%를 바꾸고 성과 차이가 −0.41%p/yr(t −0.24)라는 것은 처치 무력이 아니라 **실질 개입에 대한 무반응**이다. C1 의 null 은 강하다.
동시에 이 측정이 **C2 를 죽였다** — 3종 교체는 개입이라 부르기 어렵다(→ C-3).

### C-2 [HIGH] "승계 기전이 반증됐는데 그 위에서 처치 성과를 계속 쟀다" → **PARTIAL**

인정: R1b(전이-음성 집중 미성립: solo advocate standalone PORT_t 중앙 −0.280 > 풀 중앙 −0.348)와 R3(연결 절단: solo 편입이 consensus 대비 오히려 연 +1.48%p, t +0.25)가 **성과 측정 전에** 승계 기전의 손실 경로를 부정했다. 사전등록이 R3 를 STOP 이 아니라 "귀속 이전" 으로 규정했으므로 절차 위반은 아니지만, 이 순서 때문에 primary null 의 정보량이 줄어든 것은 사실이다.

**처리**: ① 결론을 "비-ML 결합 규칙은 무익"으로 일반화하지 않는다. 실측이 지지하는 문장은 **"성분 영향력 유계화 계열의 사전고정 2종은 전이를 개선하지 못한다"** 이다. ② 승계 자구는 수정하지 않고(Charter §8) 불일치를 `challenge_flags` + `falsification_measured` 에 기록했다. ③ alpha-hypothesis 앞으로 **재설계 요청** — FQ-116 설계 원칙 P1~P4 의 유효 범위가 "고정 5팩터 풀" 인지 "매월 재선별 K=5 풀" 까지인지가 미확정이다(NP4).

### C-3 [HIGH] "C2 를 co-primary 로 세운 것은 설계 결함" → **ACCEPT**

전면 인정. `clip(±2.0)` 이 실제로 건드린 관측은 **전체 셀의 3.4%**(중앙, `p7_adversarial.R` §3)다. 월별 max|z| 중앙이 4.08 이므로 꼬리는 존재하지만 ±2 밖 질량이 얇다. 그 결과 C2 는 매개변수를 못 움직였고(solo-advocate 비율 0.938배 = 사전등록 R2 미통과 `NO_MEDIATOR_MOVEMENT`), 명단도 3종만 바꿨다.

**처리**: ① C2 의 null 을 C1 의 null 과 **같은 무게로 보고하지 않는다** — `results.coprimary.C2.strength` 에 "약한 null, 기전 반증 증거로 부적격" 을 명시했다. ② 사전등록 시점에 clip 비율을 확인했어야 했다는 절차 결함을 기록한다(용량-반응 확인 없이 단일점을 고정한 대가). ③ NP3 로 이관.

### C-4 [HIGH] "사전등록 양성 대조가 실패했는데 사후에 다른 눈금으로 갈아탔다" → **REBUTTAL (부분 인정 포함)**

`PREREG.json::controls.positive_control_window_reachability` 는 **C0_LEAK1 과 ORACLE_FWD 를 동시에** 선언했고, 창-도달가능성 병기 의무는 그 절에서 **ORACLE_FWD 소관**으로 명시돼 있다. 따라서 문턱 교체가 아니라 사전 선언된 역할 분담이다.

인정하는 부분: C0_LEAK1 은 통과 조건(t ≥ +2.0)을 **미통과**했다(t +0.667, +1.00%p/yr). 이 실패를 숨기지 않고 `alpha_validation.controls` · `alpha_package.results.controls` · `challenge_flags` 3곳에 기록했다. 원인 진단 — z vintage 를 1개월 앞당기는 것은 *수익*을 누출하는 개입이 아니라 팩터값을 갱신하는 개입이라 양성 대조로서 약하다. 다만 vintage 축이 예측 방향으로 단조(LAG1 −2.44 / C0 0 / LEAK1 +1.00 %p/yr, 스팬 3.44%p)라 하네스가 정보량에 반응함 자체는 실증된다.

### C-5 [HIGH] "ORACLE_K 는 사전등록 밖 사후 진단인데 ⑤ 판정의 핵심 근거다" → **PARTIAL**

인정: `ORACLE_K` 는 사전등록 arm 이 아니다. 다만 ① arm 선택·챔피언 선발에 쓰이지 않았고 ② 어떤 판정 라벨도 바꾸지 않으며 ③ 사전등록이 이미 선언한 ORACLE_FWD(창-도달가능성 눈금)의 **마디-국소화판**이다.

**처리**: `label = "post_hoc_diagnostic_not_preregistered_not_judged"` 를 산출물에 박아 넣고, 게이트 근거가 아니라 **다음 라운드 설계 입력**으로만 쓴다. 추가 한계 명시: ORACLE_K 는 {K개 중 하나 고르기} 족의 상한이지 모든 볼록결합의 상한이 아니다 — 상한 자체가 과소일 수 있으나, 그 방향은 "여유폭 존재" 결론에 **보수적**이다.

### C-6 [MEDIUM] "MATERIAL 8.22 %p/yr 가 너무 높아 powered null 이 쉽게 나온다" → **REBUTTAL (정량)**

문턱 민감도를 실측했다:

| arm | CI95 상단 | 8.2228 배제 | 4.1114 배제 | 3.0 배제 | 2.0 배제 |
|---|---|---|---|---|---|
| C1 | +3.0138 | O | O | **X** | X |
| C2 | +1.4872 | O | O | O | O |

문턱을 **절반(4.11)으로 낮춰도 두 arm 모두 powered null 이 유지된다.** 정직한 한계: C1 은 +3.0%p/yr 수준의 효과까지는 배제하지 못한다 — 이 사실을 숨기지 않고 병기한다. 결합 마디가 **연 3%p 미만의 미세 개선**을 줄 가능성은 열려 있으나, 그 크기로는 벽(8.22%p 필요)에 도달하지 못하므로 라운드 결론은 불변이다.

### C-7 [MEDIUM] "유니버스 결함 창(2015-07 이전 88개월)을 포함한 전체 창을 primary 로 썼다" → **REBUTTAL (정량)**

청정창(2015-07~, n=133) 단독 재판정을 실측했다: C1 관측 **+0.975 %p/yr (t +0.483)**, MDE(t=2.0) 4.039 %p/yr / C2 관측 **+0.672 %p/yr (t +0.546)**, MDE 2.464 %p/yr. 두 MDE 모두 MATERIAL 8.22 보다 작으므로 **청정창 단독으로도 powered null 이다**. 부호는 오염창(음수)에서 청정창(양수)으로 뒤집히지만 어느 쪽도 유의하지 않다. `universe_exit_unrecorded_pre201512` 의 편향 방향이 **하방/중립**(생존자 편향 아님)이라는 승계 사실과 정합 — 오염창 포함이 처치를 부당하게 불리하게 만들지 않았다.

---

## 2. 합리화 자가스캔 (금칙 표현)

`answer-principles.md` 회피 표현 목록(5종 — 효과 축소형 2 / 관행 원용형 1 / 보수성 원용형 1 / 결과 동일 주장형 1, 및 사전반영 주장형)으로 본 note + 산출물 2종을 자가 점검했다. 금칙어를 여기 재타이핑하지 않는다(리터럴 인용 자체가 탐지기를 발화시키므로 유형명으로 지시한다).

- 전 유형 **사용 0건**.
- 근접 표현 점검: C-6 에서 "결론 불변" 을 썼으나 이는 **정량 근거(문턱 민감도 표)를 제시한 뒤의 서술**이고 근거 없는 안심이 아니다. C-7 의 "정합" 도 실측 수치 병기 후 사용.
- **auto RE-VIEW 발화 0건.** 단 C-1 은 자가스캔 이전에 이미 "근거 없이 방어할 뻔한" 지점이었고, 재측정으로 해소했음을 기록한다(스캔이 아니라 측정이 막았다).

---

## 3. Q-Lead escalate trigger 점검

| trigger | 문턱 | 실측 | 발화 |
|---|---|---|---|
| HIGH severity concern | ≥ 5 | **4** (C-1/C-2/C-4/C-5) | 미발화 |
| AX axiom hard FAIL | ≥ 3 | 0 | 미발화 |
| PIT C1 (lockbox·lookahead) 위반 | ≥ 1 | 0 (LAG1 스트레스 붕괴 없음, self_pit_check verdict=clean) | 미발화 |

**자동 escalate 미발화.** 단 C-2 의 재설계 요청(FQ-116 원칙 유효범위)은 Q-Lead 경유로 alpha-hypothesis 에 전달되어야 한다.

## 4. AX-008 Verification Triangulation

- **Self-Adversarial**: 본 문서 (7건, ACCEPT 1 / PARTIAL 2 / REBUTTAL 4 — 그중 3건은 신규 실측으로 뒷받침)
- **Forge**: 미수행 — `transition_gates_evaluated.decision = NO_TRANSITION`(cond4 미충족, 제출 후보 없음). forge-authoritative 수치 부재를 명시하며, 따라서 **graduation HARD 3종 판정을 주장하지 않는다.**
- **Architect**: 미호출.

⇒ 3-source 중 **1 PASS** — AX-008 의 2/3 요건 미충족. **이는 결함이 아니라 정합**: 본 라운드는 자본 후보를 제출하지 않으므로 graduation triangulation 대상이 아니다. 자본 경로에 오르는 순간 forge + architect 2 source 가 추가로 요구된다는 사실을 여기 명시해 둔다.

---

## 5. 승계 결함 — 재설계 요청 (Charter §8, 수정하지 않고 기록)

`alpha_hypothesis.json` 의 승계 기전 중 **두 조각이 본 팩터 풀로 수송되지 않았다**:

1. `mechanism.agent` 가 지목한 "전이-음성·IC-양성 팩터(D03_EWMA·Q01_EB·V06_EB)의 극단 z" — 본 풀(매월 재선별 K=5, 103종 등장)에서 solo-advocate 의 standalone PORT_t 중앙은 **−0.280 으로 풀 중앙 −0.348 보다 높다**. 전이-음성 집중이 없다.
2. `mechanism.path` 의 "합의-편입 종목이 전이-양성 평균 신호와 정합" — solo 편입이 consensus 편입보다 **오히려 연 +1.48%p 더 벌었다**(t +0.25, 무차별).

기전의 **구조 전제**(R1a solo-advocate 64% · R5 첨도 이질 IQR 6.94)는 참이고 **손실 전제**만 거짓이다. 자구는 그대로 두고 재설계 요청만 발행한다 — 요청 내용은 NP4(FQ-116 설계 원칙 P1~P4 의 유효 풀 범위 확정).

---

## 6. ★병렬 세션 산출물 발견 — 정합/불일치 보고 (2026-08-22 16:30, alpha-research)

본 라운드 산출 도중 **내가 쓰지 않은 파일**이 같은 WT 메일박스에 나타났다. 되돌리지 않고 대조 결과만 기록한다(과거 사례: 이명 복제·정본 변형).

| 파일 | 작성 | 상태 |
|---|---|---|
| `challenge_note_alpha.md` (13,336B, 16:21) | 내 세션 아님 | 내용 유효 — 본 note 와 **상보적**(A1 문턱 종속성 · A2 오라클 과대평가 축을 별도로 다룸). 보존 권고. |
| `qepm/.../alpha_validation.json` (24,003B, 16:28) | 내 세션 아님 | ★**같은 이름의 분기 사본**. 내 정본은 `stage_artifacts/WT-D20260822_004/alpha_validation.json` (26,031B). 두 파일 내용이 다르다. |
| `status.json` phase=ALPHA_DONE (16:30) | 내 세션 아님 | 판정·next_probe 라벨이 내 산출과 일치. 충돌 없음. |
| `stage_artifacts/.../p6_alpha_package.R` | 내 실행 **후** 수정됨 | `verdict` 필드에 라운드 판정을 넣는 변경. 의도는 옳으나 schema ast_v1.1 조건부 enum 위반이라 **P9 에서 `verdict=designed` + `round_verdict` 분리로 재수리**했다. |

### 불일치 2건 (하류가 오독하지 않도록 명시)

1. **`verdict` 필드 의미 충돌** — 메일박스 `alpha_validation.json` 사본은 `verdict = "NON_ML_COMBINATION_POWERED_NULL"` 이고 `round_verdict` 가 없다. `alpha_package.json` 정본은 `verdict = "designed"`(AST 설계 판정, schema enum) + `round_verdict = "NON_ML_COMBINATION_POWERED_NULL"`(라운드 성과 판정)로 **두 개념을 분리**했다. 판정을 읽을 때는 `round_verdict` 를 볼 것.
2. **`challenge_note_alpha.md` A1 의 수치 오기** — "ORACLE_K node headroom PORT_t 4.29 (paired t +4.29)" 는 **두 값을 뒤섞었다**. 실측은 **PORT_t 4.6470** / **paired t 4.2897** 로 서로 다른 양이다(`p4_verdict.rds$BAS` · `$PRI`). 그 절의 논증(창-도달가능성이 MATERIAL 문턱과 독립적으로 성립)은 정정 후에도 유지된다 — 4.647 이 벽 2.95 를 넘는다는 사실이 근거이므로 방향 불변.

### 처분

파일 삭제·되돌림 없음. Q-Lead 에게 **정본 지정**을 요청한다 — 권고: `alpha_package.json`(메일박스) + `alpha_validation.json`(**stage_artifacts** 판)을 정본으로 하고, 메일박스의 `alpha_validation.json` 사본은 stage 판으로 동기화하거나 이름을 달리할 것. 같은 이름 두 사본이 서로 다른 내용을 담은 채 남는 상태가 가장 나쁘다.
