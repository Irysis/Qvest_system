# Self-Adversarial Challenge — alpha-research (WT-D20260813_004)

- 작성: alpha-research, 2026-08-13, `alpha_package.json` finalize 직전
- 대상: 본 역할 산출만 — 승계 검수 · 인터페이스 검증 · AST 구성 · 핸드오프 명세. Σ 측정·성과 판정은 소관 밖
- 결과: **ACCEPT 2 · PARTIAL 3 · REBUTTAL 2** (제기 7건). ACCEPT 전건 산출물 반영 완료 (CF-9 는 초판 주장 철회)

---

## §1 — PIT 근거로 실은 '방향 검사 PASS' 가 실제로 무엇을 보증하나 (최강 제기, 자기 적발)

**제기**: 초판 `alpha_package.diagnostics.interface_verification_summary` 에 `pit_direction_test: "PASS (margin +0.0620)"` 를 실었다. 그런데 이 검사가 진짜 C5 위반에 발화하는지는 확인하지 않았다. 발화하지 않는다면 그 PASS 는 "결함 없음" 이 아니라 "검사기가 죽어 있음" 과 구분되지 않는다.

**판정: ACCEPT — 실측했더니 검사가 판별력 0 이었다. 주장 철회.**

위반 주입 실행(`s3_violation_injection.R`): σ̂ 를 `Date <= 홀딩월 말일` 로 다시 만들어(= 동월 정보 포함, 명백한 C5 위반) 같은 검사에 먹였다.

| arm | cor(σ̂_m, rv_m) | cor(σ̂_{m+1}, rv_m) | margin | 판정 |
|---|---|---|---|---|
| clean (승계 규약) | 0.6788 | 0.7434 | **+0.0647** | PASS |
| **위반 주입** | 0.7452 | 0.7747 | **+0.0295** | **PASS (발화 실패)** |

대안 통계량 2종도 전부 실패(`s4_detector_power.R`): 창밖-창안 대비 B(+0.0656 / +0.0303, 부호 불변) · 동월 첫날 반응 C(0.3380 / 0.3538, 분리폭이 **음수** — 방향조차 어긋남).

**기전**: 252거래일 창에 홀딩월 약 21일을 더해도 창의 약 8% 만 바뀐다. σ̂ 의 ac1 이 0.9902 라 지속성이 통계량을 지배해 한 달 오염이 묻힌다. 즉 **월-수준 상관 진단은 장창 신호의 1개월 오염을 원리적으로 못 잡는다.**

**반영**: ① 해당 PASS 를 `RETRACTED_NO_POWER` 로 교체 ② PIT 근거를 **구성-수준 재현**(strict 컷오프로 원천 재구축한 값이 승계 패널과 `max|diff| = 0.00e+00`, n=366) + WT-003 `assert_overlay_pit` HARD 로 교체 ③ 파급을 핸드오프에 이월 — 승계 prereg 의무 ⑥의 **lag1 스트레스가 같은 둔감성을 가질 수 있음**을 `stress_power_caveat` 로 명시하고, 통과를 근거로 쓰려면 먼저 그 검사에 위반을 주입하라고 지시 ④ CF-9 등재.

**남는 것**: 이 라운드에서 가장 값나가는 산출이 "내가 실으려던 근거가 근거가 아니었다" 는 것이다. 초판대로 넘겼으면 risk-research 는 판별력 0 인 검사를 PIT 보증으로 물려받았을 것이다.

## §2 — parity 0.00e+00 은 순환 논증 아닌가

**제기**: 나는 σ̂ 를 원천에서 재구축해 `max|diff| = 0` 을 얻었다. 그런데 그 레시피(252d, `Date < cut`, `sd(tail(r,252))`)를 생산자 코드(`s1_prereg.R:37-42`)에서 **읽어와서** 썼다. 같은 레시피로 같은 자료를 돌렸으니 0 이 나오는 건 당연하다. 이게 무엇을 증명하나?

**판정: PARTIAL — 제기가 옳다. 증명 범위를 좁혀 명시했다.**

`max|diff| = 0` 이 보이는 것은 **"승계 패널이 선언된 규약대로 만들어졌다"** 뿐이다. 보이지 못하는 것 2가지: (a) 규약 자체의 정당성 — 이건 C5 정의(`pit.md`)에서 오지 실측에서 오지 않는다 (b) 향후 restatement 내성 — 오늘 시점 원장 기준이다(A1·A4 둘 다 `restatement_prone=TRUE`).

그럼에도 이 값이 공허하지 않은 이유: **재구축을 안 했으면 §1 의 함정도, §3 의 warm-up 결손도 못 찾았다.** 그리고 "패널을 그대로 쓴다" 와 "패널이 선언대로 만들어졌다" 는 다른 명제이며 후자는 검증 가치가 있다(저장 패널 동월 look-ahead 실사고 2026-07-14 가 정확히 후자의 실패였다). `self_pit_check.pit_evidence_basis` 에 `accepted / rejected / residual_risk` 3분해로 기록했고 pin 의무를 잔여 위험 처리로 명시했다.

## §3 — warm-up 발견은 사후 정당화 아닌가

**제기**: 처음에 parity 를 재면 spearman 0.947 이 나왔고, 나는 그걸 "불일치" 로 신고할 뻔했다. 그 뒤 코드를 뒤져 basis 를 찾아 0 을 만들었다. 이건 "0 이 나올 때까지 basis 를 바꾼" 것 아닌가 — 사후 적합이다.

**판정: PARTIAL — 절차상 그 위험이 실재했고, 그래서 판별 근거를 basis 선택이 아니라 외부 증거에 뒀다.**

옳은 부분: 순서상 나는 불일치를 먼저 보고 basis 를 찾으러 갔다. 사후 적합의 형태와 같다.

사후 적합이 아닌 부분: basis 를 **자료에 맞춰 고른 게 아니라 생산자 코드에서 읽었다**(`f1b_diagnosis.R:30 VOL := exp_z(vol)` · `s1_prereg.R:50-53`). 그리고 독립 확증 2건이 있다 — (i) `d2$VOL[1]` 이 **유한값**인데 `exp_z` 는 1번째 원소에서 구조적으로 NA 를 낸다 ⇒ 패널 시작점보다 앞선 격자가 존재해야만 함이 **자료 자체에서** 강제된다 (ii) WT-002 가 남긴 `vol_basis_correction.json` 이 두 basis 의 spearman 을 **0.9246** 으로 이미 기록했고 내 오basis 측정치 **0.9240** 이 그것과 일치한다. 즉 내가 잘못 쟀다는 사실이 제3의 문서로 교차 확인된다.

만약 basis 를 자료에 맞춰 튜닝했다면 427이라는 격자 크기와 60개월이라는 warm-up 길이가 원천 데이터 구조(1990-01-05 시작 + 252일 요건)에서 **도출**되지 않고 임의값이 됐을 것이다. 실제로는 도출된다.

## §4 — 측정을 하나도 안 한 라운드가 값이 있나 (ceremony 제기)

**제기**: Σ 도 안 만들고 성과도 안 재고 신규 알파도 0건이다. 남은 건 문서다. "핸드오프 명세" 는 일하지 않았다는 것의 포장 아닌가.

**판정: REBUTTAL — 인계한 3건이 전부 실측이고, 각각 다음 라운드가 실제로 밟았을 지뢰다.**

① **§1 검사 판별력 0** — 안 잡았으면 risk-research 가 죽은 검사를 PIT 보증으로 인용. ② **warm-up 결손** — 패널만으로 anchored 변환을 재현하면 `max|diff| 2.827` 이 나오고, 이걸 "승계 불일치" 로 읽으면 정상 패널을 결함으로 신고한다(내가 실제로 그 직전까지 갔다). ③ **조인 키** — `realized_ym` 으로 조인하면 손실이 **1행뿐**(271→270)이라 "손실 5% 검문" 을 통과하면서 축이 1개월 어긋난다(축 진단 0.70 → 0.08). 오늘 이 세션에서만 조인 손실 3건이 났다는 것이 이 인계의 필요를 실증한다.

세 건 모두 "문서로 옮긴 의견" 이 아니라 수치가 붙은 실측이며, 재현 스크립트가 함께 있다.

## §5 — rank_ic = 0 을 기계가 진짜 0 으로 읽는다

**제기**: schema `type=number` 강제 때문에 0 을 넣었는데, `rank_ic` 만 읽는 하류 소비자(RF-A 계열 red flag, graduation advisory)는 "IC 0 = 신호 없음" 으로 읽는다. `rank_ic_status` 를 함께 읽어준다는 보장이 없다.

**판정: PARTIAL — 완화만 가능하고 잔여 위험은 실재한다. 은폐하지 않고 등재했다.**

`rank_ic_status = "structurally_undefined_not_measured_zero"` + `rank_ic_note` + CF-5 로 3중 표기했으나, **필드 하나만 읽는 기계는 여전히 속는다.** 스키마를 바꾸지 않고는 닫히지 않는 구멍이며 스키마 개정은 본 역할 권한 밖이다. 다만 본 라운드는 graduation 게이트에 들어가지 않으므로(성과 미산출·forge 미경유) 실제 오판 경로는 현재 닫혀 있다. 구조 문제로 CF-5 에 남긴다.

## §6 — `alpha_inheritance_cor = 1` 이 스키마 의미와 다르다

**제기**: 스키마 정의는 "parent strategy alpha 와의 cosine/correlation" 이다. 본 라운드에는 parent portfolio alpha 가 없고 내가 잰 것은 신호 패널 parity 다. 의미를 늘려 쓴 것 아닌가.

**판정: PARTIAL — 늘려 쓴 것이 맞고, 그래서 basis 를 값 옆에 붙였다.**

`alpha_inheritance_cor_basis` 필드에 "verbatim 승계 · 원천 재구축 max|diff| 0.00e+00 · n=366/366" 를 명기해 무엇을 잰 값인지 값과 같은 자리에서 읽히게 했다. role card 판정(`>0.95` → discovery 재분류 권고)은 이 해석으로도 동일하게 성립하므로 거버넌스 결론은 바뀌지 않는다(CF-1).

## §7 — 위험모델 주제인데 역할경계를 정말 안 넘었나

**제기**: 핸드오프에 `Σ = BΩB' + D`, "Ω 의 시장 요인 분산만 교체", "공통성분 몫 ≥50%" 가 적혀 있다. 이건 Σ 설계 아닌가.

**판정: REBUTTAL — 전부 승계 문구이고 추정은 0건이다.**

해당 서술은 `alpha_hypothesis.json::selected.mechanism.path` 와 `falsification` 원문이며 내가 **재작성하지 않고 옮겨 담았다**(Charter 원칙 8 — 결함 발견 시 수정이 아니라 challenge 기록). 승계 원문 자체가 "구현 추정기 선택은 risk-research 소관, 본 설계는 채널만 지정" 이라고 경계를 긋고 있다.

기계 확인: 본 라운드 스크립트 4종(`s1`~`s4`) 어디에도 `cov` / `cor` 행렬 추정 / weight 산출 / `canonical_screen_bt` / `build_bt_result` 호출이 없다. 산출한 상관은 전부 **스칼라 2변량 진단** 2종이며 각각 `metric_type` 을 붙였다(`interface_diagnostic` = 조인 축 식별 / `interface_verification` = 패널 재현). `governance.role_boundary_self_audit` 에 5항 boolean 으로 기록했다.

---

## 합리화 어휘 자가 점검

`answer-principles.md` 회피표현 · `pit.md` 금지표현 · 금칙어("처녀"·"봉투"·종결 어휘)를 `alpha_package.json` 전문에 기계 grep 했다.

- **적발·수정 2건**: "종결된다"(pit.sig_date_rationale) → "이내로 한정된다" 로 교체. "거의 그대로 잔존" → 근거 수치(A 통계량 +0.0647→+0.0295, 부호 불변)를 명시한 서술로 교체하고 "확정이 아니라 사전 경고" 라벨 부착.
- **유지 판정 3종**: "동일"(8회) = 전부 실측 등식 인용(`max|diff| = 0`, 규약 일치)이라 증거 있는 사용. "추정"(12회) = `Σ 추정` 등 기술 용어(covariance estimation)이지 회피어 아님. "관행"(3회) = 승계 원문의 `장창 추정 관행`·`pin 관행` — 마찰 주체를 지목하는 실명 명사이지 "관행적으로 허용" 류 면제 어법이 아님.
- 무라벨 성과 주장 0건. 모든 투영·전이 서술에 `metric_type` 또는 미측정 라벨 부착. 사전 기대는 승계값 그대로 "중하" 유지(상향 없음).

## Q-Lead escalate 판단

자동 escalate 트리거 **미해당**: PIT C1 위반 0 · AX axiom hard FAIL 0 · HIGH severity 3건(<5).

보고 대상 2건:
1. **CF-2 lane 라우팅 결정 필요** — 1차 판정(P1)이 Σ 추정을 수반해 alpha-research 실행 불가. 본 WT 내 risk-research spawn vs `method_frontier`(FQ-108b) 재투입 중 Q-Lead 결정. 선례 WT-D20260803_003 = `CANCELLED_LANE_MISROUTE`.
2. **CF-9 자기 철회** — PIT 검사 판별력 0 실측. 승계 prereg 의무 ⑥(lag1 스트레스)의 유효성에 직접 영향하므로 측정 착수 전에 읽혀야 한다.

verdict = `designed`. 승계분(mechanism / falsification / regime_scope) 재작성 0건, 결함 발견 0건.
