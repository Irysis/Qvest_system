---
paths:
  - "**/*.py"
  - ".venv_qvest_ml/**"
---

# Python Policy (Level 1)

> **자매 규칙 — R 측 호출 규약**: 본 문서는 Python 측을 규율한다. R에서 `system2`/`system`을 호출하거나 cleanup을 등록하거나 프로젝트 루트를 해석할 때는 **`02_Infrastructure/docs/rules/r-portability.md`**(금칙 4종 · 2026-07-25 승격, 위반 = AX-002 동급)를 함께 로드할 것. 두 문서가 언어별로 같은 층을 덮는다.

**발효**: 2026-05-29 (v8.0 Phase 2, 도훈 mandate). 기존 헌법 "R only" 폐지.
**원칙**: R과 Python은 도구적으로 동등하게 허용한다. **언어는 PIT·계약·제약을 면제하지 않는다.**

## 1. 허용 범위

- R (tidyverse + data.table) / Python 모두 리서치·전략·ML·백테스트에 사용 가능.
- 언어 선택 기준: 작업 적합성 (ML/딥러닝 = Python venv, factor DB·tidyverse 파이프 = R). 강제 아님.
- 기존 "Python은 hook router 외 금지" 규칙은 **폐지** (현실 추인 — Cycle 1/2 ML 전체가 Python).

## 2. Python 환경 표준

- venv: `C:/Users/99922/OneDrive/Quant_Module_Moltbot/.venv_qvest_ml/ (Windows venv, 2026-06-10 재생성)`.
  실행기 = `.venv_qvest_ml/Scripts/python.exe` (Windows venv 이므로 `bin/python` 아님).
- **★설치 실측 (2026-08-13 감사 → 같은 날 도훈 지시로 결손 해소).** 선언을 믿지 말고 착수 전 import 로 확인할 것.
  - **현재 전 항목 실재** (python 3.12.10): `torch 2.12.1+cpu` · `xgboost 3.4.0` · `lightgbm 4.6.0` ·
    `ngboost 0.5.11` · `optuna 4.9.0` · `mapie 1.4.1` · `statsmodels 0.14.6` · `properscoring 0.1` ·
    `numpy 2.4.6` · `pandas 2.3.3` · `pyarrow 24.0.0` · `sklearn 1.9.0`.
  - 감사 시점 결손 3종(`xgboost`·`optuna`·`properscoring`)은 **2026-08-13 설치 완료**(도훈 "노트북 환경이라
    없을거야, 깔아줘"). import 뿐 아니라 **실동작 1회씩 확인**: xgboost fit · properscoring CRPS ·
    optuna 12-trial 탐색.
  - ⚠**torch 는 CUDA 아님**(`+cpu`) — 구 선언 "PyTorch/cu124" 는 현 노트북 환경과 불일치. 이는 결손이 아니라
    **환경 사실**이므로 GPU 전제 라운드(예: 구 DPL 8config GPU 전수)는 이 머신에서 재현되지 않는다.
  - 교훈: 이 결손은 v8.4 Lane A arm A(참조 기준선이 XGBoost)의 착수 직전에 발견됐다 — **환경 선언은
    라운드 전제이므로 착수 전에 실측**한다(선언만 읽고 들어가면 관문에서 사이클을 버린다).
  - 재확인 1줄:
    `.venv_qvest_ml/Scripts/python.exe -c "import importlib;[print(m, getattr(importlib.import_module(m),'__version__','?')) for m in ('torch','xgboost','lightgbm','ngboost','optuna','mapie','statsmodels','properscoring')]"`
- **한글 경로 회피**: `normalizePath()` 류 금지. 스크립트 내 상대경로 또는 환경변수 PROJECT_ROOT 사용. R의 `source('run_all.R')` 패턴과 동등하게 Python도 `cd` 후 실행.
- I/O: parquet 표준 (pyarrow). RAWDATA 컬럼명 R과 동일 (`Vol`/`Size`/`Ret`/`Close`/`BM_Ret`/`Ticker`).
- 동시성: RAM 80% 이하, 프로세스당 4GB 이하 (R 규칙과 동일).

## 3. PIT·계약 동일 적용 (언어 무관)

- **PIT C1~C15** (`.claude/rules/pit.md`) Python에도 100% 적용. 특히:
  - C1 rolling/expanding window only. C2 same-day circular 금지.
  - **data.table::shift 부호 규칙**(`02_Infrastructure/docs/rules/data_table_shift_convention.md`)의 Python 등가: `df.shift(periods)` / `.groupby().shift()` 방향 명시. forward label은 `validate_label_direction()` + `bear_date_audit.R` PASS 의무 (Cycle 50 lookahead 사건 재발 방지 — 언어 무관).
  - C14 IC Usable_Date ≤ sig_date. C15 Factor DB는 `load_month_factors()` 경유 (Python에서도 — ML daily parquet carve-out은 명시 승인 hypothesis만).
- **lockbox 폐지 (v10 2026-08-29)**: lockbox/SIGNAL_CUTOFF 봉인 제도는 완전 폐지 — 전기간 사용. PIT C1~C15 는 언어 무관 불변 (C5 overlay_signal_cutoff 는 PIT 기계로 존치).

## 4. Backtest Contract — 자체합성 금지 (최우선)

- Python backtest도 **검증된 표준함수만**. R의 PerformanceAnalytics 동등:
  - 금지: `np.prod(1+r)-1` / `(1+r).cumprod()` / `0.8*r1+0.2*r2` 등 자체 합성 (answer-principles 정합).
  - 허용: 10-component `bt_result`는 **R `02_Infrastructure/contracts/build_bt_result()` bridge 경유** 생성 (Python은 sim_result/returns만 산출 → R이 계약 빌드·audit·registry append). 독립 Python 계약 구현은 단기 미도입.
- **포트폴리오 수익률 *구성* 도 R 경유 (도훈 mandate 2026-05-31, 안 A)**: 포트 수익률은 R `Return.portfolio()`(PerformanceAnalytics, weight drift·rebalance 정확)로 구성. **Python은 비중(weights) + asset 수익까지만 산출해 R 브릿지로 넘기고, 사전 구성된 포트 수익률 시계열을 손계산(`(w*r).sum()` 등)으로 만들지 말 것.** Python-native portfolio lib(vectorbt/bt 등) 미도입 — R 브릿지 단일 경로 유지(도입 시 R Return.portfolio와 known-case parity 검증 의무).
- `bt_result` audit (`audit_bt_result`) + registry (`register_bt_result`)는 R 경유 단일 경로 유지 → metric_type 라벨·audit_status 일관성 보장.

## 5. Hook 강제 (.py 확장 적용됨)

- ★**v9 2026-08-23: `answer_principles_grep.sh`·`backtest_contract_audit.sh` 등록 해제**(도훈 결정 ④. `.py` 자체합성 idiom 차단이 분포-표적 ML 레인에 걸리는 부작용 포함 — 파일 존치, 재등록 레시피 `02_Infrastructure/hooks/_archive_v8_enforcement/MANIFEST.md`). **본 §4 금지 규칙과 R 브릿지 단일 경로는 불변**이며, 판정은 훅이 아니라 계약(`build_bt_result`/`audit_bt_result`/`register_bt_result`)과 리뷰가 담당한다.
- (사료) 구 배선: `answer_principles_grep.sh` + `backtest_contract_audit.sh` TARGET_PATTERN에 `.py` 포함 (2026-07-03 아키텍처 수리에서 적용).
- hook 미커버 영역은 본 rule + Self-Adversarial Challenge(v8.2 — Codex Round 제거·대체, `02_Infrastructure/docs/rules/codex-round.md`)로 보강 (warn-level).

## 6. 위반 시
PIT/자체합성 위반은 **언어 무관 AX-002 동급**. 즉시 중단 → 결과 무효 → 재실행. (v10: lockbox 항목 폐지)

## 참조
- `.claude/rules/pit.md` / `backtest-contract.md` / `data_table_shift_convention.md` / `02_Infrastructure/docs/rules/answer-principles.md`
- `02_Infrastructure/contracts/` (R bridge — build/audit/save/register)
- `02_Infrastructure/docs/qvest_v8_0_upgrade_plan.md` WS1

## Change log
- 2026-07-03: §5 갱신 — hook `.py` 확장 적용됨으로 반영 + "Codex Round로 보강" 문구를 Self-Adversarial Challenge(v8.2)로 교체.
- 2026-05-29 v8.0 Phase 2: 신규 작성. "R only" 폐지 + R/Python 동등 허용 + 가드레일(PIT/계약/bridge). 도훈 mandate.
