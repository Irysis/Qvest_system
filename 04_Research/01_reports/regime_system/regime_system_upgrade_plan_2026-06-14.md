# 국면 시스템 업그레이드 플랜 (통합 로드맵)

> 작성: 2026-06-14 · 의뢰: 도훈 ("분석 채택, 업그레이드 플랜 만들어봐") · 모드: factor-rotation 메타
> 근거: ① 국면 엔진 전수 감사(2026-06-14, 7-agent, 도훈 confirm) ② 6-트랙 설계+adversarial 검증(12-agent, 316 tool-use, 1.48M tok)
> 도훈 결정: **통합 로드맵(순서매김: 입력→구조→엔진)** + **forecaster INV-7 재도전**
> 산출 워크플로우: `wf_efad72fc-ccc`(감사) · `wf_62300fda-a84`(설계검증)

---

## 0. 한 줄 평결 (검증이 확증한 것)

**6개 트랙 전부 `NEEDS_REVISION`이고, 천장(모듈풀 return_cor 0.70, covariance 1st eigenmode 지배)을 *올리는* 트랙은 0개다.** 트랙별 천장기여 자기평가 → adversarial 재평가:

| Track | 설계 자기평가 | 검증 재평가 | 의미 |
|---|---|---|---|
| A 입력 직교화 | enables_ceiling_raise | **gates_downstream / prevents_misallocation** | 천장 안 올림 — 측정·분기 |
| B Shu-Mulvey 구조 | enables_ceiling_raise | enables (Track A에 HARD 의존) | A 없으면 cost-only |
| C SJM 배선 | marginal_only | marginal_only (정직) | 신호품질·forecaster 입력만 |
| D feature 검증 | enables_ceiling_raise | enables, **대부분 REDUNDANT 예상** | 위생·진단 |
| E forecaster INV-7 | marginal_only | marginal_only (정직) | 메타지식 적립 |
| F 거버넌스 | hygiene_only | hygiene_only (정직) | 오졸업 차단 |

→ **결론: 업그레이드 플랜의 본질은 "국면 엔진 고도화"가 아니라 "천장이 입력에 있음을 측정으로 확정하고(분기), 천장과 무관한 위생·메타지식을 값싸게 적립하며, 직교 입력이 확보될 때만 구조(Shu-Mulvey)를 짓는" 순서매김 게이트 로드맵이다.** SR 천장 레버는 헌법 명문 그대로 **overlay(주역) + DPL + uncertainty** — 국면 엔진 작업이 아니다(measurement-graduation §6, §38).

---

## 1. 전제 정정 3건 (검증이 발견 — 도훈 결정 근거에 영향)

플랜 착수 전에 코드로 바로잡아야 할 사실오류:

### 1.1 ★ forecaster "persistence 92% 미돌파"는 틀렸다 — v1은 이미 돌파했다
- "92%"는 *realized* 값이 아니라 코드 내 prior 상수(`regime_forecaster.R:70` `base_p=0.92`). **realized persistence hit는 0.69~0.78**.
- v1(전이행렬+nudge)은 이미 persistence 돌파: forecast_hit 0.741 vs baseline 0.693, Brier 0.3994 vs 0.5604, `beats_baseline=TRUE`, n=378 (`regime_forecast.json:6-10`).
- **진짜 천장은 persistence가 아니라 v1**. v2(multinom) 0.770<v1 0.803 · v1tune(+US-VIX) 0.803=0.803 · v3(KR ECOS) 0.835<0.841 · v4a(SJM nudge) 0.841=0.841 · v4o(SJM override) **0.670 파국**(n_override=47). **모든 enrichment가 v1을 못 넘음**.
- → forecaster 동결 사유였던 "persistence 못 넘음"은 사실 오류. 올바른 질문은 "**무엇도 v1 전이행렬을 못 넘는다 — 이게 KR 월간 국면예측의 정보상한인가**"이고, 이는 conditional entropy H(next|cur)로 정량화해야 한다(Track E step1).

### 1.2 ★ Track F의 hook은 발화하지 않는다 — 게이트는 R 계약 내부로
- 제안된 graduation/selection_type 게이트는 `PreToolUse[Write|Edit]` hook 의존인데, **FR 산출은 Rscript subprocess의 R `write_json`으로 파일을 쓴다**(`run_wf_ensemble_fr002.R:262`). PreToolUse[Write]는 Claude의 Write *도구*만 가로채지 subprocess write는 못 잡는다.
- 실증: `dispatch_measurement_gate.log`/`factor_rotation_pit_guard.log`에 06-10 dry-run 경로오류 항목만 있고 **실 FR런(레지스트리 mtime 06-13)에 단 한 번도 발화 기록 없음**.
- → 게이트를 **`register_fr_result`/`essence_score` R 계약 내부로 이동**해야 강제된다. hook 그대로 두면 "발화 안 하는 게이트 = 순수 비용 + 거짓 안전감"(게이트 부재보다 위험).

### 1.3 ★ Track A "직교 슬리브 ≥4건"은 구조적으로 불가 — 측정으로 재정의
- 헌법 §6: KR long-only 수익률직교 구조적 불가. 16/16 standalone FAIL. value sleeve(유일 cor<0.30)는 clean-Z 재측정에서 **alpha-dead falsified**(SR 0.375·OOS_retention 0.064·2017+ PORT_t −0.14, `next_session_task.md:22`).
- 실질 신규 후보는 **TE-sink + sector-spillover 2건뿐**(Hawkes port-α −2.09·CGO rank-IC~0 기각, disclosure-meta는 2016~ floor로 부적격).
- → 목표를 "**≥4건 달성**"이 아니라 "**직교 dispatch가 의미를 갖는 데 필요한 직교 입력 수 N을 정수로 측정 + 세 경로(직교α/DPL/overlay) ΔSR 주역 판정**"으로 재정의.

---

## 2. 통합 로드맵 (4 Phase · 순서매김 · 결정 게이트)

도훈 mandate "입력→구조→엔진"을 따르되, **천장과 무관하게 값싼 위생·메타지식(Phase 0)을 먼저** 적립한다(입력 게이트가 시간 걸리는 동안 공짜 진실 확보).

```
Phase 0 ─ 즉시·천장무관 위생+메타지식 (병렬, ~1주)
            E1 entropy정정 · C1 SJM ORPHAN · C2 SJM PIT감사 · F1 selection_type · D1 feature PIT감사
                          │
Phase 1 ─ 입력 게이트 (Track A, 결정 분기, ~2주)  ◀── 전체 로드맵의 분기점
            직교후보 2건 3-axis verdict + DPL 1-sweep + 3경로 ΔSR 표 → N, ΔSR 주역
                          │
              ┌───────────┴───────────┐
        N≥3 (희박)                 N<3 (예상)
              │                       │
Phase 2 ─ 구조 (Track B)       overlay+DPL로 천장레버 공식 재배정
   slice_bl Shu-Mulvey 이식       Track B = negative 측정만, §6 공리 적립
   (stage-gate at clustering)              │
              └───────────┬───────────────┘
                          │
Phase 3 ─ 예측 레이어 (Track E INV-7, sweep, ~2-3주)
            switch-target + SJM직교 residual, holdout falsification, L-code 적립
            (step5 A/B 채택은 Phase1 N≥3 후로 보류)
                          │
Phase 4 ─ 엔진·거버넌스·진단 (Track C/D/F 잔여, 병렬·지속)
            gates-in-contracts(F) · SJM dispatch A/B(C) · feature 4분류(D) · ensemble NO-GO(C)
```

### Phase 0 — 즉시 착수 (천장 무관 · 공짜 진실 · effort 합계 ~S+S+S+S+S)

병렬 실행, Track A 무관. 도훈 결정의 전제부터 코드로 확정한다.

| # | 작업 | 파일 | 산출 | effort |
|---|---|---|---|---|
| **E1** | realized-persistence baseline 코드화 + H(next\|cur) 정보상한 산출 | 신규 `02_Infrastructure/regime/regime_forecaster_v5diag.R` | `realized_persistence_hit`(0.69~0.78 확인) + `conditional_entropy_bits` + `theoretical_max_hit=1−H` | S |
| **C1** | SJM `regime_jump_daily.parquet` ORPHAN 해소 | `02_Infrastructure/data/cache_registry.json`(entry append, msm_daily 템플릿 tier2/daily/max_lag3) + `daily_refresh.sh:226-241` 인접에 `refit_jm_daily()` tryCatch fail-open | forecaster_v4 입력 신선도 자동 보강 | S |
| **C2** | SJM refit backfill PIT 불변성 감사 (live 배선 **선행 강제**) | `regime_jm_validation.R` 확장 | cutoff 2개(2020-12/2024-12) JM_State_lag diff==0 PASS | S |
| **F1** | `essence_score` selection_type 명시 배선 (hook 무관 즉시조치) | `run_wf_ensemble_fr002.R:217` → `selection_type='sweep'` | 무라벨 호출 0건, 감사가능 | S |
| **D1** | 6 feature PIT 감사 + 데이터 가용 게이트 | 신규 `feature_audit.R` | derivatives DATA_BLOCKED 격리(`.cache/krx_derivatives/` EMPTY 확인), expanding-only assert | S |

> Phase 0의 핵심 가치: **E1이 도훈 결정 근거(forecaster 92%)를 정정**하고, KR 국면예측 정보상한을 수치로 박제. C1이 forecaster_v4가 stale 신호로 구동되는 무결성 결함 해소. **천장과 무관하지만 전부 영구 메타지식.**

### Phase 1 — 입력 게이트 (Track A · 결정 분기)

전체 로드맵이 여기서 갈린다. "≥4 슬리브"가 아니라 **N 측정 + ΔSR 주역 판정**.

| step | 작업 | 방법 | effort |
|---|---|---|---|
| A1 | 후보 funnel 재정의 (value/composite 폐기 확정, 사전등록) | TE-sink + spillover 2건만 2005~ 가능, disclosure-meta 2016~ 라벨 분리 | S |
| A2 | 잔여 후보 3-axis 직교 verdict 실측 | `canonical_screen_bt`(top20/15bps/liq2e8) → STR_1715 active corr → `valmom_ortho_check.R:90-95`. **+turnover≤11.0 축 추가**(EW_topN이 이미 11.2/yr), **정식 Carhart4 회귀 명시**(하드코딩 1.63 금지) | M |
| A3 | DPL 직교화 1-sweep (현 config 미입증 해소) | `dpl_ortho_eval_contract.R`, FEATURE_SOURCES 교체. **sweep → DSR≥0.5 HARD + IS-only HP 봉인**. 갭수치(2.906 vs 2.84) 먼저 live 확인 | L |
| A4 | 3경로 ΔSR apples-to-apples 표 | `book_optimizer.R` ΔIR. overlay는 cor=1.0 재구성 **"1차 추정" 라벨 강제**(절반만 잡는 proxy) | M |
| A5 | dependency_verdict + negative 공리 | N≥3 → 국면 GO / N<3 → overlay+DPL 재배정 + §6 적립. **rawdata P0 수리 후 재실행 트리거 명시** | S |

**GATE**: `dependency_verdict.json::N` (ORTHOGONAL verdict 통과 슬리브 수, 정수)
- **N≥3** → Phase 2(Track B) GO
- **N<3** (실측상 예상 시나리오) → Phase 2 = negative 측정만, 천장레버 공식 = overlay+DPL, INV-7 forecaster는 "overlay 정확도 개선" 목적으로만 정당화

### Phase 2 — 구조 (Track B · Shu-Mulvey · Phase1 N≥3 조건부)

**stage-gate 우선**: step1 clustering에서 `|cor_active|<0.5` 페어가 G≥3에서 없으면 **step2-8 빌드 금지**, slice_bl unavailable + §6 negative 적립(두 개 L-effort 빌드 전 차단). 현 실측(ep cor_act 0.743, batch434 |cor|<0.5 페어 0개)상 통과 희박.

| step | 작업 | 핵심 |
|---|---|---|
| B1 | 슬리브-그룹 계약 (`sleeve_grouping.R`) | hierarchical clustering(1−\|cor\|), **출처는 `hrp_core.R` (regime_module_admission엔 hclust 없음)**. asof-슬라이스 또는 time-invariant 명시(OOS로 그룹 바뀌면 C1) |
| B2 | per-sleeve SJM (`sleeve_jump_model.R`) | `.jm_fit`/`.jm_dp_path` 재사용. **`build_jm_features`는 benchmark.parquet 하드와이어 → 리팩터 필요(effort M→M+)** + KOSPI parity test |
| B3 | 국면조건부 BL views (`sleeve_bl_views.R`) | `cop_opinion_pooling.R bl_to_cop` 재사용. q[g] = **asof-expanding** IS 평균(full-sample면 C1) |
| B4 | long-only MVO 커널 (`sleeve_mvo.R`) | `book_optimize` quadprog 일반화(Σw=1·[0,cap]) + λ_TE + γ·\|w−prev\| turnover penalty |
| B5 | run_wf_slice_bl 배선 (opt-in `FR_DISPATCH_MODE=slice_bl`) | FR_001 baseline 불변. `Return.portfolio`+`build_bt_result` 경유(자체합성 금지) |
| B6 | turnover≤11.0/yr 게이트 | 출처 정정: **CLAUDE.md Production Constraints + `hurdle_gate.R` D002 1,100%** (factor-rotation.md엔 turnover 문자열 없음) |
| B7 | A/B (slice_bl vs 단일국면 vs EW) | min-across-seed ∧ min-across-G ∧ placebo p<0.05 (SJM_SR_GAIN_NONROBUST 재발 차단) |
| B8 | λ_TE·λ_SJM·γ·cut_distance 사전등록 스윕 | `prereg_slice_bl.json` 봉인 **(step7 default를 grid 보기 전 봉인 — chain위장 차단)**, selection_type='sweep' DSR HARD |

> Shu-Mulvey turnover 522% vs 우리 11.0 한도는 **해결이 아니라 측정-후-차단**: step4 γ + step8 λ_TE로 억제 시도, 한도 초과 시 step6 자동 FAIL + "slice_bl 우리 제약서 비가용" negative.

### Phase 3 — 예측 레이어 (Track E · INV-7 · honest sweep)

도훈 결정 반영. **step5(A/B 채택)는 Phase1 N≥3 후로 보류** — 0.70상관 풀에선 예측 정확도 올려도 입력천장에 막힘.

| step | 작업 | 핵심 |
|---|---|---|
| E1 | (=Phase 0) realized baseline + entropy | 이미 Phase 0에서 최우선 단독 착수 |
| E2 | target 재정의: 라벨예측 → 전환위험 P(switch\|info) 이진회귀 | SJM Bear_Prob_lag 1급 leading feature. base hit≈0.67 trivial 주의 |
| E3 | feature 직교화: SJM 선행신호 직교 residual | **직교화 계수도 walk-forward IS-only 재적합(전체패널 1회면 C1)** — code assert |
| E4 | ★ **sweep 정직 선언** (chain 위장 포기) | target 2종×feature 2종 IS 병렬비교 = 정의상 sweep. **DSR≥0.5 동반**. holdout은 직접채점 아닌 **`holdout_falsification.R` 사전등록 예측구간**(45~95월 SE 큼) |
| E6 | L-code 적립 (돌파/실패 무관) | `emit_fr_lcode(track='regime_research')`. **construction<3이면 candidate-only(AX 미승격)** — 단일 트랙 1건으로 INV-7 burden(≥3) 불충족, axiom_weekly cron+도훈 confirm 위임 |

> 경로 정정: `run_wf_ensemble_fr002.R`는 **`04_Research/factor_rotation/`** (02_Infrastructure/regime/ 아님).

### Phase 4 — 거버넌스·엔진·진단 (Track C/D/F 잔여 · 병렬·지속)

| 트랙 | 작업 | 핵심 (검증 반영) |
|---|---|---|
| **F (거버넌스)** | 게이트를 **R 계약 내부로** | `register_fr_result` 진입부: selection_type 필수 + HARD 3종(자본졸업불가 라벨, screening 등재 허용) + holdout 사전등록 내부호출. ΔIR은 **`pg1_admission_with_book_context` 단일경로**(중복 재구현 금지). book_state write 0건. hook은 보조방어만 |
| **C (SJM 배선)** | step3 dispatch A/B (2순위) | discriminative=FALSE(τ=0.568)라 한계효익≈0 — **forecaster 입력(step5, 1순위) 후 여력 시에만**. SJM은 msm 대체 NO, 병렬 진단축 |
| **C (ensemble)** | regime_ensemble NO-GO 측정-기반 종결 | 하이퍼(0.70/−0.05) 출처 추적 + Category cascade와 신호상관>0.8(중복) 정량화 |
| **D (feature)** | 5 feature 4분류 매트릭스 | **step3 overlay는 canonical_screen_bt가 exposure 못 받음 → `apply_regime_overlay.R` 경유 재설계 필수**. PROJ 하드코딩 `G:/` 제거. 대부분 REDUNDANT 예상 |
| **C (SOT)** | 3엔진 레이어 경계 `regime_engine_map.json` | 9축→overlay / Category→FR dispatch / SJM→forecaster입력+진단축 |

---

## 3. 의존성 그래프 (요약)

```
Phase 0 (E1·C1·C2·F1·D1) ── 독립, 즉시 ────────────────┐
                                                        │
Track A (Phase 1) ─── gating ──┬─→ Track B (Phase 2, N≥3 조건부)
                               ├─→ Track E step5 (Phase 3 보류분)
                               └─→ Track D 가치실현
C2 (SJM PIT) ── 강제선행 ──→ C1·C3 live 배선 / E2-3 (SJM feature)
Track F ── 메타, 트랙무관 (단 essence/holdout/governor 계약 시그니처 의존)
```

**HARD 의존**: Track B·D 가치실현 = Track A(N≥3) 선행. Track E step5 = Track A 선행. C live배선 = C2 PIT감사 선행.
**독립**: Phase 0 전부, Track F 게이트 정의, E1~E4/E6, C1/C2.

---

## 4. 측정·거버넌스 (헌법 정합 — 불변)

- **Graduation HARD (불변)**: PORT_t_nw≥2.95 · oos_retention≥0.7(v2 3분할 중앙값) · calmar≥0.64. forge-authoritative(build_bt_result 경유)에만.
- **DSR 경계**: sweep(A직교grid · A3 DPL · C k-seed race · E forecaster family · B8 λgrid)=HARD / chain(가설주도 순차)=면제. **"의심 시 sweep 보수분류"**. selection_type 분류표는 코드 상수 lookup(자유텍스트 금지).
- **selection_type 분류표** (Track별):
  - A 직교후보 = sweep · A3 DPL = sweep · B 구조 = chain(단 B8 grid=sweep) · C RCMA = sweep(진단) · D feature-selection = sweep(n_trials≥6) · E forecaster family = **sweep(DSR HARD)**
- **C3 holdout**: 사전등록 falsification(`holdout_falsification.R`, 채점 금지·예측구간만). 60월 미만 try-wrap "표본부족" 라벨(졸업차단 아님).
- **admission**: book-marginal ΔIR≥0.05 — **governor admit(book_state write)은 자동화 금지, 도훈 수동 confirm 불변**.
- **PIT**: 국면라벨 online-only(C5 t-1), expanding/rolling, full-sample Viterbi 금지. 신규 파일 전수 `lookahead_detector.R` 스캔.
- **negative = 공리**: FAIL/비로버스트도 `lcode_emit` VALIDATED_HARD_FAIL 적립(INV-7 provisional, kr-inverse-pattern-miner 입력).

---

## 5. 리스크 종합 (검증 발견 — 우선순위)

| # | 리스크 | 완화 |
|---|---|---|
| R1 | **천장 미개선인데 위생만 강화 = 리서치 동결** | 전 트랙 ceiling 정직 라벨(raises 금지). Phase 0/메타지식을 1급 산출로. N<3이면 overlay+DPL 재배정이 정답 |
| R2 | **Track A N≥3 희박** (실질 후보 2건) | "달성" 아닌 "측정"으로 재정의. negative도 §6 공리 |
| R3 | **selection_type 자기신고 = gate-shopping** | 코드 상수 lookup + chain 자격 evidence-presence 검사(register 시점). 의심 시 sweep |
| R4 | **Track F hook 미발화 = 거짓 안전감** | 게이트 R 계약 내부로(1.2). hook은 보조 |
| R5 | **chain 위장(E/B)** | holdout 봉인+IS-only assert. 병렬 grid면 sweep 정직선언 |
| R6 | **forecaster holdout 저정보**(45~95월 SE 큼) | 직접채점 금지, falsification 예측구간. PASS_LOW_INFO 라벨 |
| R7 | **rawdata P0 오염**(5월 토요일+06-04~09 누락) | 2026-04-30 절단 라벨 + Cycle2 R-track 수리 후 재판정 defer |
| R8 | **경로/시그니처 오류** (regime_module_admission는 portfolio/, run_wf는 04_Research/, G:/ 하드코딩) | 착수 전 grep 확정 |

---

## 6. 다음 액션 (권고)

1. **즉시: Phase 0 병렬 착수** — 특히 **E1**(forecaster 92% 정정 + H(next\|cur) 정보상한)을 최우선 단독. 도훈 결정 전제부터 코드로 확정. 전부 effort S, 천장 무관, 영구 메타지식.
2. **Phase 1(Track A) 착수 전 rawdata P0 수리 확인** (Cycle2 R-track 선행) — 2017+ OOS 판정 왜곡 방지.
3. **Phase 1 GATE 결과로 전체 로드맵 분기 결정** — N≥3(Track B GO) vs N<3(overlay+DPL 재배정). 실측상 N<3 예상이므로 **천장레버를 overlay+DPL로 공식 재배정하는 시나리오를 1순위로 준비**.
4. **Track F 게이트는 R 계약 내부 재설계분만 채택** (hook 버전 폐기).
5. governor admit은 전 과정 수동 + 도훈 confirm 불변.

---

## 부록 — 트랙별 검증 평결 원본

전 트랙 `NEEDS_REVISION`. 핵심 revision은 각 Phase 표에 반영. 상세 critique(PIT/헌법/과적합/실현가능/천장논리/revisions)는 워크플로우 산출 `wf_62300fda-a84` 참조.
