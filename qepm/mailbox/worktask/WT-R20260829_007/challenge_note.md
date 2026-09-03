# challenge_note.md — WT-R20260829_007 (alpha-research)

**Self-Adversarial Challenge** (v8.2 규약 · Charter §8 No Silent Override).
발행 직전 자기 적대검증. 각 concern = ACCEPT / PARTIAL / REBUTTAL 분류 + 근거 + 합리화 자기검증.
정량 근거는 진술이 아니라 **재도출**했다 → `stage_artifacts/WT_R20260829_007/s11_adversarial.json`.

---

## W1 — "PORT_t +0.929 · β-통제 α +6.99%/yr (t 1.928) 을 '유망' 으로 읽으려는 유혹"

**분류: ACCEPT**

무신호 대조를 짓지 않았다(도훈 지시 ① — 세션 차원에서 대조 arm 금지). measurement-graduation §3 의
실측 근거대로 **제약형 롱온리 top-N 은 형태 자체가 대형주 노출을 담으므로** '벤치를 이겼다' 만으로
신호 기여가 증명되지 않는다. DFA 아크 R41 에서 게이트 준수 팔 T3 이 무신호 대조와 구별 불가(+0.06%/yr,
NW-t 0.028)였던 전례가 정확히 이 자리다.

**처리**: `diagnostics.canonical_port_t_note` 에 "신호 기여는 증명되지 않았다"를 명시 기입 +
challenge_flags 에 동일 문구. 어떤 서술에서도 이 값을 알파 존재의 근거로 쓰지 않았다.

---

## W2 — "strict-PIT 판이 same-close 판보다 **좋게** 나왔다. 결과를 보고 좋은 사양을 골랐나"

**분류: PARTIAL**

인정할 사실: 발견 순서는 ①same-close 측정 → ②`ast_verify.py` FAIL_LOOKAHEAD → ③strict 측정 →
④strict 발행이다. 즉 **숫자를 본 뒤에 사양이 확정됐다**. 이 순서는 산출물에 그대로 기록했다.

반론 근거: 선택 규칙이 성과가 아니라 **외부 규칙**에서 나왔다. `06_Registry/ast_field_map_v0.json` 의
`A1_RAWDATA_OHLCVS_daily` 가용성 규칙 't1' 과 `request.json::data_lag_rules.price = "t-1 close"` 는
이 라운드 이전에 존재하며 내가 쓴 것이 아니다. strict 가 **나빴더라도** 같은 규칙이 strict 를 강제한다.
그리고 실제로 strict 가 더 좋았으므로, 만약 내가 성과로 골랐다면 same-close 를 골랐어야 한다 —
관행판이 디플레이션 쪽(상대 −31.2%)이라 '더 좋은 쪽을 골랐다' 는 서사가 데이터와 맞지 않는다.

**처리**: `production_candidate.strict_pit_ab` 에 양쪽 전량 기록(PORT_t · α · TO · 보유 겹침 78.5%),
`published_spec` 필드에 선택 규칙의 출처를 명시. 두 사양의 period_returns 를 둘 다 파일로 남겼다.

---

## W3 — "F3 의 t −35 는 발견이 아니라 기계적 항등 아닌가"

**분류: ACCEPT (부분 인정 아님 — 전면 인정)**

개인 순매수는 기관+외국인+기타법인의 **제로섬 거울상**이다. 실측에서도 정확히 거울상이 나왔다
(개인 −0.511%/월, 기관 +0.303%, 외국인 +0.214%). 따라서 "개인이 편향 주체" 를 이 관측이 **식별하지 않는다**.
또 t 의 절댓값이 큰 이유는 이것이 수익 청구가 아니라 **지속적인 단면 구조**이기 때문이다.

**처리**: `F3_agent_evidence_individual_flow.identification_caveat` 에 제로섬 거울상·비식별을 명시.
verdict 문구를 "GH2004 의 기전 서술과 **양립**한다" 로 제한하고 "개인이 주체임을 실증했다" 는 표현을 쓰지 않았다.
데이터 스테일(A6/A7 수동 export, ~22일 지연, 종점 2026-07) 도 병기. 신호 경로 미진입.

---

## W4 — "선행 런 t +3.199 재귀속에서 U1 은 +1.458 이지 +3.199 가 아니다. 과대주장 아닌가"

**분류: PARTIAL**

인정: 유니버스 축은 **부호 패턴을 재현**했지 크기를 완전 재현하지 못했다.
- 선행 보고: λ +0.00494 · t(Score) +3.199 · t(Size) −3.225 · t(Mom) −1.886 · 월평균 N 1397.7
- U1 (전 시장 + 유동성): λ +0.00309 · t(Score) +1.458 · t(Size) −2.362 · t(Mom) **−3.078** · N중앙 1457

Size·Mom 의 **부호가 U1 에서만 맞는다** — mandate 유니버스판(U3)에서는 t(Mom) 이 +1.778 로 **뒤집힌다**.
잔여 격차의 후보(미검정): 선행 하네스 내부의 정확한 표본 기간, `frollapply` NA 전파로 인한
252일 완전이력 요구, LiqPass 산출 세부, Period_Ret 의 exec_d~next_exec 경계.

**처리**: 산출물에서 주장을 두 층으로 분리했다 — (a) **확정 주장**: mandate 유니버스에서 같은 사양·정의·
NW 공식으로 재면 t(Score) = **−0.090** 이다(U3). 이건 재현 문제가 아니라 직접 측정이다.
(b) **정황 주장**: 양(+) t 는 전 시장 표본에서 산다(U1 t +1.458, 부호 패턴 일치). 크기 잔여는 미해명으로 남긴다.
정의 축(Spearman 0.9995)·사양 축(t +0.032/+0.050)·수익경로 축(t −0.393)은 각각 기각으로 기록.

---

## W5 — "n_trials = 1 / selection_type = chain 인데 실제로는 사양을 수십 개 돌렸다. sweep 아닌가"

**분류: REBUTTAL**

sweep 판별 기준은 파라미터 수가 아니라 **selection operator** 다(measurement-graduation §3,
메모리 `feedback-sweep-is-about-what-you-select-on-not-param-count`). 본 라운드에는 성과 argmax 가 없다:
- 발행 후보의 신호·구성은 사전등록(`alpha_hypothesis.json` + request)에서 고정 — 근접도 top-25.
- 두 사양(same-close / strict) 중 선택은 **PIT 규칙**이 강제(W2 참조).
- F1 의 4변형(fh252/fh12m × pooled/mktint)은 전부 보고했고 **판정이 전부 동일**(FHH t +0.85~+0.99 비유의).
  1급 사양은 선행 런과의 규약 정합을 이유로 사전 지정(M06 252d · 시장-내)했다.
- F4 사다리 6단·F2 gap 4개·재귀속 격자 8칸은 전부 진단이며, 어느 것도 발행 후보를 고르는 데 쓰이지 않았다.

DSR 은 그럼에도 진단으로 산출·기록했다(0.862). 게이트로 쓰지 않았다.

---

## W6 — "oos_retention −0.383 · 2020~2026 활성 −4.71%/yr 인데 체인에 넘기는 건 하류 낭비 아닌가"

**분류: REBUTTAL**

도훈 지시 ②가 명시한다 — 어떤 음성 판정도 체인을 멈추지 않으며, `alpha_package.json` 은
risk → optimizer → forge 로 넘어가 essence 등급을 받으므로 **음성이어도 완전한 형태**여야 한다.
따라서 α̂ 347종 결측 0 · confidence 347종 결측 0 · 유니버스 선언 · 시점 규약 선언을 갖춰 발행했고,
`handoff_to_risk.known_weaknesses_for_downstream` 에 하류가 알아야 할 약점 4건을 명시했다.

---

## W7 — "FF3 α +15.59%/yr (t 3.178) 인데 mandate 벤치 대비 활성은 +3.9%/yr. 팩터 캐시 탓으로 돌린 건 편의적 아닌가"

**분류: ACCEPT — ★자기적대검증이 초판을 반박했다. 초판 진술을 철회한다.**

초판은 "in-house MKT 팩터가 mandate 벤치와 다른 것을 잰다" 고 적었다. **그 진술이 틀렸다.**
진짜 원인은 팩터 캐시가 아니라 내가 `run_multifactor_regression()` 에 넘긴 **시계열의 날짜 라벨**이었다.
`period_returns$date` 는 **신호월 말**이고 수익은 **다음 캘린더월**에 실현되므로, 팩터를 신호월 라벨로
붙이면 1개월 어긋난다.

| | cor(bm_excess, MKT) | β | α(연) | t(α) | adjR² |
|---|---|---|---|---|---|
| 신호월 라벨(어긋남) | **−0.004** | −0.004 | +11.53% | +2.465 | −0.004 |
| 홀딩월 라벨(정렬) | **+0.968** | **0.943** | −0.11% | −0.099 | **0.937** |

정렬하면 in-house MKT 는 mandate 벤치와 **사실상 같은 것을 잰다**. 전략 알파도 바뀐다:

| | FF3 α | t | Carhart4 α | t | WML 로딩 | adjR²(FF3) |
|---|---|---|---|---|---|---|
| 신호월 라벨 | +15.59% | 3.178 | +14.83% | 3.042 | — | 0.016 |
| **홀딩월 라벨(발행값)** | **+7.76%** | **2.023** | **+3.87%** | **1.225** | **0.473** | **0.509** |

**따라서 초판의 두 번째 진술 — "선행 런의 FF3→Carhart4 소멸(3.46→0.71)이 본 후보에서 재현되지 않는다" —
도 철회한다. 재현된다**: 7.76 → 3.87 로 모멘텀 팩터가 알파의 절반을 흡수한다(WML 로딩 0.473).
이건 H5 위험이 실현된 것이고, 초판은 정렬 아티팩트 때문에 그것을 못 볼 뻔했다.

**처리**: `diagnostics.ff3_alpha_*` 를 정렬판으로 교체하고 어긋남판을 `*_misaligned_label` 로 병기 보존.
`multifactor_misalignment_record` 에 기전 기록. 호출 규약(넘기는 시계열의 날짜 라벨)을 하네스 수리 대상으로
등재 권고 — 본 에이전트는 계약 파일을 고치지 않는다(역할 경계).

---

## W8 — "회전율 1523%/yr 을 '급소' 라고 했는데 α 는 +6.99%/yr 다. 정말 구속하나"

**분류: PARTIAL — ★자기적대검증이 초판 진술을 정정했다.**

정량 재도출(S11 W8):

| 비용(편도) | 활성수익(연) | NW-t | net SR |
|---|---|---|---|
| 0 bps | +6.20% | +1.471 | +0.386 |
| 15 bps (현행) | +3.91% | +0.929 | +0.244 |
| 40 bps | +0.10% | +0.024 | +0.006 |

- 비용 잠식폭 = 연 **2.29%p** = gross 활성수익의 **36.9%** — 실질 부담은 사실이다.
- 그러나 **손익분기 편도 비용 = 40.7 bps** 로 현행 15bps 의 **2.7배**다.
- 결정적으로 **비용을 0 으로 놓아도 활성수익 NW-t 는 +1.471** 이다.

⇒ 이 후보를 죽이는 것은 비용이 아니라 **신호**다. 초판의 "15bps 편도 비용이 이 축의 급소" 를
PARTIAL 로 정정: 비용은 실질 부담이되 **구속 제약이 아니다**.

**처리**: `turnover_reading` 전면 재작성 + `cost_binding_check` 필드로 민감도표 첨부 + challenge_flags 정정.

---

## W9 — "F2·F3 가 기전을 지지했다. 이걸 성과 청구로 승격하려는 유혹"

**분류: ACCEPT (선제 차단)**

F2(장기 무반전)와 F3(신고가 부근 개인 순매도)이 둘 다 GH2004/GK2001 예측대로 나온 것은 사실이다.
그러나 설계가 못박은 대로 **F2/F3 은 부수 관측이며 성과 판정이 아니다**. 실제로 F1 의 롱온리 반쪽은
비유의하고(FHH t +0.910) 소비면 전이도 실패했다(PORT_t 0.929 · oos_retention −0.383).

**처리**: 각 verdict 의 `tier` 를 명시(`mechanism_discriminant` / `mechanism_agent_evidence`),
`envelope_applicability = NOT_APPLICABLE` 라벨, challenge_flags 에
"기전 지문은 살아 있는데 알파가 없다 — 기전의 존재는 수확 가능성을 함의하지 않는다" 를 기입.

---

## 합리화 어휘 자기검증 (auto RE-VIEW 트리거)

금지 표현 스캔 — "미미 / 관행적 (허용) / 실무적 / 보수적이면 OK / 대부분 결과 동일 /
이미 반영되어 있었을 것 / 백테스트 기간이 충분히 길어서 상쇄":
**산출물 3종(alpha_package.json · alpha_validation.json · 본 노트) 사용 0건. auto RE-VIEW 미발동.**

특히 W2(strict-PIT)에서 "차이가 미미하다" 로 넘어갈 수 있었으나 그러지 않고 **양쪽을 다 측정**했고,
W7/W8 에서는 자기 진술 2건을 **철회·정정**했다.

---

## Q-Lead escalate 트리거 점검

| 트리거 | 상태 |
|---|---|
| HIGH severity ≥ 5 | 미발동 (HIGH = W1·W7 2건. W4·W8 은 PARTIAL, W3·W9 는 ACCEPT-경미) |
| AX axiom hard FAIL ≥ 3 | 미발동 |
| PIT C1 (lookahead) 위반 | **미발동** — `ast_verify.py` 최종 PASS(순회 리프 2 · 연산자 7 · violations 0 · max_avail_ts 2026-08-28 ≤ decision_ts 2026-08-28). `detect_lookahead` 발화 2건은 보고경로 사후 요약통계(C1 `sd()*sqrt()`)로 판독 — s7_pit.json `adjudication` 참조 |

**escalate 불요.** 단 하네스 수리 대상 3건을 기록으로 남긴다:
1. `run_multifactor_regression()` 호출 규약 — 넘기는 시계열의 날짜 라벨(신호월 vs 홀딩월). 정렬 하나로 FF3 α 가 15.59 → 7.76 으로 바뀐다.
2. AST 방언 분열 ① 나눗셈 연산자명 — schema.json `DIV_GUARD` vs ast_verify.py `DIV`.
3. AST 방언 분열 ② `args` 내 스칼라 — schema 는 number 를 명시 허용하나 검증기는 "노드 형상 오류(비 dict): 252" 로 FAIL_CONTRACT.
   (본 라운드는 ①을 log-sub 단조 동치 표기로, ②를 args/children 이중 적재로 회피했고 두 분열을 probe 로 병기 실증했다.)

## 승계분 무수정 확인 (Charter 원칙 8)

`alpha_hypothesis.json` 의 `mechanism`(agent/friction/path) · `falsification`(F1~F6 조건문) ·
`regime_scope` 를 **재작성하지 않았다**. `alpha_package.json` 의 `hypothesis.mechanism` /
`hypothesis.regime_scope` 는 승계 객체를 그대로 옮겨 담았고, `falsification` 은 **조건을 바꾸지 않고**
각 조건에 실측 결과만 덧붙였다. 설계 에이전트의 착수 비권고(`verdict_qualifier`)도 삭제하지 않고
`mandatory_prior_run_disclosure` 와 함께 기록했다.

설계의 2급(cell4 대비 증분)은 도훈 지시 ③ 으로 **취소**됐다 — 나는 그 조건을 삭제한 것이 아니라
**수행하지 않았고 그 사실을 기록**했다(검정력 앵커 B 는 산출·보고만).
