# 1계층 사다리 루프 파일럿 + A 경로 소방 훈련 — 코어 v2 (2026-11-11)

도훈 결정 `L1-CHAIN-PILOT-FIRST-20261111`("파일럿부터")에 따라, 실제 원장을 건드리기 전에 임시 원장으로 사다리 루프를 끝에서 끝까지 한 번 돌렸다.
판단 `J-20261111-010`(파일럿은 코어 v2 위 · 알려진 답 사례는 v1 에서 틀린 답이 나와야 정답) · `J-20261111-013`(범위).

## 결론 — 통과

| 묶음 | 결과 | 근거 파일(`evidence/`) |
|---|---|---|
| 시나리오(상설 판 · 기저 풀 · 사슬 · 막힘 · 닫기 · A 경로) | **27 / 27** | `pilot_steps.json` · `pilot_scenario.log` |
| 실행기 경로(round.sh 판 라우팅 · 사슬 틱 드라이런 · 잠금 격리) | **8 / 8** | `pilot_runner_checks.txt` · `pilot_runner.log` |
| 실제 원장 15종 md5(실행 전 = 후) | **불변** | `real_md5_before.txt` · `real_md5_after.txt` |
| 텔레그램 실발송(발송 본문 보관 수) | **0**(30 → 30 · `QVEST_TG_DRY_RUN=1`) | `pilot_summary.txt` |

실행 = `HEAD 3c667a3f1` 에서 `PILOT_OUT=<저장소 밖 폴더> bash 08_Tests/scenarios/run_l1_pilot_v2.sh`(18:35~18:37 · 약 90초). 재현 명령도 이것 하나다.

## 무엇이 진짜이고 무엇이 대역인가

- **거울 루트**: 저장소 HEAD 의 코드 · 등록부(`git archive` — `CLAUDE.md` · `02_Infrastructure` · `04_Research/programs` · `00_Lawbook` · `06_Registry`) + 등급 계약 데이터 사본 4개(`.cache/benchmark.parquet` · 요인 수익 3). `QM_ROOT` = `CLAUDE_PROJECT_DIR` = `RC_SA_ROOT` = 거울 · `R_ENVIRON_USER` = 빈 파일(첫 줄 단정) · 잠금 · GPU 임대 · 레인 상태 = 임시 경로.
- **진짜(정본 코드 그대로)**: 상설 판 등록(`rc_register` — 점검 기록 · 철학 P1 영수증 · 핀) · 스캔 · 판정(등록 규칙 적용 · t(α) = β-통제 알파 계약 · 상승 포착 = 행동 카드) · 구성 판독 · 기저 풀 · 사슬 판 검사 · 등록(감독 영수증) · 걸음 열기 검사 · 걸음 판정(보는 창 지표 · 채택 규칙 판 v2) · 막힘 판정 · 포기 · 닫기 · **선택 현실 점검 재채점(`selection_regrade.R`)** · **A 자격 관문(`round_candidate_gate.R` → `rf_a_eligibility`)** · 모듈 풀 등재기 · 결과 원장 · `round.sh` · `chain_tick.sh`(드라이런).
- **대역**: ① 측정기 — 셀 워커 대신 KOSPI200 실제 월 수익 위 합성 수익(r = α + β·bm + ε)을 계약 함수(`build_metrics` · `build_benchmark_compare`)로 산출물화하고, 측정 시점 등급은 실제 등급 계약(`gv3_score_dir`)이 낸다. ② 상설 칸 평가의 RAWDATA 패킷(`dp_build` · `mc_card` — 7 GB 급 적재) 대신 같은 행동 카드의 보는 창 지표. ③ 영수증 리뷰 파일은 합성(거울 판단 원장 사본에만). ④ Judge 스폰 없음(요청 파일까지 = 건식).
- 왜 대역인가: DNN 칸 측정은 지속 25~33 GB 라 레인 THGNN 측정(12.8 GB)과 겹칠 수 없고(커밋 상한 55.8 GB), 파일럿의 목적은 판정 경로 배관과 관문의 양성 대조다.

## 알려진 답 2건 — v1 = 틀린 답 · v2 = 바른 답(같은 거울 원장)

| 사례 | v1(출시본 · 자식 프로세스) | v2 |
|---|---|---|
| 1. 같은 엔진 경로 두 칸 중 **처치 칸만 통과**(X_E2 미달 · X_E3 통과) | `engine:PILOT_X` 자격 TRUE — 처치 칸이 맨 엔진 행에 합쳐짐(판단 T1 C-20261111-001 재현) | 맨 엔진 행 자격 없음 · 처치 칸은 `standing:P1S90_pilot:P1S90_X_E3` 행(treatment) · 그 기저 칸 사양 = 통과 칸 사양 그대로 |
| 2. **등급 경로**(레인 권위 등급 B · 상설 통과 없음) | `engine:PILOT_Z` 자격 TRUE | 자격 없음(not_qualified) · 등급 B 는 참고 열(도훈 결정 (나)) |
| 대조: 표준 칸 통과(Y_E2) | 자격 TRUE | 같은 엔진 행에 합쳐 자격 TRUE(동작 보존) |

실제 P1S01 칸 사양 3개도 v2 구성 판독이 맞게 읽는다(E2_C0 standard · E3_RX0 treatment(weighting · factors · rebalance) · 1908.01112 standard) — 내일 실제 판정이 나면 v2 기저 풀이 E3 를 맨 엔진 행에 합치지 않는다.

## A 경로 소방 훈련 — 합성 양성 1건이 끝까지(실제 부품)

사슬 `P4C90_pilot`(기저 = 상설 표준 칸 Y · 채택 규칙 판 v2) → 걸음 1(비중 블록 · 합성 양성) 채택 → 걸음 2(리밸 블록) 기각 → 걸음 3 측정 실패 2회 → 포기 → 닫기.
- 측정 시점 등급(실제 `gv3_score_dir`): **A**(S 1.28 · 하한 4종 통과 · 시험 창 OOS 관문 통과 — 합성 자료의 값이다).
- 닫기 재채점(실제 `sr_regrade` · 시행 집합 = 기준 칸 + 판정 걸음 2 = 3 · 포기 1 제외): **A 유지** · 선택 관문 = reality_check · 조정 p 0.0005 ≤ 0.05.
- A 자격 관문(실제 `rf_a_eligibility` · 칸 경로 어댑터 `rcg_route`): **발행** · 보류 코드 0 → `judge_request.eligible.json`(judge_request_v2 · pending · source round_candidate_gate · lane program_round) · 보류 파일 없음 · Judge 스폰 없음.
- 모듈 풀 등재: 최종 후보 1개만 · 거울 `module_catalog.json` 만 바뀜(실제 원장 md5 불변).
- 결과 원장(거울): 사슬 닫기 1줄 · 다음 탐침 2 · 설계 입력 표에 보인다.

## 막힘 경로 — 건너뛰고(원장 무기록) 풀리면 잇는다

배리어 잠김(`barrier_held`) · 데이터 낡음(`data_stale`) · 판 표식 진행 중(`vintage_in_progress`) · GPU 대기(`gpu_wait` — 레인 측정 1) = 재지 않는다 · 원장 줄 수 그대로 · 러너 호출 0 → 풀린 뒤 같은 걸음 측정 · 판정. 측정 실패 2회 → `step_measure_failed` 2줄 → 포기(기각 · 산출 없음) → 사슬 계속. 핀 변경(상설 판 판정 경로 파일 1바이트) → 판정 · 측정 맥락 거부(판정 경로 핀 불일치 — 새 판) → 되돌리면 정상.

## 실행기 경로(거울 루트)

`round.sh` 가 사양 `core_version` 으로 판을 고른다: 파일럿 판(v2) = `v2/f7e5ce59` · P1S01 사본(v1) = `v1/e70ac0af` · 사양 없는 호출은 `RC_CORE_DEFAULT` 또는 거울 RELEASES 의 마지막 출시 판(v2) — v1 · v2 풀 md5 가 실제로 갈린다. 닫힌 사슬 `p4-status` 판독 · 사슬 틱 드라이런 = 열린 사슬 1개의 계획 `measure_base` · 닫힌 사슬 `skip closed` · 거울 배리어 free(실제 배리어 = 총괄 세션 writer 잠금 held 와 무관) · `round.sh -` 가 `-/results` 를 만들지 않는다.

## 파일럿이 찾아 고친 것

- 운영: 아침 상태 보고(`ops/morning_steps/l1_status_send.R`)가 코어 v1 을 직접 적재 — v2 출시 뒤에도 기저 풀 줄이 v1 규칙(등급 경로 · 처치 칸 합침)으로 셀 뻔했다 → 마지막 출시 판 적재 + 상설 판 줄은 판마다 `round.sh <판> standing-status`(한 프로세스 한 코어 · 판 핀 대조 때문 · 18:33 원자 교체).
- 운영: `round.sh -` 가 저장소 맨 위에 `-/results` 를 만들던 결함(11:39 잔재 삭제 · v2 라우팅과 함께 수리).
- 시험: `test_round_core_v2.R` R3 — '표식 없는 사슬 사양'을 round_spec 폴더로 잘못 재던 단언(출시 전에는 기본 판이 v1 이라 우연히 통과 · 출시 기록이 드러냈다).
- 파일럿 하네스 자체(3건): 거울에 `CLAUDE.md`(등급 계약의 루트 표식) · 대역 워커 권위 기록의 `measurement_regime.exec_price`(β-통제 알파 판독기 요구) · 잠금 폴더 선생성(폴더 자체가 잠금 = held).

## 실제 측정(보류 해제) — 아직

해제 조건(셋 다): ① 파일럿 통과 ✅ ② `06_Registry/factor_db_vintage.json` 의 `FACTOR-DB-INV-PANEL-RECOMPUTE-20261111` `completed_at` — **항목 없음(재계산 시작 전)** ③ GPU 임대 + 레인 측정 0 — **레인 THGNN 측정 중(11-11 18:28 기준 6.8시간 · 11-12 07~09시 종료 추정)** · 임대 free.
→ `tick_hold` 유지(판단 `J-20261111-015`). 다음 세션: 재계산 완료 확인 → `python -X utf8 02_Infrastructure/ops/qv_lock.py lease acquire --holder P1S01_standing --purpose "P1S01 상설 첫 측정" --holder-pid <pid>` + 레인 측정 0 → `tick_hold` 삭제 → 측정 창(00:03 · 07:10 회피 · DNN 시드 지속 25~33 GB).
