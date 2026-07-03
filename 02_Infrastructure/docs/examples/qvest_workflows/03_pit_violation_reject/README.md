# 03 PIT Violation Reject — `WT-D99990103_001`

**시나리오**: alpha synthesis script에 lookahead pattern 주입 → Judge Gate A (PIT C1) FAIL → JUDGE_FAILED → ABORTED.

## 핵심 학습 포인트

1. **alpha_synthesis.R**에 `lm(future_return ~ today_factor)` 주입 (실제로는 t시점에 t+1 미래 returns 사용 — PIT C1 위반)
2. **Judge Gate A (PIT)** — lookahead detector가 패턴 감지
3. **judge_verdict** verdict=FAIL + pit_violations array에 위반 명시
4. **Phase**: FORGE_DONE → JUDGE_FAILED → ABORTED
5. **Cert** alpha_discovery는 ISSUED일 수 있지만 (alpha_package 자체는 OK) Judge에서 PIT block

## 왜 PIT 위반은 hard FAIL인가

Charter v1.X: PIT C1~C15는 Level 0 axiom. 모든 다른 목표보다 우선.

> "이 데이터는 의사결정 시점에 알 수 있었는가?" (PIT 핵심 3질문)

`lm(future_return ~ today_factor)`은 t 시점에 t+1 returns를 회귀 — 룩어헤드 명시.

## File 구성 (15 file + alpha_synthesis.R)

| File | 차이 (vs 01 happy) |
|---|---|
| **alpha_synthesis.R** | 신규 — `lm(future_return ~ today_factor)` 주입 (lookahead pattern) |
| alpha_package.json | 정상 (alpha synthesis 산출은 OK처럼 보이지만 사실 lookahead) |
| **judge_verdict.json** | **verdict=FAIL**, pit_violations=["C1: future_return regressor"] |
| status.json | current_phase=JUDGE_FAILED |
| governor_admission.json | (작성 안 됨 — Judge에서 차단) |

## 다음 단계 reference

이 example을 reading하면:
- PIT C1 lookahead detection 패턴 (lm(future_return ~ ...))
- Judge Gate A 작동 방식
- ABORTED 흐름 (admit 안 됨, retry 가능)
- L-118/L-122 같은 PIT 위반 케이스 디버깅 reference
