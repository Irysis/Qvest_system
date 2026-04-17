---
name: pit-validation
description: "PIT 규칙 적용 — C1~C15, pit_engine_v3 blocking_gate, 금지 합리화 표현 격리(P2-B), detect_lookahead. forge_code_guard가 Rscript 실행 직전 자동 차단."
---
## PIT (Point-in-Time) Enforcement

### C1~C15 체크리스트
| 코드 | 규칙 | 위반 예 |
|------|------|---------|
| C1 | full-sample 통계 금지 → rolling/expanding만 | `mean(전체)` |
| C2 | same-day circular 금지 → t-1 lag | `today_signal → today_trade` |
| C3 | 같은 기간 집계→적용 금지 | |
| C4 | 재무제표 래깅 (연간→5월, 분기→45일) | |
| C5 | overlay t-1 기준 | |
| C9 | DD/VT/FM lag: `c(0, dd_pct[-n])` / `c(vol[1], head(vol,-1))` | |
| C11 | 데이터 시간축 검증 (FRED 시차 등) | |
| C13 | Z_Score_Aligned만. 수동 방향 반전 금지. | |
| C14 | IC: Usable_Date <= sig_date | |
| C15 | Factor DB: load_month_factors() 경유 | |
| C16 | 조합 폭발 금지 (grid search iter≥50 penalty) | |

### PIT Engine v3 자동 차단 (v53 Sprint 2.1 + Sprint 3 P0-A)

`forge_code_guard.sh` (PreToolUse[Bash])가 `Rscript ... run_all.R` 실행 직전 자동 호출.

**작동**:
1. Codex PIT Review flag (`/tmp/codex_pit_approved_<STR>.flag`) 확인 → 없으면 block
2. run_all.R + factor_engine.R 내용 md5 해시 기반 캐시 (`/tmp/pit_v3_clean_<STR>_<hash>.flag`)
3. 캐시 없으면 `pit_engine_v3$blocking_gate(strategy_dir, levels=c("static","ast"))` 호출
4. CLEAN 아니면 **block** + 상위 5개 위반 reason 포함

**수동 호출**:
```r
source("02_Infrastructure/validation/pit_engine_v3.R")
r <- pit_engine_v3$blocking_gate("04_Research/strategies/STR_XXX",
                                 levels = c("static", "ast"),
                                 include_intent = FALSE)
# r$clean / r$severity (CLEAN / SUSPICIOUS / VIOLATION) / r$violations / r$reports
```

**우회 env**: `QVEST_SKIP_PIT_V3=1` (긴급 시만, 로그 남음).

**4개 스캐너**:
- `scan_static` — 정규식 기반 (lookahead_detector.R)
- `scan_ast` — R AST 분석 (pit_ast_scanner.R)
- `scan_intent` — Codex LLM 의도 해석 (pit_intent_scanner.R, opt-in)
- `scan_runtime` — FACTORS vs PLOG Exec_Date 비교

### 금지 합리화 표현 (P2-B 자동 격리)

`artifact_validator.sh`가 `stage_artifacts/*.json` Write 시 자동 스캔.

**금지 표현 11종**:
"영향 미미", "관행적 허용", "보수적이면 괜찮다", "대부분 결과 동일",
"이미 반영되어 있었을 것", "백테스트 기간이 충분히 길어서 상쇄",
"실무적으로 유의미", "이 정도면 괜찮다",
"대체로 동일", "무시할 수 있는", "무시 가능한 수준"

**탐지 시**:
- 파일을 `<path>.p2b_violation`으로 격리 (자동 rename)
- Write hook block 리턴 → Claude가 증거 기반 재작성 요구받음

**복구**: `.p2b_violation` 접미사 제거 후 재작성. 증거(숫자/테스트/논문) 기반 문장으로.

### 기타 자동 검출

```r
source("02_Infrastructure/validation/lookahead_detector.R")
# C1~C11 패턴 자동 스캔
detect_lookahead("04_Research/strategies/STR_XXX/run_all.R")

source("02_Infrastructure/validation/pit_ast_scanner.R")
pit_ast_scan("04_Research/strategies/STR_XXX")  # AST 기반 간접 호출 탐지
```

### 핵심 3질문 (매 데이터 접근 전)
1. "이 데이터는 의사결정 시점에 알 수 있었는가?"
2. "이후 결과가 판단에 영향을 미치지 않는가?"
3. "'괜찮다'고 느끼는 이유가 결과를 이미 알기 때문은 아닌가?"

### 위반 시 프로토콜
1. 즉시 중단 → 결과 무효
2. 연쇄 오염 범위 파악 (hurdle_result 전수 재스캔)
3. lookahead 제거 후 재실행
4. 도훈에게 텔레그램 보고 + L-code 기록

### Env 변수 요약
| 변수 | 효과 |
|------|------|
| `QVEST_SKIP_PIT_V3=1` | PIT Engine v3 blocking_gate 우회 |
| `QVEST_STRICT_MODE=TRUE` (기본) | hurdle_gate D074 DSR/FF5 Hard Gate 활성 |
| `QVEST_ALLOW_STALE_DB=1` | Factor DB 30일 초과 block 우회 (P3-A) |
