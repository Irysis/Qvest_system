# QEPM Red Flag Rules — 3-Agent 자동 경고 체계

각 agent가 Work Task 실행 중 자동 탐지해야 하는 Red Flag. `red_flag_detector.sh` Hook이 PostToolUse[Write]에서 자동 적용.

## Alpha Agent Red Flags

### RF-A1: 논문 단독 근거 (Severity: HIGH)
- **조건**: `factor_specs[*].references` 개수 ≤ 2 && subperiod_stability < 0.5
- **대응**: challenge_flags += "논문 단독 근거. 자사 유니버스 재현 필요"
- **조치**: Alpha Agent가 KR 실증 재검증 필수

### RF-A2: Composite vs Baseline 불명 (Severity: MEDIUM)
- **조건**: K ≥ 3 (composite) && `diagnostics.post_neutralization_ic` < `baseline_single_ic` * 1.05
- **대응**: challenge_flags += "Composite 개선 미미 (+<5%)"
- **조치**: Single proxy baseline으로 축소 또는 composite 재설계

### RF-A3: 최근 3년만 성과 (Severity: HIGH)
- **조건**: `diagnostics.subperiod_stability < 0.4` && `diagnostics.recent_3y_icir > overall_icir * 1.5`
- **대응**: challenge_flags += "Recent 3Y over-fit 의심"
- **조치**: Alpha Agent STOP (Rule 1). Extended period 재검증.

### RF-A4: Sector-neutral 후 붕괴 (Severity: HIGH)
- **조건**: `diagnostics.post_neutralization_ic < 0.3 * diagnostics.rank_ic`
- **대응**: challenge_flags += "Sector effect 의존, 알파 손실 70%+"
- **조치**: Alpha Agent STOP. 팩터 설계 재검토.

### RF-A5: Top decile illiquid (Severity: MEDIUM)
- **조건**: `top_decile_liquidity_pass_rate < 0.5`
- **대응**: challenge_flags += "상위 종목 유동성 부족, 실행 불가"
- **조치**: Universe 제약 재평가

## Risk Agent Red Flags

### RF-R1: 섹터 집중 (Severity: HIGH)
- **조건**: `risk_summary.top_common_risks[0] pct > 0.40`
- **대응**: challenge_flags += "섹터 40%+ 집중, 분산 부족"
- **조치**: Optimizer에 sector_active_weight_cap 강제

### RF-R2: Covariance ill-conditioned (Severity: HIGH)
- **조건**: `diagnostics.condition_number > 500`
- **대응**: Risk Agent 자동 shrinkage 재추정 (Ledoit-Wolf → Gerber-RMT)
- **조치**: 해결 실패 시 Rule 2 STOP

### RF-R3: Crowding severe (Severity: MEDIUM)
- **조건**: `risk_summary.crowding_flags` 존재 (any severity "severe")
- **대응**: challenge_flags += "Crowding 공모기관 집중"
- **조치**: Optimizer capacity_limits 축소

### RF-R4: Stress loss 정책 초과 (Severity: HIGH)
- **조건**: `stress_tests.market_down_5 < -0.08` (정책 -8%)
- **대응**: challenge_flags += "Market -5% 시 -8%+ 손실 예상"
- **조치**: Risk Agent Rule 2 STOP 또는 tail hedge 필수

### RF-R5: Style 중복 (Severity: MEDIUM)
- **조건**: 팩터 간 상관 > 0.8 의 pair 개수 ≥ 2
- **대응**: challenge_flags += "Style 중복, 독립 팩터 감소"
- **조치**: Alpha에 challenge_note (팩터 pair 재설계)

## Optimizer Agent Red Flags

### RF-O1: Top alpha 미실현 (Severity: HIGH)
- **조건**: `binding_constraints 개수 ≥ K * 0.5` (팩터 수 절반 이상이 제약에 묶임)
- **대응**: challenge_flags += "제약 너무 타이트, 알파 반영 실패"
- **조치**: Alpha에 challenge_note + hard_constraints 재평가

### RF-O2: 낮은 순알파 (Severity: HIGH)
- **조건**: `expected_active_return < estimated_cost * 2`
- **대응**: challenge_flags += "순알파 비용 대비 부족"
- **조치**: HOLD 권고 (Rule 3)

### RF-O3: 미세 리밸런싱 과다 (Severity: MEDIUM)
- **조건**: `turnover < 0.02` (월간 2% 미만)
- **대응**: challenge_flags += "미세 리밸런싱, 의미 없는 거래"
- **조치**: No-trade region 확대

### RF-O4: Constraint 민감도 폭발 (Severity: HIGH)
- **조건**: sensitivity_report에 dual variable 급증 (>1000)
- **대응**: challenge_flags += "제약 너무 binding, 해 불안정"
- **조치**: Soft penalty로 완화 or infeasibility_report

### RF-O5: 종목수 위반 (Severity: CRITICAL — Hook block)
- **조건**: `length(target_weights) > 20`
- **대응**: **Hook hard block** (`worktask_constraint_enforcer.sh`)
- **조치**: Optimizer Agent 재실행

### RF-O6: Σw ≠ 1 / active Σ ≠ 0 (Severity: CRITICAL — Hook block)
- **조건**: `|sum(target_weights) - 1| > 0.001`
- **대응**: Hook hard block
- **조치**: Optimizer Agent 재실행

### RF-O7: Weight bounds 위반 (Severity: CRITICAL — Hook block)
- **조건**: `any(target_weights < 0 || target_weights > 0.20)`
- **대응**: Hook hard block
- **조치**: Optimizer Agent 재실행

## 전역 Red Flags (Q-Lead 레벨)

### RF-G1: Work Task 순서 위반 (Severity: CRITICAL — Hook block)
- **조건**: Risk Agent spawn 전에 alpha_package 없음
- **대응**: `worktask_sequence_enforcer.sh` hard block
- **조치**: Alpha Agent 먼저 실행

### RF-G2: Silent override 시도 (Severity: CRITICAL — Hook block)
- **조건**: Risk Agent가 alpha_vector 파일 쓰기 시도
- **대응**: `agent_role_guard.sh` hard block
- **조치**: challenge_note로 변경 요청

### RF-G3: Schema 불일치 (Severity: HIGH — warn)
- **조건**: package JSON 필수 필드 누락
- **대응**: `worktask_artifact_validator.sh` warn + Q-Lead 알림
- **조치**: Agent 재실행

## Severity 정책

| Severity | 대응 |
|---|---|
| **CRITICAL** | Hook hard block (Level 3). 실행 불가. |
| **HIGH** | challenge_flags 자동 주입 + Q-Lead 긴급 알림 + Telegram 경고 |
| **MEDIUM** | challenge_flags 자동 주입 + log 기록 |
| **LOW** | log 기록만 |

## 자동 탐지 구현

`02_Infrastructure/hooks/red_flag_detector.sh` (PostToolUse[Write]):
- 3 package JSON 저장 시 자동 scan
- Red Flag 감지 시 해당 package에 `challenge_flags` 자동 추가
- CRITICAL은 사전 차단 (별도 `worktask_constraint_enforcer.sh`)
- HIGH/MEDIUM은 사후 기록 + 알림

## Version

- **v1.0** — 2026-04-23 Session 69 Day 1 — 초기 Red Flag 규칙
- 신규 Red Flag 추가 시 L-code 발행 (L-code가 실패 패턴 축적)
