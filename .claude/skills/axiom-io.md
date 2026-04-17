---
name: axiom-io
description: "Axiom 엔진 I/O — v53 L-code → AX-code 승격 파이프라인. harvester/cluster/promote/inject/review/dashboard + sg_read_axiom_signals, sg_axiom_lcode_trace, QVEST_AXIOM_AUTO_INJECT env."
---
## Axiom 엔진 (v53 Sprint 4 L-code → AX-code 승격 엔진)

퀀트 리서치 산출물(L-code)을 AX-code로 승격하는 메타 학습 엔진.
승격된 AX-code는 qvest 모든 행위의 대전제로 기능 (CLAUDE.md + 6 prompts 자동 주입).

### 4-Layer 파이프라인

```
stage_artifacts/l_code_*.json (primary)
    ↓
[L1 Harvester] python3 02_Infrastructure/axiom/lcode_harvester.py
    → .cache/lcode_corpus.json
    ↓
[L2 Cluster] python3 02_Infrastructure/axiom/cluster_extractor.py
    → qepm/memory/axioms/candidates/CAND_*.json (empirical/methodological × positive/conditional/negative)
    ↓
[L3 Promoter] Rscript 02_Infrastructure/axiom/promote.R <candidate>
    → 5축 검증 (I/R/F/E/M) 가중 0.80+ 통과 시 active/AX-XXX.json
    ↓
[L4 Injector] Rscript 02_Infrastructure/axiom/inject.R <axiom>
    → CLAUDE.md ## Axioms + 6 prompts <!-- AXIOM_INJECT --> 자동 편집
```

자동 트리거: artifact_validator.sh가 `l_code_*.json` Write 감지 시 Harvester + Cluster 백그라운드 실행.

### Signal 읽기 (Scout S0 전 필수)
```r
source("02_Infrastructure/memory/axiom_memory_interface.R")
signals <- sg_read_axiom_signals("all")                 # 4종 전체
signals <- sg_read_axiom_signals("reuse_penalty")       # 실패 factor 조합 (30일 쿨다운)
signals <- sg_read_axiom_signals("family_cooldown")     # 포화 family (14일)
signals <- sg_read_axiom_signals("failure_cluster")     # 공통 실패 패턴
signals <- sg_read_axiom_signals("method_fatigue")      # 과사용 방법론 (90일)
```

### 역추적 (AX ↔ L-code)
```r
# AX-003 → 근거 L-code 목록
sg_axiom_lcode_trace(axiom_id = "AX-003")
# → $supporting_l_codes = c("L-132", "L-135")

# L-132 → 승격된 AX
sg_axiom_lcode_trace(l_code = "L-132")
# → $promoted_to_axiom = "AX-003"
```

### L-code 쓰기 (Judge S7 완료 후)
```r
sg_write_axiom_result("lesson", list(
  strategy_id = "STR_XXX", grade = "A",
  lesson = "핵심 교훈",
  is_failure = FALSE,
  family = "quality_earnings",
  factors_used = c("Q07", "D29")
), strategy_id = "STR_XXX")
# is_failure=TRUE면 failure_cluster + reuse_penalty 자동 등록
```

### 승격 실행 (수동 또는 axiom_weekly.sh)
```r
source("02_Infrastructure/axiom/promote.R")
r <- promote_to_axiom("qepm/memory/axioms/candidates/CAND_XXX.json")
# r$passed TRUE면 active/ 이동 + L-code 역링크 + auto-inject (QVEST_AXIOM_AUTO_INJECT=1)
# r$passed FALSE면 review_log/AX-PENDING_*.json에 5축 점수 기록
```

### Inject (CLAUDE.md + prompts)
```bash
# dry-run (diff만 출력)
QVEST_AXIOM_AUTO_INJECT=0 Rscript 02_Infrastructure/axiom/inject.R qepm/memory/axioms/active/AX-003.json
# real write
QVEST_AXIOM_AUTO_INJECT=1 Rscript 02_Infrastructure/axiom/inject.R qepm/memory/axioms/active/AX-003.json
```
diff 저장: `.cache/axiom_inject_<AX>_<ts>.diff` (roll-back 가능).

### Review (분기 또는 수시)
```r
source("02_Infrastructure/axiom/review.R")
review_axiom("AX-003")            # 단건 — OOS 열화 + 반증 증거 체크
review_all_active_axioms()        # 전체
# 실패 시 deprecated/로 이동 + CLAUDE.md 제거 + L-code 역링크 클리어
```

### Dashboard
```r
source("qepm/R/axiom_dashboard.R")
axiom_status()
# active/candidates/review_log/deprecated 카운트 + 최근 이벤트
```

### 자동화 스케줄 (cron)
```
# 주 1회 월요일 03:00
0 3 * * 1 bash 02_Infrastructure/ops/axiom_weekly.sh
# 분기 1회
0 4 1 */3 * bash 02_Infrastructure/ops/axiom_quarterly.sh
```

### IMMUTABLE 3건 (정적, review 대상 제외)
- **AX-000**: "한계란 없다" (방법론)
- **AX-001**: "Defense는 조건부 성과로 평가" (방법론)
- **AX-002**: "규칙 안에서 찾아낸 성과가 진짜 성과" (방법론)

### 현재 승격된 실증 axiom (2026-04-17)
- **AX-003** (empirical/negative): "한국시장 value factor standalone long-only 지속적 실패" — L-132 EP standalone + L-135 BCSNA 근거. 5축 weighted 0.823.

### qvest 모든 행위에 주입되는 경로
1. `unified_agent_guard.sh` → Agent 스폰 시 active AX 전체를 additionalContext로
2. `axiom_enforcement_hook.sh` → 동적 AX.enforcement regex Write/Edit block
3. `hurdle_gate.R` D075 → AX 범위 내 반대 결과 suspicion_flag + -5점 + strict 강등
4. CLAUDE.md `## Axioms` + 6 prompts `<!-- AXIOM_INJECT -->` (inject.R 자동)

### R0~R7 파이프라인
R0(raw) → R1(distill) → R2(family) → R3(evidence) → R4(regime) → R5(policy) → R6(post-trade) → **R7(axiom)**
