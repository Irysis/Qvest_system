# round_core — 1계층 공통 판정 코어

도훈 10-20 결정 `L1-SPEED-PLAN-20261020`(1계층 리서치 속도 극대화)의 WP1 이다.

**목적**: 라운드마다 판정 코드를 복사·확장하지 않는다. 라운드는 사양(`round_spec.json`) · 사고 기록(`DESIGN.md`) · 꼭 필요한 고유 규칙(`round_ext.R`)만 쓰고, 나머지는 공통 코어와 실행기가 한다.

**배경**: P2R04 의 라운드 전용 코드는 약 570KB, P2R05 는 약 1MB 였다. 교차 점검 필수 지적 17건 가운데 11건이 같은 규칙이 여러 곳에 적혀 생긴 문구 표류였다.

## 원칙 (보증 불변)

- **보증 장치는 그대로다.** PIT · 사전등록 → 커밋 → 측정 · τ_D · β 짝 · MC8 · 격리 교차 점검 · Superfan 을 바꾸지 않는다. 판정 규칙의 내용 · 수 · 설계 재량도 현행대로다.
- **규칙은 한 번만 선언한다**(`v1/rules.R`). 같은 선언에서 사전등록 문장 · 판정 실행 · DESIGN 표를 생성한다.
  - 수치 문턱은 근거(`basis`)나 정본 참조(`value_ref`)가 없으면 거부한다.
  - 미측정(NA)은 통과로 접지 않는다.
- **수치는 R 계약 산출만 쓴다**(AX-008).
  - 계약 파일은 읽기만 한다.
  - 진행 중 라운드(P2R05)의 핀 51개 파일은 그 라운드가 끝날 때까지 수정하지 않는다.
- **판은 불변이다.** 출시된 판은 고치지 않고, 바꿀 일이 생기면 새 판(v2)을 만든다.
  - 라운드는 판과 매니페스트 md5 를 핀으로 건다(`rc_core_manifest`).
  - 출시 기록 = `RELEASES.json`(v1 11-11 13:44 · v2 11-11 — 아래 '판 라우팅 · v2'). 사양의 `core_version` 이 그 라운드 · 판 · 사슬의 코어 판을 고른다.
- **속도 조치는 결과 동일 실증이 채택 조건이다**(`PERFORMANCE.md`). 실행 시간은 `.cache/round_core/perf/<round>.jsonl` 에 남는다.

## 사용 (P1 라운드 예)

```r
source("04_Research/programs/_lib/round_core/v1/load.R")
rc_init_p1("04_Research/programs/P1_RETURN/P1R03_<이름>", "P1R03_<이름>", engines = list(...), purpose = "...", hypothesis = "...")
```

```bash
bash 04_Research/programs/_lib/round_core/round.sh <round_dir> check      # 규칙 문장 · 핀
bash 04_Research/programs/_lib/round_core/round.sh <round_dir> draft      # prereg_draft.json + .md(점검자 · 감독용)
bash 04_Research/programs/_lib/round_core/round.sh <round_dir> reviewed 1 <점검 파일> ok
bash 04_Research/programs/_lib/round_core/round.sh <round_dir> register   # 등록 조건 ①~⑧ → 커밋
bash 04_Research/programs/_lib/round_core/round.sh <round_dir> measure    # 배리어 · 데이터 신선도(fresh-check · 종료 6) · 사전 점검 · 지문 · 재측정 → 평가 자동 연쇄
bash 04_Research/programs/_lib/round_core/round.sh <round_dir> report --next "..."   # 기본 dry-run · --send
bash 04_Research/programs/_lib/round_core/round.sh <round_dir> close --note "<해석>" --probe "<다음 탐침 1>" --probe "<다음 탐침 2>" [--lesson "<교훈>"] [--r7 noise|signal] --p2 <id> --t2 <id>
#   close 는 등록부와 결과 원장(06_Registry/round_outcomes.jsonl · v1/outcomes.R)에 함께 쓴다 — 다음 탐침 2개 이상(없으면 --no-probes "<사유>") ·
#   글에 정보 경계 뒤 날짜가 있으면 멈춘다. 다음 라운드 설계는 rc_outcomes_md(rc_outcomes_path(), "<프로그램>") 출력에서 출발하고,
#   마감 훅(p2 · p3 최종 후보 · rc_close_finalize → rcg_finalize = 재채점 → A 면 관문 · 아니면 앞선 요청 거두기)의 칸별 상태(전기간 등급 포함)는 results/finalize.json 에만 —
#   등록부 finalize 칸에는 거친 상태(done | error) + 그 파일 경로 · md5 만 싣는다(11-10 · 등록부는 다음 설계가 읽는 자리).
#   이어받는 탐침은 rc_probe_consume("<round_id>#<번호>", "<새 round_id>", rc_outcomes_path()) 로 표시한다(2026-11-10 · v10.2).
```

## 데이터 신선도 차단 (11-10 · v1/freshness.R)

측정 경로 넷(`round.sh measure` · `standing-measure` + `rc_standing_measure_item` · `p4-base-measure` · `p4-step-measure`)이 같은 판정 하나 `rc_data_freshness(root)`를 부른다 — 가격(RAWDATA) · 벤치(KOSPI200)가 직전 거래일 세션까지 와 있지 않으면 재지 않고 사유를 돌려준다(원장 무기록 · 실패 횟수 무증가 · 다음 실행에서 다시). 규칙은 아침 신선도 감사기(`02_Infrastructure/ops/morning_steps/freshness_audit.R` · 데이터 레인 소유) 것이다: ① 운영 = 그 파일의 판정 전용 진입점 `--check --items rawdata,benchmark`(자식 R · 종료 0 신선 · 3 낡음 · 그 밖 판독 불가 · 발송 없음) ② 진입점이 없는 판 · 날짜를 주입한 호출 = 그 파일에서 정의(as_of · 휴장일 · 세션 지연 · check_freshness · audits$rawdata/benchmark 호출)를 구문 트리로 꺼내 평가(세션 축 미측정 = 판독 불가). 판독 불가 = 거부(fail-closed). CLI `round.sh - fresh-check`(driver · 종료 0/6). 실행기: measure 는 종료 6(센티널 data_stale) · standing-measure 는 대기 측정을 건너뛰고 판정은 진행(센티널 judged_data_stale) · p4 측정은 종료 6. 시험은 `freshness` 인자에 판정 함수를 넣는다(우회 인자 없음).

## 상설 판 (P1 상설 자격 · WP5 · 사양 `standing: true` · 첫 판 = `P1_RETURN/P1S01_standing_qualification`)

규칙을 프로그램 단위로 한 번 등록하면, 충실구현 레인이 낸 엔진마다 라운드 의식 없이 측정 · 판정한다. R2 는 그대로다 — 규칙 · 입구 규칙 · 생성 함수 핀(`rc_p1_cell_spec` md5 · 선례 · 정본 고정 축)은 등록본에 고정되고, 항목 칸 사양은 등록된 생성 함수가 재량 없이 만든다(측정 · 판정 직전 다시 만들어 md5 대조). 판정 원장 = 사전등록 정본 옆 `standing_ledger.jsonl`(추가 전용 · 줄마다 앞 줄 md5 사슬 · 보는 창 값만). 규칙을 바꾸면 새 판(P1S02 …) — 옛 판정은 남고, 새 판이 등록되면 옛 판은 새 항목을 받지 않는다. 등록부는 읽기만 한다.

```bash
round.sh <판> standing-check            # 상설 사양 · 생성 함수 핀 · 시드 회계 검사 → standing_rules.md(사양에서 생성)
round.sh <판> check · draft · reviewed · register   # 라운드와 같다(등록은 판마다 1회)
round.sh <판> scan [--dry-run] [--max N] [--out f]  # 레인 산출 → 자격 큐(입구 규칙 · 사유 코드 · 성과 수치 안 읽음)
round.sh <판> standing-measure          # 배리어 → 대기 항목마다 R2 대조 · 지문 · 정본 셀 워커 → 판정(원장 · standing_visible.json)
round.sh <판> standing-report [--send]  # 통과 = 엔진마다 push 1통 · 미달 · 미시험 = 일 요약 1통(무음)
round.sh <판> standing-status           # 측정 · 판정 · 보고 · Superfan 대기 · R2 차단 · 원장 사슬
round.sh <판> superfan-mark --codes a,b --kind pass|daily --p2 <id> --t2 <id>   # 규약 §11-1
```
- 다른 작업 트리(worktree)에서 돌릴 때만 `RC_ROOT_POSIX` · `RC_ROOT_WIN` + `R_ENVIRON_USER`(QM_ROOT 를 그 트리로)를 준다. 기본은 저장소다.

정기 실행(2026-11-10) — `bash 02_Infrastructure/ops/standing_board_run.sh [--dry-run] [--send]`: 등록된 상설 판(사양 `standing: true` · round_id = 디렉터리 이름 · 사전등록 정본 있음)마다 한 틱 = `scan` → 입구 통과 대기 항목(`pending`)이 있고 리프레시 배리어(`refresh_barrier.sh status` 한 번 · 잠김 · 판정기 없음 = 이번 틱 측정 건너뜀)가 열려 있으면 `standing-measure` → `standing-report`(기본 드라이런 · `--send` 일 때만 발송). 판이 없으면 조용히 0 종료. 자체 잠금 `.cache/standing_board_run.lock`(살아 있는 보유자 = 건너뛰고 0 · 죽은 pid = 인계) · 로그 `.cache/scheduler_logs/standing_board_<시각>.log` · 어느 단계든 실패하면 rc 1(다른 단계 · 판은 계속). `--dry-run` = 할 일 · 배리어 · 잠금 상태만 출력(round.sh · R 미호출). **예약 작업 등록은 하지 않았다**(도훈 승인 뒤 별도). 시험 = `08_Tests/ops/test_standing_board_run.sh`.

- 입구 수리(11-10): 방향 층은 호출마다 `direction` 인자로 가른다 — `"registry"` | `"defensive"` 문자열 상수 = `factor_db_static`(engine_native 허용 시 함께 허용) · 인자 없음 · `"ic_asof"` · 판정 불가 값 = `factor_db_asof`. 결합용 뷰 `fc_load_month(s)` · `fc_daily` 도 같은 규칙으로 본다. 레인 산출이 팩터 DB 수리 전 측정이어도(`contracts/factor_db_vintage.R::fdv_stale = TRUE`) 입구에서 빼지 않고 표식만 남긴다(열 `factor_db_vintage` = stale | current | na — 상설 측정이 지금의 팩터 DB 위에서 새로 잰다 · 시험은 `RC_FDV_LEDGER` 로 임시 원장). 낡은 측정의 소비는 A 자격 관문과 P4 기저 풀(등급으로 들어오는 경로)이 막는다. 자격 통과 목록 읽기 = `rc_standing_qualified(program)`.

## 판 라우팅 · v2 (2026-11-11 · 판단 T1 C-20261111-001 · 002 · 도훈 결정 P4-BASE-POOL-GRADE-PATH-TAU-20261111 = (나))

- **라우팅**: `round.sh`(`rc_core_of`) · `02_Infrastructure/programs/chain_tick.R`(`.ct_core_version`)가 사양(`round_spec.json` · `chain_spec.json`)의 `core_version` 으로 코어 판 디렉터리를 고른다. 표식 없는 사양 = v1 · 사양 없는 호출(`round.sh - …` · 사양 만들기 전) = `RC_CORE_DEFAULT`, 없으면 `RELEASES.json` 의 마지막 출시 판(출시 때만 항목을 더한다). 한 프로세스에는 판 하나만 적재한다(사슬 틱 `list` 는 판이 다른 사슬을 자식 프로세스로). 새 라운드 · 판 · 사슬은 적재한 코어의 `RC_VERSION` 을 사양에 적는다(`rc_init_*` · `rc_p4_chain_new`).
- **v1 그대로 도는 것**: P1S01 판 1(사양 `core_version: v1` · 핀 31 · 매니페스트 e70ac0af). 판정 규칙 · 생성 함수(`rc_p1_cell_spec`)는 v2 와 같다 — 판정 경로는 p4.R 과 무관.
- **v2 에서 바뀐 것(그 밖 = v1 과 같은 동작 · 시험 = `08_Tests/programs/test_round_core_v2.R` + v1 시험의 v2 경로 실행)**:
  1. 기저 풀 자격 = **P1 상설 판 통과만**(결정 (나)) — 전 기간 권위 등급 A/B 경로를 뺐다(사슬 기저를 시험 창 정보로 고르던 길 · 철학 C-20261111-016 · pit.md C1 D-E). `grade` 는 참고 열 · 등급 경로 사유 `rule_change_beneficiary` · `rule_change_unknown` 은 풀에서 쓰지 않는다(A 자격 관문의 같은 이름 보류는 그대로).
  2. 상설 행 = **칸(code) 단위**(T1 C-001) — `rc_standing_qualified` 가 통과 칸마다 구성 판독(`rc_standing_construction` · 처치 축 = P4 블록 어휘의 칸 축 · 비교 = `rc_p4_spec_diff`)을 싣고, 풀은 표준 구성 칸만 같은 엔진 행에 합친다. 처치 칸(E3 꼴)은 `standing:<판>:<code>` 행으로 따로 두고 같은 엔진 등록부 행의 레인 꼬리표(구현 의심 · 감사)를 이어받는다. 그 행의 기저 칸 사양 = 통과 칸 사양 그대로(md5 = 상설 원장) · 구성 판독 불가 = `construction_unknown`(자격 없음). 풀 md5 에 `standing_code` · `construction` 이 들어간다.
  3. 부호 층 간접 호출(P1S01 격리 점검 R-2) — 입구 정적 검사가 `align_factor_direction` · `compute_rolling_ic_all` 을 식 나무의 기호 참조(함수 값 · 별칭 · `$` · `::`) · 간접 호출 문자열(do.call · match.fun · get 류)까지 본다(`rc_standing_orient_refs`). 레인 엔진 47개의 판정은 v1 과 같다(11-11 대조).
  4. GPU 임대(점검 S-2 · WP3) — 상설 측정 · 사슬 측정이 `rc_gpu_guard` 를 지난다: 레인 정본 판별(`rf_replication_slots.py classify`)이 gpu 면 레인 측정 0(`status` 의 live claim 없음) + GPU 임대(`qv_lock.R::gpu_lease_acquire`)를 잡은 뒤에만 재고 끝나면 놓는다. 못 잡으면 원장 무기록(`gpu_wait` · CLI 종료 4 · 다음 틱 재개). cpu 엔진 = 그대로.
  5. CLI 가 자기 판의 `load.R` 을 적재한다(`round_core/v2/load.R`) · `round.sh -` 가 저장소 맨 위에 `-/results` 를 만들지 않는다.
- **아직 없는 것(판단 Superfan T4 C-20261111-030 · 11-11)**: 결정 (나)의 둘째 절 — "방어형(P2 라우팅) 레인 엔진의 길은 P2 상설 판(규칙 한 번 등록)으로 따로 연다" — 은 v2 에 없다. 기저 풀은 P1_RETURN 상설 원장만 읽는다(`v2/standing.R::rc_standing_qualified(program = "P1_RETURN")` · `v2/p4.R::rc_p4_base_pool`). 지금 방어형 인계 엔진(1)이 기저가 될 길은 0 이다 — P2 상설 판 설계 = 다음 리서치 체인 세션(재개 저널 OP-20261110-V102-LADDER next ⓕ · P1S01 측정 조건을 기다리는 11-12 오전 창).
- **라우팅 두 구현의 차이(C-20261111-035 · 오늘은 같은 답)**: `round.sh` 는 RELEASES 항목의 `status` 를 보지 않고 `round_spec.json` · `chain_spec.json` 을 읽는다 · `chain_tick.R` 은 `status = released` 만 보고 `chain_spec.json` 만 읽는다. RELEASES 는 출시 때만 항목을 더하고 사슬 틱은 사슬만 다루므로 답이 갈리지 않는다 — 출시 전 후보 항목을 RELEASES 에 넣는 일이 생기면 둘을 맞춘다.
- **v1 판을 무인 틱에 다시 맡길 때(C-20261111-032)**: v1 상설 판(P1S01)의 측정 경로에는 GPU 관문이 없다 — torch 엔진이 든 v1 판의 `tick_hold` 를 지우면 무인 틱이 레인 · 임대 확인 없이 잰다. 그 판의 첫 측정은 한 셸에서 임대(`--holder-pid $$`) → scan · standing-measure · report → 임대 놓기로 돌리고, torch 칸 판정이 난 뒤 보류를 지운다(또는 같은 규칙의 새 판을 v2 로 등록).

## v3 (2026-11-11 · 판 2 P1S02 · 설계 `04_Research/01_reports/portfolio_paper_layer_split_20261112/README.md` §6-4 · §8)

- **왜**: 판 1 첫 실측정에서 포트폴리오만 내는 엔진이 입구를 통과해 측정 무효가 났고(1908.01112), 판정 지표 계산 예외가 '미시험' 판정으로 굳는 구조가 드러났다(P1S01 마감 감독 T3 C-20261111-049). 셀 경로 정합(달 스냅 · 측정 시작일 전달 — `rf_cell_engine.R` 11-11 개정)과 짝이다. v1 · v2 파일은 그대로다.
- **v2 에서 바뀐 것**(그 밖 = v2 와 같은 동작 · 시험 = `08_Tests/programs/test_round_core_v3.R` · `test_round_core_v3_v2parity.R` · `test_round_core_v3_diag_contract.R`):
  1. 입구 사유 셋(성과를 읽지 않는다 · 날짜별 개수는 τ_D 절단 뒤 센다) — `portfolio_only_base`(FACTORS 대입 없음) · `breadth_insufficient`(레인 점수 패널의 보는 창 신호일 중 폭 ≥ `max_names × breadth_mult` 인 날 없음 · **필요조건** · 패널 판독 불가면 막지 않는다 — 스캔 표 열 `breadth`) · `base_off_month_grid`(한 달에 신호일 2개 이상 = 주간 · 일간 신호 엔진 — 열 `grid`).
  2. 측정 관문 `rc_standing_base_alignment`(상설 측정 · P4 사슬 측정 공용 · 기저가 엔진인 칸만) — 산출에 셀 엔진 진단 `rf_engine_diag.json::base_alignment`(규칙 `month_snap_v1`)가 없으면 `base_alignment_missing` → 기저가 점수 패널이 아니면 `base_not_score_panel` → 신호가 월말 격자 밖이면 `base_off_month_grid`. 측정 실패로 적고 판정으로 가지 않는다(옛 셀 엔진으로 잰 측정을 가르는 판 표식). 측정 기록에 정합 요약(τ_D 뒤 날짜 없음).
  3. `rc_standing_qualified` — 같은 칸(엔진 경로 + 구성)을 여러 판이 판정했으면 판 번호가 가장 큰 판의 판정만 읽는다.
  4. `rc_standing_judge` — 판정 지표 계산 예외(status ≠ evaluated) · 자격 NA 행은 verdict 를 남기지 않고 `eval_failed` 로 적는다(다시 평가 · `RC_STANDING_MAX_FAILS` 뒤 사람 확인). v1 · v2 는 그 행을 '미시험' 판정으로 굳혔다.
- **알려진 한계** = `RELEASES.json` v3 항목의 `known_limits`(판 등록 점검 · 격리 교차 점검이 읽는 목록).
- **쓰는 판**: P1S02(판 2). 사양 없는 호출(`round.sh - …`)의 기본 판 = RELEASES 의 마지막 출시 판이라 이 항목부터 v3 다.

## v4 (2026-11-13 · 자체 사양 입구 · 판 3 준비 · 도훈 결정 FACTOR-SPINE-STAGE1-20261112 D4 (a) · 설계 `04_Research/01_reports/factor_spine_design_20261111/README.md` §3-6)

- **왜**: 팩터 척추 1단계 P1R03 이 자체 사양 엔진(생성기 산출 점수 패널 엔진 `04_Research/strategies/FC_*` · 사양 `own_spec.json`) 15개 중 8개에 P1 자격을 줬다. 사전등록 읽는 법대로 다음 = 자체 사양 입구로 상설 판 → 기저 풀 → P4 블렌딩 사슬인데, v3 상설 판은 레인 인계(`scan.source = lane_handoff`)만 받았다. P1R03 결론 범위(`round_spec.json` conclusion_scope)가 v4 에 약속한 것(철학 P2 판독 · 원천 시행 회계 · 결합용 뷰 지문 · 저위험 계열 확인)과 그날 찾은 보는 창 누출(test_hold)을 함께 고친다. v1 · v2 · v3 파일은 그대로다.
- **v3 에서 바뀐 것**(그 밖 = v3 와 같은 동작 · 레인 갈래 스캔 표 · 레인 기저 풀 판정 = v3 와 같다 — 시험 O4 · P4):
  1. **보는 창 파일 누출 수리**(`driver.R` rc_evaluate · `rules.R` rc_rules_test_ids · rc_rules_visible_table) — `_test$` 열에 더해 규칙 선언(재귀 — all_of · any_of 의 of · report 포함)에서 시험 창 지표를 쓰는 규칙의 열(P1 보고 규칙 `test_hold` = 시험 창 연 알파 > 0 여부)과 그 상위 규칙 열을 뺀다. 사람 쪽 `verdict.json` 은 그대로. p2 · p3 보는 창 파일의 표는 템플릿 표(engine · device/method · tested · pass · excluded · verdict)라 규칙 열이 없다(확인만). P1R03 의 기존 `evaluation_visible.json` 은 v3 로 써서 test_hold 가 남아 있다(그 라운드 폴더는 고치지 않았다).
  2. **자체 사양 입구**(`standing.R`) — `scan.source = "own_spec"`(기본값 `RC_STANDING_SCAN_OWN_DEFAULT` = lane_root `04_Research/strategies` · dir_glob `FC_*` · 생성기 둘 `fc_engine_gen.R::fce_engine_text` · `fc_combiner_gen.R::fcc_engine_text` · 방향 층 engine_native + orientation_layer · long_leg_window visible · exclude_combination · pit_static). 감사 판정 허용 목록은 요구하지 않는다. 새 사유 `own_spec_missing`(없음 · 판독 불가 · schema ≠ fc_own_spec_v0 · core md5 ≠ spec_md5 — 생성기와 같은 직렬화) · `own_generator_unknown`(생성기 목록 밖) · `own_generator_mismatch`(지금 생성기 md5 ≠ core.generator_md5 · 엔진 md5 ≠ own_spec engine.md5 · own_spec 에서 생성기 본문 함수로 다시 만든 본문 md5 ≠ 엔진 md5 — 생성기는 새 환경에 sys.source · 스캔마다 경로당 한 번). 판독 `.rcs_scan_own_dir`(모든 사유를 모은다 · 폭 · 격자 · 롱 레그 사유 없음 — 측정의 실효 시작 · 기저 정합 관문이 가른다). 열 `family_root` · `own_spec` · `own_spec_md5` · `generator` · `families` · `source_rounds` · `own_detail`. `source_rounds` = 등록부 P1 라운드(사전등록 md5 = 등록부 · 상설 판 제외) 중 칸 사양(md5 = 사전등록) base_signal 엔진의 **등록 md5(사전등록 핀)** 가 이 엔진 md5 와 같은 라운드(`rc_standing_source_cells` · 성과 안 읽음 · 핀 없는 옛 사전등록은 제외).
     - **orientation_layer 허용 조건(자체 사양 입구에서만 — 레인 입구는 사양 검사가 거부)**: ① 엔진 본문 = 생성기 산출(재생성 md5 대조 → 손 편집 · 부호 층 변조는 `own_generator_mismatch`) ② 본문의 실행 단정(부호 = 등록부 s_reg 고정 · 가중 유한 · 비음수 — 어기면 엔진이 멈춘다). 시험 W: FC_TOTAL_ICW 사본의 가중 줄을 `.fce_w <- .fce_a; …` 로 바꾼 돌연변이는 짧은 창(2022-08 ~ 09)에서 '가중 단정 위반'으로 멈추고 원본은 멈추지 않으며, 같은 사본은 스캔에서 `own_generator_mismatch` 로 빠진다.
     - **enqueue 시행 수**: 자체 사양 행 = 계보 `family_root`(own_spec) · 인계 기록 대신 handoff{origin = own_spec · own_spec · own_spec_md5 · generator · families · source_rounds · declared_at}. 원천 라운드가 있고 그 계보 회계가 있으면(nf_prior ≥ 1) n_family = 계보 최댓값 그대로(같은 표준 구성의 같은 시행 재측정 · +1 없음), 아니면 레인과 같은 +1. 근거 문장은 원장에 남아 `rc_standing_regen_md5` 가 같은 사양을 다시 만든다.
  3. **입구 갈래(track)** — `standing_cfg.track` = lane(lane_handoff 의 기본 · 키 없음 = lane) | own_spec(scan.source = own_spec 이면 필수 · 일치 검사). **판 번호는 갈래마다 1 부터**(자체 사양 입구 첫 판 = edition 1 — round_id 가 P1S03_… 여도). 옛 판 받기 정지(enqueue 맥락)는 **같은 갈래의 더 높은 판만** 본다. v3 코드(판 2 P1S02)는 갈래를 모르지만 1 < 2 라 자체 사양 판 1 에 막히지 않고 레인 판 3 에는 막힌다(시험 T4 — v3 코어 자식). `rc_standing_editions` 에 track 열 · 원장 줄 머리에 `track`.
     - `rc_standing_qualified` 의 '같은 칸 = 판 번호 큰 판' 규칙: 묶음 키(엔진 경로 + 구성)에 갈래를 **넣지 않았다**(넣으면 한 갈래 미달이 다른 갈래 통과를 지우지 못한다 — fail-open). 판 번호 비교는 같은 갈래 안에서만 하고, 묶음이 두 갈래에 걸치면 갈래마다의 최신 판정이 모두 통과일 때만 자격 · 행은 판정 시각이 가장 늦은 갈래 하나(fail-closed · 시험 Q1 — v3 는 판 번호 큰 레인 판 통과를 남긴다). '갈래가 다르면 같은 엔진이 두 판에 들어갈 일이 없다'는 가정이 깨지는 경우: 두 갈래의 dir_glob · lane_root 가 겹칠 때 · 손으로 넣은 항목(source manual) · 한 갈래 판의 시드가 다른 갈래 엔진일 때 · rejudge_prior_editions = TRUE · 엔진이 바뀌어(md5) 판 사이 중복 막기(`rc_standing_known`)를 지날 때.
  4. `rc_standing_qualified` 열 추가 — track · origin(handoff origin · 없으면 lane · 시드 = seed) · own_spec · own_spec_md5 · families · source_rounds · superfan_pass_p2(superfan kind = pass 이고 codes 에 그 code 가 있는 기록의 p2 id) · paper_title · paper_url.
  5. **기저 풀**(`p4.R` rc_p4_base_pool · 자체 사양 통과 칸만 — 레인 · 등록부 행 판정 = v3):
     - `philosophy_unread` — 철학 P2 판독 두 갈래가 모두 미해소: ① 상설 원장 superfan pass 기록의 p2 id 가 판단 원장에 역할 philosophy · 트리거 P2 · 대상(round) = 그 상설 판(규약 §11-1 기록 형식) ② 원천 라운드 영수증 `<원천 라운드>/results/philosophy_receipt.json`(스키마 `rc_philosophy_receipt_v1` {round_id · p2_review_id · written_at · engines{<엔진 저장소 상대 경로>: {hold · stop · note · release_decision(선택)}}} · p2_review_id = 판단 원장 philosophy P2 · round = 그 원천 라운드). 파일 없음 · 판독 불가 · 엔진 항목 없음 = 미해소(fail-closed) · 원천 라운드 중 하나라도 해소되면 해소.
     - `philosophy_hold`(도훈 확인 대기) — 확인된 영수증의 그 엔진 hold = true(stop = true 도 같은 사유 — 규약상 stop = 사용 보류) 또는 superfan 기록 P2 리뷰의 열린 보류 요청. 보류는 다른 갈래의 해소보다 앞선다.
     - `lowrisk_confirm_pending`(엔진 단위) — 가족(core.families)이 `RC_P4_LOWRISK_HOLD`(출시 전 수리 뒤 defense · risk · regime · liquidity · crowding — 정본은 이 상수 하나 · 아래 9)와 겹치거나 영수증 lowrisk_tag 인데 확인된 영수증의 그 엔진 항목에 `release_decision` 이 없거나 그 id 가 `06_Registry/decision_register.json` 에 status = resolved 로 없다. 전역 해제 목록은 두지 않는다(도훈 결정 LOWBETA-ENGINES-BASE-USE-20261113 정정 — 카테고리로 풀면 그 결정의 대상이 아닌 다른 판 엔진(예: T1 의 방어 · 위험 · 유동성 · 쏠림 가족)까지 함께 풀린다). ★토탈(FC_TOTAL_*)은 가족 14 가 그 집합과 겹쳐 release_decision 이 필요하다(그 결정이 토탈을 포함하므로 영수증 항목에 그 id 를 적으면 풀린다).
     - 영수증 쓰기 도우미 `rc_philosophy_receipt_write(round_dir, p2_review_id, engines, ledger, decision_register)` — 원천 라운드를 가진 세션이 쓴다: 등록된 라운드 · 판단 원장 대조(philosophy P2 · round) · 엔진 = 그 라운드 사전등록 칸의 기저 엔진만 · note = 처방 입력 글 검사 · release_decision 은 결정 기록부 resolved 만(없는 id · 미해결 = 거부) · 원자적 쓰기(supersedes_md5).
     - 풀 열 origin · families · source_rounds · own_spec · paper_url · 자체 사양 기저 칸의 논문 메타 = 상설 항목 paper(칸 사양 root_paper — lane_provenance 가 없다).
  6. **사슬 원천 시행**(rc_p4_chain_register · rc_p4_close) — 기저 origin = own_spec 이면 원천 라운드(풀 행 source_rounds ∪ 등록 시점 등록부에서 같은 엔진 md5 를 칸으로 등록한 P1 라운드 — 늦게 등록된 라운드도 넣는다)의 사전등록 칸 전부의 측정 산출 폴더(측정 기록 `results/<code>.json` ok · artifacts — 없으면 칸 평가 기록 `results/<code>/eval.json`)가 실재해야 등록된다(하나라도 없으면 거부 · 원장 무기록 · 빠진 칸 이름). 목록 {round_id · code · artifacts} = `chain_registered.source_trials`(+ base_origin · source_rounds). 닫기 재채점 시행 집합 · 기대 시행 수 · 기대 id 에 원천 시행을 더하고 `finalize.json` 에 source_trials. 레인 기저 = v3 와 같은 기록.
  7. **N5 β 비대칭에 blend 걸음**(`RC_P4_BETA_ASYM_BLOCKS` = 노출 층 + blend · 근거 헌장 §5 빈칸 3 · 8 · 판단 Superfan T2 C-011) — 값 계산(하락 β < 상승 β 면 1 · 아니면 0 · 그 밖 블록 1). 막는 것은 채택 규칙이다 — 출시 전 수리로 새 사슬 판(p4_rules_v3)은 이 규칙을 필수로 받는다(아래 9).
  8. **데이터 지문**(`fingerprint.sh` equality) — 결합용 뷰 `.cache/factor_combinable`(파일 전부 · 개수 · 크기 · 최신 mtime) 줄 추가(P1R03 결론 범위 '결합용 뷰는 칸 데이터 지문에 없다' · 격리 점검 v1 R-1).
  9. **출시 전 수리**(11-13 · 격리 점검 `04_Research/01_reports/round_core_v4_review_20261113/isolation_review_v4.md` revise(필수 M1 · M2) · 판단 T4 R-20261113-005(C-035 ~ 038 수용) · P1S03 감독 철학 P1 R-20261113-006 · 판단 T1 R-20261113-007 — 미출시라 판 하나 더 없이 그 자리에서 고쳤다 · 판정 규칙 · 숫자 불변):
     - **자체 사양 = 엔진 속성(M1 · C-035)** — `rc_standing_qualified` 열 `own_spec_engine`(원장 갈래 own_spec ∨ 엔진 폴더 own_spec.json — 시드 · 손 항목 포함 · origin 의 seed 표기는 그대로) · `own_resolved` · `family_root`. 기저 풀 관문 · 사슬 원천 시행 · 기저 칸 논문 메타가 그 열을 쓴다. 인계 기록이 없는 자체 사양 행은 그 자리에서 채우고(families = own_spec.json core.families · source_rounds = 아래 판독) 못 채우면 기저 풀 사유 `own_spec_unresolved`(fail-closed). 자체 사양 판의 시드는 스캔 행과 같은 인계 기록을 적는다(`.rcs_enqueue_seeds`).
     - **원천 라운드 = 엔진 md5 ∪ 계보(C-035 ②)** — `.rcs_own_source`: 이 엔진 md5 를 칸으로 등록한 P1 라운드 ∪ 같은 계보(family_root) 칸을 가진 P1 라운드(다시 만든 엔진 = 새 md5 도 앞선 계보 시행을 물려받는다). 입구 · enqueue · 기저 풀 · 사슬 등록이 같은 함수를 쓴다. 실제 FC_* 30 = 전부 P1R03 + P1R04(T1 = 계보로 P1R03).
     - **시행 수(C-036 · R1)** — 이 엔진 md5 를 변형 칸 · 같은 계보로 회계한 원천 칸이 있으면 n_family = max(계보 앞선 회계 최댓값, 원천 라운드 칸 수 — 사슬 원천 시행과 같은 집합) · +1 없음(실제 T0 · T1 = 45) · 아니면 max(그 최댓값, 원천 칸 수, 레인 하한 1) + 1(원천 없으면 레인 규칙과 같다). 원천 칸 계보 ≠ own_spec family_root = 입구 사유 `own_spec_family_mismatch`(enqueue 는 멈춘다).
     - **선언(R3)** — 입구 사유 `own_spec_undeclared`: ① 등록부 선언 줄(origin = own_spec · **kind ≠ engine**(kind = engine 줄은 기저 풀 · 레인 스캔이 레인 엔진으로 읽는다 — `kind: "own_spec"` 로 적는다) · engine_path · engine_md5 = 지금 · 선언 시각) ② own_spec.json decision 이 결정 기록부 resolved(10 R-C 뒤 = 그 항목 engine_scope 에 이 엔진 경로 · md5 가 있을 때만) ③ 이 엔진 md5 의 원천 라운드 ≥ 1 — 셋 다 없으면 제외(계보 승계는 시행 회계일 뿐 선언이 아니다). 열 `declared`.
     - **철학 판독(M2)** — 갈래 ① 리뷰의 보류 요청은 withdrawn 이 아니면 보류(accepted 포함 — Q 가 동의하고 도훈 결정을 기다리는 상태). 해제 = 상설 판 자기 영수증(`<상설 판>/results/philosophy_receipt.json` — `rc_philosophy_receipt_write` 가 상설 판에도 쓴다 · 엔진 = 그 판 원장 항목)의 그 엔진 hold = false ∧ stop = false. 갈래 ② 원천 라운드 영수증은 엔진 항목이 정본(리뷰 단위 accepted 보류로 모든 엔진을 막지 않는다 · 종전대로). 기저 풀은 원장 source_rounds ∪ 지금 판독으로 영수증을 읽는다(R4 (i)). 영수증 엔진 항목이 목록이 아니면 그 엔진만 미해소(S2).
     - **저위험(C-037 · R7)** — `RC_P4_LOWRISK_HOLD` = defense · risk · regime · liquidity · crowding(LOWBETA 결정의 다섯 + 국면 · 토탈은 겹침) · 영수증 엔진 항목 `lowrisk_tag`(선택 · 논리값 — 사이드카 꼬리표 카테고리 · 참이면 release_decision 필요) · 풀 열 `label_class`(저β 수익 엔진 | 수익 엔진 — CHARTER-GAP-LOWBETA-DEFENSE-LABEL (가)) · 사슬 등록 기록 `base_label_class`.
     - **사슬 등록(R4 (ii) · C-054)** — 원천 라운드 = 풀 source_rounds ∪ 지금 판독 · 사전등록 핀에 이 엔진 md5 가 있는데 검증이 안 되는 라운드(사전등록 md5 ≠ 등록부 · 칸 사양 검증 실패 · 사전등록 판독 불가) = `<라운드>:<검증 불가 — 사유>` 로 거부. 원천 칸 산출마다 판 표식(`contracts/factor_db_vintage.R` — 11-13 RAWDATA-SEAM-0330-REPAIR-20261113 포함)을 보고, 낡았으면 같은 엔진 md5 · 같은 구성(칸 사양 의미 서명)의 현재 판 산출로 갈음(기록 replaced{artifacts · stale_by · by} · 예 P1R03_FVALU_C0 → P1R04_FVALU_R0) · 갈음할 것이 없으면 거부(`:stale`).
     - **닫기 셈(S3 ① ②)** — 원천 시행 기대 수 = 정규화한 고유 경로 수 + 손상 기록 수(같은 산출이 두 번 오면 한 번 · 손상 기록은 관문이 막는다) · finalize.json `source_trials_count`. ③ 의도: 같은 전략(T0 엔진 · 표준 구성)이 P1R03 변형 + P1R04 기준 칸으로 두 번 들어오면 산출 폴더가 다를 때 두 시행으로 센다(보수 — C-038 수용 45 · 상설 판 '재측정 +1 없음'과 다른 셈은 의도) · 판 표식 갈음으로 같은 폴더가 되면 한 번.
     - **채택 규칙 판 p4_rules_v3(R6)** — 새 사슬 판 = v3 · 필수 지표에 `beta_asym_ok_vis`(방향 = 통과 1 요구 — '>=' 1 · '>' [0,1) · '==' 1). 블록 어휘가 사슬마다 열려 있어(모든 사슬이 blend 걸음을 열 수 있다) 판 전체에 건다. v2 · v1 판은 옛 판독 그대로.
     - **같은 계보 블렌드(C-048)** — 기저 풀 열 family_root · 블렌드 걸음(engine_blend) 키들의 family_root 가 같거나 한쪽 families 가 다른 쪽을 품으면(토탈 ⊃ 카테고리) 걸음 원장 step_open 에 꼬리표 `same_lineage_blend`(+ tag_detail · 거부 아님).
     - **시험 창 규칙 판별(S1 · C-042)** — `rc_rules_test_ids` 가 보고 규칙의 when 의존을 고정점까지 따라간다(when = 시험 창 규칙인 보고 열도 보는 창 파일에서 뺀다) · `rc_rules_test_window_use`(판정 규칙 τ_D 검사)가 확장 종류 cols(r)도 읽는다(최상위 보고는 허용).
     - **판정 출시 관문(R5)** — 자체 사양 갈래 `rc_standing_judge` 는 RELEASES.json 의 출시 판 ≥ v4 일 때만 판정한다(출시 전 통과 판정이 생기면 사양 없는 호출의 기본 판 v3 기저 풀이 관문 없이 읽는다). 원장 형식(schema)은 바꾸지 않았다 — 부팅 · 감시기(`boot_lean.sh` · `superfan_components.json`)가 `rc_standing_ledger_v1` 로 사슬을 검사해 새 형식이면 '사슬 끊김' 경보가 난다.
     - **통과 보고(C-046 · C-058 · qvest-telegram §0.2)** — 판정 줄 = IS β-통제 t(α) · IS 상승 포착률만 · 보고 열(판정 아님) = IS 하락노출 중앙 · 최악 · 위기 수 · IS β + 고정 문구 `RC_STANDING_REPORT_NOTE`(시장 대비 귀속 전 원값 — 시가총액 × β 무작위 대조 포트폴리오 미측정 · 방어 주장 없음) · OOS 유지 = 사람 쪽 줄 · 표기 IS/OOS · 동일가중 · 에디션. `standing_cfg.report.pass` = push_each(기본) | daily_summary(통과도 일 요약 1통 · 통과가 있으면 그 요약을 push) — 사양 검사가 어휘를 본다 · `rc_init_standing_p1(report = …)`.
     - **결론 범위 · 핀(C-049 · S6)** — `rc_init_standing_p1` · `rc_init_p1` 기본 결론 범위 앞에 P1 표준 철학 줄(`RC_P1_PHILOSOPHY_LINES` · 근거 C-20261111-015 · C-20261111-075 · C-20261112-020 · C-20261113-049 · 호출자 줄은 뒤 · 갈래별 — 아래 10 R-E) · 자체 사양 판은 scan.generators 를 pins.files 에 자동으로 넣는다.
  10. **변경분 점검 2 수리**(11-13 · `04_Research/01_reports/round_core_v4_review_20261113/isolation_review_v4_diff2.md` revise(필수 M3 · 권고 R-A ~ R-F · 선택 S-a · S-b · S-e · S-g) — 같은 원칙(그 자리 · 판정 규칙 · 숫자 불변 · 기존 own_spec.json · FC_* 엔진 무수정)):
     - **자체 사양 시행 수 = 함수 하나(M3)** — `rc_standing_own_nf(engine_path, family_root, root, registry_path, src, handoff_rounds, lane_n, supersedes, nf_prior)`(규칙은 9 의 C-036 그대로). enqueue · 시드 칸 사양 · 사양 검사 · standing-check 가 같이 쓴다. 시드 칸 사양 = **`rc_standing_own_seed_spec(like, code, root, registry_path, decision_register)`**(선례 칸 사양을 `rc_standing_seed_respec` 으로 다시 만들고 n_family · 근거 문장을 이 함수 값으로 넣는다 · 반환 = 목록 · 쓰기는 호출자). 사양 검사(`rc_standing_validate` · check_seeds = 등록 전만)는 자체 사양 시드 n_family < 그 값이면 거부한다. 실제 FVALU(P1R03_FVALU_C0 선례) = 45(P1R03 15 + P1R04 30 · 재측정).
     - **보류 해제 영수증(R-A)** — 상설 판 영수증이 갈래 ① 보류를 푸는 것은 그 영수증이 보류 요청 뒤에 쓰였고(written_at > 그 엔진 보류 요청 at 최댓값 · 시각 판독 불가 = 해제 없음) 해제 근거 리뷰(엔진 항목 `basis_review` · 없으면 영수증 p2_review_id)가 보류를 낸 리뷰를 모두 품을 때만. 아니면 보류 유지. `rc_philosophy_receipt_write` 가 basis_review(판단 원장 philosophy P2 · 대상 = 그 판)를 확인한다.
     - **시험 창 규칙 닫힘(R-B)** — `rules.R::.rc_rules_test_closure` 하나를 보는 창 판별(`rc_rules_test_ids`)과 판정 규칙 τ_D 검사(`rc_rules_test_window_use`)가 같이 쓴다 — 시험 창 규칙의 열(예: `metric = "test_hold"`)을 metric · cols 로 읽는 판정 규칙 · 그 상위도 잡는다.
     - **선언 = 엔진 단위(R-C)** — ② 결정은 결정 기록부 항목의 `engine_scope`(목록 {engine_path(저장소 상대), engine_md5})에 이 엔진의 경로 · md5 가 함께 있을 때만. 생성기가 모든 산출에 적는 범위 없는 결정 id(FACTOR-SPINE-STAGE1-20261112)는 선언이 아니다. 실제 FC_* 30 은 ③ 엔진 md5 원천 라운드(P1R03 · P1R04)로 선언된다.
     - **원천 꼬리표 파일(R-D)** — `<원천 라운드>/results/lowrisk_tags.json` = `{"engines": {"<엔진 경로 — 저장소 상대 엔진 파일 또는 폴더>": true}}`(성과 무참조 · 원천 라운드 세션이 사이드카 결과를 옮긴다 · 상수 `RC_P4_LOWRISK_TAGS_FILE`). 그 엔진 = true 면 영수증이 없어도 `lowrisk_confirm_pending` · 저β 수익 엔진 표기. 파일이 있는데 판독 불가 · 값이 논리값 1개가 아님 = 꼬리표로 센다(fail-closed). 풀림은 종전대로 영수증 엔진 항목 release_decision(resolved).
     - **철학 줄 갈래별(R-E)** — 줄 1 · 2(`RC_P1_PHILOSOPHY_LINES_OWN` — 결정론 엔진 · 구성원 점수 평균 = FC_* 문장)는 자체 사양 판 · `rc_init_p1(own_spec_engines = TRUE)` 에만. 레인 판 · 일반 P1 라운드 = 일반 줄 둘(`RC_P1_PHILOSOPHY_LINES_GENERAL`) · 갈래 선택 = `rc_p1_philosophy_lines(track)`.
     - **계보 대조(R-F)** — 입구 · enqueue · 시드가 이 엔진에 묶인 원천 칸(엔진 md5 ∪ own_spec `supersedes_engine_md5` ∪ 같은 엔진 경로)의 등록 칸 사양 family_root(등록 md5 보호 안)를 own_spec family_root 와 대조 — 다르면 `own_spec_family_mismatch`. 다시 만든 엔진(새 md5)이 family_root 를 바꿔도 경로로 잡힌다.
     - **사슬 등록(S-a · S-b)** — 판 표식 판정 불가(측정 시각 모름 · 계약 · 원장 없음) 원천 칸 = `:fdv_na` 거부(닫기 재채점 입력 · 기저 풀은 진단 열 그대로) · 원천 라운드(풀 source_rounds · 계보로 든 라운드)가 지금 검증된 등록 P1 라운드가 아니면 거부 · 등록부에 사전등록 경로가 없는 P1 라운드 = 검증 불가 `"*"`.
     - **시드 입구 검사(S-e) · 생성기 핀(S-g)** — 자체 사양 시드도 계보(R1 · R-F) · 선언(R3 · R-C)을 지난다(사양 검사 · `rc_standing_own_seed_spec` · 시드 넣기 — 실패 = 멈춤). 자체 사양 판 사양 검사 = scan.generators ⊂ pins.files(손 사양 · pins 를 통째 바꾼 사양 포함).
- **시험**: `08_Tests/programs/test_round_core_v4.R` — 새 관문마다 양방향만(V · F · T · I · O · W · Q · P · S · C · Z · 11-13 출시 전 수리 뒤 63 PASS · 변경분 점검 2 수리 뒤 71 PASS · 0 FAIL · 161초(수리 전 46) · 무거운 부분 = 실제 RP_AUTO_* 51개 레인 스캔 v3 · v4 대조 약 90초 · 실제 FC_* 30개 약 13초). 실제 등록부 · 원장 · RELEASES · FC 엔진은 읽기만(전후 md5).
- **알려진 한계**:
  - v3 기저 풀은 원장 형식이 같아 자체 사양 판 원장을 관문 없이 읽는다 — 판정 출시 관문(R5)이 출시 전 통과 판정을 막고, 출시 뒤 사양 없는 호출의 기본 판은 v4 다. 남는 길 = core_version v3 로 일부러 만든 사슬 판(이미 등록된 v3 사슬의 블렌드 부품 판독 포함) — 사슬은 v4 로만 등록한다. 자체 사양 엔진이 레인 갈래 판의 시드가 되면 그 판정은 관문 없이 v3 에 읽힌다(그런 판을 만들지 않는다).
  - release_decision 은 결정 기록부 resolved 만 본다(격리 점검 R2) — 결정 내용(허용 · 보류 유지 · 제외)과 대상 엔진은 읽지 않는다. 엔진 단위 해제의 정확성은 영수증을 쓰는 쪽(Q)에 기댄다. 갈래 ① 보류의 해제(상설 판 영수증 hold = false)는 결정 id 를 기계로 요구하지 않는다(보류의 결정은 도훈 — Q 가 옮겨 적는다 · 10 R-A 로 시각 · 근거 리뷰만 기계가 본다).
  - 선언 ② 엔진 범위(10 R-C)를 적을 쓰기 길이 없다 — 결정 기록부 writer(`02_Infrastructure/reinforcement/reinforce_ledger.R::dr_open` · `dr_resolve`)에는 `engine_scope` 칸이 없고(항목의 다른 칸은 보존되지만 쓰는 API 가 없다), 지금 그 칸을 쓰는 결정은 0 이다. 그래서 ② 는 사실상 닫혀 있고 선언 = ① 등록부 선언 줄(kind own_spec · 경로 · md5) · ③ 엔진 md5 원천 라운드뿐이다 — 원천 라운드 없는 새 자체 사양 엔진은 등록부 선언 줄로 선언한다(writer 에 칸을 더하는 일 = 코어 밖 · 도훈 · Q 결정).
  - 계보 대조(10 R-F)는 엔진 md5 · supersedes_engine_md5 · 같은 경로로 묶인 등록 칸이 있을 때만 걸린다 — 경로 · md5 · family_root 가 한꺼번에 바뀐 엔진(폴더 이름까지 바꾼 생성기 개정)은 묶을 등록 칸이 없어 새 계보로 들어온다(유도 규칙 'FC:<가족> · FC:total' 은 생성기에 있고 코어는 재유도하지 않는다).
  - 사전등록 경로가 없는 P1 라운드 항목이 등록부에 하나라도 있으면(10 S-b — 지금 0) 자체 사양 기저 사슬 등록이 모두 멈춘다(검증 불가 "*" · fail-closed) — 라운드 항목은 등록(사전등록 경로 · md5)과 함께 넣는다.
  - 블렌드 부품(자체 사양 엔진)의 원천 시행은 닫기 시행 집합에 들지 않는다(변경분 점검 2 S-c — 기저 source_trials 만 · 지금 FC_* 30 은 원천 라운드가 같아 영향 없음 · 원천이 다른 부품을 섞는 사슬부터 생긴다).
  - 판정 출시 관문(R5)은 판 갈래로만 건다(S-d) — 자체 사양 엔진을 시드로 둔 레인 갈래 판은 출시 전에도 판정한다(위 첫 줄 · 그런 판을 만들지 않는다 · 항목 own_spec_engine 으로 걸면 닫힌다).
  - 일부만 실린 수리(S-f): C-048 same_lineage_blend 꼬리표는 걸음 원장 step_open 에만(rx_validate · 닫기 결론에는 없음) · C-037 label_class 는 풀 · chain_registered 에만(닫기 기록 없음) · C-046 '일 요약의 통과 엔진 P2 한 줄' 없음 · C-049 '원천 라운드 결론 범위와 철학 줄 대조 경고(standing-check)' 없음.
  - 자체 사양 입구는 `exclude_combination` · `long_leg_window` 를 쓰지 않는다(격리 점검 S4 — 사양 검사만 · 결합 · 롱 레그는 자체 사양 엔진에 해당 없음).
  - 자체 사양 갈래가 판 3 이상이 되면 v3 레인 판 2(P1S02)의 enqueue 가 v3 규칙(갈래를 모르고 번호만 본다)으로 막힌다(격리 점검 S5) — 그 전에 레인 갈래를 v4 판으로 옮긴다.
  - 같은 계보의 상설 판 형제 항목(다른 md5 · 같은 family_root 의 상설 칸)은 사슬 원천 시행에 들지 않는다(원천 = 등록 라운드 사전등록 칸 · 상설 원장은 n_family 로만 센다).
  - 감시기 `02_Infrastructure/programs/superfan_watch.py` 의 standing_board scan_stale 은 프로그램 폴더마다 edition 이 가장 큰 원장 하나만 본다(갈래 모름) — 레인 판 2 가 있는 동안 자체 사양 판 1 의 스캔 정체는 그 규칙에 안 보인다(원장 줄 머리 track 으로 묶도록 감시기 수정 필요 · 코어 밖).
  - 원천 라운드 판독은 사전등록 핀(pins.files)에 엔진이 든 판만(P1R01 · P1R02 옛 형식 제외 · 지금 자체 사양 엔진은 그 판에 없다). 생성기 자동 핀은 `rc_init_standing_p1` 이 만든 사양만 — 손으로 쓴 사양 · pins 를 통째 바꾼 사양은 사양 검사가 생성기 ⊂ pins.files 를 요구한다(10 S-g).
  - 영수증 엔진 키는 경로(저장소 상대) — 엔진 바이트는 원천 라운드 정의(등록 md5 = 상설 항목 md5)와 standing_engine_changed 가 묶는다. superfan 기록 P2 의 대상(round) 대조는 규약 §11-1 기록 형식(`--round <판 round_id>`)을 가정한다.
  - 원천 라운드가 측정 중(산출 미완)이면 그 엔진을 기저로 쓰는 사슬 등록이 거부된다(빠지면 거부 — 의도). 지금 T0 · T1 엔진의 원천 라운드 = P1R03 + P1R04 — 사슬은 P1R04 30칸 측정이 끝나야 등록되고, P1R03 15칸 산출(이음매 수리 전 판)은 P1R04 같은 사양 칸으로 갈음돼야 한다. 두 갈래에 걸친 칸의 행 고르기는 판정 시각(초 단위) 순 — 같은 초면 갈래 이름 순.
- **출시**: RELEASES.json 은 고치지 않았다(변경분 점검 뒤 Q 가 넣는다 — 지금 넣으면 사양 없는 호출의 기본 판이 바뀐다). 새 라운드 · 판 · 사슬은 사양 `core_version: v4` 로 이 판을 고른다(round.sh 라우팅 그대로). 자체 사양 갈래 판정은 RELEASES v4 항목 뒤에만 돈다(9 의 판정 출시 관문).
- **출시(2026-11-13 20:07)**: RELEASES.json v4 항목 — 매니페스트 95d4a286 · 파일 20 · 소스 커밋 028078396 · 시험 test_round_core_v4.R 71/0 · 격리 점검 전체(revise → 7037cd6cc) + 변경분(revise → 028078396 · M3 해소 Q 확인). 이 항목부터 사양 없는 호출(`round.sh - …` · p4-pool)의 기본 판 = v4 · 자체 사양 갈래 판정(R5) 열림.

## v5 (2026-11-15 · P4 생성기 입력 수리 · 판단 J-20261115-005 · 설계 `04_Research/programs/P4_ASSEMBLY/P4C02_fc_blend/DESIGN_draft.md`)

- **왜**: P4C01(v4 사슬) 첫 무인 틱(11-15 08:37)이 생성기 작업 폴더 만들기에서 멈췄다 — 설계 입력 §1 사유 코드 설명(상수 `RC_P4_REASONS`)의 리뷰 id 날짜 · '전 기간' · 'T4' 가 마지막 전수 검사(`rc_input_issues`)에 걸린다. 무인 틱은 늘 기저 풀을 넘기므로 **v4 사슬은 모두 같다**. 둘째 구멍: 사슬 목적 글(purpose)이 생성기 입력에 없었다 — 목적 글의 범위 문장('생성기가 지킨다')은 집행되지 않았다.
- **바뀐 것**(v4 대비 파일 여섯 · 나머지 14 = 같은 바이트): ① §1 사유 코드 설명마다 처방 입력 검사(못 지나면 코드만) ② §0 = 목적 글(id 안 8자리 날짜만 § 로 가림 — 그 밖의 날짜 · 연도는 남겨 등록 거부) + 걸음 정책 줄 · 등록 검사가 같은 도우미(`.rcp4_section0`)로 검사 ③ 걸음 정책 `step_policy`(선택): `blocks` · `axes`(blend 블록은 factors · base_weight 축도 바꿀 수 있다) · `part_engine_rx` · `blend_rule = parent_plus_one` · `source` — 등록 + 걸음 열기에서 기계 거부 ④ §1 풀 표 표기 열(label_class) ⑤ 판 표기 · 적재 경로.
- **쓰는 법**: 새 사슬 판은 `rc_p4_chain_new(..., step_policy = list(blocks = list("blend"), axes = list("base_signal"), part_engine_rx = "<정규식>", blend_rule = "parent_plus_one", source = "<근거>"))`. 범위 문장을 목적 글에 쓸 때는 그 문장을 거부하는 코드 자리를 함께 적는다(판단 T1 습관 제안 — P4C02 DESIGN §6 표). **목적 글은 처방 입력이다**(τ_D 통로 — 기계 검사는 날짜 · 연도 · 등급 · '키워드 + 수치'만 막는다 · 정성 서술은 교훈 카드와 같은 규율).
- **출시 절차에 더함**(판단 C-20261115-075): 그 판의 load.R 로 실제 사슬 상태 · 실제 기저 풀의 설계 입력 · 생성기 작업 폴더를 도는 시험(v5 = `test_round_core_v5.R` E 묶음)을 출시마다 돈다 — 틱 경로 시나리오 시험(`test_scn_chain_tick_core.R`)은 v1 고정이라 v2 ~ v4 의 그 경로를 아무도 돌지 않았다.
- **시험 · 점검**: `08_Tests/programs/test_round_core_v5.R` 77/0 · 변경분 점검 `04_Research/01_reports/round_core_v5_review_20261115/change_review_v5.md`(revise M-1 → 재점검 revise M-2 → 제안 식 반영) · 판단 T1 R-20261115-010 · 철학 P1 R-20261115-011.
- **알려진 한계**: RELEASES v5 known_limits(사슬은 코어 매니페스트를 핀하지 않는다 · 생성기 g1 은 §0 을 모른다 · chain_tick.sh 는 정책 거부를 invalid 로 센다 · §1 설명 생략 둘 · v4 코어는 step_policy 를 모른다 · `$` 부분 일치).
- **출시(2026-11-15)**: RELEASES.json v5 항목 — 매니페스트 1dc74f98 · 파일 20 · 소스 커밋 632a7034e. 이 항목부터 사양 없는 호출의 기본 판 = v5(P4 생성기 입력 밖은 v4 와 같은 동작) · v4 사양(P1S03 · P1S04 · P4C01)은 그대로 v4.

## P4 강화 사슬 (p4_chain · v1/p4.R · v10.2 · 2026-11-10)

한 사슬 = 기저 엔진 1개에서 출발해 **한 걸음에 가설 하나 · 칸 하나 · 블록 유형 하나**씩 얹는 순차 루프(사슬형 — 스윕 아님). 규칙(채택 규칙 · 예산 · 생성기 판 핀)은 사슬 판 `chain_spec.json`(스키마 `rc_p4_chain_v1`)에 한 번 등록하고, 걸음은 추가 전용 원장 `chain_steps.jsonl`(앞 줄 md5 사슬)에 흐른다. 루프가 고쳐 쓰는 것은 생성기(`06_Registry/rx_generator.json` · 본문 `04_Research/programs/P4_ASSEMBLY/_generator/g<n>/*.md`)뿐이고, 판정 규칙을 바꾸려면 새 사슬 판을 등록한다.

```r
source("04_Research/programs/_lib/round_core/v1/load.R")
pool <- rc_p4_base_pool()                               # 등록부 kind = engine + 상설 자격 → 자격(v2 = 상설 통과만 · 칸 단위 · 권위 등급 = 참고 열 — 결정 (나)) · 제외 사유 코드
gap  <- rc_p4_gap("<산출 폴더>")                         # 보는 창 A 하한별 값 · 문턱 · 여유 · 병목(시험 창 값 없음)
rc_p4_base_cell_spec("<풀 key>", pool, out_path = "<f>.json")   # 기저 칸 사양 = P1 표준 구성 생성기(rc_p1_cell_spec) 그대로 · 논문 메타 = rc_standing_paper
rc_p4_chain_new("<사슬 디렉터리>", "P4C01_<이름>", base_key = "<풀 key>", pool,   # base_cell_spec 생략 = 위 도우미가 <사슬>/base_cell_spec.json 을 만든다
                adoption_rules = list(                    # 보는 창 지표만 · 숫자는 정본 참조(value_ref) + source 문구(필수 셋: dS_vis · uc_vis · d_dd_capture_median_vis)
                  list(id = "improve", type = "threshold", label = "보는 창 S 개선", metric = "dS_vis", op = ">=",
                       value_ref = "04_Research/programs/P3_CONSTRUCTION/P3R03_advanced_construction/prereg.json::final_selection_rule.tie_eps", source = "…"),
                  list(id = "uc_floor", type = "threshold", label = "상승 포착 하한", metric = "uc_vis", op = ">=",
                       value_ref = "06_Registry/behavior_card.json::uc_floor", source = "…"),
                  list(id = "crisis_no_worse", type = "threshold", label = "위기 하락 포착 비악화", metric = "d_dd_capture_median_vis", op = "<=",
                       value = 0, basis = "정의 — 비악화 = 부모 이하", source = "…")),
                budget = list(max_steps = <정수>, max_steps_source = "<출처>", noise_k = <정수>, noise_k_source = "<출처>"))   # 예산 숫자는 사양 작성자가 출처와 함께(기본값 없음)
rc_p4_chain_register("<사슬 디렉터리>", pool, p1 = "<철학 P1 R-id>", t1 = "<판단 T1 R-id>")   # 원장 첫 줄(사양 md5 · 해석된 규칙 · 기저 보는 창 지표 · 영수증)
```

```bash
round.sh - p4-base-spec --key "<풀 key>" --out <f>.json                    # 기저 칸 사양만 따로 만들 때
round.sh <사슬 디렉터리> p4-pool [--out f] · p4-check · p4-design [--out f]  # 설계 입력 = 생성기 입력(보는 창만)
round.sh <사슬 디렉터리> p4-register --p1 <R-id> --t1 <R-id>              # 감독 영수증 없으면 거부
round.sh <사슬 디렉터리> p4-base-measure                              # 기준 칸(k = 0) — 걸음 전 필수 · 기저 칸 사양을 걸음과 같은 러너 · 배리어 · 지문 · 판 표식으로 → base_measured
round.sh <사슬 디렉터리> p4-step-open --k 1 --hypothesis "…" --mechanism "…" --block <유형> --cell <칸 사양> --parent 0 --generator g1
round.sh <사슬 디렉터리> p4-step-measure --k 1                             # 배리어 대기 → 칸 사양 md5 대조 → 정본 셀 워커 → 원장 step_measured(종료 0 · 4 배리어 · 1 실패)
round.sh <사슬 디렉터리> p4-step-decide --k 1 [--artifacts <산출 폴더>]     # 산출 = step_measured 기록(넘기면 같아야 함) · 보는 창 지표(부모 0 = base_measured) → 채택 규칙 → accept | reject · r7
round.sh <사슬 디렉터리> p4-step-abandon --k 3 --reason "…"             # 측정 실패 2회 이상 · 측정 기록 없는 걸음 = 기각(산출 없음 · r7 NA) — 사슬이 멈추지 않게
round.sh <사슬 디렉터리> p4-workdir --out <사슬 밖 빈 폴더>                  # 생성기 작업 디렉터리(네 파일만 — design_input · 헌장(τ_D 뒤 날짜 가림) · toolbox · 부모 칸 사양)
round.sh <사슬 디렉터리> p4-status · p4-close --note "…" --probe "…" --probe "…" [--lesson "…"] --regrade-write|--regrade-dry-run --p2 <R-id> --t2 <R-id>   # 둘 중 하나 필수(닫기는 한 번뿐)
round.sh - p4-generator-review [--out f]                                   # 블록 유형별 채택률 · 보는 창 dS_vis · 주된 기각 사유(다음 판 재료)
```
- 명령 순서: `p4-register` → **`p4-base-measure`** → (`p4-workdir`(또는 `p4-design`) → 생성기 → `p4-step-open` → `p4-step-measure` → `p4-step-decide` | `p4-step-abandon`)× → `p4-close --regrade-write`. 기준 칸 측정 전에는 걸음 열기 · 측정 · 판정 · 설계 입력이 거부된다(건너뛰기 경로 없음).
- 원장(`chain_steps.jsonl`) 이벤트: `chain_registered`(규칙 해석본 · 영수증 · 풀 산출 지표 `base_metrics` = **참고 기록 · 판정에 안 씀**) · `base_measured` | `base_measure_failed` · `step_open` · `step_measured` | `step_measure_failed` · `step_result`(`artifacts_source` · `parent_basis`) · `chain_closed`.
- 기준 칸 측정(`rc_p4_base_measure(chain_dir, root, runner, barrier, fingerprint, vintage, metrics_fun)`): 기저 칸 사양 md5 = 사슬 판 확인 → 측정 사본 `measure/k0.spec.json`(sweep · family_root = 사슬 id · 시행 1) · role base → `base_measured`{artifacts · measured_spec_md5 · metrics(보는 창 — `rc_p4_visible_metrics`) · vintage · same_construction(기록) · measured_at}. 첫 걸음을 포함한 모든 비교의 기저 지표 = `base_measured$metrics` · 닫기 재채점 시행 집합의 기저 = `base_measured$artifacts`.
- 팩터 DB 판 표식: 측정마다 `contracts/factor_db_vintage.R::fdv_stamp` 의 직렬화 md5(`vintage.id` · 수리 수)를 `base_measured` · `step_measured` 에 적는다(완료 시각은 τ_D 뒤 날짜라 싣지 않는다). 걸음 측정 직전 표식 ≠ 기준 칸 표식이면 재지 않고 사유(원장 무기록) — "이 사슬을 닫고 새 사슬에서 기준 칸부터 다시". 판정도 표식이 다른 측정은 거부 · 닫기는 허용 · 표식 판독 불가 = 측정 거부(fail-closed).
- 걸음 측정(`rc_p4_step_measure(chain_dir, k, root, runner, barrier, fingerprint)`): 기준 칸 측정됨 · 열린 미판정 걸음 · 칸 사양 md5 = 열 때(R2) · 리프레시 배리어(`refresh_barrier.R::rb_status` — held · error 면 재지 않고 사유 반환 · 원장 무기록) → 측정 사본 `<사슬>/measure/k<k>.spec.json`(열린 사양 + `selection_accounting` 만 다시 씀: `selection_type = sweep` · `family_root = 사슬 id` · 계보 누적 시행 = 기저 1 + 지금까지 연 걸음 수 · `n_trials_basis` 문구 — 사슬도 회계는 스윕) → 기본 러너 `rc_p4_runner_default` = `Rscript rf_cell_worker.R <사양> 1 <사슬>_k<k> <결과 json>`(`v1/measure_cell.R` 와 같은 호출 · 요인 분석 끔 · **2계층 모듈 풀 등재 끔** `QVEST_RP_REGISTER = 0` — 기준 칸 · 걸음 칸 모두) → 데이터 지문 앞뒤 대조. ok ∧ 산출 폴더 ∧ 지문 같음 = `step_measured`{k · artifacts · vintage · measured_at · md5}, 아니면 `step_measure_failed`(다시 잴 수 있다). 시험은 `runner` 에 가짜 러너를 넣는다.
- 감독 영수증(라운드 등록 ⑥ 과 같은 규율 — 판단 원장 `06_Registry/q_judgment_ledger.json`): 등록 = 철학 P1(`register.R::rc_p1_check` 재사용 — 대상 round = 사슬 id · 파일 `…_P1_P4Cnn.md`) + 판단 T1 · 닫기 = 철학 P2 + 판단 T2 · 생성기 개정 `rxg_revise(…, philosophy_review = <R-id>)` = 철학 P1 | P4 · 대상 round = `P4_generator_<새 판 id>`. 공통: id 실재 · 역할 · 트리거 · 대상 일치 · 파일 실재 · 도전 · 정지 응답 · 열린 보류 요청 없음. 시험 우회 = `ledger` · `review_root` 인자(임시 원장)뿐.
- 걸음 열기 기계 검사: 앞 걸음 판정됨 · k 연번 · 칸 사양 1개(처음 보는 md5) · 부모 = 사슬 머리 · 부모와 **한 블록 유형만** 다름(고정 축 · 어휘 밖 축 거부 · 기저 변경은 풀 안 자격 엔진만) · 가설 · 기전 문장 · τ_D 뒤 날짜 없음 · 예산 안 · 생성기 md5 = 사슬 판.
- 닫기: 최종 후보 = 마지막 채택 걸음(채택 0 · 걸음 ≥ 1 이면 기저 자신 k = 0 · 기준 칸 산출 · 걸음 0 = `no_candidate`) · 결과 원장(`rc_outcome_record` · extra = 생성기 판 · 걸음 수 · 블록 유형별 채택/기각 · P2 · T2 id) · 마감 훅 `programs/selection_regrade.R::sr_regrade`(기준 칸 산출 + 모든 걸음 칸 = 시행 집합 · 결과는 `finalize.json`(사람 쪽)에만 · 원장엔 상태 · md5) → 새 등급 A 면 후보 관문 `programs/round_candidate_gate.R::rcg_route(후보, <사슬>_k<k>, 측정 사본 사양, root, write)`(파일이 있을 때 · 요약 action · eligible · codes · path 는 `finalize.json` 에만). 원장 · 결과 원장의 `candidate_gate` = `pending`(관문 파일 없음) | `evaluated`(A 아님도 같은 값 — 등급이 상태로 새지 않게) | `error` | `not_run`. Judge 요청 파일은 쓰지 않는다. 모듈 풀 등재 = 최종 후보 1개만 · `regrade_write` ∧ 재채점 뒤 등급 A | B 일 때 정본 등재기 `contracts/register_measured_module.R::rmm_register_measured(후보 산출, origin_mode = "replication", meta = 사슬)`를 측정 밖에서 사후 호출(sim 없이 계약 CSV 로 재조립 — `rf_replication_verify.R` 감사 뒤 등재와 같은 경로 · 자격은 등재기의 계약 술어가 다시 낸다) · `module_pool` = registered | not_registered | not_attempted | pending_manual(등재기 없음) | error → `finalize.json` · 결과 원장 줄.
- 처방 도구 상자(`02_Infrastructure/programs/rx_round.R`): `rx_validate(impl, root, pool)` 이 `base_signal`(풀 key · `engine_blend` keys ≥ 2 · 경로 지정 거부)과 `factors[].direction`(ic_asof | registry | defensive — defensive 는 등록부 방어 방향이 있는 팩터만)을 받는다 · 도구 상자 표에 방어 방향 열 · 헌장 격차 절 `rx_charter_gap_md(gap)`.
- 동시 진행 · 재진입(11-10): 원장 추가는 잠금 안에서 방금 읽은 원장으로 사건 단일성을 다시 본다(`.rcp4_unique_guard` — 같은 k 의 step_open · step_measured · step_result · 두 번째 base_measured · chain_closed · 닫힌 뒤 추가 = 거부). 측정은 칸마다 점유 `measure/<tag>.claim`(pid · 살아 있는 보유자 = `busy` 종료 7 · 죽은 pid = 인계 · 점유 뒤 원장 재확인). 측정 중 크래시 = 다음 실행이 점유를 인계해 다시 잰다. 닫기 중간 크래시(결과 원장 뒤 · chain_closed 전) = 다시 닫으면 결과 원장 중복 없이 chain_closed 1줄(재채점 · 관문 · 등재는 한 번 더 — 덮어쓰기).
- **채택 규칙 판 v2(`rules_version = p4_rules_v2` · 11-10 · 헌장 §5 빈칸 집행)**: 새 사슬 판은 v2 만 등록된다(표식 없는 옛 판 = v1 판독 — 옛 원장 판정 불변). 필수 지표 = `dS_vis` · `uc_vis` · `d_dd_capture_median_vis` + **N1 `uc_seg_ok_share_vis`**(강세 구간 중 상승 포착 ≥ 기준 칸 − 0.2·|기준 칸| 비율 · 빈칸 4 · 7 · 24 · 짝 ≥ 2) · **N2 `deep_crisis_nonworse_share_vis`**(깊은 위기 = 시장 낙폭 ≥ 중앙값 중 부모 이하 비율 · 빈칸 2 · 23 · 깊은 짝 ≥ 2). 선택 지표 = N3 `d_cdar_vis`(부모 대비 CDaR · 빈칸 5 · 18) · `rec_delay_share_vis`(기록) · N4 `worst_name_contrib_deep_vis`(깊은 위기 한 종목 기여 · 빈칸 1 · 규칙이 쓰면 판정이 `concentration = TRUE` 로 diagnosis_packet 을 부른다) · N5 `beta_asym_ok_vis`(노출 블록 regime_exposure · tail_overlay · defense_sleeve 만 하락 β < 상승 β · 그 밖 = 1). 재료 = `rc_p4_visible_metrics` 의 `bull_vis` · `crises_vis` · `cdar_vis` · `beta_*_vis`(행동 카드가 τ_D 에서 자른 표) · 없으면 NA = 기각. r7(v2) = `dS ≥ +여유`일 때만 signal · 그 밖 noise(`r7_detail` = improve | within | worse — 악화도 연속 '개선 없음'으로 센다). 닫기 결론 `extra.conclusion` = 엔진 대비 · 시장 대비(하락 포착 ≤ 1) · '시장보다 덜' 문장 허용 여부(빈칸 16). 기저 풀 `cash_machine`(상설 판정 기록 보는 창 uc < uc_floor = 제외 · 기록 없음 = unknown). MC8 선택 방어 라벨(빈칸 14) · 재시드 띠(빈칸 21)는 미구현(감사 E1 보고 — 걸음마다 MC8 짝 · 재시드 칸 측정이 필요).
- 지식 고리(11-10 · 감사 K): 결과 원장 쓰기 = 설계 입력 읽기와 같은 검사(`util.R::rc_input_issues` — τ_D 날짜 · 등급 표기) · 검사 강화 전 나쁜 줄은 처방 입력 읽기(`tau_clean`)에서 그 줄만 빠진다(경고) · τ_D 날짜 표기 변형(한국어 연월 · 슬래시 · 점 · ’yy년 · 분기 — `RC_TAU_ALT_RX`) · 설계 입력 §4b 다른 사슬 기각 걸음(사유 코드만) · `p4-step-open --probe-ref` = 탐침 이어받기 기록 · 칸 측정 L-code 끔 · 손상 줄 격리(사람 호출만: `p4-quarantine --line --reason` · `- outcomes-quarantine --line --reason` — 원장 줄은 지우지 않고 격리 기록 · 사본만).
- 신선도: 기준 칸 · 걸음 측정은 배리어 다음에 `rc_data_freshness`(위 절) — 낡음 · 판독 불가 = `data_stale`(원장 무기록 · 종료 6).
- 기저 풀 제외 사유(11-10 추가): `rule_change_beneficiary`(권위 기록 `selection_regrade$benefits_from_rule_change` 또는 `rule_change_benefit$benefit` — measurement-graduation §3b · 판정 = `rf_runner_gates.R::.rfg_rule_benefit` 정의를 구문 트리에서 꺼내 씀) · `rule_change_unknown`(판독 불가 · fail-closed). 상설 경로(새 측정)는 해당 없음.
- 닫기 후보 관문(11-10 추가): 새 등급 A 아님 = 관문 미호출 + 앞선 Judge 트리거 거두기(`rcg_withdraw` · 쓰기 모드) · finalize.json 에 `withdrawn` · 포기 걸음 수 `n_abandoned`.
- 시험: `08_Tests/scenarios/test_scn_l1_chain_e2e.R`(끝에서 끝 — 신선도 · 상설 원장 → 풀 · 사슬 전 상태 전이 · 실패 주입 · 두 프로세스 동시 측정 · 닫기 재진입 · 다음 사슬 설계 입력) · `08_Tests/programs/test_round_core_v1_p4_chain.R`(격리 — 임시 등록부 · 원장 · 생성기 등록부 · 판단 원장 · 합성 산출물 · 가짜 러너 · 가짜 재채점 · 관문 파일 · 실제 측정 없음).

## 모듈 (v1)

| 파일 | 내용 |
|---|---|
| `v1/load.R` | 단일 진입 |
| `v1/util.R` | 경로 · md5 · 원자적 JSON · 과반 · 안전 호출 · τ_D 가림/누출 검사 · 참조 해석 · 실행 시간 기록 |
| `v1/rules.R` | 규칙 선언(threshold · all_of · any_of · report) — 검사 · 해석 · 판정 · 문장 · 표 |
| `v1/metrics.R` | 지표 공급자(β-통제 알파 · 증분 알파 · 집중 · S) — 계약 호출 |
| `v1/spec.R` | 라운드 사양 검사 |
| `v1/p1.R` | P1 엔진 자격 판정 · 표준 구성 칸 사양(P0R01 C0 선례 · 정본 대조) · 라운드 골격 |
| `v1/pins.R` | 핀 계산 · 대조 단일 함수(코어 매니페스트 · 운영 파일 · 엔진 · 패키지 · R 판) |
| `v1/cell_eval.R` | 칸 평가(rk_eval_cell 이관) + 내용 주소 캐시 · 원자료 1회 적재 |
| `v1/register.R` | 초안 · 점검 기록(drafts.json — 점검본 사본 없음) · 등록 조건 ①~⑧ · 종료 기록 |
| `v1/driver.R` | 단계 실행(check · precheck · plan · draft · reviewed · register · evaluate · report · close) |
| `v1/measure_cell.R` · `v1/fingerprint.sh` | 칸 측정(정본 셀 워커) · 데이터 지문 |
| `v1/standing.R` | 상설 판 — 사양 검사 · 생성 함수 핀 · 레인 스캔(입구 규칙 · 사유 코드) · 항목 넣기 · 항목 R2 · 측정 · 판정 · 원장(추가 전용 사슬) · 보고 · Superfan 표식 · 상태 |
| `v1/freshness.R` | 측정 경로 데이터 신선도 판정(감사기 --check 진입점 · 정의 꺼내기) |
| `v1/p4.R` | P4 강화 사슬 — 기저 풀 · 격차(보는 창 A 하한 여유 · 병목) · 사슬 판 검사 · 걸음 원장(추가 전용 사슬) · 걸음 열기 · 판정 · 설계 입력 · 닫기(결과 원장 · 마감 훅) · 생성기 판(rxg_*) · 생성기 검토 |
| `v1/pair.R` | 짝 평가 골격(단계 목록 · 라운드 훅 · 미시험 사유) · P2 · P3 공용 도우미(위기 과반 · 깊은 위기 · 사이클 · 집중 · 회복 · 보유 대조 · 공통 창 · β 짝 사본) · 보는 창 / 사람 쪽 칸 평가 · 라운드 판정(판정 칸 수 · 판정어별 칸 수) · 선택 · 샤딩 · 메모(원자료 · ta_load_market · MC8) |
| `v1/p2.R` | P2(장치 × 엔진) 템플릿 — P2R04 판정 ①~⑭ 단계 · 기록 · 진단 읽기 · R7 · A 거리 · 보는 창 파일(τ_D 가림 · 전수 검사) · P2R05 범용분(시드 띠 · 판정 여유 · Dimson β · 위기 유형 · 유동성 3분위 귀속) · 사양 라운드 판정 |
| `v1/p3.R` | P3(구성 변형) 템플릿 — P3R03 결정 a~e · S · 알파 · β 짝(중앙값형) · 기전 방어 · 이력 탈락 · 후보 꼬리표 · 사양 라운드 판정 |
| `v1/rules_p2.R` | rules.R 선언 형식의 P2 규칙 종류 — 위기 과반 · β 짝 승 · 비열등 알파 · 상승 포착 · 축 감사 + 판정 표 · 선언 = 단계 판정 대조 |
| `rejudge/` | 끝난 라운드 재판정(결과 동일 실증) — 구판 고유 규칙(`P2R04_ext.R` · `P2R03_ext.R` · `P3R03_ext.R`) · 구 이름 심(`shims.R` — 구 픽스처를 코어로) · 재현 루트(`make_repro_root.R`) · 실행 · 대조 · 요약(`rejudge.R` · `run_rejudge.sh` · `compare.R` · `summarize.R` → `RESULTS.json`) · 캐시 실증(`cache_check.R`) · 속도표(`perf_table.R` → `../PERF.json`) · 구판 격리 실행(`legacy_sandbox.R` — 차이 분류) · P2R05 황금값(`p2r05_golden.R`) |
| `round.sh` | 셸 진입 — 측정 파이프라인 · 샤딩 평가(칸 평가 샤드 → 짝 평가 샤드 → 병합 종합) |
| `templates/DESIGN_p1.md` | 사고 기록 템플릿(코어 승계 항목은 다시 쓰지 않는다) |

## P2 · P3 라운드(사양만 쓴다)
- `round_spec.json` — `template: p2_device | p3_construction` · 칸(`code` · `engine` · `role` · `component` · `spec`) · `params`(판정 상수: 값 + 근거 또는 정본 참조) · `devices` · `diagnostics` · `rules`(P2 종류 포함 선언).
- 고유 규칙이 필요하면 `ext`(라운드 디렉터리 `round_ext.R`)에 `RC_EXT_CFG` · `RC_EXT_HOOKS`(단계 교체) · `RC_EXT_READINGS`(진단 읽기) · `RC_EXT_RULES_MAP` 만 쓴다.
- 판정 단계 · 기록 · 라운드 판정 · 보는 창 파일은 코어가 한다. 판정 시작에 선언 규칙과 단계 판정을 칸마다 대조해 어긋나면 판정하지 않는다(문구 표류 차단).

## 검증
- `08_Tests/programs/test_round_core_v1.R`: 규칙 · 사양 · P1R01 결과 동일. 원래 evaluate.R 격리 사본과 바이트 동일한지 본다.
- `08_Tests/programs/test_round_core_v1_flow.R`: 격리 흐름. 등록 거부 7종 · 등록 → 판정 → 종료 · R2 · 캐시 키 · 핀 · 표준 구성을 본다.
- `08_Tests/programs/test_round_core_v1_standing.R`: 상설 판 격리(RC_SA_ROOT · 임시 등록부 · 임시 원장 · 임시 레인). 입구 사유 코드 전수 · 주석 토큰 양성 대조 · 성과 무관 음성 대조 · 등록 → 스캔 → 측정(대체 워커) → 판정(코어 P1 판정과 같은 값) → 보고 · 항목 R2 거부 6종 · 칸 평가 예외 재시도 · 원장 사슬 변조 · 추가 잠금 · 새 판. 소스 텍스트 치환 뮤테이션 15종 전부 검출(10-20).
- `08_Tests/programs/test_round_core_v1_p2.R`(가벼움): 구 라운드 픽스처 3종을 코어 심으로(P2R04 52 · P2R03 33 · P3R03 48) · 코어 뮤테이션 15 · P2 규칙 종류 · 최소 사본 · 샤딩 · 메모 · τ_D · 사양 라운드 배선 · P2R05 범용분 = 원판 황금값 53 사례(`08_Tests/fixtures/round_core_p2r05_golden.json` · 생성기 `rejudge/p2r05_golden.R`) · 재판정 요약(`rejudge/RESULTS.json`).
- `08_Tests/programs/heavy_round_core_v1_p2_rejudge.R`(무거움 · SUITES 밖): 등록 커밋 핀 판 재현 루트 위에서 P2R04 → P2R03 → P3R03 재판정 · 저장본 대조 · 작업 사본 패킷 대조 · 요약 갱신.
  - 10-20 결과(`rejudge/RESULTS.json`): 세 라운드 판정 · 칸 판정 · 핵심 수치 · 보는 창 / 사람 쪽 파일 구조 차이 0 · 작업 사본 패킷 16/16 · 28/28 · 10/10 바이트 동일.
- `PERF.json`: 최종 판정 전후 시간(등록 당일 로그 · 같은 날 구판 격리 사본 짝 · 스레드 실험) · 캐시 · 메모 실증(`rejudge/cache_check.R`). 짝 평가 시간의 대부분은 패킷(dp_build) — 데이터 표 스레드 수는 거의 무관(8스레드 −6%)하고 샤드 수 K 가 손잡이다.

## 다음
- 측정 서버 `ms_submit` 연결(WP2) — 상설 측정(`standing-measure`)도 서버가 생기면 그쪽을 먼저 쓴다.
- P1 상설 자격(WP5) — P1S01 판 1 등록(11-11 15:12 · 코어 v1) · 측정은 도훈 '파일럿부터'(L1-CHAIN-PILOT-FIRST-20261111)로 `tick_hold` 보류 중.
- 출시: v1 = 11-11 13:44 · v2 = 11-11 18:29 · v3 = 11-11 23:30 · v4 = 11-13 20:07 · v5 = 11-15(RELEASES.json · 위 'v4' · 'v5' 절). 출시본 대조 검사(디렉터리 매니페스트 ≠ 출시 값이면 실패)는 아직 없다 — 지금 보증은 사양 핀(rc_pins_mismatches)뿐.
