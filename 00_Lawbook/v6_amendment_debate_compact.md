# V6 Lawbook Amendment — S0 Debate Compact Mode (5→3인)

**Status**: **APPROVED** (2026-04-19, Session 68 Day 2, 도훈 명시 승인)
**Proposed Date**: 2026-04-19
**Approved Date**: 2026-04-19
**Amendment Scope**: V6 Lawbook §S0 Debate + `.claude/skills/s0-debate/SKILL.md` + 4 hooks
**상위 규칙**: v55 Consensus Addendum (유지) / AX-000~AX-005 (무변경) / PIT C1~C15 (무변경)

## Open Questions 답변 (승인 시점 결정)
1. **3인 구성**: Q-Lead가 매번 가설 유형에 따라 Judge/Governor 중 선택 (유연성 우선). 선택 기록은 `stage_artifacts/s0_judge_or_governor_{H_ID}.md` 1줄.
2. **Shadow mode**: **5회** 합격 기준 (verdict 일치율 ≥80%, veto 누락 0건).
3. **Fact-check Hook 실패 fallback**: LLM Academic·Quant 1회 스폰 복구. Hook 실패 원인을 `stage_artifacts/factcheck_fallback_{H_ID}.log` 기록.
4. **스키마**: v55 stance/veto 스키마 그대로 유지 (3인도 동일 사용).

---

## 1. 개정 배경

### 1.1 문제 진단 (Session 68 Day 2 Token Audit)
- **S0 Debate 1회 = 19,685 tokens** (Opus 4.7 기준)
  - 5인 Opus 동시 스폰 (Risk / Governor / Quant / Academic / Codex)
  - R2 Rebuttal에서 R1 transcript 1.5K를 5인에게 재주입 = 7,500T 단일 라운드
  - R3 Closing 조건 충족 시 추가 ×2~3인 재스폰
  - Init prompts 5종 누적 + v55 Consensus JSON 오버헤드

### 1.2 실증 근거
- **Codex Critic**: cross-model 독립성 확보 (GPT-5.4, ChatGPT OAuth, Claude 토큰 0)
- **Risk Manager**: tail_risk veto 도메인 — L13 Risk Engine 전담, 필수
- **Judge/Governor**: admission_rule + gap_misaligned veto — 포트폴리오 적합성 전담
- **Academic**: 논문 타당성 검증 — **대부분 fact-check 수준** (DOI 확인, FF5 존재 검증, 인용 실존)
- **Quant**: ICIR/Z_Score/FF5 roll-forward — **대부분 rule-based 계산**

→ Academic·Quant는 LLM 토론보다 **자동 fact-check Hook**으로 대체 시 품질 저하 없이 토큰 절감.

### 1.3 설계 원칙
- **Cross-check 약화 금지**: 3인 = Codex(외부) + Risk(통계) + Judge(PIT/admission). 3개 독립 관점 유지.
- **Academic·Quant → Rule-based Hook**: 정량적·사실확인 작업은 LLM 불요. Hook으로 대체 + 결과를 3인 debaters 참고 자료로 주입.
- **Shadow mode 5회 검증 의무**: 기존 5인 vs 신규 3인 verdict 일치율 ≥80% 달성 후에만 본격 전환.

---

## 2. 개정 조문

### §S0.1 Debater 구성 (5인 → 3인)

**기존** (v55 유지):
```
5인 debate = Codex Critic + Risk Manager + Governor + Quant + Academic
```

**개정**:
```
3인 debate = Codex Critic + Risk Manager + Judge(또는 Governor — 가설 유형에 따라)
+ Academic Fact-Check Hook (자동)
+ Quant Fact-Check Hook (자동)
```

**3인 역할 분담**:
| Debater | Role | Veto 도메인 | Model |
|---------|------|-------------|-------|
| Codex Critic | External cross-model (GPT-5.4) | 없음 (flag만) | GPT-5.4 (OAuth, 토큰 0) |
| Risk Manager | tail_risk + kill_scenarios + regime | `tail_risk` | Opus 4.7 |
| Judge / Governor | PIT + admission + gap + family | `PIT` / `admission_rule` / `gap_misaligned` | Opus 4.7 / Sonnet 4.6 |

**Judge vs Governor 선택 규칙**:
- **Judge 우선**: 가설이 신규 factor/mutation 도입이거나 PIT 경계 판단 필요 → Judge (Opus)
- **Governor 우선**: 가설이 기존 family 교체/admission 중심 → Governor (Sonnet)
- 판단이 모호하면 Q-Lead가 S0 스폰 직전에 선택. 선택 이유를 `stage_artifacts/s0_judge_or_governor_{H_ID}.md`에 1줄 기록.

### §S0.2 Academic Fact-Check Hook

**신규 파일**: `02_Infrastructure/hooks/academic_factcheck.sh` (향후 구현, Block H 범위)

**기능**:
1. Scout plan의 `core_reference` DOI/arXiv ID 추출
2. 로컬 캐시(`01_Literature/Korea_Research/` + arXiv metadata cache) 조회
3. 존재 여부 확인 → `{exists: true/false, title: "...", year: XXXX, cite_count: N}` 반환
4. 한국 실증 관련 L-code(`methodology_active.md`) 매칭 → `{matched_lcodes: [L-160, L-161, ...]}`
5. 결과를 `stage_artifacts/academic_factcheck_{H_ID}.json`에 저장

**3인 debaters에 주입**: R1 스폰 프롬프트에 fact-check JSON을 첨부. LLM이 이를 근거로 평가.

### §S0.3 Quant Fact-Check Hook

**신규 파일**: `02_Infrastructure/hooks/quant_factcheck.sh`

**기능**:
1. Scout plan의 factors 추출 → Factor DB 존재 확인 (`load_month_factors()` 대리)
2. ICIR 10Y 자동 계산 (Rscript `stage_gate_engine.R::sg_quick_icir()`)
3. `.cache/conditional_ic_matrix.csv` 조회 → KR IC sign/hit rate
4. `methodology_active.md` VALIDATED_HARD_FAIL 패턴 매칭 → `kr_empirical_check: hard_fail_match|partial|confirmed|no_data`
5. 결과를 `stage_artifacts/quant_factcheck_{H_ID}.json`에 저장

**3인 debaters에 주입**: R1 스폰 프롬프트에 fact-check JSON을 첨부.

### §S0.4 R3 Closing 생략 조건

**기존** (v55 유지):
```
R3 = R2에서 stance 변동 또는 score delta > 4점 있을 때 재소환
```

**개정 (Compact Mode)**:
```
R3 생략 조건 (둘 다 만족):
1. R2 stance 3/3 일치 (UNCHANGED 또는 동일 new_stance)
2. veto_flag 변동 없음
→ 즉시 VERDICT_READY (consensus_tier: strong)

R3 진입 조건 (하나라도 만족):
1. R2 stance 이견 (2/3 또는 1/2/... 분산)
2. veto_flag 신규 발생 또는 철회
→ R3 Closing 필수
```

**enforcer 변경**:
- `s0_debate_enforcer.sh` 상태 머신에 `R2_COMPLETE → VERDICT_READY` 직접 전이 조건 추가 (기존은 R3 거쳐야 함)

### §S0.5 Cache 정책

- Codex Critic verdict는 `hash(SCOUT_PLAN + L_CODE_FINDINGS + FAILED_STRATEGIES + AXIOM_SIG)` 기반 `.cache/codex_verdicts/` 저장 (Block F 구현 완료, 본 amendment에서 공식화)
- REVISE 재토론 시 hypothesis content 변경 → hash miss → Codex 재호출 + 캐시 갱신
- 동일 가설 cross-check 시 cache hit → Claude 토큰만 수신 (~500T)

### §S0.6 예상 토큰 절감

| 항목 | Before (v55 5인) | After (v6 3인 Compact) | 절감 |
|------|------------------|------------------------|------|
| R1 Opening | 5인 × init+scoring ≈ 7,500T | 3인 × 2,500T ≈ 7,500T + fact-check 500T | 유사 |
| R2 Rebuttal | 5인 × (transcript 1.5K + rebuttal) ≈ 7,500T | 3인 × (R1 요약 300T + rebuttal) ≈ 2,400T | **-68%** |
| R3 Closing | 조건부 2~3인 ≈ 2,000T | 대부분 생략 (strong consensus) | **-85%** |
| Codex R2 Verify | 2,000T (외부 비용 0, Claude 수신 2,000T) | 500T (jq 요약) | **-75%** |
| Init prompts | 5인 누적 1,258T | 3인 1,000T (Judge 1회 + Risk 1회 + Codex prompt 1회) | -20% |
| **총 1회 Debate** | **~19,685T** | **~6,000T** | **-70%** |

---

## 3. Shadow Mode 검증 프로토콜

### 3.1 진행 방식
- Amendment 도훈 승인 → shadow mode 5회 debate
- 매 debate마다 **5인(기존) + 3인(신규) 병렬 실행**. 5인 verdict을 공식 사용, 3인은 비교용.
- 결과 비교 기록: `stage_artifacts/s0_shadow_comparison_{H_ID}.json`
  ```json
  {
    "hypothesis_id": "...",
    "5p_verdict": "APPROVE",
    "3p_verdict": "APPROVE",
    "stance_match": true,
    "veto_match": true,
    "match_rate": 1.0,
    "divergence_reason": null
  }
  ```

### 3.2 합격 기준
- 5회 debate에서:
  - **verdict 일치율 ≥ 80% (4/5 이상)**
  - **veto 누락 0건** (3인이 5인 대비 veto를 놓치지 않음)
  - **critical_concerns recall ≥ 70%** (5인이 제기한 주요 concern 중 3인이 최소 70% 커버)
- 미달 시: amendment 재수정 + 추가 shadow 5회

### 3.3 정식 전환 후 fallback
- 3인 debate 중 verdict 모호 시 (예: 1/1/1 분산): **자동으로 5인 debate로 escalation**
- Q-Lead가 "escalate_to_5p: true" flag 설정 시 즉시 Academic/Quant LLM 스폰 복구

---

## 4. Hook 변경 요약 (Block H 구현 시)

| 파일 | 변경 |
|------|------|
| `s0_debate_guard.sh` | 3인 최소 debater 검증 (Codex + Risk + (Judge\|Governor)) |
| `s0_debate_enforcer.sh` | 5→3인 state machine + R3 생략 조건 + fact-check hook 자동 실행 |
| `s0_verdict_router.sh` | `debaters` 배열 3인 허용 (기존 5인 강제 해제) |
| `academic_factcheck.sh` | **신규** — DOI + 한국 실증 L-code 매칭 |
| `quant_factcheck.sh` | **신규** — ICIR + KR IC sign + hard_fail_match |

---

## 5. 승인 절차

1. 본 draft를 도훈이 검토
2. 승인 시: `00_Lawbook/v6_amendment_debate_compact.md` 상태를 `DRAFT` → `APPROVED`로 변경, 승인 일자 기록
3. `00_Lawbook/v55_consensus_addendum.md` §1.6 "5인 → 3인 전환 가능" 조항 추가
4. Shadow mode 5회 실행 → 합격 시 정식 전환
5. 정식 전환 후 `CLAUDE.md`의 "## S0 Debate 5인 독립 토론 강제" 섹션을 "3인 Compact Mode" 기반으로 개정 (v6 amendment 공식 반영)

---

## 6. 제약 (Level 0 — 개정 시에도 절대 위반 금지)

- PIT C1~C15 검증 로직 0% 변경
- AX-000~AX-005 강제 로직 0% 변경
- Stage Gate 순서 (S0→S1→S2→S3→S4→S5→S6→S7→PG0~PG3) 무변경
- Judge의 veto 권한은 통합 단계에서 `Judge OR Governor` 선택 시에도 **Judge 우선 적용 가능**
- Codex Critic의 cross-model 독립성(GPT-5.4) 절대 유지
- Risk Manager의 `tail_risk` veto 절대 유지

---

## 7. Open Questions (도훈 결정 필요)

1. **3인 구성**: Codex + Risk + (Judge 또는 Governor) 선택을 Q-Lead가 매번 판단할지, vs 가설 유형별 고정 규칙으로 강제할지?
2. **Shadow mode 기간**: 5회로 충분한지, 10회 이상 권장?
3. **Academic·Quant fact-check Hook 실패 시**: fallback으로 LLM Academic·Quant를 1회 스폰할지, 또는 Codex에 해당 task 위임할지?
4. **기존 v55 stance/veto 스키마 유지**: 그대로 3인도 동일 스키마 사용 (권장) vs. 3인용 별도 스키마 신설?

---

**본 amendment는 `ExitPlanMode` 이후 도훈 명시 승인 (예: "amendment approve") 전에는 배포·적용 금지.**
Block H (Hook 실제 구현 + shadow mode 5회)는 승인 이후에만 진행.
