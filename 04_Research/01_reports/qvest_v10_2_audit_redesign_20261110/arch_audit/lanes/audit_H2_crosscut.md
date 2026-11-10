# H2 교차 영역 감사 — 안 쓰는 프로세스 · 배선 · 실행 속도 (1단계 · 읽기 전용 · 2026-11-10)

작성: H2 레인. 아무것도 지우거나 고치지 않았다(운영 파일 · `.cache` · 등록부 · 예약 작업 쓰기 0). 산출 = 이 문서 + `dead_H2_crosscut.tsv` + 보조 파일(아래 §10).

## 1. 진입점(도달성의 뿌리)

| 종류 | 살아 있음 | 비고 |
|---|---|---|
| 예약 작업 17 (Qvest_*) | Ready 13 · Disabled 4 | 실행기 = `%LOCALAPPDATA%\Qvest\jobs\*.cmd`(qvest_tasks.ps1 생성) → `02_Infrastructure/ops/scheduler/*.bat` 등. `C:\Users\99922\OneDrive` = `G:\OneDrive` 심볼릭 링크(정상) |
| ├ 매일/시간 | DailyRefresh(rc 1) · MorningBrief(267014) · MorningReboot · StrandedRepairs(+handbook_facts_audit · scheduler_task_health) · SuperfanWatch(1h) · StressDaily · FundV2Update(rc 1) · InsiderBackfill(`stage_artifacts/dart_parser_build/code/run_backfill_daily.bat`) · ClaudeCliUpdate · MachineHeartbeat(5분) | 결과 코드 진단은 데이터 · 모닝 레인 몫 |
| ├ 주/월 | WeeklyCleaner(토 09:00 · 이 PC 미실행 267011 · StartWhenAvailable=True — 11-08 토요일을 놓친 원인 미확인) · AxiomReview(일 05:00 · `axiom_quarterly.sh`) · MonthlyDistill(12-01 첫 예정) | AxiomReview · MonthlyDistill = 오늘 끌 예정(총괄) |
| ├ Disabled | AuditWatch(`audit_watch.ps1`) · AxiomActivate(`rf_axiom_activate.R`) · ReinforceAutoLoop(`reinforce_auto_tick.sh` = **충실구현 레인 + 2계층 레인 진입점**) · WeightCatalogGrow | ReinforceAutoLoop 꺼짐 = 무인 충실구현 0(§8) |
| ├ 고아 실행기 | `jobs/Qvest_ZZ_wraptest.cmd`(지운 스크래치 job.bat 가리킴) · `jobs/noLayer4_Monthly_PaperTracking.cmd`(등록 작업 없음) · `jobs/off/DART_Insider_Backfill.cmd`(InsiderBackfill 로 대체) | 작업 없이 파일만 남음 |
| 등록 훅 | 서로 다른 .sh 13 · 10 매처 그룹(Pre: Write\|Edit 3 · Write 3 · Bash 2 · PowerShell 2 · Agent 1 · Read\|Grep\|Glob 1 / Post: Write\|Edit 1 / SessionStart 1 / SessionEnd 2) | `hooks/` 안 미등록 스크립트 ≈ 58(§3) |
| 스킬 21 + 느슨한 .md 3 | 동결 3(qvest-worktask · qvest-dossier-pipeline · qvest-multi-track) | `.claude/skills/{factor-db-access,optimized-backtest,pit-validation}.md` = 스킬로 적재되지 않음(목록 부재) |
| 에이전트 13 · 명령 6 · 룰 6(자동 2 · 경로 4) | 퇴역 폴더 3(agents/skills/commands_retired_v10) | `.claude/workflows/*.js` 2 = 동결 스킬 전용 |
| 레인 · 체인 | `round.sh`(round_core) · `morning_run.sh`(cron/reboot) · `daily_refresh.sh` · `standing_board_run.sh`(오늘 생성 · 미등록) | |

## 2. 파일 단위 도달성 — 방법과 한계

- 정적 그래프(`h2_reach.py` → `h2_an.py` → `h2_classify.py`): 말뭉치 = git 추적 + 비무시 미추적 + 대상 폴더 디스크 전체(44,444 파일 · `.claude/worktrees` 제외). 간선 = 파일 A 의 **주석 뺀** 본문에 든 파일 이름 토큰(경로 꼬리 2마디로 동명 파일 구분 · 같은 폴더 우선 · 후보 4개 이상이고 경로 없으면 연결 안 함). 전파 = 코드(.R .sh .py .ps1 .bat .cmd .js) 전부 · 설정 JSON 은 대상 파일 25개 미만을 가리킬 때만, 그리고 코드 · 설정으로만(색인 · 원장 허브 차단) · md 는 뿌리(스킬 · 에이전트 · 명령 · 룰 · CLAUDE.md)만 · `04_Research/programs/P*` 라운드 폴더는 .R 만 통과 · 운영 뿌리에서 `08_Tests` 로는 안 들어감(시험은 별도 뿌리).
- 뿌리 집합: 훅 13 · Ready 예약 작업 12 실행 파일 + heartbeat · 스킬/에이전트/명령/룰/CLAUDE.md · round.sh · 예정(standing_board_run.sh · Qvest_InfraCurrency.bat). 동결 스킬 · Disabled 작업 · 08_Tests 는 별도 집합(어디서만 닿는지 표시).
- 결과: 대상 2,019 파일 중 운영 도달 854 · 미도달 1,165. 동적 조립(paste0/설정 JSON 의 경로 · `list.files` 루프)은 ① 이름 줄기(stem) 전역 언급 ② 데이터 폴더 이름이 살아 있는 코드에 나오는지 ③ `methods/adapters` 의 list.files 로더 를 따로 확인해 confidence 를 낮췄다.
- **과대 도달 쪽 오차**(보수적 — 죽은 것을 산 것으로): 주석 아닌 문자열(메시지 · 정규식 목록)에 이름이 나오면 간선이 생긴다. 예: `arm_gen_read_guard.sh` 의 산출물 이름 정규식, `qvest_hook_router.py`. 그래서 미등록 훅 상당수가 '도달'로 나와 §3 에서 실행 패턴(`bash|source|python <이름>`)으로 따로 재판정했다.
- **과소 도달 쪽 오차**(위험 — 산 것을 죽은 것으로): 설정 JSON 이 경로를 쥐는 경우(예: `grade_v3.json::cr_notch.timing_evidence` → `timing_defense_evidence.json`). 등록부 표(§4)는 그래서 `cfg_indirect` 표식을 따로 달았다. **delete 행이라도 총괄 삭제 전 `git grep -n <이름>` 1회 재확인 권고.**

## 3. 안 쓰는 것 — 건수 (`dead_H2_crosscut.tsv` · 1212 행)

| 묶음 | 행 | certain/delete | probable/delete | probable·certain/decide | keep |
|---|---|---|---|---|---|
| `06_Registry/regime_published` | 184 | 0 | 4 | 180 | 0 |
| `02_Infrastructure/alpha_search` | 135 | 61 | 71 | 3 | 0 |
| `06_Registry/(top)` | 101 | 81 | 14 | 6 | 0 |
| `02_Infrastructure/reinforcement` | 84 | 24 | 5 | 55 | 0 |
| `02_Infrastructure/ops` | 79 | 17 | 17 | 45 | 0 |
| `06_Registry/overlay_ab_results` | 67 | 19 | 0 | 48 | 0 |
| `02_Infrastructure/hooks` | 64 | 11 | 31 | 22 | 0 |
| `02_Infrastructure/ml_pipeline` | 54 | 28 | 22 | 4 | 0 |
| `02_Infrastructure/data` | 47 | 7 | 14 | 26 | 0 |
| `04_Research/programs/_lib` | 45 | 37 | 5 | 3 | 0 |
| `06_Registry/live_track` | 42 | 0 | 9 | 33 | 0 |
| `06_Registry/m4_published` | 36 | 0 | 0 | 36 | 0 |
| `02_Infrastructure/portfolio` | 18 | 8 | 8 | 2 | 0 |
| `02_Infrastructure/regime` | 18 | 4 | 7 | 7 | 0 |
| `02_Infrastructure/contracts` | 17 | 1 | 12 | 4 | 0 |
| `02_Infrastructure/factor_db` | 17 | 0 | 0 | 0 | 17 |
| `02_Infrastructure/tools` | 15 | 6 | 4 | 5 | 0 |
| `04_Research/programs/_lib/round_core` | 15 | 0 | 0 | 0 | 15 |
| `02_Infrastructure/validation` | 14 | 3 | 9 | 2 | 0 |
| `06_Registry/prereg` | 14 | 0 | 0 | 14 | 0 |
| `02_Infrastructure/docs` | 13 | 3 | 0 | 10 | 0 |
| `02_Infrastructure/reports` | 11 | 5 | 6 | 0 | 0 |
| `02_Infrastructure/prompts` | 9 | 3 | 3 | 3 | 0 |
| `02_Infrastructure/worktask` | 9 | 0 | 3 | 6 | 0 |
| `02_Infrastructure/ast` | 8 | 2 | 2 | 4 | 0 |
| `02_Infrastructure/methods` | 8 | 0 | 0 | 8 | 0 |
| `06_Registry/ramp` | 8 | 0 | 0 | 8 | 0 |
| `00_Lawbook` | 7 | 4 | 0 | 3 | 0 |
| `06_Registry/book_carrier` | 6 | 0 | 0 | 6 | 0 |
| `02_Infrastructure/axiom` | 5 | 0 | 0 | 0 | 5 |
| `06_Registry/replication_slots` | 5 | 0 | 0 | 5 | 0 |
| `02_Infrastructure/(top)` | 4 | 2 | 0 | 2 | 0 |
| `02_Infrastructure/discovery` | 4 | 4 | 0 | 0 | 0 |
| `02_Infrastructure/memory` | 4 | 1 | 0 | 2 | 1 |
| `02_Infrastructure/attribution` | 3 | 0 | 2 | 1 | 0 |
| `02_Infrastructure/cpp` | 3 | 0 | 1 | 2 | 0 |
| `02_Infrastructure/observability` | 3 | 0 | 0 | 3 | 0 |
| `02_Infrastructure/ramp` | 3 | 0 | 2 | 1 | 0 |
| `02_Infrastructure/telegram` | 3 | 2 | 1 | 0 | 0 |
| `06_Registry/_archive` | 3 | 2 | 0 | 1 | 0 |
| `.claude/skills` | 3 | 3 | 0 | 0 | 0 |
| `(외부 실행기)` | 3 | 1 | 1 | 1 | 0 |
| `.cache` | 3 | 0 | 0 | 3 | 0 |
| `02_Infrastructure/monitoring` | 2 | 0 | 0 | 2 | 0 |
| `02_Infrastructure/report_templates` | 2 | 0 | 2 | 0 | 0 |
| `02_Infrastructure/search` | 2 | 0 | 0 | 2 | 0 |
| `06_Registry/lean_carrier` | 2 | 0 | 0 | 2 | 0 |
| `02_Infrastructure/book` | 1 | 1 | 0 | 0 | 0 |
| `02_Infrastructure/eval` | 1 | 0 | 1 | 0 | 0 |
| `02_Infrastructure/pipeline` | 1 | 0 | 1 | 0 | 0 |
| `.claude/worktrees` | 1 | 0 | 0 | 1 | 0 |
| `.claude/agents_retired_v10` | 1 | 1 | 0 | 0 | 0 |
| `.claude/skills_retired_v10` | 1 | 1 | 0 | 0 | 0 |
| `.claude/commands_retired_v10` | 1 | 1 | 0 | 0 | 0 |
| `.claude/workflows` | 1 | 0 | 0 | 1 | 0 |
| `.claude/(top)` | 1 | 1 | 0 | 0 | 0 |
| `Rplots.pdf` | 1 | 1 | 0 | 0 | 0 |
| **합계** | **1212** | **345** | **257** | **572** | **38** |

핵심 묶음(폴더 단위로 지울 수 있는 것):
1. **미등록 훅 ≈ 58개**(`02_Infrastructure/hooks/*.sh|py` 중 settings.json 13 밖). 실행자 검색(`source|bash|python … <이름>`)에서 등록 훅 · 살아 있는 스크립트가 실행하는 것은 `_shared_parse.sh`(safety_guard · axiom_context_inject 가 source) · `resolve_project.sh`(boot_lean · daily_refresh 등) 둘뿐 · `harness_health.sh`(bootstrap/health_full) · `pipeline_trigger.sh`(resurrection_verify) · `lockbox_paths.sh`(죽은 lockbox 훅들만) · `axiom_enforcement_hook.sh`(memory_knowledge_health 언급) 는 decide. 나머지는 실행자 0 — 다만 `08_Tests/hooks/run_all_hooks.sh` 스위트가 다수 참조 → 시험 레인과 한 묶음으로 지워야 한다.
2. `.claude/worktrees/elastic-diffie-5efb03/` — 10-17 에 멈춘 git 작업 트리(추적 35,914 파일)가 OneDrive 안에 있다. 동기화 대기열 · 전역 grep/find 시간 · 동명 파일 오인(본 감사도 처음에 걸림)의 원인. `git worktree remove` 대상(브랜치 `claude/interesting-ishizaka-0ee022` 처분 = 도훈).
3. 퇴역 폴더: `.claude/{agents,skills,commands}_retired_v10/`(15 파일) · `02_Infrastructure/prompts/_retired_v10/` · `.claude/skills/*.md` 느슨한 3장 · `.claude/settings.json.bak_20260704` · `Rplots.pdf`(루트 · 02_Infrastructure).
4. `06_Registry/alpha_frontier_queue.json.bak*` 40개 · `regime_published/*.bak_*` 20개(+ `regime_append_only.R` 가 게시마다 .bak 를 쌓고 지우지 않는다 — 오늘만 계열당 3개 이상) · `06_Registry` 일회성 스냅샷/매니페스트(distill_manifest_* 16 · *_snapshot_20260809* · *_20260704 등).
5. `02_Infrastructure/alpha_search/` 구 엔진 135(fe_*.R · factor_engine_*.R) — v10 이전 `run_alpha_search(factor_engine_path=…)` 시대 엔진. 현행 충실구현은 엔진을 `stage_artifacts/replication/<id>/` 에 두고, 현 큐(`alpha_frontier_queue.json`)는 이 폴더 엔진을 0회 참조. 단 팩터 DB 수리 뒤 재측정에 옛 결과를 재현해야 하면 필요할 수 있다 → 충실구현 레인과 교차 확인.
6. `ml_pipeline/` 54/55 · `reinforcement/` 84 · `ops/` 79 · `regime/` 18(forecaster v1tune/v2/v4 등) · `portfolio/` 18 · `discovery/` 4 — 영역 레인과 교차.
7. `04_Research/programs/_lib/` 1회성 파이프라인 · 로그 · night_state(43).
8. `.cache` 큰 백업(§9).

## 4. 등록부(06_Registry) writer · reader (`h2_registry_rw.tsv` · .bak · 로그 · `_archive` 제외 335)

| 분류 | 건수 | 뜻 |
|---|---|---|
| live | 103 | 살아 있는 코드에 writer · reader 둘 다 |
| writer0(stale snapshot) | 46(그중 설정 경유 35) | 읽는 코드만 — 사람이 쓰는 설정(`fundamental_source.json` · `kr_factor_returns.json` · `rx_generator.json` 등)과 낡은 스냅샷이 섞임 |
| reader0(write-only) | 17(설정 경유 11) | 쓰기만: `rf_trial_log.jsonl`(94 KB) · `rf_decisions.jsonl` · `knowledge_index.md`(368 KB) · `module_regime_admission.json`(402 KB) · `benchmark_parity_history.jsonl` · `book_carrier/h1*_ab_*.csv` |
| 코드 참조 0(orphan) | 153(설정 경유 40) | 큰 것: `vintage_cascade_20260923.json` 1.6 MB · `basis_break_registry.json` 1.6 MB(★`liquidity_basis.R:57` 이 읽음 — 정규식이 놓친 사례, live) · `round_closures_snapshot_20260809.jsonl` 1.4 MB · `lcode_distill_execution_20260704.json` 1.1 MB · `combination_candidates.json` 368 KB · `essence_regrade_20260824.json` 256 KB · `next_session_task.md` 38 KB |
| 죽은 코드만 참조 | 22 | |

v10.2 정본인데 **아직 한 번도 쓰이지 않은 원장**: `06_Registry/round_outcomes.jsonl`(사다리 6항 · 파일 없음) · `06_Registry/mechanism_atlas.jsonl`(writer `programs/mechanism_atlas.R` · 파일 없음) · `06_Registry/l2_judge_request.json`(정상 — A 없음). `timing_defense_evidence.json` 은 10-18 이후 갱신 없음. `.cache/portfolio_gap_vector.json`(pit.md §V6 가 읽으라는 파일)은 살아 있는 생산자가 없다(언급 = 미등록 훅 3개뿐).

## 5. 훅 지연

측정 = `hook_latency_bench.sh`(20회 중앙값 · 바깥 셸 없이 `bash 훅.sh` 만 잰다 · 쓰기 없는 평상 입력 · 결과 전부 allow 확인) · **부하 중 측정**(13:46 시작 CPU 77 % · 직전 96 % · Rscript 5~37 개). 기준선: bash 프로세스 1개 = **492 ms**, 파이썬 1회 기동 + JSON 파싱 = **795 ms**. 절대값은 부풀었다. 읽을 것은 구조다. 빠른 길이 켜진 훅은 모두 기준선 + 0~240 ms 안에 든다. 곧 **지연의 거의 전부가 프로세스 생성**이다. 실제 도구 호출에서는 Claude Code 가 훅마다 바깥 셸을 하나 더 띄운다(`DIR=…; bash 훅.sh` → 셸 2개).

| 이벤트 · 매처 | 훅(빠른 길 켬 ms / 끔 ms) | 도구 호출 1회 합(켬) | 안쪽 bash 수 |
|---|---|---|---|
| Pre Bash | safety_guard 607/1697 · telegram_direct_call_guard 619/2430 | 1,226 | 2 |
| Pre PowerShell | safety_guard 708/1621 · telegram 682/2393 | 1,390 | 2 |
| Pre Write(.md) + Post | safety 561 · legacy_write_block 603 · book_write_guard 556 · discovery_graduation_gate 543 · worktask_constraint_enforcer 463 · backtest_contract_audit 587 · Post overlay_pit_grep 599 (끔 합 11,052) | **3,912** | 7 |
| Pre Edit(.R) + Post | safety 565 · legacy 510 · book 519 · Post overlay 728 (끔 합 6,556) | 2,322 | 4 |
| Pre Read\|Grep\|Glob | arm_gen_read_guard 424/391 | 424 | 1 |
| Pre Agent | axiom_context_inject — 미측정(`.cache/axiom_inject_last.json` 을 쓰므로 실행하지 않음) · 정적 = 파이썬 2~3회 기동 | ≈ 2×795 + 492(추정) | 1 |
| SessionStart | boot_stamp_check 1,014/1,185 | 1,014 | 1 |
| SessionEnd | auto_commit · auto_push — 미측정(git 쓰기) | | 2 |

Claude Code 는 한 이벤트에 걸린 훅들을 병렬로 띄운다. 그래서 벽시계 대기는 '합'보다 짧을 수 있다. 다만 CPU 가 포화일 때는 병렬 생성끼리 서로를 늦춘다. 위 합은 도구 호출마다 쓰는 CPU 다.

**무엇을 지키는가(코드 확인)**
- `legacy_write_block.sh`: `/_archive_v55/ · /legacy/v55/ · /_archive_4_6/` 쓰기를 막는다. 그런 경로의 파일은 추적 0 · 미추적 0(git ls-files). **지킬 대상이 없다.**
- `discovery_graduation_gate.sh`: `*/WT-P*/request.json`(QEPM Deployment WT)을 쓸 때 HARD 3(PORT_t 2.95 · oos_retention 0.7 · Calmar 0.64)을 본다. 마지막 WT-P request = 2026-07-06 · QEPM-R0-FREEZE(09-25). 기준도 등급 v3.4(PORT_t 하한 2.0 · 시험 창 Calmar OOS 관문 · 선택 현실 점검)와 다르다.
- `worktask_constraint_enforcer.sh`: `optimization_package.json`(QEPM WT) 고정 축을 검사한다. 마지막 쓰기 2026-09-03 · 동결.
- `axiom_context_inject.sh`: Axiom 엔진 보관(11-10) 뒤 변동부는 `axiom_engine_status.json::inject_variable_part` 스위치로 켜고 끈다. 의미가 남은 것은 고정부(고정 축 문구)뿐이다 → 총괄의 Axiom 처분과 한 묶음.
- 살아 있음: safety_guard(생산 · 문헌 폴더 · 경로 정규화 낱말) · telegram_direct_call_guard · book_write_guard(BOOK 등록부) · backtest_contract_audit(원장 · 방법론) · overlay_pit_grep(C5 권고) · arm_gen_read_guard(생성기 세션만) · boot_stamp_check.

**제안 A — 판정 불변 빠른 길(바깥 셸에서 걸러 안쪽 bash 를 생략)**. 각 훅에는 이미 WP4 빠른 길 조건이 있다(증명 · 동치 시험 `08_Tests/hooks/test_hook_fastpath_equivalence.sh`). 그 조건을 settings.json 명령 앞으로 글자 그대로 옮긴다. 조건이 거짓이면 그 훅의 원래 출력은 `{}` 로 증명돼 있으므로, 바깥 셸이 `{}` 를 내도 판정이 같다. 참이면 같은 stdin 을 그대로 넘긴다(`$(cat)` 이 끝 줄바꿈을 지우는 것은 훅 안 `INPUT=$(cat)` 과 같다). `QVEST_HOOK_FASTPATH=0` 은 그대로 존중한다.
```
# arm_gen_read_guard (훅 130행과 글자 그대로 같은 조건 — 그 앞 줄은 정의뿐 · stdin 미소비)
if [ "${QVEST_ARM_GEN:-0}" != "1" ] && [ "${QVEST_DESIGN_LANE:-0}" != "1" ] && [ "${QVEST_CLEAN_LANE:-0}" != "1" ]; then echo '{}'; exit 0; fi; DIR=…; bash "$DIR/02_Infrastructure/hooks/arm_gen_read_guard.sh"
# discovery_graduation_gate (훅 51~54행)
I=$(cat); if [ "${QVEST_HOOK_FASTPATH:-1}" != "0" ]; then case "$I" in *WT-P*|*'\u'*) : ;; *) echo '{}'; exit 0 ;; esac; fi; DIR=…; printf '%s' "$I" | bash "$DIR/…/discovery_graduation_gate.sh" 2>>/tmp/discovery_graduation.log || true
# worktask_constraint_enforcer (39~42행) : *optimization_package*|*'\u'*
# telegram_direct_call_guard (46~49행)   : *tg_send*|*'\u'*
# overlay_pit_grep (33~36행)             : *'.R"'*|*.R$'\r'*
# book_write_guard (50~53행)             : *06_Registry*|*book_state*|*'\u'*|*[[:cntrl:]]* → 통과 · '{'*'}' → '{}' · 그 밖 → 통과
# legacy_write_block · backtest_contract_audit 은 조건이 함수(_lwb_may_match · _bca_may_target)라 그 본문까지 옮겨야 한다 — 옮기지 말고 B 로.
```
예상(같은 부하 · 안쪽 bash 기준): Read\|Grep\|Glob 424 → 0 ms(가장 잦은 호출) · Bash 1,226 → 607(telegram 생략) · PowerShell 1,390 → 708 · Write(.md) 3,912 → 1,751(safety + legacy + backtest 만 남음) · Edit(.R) 2,322 → 1,803(book 생략 · overlay 는 .R 이라 남음). 바깥 셸 생성은 그대로다. 주의: settings.json 은 총괄 관할이다. 등록 훅 수는 바뀌지 않는다. 바꾼 뒤에는 settings 명령 단위로 동치 시험(빠른 길 켬/끔 × 입력 표본)을 한 번 더 돌려야 한다.

**제안 B — 결정 필요(판정이 바뀐다)**: 퇴역 아키텍처 가드 3개의 등록을 해제한다. 대상은 legacy_write_block(대상 경로 0) · discovery_graduation_gate · worktask_constraint_enforcer(QEPM 동결)다. 이 해제로 판정이 달라지는 입력은 각 가드의 경로 패턴을 담은 Write 뿐이고, 지금 그런 쓰기를 하는 코드 · 스킬은 0개(동결)다. 효과: Write 마다 바깥 셸 3 + 안쪽 bash 3 이 줄어 Write(.md) 3,912 → 약 2,300 · A 와 합치면 약 1,150. 등록 훅은 13 → 10. QEPM 동결을 해제할 때 되살릴 수 있도록 git 태그를 남긴다.

## 6. 부팅

측정 = `boot_bench.sh`(boot_lean.sh 의 파이썬 블록만 · 3회 · `.cache/boot_stamp.json` 쓰기와 alerts_digest 재빌드는 뺐다) · **부하 중 측정**(CPU 91 %). 합 **4.3 / 5.3 / 8.4 s**로, qvest.md 의 '≈5초'와 같은 범위다. 단계(1회 · 누적 실행):

| 단계 | ms | 무엇 |
|---|---|---|
| ① Data | 2,867 | `pyarrow` 가져오기 + `factor_db/factor_ic_monthly.parquet` 의 Factor_Name 열 읽기 + rawdata 스키마 + krx_holidays |
| ② Queue | 909 | 자식 파이썬 `research_pool_predicates.py alpha-pending stage_artifacts/paper_recharge`(따로 재면 0.85~1.26 s) |
| 가져오기 | 173 | |
| ③~⑧ | 93 | Last(l_code glob) · Book · Alerts · Programs · 대기 결정 · Resume · Infra |

- 퇴역 대상 검사 줄: ③ Last 가 아직 `qepm/memory/axioms/review_log/dryrun/` 를 glob 한다(Axiom 보관 뒤 의미 없음 · 블록 140행). ⑤ 'v9 예산 4종'의 `hooks 14/13 ✗` 는 **오탐**이다. `hk` 정규식(블록 165행 · `hooks/…\.sh` 를 파일 아무 곳에서나 셈)이 settings.json `_doc_powershell_guards` 설명 속 `08_Tests/hooks/test_hook_powershell_coverage.sh` 까지 센다. 패치: `re.findall(r'"command":\s*"[^"]*02_Infrastructure/hooks/([A-Za-z0-9_.-]+\.sh)', …)`(command 값만 센다). 같은 줄의 `CLAUDE.md 14563/8192 ✗ · ctx 165288/50000 ✗` 는 늘 ✗ 다. 예산 문턱이 현실과 어긋나 신호 가치가 0 이다(도훈 결정).
- `boot_currency_check.sh` 는 /qvest 부팅에서 **돌지 않는다**(호출자 = bootstrap.sh · health_full.sh · 시험). CLAUDE.md:7 의 'C0 파생'은 주간/수동 점검에서만 참이다.
- 단축안(판정 불변): ① Data 의 팩터 수 · 축 계수를 `factor_ic_monthly.parquet` mtime 을 키로 삼은 작은 JSON 메모(`.cache/boot_memo.json`)에서 읽으면 pyarrow 가져오기를 생략해 약 2.5 s(부하 중)를 아낀다. ② Queue 는 자식 파이썬 대신 같은 프로세스에서 모듈로 가져오면(boot 가 이미 session_resume · infra_currency 를 그렇게 한다) 파이썬 기동 1회(0.5~0.8 s)를 아낀다. 예상 4.3 s → 약 1.5 s(부하 중 · 미검증).

## 7. 스킬 · 에이전트 · 명령

| 대상 | v10.2 호출 근거 | 상태 | 낡은 사실 · 죽은 경로 | 설명(문맥) 자 |
|---|---|---|---|---|
| research-program | CLAUDE · lean-loop · qvest.md | 활성(1계층 정본) | `:80` `:203` 이 가리키는 `round_outcomes.jsonl` · `mechanism_atlas.jsonl` 아직 없음 | 774 |
| alpha-search(스킬+에이전트+명령) | CLAUDE · 코드 56 | 활성(레인 꺼짐) | 'S0~S5' 류 3 | 691/825/143 |
| reinforce | 코드 109 · 8 스킬 | 활성(2계층 · 도구 상자) | `l2_judge_request.json` 미생성(정상) | 661 |
| strategy-rotation · book · book-rebalance · book-tracker · judge | CLAUDE | 활성 | strategy-rotation 낡은 용어 5 · dispatch-orchestrator 8 | 599/485/419/707 |
| qvest-telegram | 11 참조 | 활성 · **본문 52.8 KB**(호출 때마다 적재) | 낡은 용어 19(v8 · cert · governor) | 552 |
| qvest-advisor + style 4 + alpha/risk/optimizer-research(스킬 3 + 에이전트 3) · alpha-hypothesis · forge | /advisor | 활성(자문) · forge = QEPM 실행기(동결 체인) | advisor `:28` `grade_a_queue.json` 없음 · forge 낡은 용어 7 | 784 외 |
| superfan 3종 | 규약 | 활성(총괄 통합 중 — 손대지 않음) | `superfan.md:56` · `superfan-philosophy.md:47` 이 가리키는 `round_outcomes.jsonl` 아직 없음(2단계 정정: 확장자 지적은 정규식 절단 오탐 — 철회) | **1,070 / 1,429 / 1,441**(가장 큼) |
| cleaner | WeeklyCleaner | 활성 | `:126 :136 :200` `axiom/distilled.R`(오늘 삭제) · `:137` 시험 | 595 |
| qvest-hook-debug | 호출 근거 0 | **퇴역 후보** — 'v8.x router selftest · cert eligibility' | 낡은 용어 13 | 142 |
| improve-drain · factor-db-discovery · kr-inverse-pattern-miner | 문서 호출 0 · 코드 1~3 | decide(부팅 5줄이 큐를 안 띄움) | | 461/562/219 |
| qvest-worktask · worktask(명령) · qvest-dossier-pipeline · qvest-multi-track · workflows 2 | 동결 | decide(QEPM-R0-FREEZE) | qvest-worktask `:75` `research_ev_map.json` 없음 | 286/97 |
| architect(에이전트) | 참조 0 | decide | | 172 |
| simplify | Bash 도구 지침(커밋 전 필수) | 유지 | QEPM 3-agent 용어 | 217 |

세션마다 실리는 설명 합(스킬 21 + 에이전트 13 + 명령 6) ≈ 17.4 KB(UTF-8 바이트). 가장 큰 3개 = superfan 3종(3.9 KB · 23 %). (표의 '자' 열도 바이트다.)

## 8. 예약 작업 정리안 (등록 · 변경 = 도훈 · 일반 PowerShell)

| 작업 | 목적 | 상태 | 권고 |
|---|---|---|---|
| DailyRefresh · MorningBrief · MorningReboot · StrandedRepairs · SuperfanWatch · StressDaily · FundV2Update · InsiderBackfill · ClaudeCliUpdate · MachineHeartbeat | 데이터 · 모닝 · 감시 · 기계 | Ready | 유지(결과 코드 1 · 267014 진단은 데이터/모닝 레인) |
| WeeklyCleaner | 주간 스윕 + 증류 | Ready · 이 PC 미실행 | 유지 · **11-14(토) 09:00 첫 실행 확인**. StartWhenAvailable=True 인데 11-08 을 놓친 원인은 미확인이다(등록 시각이 11-08 09:00 뒤였을 가능성) |
| AxiomReview · MonthlyDistill | Axiom 주간 검토 · 월간 증류 | Ready | 끄기(총괄 예정). 끈 뒤 Export→Apply 로 실행기를 jobs\off 로 옮긴다 |
| AxiomActivate · WeightCatalogGrow | Axiom 활성 · 비중 카탈로그 | Disabled | **등록 해제**(퇴역) |
| AuditWatch | SACL 감사 디제스트(boot_currency_check C11 의 입력) | Disabled | decide. 켜거나, 끈 채로 두려면 C11 을 걷어 낸다(지금 상태면 health_full 에서 늘 실패할 것으로 보임 · 미확인) |
| ReinforceAutoLoop | **충실구현 레인 + 2계층 레인 틱**(`reinforce_auto_tick.sh` · config `replication_lane.enabled=true`) | Disabled | **decide — 켜기 권고**(P/L 제약 1) |
| (없음) noLayer4_Monthly_PaperTracking | BOOK_0001 noLayer4 월간 추적(`monitoring/run_nolayer4_monthly.bat`) | 실행기 .cmd 만 있고 작업은 없음 | decide. 다시 등록하거나, /book 트래킹이 대신하면 실행기와 monitoring 4파일을 퇴역 |
| (신규) Qvest_InfraCurrency | 인프라 판 점검(기계마다 · machines.conf period local) | 미등록 · bat · XML 백업 있음(매일 05:40) | 등록 |
| (신규) Qvest_StandingBoard | 상설 판 한 틱(`standing_board_run.sh`) | 미등록 · bat · XML 없음 | 등록(시각과 `--send` 여부 = 도훈) |

절차(일반 PowerShell · Claude 세션 밖 · 관리자 불필요). 도구 세션 안에서는 HKCU/AppData 쓰기가 가상화된다.
```powershell
$R = 'C:\Users\99922\OneDrive\Quant_Module_Moltbot'; $Q = "$R\02_Infrastructure\ops\machine\qvest_tasks.ps1"
$T = "$env:USERPROFILE\Desktop\qvest_tasks_20261110"          # 백업 겸 Apply 원본
powershell -NoProfile -ExecutionPolicy Bypass -File $Q -Mode Export -Out $T                     # 0) 현재 원본 백업
Disable-ScheduledTask -TaskName Qvest_AxiomReview; Disable-ScheduledTask -TaskName Qvest_MonthlyDistill   # 1) 끄기
Unregister-ScheduledTask -TaskName Qvest_AxiomActivate -Confirm:$false                           # 2) 퇴역 작업 해제
Unregister-ScheduledTask -TaskName Qvest_WeightCatalogGrow -Confirm:$false
powershell -NoProfile -ExecutionPolicy Bypass -File $Q -Mode Export -Out "$T\after"              # 3) 끈 상태로 다시 내보내고
powershell -NoProfile -ExecutionPolicy Bypass -File $Q -Mode Apply -From "$T\after" -Name Qvest_AxiomReview,Qvest_MonthlyDistill   #    실행기를 jobs\off 로
powershell -NoProfile -ExecutionPolicy Bypass -File $Q -Mode Apply -From "$R\02_Infrastructure\ops\scheduler\_task_xml_backup" -Name Qvest_InfraCurrency   # 4) 신규 등록
Remove-Item "$env:LOCALAPPDATA\Qvest\jobs\Qvest_ZZ_wraptest.cmd", "$env:LOCALAPPDATA\Qvest\jobs\off\DART_Insider_Backfill.cmd", "$env:LOCALAPPDATA\Qvest\jobs\off\Qvest_AxiomActivate.cmd", "$env:LOCALAPPDATA\Qvest\jobs\off\Qvest_WeightCatalogGrow.cmd"   # 5) 고아 실행기
powershell -NoProfile -ExecutionPolicy Bypass -File $Q -Mode Status                               # 6) 확인
# (결정 시) 충실구현 레인: Enable-ScheduledTask -TaskName Qvest_ReinforceAutoLoop → Export → Apply -Name Qvest_ReinforceAutoLoop
```
StandingBoard 는 Q 가 먼저 두 파일을 만든 뒤 4) 와 같은 Apply 로 등록한다. ① `02_Infrastructure/ops/scheduler/Qvest_StandingBoard.bat`: SuperfanWatch.bat 과 같은 PATH · 환경 머리 + `cd … && bash 02_Infrastructure/ops/standing_board_run.sh [--send] >> .cache/scheduler_logs/standing_board_task.log 2>&1`. ② XML: `_task_xml_backup/Qvest_SuperfanWatch.xml` 을 본떠 Command 만 바꾸고, 트리거는 도훈이 정한 시각. 노트북(secondary)은 machines.conf period 기본(메인 게이트) 기준으로 따로 Apply 할 필요가 없다.

## 9. 문서 무게 · `.cache` 고아

**매 세션 문맥에 실리는 것**: CLAUDE.md 14,563 B(106줄) + 자동 룰 pit.md 8,105 B + lean-loop.md 9,957 B = **32.6 KB** · 스킬/에이전트/명령 설명 합 17.4 KB(UTF-8 바이트 · superfan 3종 3.9 KB = 23 %). 경로 트리거 룰: measurement-graduation.md **38,952 B**는 `02_Infrastructure/contracts/**` 를 건드릴 때마다 실린다(계약 수리 세션마다). axioms.md 9.4 KB 는 Axiom 보관 뒤 트리거 경로 `02_Infrastructure/axiom/**` 가 비어 간다. python-policy.md 8.8 KB 는 **모든 .py** 에 실린다.

사실과 어긋나거나 중복인 구절:
- CLAUDE.md:7 — '`boot_currency_check.sh` C0 파생'이라 하지만 부팅(/qvest = boot_lean)은 그 검사를 돌리지 않는다.
- CLAUDE.md:105 · qvest.md:58 — 'settings.json 13 distinct .sh' 는 맞다. 다만 부팅 ⑤ 줄은 14 로 센다(§6 오탐).
- lean-loop.md:44 — '등급 v3.2 에서 정한 규칙 · **현행 판 v3.3**'. 같은 파일 :45 와 CLAUDE.md 는 v3.4 다.
- pit.md:57~62 'S0/S1 오버레이 금지'는 S0~S5 · v6.4 Optimizer/Forge 같은 QEPM 시대 단계명을 쓴다. pit.md:75~80 'V6 Gap-Directed 가설'이 읽으라는 `.cache/portfolio_gap_vector.json` 은 살아 있는 생산자가 없고, 읽는 쪽도 미등록 훅 3개뿐이다. 자동 로드 룰이 현 루프에 없는 단계를 지시하고 있다.
- measurement-graduation.md:33 · :46~47 — HARD 3(PORT_t ≥ 2.95 · oos_retention ≥ 0.7 · Calmar ≥ 0.64)을 'essence Grade A 의 HARD 3종'이라 부른다. 그러나 등급 v3.4 의 A 하한은 PORT_t ≥ 2.0 · 시험 창 Calmar OOS 관문 · 선택 현실 점검이다(CLAUDE.md §등급). 훅 discovery_graduation_gate 도 이 구 기준을 쓴다.
- research-program SKILL:80 · :203 · superfan.md:56 · superfan-philosophy.md:47 — `round_outcomes.jsonl` · `mechanism_atlas.jsonl` 은 아직 한 번도 생성되지 않았다(2단계 정정: 확장자 지적 철회 — 문서 표기는 .jsonl 로 맞다). cleaner SKILL:126 · :136 · :200 은 오늘 삭제된 `axiom/distilled.R` 을 가리킨다.
- qvest-telegram SKILL 본문은 52.8 KB 로 호출 때마다 실리고, 낡은 용어가 19개 남아 있다.

**`.cache`(53.6 GB · OneDrive 동기화 대상) 큰 것 · 읽는 코드**

| 크기 | 경로 | 읽는 코드 |
|---|---|---|
| 22.6 GB | factor_db_daily | 살아 있음(팩터 DB) |
| 8.2 GB | pins/(47 · WT-D2026* 포함) | pin_cache.R · 동결 WT 라운드 핀은 decide |
| 7.1 GB | factor_db | 살아 있음 |
| **6.7 GB** | factor_db_backup | 전체 재빌드 스크립트만(백업) · decide |
| 1.2 GB | flow_features_daily.parquet | incremental_update_file.R |
| 0.9 / 0.7 / 0.7 GB | factor_combinable · investor_stock · factor_db_partcache | 살아 있음 |
| **1.2 GB** | rawdata_pre_naveradj_2026101{5,6,7}.parquet | 쓰는 쪽(naver_data_collector.R)만 · 백업 |
| **0.4 GB ×3** | backup_cal20241230_20261017_175419 · RAWDATA_pin20260703.parquet · pin/ | 코드 참조 0 |
| 0.28 GB | fundamental_backup | fundamental_produce_v2.R(백업) |
| 0.13 / 0.11 GB | installers · nps_probe | 0 · probe |

백업 · 참조 0 합 ≈ **9.5 GB**(factor_db_backup 6.7 + rawdata_pre 1.2 + 0.4×3 + installers 등). 저장소 쪽에서 grep/동기화 부담이 가장 큰 것은 `.claude/worktrees/elastic-diffie-5efb03`(추적 35,914 파일 · 10-17 정지)다. 크기는 du 가 180 s 안에 끝나지 않아 미확인이다.

## 9-b. P/L 우상향 관점의 최대 제약(교차 영역)

1. **재료 공급 레인이 꺼져 있다**: `Qvest_ReinforceAutoLoop` = Disabled(이 PC 실행 0회)인데 config 는 `replication_lane.enabled=true` 다. 무인 충실구현 → 상설 판 → 기저 풀로 이어지는 v10.2 사다리의 입구가 돌지 않는다. 상설 판(`standing_board_run.sh`)도 미등록이다.
2. **닫기 원장이 비어 있다**: 결과 원장 `round_outcomes.jsonl` · `mechanism_atlas.jsonl` 이 아직 없다. 사다리 6항('다음 설계는 원장에서 출발')의 재귀 개선 고리가 아직 한 바퀴도 돌지 않았다.
3. **낡은 규칙이 문맥과 지연을 차지한다**: 자동 로드 룰(pit.md)의 QEPM 단계 지시, A 기준과 다른 measurement-graduation HARD 3 · 졸업 훅, Write 마다 퇴역 가드 3개(CPU 약 1.6 s · 부하 중). 판정은 바꾸지 않지만, 라운드를 도는 세션의 문맥과 도구 지연을 계속 갉아먹는다.

## 9-c. 도훈 결정 필요

| 항목 | 선택지 | 권고 |
|---|---|---|
| ReinforceAutoLoop | 켜기 / 끈 채 유지 | 켜기(재료 공급) |
| Qvest_StandingBoard | 등록 시각 · `--send` | 등록 · 처음 1주 드라이런 |
| 퇴역 가드 3(legacy · discovery_graduation · worktask_constraint) | 등록 해제 / 유지 | 해제(대상 0 · 동결) + 태그 |
| AuditWatch / C11 | 켜기 / C11 퇴역 | 둘 중 하나로 정합 |
| noLayer4 월간(BOOK_0001) | 재등록 / /book 으로 일원화 후 퇴역 | /book 일원화 확인 뒤 퇴역 |
| `.claude/worktrees/elastic-diffie-5efb03` · 브랜치 | 제거 / 보존 | 제거(10-17 정지) |
| `.cache` 백업 ≈ 9.5 GB · WT 핀 | 99_Archive 밖 로컬로 이동 / 삭제 / 유지 | 데이터 레인 확인 뒤 정리 |
| alpha_search 구 엔진 135 | 삭제 / 보관 | 충실구현 레인과 교차 확인(재측정 재현 필요성) |
| 부팅 예산 문턱(CLAUDE.md 8192 · ctx 50000) | 현실화 / 문서 감량 | 문서 감량(CLAUDE.md 사실 오류 4줄부터) |

## 10. 보조 파일(스크래치)

`h2_reach.py`(그래프 · 2분) · `h2_an.py`(뿌리 · 도달) · `h2_classify.py`(TSV) · `h2_registry.py`(등록부 표) · `h2_reach2.json` · `h2_registry_rw.tsv` · `hook_latency_bench.sh` + `hook_latency_result.tsv` · `boot_bench.sh` + `boot_py_block.py`. 재실행: `cd <repo> && python -X utf8 <SCR>/h2_reach.py . <SCR>/h2_reach.json && python -X utf8 <SCR>/h2_an.py . reach && python -X utf8 <SCR>/h2_classify.py .` (classify 는 뒤에 덧붙인 폴더 · 훅 행을 다시 지우므로 덧붙임은 재수행 필요).
