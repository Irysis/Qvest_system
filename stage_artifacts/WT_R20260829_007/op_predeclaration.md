# Optimizer 사전 선언 (pre-registration) — WT-R20260829_007

작성 시각: 2026-08-29, **method_comparison 산출 이전**. 이 문서는 결과를 보고 수정하지 않는다.
(결과를 보고 축을 바꾸면 파기 — 도훈 지시. 사후 변경이 필요하면 파기 사실을 명시하고 재선언한다.)

## 0. 입력 (read-only)
- alpha: `alpha_package.json` (α̂ 347종, λ_FM=+0.001534) + `alpha_scores.parquet`(260 sig_date) + `period_returns_production.csv`(strict-PIT 판, 259개월).
  ★`period_returns_same_close_ab.csv` 는 소비하지 않는다.
- risk: `risk_package.json` + `covariance.parquet`(as-of 347×347, structural BΩB'+D) + `rk3_objects.rds`(요인모형 성분 X/Fw/RES) + `tail_risk.json`(EVT) + `regime_correlation.parquet`.
- **alpha 재해석 금지 / Σ 재정의 금지.** α̂ 는 그대로 받고, Σ 는 risk 가 채택한 구조형(LW-Ω ρ0.0111 / Bayes-D k=24 / floor p10)을 **그대로** 각 결정시점에 인스턴스화만 한다(§5).

## 1. 선택축 (selection_objective) — 단 하나
**`net_ir`** = annualized mean(active_net) / annualized sd(active_net),
active_net = ret_net − benchmark_ret, 259개월 walk-forward 전구간.
비용 = **15bps one-way, delta-based(v2.4)** — `cost_t = 0.0015 × Σ|Δw_t|`.

**선택축에서 배제(명시)**:
- `sharpe` 단독 최대화 — Hook 금지(v61_selection_objective).
- **β** — risk 1급 경고. 하방 TDC 0.545 · COVID β 0.946 이므로 저-β 는 위험 축소가 아니다.
  목적함수·제약·선택축 어디에도 β 를 상수 위험 프록시로 넣지 않는다.
- MDD — 등급을 접지 않는다(CLAUDE.md v9.21). 진단으로만 병기.

## 2. Hard 실격 게이트 (순위 매기기 **이전**, 예외·완화 없음)
| # | 조건 | 정본 |
|---|---|---|
| G1 | 매 리밸일 n_names ≤ 25 | request.hard_constraints.max_names |
| G2 | 모든 w ≥ 0 (long-only) | hard_mandate.long_only_mandate |
| G3 | \|Σw − 1\| ≤ 1e-6 | v10 absolute |
| G4 | 유니버스 = alpha 발행 PIT 적격집합(20일 ADV ≥ 2e8 내장) | universe_definition |
| G5 | **연 양방향 회전 ≤ 11.0** | constraint_defaults.json::`turnover_hard_fail_annual` = 11.0 (round-trip) |
| G6 | schedule density ≥ 0.95 × alpha sig_dates | Charter §9 |

★**G5 는 현행 사양이 이미 위반한다** — alpha diagnostics `turnover_proxy` = **15.233** (양방향, 계약 규약 Σ\|dw\|×12) > 11.0.
따라서 회전 축은 "자연스러운 선택"이 아니라 **제약 충족 문제**다. 이것이 본 라운드 설계의 출발점이다.
G5 실격은 net_IR 이 아무리 높아도 구제되지 않는다(silent relaxation 금지 — R12).

## 3. Tie-break 사다리 (Δnet_IR < 0.05 일 때만, 이 순서 고정)
1. **용량**: 참여율 10% 기준 AUM 상한(최근 12M 중앙값) 큰 쪽
2. **꼬리**: book 월간 EVT(GPD) ES99 작은 쪽 — 정규 가정 CVaR 금지(Hill α 2.93)
3. **breadth**: 시간평균 HHI 작은 쪽 (Grinold)

## 4. 방법론 5종 (상한 5 · 단순→복잡 · 하이퍼파라미터도 사전 고정)
| id | 이름 | 축 | Σ 필요 | 사전고정 하이퍼 |
|---|---|---|---|---|
| M1 | `EW25_base` | alpha 생산 사양 그대로(근접도 top-25 · 등가중) — **baseline** | 아니오 | — |
| M2 | `EW25_buffer` | 등가중 + **no-trade band**(보유 종목은 근접도 순위 ≤ B 인 동안 유지, 공석만 상단에서 충원) | 아니오 | B = 40 (= 1.6×카디널리티, 관례대) |
| M3 | `ALPHA_TILT` | top-25, w ∝ confidence-scaled α̂ 의 단조 tilt (Σ 미사용 sizing) | 아니오 | tilt = rank-linear, floor 0.5/25 |
| M4 | `MVO_TO` | confidence-aware MVO + **명시적 회전 페널티** φ | 예 | λ=2.0, ψ=0.3, φ = **40.5bps one-way**(risk 발행 손익분기) |
| M5 | `BUF_MVO_TO` | M2 선별 ∩ M4 sizing (복합) | 예 | 위와 동일 |

φ 를 15bps 가 아니라 40.5bps 로 잡는 이유는 사전에 고정한다: risk 가 발행한 손익분기 편도 비용이 40.5bps 이므로
**비용 모델(15bps)로 채점하되 최적화는 손익분기 비용을 내재화**한다(Jensen-Kelly-Malamud-Pedersen 2022 의 cost-aware 목적함수).
채점 비용은 여전히 15bps 다 — φ 는 목적함수 파라미터이지 채점 비용이 아니다.

**하이퍼 sweep 금지.** 위 값은 결과를 보기 전에 고정했고 결과를 보고 바꾸지 않는다.

## 5. Σ 의 walk-forward 인스턴스화 (경계 선언)
risk 는 as-of Σ 1개만 발행했다. 259개월 schedule 을 위해 **risk 가 자기 rk5_walkforward.R 에서 쓴 것과 동일한 조립식**
(B_t = MKT+섹터더미+7스타일, Ω_t = LW shrinkage on f_1..f_{t-1}, D_t = rolling-60 잔차분산 + p10 floor)을
risk 가 발행한 성분(rk3_objects.rds 의 X/Fw/RES)으로 **인스턴스화**한다.
- 추정기·shrinkage·창·floor **어느 것도 내가 고르지 않는다**(전량 risk 승계). = 모형 적용이지 재추정 아님.
- 그럼에도 이것은 risk 산출물의 경계를 건드리는 행위이므로 **명시 공개**한다(No Silent Override).
- PIT: 결정시점 t 에서 f_1..f_{t-1}, u_1..u_{t-1} 만 사용(risk C1 규약 동일).

## 6. 사전 선언한 예외 처리 규칙 (결과를 보기 전에 고정)
- **G5 미충족이 전 방법론에서 발생하면**: 버퍼폭을 사전 사다리 **B ∈ {40, 50, 60, 75}** 로 올려
  **G5 를 만족하는 최소 B** 를 취한다. 이것은 제약충족 규칙이지 성과 sweep 이 아니다(선택은 여전히 net_IR).
  B 사다리를 다 써도 G5 미충족이면 → `infeasibility_report` 발행(완화 금지).
- **선택 method 의 net_IR 이 M1 대비 개선이 없으면** 그 사실을 그대로 적는다(과장 금지 — Cycle 2 교훈, DeMiguel 2009).
- 제약 완화(>25종 / short / 유동성 하향)는 레버로 제시하지 않는다(INV-7).

## 7. 산출 의무
`optimization_package.json` · `weights.csv`(다중 as_of_date 시계열, density ≥ 0.95) · `weight_method_selected.md` · `challenge_note_optimizer.md`.
