# Self-Adversarial Challenge — WT-D20260809_004 (FQ-173 인플레이션 나침반 KR)

**대상**: `alpha_package.json` + `stage_artifacts/WT-D20260809_004/alpha_validation.json`
**시점**: finalize 직전, 2026-08-09 (v8.2 — 외부 Codex 미호출, 메인 세션 모델 자체 적대검증)
**규약**: Charter §8 No Silent Override · AX-008 3-source 중 1개

---

## C1. primary falsification 의 "통과"가 시장베타의 재진술 아닌가 — **ACCEPT (자기 결론 정정)**

**제기**: 예측표의 음(-) 집합(유틸리티·통신·소프트웨어·건강관리·미디어)은 사실상 **저베타 방어섹터**,
양(+) 집합(에너지·화학·철강·비철·상사)은 **고베타 경기섹터**다. infl_t 가 경기와 동행하면 부호 패턴은
인플레 전가력 채널이 아니라 "방어섹터는 베타가 낮다"의 재진술로 자동 충족된다. 그러면 통과 0.649(p 0.0005)는
채널 확인이 아니다.

**논증 대신 측정** (`a11_adversarial.R`, 사전등록에 없던 추가 통제):

| 채점 기준 | 예측 일치율 |
|---|---|
| 인플레 β_s (원판) | 0.649 |
| **섹터 시장베타 β^mkt (대안 설명)** | **0.822** |
| 시장중립화 β_s^⊥ (r_s 를 벤치에 회귀한 잔차 위 재추정) | 0.600 (stride-12 **0.571**, 이항 p **0.0845**) |

- β_s ↔ β^mkt 상관: 섹터-월 Pearson +0.239 / **섹터 평균끼리 +0.509**.
- **대안 설명이 더 잘 맞는다.** 시장성분을 제거하면 5% 유의성을 잃는다.

**처리 (반영 완료)**: primary falsification 판정을 PASS → **INCONCLUSIVE (시장베타 교락)** 으로 정정.
`alpha_package.hypothesis.falsification[0]` 과 `alpha_validation.falsification_results.primary_beta_sign`
양쪽에 통제 결과·수치·방법을 기재하고, challenge_flags 에 자기 정정 항목을 추가했다.
잔존 신호: 시장중립화 후에도 유틸 0.815·건강관리 0.809·철강 0.794 는 견고 — 채널이 **일부** 섹터에는
남아 있을 가능성. 단 그것만으로 채널 확인을 주장하지 않는다.

## C2. 발행한 α̂ 가 가설이 아니지 않은가 (미끼-교체) — **PARTIAL**

**제기**: FQ-173 은 3층 인플레 설계인데, 층2 가 죽자 층3(컨센서스 성장 합성)을 α̂ 로 발행했다.
라운드의 인프라를 빌려 FQ-173 과 무관한 범용 팩터를 내놓는 것 아닌가.

**판정: PARTIAL**
- 인정: 발행 α̂ = C01_SUE+C02_EPS_Chg_1m+M26_Revenue_Mom 동일가중이며, 인플레 성분이 **들어 있지 않다**.
  이 조합 자체는 신규 발굴이 아니다(registry 기존 3종).
- 반박: 이것은 사전등록이 정한 처분 그대로다 — F3 규칙 "(a) 무효 ∧ (c)−(b) 증분 무효 → 인플레 층 제외,
  **'종목선택 알파'로 재라벨**". 결과를 보고 만든 후퇴로가 아니라 측정 전에 고정된 분기다.
- 처리: `combination_rule_detail` 과 challenge_flags 에 "조립층은 α̂ 정의 밖 · 알파 기여 미확립"을 명시하고,
  조립층 실측은 `alpha_validation.arms_*` 에만 남겼다. discovery 신규성 주장은 하지 않는다
  (상속 상관 0.5104 · incumbent top-25 이름 중복 9.67/25 를 정직 기재).

## C3. 스키마 헤드라인 필드에 다른 창의 수치를 넣은 것 아닌가 — **ACCEPT**

**제기**: `diagnostics.canonical_port_t_nw_lag3 = 2.479` 는 **층3 단독 · 전창 284개월** 값이다.
사전등록의 주 판정 대상(결합 설계, 공통창 209개월)은 1.399 다. 스키마 헤드라인 필드에 큰 쪽을 넣으면
읽는 쪽이 2.479 를 이 라운드의 성적으로 앵커링한다 — 2026-08-08 창-교락 계통.

**처리 (반영 완료)**: 같은 diagnostics 블록에 `canonical_basis`(창·벤치·비용 명시)와
`canonical_scope_note`("발행 alpha_vector 의 재료인 층3 단독 · 결합 값은 arms 절 · **서로 다른 창이므로
나란히 비교 금지**")를 인접 필드로 붙였고, challenge_flags 에 세 수치(2.479 / 1.746 / 1.399)를 창과 함께
병기했다. 필드 자체를 비우지 않은 이유: 발행 α̂ 의 재료가 층3 이므로 헤드라인은 그 재료여야 정합.

## C4. 승계 스펙을 바꿨다 (No Silent Override) — **PARTIAL**

**제기**: 승계 가설의 `exp(λ·β_s·infl)` 를 `exp(λ·β̃_s·infl)`(scale-only 정규화)로 바꿔 측정했다.
이는 alpha-hypothesis 산출물의 재작성이다.

**판정: PARTIAL**
- 인정: 판정판을 바꾼 것은 사실이다.
- 반박: ①변경 대상은 승계 3항목(mechanism/falsification/regime_scope)이 **아니라** alpha-research 소관인
  ⑤구현 스케일이다. ②변경 근거가 **수익률을 보기 전** 신호 패널만으로 확정됐다(`a4_tilt_scale.json`):
  문자 그대로의 판은 λ∈{0.5,1.0} 에서 25슬롯 중 교체가 **0인 달이 60.8~65.6%** — 산술적 불활성이라
  그대로 재면 "기전 부재"와 "격자를 못 넘음"을 구별할 수 없다. ③부호 보존율 1.0000 (demean 하는 z 판은
  2.66% 를 뒤집어 기전을 변형하므로 배제). ④문자 그대로의 판도 **전량 병기 측정**(PORT_t 1.062/1.066,
  증분 −0.05%/yr) — 폐기가 아니다.
- 처리: `prereg_amendment_1.json` 에 사유·전후 수치·시점을 기록하고 challenge_flags 에 고지.

## C5. 진단 수치를 오용해 놓고 넘어갈 뻔했다 — **ACCEPT (자가 적발·수리)**

**제기**: 초판 arm 실행에서 `diag_ew_universe` PORT_t 가 −53 ~ −66 으로 나왔다. 이 값을 "EW 대비 참패"로
읽고 지나갔으면 결론이 정반대로 갔다.

**처리 (반영 완료)**: 원인 = `scores_dt` 에 선택 25종만 실어 canonical 의 "유동성필터 前 유니버스"가
포트 자신이 됐고, EW 벤치 = 포트 gross → active = −비용(상수 음수). 전-유니버스 점수판(비선택 −1)으로
수리했고 **cap-w 본판정 parity 차 0.00e+00** 로 선택 불변을 실증했다. 수리 후 EW-유니버스 진단은
R0 +3.001 / B +2.505 / C_l0.5 +2.697 / C_l1.0 +2.621. 교훈: 진단 함수의 **입력 전제**(패널이 유니버스인가)를
확인하지 않으면 진단이 조용히 다른 것을 잰다.

## C6. EW-basis 3.00 을 근거로 cap-w 게이트를 우회하려는 것 아닌가 — **REBUTTAL**

**제기**: cap-w 에서 전건 미달인데 EW-유니버스 진단에서 R0 가 3.001(공통창)·3.126(전창)으로 2.95 를 넘는다.
이걸 강조하는 것은 게이트 우회 서사다.

**판정: REBUTTAL**
- `hard_gate_status.port_t_2p95 = "FAIL"` 로 명시했고 `dual_basis_diagnostic.binding = FALSE`,
  `metric_type = "canonical_screen_diag"` 를 함께 기재했다. 상신 자격도 없다고 적었다.
- EW 병기는 v8.3 M2 가 **의무화한** 진단이며, cap-tier 분해상 보유의 **90.6%가 OTHER(31위 밖)** 이라
  문서화된 cap-w 벤치 구성 미스매치 형태에 정확히 해당한다 — 은폐가 오히려 규약 위반이다.
- 처분은 "판정 뒤집기"가 아니라 `screen_route` 재분류 **검토 대상 부기** + NP-1 로 등재.

## C7. 시행 수를 축소 계상한 것 아닌가 — **PARTIAL**

**제기**: `n_trials=7` 로 DSR 을 냈지만 실제로는 λ 3값 × (judged/literal) × arm 종류 + 20 시드 × 3 세트가 돌았다.

**판정: PARTIAL**
- 인정: 실행 횟수는 7 보다 훨씬 많다.
- 반박: DSR 의 n_trials 는 **챔피언 선택에 노출된 후보 수**다. 본 라운드는 `selection_type =
  diagnostic_no_argmax` — 어떤 arm 도 승격하지 않았고 발행 α̂ 는 λ 와 무관한 층3 이다. 시드 20개는
  후보가 아니라 **동일 arm 의 표집 잡음 추정**이며 평균±sd 로만 보고했다(단일 draw 문턱 취약성 규약).
- 처리: DSR 은 게이트가 아닌 진단으로 라벨(모두 0.000)했고, 실행된 arm 전량을 `arms_common_window_209m`
  에 열거했다. 축소 없이 세려면 열거표를 세면 된다.

## C8. confidence_vector 가 정보를 담고 있나 — **ACCEPT (한계 고지)**

평균 0.980 · sd 0.046 · 최소 0.767 — 사실상 평탄하다. 3항 중 1항(rank-IC t 항)이 **종목 무관 상수**라
변별력을 깎는다. 발행은 하되 옵티마이저가 이 벡터로 종목을 구별할 수 있다고 주장하지 않는다.
개선안은 next_probe 가 아니라 다음 라운드 설계 항목으로 남긴다.

## C9. 유동성 정의가 저장소 표준과 다르다 — **PARTIAL (미측정 고지)**

본 라운드 adv = **20 거래일 평균** mean(Close×Vol) 이고, repo canonical 경로 표준은 단일일 Vol0×Close0 근사다.
본 라운드 쪽이 엄격하지만 **두 정의의 차이는 재지 않았다**. 비교 인용 시 정의 라벨 확인 필요를
challenge_flags 에 기재했다.

---

## 합리화 어휘 자가 검사

`answer-principles` 회피표현 목록(축소/관행/안전마진/영향 미미 계열) 대조 — 본문 및 산출물 미사용 확인.
"검정력 부족"은 회피가 아니라 `verdict_with_power` 실측 라벨(관측/필요 0.39~0.46)이며 수치와 함께 기재했다.

## 종합

- **ACCEPT 4** (C1 자기 결론 정정 · C3 창 라벨 · C5 진단 오용 수리 · C8 한계 고지)
- **PARTIAL 4** (C2 · C4 · C7 · C9)
- **REBUTTAL 1** (C6)
- C1 은 **판정 자체를 뒤집었다** — primary falsification PASS 를 INCONCLUSIVE 로 정정하고 산출물 2건을 재발행했다.

## Q-Lead escalate 판단

- HIGH severity ≥ 5 : 미충족 (ACCEPT 4 중 자기 정정 1 + 수리 완료 2 + 고지 1)
- AX axiom hard FAIL ≥ 3 : 없음 (AX-000/001/002/008 위반 없음)
- PIT C1 (lockbox·lookahead) 위반 : 없음 — `a9_pit_assert.R` 5축 HARD PASS + 위반 주입 검출 확인
→ **자동 escalate 트리거 미발동.** 단 인프라 결함 2건(schema↔ast_verify 방언 분열 / 게이트 advisory 메시지
불일치)은 별도 태스크로 분리 제안했다.
