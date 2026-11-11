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
- 출시: v1 = 11-11 13:44 · v2 = 11-11 18:29 · v3 = 11-11 23:30(RELEASES.json). 출시본 대조 검사(디렉터리 매니페스트 ≠ 출시 값이면 실패)는 아직 없다 — 지금 보증은 사양 핀(rc_pins_mismatches)뿐.
