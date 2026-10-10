# 2계층 리서치 1단위 #1 — 역할 슬리브 로테이션 v0 결과 (PR-L2-ROLESLEEVE-V0 · 2026-10-10)

> 상태: **측정·판정 완료(1회)** · scope = `mechanism_only`(A 자격 없음 — Judge·BOOK 경로 없음) · 텔레그램 미발송(Q-Lead 소관)
> 근거 지시: 도훈 2026-10-08 "2계층은 1계층 전략별 라벨 이용" · 2026-10-10 "자체판단으로 진행" · 사양 = Q-Lead 2026-10-10
> 수치는 전부 산출물 인용(`authoritative_remeasure.json` 권위 등급 · `verdict/h1_verdict_v0.json` 계약 산출) — 손계산 없음.

## 0. 한 줄

분산 상태 기울기(T_var)는 노출 맞춤 정적 혼합(K) 대비 **일평균 Δ +0.54%/yr · NW t 0.28 → H1 `undetermined`**(SESOI 1%/yr 를 배제하지 못함 — 미결, 벽 아님).
위험조정 얼굴도 없다(Calmar Δ −0.007 · p_gt0 0.39). 기전 전제가 깨졌다: **as-of 방어 슬리브가 이후 약세월에 β-잔차 −0.25%/월(MC2 FAIL)**.
처치는 전달됐다(MC3 0.117). 5 arm 전부 essence **C** · PORT_t 음수. 슬리브를 무시한 **EW_all 이 전 지표 우위**.

## 1. 사전등록 (측정 전 잠금)

| 항목 | 값 |
|---|---|
| prereg_id / family | `PR-L2-ROLESLEEVE-V0` / `FAM-PR-L2-ROLESLEEVE-01` |
| 초안 | `06_Registry/prereg/drafts/PR-L2-ROLESLEEVE-V0.draft1.json` · sha256 `6f2781942c2187c706d92ee014c2b65c7fe5a700209acde398e11d84cb57c611` · 색인 written_at **2026-10-10T22:23:54+0900** |
| 설정 | prereg_config sha256 `a888793b…`(색인 기록) |
| 등록 | **차단 7건**(`prereg_registration_attempt_v0.json`) — ①바닥 POOL65 가 `reference_floors_v2.json` 에 없음(L2 바닥 개념 부재) ②SE 미산출(T−K 계열은 측정 전 없음) ③④t_crit_lo/hi 출처 없음(지시값 ±1.96 · 경험 귀무 교정 요구) ⑤selection_accounting chain(설정은 sweep·N≥2 요구) ⑥의존 L2-FLOOR-REGISTRY unavailable ⑦pin_tag 없음 |
| 대체 잠금 | 초안 sha256 + 색인 written_at. arm 측정 22:26~22:34(전부 잠금 뒤 · 판정이 대조) · 엔진·설계·입력·판정 스크립트 sha256 을 초안이 고정(측정 후 엔진 sha `f8e84c76…` 일치 확인) |
| 판정 기록 | `rf_prereg_verdict` 는 등록본 전용 → 미사용. 초안 규칙을 `verdict_l2v0.R` 가 그대로 집행 · 1회(덮어쓰기 거부) · `rf_record_decision` 기록 없음 |

## 2. 설계 (l2v0_design.json · 동결)

- **후보** = `module_performance.json` 65 close_t1 모듈 ∩ as-of 구성원 81 → 65 전부(계열 경로로 대응).
- **슬리브**(시점 m 첫날 decision_date · `asof_roles.parquet` phase · is_member A/B): 방어·공격·반등·α. 창 2015-10~2026-09 132개월 전부 슬리브 ≥2(최소 반등 2 · 방어 5).
- **P(m)** = `work/msm_asof_daily.parquet::Crisis_Prob_asof`(Date ≤ 시그널일 마지막 값) · 창 평균 Pbar 0.1499 · P>0.5 비율 10.6%.
- **arm**: T_var = P·{방어½, α½} + (1−P)·{공격⅓, 반등⅓, α⅓}(1/N — DeMiguel et al. 2009) · K = Pbar 고정(노출 맞춤 · 전기간 P 평균 → 실시간 불가 대조) · K_eq = ¼ 씩 · S = P 1개월 추가 지연 · EW_all = 가용 모듈 전부 동일가중.
- **구성**: 종목 비중 = Σ(모듈 비중 × 모듈 목표 비중 — 집행일 이하 마지막 스냅샷 · 롱숏 모듈 2개는 순합산) → 시그널일 K200∪KQ150 ∧ LIQ 2e8(1일 지연) → 상위 25 → Σw=1 · 월 리밸 · 15bps · close_t1.
- **측정**: `run_paper_replication`(engine_direct · data_cutoff 2026-09-30 · start_date 2015-09-01 = 첫 시그널일 2015-09-30 을 통과시키기 위함 · chain/1 · QVEST_RP_REGISTER=0 · NO_LCODE=1 · NO_LEDGER_OPEN=1 · send_telegram FALSE).

## 3. 측정 전 점검 (`sanity/sanity_v0.json` — 비중만)

5 arm 모두 통과: 시그널일 132(2015-09-30~2026-08-31) · 월 25종 · max|Σw−1| 4.4e-16 · w>0 · 러너 유니버스 필터가 떨굴 행 0 · `detect_lookahead` CLEAN.
**MC3 = 0.1167 ≥ 0.05 PASS** · MC3b(종목 수준 T−K) 0.1035 · 상위 25 가 남기는 양(+) 모듈 질량 중앙 약 31%(엔진 진단 kept_share — 25종은 모듈 합의 상위 종목).

## 4. 결과 — 권위 등급 (15bps · close_t1 · 2015-10-02~2026-09-30 · 2,695일 · 판본 지문 `170736e5…` 5 arm 동일)

| arm | essence | PORT_t | SR | CAGR | MDD | Calmar | OOS ret. |
|---|---|---|---|---|---|---|---|
| **T_var** | C | −1.001 | 0.464 | 8.9% | 49.3% | 0.181 | −6.764 |
| K | C | −1.133 | 0.483 | 8.9% | 47.3% | 0.189 | −4.430 |
| K_eq | C | −1.188 | 0.434 | 8.1% | 48.1% | 0.169 | −5.650 |
| S | C | −1.354 | 0.394 | 7.0% | 52.2% | 0.134 | −7.864 |
| EW_all | C | −0.238 | 0.665 | 14.0% | 47.5% | 0.294 | −1.759 |

연변동성(bt metrics): T_var 25.4% · K 23.2% · K_eq 25.1% · S 25.2% · EW_all 24.0% — **T_var 가 K 보다 변동성이 높다**(M&M 이 예측하는 방향의 반대).
judge_request 산출 0건(A 없음 → `.EXPERIMENT_HOLD` 개명 대상 없음).

## 5. H1 · 보조 대조 (`beta_controlled_alpha` 계약 · NW lag 3 · 같은 날 짝 2,695일)

| 대조 | 평균 Δ | NW t | β-통제 |
|---|---|---|---|
| **H1 T_var−K** | **+0.538%/yr** | **0.276** | t(α) −0.02 · β 1.05 |
| H1 강건(lag 21) | +0.538%/yr | 0.284 | — |
| S−K (lag-1 스트레스) | −1.303%/yr | −0.712 | t(α) −1.05 |
| T_var−S | +1.842%/yr | 1.587 | t(α) 1.62 |
| T_var−K_eq | +0.871%/yr | 0.457 | t(α) 0.58 |
| T_var−EW_all | −4.184%/yr | −1.156 | t(α) −0.89 |

- se 1.95%/yr → 90% CI ≈ [−2.7%, +3.8%]/yr. (value − ie)/se = −0.236 > −1.96 → 함의 효과(1%/yr) 배제 실패 → **`undetermined`**(powered_null 아님 — 검정력 부족).
- 짝지은 원형 블록 부트스트랩(B 2000 · 블록 14 · 설정 seed): 평균 p_gt0 0.612 · **Calmar Δ −0.007 [−0.158, 0.104] · p_gt0 0.394**.
- lag-1: 지연 P 가 더 나쁘다(T−S +1.84%/yr · t 1.59 · 비유의). T_var 자체에 이득이 없으므로 동월 누출이 이득을 만든 흔적은 없다(P 는 pit_audit PIT-clean · 활성 격리 PITQ-C1-MSM 의 as-of 제외 조항 해당).

## 6. 조작 확인

| MC | 규칙 | 값 | 판정 |
|---|---|---|---|
| MC1_var | IS 분산 AUC 95% CI 하한 > 0.5 | AUC 0.840 · CI [0.718, 0.917] (IS · 기존 산출 · 등록 전 알려짐) | PASS |
| MC2 | as-of 방어 슬리브 약세월(사후 PS · 평가 표적 전용) β-잔차 평균 > 0 ∧ NW t ≥ 1.0 | **−0.250%/월 · NW t −0.59**(평범 t −0.50) · 약세월 54/131 · 슬리브 β 0.672 · 월 구성원 4~40(중앙 23) | **FAIL** |
| MC3 | 슬리브 처치 전달량 ≥ 0.05 | 0.1167 (종목 0.1035) | PASS |

## 7. 해석 (기전)

1. **처치는 전달됐는데 효과가 없다** — 구 FR 의 'EW 붕괴'(처치 미전달)가 아니다. MC3 0.117 · 종목 수준 10% 가 매달 다르다.
2. **원인 후보 1순위 = 라벨 비지속(MC2)**: as-of 방어 등급(과거 확정 약세 국면 β-잔차)이 창 안의 다음 약세월로 이어지지 않는다. 고분산 국면에 '방어'로 옮겨도 방어가 일어나지 않으니 T_var 는 오히려 변동성이 커졌다(25.4% vs 23.2% · β 1.05).
3. **M&M 기전과의 거리**: M&M 의 개선은 고분산에서 *노출 자체*를 줄이는 데서 나온다. Σw=1 롱온리 슬리브 혼합은 노출을 줄이지 못하고 '어느 롱북을 드느냐'만 바꾼다 — 그 선택이 라벨 비지속으로 무작위화됐다.
4. **EW_all 우위**(CAGR 14.0% vs 8.9% · Calmar 0.294 vs 0.181 · 비유의 t −1.16): 역할 부분집합의 합의 상위 25 보다 전 모듈 합의 상위 25 가 낫다 — 역할 필터가 정보를 더하기보다 표본을 줄인 쪽. 단, 전 arm PORT_t 음수 · OOS retention 음수(2025~26 시총 집중 랠리 구간에서 벤치 대비 열위)라 '좋은 기준선'이 아니라 '덜 나쁜 기준선'이다.

## 8. 공개 사항

- **표적 전환**: 사전 규칙은 방향 표적이었고 IS 방향 MC1 실패(JM AUC 0.675 · CI 하한 0.487) **뒤** 분산 표적 채택(선험 근거 Moreira & Muir 2017 · Barroso & Santa-Clara 2015). 예측기는 IS 분산 AUC 최대(MSM 0.840 > HMM2 0.815 > JM 0.756).
- **OOS 열람 가능성**: `predictor_oos_diagnostic.json`(21:21 · 사전등록 이전)이 OOS 분산 AUC(MSM 0.790)를 이미 보였다 — 순위가 IS 와 같아 선택은 불변이나 분기 경로 위험.
- **후보 집합 사후 선택**: 81 대표 = 전기간 역할 t + 사후 PS 로 선정(README §6-1) — 라벨은 as-of 여도 후보는 아니다.
- **1계층 표식 상속**: 65 중 49 가 C1 류 표식(전기간 IC 선정 28 · 교차 entry 설계 노출 33 — 원장 재귀 탐색 · 진단 정밀도 한계). 활성 격리(PITQ-C11 · PITQ-C1-MSM) 모듈 목록과의 교집합 0 · 엔진은 격리 원천 정규식 미적중.
- K 는 실시간 불가 대조(Pbar = 창 전체 P 평균). 롱숏 모듈 2개는 순합산. 스냅샷이 일찍 끝난 모듈(2026-08-03·2025-12-01·분기 2026-07-01)은 마지막 결정을 그대로 보유.
- 판정 임계 ±1.96 은 명목(Q-Lead 지시) — 설정이 요구하는 경험 귀무 교정 아님. SESOI 1%/yr 는 판단값(Lakens 2017 틀).

## 9. 2계층 부기 (`verdict/bookkeeping_v0.json`)

| 경로 | 처리 | 사유 / 빠진 것 |
|---|---|---|
| L-code | **적립** `L-FR-20261010_223658`(`stage_artifacts/l_code/factor_rotation/l_code_L2_ROLESLEEVE_V0.json` · strategy_rotation 정규화) | — |
| FR 레지스트리 `register_fr_result` | 미등재 | 문서화된 입력 = `run_wf_ensemble` 산출 · 소비자 `rf_director` 가 FR 산출 디렉터리(manipulation_check.json)를 전제. **필요: 'run_paper_replication 측정 2계층 단위' 수락 결정 + fr_id·module_pool·MC 경로 어댑터** |
| L2 원장 `rf_open_entry/rf_append_attempt(layer=2)` | 미개설 | 사전등록 실험 원장 경로(priority='prereg', experiment=)는 `run.live_enabled=false` · `rf_l2_auto.R` 는 run_wf_ensemble arm 만 · mechanism_only 라 A 표적 강화 계보 부적합 |
| 사전등록 등록 | 차단 | **필요: L2 바닥 개념(reference_floors 또는 L2 전용 바닥 레지스트리) · 경험 귀무 교정 산출물 · pin 스냅샷** |

## 10. 다음 (next probes)

1. **라벨 지속성 수리가 먼저** — 방어 역할을 '다음 약세 구간 잔차'로 검증되는 as-of 표적(실현 하락월·심층 하락 캡처의 as-of 판)으로 재정의하고 MC2 재측정. MC2 미통과 상태에서 배분 규칙을 바꾸는 것은 처치 없는 조정이다.
2. **EW_all 우위 분해** — 역할 부분집합 vs 전 모듈 합의(25 절단 잔존 질량·종목 집중·회전) · 슬리브 안 비중법(EW→RP) · 모듈 단위 배분 대조.
3. 분산 기울기를 역할 라벨 대신 **모듈 as-of 실현 β 순위**에 걸기(고분산 → 저β 모듈 ↑ · 고정 축 안) — 같은 틀(K 노출 맞춤 · MC3)로.

## 11. 파일

- 설계·코드: `l2v0_design.json` · `build_l2v0_inputs.R` · `allocator_engine.R` · `prereg_l2v0.R` · `sanity_l2v0.R` · `run_l2_v0.R` · `verdict_l2v0.R` · `bookkeeping_l2v0.R`
- 입력 동결: `work/l2v0_candidates.csv` · `work/l2v0_module_holdings.parquet` · `work/l2v0_inputs_manifest.json`(sha `ec12fbfc…`)
- 사전등록: `06_Registry/prereg/drafts/PR-L2-ROLESLEEVE-V0.draft1.json` · `prereg_registration_attempt_v0.json`
- 측정: `runs/<arm>/<run_id>/`(T_var `20261010_222715_15732` · K `…222847_27940` · K_eq `…223019_2328` · S `…223149_31468` · EW_all `…223318_22132`) · `runs/<arm>/engine_diag/` · `runs/_logs/`
- 판정: `verdict/h1_verdict_v0.json`(sha `e56e7735…`) · `h1_TvarK_beta_controlled_alpha.json` · `boot_mean_TvarK.json` · `boot_calmar_TvarK.json` · `mc2_defensive_sleeve.json` · `bookkeeping_v0.json` · `sanity/sanity_v0.json`
