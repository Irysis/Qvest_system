# challenge_note — WT-D20260802_001 / FQ-073 (alpha-research)

**규약**: Charter §8 No Silent Override + v8.2 Self-Adversarial Challenge (AX-008 3-source 중 1).
**절차**: finalize 직전 스스로 적대 검증 → 각 concern 을 ACCEPT / PARTIAL / REBUTTAL 로 분류 →
근거 기록 → 자기합리화 어휘 자동 검출.
**작성**: 2026-08-02 · alpha-research agent (자체)

---

## 0. 자기합리화 auto-detection 결과

스캔 대상 = `answer-principles.md` 회피표현 조항 + `pit.md` 금지표현 조항이 열거한 어휘군
(영향 축소형·관행 원용형·사전반영 주장형). 정본 목록은 두 규범 파일이며 여기서 재수록하지 않는다.

- **1차 초안에서 1건 적발**: BM_Ret 오염 통지를 받고 "112개월 중 1개월뿐이라 결과가 바뀌지 않는다" 는
  취지의 *영향 축소형* 서술로 넘어가려 했다. 근거 없는 규모 주장이므로 auto RE-VIEW 발동.
  → 실측으로 대체: `col_select` 확인 결과 **BM_Ret 컬럼을 애초에 로드하지 않았고**(미접촉),
  벤치 basis 대조도 내 산출 −22.76% vs 정본 benchmark.parquet −23.63% vs 오염 RAWDATA −17.70% 로
  **오염판과 무관함을 수치로 확정**했다. 정답은 "규모가 작다" 가 아니라 "경로가 닿지 않았다" 였다.
- 그 외 최종본에서 회피표현 사용 0건 — 모든 규모 주장에 실측치를 병기했다.

> ⚠ 도구 관측: `rationalization_detector` 훅은 어휘의 **사용(use)과 언급(mention)** 을 구분하지 못한다.
> 본 절이 금칙어를 *탐지 대상으로 나열*했을 때 훅이 위반으로 발화했다(1차 초안). 오탐이나, 규범상
> 표현 제거가 정당하므로 재수록을 없앴다. 검출기 개선 제안은 별건(본 라운드 범위 밖).

---

## 1. [ACCEPT] "상한(upper bound) 논증" 이 내가 주장한 만큼 강하지 않다

**자기 비평**: 나는 "측정 lane 이 look-ahead 를 포함하므로 상한이고, 상한이 음수면 clean lane 도 음수"
라고 쓰려 했다. 이는 틀렸다. 노출 3종은 성질이 다르다.

| 노출 | 방향 |
|---|---|
| survivorship (현재 상장사 풀) | favorable bias — 상한 논증 성립 |
| customs revised vintage | favorable bias(정정 확정분 반영) — 성립 |
| **crosswalk static_current (2025 제품믹스 → 2015 귀속)** | **attenuating noise** — 성립 안 함 |

사업구성이 바뀐 기업에 틀린 HS 버킷을 붙이는 것은 *유리한 편향*이 아니라 *잡음*이다. 잡음은 신호를
0 쪽으로 끌어내리지 음수로 밀지 않는다. 따라서 "상한 음수 ⟹ clean 음수" 는 **강한 신호에 대해서만**
성립하고, 약한 신호는 배제하지 못한다.

**처리**: ACCEPT. alpha_package `challenge_flags` CF-02 로 명시하고, verdict 문구를
"clean lane 도 실패한다" → "강한 신호는 배제되나 약한 신호는 미배제" 로 하향 수정했다.
next_probe 1(vintage 크로스워크 구축)의 근거가 이것이다.

---

## 2. [ACCEPT] rank-IC ≈ 0 인데 PORT_t = −1.71 — 나는 수출 가설이 아니라 다른 것을 측정했을 수 있다

**자기 비평**: rank-IC −0.0034 (t −0.30) 은 횡단면 전체에 신호가 **없다**는 뜻이다. 그런데 top-25
PORT_t 는 −1.71 로 0 에서 유의하게 떨어져 있다. 이 둘이 동시에 참이려면 음수는 **극단 tail 선택**에서만
나와야 한다. 그리고 내 스코어의 극단은 로그 YoY 성장의 절대 크기가 큰 종목 = **가장 변동이 큰 niche
HS4 버킷** = 소형주다. 실제로 cap-tier 분해가 OTHER 88.9% 를 보였다.

즉 이 라운드가 측정한 것은 "수출 정보의 예측력" 이 아니라 **"변동성 극단 선택의 페널티"** 일 개연이 크다.
수출 가설은 제대로 시험되지 않았을 수 있다.

**처리**: ACCEPT. CF-03 등재. 이것이 판정을 "구조 판결" 이 아니라 "config-scoped negative" 로
묶어두는 가장 강한 이유다. next_probe 2(materiality 가중)가 직접 대응.

---

## 3. [ACCEPT] 내가 선언한 regime_scope 가 데이터에 의해 반증됐다

**자기 비평**: 나는 메커니즘(수출액의 USD 표시)에서 "crisis 에서 약화·역전" 을 도출했다. 그런데
부기간 PORT_t 는 2016-19 −1.71 / **2020-22 +1.53** / 2023-26 −2.59 로, COVID crisis 를 포함하는
구간이 **유일한 양수** 였다. 내 국면 경계 예측은 부호가 반대다.

**처리**: ACCEPT. CF-05 등재. 사후에 경계를 고쳐 쓰지 않는다(goalpost 이동 금지) — 예측이 틀렸다고
기록하고 남긴다. 다만 n=3 구간·112개월이라 이 자체도 약한 증거임을 병기한다.

---

## 4. [PARTIAL] 반증 검정이 t=1.969 로 사전등록 기준 t≥2 에 "간발로" 미달 — 기준을 낮추고 싶은 유혹

**자기 비평**: Q5−Q1 컨센서스 영업이익 개정 스프레드 = +1.49% (log), t = **1.969**, 3M·6M 부호 일치
(Q5 +1.78% vs Q1 +0.29%). t≥2 를 1.96 으로 바꾸면 "MECHANISM_SUPPORTED" 가 된다. 이것은 전형적
goalpost 이동이다.

**처리**: PARTIAL.
- 사전등록 기준(t≥2)은 **그대로 적용** → verdict = MECHANISM_NOT_SUPPORTED 유지.
- 동시에 "부호는 방향이 맞고 두 horizon 에서 일관되며 문턱에 근접" 을 수치와 함께 병기한다.
  기준 미달을 "기전 전면 부재" 로 과장하는 것도 똑같이 부정직하기 때문이다.
- 정직한 요약: **기전의 1차 링크(수출→실적기대)는 약하게 존재하고, 2차 링크(→가격)는 부재.**

---

## 5. [ACCEPT] 'firm-level' 이라는 이 라운드의 핵심 명사가 64% 만 실현됐다

**자기 비평**: 가설 제목은 "종목-레벨 수출 nowcast" 다. 그러나 크로스워크는 종목→HS4 매핑이고,
같은 HS4 에 단일 매핑된 종목들은 **완전히 같은 스코어**를 받는다. 실측: 월평균 183 종목에 서로 다른
값은 116 개(비율 0.644). 나머지는 구분 불가 동점이다. 유효 해상도는 firm 이 아니라 "HS 믹스" 다.

**처리**: ACCEPT. CF-06 등재 + 진단 필드 `effective_cross_section` 로 수치 고정.
제목·서술에서 "firm-level" 을 무조건 주장하지 않고 "HS 믹스 해상도의 준-종목 레벨" 로 정정.

---

## 6. [ACCEPT] 회전율 1288%/yr — 양(+)이었어도 배포 불가였다

**자기 비평**: Production Constraints 상 TO ≤ 1100%/yr. 내 신호는 1159~1556%. 즉 이 config 는
**알파 부호와 무관하게** 구현 규율을 위반한다. 나는 이걸 부수적 관찰로 넘기려 했으나, 실은
"이 horizon 자체가 제약 조건 밖" 이라는 1급 사실이다.

**처리**: ACCEPT. CF-04 등재. 제약 완화를 레버로 제시하지 않는다(AX-000 따름정리 / INV-7).
대신 조건-안 해법 = 신호 평활(3M/6M 누적 서프라이즈)로 회전을 낮추는 next_probe 3.

---

## 7. [REBUTTAL] "PIT 타이밍이 새고 있는 것 아니냐"

**제기**: 저장 패널 기반 신호는 2026-07-14 동월 look-ahead 실사고 계열이다. 음수라도 타이밍이
틀렸을 수 있다.

**반박 근거 (정량 3축 + 코드 경로)**:
1. **컴파일러-소유 AS_OF** — 신호 조인을 수기로 하지 않았다. `ast_compile()` 이 패널의 `avail_ts`
   컬럼(= 데이터월 M+1 의 15일)을 읽어 `avail_ts <= eval_date` 로 조인한다. 수기 merge 0건.
2. **C5 HARD 가드 통과** — `assert_overlay_pit(usable_date, holding_start)` PASS,
   버퍼 **실측 14~17일** (요건 ≥10). 홀딩월 H = 데이터월 M+2.
3. **lag1 스트레스 무변화** — base PORT_t −1.708 vs lag1 −1.705 (Δ 0.003). 동월 누출이 있으면
   1개월 추가 지연 시 성과가 붕괴해야 한다. 붕괴 없음.
4. **라벨 방향 감사** — cor(Ret_1m, forward recompute) = **1.000000**.

L-code/규범 근거: `.claude/rules/pit.md` §오버레이 신호 타이밍(C5) · `measurement-graduation.md` §7b ·
메모리 [[project-stored-panel-samemonth-lookahead]] · [[project-riskoverlay-multilayer-bearprob]].

**남는 노출은 타이밍이 아니라 vintage** (customs 개정판 · crosswalk static_current) 이며 §1·CF-01 로
별도 계상했다. 따라서 REBUTTAL — 단 "vintage 는 clean 하다" 는 주장은 하지 않는다.

---

## 8. [PARTIAL] vintage-swap 이 "개정 0" 을 보였는데 이걸 안심 근거로 쓸 뻔했다

**자기 비평**: 스냅샷 2개(07-26, 08-01) 차분에서 227,459 셀 중 변경 0. 이걸 "개정 위험 없음" 으로
읽으려 했다. 그러나 두 스냅샷은 **6일 간격이고 개정일(매월 15일경)을 포함하지 않는다.** 검정이
발화할 수 없는 창에서 얻은 0 은 증거가 아니다 — 저장소가 반복 겪은 "검사 사망 = 무경고 통과" 계통.

**처리**: PARTIAL. CF-08 로 "무증거 ≠ 무개정" 명시. 15일을 사이에 둔 스냅샷 쌍이 쌓일 때 재측정.

---

## 9. [ACCEPT] AST 계층을 "통과했다" 고 보고할 뻔했다 — 실은 검증이 사망해 있었다

**자기 비평**: `ast_spec_gate.sh` 가 최종적으로 `{}`(통과) 를 반환했다. 이걸 "AST 계약 이행 완료" 로
보고하면 정확히 틀린 보고가 된다. 직접 확인하니, 게이트가 소비한 in-process `ast_verify` 는
**컴파일러 방언 트리를 순회하지 못해 leaf_count=0 · op_count=1 로 '위반 0' → PASS** 를 낸 것이었다.
검사 대상이 0이라 통과한 것이지 검사를 통과한 게 아니다.

**처리**: ACCEPT — 그리고 이것을 이 라운드의 **최상위 산출물**로 승격했다.
`06_Registry/ast_leaf_table_bugs.jsonl` **ALB-007 (CRITICAL)** 적립.
"경고 0 / 통과" 를 받은 순간이 가장 위험하다는 기존 교훈([[feedback-verify-both-directions-always]])의
재현이며, 양방향 확인(정직판 FAIL_CONTRACT vs 실행판 PASS 대조)이 아니었으면 못 잡았다.

---

## 10. Q-Lead escalate trigger 판정

| 트리거 | 기준 | 실측 | 발동 |
|---|---|---|---|
| HIGH severity concern | ≥ 5 | ACCEPT-HIGH 계열 6건(§1·2·3·5·6·9) | **YES** |
| AX axiom hard FAIL | ≥ 3 | 0 | no |
| PIT C1 (lockbox·lookahead) 위반 | 1건 | 타이밍 위반 0 (§7). vintage 노출은 라벨링됨 | no |

→ **escalate = YES** (HIGH ≥5). 사유는 알파 결과가 아니라 **인프라(ALB-007 CRITICAL)** 다.
알파 판정 자체는 config-scoped negative 로 정상 종결 가능하나, AST 정적검증이 실행 경로에서
무효라는 사실은 다른 모든 진행 중 WT 에 소급 적용되므로 즉시 통지 대상이다.

---

## 11. 이 라운드가 스스로 만들지 못한 증거 (정직 공백)

- **PIT-clean lane 측정 부재** — vintage 크로스워크(연도별 DART 사업보고서)를 구축하지 않았다.
  effective_from 을 엄격 적용하면 n_months ≈ 15 로 판정 불가여서 측정 자체를 생략했다.
  따라서 "clean lane 에서의 값" 은 **미측정**이며 추정하지 않는다.
- **oos_retention / calmar / DSR 미산출** — PORT_t 가 음수라 forge 승격에 도달하지 않았다.
  graduation HARD 3종은 forge-authoritative 값에만 적용되므로 alpha 단계에서 선언하지 않는다.
- **해외 현지생산 누락 미보정** — 매핑 315사 중 29.8% 가 해외생산을 언급(export_exposure_probe.json).
  이들의 실적은 한국 통관 통계에 잡히지 않는다. 보정 없이 측정했다.
