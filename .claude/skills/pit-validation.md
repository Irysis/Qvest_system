---
name: pit-validation
description: "PIT 규칙 적용 — C1~C15, pit_engine_v3 blocking_gate(수동 호출), 합리화 표현 탐지, detect_lookahead(.R + .py). ⚠ 자동 차단 훅(forge_code_guard)은 2026-05-16 DEPRECATED — 정적 스캔은 백테 전 수동 실행 의무."
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

### PIT Engine v3 — 수동 게이트 (자동 차단 아님 — 2026-07-03 정정)

⚠️ **구 문구 "`forge_code_guard.sh`가 Rscript 실행 직전 자동 차단"은 사실이 아니다.**
- `forge_code_guard.sh`는 **2026-05-16 DEPRECATED** (`_archive_v55/` Tier 1 cleanup 삭제 — `00_Lawbook/DEPRECATION.md`, `02_Infrastructure/docs/rules/harness.md` Hook 정합 audit). `.claude/settings.json`에 미등록 (doc 주석에만 잔존).
- `pit_v3_daemon.sh`는 FS retain이나 호출자(forge_code_guard)가 사라져 **배선 끊김** (harness.md: "헬퍼/비-hook" 분류).
- 따라서 **PIT Engine v3 blocking_gate는 현재 수동 호출로만 작동한다.** 백테 실행 전 forge/Q-Lead가 아래 수동 호출을 직접 실행할 의무.

**실제 자동 방어선 (settings.json 등록 hook — 이것이 전부)**:
| Hook | 이벤트 | 검사 내용 |
|------|--------|-----------|
| `factor_rotation_pit_guard.sh` | PreToolUse | FR 모드 Cycle50 shift / `prod`·`cumprod` 자체합성 (advisory) |
| `axiom_enforcement_hook.sh` | PreToolUse[W/E] | AX-001 일부 block, AX-002~005 advisory |
| `backtest_contract_audit.sh` | PreToolUse[Write] | registry/L-code 등재 시 `audit_status=FAIL` 차단 |
| `selection_contamination_detector.sh` | PreToolUse | 정규 리서치 lockbox 차단 |

위 hook들은 **run_all.R의 lookahead 코드 자체를 실행 직전에 스캔하지 않는다** — 정적 스캔(detect_lookahead / pit_engine_v3 / pit_ast_scanner)은 수동 실행이 유일한 경로.

**수동 호출 (백테 전 의무)**:
```r
source("02_Infrastructure/validation/pit_engine_v3.R")
r <- pit_engine_v3$blocking_gate("04_Research/strategies/STR_XXX",
                                 levels = c("static", "ast"),
                                 include_intent = FALSE)
# r$clean / r$severity (CLEAN / SUSPICIOUS / VIOLATION) / r$violations / r$reports
```

**우회 env**: `QVEST_SKIP_PIT_V3=1` (긴급 시만, 로그 남음 — 수동 게이트 경로에만 유효).

**4개 스캐너**:
- `scan_static` — 정규식 기반 (lookahead_detector.R — .R + .py 지원, 2026-07-03)
- `scan_ast` — R AST 분석 (pit_ast_scanner.R)
- `scan_intent` — Codex LLM 의도 해석 (pit_intent_scanner.R, opt-in — v8.2 Codex 제거로 사실상 휴면)
- `scan_runtime` — FACTORS vs PLOG Exec_Date 비교

### 금지 합리화 표현 탐지 (2026-07-03 정정 — 자동 격리 아님)

⚠️ 구 문구 "`artifact_validator.sh`가 자동 스캔 + `.p2b_violation` 자동 격리(rename)"는 stale — `artifact_validator.sh`는 ARCHIVED(`_archive_v55/`, worktask_artifact_validator로 rename됐으나 후자는 phrase 스캔을 하지 않음). 자동 rename 격리 메커니즘은 현재 없다.

**실제 활성 탐지 (둘 다 soft — block 아님)**:
- `rationalization_detector.sh` (PostToolUse[Write/Edit]) — challenge_note / verdict / admission 파일 한정, KR/EN phrase 라이브러리 매칭 → warn (3회+ escalate)
- `answer_principles_grep.sh` (PostToolUse) — 회피 표현 soft alert

**금지 표현 (규율은 유지 — 탐지가 soft일 뿐 위반은 AX-002 동급)**:
"영향 미미", "관행적 허용", "보수적이면 괜찮다", "대부분 결과 동일",
"이미 반영되어 있었을 것", "백테스트 기간이 충분히 길어서 상쇄",
"실무적으로 유의미", "이 정도면 괜찮다",
"대체로 동일", "무시할 수 있는", "무시 가능한 수준"

**탐지 시**: warn 수신 즉시 증거(숫자/테스트/논문) 기반 문장으로 재작성. hook이 막아주지 않으므로 자기 규율이 1차 방어선.

### 기타 자동 검출

```r
source("02_Infrastructure/validation/lookahead_detector.R")
# C1~C11 패턴 자동 스캔 (.R) + PY_* 패턴 (.py — shift(-N)/merge_asof forward/full-sample fit 등)
detect_lookahead("04_Research/strategies/STR_XXX/run_all.R")
detect_lookahead("02_Infrastructure/ml_pipeline/some_model.py")

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
