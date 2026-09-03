# v10.1 하네스 정리 — 도훈 결정 대기 항목 (2026-09-03)

> 아래는 **파괴적이거나 외부(OS 예약작업·worktree)에 영향을 주는 조치**라 실행하지 않고 남겼다.
> 코드·문서 정합은 전부 적용 완료(CHANGELOG_constitution.md v10.1 참조). 롤백 = git.

---

## 1. Windows 예약작업 6건

실측(2026-09-03 08:20). `runlevel=Highest` 인 항목만 **관리자 PowerShell**이 필요하고 나머지는 일반 권한이다.

| # | 작업 | 지금 상태 | 문제 | 추천 조치 |
|---|---|---|---|---|
| A | `Qvest_AuditWatch` | Ready · **Highest** · 배터리 거부(0x800710E0) 반복 | venv 삭제 포렌식용인데 **소비자가 0**이다 — boot_currency C11 은 v9(08-23)에 은퇴해 `BCC_RUN_C11=1` 일 때만 돌고, 그 기본값은 off. 매일 '신규 실패 1' 을 만들던 두 원인 중 하나 | **비활성화**(v9 재설계안이 이미 '비활성 예정' 으로 적어둔 것의 집행). 감시를 살리려면 대신 배터리 설정을 고치고 `BCC_RUN_C11=1` 을 되살려야 한다 |
| B | `Qvest_ReinforceAutoLoop` | Running · 배터리 구동 시 tick 거부 | v10 라이브 핵심 러너인데 다른 Qvest_* 와 달리 `DisallowStartIfOnBatteries=True` — 노트북이 배터리일 때 무인 강화가 **조용히** 멈춘다(State 는 Ready 로 보인다) | 배터리 허용으로 설정 보정. 전력 소모가 늘어나므로 도훈 선택 |
| C | `Qvest_RAMP_AutoLoop` | **Disabled** · 1,776회 miss 누적 | RAMP 모드는 v9.21 진입점 퇴임. 등록만 남아 있다 | 등록 해제. bat·ramp 코드·L-code 73건은 사료로 존치 |
| D | `DART_Priority_Backfill_2015_2024` | Ready · **다음 실행 없음** | 2026-07-06 1회성 트리거가 끝나 다시 발화하지 않는 죽은 등록. 대상 cmd 도 `stage_artifacts/` 안이라 코드 정본이 아니다 | 등록 해제 |
| E | `DART_Insider_Backfill` | Ready · 3시간 반복 · 배터리 거부 반복 | 백필은 **258/258 월 완료**(매 실행 calls=0 no-op)인데 반복 트리거가 하루 최대 8회 실패 rc 를 남긴다 | 일 1회로 축소 + 배터리 허용, 또는 필요할 때만 수동 실행하고 비활성화 |
| F | `noLayer4_Monthly_PaperTracking` | Ready · 매월 1일 09:00 · rc 0 | BOOK_0001 월간 트래킹. v10 정본은 `/book`·`/book-rebalance` 온디맨드라 **이중화**다. ★단 이 스크립트는 알림기가 아니라 m4/paper-NAV **연장 파이프라인**이므로 끄면 데이터가 멈춘다 | 유지 권장(데이터 파이프라인). 알림 중복만 줄이려면 텔레그램 발송 스위치만 끌 것 — 아래 3번 |

실행 예 (일반 권한):
```bash
powershell -NoProfile -Command "Unregister-ScheduledTask -TaskName Qvest_RAMP_AutoLoop -Confirm:\$false"
```
```bash
powershell -NoProfile -Command "\$s = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Hours 2) -MultipleInstances IgnoreNew; Set-ScheduledTask -TaskName Qvest_ReinforceAutoLoop -Settings \$s"
```
A(AuditWatch)는 `RunLevel=Highest` 라 **관리자 PowerShell**에서만 된다:
```
Disable-ScheduledTask -TaskName Qvest_AuditWatch
```

---

## 2. worktree 24개 처분

좌초 감사기는 이제 v10 태그(`pre-v10-2layer`) 이전에 멎은 worktree 를 `legacy_pre_v10` 으로 분리해 **경보에서 뺀다**(유실 0 · 레거시 24 · 발송 0). 즉 소음은 이미 멎었고, 남은 것은 실제 정리 여부다.

- **미커밋 0 · 미병합 커밋만 있는 것** → `git worktree remove` 후 브랜치 보존이 안전(작업은 브랜치에 남는다).
- **미커밋 보유** — `priceless-elion`(167) · `heuristic-wozniak`(17) · `lucid-hofstadter`(13, sleepy-driscoll 포함) · `angry-almeida`(47 커밋) → 제거 시 미커밋분 소실. 내용을 한 번 보고 결정할 것.
- **유지** — v10 이후 tip 3개(`bold-mayer` 09-01 · `wizardly-rosalind` 08-30 · `amazing-morse`) + `zen-pare`(detached, main HEAD): 활동 중일 수 있다.

목록·건수 정본 = `06_Registry/stranded_repairs.json` (`legacy_pre_v10` · `lost_legacy` 필드).

---

## 3. 그 밖의 결정

| 항목 | 내용 | 선택지 |
|---|---|---|
| `design_envelope_gate.sh` | v10.1 에 신설됐으나 **등록·검사·문서 0** — 존재하지만 발화하지 않는 계기. 등록하면 훅 12→13 이 되어 CLAUDE.md 선언 줄·boot_lean 예산·boot_currency C6 를 함께 올려야 한다. 또 이 훅은 Write/Edit 도구 경유 쓰기만 잡아 **무인 강화 레인(R 직접 기록)은 커버하지 못한다** | ①검사 신설 후 등록(예산 13) ②설계 envelope 강제를 훅이 아니라 `rf_cell_engine` 계약에 두고 이 파일은 ★RETIRED |
| 강화 분모 20 vs 25 | 원장 `max_attempts` 는 25, 일부 문서는 20. 텔레그램 표제는 이미 25 로 갱신됨 | 정본을 25 로 확정하고 남은 문서를 맞출지 |
| noLayer4 일별 MTM 텔레그램 | `mark_nolayer4_daily.R` 이 `agent="Monitoring"`(v10 퇴역 에이전트)로 매일 발송 시도(14일 실발송 1건). ★데이터 적재(일별 NAV)는 같은 스크립트가 하므로 **호출 자체를 끄면 안 된다** | ①표제만 `[BOOK] 트래킹 — …`·agent `Book` 으로 승계 ②`NOLAYER4_DAILY_TG=0` 로 발송만 차단 |
| `08_Tests` 퇴역 스위트 이동 | v9 개념(governor dir resolution · cert · v8 readiness · mode_queue 레인 · Stop 훅 continuity 등) 약 20 스위트가 여전히 매일 돈다. 이동 시 디렉터리명은 반드시 `_archive_v10*`(편입 검사기 제외 패턴이 `_archive*` 라서) | 이번 판에서는 **총계 기준선 재승격까지만** 하고 이동은 다음 판으로 분리하는 것을 권장(감소와 수리를 한 델타에 섞지 않기 위해) |

---

# 실행 기록 (2026-09-03 · 도훈 "모두 추천 조치로 실행해")

## 1. 예약작업 6건

작업 정의는 실행 전 `02_Infrastructure/ops/scheduler/_task_xml_backup/*.xml` 로 전량 내보냈다(되돌리기용).

| # | 작업 | 조치 | 결과 |
|---|---|---|---|
| A | `Qvest_AuditWatch` | 비활성화 | **미완 — 관리자 권한 필요**(`RunLevel=Highest`, Access is denied) |
| B | `Qvest_ReinforceAutoLoop` | 배터리 허용으로 설정 보정 | 완료 (`disallowBatt=False stopBatt=False startWhenAvail=True triggers=1`) |
| C | `Qvest_RAMP_AutoLoop` | 등록 해제 | 완료 |
| D | `DART_Priority_Backfill_2015_2024` | 등록 해제 | 완료 |
| E | `DART_Insider_Backfill` | 일 1회 09:30 + 배터리 허용 | 완료 (`triggers=1 next=2026-09-03 09:30`) |
| F | `noLayer4_Monthly_PaperTracking` | 유지(데이터 파이프라인) | 표제만 BOOK 계층으로 승계 — 아래 3번 |

A 는 도훈이 **관리자 PowerShell**에서 직접 실행해야 한다:

```
Disable-ScheduledTask -TaskName Qvest_AuditWatch
```

## 2. worktree 처분 — 30 → 4 (+main)

순서: ①미커밋 보유 8개를 **각자 브랜치에 보존 커밋**(215 파일) → ②레거시 24개 제거 → ③잔해 정리.

- 보존 커밋 8건 — `priceless-elion`(167) `heuristic-wozniak`(17) `sleepy-driscoll`(13) `lucid-hofstadter`(12) `amazing-grothendieck`(2) `keen-mirzakhani`(2) `ecstatic-elgamal`(1) `qvest-cleaner-execution`(1). **브랜치는 24개 전부 존치** — 이력은 하나도 안 지워졌다.
- 삭제 전 전수 대조: 디스크에만 있고(브랜치 미추적) main 에도 없는 파일 = **20건**. 그중 19건은 lock/`__pycache__`/세션캐시였고, 연구 산출물 5건(`stage_artifacts/WT-D20260813_006/` 의 rds·csv)은 **main 으로 회수한 뒤** 삭제했다.
- 유지 4 — `amazing-morse`(미커밋 3) · `bold-mayer`(0) · `wizardly-rosalind`(15) · `zen-pare`(detached).
- 좌초 감사 재실행: worktree 27→**3** · 유실 0 · 레거시 0.

★사고 1건과 그 복구: 잔해 정리 루프의 보호 목록이 줄바꿈 구분인데 대조는 공백 구분 `case` 패턴이라 **유지 대상 4개의 등록까지 삭제**됐다(작업 파일·브랜치는 무사). `gitdir`/`commondir`/`HEAD` 수기 재구성 + `read-tree HEAD` 로 복원했고, 복원 후 미커밋 건수가 정리 전 감사값(3/0/15/0)과 **정확히 일치**하는 것으로 무손실을 확인했다. 재발 방지는 기억 카드에 적었다.

## 3. 그 밖의 결정 — 전부 집행

| 항목 | 집행 |
|---|---|
| noLayer4 텔레그램 | ①안 채택. `mark_nolayer4_daily.R`·`monitor_nolayer4_paper.R` 이 `agent="Book"` + `[BOOK] 트래킹 — {book_id} …` 표제로 발송. book_id 는 `book_registry.json` 조회(리터럴 금지). **데이터 적재는 무변경** |
| `design_envelope_gate.sh` | ②안 채택 — ★RETIRED(본문 사료 존치·실행 시 무해 통과). 그 훅이 지려던 long_only 축은 `test_rf_holdings_axis.R` (5)절로 이관(엔진 배출 Leg 직접 판정 + 숏 주입 양성 대조 + 격자 선언 일치). 11/0 |
| 강화 분모 | 25 로 확정. `CHANGELOG_constitution.md` 의 "≤20회" 정정 + reinforce SKILL 에 "실측 인용의 `n/20` 은 상한이 아니라 당시 시도 번호" 명시 |
| `08_Tests` 퇴역 이동 | 예정대로 다음 판으로 분리(이번 판 미실시) |

## 4. 그 과정에서 드러난 것 — 함께 수리

| 발견 | 수리 |
|---|---|
| **`08_Tests/reinforcement/` 18스위트가 배터리에 한 번도 실린 적 없음**(`suite_enrollment_check` E2 미편입 18/218) — v10 실제 리서치 레인을 지키는 검사가 전부 침묵 | SUITES 편입. 편입 커버리지 **218/218**, `suite_enrollment` 1/1 → **2/0** |
| `axiom_context_inject.sh` 감축 사다리 소진 — v10 고정부 증가로 마지막 단이 ~2,045자가 돼 하드 절단이 **dead 조회 명령을 잘라먹음**(훅 자기 주석이 예견한 실패) | 사다리 2단 연장 + 절단이 dead 줄을 보존. `test_inject_usage_ranking` 11/2 → **13/0** |
| `test_reinforce_ledger.R` 이 상한 20 을 하드코딩(9-01 격자 25 재편 미추종) | 원장 `max_attempts` 파생. 10/1 → **12/0** |
| 낡은 판 표기 | 배터리 배너 v6.4→v10 · suite 키 `qvest_test_battery` · `harness_health` v8.1→v10.1 · 라우터 헤더(dispatch 폐지 사연 명시) |

## 5. 배터리 — 실패 27건의 정체

격리 재실행 결과, **knowledge_index 계열 14건은 실패가 아니라 동시 실행 경합 인공물**이었다(강화 워커 5개가 배터리 도중 등록부를 쓴다). 격리에서 `knowledge_index_stale` 20/0 · `knowledge_index_consumer_heal` 31/0.

남은 진짜 실패 10건 중 **이번 정리에서 비롯된 것은 0건**이다.

| 스위트 | 실패 | 귀속 |
|---|---|---|
| `r_portability` | 4 | **다른 세션의 미커밋 파일** — `reinforce_auto_run.R`·`test_rf_terminal_retry.R` 최상위 `on.exit`, `test_replication_harness.R` regmatches×TRE |
| `emission_identity_axes` | 2 | 팩터 DB — C15 죽은 배출 축 |
| `emission_guard` | 1 | 팩터 DB — 기준선 항목 4종이 registry 에 없음 |
| `label_eligibility_gate` | 1 | 국면 라벨 — 사건 정의(<0% vs <-10%) 조건부 |
| `test_inject_usage_ranking` | 2 | ★수리 완료(위 4번) |

**총계 기준선은 승격하지 않았다.** 기준선은 "정상 상태"의 정의인데 지금 fail>0 이라 승격하면 위 실패들이 정상으로 굳는다. 스위트 18건 편입으로 총계가 올라간 것은 사실이므로, **위 실패를 정리한 뒤** `suite_totals_watch.sh --collect && --baseline` 으로 승격할 것을 권한다.

## 6. 배터리 — 두 판

| | 09:41 (편입 직후) | 10:06 (계약 줄 보강 후) |
|---|---|---|
| FINAL | 3339 pass / 26 fail / 7 skipped / **18 unmeasured** / 3365 | 3624 pass / 26 fail / 8 skipped / **0 unmeasured** / 3650 |
| 집계 스위트 | 196 | **214** |
| suite 키 | `qvest_test_battery` | `qvest_test_battery` |

오늘 수리한 3건은 실패 목록에서 사라졌다 — `reinforce_ledger` · `suite_enrollment_guard` · `test_inject_usage_ranking`.

★**편입이 새 침묵을 드러냈다**: 09:41 판에서 신규 18건이 전부 UNMEASURED 였다. 한국어 `합계:` 만 찍고
러너가 파싱하는 `{"test":..,"pass":N,"fail":N,"total":N}` 계약 줄이 없었기 때문이다(오늘 계약 9건에 적용한 것과 같은 수리).
배터리 **밖**에 있는 동안은 이 결함이 침묵인지 통과인지 구분조차 되지 않았다.
18건 전부에 계약 줄을 넣은 뒤 **강화 레인 285 단정이 처음으로 집계에 들어왔다(fail 0)**.
`rf_block_lcode` 는 원장에 완료 블록이 없어 단정 0건인데, `pass=0/fail=0` 은 '안 돌았다' 와 구분되지 않으므로 `skipped=1` 로 보고하게 고쳤다.

### 남은 실패 26건 — 이번 정리 귀속 0

| 스위트 | 실패 | 귀속 |
|---|---|---|
| `knowledge_index_consumer_heal` | 8 | 강화 워커 동시 실행 경합 — **격리에서 31/0** |
| `knowledge_index_stale` | 6 | 같음 — **격리에서 20/0** |
| `r_portability` | 4 | 다른 세션의 미커밋 파일(`reinforce_auto_run.R`·`test_rf_terminal_retry.R` 최상위 `on.exit`, `test_replication_harness.R` regmatches×TRE) |
| `emission_identity_axes` | 2 | 팩터 DB — C15 죽은 배출 축 |
| `emission_guard` | 1 | 팩터 DB — 기준선 4종이 registry 부재 |
| `label_eligibility_gate` | 1 | 국면 라벨 — 사건 정의(<0% vs <-10%) 조건부 |

**총계 기준선은 승격하지 않았다.** fail>0 상태를 정상으로 굳히게 된다.
위 실패를 정리한 뒤 `suite_totals_watch.sh --collect && --baseline` 으로 승격할 것.
(★`--collect` 는 배터리를 **다시 돌린다** — 타임아웃을 짧게 걸면 옛 값이 남는다. 실측 09:27 스냅샷이 그 경우였다.)
