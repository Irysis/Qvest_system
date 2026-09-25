# 유기적 강화 설계 — 통계적 의사결정형(베이지안 순차 배분)

- 작성: 2026-09-25 16시 KST · Q 설계 패널(관점 = 통계적 의사결정)
- 작업 방식: 읽기 전용. 운영 트리·원장·레지스트리·기억 디렉터리에 쓴 것 0, R 실행 0. python 은 기존 CSV·JSON 을 읽어 집계만 했다.
- 근거 파일
  - 플랜 `C:/Users/99922/.claude/plans/qvest-1-drifting-eclipse.md`
  - 레버 감사 `scratchpad/organic/lever_audit_final.md`, `scratchpad/lever_audit/new_conv/*.csv`
  - `06_Registry/decision_register.json`(REINFORCE-ORGANIC-AUTONOMY · D-A · D-B · D-E · D-F · D-G)
  - 코드 재독 — 파일·줄 번호는 본문에 적었다.
- 수치 표기
  - [원장]: 원장을 읽어 재집계한 값
  - [감사]: 레버 감사 산출을 인용한 값(진단)
  - [판단]: Q 의 판단값
  - 결정에 쓰는 수치는 모두 R 계약이 산출한다(AX-008). 이 문서의 수치는 설계 근거이며 판정 근거가 아니다.

---

## 0. 한 줄 요지 · A 에 기여하는 경로

**한 줄 요지**

레버 효과의 계층 사후분포를 상태로 삼는다. 구조는 블록 안에 처치를 두고, 계보 무작위효과를 더하며, 규약·빈티지·표식으로 증거를 거른다. 이 사후분포는 **시장 시점 τ_sel = 2016-11-30 이전의 수익으로만** 추정한다. τ_sel 은 essence 의 첫 OOS 분할점과 같은 이미 등록된 값이다. 이 사후분포로 네 가지를 정한다.
- 예산: top-two Thompson 배분과 예측확률 기반 조기 소진
- 공간: 사후 P(효과>δ) 상한에 따른 휴면
- 선택: 축소 추정 가치
- 구조: 블록 휴면과 초모수 병합

τ_sel 이후 창은 유기체가 한 번도 최적화하지 않는 **채점 전용 창**으로 남긴다.

**설계를 정한 세 가지 실측 관찰**

1. **식별 해상도는 블록 수준이다. arm 수준에서는 식별이 안 된다.**
   - 블록 안 arm 평균 ΔCalmar 의 arm 간 SD 는 0.012~0.027 이다. 칸 하나의 짝지은 ΔCalmar SD 는 0.032~0.068 이다[감사 `arm_delta_new.csv` · `pairs.csv` 재집계].
   - arm 차이 0.02 를 이 잡음(0.05) 위에서 90% 수준으로 가르려면 arm 당 약 (2·1.64·0.05/0.02)² ≈ 67칸이 필요하다.
   - 반면 블록 평균 간 차이는 크고(B3 −0.092 대 B5 −0.010), 블록당 n 도 150 안팎이다. 따라서 블록 평균은 식별된다.
   - 귀결: 퇴출·배분의 실효 단위는 블록과 계보다. arm 휴면은 증거 하한(n_min_evidence)을 넘을 때만 드물게 켠다.
2. **유효 증거 풀은 원장의 절반 남짓이다.**
   - 원장 규모: 64 entry · 1,311 attempts · rebase 된 칸 1,193[원장].
   - 제외 대상: 선정기저 표식(`selection_basis_full_sample_ic` 60 + `_inherited` 501), `pit_c11` 35, `treatment_misspecified` 25.
   - 이를 빼면 등급이 있는 칸은 B 83 · C 530 · F 36 이다[원장].
   - 여기서 적대검증 판정이 없는 B5 칸도 빠진다. 적대검증 기록이 있는 칸은 93칸뿐이다[원장].
3. **구속 축인 OOS 는 as-of 로 직접 최적화할 수 없다.**
   - 레버 감사에 따르면 A 를 막는 축은 1,105/1,193칸에서 OOS 다. OOS 벽은 2017~20년과 2025~26년의 공통 활성 성분이다[감사].
   - 둘 다 τ_sel 이후 구간이다. 유기체가 평가 창을 보지 않는 한 이 벽을 직접 겨냥할 수 없다.
   - 이것은 결함이 아니라 설계 의도다(§2). 겨냥하는 순간 OOS retention 은 과적합 검정으로서 의미를 잃는다.

**A 에 기여하는 경로 (정직하게)**

| 경로 | 기전 | 구속 축과의 연결 | 사전확률 [판단] |
|---|---|---|---|
| ① 처리량 | 조기 소진(futility)과 B3·B5 예산 회수로 새 기저(논문)를 더 뽑는다 | 천장을 옮기는 유일한 경로는 새 기저다[감사 ③-2]. 마지막 개선 이후에 쓰인 예산이 중앙 83~86%[감사] | 신규 기저 소비 ≥1.3배가 될 확률 약 60~70%. 그 증분으로 3개월 안에 권위 A 가 나올 확률 +1~3%p |
| ② 선택 정직성 | 축소 추정으로 argmax 승자 인플레(28 entry 중 23곳)를 교정한다 | 거짓 B·A 를 줄인다. A 를 만들지는 않는다 | A 직접 기여 ≈0. 정정 방향이다 |
| ③ 사전등록 레버 예산 보장 | 레인 순서 prereg > 신규 논문을 상위 제약으로 두고, 회수한 예산이 PR-L2·PR-L1 착수를 앞당긴다 | L1 cap_core 는 OOS 를 겨냥하는 유일한 유형 | 플랜 사전확률(L1 A 3% · L2 ≤1%)에 유기체가 보태는 몫은 착수 지연 단축뿐 |
| ④ as-of 규율 | 자동 선정이 OOS 창을 안 보게 한다 | OOS 가 정직한 검정으로 남는다 | 격자에서 A 가 나올 확률은 **내려간다**. 설계 원칙 1 "고치면 A 는 멀어진다"와 같은 방향 |

**합계 판단값**: 이 설계가 있고 없음에 따른 3개월 내 권위 A(관문과 Judge PASS 까지) 확률 차이는 +1~3%p 다. 가치의 대부분은 A 확률이 아니라 다음 셋에 있다.
- 쓰이지 않는 예산을 회수한다.
- 나중에 A 가 나왔을 때 그 A 를 신뢰할 수 있게 만든다.
- 유기체 자신이 나아지고 있는지를 평가 창에서 정직하게 잴 수 있다.

---

## 0.5 지형 지도 검증 · 정정 (코드 재독)

**확인 — 지도와 일치**
- 러너 줄 번호가 일치한다:
  - 예산: L446-448 · 소진: L501 · 순서 트리거: L517 · room: L557 · 시드: L576
  - `.winner_of`: L664-699(which.max L684) · 승자 호출: L726/729/736 · 바닥 argmax: L754-783 · 격자 소진: L1263
- 게이트: `rf_budget_auto`(:92-96) · `rf_budget_want`(:98-101). 감산 경로는 0 이다.
- `rf_a_eligibility` ⑤ vintage_flag(:552-559)는 attempt 자기 표식만 읽는다.
- `rf_record_decision` 에는 policy·shadow 필드가 있다(ledger:710-711, 743-745).
- `rf_decisions.jsonl` 3행은 모두 `direction`(pi_dir_v0 · advisory)이다[원장]. A 관문 결정 기록은 배선돼 있지만 러너가 정지 중이라 0행이다.
- policy_state.R 의 `pol_transition` 은 env 인자를 받는다. 기본값은 `QVEST_POLICY_UNATTENDED=0` 이다(DIR-ABSORB-ITEMS ④).

**정정 1 — "퇴출 = 카탈로그 status 쓰기 1회, 러너 무수정"은 비중 arm 에서 틀리다**
- `rf_weight_arms.R:40` 은 **denylist**(`retracted/withdrawn/failed`)다. 새 status 값(예: 휴면)은 필터를 그대로 통과한다.
- overlay 픽커(`rf_overlay_arms.R:47`)는 active 만 통과시키는 allowlist 라서 예외다.
- factor lifecycle(`rf_factor_arms.R:273`)은 `.cache/factor_db/factor_registry.json` 정본이고, 팩터 DB 빌더와 2계층이 함께 소비한다.
- 따라서 유기체는 **정본 카탈로그·registry 에 쓰면 안 된다**. 휴면은 유기체 전용 목록으로 두고, 두 지점에서 적용한다.
  - 칸 조립 뒤 trim
  - 픽커 `exclude` 인자

**정정 2 — B5 증거는 원 Δ 가 아니라 T3 플라시보 보정 Δ 여야 한다**
- 원 ΔCalmar 로 보면 B5 최고 arm `multivar_channel_tilt` 는 +0.056 · P>0 1.00(n=12)이다[감사].
- 그러나 B5 에서 유효한 G2 pass 는 0 이고, 노출을 짝지은 플라시보가 관측값을 넘는다(메모리 09-21).
- 원 Δ 를 증거로 쓰면 사후분포가 노출 축소를 타이밍 가치로 오인한다.

**정정 3 — 0칸 설계는 격자 폴백이 된다(지도 확인)**
- 러너 L389 `if (length(.cc))` 조건 때문이다. 블록 휴면은 설계 파일이 아니라 칸 조립 뒤 trim 으로 구현해야 한다.

**보강**
- **as-of 재료가 이미 있다.**
  - rebase 된 1,193칸 모두 형제 판에 `bt_result.rds`·`03_period_returns.csv`·`05_benchmark_returns.csv` 가 있다(`measurement_regime.remeasure_path` 1,193/1,193 존재 확인[원장]).
  - `essence_diagnostics()`(essence_score.R:401)는 이 rds 에서 `oos_calendar_components` 를 재산출한다. 이 값은 τ 마다 is_ir/oos_ir 이고, 활성 = ret_net − benchmark_ret 이다(:208-219, :348).
  - 단, auth json 에는 진단 필드가 없다(확인). 절단 창 PT·Calmar 는 여전히 P1-03 `sa_subwindow` 가 필요하다. 재시뮬 없이 rds 를 재채점하면 된다.
- 원장 상태[원장]
  - active 1 = `RP_20260924_052517_7308_adapted_rulefast`(26/41)
  - exhausted 41 · parked 21
  - entry `max_attempts` 는 26~44(26 entry)이고, 38 entry 는 전역 35 를 쓴다.
- **as-of 선례가 이미 가장 엄격하다.**
  - P0-08 `rf_factor_arms.R::.rff_asof` 기본값 = `fixed_axes.start_date`(2005-01-01), 즉 **백테스트 창 데이터를 전혀 쓰지 않는** 선정이다.
  - `reinforce_program.json::blocks[B1].selection_asof` · `B7.selection_asof` 도 같다.
  - 이 선례는 §2 의 선택지 판정에 결정적이다.
- B3 휴면은 가능하다. B4 에서 w3 가 NULL 이면 유니버스가 `k200_kq150` 로 폴백한다(러너 L947). 휴면 블록의 LOO 칸은 서명 dedup 으로 닫힌다.

---

## 1. 네 층 설계

### 1.0 공통 — 증거표 · as-of 효용 · 계층 모형

**증거 단위 i (측정 칸) 자격 — 전부 충족해야 한다**

| 코드 | 조건 | 원천 |
|---|---|---|
| E1 | `measurement_regime.key` == 원장 `current_axis`(exec_v2_close_t1) | 원장 |
| E2 | `vintage_flags` 에 `pit_c11`·`treatment_misspecified` 가 없다. `selection_basis_full_sample_ic(_inherited)` 표식이 있으면 **B1 팩터 집합 레버의 증거에서만 제외**하고, 다른 블록 Δ 에는 공변량 표식으로 넣는다. 칸과 바닥이 같은 팩터 집합을 공유하므로 Δ 에서 대부분 상쇄된다 | 원장 |
| E3 | `essence$inherited_from` 없음 · terminal 아님 · `cell_no_treatment` 아님 | 원장·jlog |
| E4 | B5 는 adversary verdict(pass/fail/not_candidate)가 있을 것. 관측값 = T3 플라시보 보정 Δ(관측 − 플라시보 중앙). verdict 부재(unverified)는 제외 | `rf_overlay_adversary.R:220` |
| E5 | `window_deviation_months` ≤ `diagnostics.window_allowance_months`(12, D-C) | essence 진단 |
| E6 | 바닥 칸이 같은 규약·같은 `measurement_regime.data_vintage` 일 것. 비동시 대조 금지 — 추세가 있으면 1종 오류가 부푼다(Lee & Wason 2020) | 원장 |
| E7 | as-of 뷰(아래)가 있을 것 | 형제 판 |

**as-of 지표**
- m_{i,j} = `essence_score(bt_result_i[date ≤ τ_sel])` 의 축 j 이다.
- j ∈ {PT, Calmar, SR, CAGR, OOS}. OOS 는 **창 안** 분할(0.55/0.65/0.75)로 계산한 retention 이다. 산출 계약은 P1-03 `sa_subwindow` 다.
- τ_sel 은 `constraint_defaults.json::diagnostics.oos_calendar_splits[1]` 을 참조만 한다(새 수치가 아니다).
  - 이 날짜는 2005년 시작 칸에서 등급의 0.55 비율 분할과 같도록 등록된 값이다(essence_score.R:256 주석).
  - 따라서 등급의 세 OOS 창(0.55·0.65·0.75)은 모두 τ_sel 이후이고, 자동 선정과 **완전히 분리**된다.

**부족분과 효용**

```
S_i   = Σ_j max(0, (θ_j^τ − m_{i,j}) / s_j)
θ_j^τ = θ_j (tier_graduation, 읽기 전용) ;
        PT 만 θ_PT^τ = θ_PT · sqrt(T_τ / T_full)
        — NW-t 는 IR 이 고정일 때 √T 에 비례한다는 유도식이지 새 문턱이 아니다. 등급에는 절대 쓰지 않는다
s_j   = 축 j 의 칸 수준 잡음 SD (as-of 창 · 아래 잡음 모형)
u_i   = Ŝ_{f(i)} − S_i        (부족분 감소 · 양수 = 좋음)
Ŝ_f   = 바닥 칸의 **축소 추정** 부족분
```

- 바닥은 argmax 로 뽑힌 칸이라 원값이 부풀어 있다. 원값을 기준선으로 쓰면 Δ 가 음으로 편향된다. 레버 감사에서 "B1 이 선행 칸 중앙값 기준이면 + 로 뒤집힌다"고 나온 기전이 이것이다.
- **목표 축 상한**: S 는 문턱을 넘은 축에서 0 이다. 문턱 위로 더 올라간 부분은 점수를 받지 않는다(Goodhart 방지 · 메모리 "상한은 목표 축에").
- 보조 지표: z_i = 1[ΔCalmar_τ > 0 ∧ ΔOOS_τ > 0]. 두 구속 축을 동시에 올렸는지를 본다. 보고와 동률 해소에만 쓴다.

**계층 모형**

```
u_i = α_{b(i)} + θ_{ℓ(i)} + η_{r(i)} + γ·Ŝ_{f(i)} + ε_i ,   ε_i ~ N(0, σ_i²)
θ_ℓ | b ~ N(0, τ_b²)        (처치 ⊂ 블록 — 레버 키 ℓ = (block, 처치 id, design_source))
α_b ~ N(0, s_α²)            (블록 효과 — 위치 사전은 0 에 중심)
η_r ~ N(0, ω²)              (계보 무작위효과 — 같은 기저 위 칸들의 상관)
γ   ~ N(0, s_γ²)            (평균회귀 공변량 — 나쁜 바닥일수록 개선이 쉽다)
τ_b, ω, s_α ~ Half-Normal(scale)   — Gelman(2006)
```

- **사전**
  - 위치 사전은 0(중립)이다.
  - 레버 감사의 블록 Δ 표는 τ_sel 이후 수익을 포함하므로 **위치 사전으로 쓰지 않는다**(§2 해석 (iii)). 척도만 쓴다. 분산 초사전의 크기 규모는 arm 간 SD 0.012~0.027, 칸 SD 0.03~0.07 을 u 단위로 환산해 정한다.
  - 척도는 잡음의 2차 모멘트이지 어떤 레버를 편드는 정보가 아니다.
- **잡음 σ_i**
  - 칸 i 와 바닥의 일간 수익 차 계열을 as-of 창에서 순환 블록 부트스트랩한다. 블록 길이는 Politis-White(2004)로 정하고, `adv_block_len`·`adv_circular_block_perm` 을 재사용한다(rf_overlay_adversary.R:168,184). 여기서 u 의 SE 를 얻는다.
  - P1-06 통제칸(null 희석)이 가동되면 블록별 통제칸 분산과 대조해 **큰 쪽**을 쓴다.
  - 위상쌍 B6_32/33 은 계통 효과라 SE 원천에서 제외한다[감사].
- **적합**
  - 켤레 정규 Gibbs 를 base R 로 구현한다. draws·burn 은 config 에서 읽는다.
  - 시드 = md5(원장 스냅샷) ⊕ policy_id 다. 같은 원장이면 같은 결정이 나온다(결정론 해시 검사).
- **출력**: `06_Registry/organic/state.json`
  - {ledger_md5, tau_sel, fit_at, 블록·레버·계보 사후 요약, 사후예측 표본 요약, 적합 진단(R̂·ESS)}
  - 러너는 이 캐시만 읽고 적합을 하지 않는다.
- **근거 문헌**
  - 계층 축소: Efron & Morris 1975. 팩터 복제 문제에 계층 베이지안 축소를 적용한 선례: Jensen·Kelly·Pedersen 2021/2023.
  - 비동시 대조: Lee & Wason 2020.
  - 적응 배분의 편향과 추세 위험: Thall·Fox·Wathen 2015.

---

### 1.1 예산 층

**상태 변수**
- entry 별 {used, MAXA, 블록별 남은 계획 칸, 측정 블록 수}
- 블록·레버·계보 사후
- 승격 사슬 깊이
- 레인별 대기(충실구현 요청 · prereg · 승격 · 반사실)

**결정 규칙**

- **(B1) 블록 칸 배분 — top-two Thompson (Russo 2020)**
  - 남은 슬롯 k=1..K 마다 사후 표본 한 벌을 뽑는다.
  - 각 블록의 가치: v_b = α̃_b + max_{ℓ∈A_b} θ̃_ℓ + η̃_r + γ̃·Ŝ_f
    - A_b = 이 entry 에서 아직 재지 않았고 휴면도 아닌 처치.
    - 설계 전인 B1·B5 는 max 항을 N(0, τ̃_b²) 새 표본으로 대신한다.
  - 확률 β 로 argmax 블록을 고르고, 1−β 로 argmax 와 다른 블록이 나올 때까지 다시 뽑는다.
  - n_b = clip(횟수_b, n_min_b, n_grid_b). n_grid_b 는 격자·설계가 낸 칸 수다. 유기체는 칸을 **늘리지 않는다**. 가산은 설계 레인의 몫이다.
  - B1(블록 선두)·B4(결합, 마지막)는 배분 대상 밖에 두고 격자대로 간다. B4 는 다른 블록 승자를 합치는 칸이라 순서와 존재가 고정이다.
- **(B2) 조기 소진 — 예측확률 무익성 (Saville et al. 2014)**
  - 블록 경계마다 계산한다: P_cont = P( max_{k≤K_rem} u_new,k > δ | D ). K_rem = 남은 계획 칸, δ = `futility_delta_sigma`·σ̄_u.
  - P_cont < `futility_p` ∧ used ≥ `n_min_entry` ∧ 측정 블록 수 ≥ `min_blocks_before_futility` 이면 entry 예산 정책 = used 로 둔다.
  - 그러면 다음 tick 에 **기존 경로**(L501 `used >= MAXA` → `.exhaust_and_delegate` → next_paper)로 소진된다.
- **(B3) 승격 예산 — D-F soft 형식화**
  - 자식 예산 = clip(round(B_base · P(u_child,best > δ | D)), B_min, B_base).
  - P < `promote_p_min` 이면 승격하지 않고 신규 논문으로 넘긴다.
  - D-G "승격 세대당 신규 논문 ≥1" 은 상위 제약으로 유지한다.
- **(B4) 레인 순서**
  - D-G(prereg > 신규 논문 > 승격 > 반사실)를 **상위 제약**으로 둔다. 같은 순위 안에서만 P_cont 로 정렬한다.
  - P1-08 FIFO(LIFO → exhausted_at 오름차순)는 선행 수리다.
- **불변(적응 대상 아님)**
  - `daily_cap`·`parallel_cells`·`worker_timeout_sec`·`cell_max_retry` 는 자원 안전선이다. 유기체의 writer 허용목록 밖이다.

**입력**
- 원장 attempts(`cell_code`·`essence.block`·`measurement_regime`·`vintage_flags`·`adversary`·`terminal`)
- as-of 뷰
- `entry.parent/carry`
- config

**갱신 주기**
- 사후 재적합: 원장 md5 가 바뀐 블록 경계 이벤트 + 야간 1회. `rf_organic_tick` 레인이 러너 직전에 돈다.
- 러너는 tick 마다 캐시를 읽는다. 캐시가 오래됐으면(ledger_md5 불일치 ∧ age > `state_max_age_h`) 그 tick 은 pi0 로 돌고 로그를 남긴다(무성 폴백 금지).

**파라미터** (`reinforce_auto_config.json::organic.budget.*`)

| 키 | 초기값 | 근거 |
|---|---|---|
| `thompson_beta` | 0.5 | Russo 2020 의 top-two 기본값 |
| `futility_p` | 0.10 | 판단 사전값. Saville 2014 는 무익성 문턱을 설계로 보정하라고 권한다 → O2 리플레이로 보정. 보정 전 live 금지 |
| `futility_delta_sigma` | 1.0 | 잡음 1σ 밴드. D-F "잡음 파생 여백" |
| `n_min_entry` | 격자 B1 칸 수 + 한 블록 칸 수 | 격자에서 재도출(하드코딩 금지) |
| `min_blocks_before_futility` | 2 | B1 + 위험 블록 1개 — 블록 순서 규칙(rf_lesson.R:106-)과 정합 |
| `n_min_block` | {B3:1, 그 밖 0} | 레버 감사 ④ "B3 는 유니버스 의존 유일 진단원" |
| `promote_p_min` · `B_min` | 0.2 · 격자 B1+B4 칸 수 | 판단 → O2 보정 |

**러너 개입 지점 (본체 불변 · 국소 변경)**
- `rf_runner_gates.R:98-101` `rf_budget_want(auto, manual, policy = NULL)`
  - policy 가 live 일 때만 `policy$max_attempts` 를 쓴다. 이 경우 auto 아래로 내릴 수 있다. 현행 코드에는 감산 경로가 없다.
  - policy 가 NULL 이거나 shadow 면 현행 max(auto, manual) 과 비트 동일하다.
- 러너 L448: `.want <- rf_budget_want(.auto, E$max_attempts, policy = rf_organic_budget(.OST, BID))` (1줄)
- 러너 L143-144 옆: `.OST <- rf_organic_state(ROOT, log = jlog)` (1줄)
- `reinforce_ledger.R:288-301` `rf_record_entry_budget`: `max_attempts_history` append 를 추가한다(현행은 덮어쓰기라 롤백 불가).
- `reinforce_auto_next_paper.R` 승격 분기(L130-215): 자식 entry 개설 직후 `rf_record_entry_budget(child, rf_organic_child_budget(...))` (1줄).

---

### 1.2 공간 층 (arm 생성 · 휴면)

**상태 변수**
- 레버 ℓ 별 사후 θ_ℓ
- 유효 증거 n_eff,ℓ 와 계보 수
- 휴면 목록 `06_Registry/organic/dormancy.json`: {id, block, since, reason, decision_id, revive_after, policy_id}

**결정 규칙**

- **(S1) 휴면 (플랫폼 시험의 무익성 탈락 — Saville & Berry 2016)**
  - n_eff,ℓ ≥ `n_min_evidence` ∧ 계보 수 ≥ `r_min` ∧ P(α_b + θ_ℓ > δ | D) < `dormant_p` 이면 dormant.
  - **부활(히스테리시스)**: 셋 중 하나면 부활한다.
    - P > `revive_p`
    - 규약·빈티지 epoch 가 바뀜
    - `dormant_weeks` 가 지남 → probation(1칸)으로 복귀
  - 휴면은 "탐색 우선순위에서 뺀다"는 뜻이다. **후보 자격을 바꾸는 퇴출이 아니다.** 정본 status 는 불변이다.
- **(S2) 생성 억제 — D-G "overlay_propose 는 dead 동안 정지"의 형식화**
  - B5 생성 레인(`rf_overlay_propose.sh` · B5 설계 새 arm)의 일일 쿼터는 P(α_B5 > 0 | T3 보정 증거) ≥ `b5_gen_p` 일 때만 0 보다 크다.
  - 현재는 G2 유효 pass 0 이라 사후가 이 문턱을 넘지 못할 것으로 예상한다[판단].
- **(S3) 새 처치 유형 — 사전등록 판정을 통과한 것만(예: PR-L1 cap_core 가 confirmed 일 때)**
  - 사전 θ ~ N(α̂_b, κ·τ̂_b²) 로 분산을 팽창한다(κ = `new_type_var_inflation`). 그러면 Thompson 이 자연히 탐색한다.
  - 유기체는 새 유형을 **만들지 않는다**. 코드 생성은 금지다. 사전등록 경로만 받는다.
- **(S4) B1 팩터 수준 휴면 = v1 범위 밖**
  - B1 은 LLM 설계가 대체하고, 팩터 풀 선정은 D-E·P0-08 as-of 규칙의 소관이다.
  - 유기체는 B1 에 대해 칸 수(예산 층)만 정한다.

**입력**: 증거표(E1~E7), 사후, 방출 원장 `overlay_arm_ledger.jsonl`(생성 arm 출처), 카탈로그 status(읽기만).

**갱신 주기**: 주 1회 배치. 진동을 막으려고 한 번 휴면에 들면 최소 `dormant_weeks` 를 유지한다. 결정마다 `rf_record_decision(kind="organic_arm_status")` 를 남긴다.

**파라미터** (`organic.space.*`)

| 키 | 초기값 | 근거 |
|---|---|---|
| `dormant_p` · `revive_p` | 0.05 · 0.15 | 판단 · 히스테리시스. O2 보정 |
| `n_min_evidence` · `r_min` | 20칸 · 3계보 | §0 ① 신호대잡음(arm 식별 약 67칸) — 20칸에서는 크게 음인 arm 만 걸린다(의도된 보수) |
| `dormant_weeks` | 8 | policy_state `tombstone_window_weeks` 8 과 같은 창 |
| `b5_gen_p` | 0.2 | 판단 |
| `new_type_var_inflation` | 4 | 판단 — 사전표준편차 2배 |

**러너 개입 지점**
- 러너 L436 뒤(상주 칸 삽입 후): `cells <- rf_organic_apply_cells(cells, E, .OST, log = jlog)` (1줄)
  - 설계 칸·격자 칸·상주 칸 모두에서 휴면 arm 과 휴면·축소 블록 칸을 뺀다(층 1.4 와 공용).
- L597-629 `.done_arms` 에 `rf_organic_exclude("B5", .OST)` 합류 · L633-640 `.done_wt` 에 `rf_organic_exclude("B2", .OST)` 합류 (각 1줄).
- 생성 레인 셸 2개(`rf_overlay_propose.sh` · `rf_b5_design.sh`)가 `state.json` 의 쿼터를 읽는다(각 수 줄).

---

### 1.3 선택 층 (블록 승자 · 바닥 · carry · 승격)

**상태 변수**: 후보 칸 c 의 as-of 효용 u_c · σ_c · 레버·블록·계보 사후.

**결정 규칙**

- **축소 가치** (Efron-Morris 1975 · Jensen·Kelly·Pedersen)

  ```
  û_c = w_c·u_c + (1 − w_c)·(α̂_b + θ̂_ℓ + η̂_r + γ̂·Ŝ_f) ,  w_c = V_c / (V_c + σ_c²)
  V_c = 레버 수준 사전예측 분산(τ̂_b² + 사후 불확실성)
  ```

- 블록 승자와 바닥 = 자격 후보 중 argmax û_c.
  - 후보 자격 술어(`rf_candidates_keep`·`RF_ROLE_CHECKS`·`rf_adversary_ok`)는 **불변**이다.
- **carry 채택**: P(u_winner > 0 | D) ≥ `carry_p`.
  - 현행 `.beats_carry` 의 "PT > carry" 를 대체하는 안이다.
- **승격**
  - P(u_child,best > δ | D) 로 판정한다. 연장 여백 0.01(짝지은 SE 약 0.07 대비 잡음 이하)을 잡음 파생 기준으로 바꾼다(D-F).
  - 짝지은 부트스트랩 하한 >0 을 하드 규칙으로 쓰지 않는다(플랜 '하지 말 것' 5). 확률은 soft 예산(B3)에만 쓴다.
- **승자 추론 보고**
  - 승자 칸 요약에 Andrews·Kitagawa·McCloskey(2019) 조건부·하이브리드 구간을 병기한다.
  - max-of-k 과대평가를 서술 수준에서 교정한다. 등급은 불변이다.
- **pi0 = 현행 비트 동일**
  - `blocks[].select_winner_by` 를 **실제로 읽는다**(죽은 선언 해소 · P1-05).
  - B6·B7 은 승자 함수가 없는데, `phase_control`·`success_criterion` 을 순수 술어로 신설해 shadow 로 병기한다.

**★live 전환 제한**
- §2 D-N 결정 전까지 선택 층은 **shadow 전용**이다.
- 격자 live 선택의 정본은 09-23 플랜 확정 '선택 규율 (A)'(전기간 데이터 유지 + sweep 계상 + 서류)다.
- 선택 층을 as-of 로 live 전환하는 일은 성과로 판정할 수 없는 **원칙 문제**다.
  - as-of 선택기는 as-of 효용에서 당연히 이긴다.
  - 전기간 argmax 는 τ 이후 창을 이미 봤으므로 공정한 평가 창이 없다.
  - 그래서 기계 권한 밖이다.

**입력**: as-of 뷰 · 사후 · 역할.

**갱신 주기**
- 러너 tick 마다 캐시된 사후를 쓴다.
- 새 칸의 as-of 뷰는 워커가 측정 직후 산출한다(`rf_cell_worker.R` 에서 bt_result 를 메모리에 둔 채 `sa_subwindow` 호출 → 형제 `essence_asof_<τ>.json`).
- **결손 규칙**: 후보 중 as-of 뷰가 하나라도 없으면 그 결정 전체를 pi0 로 돌리고 `asof_view_missing` 을 남긴다. 한 argmax 에 두 창을 섞지 않는다. 규약 혼합 가드와 같은 원리다.

**파라미터** (`organic.select.*`)

| 키 | 초기값 | 근거 |
|---|---|---|
| `value` | `"shrunk_u"` | Efron-Morris 1975 |
| `carry_p` | 0.8 | 플랜 PR-L2 성공 기준 "P(Δ>0) ≥0.8" 과 같은 척도 |
| `report_winner_ci` | `"akm_hybrid"` | Andrews·Kitagawa·McCloskey 2019 |

**러너 개입 지점**
- L683 `.winner_of` 의 `vapply(cand, function(a) .metric(a, by))` → `rf_select_value(a, by, role = paste0("winner_", bid), ost = .OST)` (1줄)
- L766(진단)·L774(바닥) → `rf_select_value(a, "port_t", role = "floor", ost = .OST)` (2줄)
- pi0 에서 `rf_select_value` ≡ `.metric` 이다(identical 회귀 검사).
- carry: `rf_runner_gates.R:629-636` `rf_floor_carry_gate` 옆에 `rf_carry_decide()` 순수 함수를 신설한다. shadow 기록만 한다.
- 승격: `rf_promote.R:93-124` `rf_promote_decide(..., organic = NULL)` 인자를 추가한다. NULL 이면 비트 동일이다.

---

### 1.4 구조 층 (블록 휴면 · 병합)

**상태 변수**: 블록 사후 α_b · 블록 최대 처치 효과 사후 · 블록 유효 증거(칸·계보).

**결정 규칙**

- **(T1) 블록 휴면**
  - n_eff,b ≥ `n_min_block_evidence` ∧ 계보 ≥ `r_min_block` ∧ P(α_b + max_ℓ θ_ℓ > δ | D) < `block_dormant_p` 이면 n_b = `n_diag_b` 로 줄인다.
  - `n_diag_b` = B3 1(진단칸), 그 밖 0.
  - 부활 규칙은 S1 과 같다.
- **(T2) 초모수 병합 (모형 수준)**
  - 두 블록이 P(|α_b − α_b'| < δ) > `merge_p` ∧ 같은 축 계열이면 α 를 공유하는 하나의 집단으로 풀링한다. 파라미터 수를 줄이고, 운영상 예산 풀을 공유한다.
  - 격자 블록 목록·코드는 불변이다.
- **(T3) B4 결합 축 = 휴면 아닌 블록만**
  - 휴면 블록 LOO 칸은 서명 dedup 으로 닫힌다. L947 에서 w3 가 NULL 이면 `k200_kq150` 로 폴백하는 것을 확인했다.
- **(T4) B7 = 사전등록 전용 블록**
  - 과거 25칸은 `treatment_misspecified` 라 증거가 0 이다. PR-L2 판정 전까지 유기체 배분은 0 이고, 사전등록 경로가 칸을 연다.
- **(T5) 블록 순서는 건드리지 않는다**
  - `rf_block_order_decide` 를 유지한다(09-18 NO-GO · 플랜 '하지 말 것' 1).
- **(T6) 새 축·새 블록 추가 = 기계 권한 밖**
  - 엔진 코드가 필요하고, 러너는 코드를 생성하지 않는다. 사전등록 경로다.

**입력**: 증거표 · 사후 · prereg 판정(`rf_record_decision(kind="prereg_verdict")`).

**갱신 주기**: 주 1회 + 사전등록 판정 이벤트.

**구현**
- `06_Registry/organic/structure_policy.json`: {block: {n, state, since, decision_id, policy_id}}
- `rf_organic_apply_cells` 가 이 파일을 읽는다.
- **`reinforce_program.json` 에는 쓰지 않는다.** `fixed_axes`(헌법 INV-7)가 같은 파일에 있기 때문이다.

**파라미터** (`organic.structure.*`)

| 키 | 초기값 | 근거 |
|---|---|---|
| `block_dormant_p` | 0.05 | 판단 |
| `n_min_block_evidence` · `r_min_block` | 30칸 · 5계보 | 판단 — 레버 감사의 블록별 n 147~217 · 계보 14~24 대비 보수 |
| `merge_p` | 0.9 | 판단 |
| `n_diag` | {B3:1} | 레버 감사 ④ |

**러너 개입 지점**: 1.2 의 `rf_organic_apply_cells` 와 같은 지점(추가 0줄).

---

## 2. ★D-E 정합 — 적응 층의 선정 통계는 C1/C14 에 걸리는가

### 2.1 문제: 이미 결정된 세 규율이 한 함수에서 만난다

| 규율 | 내용 | 현 구현 |
|---|---|---|
| **09-23 선택 규율 (A)** (플랜 확정표) | 격자 선택은 "sweep 정직 표기 + 강건 선택(CSCV·축소) + A 후보 구속 축 다중검정 서류 — **전기간 데이터 유지**" | 승자·바닥·carry·승격 = 전기간 essence argmax 5곳. 대가는 N·DSR(D-A)·서류(D-B)로 치른다 |
| **09-23 D-E** (pit.md C1) | "평가 창 결과를 소비하는 자동 선정 규칙도 C1/C14. 팩터·arm·슬리브를 전기간 IC·ic_bad·상관으로 고르면 시점 t 보유를 미래 통계로 정한 것. 선정 통계는 as-of(Usable_Date <= 결정 시점)로만" | P0-08: as-of = `fixed_axes.start_date`(2005-01-01). **백테스트 창을 전혀 안 쓰는** 가장 엄격한 판. 22632 계보 = `selection_basis_full_sample_ic_inherited` |
| **09-25 ORGANIC** | 적응 층이 "선택 기준"까지 결정한다. 가드 "**as-of 정보만**" | 미구현 |

**두 개의 시간축**
- **연구 시점 as-of**: 이미 측정된 칸만 본다는 뜻이다. 인과적 컨트롤러라면 자동으로 충족된다. 가드로서는 **공허**하다.
- **시장 시점 as-of**: 시점 t 의 보유를 정하는 통계가 t 이후 데이터를 쓰지 않는다는 뜻이다. D-E 의 뜻이 이것이다.

**핵심 사실**
- 2005년부터 보유하는 **고정 구성**을 백테스트 성과로 고르는 순간, 선정 통계는 반드시 (t, 선정 창 끝] 을 쓴다.
- 따라서 D-E 문언을 완전히 만족하는 길은 둘뿐이다.
  - (a) 성과 기반 선정을 하지 않는다. P0-08 의 start_date 방식이다.
  - (b) 선정을 전략의 일부로 만든다. 워크포워드 이음 NAV: τ_k 에서 ≤τ_k 로 고르고 (τ_k, τ_{k+1}] 만 보유한다.
- 적응 층이 "선택 기준"을 맡으면 09-23 선택 규율(전기간)과 ORGANIC 가드(as-of)가 **같은 함수에서 충돌**한다. 이 충돌은 정면으로 결정해야 한다.

### 2.2 선택지

- **(i) 계상형 — 연구 과정 선택 = 다중검정 대상이지 PIT 가 아니다**
  - 격자 argmax 와 적응 층 모두 전기간 통계를 쓴다. 대가는 시행 회계(N_cell·N_program·N_policy)와 서류(DSR·PBO)로 치른다.
  - C1 은 다음 둘에 한정한다.
    - ① 보유 규칙 **내부**에서 시점마다 쓰이는 통계(예: 가중 = 전기간 IC)
    - ② **N 에 계상되지 않은 스캔**(B1 픽커가 343종을 IC 로 훑었으나 N 에 없음)
  - ORGANIC 가드 "as-of" 는 연구 시점으로 읽는다.
- **(ii) 워크포워드형(엄격) — 성과를 소비하는 모든 자동 선정은 τ_k as-of, A 대상은 이음 NAV**
  - 적응 층과 격자 내용 선정(승자·바닥·carry·승격) 모두 ≤τ_k 통계만 쓴다.
  - A 후보 = 선정 절차의 워크포워드 이음 보유 패널을 `remeasure_from_holdings` 로 채점한 NAV 다.
    - τ_1 이전 보유는 문헌 기저 또는 as-of-2005 규칙 구성이다.
  - 성과 선정 계보의 고정 구성 칸은 "연구 측정"으로 남고 A 발행은 보류된다(새 보류 코드).
- **(iii) 혼합(평가 창 불가침) — 적응 층은 시장 시점 as-of τ_sel, 격자 live 선택은 09-23 규율 유지**
  - 적응 층 네 층의 모든 통계(예산·휴면·구조·선택 가치 함수 제안)는 ≤τ_sel 수익으로만 계산한다.
    - τ_sel = essence 첫 OOS 분할점 2016-11-30(등록값)이다.
    - τ_sel 이후 창은 유기체의 채점(메타 목표)에만 쓴다.
  - 격자의 live 내용 선정은 09-23 규율(전기간·계상)대로 유지한다. 유기체는 as-of 가치 함수를 shadow 로만 병기한다.
  - 성분 선정(팩터·arm·슬리브 id 를 통계로 고르는 규칙)은 D-E·P0-08 을 그대로 둔다(start_date as-of · 완화 없음).
  - 유기체의 휴면은 "후보 선정"이 아니라 "탐색 우선순위"로 정의한다. 휴면된 arm 의 기측정 칸은 N 에 그대로 남는다.

### 2.3 일관성 표

| 항목 | (i) 계상형 | (ii) 워크포워드형 | (iii) 혼합 |
|---|---|---|---|
| 격자 승자·바닥 (전기간 argmax) | 현행 그대로 · 계상 | ✗ — 고정 구성 A 불가 | 현행 live 유지(09-23) · 유기체 as-of shadow 병기 |
| carry | 일관 | ✗(이음 NAV 로만) | 일관(현행) |
| 승격 | 일관 · 유기체 예산은 전기간 사후 | ✗ | 일관 · 유기체 예산은 as-of 사후 |
| 22632 표식 (전기간 IC 팩터 집합 승계) | **부분 불일치**. 같은 "전기간 통계 선정"인데 argmax 는 계상, IC 는 C1 이다. 표식을 "미계상 스캔" 사유로 재정의해야 일관된다. 그러면 스캔을 계상하는 순간 표식이 풀리는 경로가 생겨 D-E 가 약해진다 | 일관(특수 사례) | 일관(IC 가 평가 창을 소비) |
| P0-08 선례 (start_date) | 과잉 엄격(무해) | 일관 | 일관(완화하지 않음) |
| 적응 층 | 평가 창을 직접 최적화한다 → OOS retention 이 유기체의 목적함수가 된다(Goodhart). "as-of" 가드는 공허 | τ_k as-of | τ_sel as-of → 메타 채점 가능 |
| 현 원장 A 가능 계보 | 현행과 같다(표식 칸 제외) | **0 에서 재시작** | 현행과 같다 |
| OOS retention 의 의미 | 유기체 최적화 대상 → 과적합 검정 의미 상실 | 선정이 OOS 창을 전혀 안 본다. 다만 IS = 기저 구간이라 비율의 의미가 바뀐다 | 유기체에 대해서는 정직. 격자 argmax 에 대해서는 여전히 계상 대상 |
| 필요 인프라 | 서류(P1-04) | 이음 NAV 계약 · τ_k 뷰 3종 · 새 보류 코드 · BOOK 추적(절차 재현) | `sa_subwindow`(τ_sel) · 워커 as-of 뷰 |

### 2.4 Q 권고 — (iii) 혼합

1. **이미 결정된 세 규율을 모두 지키는 유일한 해석이다.**
   - 09-23 선택 규율(전기간·계상)은 격자 live 에 그대로 남는다.
   - D-E·P0-08(성분 선정 as-of)은 완화하지 않는다.
   - ORGANIC 가드 "as-of 정보만"은 **비공허한 시장 시점 의미**로 적응 층 전체에 걸린다.
2. **메타 목표를 정직하게 잴 수 있는 유일한 해석이다.**
   - (i) 에서는 유기체가 평가 창을 최적화하므로, 유기체가 나아지는지를 잴 보류 창이 없다.
   - (iii) 은 τ_sel 이후를 유기체가 한 번도 최적화하지 않는 창으로 남긴다. "as-of 에서 좋아 보인 결정이 τ 이후에도 유지되는가"(§7 M1b)가 곧 채점이다. 재사용 보류 창의 원리와 같다(Dwork et al. 2015).
3. **(ii) 는 문언상 가장 깨끗하지만, 격자 A 경로를 0 으로 되돌리고 A 대상의 정의를 바꾼다(이음 NAV).**
   - 이것은 등급 대상의 재정의에 가깝다. 도훈 권한이다.
   - (iii) 운전 중에 O4 에서 이음 NAV 를 **진단으로** 산출해 두면, (ii) 로 옮길 때의 비용과 효과를 사실로 판단할 수 있다.

**(iii) 의 잔여 위반 — 명시 수용 대상**
- **① 격자 live argmax 의 전기간 선정**
  - D-E 의 넓은 문언("평가 창 결과를 소비하는 자동 선정 규칙")에 걸릴 수 있다.
  - (iii) 은 이것을 "완전히 지정된 개별 PIT 전략들 사이의 성과 선정 = 다중검정(09-23 규율)"으로 분류한다. 이 분류를 도훈이 확인해야 한다.
- **② τ_sel 이전 보유(2005~16)에 대한 유기체 결정도 (t, τ_sel] 수익을 쓴다.**
  - 다만 유기체 결정은 보유를 정하지 않는다. 무엇을 잴지, 몇 칸을 쓸지만 정한다. 그래서 계상형(N_program)으로 처리한다.
- **③ 연구 시점 지식 오염은 어느 선택지로도 제거할 수 없다.**
  - Q·도훈·LLM 설계자는 2017~20 EW−CW 역전을 이미 안다.
  - 사전등록 + "반증 시도" 라벨 + 2024-12 절단판으로만 다룬다(플랜 P2 공통 규약).
  - 그래서 "틸트 중립 레버 선호"를 유기체 사전에 자동으로 넣는 것도 금지한다(§9).

### 2.5 도훈 결정 안건 문안

> **D-N 자동 선정 규칙의 PIT 범위 (D-E 적용 경계)**
>
> **배경**
> - 적응 층(REINFORCE-ORGANIC-AUTONOMY)이 "선택 기준"을 맡으면서 두 결정이 한 함수에서 만난다: 09-23 선택 규율 (A)("전기간 데이터 유지 + 계상")와 ORGANIC 가드("as-of 정보만").
> - D-E 문언을 완전히 만족하는 경로는 성과 기반 선정 금지(P0-08 start_date 방식)와 워크포워드 이음 NAV 둘뿐이다.
>
> **선택지**
> - (i) **계상형**: 격자·적응 층 모두 전기간, 다중검정 계상. C1 = 보유 규칙 내부 통계 + 미계상 스캔. "as-of" 가드는 연구 시점으로 읽는다.
> - (ii) **워크포워드형**: 성과를 소비하는 모든 자동 선정은 τ_k as-of. A 대상 = 이음 NAV. 성과 선정 계보의 고정 구성 칸은 A 보류(현 원장 A 가능 계보 0).
> - (iii) **혼합(평가 창 불가침)**: 적응 층 전 결정 = 시장 시점 as-of τ_sel(2016-11-30 · essence 첫 OOS 분할점 · 등록값). 격자 live 선택 = 09-23 규율 유지(유기체는 as-of 가치 함수 shadow 만). 성분 선정 = D-E·P0-08 불변. 휴면 = 탐색 우선순위(후보 자격 불변).
>
> **Q 권고**: (iii). 기결 세 규율을 모두 지키고, 유기체를 채점할 보류 창을 남긴다. (ii) 로 옮길지는 O4 이음 NAV 진단을 보고 재상정한다.
>
> **결정 전 기본값**
> - 적응 층은 (iii) 방식으로 **shadow 만** 돈다(live 금지).
> - 격자 live 선택·A 관문은 현행이다.
> - P0-14 표식 범위 = 팩터 IC 선정 승계(현행 설계).
>
> **막는 것**: 유기체 네 층의 live 전환 · 선택 층 as-of live · (ii) 선택 시 새 보류 코드 `selection_asof` 와 이음 NAV 계약.

**부수 안건 D-A′ (선택)**
- 유기체가 계보 간 풀링 사후로 결정하면 계보 N(D-A)이 실제 선택 다중성을 과소 계상한다.
- Q 권고: 게이트 N 은 D-A 를 유지한다(기계 권한 밖). 대신 서류(P1-04)에 N_program 민감도 행을 **의무**로 둔다(§4).

---

## 3. 가드 8종

| # | 가드 | 구현(파일·함수) | 검사 — 양성 대조 / 위반 주입 / 돌연변이 |
|---|---|---|---|
| G1 | 시행 회계 | `06_Registry/rf_trial_log.jsonl`(P1-02 신설)에 유기체 레코드 kind ∈ {organic_proposal, organic_shadow, organic_live, organic_policy_transition, organic_rejected} 를 쓴다. **효과보다 먼저 쓴다**(write-ahead). 필드: policy_id · layer · decision_id · ledger_md5 · tau_sel · inputs_digest · n_candidates · chosen · mode · counted_in{family_root, program}. writer = `rf_organic_write.R::rfo_trial_append` | (+) live 결정 효과(trim·예산·휴면) 전부에 선행 레코드가 있다(조인 100%). (−) 레코드 없이 효과만 주입하면 guard red → K2 발화. (돌연변이) write-ahead 순서를 뒤집으면 red |
| G2 | as-of 만 | `rf_organic_evidence.R::rfo_asof_view(att)` 가 **유일한 접근자**다. `sa_subwindow(τ_sel)` 산출물(형제 `essence_asof_<τ>.json`)만 읽고 전기간 essence 필드는 떼어낸다 | (+) 합성 픽스처에서 τ 이후 수익을 교란해도 사후·결정 md5 가 불변(섭동 불변). (−) 전기간 `essence$calmar` 를 읽는 돌연변이는 결정이 변해 red. (정적) 유기체 파일 AST 에서 `essence`/`authoritative_remeasure` 접근은 `rfo_asof_view` 밖에서 0 |
| G3 | 자동 사전등록 | `rf_prereg.R`(P2-01) writer 재사용 → `06_Registry/organic/prereg/<policy_id>.json` {가설 · 층 · 규칙·파라미터 해시 · 리플레이 지표 · 성공·실패 문턱(pol_cfg) · shadow 최소 기간 · 킬 조건 · 사전확률}. 덮어쓰기를 거부한다. 파라미터를 바꾸면 새 policy_id 다 | (+) 정상 prereg → shadow 진입. (−) prereg 없는 정책의 shadow 진입 거부 · 덮어쓰기 거부. (돌연변이) 해시 불일치 정책 실행 → 거부 |
| G4 | shadow → 리플레이 → live | `axiom/replay/policy_state.R` 를 재사용한다(pol_transition · pol_gate_shadow · pol_gate_live · pol_gate_demote). 채점기 = `rf_organic_replay.R`. live 게이트 env 는 **명시 인자**: `list(rf_policy_off = QVEST_RF_POLICY=="off", unattended = isTRUE(cfg$organic$auto_live))`. 전역 `QVEST_POLICY_UNATTENDED` 는 건드리지 않는다. 다른 정책 종류는 여전히 도훈 confirm 이다 | 아래 판정식 · 무작위 정책 음성 대조가 탈락해야 한다 · `test_policy_auto_live_rule.R` 회귀 |
| G5 | 킬스위치 | `rf_organic_guard.R::rfo_kill_check` · config `organic.enabled` · `organic.layers.<층>.mode ∈ {off, shadow, live}` · env `QVEST_RF_POLICY=off` | 아래 K1~K8 을 각각 위반 주입으로 발화 실증 |
| G6 | 롤백 | 단위 = policy_id. live 전이 직전 `06_Registry/organic/snapshots/<policy_id>/pre.json`(dormancy · structure_policy · 대상 entry 의 max_attempts_history). `rfo_rollback(policy_id)` 가 복원하고 롤백 레코드를 append 한다. **측정된 과거 칸은 절대 롤백하지 않는다**(append-only) | (+) 드릴: live → 롤백 → 대상 객체 md5 = pre. (−) 원장 attempts 를 건드리는 롤백 시도 → 거부 |
| G7 | 결정 레지스터 자동 기록 | 틱 결정 = `rf_record_decision(kind = organic_budget/organic_arm_status/organic_select/organic_structure)`. RF_DECISION_KINDS(ledger:712)에 추가하고 초 단위 id 충돌도 수리한다. 정책 전이 = `decision_register.json` 에 `dr_record_machine()` 신설. owner=`machine_organic` · authority=`REINFORCE-ORGANIC-AUTONOMY` · status=resolved · **scope 허용목록 검사**(헌법 범위 id 는 거부). `dr_resolve`(owner=dohoon)는 불변 | (+) 전이 1건 → 레지스터 1행. (−) scope=`tier_graduation` 기록 시도 → 거부 |
| G8 | 주간 보고 | `rf_organic_report.R` → `tg_agent_brief()`(telegram_notify.R 단일 진입). 표제 `[1계층·강화] 유기적 강화 주간 — <ISO 주차>`. qvest-telegram SKILL §5.6b 표에 행을 추가한다(문서 편집) | 드라이런(`QVEST_TG_DRY_RUN=1`)으로 본문 ≤4096자 · 섹션 누락 0 |

### 3.1 킬스위치 발화 조건 (수치는 `organic.kill.*`)

| 코드 | 조건 | 조치 |
|---|---|---|
| K1 | 헌법 경계 위반 시도: writer 가 거부했거나, denylist 파일 md5 가 유기체 실행 전후로 바뀜 | `organic.enabled=false` 를 **state 로 표시**하고 전 층 off. config 는 사람 소유라 state 플래그로 막는다. 즉시 텔레그램 |
| K2 | 회계 공백: 효과에 선행 trial log 가 없거나 파싱 실패 | 전 층 off |
| K3 | 메타 전이 음수: 최근 `meta_window`(60) 신규 칸에서 P(ρ(예측 u_τ, 실현 u_post) < 0) > `meta_neg_prob`(0.9) | live 정책 전부 demoted |
| K4 | 보정 이탈: 80% 사후예측구간 포함률 ∉ `calib_band`([0.65, 0.92]) | demoted |
| K5 | 처리량: 7일 신규 기저 소비 < pi0 기준(직전 4주 중앙) × `throughput_ratio_min`(0.7) | 예산 층 demoted |
| K6 | best_loss: 프로그램 as-of 최고 S 가 pi0 리플레이보다 `best_loss_band` 넘게 악화 | demoted |
| K7 | 사후 적합 실패 · NaN · R̂ > `rhat_max` · state 가 오래됨 | 그 tick 은 pi0 + jlog `organic_fallback` (무성 폴백 금지) |
| K8 | 수동 | `organic.enabled=false` · 층별 mode=off · `QVEST_RF_POLICY=off` |

수치 근거
- K3·K4 는 판단 사전값이며 O2 에서 보정한다.
- K5 의 0.7 은 판단값이다.
- `rhat_max` 1.05 는 Gelman-Rubin 관행값이다.

### 3.2 shadow → 리플레이 → live 승격 판정식 (정책 단위)

**proposed → shadow** = `pol_gate_shadow` 전항. 통계는 `rf_organic_replay.R` 가 원장에서 재도출한다.

| 통계 | 정의 | 문턱(pol_cfg 재사용) |
|---|---|---|
| heldout_win | 계보 제외 교차검증: 적합에서 뺀 계보에서 정책 결정의 as-of 효용이 pi0 이상인 비율 | ≥ 0.60 |
| null_pct | 같은 수의 trim·휴면을 무작위로 한 귀무 분포 대비 백분위 | ≥ 0.95 |
| discovery_drop | entry 의 as-of 최고 칸을 정책이 잘랐을 비율 | ≤ 0.10 |
| unreachable | 정책 아래서 도달 불가가 된 기측정 승자 비율 | ≤ 0.20 |
| best_loss | 프로그램 as-of 최고 S 의 악화 | ≤ 0.05 |
| peek_blocked · static_clean · negative_control_ok | G2 섭동 검사 · 정적 검사 · 무작위 정책이 같은 게이트에서 탈락 | 필수 |

**shadow → live** = `pol_gate_live` 전항. 수치는 도훈 09-21 ① 값을 그대로 쓴다.
- shadow ≥ 4주
- 유익한 불일치 ≥ 3건: shadow 결정 ≠ pi0 이면서, 사후 판명된 as-of 효용에서 shadow 가 더 나았던 사례
- 최신 재리플레이 승 · placebo 통과
- 같은 kind live ≤1 · 총 ≤2 · 주간 활성화 ≤1
- `organic.auto_live = true`

**가산 정책(칸을 늘리는 정책)** 은 리플레이할 수 없다. 반사실 결과가 결측이기 때문이다. 그래서 **canary** 로 간다.
- live 를 `canary_entries`(1) entry 에만 4주 적용한다.
- 메타 지표(M1b·M3)가 비열위면 확대한다.

**강등·폐기**: 최신 5 판정 중 3 패 → demoted → shadow · 8주 안에 2회 강등 → tombstoned(해제 = 도훈).

### 3.3 주간 보고 내용

1. 정책 전이(id · 층 · from→to · 사유 · 되돌리기 명령)
2. 블록별 칸 배분 변화(pi0 대비) · 조기 소진 entry 수와 절약 칸
3. 휴면·부활 목록
4. 선택 층 shadow–live 일치율과 불일치 사례 3건
5. 메타 지표 M1a·M1b·M2·M3·M4(§7)와 추세
6. N_cell·N_program·N_policy
7. 킬 조건 여유(각 K 의 현재값 / 문턱)
8. 헌법 경계 검사 결과(denylist md5 불변 확인)
9. as-of 사후 기준 상위 3계보의 P(u > δ)

**싣지 않는 것**: 전기간 PT·Calmar 원수치, A 근접도. 보고가 목적함수로 새는 것을 막는다.

---

## 4. 시행 회계

**층위 — 무엇을 세는가**

| 수 | 정의 | 소비처 |
|---|---|---|
| N_cell | D-A = 계보 누적 측정 칸(상속 제외) + 기저 1 + 배치 크기(`rf_selection_accounting` · gates:218-222) | DSR 게이트(불변 — 기계 권한 밖) |
| N_program | 유기체 사후 적합에 들어간 증거 칸 수(전 계보) | 서류 민감도 행(의무) |
| N_policy | 종류별로 리플레이에서 비교한 정책 수. 기각된 제안과 shadow 탈락을 포함한다 | 서류 · 주간 보고 |
| N_meta | live 정책 전이 수 | 서류 |

**적응 결정이 N 에 들어가는 방식**
- 칸 수준: 유기체가 배분해서 측정된 칸은 기존대로 N_cell 에 들어간다.
- 유기체가 **안 재기로 한** 칸(trim·휴면)은 측정이 없으므로 N_cell 에 넣지 않는다. 대신 그 결정이 쓴 증거(N_program)가 선택의 다중성이다.
  - 계층 사후는 계보 간 정보를 풀링한다. 그래서 한 계보의 승자 선택이 사실상 프로그램 전체를 보고 이뤄진다.
- 정책 수준: shadow 에서 비교된 정책 K 개 중 하나가 live 가 되는 것은 메타 선택이다. N_policy 로 센다. 기각된 제안도 센다.

**DSR·PBO 가 더 엄격해지는 효과**
- Bailey & López de Prado(2014)의 기대 최대 SR 항은 E[max]/σ ≈ (1−γ_E)·Φ⁻¹(1−1/N) + γ_E·Φ⁻¹(1−1/(N·e)) 다.
- N 이 170(최대 계보 22632 규모)에서 1,200(프로그램)으로 가면 이 항은 2.71 → 3.31 로 **약 +22%** 커진다. 계산은 식을 그대로 대입한 값이다.
- 서류에는 N_cell 판 DSR(게이트)과 N_program 판 DSR(민감도)을 병기한다.
- CSCV-PBO(Bailey·Borwein·López de Prado·Zhu 2016)의 가족 = 같은 초모수 집단(블록 병합 T2 반영) 전체 칸이다.

**A 후보 서류(P1-03/04)와의 분리**
1. 유기체는 A 관문(`rf_a_eligibility`)·`a_eligibility_gate.json`·`grade_a_queue.json`·`judge_request_*`·서류를 **읽지도 쓰지도 않는다**. 서류가 유기체 provenance(`06_Registry/organic/*` · trial log)를 읽기만 한다.
2. 유기체 효용은 as-of S 뿐이다. **A 근접도·등급으로 예산을 올리지 않는다.** A 근접 계보에 "확인 측정"을 몰아주는 것은 그 자체가 선택이다.
3. 계정을 분리한다. 유기체는 **칸 수**만 배분한다. 서류 계산(CSCV·부트스트랩·절단판)은 idle 비동기 CPU 큐에서 돈다(P1-04 · tick PT2H 회피). 서로 예산을 잠식하지 않는다.
4. 서류 항목을 추가한다: "탐색 경로에 관여한 유기체 정책 id · 결정 시점 사후 요약 · N_program · N_policy".

---

## 5. 헌법 경계 봉쇄 — 기계가 절대 바꾸지 못하는 것

| 계층 | 장치 | 검사(양방향) |
|---|---|---|
| **단일 writer** | `rf_organic_write.R::rfo_write(path, obj, schema)` 만 파일을 쓴다. 경로 **allowlist** = `06_Registry/organic/**` · `06_Registry/rf_trial_log.jsonl`(append) · `06_Registry/rf_decisions.jsonl`(append · ledger writer 경유) · `decision_register.json`(`dr_record_machine` 경유 · scope 허용목록) · 원장 entry 필드 `max_attempts`/`max_attempts_history`(`rf_record_entry_budget` 경유) | (+) 허용 경로 정상 쓰기 통과. (−) `constraint_defaults.json` 쓰기 주입 → 거부 + K1. (돌연변이) allowlist 검사 제거판 → 검사 red |
| **denylist (절대)** | `02_Infrastructure/worktask/constraint_defaults.json`(문턱·집행 규약·진단) · `06_Registry/reinforce_program.json`(fixed_axes 동거) · `06_Registry/a_eligibility_gate.json` · `06_Registry/pit_quarantine.json` · `06_Registry/book/**` · `05_Production/**` · `01_Literature/**` · `grade_a_queue.json` · `qepm/mailbox/judge_request*` · 정본 카탈로그 3종(`overlay_catalog.json`·`weight_catalog.json`·`factor_registry.json`) · `reinforce_auto_config.json`(사람 소유 — 유기체 상태는 state 파일) · `.claude/**` · 훅 | 유기체 실행마다 전후 md5 스냅샷을 찍는다. 불일치면 K1. 위반 주입 픽스처로 발화를 실증한다 |
| **정적 봉쇄** | 유기체 R 파일을 parse 해서 파일 쓰기 호출(`writeLines`·`write`·`cat(file=)`·`saveRDS`·`file.rename`·`file.copy`·`jsonlite::write_json`·`unlink`)을 찾는다. `rfo_write` 밖에서 0 이어야 한다 | 우회 3종(문자열 결합 경로 · `do.call` · `eval(parse())`) 양성 대조 — 셋 다 잡혀야 한다 |
| **스키마** | dormancy·structure_policy·budget_policy JSON 스키마 | 스키마에 고정 축 키(`n_max`·`universe`·`start_date`·`commission_bps`·`liq_adv20_min`·`long_only`·`weight_cap`)나 문턱 키가 **나타나면 거부** |
| **값 제약** | structure_policy n_b ≤ 격자·설계 칸 수(늘리기 불가) · 예산 ≤ max(auto, manual)(유기체는 **줄이기만** 한다. 늘리는 권한은 설계 레인과 사람) · 휴면 대상 id ∈ 카탈로그 active ∪ 기존 dormant(retired·suspended·PIT 격리 id 는 "부활" 불가) | (−) PIT 격리 arm(pg2_risk_overlay_v1 · C11)을 부활시키는 정책 주입 → 거부 |
| **판정 경로 격리** | `rf_a_eligibility`·essence·`run_paper_replication` 은 `06_Registry/organic/*` 를 읽지 않는다 | 정적: 세 파일에 "organic" 참조 0 |
| **BOOK·프로덕션** | 유기체 코드에 `register_book_entry`·`promote_to_production` 호출 0 | 정적 검사 |
| **PIT 기계** | 유기체는 `overlay_pit_guard`·`lookahead_detector`·`pit_quarantine` 을 호출만 할 뿐 설정을 바꾸지 않는다. C11 격리 id 는 증거에서 자동 제외한다(E2) | 격리 id 증거 주입 → 제외 확인 |

양방향 원칙: 모든 장치는 양성 대조(정상 통과) + 위반 주입(차단 발화) + 돌연변이(장치 제거판에서 검사 red)를 통과해야 방어선 목록에 오른다. "양성 대조 없는 계기는 방어선이 아니다."

---

## 6. 레버 감사 우선순위 1~9 · 플랜 항목과의 관계

| # | 레버 감사 항목 | 관계 | 설명 |
|---|---|---|---|
| 1 | `tilt_attribution.R`(P2-02) | **선행조건(O2)** | 유기체 Δ 를 [시장·EW−CW·틸트·선별]로 분해해 **보고**한다. 선호로 쓰지는 않는다(§9-2). 메타 전이(M1b) 해석에 필요하다 |
| 2 | 쓰이지 않는 예산 회수 · D-G B5 축소 · 해로운 arm 퇴출 | **흡수** | 예산 층(B1·B2)·공간 층(S1·S2)·구조 층(T1)이 사후에서 도출한다. D-G 정적 규칙은 유기체의 **초기 정책 π_DG** 가 된다. π_DG 는 이미 결정된 사항이라 O1 이전에 정적 규칙으로 먼저 배포할 수 있다 |
| 3 | 승격 통제칸(P1-06: carry 재현 + null 희석) | **선행조건(O0~O1)** | 잡음 σ 의 원천이다. 없으면 부트스트랩 임시값으로 간다 |
| 4 | PR-L2 B7 as-of 새 칸 | 독립 · 예산 보장 | B7 = 사전등록 전용 블록(T4). 판정은 새 처치 유형 사전(S3)으로 들어온다 |
| 5 | PR-L1 cap_core | 독립 · 예산 보장 | 같다. confirmed 면 S3 로 탐색 배분 |
| 6 | D-F soft | **흡수** | B3 승격 예산 · 선택 층 승격 판정 |
| 7 | 선택 가치 함수 + 결정 기록(P1-05) | **흡수** | 선택 층(shrunk_u) · `select_winner_by` 실배선 · B6/B7 술어 · `rf_record_decision` 배선 |
| 8 | 설계 레인 학습 고리(P1-02 · P3-03) | 부분 흡수 | 레버 키에 `design_source` 가 있으므로 레인별 효과 사후가 곧 설계 레인 skill 이다. expect 채점(P3-03)은 별도로 남는다 |
| 9 | 크래시 위험 선별 | 범위 밖 | L2 판정 뒤 사전등록 |

**P0-14 와의 관계**
- **러너 재개 전 필수**이고, 유기체 O1 의 선행조건이다.
- 유기체 증거 필터 E2 가 계보 기반 선정기저 표식을 정확히 승계하는지에 의존한다.
- D-N 이 (ii) 로 결정되면 표식 가족이 `selection_basis_full_window`(바닥·carry·승격의 전기간 선정)로 확장된다. 이것은 P0-14 의 일반화다.

**플랜 항목**

| 항목 | 처분 |
|---|---|
| P1-01 d_A·S | **흡수**. 유기체 효용 S_τ(as-of 판). 전기간 판은 서류용으로 남긴다 |
| P1-02 trial log | 선행조건(G1) |
| P1-03 `sa_subwindow` | **선행조건**(as-of 뷰 계약). 유기체가 첫 대량 소비자다 |
| P1-04 서류 | 소비자. §4 항목 추가 |
| P1-05 | 흡수(선택 층) |
| P1-06 | 선행조건 |
| P1-07 E2 | **대체·일반화**. 유기체 리플레이(`rf_organic_replay.R`)가 E2 의 상위 집합이다 |
| P1-08 | 흡수(FIFO 선행 + 레인 순서 제약) |
| P1-09 | 조건 변경. 설계 재료의 A-거리 표·성과 표는 **as-of τ_sel 판**이어야 한다(설계 레인 = 자동 내용 선정) |
| P3-01 레버 장부 | **흡수**. 유기체 증거표·사후가 곧 장부다. 수용 게이트 PE-5(합성 우월 arm 1위 · 순열 \|중앙Δ\| < 0.01 · 결정론 해시)를 O0 완료 판정에 재사용한다. `rf_overlay_outcomes` 대체도 여기서 한다 |
| P3-02·03·06 | 독립(교훈 저장소·예측 채점·폐루프 E2E). 유기체 결정 기록은 P3-06 ⑥ "결정 기록 shadow" 마디를 채운다 |

**폐기·개정하는 플랜 조항**
- P1-07 "live 는 도훈 confirm 후" → **유기체 층에 한해** ORGANIC 결정으로 대체한다. 다른 정책 종류는 불변이다.
- P3 "보류(도훈 재승인 후): π_lever(Thompson)·probe 칸 치환·policy_state 자동 live" → ORGANIC 으로 **해제**한다. 단 "probe" = O2 리플레이 + 음성 대조 통과로 정의한다.
- 플랜 '하지 말 것' 11 "probe 없이 policy_state 자동 live 금지" → **유지**한다. 유기체는 probe 를 경유하므로 충돌하지 않는다.
- 격자 `graduation.improvement_check`(죽은 선언) → 유기체 futility(B2)로 대체한 뒤 삭제를 제안한다.
- D-G 정적 규칙 "상주+2칸" → π_DG 초기 정책으로 흡수한다. 유기체 live 뒤에는 사후가 대체한다.

---

## 7. 메타 목표 — "유기체가 나아지고 있는가"

**지표 (전부 R 계약 산출 · 주간 보고)**

| 코드 | 지표 | 정의 | 역할 |
|---|---|---|---|
| M1a | 연구 시점 예측력 | 측정 **전에** 낸 새 칸 예측(u_τ 사후예측)과 실현 u_τ 의 로그예측밀도 · 순위상관 | 모형이 새 칸으로 일반화되는가 |
| **M1b** | **시장 시점 전이** | 유기체가 고른·배분한 칸에서 ρ(실현 u_τ, 실현 u_post). u_post = (τ_sel, 끝] 창 부족분 감소. pi0 선택분과 비교 | **Goodhart 방지 핵심**. 유기체는 u_post 를 한 번도 최적화하지 않는다 |
| M2 | 효율 | as-of S 감소 1단위당 칸 수(pi0 리플레이 대비) | 예산 층 채점 |
| M3 | 처리량 | 주당 신규 기저(논문) 소비 | 경로 ① |
| M4 | 보정 | 80% 사후예측구간 포함률 | 과신 감시 |
| 감시만 | A 수 · 전기간 PT/Calmar · OOS retention | **목적함수에도 보상에도 넣지 않는다** | 보고 |

**목표 축 상한**
- 효용 S 는 문턱에서 0 이다. 문턱을 넘은 뒤의 초과분은 점수가 없다.
- 유기체의 "나아짐" 은 M1b·M4 가 결정한다. 이 둘은 유기체가 최적화하지 않는 창에서 잰다.
- M2·M3 에는 상한이 없지만 K5·K6 이 하한을 지킨다.

**실패 모드와 대응**

| # | 실패 모드 | 탐지 | 대응 |
|---|---|---|---|
| F1 | 사후 과신(τ_b²·ω² 과소추정) → 승자 저주 잔존 | M4 포함률 < 0.65 | K4 강등 · 초사전 척도 상향은 사전등록으로만 |
| F2 | 비동시 대조·빈티지 드리프트(추세) → 편향(Lee & Wason 2020 · Thall 2015) | epoch 별 잔차 평균 검정 | E1·E6 필터 · epoch 가 바뀌면 부활·재적합 |
| F3 | 탐색 고갈(적응 배분이 한 블록으로 쏠림) | 블록별 배분 엔트로피 | `n_min_block` · Thompson 무작위성 · canary |
| F4 | LLM 설계자 되먹임(사후를 보고 사후에 맞춰 설계) | 설계 재료 감사 | 설계 레인에는 **라벨만** 준다(D-I) · `06_Registry/organic/` 를 `arm_gen_read_guard` 정규식에 추가(기존 훅 확장) |
| F5 | 평가 창 누출(사전·재료·보고를 통해) | G2 섭동 · 정적 검사 | 레버 감사 Δ 표를 위치 사전 금지 · 보고에서 전기간 수치 제외 |
| F6 | as-of 사후가 τ 이후를 **반대로** 예측(EW−CW 구조 전환 — 2005~16 활성 IR 양수 칸 100%, 2017~20 2%[감사]) | M1b < 0 | K3 강등 → pi0 + 보고. 이것은 실패가 아니라 **사실 발견**이다: "as-of 로 좋아 보이는 개선은 이 계보에서 전이되지 않는다". 대응은 사전등록 레버(L1)의 몫이다 |
| F7 | 과도한 예산 수축 → 검정력 저하 → 사후가 더 불확실 → 다시 수축(악순환) | 증거 증가율 | `n_min_entry` · 휴면 최소 증거 · 감산 폭 상한 `max_trim_frac` |
| F8 | N 과소 계상(풀링) | 서류 민감도 | N_program 병기 의무 · D-A′ |
| F9 | 휴면·부활 진동 | 상태 전이 빈도 | 히스테리시스(0.05/0.15) · 최소 휴면 8주 |
| F10 | 무성 폴백(사후 실패 시 조용히 pi0) | jlog `organic_fallback` 계수 | K7 fail-loud · 주간 보고 항목 |
| F11 | 평균회귀 교락(나쁜 바닥에서 쉬운 개선) | γ 사후 | γ·Ŝ_f 공변량 · 축소 기준선 |
| F12 | 유기체가 헌법 설정을 우회(config·정본 편집) | denylist md5 | K1 · 단일 writer · 정적 검사 |

---

## 8. 구현 단계 O0~O4

**선결 (유기체 밖 · 플랜 항목)**
- P0-14(러너 재개 전 필수)
- P1-02 trial log
- P1-03 `sa_subwindow`
- P1-06 통제칸(없으면 부트스트랩 임시값)
- P1-08 FIFO
- D-N 결정(없으면 기본값 = shadow 만)

**편집 순서 주의**
- 동시 수리 워크플로가 `rf_runner_gates.R` 와 `run_paper_replication.R` 를 스테이징 중이다.
- 유기체의 게이트 편집(`rf_budget_want`·`rf_select_value`·`rf_organic_*`)은 **그 워크플로가 배포된 뒤** 병합한다.
- O0 는 오프라인·신규 파일만 다루므로 충돌이 없다.

| 단계 | 산출 | 검사 | 완료 판정 | 규모 [판단] |
|---|---|---|---|---|
| **O0 오프라인 기질** (러너 불요) | `rf_organic_evidence.R`(E1~E7 · `rfo_asof_view`) · `rf_organic_model.R`(Gibbs · 요약) · 합성 세계 시뮬레이터(레버 감사 **척도**로 보정 — 위치는 합성) · 1,193칸 as-of 뷰 배치(`sa_subwindow` · rds 재채점만 · claim idle · 형제 판 쓰기) | 양성 대조: 합성 우월 레버 1위 · 블록 효과 복원 · 순열 귀무 \|중앙 Δ\| < band · 결정론 해시 · G2 섭동 양방향 · 캘리브레이션(합성 80% 구간 포함 0.75~0.85) | PE-5 준용 통과 · 증거표를 원장에서 재도출해 일치 | R 약 700줄 + 검사 약 500줄 · 2세션 + 배치 수 시간 |
| **O1 shadow** | `ops/rf_organic_tick.R`·`.sh`(tick.sh 에 레인 1줄 — 훅 아님) · `state.json` · 러너 국소 7줄(전부 pi0 비트 동일) · `rf_organic_write.R`·`rf_organic_guard.R` · 결정 기록 · `rf_organic_report.R` | **pi0 비트 동일 회귀**(러너 결정 전수 identical) · 돌연변이(정책 누락·오적용) · writer allowlist/denylist 양방향 · K1~K8 발화 실증 | shadow 2주 이상 기록 · 주간 보고 1회 · 킬 드릴 1회 | R 약 600줄 + 검사 약 500줄 · 2세션 + 벽시계 2주(**러너 재개 = 도훈 지시 필요**) |
| **O2 리플레이** | `rf_organic_replay.R` · 사전등록 3건(π_DG · π_trim(블록 휴면+futility) · π_dorm(arm 휴면)) · `pol_gate_shadow` 채점 | 무작위 정책 음성 대조 탈락 · 계보 제외 교차 · 절단 원장 재현(연구 시점 as-of: 결정 시각 이전 closed 칸만) | 정책별 판정 기록(통과·철회 모두 완료로 친다) · 파라미터 보정값 prereg | 약 400줄 · 1~2세션 |
| **O3 live canary** | 예산 층(감산) → 공간 층 → 구조 층 순. 각각 shadow ≥4주 뒤 `pol_gate_live`. **선택 층은 D-N 전 shadow 고정** · 가산 정책은 canary 1 entry | 위반 주입 킬 발화 · 롤백 드릴(pre md5 복원) · M1b·M4 추적 | 층별 live 1개 이상 또는 철회 기록 · 강등 경로 실증 | 1~2세션 + 벽시계 4~8주 |
| **O4 정상 운전** | 주간 보고 · 월간 재보정(사전등록된 파라미터만) · (선택) **이음 NAV 진단**(D-N (ii) 판단 자료 — τ_k 3개 워크포워드 보유 패널 → `rfh_remeasure`) | 이음 NAV 의 PIT 섭동 검사 | 도훈에게 (ii) 이행 비용·효과 사실표 상정 | 약 300줄 · 1세션 |

### 8.1 신규 config 키 (`reinforce_auto_config.json::organic` — 사람 소유 · 유기체는 읽기만)

```
organic.enabled                         false
organic.auto_live                       false   (ORGANIC 결정상 true 허용 — O3 진입 시 사람이 켠다)
organic.canary_entries                  1
organic.layers.{budget,space,select,structure}.mode   "off"|"shadow"|"live"   (초기 shadow)
organic.asof.mode                       "tau_select"   (D-N 결정값 — (i) 이면 "full_counted")
organic.asof.tau_select_source          "constraint_defaults.json::diagnostics.oos_calendar_splits[1]"
organic.asof.pt_threshold_scaling       "sqrt_T"
organic.evidence.exclude_flags          ["pit_c11","treatment_misspecified"]
organic.evidence.b1_exclude_flags       ["selection_basis_full_sample_ic","selection_basis_full_sample_ic_inherited"]
organic.evidence.b5_observation         "t3_placebo_adjusted"
organic.model.{draws, burn, rhat_max}   2000, 500, 1.05
organic.model.hyperprior_scale_source   "lever_audit dispersion (scale only)"
organic.model.noise_source              ["control_cells_P1-06","block_bootstrap_politis_white"]
organic.budget.{thompson_beta, futility_p, futility_delta_sigma, min_blocks_before_futility,
                n_min_block, promote_p_min, max_trim_frac}
organic.space.{dormant_p, revive_p, n_min_evidence, r_min, dormant_weeks, b5_gen_p, new_type_var_inflation}
organic.select.{value, carry_p, report_winner_ci}
organic.structure.{block_dormant_p, n_min_block_evidence, r_min_block, merge_p, n_diag}
organic.kill.{meta_window, meta_neg_prob, calib_band, throughput_ratio_min, best_loss_band, state_max_age_h}
organic.policy_state                    (pol_cfg 키 재사용 — shadow_min_weeks 4 · informative_disagreements_min 3 · …)
organic.report.{weekday, header}
```

각 키에는 `_source`(문헌 링크·결정 id·"판단 — O2 보정 대상")를 병기한다.

### 8.2 파일

**신규**
- `02_Infrastructure/reinforcement/`
  - `rf_organic_evidence.R`
  - `rf_organic_model.R`
  - `rf_organic_policy.R`(층별 결정 규칙)
  - `rf_organic_replay.R`
  - `rf_organic_write.R`
  - `rf_organic_guard.R`
  - `rf_organic_report.R`
- `02_Infrastructure/ops/rf_organic_tick.R` · `rf_organic_tick.sh`
- (P1-03) `02_Infrastructure/contracts/selection_accounting.R::sa_subwindow`
- `06_Registry/organic/`
  - `state.json`
  - `dormancy.json`
  - `structure_policy.json`
  - `snapshots/`
  - `prereg/`
- (P1-02) `06_Registry/rf_trial_log.jsonl`
- `08_Tests/reinforcement/test_rf_organic_{evidence,model,policy,replay,write_guard,asof_perturb,kill,rollback,pi0_identity}.R`

**수정 (국소)**

| 파일 | 변경 |
|---|---|
| `rf_runner_gates.R` | `rf_budget_want(policy=)` · `rf_select_value` · `rf_carry_decide` · `rf_organic_apply_cells` · `rf_organic_exclude` · `rf_organic_state` |
| `reinforce_auto_parallel.R` | 약 7줄: L143-144 옆 · L436 뒤 · L448 · L597-629 · L633-640 · L683 · L766·L774 |
| `reinforce_ledger.R` | RF_DECISION_KINDS 추가 · decision_id 충돌 수리 · `rf_record_entry_budget` 이력 · `dr_record_machine` |
| `rf_promote.R` | `organic=` 인자 |
| `reinforce_auto_next_paper.R` | FIFO · 자식 예산 1줄 |
| `rf_cell_worker.R` | 측정 직후 as-of 뷰 산출 |
| `reinforce_auto_tick.sh` | 레인 1줄 |
| `rf_overlay_propose.sh` · `rf_b5_design.sh` | 쿼터 읽기 |
| `hooks/arm_gen_read_guard.sh` | 정규식에 `06_Registry/organic/` 추가 — **기존 훅 확장 · 동시 수리 워크플로 배포 뒤** |
| 문서 | qvest-telegram SKILL §5.6b 행 · reinforce SKILL §0.3 포인터 |

---

## 9. 하지 말 것

1. 적응 층 통계에 τ_sel 이후 수익을 넣지 않는다. **사전·재료·보고 경로 포함**이다. 레버 감사 Δ 표(전기간)를 위치 사전으로 쓰지 않는다. 척도만 쓴다.
2. "EW−CW 틸트 중립 레버 선호" 를 유기체 사전·효용에 자동으로 넣지 않는다. 이 지식은 τ 이후 관측에서 나왔다. 사람이 문헌 근거로 하는 사전등록(PR-L1)으로만 다룬다.
3. D-N 전에 유기체가 격자 live 선택을 as-of 로 바꾸지 않는다. 반대로 유기체 결정을 전기간 통계로 내리지도 않는다. 두 창을 한 argmax 에 섞지 않는다.
4. 정본 카탈로그 3종·registry lifecycle·`pit_quarantine.json`·`reinforce_program.json`·`constraint_defaults.json`·`a_eligibility_gate.json`·`reinforce_auto_config.json` 에 쓰지 않는다. 휴면은 유기체 목록으로만 한다.
5. 블록 순서 최적화를 다시 넣지 않는다(09-18 NO-GO). 유기체가 칸을 **늘리지** 않는다. `daily_cap`·`parallel_cells` 를 움직이지 않는다(플랜 '하지 말 것' 1).
6. 고정 축(INV-7)·등급 문턱·DSR N 정의(D-A)·A 관문 설정·BOOK·프로덕션을 건드리지 않는다. 유기체가 A 관문·서류·큐를 읽거나 쓰지 않는다.
7. A 근접 계보에 예산을 몰아 "확인 측정" 하지 않는다. 등급·A 근접도를 효용이나 예산 입력으로 쓰지 않는다.
8. arm 수준 사후로 퇴출을 남발하지 않는다. 신호대잡음상 arm 은 약 67칸 전에는 식별되지 않는다. 블록·계보 수준을 우선하고 `n_min_evidence` 를 지킨다.
9. 위상쌍 B6_32/33 을 SE 원천으로 쓰지 않는다. B7 과거 칸(misspecified)·C11 칸·unverified B5 원 Δ 를 증거로 쓰지 않는다. B5_31 재측정을 요구하지 않는다.
10. 짝지은 부트스트랩 하한 >0 이나 P(Δ>0) 를 **하드** 승격·carry 게이트로 쓰지 않는다. 확률은 soft 예산과 shadow 판정에만 쓴다(플랜 '하지 말 것' 5).
11. 사후 실패 시 조용히 pi0 로 돌지 않는다(fail-loud · K7).
12. Q-Lead·python 이 사후를 계산해서 결정에 쓰지 않는다. R 모듈만 쓴다(AX-008). 이 문서의 [감사]·[원장] 수치는 결정 근거가 아니다.
13. 새 훅을 등록하지 않는다. `arm_gen_read_guard` 정규식 확장만 하고, 동시 수리 뒤에 한다. 설계 레인에 사후 원수치·τ 이후 성과를 주지 않는다(D-I).
14. 유기체의 결론을 "A 는 안 나온다"는 한계로 적립하지 않는다(AX-000). 유기체의 산출은 예산 재배분·휴면·전이 사실이다. M1b 음수(F6)는 "이 계보에서 as-of 개선이 전이되지 않는다"는 **사실**로 적는다.
15. 옛 규약(close_d_legacy) 수치, rebase 전 essence 를 증거에 섞지 않는다(E1).
16. B7·B1 폴백 과거 칸을 as-of 규칙으로 "재측정" 하지 않는다. 새 규칙이면 새 칸이다.

---

## 부록 A — 근거 문헌 (원문 링크 · crossref 로 DOI 확인)

- Thompson, W.R. (1933). On the Likelihood that One Unknown Probability Exceeds Another in View of the Evidence of Two Samples. *Biometrika* 25(3/4). https://doi.org/10.2307/2332286
- Russo, D., Van Roy, B., Kazerouni, A., Osband, I., Wen, Z. (2018). A Tutorial on Thompson Sampling. *FnT ML* 11(1). https://doi.org/10.1561/2200000070
- Russo, D. (2020). Simple Bayesian Algorithms for Best-Arm Identification. *Operations Research* 68(6). https://doi.org/10.1287/opre.2019.1911 — top-two Thompson · β 기본값
- Frazier, P., Powell, W., Dayanik, S. (2008). A Knowledge-Gradient Policy for Sequential Information Collection. *SIAM J. Control Optim.* 47(5). https://doi.org/10.1137/070693424 · (2009) Correlated Normal Beliefs. *INFORMS J. Computing* 21(4). https://doi.org/10.1287/ijoc.1080.0314 — shadow 대안 배분기
- Efron, B., Morris, C. (1975). Data Analysis Using Stein's Estimator and its Generalizations. *JASA* 70(350). https://doi.org/10.1080/01621459.1975.10479864
- Gelman, A. (2006). Prior distributions for variance parameters in hierarchical models. *Bayesian Analysis* 1(3). https://doi.org/10.1214/06-BA117A
- Jensen, T.I., Kelly, B., Pedersen, L.H. (2021). Is There a Replication Crisis in Finance? NBER w28432. https://doi.org/10.3386/w28432 — 팩터 복제의 계층 베이지안 축소
- Andrews, I., Kitagawa, T., McCloskey, A. (2019). Inference on Winners. NBER w25456. https://doi.org/10.3386/w25456
- Saville, B.R., Connor, J.T., Ayers, G.D., Alvarez, J. (2014). The utility of Bayesian predictive probabilities for interim monitoring of clinical trials. *Clinical Trials* 11(4). https://doi.org/10.1177/1740774514531352
- Saville, B.R., Berry, S.M. (2016). Efficiencies of platform clinical trials: A vision of the future. *Clinical Trials* 13(3). https://doi.org/10.1177/1740774515626362 — arm 추가·탈락
- Lee, K.M., Wason, J. (2020). Including non-concurrent control patients in the analysis of platform trials: is it worth it? *BMC Med. Res. Methodol.* 20. https://doi.org/10.1186/s12874-020-01043-6
- Thall, P., Fox, P., Wathen, J. (2015). Statistical controversies in clinical research: scientific and ethical problems with adaptive randomization in comparative clinical trials. *Annals of Oncology* 26(8). https://doi.org/10.1093/annonc/mdv238
- Garivier, A., Moulines, E. (2011). On Upper-Confidence Bound Policies for Switching Bandit Problems. *ALT 2011, LNCS*. https://doi.org/10.1007/978-3-642-24412-4_16 — 드리프트 대안(기본은 epoch 필터)
- Dwork, C., Feldman, V., Hardt, M., Pitassi, T., Reingold, O., Roth, A. (2015). The reusable holdout: Preserving validity in adaptive data analysis. *Science* 349(6248). https://doi.org/10.1126/science.aaa9375
- Bailey, D.H., López de Prado, M. (2014). The Deflated Sharpe Ratio. SSRN. https://doi.org/10.2139/ssrn.2460551
- Bailey, D.H., Borwein, J., López de Prado, M., Zhu, Q.J. (2016). The probability of backtest overfitting. *J. Computational Finance*. https://doi.org/10.21314/JCF.2016.322
- Harvey, C.R., Liu, Y. (2020). False (and Missed) Discoveries in Financial Economics. *J. Finance* 75(5). https://doi.org/10.1111/jofi.12951
- Politis, D.N., White, H. (2004). Automatic Block-Length Selection for the Dependent Bootstrap. *Econometric Reviews* 23(1). https://doi.org/10.1081/ETC-120028836
