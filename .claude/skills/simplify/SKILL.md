---
name: simplify
description: QEPM 3-Agent 아키텍처 인식 코드 검토 + 간소화. Alpha/Risk/Optimizer 역할 경계 침범 검토, 25종 hard/long-only/Σw=1 제약 확인, PIT C1~C15 준수. Factor engine에 cov/weight 있으면 경고.
---

# /simplify — QEPM 3-Agent Architecture-Aware Code Review

변경된 코드를 검토하고 간소화. **QEPM 3-Agent 역할 경계** + **Hard Constraints** + **PIT** 자동 체크.

## Usage

```
/simplify                  # git diff 대상 자동 검토
/simplify {file_path}      # 특정 파일 검토
```

## 3-Agent Architecture Awareness

리뷰 대상이 아래 중 하나면 **추가 검증**:

### Alpha Agent 코드 (factor_engine.R / alpha_research_*.R)
체크 항목:
- ✗ 역할 침범 금지:
  - `cov(` / `solve.QP(` / `weights` 결정 로직 **없어야**
  - `hrp_` / `mvo_` / `cvar_` 방법론 호출 **없어야**
- ✓ Z_Score_Aligned 사용 (C13)
- ✓ load_month_factors() 경유 (C15) 또는 L-164 v1.1 carve-out 명시
- ✓ alpha_package.json 스키마 준수 (alpha_vector / confidence_vector / factor_specs / diagnostics)
- ✓ expanding / rolling window only (C1)
- ✓ shift(, 1L) 명시적 t-1 lag (C5, C10)

### Risk Agent 코드 (risk_research_*.R / covariance_cache.R)
체크 항목:
- ✗ 역할 침범 금지:
  - alpha score 생성 로직 **없어야**
  - weight 계산 / 종목 rank **없어야**
- ✓ Σ = BΩB' + D 분리 구조
- ✓ shrinkage 조건부 적용 (condition number > 500)
- ✓ risk_package.json 스키마 (exposure_matrix_ref / factor_covariance_ref / specific_risk_ref / stress_tests)

### Optimizer Agent 코드 (optimizer_research_*.R / mean_variance_optimizer.R)
체크 항목:
- ✗ 역할 침범 금지:
  - alpha 재계산 **없어야**
  - cov 재추정 **없어야**
- ✓ objective function = `x'α - λ/2 x'Σx - φ·TC(x)`
- ✓ Σw=1 (active 기준 Σw=0) enforcement
- ✓ infeasibility_report 로직 (조용한 제약 완화 금지)
- ✓ method_comparison 기록 (여러 방법론 비교)

### Forge run_all.R (WT 통합 경로)
체크 항목:
- ✗ alpha / risk / weight 계산 로직 **없어야** (통합만)
- ✓ load_alpha_package() / load_risk_package() / load_optimization_package() 3-step
- ✓ 25종 hard constraint final check
- ✓ PIT lookahead_detector.R 호출

## Hard Constraints 검증 (사용자 강제)

모든 코드에서 확인:
- **max_names 25** 적용 여부 (Optimizer + Forge)
- **long-only** (weights ≥ 0)
- **weight_bounds [0, 0.20]**
- **liquidity_min 2e8** (LIQ_THRESHOLD)
- **transaction_cost 15bps** (cost_model_version 준수)
- **universe** (KOSPI200 ∪ KOSDAQ150)

## PIT C1~C15 자동 체크

**금지 합리화 표현 탐지**:
- "영향 미미" / "관행적 허용" / "보수적이면 괜찮다" / "대부분 결과 동일"
- "이미 반영되어 있었을 것" / "백테스트 기간이 충분히 길어서 상쇄"

**패턴 탐지**:
- C1: `cov(full_sample)`, `mean(full_sample)` — full-sample 통계
- C2: `fwd_ret` + `Date == sig_date` — same-day circular
- C10: `frollmean(Size, 20L)` without `shift(, 1L)` — 당일 유동성
- C13: `NEGATE_FACTORS` / `FLIP_SIGN` — 수동 방향 반전
- C14: `IC` 접근 시 `Usable_Date` 필터 없음
- C15: `open_dataset()` + factor parquet 직접 — `load_month_factors()` 미경유

## 출력 포맷

```markdown
## /simplify 결과

**파일**: {file_path}
**Agent 역할**: Alpha / Risk / Optimizer / Forge / 기타

### 🔴 역할 경계 위반 (Critical)
- Line N: {violation}

### 🟡 Hard Constraints 경고
- Line N: {constraint} 미적용

### 🟠 PIT 위반 (High)
- Line N: C{rule} 위반 {pattern}

### 🟢 Simplification 제안
- Line N: {redundancy} → {simpler_alternative}
```

## 자동 Trigger

PR 생성 / commit 전 자동 실행 권장:
```
/simplify
```

위반 발견 시 fix 후 재검토.

## 예외 처리

- **L-164 v1.1 carve-out**: consensus parquet / daily factor DB ML 전략은 C15 예외
- **Smoke test 전략**: h_smoke_v55 같은 테스트는 일부 constraint skip 허용
- **Legacy 전략**: `04_Research/strategies/STR_*/` 기존 전략은 read-only 검토만
