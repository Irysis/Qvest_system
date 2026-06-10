# Lockbox / Frozen Alpha Scope (Level 0)

**도훈 mandate 2026-05-09**:
> "Frozen 규칙 리서치 정규 프로세스에만 적용. 전기간 백테스팅, 성과 트래킹 등 정규 리서치 외에선 Frozen 폐기"

## 정책 요약

Frozen alpha (lockbox / SIGNAL_CUTOFF / signal_lockbox) 적용 범위 명확화:

| 단계 | Lockbox 적용 | 이유 |
|---|---|---|
| **alpha-research** | ✅ 적용 | PIT lookahead bias 방지 (alpha 산출 시 future return 사용 금지) |
| **risk-research** | ✅ 적용 | Σ 추정 시 lockbox 외부 reuse 방지 |
| **optimizer-research** | ✅ 적용 | 가중치 결정 시 lockbox 외부 데이터 사용 금지 |
| **judge** | ✅ 접근 가능 (audit 기록) | 단독 lockbox 검증 권한 |
| **forge** | ❌ **폐기** (도훈 mandate) | 전기간 백테 / 운용 백테 / monitoring backtest = 최신 sig_date까지 사용 |
| **monitoring** | ❌ **폐기** | 라이브 성과 트래킹 / drift 감지 = 최신 데이터 의무 |
| **execution** | ❌ **폐기** | 주문 schedule = 최신 weights 의무 |
| **Q-Lead** | ❌ **폐기** | 집계 보고 / 도훈 mandate 응답 = 최신 sig_date 의무 |

## Why

1. **정규 리서치 (alpha / risk / optimizer)** — alpha 신호 산출이 본질. 미래 정보 사용 시 lookahead bias → backtest invalid. **Lockbox 정합 의무**.

2. **운용 / 트래킹 (forge / monitoring / execution / Q-Lead)** — 이미 admit된 alpha를 활용해 백테 / 트래킹 / 주문. 최신 sig_date까지 자동 갱신이 본질. **Lockbox 폐기 정합**.

3. **도훈 명시 사례 (2026-05-09)**:
   - "1715 패밀리 alpha_scores 2026-04까지 갱신해줘" → lockbox 해제 + 2024-01 ~ 2026-04 sig_dates 추가 산출
   - "PG2 수익률 트래킹해주고 벤치마크랑 비교해줘" → 5월 라이브 트래킹 (lockbox 무관)
   - "전기간 백테스팅" 5종 family 256m+OOS → forge 단계 lockbox 폐기

## How to apply

### 정규 리서치 단계 (alpha / risk / optimizer)

- `SIGNAL_CUTOFF` hardcoded: 예 `as.Date("2023-12-22")` retain
- factor_engine_proposal.R 등 alpha-research driver는 cutoff 정합
- lockbox 내 `evaluation_windows.lockbox_window` 외부 sig_date 산출 금지

### 운용 / 트래킹 단계 (forge / monitoring / Q-Lead)

- alpha_scores.parquet **최신 sig_date까지 자동 사용**
- SIGNAL_CUTOFF 동적 산출: `max(sig_date)` 또는 `current_month - 1`
- 운용 진단 / 백테 / 트래킹 시 lockbox 해제

### Hook 강제

`02_Infrastructure/hooks/selection_contamination_detector.sh` (PreToolUse[Read]):
- alpha / risk / optimizer / opt_ → **block** (정규 리서치 lockbox 접근 차단)
- judge / forge / monitoring / execution → **allow + audit log**
- Q-Lead / unidentified → allow (default)

## Lockbox Sealing 정책 (judge_post_seal)

`02_Infrastructure/hooks/lockbox_post_judge_seal.sh` (PostToolUse[Write] judge_verdict):
- Judge verdict 저장 시 `lockbox_sealed.json` flag
- 재접근 시 warn + 사유 기록 (post-hoc selection bias 방지)
- 본 정책은 정규 리서치 cycle 내 lockbox 봉인용 — 운용 단계 무관

## R 코드 정합 패턴

### 정규 리서치 (alpha-research) — 예: factor_engine_proposal.R

```r
SIGNAL_CUTOFF <- as.Date("2023-12-22")  # PIT lockbox cutoff
sig_dates <- sig_dates[sig_dates <= SIGNAL_CUTOFF]
```

### 운용 / 트래킹 (forge / monitoring) — 예: run_all.R, forward_weights.R

```r
# Lockbox 폐기 — 최신 sig_date까지 사용
SIGNAL_CUTOFF <- max(alpha_scores$Date, na.rm = TRUE)
# 또는 명시적 운용 시점 (현 월말)
SIGNAL_CUTOFF <- as.Date(format(Sys.Date(), "%Y-%m-01")) - 1
```

## 적용 자원

- `02_Infrastructure/hooks/selection_contamination_detector.sh` (v6.5 scope 정정)
- `02_Infrastructure/docs/rules/lockbox-scope.md` (본 파일, 신규 SOT)
- `.claude/rules/pit.md` (lockbox 섹션 reference)
- 운용 cycle R 코드 (run_all.R / forward_weights.R / monitoring scripts)

## 참조

- 도훈 mandate 2026-05-09 KST
- AX-002 (PIT) — 본 정책의 상위 axiom
- Charter v1.7 §10 (Lockbox sealing 정책)
- L-285 (S4 admit + lockbox scope refinement 적립 예정)

## Change log

- 2026-05-09: 신규 SOT 작성 (도훈 mandate scope 정정). selection_contamination_detector.sh v6.5 동기화.
