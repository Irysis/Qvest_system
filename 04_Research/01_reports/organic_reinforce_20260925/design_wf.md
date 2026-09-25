# 유기적 강화 설계안 — PIT-우선 워크포워드 메타 리서치형 (design_wf)

- 작성: 2026-09-25 16시 KST · 설계 패널 3관점 중 'PIT-우선 워크포워드' 관점. 다른 두 관점(베이지안 순차 배분 · 개방형 진화)과 독립 작성.
- 읽기 전용 준수: 운영 트리·원장·레지스트리·기억 쓰기 0 · R 실행 0 · python 은 원장 JSON 의 기술 집계만(결정 수치 아님 — [재집계·진단] 라벨) · 텔레그램 0 · 커밋 0.
- 입력: 플랜 `qvest-1-drifting-eclipse.md`(P0~P3 · D-A~D-M · 09-25 절) · 레버 감사 최종 `organic/lever_audit_final.md` · 지형 A(4층)·B(가드) · 결정 `REINFORCE-ORGANIC-AUTONOMY` · 코드 직접 확인(§0.5).
- 표기: [확인] = 코드·원장에서 Q 가 직접 본 사실 · [재집계·진단] = 원장 JSON 기술 집계 · [판단] = 사전확률 등 판단값 · 수치 결정은 전부 R 계약 산출로만(AX-008).

---

## 0. 요지 · A 에 기여하는 경로

**한 줄**: 적응 층의 모든 결정은 결정 시각까지 공개된 정보만 보고(시장 시각 τ · 연구 시각 r), 그 결정의 가치는 결정 이후에 드러난 데이터로만 채점한다. 성과로 고른 **정적** 칸은 원리상 PIT 가 될 수 없으므로, 적응 층의 A 후보는 **워크포워드 합성 전략**(τ_k 마다 as-of 로 고른 칸의 보유를 (τ_k, τ_{k+1}] 동안만 이어 붙인 경로)으로만 낸다.

### 0.1 왜 이 구조인가 — 정적 칸 명제

**명제 P.** 칸 c 의 보유 경로는 [2005-01-01, 데이터 끝] 전체다. c 의 구성이 다른 칸들의 **성과** 통계로 골라졌고 그 통계가 τ_sel 까지의 수익을 썼다면, t < τ_sel 인 c 의 모든 보유는 t 이후 통계로 정해진 것이다. 이는 D-E 문언의 "시점 t 보유를 미래 통계로 정한 것"과 같다. 그런데 τ_sel ≤ 2005-01 이면 성과 표본이 0 이라 성과로 고를 수 없다.
⇒ **성과 기반 자동 선정 + 정적 칸은 어떤 τ_sel 로도 D-E 문언상 청정할 수 없다.** 청정한 형태는 구성이 시간에 따라 바뀌는 전략뿐이다(τ_k 마다 ≤τ_k 정보로 고르고 다음 결정까지만 보유).

- 현행 B1 규칙 픽커의 as-of = `fixed_axes.start_date`(2005-01-01)는 이 명제의 퇴화 사례다: 결정 시점이 하나이고, 성과가 아니라 IC 통계로 고른다 [확인 `rf_factor_arms.R:186-194, 263-268`].
- 격자 승자·바닥·carry·승격은 전부 정적 칸 위의 성과 argmax 다 [확인 러너 `:683-684 · :774-776` · `rf_promote.R:59` · `rf_lesson.R:115`].

### 0.2 두 시계 × 두 층

| | 시장 시각 τ (데이터 날짜) | 연구 시각 r (원장 `opened_at`/`closed_at`) |
|---|---|---|
| **탐색 층 E** (현 러너 + 예산·공간·구조 제어) | 레버 효과의 **시간 안정성** 검정(τ 격자 위 부호·순위 일치) | 결정마다 예측을 기록하고 그 뒤 측정된 칸으로 **전방 채점** |
| **확약 층 C** (워크포워드 합성) | τ_k 마다 as-of 선택 → (τ_k, τ_{k+1}] 보유 | 합성 명세 동결 시각 이후의 **진짜 전방 구간**(누구도 본 적 없는 데이터) |

**원칙 — 결정 함수는 하나이고 시각 (r, τ) 만 주입된다.**
- live = (r_now, τ_latest), 리플레이 = (r_k, τ_k).
- 리플레이 전용 코드 경로가 없으므로 리플레이가 엿볼 통로도 없다. `rf_runner_ctx(regime = injected)` 와 같은 형태다 [확인 `rf_runner_gates.R:293-303`].
- 검사: 같은 (r, τ) 에서 live 결정 = 리플레이 결정(항등).

### 0.3 A 기여 경로 — 정직판

레버 감사의 전제는 다음과 같다.
- A 가 되려면 Calmar +0.16 과 OOS +0.36 이 **동시에** 필요하다.
- 7블록 어느 것도 둘을 함께 올리지 못한다.
- OOS 벽은 2017~20·2025~26 두 구간의 공통 활성 성분이다. PT≥2 인 157칸 가운데 2017~20 활성 IR 이 양수인 칸은 2% 다.

| 경로 | 기전 | 사전확률 [판단] |
|---|---|---|
| (a) 확약 층 합성이 직접 A | as-of 선택은 후보 풀에 없는 수익을 만들지 못한다. 2017~20 에 양수인 후보가 2% 이면 어떤 as-of 규칙도 그 구간을 건너지 못한다 | 현 후보 풀에서 ≤0.5% |
| (b) PR-L1(cap_core)이 확인된 뒤의 합성 | 벤치 인지 후보가 풀에 들어오면, 합성이 as-of 증거만으로 그것을 적시에 고르는지가 첫 실검정이 된다. 다만 국면 타이밍 주장이라 선례가 나쁘다(오버레이 22칸 0 pass · FR 로테이션 기여 0) | PR-L1 자체 3% 위에 +≈0.5%p |
| (c) 예산 회수 → 신규 논문 | entry 당 약 10~15칸(B3 5 · B3 을 쓰는 B4 4 · B5 초과분)을 새 기저로 돌린다. 기저 품질이 결과를 거의 예측하지 않는다(D10-06)는 진단 때문에 칸당 가치는 작다 | +≈0.5~1%p / 8주 |
| (d) 간접 — 가장 큰 가치 | ① 구속 축 OOS retention 을 선택 편향에서 보호한다. 전기간 argmax 로 고른 승자의 retention 은 OOS 창을 보고 고른 값이다(measurement-graduation §3 chain ② 'IS-only 선택' 이 막으려는 것). ② 적응 층 산출이 엄격 D-E 로도 Judge 를 통과할 수 있는 유일한 형태다. ③ 유기체 자신의 OOS 계기(자율이 이득인지 재는 자)를 준다 — 디렉터가 결정을 하나도 못 바꾸고 자기 채점도 못 했던 전철을 막는다. ④ 선택 인플레를 실측한다(현행 규칙 대 그 as-of 쌍둥이 합성의 차) | A 확률 아님 |

**종합**: 8주 안 권위 A 에 대한 직접 기여는 +≈1%p 다 [판단 — 플랜의 프로그램 사전확률 약 5% 대비]. 이 설계를 A 레버로 보고하지 않는다. 이 설계는 **정직성과 효율의 기계**다.

---

## 0.5 지형 지도 검증·보강 (코드 직접 확인)

**확인된 것** [확인]
- `rf_budget_want = max(auto, manual)` 이고 감산 경로는 0 이다(`rf_runner_gates.R:92-101`).
- 승자 argmax 는 `:683-684` 에 있다. B1 port_t(:726), B2 port_t·B3 calmar(:729), B5 calmar + 적대검증 게이트(:736)다.
- 바닥 argmax 는 `:774-776`, 진단 argmax 는 `:766-767` 이다.
- vintage 보류는 attempt 자기 표식만 읽는다(`:552-559`). **P0-14 구멍은 실재한다.**
- `RF_DECISION_KINDS` 에 budget·block_winner·floor·promote 가 등재돼 있지만 러너 호출은 a_eligibility 1종뿐이다.
- 러너에서 'oos' 문자열은 0회 나온다.
- `b5_budget` 키가 없다.

**정정·보강**
1. **리플레이 엔진의 '공개된 접두'는 연구 시각 접두다.** `replay_engine.R:3-8` 이 그렇게 정의하고, 뷰(`:45-48`)는 공개된 칸의 **전기간** score·calmar·oos 를 그대로 싣는다. 따라서 시장 시각 as-of 선택 계기는 운영·연구 어디에도 없다. 지형 B G2 의 '연구 시점 as-of 존재'는 연구 시각에 한해서만 맞다.
2. **B1 as-of 는 결정 시각이 아니라 고정일(2005-01-01)이다.** 청정하지만 선정 표본이 2005 이전 IC 뿐이다. 최소 표본은 `B1.selection_asof.min_ic_months` 가 정한다.
3. **원장 노출 규모** [재집계·진단]
   - 측정 칸(port_t 유한) 1,238 중 **1,030칸(83%)** 이 성과로 고른 바닥·carry 위에 선다.
   - H2 조상이 없는 칸은 뿌리 entry 의 B1 칸 208 뿐이다.
   - 계보 28 · carry entry 17 · 미측정 73.
   - H1 표식: `selection_basis_full_sample_ic` 60 · `…_inherited` 501.
   - 이 수치가 §2 선택지들의 비용이다.
4. **`policy_state.R` 의 자동 live 는 `QVEST_POLICY_UNATTENDED="1"` 을 명시할 때만 선다**(`:33-34`, 기본 0 — DIR-ABSORB-ITEMS ④). stats 필드(heldout_win·null_pct·discovery_drop…)는 방향 세계 리플레이용이라 WF 지표와 1:1 대응이 없다. 따라서 어댑터가 필요하다(상태기계 `pol_transition` 은 재사용).
5. **칸을 줄이면 `max_attempts` 가 아니라 격자 소진(`:1263 rf_grid_consumed → .exhaust_and_delegate("grid")`)으로 이월된다.** 그래서 예산 층은 `max_attempts` 를 건드리지 않고 칸 수만 줄여도 회수가 된다.
   - 단 `:547 halt_no_free_cell` 은 빈 칸 0 ∧ used < length(cells) 일 때 소진 없이 멈춘다.
   - 따라서 칸 절단에는 '**시도가 있는 코드는 절대 지우지 않는다**' 불변식이 필수다.
6. `rf_record_decision` 은 미등재 kind 에서 stop 한다(`reinforce_ledger.R:720`). 적응 층 kind 를 먼저 등재해야 한다.
7. `rf_decisions.jsonl` 은 3행이다(레버 감사 과정 렌즈의 '미확인' 해소).
8. 부재를 확인한 것: `rf_prereg.R` · `rf_trial_log.jsonl` · `contracts/selection_accounting.R` · `contracts/tilt_attribution.R`. `06_Registry/prereg/` 에는 08-24 파일 1개뿐이다.
9. `reinforce_program.json` 의 `select_winner_by` 값(B1 port_t · B2 port_t · B3 calmar · B5 calmar)은 러너 리터럴과 일치한다. 따라서 pi0 가 program 을 읽어도 비트 동일이다(P1-05 전제 성립). B6·B7·B4 선언은 대응 호출 자체가 없다.
10. essence OOS 분할은 칸 표본의 비율이다(0.55/0.65/0.75 — `essence_score.R:193`). 달력판 `diagnostics.oos_calendar_splits` = 2016-11-30 · 2019-02-11 · 2021-04-08 은 2005 시작 칸에서 비율판과 같도록 등록됐다(`:255-256`). 따라서 IS-only 기준일 τ_IS 를 리터럴 없이 config 에서 읽을 수 있다.
11. **결정 레지스터 writer 는 owner 인자를 받는다**(`dr_open(owner=)` · `dr_resolve` 는 decided_by == owner). 기계 결정은 owner=`machine:organic` 로 열고 즉시 닫으면 되고, 새 writer 는 필요 없다.

---

## 1. 4층 설계

### 1.0 공통 부품 (4층이 모두 쓴다)

**(a) `wf_asof_stats` — 신규 R 계약** `02_Infrastructure/contracts/wf_asof_stats.R`
- 입력: 칸의 현행 규약 수익(rebase 형제 판 `remeasure_<regime>/03_period_returns` + 벤치)과 τ.
- 산출: m_τ(c) = {PT_τ, IR_τ, SR_τ, CAGR_τ, MDD_τ, Calmar_τ, n_τ}.
  - t ≤ τ 행만 쓴다.
  - PT_τ = `build_benchmark_compare` 의 `Portfolio_Alpha_t_NW_lag3` 와 **같은 함수**다(복제 금지).
- 계약 두 가지:
  - τ = 표본 끝이면 authoritative essence 와 `identical` 이어야 한다.
  - τ 이후 수익을 섭동해도 m_τ 는 비트 불변이어야 한다.
- P1-03 `sa_subwindow`(2024-12 절단판)를 임의 τ 로 일반화한 것이다.

**(b) `rf_asof_view(r, τ)` — 컨트롤러의 유일한 데이터 접근자**
- `closed_at < r` 인 칸만 돌려준다.
- 열 = m_τ + 구조 필드(계보·블록·arm 키·표식·규약·설계 출처).
- **essence·등급·retention·DSR 열은 없다.**
- 컨트롤러 코드가 원장·essence 를 직접 읽는 것은 정적 파싱으로 금지한다(§5).

**(c) 제한 목적함수 J (목표 축 상한)**

  J_τ(c) = min_{j ∈ {PT, SR, CAGR, Calmar}} min(1, m_{j,τ}(c) / θ_j)

- θ 는 `tier_graduation` 에서 읽기만 한다. 동률은 Σ_j min(1, ·) 로 깬다.
- 상한 1: PT 를 2.95 위로 더 밀어도 가치가 0 이다. 레버 감사가 확인한 PT 추격(구속 축이 아닌 축)을 구조적으로 막는다.
- OOS retention·DSR 은 넣지 않는다. 이유는 둘이다: 비율 Goodhart(IS 희석으로 retention 상승)와 A 서류와의 분리. **OOS 는 칸 특징이 아니라 정책의 τ 이후 성적으로만 들어온다**(§1.3).

**(d) 잡음 척도 σ**
- 짝지은 일간 차이의 블록 부트스트랩을 쓴다(`rf_overlay_adversary.R::adv_block_len(rule="auto")` · Politis & White 2004).
- P1-06 null-factor 희석 칸을 함께 쓴다.
- 위상쌍 B6_32/33 은 쓰지 않는다(계통 효과 — 레버 감사).

**(e) 경험 베이즈 수축** (Efron 2011, Tweedie 공식의 선택 편향 보정)

  Δ̂_EB = μ̂_b + (1 − B_b)(Δ_obs − μ̂_b),  B_b = σ² / (σ² + τ̂_b²),  τ̂_b² = max(0, Var_b(Δ_obs) − mean σ²)

- b = 블록(또는 arm 계열)이고, 군집은 계보 뿌리다.

**(f) AAC — as-of 조상 일관성** `02_Infrastructure/reinforcement/rf_aac.R` (신규)
- 칸 c 의 조상 노드 n(B1 승자 · 바닥 · B2/B3/B5 승자 · 승격 best)마다:
  - K_n = r_n 이전에 닫힌 자격 칸(RF_ROLE_CHECKS 동일)
  - k*_n = 실제 선택

  AAC(c, τ) = ∧_n [ argmax_{k ∈ K_n} ρ_n(m_τ(k)) = k*_n ]

  - ρ_n = 그 노드 현행 규칙의 as-of 쌍둥이다(PT 또는 Calmar).
  - 뜻: "그 시점까지의 데이터만 봤어도 같은 조상을 골랐는가".
- τ 에서 후보 통계가 정의되지 않으면(τ < 첫 보유 + min_is) 그 노드는 미결이고 AAC 는 거짓이다(fail-closed).
- **H1clean(c)**: 조상의 B1 팩터 집합 노드가 둘 다를 만족해야 한다.
  - `selection_basis` ∈ {asof_ic, literature}
  - 설계 출처 ∈ {rule_asof, llm_blinded(R2 배포 뒤)}
  - P0-14 의 계보 승계 표식을 그대로 읽는다.
- **노드 복원**: 칸 spec 의 승계 성분(factors · weighting · universe · overlay)마다, 그 성분을 **자기 축 처치**로 가진 같은 entry 칸을 출처로 찾는다(서명 기반 — 규칙이 시기마다 바뀐 것에 강건).
  - 양성 대조: `floor_code` 가 기록된 칸(09-17 이후 B5)에서 복원 바닥이 기록 바닥과 ≥99% 일치해야 한다.
  - 복원 불일치 칸은 AAC 거짓이다.

### 1.1 예산 층

- **상태 변수**
  - 블록별 개선 확률 P̂_b
  - 블록 레버 시간 안정성 S_b
  - entry·블록 칸 수 n_{e,b}
  - 신규 논문 비중 s_new(7일 이동)
  - 레인 가중 λ_ℓ
- **결정 규칙**
  1. 짝지은 개선 ΔJ_c = J(c) − J(floor(c))(같은 규약·같은 창)로 계보 군집 부트스트랩 + EB 사후를 만든다. P̂_b = Pr(ΔJ_b > 0).
  2. 칸 배정:
     n_{e,b} = n_min,b + ⌊(n_grid,b − n_min,b) · min(1, P̂_b / p_ref)⌋
     - **축소는 S_b ≥ s_min 일 때만** 한다. 음의 효과가 시간적으로 안정할 때만 줄이고, 불안정하면(한 에피소드의 산물) 격자를 그대로 둔다.
  3. **D-G(도훈 결정 — 사람 규칙이라 shadow 없이 live 가능)**: 프로그램 G2 pass 0 ∧ compose_only 지속이면 n_B5 = 상주 + 2 로 줄이고, pass 가 생기면 복원한다.
  4. entry 조기 종료(shadow 전용 후보): Pr(남은 블록 중 하나라도 ΔJ > δ) < p_stop 이면 소진·이월한다. 판정 축은 J 이고 PT 가 아니다(레버 감사 ④ 지시).
  5. 회수된 칸은 신규 논문으로 간다. next_paper 순서 = FIFO(P1-08) + 신규 논문 하한 s_new ≥ s_floor(D-G '승격 세대당 신규 논문 ≥1' 을 비율로 옮긴 것).
  6. 예측 기록: 매 배정에서 P̂_b 를 trial log 에 쓴다. 그 블록 측정 뒤 결과 1{max ΔJ_b > 0} 로 Brier 채점한다(연구 시각 전방 · Gneiting & Raftery 2007).
- **레버 시간 안정성 S_b (시장 시각 WF)**
  - τ 격자를 m 등분한 **비중첩 등길이 창** W_1..W_m 을 쓴다. 사건 기반 분할은 금지한다 — 2017~20 을 보고 자르지 않는다.
  - S_b = 창별 ΔJ_b 부호 일치율.
  - 병기: τ_k 까지 추정한 Δ 와 (τ_k, τ_{k+1}] 실현 Δ 의 순위상관 ρ_b^WF(τ 평균).
  - ρ^WF ≈ 0 이면 "레버 효과가 에피소드 산물이다"로 읽고, Δ 로 예산을 움직이지 않는다(균등 배정 유지). 유기체가 스스로 '배울 수 없음'을 아는 계기다.
- **입력**
  - `rf_asof_view(r, τ_latest)` 의 m_τ.
  - 제외 표식: vintage_flags · pit_c11 · treatment_misspecified · window_deviation · 규약 ≠ 현행 · 적대검증 미통과 B5.
- **갱신**: 블록 진입 시 1회 결정한다. 사후분포는 야간, S_b 는 주간에 갱신한다.
- **파라미터** (`reinforce_auto_config.json::organic.budget.*` — 사람 소유 · 기계는 읽기만)

  | 키 | 값 | 근거 |
  |---|---|---|
  | n_min | B1 3 · B2 2 · B3 1 · B5 상주+2 · B6 2 · B7 사전등록값 · B4 1 | 레버 감사 ②(B3 는 '진단 1칸') · D-G · B6 위상쌍 유지 |
  | p_ref | 0.5 | D-F soft '다음 세대 예산 ∝ P(Δ>0)' — 비례 상수 = 동전던지기 기준(evidence=method) |
  | s_min · m | 0.75 · 4 | evidence=none(강화 레인 면제) — 사전등록 동결 |
  | p_stop · δ | 0.1 · 0.01 | shadow 전용, 사전등록 동결 |
  | s_floor | D-G 하한 | 도훈 결정 |

  - 문헌: 수축 = Efron 2011 · 블록 부트스트랩 = Politis & White 2004 · 채점 = Gneiting & Raftery 2007.
- **러너 개입 지점**
  - `reinforce_auto_parallel.R:436` 뒤 1줄: `cells <- rf_organic_cells(cells, E, ROOT, log = jlog)`. 꺼져 있으면 항등이다.
    - 불변식 ①: 시도가 있는 코드는 지우지 않는다(`:547` 정지 경로 회피).
    - 불변식 ②: 블록 진입 전 1회만 결정하고, 원장에 기록하며 덮어쓰기를 거부한다(`rf_record_block_order` 선례).
    - 불변식 ③: B4 는 0칸 블록을 참조하는 LOO 칸만 제거한다(남은 축 전결합은 유지).
  - `:446-460`(max_attempts·`rf_budget_auto/want`)은 불변이다. 감소는 격자 소진 경로로 실현한다.
  - `reinforce_auto_next_paper.R:61-65` LIFO → exhausted_at 오름차순(P1-08). 레인 가중은 `organic_state.json` 에서 읽는다.

### 1.2 공간 층 (arm 생성·휴면)

- **상태**
  - arm 별: n_a · ΔJ_EB,a · P̂_a · 부호 안정성 S_a · 상태(active|organic_paused) · 휴면 시각 · 부활 탐침 수
  - 생성 레인별 수율 y_ℓ
- **규칙**
  - **휴면**: P̂_a < p_pause ∧ n_a ≥ n_min ∧ 음 부호 일치율 S_a ≥ s_min 이면 `organic_paused`. 금지가 아니라 휴면이다(AX-000 · INV-7).
  - **부활**: 새 뿌리 entry K 개마다 휴면 arm 계열당 탐침 1칸을 배정한다(탐색 쿼터). 탐침 ΔJ 로 P̂ 를 갱신해 p_pause 위로 올라오면 active 로 돌린다.
  - **생성 레인 쿼터**: q_ℓ = min(q_cap,ℓ, round(q_cap,ℓ · y_ℓ / y_ref))
    - q_cap 은 사람 config 이고, 기계는 **줄이기만** 한다.
    - y_ℓ = 그 레인이 낸 arm 중 (G1 통과 ∧ 측정 ∧ ΔJ > 0 ∧ B5 면 G2 pass) 비율.
    - y = 0 이 w 주 지속되면 q = 0 이다(D-G 'overlay_propose dead 동안 정지').
  - **생성 출처 라벨**: M2 배포(09-25 15:01) 이전 LLM 생성 arm 은 `generation_unblinded` 다. 연구 시각 사후지식이므로 확약 층 후보 자격이 없다.
- **입력**: 1.1 과 같은 뷰 + `overlay_arm_ledger.jsonl`(방출·기각) + 카탈로그(읽기).
- **갱신**: 주간. 주간 상한 = max_pause_per_week.
- **파라미터** (`organic.space.*`)
  - p_pause 0.10 · n_min 8 · s_min 0.75 · revive_every_entries 10 · max_pause_per_week 2
  - yield_window_weeks 2 — 선례: B5 설계 H3 `stagnation_window` 2
  - 근거는 evidence=method/none 이고, 전부 사전등록 동결이다.
- **개입 지점 — 기계는 카탈로그를 고치지 않는다**
  - 자기 파일 `06_Registry/organic_state.json::arm_status` 만 쓰고 픽커가 그것을 읽는다. 각 1줄 필터이며, 파일이 없으면 필터도 없어 비트 동일이다.
  - `rf_weight_arms.R:40` · `rf_overlay_arms.R:47` · `rf_factor_arms.R:271-282`(keep 술어).
  - `rf_block_design.R:90-111`(`rfbd_catalog`) — 설계 레인이 휴면 arm 을 설계로 되살리지 못하게.

### 1.3 선택 층 + 확약 층 C

- **상태**: live 선택 정책 π_live(버전) · shadow 정책 집합 · 정책별 합성 C_π 의 구간 목록 {(τ_k, c_k)}.
- **정책 가족** (사전등록 v1 — 사후 추가 금지. 추가는 새 가족 = 새 N)

  | 정책 | 규칙 | 역할 |
  |---|---|---|
  | π_0 | 현행 규칙의 as-of 쌍둥이(역할별 PT/Calmar argmax) | **계측용** — "현행 규칙이 PIT 였다면 얼마였나" = 선택 인플레 실측 |
  | π_1 | argmax J_EB,τ(수축된 제한 목적) | 절제(ablation) |
  | π_2 | π_1 + 교체 이력현상: 현재 보유 칸 c_{k−1} 이 τ_k 의 모형신뢰집합(MCS, α=0.10)에 남아 있으면 유지하고, 탈락하면 J_EB argmax 로 교체 | **확약 1차(primary)** — 잡음 추격·교체 비용 억제 |
  | π_R | τ_k 마다 허용 집합에서 균등 무작위(시드 고정) | **음성 대조**(Li SSRN 7190318: 에이전트 = 같은 예산 무작위와 구분 불가) |

  - MCS 출처: Hansen, Lunde & Nason 2011.
- **확약 층 합성** `02_Infrastructure/reinforcement/rf_wf_composite.R` (신규)
  - τ 격자 T = {τ_1 = 2005-01-01 + min_is, τ_1 + Δτ, …}.
  - **허용 집합** A_k = {c : AAC(c, τ_k) ∧ H1clean(c) ∧ 표식 청정 ∧ 규약 = 현행 ∧ 월간 집행}. v1 은 B6 간격 칸을 제외한다.
    - 선택 민감도(기본 off): `publication_asof` — 기저 논문 최초 공개일 ≤ τ_k 인 칸만 허용(McLean & Pontiff 2016 · Chen-Welch 2607.06502).
  - c_k = π(A_k, m_{τ_k}).
  - 보유 = c_k 의 **저장 목표 비중**을 τ_k 뒤 첫 집행일부터 다음 교체 전까지 쓴다. 그 비중은 τ_k 이전 시그널일에 확정된 것이라 PIT 다.
  - 구간 0 [2005-01, τ_1] = 사전등록한 문헌 선택 칸이다(기저의 실투형 B1_0 — P1-06 이 만든다 · D-E 면제 '사람이 문헌 근거로 고르는 것').
  - **측정은 R 계약으로 한다.** 구간 보유를 이어 붙여 다음 순서로 태운다.
    1. rfh 부품(`rfh_load_market` · `rfh_restore_weights`)
    2. replication 하네스(close_t1 · 15bps · 교체일 Δw 비용 포함)
    3. `build_bt_result` → audit → `essence_score(selection_type="sweep", n_trials = N_policy_family)`
    4. 결과 = `stage_artifacts/wf_composite/<id>/authoritative_remeasure.json`
  - 고정 축은 칸마다 이미 성립한다. 이어 붙인 보유는 `rf_preflight_verify_axes` 로 다시 도출해 확인한다.
- **탐색 층 live 선택**
  - `rf_select_value(a, role, block, policy, ctx)`. pi0 은 program `select_winner_by` 를 실제로 읽으며 비트 동일이다(§0.5-9).
  - 정책 교체는 §3 G4 판정식을 통과한 것만 한다.
  - 권고 (iii) 아래에서 탐색 층 live 규칙에 들어갈 수 있는 것은 **π 가족 규칙을 τ_live 에 적용한 것뿐**이다. 전기간 전용 신규 규칙은 금지한다.
  - **같은 규칙이 두 층에 쓰인다**: 탐색 층에서는 τ_now 에, 확약 층에서는 각 τ_k 에 적용된다. 따라서 합성의 τ 이후 성적이 곧 그 규칙의 OOS 다(연구 과정 자체의 OOS).
- **입력**: `rf_asof_view(r_k, τ_k)` · AAC 표 · 저장 보유(`bt_result.rds$holdings` · `04_holdings`).
- **갱신**: 합성은 주간 재구성하고, τ_k 에 도달하면(반기) 구간을 추가한다. live 교체는 주 1회 이하다.
- **파라미터** (`organic.wf.*` · `organic.select.*`)

  | 키 | 값 | 근거 |
  |---|---|---|
  | min_is_months | 36 | `rolling_grade.R` 36M 창(rg_params) 선례 + MinBTL(Bailey et al. 2014: N=4, 목표 SR 1 이면 ≈2.8년 ≤ 3년) |
  | step_months | 6 | Tashman 2000 rolling-origin — 원점 수(≈37)와 교체 비용의 균형. 사전등록 동결 |
  | publication_asof | false | 민감도 |
  | mcs_alpha | 0.10 | Hansen-Lunde-Nason 2011 |
  | shrink | tweedie_eb | Efron 2011 |

- **러너 개입 지점 (5자리, 전부 pi0 에서 비트 동일)**
  - 러너 `:683`: `.winner_of` 의 `.metric(a, by)` → `rf_select_value(...)`.
  - `:766` · `:774`: 바닥 argmax.
  - `rf_promote.R:59` · `rf_lesson.R:115`.
  - 결정 기록: `.winner_of`·바닥 직후 `rf_record_decision(kind = block_winner/floor, shadow = π_1·π_2 의 선택)` — P1-05.

### 1.4 구조 층

- **상태**: 블록별 칸 상한 n_b(격자 이하) · 상주 통제칸(P1-06) 활성 · 승격 파라미터(연장 여백) · 레인 가중.
- **규칙**
  - **블록 비활성**(n_b = n_min,b)은 1.1 규칙의 프로그램 수준 판정이다(전 entry 공통): S_b ≥ s_min ∧ P̂_b < p_off 가 연속 k 주 지속될 때.
  - **승격 연장 여백**: 고정값 0.01 을 z · σ_ΔCalmar(짝지은 부트스트랩 SE · 레버 감사 실측 약 0.07~0.15)로 대체한다 — D-F '잡음 파생 여백'.
  - **soft 승격**: 다음 세대 칸 수 ∝ P̂(ΔJ > 0)(D-F). 칸 절단으로 적용한다.
  - 깊이 하드 6(사람 config)은 불변이다.
- **금지**: 블록 신설 · 격자 칸 확대 · `fixed_axes` · 블록 의존(B2/B3 는 B1 위, B4 는 승자 위) 변경.
- **갱신**: 주간 평가. 구조 변경은 월 1회 이하.
- **파라미터** (`organic.structure.*`): p_off 0.10 · consecutive_weeks 2 · promote_margin_z 1.0(evidence=method — D-F).
- **개입 지점**
  - 1.1 과 같은 훅(`rf_organic_cells`).
  - `reinforce_auto_next_paper.R` 승격 분기(`:130-215`)가 `rf_promote_decide(entry, best, cfg)` 에 넘기는 cfg 에 organic 여백을 병합한다. `rf_promote_extend_ok`(`rf_promote.R:74-87`)는 이미 cfg 로 받으므로 함수는 불변이다.

---

## 2. D-E 정합 — 적응 층의 선정 통계는 C1/C14 에 걸리는가

### 2.1 분류

| 유형 | 정의 | 예 | 보유 경로에 들어가나 | 시행 N 계상 |
|---|---|---|---|---|
| **H1** | 칸 구성 **안에서** 데이터 통계로 고른다 | B1 IC 픽커 · LLM 설계(전기간 IC 재료) · B7 ic_bad | 예 | 아니오(숨은 시행 — 풀 370종) |
| **H2** | 측정된 칸들 **사이에서** 성과로 골라 다음 칸 구성에 심는다 | 블록 승자 · 누적 바닥 · carry · 승격 best | 예(자식 칸) | 예(P0-01 계보 N) |
| **R** | **무엇을 측정할지** 정한다 | 예산 · arm 휴면 · 생성 쿼터 · 레인 순서 · 조기 종료 | 아니오 | 간접(후보 집합을 바꿔 최종 선택 편향을 키운다) |
| **C** | 시간가변 구성(τ_k 마다 선택) | 확약 층 합성 | 예 — 단 ≤τ_k 정보만 | 정책 가족 N |

원장 노출 [재집계·진단]: H2 조상 1,030/1,238(83%) · H1 표식 60 + 승계 501.

### 2.2 선택지

| | (i) 회계형 | (ii) 엄격 WF형 | (iii) 경계형 — **권고** |
|---|---|---|---|
| D-E 적용 범위 | H1 만 | H1 ∪ H2 ∪ 적응 층의 모든 성과 기반 자동 선정 | H1 = C1 · H2 기존 격자 = 다중검정 영역 · 적응 층 = 전 결정 as-of · R = C1 아님(기록 의무) |
| 격자 승자·바닥 | 다중검정(09-23 결정 (A) 그대로) ✓ | C1 — 탐색 도구로만 존치. (A)의 '전기간 데이터 유지'와 충돌하므로 **재결정 필요** | 다중검정 + A 서류에 as-of 경로 감사 ✓ |
| carry·승격 | 다중검정 ✓ | 탐색 전용 | 다중검정 + 감사 ✓ |
| 22632 표식 | H1 승계 → C1 ✓(P0-14) | ✓ | ✓(P0-14) |
| 적응 층 | 전기간 essence 로 자유 최적화(시행 기록만) | 전부 as-of | 전부 as-of · A 후보는 확약 층 합성만 |
| A 가능 경로 | 정적 칸 전부 | H2 조상 없는 칸(뿌리 B1 규칙 칸·기저) + 합성 | 정적 칸(다중검정 + 표기) + 합성 |
| 약점 | ① IC 로 고르기와 PT 로 고르기는 미래 참조량이 같다 — 선의 근거가 '계상 여부'뿐이다. ② 누출 오라클이 DSR 을 통과한다(Gençay 2608.27734 — 통계 보정은 누출을 못 잡는다). ③ 자율 제어기가 평가 창 전체를 목적으로 최적화하면 유효 시행 수가 적응적으로 늘어 계보 N 으로 못 잡는다(Dwork et al. 2015). ④ 구속 축 retention 이 선택 편향으로 오염된다(chain ② 가 막으려던 것) | 1,030칸이 A 불가다(현재 A 0 이라 잃는 A 는 없으나 2계층 B 풀 공급은 별개 판단). 직접 A 사전확률이 더 낮아진다. 사람의 문헌 선택 면제와 기계의 구성 탐색을 비대칭으로 다룬다 | H2 에 이중 기준(기존 = 다중검정, 신규 = as-of) — 과도기 조항으로 명시하고 일몰을 둔다 |

**부속 선택 ORGANIC-TAU-LIVE** — 탐색 층 live 선택 통계의 τ
- (a) τ_latest(현행 · (iii) 아래 권고).
- (b) τ_IS = `diagnostics.oos_calendar_splits[1]` = 2016-11-30.
  - measurement-graduation §3 chain ② 'iteration 중 변형 선택은 IS-only' 를 준용한 것이다.
  - **봉인이 아니다**: 데이터는 등급·보고·전략 구현에 전부 쓰이고, 자동 선정의 입력에서만 빠진다.
  - 다만 lockbox 폐지 조항('가용 데이터 모두 활용')과 긴장이 있으므로 도훈 판단 사항이다.

### 2.3 권고 근거

- **확약 층은 '프로세스 수준 PIT' 의 운영판이다.** AEAP(2609.00731, Pan·Ding·Giesecke)는 발굴 루프를 과거 각 시점에 재실행해 2025 대표 시스템들의 OOS 가 ≈0 임을 드러냈다.
- **(i) 은 비권고다.** 통계 보정은 누출을 못 잡는다(Gençay). 그리고 자율 제어기는 평가 창을 목적으로 삼는 순간 적응적 선택기가 된다.
- **(iii) 은 최소 변경이다.** 09-23 (A) 결정을 뒤집지 않으면서, 자율 층이 새 누출 통로가 되는 것만 구조적으로 막는다.
- **(ii) 는 문언상 가장 일관된다.** 그래서 스위치 하나로 (ii) 로 전환할 수 있게 설계한다. `a_eligibility_gate.json` 에 보류 코드 `selection_path_full_sample` 을 신설한다(기본 off · 도훈 소유). 켜면 H2 조상 칸의 A 가 보류된다. `RF_A_HOLD_CODES` 는 코드 집합 일치를 요구하므로(`rf_runner_gates.R:468-470`) 코드 추가와 설정 추가는 한 커밋이어야 한다.

### 2.4 결정 안건 문안 (`decision_register.json` 형식 · owner dohoon)

**ORGANIC-DE-SCOPE** — 자율 적응 층과 격자 자동 선정(승자·바닥·carry·승격)의 D-E(pit.md C1) 적용 범위
- options: (i) 회계형 — H1 만 C1 · (ii) 엄격 WF형 — 성과 기반 자동 선정 전부 C1, A 는 H2 조상 없는 칸·WF 합성만 · (iii) 경계형
- recommendation: **(iii)**
  - H1(칸 구성 안 데이터 통계 선정) = C1(현행).
  - H2(측정된 칸 사이 성과 선정) = 09-23 (A)대로 다중검정 영역. 단 A 서류에 as-of 경로 감사와 retention 선택편향 표기를 싣는다.
  - 적응 층 신규 결정 = 전부 as-of(시장 τ · 연구 r).
  - 적응 층의 A 후보 = WF 합성만.
  - (ii) 전환 스위치 = `a_eligibility_gate.json::selection_path_full_sample`(기본 off).
  - 일몰: O1 첫 성적표 또는 첫 A 후보 중 먼저 오는 시점에 재상정.
- default_until_decided: 적응 층은 O0~O1(관측·shadow)만 진행하고 live 는 없다.

**ORGANIC-TAU-LIVE** — 탐색 층 live 선택 통계의 시장 τ
- options: τ_latest / τ_IS(2016-11-30 · IS-only 선택)
- recommendation: τ_latest(현행) + 정적 A 후보에 retention 선택편향 표기
- default_until_decided: 현행

**ORGANIC-N-SCOPE (D-A')** — 적응 층 아래 시행 수 N 정의
- options: 계보 N 유지 / 계보 N + 적응 결정 대안 수(단조 증가) / 프로그램 N
- recommendation: **계보 N + 적응 결정 대안 수**(DSR 게이트 입력). 프로그램 N 과 N_eff 는 서류에 병기만 한다.
- default_until_decided: 계보 N(현행 D-A)

**ORGANIC-COMPOSITE-OBJECT** — WF 합성을 A·Judge·BOOK 대상 객체로 인정하는가
- recommendation: **예.**
  - 합성은 고정 축을 만족하는 보유 경로를 가진 전략이다.
  - frozen 스펙 = {정책 버전, τ 격자, 후보 풀 동결 목록, 구간 0 칸}.
  - `/book` 트래킹은 같은 규칙이 새 τ 마다 as-of 로 계속 고르는 '살아 있는 스펙'이 된다.
  - Judge 6축은 그대로 적용하고, AAC 경로 감사를 추가한다.
- default_until_decided: 합성은 보고만 한다(A 발행 없음).

---

## 3. 가드 8종

| 가드 | 구현(파일·함수) | 검사(양성 대조 · 위반 주입 · 돌연변이) |
|---|---|---|
| **G1 시행 회계** | `rf_trial_log.jsonl`(P1-02 writer 재사용) · kind = organic_proposal / organic_shadow / organic_live / organic_reject / organic_prediction. N 이중 도출: ① 컨트롤러 계수 ② 서류가 trial log + 원장에서 독립 재도출 → 불일치 = K1 | 제안 1건 기각 주입 → 로그 1행과 N+1 확인 · 로그 쓰기 실패 주입 → 결정 미집행(fail-closed) · 계수 함수 돌연변이 → 이중 도출 불일치로 red |
| **G2 as-of 만** | `rf_asof_view(r, τ)` 유일 접근자 · `wf_asof_stats` · 정적 파싱: 적응 층 파일에 `essence`·`authoritative_remeasure`·`oos_retention`·`dsr`·`rf_load(`·원장 경로 `fromJSON` 토큰 금지(주석 제외) | τ 이후 수익 섭동 → 모든 결정 비트 불변 · r 이후 원장 레코드 섭동 → 불변 · 양성 대조: `a$essence$calmar` 를 읽는 가짜 정책은 섭동 검사와 파싱 검사 둘 다 red |
| **G3 자동 사전등록** | `rf_prereg.R`(P2-01) 스키마 재사용 → `06_Registry/prereg/adapt/<policy>_<ver>.json`: 가설 · 1차 지표 · 검정력 3종(ratio · 기대 t · 검정력 — measurement-graduation 착수 크기산술 관문) · 멈춤 · 사전확률 · `hypothesis_index lookup` 첨부. **사전등록 단위 = 정책 버전**, 결정 단위 = 그 아래 예측 기록. 덮어쓰기 거부 | 같은 id 재쓰기 → stop · 검정력 ratio < 0.15 → '착수 금지'(shadow 전용 라벨) · 사전등록 없는 정책의 shadow 진입 → 거부 |
| **G4 shadow→리플레이→live** | `axiom/replay/policy_state.R::pol_transition` 재사용 + WF 통계 어댑터 `rf_organic_polstats()` · 판정식은 아래 | 알려진 개선을 심은 합성 정책 → live · π_R → 항상 탈락 · τ 라벨 순열(플라시보) → 효과 소멸 |
| **G5 킬스위치** | 사람 스위치 `organic.enabled` · `organic.layers.*.enabled`(읽기 전용) + 기계 자기 정지 `organic_state.json::killed`(기계는 **끄기만**, 켜기는 사람) · 발화 조건 K1~K8 | 조건마다 합성 열화 주입 → 발화 · 주간 자가 검사(샌드박스 사본) |
| **G6 롤백** | `06_Registry/organic_actions.jsonl`(append-only · {decision_id, target, pointer, before, after, at}) · `rf_organic_rollback(decision_id | policy_version)` | 적용 → 롤백 → `organic_state.json` md5 가 적용 전과 동일 · 연쇄 롤백(정책 버전 → 그 버전 아래 휴면·칸 결정 전부) |
| **G7 결정 레지스터 자동 기록** | 정책 전이(proposed/shadow/live/demoted/tombstoned) · 킬 · 롤백 · arm 휴면/부활 · 구조 변경 → `dr_open(owner="machine:organic")` + 즉시 `dr_resolve(decided_by="machine:organic", evidence = decision_id + prereg 경로)`. 칸 단위 결정은 `rf_decisions.jsonl`(kind 등재 필요) | 기록 누락 돌연변이 → 전이 카운트와 레지스터 항목 수 불일치로 red · owner 위조(decided_by="dohoon") → 기존 writer 가 거부 |
| **G8 주간 보고** | `rf_organic_weekly.R` → `tg_agent_brief()` 단일 진입 · 표제 `[1계층·강화] 유기 적응 주간 보고` | `QVEST_TG_DRY_RUN=1` 드라이런 본문 스냅샷 · 섹션 누락 돌연변이 → red |

### 3.1 킬스위치 발화 조건 (수치는 `organic.kill.*`)

| 코드 | 조건 | 처분 |
|---|---|---|
| K1 회계 | G1 이중 도출 불일치 ≥1 | 적응 층 전체 정지 |
| K2 경계 | 보호 파일 md5 변화(§5) ∨ `rf_organic_write` 거부 발생 | 전체 정지 + 경보 |
| K3 PIT | 야간 섭동 자가 검사 red | 전체 정지 |
| K4 성과 | live 정책의 전방 e-과정이 1/α 를 넘음(α = `eprocess_alpha` 0.05 · 언제든 유효한 추론 — Ramdas et al. 2210.01948 · Howard et al. 1810.08240). R 형은 보정(calibration) 귀무, 선택형은 '현행 대비 열위 아님' 귀무 | 그 정책만 강등 → π_0 대신 현행(pi0) |
| K5 기아 | 7일 신규 논문 비중 < s_floor | 예산 층 정지 |
| K6 진동 | 주간 live 교체 > 1(policy_state `weekly_activation_max` 선례) ∨ 휴면 > max_pause_per_week | 해당 층 1주 정지 |
| K7 낡음 | 결정 시 상태 키(current_axis · 원장 md5 · 시장 지문) 불일치 | 그 결정 건너뜀(fail-closed). 3연속이면 층 정지 |
| K8 러너 건강 | tick 성공률이 7일 기준 대비 하락 > `runner_health_drop` | 전체 정지(러너를 깨지 않는다) |

### 3.2 롤백 단위
- 1차 단위는 **결정 id** 다. 정책 버전을 롤백하면 그 버전이 live 인 동안 낸 결정 전부가 연쇄로 롤백된다.
- 측정은 되돌리지 않는다(원장 attempt = 사실 기록). 대신 그 정책 아래 측정된 칸에 `organic_policy_version` 표식을 남겨 이후 집계에서 거를 수 있게 한다.

### 3.3 shadow → 리플레이 → live 판정식

live(π) ⇔ 아래 전부
1. 사전등록 존재 ∧ 동결
2. 리플레이: 1차 지표의 짝지은 차 ΔM_post(π, π_inc)의 정상 블록 부트스트랩(Politis-Romano) 90% 하한 > 0 ∧ 2차 지표 하한 > −ε
   - 선택형: M = 합성의 τ 이후 활성 IR(1차) · Calmar(2차).
   - R 형: M = 예측 Brier skill(연구 시각 전방) ∧ 레버 시간 안정성 S ≥ s_min.
3. 음성 대조: π 가 π_R 시드 분포의 ≥95 백분위
4. 플라시보: τ 라벨 순열에서 효과 소멸
5. 검정력: ratio ≥ 0.15. 미달이면 '미결' 라벨이고 live 하지 않는다.
6. shadow ≥ `shadow_min_weeks`(4) ∧ 유익한 불일치 ≥ 3(`pol_cfg` 도훈 09-21 ① 값 재사용)
7. 전방 e-과정이 '열위 아님'을 기각하지 않음
8. 경계·PIT 자가 검사 green ∧ 주간 활성화 ≤ 1

- demote(π) ⇔ K4 ∨ `pol_gate_demote`(최신 m 중 k 패 — 3/5).
- 자동 live 는 `organic.auto_live = true`(사람 config) ∧ 적응 층 셸이 `QVEST_POLICY_UNATTENDED=1` 을 **자기 프로세스에만** 설정할 때 선다. 전역 기본 0 은 유지한다.

### 3.4 주간 보고 내용 (`[1계층·강화] 유기 적응 주간 보고`)

1. 상태: 킬스위치 · live 정책·버전 · 층별 활성
2. 이번 주 결정 수(층별 · 제안/기각/shadow/live/강등) · **러너 결정이 현행과 달라진 횟수**(디렉터 전철 감시 — 결정을 실제로 바꿨는가)
3. WF 성적표: 합성 π_0/π_1/π_2/π_R 의 τ 이후 활성 IR · Calmar · 90% CI · 검정력. **IS(2005~16) 활성 IR 병기 의무**(레버 감사 '하지 말 것')
4. 연구 시각 전방 채점: Brier · skill · n · 보정도
5. 레버 시간 안정성: 블록별 S_b · ρ^WF
6. 예산 흐름: 신규 논문/승격/사전등록 비중 · 회수 칸 수(원장 재도출)
7. arm 휴면·부활 목록과 사유
8. N 변화: 계보 · 프로그램 · N_policy_family · DSR 영향
9. 경계 감사: 보호 파일 md5 불변 확인
10. 킬·롤백 사건
11. 진짜 전방 구간 누적 일수(합성 동결 이후)

---

## 4. 시행 회계

| 객체 | selection_type | N | 근거 |
|---|---|---|---|
| 정적 칸(탐색 층) | sweep | 계보 N(P0-01) + 그 계보에 영향을 준 적응 결정의 대안 수(안건 D-A' 권고안) | 적응 결정은 계보의 '선택 이력' 이다(단조 증가 = 더 엄격해지기만 한다) |
| WF 합성(확약 층) | sweep | N_policy_family = 가족에서 리플레이 평가까지 간 정책 수(π_R 제외 · 기각·shadow 포함 · 버전마다 누적) | 선택 경로는 PIT 라 칸 수준 선택 시행이 없다. 남는 선택 = 정책 선택 |
| 적응 제안(기각·shadow 포함) | — | `rf_trial_log` 행 | 제안 자체는 채점 대상 전략이 아니다. 정책 N 에 들어간다 |

- **후보 생성의 사후지식**(연구 시각 오염)은 N 으로 못 센다. 논문 트리아지·격자 arm 설계가 2005~26 을 알고 만들어졌기 때문이다. 서류에 두 가지를 싣는다.
  - 허용 후보 행렬의 CSCV-PBO(Bailey, Borwein, López de Prado & Zhu 2017)
  - `publication_asof` 민감도
  - D-B 에 따라 **보고만** 한다.
- **DSR 이 더 엄격해지는 효과**
  - 귀무 최대 SR 기대의 주항 Φ⁻¹(1−1/N)은 N=4 → 0.67σ · N=45 → 2.01σ · N=1,250 → 3.16σ 다(Bailey & López de Prado 2014).
  - 다만 플랜 D-A 기록대로 일간 표본의 최고 칸은 N=1,083 에서도 DSR 0.86 이다. 따라서 **DSR 은 구속하지 않을 가능성이 크고**, 판별력은 PBO 와 retention 감쇠귀무(D-B)에서 나온다.
  - 적응 결정이 늘수록 그 둘이 엄격해지는 방향은 정직하다.
- **예산과 A 서류(P1-03/04)의 분리 — 네 겹의 벽**
  1. **자료**: 컨트롤러는 as-of 통계와 연구 시각 전방 결과만 소비한다. 서류는 전기간 essence 와 trial log 를 소비한다.
  2. **권한**: 컨트롤러는 서류·관문·등급을 쓰지 못한다(§5).
  3. **목적**: J 는 DSR·PBO·retention 을 포함하지 않는다. 서류 통과를 목적으로 최적화하는 경로(Goodhart)를 차단한다.
  4. **회계**: N 을 서류가 trial log 에서 독립 재도출하고 컨트롤러 계수와 대조한다(K1).

---

## 5. 헌법 경계 봉쇄

**원칙 — 기계는 헌법 파일과 사람이 큐레이션한 파일을 쓰지 않는다. 자기 파일만 쓴다.**

- **쓰기 허용 목록**(`rf_organic_write(target, pointer, value, decision_id)` 단일 writer)
  - `06_Registry/organic_state.json`(정책 · 블록 n_b · arm_status · 쿼터 · 레인 가중 · killed)
  - `06_Registry/organic_actions.jsonl`(append)
  - `06_Registry/prereg/adapt/**`
  - `rf_trial_log.jsonl`(append · 기존 writer 경유)
  - `rf_decisions.jsonl`(`rf_record_decision` 경유)
  - `stage_artifacts/wf_composite/**`
  - `decision_register.json`(`dr_open/dr_resolve` 경유 · owner=`machine:organic` 만)
- **보호 목록**(적응 tick 앞뒤로 md5 대조 → 변화 = K2)
  - `02_Infrastructure/worktask/constraint_defaults.json`(tier_graduation · execution · diagnostics 포함 전체)
  - `06_Registry/reinforce_program.json`(fixed_axes 가 blocks 와 한 파일이라 **파일 전체** 보호 — 구조 변경은 organic_state 로만)
  - `06_Registry/a_eligibility_gate.json` · `06_Registry/pit_quarantine.json`
  - `06_Registry/book/**` · `05_Production/**`
  - 카탈로그 3종(`overlay_catalog.json` · `weight_catalog.json` · `.cache/factor_db/factor_registry.json`)
  - `06_Registry/reinforce_auto_config.json`(사람 소유 · 기계 읽기 전용)
  - `02_Infrastructure/contracts/**` · `.claude/**`
- **값 스키마**(writer 가 검증하고, 소비자가 다시 검증한다 — 이중 방어)
  - n_b ∈ [n_min,b(config), n_grid,b(program)] 정수 — **격자 확대 불가**
  - arm_status ∈ {organic_paused} — 카탈로그 active 인 arm 만 대상이다. retired·suspended(C11 pg2 포함)는 건드리지 못한다.
  - 쿼터 ∈ [0, q_cap(config)]
  - 선택 정책 ∈ 사전등록 가족
  - 승격 여백 ∈ [config 하한, 상한]
  - N 정의 · DSR · 보류 코드 · 문턱 · 고정 축 · PIT 격리에 해당하는 키는 스키마에 **없다**. 존재하지 않는 키는 쓸 수 없다.
- **정적 파싱**(M1 '미경유 0' 검사 선례)
  - 적응 층 파일(`rf_organic*.R` · `rf_aac.R` · `rf_wf_composite.R`)에서 `writeLines` · `write(` · `cat(file=` · `saveRDS` · `fwrite` · `write_json` · `file.copy` · `unlink` 호출은 `rf_organic_write` 와 `wf_composite` 산출 writer 안에서만 허용한다.
- **사후 재도출 불변**: `rf_preflight_verify_axes`(기존)는 모든 칸과 모든 합성 보유에서 고정 축을 다시 도출한다. 기계가 어떤 경로로든 축을 어기면 칸 단위에서 드러난다.
- **양방향 검사 행렬**(`08_Tests/reinforcement/test_rf_organic_boundary.R`)
  - 양성 대조: 허용 키 쓰기 성공 + actions 1행.
  - 위반 주입 7종: fixed_axes 포인터 · tier_graduation · a_eligibility_gate · 카탈로그 status · n_b > n_grid · retired arm 부활 · 보호 파일 직접 쓰기 → 전부 stop + K2.
  - 돌연변이 3종: 허용 목록 검사 제거 · md5 대조 제거 · 스키마 검사 제거 → 각 위반 주입이 통과하게 되어 검사 red.
  - 격리: `R_ENVIRON_USER` 빈 파일 + 루트 리터럴 + 전후 스냅샷. `08_Tests` 글롭 금지(09-24~25 운영 오염 3건 교훈).
- **새 훅은 등록하지 않는다.** 적응 층은 R(비-LLM)이라 Claude 훅의 시야 밖이다. 봉쇄는 R writer + 검사 + 사후 재도출로 한다.
- **LLM 은 적응 층 결정자가 아니다.** 사전학습 기억은 C1~C15 밖이다(문헌 스윕 09-24: Memorization Problem 2504.14765). LLM 레인은 제안자로 남고, 그 쿼터만 적응 층이 줄인다.

---

## 6. 레버 감사 우선순위 · 플랜 항목과의 관계

| 레버 감사 # | 관계 | 내용 |
|---|---|---|
| 1 `tilt_attribution` | **선행조건(보고)** | 합성·정적 A 후보 보고에 IS 활성 IR + [시장 · EW−CW · 틸트 · 선별] 분해 병기. 흡수하지 않는다. as-of 판(≤τ)을 정책 특징으로 쓰는 것은 사전등록 정책에서만 허용(타이밍 주장이라 플라시보 필수) |
| 2 예산 회수 | **흡수** | D-G = policy 0(사람 결정 → 즉시 live) · B3 축소 · B3 참조 B4 LOO 제거 · 해로운 arm 휴면(B2 CDaR_LP·SchurDamping·minvar · B1 7개 이상 적층) = shadow → 게이트. 축소 조건에 **시간 안정성**을 추가한 것이 이 설계의 몫이다 |
| 3 통제칸 | **선행조건** | σ 원천(EB 수축 · MCS · 휴면 판정). P1-06 은 사람 설계 상주 칸이고, 적응 층은 그것을 소비만 한다. B1_0 은 합성 구간 0 이기도 하다 |
| 4 PR-L2 · 5 PR-L1 | **독립 · 우선 레인** | 사전등록 실험 레인은 적응 예산보다 먼저 배정한다. 판정 뒤 새 칸은 확약 층 후보 풀에 들어간다 — cap_core 가 확인되면 합성이 2017~20 에 그것을 as-of 로 고르는지가 첫 합성 검정이다(사전등록 필수) |
| 6 D-F soft | **흡수** | 예산 층 배정 ∝ P̂(ΔJ>0) · 승격 soft · 잡음 파생 여백 |
| 7 선택 가치 함수 | **흡수(재정의)** | 선택 층 π 가족 · `rf_select_value`. A 레버가 아니라 정직성·학습 계기로 다룬다 |
| 8 설계 레인 학습 고리 | **부분 흡수** | 연구 시각 전방 채점 인프라(expect 구조화 · Brier)를 공유한다. 교훈 저장소(P3-02)는 별개 |
| 9 크래시 위험 선별 | 범위 밖 | 후순위 유지 |

| 플랜 항목 | 관계 |
|---|---|
| **P0-14** | **선행 필수(O0-1)** — 러너 재개 전에 둔다. AAC 는 P0-14 의 일반화다(H1 계보 승계 + H2 노드 일치) |
| P1-01 d_A | 보고·계기(meter)에만 쓴다. 컨트롤러 목적은 J(상한 · OOS 제외) |
| P1-02 trial log | 선행(G1) |
| P1-03 selection_accounting | `sa_subwindow` ⊂ `wf_asof_stats`(임의 τ). N_eff·PBO 는 서류용이고 컨트롤러 입력은 금지 |
| P1-04 서류 | 항목 2 추가: AAC 경로 감사 곡선 · 동반 WF 합성(정적 A 후보가 나오면 같은 계보의 π_2 합성을 병기) |
| P1-05 | 흡수(개입 5자리 · 결정 기록 배선) |
| P1-06 | 선행 |
| **P1-07** | **대체** — 연구 시각 IS-only 바닥 리플레이 대신 시장 시각 WF 리플레이(O1·O3). live 는 도훈 confirm 대신 G4 판정식(결정 AUTONOMY) |
| P1-08 | 흡수(FIFO 기본 · 레인 가중) |
| P1-09 | 독립 |
| P2-01 `rf_prereg.R` | 선행(G3 writer 재사용) |
| P2-03 floor v2 | 정합: F1 을 as-of 재선정 새 칸으로 재정의(09-25 절)하는 것은 확약 층 원칙과 같다 |
| P3-01 레버 장부 | 통합: `wf_lever_stability` = 장부의 as-of 절단·시간 안정성 뷰. PE-5 수용 게이트 공유 |
| P3-03 예측 채점 | 인프라 공유 |
| P3-02·04·06 | 독립. 적응 층 상태는 기억층이 아니다(AX-D2 '4번째 기억층 금지' 준수 — `organic_state` = 제어 상태 · `organic_actions` = 행동 로그) |

**폐기하는 플랜 조항**
1. P1-07 'live 는 도훈 confirm 후' — 적응 층에 한해 대체(결정 AUTONOMY). E2 설계(연구 시각 IS-only 바닥 리플레이)는 시장 시각 WF 로 대체한다.
2. P3 보류 목록 중 'policy_state 자동 live(도훈 재승인 후)' — 적응 층에 한해 G4 판정식 통과 시 자동으로 한다. π_lever(Thompson) 보류는 유지한다(이 설계 범위 밖).
3. D-G 의 레인 **고정** 순서 'prereg > 신규 논문 > 승격 > 반사실' — policy 0(초기 live 값)으로 흡수하고 고정 조항은 폐기한다(적응 대상). 단 '승격 세대당 신규 논문 ≥1' 은 가드(K5 하한)로 존치한다.
4. P1-06 '승격 판정에 짝지은 증거 기록 (live 규칙 교체는 안건)' — 교체 경로가 G4 판정식이 되므로 '안건' 문구를 폐기한다.
5. `graduation.improvement_check`(죽은 선언) — J 로 대체하고 삭제를 권고한다. 파일이 사람 소유이므로 세션이 편집한다.
6. `04_Research/meta/axiom_replay` 리플레이 엔진을 적응 층 게이트로 쓰는 경로 — 쓰지 않는다(연구 시각 접두 · 전기간 점수 뷰 — §0.5-1). 연구 산출물로 보존한다.

---

## 7. 메타 목표 — 유기체가 나아지고 있는가

**원칙 — 컨트롤러가 최적화하는 값과 계기(meter)가 재는 값을 분리하고, 목표 축에 상한을 건다**(카드 '상한은 목표 축에').

| 계기 | 정의 | 컨트롤러가 조작할 수 없는 이유 |
|---|---|---|
| M1 연구 과정 OOS | 1차 합성 π_2 의 τ 이후 활성 IR · Calmar(수준, 비율 아님) · 권위 등급 · d_A(judge basis) · **축별 min(1, m/θ) 상한** | 모든 구간 보유가 ≤τ_k 결정이고, 평가는 >τ_k 데이터다 |
| M2 선택 인플레 | π_0 합성 대 원장 최고 칸의 차(현행 규칙이 PIT 였다면 잃었을 몫) | 원장 사실 + 합성 계약 산출 |
| M3 전방 보정 | R 결정 예측의 Brier skill(기후값 대비) | 결과는 결정 뒤에 측정된 칸 |
| M4 청정 전선 | AAC·H1clean·표식 청정 칸 중 최소 d_A 의 주간 추이 | 청정 필터는 기계 밖 표식이다 |
| M5 효율 | 신규 기저당 칸 수 · 죽은 블록에 쓴 칸 비중 · 결정 변경 수 | 원장 재도출 |
| M6 진짜 전방 | 합성 동결 뒤 누적 일수와 그 구간 활성 수익 | 누구도 본 적 없는 데이터 |

- **"나아졌다"의 선언 조건**: M1 이 π_R 대비 우월(90% 하한 > 0) ∧ M3 skill > 0(하한) ∧ M4 가 악화되지 않음. 셋 중 하나라도 없으면 '미결'이다.
- **상한의 뜻**: 어떤 축이 θ 에 도달하면 그 축의 추가 개선은 진전으로 세지 않는다. 진전 = 구속 축(현재 OOS·Calmar)의 이동뿐이다.
- 레버 감사가 경고한 **'PT 가 올라가서 좋아 보이는' 착시**는 이 정의상 진전이 아니다.

### 실패 모드와 대응

| # | 실패 모드 | 대응 |
|---|---|---|
| 1 | 후보 생성의 사후지식(연구 시각 오염) — WF 는 선택 경로만 고친다 | N_policy · CSCV-PBO · `generation_unblinded` 라벨 · `publication_asof` 민감도 · M2 블라인드 |
| 2 | 리플레이 자체의 누출(피처가 전기간 essence 를 읽음) | 단일 접근자 · 섭동 불변 검사 · 정적 파싱 · live=리플레이 항등 |
| 3 | 표본 부족(τ 이후가 짧음 · 개별 결정 판정 불가) | 정책 수준 풀링(τ_1 이후 약 18년 경로) · 검정력 3종 기재 · ratio<0.15 착수 금지 · '미결' 라벨 · 최신 결정은 진짜 전방(M6)으로만 |
| 4 | OOS 비율 Goodhart(IS 희석으로 retention 상승) | J 에서 retention 제외 · 수준 지표 · IS 활성 IR 병기 의무 |
| 5 | 정책 진동(live↔강등 반복) | MCS 이력현상 · 최소 체류 4주 · 주간 활성 ≤1 · tombstone(policy_state 기존) |
| 6 | 신규 논문 기아(승격 사슬이 예산 독식) | K5 하한 · 깊이 하드 6 불변 |
| 7 | 거짓 퇴출(한 국면에서만 나쁜 arm 영구 사장) | 휴면(금지 아님) · 시간 안정성 조건 · 부활 탐침 쿼터 · 주간 상한 |
| 8 | N 팽창으로 A 원천 봉쇄(과엄격) | N_eff 병기 · N 정의 = 도훈(D-A') · 합성은 선택 경로가 PIT 라 N_policy 만 |
| 9 | 조용한 낡음(rebase·current_axis 변화 뒤 캐시) | 상태 키 불일치 = fail-closed(K7) |
| 10 | 경계 우회(간접 경로로 헌법 파일 변경) | 허용 목록 · 보호 md5 · 정적 파싱 · 소비자 재검증 · 사후 축 재도출 |
| 11 | 킬스위치 불발(죽은 계기) | 조건별 합성 열화 주입 양성 대조 · 주간 자가 검사 |
| 12 | 러너와 경합(tick 중 쓰기) | 러너 claim 아래 idle 에서만 · 원자 쓰기 · 리프레시 배리어 준수 |
| 13 | AAC 과엄격 → 합성이 기저로 붕괴 | '미결' 라벨(벽 적립 금지 · AX-000) · AAC 통과율 곡선 보고 · 복원 양성 대조 |
| 14 | 무작위 정책과 구분 불가 | π_R 대조 필수 · 구분 불가면 live 금지 · 그 사실을 M1 에 그대로 보고 |
| 15 | 디렉터 전철(권고만 쌓이고 결정은 안 바뀜) | 러너 결정 변경 수를 주간 보고 1면에 · 소비 경로 = 러너 훅(권고 파일 아님) |

---

## 8. 구현 단계 (O0~O4)

**공통 검사 규율**
- 모든 신규 계기·writer 에 양성 대조 · 위반 주입 · 돌연변이 · 원장 재도출을 적용한다.
- 등급 불변 회귀: `test_grade_unification.R` B4~B6 + 픽스처가 비트 동일이어야 한다.
- 검사 격리: `R_ENVIRON_USER` 빈 파일 · 루트 리터럴 · 전후 스냅샷 · `08_Tests` 글롭 금지.

### O0 — 선행·골격 (결정 영향 0)
- **산출**
  1. P0-14 — 관문 시점 계보 기반 선정 기저 표식 승계. derive 의 '승계 집합 ⊆ factors' 재사용.
  2. `wf_asof_stats.R`
  3. `rf_trial_log`(P1-02 · organic kind 등재) + `RF_DECISION_KINDS` 추가(organic_policy · arm_status · structure · organic_kill)
  4. `rf_organic_write` + `organic_state.json` 스키마 + 보호 md5 감사 + 정적 파싱 검사
  5. config `organic.*`(enabled=false) · 킬 배선 · `dr_*` owner=machine 경로
  6. P1-06 통제칸 정의(사람 편집)
- **검사**
  - P0-14: 22632 팩터 집합을 승계한 합성 새 칸 → A 보류(`vintage_flag`) · 승계 제거 돌연변이 red.
  - `wf_asof_stats`: τ=끝이면 essence 와 identical(골든 20260921_100007_6876 close_t1 판 3.777/0.433) · τ 이후 섭동 불변 · τ+1 을 읽는 가짜 통계는 섭동 검사가 red(검사의 양성 대조).
  - 경계 행렬(§5).
- **완료 판정**: 전 검사 green · 러너 리플레이 픽스처가 비트 동일(적응 층 off).
- **규모**: 약 2세션.

### O1 — 관측 전용 (shadow 계기)
- **산출**
  1. `rf_asof_view` · `rf_aac.R`(노드 복원 + AAC 표) · `wf_lever_stability`(S_b · ρ^WF)
  2. `rf_wf_composite.R` — 사전등록 `organic_policies_v1.json`(π_0/π_1/π_2/π_R · τ 격자 · 구간 0 칸 · 1차/2차 지표 · 검정력 · 멈춤)
  3. R 결정 예측 기록(집행 없음)
  4. 주간 보고 드라이런
- **검사**
  - AAC 복원 양성 대조 ≥99%.
  - 합성 구간 0 이 기저 칸 수익과 비트 일치.
  - 합성 보유 고정 축 재도출 100%.
  - 교체일 비용 계상 대조(Δw × 15bps).
  - π_R 분포 중심성 · τ 라벨 순열 플라시보.
  - 합성 경로의 PIT 섭동: τ_k 이후 후보 수익을 교란해도 c_k 불변.
- **완료 판정**: 첫 '연구 과정 OOS' 성적표(M1·M2) · AAC 통과율 곡선 · 레버 안정성 표 · ORGANIC-DE-SCOPE 상정 자료 완비.
- **규모**: 약 2세션 + 계산 약 1시간(칸 1,238 × τ 약 37 · 합성 4 × 약 1분).

### O2 — R 형 live (예산·공간)
- **산출**
  1. D-G B5 규칙 live(사람 결정)
  2. 예산 정책(칸 절단 · 회수 → 신규 논문) · arm 휴면/부활 · 레인 FIFO·가중 — shadow ≥4주 → G4 → live
  3. K1~K8 live · 롤백 실전 경로
- **검사**
  - 게이트 양성 대조(개선을 심은 합성 정책 통과) · 음성(π_R 탈락).
  - 킬 주입(조건마다 설정 시간 안에 발화).
  - 롤백 비트 복원.
  - `:547` 정지 경로 주입(절단 뒤 used < length(cells) ∧ 빈 칸 0 이 생기지 않음).
  - 보호 md5 7일 연속 green.
- **완료 판정**: 킬 없이 live 2주 · 주간 보고 2회 발송 · 회수 칸의 신규 논문 투입을 원장에서 재도출(주장 아님).
- **규모**: 약 2세션 + 벽시계 2~4주.

### O3 — 선택 층 + 확약 객체
- **산출**
  1. `rf_select_value` 5자리 교체(pi0 비트 동일) · shadow π_1/π_2 결정 기록
  2. 확약 1차 합성(π_2)을 후보 객체로 등록 → `rf_a_eligibility` 적용(합성용 attempt 모양) → A 면 `judge_request_WF_<id>.json`(judge.md 스폰 조건 ① 과 같은 스키마 — ORGANIC-COMPOSITE-OBJECT 결정 뒤에만)
  3. P1-04 서류 항목 2종
- **검사**
  - program 사본의 `select_winner_by` 를 바꾸면 결과가 변함(죽은 선언 해소).
  - pi0 가 과거 결정과 비트 동일.
  - 합성 A 합성 주입 → 보류/발행 정확.
  - 합성 frozen 스펙 재현(동결 목록으로 재구성 = 동일 NAV).
- **규모**: 2~3세션.

### O4 — 구조 층 + 확장
- **산출**
  1. 구조 정책(블록 n_b · 승격 여백 · 레인 가중) live — G4
  2. (선택 · 사전등록) **블라인드 설계 WF 실험**: 설계 레인 재료를 τ_gen = τ_IS 까지로 절단하고, 설계된 arm 을 τ_gen 이후로만 판정한다. LLM 사전학습 기억은 막을 수 없으므로 라벨 '연구 OOS(기억 미차단)'.
  3. B6 칸 합성 후보 편입(v2)
  4. 8주 메타 재검토 — §2 일몰 재상정
- **규모**: 약 2세션.

### 신규 config 키 (`reinforce_auto_config.json::organic.*` — 사람 소유 · 기계 읽기 전용)
- `organic.enabled` · `organic.auto_live` · `organic.layers.{budget,space,select,structure,commit}.enabled` · `organic.state_path`
- `organic.wf.{min_is_months, step_months, publication_asof, candidate_cadence, segment0_cell_rule, policies_prereg}`
- `organic.select.{mcs_alpha, shrink}`
- `organic.budget.{n_min, p_ref, s_min, windows_m, p_stop, delta_stop, s_floor}`
- `organic.space.{p_pause, n_min, s_min, revive_every_entries, max_pause_per_week, yield_window_weeks, q_cap_source}`
- `organic.structure.{p_off, consecutive_weeks, promote_margin_z}`
- `organic.gate.{replay_ci, bootstrap_B, block_rule, power_min_ratio, shadow_min_weeks, informative_min, placebo_perms, random_seeds}`
- `organic.kill.{eprocess_alpha, max_live_changes_per_week, runner_health_drop, stale_consecutive}`
- `organic.report.{weekday, dry_run}`
- `b5_budget.*`(D-G)
- `06_Registry/a_eligibility_gate.json::holds.selection_path_full_sample`(기본 off · 도훈 소유)
- 읽기만 하는 기존 키: `constraint_defaults.diagnostics.oos_calendar_splits`(τ_IS) · `tier_graduation.*`(θ)

### 신규 파일
- `02_Infrastructure/contracts/wf_asof_stats.R`
- `02_Infrastructure/reinforcement/rf_organic.R`(층별 순수 결정 함수 · `rf_organic_cells` · `rf_select_value` · 어댑터)
- `02_Infrastructure/reinforcement/rf_organic_write.R`(단일 writer · 스키마 · md5 감사 · 롤백)
- `02_Infrastructure/reinforcement/rf_aac.R` · `rf_wf_composite.R` · `rf_wf_lever_stability.R`
- `02_Infrastructure/ops/rf_organic_tick.sh`(레인 · 자기 claim · idle 전용) · `rf_organic_weekly.R`
- `06_Registry/organic_state.json` · `organic_actions.jsonl` · `prereg/adapt/organic_policies_v1.json`
- 검사: `08_Tests/reinforcement/test_wf_asof_stats.R` · `test_rf_aac.R` · `test_rf_wf_composite.R` · `test_rf_organic_boundary.R` · `test_rf_organic_gate.R` · `test_rf_organic_kill.R` · `test_rf_organic_rollback.R` · `test_p0_14_lineage_flag.R` · `test_rf_organic_live_replay_identity.R`(모두 `run_all_hooks.sh` SUITES 편입)

### 수정 파일 (국소)
- `ops/reinforce_auto_parallel.R`
  - `:436` 뒤 1줄(`rf_organic_cells`)
  - `:683` · `:766` · `:774`(`rf_select_value`)
  - 결정 기록 2~3줄
- `reinforcement/rf_runner_gates.R` — P0-14(`rf_a_eligibility` ⑤ 계보 승계) · `selection_path_full_sample` 코드(`RF_A_HOLD_CODES`)
- `reinforcement/rf_promote.R:59` · `rf_lesson.R:115`
- `reinforcement/reinforce_ledger.R` — `RF_DECISION_KINDS` 추가
- `ops/reinforce_auto_next_paper.R:61-65`(FIFO) · 승격 cfg 병합
- `ops/rf_weight_arms.R:40` · `ops/rf_overlay_arms.R:47` · `ops/rf_factor_arms.R:271-282` · `reinforcement/rf_block_design.R:90-111` — 휴면 필터 1줄씩
- `ops/reinforce_auto_tick.sh` — 러너 앞 레인 1줄
- `axiom/replay/policy_state.R` — 무변경(어댑터가 stats 를 공급)
- `06_Registry/a_eligibility_gate.json` — 코드 추가(사람 편집)

---

## 9. 하지 말 것

1. 컨트롤러 입력에 OOS retention · 분할 성분 · DSR · PBO · 서류 통계를 넣지 않는다. OOS 는 정책의 τ 이후 성적으로만 들어온다.
2. 적응 층이 성과 선정으로 **정적** A 후보를 만들지 않는다. 적응 층의 확약은 WF 합성으로만 한다.
3. 리플레이 결과를 본 뒤 τ 격자 · step · min_is · 정책 가족 · 구간 0 칸을 바꾸지 않는다. 바꾸려면 새 사전등록 = 새 가족 N 이다.
4. WF 합성의 성적을 정적 칸의 증거로 인용하지 않는다(다른 객체다). 합성 수치를 원장 칸 essence 와 한 argmax 에 섞지 않는다.
5. τ_IS 를 '봉인'·lockbox 로 부르거나 그렇게 쓰지 않는다. 데이터는 봉인되지 않는다.
6. 격자 칸 확대 · daily_cap 증액 · B5 칸 증설을 적응 결정으로 하지 않는다(플랜 '하지 말 것' 1). 기계는 줄이기와 복원만 한다.
7. 헌법 파일 · 카탈로그 · 격자 · 관문 설정 · PIT 격리 · BOOK · 프로덕션을 기계가 쓰지 않는다. 자기 파일만 쓴다.
8. 휴면 arm 을 금지 목록으로 집행하지 않는다(부활 탐침 필수 · AX-000).
9. 위상쌍을 σ 원천으로 쓰지 않는다. 짝지은 부트스트랩 하한을 칸 단위 하드 규칙으로 쓰지 않는다(플랜 '하지 말 것' 5).
10. 새 훅을 등록하지 않는다. 결정 수치를 python·손계산으로 내지 않는다(AX-008 — `wf_asof_stats`·합성 계약만).
11. π_R 과 구분되지 않는 정책을 live 에 올리지 않는다. 그 사실을 '벽'이나 '한계'로 적립하지 않는다(미결 · AX-000).
12. 컨트롤러가 최적화한 값으로 '유기체가 나아졌다'를 선언하지 않는다. 계기(M1~M6)로만 선언한다.
13. P0-14 와 O0 검사 전에 O2(live)를 시작하지 않는다. 러너 재개를 적응 층 준비에 묶지 않는다(적응 층 off 로 러너는 따로 돈다).
14. 무신호 대조(cap-w top-N) 칸을 사전등록 없이 합성 후보에 넣지 않는다. 그 칸으로 교체하는 것은 타이밍 주장이라 플라시보가 필요하다.
15. 설계 레인(LLM)에 적응 층 상태 · 합성 성적을 재료로 주지 않는다(M2 봉쇄 범위와 같은 이유).

---

### 부록 — 문헌 (원문 링크)
- Bailey & López de Prado (2014) The Deflated Sharpe Ratio — https://papers.ssrn.com/sol3/papers.cfm?abstract_id=2460551
- Bailey, Borwein, López de Prado & Zhu (2017) The Probability of Backtest Overfitting (CSCV-PBO) — https://papers.ssrn.com/sol3/papers.cfm?abstract_id=2326253
- Bailey, Borwein, López de Prado & Zhu (2014) Pseudo-Mathematics and Financial Charlatanism (MinBTL) — https://www.ams.org/notices/201405/rnoti-p458.pdf
- Dwork, Feldman, Hardt, Pitassi, Reingold & Roth (2015) Generalization in Adaptive Data Analysis and Holdout Reuse — https://arxiv.org/abs/1506.02629
- Hansen, Lunde & Nason (2011) The Model Confidence Set — https://doi.org/10.3982/ECTA5771
- Efron (2011) Tweedie's Formula and Selection Bias — https://doi.org/10.1198/jasa.2011.tm11181
- Politis & White (2004) Automatic Block-Length Selection — https://doi.org/10.1081/ETC-120028836
- Gneiting & Raftery (2007) Strictly Proper Scoring Rules — https://doi.org/10.1198/016214506000001437
- Ramdas, Grünwald, Vovk & Shafer (2023) Game-theoretic statistics and safe anytime-valid inference — https://arxiv.org/abs/2210.01948
- Howard, Ramdas, McAuliffe & Sekhon (2021) Time-uniform confidence sequences — https://arxiv.org/abs/1810.08240
- Tashman (2000) Out-of-sample tests of forecasting accuracy (rolling origin) — https://doi.org/10.1016/S0169-2070(00)00065-0
- McLean & Pontiff (2016) Does Academic Research Destroy Stock Return Predictability? — https://doi.org/10.1111/jofi.12365
- 2026 문헌(09-24 스윕 카드에서 원문 대조한 목록): AEAP 2609.00731 · Gençay 2608.27734 · Li SSRN 7190318 · Memorization Problem 2504.14765 · Chen-Welch 2607.06502 — https://arxiv.org/abs/2609.00731 · https://arxiv.org/abs/2608.27734 · https://papers.ssrn.com/sol3/papers.cfm?abstract_id=7190318 · https://arxiv.org/abs/2504.14765 · https://arxiv.org/abs/2607.06502
