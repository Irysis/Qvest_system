# 부팅 WARN 4건 진단·수리 — 2026-08-02

**세션**: architect (온디맨드) · 도훈 지시 "밤샘 자율 진행, 판단 대기로 멈추지 말 것"
**규범 로드**: `02_Infrastructure/docs/rules/harness.md` · `r-portability.md` (금칙 4종)
**전제 실측**: 2026-08-02 01:5x 부팅 배너 + 02:0x~02:5x 직접 재측정

---

## 총괄

| # | 항목 | 판정 | 결과 |
|---|---|---|---|
| 1 | 부팅 보고 6 vs 실행 2 불일치 | **수리** | 스냅샷 vintage 라벨링 신설 — 과거 트리 판정을 현재로 단언하지 않음 |
| 2 | hooks FAIL 2건 | **수리** | 신규 위반 1 + 래칫 역행 1. 둘 다 근본 수리(무력화 아님) |
| 3 | v8 readiness FAIL 1건 | **수리(2에 종속)** | fail 1 = `hook_dryrun` — 2의 동일 실패를 읽던 것 |
| 4 | 예약작업 5종 전멸 | **부분 확정 + 수리** | 4건 = 5일 절전 후 catch-up 일괄 발화(단일 사건). 1건 = 실제 신규 실패, 근본 수리 |

**부수 발견 2건(고가치)**: ① `DailyRefresh` 일일 통보 스텝의 R 구문 오류 — 실패 요약이 텔레그램에 영영 미도달 ② 좌초 worktree에 **★★believed-done 수리가 main에 없음**.

**공통 기전**: 4건 중 3건이 같은 계열이다 — **소비자가 "언제/어느 트리의 사실인지" 모르는 캐시를 현재 상태로 읽는다.** 이 저장소가 반복 수리해온 "검사기가 잘못된 것을 잼"(존재→유효성, mtime→최신성)의 이번 변주는 **"과거 스냅샷→현재 판정"**이다.

---

## [1] 6 vs 2 불일치 — 부팅이 79분 낡은 스냅샷을 현재로 단언

### 증상
- 부팅 배너: `[suite-totals] ★FAIL>0 감지 — hooks_fail fail=6`
- 직접 실행(01:59): `FINAL: 338 pass / 2 fail / 340 total`

### 근본원인
`02_Infrastructure/ops/bootstrap.sh:877` 이 `suite_totals_watch.sh --check` 를 호출한다. `--check` 는 **러너를 돌리지 않는다** — `.cache/suite_totals_latest.json` 을 읽어 기준선과 비교만 한다(설계대로: 부팅은 빨라야 함).

그 스냅샷의 실측 vintage:
```
collected_at: 2026-08-02T00:40:58   hooks: 338  hooks_fail: 6
```
`daily_refresh.sh:593` → `suite_totals_watch.sh --collect` 가 00:03 시작한 DailyRefresh 안에서 00:40 에 수집한 값이다. 부팅은 01:5x. **그 사이 8 커밋**(00:47·01:01·01:02·01:04·01:51·01:52·01:56·01:57)이 실패 4건을 수리하고 케이스 2건을 추가했다 → 실제는 `340 total / 2 fail`.

★ 즉 **6도 2도 둘 다 참이다. 서로 다른 트리에 대해서.** 결함은 수치가 아니라 **주장**이다 — 부팅이 과거 트리의 사실을 현재 판정으로 단언했다.

기존 신선도 가드는 `age_h >= 48` 뿐이었다(`suite_totals_watch.sh` check). 79분은 통과한다. **시간 임계가 잘못된 축이다** — 이 저장소는 auto-commit으로 시간당 여러 번 움직인다. 판정의 유효범위를 정하는 것은 경과 시간이 아니라 **트리 정체성**이다.

### 수리
`02_Infrastructure/ops/suite_totals_watch.sh`
- `collect()`: 수집 시점 `git rev-parse --short HEAD` 를 `tree_head` 로 기록
- `check()`: 현재 HEAD 와 대조 → 3상태 라벨(`현재 트리와 동일` / `수집 시점 X 기준 · 이후 N 커밋 — 현재 트리 미검증` / `구식 스냅샷 — 일치 미확인`) + 수집 나이 **항상** 표시
- `promote()`: null 거부 검사에서 `tree_head` 제외(총계가 아님)

★ **경보는 절대 약화하지 않았다.** 트리가 움직였다고 조용히 통과시키면 그게 검사 사망이다. FAIL>0 이면 여전히 exit 1 — 바뀐 것은 "무엇에 대한 사실인지"의 라벨뿐이다.

### 위반 주입 테스트 (차단 실효)
| 주입 | 출력 |
|---|---|
| tree_head 없음(구식) | `[수집 1.7h 전 · 수집 시점 트리 미기록(구식 스냅샷) — 현재 트리와의 일치 미확인]` |
| tree_head = 현재 HEAD | `[수집 1.7h 전 · 현재 트리와 동일]` |
| tree_head = HEAD~6 | `[수집 1.7h 전 · 수집 시점 45593f9d 기준 · 현재 d40b6614 · 이후 6 커밋 — 현재 트리 미검증]` |

세 상태 모두 판별, 세 경우 모두 FAIL 경보 유지(무음 통과 0).

---

## [2] hooks FAIL 2건 — 정체와 근본원인

두 건 다 `test_r_portability.R` 안에서 났다. 이 검사기는 **baseline 래칫**이라 두 방향으로 운다.

### 2-a. `novel_violation` — 신규 파일이 legacy 잔재를 들여옴
`02_Infrastructure/portfolio/run_layer5_rerun_extended.R:78` (해당 파일은 00:47 신규 생성)
```r
BASE_DIR <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"))
```
금칙 ③. Windows R 은 `/mnt/c/...` 를 현재 드라이브 기준 `C:/mnt/c/...` 로 해석하고, 그 자리에 빈 잔재 디렉터리가 있으면 **조용히 안착**한다(2026-06-10 이전 구 프로젝트 위치의 stale 폴백).

**수리**: marker 검증 resolver로 교체(존재검사 → 정체성검사). 해석 실패 시 `stop()` — 조용한 오작동보다 명시적 실패.
검증: `Rscript -e 'invisible(parse(...))'` → `PARSE_OK`.

★ 래칫이 의도대로 작동한 사례다 — 신규 파일이 baseline 밖 위반을 들여온 즉시 검거.

### 2-b. `baseline_not_shrunk` — 수리분이 원장에 잔존(래칫 역행)
2건이 실제로는 없어졌는데 baseline 에 남아 있었다:

| 항목 | 사유 | 확인 |
|---|---|---|
| `02_Infrastructure/monitoring/mark_faithtrend_daily.R:4` | 파일 삭제 | `b5d33b92` "faith 레인 소비처 재배선 + 전용 스크립트 철거" |
| `02_Infrastructure/contracts/essence_score.R:4` | resolver 역전 수리 | `:392-393` CLAUDE_PROJECT_DIR → QM_ROOT 순서로 정정됨 |

★ **파일이 사라진 것과 수리된 것을 구분해서 확인했다** — 확인 없이 `--write-baseline` 하면 "삭제로 인한 소멸"을 "수리"로 오기록한다.

**수리**: `--write-baseline` (계약이 정한 축소 경로). 원장 **52 → 50**.

### 재측정
```
test_r_portability: 7 pass / 0 fail   (566 files 스캔 / baseline 50건 수용)
```
위반 주입 5종(금칙 4 합성 위반 + 정본 오검출 통제) 전부 PASS — 검사기가 살아 있음을 동반 실증.

---

## [3] v8 readiness FAIL 1건

`bash 02_Infrastructure/tools/qvest_v8_ready --strict` 실측:
```
Summary: 14 pass / 1 fail / 1 warn / 0 skip
  ❌ hook_dryrun   [FAIL] 338 pass / 2 fail / suite 19 — 실패 2건 (rc=2)
  ⚠️ soak_record   [WARN] recent_3d=0 critical=0 (요구: recent>=2 + critical=0)
```

**fail 1건의 정체 = `hook_dryrun`** — 독립 결함이 아니라 [2]의 그 2건을 `.cache/test_results/hook_dryrun_results.json` 에서 읽던 것. [2] 수리로 해소.

**warn = `soak_record`** — 3일 내 readiness 2회+ / critical 0 이 요구인데 `recent_3d=0`. **human 확인 의무 항목이라 수리 대상이 아니다**(보고만). 해소 조건 = 3일 안에 게이트를 2회 이상 통과시키는 것 = 시간 경과 + 도훈 확인.

부팅 배너(`--no-write`, `pass=12 fail=1 warn=1 skip=2`)와 `--strict`(14/1/1/0)의 차이는 write 필요 체크 2건의 skip 여부 — 모드 차이지 결함 아님.

---

## [4] 예약작업 — 4건은 단일 사건, 1건은 진짜 신규 실패

### 4-a. 공통 사인 규명 (Windows 실측)

| 증거 | 값 |
|---|---|
| 절전 진입 → 복귀 | `Power-Troubleshooter` Id 1: Sleep `2026-07-27T14:47:51Z` → Wake `2026-08-01T06:43:22Z` (**약 5일**) |
| 시스템 시각 점프 | `Kernel-General` Id 1: Time Delta **402,916,527 ms** (4.66일) |
| 마지막 부팅 | `2026-07-17T19:15:48` — **재부팅 아님**(절전/복귀) |
| 작업 시작 시각 | MorningReboot 15:46:26 · MonthlyDistill/MorningBrief/WeeklyCleaner 15:49:19 → **복귀 후 3~6분** |
| 종료 코드 | `0xC000013A` (STATUS_CONTROL_C_EXIT) 4건 동일 |
| 배터리 정책 | 해당 4건 전부 `StopIfGoingOnBatteries=False` |
| 실행시간 한도 | PT2H/PT3H — 최초 가능 kill 창(16:42 Modern Standby 진입)까지 약 53분 ≪ 한도 |
| LogonType | 8작업 전부 `Interactive` (= 세션 종료 시 함께 죽는 수명) |
| TaskScheduler/Operational 로그 | **Enabled=False** |

**확정된 것**: 4건은 개별 작업 결함이 아니라 **5일 절전에서 복귀한 직후 밀린 트리거가 일괄 발화(`StartWhenAvailable=True` catch-up)했다가 함께 죽은 하나의 사건**이다. 배터리 정책 **아님**(소거), 실행시간 한도 **아님**(소거).

**미확정**: 그 burst를 종료시킨 **주체의 이름**. `Microsoft-Windows-TaskScheduler/Operational` 로그가 **꺼져 있어** 사후 규명이 구조적으로 불가하다 — 2026-07-26 메모리의 "사망 주체 미확정"이 남은 이유가 이것이다. 남은 후보는 세션 종료(LogonType=Interactive) 또는 Modern Standby 재진입. **추정으로 단정하지 않는다.**
→ 로그 활성화는 **시스템 설정 변경**이므로 이번 세션에서 하지 않았다. 도훈 판단 사항(활성화하면 다음 발생 시 종료 주체가 이름으로 남는다).
→ 5일 공백 자체는 머신 절전 기인 = **정상 정지**(2026-08-01 도훈 피드백 "무인 공백은 한도부터 확인" 정합). 조치 없음.

### 4-b. 보고 결함 — 렌더러가 둘이라 판정도 둘

같은 원장(`06_Registry/scheduler_task_health.json`)을 두 코드가 **각자 판정**했다:

| 소비자 | 판정 |
|---|---|
| 권위 스크립트 `scheduler_task_health.sh` | `실패 1 · 정지 1` + "동시 다발 종료 … 하나의 사건으로 계수" |
| 부팅 `bootstrap.sh` §4i | `★실패` **5개 개별 나열** |

부팅이 클러스터링을 **모른 채 원시 rc 로 재판정**하고 있었다. 클러스터 판정이 `.sh` 의 stdout 에만 살고 **원장에 저장되지 않아서**, 세션을 넘겨 살아남는 유일한 소비자(부팅)는 접근할 수 없었다.

추가로 부팅이 읽은 스냅샷은 `2026-08-01T20:00:29` 측정분이었다(26h 임계 미만이라 무경고) — [1]과 **같은 계열**이다.

### 4-c. 분류기 결함 — 경과 시간으로 원인을 라벨링

`scheduler_task_health.sh:88` (구판)
```python
hint = ("부팅/가동 중 동시 강제종료 의심 — 실제 실패" if hrs < 6
        else "머신 정지 시각의 사후 흔적일 수 있음")
```
**같은 사건이 6시간이 지나면 다른 라벨이 된다.** 경과 시간은 원인에 대해 아무 정보도 없다 — "잘못된 것을 재는 검사기" 계열의 재발.

### 4-d. 수리

- `scheduler_task_health.ps1` (ASCII-only 계약 준수, 검증 완료) — `schema_version` 2로: `last_resume`(복귀 시각) · `last_boot` · `tasksched_oplog_enabled` + 작업별 `logon_type` · `stop_on_battery` · `start_when_available`. **기록만으로 가설을 소거**할 수 있게 한 것(매번 라이브 조회 불요).
- `scheduler_task_health.sh` — 분류를 **증거 기반**으로: 복귀 후 15분 내 동시 시작 = `catchup_burst_after_resume`. 아니면 `unclassified`(단정 금지). 기록으로 반증되는 가설은 `ruled_out` 에 적시. 오퍼레이셔널 로그가 꺼져 있으면 `terminator_identifiable: false` 로 **규명 불가를 명시**. 판정을 **원장에 되쓴다**.
- `bootstrap.sh` §4i — 재판정 금지, 원장의 `cotermination` 을 **소비**. 접힌 작업은 개별 계수에서 제외.

### 위반 주입 테스트 (차단 실효)
| 입력 | 부팅 출력 |
|---|---|
| 현행 원장(cotermination 존재) | `★실패 DailyRefresh=exit_1 · 동시종료 4건 08-01 15:46 [catchup_burst_after_resume]` |
| cotermination 제거(구 스키마) | `★실패 DailyRefresh=exit_1·MonthlyDistill=hard_…·MorningBrief=hard_…·MorningReboot=hard_…·WeeklyCleaner=hard_…` |

후자가 **원래 부팅 배너를 정확히 재현**한다 → 진단 확증 + 구 스키마 하위호환(크래시 없이 폴백) 동시 실증.

### 재측정
```
[02:24:42] 예약작업 8개 · 실패 1 · 정체 0 · 정지 1
  ※동시 다발 종료 08-01 15:46 — 작업 4개…·173초 창. 시스템 재개(08-01 15:43) 후 3분에 동시 시작
    — 밀린 트리거 일괄 발화(catch-up) 서명 … · 전 작업 LogonType=Interactive = 세션 종료 시 함께 죽는 수명
    [소거: 배터리 정책(StopIfGoingOnBatteries=false)]
  ★실패: Qvest_DailyRefresh(exit_1)
```

---

## [부수 1] ★DailyRefresh exit_1 — 일일 통보가 자기 자신 때문에 침묵

부팅이 보고하지 못한(20:00 스냅샷을 읽었으므로) **현재 유일한 진짜 작업 실패**.

### 증상
`.cache/scheduler_logs/daily_refresh.log`
```
Error: unexpected 'else' in "          else"
Execution halted
[run_r] ★r18 FAILED rc=1
=== Daily Refresh v2 Done — ★실패 1스텝: r18(rc=1) @ Sun Aug  2 00:40:58 2026 ===
```

### 근본원인
`02_Infrastructure/data/daily_refresh.sh:535-536`
```r
.hdr <- if (identical(.fails, "없음")) "[Daily Refresh v2 완료]"
        else sprintf("[Daily Refresh v2 ★부분실패 — %s]", .fails)
```
R 은 **최상위**에서 줄바꿈을 만나면 `if` 문을 닫는다 → 다음 줄 `else` 가 고아가 되어 파싱 단계에서 사망(중괄호 안이면 정상).

★ **하필 이 블록이 일일 성공/실패를 텔레그램으로 알리는 스텝이다.** 2026-07-26 DR-01 수리가 "실패를 보이게 하려고" 넣은 실패 요약(`DR_FAILED_SO_FAR`)이, 바로 그 요약을 넣는 문법 때문에 **발송 자체를 죽였다**. rc=1 은 남았지만 내용은 어디에도 도달하지 않았다.

### 수리
중괄호 형태로 교체 + 재발 사유 주석.

### 위반 주입 테스트
원 형태를 임시 파일에 재주입 → `CAUGHT: ...:3:9: unexpected 'else'`. 수리본 → `PARSE_OK r18_block`.

### 실행 실측 (end-to-end, 읽기전용 · `QVEST_REFRESH_TG=0` 발송 차단)
수리 전에는 파싱 단계에서 죽어 **한 분기도 실행되지 못했다**. 수리 후 양 분기 정상 산출:
```
DR_FAILED_SO_FAR="없음"      → [Daily Refresh v2 완료]
DR_FAILED_SO_FAR="r18(rc=1)" → [Daily Refresh v2 ★부분실패 — r18(rc=1)]
공통: RAWDATA 2026-07-31까지 (2763 tickers) / 총 14,045,583 rows
```
★ 부분실패 분기가 실제로 실패 목록을 본문에 싣는 것까지 확인 — DR-01 수리의 원래 의도가 이제 도달한다.

### 구조 수리 — 이 부류를 다시 놓치지 않게
**저장소에 내장 R 블록을 실행 전에 검사하는 장치가 0건이었다.** 구문 오류는 그 스텝이 실제로 도는 새벽에, 로그 안에서만 드러난다.

신설: `08_Tests/data/test_daily_refresh_r_blocks.R` (SUITES 등재)
- `run_r '<R>'` 블록 23개 전량 추출 → `parse()` (실행 안 함, 부작용 0)
- **독립 교차계수**: 추출 블록 수 ≠ 독립 opener 수 이면 FAIL — 추출기가 조용히 0건을 집어 "전부 통과"로 위장하는 것을 차단
- 셸 인용부호 스플라이스(`setwd("'"$BASE"'")` 6곳) 복원 — 치환 범위를 그 관용구로 한정하고, 경계 파수꾼으로 `injection_splice_with_dangling_else`(스플라이스 + 고아 else 는 여전히 검거) 배치
- 위반 주입 4종(고아 else·중괄호 불균형·문자열 미종료·스플라이스+고아 else) + 음성 통제 2종(정상 블록·스플라이스 복원)
- **실파일 사본 주입**: 실제 `daily_refresh.sh` 를 복사해 첫 블록에 고아 else 를 심고 추출→복원→파싱 전 경로가 잡는지 확인 → `parse 실패 1건 검거`

결과: `31 pass / 0 fail`.

> ★설계 중 자기 교정 1회: 최초 구현은 스플라이스 관용구를 몰라 **정상 블록 6건을 FAIL로 오검출**했다. "오탐 제거와 검사 사망은 겉보기가 같다"는 이유로 오탐을 그냥 지우지 않고, 치환 경계를 지키는 주입 케이스를 함께 넣었다.

---

## [부수 2] 좌초 worktree — believed-done ★★수리가 main에 없음

`bash 02_Infrastructure/ops/stranded_repairs_audit.sh` 실측(02:26):
```
worktree 4 · 미커밋 4 · 미병합 0 · 3일+ 방치 3 | 유실 6 · 부분 0 · 충돌 1 · prune후보 0
★ 유실 대상: serene-liskov-598614(6건·0일)
```

### 부팅 WARN 이 가리킨 3건 = 전부 무해
| worktree | 방치 | triage |
|---|---|---|
| `frosty-torvalds-5e24f0` [angry-bhabha-b50a41] | 7일 · 20파일 | **전량 `merged_upstream`** (missing_in_main=0) |
| `great-burnell-e15c26` | 8일 · 1파일 | `merged_upstream` |
| `suspicious-diffie-76e162` | 8일 · 1파일 | `merged_upstream` |

작업이 이미 main 에 있는 stale 사본이다. **조치 불요.** 등재된 충돌(`measurement_basis_audit.R` 2 worktree)도 양쪽 다 `merged_upstream` 이라 실질 무효.

### ★실제 좌초 = `serene-liskov-598614` [claude/clever-cerf-033672]
방치 **0일**(HEAD 08-01 16:00) 이라 3일 임계에 안 걸렸고, 부팅 WARN 은 "3일+ 방치" 3건만 강조했다 — **연차(age)는 "작업이 위험한가"의 잘못된 축**이다([1][4c]와 같은 계열).

| 파일 | triage | main 실측 |
|---|---|---|
| `02_Infrastructure/hooks/resolve_project.sh` (+70) | `mostly_lost` (67 missing) | `grep -c marker` = **0** |
| `02_Infrastructure/ops/resolve_project.sh` (+45) | `mostly_lost` (42 missing) | `grep -c marker` = **0** |
| `08_Tests/hooks/test_resolve_project_marker.sh` (신규) | `lost` | **파일 부재** |
| `08_Tests/hooks/run_all_hooks.sh` (+7) | `lost` | SUITES 등재 **0** |
| `02_Infrastructure/docs/rules/r-portability.md` (+25) | `lost` | 25행 미반영 |
| `qepm/observability/events.jsonl` (+145) | `mostly_lost` | (데이터, 코드 아님) |

메모리 `project-resolve-project-marker-gate-20260801`(★★, "검사기 11/11에 돌연변이 축")는 이 수리를 **완료로 기록**하고 있으나 **main 에 없다.** 브랜치 커밋도 0(`git log main..claude/clever-cerf-033672` 공백) — 즉 worktree 안에서 **미커밋** 상태다. date32 writer·lcode harvester 전례와 동일 패턴.

**자동 병합·prune 하지 않았다**(지시 준수). 판단 근거만 위 표에 제시.

⚠ **병합 시 주의**: 본 세션이 main 의 `08_Tests/hooks/run_all_hooks.sh` 를 수정했다(신규 suite 등재). 그 worktree도 같은 파일에 +7 을 갖고 있어 **병합점이 겹친다**. 감사기의 충돌 탐지는 worktree↔worktree 만 보고 worktree↔main-작업트리는 보지 않는다.

---

## [부수 3] bear_date_audit — 신규 아님

`0 PASS / 4 FAIL` 재현. 실패 축 = **Lehman GFC · Euro Crisis · COVID · Stagflation 2022** = 기지 4개 bear date 그대로. 신규 날짜/축 **없음**. `STATUS_BUGGY_ERA.md`(2026-05-20, `02_target_builder.R` backward label bug) 문서화 상태와 정합. **조치 불요**(지시대로 신규 여부만 확인).

---

## [부수 4] hook-fire 관측창 — 조치 불요

`판정 보류 — 원장 관측창 147h < 요구 168h`. 설계대로의 정상 동작.

---

## 동시성 주의 (본 세션 실측)

작업 중 **다른 세션이 main 작업트리를 동시 편집**했다(`essence_score.R` 02:17 수정, `08_Tests/contract_regression/test_ast_sidecar.R` 02:20 신규). 후자는 최종 배터리에서 **신규 위반으로 검거**됐다:

`08_Tests/contract_regression/test_ast_sidecar.R:33` — 금칙 ② 최상위 `on.exit()`. 작성자도 주석으로 미발화 가능성을 인지하고 "말미 직접 호출 병행"으로 완화했으나, **중도 error/quit 경로에서는 복원이 안 되어** 환경변수 오염이 후속 테스트로 샌다(계약이 문서화한 3경로 미발화). 정본 `reg.finalizer(globalenv(), ..., onexit = TRUE)` 로 교체 — 해당 테스트 자체는 `24 pass / 0 fail` 유지.

★ 이 사실 자체가 [1] 수리의 필요성을 다시 입증한다: 트리가 시간당 여러 번 움직이는 환경에서 "언제 잰 값인가" 없는 판정은 곧 낡는다.

---

## 재측정 최종 수치 (전부 실행 실측)

| 스위트 | 수리 전 | 수리 후 |
|---|---|---|
| `run_all_hooks.sh` | 338 pass / **2 fail** / 340 | **403 pass / 0 fail / 403** · `STATUS: ✅ ALL PASS` |
| `test_r_portability` | 5 / **2** / 7 | **7 / 0 / 7** (원장 52→50) |
| `test_daily_refresh_r_blocks` (신설) | — | **31 / 0 / 31** |
| `test_ast_sidecar` (동시 세션 신설분 수리) | — | **24 / 0 / 24** |
| `qvest_v8_ready --strict` | Overall **FAIL** · 14 pass / **1 fail** / 1 warn | Overall **WARN** · **15 pass / 0 fail / 1 warn / 0 skip** |
| `hook_dryrun` 체크 | `[FAIL] 338 pass / 2 fail / suite 19 (rc=2)` | `[PASS] 403 pass / 0 fail / suite 22 (rc=0)` |
| 예약작업 | `★실패` 5종 개별 나열 | `실패 1 · 정지 1`(사건 1건으로 접힘) → DailyRefresh 수리 |

**총계 증분 회계** (340 → 403, +63): 본 세션 신설 `test_daily_refresh_r_blocks` **+31** · 병렬 Q-Lead 신설 `test_ast_spec_gate.sh`(+8) + `test_ast_sidecar.R`(+24) **+32**. 감소분 0.

### 래칫 기준선 재승격 (SUITES 편입 시 의무 — harness.md)
`06_Registry/suite_totals_baseline.json` **hooks 296 → 403** (regime 5 · contract_regression 54 · continuity 31 불변, fail 축 전부 0).
승격 후 `--check` → `OK … [수집 0.0h 전 · 현재 트리와 동일]`.

★ 승격 전 기준선이 296이었다 = 실측(403)보다 **107 낮았다**. 그 상태에서는 스위트가 100건 넘게 조용히 사라져도 래칫이 울지 않는다. 재승격이 의무인 이유가 이것이다.

### 래칫 차단 실효 (승격 후 위반 주입 — 종료코드는 파이프 없이 측정)
| 주입 | 출력 | rc |
|---|---|---|
| 기준 상태 | `OK hooks=403 …` | 0 |
| 총계 감소 403→362 | `★총계 감소 — … hooks 403 → 362 (-41)` | **1** |
| FAIL>0(총계 불변) | `★FAIL>0 — 총계 불변이어도 회귀: hooks_fail fail=3` | **1** |
| 수집 실패(null) | `⚠ 수집 실패(null): hooks — 수치 없음은 '정상'이 아니다` | 0(경고) |
| 원복 | `OK hooks=403 …` | 0 |

> ⚠ 자기 교정 1건: 최초 이 표를 `... | tail -3; RC=$?` 로 재려다 **전부 rc=0** 을 얻었다 — 파이프 뒤 `$?` 는 `tail` 의 코드다(계약이 금지한 패턴). 파이프 없이 재측정해 정정. *검사기를 재는 내 계측이 먼저 틀린 사례.*

---

## 남은 미해결

| 항목 | 왜 남았나 |
|---|---|
| `soak_record` WARN | **human 확인 의무** — 요구 `recent>=2 + critical=0`, 현재 `recent_3d=1 critical=1`. critical 1건 = 오늘 02:0x 의 FAIL 판정 기록(이번에 수리한 그 실패). 게이트를 3일 내 2회 이상 통과시키면 자연 해소 — 코드 수리 대상 아님 |
| `--check` 의 null 종료코드 | 수집 실패(null)는 경고만 내고 **rc=0** 이다(기존 설계). 오늘 02:32 수집이 실제로 `hooks=null` 을 냈다(병렬 세션의 SUITES 편집과 동시 실행된 일시 현상 — 02:40 재수집 시 403 정상). 문구는 "수치 없음은 정상이 아니다"인데 종료코드는 통과 — 불일치. 부팅이 경고를 표시하므로 침묵은 아니나, 종료코드 의미 변경은 부팅 probe 처리에 영향이 있어 **단독 변경하지 않음**(도훈 판단) |
| 예약작업 종료 **주체** 이름 | `TaskScheduler/Operational` 로그가 꺼져 있어 사후 규명 구조적 불가. 활성화 = **시스템 설정 변경** → 도훈 판단 |
| `serene-liskov-598614` 6파일 병합 | **자동 병합 금지** 지시. `run_all_hooks.sh` 병합점 겹침 주의 |
| 3개 stale worktree prune | `prune_candidates: 0`(미커밋 잔존) + 자동 prune 금지 |
| bear_date_audit 4 FAIL | 기지 buggy-era. 별건 |
| r-portability baseline 50건 | 기수용 부채(신규 위반만 FAIL). 축소는 별건 |
