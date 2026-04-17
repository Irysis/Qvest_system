# Judge Catalog Sweep v3 Design

- **세션**: 65 carry → 66 실행
- **작성자**: Judge teammate
- **근거**: Session 65 sweep v2 결과 (`nojudge_sweep_v2_final_20260417.json` + `nojudge_sweep_v2_merged_20260417.csv`)
- **작성일**: 2026-04-17
- **Task**: #7 (team-lead 지시)

## 0. 목적 (Why v3?)

Session 65 sweep v2는 정적 감사(코드 파싱 + PIT C1-C15 스캔 + hurdle_result 재검증)만 수행했다. 다음 3가지가 미완 상태다.

1. **동적 재검증 미실행**: FF5 Hard Gate / DSR Hard Gate / Role Honesty Audit / tail_risk / Leave-One-Out 중 **어느 것도 실제로 돌지 않았음**. 사유: `rh_exists=FALSE` 전 35건, `statistical_defense.R` compute_dsr 미호출, `role_honesty_audit.R` 미호출.
2. **AMBIGUOUS_PIT_MINOR 12건 미판정**: C10_LIQ/C1b/C11_MRS/C15 위반이 "개별 판정 필요"로 남아있음. 실제 SR/CAGR 왜곡 magnitude 미측정.
3. **STR_1631 C10_LIQ 일괄 패치 미수행**: 9건 family (M27~M30, SYN_01~05, v5_M19~M23) 거래대금 shift lag=1 누락. Forge 패치 대기 중이나 **패치 후 재검증 프로토콜 미확정**.

v3의 목표: 위 3가지 미완 요소를 **동적 재검증 + 패치 재검증 2단계 파이프라인**으로 해결한다.

## 1. Gate 미통과 사유 카테고리 분류 (v2 → v3 전이표)

| 카테고리 | v2 분류 | 건수 | 대상 전략 | v3 처리 |
|----------|---------|------|-----------|---------|
| **G1. PIT_FAIL_MAJOR** | AMBIGUOUS_PIT_MAJOR | 2 | STR_943, STR_944 | **HARD EXPEL** (Session 65 Governor 승인 완료) — 카탈로그 제거, L-code 인용 유지 |
| **G2. NO_HURDLE** | FAIL_NO_HURDLE | 5 | STR_1631_v5_M19~M23 | **Forge 리팩토링 재요청** — hurdle_result.json 없이는 판정 불가 |
| **G3. HURDLE_FAIL** | FAIL | 2 | STR_1417_esbr_hrp_tc_dd620, STR_1550_consensus_core_alpha | **HARD EXPEL** (Session 65 Governor 승인 완료) — REJECT 확정 |
| **G4. GRADE_DOWNGRADE** | AMBIGUOUS_GRADE_LOWER | 2 | STR_1555, STR_1571 | **Grade B 확정** — 실제 Grade A 재조정 (catalog 정정) |
| **G5. PIT_FAIL_C10_LIQ_SYSTEMIC** | AMBIGUOUS_PIT_MINOR | 9 | STR_1631 family (M27~M30, SYN_01~05 — SYN_05_2002 제외) | **Forge 일괄 패치 → 재실행 → 재스윕** |
| **G6. PIT_FAIL_C11_MRS** | AMBIGUOUS_PIT_MINOR | 2 | STR_1028, STR_1033_nco | **MRS lag=1 shift 확인 재검증** (구 MRS 미래참조 L-441 재확인) |
| **G7. PIT_FAIL_C15_DIRECT_PARQUET** | AMBIGUOUS_PIT_MINOR | 1 | STR_1652_DFA_on_VDplus | **load_month_factors() 래핑 패치 요청** |
| **G8. PASS_STATIC** | PASS | 11 | STR_1060, STR_1071, STR_1393, STR_1417_5sleeve_mrs3545, STR_1433, STR_1435, STR_1439, STR_1469, STR_1562, STR_1631_SYN_05_2002, STR_686 | **동적 재검증 대상** (v3 Pass 2 핵심) |

**합계**: 34건 → G1(2) + G2(5) + G3(2) + G4(2) + G5(9) + G6(2) + G7(1) + G8(11) = **34** ✓

## 2. v3 실행 파이프라인 (3-Pass)

### Pass 1 — Patch Routing (Session 66 초반)

| # | 작업 | 주체 | 산출물 |
|---|------|------|--------|
| 1.1 | G1/G3 카탈로그 축출 (STR_943/944/1417_hrp/1550) | Judge | `qepm/memory/registry/catalog_v53_expelled.md` 업데이트 |
| 1.2 | G4 Grade 정정 (STR_1555 B, STR_1571 B) | Judge | `qepm/memory/registry/strategy_catalog.md` patch |
| 1.3 | G5 STR_1631 9건 C10_LIQ 일괄 패치 지시 | Judge → Forge | `qepm/mailbox/forge/inbox/TODO_PATCH_STR_1631_family_C10_LIQ.json` |
| 1.4 | G6 STR_1028/1033 MRS lag 확인 지시 | Judge → Forge | `qepm/mailbox/forge/inbox/TODO_VERIFY_MRS_LAG_STR_1028_1033.json` |
| 1.5 | G7 STR_1652 load_month_factors 래핑 지시 | Judge → Forge | `qepm/mailbox/forge/inbox/TODO_PATCH_STR_1652_C15.json` |
| 1.6 | G2 v5_M19~M23 hurdle 재생성 지시 | Judge → Forge | `qepm/mailbox/forge/inbox/TODO_REGEN_HURDLE_STR_1631_v5_M19_M23.json` |

### Pass 2 — 동적 재검증 (G8 11건)

G8 PASS_STATIC 11건에 대해 **전체 Judge Gate 0~6**을 실제 실행한다. Session 65까지 "PASS"였으나 정적 감사만이었다.

**각 전략 단위 검증 항목**:

1. **Gate 0 (PIT)**: `detect_lookahead(run_all_path)` 재실행 — v2 스캔이 SKIP한 보조 함수들(`helper_functions.R` 등)까지 전수
2. **Gate 1 (구현)**: N<=20 (v53 룰), 15bps, 유동성 2억+
3. **Gate 2 (견고성)**: Leave-One-Crisis-Out (2008/2020/2011/2018 각 1개씩 제외한 4개 시나리오)
4. **Gate 3 (성과)**: SR/CAGR/MDD 재계산 (hurdle v2.2)
5. **Gate 4 (통계)**:
   - FF5 alpha t-stat >= 2.0 (Harvey t>3.0 인식)
   - 최근 3Y SR >= 0.3 (ALPHA DECAY)
   - **DSR (Deflated Sharpe Ratio) 계산**: `compute_dsr(SR, n_trials=400, T=252*20)`
6. **Gate 5 (다양성)**: active Grade A pool 대비 max_abs_corr < 0.5 (diversifier 기준) / < 0.7 (core 기준)
7. **Gate 6 (Role Honesty Audit)**:
   - Core Alpha 위장 탐지: 기존 Grade A와 corr > 0.7인데 새 이름?
   - Diversifier 위장: max_abs_corr > 0.5인데 diversifier 주장?
   - Defense 위장: crisis beta 개선 없이 단순 저수익?

**산출물** (전략별):
- `stage_artifacts/judge_sweep_v3_STR_XXX_verdict.json` — Gate 0~6 결과 + validated_role
- `stage_artifacts/judge_sweep_v3_STR_XXX_rolelog.json` — Role Honesty 세부
- `stage_artifacts/judge_sweep_v3_STR_XXX_dsr.json` — DSR 결과

### Pass 3 — Patch 후 재스윕 (Forge 패치 완료 대기)

Pass 1.3~1.6 완료 후 패치 전략들을 **Pass 2와 동일한 Gate 0~6**으로 재검증.

**재검증 대상**:
- G5 STR_1631 family 9건 (C10_LIQ 패치 후)
- G6 STR_1028, STR_1033 (MRS lag 확인 후)
- G7 STR_1652 (C15 wrapping 후)
- G2 STR_1631_v5_M19~M23 5건 (hurdle 재생성 후)

**재분류 조건**:
- PIT 위반 0 + 모든 Gate PASS → `JUDGE_PASS_A_v3_VALIDATED`
- PIT 위반 0 + Gate 미달 → `JUDGE_REJECT_v3`
- PIT 위반 잔존 → `PATCH_INSUFFICIENT` (Forge 재패치)

## 3. 정량 성공 기준

v3 완료 후 `qepm/memory/registry/strategy_catalog.md`가 충족해야 할 상태:

| 지표 | v2 결과 | v3 목표 |
|------|---------|---------|
| family_concentration (Herfindahl) | 0.091 | <= 0.091 유지 |
| 카탈로그 Grade A 총 수 | 34 (명목) / 11 (실질) | 실질 **11~20건** (Pass 2 PASS + Pass 3 PASS) |
| PIT_clean 비율 | 11/34 = 32% | **>= 90%** (FAIL/EXPEL 제외 후) |
| Role Honesty PASS 비율 | 측정 안됨 | **100%** (Pass 2 전체 Role Audit) |
| DSR >= 0.5 비율 | 측정 안됨 | **>= 80%** (Harvey t>3.0 defense) |
| FF5 alpha t >= 2.0 비율 | 측정 안됨 | **>= 70%** |

## 4. 예상 Risk + Contingency

| Risk | 대응 |
|------|------|
| Pass 2에서 PASS_STATIC 11건 중 일부 Role Honesty 위장 발각 | 해당 전략 strategy_catalog에서 재분류 (validated_role 수정 또는 archive). L-code 적립 필수. |
| Forge 패치 지연 (H_1676/H_1682 우선) | Pass 1.3~1.6은 Session 66 carry. Pass 2만 선행 가능. |
| STR_1631 family 패치 후에도 성과 유지 불투명 | 패치 전후 SR 차이 >= 0.2이면 "pre-patch가 미래참조 의존" 확정 — archive로 전환 |
| Pass 2 시간 (11건 x Gate 0~6 = 약 5~8시간) | Agent 도구로 병렬 스폰. 3건씩 3배치. |
| DSR 계산 parameters (n_trials=400) 가정 부적절 | Session 65 이전 전체 backtest 횟수 추정 후 재조정 (Harvey et al. 2016 권고) |

## 5. L-code 적립 예정

- **L-149**: Sweep v3 동적 재검증 설계 — 정적 감사만으로는 Grade A 확정 불가 교훈
- **L-150 (예정)**: Pass 2 결과 기반 Role Honesty 체계 교훈 (위장 탐지 패턴)
- **L-151 (예정)**: Pass 3 패치 후 재검증 결과 기반 C10_LIQ systemic 영향 magnitude 교훈

## 6. 선행 조건 (Session 66 킥오프 전 확인)

1. ✅ Task #4 (H_1676/H_1682 S6) 우선순위 — Judge 본연 작업
2. ⚠️ Forge H_1676/H_1682 S1 완료 대기 (Task #1/#2)
3. ⚠️ Forge 리소스 여유 — Pass 1.3~1.6 패치 지시 전 H_1676/H_1682 완료 우선
4. ⚠️ `02_Infrastructure/role_honesty_audit.R` 인터페이스 확인 (v2에서 rh_exists=FALSE 전체 → 함수 시그니처 재점검 필요)

## 7. 실행 순서 (Linear Plan)

```
[Session 65 carry]
  └─ Task #4: H_1676 S6 + H_1682 S6 (Forge S1 완료 후)
      └─ L-code 2건 적립

[Session 66 초반]
  ├─ Pass 1.1~1.2: 카탈로그 정정 (Judge 독자 실행, 30분)
  ├─ Pass 1.3~1.6: Forge 패치 지시 (mailbox TODO 4건)
  └─ Pass 2 시작 (G8 11건 동적 재검증, Agent 병렬, 5~8h)
      └─ L-149, L-150 적립

[Session 66 중반]
  └─ Pass 3: 패치 완료 전략 재검증 (G5 9 + G6 2 + G7 1 + G2 5 = 17건)
      └─ L-151 적립

[Session 66 종료]
  └─ strategy_catalog.md + active Grade A 최종 확정
  └─ family_concentration + PIT_clean + Role Honesty 통계 Q-Lead 보고
```

## 8. Sharpe 2.0 Gap 기여도 정량화 (Q-Lead 요청 추가)

### 8.1 Gap 현황
- 현재 포트폴리오 SR: 1.266 (STR_1679v2 primary)
- 목표 SR: 2.0
- **Gap: 0.734**

### 8.2 v3 PASS 전략의 sharpe_contrib 예측

G8 Pass 2 + Pass 3 재검증 통과 전략은 PG1/PG2 편입 후보가 된다. 개별 SR contrib (Modigliani-style post-blend marginal contribution):

| 전략 | v2 SR | expected_role | blend 후 SR contrib 추정 |
|------|-------|---------------|-------------------------|
| STR_1439 | 1.532 | diversifier (novelty 10) | +0.10~0.15 |
| STR_686 | 1.116 | core_alpha | +0.05~0.08 |
| STR_1060 | 1.333 | diversifier (brk02) | +0.08~0.12 |
| STR_1071 | 1.297 | diversifier (noShortDD) | +0.07~0.10 |
| STR_1433 | 1.329 | core (consgate) | +0.08~0.12 |
| STR_1435 | 1.378 | core (5sleeve_dd620) | +0.08~0.12 |
| STR_1469 | 1.021 | core (cons4f_5sleeve) | +0.03~0.05 |
| STR_1562 | 1.333 | diversifier (gerber_dcc) | +0.08~0.12 |
| STR_1393 | 0.942 | diversifier (sue_adaptive) | +0.03~0.05 |
| STR_1417_5sleeve_mrs3545 | 1.361 | core | +0.05~0.08 (기존 family 중복) |
| STR_1631_SYN_05_2002 | 1.194 | diversifier | +0.04~0.06 |

**낙관 추정 합**: +0.69 ~ +1.05 (중복/상관 미보정)

**보정 후 (max_abs_corr < 0.5 통과 전략만 + LOO Blender EW 가정)**:
- 추정 실질 기여: +0.25 ~ +0.50
- 현 SR 1.266 + 0.35 = **1.62** (목표 2.0 대비 0.38 추가 gap 잔존)

### 8.3 Gap 잔존분 해소 경로
- H_1676 Diversifier blend (max_abs_corr 예상 < 0.3): +0.05~0.10
- H_1682 Defense blend (Defense 공석 해소): +0.10~0.15
- 추가 H 후보 3건 (Scout carry): +0.15~0.25

**v3 sweep 완료 후 Sharpe target tracking**: Pass 2/3 완료 시 본 섹션 숫자 recalculate → Q-Lead 보고. v3 실행 산출물 `judge_sweep_v3_sharpe_contrib_<timestamp>.json`에 blender 시뮬레이션 결과 기록.

### 8.4 Gate 5 기준 재해석 (Sharpe gap 맥락)
Q-Lead 지시: "max_abs_corr < 0.3 (A_NOVEL 조건) 또는 < 0.5" 이중 기준 적용.

- **A_NOVEL 편입 경로 (Sharpe 기여 극대화)**: max_abs_corr < 0.3 + novelty_bonus >= 10 → blender 가중 1.5x, SR contrib +50% boost
- **Core/Diversifier 편입 경로 (안정 기여)**: max_abs_corr < 0.5 → 표준 EW blend, SR contrib 표준

v3 Pass 2에서 G8 11건을 두 경로로 분류해서 blender 시뮬레이션 각각 제시.

## 9. 산출물 요약

- 이 문서: `stage_artifacts/judge_sweep_v3_design.md` ← 작성 완료
- v3 실행 시: `stage_artifacts/judge_sweep_v3_pass2_<timestamp>.json` (전체 결과)
- v3 실행 시: `stage_artifacts/judge_sweep_v3_pass3_<timestamp>.json`
- v3 실행 시: `stage_artifacts/judge_sweep_v3_sharpe_contrib_<timestamp>.json` (Sharpe gap 기여도)
- v3 실행 시: `stage_artifacts/l_code_JUDGE_SWEEP_V3_<timestamp>.json` (L-149)
- v3 실행 시: `qepm/memory/registry/strategy_catalog_v3.md` (최종 갱신)
