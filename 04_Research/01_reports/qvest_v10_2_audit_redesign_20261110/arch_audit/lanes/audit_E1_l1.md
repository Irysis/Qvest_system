# 감사 레인 E1 — 1계층 리서치 프로세스(라운드 코어 · 상설 판 · 강화 사슬) 독립 감사 (2026-11-10)

범위 = `04_Research/programs/_lib/round_core/**` · `02_Infrastructure/programs/{round_candidate_gate,selection_regrade,trial_budget}.R` · 상설 판 · 기저 풀 · P4 강화 사슬 · 결과 원장 · 감독 영수증 · 생성기 판.
방법 = 코드 정독 + 격리 시나리오 시험(임시 루트 · 합성 자료 · 가짜 러너 · 실제 측정 0 · 발송 0) + 소스 텍스트 치환 돌연변이.

## 1. 배선 지도 (코드로 확인한 것만)

```
충실구현 레인(RP_AUTO_*) ─ 등록부 kind=engine 인계 ─┐
                                                   ├─ round.sh <P1Sxx> scan → standing_ledger.jsonl(enqueue) → standing-measure
                                                   │    → rf_cell_worker.R(정본 셀 워커) → judge(rc_eval_cell + 규칙) → verdict(qualify)
                                                   │    (정기 = ops/standing_board_run.sh · 예약 작업 미등록 · P1S01 미등록 → 지금 실행 0)
rc_standing_qualified() ─────┬─ rc_p4_base_pool() ←── 등록부 권위 등급 A/B 경로(+ factor_db_vintage · 11-10 수혜 기록 제외)
                             └→ p4-base-spec(rc_p1_cell_spec 재사용) → p4 chain_new → p4-register(철학 P1 + 판단 T1 영수증)
  → p4-base-measure(k0) → [p4-workdir/p4-design → 생성기(LLM · 수동) → p4-step-open → p4-step-measure → p4-step-decide | abandon]×
  → p4-close(P2 + T2 영수증) → selection_regrade.R::sr_regrade(시행 집합) → A 면 round_candidate_gate.R::rcg_route / 아니면 rcg_withdraw
  → finalize.json(사람 쪽) · round_outcomes.jsonl(결과 원장 · 다음 설계 입력) · register_measured_module(최종 후보 1개 · B 이상)
  → 다음 사슬 rc_p4_design_input 이 rc_open_probes · rc_outcomes_md 로 결과 원장을 읽는다 · rc_probe_consume 로 이어받음 표시
```
- 운영 실측: P1S01 상설 판 **미등록**(stage_artifacts 에 standing_ledger 없음) · P4 사슬 0개 · `06_Registry/round_outcomes.jsonl` 없음 · 생성기 g1 만 등록(evidence 0). 즉 v10.2 1계층 강화 경로는 **코드만 있고 운영 실행 0회**.
- 프로그램 라운드(P0~P3): 10라운드 complete · P2R05 registered(측정 미시작 · 코어 이전 라운드 고유 실행기 + `_lib/night_state` 의존).

## 2. 시나리오 표

| 시나리오 | 기대 | 수리 전 실제 | 조치 | 시험 |
|---|---|---|---|---|
| RAWDATA 가 직전 거래일 세션을 빠뜨림(오늘 운영 = 11-06 · 11-09 누락) | 측정 거부 | **4경로 모두 측정 진행**(완료 줄 · 배리어만 봄) | `v1/freshness.R` 단일 판정 · 4경로 배선 | e2e F1~F14 · standing E0 |
| 신선도 판정기 판독 불가(감사기 변경 · 휴장일 연도 없음 · 오류) | 거부 | 해당 없음(판정 없음) | unreadable = 거부 | F6 F7 F9b F10 F12 |
| 규칙 변경 수혜 기록이 등급 B/A 로 기저 풀 진입 | 제외 | **자격 통과** | `rule_change_beneficiary` · `rule_change_unknown` | e2e P3 P5 P6 |
| 두 프로세스가 같은 걸음을 동시에 연다/잰다 | 하나만 | **둘 다 원장에 기록**(상태 검사가 잠금 밖) · 같은 measure json 덮어씀 | 잠금 안 재확인 guard + 측정 점유(claim) | e2e C9 C9b C10(실제 자식 프로세스 2개) |
| 측정 중 크래시(점유 잔재) | 다음 실행이 인계 | 해당 없음(점유 없음) | 죽은 pid = 인계 · 산 pid = busy | e2e C5 C6 |
| 측정이 결정론적으로 실패하는 걸음 | 사슬 진행 가능 | **사슬 영구 정지**(다음 열기 · 닫기 모두 '판정 안 된 걸음' 거부) | `p4-step-abandon`(실패 ≥ 2 · 기각 · 산출 없음) | e2e C16 C17 |
| 닫기 중간 크래시(결과 원장 뒤) | 재진입 멱등 | 결과 원장 dedup 은 있었음 · 확인 시험 없음 | 시험 고정(재채점 · 관문은 재실행 = 덮어쓰기) | e2e Z2 Z4 |
| 재채점 뒤 A 아님 · 앞선 Judge 트리거 잔존 | 거둔다 | **p4 닫기는 거두지 않음**(rcg_finalize 만 거둠) | p4 닫기에 rcg_withdraw | e2e Z9 |
| `p4-close` 를 `--regrade-write` 없이 실행 | 막음 | **드라이런으로 영구 닫힘**(재채점 · 관문 · 등재 재실행 경로 없음) | CLI 가 둘 중 하나 명시 요구 | e2e Z11 |
| 처방 에이전트가 사슬 디렉터리를 읽음 | 보는 창만 | measure/k*.json = 전기간 등급 · Sharpe · CAGR · MDD 노출 · 작업 디렉터리 조립 코드 **없음** | `p4-workdir`(네 파일만 · 헌장 날짜 가림) | e2e C19 C20 |
| 라운드 닫기 마감 상태가 등록부에 | 상태만 | **"regrade ok(B→A) · gate publish"(전기간 등급) 등록부 기록** | 등록부 = 거친 상태 + results/finalize.json | flow 39(기존) |
| 원장 변조 · 칸 사양 변경 · τ_D 날짜 · 판 표식 변경 · 영수증 없음 | 거부 | 거부(기존 정상) | 끝에서 끝 시험으로 고정 | e2e C2 C7 C12 C13 C15 Z1 |
| 연속 잡음 → 예산 종료 · 포기 걸음 | 종료 · 포기는 연속 무관 | 정상 | 고정 | e2e C18 |
| 다음 사슬 설계 입력이 결과 원장을 읽음 · 탐침 이어받기 | 읽음 | 정상 | 고정 | e2e Z7 Z8 |
| 사슬 판 고정 축 → 구 축(reinforce_program.json K200_KQ150 · 2005) 오염 | 경로 없음 | **경로 없음**(셀 워커는 칸 사양 measurement_axis epoch 로 유니버스 · 시작일; 사슬은 fixed_axes 변경 거부) — 단 n_max · 비용은 AX(reinforce_program.json)에서 읽음 | 소유 밖 패치 제안 | 정독(rf_cell_worker.R:32,83-100) |

## 3. 수리한 결함

1. **측정 경로 신선도 차단 없음** — `v1/freshness.R`(신규) `rc_data_freshness(root, today)`: ① 운영 = 감사기 `freshness_audit.R --check --items rawdata,benchmark`(데이터 레인이 오늘 추가한 판정 전용 진입점 · 자식 R · R_ENVIRON_USER 빈 파일 · 종료 0/3/1) ② 날짜 주입 · 진입점 없는 판 = 감사기 구문 트리에서 정의(as_of · .krx_hol · .sess_lag · check_freshness · audits$rawdata/benchmark 호출)를 꺼내 평가(발송 · JSON 식 미평가 · `.fa_items` 주입). 배선: `p4.R::.rcp4_run_cell`(배리어 다음 · data_stale · 원장 무기록) · `standing.R::rc_standing_measure_item`(워커 앞 · 원장 무기록 · 실패 수 무증가) · `driver.R fresh-check`(0/6) · `round.sh measure`(배리어 → fresh-check → precheck · 종료 6) · `standing-measure`(대기 측정 건너뜀 · 판정 진행) · p4 센티널 6/7. 운영 루트 건식 호출 = **stale**("[감사기 --check] status=STALE · 기준일 2026-11-09 · 낡음 rawdata"). 시험 중 발견: arrow 기본 mmap 이 Windows 에서 파일을 잡아 덮어쓰기 실패(오류 1224) → 꺼내기 경로는 `mmap = FALSE`(리프레시가 쓰는 RAWDATA 를 판정이 잡지 않게).
2. **기저 풀 규칙 변경 수혜 기록 미제외** — `p4.R::.rcp4_rule_benefit`(rf_runner_gates.R 의 `.rfg_rule_benefit` · `.rfg_s1` 를 구문 트리에서 꺼냄 · 복제 없음) · 등급 경로(A/B)만 · 사유 `rule_change_beneficiary` / 판독 불가 `rule_change_unknown`.
3. **동시 진행 경합** — `.rcp4_append(guard)` 잠금 안 사건 단일성 재확인(`.rcp4_unique_guard`) · 측정 점유 `measure/<tag>.claim`(ps::ps_pids 생존 판정 · ps 1.9 에는 pid_exists 없음 — 처음 구현이 이것 때문에 항상 busy 였고 시험이 잡았다 · OneDrive 읽기 전용 속성 chmod 뒤 삭제).
4. **측정 실패 걸음으로 사슬 영구 정지** — `rc_p4_step_abandon` + `p4-step-abandon`(실패 ≥ RC_STANDING_MAX_FAILS · 사유 τ_D 검사 · r7 NA). 닫기 시행 집합 산출 판독을 `.rcs_str` 로(NULL 산출에서 vapply 오류 방지) · `finalize.json::n_abandoned`.
5. **p4 닫기 요청 거두기 누락** — 새 등급 A 아님 = `rcg_withdraw`(관문 파일에 있을 때 · 쓰기 모드).
6. **드라이런 닫기 영구화** — `driver.R p4-close` 가 `--regrade-write | --regrade-dry-run` 명시 요구.
7. **처방 작업 디렉터리 부재(누출면)** — `rc_p4_generator_workdir` + `p4-workdir`(네 파일 · 사슬 밖 빈 폴더만 · 헌장 τ_D 뒤 날짜 가림 · 부모 칸 · 도구 상자 등급 표기 검사).
8. **라운드 닫기 등록부 누출** — `register.R::rc_close` 가 칸별 마감 상태(재채점 전후 등급)를 `results/finalize.json` 으로 · 등록부엔 거친 상태 + 경로 · md5(`rc_close_finalize` 반환에 `detail`).
9. **이식성 금칙 ④** — `round_candidate_gate.R::.rcg_root` 와 그 시험 러너가 QM_ROOT 를 CLAUDE_PROJECT_DIR 앞에 둠 → 순서 교체(시험 러너는 self-first 유지). 이식성 검사에서 두 파일 위반 사라짐(기준선 손대지 않음).
10. README — 신선도 절 · 명령 순서 · 포기 · 작업 디렉터리 · 동시 진행/재진입 · 기저 풀 사유 · 닫기 거두기 · rc_close finalize.json · freshness.R 모듈 · RELEASES.json 부재 명시.

## 3b. 못 고친 결함 · 패치 제안(소유 밖)

- `02_Infrastructure/ops/morning_steps/freshness_audit.R:76` (데이터 레인) — max_sess 를 준 항목에서 `sess` 가 NA(휴장일 연도 미수록)이면 달력 축만으로 FRESH. 측정 차단용 `--check` 에서는 `unreadable` 로: `if (!is.na(max_sess) && is.na(sess) && FA_CHECK) status <- "PARSE_FAIL"` 류. 지금 ①경로는 이 경우를 통과시킨다(②경로는 막는다 · 시험 F6).
- `02_Infrastructure/ops/rf_cell_worker.R:32,95-99` — `n_long/n_max = AX$n_max` · `commission = AX$commission_bps` 를 `06_Registry/reinforce_program.json::fixed_axes`(구 축 표기 K200_KQ150 · 2005 가 남은 파일)에서 읽는다. 값(25 · 15)은 정본과 같지만 출처가 칸 사양(`SPEC$fixed_axes`)이 아니다 → 칸 사양 값 우선 · 정본(constraint_defaults.json) 대조로 바꿀 것. 유니버스 · 시작일은 칸 사양 epoch 로 이미 갈린다(오염 경로 없음).
- `.claude/skills/research-program/SKILL.md:65-75` — 사슬 절에 `p4-base-measure` · `p4-step-measure` · `p4-step-abandon` · `p4-workdir` · `p4-close --regrade-write` 가 없고 `p4-step-decide --artifacts` 를 측정 수단처럼 적었다(지금은 측정 기록 대조용). README 의 명령 순서로 교체.
- `02_Infrastructure/ops/standing_board_run.sh` — 수리 뒤 standing-measure 는 낡음이면 측정만 건너뛰고 rc 0(판정 진행). 보드 로그에 '[신선도] … 건너뜀' 줄이 남는다. 보드가 센티널 `judged_data_stale` 를 요약 줄에 싣도록 제안.
- r7 판독(`p4.R::rc_p4_step_decide` · `abs(dS) ≥ 여유` = signal) — 크게 나빠진 걸음도 signal 이라 연속 잡음 예산을 끊는다(시험 Z10 기록). 판정 규칙 성격이라 고치지 않았다 — 도훈 결정 항목(§8).

## 4. 업데이트 누락 감지 표

| 산출물 | 생산자 | 주기 | 신선도 검사 | 소비자 | 낡았을 때 동작(수리 뒤) |
|---|---|---|---|---|---|
| `.cache/RAWDATA.parquet` · `benchmark.parquet` | daily_refresh | 매 거래일 아침 | 감사기 세션 축(레인 A) + **측정 직전 rc_data_freshness(신규)** | 셀 워커 · 상설 · P4 | 측정 거부(data_stale · 원장 무기록 · 다음 틱 재개) |
| 팩터 DB 판(`06_Registry/factor_db_vintage.json`) | 팩터 DB 수리 | 수리 때 | fdv_stamp 판 표식 · fdv_stale | P4 측정 · 기저 풀 · A 관문 | 사슬 도중 변경 = 측정 · 판정 거부(새 사슬) · 낡은 레인 측정 = 기저 풀 제외 |
| `standing_ledger.jsonl` | 상설 판 | 틱마다(예약 작업 미등록) | 앞 줄 md5 사슬 | 기저 풀 | 끊긴 원장 = 자격 목록에서 빠짐(경고) |
| `chain_steps.jsonl` | 사슬 명령 | 걸음마다 | 앞 줄 md5 사슬 · 잠금 안 재확인 | 상태 · 설계 입력 · 닫기 | 끊김 = 모든 명령 거부 |
| `06_Registry/round_outcomes.jsonl` | rc_close · rc_p4_close | 닫을 때 | 판독 불가 줄 = 멈춤 · τ_D 글 검사 | 다음 설계 입력 · rxg_revise 근거 | 손상 = 설계 입력 생성 거부 |
| `06_Registry/rx_generator.json` + g<n>/*.md | rxg_revise(철학 영수증) | 개정 때 | 파일 md5 = 등록부 = 사슬 판 | 걸음 열기 · 사슬 판 검사 | 무등록 수정 = 걸음 열기 거부 |
| `authoritative_remeasure.json`(후보) | 셀 워커 · sr_regrade | 측정 · 닫기 | 수혜 표식 · selection_gate.mode | rcg_route · 기저 풀 | 재채점 없음 = selection_check_missing 보류 |

## 5. 안 쓰는 것 — `dead_E1_l1.tsv` 24건(certain 6 · probable 18 → delete 13 · decide 8 · keep 3). 핵심: `_lib` 일회성 파이프라인 3종 · 그 하위 도구 · 로그 · round_kit 계열(P4R01 골격 · test_round_kit_*) · measure_server.R(실행기 미연결) · P2R05 고유 실행기.

## 6. 속도

- 걸음 1회 임계 경로: 설계 입력/작업 디렉터리(R · 수 초) → **생성기(LLM 처방 에이전트 · 세션 Q 가 띄움 · 사람 · 세션 대기)** → step-open(수 초) → step-measure(셀 1개 · 실측 10-20 기준 새 프로세스 54초(요인 분석 끔) ~ 188초(켬) · 오버레이 · ML 칸은 미측정) → step-decide(보는 창 지표 · 행동 카드 · 수 초~수십 초).
- 상위 시간 소모처: ① 생성기 호출 · 세션 왕복(자동 루프 없음 — 사슬을 도는 러너 · 예약 작업이 없다) ② 셀 측정(요인 분석 켜면 40%가 run_analysis — 사슬 기본 러너는 끔) ③ 상설 판 미등록으로 기저 풀 입력 0(리서치 처리량 0).
- 하루 처리량 한계: RAM 32GB = 셀 워커 2개(메모리 카드 7.45GB/워커) — 사슬은 순차(한 사슬 = 한 번에 한 칸)라 병렬은 사슬 2개까지. 측정 서버(WP2) 미연결 → 칸마다 RAWDATA 적재 12초 · 워커 기동 18초 반복.
- 판정 불변 단축안: (a) 사슬 러너 1개(설계 → 생성기 → 열기 → 측정 → 판정을 한 명령으로 · 사람 확인은 등록 · 닫기 영수증 두 곳만) (b) measure_server 를 p4 러너 기본으로(결과 동일 실증 10/10 이미 있음) (c) 두 사슬 병렬(서로 다른 기저).

## 6b. 출시 준비 — 코어 v1 출시 · P1S01 등록을 막는 것

- `round_core/RELEASES.json` **파일 없음**(README · load.R 가 '출시 판 매니페스트 검사'를 말하지만 검사 대상이 없다) — 출시 = 매니페스트 md5 고정 + 그 뒤 v1 파일 수정 금지 검사. 이번 수리로 v1 매니페스트가 바뀌었다(freshness.R 추가) → 출시 전 마지막 변경으로 계상.
- P1S01 사양(`04_Research/programs/P1_RETURN/P1S01_standing_qualification`) 등록 조건: 초안 · 격리 점검 기록 ok · **철학 Superfan P1 리뷰(파일 `…_P1_P1S01.md` + 판단 원장)** · 고정 대상 커밋 · 생성 함수 핀(rc_p1_cell_spec md5)이 지금 코드와 같을 것 — p1.R 은 이번에 안 바꿨다.
- 상설 정기 실행 예약 작업 미등록(도훈 승인 사항) · standing 보고 발송(--send) 경로는 드라이런만 시험됨.
- 사슬: 기저 풀 자격 0(§7-1) → 첫 사슬 등록 불가. 생성기 g1 evidence 0(첫 판 · 정상). 칸 delta → 칸 사양 합성 도구 없음(수동).
- 미뤄 둔 P2R05: 등록본 보존 · 코어 이전 실행기 · 재개 시 재핀(불일치 개수 미확인) — 코어 출시를 막지 않게 '뒤로 미룸' 상태 유지 권고.

## 7. P/L 우상향 관점 최대 제약 3

1. **기저 공급 0** — P1S01 상설 판 미등록 · 풀 자격 경로는 등급 B 이상(현 축 A 3건은 재무 v1 보류 · B 다수는 팩터 DB 수리 전 측정 = factor_db_stale) → 사슬이 출발할 엔진이 없다. 증거(운영 건식 `round.sh - p4-pool` 11-10): **엔진 12 · 자격 0** — factor_db_stale 12 · not_qualified 10 · needs_long_leg 9 · audit_not_passed 4 · implementation_suspect 4 · no_engine 2 · stage_artifacts 에 standing_ledger 0.
2. **사슬은 사람 · 세션이 한 걸음씩 민다** — 생성기 호출 · 작업 디렉터리 조립 · 칸 사양 합성(delta → 칸) 코드가 없었다(작업 디렉터리는 이번에 추가 · delta 적용은 아직 없음). 하루 걸음 수 = 세션 수.
3. **오늘 자료가 낡았다** — RAWDATA 11-06 정지(운영 건식 판정 stale). 수리 전이면 이 상태로 잰 칸이 정상 기록으로 남았다. 이제는 측정이 멈춘다 → 리프레시 복구가 리서치 처리량의 선행 조건.

## 8. 도훈 결정 필요

- (a) r7 판독: 크게 나빠진 걸음을 'signal' 로 볼 것인가(현행 · 연속 잡음 예산을 끊음) vs 'noise'(개선 없음 = 잡음 이내로 셈 · 예산 빨리 소진). 권고 = noise(목표 축 '개선' 판독 · R7 취지). 판정 규칙 변경 = 새 사슬 판부터.
- (b) trial_budget.R: 등급 v3.4 스윕 관문 = 선택 현실 점검인데 계획 도구는 DSR 표만 낸다. 권고 = 시행 수 대신 '실효 독립 시행 수'(RC 산출)로 계획하는 판을 추가(지금 표는 진단).
- (c) 사슬 러너 자동화 범위(생성기 LLM 호출 무인화 여부 · 예산 상한) · 상설 판 예약 작업 등록(standing_board_run.sh).

## 9. 바꾼 파일 · 시험

- 바꾼 파일: `04_Research/programs/_lib/round_core/v1/freshness.R`(신규) · `v1/load.R` · `v1/p4.R` · `v1/standing.R` · `v1/driver.R` · `v1/register.R` · `round.sh` · `README.md` · `02_Infrastructure/programs/round_candidate_gate.R` · `08_Tests/programs/test_round_candidate_gate.R` · `08_Tests/programs/test_round_core_v1_p4_chain.R`(신선도 주입) · `08_Tests/programs/test_round_core_v1_standing.R`(주입 + E0) · `08_Tests/scenarios/test_scn_l1_chain_e2e.R`(신규).
- 새 시험(총괄 SUITES 등록 요청): `08_Tests/scenarios/test_scn_l1_chain_e2e.R` (57/57 · 40초).
- 코어 판 매니페스트: v1 파일이 바뀌었다(freshness.R 추가 포함) — v1 은 미출시라 판 규칙 위반은 아니지만, P2R05 등 v1 핀을 건 등록본이 있으면 재개 때 재핀 대상(미확인).
- 돌린 시험(수리 뒤 · 한 번에 하나): p4_chain 123/123 · candidate_gate 22/22 · flow 39/39 · v1 33/33 · p2 34/34(뮤턴트 15/15) · standing 94/94(+E0) · measure_server 34/34 · selection_regrade 11/11 · trial_budget 16/16 · standing_board_run 16/16 · scn_l1_chain_e2e 57/57 · r_portability = 두 파일(round_candidate_gate.R · 그 시험) 위반 해소(전체 40 fail 은 다른 파일들).
- 확인 못 한 것: 실제 셀 워커로 잰 걸음의 시간(오버레이 · ML) · P2R05 핀 불일치 개수 · 예약 작업 상태 직접 조회 · 요인 수익률 캐시 v1.1 재빌드 영향(이 레인 시험은 운영 요인 표를 읽지 않는다 — 합성 자료 · 가짜 재채점).

---

## 10. 추가 과제 ① — 채택 규칙 대 헌장(E2 패치 제안 집행 · 빈칸 14~24)

| 조건 | 지표(보는 창) | 비교 기준 | 숫자 출처(새 숫자 없음) | 필수 | 시험 · 돌연변이 |
|---|---|---|---|---|---|
| N1 강세 구간별 참여 | `uc_seg_ok_share_vis` | 엔진 기준 칸(base_measured) 구간별 · ≥ 기준 − 0.2·\|기준\| · 짝 ≥ 2 | 헌장 빈칸 4 (B) 80% · 7 · 과반 = behavior_card majority_share | v2 필수 | e2e N1(둘 놓침 = 기각 · 중앙값 통과) · N1 위반 주입 |
| N2 깊은 위기 과반 | `deep_crisis_nonworse_share_vis` | 부모 · 깊은 = 시장 낙폭 ≥ 중앙(pair.R rc_deep_crisis_keys) · 깊은 짝 ≥ 2 | 빈칸 2 · 23 | v2 필수 | e2e N2(깊은 위기만 악화 · 중앙값 개선 = 기각) |
| N3 낙폭 경로 | `d_cdar_vis`(+ `rec_delay_share_vis` 기록) | 부모 | 빈칸 5 · 18 · cdar_alpha(behavior_card) | 선택 | e2e N3 + 돌연변이(부호) |
| N4 집중 | `worst_name_contrib_deep_vis` | 절대 한도 | 빈칸 1 · P3R03 prereg single_name_loss_floor −0.1 | 선택 | e2e N4 + 돌연변이 · N4b 순수 함수 + 돌연변이 |
| N5 β 비대칭 | `beta_asym_ok_vis` | 노출 블록만 | 빈칸 3 · 8 | 선택 | e2e N5(노출 기각 · 비노출 해당 없음 채택) + 돌연변이 |
| 재료 없음 | — | — | — | — | e2e N6 = 미측정 = 기각 |
| 현금 기계(기저 풀) | `cash_machine` 열 | 상설 판정 visible.uc_vis < uc_floor | 빈칸 24 · uc_floor | 제외 사유 | e2e N8 + 돌연변이 · 등급 경로 = unknown(기록에 보는 창 값 없음 — grade_v3.cr.uc_median 은 전기간이라 쓰지 않음) |
| 결론 기준점 | `extra.conclusion`(engine_relative · market_relative · market_sentence_allowed) + 라벨 | 엔진 · 시장(하락 포착 ≤ 1) | 빈칸 16 | 기록 | e2e Z10b |
- 판 구분: 사슬 판 `rules_version`(새 판 = p4_rules_v2 · 표식 없음 = v1 판독 · 새 등록은 v2 만) — 옛 원장을 다시 읽어도 판정 불변.
- 미구현(패치 제안 · 이유): **빈칸 14 MC8 선택 방어 라벨** — 걸음마다 `matched_controls.R::mc_card(dir)`(크기 × β 동시 짝 · 가격 패널 적재 · 칸당 수 분)를 판정에 넣어야 한다. 판정 시간 · RAM(워커 2개 한도)과 겹치고 MC8 짝 자체가 τ_D 자르기 판을 따로 요구한다 → 제안: 방어 블록 걸음의 측정 직후 `mc_card(dir, tau_d)` 의 보는 창 귀속을 `step_measured` 옆 파일로 남기고, 사슬 판 선택 규칙 `mc8_selection_vis ≥ 1`. **빈칸 21 재시드 띠** — 학습 처치 블록에 같은 사양 재시드 칸 2개를 같은 걸음에 묶어야 해 '한 걸음 = 칸 하나' 원장 모델과 시행 회계(+2)를 바꾼다 → 제안: 걸음 원장에 `seed_replicates` 사건 추가 · 띠 안 승리 = 'seed_undecided' 기각.
- 생성기 성적표 연결: `rc_p4_generator_review` 가 `rx_generator_scorecard.R::rxg_scorecard/rxg_scorecard_md` 를 읽기 전용으로 불러 '판별 성적표' 절을 싣는다(사슬 검증 뒤 원장 · 오류는 그 절에만) — e2e Z10c. ⚠ 성적표의 noise_streak 는 r7 == "noise" 만 센다 — v2 의 악화도 r7 = noise 로 적으므로 그대로 맞는다(r7_detail 로 악화 구분).

## 11. 추가 과제 ② — 총괄 결정 (a) (b) (c)

- **(a) r7**: v2 = `dS ≥ +여유`일 때만 signal · 잡음 이내 · 악화 = noise(`r7_detail` = worse | within | improve). e2e N7: 악화 2회 → 연속 2 = 예산 종료 · 돌연변이(옛 |dS| 규칙) = signal · 열기 허용. Z10 기대 갱신.
- **(b) trial_budget.R v3.4 판**: `tb_rc_required_t(n_eff, α)`(계약 n_eff 정의의 역) · `tb_rc_required_t_rho(K, rho, cfg)`(같은 상관 정규 최댓값 · rho 입력 필수 · 재표집 · 씨앗 = grade_v3.json::selection_bias) · `tb_rc_max_variants` · `tb_rc_from_trials`(과거 시행 집합 → 계약 src_check_dirs 그대로) · CLI `trial_budget.R rc <rho> [<기대 t>]`. DSR 표 = 진단. 시험 `08_Tests/programs/test_trial_budget_rc.R` 10/10(돌연변이 1). 예: rho 0.5 · 기대 t 2.95 → 최대 변형 62.
- **(c) 무인 구간 · 사람 지점**

| 구간 | 명령 | 무인 가능 | 종료 코드 | 잠금 · 멱등 |
|---|---|---|---|---|
| 사슬 판 만들기 · 등록 | `p4-register --p1 --t1` | **사람/감독** — 철학 P1 · 판단 T1 영수증 | 0 / 오류 1 | 원장 비어 있어야 · 잠금 안 재확인 |
| 기준 칸 | `p4-base-measure` | 무인 | 0 측정·already · 4 배리어 · 6 데이터 낡음 · 7 점유 · 1 실패/판 표식 | 점유 claim · already |
| 걸음 설계 | `p4-workdir --out` → 생성기(LLM) | 무인(LLM 호출 자동화는 별도 과제) | 0 / 1 | 빈 폴더만 |
| 걸음 열기 | `p4-step-open … [--probe-ref]` | 무인(생성기 JSON → 칸 사양 합성 도구 필요 · 미구현) | 0 / 1(거부 사유) | 잠금 안 재확인 |
| 걸음 측정 | `p4-step-measure --k` | 무인 | 0 · 4 · 6 · 7 · 1 | 점유 · already |
| 걸음 판정 | `p4-step-decide --k` | 무인 | 0 / 1 | 잠금 안 재확인 |
| 실패 걸음 포기 | `p4-step-abandon --k --reason` | 무인 가능(실패 ≥ 2 기계 조건) — 사유 문장 필요 | 0 / 1 | — |
| 예산 종료 감지 | `p4-status`(연속 잡음 · 최대 걸음) · 열기 거부 '예산 소진' | 무인 | — | — |
| 닫기 | `p4-close --regrade-write --p2 --t2` | **사람/감독** — 철학 P2 · 판단 T2 영수증 · 해석 · 탐침 | 0 / 1 | 재진입 멱등 |
| 원장 격리 | `p4-quarantine` · `- outcomes-quarantine` | **사람만** | 0 / 1 | — |
- 레인 틱(`02_Infrastructure/ops/reinforce_auto_tick.sh`)에 붙일 진입점 제안: `bash round_core/round.sh <사슬> p4-tick`(미구현) = ① 상태 판독(닫힘 · 예산 소진 · 영수증 대기면 0 종료 + 상태 줄) ② 기준 칸 없으면 p4-base-measure ③ 열린 미측정 걸음 측정 ④ 측정된 미판정 걸음 판정 ⑤ 다음 걸음은 생성기 산출 파일이 있을 때만 열기. 종료 코드 = 위 표 그대로(4 · 6 · 7 = '다음 틱'으로 레인 틱이 rc 0 처리). 잠금 = 틱의 기존 배리어(halt_refresh_lock) + 사슬 단위 점유(measure/*.claim) + 원장 잠금(.lock) — 레인 틱은 사슬마다 한 프로세스만 돌리면 충분. 틱 앞에 `fresh-check`(6) 를 한 번 부르면 낡은 날 전체 건너뜀.
- SKILL.md §0-1(소유 확장) · standing_board_run.sh 건너뜀 표시(센티널 judged_data_stale → 로그 한 줄 · 시험 10 · 10b 돌연변이) — 고쳤다.

## 12. 추가 과제 ③ — 지식 축적 고리 결함(K P1~P6)

| 항목 | 수리 | 시험 · 돌연변이 |
|---|---|---|
| P1 쓰기 · 읽기 검사 비대칭(원장 독살) | `util.R::rc_input_issues`(τ_D 날짜 · 등급 표기) 를 결과 원장 쓰기 · `.rcp4_assert_clean` 이 함께 쓴다 · 옛 나쁜 줄은 처방 입력 읽기(`rc_outcomes_read(tau_clean)`)에서 그 줄만 빠진다(경고) | e2e K1(+돌연변이) · K1b · K 시험 L10 · L10b |
| P4 날짜 표기 변형 | `RC_TAU_ALT_RX`(한국어 연월 · 슬래시 · 점 · ’yy년 · 분기 2종 · ‘n분기’) — 검사와 가림 같은 규칙 · '2022년 12월까지' 등 정상 문장 통과 | e2e K4(+돌연변이) · K 시험 L6c · L6d |
| P2 사슬 사이 기억 | 설계 입력 §4b `.rcp4_other_chain_rejects`(사슬 · 걸음 · 블록 · 사유 코드만 · 블록마다 최근 max_steps 줄) | e2e K2(+돌연변이) · K 시험 L3c |
| P3 탐침 이어받기 | `rc_p4_step_open(probe_ref)` · CLI `--probe-ref` — 열린 탐침만 · 열기 뒤 `rc_probe_consume(ref, "<사슬>#k<k>")` | e2e K3 · K 시험 L8c |
| P5 칸 L-code | ⚠ K 의 '쌓인다'는 **확인되지 않음** — `rf_cell_worker.R:27` 이 이미 `QVEST_RP_NO_LCODE=1` 을 무조건 켠다. 방어 깊이로 p4 러너 · measure_cell.R · 상설 측정에도 켬 | e2e K5(+돌연변이) |
| P6 손상 줄 격리 | `rc_outcomes_quarantine`(kind = quarantine 줄 + 사본 · 원장 줄 안 지움) · `rc_p4_steps_quarantine`(옆 파일 · 다음 줄 prev 수용 · 해시 재연결 없음) · CLI 2개 · 사람 호출만 | e2e K6(+돌연변이) · K 시험 L7c |
- K 시험 GAP 8 → 1(남은 L3b = 설계 입력에 과거 negative(hypothesis_index) — K §4 패치 목록 밖 · 미처리).
