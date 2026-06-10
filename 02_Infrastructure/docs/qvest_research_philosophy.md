# Qvest Research Philosophy SOT — 7 QEPM Modern Trends Integration

**Charter-level Constitutional Document**
**Version**: v1.0 (2026-05-14, Session 81 도훈 mandate)
**Adoption**: 모든 alpha/risk/optimizer/forge/judge/governor cycle reference
**Update**: 분기별 review (3개월) + trigger-based 보강
**Reference**: `CLAUDE.md` Level 0 / `.claude/rules/research_philosophy.md` autoload

---

## §1 본 SOT 위상 (Why Constitutional)

**근거**: 도훈 mandate 2026-05-14 Session 81 — Jensen-Kelly-Malamud-Pedersen 2022 / Liao-Ma-Neuhierl-Schilling 2025 RFS / You-Zhang 2025 / Acadian 2026 등 최신 QEPM 학술 트렌드를 시스템 리서치 영구 근간으로 통합.

**적용**: Charter v1.7 + AX-000~008 + L-code 학습 위에 본 SOT가 7 trend principle reference로 작동. PIT C1~C15 (Level 1) 위 / Charter §10~13 (Level 1) 위 / **본 SOT는 Level 0 (Constitutional)**.

**증거 base**: 본 SOT 도입 직전 Session 81 누적 9 cycle archived + L-316~L-320 본질 통찰:
- **L-316**: alpha-vector cor ≠ portfolio realized cor distinction (Optimizer level extension)
- **L-317/L-318**: family-specific universe effect + component dilution mechanism
- **L-319**: KR ML 12-feature low-dim baseline FAIL → Kelly Virtue 200+ mandate
- **L-320**: Sequential Admission HOLD + Cross-Harness Drift L-282 type 재발

→ 단순 "factor 발굴" 차원 한계 입증. **최신 학술 = Net-of-Cost Implementable Frontier 방향**.

---

## §2 Constitutional 7 Principles

### Principle 1: Factor Zoo 축소 (Validation > Discovery)

**원칙**: 새 factor 발굴보다 **기존 factor 검증·중복 제거·경제적 해석**이 우선.

**근거 학술**:
- Harvey-Liu-Zhu (2016) "...and the Cross-Section of Expected Returns" — multiple testing penalty
- McLean-Pontiff (2016 JoF) — post-publication anomaly decay

**의무 (Hook 강제)**:
- `feature_registry.json`에 `economic_rationale` (≥50자) + `redundancy_cluster_id` 필수 필드
- 단일 factor t-stat 또는 CAGR 높음 ≠ valid alpha
- 기준: `Economic Rationale + OOS Robustness + Net-of-Cost Profitability + Capacity`
- Charter §10 statistical defense (Harvey 5-spec NW t lag 6 + DSR Bailey-LdP) 강제

**현 Qvest 정합도**: ⚠️ Factor DB 330 registry + WT-008 quality_audit 있지만 `economic_rationale` 메타 부재. Phase 2.C에서 보강.

---

### Principle 2: Cost-aware Alpha (Net > Gross)

**원칙**: 거래비용·market impact를 **설계 단계에서 직접** 반영 (post-hoc 차감 X).

**근거 학술**:
- Jensen-Kelly-Malamud-Pedersen (2022 SSRN, ID 4187217) "Machine Learning and the Implementable Efficient Frontier"
- ScienceDirect 2024 "Comparing factor models with price-impact costs"
- Research Affiliates "Transaction Costs of Factor Investing Strategies"

**의무 (Hook 강제)**:
- ML loss function 안 turnover penalty 통합: `loss = -E[ret] + γ·|Δw|`
- Optimizer 목적함수: `max w^T μ̃ - λ w^T Σ w - γ C(w_t - w_{t-1}) - η TE(w_t, b_t)`
- 백테스트 산출 시 `metrics.csv`에 `net_cost_basis` + `cost_drag_bps` columns 의무
- **Hook**: `C_gross > C_threshold` (예: 100bps/yr) 시 strategy 폐기 mandate

**현 Qvest 정합도**: ⚠️ cost_model_version v2.3_kr_retail_15bps 정합 + TO ≤ 11.0/yr constraint(2026-05-29 완화) 있지만 ML loss 통합 X. Phase 1.B에서 즉시 통합.

---

### Principle 3: Uncertainty-aware Forecasting (CI > Point Estimate)

**원칙**: 점예측 μ̂ 대신 **예측 신뢰구간 SE(μ̂)** 반영.

**근거 학술**:
- Liao-Ma-Neuhierl-Schilling (2025 RFS) "The Uncertainty of Machine Learning Predictions in Asset Pricing" (SSRN 5160731)
- 핵심 정리: ML forecast confidence interval + confident-high-low strategy가 traditional high-low strategy 대비 OOS Sharpe 우월

**의무 (Hook 강제)**:
- ML pipeline에 bootstrap prediction interval 또는 quantile head 의무
- Uncertainty-discounted alpha: `μ̃ = μ̂ - k·SE(μ̂)`, k ∈ [0.5, 2.0]
- **Confident-High-Low** 전략: 예측 신뢰도 + 점수 둘 다 높은 종목만 선별
- `predictions_with_ci.parquet` 산출: `mean / std / p25 / p75 / p05 / p95`

**현 Qvest 정합도**: ❌ Point estimate only — **가장 큰 신규 가치 Gap**. Phase 1.A에서 즉시 통합.

---

### Principle 4: Direct Portfolio Learning (Integration > Two-stage)

**원칙**: 신호 → 가중치 **직접 학습** (μ̂ → optimizer separate 회피).

**근거 학술**:
- You-Zhang (2025 SSRN 5992294) "When Markowitz Meets Machine: Optimization of Large Portfolios with High-Dimensional Stock Characteristics"
- 기존 문제: 작은 μ̂ 추정오차 → 큰 weight 증폭 (estimation error amplification)

**의무 (Phase 3 도입)**:
- `ml_models.py`에 Direct Policy NN candidate 추가 (constrained sigmoid + L1 normalize for Σw=1, long-only via softmax)
- features → weights 직접 학습
- 검증: vs Mean-variance optimizer base 50% OOS Sharpe 비교

**현 Qvest 정합도**: ❌ Two-stage (alpha → optimizer separate). Phase 3 도입 — GPU 필수, 복잡도 큼.

---

### Principle 5: Risk Model 고도화 (Crowding + Concentration)

**원칙**: Σ 추정 + **crowding score + demand elasticity + benchmark concentration** 통합.

**근거 학술**:
- Behmaram (2024 SSRN 4823976) "From Active to Passive: The Consequences for Demand Elasticity"
- Hua-Sun (2024 SSRN 5023380) "Dynamics of Factor Crowding"
- Acadian Asset Management (2026) "Misplaced Anxiety? A Reassessment of Crowding in Systematic Investing"
- MSCI Factor Investing crowding measurement

**의무 (Hook 강제)**:
- `risk_package.json`에 `crowding_score_per_factor` + `passive_concentration_audit` 필수
- INV family + 외국인 cumulative flow + similar fund position overlap 측정
- benchmark-relative risk 강제 (KOSPI200 삼성전자/SK하이닉스 등 over/under)

**현 Qvest 정합도**: ✅ Σ = BΩB' + D + LW shrinkage + HHI audit 정합. ⚠️ per-factor crowding_score 미산출. Phase 2.C에서 보강.

---

### Principle 6: Implementation Discipline (Already 강점)

**원칙**: turnover / liquidity / ADV / rebalancing buffer = 성과 핵심.

**근거 학술**:
- Research Affiliates "Transaction Costs of Factor Investing Strategies"
- Springer JAM 2024 "Cost mitigation of factor investing in emerging equity markets"

**의무 (Hook 강제 — 이미 정합)**:
- TO ≤ 11.0/yr (Charter §10 R5, 도훈 mandate 2026-05-29 6.0→11.0 완화)
- LIQ_THRESHOLD 2e8 KRW (20d ADV)
- max_names 20 hard
- weight_bounds [0, 0.20]
- Σw = 1 absolute
- long-only weights ≥ 0
- 15bps one-way cost
- rebalancing buffer (rank ≤ 30 keep + rank ≤ 25 new entries) ⚠️ Phase 1.B 보강

**현 Qvest 정합도**: ✅✅ 매우 잘 정합 (`worktask_constraint_enforcer.sh` Hook 강제).

---

### Principle 7: Attribution & Feedback Loop (Decay 감시)

**원칙**: 성과 = factor exposure + selection + sector + cost + residual 분해. Decay 자동 감지.

**근거 학술**:
- Robeco (2025) "Seizing quant and fundamental alpha in developed equity markets" — quant + fundamental risk parity IR 우월
- Brinson-Fachler attribution / Carhart 4-factor decomposition 정통
- Acadian (2026) crowding monitoring

**의무 (Hook 강제)**:
- 단순 CAGR/Sharpe 보고 금지 — 출처 분해 의무
- 분기별 자동 Brinson 분해 + Carhart 4-factor decomposition
- monitoring agent에 `cost_prediction_error` + `uncertainty_drift` + `feature_stability_12m_rolling` 추가

**현 Qvest 정합도**: ✅ PG3 monitoring agent + L-code 적립 + dual-track gross/cost. ⚠️ 자동 attribution 부재. Phase 2.D에서 보강.

---

## §3 Implementation Roadmap

### Phase 1 (Immediate, ~2-3주, **A + B 병렬** — 도훈 mandate)

#### A. Uncertainty-aware Alpha (P3)
| File | Change |
|---|---|
| `02_Infrastructure/ml_pipeline/ml_models.py` | bootstrap CI per stock prediction (B=100 bootstraps) 또는 quantile regression head (p25/p75) |
| `02_Infrastructure/ml_pipeline/quality_metrics.py` | CI coverage metric + Confident-High-Low strategy 평가 추가 |
| `02_Infrastructure/ml_pipeline/run_ml_cycle.py` | `--enable-uncertainty` flag + `predictions_with_ci.parquet` 산출 (mean + std + p25 + p75 + p05 + p95) |

**검증**: Confident-High-Low vs naive High-Low Sharpe 비교 (Liao 2025 RFS reproduce 기준 +0.2~0.4 SR 개선 기대)

#### B. Cost-aware ML Loss (P2)
| File | Change |
|---|---|
| `02_Infrastructure/ml_pipeline/ml_models.py` | 새 objective `make_cost_aware_loss(γ)` 추가. 기존 candidates의 cost-aware variant |
| `02_Infrastructure/ml_pipeline/walk_forward_cv.py` | per-fold turnover 계산 helper |
| `02_Infrastructure/ml_pipeline/run_ml_cycle.py` | `--enable-cost-aware --gamma 0.001` flag + post-cost summary_stats (`rank_IC_post_cost`, `IR_net`, `sr_net_proxy`) |
| `ml_models.py` | M7 XGBoost-CostAware 추가 |

**검증**: M4_XGB_GPU vs M7_XGB_CostAware turnover 비교 — post-cost SR 우월 입증

### Phase 2 (~2-3주) — **C/D 인프라 신규 (2026-05-14 Session 81 조기 도입)**

#### C. Crowding Score per Factor (P5) — ✅ infrastructure built 2026-05-14
- ~~`02_Infrastructure/factor_db/compute_crowding.R` 확장~~ → **신규** `02_Infrastructure/factor_db/crowding_score_per_factor.R` (Acadian 2026 정통)
  - 4 sub-components: HHI_top + Vol_concentration + Passive_overlap + Demand_elasticity (Behmaram 2024)
  - API: `crowding_score_per_factor()` + `crowding_timeseries()` + `crowding_alert()`
- `risk_research_init.md` Step 2 추가 (다음 cycle): `crowding_audit_per_factor` mandate
- `feature_registry.json` schema 확장 (다음 cycle): `crowding_score` field

#### D. Attribution Engine (P7) — ✅ infrastructure built 2026-05-14
- ✅ **신규** `02_Infrastructure/attribution/` 디렉토리
- ✅ `brinson_decomp.R` (Brinson-Fachler 1985 + Brinson-Hood-Beebower 1986 FAJ)
  - allocation + selection + interaction effect 분해 + per_period/per_sector/summary 3축
- ✅ `carhart_4factor.R` (Carhart 1997 JoF + Newey-West 1987 HAC lag 6)
  - Jensen's α + 4 β {MKT, SMB, HML, UMD} + NW t-stats + R²
  - `attribution_full_decomp()` 결합 helper (Brinson + Carhart + cost_drag)
- 분기별 자동 호출 (다음 cycle): `attribution_quarterly_trigger.sh` Hook + monitoring agent Step 5

### Phase 3 (~4-6주, complex)

#### E. Direct Portfolio Learning (P4)
- `ml_models.py`에 M8 Direct Policy NN 추가 (constrained sigmoid + L1 normalize)
- You-Zhang 2025 정통, GPU 필수
- 검증: vs Mean-variance optimizer base 비교

---

## §4 Update Mechanism (영구 진화 구조)

### 4.1 분기별 Review (3개월)
- arxiv MCP + jina MCP로 학술 신규 paper 검색 (top-tier RFS/JoF/JFE/JFQA)
- 7 principles 각각 학술 update 여부 평가
- 도훈 review + amend approval
- L-code 적립 (예: L-321 = Quarterly Review Q3 2026)

### 4.2 Trigger-based 보강
- **Paradigm shift trigger**: 학술 새 frame (예: RL portfolio / Transformer cross-section / 등) 발견 시 즉시 amend candidate
- **Codex 외부 검증 trigger**: 본 cycle 검토 중 외부 Codex가 새 핵심 method 발견 시
- **도훈 직접 mandate**: 도훈 명시 시 즉시 amend

### 4.3 Amendment 절차
1. 본 SOT (`qvest_research_philosophy.md`) 안 Principle 추가/수정 (version bump)
2. `CLAUDE.md` Level 0 reference 1줄 갱신
3. `.claude/rules/research_philosophy.md` 1줄 reference 갱신
4. `methodology_active.md`에 L-code 적립 (amendment 사유 + 학술 인용 + 도훈 mandate)
5. (선택) `axiom_signals.json` candidate 추가 (예: AX-009 Net-of-Cost)

### 4.4 Version log
- **v1.0 (2026-05-14, Session 81)**: 초기 SOT 도입. 7 principles + Phase Roadmap + 분기별 review mandate. 도훈 mandate.

---

## §5 Cross-References

| Layer | File | 관계 |
|---|---|---|
| Level 0 Constitutional | 본 SOT (`qvest_research_philosophy.md`) | 7 principles |
| Level 0 Q-Lead autoload | `.claude/rules/research_philosophy.md` | 1줄 reference |
| Level 0 Constitution main | `CLAUDE.md` Level 0 | "## Research Philosophy" section reference |
| Level 1 axioms | `.claude/rules/axioms.md` (AX-000~008) | AX-009 Net-of-Cost candidate |
| Level 1 PIT | `.claude/rules/pit.md` (C1~C15) | 본 SOT P2 cost-aware + P3 uncertainty의 PIT 정합 의무 |
| Level 1 Charter | `02_Infrastructure/worktask/common_charter.md` §10~13 | §13에 본 SOT 1줄 reference 추가 (Charter v1.8 candidate) |
| Level 2 L-code | `methodology_active.md` L-316~L-320 | 본 SOT 도입 직전 핵심 통찰 inherit |

---

## §6 Hook 정합 (필수 amend)

본 SOT 정합 강제 Hook 신규/amend 후보 (Phase 1-2에서 도입):

| Hook | 영역 | Phase |
|---|---|---|
| `feature_registry_economic_rationale_check.sh` | P1 — economic_rationale 필드 부재 시 PreToolUse[Write] block | Phase 2.C |
| `ml_cost_aware_audit.sh` | P2 — ml_models.py training 시 cost_aware loss 없으면 PostToolUse warn | Phase 1.B |
| `ml_uncertainty_audit.sh` | P3 — predictions.parquet에 CI columns 없으면 PostToolUse warn | Phase 1.A |
| `risk_crowding_score_check.sh` | P5 — risk_package.json에 crowding_score_per_factor 없으면 PreToolUse[Write] warn | Phase 2.C |
| `attribution_quarterly_trigger.sh` | P7 — 분기별 자동 Brinson + Carhart 호출 | Phase 2.D |

---

## §7 Open Decisions

- **AX-009 Net-of-Cost axiom candidate**: Phase 1 완료 후 검토 (`axiom_signals.json` candidate → empirical 승격 path)
- **Charter v1.8 amendment**: §13 본 SOT reference 추가 시점 (본 SOT 도입 직후 vs Phase 1 완료 후)
- **본 SOT 자체 Codex Round 적용**: 분기별 review 시 외부 Codex 검증 의무 (도훈 명시 시에만)
