# Path A NAV-level Blend Paradigm — DPL-RC v2.0

**WT-D20260517_004 alpha-research Step 2.1**
**wt_type**: `discovery_design_phase_a` (Charter §10 v1.8)
**Author**: alpha-research agent
**Date**: 2026-05-17
**Designed under**: 도훈 mandate "Path A NAV-level blend" (autonomous mode)
**Predecessor**: WT-D20260517_003 DPL-RC v1.0 weights-level A-option, DEFER (3 structural blockers)

---

## 0. Executive Summary (1 paragraph)

DPL-RC v2.0는 **포트폴리오 가중치 수준이 아닌 슬리브 NAV 수준에서 결합**한다.
`NAV_blend(t) = (1 - a_t) · NAV_1715_5Layer(t) + a_t · NAV_comp(t)` 로 두 슬리브의 일간/월간 자본가치(net of cost)를 직접 가중. 1715 alpha core는 **물리적으로 분리 보존**(MODIFICATION X) 되고, complement는 1715 외부 universe(`KR_TOP500_LIQ1E8 ∖ STR_1715_top_20_universe`)에서 자유롭게 종목 선정 → cor ≤ 0.3 자격이 **by construction 가능**(WT_003 A안에서는 강제 cor ≈ 1.0). Multi-sleeve admission framework는 L-279~L-281 Hybrid 70/15/15 (STR_1715 + TSMOM + KR_10y) 선례 + AX-007 exemption #1 (multi-sleeve)에 1:1 정합한다.

---

## 1. WT_003 → WT_004 paradigm shift (1 page summary table)

| 영역 | WT_003 v1.0 (weights-level A-option) | **WT_004 v2.0 (Path A NAV-level)** |
|---|---|---|
| **Blend 단위** | portfolio weights `w_final = (1-a)·w_1715 + a·w_comp` | **sleeve NAV `NAV_blend = (1-a_t)·NAV_1715 + a_t·NAV_comp`** |
| **Comp universe** | 1715 top-20 강제 (portfolio union ≤ 20 hard) | **1715 외부 (`KR_TOP500_LIQ1E8 ∖ STR_1715_top_20`)** |
| **Top-K cor 결과** | cor = **0.9997** by construction | cor ≤ 0.3 target **가능 by construction** |
| **Production lineage** | 1715 weights 일부 dilute (alpha 침범) | **100% retain (NAV 그대로)** |
| **Max names hard** | union ≤ 20 single-sleeve strict | sleeve 각 20 + 합 ≤ 40 OK (L-279 multi-sleeve precedent) |
| **Baseline measurement** | production SR 1.95 vs canonical SR 0.37 (cross-base mismatch) | **same-harness NAV-level fair comparison** |
| **AX-007 exemption** | exemption #1 multi-sleeve + #4 ML sizing (sleeve 분리 미입증) | **exemption #1 multi-sleeve 명시적 정합 (NAV 단계 분리)** |
| **G1 classifier** | Recall **0.089** OOS (HARD_ABORT) | **G1 4-옵션 비교 재설계** (threshold tuning / continuous / 1715-specific / class-balanced) |

---

## 2. NAV_blend formula 정밀 정의

### 2.1 Core blend equation

```
NAV_blend(t) = (1 - a_t) · NAV_1715_5Layer(t) + a_t · NAV_comp(t)
```

where:
- `NAV_1715_5Layer(t)` = STR_1715_AR_on_M4_R05_overlay_PG2 net cumulative NAV at month t (production retain, 15bps cost embedded)
- `NAV_comp(t)` = complement sleeve net cumulative NAV at month t (1715 외부 universe, 15bps cost embedded)
- `a_t` = injection rate at sig_date t (decision time)
- 두 NAV 모두 PerformanceAnalytics `Return.portfolio()` standard 산출 (Backtest Contract v1.0)

### 2.2 Daily/monthly return decomposition (PIT strict)

월간 return decomposition (NAV-level → return):

```
r_blend(t→t+1) = NAV_blend(t+1) / NAV_blend(t) - 1
              = w_1715(t) · r_1715(t→t+1) + w_comp(t) · r_comp(t→t+1)
```

where wealth-weight at decision time t:
```
w_1715(t) = (1 - a_t) · NAV_1715(t) / NAV_blend(t)
w_comp(t) = a_t · NAV_comp(t) / NAV_blend(t)
```

이는 정확히 **Markowitz 1952 wealth-weighted portfolio**의 NAV-level 등가 표현 (단, 두 자산의 가격 = sleeve NAV).

### 2.3 Injection rule (PIT strict)

```
a_t = clip(a_max · p_bad_1715(t+1 | F_t), 0, a_max)
```

where:
- `p_bad_1715(t+1 | F_t)` = G1 classifier forecast at sig_date t (features observable at t close, t-1 lag inclusive)
- `a_max ∈ {0.05, 0.10, 0.15, 0.20}` (Pareto curve grid, Forge cycle)
- `clip(·, 0, a_max)` = bounded conditional injection (a_max upper bound = 4th sleeve total exposure cap)

**PIT C2/C9 strict**: `a_t` is decided at sig_date t using `F_t` (t-1 lag features), applied to compute `r_blend(t→t+1)`. NO same-period circular.

### 2.4 Rebalancing & cost accounting

NAV-level blend의 **rebalance cost는 sleeve 내부에서 별도 계산** (15bps × |Δw_within_sleeve|). NAV_1715 / NAV_comp 각각은 이미 net-of-cost. blend 자체에는 sleeve 간 wealth-rebalance cost 추가 발생:

```
turnover_blend(t) = |w_1715(t) - w_1715(t-1)| + |w_comp(t) - w_comp(t-1)|
                  ≤ 2 · |Δa_t|  (each sleeve symmetric move)
```

Hard ceiling: `annualized blend rebalance cost ≤ 0.5 × cost_1715` (small Δa_t target).

---

## 3. Production lineage 100% retain mechanism

### 3.1 NAV input source (READ ONLY)

```r
production_nav_rds <- "05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/04_backtest_results/bt_result_layer5_R05.rds"
production_nav <- readRDS(production_nav_rds)$nav  # bt_result Backtest Contract v1.0 nav field
```

`bt_result_layer5_R05.rds` 는 STR_1715_AR_on_M4_R05_overlay_PG2 PG2 admit 시 Forge 산출(L-313 production 승격). 본 cycle은 read only.

### 3.2 Modification ABSOLUTE prohibition

- `05_Production/` 디렉터리 Hook 강제 (safety_guard PreToolUse[W/E])
- NAV time-series는 input feature로만 사용, 변형 X
- 회귀/스무딩/필터 적용 X (다른 시계열 변환은 NAV_comp 측에서만)
- 만일 NAV missing values 발견 시 → STOP + Forge 위임 (alpha-research 수정 권한 X)

### 3.3 Layer architecture 정합

Production 5-Layer:
```
w_final_1715 = w_str1715 × m4_scalar × β_AR × β_R05(regime_t)
```

DPL-RC v2.0 6-Layer extension:
```
NAV_blend = (1 - a_t) · NAV_1715_5Layer + a_t · NAV_comp
```

→ 1715 5-Layer 위에 **NAV-level orthogonal sleeve를 6번째 Layer로 추가** (sequential overlay 정합, L-308 R05 Layer 5 admit precedent와 동일 구조).

---

## 4. Multi-sleeve admission framework (L-279~L-281 + AX-007 exemption #1)

### 4.1 L-279~L-281 Hybrid 70/15/15 precedent 정합

| Hybrid 70/15/15 (admit) | DPL-RC v2.0 Path A |
|---|---|
| 70% STR_1715_AR_threshold | (1 - a_t) ≈ 80-95% · NAV_1715_5Layer |
| 15% TSMOM ETF rotation (cross-asset, sleeve 분리) | a_t ≈ 5-20% · NAV_comp (conditional, cross-section sleeve 분리) |
| 15% KR_10y bond ETF (asset class 분리) | (production 5-Layer 내부 흡수) |
| `w_book = {0.70, 0.15, 0.15}` static | `a_t = clip(a_max · p_bad, 0, a_max)` dynamic |

**유사점**: NAV-level wealth share 결합 (asset-class-aware sleeve composition). 두 슬리브 모두 ≤ 20 종목 single-sleeve 운용.

**차이점**: 
- Hybrid = static asset-class diversification (60/40 paradigm 진화)
- DPL-RC v2.0 = **conditional cross-section sleeve injection** (1715 약세 상태에서만 보강)

→ L-279 precedent는 NAV-level multi-sleeve admission이 admit 가능함을 입증. DPL-RC v2.0는 그 conditional 변형.

### 4.2 AX-007 exemption #1 (multi-sleeve) explicit mapping

`.claude/rules/axioms.md` AX-007:
> "roles=[defense, core_secondary], structure=single_sleeve_long_only_top20, signal-portfolio translation 메커니즘 단절. 예외 4종 (multi-sleeve / long-short / 50+ 분산 / ML sizing)."

DPL-RC v2.0 매핑:
- **exemption #1 (multi-sleeve)**: NAV_1715 (sleeve A, 20 names) + NAV_comp (sleeve B, 20 names, 1715 외부 universe) → **물리적 sleeve 분리 입증 가능 by construction**. WT_003 A안에서는 union ≤ 20 강제로 sleeve 분리 X (그래서 exemption #1 입증 부족).
- **exemption #4 (ML sizing)**: p_bad_1715 classifier (G1) + injection rate `a_t = clip(...)` ML-sized
- 두 exemption **동시 충족 by construction** (WT_003는 exemption #4만 명확, #1 모호)

### 4.3 ≤ 40 names hard ceiling

| Item | Cap |
|---|---|
| Sleeve A (STR_1715) names | ≤ 20 (production retain) |
| Sleeve B (NAV_comp) names | ≤ 20 (production constraint inherit) |
| **Portfolio union** | **≤ 40** (multi-sleeve precedent, L-279 = 1715(20) + TSMOM(8 ETFs) + KR_10y(1 ETF) = 29 names admit) |
| weight_bounds per name within sleeve | [0, 0.20] |
| sleeve weight | (1-a_t) and a_t, with a_max ≤ 0.20 |

**Cross-sleeve overlap audit**: WT_003 A안에서는 by construction overlap = 100%, v2.0에서는 universe 분리로 overlap = **0%** (1715 top-20 명시 제외).

---

## 5. Path A NAV-level vs Path B weights-level (Blocker 1 resolution scope)

본 cycle은 **Path A 단독 채택**. Path B는 도훈 mandate에 의해 제외(WT_003 DEFER에 흡수).

| 측면 | Path A NAV-level (채택) | Path B weights-level (rejected) |
|---|---|---|
| cor by construction | ≤ 0.3 가능 | ≈ 1.0 강제 |
| 1715 alpha 보존 | 100% (NAV 그대로) | partial (weights dilute) |
| sleeve 분리 검증 | physical NAV 분리 | universe overlap audit complex |
| baseline 비교 | NAV-level fair | cross-base mismatch (production vs canonical) |
| L-279 precedent 정합 | direct (multi-sleeve NAV) | indirect |
| compute cost | NAV computation O(N×T) | weight optimization O(K×N²×T) |
| AX-007 exemption | #1 + #4 both clear | #1 ambiguous |

→ Path A는 6/6 우위. Path B는 cor by construction issue + AX-007 exemption #1 모호 + cross-base mismatch 동시 fail (WT_003 empirical 입증).

---

## 6. Phase A vs Phase B/C separation (wt_type role card)

| Phase | wt_type | Cycle responsibility |
|---|---|---|
| **A: Design** | `discovery_design_phase_a` | spec / protocol / architecture markdown + alpha_package.json + Codex Round (본 cycle, WT_004) |
| **B: Empirical mini-Forge** | `discovery_phase_b_mini_forge` | G1 classifier OOS + Stage 1 Linear PPP mini-feasibility + same-harness NAV comparison (다음 cycle) |
| **C: Full Forge + admission** | `deployment` | GPU 코드 + Stage 2-4 incremental + Pareto curve + Codex/Architect/AX-008 + admission decision |

**현 cycle (WT_004) Expected Output**:
- 4 markdown spec/protocol/architecture artifacts
- alpha_package.json (8-field schema) + Codex Round 5단계
- NO factor_engine code, NO training, NO alpha_scores.parquet generation

**Codex C1 misclassification 방지**: design_phase_a Role Card explicit 명시 (WT_003 challenge_note Section 0 정합).

---

## 7. Self-check (design-quality compliance)

- [x] Production lineage 100% retain mechanism 명시
- [x] NAV_blend formula 정밀 정의 (daily/monthly + injection + rebalance cost)
- [x] L-279~L-281 precedent 1:1 정합 mapping
- [x] AX-007 exemption #1 + #4 explicit 입증
- [x] WT_003 3 structural blockers 본 paradigm 단계에서 해소 path 명시
- [x] Phase A/B/C role card separation 명시
- [x] PIT C1-C15 design-level compliance
- [x] 자기합리화 0건 (WT_003 empirical fail 정직 inherit)

**Charter §8 No Silent Override**: WT_003 DEFER 사유(G1 recall 0.089 + cor 0.9997 + cross-base mismatch) 명시적 inherit + 본 cycle paradigm shift가 각 blocker를 어떻게 해소하는지 explicit.

---

## 8. References

- 도훈 mandate 2026-05-17 "Path A NAV-level blend" (autonomous mode)
- WT-D20260517_003 admission_decision.json (HARD_ABORT_G1_FAIL)
- WT-D20260517_003 challenge_note_alpha-research.md (Codex Round 9 concerns)
- `.claude/rules/axioms.md` AX-007 (multi-sleeve exemption #1)
- L-279 (Hybrid 70/15/15 admit precedent), L-280 (Path C 결정 사유), L-281 (TSMOM cross-section vs time-series orthogonal)
- L-308~L-313 (STR_1715 5-Layer R05 admit + production promotion)
- `05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/` (READ ONLY)
- Markowitz 1952 (NAV-level wealth-weighted portfolio)
- Brandt-Santa-Clara-Valkanov 2009 (PPP framework, Stage 1 baseline)
- Asness-Frazzini-Pedersen 2014 (BAB conditional crisis hedge)
- Moskowitz-Ooi-Pedersen 2012 (cross-asset TSMOM orthogonal precedent)
- Wood-Roberts-Zohren 2026 (DeePM regime-conditional EVaR, Stage 4 backbone)
