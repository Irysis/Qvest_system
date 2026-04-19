# v55 Consensus Addendum — S0 Debate + Role Taxonomy + 3 Trail + GAP 4축

**적용 일자**: 2026-04-19
**적용 대상**: Scout / Forge / Judge / Governor / Codex Critic + 5인 S0 Debater 전원
**대체 규칙**: v54 점수 기반 판정 (threshold 70 / BORDERLINE 60-69 구간) → Consensus 기반 판정 전면 이행

---

## 1. S0 Debate: 점수제 폐지 → Consensus 기반

### 이유
- 점수 산술합(20×5=100) = 허위 정량화 (비교 불가능한 단위 합산)
- 60-69 BORDERLINE 재설계 루프 (conversion 18.75% 고정)
- Codex empirical gate 상시 요구 → 8/20 고정 → 전체 점수 65점 천장
- AX-001 철학(단일 숫자 평가 금지)과 정면 충돌

### 새 스키마 (v55)

**R1 Opening** (5인 병렬, 독립):
```json
{
  "role": "risk_manager | academic | quant | governor | codex_critic",
  "stance": "APPROVE | APPROVE_CONDITIONAL | REVISE | REJECT",
  "critical_concerns": ["핵심 문제 1", "핵심 문제 2"],
  "supporting_arguments": ["지지 근거 1", "지지 근거 2"],
  "veto_flag": null | "tail_risk" | "mechanism" | "PIT" | "kr_empirical_hard_fail" | "admission_rule" | "gap_misaligned",
  "s1_gate_items": ["S1에서 실측 필요한 empirical 항목"]
}
```

**R2 Rebuttal** (R1 전부 읽고):
```json
{
  "role": "...",
  "stance_change": "UNCHANGED | UPGRADED | DOWNGRADED",
  "new_stance": "APPROVE | APPROVE_CONDITIONAL | REVISE | REJECT",
  "addressed_concerns": ["R1에서 제기된 이슈 중 해결됨"],
  "unresolved": ["끝까지 풀리지 않는 논점"],
  "veto_flag_updated": "null | ..."
}
```

**R3 Consensus (자동 집계, router가 수행)**:
```
4+ APPROVE       → APPROVE (S1 즉시 dispatch)
3+ REJECT        → REJECT (archive)
veto 2+ 동의      → REVISE (Codex 제외. 도메인별 REJECT 가능)
3+ APPROVE/COND && REJECT<=1 → APPROVE_CONDITIONAL (unresolved → S1 gate)
그 외            → REVISE
```

**Consensus Tag**: UNANIMOUS / MAJORITY / MINORITY / DEADLOCK 자동 라벨링.

### Veto 도메인 권한 매트릭스

| Debater | Veto dimension |
|---------|----------------|
| Risk Manager | `tail_risk` / EVT 위반 |
| Academic | `mechanism` 논리 결함 |
| Quant | `PIT` 설계 결함 / `kr_empirical_hard_fail` |
| Governor | `admission_rule` 위반 / family saturation / **`gap_misaligned`** |
| Codex Critic | **flag만** (veto 권한 없음). empirical gate 항목은 **s1_gate_items**로 이동 |

### Codex Critic 재정의
- **점수 없음** (stance만 표명)
- **Veto 권한 없음** (flag만, 집계 시 2+ 동의 필요)
- **empirical 항목 금지**: walk-forward, IC-to-Return coupling, beta stability 등은 S0 scope 밖 → `s1_gate_items`로 이동
- **"논문 없음" flag 제거**: ML / 통계적 발견 / KR-original 가설 허용
- 역할: cross-model diversity + PIT 설계 결함 + 메커니즘 논리 + kill scenario

---

## 2. Role Taxonomy 6종 (기존 3 → 6)

| Role | 설명 | GAP 타깃 |
|------|------|---------|
| `core_alpha` | 주 수익원 (기존) | SR/CAGR |
| `diversifier` | 저상관 보조 수익원 (기존) | SR 분산 효과 |
| `defense` | 위기 alpha + MDD 완화 (기존, **AX-001 조건부**) | MDD_regime |
| `cash_allocation` | Regime-conditional 현금 (신규) | cash_efficiency |
| `regime_adaptive` | 국면별 가중 변경이 alpha 자체 (신규) | MDD_regime / SR |
| `ml_predictive` | ML/DL 기반 예측 (신규, **empirical-first**) | SR / KR_structural |

**필수 필드** (s0_record):
- `expected_role` — 6종 enum 중 하나 (**unknown 금지**, `artifact_validator.sh` BLOCK)
- `expected_role_rationale` — 50자+ (왜 이 role인가)

---

## 3. 3-Trail (학술 vs 통계 vs ML)

| Trail | 조건 | S0 허들 | S1 허들 |
|-------|------|---------|---------|
| `standard` | 학술 메커니즘 기반 | 논문 1편+ 필요 | 기존 C1~C15 + ICIR≥0.20 |
| `ml_empirical_first` | ML/DL | 학술 근거 **권장만** (Codex "논문 없음" flag 제외) | SR_OOS/SR_IS>0.70, feature concentration<0.4, holdout 12M+ |
| `kr_statistical` | KR-original 통계 발견 | 경제적 설명 시도 의무 | Harvey t>3.0 + DSR + FDR 다중검정 |

**필수 필드**: s0_record에 `trail` 명시 (누락 시 artifact_validator WARN).

**Trail 전파**: s0_record → s1_construction → … → s6_validation (모든 stage artifact에 `trail` 필드 전파).

---

## 4. GAP Targeting 4축

현재 포트폴리오 상태 (2026-04-19):
- Sharpe 1.193 / 목표 2.0 → **gap 0.807** (유일한 수치 gap)
- CAGR 16.14% ✅
- MDD -21.27% ✅

**4축 정의**:
```
SR               — Sharpe ratio 개선 (단순 수치)
MDD_regime       — 위기 구간 MDD 완화
KR_structural    — 한국시장 구조 특성 (외국인/재벌/환율/정책)
cash_efficiency  — 무비용 drawdown 제거 (cash sleeve)
```

**필수 필드** (s0_record):
- `gap_targeting_axes` — 배열, 4축 중 1+ 선택 (누락 시 BLOCK)

**Governor gap_misaligned veto**: 신규 전략 role이 현재 GAP을 직접 해소하지 않으면 veto. 예: Core_alpha 가설 제안이지만 현재 Core 포화 상태 → veto 발동 가능.

---

## 5. AX-001 v2 — Defense 조건부 평가

**기존**: 전기간 SR/CAGR/MDD로 Defense 평가 → 항상 Grade F (AX-005 standalone 실패)

**v55**: Defense는 **multi-sleeve 내에서만** 평가:
```
Condition 1: multi_sleeve_only = TRUE (single-sleeve standalone 금지)
Condition 2: crisis_alpha > 0 (6대 위기 구간 alpha 측정)
Condition 3: bad/normal IC ratio > 0.6 (regime-conditional IC 비대칭)
Condition 4: Core 대비 MDD 완화 (partial drawdown reduction)
```

Judge S6 Gate 추가:
- `role_honesty_audit.crisis_alpha_test` = PASS/FAIL
- Defense role에서 FAIL이면 REVISE (Grade F 자동 아님)

---

## 6. Admission Rule v3.5.2 — Role-Specific Thresholds

**v54 Freeze 호환**: 기존 hard fail(MDD>45%, TO>600%) 유지 + "확장(addition)" 프레이밍

| Role | Threshold |
|------|-----------|
| Core alpha | SR>0.8, CAGR>16%, MDD<45%, FF5 alpha t>2.0 |
| Diversifier | max_corr<0.50, div_benefit>0, IC>0.015 |
| Defense (AX-001 v2) | multi-sleeve only, crisis_alpha>0, bad/normal IC ratio>0.6 |
| Cash_allocation | tail_risk=0, opportunity_cost<20bps vs 3M rates |
| Regime_adaptive | switching_alpha>0.10, transition_cost<50bps, stability>0.60 |
| ML_predictive | SR_OOS/SR_IS>0.70, feature concentration<0.4, holdout 12M+ |

**Sequential Admission TDC**: 5-sleeve pair의 pairwise TDC<0.30 (crisis 기준, L-156 v2).

---

## 7. 하위 호환 규칙

- 기존 s0_record에 `expected_role` 필드만 있으면 → 유지 (6종 중 한 값으로 재분류하지 않음)
- 기존 S0_VERDICT에 `score_breakdown` 있으면 → Consensus 모드 비활성, legacy 점수 기반 라우팅 (WARN 로그)
- 구 artifact는 `_archive/` 이동 권장, 삭제 금지 (참조 유지)
- 새 artifact부터 v55 스키마 강제

---

## 8. 참조 파일

- `02_Infrastructure/hooks/s0_verdict_router.sh` — Consensus 집계 구현
- `02_Infrastructure/hooks/artifact_validator.sh` — s0_record 필드 검증
- `.claude/skills/s0-debate/SKILL.md` — 3-Round 흐름 (R1 스키마에 stance 추가)
- `02_Infrastructure/prompts/scout_init.md` — 6종 role / 3 trail / GAP 4축 가이드
- `02_Infrastructure/prompts/governor_init.md` — gap_misaligned veto + 5-sleeve 배분
- `02_Infrastructure/prompts/judge_init.md` — AX-001 v2 + Role Honesty 6종 + consensus_stance
- `00_Lawbook/admission_rule_v352.md` — Role threshold 세부 (Tier 2.3 작성 예정)
