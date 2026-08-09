# challenge_note_contract_repair.md — WT-D20260808_001 (FQ-122)

**작성**: alpha-research (2차 병행 실행), 2026-08-08
**성격**: 기존 `challenge_note.md`(1차 실행 작성분)를 **대체하지 않는다**. 그 문서의 concern 9건과 판정은 그대로 유효하며, 본 문서는 ① 병행 중복 실행 사실 ② 산출물 계약 위반 수리 ③ 독립 재현·추가 실측을 기록한다.
**규약**: Charter 원칙 8 No Silent Override — 수리는 전부 여기 명시하고 원본을 보존한다.

---

## 0. 병행 중복 실행 (사건)

동일 `WT-D20260808_001` 을 **두 개의 alpha-research 실행이 병렬 수행**했다. 1차 실행이 22:59~23:02 에 `alpha_package.json` / `challenge_note.md` / `artifact_lineage.json` / `alpha_validation.json` / `alpha_scores.parquet` 를 발행했고, 그 과정에서 2차(본 실행)의 `alpha_validation.json` · `challenge_note.md` · `alpha_scores.parquet` 를 덮어썼다.

**중복 자체는 v8.3 hypothesis_index in-flight WT 인덱싱이 막았어야 할 사건** — Q-Lead 보고 대상.

**다만 결과적으로 독립 재현 증거가 생겼다** (AX-008 triangulation 상 유리):

| 항목 | 1차 실행 | 2차 실행(본) | 일치 |
|---|---|---|---|
| P1 D03 top-25 기울기 | −3.443%/yr, t −1.093 | −3.44%/yr, t −1.09 | ✔ |
| P1 Q01 top-25 기울기 | +3.771%/yr, t +1.606 | +3.77%/yr, t +1.61 | ✔ |
| F4 밴드 기울기 D03 / Q01 | −3.283 / −3.257 | −3.28 / −3.26 | ✔ |
| F1 Q01 Q1−Q3 | t −2.25 | t −2.25 | ✔ |
| p_hit D03 q20 | 0.3862 | 0.3822 | ≈ (eligible set 구성 미세차) |
| base canonical PORT_t | 2.050 | 2.050 | ✔ |
| Q01_q20 canonical PORT_t | 2.381 | 2.357 | ≈ |

서로 다른 코드로 같은 수를 얻었다 — 핵심 판정(전 arm INCONCLUSIVE_UNDERPOWERED · (a) 사전 KILL · D03 F1 기각 · Q01 F1 지지)은 양쪽 독립 확인이다.

## 1. 산출물 계약 위반 — 검사 결과

발행된 `alpha_package.json` 을 `ast_spec_gate.sh` 와 `schema.json` 에 걸어보니:

- **ast_spec_gate: `{"decision":"block"}`** — `falsification 사전 부재/빈 배열`
- **schema 위반 13건**

이 산출물이 디스크에 오른 경로는 **R `write_json`** (`run_fq122_emit.R`) 이다. `ast_spec_gate.sh` 는 PreToolUse[Write] 훅이므로 **R 이 쓰는 산출물은 게이트 시야 밖**이다. 즉 게이트가 통과시킨 게 아니라 **게이트를 지나지 않았다**. (init prompt `v61_lineage_obligation` 절이 규정한 표준 발행 경로가 바로 R `write_json` 이므로, 이 우회는 개별 실행의 잘못이 아니라 **하네스 구조**다 — AX-001 훅에서 이미 문서화된 동일 계통: "정상 산출물은 R write_json 이 써서 PreToolUse 시야 밖".)

### 위반 6종

| # | 위반 | 근거 |
|---|---|---|
| V1 | `hypothesis.falsification` 이 **문자열** | schema 는 객체배열 + field_dictionary 필드 지목 요구. gate ① BLOCK 사유 |
| V2 | `pit` 필드 **부재** | v1.1 conditional required (ALB-006). ast_verify 가 sig_date 를 요구 |
| V3 | `diagnostics.alpha_inheritance_cor` **부재** | schema required 3종 중 1. discovery role card 판정 입력 |
| V4 | `diagnostics` 6개 필드 **null** (rank_ic / icir / monotonicity / subperiod_stability / harvey_t_stat / post_neutralization_ic) | schema type = `number`. null 불가 |
| V5 | `factor_specs[].economic_rationale` 자유서술 (2건) | schema enum {risk_premium, behavioral, structural} |
| V6 | `factors[].ast` escape_contract 가 `provenance_path/builder/vintage` 평면 키 | schema 는 `provenance{store_build_hash, generator_code_path, generated_at}` 객체 required. ast_verify 도 `node["provenance"]` 를 봄 → FAIL_CONTRACT |

## 2. 수리 — 무엇을 바꿨고 무엇을 안 바꿨나

**안 바꾼 것 (전부)**: 판정 · 수치 · verdict · 결론 · 기존 challenge_flags · 기존 진단값. `alpha_validation.json` 은 **손대지 않았다**.

**바꾼 것 (형식 6종, `repair_package_contract.R`)**:

- **R1** falsification 문자열 → 객체배열. **원문을 쪼개 `expectation` 에 verbatim 보존**하고 각 항에 실측 결과를 부기. 원문 전체는 `hypothesis.falsification_original_text` 로 무손실 보존. 필드 지목은 승계 설계의 `field_dictionary_refs` 를 그대로 사용(D03_RealVol / Q01_GPA / A6_investor_flow_stock_daily / A1_RAWDATA_OHLCVS_daily / M01_Mom_12_1).
- **R2** `pit{sig_date: 2026-06-30, decision_ts: 2026-06-30}` 추가. 패널 최신 월말이며 `as_of_date` 와의 차이는 vintage lag 로 명시.
- **R3** `alpha_inheritance_cor = 0.7330` 추가 (Spearman 월별 중앙값, emitted masked score vs base M01). **< 0.95 → wt_type=discovery 유지**, 재분류 제안 불요.
- **R4** null 6종을 **실측값**으로 대체. 1차 실행의 "판정 대상이 아니라 미산출" 이라는 사유는 타당하나, Step 4-B advisory 배터리는 **기록 의무**이고 schema 가 number 를 요구한다. 값은 emitted 패널(`score_q01filtered`) 기준이며 판정 권위 아님(advisory).
- **R5** `economic_rationale` → `behavioral` (enum). 원 서술은 `economic_rationale_detail` 로 보존.
- **R6** escape_contract 에 `provenance{3필드}` 구성(기존 `provenance_*` 값을 그대로 옮김) + `production_parity_verified=false` 유지 + ast_verify 방언(node 최상위 provenance) 병기 + `vintage_available=true`(WT-009/Iter31 저장 패널은 생성 후 불변).

**수리 후 검증**: schema 위반 **13 → 0**, ast_spec_gate **block → PASS(advisory)**.

**원본 보존**: `alpha_package_prerepair_20260808.json`.

## 3. 남은 advisory 1건 — 계약 표면 분열 (인프라 결함 보고)

수리 후에도 ast_verify 가 하나를 남긴다: `노드 형상 오류(비 dict): 0.2`.

- `schema.json` 의 `ast_node.args` 는 `{"type":"number"}` 스칼라를 **명시적으로 허용**한다("윈도우 길이·클립 경계 등").
- `ast_verify.py:498` 은 비-dict 노드를 무조건 `FAIL_CONTRACT` 로 처리한다.
- 따라서 **윈도우 길이를 쓰는 모든 AST 가 FAIL_CONTRACT** 이며, init prompt 의 표준 예시 `{"op":"TS_SUM","args":[{"leaf":...},3]}` 조차 여기 걸린다.
- ast_verify 는 `{"const": 0.2}` 를 수용하지만 그 형태는 schema `ast_node` oneOf 를 만족하지 못한다 → **두 계층을 동시에 만족하는 표현이 존재하지 않는다**. ALB-005(falsification 문자열 vs 객체배열)와 **동류의 결함**이다.
- 본 패키지는 **schema 정본을 따라 스칼라를 유지**하고 이 분열을 여기 기록한다. `06_Registry/ast_operator_backlog.json` 또는 ALB 계열 백로그 등재 권고 — 본 에이전트 소관 밖이므로 실행하지 않고 보고만 한다.

## 4. 2차 실행이 추가로 실측한 것 (1차에 없던 축)

1. **F2 사이즈 교락 통제** — 1차 challenge_note C-7 이 "고변동 월 거래증가 기계 성분 미배제" 로 남긴 자리. `log(시총)` 을 같은 회귀에 넣어 재측정: D03 −0.0454(t −5.15) → **−0.0378(t −4.29), 잔존 0.83** / Q01 −0.0202(t −3.75) → **−0.0228(t −4.33), 잔존 1.13**. 사이즈 자체 기울기는 −0.0321 / −0.0478 로 크지만 필터 z 성분은 그와 별개로 살아남는다. **사이즈 대용 가설 배제** — 동시기 연관이라는 한계(1차 C-7)는 그대로 유지.
2. **Q01_EB rank-IC 의 시기 편중** — P1(2001-2014) **+0.0327 t 2.78** / P2(2015-2019) **−0.0010** / P3(2020-2026) **−0.0037**. 전표본 F1 좌측-국소화와 P1 양의 기울기는 **pre-2015 가중**이다. 1차가 잡은 "post-2017 EW-유니버스 개선 소멸(1.507→1.505)" 과 같은 방향의 독립 증거이며 더 이르다(2015). 분할 판정이 아니라 advisory 진단의 정직 라벨.
3. **D03_EWMA 순위↔평균 형상 불일치** — rank-IC +0.0400, **Harvey-t +3.50(재측정 +3.46, 3.0 통과)** 인데 5분위 평균 연수익은 ~~**Q1 +13.1% → Q5 +8.0% 단조 감소**~~ **[2026-08-09 정정]** 실제로는 **Q2 정점 역U형**이다: 구 발행 패널 **[12.91, 15.44, 14.30, 11.77, 8.19]** · 재발행 패널 **[12.96, 15.54, 14.94, 10.90, 7.93]** (Q1→Q2 +2.5%p **상승**, 하락은 Q3→Q5 국한, monotonicity 0.25). 또한 **Q5−Q1 평균 스프레드는 연 −4.72%(NW t −1.02)로 비유의**다. ⇒ 확립 사실은 "부호 역전"이 아니라 **"순위 통계 양(+) ∧ 평균 스프레드 비유의"**. "고변동 꼬리의 양의 왜도가 평균을 끌어올린다"는 기전은 Q3→Q5 구간 한정 후보로 남고, **WT-021 의 D03 standalone PORT_t −1.73 과의 연결도 이 약한 형태로만 유지**된다. 1차의 "손해의 정체는 D03 정보가 아니라 9.65종 제거의 희석(플라시보 p 0.833)" 과의 상보 관계 주장도 같은 만큼 약해진다 — 제거 대상이 "평균 기여가 높은 종목"이라는 진술은 평균 스프레드가 비유의인 이상 확립되지 않았다. 출처 = `stage_artifacts/WT_D20260808_001/verification_followup/probe_d03_quintile.R`
4. **vol-축 직교화 통제** — Q01 z 를 D03_EWMA(EWMA vol 63d)에 월별 횡단면 직교화 후 동일 필터: Δ **+1.25%/yr(t 0.84) → −0.03%/yr(t −0.03)**. 다만 **두 arm 의 차이 자체가 비유의**(+1.28%/yr, t 1.62, CI [−0.27, +2.84]) → "vol 축 재발견이다" 도 "아니다" 도 확립 불가. 확립된 것은 **Q01 필터의 양의 기울기가 vol-축 성분 제거에 강건하지 않다** 뿐이며, 이는 회수 주장을 더 약화시키는 방향이다. ⚠ MAX5 원변수 통제는 미실시(결손 명시).
5. **검정력 사전 계산** — 무작위-교체 placebo 20시드로 paired diff sd 실측(D03 0.02560 / Q01 0.01727) → t=2.0 필요 연효과 **D03 +4.47% / Q01 +3.02%**. F1 기반 사전 효과는 **0.79 / 0.81%/yr** = 필요치의 18~27%. **측정 전에** 문턱 판정을 폐기하고 구간추정으로 전환한 근거.

## 5. 자기 적대검증 (2차 실행분)

- **[ACCEPT]** 나는 P1 을 "검정력 확보 주판정" 으로 사전등록했으나 실측은 |t|<2 였다. observed/required 비가 P2 0.38 → P1 0.80 으로 나아졌을 뿐 충분하지 않았다 — "확보" 는 과한 표현이었고 정정한다.
- **[ACCEPT]** D03 Δ 가 3개 분위점 전부 음·단조·양 basis 동조라는 사실을 "유해 확정" 으로 쓰고 싶었다. 개별 |t| 1.50~1.85 이므로 **방향 일관성까지만** 진술한다. 1차의 24-seed 플라시보(p 0.833)가 이 자제를 독립적으로 정당화한다.
- **[ACCEPT]** 국면 상호작용 D03×bm_trail12 t 2.59 를 발견으로 승격하려는 유혹이 있었다. 4개 중 1개이고, `bm_trail12` 는 **trailing** 이라 승계 가설의 "상승 드리프트 국면"(forward)과 직접 대응하지 않는다. ADVISORY 유지, 승격 없음.
- **[ACCEPT]** 1차 산출물을 수리하면서 내 수치로 덮어쓸 유혹이 있었다. **판정 수치는 1차 값을 그대로 두었다** — 예: `canonical_port_t_nw_lag3` 는 내 재현값 2.357 이 아니라 1차 값 2.381 을 유지했다. 두 값의 차이(eligible set 구성 미세차)는 판정에 무관하고, 발행 주체의 측정을 존중하는 것이 No Silent Override 정합이다.
- **[PARTIAL]** 승계 가설의 `regime_scope.holds_in` 이 "상승 드리프트 국면" 을 관측 변수 `벤치 trailing 수익` 에 매핑했는데 trailing 은 forward 국면의 대용이 아니다. **승계분을 수정하지 않고** 재설계 권고로만 기록한다.
- **[REBUTTAL]** "alpha_vector 를 25종만 발행한 것은 optimizer 에 부족하다" 는 자문에 대해: `signal_matrix_ref` 로 전 패널(86,942행 × 295개월)이 넘어가고, `alpha_vector` 는 최신 sig_date 의 선별 결과다. 다만 confidence 상한이 라운드 미확립을 반영하는지는 optimizer 가 확인할 몫이므로 flag 로 남긴다.

## 6. Q-Lead escalate 판정

- HIGH severity ≥ 5 : **미해당**
- AX axiom hard FAIL ≥ 3 : **미해당**
- PIT C1(lockbox·lookahead) 위반 : **미해당** — parity 5.13e-16(1차, production 경로) / 0.000e+00(2차, WT-015 재현), 항등 1e-17, lag1 스트레스 부호 유지
- → **자동 escalate 조건 불충족**. 단 아래 3건은 Q-Lead 인지 필요:
  1. **병행 중복 실행** (in-flight 인덱싱 미발화)
  2. **R write_json 발행이 ast_spec_gate 를 구조적으로 우회** — 이번엔 사후 검사로 잡았으나 상시 보장이 아니다
  3. **schema ↔ ast_verify 계약 표면 분열** (스칼라 args)

## 7. 합리화 어휘 자가 스캔

금칙 4계열(효과 축소 원용 · 관행/실무 원용 · 안전마진 원용 · 결과 불변 원용) — 본문 **사용 0건**. 정본 목록은 `.claude/rules/answer-principles.md` 이며 여기서 재인용하지 않는다(재인용 자체가 검출기에 걸린다 — 2026-08-08 실측).
`INCONCLUSIVE_UNDERPOWERED` 와 `NEGATIVE_POWERED` 를 한 문장에 혼용하지 않았다. 본 라운드 전 arm 은 전자이며 후자는 **0건** 사용.
성과 수치 합성 없음 — 전 수치가 `canonical_screen_bt()` / `build_monthly_forward_returns()` / `required_effect_size.R` 실행 산출.
