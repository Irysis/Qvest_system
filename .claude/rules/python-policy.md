# Python Policy (Level 1)

**발효**: 2026-05-29 (v8.0 Phase 2, 도훈 mandate). 기존 헌법 "R only" 폐지.
**원칙**: R과 Python은 도구적으로 동등하게 허용한다. **언어는 PIT·계약·제약을 면제하지 않는다.**

## 1. 허용 범위

- R (tidyverse + data.table) / Python 모두 리서치·전략·ML·백테스트에 사용 가능.
- 언어 선택 기준: 작업 적합성 (ML/딥러닝 = Python venv, factor DB·tidyverse 파이프 = R). 강제 아님.
- 기존 "Python은 hook router 외 금지" 규칙은 **폐지** (현실 추인 — Cycle 1/2 ML 전체가 Python).

## 2. Python 환경 표준

- venv: `/home/quant/.venvs/qvest_ml/` (`source .../bin/activate` 후 실행). 주요: PyTorch/cu124 · xgboost · lightgbm · ngboost · optuna · mapie · statsmodels · properscoring.
- **한글 경로 회피**: `normalizePath()` 류 금지. 스크립트 내 상대경로 또는 환경변수 PROJECT_ROOT 사용. R의 `source('run_all.R')` 패턴과 동등하게 Python도 `cd` 후 실행.
- I/O: parquet 표준 (pyarrow). RAWDATA 컬럼명 R과 동일 (`Vol`/`Size`/`Ret`/`Close`/`BM_Ret`/`Ticker`).
- 동시성: RAM 80% 이하, 프로세스당 4GB 이하 (R 규칙과 동일).

## 3. PIT·계약 동일 적용 (언어 무관)

- **PIT C1~C15** (`.claude/rules/pit.md`) Python에도 100% 적용. 특히:
  - C1 rolling/expanding window only. C2 same-day circular 금지.
  - **data.table::shift 부호 규칙**(`.claude/rules/data_table_shift_convention.md`)의 Python 등가: `df.shift(periods)` / `.groupby().shift()` 방향 명시. forward label은 `validate_label_direction()` + `bear_date_audit.R` PASS 의무 (Cycle 50 lookahead 사건 재발 방지 — 언어 무관).
  - C14 IC Usable_Date ≤ sig_date. C15 Factor DB는 `load_month_factors()` 경유 (Python에서도 — ML daily parquet carve-out은 명시 승인 hypothesis만).
- **lockbox-scope** (`.claude/rules/lockbox-scope.md`): alpha/risk/optimizer 정규 리서치는 SIGNAL_CUTOFF 적용, forge/monitoring은 폐기 — 언어 무관.

## 4. Backtest Contract — 자체합성 금지 (최우선)

- Python backtest도 **검증된 표준함수만**. R의 PerformanceAnalytics 동등:
  - 금지: `np.prod(1+r)-1` / `(1+r).cumprod()` / `0.8*r1+0.2*r2` 등 자체 합성 (answer-principles 정합).
  - 허용: 10-component `bt_result`는 **R `02_Infrastructure/contracts/build_bt_result()` bridge 경유** 생성 (Python은 sim_result/returns만 산출 → R이 계약 빌드·audit·registry append). 독립 Python 계약 구현은 단기 미도입.
- **포트폴리오 수익률 *구성* 도 R 경유 (도훈 mandate 2026-05-31, 안 A)**: 포트 수익률은 R `Return.portfolio()`(PerformanceAnalytics, weight drift·rebalance 정확)로 구성. **Python은 비중(weights) + asset 수익까지만 산출해 R 브릿지로 넘기고, 사전 구성된 포트 수익률 시계열을 손계산(`(w*r).sum()` 등)으로 만들지 말 것.** Python-native portfolio lib(vectorbt/bt 등) 미도입 — R 브릿지 단일 경로 유지(도입 시 R Return.portfolio와 known-case parity 검증 의무).
- `bt_result` audit (`audit_bt_result`) + registry (`register_bt_result`)는 R 경유 단일 경로 유지 → metric_type 라벨·audit_status 일관성 보장.

## 5. Hook 강제 (Phase 3에서 .py 확장 예정)

- `answer_principles_grep.sh` + `backtest_contract_audit.sh` TARGET_PATTERN에 `.py` 추가 (자체합성·회피표현 탐지를 Python까지 — v8.0 Phase 3 harness 배치에서 적용).
- 그 전까지는 본 rule + Codex Round로 보강 (warn-level).

## 6. 위반 시
PIT/자체합성/lockbox 위반은 **언어 무관 AX-002 동급**. 즉시 중단 → 결과 무효 → 재실행.

## 참조
- `.claude/rules/pit.md` / `backtest-contract.md` / `data_table_shift_convention.md` / `lockbox-scope.md` / `answer-principles.md`
- `02_Infrastructure/contracts/` (R bridge — build/audit/save/register)
- `02_Infrastructure/docs/qvest_v8_0_upgrade_plan.md` WS1

## Change log
- 2026-05-29 v8.0 Phase 2: 신규 작성. "R only" 폐지 + R/Python 동등 허용 + 가드레일(PIT/계약/bridge). 도훈 mandate.
