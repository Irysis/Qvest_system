# Pilot 8 Design Draft — L-197 Active IR Structural Fix

**작성**: 2026-04-24 Q-Lead  
**근거**: AX-007 Verification Sprint (Phase 1 Architect + Phase 2 Codex convergence)  
**상태**: DRAFT (Phase 3 Replication 완료 후 FINAL 확정)

---

## 3-Source Convergence 확정 사항

| 항목 | Architect | Codex | 사용자 | 판정 |
|---|---|---|---|---|
| Infra bug | CLEAN | 구현 독립 | — | ✅ Clean |
| Divergence 주원인 | regime-dep 0.70 | regime-dep 0.79 | — | ✅ β under-hedge |
| β_target 완화 | "25% leverage loss" | baseline 0.90 | β ≥ 1.0 허용 | ✅ **0.90~1.05** |
| MinVar 구조적 결함 | infra 아님 | 0.84 신뢰 | — | ✅ 아키텍처 문제 |
| Active IR fail 불가피? | L-196 HIGH | **NOT inevitable 0.82** | — | ✅ **해결 가능** |
| Style mismatch 기여 | FF3 10.5% retain | 35~45% | — | ✅ 주요 원인 중 하나 |
| Signal-portfolio transfer | — | **55~65% 주원인** | — | ✅ Pilot 8 핵심 타겟 |

## Pilot 8 Path A — Risk Universe Redesign (즉시 실행)

### 변경 요약
| 항목 | Pilot 7 | **Pilot 8 Path A** |
|---|---|---|
| Alpha | RAPC 5F + CAPM Blume (상속) | **상속 그대로** |
| Risk universe 선발 | top-40 by α rank | **top-40 by α-divergence (α_std 우선)** |
| α divergence filter | 없음 | **unique_α/n ≥ 0.80 강제** (L-195a fix) |
| β_target | 0.75 hard γ=1.0 | **0.90 baseline + tier** |
| Confidence tier | 없음 | **Alpha Agent 산출 `confidence_tier`** |

### Confidence-weighted β tier

| α tier | 기준 | β_target | γ |
|---|---|---|---|
| HIGH | DSR>0.8 + rank_IC>0.04 + ICIR>0.5 + FF3 retain>30% | **1.00~1.05** | soft 0.5 |
| MEDIUM | DSR>0.5 + rank_IC>0.03 + ICIR>0.3 | **0.90~1.00** | soft 0.5 |
| LOW | DSR>0.2 + rank_IC>0.02 | 0.80~0.90 | soft 0.5 |
| REJECT | 아래 | 전략 재검토 | — |

**Pilot 7 기준** (DSR 1.011 / rank_IC 0.0381 / ICIR 0.6273 / FF3 10.5%):
- rank_IC 0.04 미달 + FF3 retain 10.5% < 30% → **MEDIUM tier** → **β_target 0.90**

### 기대 효과

- β 0.75 → 0.90: **+15pp leverage 회복 → 연 ~0.75pp active return 상승** 추정
- α-divergence filter: L-195a resolved → Optimizer α-aware MVO 선택 복귀 가능
- n=20 유지 / HHI 0.15 / max_w 0.15 (v2.2 유지)

## Pilot 8 Path B — Multi-sleeve Prototype (별도 sprint)

### 구조
- **Core sleeve (70%)**: RAPC 5-factor (Pilot 7 승계) — earnings-surprise alpha
- **Diversifier sleeve (30%)**: Scout 2차 Shortlist 기반 신규 signal
  - 후보 1: Ball 2016 Cash-OP surprise (α-decorrelated from RAPC)
  - 후보 2: Momentum residual (Daniel-Moskowitz 2016 risk-managed)
  - 후보 3: Low-volatility (Pilot 4~7 기 사용, multi-sleeve 내에서만 정당)

### TDC 조건
- Core-Diversifier pairwise TDC ≤ 0.40 (L-156 v2 standard)
- 각 sleeve 내 정상 TDC ≤ 0.40

### Diversifier signal 선택 기준
- RAPC와 CAPM residual correlation < 0.3
- FF3 residual retention > 40% (style-free)
- DSR > 0.5

## 실행 순서

### Phase 0 (Pilot 8 전 선행) — Urgent Fix HIGH 2건
- [ ] Train window 통일 (Forge 2012+ vs Judge 1990+ 혼란 제거)
- [ ] `record_package_lineage()` timing fix (3 pilot 연속 미반영)

### Phase 1 — Pilot 8 Path A (Risk Redesign, 즉시)
- WT-D20260424_006 생성
- Alpha Agent 호출 생략 (Pilot 7 alpha_package 상속)
- Risk Agent 스폰 (α-divergence filter + confidence-weighted β)
- Optimizer / Forge / Judge 체인

### Phase 2 — Pilot 8 Path B (Multi-sleeve, 후속 sprint)
- Scout bibliography 재검토 → Diversifier signal 1개 선택
- WT-D20260425_001 생성
- Alpha Agent full run (Core + Diversifier 2-sleeve 설계)

## 예상 결과 (Phase 1 Pilot 8 Path A)

**보수적 추정**:
- Forge Full SR: 0.258 → **0.35~0.45** (β 회복 효과)
- Lockbox SR: 1.020 → **1.15~1.30** (β 회복 + style neutralize 부분)
- Active IR: -1.033 → **-0.5 ~ -0.7** (여전 fail but 개선)

**낙관 추정** (α-divergence filter 효과):
- Optimizer α-aware MVO 선택 복귀 시
- Active IR: **-0.3 ~ 0.0** (breakthrough 가능)
- Grade B~B+ 기대

**실패 시**:
- L-197 구조적 dead-end 재확인 (4 pilot → 5 pilot)
- Path B Multi-sleeve 필수 진입

## constraint_defaults v2.3 Draft

```json
{
  "version": "v2.3",
  "effective_from": "2026-04-24 Pilot 8+",
  "_changelog": {
    "v2.3": "2026-04-24 AX-007 Verification 결과 + β 철학 적용. β_target 0.75→0.90 default, confidence-weighted tier, α-divergence filter 신규."
  },
  "tier_soft_deployment": {
    "max_names": 20,
    "min_names": 20,
    "weight_bounds": [0.0, 0.15],
    "hhi_cap": 0.15,
    "alpha_winsor_sigma": 3.0,
    "beta_target_baseline": 0.90,
    "beta_target_tier": {
      "HIGH": [1.00, 1.05],
      "MEDIUM": [0.90, 1.00],
      "LOW": [0.80, 0.90]
    },
    "gamma_beta_default": 0.5,
    "gamma_beta_mode": "soft",
    "alpha_divergence_filter": 0.80,
    "alpha_divergence_filter_rationale": "unique_alpha/n >= 0.80 강제. L-195a fix."
  }
}
```

## 리스크

- β 0.90 상향 → drawdown 확대 위험 (2008/2020 stress 재검증 필요)
- α-divergence filter → 유효 universe 축소 가능 (liquidity 하한 2e8 충족 종목 부족 위험)
- Multi-sleeve 복잡도 ↑ → 구현 버그 위험

## Success Criteria (Pilot 8 Path A)

- **MUST**: Forge Full SR ≥ 0.40 + Active IR ≥ -0.8
- **TARGET**: Forge Full SR ≥ 0.50 + Active IR ≥ -0.5
- **BREAKTHROUGH**: Active IR ≥ -0.3 + PG1 candidate 자격

Phase 3 Replication 완료 후 본 DRAFT → FINAL 확정.
