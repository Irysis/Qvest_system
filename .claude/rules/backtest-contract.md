---
paths:
  - "02_Infrastructure/contracts/**"
  - "qepm/mailbox/worktask/**"
  - "04_Research/strategies/**/run_all.R"
---

# Backtest Result Contract v1.0 (Level 0)

**발효**: 2026-04-29 / Session 75 v6.4 rule 분리
**위반 = AX-002 동급**

## 10-Component bt_result list

모든 전략 백테스트는 동일한 `bt_result` 산출:

1. `manifest`
2. `strategy_spec`
3. `nav`
4. `period_returns`
5. `holdings`
6. `benchmark_returns`
7. `metrics`
8. `benchmark_compare`
9. `rolling_metrics`
10. `drawdowns`
11. `audit`

**제외**: trades + costs (Qvest 리서치 시스템, commission=0.0015 입력 단계 차감).

## 추정 vs 백테스트 분리

`metric_type`:
- `backtested` (official)
- `estimated`
- `proxy`
- `unavailable`

(official 제외 모두 명시 라벨)

## 핵심 함수 (`02_Infrastructure/contracts/`)

- `build_bt_result(sim_result, strategy_spec, ...)` — 10-component 빌드 (PerformanceAnalytics 표준 함수만)
- `audit_bt_result(bt_result)` — 10 checks. Critical FAIL 시 `metric_type='unavailable'` + `integrity='FAIL'`
- `save_bt_result(bt_result, output_dir)` — RDS + CSV × 10 + JSON × 2 + XLSX 11-sheet
- `register_bt_result(bt_result)` — `qepm/registry/backtest_registry.csv` append (audit FAIL 차단)

## L3 hard block — v9(08-23) 등록 해제 → **2026-08-24 재등록**(원장 integrity 게이트)

`02_Infrastructure/hooks/backtest_contract_audit.sh`(PreToolUse[Write])는 08-23 에 해제됐다가 **2026-08-24 재등록됐다** — 해제 사유였던 `.py` 자체합성 idiom 차단 가지만 제거하고 원장 integrity 판정은 복원했다(대상 = `backtest_registry.csv`·`methodology_(active|memory).md`·`metrics_official.csv`. 양성/음성/돌연변이 10/10 실증 = `08_Tests/hooks/test_backtest_contract_audit_gate.R`). 현행 등록 12종에 포함(`.claude/settings.json` `_doc_bt_contract`).
- **계약 자체는 불변**: `audit_bt_result()` Critical FAIL → `metric_type='unavailable'` + `integrity='FAIL'`, `register_bt_result()`가 audit FAIL 등재를 계속 거부한다. 차단 지점이 훅(쓰기 시점)에서 **R 계약(등재 시점)** 으로 이동했을 뿐이다.
- (사료) 구 동작: backtest_registry.csv / L-code 등재 시 `audit_status=FAIL` 차단

## 적용 대상

- 신규 전략: 의무
- STR_1631_SYN_06 + STR_1715: retrofit 완료
- 나머지 178개: 사용 시점 전환

## 참조

- `00_Lawbook/Multi_Agent/backtest_result_contract.md` v1.0
- `_shared_prefix.md::<backtest_contract>`
- L-248 사례
