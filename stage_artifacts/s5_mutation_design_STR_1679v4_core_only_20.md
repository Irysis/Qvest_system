# STR_1679v4 Core-Only 20 Mutation 설계 — Scout

**버전**: draft v1 (2026-04-17)  
**의존**: Governor 옵션 1 수용 + STR_1679v2 Gate 수리 완료 후 activation  
**관계**: STR_1679v2 (Core 15 + Def 5) vs **STR_1679v4 (Core 20 순수)** A/B 실험

## 배경

Judge S6 Full Audit (2026-04-17):
- STR_1679v2 Primary HRP+DD Grade A 77.1
- **honest_role = core_alpha_with_overlay_dependency** 공식
- Def sleeve 실질 기여 **0.3pp** (Role Misalignment)
- MDD 축소 22.54pp 전적으로 Layer 3 overlay 기여

Governor 시나리오 3개 검토:
- **옵션 1 (Core 20 순수화)** Scout 수용 (이 문서)
- 옵션 2 (H_1682 흡수) 기각 (Governor 자체)
- 옵션 3 (다층 Defense) 기각 (복잡도 > 가치)
- **옵션 4 (Role 재라벨링)**: STR_1679v2 병행 유지 (별도 조치)

## STR_1679v4 Core-Only 20 설계

### 구조
- **Core sleeve 단일**: C19 Top 20 (ICIR weighted 또는 EW)
- Def sleeve **완전 제거**
- Layer 3 overlay 유지 (DD 6/20 + inverse ETF + cash)
- Regime weight 유지 (Normal 100% Core, Crisis 감속 — overlay 담당)

### STR_1679v2 vs STR_1679v4 비교

| 항목 | STR_1679v2 | STR_1679v4 |
|---|---|---|
| N_CORE | 15 | 20 |
| N_DEF | 5 | 0 |
| N_HOLD | 20 | 20 |
| Core selection | C19 Top 15 | C19 Top 20 |
| Defense factor | Q07 80% + D29 20% | 없음 |
| Regime weight | 95/5 → 80/20 → 60/40 | 100% Core (weight 조정 없음) |
| Overlay | HRP + DD 6/20 + Layer 3 | HRP + DD 6/20 + Layer 3 |
| Role | core_alpha_with_overlay_dependency (Judge) | **core_alpha_pure** (명확) |
| 복잡도 | 중 | 낮음 |

### 성과 예측

**STR_1679v2 baseline (3 variant)**:
- Primary HRP+DD: SR 1.266, MDD -29.06%, CAGR 24.71% ✅ Grade A
- HRP base (no overlay): SR 1.152, MDD -51.6%, Grade C
- EW base (no overlay): SR 1.097, MDD -53.54%, Grade C

**STR_1679v4 예상**:
- **Primary HRP+DD + Core 20**: SR 1.25~1.30 (STR_1679v2 Primary ± 0.05 범위 내)
- Def sleeve 5종목 제거 → per-stock weight 5% → 5% (동일), alpha 기여 Core 15→20 확장 대체 효과
- L-143 Q07+D29 0.3pp 기여 손실 vs C19 Top 15→20 확장 이득: **net ≈ 0 또는 소폭 positive** 예상
- MDD: 29% ± 3% (overlay 지배)

### 핵심 가설
**"STR_1679v2 Def sleeve 5종목 = structural noise"** 검증:
- 만약 STR_1679v4 SR ≥ STR_1679v2 → Def sleeve 제거 정당
- 만약 STR_1679v4 SR < STR_1679v2 -0.05 → Def sleeve 실제 0.3pp 이상 기여 (Judge audit 수정)

### PIT Compliance
STR_1679v2와 동일 원칙 (C1~C15, L-484, L-557 모두 유지)

## Forge Implementation Plan

### 최소 수정 사항 (run_all.R 기반)
1. `N_CORE <- 15L` → `N_CORE <- 20L`
2. `N_DEFENSE <- 5L` → `N_DEFENSE <- 0L`
3. Core selection: `head(sc, N_CORE)` → `head(sc, 20L)`
4. Def sleeve merge 로직 전부 제거 (blend_dt 단순화)
5. Regime weight 로직 유지하나 w_def 항상 0 — effective 단일 Core
6. `n_core_dominant` = 20 (항상)
7. Buffer zone `list(keep_n = 22, entry_n = 20)`

### Rename / Version
- 디렉토리: `04_Research/strategies/STR_1679v4_core_only_20/`
- STRATEGY_ID: `STR_1679v4`
- STRATEGY_NAME: `Core_Only_20_Overlay_Reference`
- 기존 STR_1679_score_blend 디렉토리 유지 (v2 Primary Grade A 실증 기록)

## A/B 실험 목적

### STR_1679v2 vs STR_1679v4 비교 측정
- **primary_overlay SR 차이**: ±0.05 범위 내 → Def sleeve structural noise 확정
- **MDD 차이**: ±3%p 범위 내 → overlay 지배 확정
- **honest_role**: v4는 "core_alpha_pure" 명확화 (Role Misalignment 원천 해소)
- **Turnover**: v4 sleeve 경계 없이 단일 → transition 단순화

### Portfolio-level 영향
- PG2 선택: STR_1679v2 or STR_1679v4 중 1건만 편입 (중복 회피)
- Scout 권고: **SR drift ≤ 0.05 이내면 STR_1679v4 선호** (role honesty 확보 + 단순성)

## 검증 Gate

1. Primary SR ≥ 1.20 (STR_1679v2 대비 drift 허용)
2. MDD < 35% (DD overlay 기여 유지 확인)
3. FF5 alpha t > 2.0 (Core 확장 alpha 유지)
4. Role Honesty = PASS (Def sleeve 없이 core_alpha_pure 선언)
5. Judge Gate 0-6 재심사 PASS

## AX / L-code Compliance

- AX-003 value 무관 ✅
- AX-004 quality_profitability 무관 ✅
- AX-005 defense (Q07+D25/BAB) 무관 ✅
- L-143 Q07+D29 drag **회피** (Q07/D29 미사용)
- L-146 Overlay-driven MDD ≠ Core alpha **직접 수용** (core_alpha_pure 라벨)
- L-484 20종목 준수 ✅
- L-557 sleeve 차별화 **N/A** (단일 sleeve)

## Activation Condition

1. STR_1679v2 Gate 수리 완료 (sg_init + tail_risk + DSR + 3 variant 백테)
2. Judge 재심사 STR_1679v2 PASS 확정
3. H_1682 Forge S1 실행 (선제 또는 병렬)
4. Q-Lead 승인 → Scout → Forge TODO 작성 → Forge 구현

## Timeline

- **Week 1 (Session 66)**: STR_1679v2 Gate 수리 완료
- **Week 2**: STR_1679v4 Forge 구현 + 백테스트
- **Week 3**: Judge Gate 0-6 재심사 + Scout S3
- **Week 4**: Governor PG1 admission 심사 (STR_1679v2 vs v4 선택)

## Scout 최종 권고

**STR_1679v4는 STR_1679v2와 병행 실험**:
- STR_1679v2 = 현 Grade A 77.1 실증 기록 보존
- STR_1679v4 = Role honesty 명확 + 단순 구조 실증
- A/B 결과 기반 Governor PG1 최종 선택
- H_1682 Defense anchor는 **독립 유지** (STR_1679v2 Def sleeve 흡수 금지)

## 옵션 3 (다층 Defense) 기각 근거

Scout 분석:
- STR_1679v2 Def sleeve 교체 factor 후보:
  - Q25+R16 (H_1682와 동일, 중복)
  - Regime-conditional (후보 B) — STR_1417/H_1675 이미 실패
  - CDaR path-dependent (후보 D) — H_1662 REJECTED (AX-005)
- → 모든 후보가 기존 실패 또는 H_1682 중복
- 다층 Defense의 실질 효과 불명, 복잡도 증가
- **drop 권고**

---

**작성**: Scout, 2026-04-17  
**상태**: draft v1 — Governor 검토 + Q-Lead 승인 후 Forge 구현
