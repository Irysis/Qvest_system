# WP3 시험 기록 — 충실구현 레인 다중 슬롯 · GPU 임대 · 쓰기 잠금

- 브랜치 `worktree-agent-a379a174f353bfd3f` · 작업 커밋 `109d910a1` · main 병합 커밋 `a16db8833`(main `1a9fbbd6c` 까지 · 충돌 0)
- 환경: Windows 11 · Git Bash · R 4.5.2 · 파이썬 = `.venv_qvest_ml`(3.12) · GPU 미사용(시험 프로세스 `CUDA_VISIBLE_DEVICES` 빈 값)
- 격리: 전부 임시 경로(`QVEST_RP_*` · `QVEST_GPU_LEASE` · `QVEST_RF_CONFIG` · `QVEST_JUDGMENT_LEDGER_PATH` · `QVEST_SESSION_RESUME_PATH` ·
  등록부 `path=` · 결정 기록부 `root=` · `QVEST_DR_CLAIM`) · 에이전트 = 대역(`RF_CLAUDE_BIN`) · 검증기 = 대역(W4) · 발송 = `QVEST_TG_DRY_RUN=1`
- R 은 `~/.Renviron` 의 QM_ROOT(운영 체크아웃)로 환경을 덮는다 → R 시험은 `R_ENVIRON_USER=<빈 파일>` + `QM_ROOT=<worktree>` 로 돌려 worktree 코드를 시험했다.

## main 병합 · 충돌 해소

- `git merge --no-ff main` → 병합 커밋 `a16db8833`(ort 자동 병합 · **충돌 0**). main 쪽 `5170d410d`(THGNN 축 덮어쓰기 · 메모리 넘침 처방)와
  `1a9fbbd6c`(인계 카드)를 받았다.
- `rf_replication_verify.R` 두 변경이 서로 다른 구획이라 겹치지 않았다 — main 의 덮어쓰기 블록(`.BASE_ARGS` 뒤 · `replication_axis_overrides.json` ·
  `fail("axis_override_invalid")` · `Sys.setenv(env)`)과 WP3 의 요청 경로(`QVEST_RP_REQUEST`) · 저널 slot · 공유 기록 잠금 · 슬롯 모드 폴백 금지가
  모두 남았다(행 112 · 122 · 133 · 649 · 852~866 · 876 · 942).
- 상호작용 확인(W8): 덮어쓰기 열쇠 = 논문 키라 슬롯과 무관 · 대표(행 867)와 변형(행 892 · `modifyList` 가 축 키를 안 건드림)이 같은 `.BASE_ARGS` ·
  `fail()` 은 슬롯 요청을 닫는다 · `env` 는 그 검증기 프로세스에만.
- 두 번째 병합 `61990e0bb`(main `9d2b63ccc` 까지 — WP5 상설 자격 `ccbe55080` + SUITES 편입) · 충돌 0(SUITES 두 항목 공존). WP5 의 레인 스캔은
  작업 디렉터리(`04_Research/strategies/RP_AUTO_*`)를 읽고 요청 파일을 읽지 않아 슬롯 전환과 무관. 병합 뒤 재실행: round_core_v1_standing 84/84 ·
  round_core_v1_flow 27/27 · qv_lock 24/24 · qv_lock_cross 13/13 · replication_slots 29/29 · ledger_write_locks 11/11 · replication_slots_lane 18/18 ·
  replication_lane 89/89.

## 새 시험 (병합 뒤 · 최종 코드)

| 시험 | 결과 | 양성 대조(위반 주입) · 뮤테이션 |
|---|---|---|
| `08_Tests/ops/test_qv_lock.py` | 24/24 | 두 프로세스 경합(시간 제한 · 대기 후 획득) · 죽은 소유자 즉시 회수 · pid 재사용(시작 시각 불일치) · 소유자 표식 없음(유예 · 경과) · 매달린 소유자 회수 + 펜싱(빼앗긴 쪽 LockLost) · 회수 경합(+뮤테이션: 토큰 대조 제거 → 새 잠금을 지움) · 8프로세스 × 3회 구간 겹침 0 · 임대 획득 · 거부 · 멱등 · 해제 · 상한 자르기 · 만료(+뮤테이션: 만료 비교 제거 → held) · 보유자 사망 · 이력 · CLI · 셸 API(qv_lock.sh) |
| `08_Tests/ops/test_qv_lock_cross.R` | 13/13 | R 이 잡은 잠금 = 파이썬이 산 잠금 · 파이썬이 잡은 잠금 = R 이 산 잠금(시간 초과 · 놓으면 획득) · 파이썬 형식 죽은 소유자 R 회수 · R 재진입 · R 펜싱 · R 생존 판정 양방향 · 잠금 위치 규칙 동일 · GPU 임대 R API |
| `08_Tests/ops/test_replication_slots.py` | 29/29 | S1 등급별 발행 · S2 두 틱 동시(슬롯당 발행 1회 · +뮤테이션: 디스패처 · 발행 잠금 제거 → 같은 슬롯 2회) · S3 같은 논문 중복(duplicate_held_elsewhere · 끝난 논문은 회수 · +뮤테이션: 생존 판정 제거 → 빼앗음) · S4 슬롯 소유자 사망(즉시 회수 · 재착수 · 그 논문 보호) · 생존 소유자 유지 · claim_live_long 1회 · pid 재사용 · S5 GPU 오배치 → 인계함 → gpu1 · 구현 의존성 우선(+뮤테이션: 의존 정규식 무력화) · S6 임대 유효 = GPU 보류 · 만료 = 틱이 풀고 재개(+뮤테이션: 만료 비교 제거 → 영영 보류) · 보유자 사망 · 임대 중 GPU 발행 안 함 · S7 구판 요청 인수(살아 있는 구판 작업자 = 점유) · S8 용량 · S9 환경 백오프 · S10 일 소진량 · S11 설정 켜기/끄기(LEGACY 복귀) · S12 틱 요약 → 부팅 줄 |
| `08_Tests/ops/test_replication_slots_lane.sh` | 18/18 | 레인 셸을 실제로 돌린다 — D1 디스패처 · D2 스위치 꺼짐 · D3 구판 설정 무동작 · W1 같은 슬롯 작업자 3개 동시 = 에이전트 1회 · 저널 slot 필드 · W2 CPU 슬롯의 GPU 논문 = 에이전트 0회 인계 · GPU 슬롯 없는 설정 = 그대로 · W3 측정 직전 관문(torch 엔진 = verify-only 인계 · 아니면 통과 · +뮤테이션) · W4 인계분 = 검증기만(슬롯 요청 경로 · RP_SLOT 전달) · W5 다른 슬롯이 쥔 논문 = 착수 안 함 · W6 임대 = GPU 새 착수 보류 · 연쇄는 진행 · W7 디스패처 → 작업자 2개 끝까지 · **W8 main 병합분(논문별 측정 축 덮어쓰기)이 슬롯 경로에서도 칸마다 적용** |
| `08_Tests/programs/test_ledger_write_locks.py` | 11/11 | 동시 writer 2개 × N건(저장 직전 0.3초 쉼으로 경합 창을 넓힘): ①판단 원장 10/10 · id 중복 0 ②재개 저널 10/10 ③프로그램 등록부 10/10 · 잠금 자리 = `.cache/registry_locks` ④결정 기록부 6/6(09-25 claim + CAS — 고치지 않음 · 실측) — 각자 **뮤테이션(잠금 제거)판은 갱신을 잃는다**(①5/10 ②5/10 ③5/10 ④<6) · ⑤검증기 공유 기록 구간(슬롯 3개) 겹침 0 · 종료 해제 · 구판 무동작 |

## 기존 시험 (worktree 코드 · 병합 뒤)

| 시험 | 결과 | 비고 |
|---|---|---|
| `test_replication_lane.sh` | 89/89 | 구판 단일 슬롯 동작 불변(S1 · S2 · C1~C5 · K1~K7 · J1~J7). ★병합 뒤 부하 중 1~3건이 흔들렸다 — `printf "$큰문자열" \| grep -q` 가 pipefail 아래서 SIGPIPE(141)로 일치를 실패로 접는 기존 시험 결함(검증기 · 레인 스크립트가 ~100KB 로 커지며 드러남). 입력을 끝까지 읽는 `gq` 로 22곳 바꿈 → 부하 중 89/89 |
| `test_rf_verify_*`(extract_pkgs · judge_hold · pit_preflight · report_composition · tg_target · variants) | 7 · 14 · 4 · 8 · 39 · 31 — 전부 통과 | 검증기 추출 시험 |
| `test_rp_env_failure_classify` · `test_rp_telegram_relaxed` · `test_rp_commission_basis` · `test_rp_count_paper` | 32 · 7 · 9 · 6 — 전부 통과 | |
| `test_rf_reimplement_queue.R` · `test_rf_request_guard.R` | 40/40 · 10/10 | `only_key` · `slot` · `issued_request` 변경 |
| `test_rf_audit_tg_brief.R` · `test_rf_prompt_quote_parity.R` | 22/22 · 4/4 | |
| `test_rf_audit_not_run_blocks_open.R` | 39/40 | C4(정적 패턴 `rp_verify; exit`) — **main 코드에서도 같은 실패**(10-17 연쇄 변경 이후 기존 실패) |
| `test_q_judgment_ledger.R` · `test_session_resume.R` | 50/50 · 13/13 | |
| `test_program_registry.R` | 24/29 | **main 코드에서도 24/29**(운영 등록부 큐 상태에 묶인 기존 실패 5) |
| `test_program_paper_sync.R` · `test_round_core_v1_flow.R` | 23/23 · 27/27 | pr_* 잠금 경유 |
| `test_rf_clean_lane.sh` · `test_llm_single_entry.sh` · `test_rf_llm_fallback.sh` · `test_refresh_barrier.sh` | 107/107(생략 1) · 54/54 · 27/27 · 80/80 | |
| `test_boot_lean_programs_line.R` · `test_boot_lean_rf_budget.R` · `test_superfan_watch.R` | 13/13 · 8/8 · 35/35 | |
| `test_rf_l2_auto.sh` · `test_rolling_defensive.R` · `test_ds_convex_retired.R` · `test_rf_axiom_inject.R` · `test_run_wf_env_defaults.R` | 10 · 52 · 12 · 16 · 7 — 전부 통과 | (병합 전 실행) |
| `test_mechanism_atlas.R` · `test_module_admission_seam.R` · `test_paper_atlas_run.sh` | 10/11 · 35/38 · 3/5 | **main 코드에서도 같은 수**(기존 실패) |
| `test_suite_enrollment.sh` | 9/10 | V7 = 실 트리 미편입 13건(기존) — WP3 새 시험 5종은 SUITES 등재 확인 |
| 선택기 기본 출력 | 바이트 동일 | 원본 `rf_next_paper_pick.py` 와 `cmp` |
| `test_rf_base_cache_seed.R` | 미실행 | 실제 `.cache/rawdata.parquet` 를 읽는다(worktree 에 없음 · 무거운 R 금지) |

## 분리 실행 생존(MSYS)

- `nohup bash -c '…' &` + `disown` 뒤 부모 셸이 곧바로 끝나도 자식이 12초 뒤 파일을 썼다(11:06:31 부모 종료 → 11:06:43 자식 기록).
- 예약 작업(Task Scheduler) 맥락은 배포 첫 틱에 실측한다(DEPLOY.md Step 7 · 실패 시 `replication_lane.launch_mode = "foreground"`).

## 사건 (시험 중 부수효과 · 정직 기록)

1. **W4 첫 판이 진짜 검증기를 돌렸다**: 시험 PATH 에 Windows 형 경로(`C:/…`)를 넣어 ':' 에서 갈라져 검증기 대역(`Rscript`)이 안 잡혔다. 진짜
   `rf_replication_verify.R` 가 임시 슬롯 요청으로 돌았고, R 이 `~/.Renviron` 의 QM_ROOT(운영 체크아웃)로 ROOT 를 잡아 운영 `.env` 의 텔레그램
   자격을 읽었다 → 엔진이 작아 `engine_too_small` 로 끝나며 **실패 알림 1통이 발송됐을 가능성이 크다**(제목 '[1계층·충실구현] LSTM forecasting of
   stock returns' · 운영 `.cache/tg_locks/qvest_tg_lock_prep_충실구현_LSTM_forecasting_of_stock_returns_549347a4_20261020103045.lock` 생성 ·
   발송 실패 기록 없음). 그 밖의 운영 파일 쓰기는 없었다(요청 · 저널 = 임시 경로 · 운영 programs_log 무변화). 잠금 파일은 운영 main 무접촉 원칙에 따라
   지우지 않았다(같은 제목 중복 발송 방지 잠금 · 무해).
   - 수리: 시험 PATH 를 MSYS 형(`cygpath -u`)으로 · 대역이 PATH 에서 먼저 잡히는지 확인한 뒤에만 W4 실행 · 모든 레인 실행에 `QVEST_TG_DRY_RUN=1`.
2. **기존 레인 시험 S2 가 worktree 의 재구현 대기열을 바꿨다**: 공급기 `next_replication.R` 이 한때 `QVEST_RP_REQUEST`(시험 격리 변수)를 읽게
   바꿨더니 격리 요청(done)이 '빈 자리'로 보여 worktree `06_Registry/reimplement_queue.json` 2항목을 issued 로 바꿨다(운영 아님 · `git checkout` 으로 원복).
   - 수리: 공급기는 `--req` 인자만 읽는다(구판 동작 보존 · 슬롯 발행기만 넘긴다).
3. 기존 시험(`test_rolling_defensive.R` 계열)이 worktree `06_Registry/ast_structure_log.jsonl` 에 2줄을 덧붙였다 — 원복(기존 시험의 동작 · WP3 무관).
