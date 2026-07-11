# R5 — 팩터 선별-규율 비교전 (사전등록 스펙, R4 완료 시 무지시 자동 착수)

**작성**: 2026-07-11 Q-Lead. **도훈 사전 승인**: "결과 보고 내가 별다른 지시 안 해도 바로 실행 가능하게 준비해둬" (2026-07-11) — 본 스펙 범위 내 자동 착수 권한. 범위 밖 확장은 별도 confirm.
**트리거**: RAMP R4(Boruta, 진행 중) 완료 알림 수신 즉시. **하네스**: R4가 구축한 동일 측정 하네스 재사용(팩터 패널·rolling 워크포워드·배분·run_ramp_graduation 게이트) — 비교 유효성의 핵심.

## 1. 목적

R4(Boruta = shadow-null 선별)의 결과와 무관하게, "선별-규율" 계열의 나머지 대표 2종을 동일 하네스로 측정해 **계열 전체의 판정을 한 번에 확정**한다:
- **Stability Selection** (Meinshausen-Bühlmann): 서브샘플 반복 선택의 일관성 기준 — 2017+ 레짐-취약 팩터 배제 겨냥.
- **mRMR** (max-relevance min-redundancy): 예측력·저중복 동시 최적 — factor DB 342개의 고상관(중복) 질병에 직접 작용, effective breadth 확대 겨냥.
- (조건부 3안) FGX double-selection LASSO: R4/R5에서 선별 실효가 확인될 때만 — 신규 재료 편입 심사기 용도로 별도 설계.

## 2. 분기 로직 (R4 결과에 따라 — 사전등록)

| R4 arm S 결과 | R5 실행 |
|---|---|
| **선별 실효 + 방향 양** (팩터를 실제로 거르고 base 대비 paired > 0) | **Branch A — 우열 비교**: StabSel·mRMR 각 ≤4 config, Boruta 최선 config과 3-way 비교. 목적 = 최강 선별-규율 확정 |
| **선별 무실효 또는 방향 음** | **Branch B — 계열 폐쇄 판정**: StabSel·mRMR 각 ≤3 config 최소 예산. 목적 = "Boruta-특이 실패인가, 선별-규율 계열 전체가 죽었는가" 확정. 셋 다 미달이면 계열 DISTILLED_NEG 후보 |

## 3. 설계 고정 사항 (양 분기 공통)

- **config 예산**: 총 ≤8 (StabSel ≤4: 서브샘플 비율 2 × 선택 문턱 2 / mRMR ≤4: k 팩터 수 2 × 관련성 척도 2). 사전등록 hash 동결, n_trials 기록, null max-t 등재. **R4 6 config과 합산한 selection-discipline family 회계 병기.**
- **구현**: StabSel = LASSO(glmnet) × complementary-pairs 서브샘플 반복, 선택빈도 문턱. mRMR = 상호정보 기반(infotheo/praznik 패키지 가용 확인, 불가 시 상관-기반 근사로 대체하되 방법 명시). Python 사용 시 $QVEST_PY + bt_result는 R 브릿지.
- **판정**: cap-w authoritative + EW-uni 진단 병기 + HARD 3종 + 2017+ 분리 + base 대비 paired NW-t(문턱 2.0). PIT C1(rolling 학습창 trailing-only)·pin_cache 고정.
- **kill 사전등록**: 전 config paired < 2.0 → 해당 규율 소진. R4+R5 전체 미달 시 "선별-규율 계열(shadow-null·stability·redundancy) 소진" L-code + DIST 후보 초안(주간 Cleaner).
- **Self-Adversarial**: confirmed/selected 집합의 시계열 안정성(월간 turnover), 서브샘플-레짐 confound, 선별이 결국 동일 팩터(모멘텀류)로 수렴하는지(수렴하면 규율 무관 = 신호 내용 벽 재확인) 자가점검.

## 4. 실행 절차 (완료 알림 수신 시 Q-Lead 액션)

1. R4 보고에서 arm S 실효 여부 판독 → 분기 결정(§2) — 판독 근거 1줄 기록.
2. ramp-orchestrator spawn: 본 스펙 경로 + R4 하네스 경로 + 분기 지정 전달. (R4가 하네스 경로를 보고에 명시하도록 이미 지시됨 — 미명시 시 outputs/ramp/ 스캔.)
3. 완료 시: L-code emit(modecode RAMP) → FQ-013 갱신 → 텔레그램 v7 판정 보고 → 도훈 결정 필요 사항 있으면 분리 표기.

## 5. 안전 경계 (자동 착수 권한의 한계 — 위반 금지)

- 자본/book_state 무변경 · governor 정지 불변 · 텔레그램은 판정 보고만.
- config 예산 초과·신규 재료 투입·게이트 변경은 자동 권한 밖 — 도훈 confirm 필요.
- 지출한도 오류 재발 시: 즉시 중단·banking·보고 (07-10 프로토콜 재사용).
