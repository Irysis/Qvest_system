# 강화 사슬 무인 틱 — 설계 (chain_tick v1 · 2026-11-10)

결정 근거: 도훈 11-10 CHAIN-AUTOMATION-STANDING-BOARD-AND-TICK-20261110 "만들고 바로 켠다" · 같은 날 저녁 "사슬 무인틱 구축은 해둬".
이 문서만 보고 구현할 수 있게 쓴다. 코어(`04_Research/programs/_lib/round_core/v1/*.R` · `round.sh`)는 **고치지 않는다** — 빈 곳은 §9 core_gaps 와 우회.

---

## 0. 한 줄 요약

`chain_tick.sh`(오케스트레이터 · LLM 없음) → 사슬마다 읽기 전용 계획기 `chain_tick.R plan` 이 다음 행동 하나를 낸다 → 틱은 **허용 목록에 있는 round.sh 명령만** 부른다.
다음 걸음 설계가 필요할 때만 별도 무인 LLM 러너 `chain_gen_run.sh`(청정 레인 · 읽기 3도구 · 단일 진입 `rf_llm_agent_run`)를 한 번 부르고,
그 산출을 `chain_tick.R compile`(rx_parse_json → rc_input_issues → rx_validate → 칸 사양 컴파일)로 검사한 뒤 `round.sh <사슬> p4-step-open` 에 넘긴다(최종 판정 = 코어).
등록 · 닫기 · 생성기 새 판 · 격리는 틱이 **절대** 부르지 않는다 — 닫을 때가 되면 '닫기 대기' 알림 1통.

## 1. 파일 구성

| 파일 | 역할 | 비고 |
|---|---|---|
| `02_Infrastructure/ops/chain_tick.sh` | 진입점(인자 없음 = 실제 · `--dry-run` · `--reset <chain_id>`) | 예약 작업 Qvest_StandingBoard.bat 이 `bash 02_Infrastructure/ops/chain_tick.sh` 로 부른다(이미 배선 · 파일이 있을 때만) |
| `02_Infrastructure/programs/chain_tick.R` | 읽기 전용 계획기 + 컴파일러 + 알림 문안 | 하위 명령 `config` · `list` · `plan` · `compile` · `abandon-reason` · `notify` |
| `02_Infrastructure/ops/chain_gen_run.sh` | 생성기 LLM 1회(무인 LLM 러너 계약 대상) | 최상위 선형 스크립트(paper_router_run.sh 와 같은 모양 — 계약 시험의 앵커가 열 0 에 있어야 한다) |
| `06_Registry/chain_tick.json` | 스위치 · 상한(§4) | 새 등록부 · 쓰기 = 사람(도훈/세션) |
| `08_Tests/scenarios/test_scn_chain_tick.sh` | 셸 오케스트레이션 시나리오(가짜 round.sh · 가짜 계획기 · 가짜 claude) | §8 |
| `08_Tests/scenarios/test_scn_chain_tick_core.R` | 계획기 · 컴파일러 ↔ 실제 코어 상태 전이(임시 루트 · 가짜 측정) | §8 |
| `08_Tests/scenarios/test_scn_chain_gen_guard.sh` | 생성기 읽기 경계 양성 대조(가드 탐침) | §8 |

틱이 쓰는 곳(운영 실행 때): `.cache/chain_tick.lock/`(자기 잠금) · `.cache/chain_tick/state/<chain_id>.json`(틱 장부 — 원장 아님) · `.cache/chain_tick/llm_backoff.json` · `.cache/scheduler_logs/chain_tick_<YYYYmmdd_HHMMSS>.log` ·
`04_Research/programs/P4_ASSEMBLY/_lanes/<chain_id>/k<k>_<YYYYmmdd_HHMMSS>/`(생성기 작업 폴더) · `<사슬>/cells/k<k>.json`(걸음 칸 사양 — 열기 전 1회 쓰기).
원장(`chain_steps.jsonl`)에는 **round.sh 명령으로만** 쓴다.

### 1.1 근거(파일:행)

- 사슬 위치 = `04_Research/programs/P4_ASSEMBLY/*/chain_spec.json`(p4.R `.rcp4_other_chain_rejects` 의 glob · p4.R:1088 부근). `_generator` · `_lanes` 처럼 `_` 로 시작하는 폴더는 사슬이 아니다.
- 원장 사건: `chain_registered` · `base_measured` · `base_measure_failed` · `step_open` · `step_measured` · `step_measure_failed` · `step_result`(abandoned TRUE 포함) · `chain_closing` · `chain_closed`(p4.R:593~610 · 679 · 929 · 935 · 972 · 976 · 1040 · 1063 · 1316 · 1389).
- 걸음 열기 거부 조건(p4.R:732~792): 앞 걸음 미판정 · k ≠ 다음 번호 · 예산(max_steps · noise_k) · 부모 ≠ 머리 · 블록 어휘 · 생성기 판 md5 · 가설 · 기전 rc_input_issues · 칸 사양 md5/정규화 서명 중복 · rc_p4_spec_diff(한 블록만).
- 측정 상태(p4.R:869~907 `.rcp4_run_cell`): barrier_held · data_stale · vintage_unknown · vintage_in_progress · vintage_changed(원장 무기록) · failed(→ *_measure_failed 기록) · ok. 점유 busy(p4.R:843~857).
- driver 종료 코드(driver.R:159~164): measured/already 0 · barrier_held 4 · data_stale 6 · busy 7 · **나머지 전부 1**(vintage_* 와 failed 를 못 가른다 — gap G1).
- round.sh p4 측정은 배리어 `wait 7200 60`(round.sh:24 · 120~125) — 틱은 그 전에 `status` 한 번으로 막는다(standing_board_run.sh:46~55 와 같은 관습).
- 포기 = 측정 실패 ≥ `RC_STANDING_MAX_FAILS`(standing.R:32 = 2L · "2번째 실패면 사람이 본다") · 측정 기록 없음 · 사유 rc_input_issues(p4.R:1051~1066).
- 생성기 작업 폴더 = 네 파일 · 빈 폴더 · 사슬 밖(p4.R:1172~1196) · 프롬프트 = `06_Registry/rx_generator.json` 판의 `step.md`(파일 md5 핀).
- 청정 레인 선례 = `02_Infrastructure/programs/rx_lane.sh`(QVEST_CLEAN_LANE=1 · QVEST_CLEAN_WDIR · Read/Glob/Grep 만 · 자동 커밋/푸시 끔 · 기본 시간 3600 = rx_lane.sh:16).
- 생성기 읽기 경계 정본 = `02_Infrastructure/hooks/arm_gen_read_guard.sh` R5(성과 경로 정규식) · R6_scope(저장소 안 · 허용 목록 밖 = block · 작업 디렉터리만 열림 · 판정 불능 = block) — 설정 `02_Infrastructure/hooks/policies/arm_gen_read_guard.json::clean_lane`.
- 무인 LLM 러너 계약 앵커(08_Tests/ops/test_credential_scope_wiring.sh:44~66 · test_run_completion_notify.sh:28~60,124~215 · test_stall_lock_alert.sh:27~75 · test_llm_lane_wiring.sh:103~110 · test_llm_single_entry.sh 전수 스캔).
- 예약 작업 = `Qvest_StandingBoard.xml`: `MultipleInstancesPolicy = IgnoreNew` · `ExecutionTimeLimit = PT24H` · 매시(PT1H) :37(백업 XML `02_Infrastructure/ops/scheduler/_task_xml_backup/Qvest_StandingBoard.xml`). ★지금 이 기기 작업 목록에 Qvest_StandingBoard 가 보이지 않는다(Get-ScheduledTask 읽기) — 등록 여부는 총괄 확인.

## 2. 사슬별 상태 기계

### 2.1 계획기 입력 · 출력

`Rscript 02_Infrastructure/programs/chain_tick.R plan <사슬 디렉터리(저장소 상대)>` → stdout 한 줄 `ACTION<TAB>k<TAB>reason_code<TAB>detail`(detail = 사람 문장 · τ_D 뒤 수치 없음). 종료 0(판독 실패도 ACTION=broken 으로 0).
읽기만 한다: `rc_p4_steps_verify` · 내부 `.rcp4_state(chain_dir, root, need_registered = FALSE)`(gap G2) · `rc_p4_vintage_default(root)` · `rxg_files_md5` · `RC_STANDING_MAX_FAILS` · 틱 장부.
`chain_tick.R list` = 모든 사슬에 plan 을 돌린 TSV(사슬 · ACTION · k · reason · last_served_at) — `--dry-run` 과 틱 순서 정하기에 쓴다.

### 2.2 판정 순서(위에서 처음 맞는 것)

| # | 조건(원장 · 상태) | ACTION | reason_code | 틱 동작 |
|---|---|---|---|---|
| 1 | 원장 없음 · 첫 사건 ≠ chain_registered | `skip` | unregistered | 조용히 넘김(등록은 감독 아래) |
| 2 | `rc_p4_steps_verify` 끊김 · `.rcp4_state` 오류(사양 R2 변경 등) | `broken` | ledger_broken / spec_changed | 알림 1회(원인 키) · 손대지 않음(격리 = 사람 p4-quarantine) |
| 3 | `chain_closed` | `skip` | closed | 조용히 |
| 4 | `chain_closing` | `close_stuck` | closing | 알림 1회 "닫기 중단 — 세션이 p4-close 재실행" · 아무것도 안 부름 |
| 5 | `<사슬>/tick_hold` 파일 있음 | `skip` | held_by_session | 로그 한 줄(세션이 손으로 돌리는 중 — §5.3) |
| 6 | 기준 칸 미측정 · base_measure_failed ≥ RC_STANDING_MAX_FAILS | `blocked` | base_failed | 알림 1회 · 재시도 안 함(k0 포기 경로 없음 — gap G6) |
| 7 | 기준 칸 미측정 | `measure_base` | — | 무거운 경로(§2.4) |
| 8 | 판 표식: 지금 `vintage.id` ≠ base_measured.vintage.id(진행 중 수리 0) | `close_wait` | vintage_changed | '닫기 대기' 1통 · 측정/판정 안 함(코어도 거부 — p4.R:893 · 1001) |
| 9 | 판 표식 진행 중 수리 > 0 | `wait` | vintage_in_progress | 조용히(다음 틱) |
| 10 | 열린 미판정 걸음 k 에 step_measured 있음 | `decide` | — | `p4-step-decide --k k` |
| 11 | 열린 미판정 걸음 k · 측정 기록 없음 · step_measure_failed(k) ≥ RC_STANDING_MAX_FAILS | `abandon` | measure_failed | `p4-step-abandon --k k --reason "$(chain_tick.R abandon-reason …)"` + 경고 1회 |
| 12 | 열린 미판정 걸음 k · 측정 기록 없음 | `measure_step` | — | 무거운 경로 |
| 13 | 미판정 없음 · (열린 걸음 수 ≥ budget.max_steps ∨ noise_streak ≥ budget.noise_k) | `close_wait` | budget_steps / budget_noise | '닫기 대기' 1통 · p4-close 안 부름 |
| 14 | 생성기 판 파일 md5(디스크) ≠ 사슬 판 generator.files | `close_wait` | generator_changed | 알림 1회(사슬은 생성기 판을 바꿀 수 없다 — 새 사슬 판 = 감독) |
| 15 | 틱 장부 gen_blocked = true | `blocked` | gen_failures | 조용히(차단 때 이미 1통) · `--reset <chain_id>` 로 풀림 |
| 16 | 그 밖(미판정 없음 · 예산 남음 · 기준 칸 측정됨) | `open` | — | 무거운 경로(생성 → 열기 → 측정 → 판정) |

13 의 예산 문턱은 사슬 판 값을 그대로 쓴다(코어 p4.R:743~746 과 같은 식) — 틱이 숫자를 갖지 않는다.

### 2.3 한 틱의 순서(전역)

```
0. 사슬 목록(glob) → 등록된 사슬 0 → 무음 exit 0(잠금 · 로그 · R 호출 없음)
1. 설정 읽기(chain_tick.R config) — enabled=false → 무음 exit 0 · 판독 불가 → 알림 1회(config_unreadable) + exit 0(fail-closed: 아무것도 안 함)
2. 자기 잠금(§5.1) → 로그 파일 연다
3. 배리어 status 한 번(standing_board_run.sh:46~55 와 같은 함수) — held/missing/오류 → "배리어 잠김 — 이번 틱 측정 · 판정 · 설계 건너뜀" 로그 한 줄 · 계획만 돌려 close_stuck/broken/close_wait 알림만 내고 exit 0
     (판정 · 설계 입력도 R 계약이 데이터 파일(벤치 등)을 읽는다 — 리프레시 중에는 읽지 않는다)
4. 가벼운 패스(모든 사슬 · 순서 = 디렉터리 이름): plan → decide | abandon | close_wait | close_stuck | broken | blocked 처리(측정 · 생성 없음). 행동 뒤 plan 재실행(사슬당 이 패스 최대 2행동: abandon 다음 decide 는 생기지 않으므로 사실상 1)
5. 무거운 패스(틱당 사슬 하나): ACTION ∈ {measure_base, measure_step, open} 인 사슬 중 last_served_at 가장 오래된 하나(동률 = 이름 순)
     a. open 이면: 데이터 신선도 `round.sh - fresh-check` rc 0 이어야 생성한다(열자마자 못 재는 걸음을 만들지 않는다 — Superfan step_stalled 오경보 방지)
        → 생성(§3) → compile → p4-step-open → plan 재실행 → measure_step 이어야 함
     b. measure_*: `round.sh <사슬> p4-base-measure` | `p4-step-measure --k k` → 원장 다시 읽기(plan)
     c. plan 이 decide 면 같은 틱에 `p4-step-decide --k k`(측정 → 판정 사이를 최소로 — step_stalled 6h 규칙과 맞물림)
     d. last_served_at 기록
6. 요약 줄 · exit(어느 사슬 행동이 오류면 1 · 아니면 0)
```

틱당 측정 = 최대 1회(`measures_per_tick` — §4). 생성 = 사슬당 최대 1회 · 무거운 패스 한 사슬뿐이므로 **틱당 최대 1회**.

### 2.4 측정 결과 처리(원장이 진실 — stdout 은 분류 · 로그용)

`round.sh` 출력에서 `[p4-step-measure] 걸음 <k> — <status>` / `[p4-base-measure] 기준 칸 — <status>`(driver.R:160 · 163)를 잡아 로그 · 알림 분류에 쓰고, 다음 행동은 **원장을 다시 읽은 plan** 으로 정한다.

| status | 원장 | 틱 |
|---|---|---|
| measured / already | step_measured / base_measured | 같은 틱에 decide(걸음) |
| failed | *_measure_failed 1줄 | 경고 없음(1회째) · 다음 틱 재측정 · 2회째면 plan 이 abandon(걸음) / blocked(기준 칸) |
| barrier_held(rc 4) · data_stale(rc 6) · busy(rc 7) · vintage_in_progress · vintage_unknown | 무기록 | 조용히 다음 틱 · 단 vintage_unknown 은 판독 결함이라 원인 키 `chain_tick:vintage_unknown` 으로 하루 1통 |
| vintage_changed | 무기록 | plan 이 close_wait(vintage_changed) |
| 그 밖 rc · 출력 없음(R 죽음) | 무기록일 수 있음 | 오류 로그 · 원인 키 `chain_tick:measure_error:<chain_id>` 하루 1통 · 다음 틱 재시도 |

### 2.5 판정 오류

`p4-step-decide` rc ≠ 0: 출력에 "이미 판정" → 무해(세션이 먼저 판정) · plan 재실행. "판 표식 ≠ 기준 칸" → plan 이 close_wait. 그 밖 → 장부 decide_errors(k) +1 · 원인 키 하루 1통 · 다음 틱 재시도. 연속 decide_errors ≥ RC_STANDING_MAX_FAILS → blocked(decide_failed) · 알림 1회 · 사람.

## 3. 다음 걸음 설계(생성기 LLM)

세션에서 Q 가 하는 절차와 같은 순서 · 같은 입력. 틱은 생성기 산출을 판정하지 않는다(채택 · 기각 = 코어 규칙).

### 3.1 절차

```
k      = 열린 걸음 수 + 1                     (plan detail 에 실린다)
WDIR   = 04_Research/programs/P4_ASSEMBLY/_lanes/<chain_id>/k<k>_<YYYYmmdd_HHMMSS>     (새 폴더 · 존재하면 안 된다)
1) WDIR 경로 검사: arm_gen_read_guard.json::clean_lane.target_regex 에 안 걸려야 한다(chain_tick.R config 가 정규식 판정 · 걸리면 gen_wdir_regex 알림 · 생성 안 함)
2) round.sh <사슬> p4-workdir --out <WDIR>      → design_input.md · investment_philosophy_charter.md · toolbox.md · parent_cell_spec.json (코어가 τ_D 검사 · fail-closed)
3) 프롬프트 조립(chain_tick.R compile 의 앞 단계 `prompt` 또는 셸): 사슬 판 generator.id → rx_generator.json 의 dir/step.md · 디스크 md5 = 사슬 판 generator.files 확인(다르면 close_wait generator_changed)
     prompt.md = 고정 머리말(코드 상수 CT_PROMPT_PREAMBLE · 판 표식 ct_preamble_v1) + step.md 바이트 그대로
     머리말 = "작업 디렉터리: <WDIR 절대 경로(슬래시)>\n이 디렉터리의 네 파일만 Read 로 읽는다. 다른 경로는 읽지 않는다.\n\n"
4) bash 02_Infrastructure/ops/chain_gen_run.sh <WDIR>     (§3.2) — 종료 0 산출 · 3 한도 · 4 인증 · 5 가드 탐침 실패 · 6 시간 초과 · 1 그 밖
5) Rscript chain_tick.R compile <사슬> <WDIR> <k>   (§3.3) — 종료 0 = WDIR/open/{hypothesis,mechanism,block,cell,parent,generator}.txt + <사슬>/cells/k<k>.json · 10 거부(사유 코드 stdout)
6) round.sh <사슬> p4-step-open --k <k> --hypothesis "$(cat open/hypothesis.txt)" --mechanism "$(cat open/mechanism.txt)" --block "$(cat open/block.txt)" \
        --cell "$(cat open/cell.txt)" --parent "$(cat open/parent.txt)" --generator "$(cat open/generator.txt)"
     rc ≠ 0 → 출력에서 분류(아래) · cells/k<k>.json 삭제(원장이 참조하지 않는 파일) · 원장 무기록
7) 성공 → 장부 consecutive_gen_failures = 0 · WDIR/tick_provenance.json(사슬 · k · 프롬프트 sha256 · 산출 sha256 · 모델 · 열기 시각)
```

### 3.2 chain_gen_run.sh — 무인 LLM 러너(계약 대상)

paper_router_run.sh 의 모양을 그대로 따른다(계약 시험 앵커가 줄 머리를 잡는다 — 함수 안에 넣지 말 것):

```bash
#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]:-$0}")/resolve_project.sh"      # BASE/PROJECT (paper_router_run.sh:23)
BASE="${BASE:-${PROJECT:-$PWD}}"; cd "$BASE" || exit 1
WDIR="${1:?usage: chain_gen_run.sh <wdir>}"; TODAY=$(date +%Y%m%d)
LOG="$BASE/.cache/scheduler_logs/chain_gen_${TODAY}.log"            # ^LOG= 가 정체 검사보다 앞(test_stall_lock_alert 의존 축)
log(){ echo "$(date -Iseconds) [chain_gen] $*" >> "$LOG"; }
log "start wdir=$WDIR"                                                 # 시작 표식
GEN_TMO=$(Rscript --vanilla 02_Infrastructure/programs/chain_tick.R config gen_timeout_sec)   # 설정값(§4) · 판독 불가 = 종료 1
# 잠금 + 정체 경보(stalled_lock 이 '다른 인스턴스' skip 보다 앞 · 홀더를 죽이지 않는다 · 문턱 QVEST_STALL_ALERT_MIN)
GLOCK="$BASE/.cache/chain_gen_run.lock"
if ! mkdir "$GLOCK" 2>/dev/null; then
  _rp=$(cat "$GLOCK/pid" 2>/dev/null)
  if [ -n "$_rp" ] && kill -0 "$_rp" 2>/dev/null; then
    _stall_min="${QVEST_STALL_ALERT_MIN:-$(( GEN_TMO / 60 ))}"          # 근거: 살아 있는 홀더가 자기 timeout 을 넘기면 timeout 이 실패한 것 = 매달림(새 숫자 없음)
    _age_min=$(( ( $(date +%s) - $(stat -c %Y "$LOG" 2>/dev/null || date +%s) ) / 60 ))
    if [ "$_age_min" -ge "$_stall_min" ]; then
      source "$(dirname "${BASH_SOURCE[0]:-$0}")/_sched_failure_classify.sh" 2>/dev/null || true
      command -v sched_alert_emit >/dev/null 2>&1 && sched_alert_emit "chain_gen" "stalled_lock" "홀더 PID=$_rp · 로그 ${_age_min}분 정체" "chain_gen:stalled_lock" "강화 사슬 생성기 실행이 멈춘 것 같습니다"
    fi
    log "다른 인스턴스 실행 중(PID=$_rp) — skip"; exit 0
  fi
  rm -rf "$GLOCK"; mkdir "$GLOCK" 2>/dev/null || { log "락 획득 실패 — skip"; exit 0; }
fi
echo "$$" > "$GLOCK/pid"; trap 'rm -rf "$GLOCK"' EXIT
[ -f "$WDIR/prompt.md" ] || { log "prompt.md 없음"; exit 1; }
CLAUDE_BIN="${CLAUDE_BIN:-$(command -v claude || echo /c/Users/99922/AppData/Roaming/npm/claude)}"   # 레인과 같은 탐색(paper_router_run.sh:350)
. "$BASE/02_Infrastructure/ops/rf_llm_env.sh"
rf_llm_resolve chain_generator "${QVEST_CG_MODEL:-}" "${QVEST_CG_EFFORT:-}"    # 설정 llm.lanes 에 없으면 llm.model/effort = opus/max
LLM_FALLBACK_MODEL=""                                                          # 폴백 미탑재(rx_lane.sh 와 같다 — 한도면 물러난다)
[ -x "$CLAUDE_BIN" ] || { log "claude CLI not found"; exit 1; }
source "$(dirname "${BASH_SOURCE[0]:-$0}")/_sched_failure_classify.sh" 2>/dev/null || true
if command -v sched_check_credentials >/dev/null 2>&1; then
  CRED_ST=$(sched_check_credentials)
  case "$CRED_ST" in ok*) : ;; *) log "인증 사전점검 실패 $CRED_ST"; exit 4 ;; esac      # 문자열 집합은 sched_check_credentials 출력에 맞춘다
fi
command -v sched_resolve_oauth_token >/dev/null 2>&1 && sched_resolve_oauth_token >/dev/null 2>&1 || true   # 열 0 (계약 C 축)
command -v sched_token_fingerprint >/dev/null 2>&1 && _tokfp="$(sched_token_fingerprint 2>/dev/null || echo none)" && log "token fp=$_tokfp"
# 가드 탐침(양성 대조 · §3.4) — 실패 = 종료 5(LLM 호출 안 함)
_guard_probe "$WDIR" || { log "가드 탐침 실패 — claude 호출 안 함"; exit 5; }     # 같은 파일 위쪽에 정의한 함수(§3.4-5)
_NOTIFY_SINCE=$(date +%s)
_run_claude(){
  QVEST_SKIP_AUTO_COMMIT=1 QVEST_SKIP_AUTO_PUSH=1 QVEST_CLEAN_LANE=1 QVEST_CLEAN_WDIR="$WDIR" \
  RF_CLAUDE_BIN="$CLAUDE_BIN" LLM_MODEL="${1:-$LLM_MODEL}" LLM_FALLBACK_MODEL="" \
    rf_llm_agent_run "$WDIR/prompt.md" "$WDIR/out.md" "${QVEST_RUN_TIMEOUT:-$GEN_TMO}" \
      --permission-mode default --allowed-tools "Read,Glob,Grep" \
      --disallowed-tools "Bash,PowerShell,Monitor,REPL,Workflow,CronCreate,RemoteTrigger,Agent,Skill,Write,Edit,NotebookEdit,WebFetch,WebSearch" \
      --add-dir "$WDIR"                                                  # rx_lane.sh:29~33 그대로
  rc=$?
}
log "claude 호출 시작 model=$LLM_MODEL"
_run_claude ""
if [ "$rc" -ne 0 ] || rf_llm_limit_hit "$WDIR/out.md"; then
  reason=$(sched_classify_failure "$rc" "$WDIR/out.md" 2>/dev/null || echo "exit_$rc")
  rf_llm_limit_hit "$WDIR/out.md" && reason="usage_limit"                # 주간 · 세션 · Fable 한도 문구 전부(RF_LLM_LIMIT_RE · rf_llm_env.sh:62)
  [ "$rc" -eq 124 ] && reason="timeout_kill"
fi
# (완주 알림 블록 — paper_router_run.sh 의 '완주할 때마다' 주석 · `_RS=… research_run_notify.R` · QVEST_RUN_NOTIFY=1 일 때만 · 기본 off 를 그대로 복제)
printf '{"rc":%s,"reason":"%s","model":"%s"}\n' "$rc" "${reason:-ok}" "$LLM_USED_MODEL" > "$WDIR/gen_result.json"
case "${reason:-ok}" in ok) exit 0 ;; usage_limit|session_limit|spend_limit|rate_limit) exit 3 ;; auth_expired) exit 4 ;; timeout_kill) exit 6 ;; *) exit 1 ;; esac
```

- 경보는 이 러너가 내지 않는다(정체 잠금만 예외) — 원인 분류 코드를 종료 코드로 돌려주고 **틱이** 원인 하나 = 하루 한 통으로 낸다(§6).
- `QVEST_RUN_TIMEOUT` 은 계약 축(env 로 상한 복원) — 기본은 설정 gen_timeout_sec. 하드코딩 `timeout 3000` 금지.
- 계약 시험 대상 목록에 올린다(§8.4).

### 3.3 compile — 산출 검사 · 칸 사양 만들기(chain_tick.R)

```
chain_tick.R compile <사슬> <WDIR> <k>
 0. gen_result.json rc = 0 확인 · out.md 존재
 1. J <- rx_parse_json(readLines(out.md))             (rx_round.R:292 · 마지막 ```json 블록 · 없음 = reject parse)
 2. 필수 키: hypothesis · mechanism · block_type · delta(이름 있는 list · 비어 있지 않음) — 문자열 1개씩 · 없음 = reject schema
 3. block_type ∈ RC_P4_BLOCK_TYPES                    (p4.R:25 · 아니면 reject block)
 4. 정보 경계: rc_input_issues(list(hypothesis, mechanism, expected_direction, falsification, philosophy_alignment), tau) — tau = 사슬 판 tau_d
       + rc_after_tau_leaks(out.md 전문, tau) 가 비어야 한다(산출 전문에 τ_D 뒤 날짜 = 오염 · 원장에 안 가는 글도 막는다) → reject contaminated
 5. rx_validate(delta, root, pool = rc_p4_base_pool(root))   (rx_round.R:308 · 엔진 파서) → ok = FALSE 면 reject invalid(errors 를 로그)
 6. 부모 칸 = WDIR/parent_cell_spec.json(코어가 사슬 머리에서 만든 사본) → 칸 = rx_compile_spec(parent, V$delta, code = "<chain_id>_k<k>",
       label = "<chain_id> 걸음 <k>", idea = hypothesis, selection_accounting = parent$selection_accounting, root = root)
       (selection_accounting 은 측정 때 코어가 다시 쓴다 — p4.R:897 · 메타 키라 서명 밖)
 7. 사전 점검(읽기 전용 · 코어가 최종): rc_p4_spec_diff(parent, cell, block_type, root, pool)$ok · 아니면 reject diff
 8. 쓰기: <사슬>/cells/k<k>.json(이미 원장 step_open 이 그 경로를 참조하면 거부 — R2 보호) · WDIR/open/*.txt(UTF-8 · 줄바꿈 없음 · cell = 저장소 상대 경로)
 9. stdout: "ok" | "reject <code> <한 줄>" · 종료 0 | 10
```

p4-step-open 거부 문구 분류(셸 · 원장 무기록): "이미 쓴 칸 사양" → duplicate · "처방 입력 금지 정보" → contaminated · "예산 소진" / "앞 걸음이 판정되지 않았다" / "이미 열렸다" → race(세션과 경합 · 실패로 세지 않음 · plan 재실행) · 그 밖 → invalid.

**연속 실패 상한**: parse · schema · block · contaminated · invalid · diff · duplicate · 생성기 종료 1/6 은 장부 `consecutive_gen_failures` +1. 한도 · 인증(종료 3 · 4) · 가드 탐침 실패(5) · race 는 세지 않는다(생성기 탓이 아니다).
상한 = `RC_STANDING_MAX_FAILS`(standing.R:32 = 2 · "2번째 실패면 사람이 본다" — 코어 포기 규칙과 같은 뜻 · 새 숫자 없음).
상한 도달 → 장부 gen_blocked = true · 알림 1회(원인 키 `chain_tick:gen_blocked:<chain_id>` · 마지막 두 사유 코드) · 그 사슬은 생성 안 함(측정 · 판정은 열린 걸음이 없으므로 없음) ·
풀기 = `bash 02_Infrastructure/ops/chain_tick.sh --reset <chain_id>`(장부 한 칸만 지운다 · 원장 무접촉) 또는 생성기 새 판 → 새 사슬 판(감독).

### 3.4 생성기 읽기 경계(무인 호출에서 어떻게 지키나)

세션의 `arm_gen_read_guard.sh` 가 무인 호출에도 그대로 걸리게 한다 — 같은 장치 · 더 붙이는 것은 양성 대조뿐.
1. **훅이 실린다**: claude 를 cwd = 저장소 루트에서 띄운다(rx_lane.sh:20 "cwd 이동 = 훅 전멸") → `.claude/settings.json` 의 PreToolUse 훅. 표식 QVEST_CLEAN_LANE=1 · QVEST_CLEAN_WDIR=WDIR → R5(성과 경로 정규식: authoritative_remeasure · stage_artifacts · essence · memory · reinforce_ledger …) + R6_scope(저장소 안 허용 목록 밖 = block · WDIR 만 열림) · 판정 불능 = block.
2. **도구 셋**: Read · Glob · Grep 만(Bash · Write · Agent · Web 금지) — 디스크 밖 경로 실행 · 위임 · 네트워크 없음.
3. **입력 자체가 보는 창만**: WDIR 네 파일은 코어가 τ_D 검사로 만든다(p4.R:1172~1196) · 설계 입력 §4b 다른 사슬 = 사유 코드만(수치 없음 · p4.R:1086~1108). 사슬 폴더(measure/*.json = 전기간 등급 · finalize.json) · 결과 원장 · 권위 등급 · 다른 사슬 원장은 WDIR 밖 + 허용 목록 밖 → R6 block. 결과 원장의 미통과 줄은 설계 입력에서 이미 빠진다(rc_outcomes_md tau_clean).
4. **자동 기억 차단**: rf_llm_agent_run 의 CLAUDE_CODE_DISABLE_AUTO_MEMORY=1(rf_llm_env.sh:142). CLAUDE.md · 규칙 자동 주입은 알려진 경계(정책 read_allow why 문구 — 목표 문턱 수치).
5. **가드 탐침(양성 대조 · LLM 전)** `_guard_probe`: 같은 환경(QVEST_CLEAN_LANE=1 · QVEST_CLEAN_WDIR=WDIR · cwd = 루트)으로 `02_Infrastructure/hooks/arm_gen_read_guard.sh` 에 PreToolUse JSON 을 stdin 으로 넣는다
   (입력 모양은 08_Tests/ops/test_rf_clean_lane.sh 의 픽스처를 따른다):
   - Read `<ROOT>/06_Registry/round_outcomes.jsonl` → `"decision":"block"` 이어야 한다
   - Read `<사슬>/measure/k0.json`(저장소 상대 · 절대 두 꼴) → block
   - Read 같은 파일의 **다른 루트 표기**(G:/OneDrive/… 와 C:/Users/99922/OneDrive/… 접합점 · 역슬래시 꼴) → block
   - Read `<WDIR>/design_input.md` → block 아님
   - `.claude/settings.json` 에 arm_gen_read_guard.sh 가 Read|Glob|Grep 매처로 등록돼 있는지(읽기 · 문자열 확인)
   하나라도 어긋나면 종료 5 → 틱: 원인 키 `chain_tick:guard_probe` 하루 1통 · 그 틱 생성 중단(세지 않음).
6. **사후 검사**: compile 4단계(산출 전문 τ_D 날짜) + 코어 step_open 의 rc_input_issues. 산출 글은 원장의 가설 · 기전만 남는다.
7. 산출 폴더 위치: WDIR 은 저장소 안(R6 가 WDIR 만 연다 · rx_round.R:6~8 의 '작업 디렉터리 = 저장소 안 · 성과 경로 정규식 밖' 관습) · %TEMP% 금지(저장소 정리 사고 카드 reference-windows-storage-sense…).

## 4. 스위치와 상한 — `06_Registry/chain_tick.json`(제안)

```json
{
  "schema": "chain_tick_v1",
  "_doc": "강화 사슬 무인 틱(02_Infrastructure/ops/chain_tick.sh) 스위치 · 상한. 읽는 곳 = 02_Infrastructure/programs/chain_tick.R config. 쓰기 = 사람. 판독 불가 = 틱이 아무것도 하지 않는다(fail-closed).",
  "enabled": true,
  "enabled_source": "decision_register CHAIN-AUTOMATION-STANDING-BOARD-AND-TICK-20261110 — 도훈 11-10 '만들고 바로 켠다' · 저녁 '사슬 무인틱 구축은 해둬'",
  "measures_per_tick": 1,
  "measures_per_tick_source": "Qvest_StandingBoard 작업 = MultipleInstancesPolicy IgnoreNew · PT24H(_task_xml_backup/Qvest_StandingBoard.xml) — 틱이 재는 동안 그 시간의 상설 판 틱이 건너뛰어진다 · 셀 워커 1개 정점 7.45 GB(기억 카드 project-main-pc-ram-benchmark-20261103 · 32 GB 에 워커 2개) — 상설 판 측정과 같은 기계를 나눈다",
  "gen_calls_per_chain_per_tick": 1,
  "gen_calls_per_chain_per_tick_source": "사슬형 — 앞 걸음 판정 전 다음 걸음을 열 수 없다(p4.R:741) · 열린 걸음은 측정(수 시간 · p4.R:830)을 거쳐야 판정된다 → 생성 호출 수는 측정 수 + 연속 실패 상한으로 위가 막힌다(하루 상한 숫자를 따로 두지 않는다)",
  "gen_max_consecutive_failures_ref": "04_Research/programs/_lib/round_core/v1/standing.R::RC_STANDING_MAX_FAILS",
  "gen_max_consecutive_failures_source": "코어 포기 규칙과 같은 뜻('2번째 실패면 사람이 본다' · standing.R:32 · p4.R:1057) — 값은 코어 상수를 읽는다(사본 없음)",
  "gen_timeout_sec": 3600,
  "gen_timeout_sec_source": "02_Infrastructure/programs/rx_lane.sh:16 처방 레인 기본 TMO(같은 청정 레인 · 같은 프롬프트 종류) · QVEST_RUN_TIMEOUT 이 덮는다",
  "stall_alert_min_source": "별도 숫자 없음 — gen_timeout_sec/60(살아 있는 홀더가 자기 timeout 을 넘겼다 = timeout 실패 = 매달림)",
  "llm_backoff": "until_next_day",
  "llm_backoff_source": "한도 사유는 자동 재시도하지 않는다(paper_router_run.sh:76 · 07-26 도훈) · 경보 단위 = 하루(sched_alert_emit 1일 1회) — 다음 날 첫 틱이 다시 시도",
  "lanes_dir": "04_Research/programs/P4_ASSEMBLY/_lanes",
  "llm_lane": "chain_generator",
  "llm_lane_source": "rf_llm_env.sh::rf_llm_resolve — reinforce_auto_config.json llm.lanes 에 없으면 llm.model/effort(opus/max)",
  "notify_close_wait": true
}
```

끄는 법(한 줄): `06_Registry/chain_tick.json` 의 `"enabled": false`(다음 틱부터 무음 0 종료). 사슬 하나만 멈추기 = `<사슬>/tick_hold` 파일 만들기. 한 번만 건너뛰기 = 환경 `QVEST_CHAIN_TICK=off`.

## 5. 경합과 멱등

### 5.1 자기 잠금
`.cache/chain_tick.lock/`(mkdir · pid) — standing_board_run.sh:57~92 와 같은 규칙: 살아 있는 보유자(kill -0) → 로그 한 줄 · 0 종료 · 죽은 pid = 인계 · 빈 pid 는 만든 지 60초 안이면 보유 중(같은 관습 · 같은 숫자).
예약 작업은 IgnoreNew 라 겹쳐 뜨지 않는다 — 잠금은 세션 수동 실행과의 겹침 방지.

### 5.2 사슬별 점유 = 코어
측정 점유(`measure/k<k>.claim` · p4.R:843~857) · 원장 추가 잠금 안 재확인(`.rcp4_append` · p4.R:611~620)이 이중 측정 · 같은 걸음 이중 열기 · 이중 판정을 막는다. 틱은 따로 잠그지 않는다. 코어가 거부하면(race 문구) 실패로 세지 않고 plan 재실행.

### 5.3 세션이 같은 사슬을 손으로 돌릴 때
- 측정 중 = 점유 busy(rc 7) → 틱 조용히 다음.
- 세션이 걸음을 설계 중(아직 안 연 상태)이면 틱이 먼저 같은 k 를 열 수 있다 → **세션 규약 추가**: 손으로 돌리는 동안 `<사슬>/tick_hold` 를 둔다(SKILL research-program §0-1 강화 사슬 절에 한 줄 — 총괄이 반영). 틱은 이 파일이 있으면 그 사슬을 건너뛴다.
- 세션이 먼저 판정 · 열기 → 틱 쪽 명령이 "이미 …" 로 거부 → 무해.

### 5.4 틱이 도중에 죽었을 때(PT24H · 전원 · 재부팅)
- 측정 도중: 점유 디렉터리의 pid 가 죽음 → 다음 측정이 인계(p4.R:850) · ps 패키지가 없으면 '확인 불가 = busy' 로 남는다(gap G8 · Superfan step_stalled 6h 경고가 잡는다).
- 생성 뒤 · 열기 전: cells/k<k>.json 은 원장이 참조하지 않는 고아 → 다음 틱이 같은 k 로 새 WDIR 에서 다시 생성하며 덮어쓴다(R2 무관). 고아 WDIR 은 남는다(출처 기록).
- 열기 뒤 · 측정 전: 다음 틱 plan = measure_step.
- 측정 뒤 · 판정 전: plan = decide.
- 장부 쓰기는 원자적(임시 파일 → mv) — 깨진 장부 = 장부 없음으로 본다(원장이 진실 · 잃는 것은 연속 실패 수 · 알림 표식뿐).

### 5.5 사용 한도('weekly limit' 류)
chain_gen_run 종료 3 → 틱이 `.cache/chain_tick/llm_backoff.json {"until":"<다음 날 00:00 로컬>","reason":"usage_limit"}` 쓰고 sched_alert_emit(원인 키 `llm_limit:usage_limit` · 하루 1통) · 이후 그날 틱은 생성 단계만 건너뛴다(측정 · 판정은 LLM 이 아니라 계속). 사슬 실패로 세지 않는다.
가드 탐침 실패(5) · 인증(4)도 같은 '물러남'(원인 키 `chain_tick:guard_probe` · `chain_tick:auth`) — 백오프 없이 다음 틱 재시도 · 알림은 하루 1통.

## 6. 보고

| 사건 | 통로 | 빈도 |
|---|---|---|
| 걸음 판정(채택 · 기각) · 걸음 열기 · 측정 | 원장 + 틱 로그 | **푸시 없음**(qvest-telegram §0 평상 무음 · 리서치 1단위 = 사슬 · 보고는 닫기 때 세션이 prep_send) |
| 닫기 대기(budget_steps · budget_noise · vintage_changed · generator_changed) | `chain_tick.R notify <사슬> close_wait <reason>` → `prep_send(program = "P4_ASSEMBLY", target = chain_id, status = list(stage = "닫기 대기", position = "걸음 n(채택 a · 기각 r · 포기 p)", previous = 마지막 판정), verdict_line = "닫기 대기 — <사유 문장>", next_step = "세션: 철학 P2 · 판단 T2 뒤 round.sh <사슬> p4-close --regrade-write", push = TRUE)` · 계층 표제 [1계층·P4_ASSEMBLY] | 사슬당 1회(장부 close_wait_notified_at · 같은 사유 재발송 없음) |
| 닫기 중단(chain_closing) · 원장 끊김 · 기준 칸 실패 2회 · 생성 차단 · 판정 차단 | `sched_alert_emit "chain_tick" <reason> <detail> "<원인 키>" "<요약>"`(alert_dedup 공유 저장소) | 원인 하나 = 하루 1통 + 장부 표식으로 같은 사슬 같은 사유는 1회 |
| 측정 오류 · vintage_unknown · 가드 탐침 · 인증 · 한도 · 설정 판독 불가 | sched_alert_emit | 원인 하나 = 하루 1통 |
| 측정 1회째 실패 · 배리어 · 낡음 · 점유 · 진행 중 수리 | 로그만 | — |

- 발송 결과는 수동 실행(QVEST_UNATTENDED≠1)이면 마커만(sched_alert_should_send) · `--dry-run` 은 발송 0. prep_send 는 `push = (QVEST_UNATTENDED=1 ∧ !dry-run)` · 시험 = QVEST_TG_DRY_RUN=1.
- 원인 키 이름 = `chain_tick:<reason>[:<chain_id>]` · 한도만 `llm_limit:<reason>`(다른 레인과 같은 날 같은 원인이면 묶이게 — 다른 레인 키와 맞추는 것은 구현 때 alert_dedup.py 의 기존 키를 확인).
- **Superfan reinforce_chain 과의 관계**: step_stalled(열린 걸음 6h 미판정 · warn · max_age_h 근거 = claim_stale_hours 6)는 틱이 '열고 같은 틱에 재고 곧바로 판정'하므로 정상 경로에서는 측정 시간만큼만 열려 있다. 틱은 **측정할 수 없는 때(배리어 · 데이터 낡음 · 측정 예산 소진) 새 걸음을 열지 않는다**(§2.3 5a) — 생성 때문에 생기는 오경보를 만들지 않는다. 측정 자체가 6h 를 넘으면 경고가 맞는 경고다(충실구현 claim_live_long 과 같은 성격). ledger_chain(원장 끊김 fail)과 틱 broken 알림은 같은 원인 → 원인 키를 `chain_tick:ledger_broken:<chain_id>` 로 두고, Superfan 쪽 키와 합치는 것은 등록부 수정이라 **제안만**: superfan_components.json reinforce_chain `schedule` 문구를 "세션 또는 무인 틱(chain_tick.sh · Qvest_StandingBoard 매시 37분)" 으로.

## 7. 셸 의사 코드 — chain_tick.sh

```bash
#!/usr/bin/env bash
set -u
ROOT=${RC_ROOT_POSIX:-/c/Users/99922/OneDrive/Quant_Module_Moltbot}      # round.sh 와 같은 뜻(시험 임시 루트)
SH=${BASH:-bash}
RS=${CT_RS:-$ROOT/04_Research/programs/_lib/round_core/round.sh}
HELPER=${CT_HELPER:-$ROOT/02_Infrastructure/programs/chain_tick.R}
GEN=${CT_GEN:-$ROOT/02_Infrastructure/ops/chain_gen_run.sh}
RB=${RB_SH:-$ROOT/02_Infrastructure/ops/refresh_barrier.sh}
RSCRIPT=${CT_RSCRIPT:-Rscript}
STATE=${CT_STATE_DIR:-$ROOT/.cache/chain_tick}
ALLOWED=" p4-base-measure p4-step-measure p4-step-decide p4-step-abandon p4-workdir p4-step-open p4-status fresh-check "   # ★허용 목록 — 이 밖 = 거부
DRY=0; RESET=""
인자: --dry-run | --reset <chain_id> | 그 밖 = usage exit 2
[ "${QVEST_CHAIN_TICK:-on}" = off ] && exit 0
# 0. 사슬 목록(셸 glob · 등록 여부는 원장 첫 줄 문자열 'chain_registered')
CHAINS=(); for sp in "$ROOT"/04_Research/programs/P4_ASSEMBLY/*/chain_spec.json; do d=${sp%/chain_spec.json}; case "$(basename "$d")" in _*) continue;; esac
  [ -f "$d/chain_steps.jsonl" ] && head -n 1 "$d/chain_steps.jsonl" | grep -q '"event":"chain_registered"' && CHAINS+=("${d#"$ROOT"/}"); done
[ ${#CHAINS[@]} -eq 0 ] && exit 0                                                     # 무음
# 1. 설정
EN=$("$RSCRIPT" "$HELPER" config enabled 2>/dev/null) || { alert config_unreadable …; exit 0; }
[ "$EN" = "true" ] || exit 0
[ -n "$RESET" ] && { "$RSCRIPT" "$HELPER" reset "$RESET"; exit $?; }
# --dry-run: 배리어 상태 · 잠금 보유자 · chain_tick.R list 출력만 · 로그/잠금/round.sh 무호출 · exit 0
# 2. 잠금(§5.1) · 3. 로그 열기 · 4. 배리어(§2.3-3)
rs(){ case "$ALLOWED" in *" $2 "*) ;; *) log "[거부] 허용 목록 밖 명령: $2"; alert forbidden_stage; return 99;; esac; "$SH" "$RS" "$@" 2>&1 | tee -a "$LOG"; return "${PIPESTATUS[0]}"; }
plan(){ "$RSCRIPT" "$HELPER" plan "$1"; }            # → ACTION k reason detail
# 5. 가벼운 패스 → 6. 무거운 패스(§2.3) — 생성은 gen_step() = §3.1 1)~7)
#    backoff: "$RSCRIPT" "$HELPER" backoff-active → yes 면 open 건너뜀(측정할 열린 걸음 있는 사슬만 무거운 후보)
```

- 모든 R 호출은 `Rscript` 그대로(운영) — 시험은 `R_ENVIRON_USER=<빈 파일>` 과 `CLAUDE_PROJECT_DIR=<임시 루트>`(chain_tick.R 은 CLAUDE_PROJECT_DIR → QM_ROOT 순서로 루트 해석 · r-portability.md).
- 셸은 판단 규칙을 갖지 않는다(계획기 한 곳) — 셸이 쓰는 것은 허용 목록 · 순서 · 상한 집행뿐.
- 시험 주입 환경변수: `RC_ROOT_POSIX` · `RC_ROOT_WIN`(round.sh 에도 그대로 전달) · `CT_RS` · `CT_HELPER` · `CT_GEN` · `RB_SH` · `CT_STATE_DIR` · `CT_CFG`(설정 경로 · chain_tick.R 이 읽음) · `CT_LANES_DIR` · `CT_NOW`(백오프 날짜) · `CT_RSCRIPT` · chain_gen_run 쪽 `CLAUDE_BIN`(가짜 claude) · `QVEST_TG_DRY_RUN=1` · `QVEST_NO_ALERT=1` · `RC_RXG_PATH`(생성기 등록부 · 코어 기존).

## 8. 시험 계획

공통: 한 번에 하나 · 임시 루트(저장소 밖 tempdir · 단정) · `R_ENVIRON_USER=<빈 파일>` · 운영 등록부 · 원장 · .cache md5 전후 동일 단정 · 발송 0 단정(QVEST_TG_DRY_RUN=1 + tg 함정) · 마지막 줄 `{"test":…,"pass":N,"fail":N,"total":N}`.

### 8.1 test_scn_chain_tick.sh — 셸 오케스트레이션(가짜 코어)

가짜 round.sh(CT_RS) = 호출 인자를 `calls.log` 에 한 줄씩 적고, 시나리오 표(파일)대로 출력 · 종료 코드를 낸다. 가짜 계획기(CT_HELPER = 작은 R 또는 셸 래퍼) = 시나리오 상태 파일에서 ACTION 을 읽는다. 가짜 생성기(CT_GEN) = 시나리오가 정한 종료 코드 · out.md.

| id | 시나리오 | 단정 |
|---|---|---|
| T1 | 사슬 폴더 0 · 등록 안 된 사슬만 | 출력 0바이트 · 종료 0 · 잠금 · 로그 · calls.log 없음 |
| T2 | enabled=false · QVEST_CHAIN_TICK=off | 무음 0 · 호출 0 |
| T3 | 설정 판독 불가 | 호출 0 · 알림 마커 1(config_unreadable) |
| T4 | 기준 칸 미측정 | calls = p4-base-measure 1 → (재계획) |
| T5 | 열린 걸음 측정됨 | p4-step-decide 1 · 측정 0 |
| T6 | open 경로 끝까지 | 순서 = fresh-check → p4-workdir → (생성기 1) → p4-step-open → p4-step-measure → p4-step-decide |
| T7 | 배리어 held(RB_SH 가짜 rc 10) | 측정 · 판정 · workdir · 생성 0 · 로그 한 줄 |
| T8 | 데이터 낡음(fresh-check rc 6) · open 필요 | 생성 0 · 열기 0 |
| T9 | 생성 산출 쓰레기 / 오염 / 중복(compile reject · step-open 거부 문구) | 원장 명령 p4-step-open 은 중복 때만 1회 · 장부 실패 +1 · 두 번째 틱에서 gen_blocked · 알림 1 · 세 번째 틱 생성 0 |
| T10 | race 문구("이미 열렸다") | 실패로 세지 않음 |
| T11 | 닫기 대기(budget) 두 틱 | 알림(prep_send 드라이런) 1회만 · p4-close 호출 0 |
| T12 | 전 시나리오 합 | calls.log 에 p4-register · p4-close · p4-quarantine · p4-generator-review · outcomes-quarantine · register · close · rxg 0건 |
| T13 | 계획기가 CLOSE 같은 모르는 ACTION · 허용 밖 단계 요청 | rs() 거부 · 알림 · 호출 0 |
| T14 | 이중 실행(살아 있는 잠금 보유자) | 두 번째 0 종료 · 호출 0 |
| T15 | 죽은 잠금(pid 없음 · 60초 넘음 / 죽은 pid) | 인계 · 정상 진행 |
| T16 | 생성기 종료 3(한도) | 백오프 파일 · 알림 1 · 같은 날 다음 틱 생성 0 · 측정은 진행 · CT_NOW 다음 날 → 생성 재개 · 실패 수 불변 |
| T17 | 생성기 종료 5(가드 탐침) · 4(인증) | 생성 중단 · 실패 수 불변 · 알림 하루 1 |
| T18 | 측정 출력 failed 1회 → 2회 | 2회째 다음 틱 = p4-step-abandon(사유 문장에 숫자 · 날짜 없음) |
| T19 | tick_hold | 그 사슬 호출 0 · 다른 사슬은 진행 |
| T20 | 두 사슬 모두 measure 필요 | 틱당 측정 1 · last_served_at 순환(두 틱에 걸쳐 둘 다) |
| T21 | --dry-run | round.sh · 생성기 호출 0 · 잠금 · 로그 0 · 계획 표 출력 |
| T22 | --reset | 장부 gen_blocked 해제 · 원장 무접촉 |

돌연변이(소스 텍스트 치환 · 치환 성사 단정 · 사본 단독 실행): M1 허용 목록 검사 줄 제거 → T13 빨강 · M2 배리어 분기 제거 → T7 빨강 · M3 enabled 검사 제거 → T2 빨강 · M4 백오프 검사 제거 → T16 빨강 · M5 실패 상한 비교 제거 → T9 빨강 · M6 close_wait 1회 표식 제거 → T11 빨강 · M7 fresh-check 앞세움 제거 → T8 빨강 · M8 틱당 측정 상한 제거 → T20 빨강.

### 8.2 test_scn_chain_tick_core.R — 계획기 · 컴파일러 ↔ 실제 코어

test_scn_l1_chain_e2e.R 의 사슬 만들기를 따른다(임시 루트 SB · 임시 생성기 등록부 RC_RXG_PATH · 판단 원장 · 결과 원장 · 합성 산출 · 가짜 러너 · FRESH · VINT 주입 · `rc_p4_chain_new` → `rc_p4_chain_register`).
틱의 한 걸음을 R 안에서 흉내 내는 실행기 `exec(stage, args)` = 코어 함수를 주입 러너로 직접 부른다(round.sh CLI 대신 — gap G5) · 계획기 · compile 은 실제 chain_tick.R 함수.

| id | 단정 |
|---|---|
| C1 | 등록 직후 plan = measure_base → base_measure 뒤 plan = open(k = 1) |
| C2 | 가짜 생성기 산출(정상 JSON · weighting 1블록) → compile ok · 칸 사양이 부모와 한 블록만 다름 · step_open 성공 · plan = measure_step |
| C3 | 측정(가짜 러너) → plan = decide → decide → plan = open(k = 2) · 채택이면 부모 = 1 |
| C4 | 측정 실패 2회 → plan = abandon · abandon-reason 이 rc_input_issues 통과 · 코어 포기 성공 |
| C5 | 예산(max_steps) 소진 → plan = close_wait budget_steps · noise_k 연속 → budget_noise |
| C6 | 판 표식 바뀜(VINT 교체) → close_wait vintage_changed · 진행 중 수리 → wait |
| C7 | chain_closing 줄 → close_stuck · chain_closed → skip · 원장 변조 → broken · 사양 변경(R2) → broken |
| C8 | compile 거부: json 없음(parse) · 키 빠짐(schema) · 어휘 밖 블록 · 가설에 '2023년 3월'(contaminated) · 산출 전문에만 τ_D 뒤 날짜(contaminated) · rx_validate 실패(invalid) · 두 블록 변경(diff) · 같은 칸(→ step_open duplicate) — 각각 원장 줄 수 불변 |
| C9 | compile 이 이미 열린 k 의 cells 파일을 덮지 않는다(R2) |
| C10 | 생성기 파일 md5 변경 → close_wait generator_changed |
| C11 | 계획기 · compile 실행 전후 원장 md5 동일(읽기 전용 단정) · 운영 파일 md5 동일 |

돌연변이: 계획기 예산 조건 제거 → C5 빨강(open 이 나오고 코어가 거부) · compile 의 산출 전문 τ_D 검사 제거 → C8 해당 칸 빨강 · rx_validate 호출 제거 → C8 invalid 칸 빨강 · 판 표식 비교 제거 → C6 빨강.

### 8.3 test_scn_chain_gen_guard.sh — 생성기 읽기 경계(양성 대조)

- 실제 `arm_gen_read_guard.sh` 에 §3.4-5 의 탐침 JSON 을 넣어 block / pass 단정(성과 파일 · 사슬 measure · finalize.json · authoritative_remeasure · 결과 원장 · 다른 사슬 원장 · 루트 표기 3꼴 · WDIR 파일 pass · Glob 패턴 · Grep 뿌리).
- chain_gen_run.sh 를 가짜 claude(CLAUDE_BIN · 받은 환경을 파일로 적는 스크립트)로 돌려: QVEST_CLEAN_LANE=1 · QVEST_CLEAN_WDIR=WDIR · CLAUDE_CODE_DISABLE_AUTO_MEMORY=1 · QVEST_SKIP_AUTO_COMMIT=1 · allowed-tools = Read,Glob,Grep · Bash/Write/Agent 금지 목록 · cwd = 루트 단정 · 비밀 값은 '있음/없음'만.
- 가짜 claude 가 한도 문구("You've hit your weekly limit")를 내면 종료 3 · gen_result.json reason usage_limit · 시간 초과(QVEST_RUN_TIMEOUT=1 · 가짜 sleep) → 종료 6.
- 돌연변이: 사본에서 QVEST_CLEAN_LANE=1 제거 → 환경 단정 빨강 · 탐침 호출 제거 → '탐침 없이 claude 호출' 단정 빨강 · allowed-tools 에 Bash 추가 → 빨강.

### 8.4 무인 LLM 계약 시험 5종에 올리기

대상 = `chain_gen_run`(LLM 을 실제로 부르는 러너 · chain_tick.sh 는 LLM 을 부르지 않는다):
- `08_Tests/ops/test_credential_scope_wiring.sh:35` `RUNNERS="paper_router_run chain_gen_run"`
- `08_Tests/ops/test_run_completion_notify.sh:28` `RUNNERS="paper_router_run.sh chain_gen_run.sh"`(알림 블록 = paper_router 의 '완주할 때마다' 주석 · `$_RS` · QVEST_RUN_NOTIFY 기본 off 복제 · `_NOTIFY_SINCE=` 를 `_run_claude ""` 앞에)
- `08_Tests/ops/test_stall_lock_alert.sh:27` `RUNNERS="paper_router_run.sh chain_gen_run.sh"`
- `08_Tests/ops/test_llm_lane_wiring.sh:103 · 108` 목록에 `chain_gen_run.sh`(C7 문법 · C8 rf_llm_agent_run 경유)
- `08_Tests/ops/test_llm_single_entry.sh` = git 추적 파일 전수 스캔 — 커밋되면 자동 편입(bare `claude` 0 · rf_llm_agent_run 경유). chain_tick.sh · chain_tick.R 에 claude 문자열 호출 없음.
러너 · 프로필 파일(run_all_hooks.sh · suite_tiers.tsv)은 고치지 않는다 — 새 시나리오는 08_Tests/scenarios/ 자동 편입.

## 9. core_gaps(코어를 고치지 않고 우회)

- G1 driver.R:159~164 — 측정 상태 vintage_unknown · vintage_in_progress · vintage_changed · failed 가 모두 종료 1. 우회: 원장 재판독(plan)이 진실 · stdout `[p4-*-measure] … — <status>` 는 분류용.
- G2 읽기 전용 상태 접근자가 공개 함수로 없다(p4-status 는 사람 문장). 우회: chain_tick.R 이 내부 `.rcp4_state(…, need_registered = FALSE)` 를 읽기만 · 서명 변화는 C1~C7 이 잡는다.
- G3 생성기 산출(delta) → 칸 사양 컴파일 명령이 코어에 없다(세션이 손으로). 우회: rx_validate + rx_compile_spec + rc_p4_spec_diff 사전 점검 · 최종 = step_open.
- G4 round.sh p4 측정은 배리어 최대 2시간 대기(wait 7200). 우회: 틱이 status 한 번 먼저(열림일 때만 부른다 · 사이 경합은 대기로 끝난다).
- G5 round.sh · driver.R 에 러너 · 배리어 · 지문 · 판 표식 주입 이음매가 없다(CLI 시험 = 저장소 전체 사본 필요). 우회: 셸 시험은 가짜 round.sh · 코어 연동 시험은 R 함수 주입.
- G6 기준 칸(k = 0) 포기 경로 없음. 우회: 2회 실패 = blocked + 사람.
- G7 Superfan 등록부 reinforce_chain `schedule` = "세션이 부른다" — 수정 제안만(§6).
- G8 측정 점유 생존 판정이 ps 패키지 의존 — 없으면 죽은 점유가 영구 busy. 우회 없음(관찰: step_stalled 경고) · 구현 전 `Rscript -e 'requireNamespace("ps")'` 확인을 사전 점검에.
- G9 p4-step-open 의 `--probe-ref` 를 생성기 산출이 내지 않는다(step.md 산출 형식에 없음) — 틱은 넘기지 않는다(탐침 이어받기 = 세션).
- G10 round.sh 기본 ROOT 가 `/c/Users/99922/...` 고정(RC_ROOT_POSIX 로만 바뀜) — 틱도 같은 기본값 · 같은 환경변수를 그대로 넘긴다.

## 10. 위험

- R1 IgnoreNew: 틱이 측정 · 생성(최대 1h)으로 오래 돌면 그동안 상설 판 매시 틱이 건너뛰어진다. 완화 = 틱당 측정 1 · 생성 1. 근본 = 별도 예약 작업(Qvest_ChainTick) — 등록은 총괄 · 도훈(아래 명령 제안).
- R2 생성기 경계는 훅(R5/R6)에 기댄다 — 훅이 안 실리면 경계가 없다. 완화 = LLM 전 가드 탐침(양성 대조) · cwd 고정 · settings.json 등록 문자열 확인. 접합점(G: · C:) 루트 표기 우회 가능성은 탐침이 매번 잰다.
- R3 사전학습 서사 지식(τ_D 뒤 사건)은 막지 못한다(pit.md 정보 경계 주석) — 산출 글 τ_D 날짜 검사 + 시험 창 판정은 크기 짝 대조와 함께(등급 쪽).
- R4 세션과의 경합 — tick_hold 규약이 SKILL 에 실려야 실효.
- R5 컴파일(rx_compile_spec)이 고정 축을 활성 epoch 로 다시 쓴다 — 부모와 다르면 spec_diff 가 거부(fail-closed · 생성 실패로 세어 2회면 차단 → 사람).
- R6 측정 1회가 수 시간 · PT24H 안에서 생성 1h + 측정 n시간 — 측정이 24h 를 넘으면 작업이 죽는다(점유 인계로 다음 틱 재측정 · 실패로 기록 안 될 수 있음).
- R7 OneDrive 폴더 읽기 전용 속성 — WDIR · cells 삭제 실패 가능(기억 카드 reference-onedrive-synced-dirs-readonly…) — 삭제는 chmod 뒤 · 실패해도 판정 영향 없음(원장 미참조).

## 11. 구현 · 배포 순서(운영 파일 교체 규칙)

1. 스크래치에서 chain_tick.R · chain_tick.sh · chain_gen_run.sh · chain_tick.json · 시나리오 3개 작성 → 스크래치 사본으로 시험 통과(한 번에 하나).
2. 계약 시험 4종의 RUNNERS 줄 추가본도 스크래치에서 통과 확인.
3. 교체는 맨 끝 한 번(cp 사본 원본.tmp && mv -f 원본.tmp 원본) · 매시 15~20분 · 35~40분 · 20:00 전후 · 00:03 이후 창 피함. ★chain_tick.sh 가 생기는 순간 :37 틱이 부른다 — **chain_tick.sh 를 마지막에** 옮긴다(앞의 R · 설정 · 러너가 먼저 자리 잡게).
4. 지금 등록된 사슬 0 → 첫 실 틱은 무음 0 종료여야 한다(로그 없음 확인).

총괄이 실행할 명령(제안 · 이 설계 단계는 실행하지 않음):
- SKILL research-program §0-1 강화 사슬 절에 한 줄: "손으로 걸음을 돌리는 동안 `<사슬>/tick_hold` 를 둔다 — 무인 틱(chain_tick.sh)이 그 사슬을 건너뛴다."
- superfan_components.json reinforce_chain.schedule 문구 갱신(§6).
- (선택) 별도 예약 작업 Qvest_ChainTick — 도훈 승인 뒤.
