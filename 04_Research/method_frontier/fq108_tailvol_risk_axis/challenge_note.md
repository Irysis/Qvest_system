# FQ-108 Self-Adversarial Challenge (v8.2 — 메인 세션 모델 자체 적대검증)

- **라운드**: FQ-108 단기 꼬리-변동성의 위험-축 소비 판정 (method_frontier lane, WT 아님)
- **에이전트**: risk-research
- **시점**: finalize 직전 (verdict 작성 전 제기 → 조치 후 verdict 확정)
- **AX-008**: Verification Triangulation 3-source 중 self-adversarial 1건 (나머지 = Forge / Architect)
- **자기 비평 총 8건** — ACCEPT 2 / PARTIAL 2 / REBUTTAL 4

---

## SC-1 [ACCEPT · 수정 완료] 사전등록 canary 가 primary 셀에서 발화하지 않았다

**제기**: 사전등록한 위반 주입 arm `X_oracle`(확장창 회귀에 미래 월평균 log-RV 주입)이
primary 셀에서 DM t = **−0.744 (tie)** 였다. 즉 "명백히 미래를 아는 arm"조차 유의한 개선을
못 냈다. 이 상태로 "B_d35 증분 없음"을 보고하면, **검정력 부재(측정계 사망)를
'증분 없음'으로 오독**하는 것이다. 이건 이 저장소가 반복해서 밟은 계통 결함이다
(메모리: `project-dead-checker-exitcode-collision`, `project-empty-means-pass-family` —
"발화 0"이 "안전"으로 읽히는 패턴).

**판정**: **ACCEPT**. 명백한 측정 무결성 위반급. 그대로 보고했으면 부정직한 negative였다.

**조치 (실행함)**:
1. **X_perfect** 주입 arm 추가 — v̂_i = 홀딩월 t+1 의 실현 종목분산(완전 미래참조).
   결과 **DM t = −3.420 (FIRED)**. 하네스가 진짜 개선을 검출한다.
2. **양성 대조** 추가 — `lw_nls A_base` vs `lw_linear A_base`.
   FQ-057 P1c 의 기지 결과(실 book total DM-t ≈ −4.0)를 **−3.748 로 재현**.
   외부 기준점으로 검정력을 독립 확인.

**X_oracle 이 약했던 원인 (진단)**: X_oracle 은 pooled 확장창 회귀(A2_recal) 위에 얹혀 있고,
A2_recal 자체가 A_base 대비 **유의 열화(+0.132, t +3.255)** 다. 미래 정보의 이득이
회귀 핸디캡에 상쇄됐다. 동일 머신러리 대조(X_oracle vs A2_recal)에서는 t −1.950 으로 회복.
→ verdict 에 `status = PARTIAL` 로 정직 기록, 결정적 canary 는 X_perfect 로 명시.

---

## SC-2 [ACCEPT · 판정문에 명시] PRIMARY 비교가 해로운 재보정을 업고 있다

**제기**: 사전등록 PRIMARY 는 `B_d35 vs A_base`인데, B_d35 는 pooled 확장창 회귀로 대각을
다시 만든다. 그런데 그 회귀 자체(A2_recal)가 A_base 보다 유의하게 **나쁘다**(t +3.255,
월별 레벨 추적을 잃기 때문). 따라서 PRIMARY 의 "증분 없음"을
**"D35 에 정보가 없다"로 읽으면 틀린다** — 두 효과가 섞여 있다.

**판정**: **ACCEPT**. 다만 사전등록이 이미 이 교란을 예상해 `B_d35 vs A2_recal` 를
confound control 로 등록해 두었다(값: **−0.103, t −3.729** = D35 항 자체는 유의 기여).

**조치**: 문턱·PRIMARY 셀·판정규칙은 **변경하지 않는다(no-flip)**. 대신 headline 과
`primary_verdict.confound_control` 에 두 수치를 병기하고, 결론 문장을
"D35 정보 없음"이 아니라 **"이 operationalization 이 현행 Σ 대각을 못 이긴다"** 로 정확히 서술.

---

## SC-3 [PARTIAL] H_hybrid 를 사후에 추가한 것은 사전등록 정신에 대한 압박이다

**제기**: `H_hybrid`(상관=60m 불변, 분산=60m·63일 기하평균)는 사전등록 이후 추가했고
4셀 중 3셀에서 유의 개선(−3.588 / −2.756 / −2.374)이 나온다. 이걸 근거로 배선을 권고하면
**사후 선택으로 원하는 결과를 만든 것**이 된다.

**판정**: **PARTIAL 인정**.

**인정하는 부분**: 배선 권고의 **근거로 쓰지 않는다**. verdict 에
`exploratory_post_registration` 블록으로 격리하고, `wiring_recommendation.strength =
CONDITIONAL_PENDING_PREREGISTERED_CONFIRMATION` + `blocker = FQ-108a 통과 전 배선 금지` 명시.

**전면 철회하지 않는 근거 3축**:
- **구조**: 자유 파라미터가 0 이다(θ=0.5 고정, 기하평균). 사후 튜닝으로 유의성을 만들 여지가 없다.
- **사전등록 정합**: 사전등록에 이미 `F_sv63`(같은 rawdata 레벨 채널, 회귀 형태)이 등록돼 있다.
  H_hybrid 는 **새 축이 아니라 그 축의 파라미터-없는 변형**이다.
- **정량**: 3/4 셀 일관 + 미달 셀이 하필 PRIMARY 라는 사실을 숨기지 않고 그대로 보고했다.
  (숨겼다면 "3/4 성공"으로 팔 수 있었다 — 그렇게 하지 않았다.)

---

## SC-4 [REBUTTAL] "대각을 교체하면 Σ 의 양정치성(PD)이 깨질 수 있다"

**제기**: Σ_new = D^½ C D^½ 로 재조립하면 PSD 위반 위험 — escalate trigger 대상.

**반박 3축**:
- **학술**: 합동변환(congruence transformation) `A ↦ S A Sᵀ` 는 S 가 가역이면
  관성(inertia)을 보존한다(Sylvester's law of inertia; Horn & Johnson, *Matrix Analysis*, Thm 4.5.8).
  D 는 양의 대각행렬이므로 D^½ 가역 → C 가 PSD 이면 Σ_new 도 PSD. 구조적으로 보장된다.
- **구현**: `pmax(v, .Machine$double.eps)` 로 대각 양수 강제, `pred_var_scaled` 는
  이차형식 음수를 0 으로 클립. 상관 C 는 **전 arm 동일**(처치가 대각에 국한)이라
  상관 채널發 오염 경로 자체가 없다.
- **정량 실측**: `fq108_sigma_diag.parquet` — lw_nls psd_rate **1.000**, min_ev 중앙값
  **+0.00989**, cond 중앙값 **98.14** (RF-R2 문턱 500 미달). lw_linear cond 1.00, psd_rate 1.000.
  198개월 × 2 추정기 전부에서 PD 위반 0건.

**→ escalate trigger 미발화.**

---

## SC-5 [REBUTTAL] "regime small-sample 을 pooled fallback 으로 메웠을 것"

**제기**: CRISIS 국면 n_months = 2 다. small-n 을 pooled 값으로 메우면 침묵 왜곡이다.

**반박**:
- CRISIS 의 `crash_lift_nw_t` 를 **NA 로 남겼다**(`fm_nw_t` 의 n < 10 가드).
  0 이나 pooled 로 대체하지 않았다 — 무판정이 정직한 처리.
- CAUTION(n=13, t 2.18)도 small-n 라벨을 verdict 에 남겼고, next_probe FQ-108c 에
  "CRISIS 는 n=2 로 검정 불가 → CAUTION 부터"를 명시했다.
- **정량**: `regime_decomposition` 표에 n_months 를 열로 노출해 독자가 직접 검정력을 판단할 수 있다.

---

## SC-6 [REBUTTAL] "Σ method shopping 상한(R2-C, 5) 위반"

**제기**: arm 이 10개다. 최적 arm 을 골라 결론을 만든 것 아닌가.

**반박**:
- **범위**: R2-C 가 규율하는 건 **공분산 추정기** 탐색이다. 본 라운드는 2건
  (`lw_nls`, `lw_linear`)이고 **둘 다 `.get_cor_cov` 기등재본** — 신규 estimator 발굴 아님.
  상한 5 이내. `scope_compliance.method_shopping` 에 로그 기록.
- **대각 처치 7종은 사전등록된 A/B 설계축**이다(`preregistration.json::design.diagonal_treatments`).
  측정 전에 고정됐고 정의를 바꾸지 않았다.
- **결정적으로**: 최적 arm 을 골라 자본/성과 주장을 하지 않았다. 오히려
  **PRIMARY 가 negative** 이고 그걸 headline 으로 냈다. shopping 의 이득 방향과 반대다.

---

## SC-7 [PARTIAL] crowding 하위 2성분이 바닥에 붙어 "군집 없음"으로 읽힌다

**제기**: `crowding_score_per_factor` 결과에서 `vol_concentration` 과 `passive_overlap_proxy`
가 9/9 셀에서 **정확히 0** 이었다. 이걸 그대로 "crowding_flags 없음"으로 보고하면
바닥값을 측정값으로 파는 것 — 메모리 `project-tripwire-structural-silence`
(유계 지표 + 고정 문턱 → 구조적 침묵)의 재현이다.

**판정**: **PARTIAL 인정**.

**조치 (실행함)**:
- `run_06_crowding_addendum.R` — 도달가능성 진단: `vol_concentration` 은 top-20 거래량 점유가
  중립비(20/3900 = 0.00513)를 넘어야만 0 초과인 **한쪽 바닥 clamp**,
  `passive_overlap_proxy` 는 `benchmark_tickers = NULL` 폴백(size 상위 200 겹침)이라
  소형 편향 팩터에서 구조적 0. → **"0 = 중립 이하"이지 "군집 없음"이 아니다**.
- 추가로 **고변동 끝(exposure 부호 반전)** 재측정: `vol_concentration` 이 대부분 셀에서
  0 초과로 살아났다(최대 0.0217) → 앞선 0 이 부분적으로 정렬 방향 아티팩트였음을 실증.
  (정렬 z 상위 = D35 direction `lower_better` 이므로 **저변동 끝**이었다.)
- verdict `crowding.caveat` 에 **floor-biased 라벨**을 박고 "'not crowded' 절대 단정 금지,
  시점 간 상대 변화만 유효"로 명시.

**미해결(본 라운드 범위 밖)**: 함수 자체의 한쪽-바닥 정규화는 `crowding_score_per_factor.R`
수리 대상이지 본 라운드 산출물이 아니다. → 별도 태스크로 분리.

---

## SC-8 [자기합리화 자기검증 — 기각] "PRIMARY 만 tie 니 사실상 성공 아닌가"

**유혹**: "4셀 중 3셀에서 유의 개선이 나왔으니 배선해도 된다"고 쓰고 싶어졌다.

**자기검증 결과 — 기각**. 이건 `.claude/rules/pit.md` §"금지 표현 (자동 탐지)"에
열거된 합리화 계열이다(해당 문자열은 본 문서에 옮겨 적지 않는다 — 인용 자체가
`rationalization_detector` 를 발화시키므로 규칙 참조로 대체). 사실은:
- 3/4 우세는 **사후 arm(H_hybrid)** 의 성적이지 **사전등록 arm(B_d35)** 의 성적이 아니다.
- 사전등록 arm `B_d35` 는 4셀 중 유의 우세가 `ew_top25 × total`(−2.235) **1건뿐**이고,
  나머지는 tie 또는 열화(`real_book × total` +0.724, `real_book × te` +1.571,
  `ew × te` −0.917).
- 그리고 사전등록이 PRIMARY 로 지정한 셀은 **실 book × total** 이고, 거기서 tie 다.

**→ 판정 NO_INCREMENT 유지. 문턱·PRIMARY 불변.**

### 회피 표현 grep 자기검사
verdict / challenge_note 전문에 대해 `.claude/rules/answer-principles.md` §"회피 표현 grep"
목록을 대조 확인 — **0건**(목록 문자열은 위와 같은 이유로 전재하지 않는다).
모든 불확실성은 `tie` / `무판정` / `small-n` / `floor-biased` /
`exploratory_post_registration` 라벨로 명시했다.

---

## 종합

| 항목 | 결과 |
|---|---|
| ACCEPT | 2건 (SC-1 canary 부발화 → 수정 완료 / SC-2 교란 → 판정문 명시) |
| PARTIAL | 2건 (SC-3 사후 arm 격리 / SC-7 crowding 하향편향 라벨) |
| REBUTTAL | 4건 (SC-4 PD / SC-5 small-n / SC-6 shopping / SC-8 합리화 기각) |
| Σ PD violation | **0건** (psd_rate 1.000, min_ev +0.00989, cond 98.14) |
| PIT hard violation | **0건** (팩터 as-of 198/198, 훈련창 394/394, 둘 다 fail-closed) |
| HIGH severity | 2건 (< 5) |
| AX axiom hard FAIL | 0건 |
| **Q-Lead escalate** | **미발화** (모든 trigger 미충족) |

**최종**: PRIMARY = `NO_INCREMENT` 로 확정. 사전등록 문턱·primary cell·arm 정의 무변경(no-flip).
사후 추가분(X_perfect, H_hybrid)은 전부 라벨링 후 배선 결정에서 격리.
