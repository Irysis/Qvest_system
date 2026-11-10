# 골든 4종 · 결함 후보 2건 정비 보고 (2026-11-10)

출력 전문: `scratchpad/out/*.txt`(수리 전 = `<suite>.txt` · 수리 뒤 = `<suite>_after.txt`) · 진단 스크립트 = `scratchpad/diag_*.R`.

## 요약 — 팩터 DB 수리(재무 v2 · 방향 · 총부채)가 원인인 골든은 하나도 없다

| 스위트 | 수리 전 실패 | 원인(재도출) | 처분 | 수리 뒤 |
|---|---|---|---|---|
| replication_exec_golden | 4 | ① 2024-12-30 거래일 복원(48b3d3bfd · 10-17) ② OHLCVS 재수출(경계 뒤) ③ 등급 v3.3(B→A) | 재핀(시험 소유 참조 파일 신설) | 8 PASS · 0 FAIL · 1 SKIP |
| remeasure_from_holdings | 8 | 위 ①②③ + 등급 v3 승격(close_t1 B→C · 10-13) + 운영 rebase(09-25)가 골든 폴더에 쓴 remeasure_ 판 | 재핀 + 운영 상태 의존 단언 수리 | (아래) |
| inv13_beta_asof | 5 | ① 같은 달력 복원(202412 월말) ② 투자자 패널 99종목 보충(11-10 00:16 · 수집 체계 v2) | 참조 β 재핀 + D2 픽스처 수리 · A1 · B2 는 빨강 유지(팩터 DB INV 재계산 필요) | 14 PASS · 2 FAIL |
| rf_overlay_pit_mask | 1 | 엔진 수리 b234afb11(10-17 전액 현금 달 보존) — 자매 스위트는 갱신, 이 스위트는 누락 | 시험 수리(자매와 같은 대조) | 62/0 |
| method_adapter_contract | 3 | 픽스처 한계 — Σ = 단위행렬이면 HRP · ERC · NCO 가 수학적으로 정확히 EW(폴백 아님) | 시험 수리(이질 Σ · 폴백 호명 단언 추가) | 61/0 |
| l2_pool_grade_floor | 1 | 시험 낡음 — 10-06 도훈 결정 '풀 = 역할 대표'(role 모드)는 역할 등급 B+ 로 편입, essence 는 C · F 가능 | 시험 수리(경로별 재도출) + 생산자 메타 결함 보고 | 9/0 · 돌연변이 빨강 확인 |

(세부 증거는 아래 절)

수리 뒤 remeasure_from_holdings = 47 PASS · 0 FAIL(돌연변이 M2 는 재핀 참조 대비로 옮겨 계속 빨강을 냄 — 5368 vs 5337일).

## 1. replication_exec_golden · remeasure_from_holdings (같은 골든 20260921_100007_6876)
- 비중은 저장 factors_panel / 저장 보유에서 온다(비트 일치) → 팩터 DB 를 읽지 않음 = 수리와 무관.
- 백업(.cache/backup_cal20241230_20261017_175419) 데이터로 두 경로를 돌리면: 경계(2026-03-30) 앞 ret_net 비트 동일 · 첫 차이 2026-07-01(OHLCVS 재수출 빈티지) · close_t1 은 09-25 운영 판과 경계 앞 max|Δ| 3.75e-16.
- 백업 → 현행 RAWDATA(≤2026-09-18) 차이: 2024-12-30 행 2,504 신규 · 2025-01-02 Ret 2,292 변경(두 날 복리와 2.2e-16 일치) + 01-02 2행 신규 · 벤치 12-30 신규/01-02 변경 · 경계 뒤 526 변경/4 소멸. 그 밖 0 → 커밋 48b3d3bfd(2024-12-30 거래일 복원)로 전부 설명.
- 등급: legacy B→A = 등급 v3.3(63a4433b3 · OOS 관문 교체) · close_t1 B→C = 등급 v3 승격(10-13 · CR 약함 노치).
- C3 '산출물 안 remeasure_ 0' 은 09-25 운영 rebase 가 골든 폴더에 remeasure_close_d_legacy_dc0a53ba · remeasure_close_t1_5562284e 를 쓴 날부터 빨강(운영 상태 의존) → 전후 항목 동일 + 재귀 md5 불변으로 교체.
- 처분: 시험 소유 참조 08_Tests/fixtures/replication_exec_golden/ref_legacy_20261110.rds(+README.md 사유 · 재생성 절차) 신설. 운영 stage_artifacts 무접촉. 저장 authoritative(09-21 빈티지) 3자리 대조는 '축 = 저장 + 1일' 일 때만 SKIP(PASS 아님) · 등급 다르면 FAIL.
- 값(2005-01~2026-09 · 2023-01~ 시험 창 포함): legacy A · CAGR 0.275 · Calmar 0.500 · PORT_t 4.336 / close_t1 C · PORT_t 3.772 · Calmar 0.432.

## 2. inv13_beta_asof
- INV13 입력 = investor_wide + 빌더 달력뿐 → 팩터 DB 수리 무관.
- β 202606: 구 참조 −0.595292416327731 = (12-30 뺀 달력 + 99종 뺀 패널)로 Δ 1.1e-16 재현. 달력 복원만 → −0.594876161286015(저장 factor_db_202606 이 이 값 · 99종 제외 패널 단독 빌드가 저장 INV13 과 비트 동일 · 종목 3394/3373/3358 일치). 99종 보충(11-10 00:16 [incr_investor] 7,060,494→7,124,398행 · BUILD_20261108.md Investor_Act 3,668→3,767) → −0.595046943514193.
- 처분: REF_BETA 재핀(202606/202607) + D2 대조 달력을 '투자자 달력'(이제 빌더와 같아 공허) → '복원 전 빌더 달력'(Δβ −4.16e-4)으로. 수리 뒤 14 PASS · 2 FAIL(A1 · B2).
- A1 · B2 빨강 유지 = 정당한 데이터 변경 신호: 저장 팩터 DB INV 계열이 11-09 재빌드(99종 보충 전) 판. ★위험: A1 이 빨강인 동안 Ma2 · Mb(돌연변이 → '재현 red' 판정)는 공허하게 통과한다.
- 필요 절차(무거움 · 안 돌림): 팩터 DB INV01~INV13 을 202306~202611 달 재계산(rebuild_factor_subset.R · factor_db_vintage.json 한 줄 추가 · 도훈/Q 판단). 예상 = 수십 분~1시간 남짓(11-10 총부채 27팩터 × 442달 = 약 2시간 14분 실측에서 추정 · 미실측).

## 3. rf_overlay_pit_mask — A4 dd_brake 1920 vs 1860행
합성 픽스처라 데이터 무관. 엔진 b234afb11(10-17) 이 노출 0 달 신호일을 표현 하한(1e-9 × w)으로 남김 = 3 신호일 × 20종목. 같은 커밋이 자매 test_rf_engine_overlay_stack.R 은 고쳤으나 이 스위트는 누락 → 같은 대조(늘어난 날 전부 Σw ≤ 1e-8 · 나머지 비트 동일) 이식. 62/0.

## 4. method_adapter_contract — 결함 아님(픽스처 한계)
어댑터 3종은 98884bf292(10-16)부터 ctx$Sigma 우선. 픽스처 Σ = diag(25) → HRP(역분산) · ERC · NCO 가 수학적으로 정확히 EW(max|w−1/25| ≤ 1.4e-17 · 폴백 로그 없음). 이질 Σ 이면 0.113/0.124/0.037. 실물 절만 이질 분산 표본 Σ(seed 11) 로 바꾸고 'EW 폴백' 호명 단언 추가. 61/0.

## 5. l2_pool_grade_floor — 시험 낡음 + 생산자 메타 결함(보고만)
10-06 도훈 결정(strategy_role.json pool.mode = role · 커밋 f0930f5532): 풀 = 역할 대표 · 자격 = 역할 등급 B+(essence floor 와 병렬). 71건 전부 admission_route = role_rep · essence C 53 · F 5. 재도출: 71/71 역할 등급 B+ (빌더 .role_of 와 같은 조회 — 빈 pool_rep_roles 행 제외 → run id 4건).
- 시험 수리: role_rep = strategy_roles.json 역할 등급 B+ 재도출 · 그 밖 경로 = essence floor 그대로 · role 모드가 아닌데 role_rep 있으면 빨강. 돌연변이(역할 등급 1건 C) → 빨강 확인. 9/0.
- 생산자 결함(수리안 · 안 고침): 02_Infrastructure/regime/build_module_performance.R:511 `grade_floor=.L2_FLOOR` 가 role 모드에서도 'B' 를 적는다(실제 편입 축은 역할 등급 · pool_mode 필드 없음) · n_floor_excluded 770 은 실제로 not_role_rep 수. 수리 = pool_mode · grade_axis("role_grade_bplus") 기록 + grade_floor 를 모드별로. 영향 = 하류가 'essence B+ 풀'로 오독(2계층 소비자 확인 필요).
