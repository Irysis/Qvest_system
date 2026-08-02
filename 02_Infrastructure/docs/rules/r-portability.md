# R 측 Windows 이식성 계약 (확장 rule)

**발효**: 2026-07-25 (도훈 지시 "승격해"). **위반 = AX-002 동급**(계측이 죽은 채 GREEN을 보고하면 프로세스 우회와 같다).
**적용**: 이 리포지토리의 모든 `.R` — 외부 프로세스 호출 / 정리(cleanup) 로직 / 경로·루트 해석을 작성·수정할 때.
**로드 시점**: R에서 `system2`·`system`을 쓰거나, cleanup을 등록하거나, 프로젝트 루트를 해석할 때 (on-demand).
**자매 규칙**: `.claude/rules/python-policy.md`(Python 측 — R/Python 1급 + PIT·계약 동일적용). 본 문서는 그 R 측 호출 규약 공백을 메운다.

---

## 왜 계약인가 (근거)

2026-07-25 `08_Tests/integration` 2종이 **assertion 0건으로 exit 1** 하는 상태가 적발됐다("hollow pass"가 아니라 계측 사망). 수리 과정에서 결함이 **서로를 가리고 있었다** — ①을 걷어내야 ②가, ②를 걷어내야 fixture 결손이 드러났다. 개별 파일 수리로는 재발이 멎지 않는 이유가 이것이다.

**공통 기전 = 존재 검사로 정체성 검사를 대신한 것.** `dir.exists()`가 참이라고 그게 *그* 프로젝트 루트인 건 아니다. 같은 기전이 07-25 텔레그램 `.tg_lock_root()`(빈 디렉토리를 루트로 신뢰 → 직렬화 무력화), L-code substring 오매칭, `strategy_id` substring 모호에서도 반복됐다.

---

## 금칙 5종 (위반 시 수리 의무)

### ① `system2(..., env = ...)` 금지
Windows에서 `env=` 문자열은 환경변수로 설정되지 않고 **명령줄 첫 인자로 앞에 붙는다**. 실측:

```
system2(py, args=c("-c", code), env="X=1")
→ '"python.exe" X=1 -c "..."'   → python이 X=1을 스크립트 경로로 오인, rc 2
```

★위험한 건 실패 그 자체가 아니라 **위장**이다: `stdout=TRUE, stderr=TRUE`면 그 에러문이 `out`에 담겨 호출자의 `length(out) == 0` 가드를 **통과**하고, 이후 JSON 파싱 실패로 "router output parse fail" 같은 **엉뚱한 사유**로 보고된다. 진짜 원인이 가려진다.

**대체 (정본)**: `Sys.setenv()` + 복원 — `02_Infrastructure/worktask/state_machine.R:248-252`

```r
.old <- Sys.getenv("NAME", unset = NA)
Sys.setenv(NAME = value)
on.exit({ if (is.na(.old)) Sys.unsetenv("NAME") else Sys.setenv(NAME = .old) }, add = TRUE)
system2(cmd, args = ...)          # env= 없이
```

### ② 스크립트 최상위 `on.exit()` 금지
`on.exit`는 **함수 프레임**에 등록된다. 스크립트 최상위(global env)에 쓰면 **조용히 no-op**이다. 실측: 정상종료 / error halt / `quit(status=1)` **3경로 전부 미발화**.

결과가 나쁜 쪽으로 조용하다 — cleanup 계약이 dead code가 되어 **production으로 잔재가 샌다**(실사례: synthetic year-9999 WT가 `qepm/mailbox/worktask/`에 실행마다 누적, 실측 5건 잔류. "cleanup obligation" 주석과 guard 호출이 *있는데도* 안 돌았다).

**대체**: `reg.finalizer(globalenv(), f, onexit = TRUE)` — 3경로 전부 발화 실측.

```r
invisible(reg.finalizer(globalenv(), function(e) cleanup_all(), onexit = TRUE))
```

`reg.finalizer`는 `NULL`을 반환하므로 최상위에서는 `invisible()`로 감쌀 것. 함수 *안*에서 쓰는 `on.exit`은 정상이며 금칙 대상이 아니다.

### ③ 선행 `/` 경로 하드코딩 금지 + 루트는 marker로 검증
Windows R은 `/mnt/c/...`를 **현재 드라이브 기준** `C:/mnt/c/...`로 해석한다. 그 자리에 과거 실행이 남긴 **빈 디렉토리 잔재**가 있으면 `setwd()`가 **조용히 성공**하고, 이후 상대경로 `source()`가 전부 파일 부재로 죽는다.

- 루트 후보 판정에 `dir.exists()`만 쓰지 말 것 → **marker 파일**로 검증:
  `file.exists(file.path(cand, "02_Infrastructure/hooks/qvest_hook_router.py"))`
  쉘 등가: `[ -f "$cand/02_Infrastructure/hooks/qvest_hook_router.py" ]`.
  **marker 미충족 후보는 수락이 아니라 다음 tier로 낙하**시키고, 기각 사실을 stderr로 알릴 것 —
  조용한 fall-through는 이 계통의 재발 기전이다(정본: `resolve_project.sh::_qvest_root_ok`).
  ★**정규화를 검사보다 먼저** 할 것. `-d`/`dir.exists`는 역슬래시 루트(`C:\Users\…`)도 통과시키므로,
  검사 뒤에 정규화하면 검사가 자기가 고쳐 쓸 문자열을 읽은 셈이 된다.
  2026-08-01 실사고: User scope `QM_ROOT`가 역슬래시라 `daily_refresh.sh`의 `setwd("$BASE")` 6지점이
  R 소스문자열에서 `\U`로 파싱돼 halt → `run_r`은 체인을 계속하므로 **5개 스텝만 침묵 실패**
  (KTRI v3 · MSM · regime_daily_v2 · SJM · cache_freshness_audit).
- 절대경로 판정에 `startsWith(p, "/")` 쓰지 말 것 → drive-letter·UNC·`~`를 인식할 것:
  `grepl("^([A-Za-z]:)?[/\\\\]", p) || grepl("^~", p)`
- 임시 디렉토리는 `"/tmp/..."`(→`C:/tmp/...`) 대신 `tempfile()`.
- ★**bash 와 R 이 같은 경로 문자열을 공유하면 그 자리가 급소다.** `/tmp` 는 두 런타임에서 **다른 디렉토리로 해석된다** — bash(MSYS)는 `AppData\Local\Temp`, Windows R 은 `C:/tmp`. 한쪽이 쓰고 다른 쪽이 읽으면 읽는 쪽은 **영원히 빈 손**이고, 그 공허함이 "위반 없음"으로 읽히면 감사가 죽는다(실측: `v61_compliance_audit.R` P2 — 원장 표 참조).
  판별법: 리터럴을 R 과 `.sh`/`.py` 양쪽에서 `grep -rl` 해 **둘 다 나오면 분기 위험**. 2026-08-02 전수 결과 `/tmp` 리터럴 6계열 중 공유 2건, 그중 실제 분기 **1건**(`qvest_lockbox_access`) — 나머지 1건(`…update.lock`)은 `.sh` 쪽이 주석뿐이라 오탐이었다.
  정본: 공유가 필요한 경로는 `/tmp` 대신 **프로젝트-상대 경로**(`.cache/` 등)를 쓰거나, 양쪽이 같은 환경변수(`TEMP`)를 경유할 것.

### ④ 루트 resolver 우선순위 = `CLAUDE_PROJECT_DIR` 먼저
`~/.Renviron`이 `QM_ROOT`를 고정하므로 **쉘 `export`로 덮이지 않는다**(실측). 실행 루트를 바꾸려면 `CLAUDE_PROJECT_DIR`를 쓴다.

리포지토리에 resolver가 두 계열로 갈려 있다:

| 계열 | 파일 |
|---|---|
| `CLAUDE_PROJECT_DIR` → `QM_ROOT` (**표준**) | `cert_rules.R .qvest_find_root` · `essence_backfill.R` · `distilled.R` · `close_round.R` · `constraint_firewall.R` · **`hooks/resolve_project.sh`**(2026-08-01) |
| `QM_ROOT` → `CLAUDE_PROJECT_DIR` (예외) | `config.R:13-20` · **`ops/resolve_project.sh`**(2026-08-01 도훈 결정 — 아래 사유) |

호출자와 피호출 모듈이 다른 계열이면 **worktree 실행에서 root가 갈린다** — 테스트는 main에 상대경로로 쓰고 모듈은 worktree에서 찾아 **존재하는 파일이 "package not found"로 기각**된다(실측). main 단독 실행에선 두 값이 같아 **잠복**하므로, worktree 검증에서만 터진다. 신규 코드는 표준 계열을 따를 것.

#### 쉘 resolver 2벌의 계열 분기 (2026-08-01 도훈 결정 — 미수리 아님)

`resolve_project.sh`는 `ops/`(28 소비자)와 `hooks/`(pipeline_trigger 등) 두 벌이고, **우선순위가 의도적으로 다르다.** 감사 시 ops 판을 금칙 ④ 미수리로 재적발하지 말 것.

- **hooks 판 = CPD-first (표준)**. `settings.json`의 훅 command 30곳이 전부 `DIR=${CLAUDE_PROJECT_DIR:-${QM_ROOT:-$PWD}}`로 worktree를 고르는데, 그 훅이 sourcing하는 resolver가 QM_ROOT(=main)를 답하면 **코드는 worktree·데이터 루트는 main**으로 갈린다. 실측 경로 `settings.json:105 → pipeline_trigger.sh:18 → stage_dispatch.py`: 미병합 worktree 사본이 main의 정본 WT mailbox에 `mkdir`·이동·`Popen`을 건다.
- **ops 판 = QM_ROOT-first 유지**. 스케줄러 10종·`daily_refresh.sh`·PG2 러너 등 28 소비자의 루트 해석 의미를 바꾸지 않기 위함. 실측상 그쪽은 CPD가 `QM_ROOT`로 핀되거나(`.bat` 10종 전부, `run_pg2_rebalance_full.sh:25` 등) 아예 미설정(Bash 툴·`bootstrap.sh:14` 시점)이라 **flip해도 no-op**이지만, 프로덕션 데몬의 root 해석 의미를 무변경으로 두는 쪽을 택했다.
- ★ 참고: 금칙 ④의 원 근거("`~/.Renviron`이 QM_ROOT를 고정해 export로 못 덮는다")는 **R 한정**이다. 쉘에서는 `export QM_ROOT`가 정상 동작하므로 그 논거는 쉘 resolver에 그대로 전이되지 않는다.
- 강제: `08_Tests/hooks/test_resolve_project_marker.sh`가 이 분기를 **양방향으로** 검사한다(hooks=CPD 우선 ∧ ops=QM_ROOT 우선). 한쪽만 검사하면 "둘을 통합" 리팩터가 조용히 통과한다.

### ⑤ `system()` / `system2()` 명령 문자열에 쉘 리다이렉션·연쇄 연산자 금지
Windows R의 `system()`/`system2()`는 **셸을 경유하지 않는다**. `2>/dev/null` · `&&` · `|` 는 해석되지 않고 대상 프로그램의 **리터럴 argv**가 된다. 2026-08-02 실측:

```
system("git rev-parse HEAD 2>/dev/null", intern=TRUE)
→ c("f8da73e4…", "2>/dev/null"), status 128
   (git이 HEAD를 먼저 출력하고 두 번째 '리비전'에서 죽는다)
system("git status --porcelain 2>/dev/null", intern=TRUE)
→ character(0), status 128
```

★위험한 건 실패가 아니라 **위장의 비대칭**이다. 같은 결함이 두 필드에 정반대로 작용했다 — `rev-parse`는 SHA를 먼저 뱉어 `sha[1]`이 **우연히 정답**이었고, `status`는 통째로 죽어 0행을 반환해 호출자의 `length(out) > 0`이 **항상 `FALSE`** = "clean tree"라는 그럴듯한 정상값이 됐다. **빈 출력이 '변경 없음'으로 읽히는 지점이 이 금칙의 급소다**(메모리 `project-benchmark-two-source-divergence-20260802`의 "값 `0`이 안 움직였다로 읽힌다"와 같은 기전).

실측 피해: `qepm/mailbox/worktask/*/artifact_lineage.json` 388 entry 중 **2026-06(Windows 이관)~08 기록 79건이 `git_dirty=false` 전량**, 그 이전 309건은 전량 `true`. 월 경계에서 100% 갈린다 — 분산 0이 곧 미측정의 지문이다.

**대체 (정본)**:

```r
out <- suppressWarnings(system2("git", c("rev-parse", "HEAD"),
                                stdout = TRUE, stderr = FALSE))
st  <- attr(out, "status"); st <- if (is.null(st)) 0L else as.integer(st)
if (st != 0L) { ... }        # 결손을 값으로 내려앉히지 말 것
```

- 리다이렉션 → `stdout=` / `stderr=` 인자. 필터링·집계는 R에서(`grep(pattern, out, value=TRUE)`).
- 연쇄(`&&`) → **호출 분리** + 각 단계 exit status 검사.
- 셸이 정말 필요하면 `shell()`을 쓰되 `/dev/null`이 아니라 `NUL`.
- **미측정은 `FALSE`/`0`이 아니라 `NA`(→ JSON `null`) + 명시 라벨**로 기록할 것. 정본 선례: `worktask/lineage_utils.R::capture_git_state()`(`git_commit="UNAVAILABLE"` · `git_dirty=NA` · `git_state_error=<사유+exit code>`).

### (동반) bare `python3` 금지
별도 규칙으로 이미 확립 — `python3`는 Windows Store 스텁("Python" 출력 후 rc 49). `QVEST_PY` → venv 순 해석.
메모리 `reference-python3-windows-stub-use-qvest-py` · 훅은 `_shared_parse.sh` `QVEST_PY_BIN` 체인.

---

## 위반 원장 (2026-07-25 실측 스캔)

**정본 = `08_Tests/hooks/_r_portability_baseline.json`** (기계 생성, 재생성 `Rscript 08_Tests/hooks/test_r_portability.R --write-baseline`).
스캔 범위 = **라이브 존** `02_Infrastructure` · `08_Tests` · `qepm/scripts` (**569 .R**, 2026-08-02 실측 — 구 표기 531은 스테일). 아카이브 존(`stage_artifacts/` · `qepm/mailbox/` · `04_Research/strategies/`)은 재실행 대상이 아니므로 제외.
★파일 수·통과 수는 리포지토리가 자라면 계속 움직인다 — **문서 숫자는 스냅샷이고 정본은 검사기 실행 출력**(`live zone` 줄)이다. 문서와 어긋난다고 계약 위반이 아니다.

**발효 시점 원장 = 54건**(main 기준, `73a8e95b` 병합 직후 재생성).

> ⚠ **운영 특성 — baseline은 트리에 종속이다.** worktree에서 생성한 원장을 그대로 main에 병합하면 그새 움직인 main과 어긋나 즉시 FAIL한다(실증: worktree 60건 → main 재생성 54건. 다른 세션이 `/tmp` writer 7건을 수리해 축소 + `essence_score.R` 1건 추가). **병합 후 대상 브랜치에서 `--write-baseline`을 한 번 돌려 커밋할 것.** 이 어긋남 자체는 버그가 아니라 래칫이 의도대로 작동한 신호다 — 원장이 조용히 늘거나 수리분이 남는 것을 막는다.

**발효 시점 원장 = 60건(worktree 생성분, 위 사유로 폐기).** 금칙별 분포는 baseline 파일 참조. ★수치가 초기 육안 grep(≈12건)보다 5배 큰 이유: 육안 스캔은 `/mnt/c/Users/User|바탕 화면`만 봤고, 계약 검출기는 `"/tmp/` 리터럴과 resolver 우선순위 역전까지 본다. **검사기를 만들고 나서야 표면의 실제 크기를 알았다** — 이것이 문서-only 규칙을 인정하지 않는 이유다.

아래 표는 그중 **판단이 필요한 항목**만 발췌한다(전량은 baseline).

| 상태 | 위치 | 금칙 | 비고 |
|---|---|---|---|
| ⚠ **미수리(감사 사망)** | `worktask/v61_compliance_audit.R:24` | ③ | 2026-08-02 실측. `LOCKBOX_LOG_PATTERN <- "/tmp/qvest_lockbox_access_%s.log"` → Windows R 은 `C:/tmp/…`, bash 훅(`lockbox_audit_trail.sh`)은 MSYS `/tmp`(=`AppData\Local\Temp`)에 쓴다. **실제 접근기록 4건이 감사자가 안 보는 디렉토리에 있다** → `audit_p2_data_separation()` 이 항상 `pass=TRUE, reason="no_lockbox_access (clean)"`. **P2 Data Separation 은 구조적으로 실패할 수 없다.** ★이 항목은 baseline 에 "수용된 기존 위반"으로 이미 있었다 — 린트로는 수용됐지만 **행동 결과(감사 사망)는 아무도 보지 않았다**. 원장 등재 ≠ 무해. 수리는 bash·R 양쪽 경로 규약을 함께 바꿔야 하는 교차언어 계약 변경 |
| ○ 잠복 | `worktask/v61_compliance_audit.R:25` | — | `BOOK_STATE <- "qepm/mailbox/governor/book_state.json"` 상대경로. cwd 가 다르면 136KB 실파일이 있는데도 P8 이 `"no_book_state_yet"`(아직 없음)으로 통과 |
| ✅ 수리 | `worktask/lineage_utils.R` | ⑤ | 2026-08-02. `git_dirty`가 2026-06~08 **79건 전량 `false`로 위장**(미측정). 수리 후 미측정 = `UNAVAILABLE`/`null` + `git_state_error`. 소급 수정 없음(역사 보존) |
| ✅ 수리 | `ops/update_research_philosophy.R:104` | ⑤ | 2026-08-02. `system("git add -A && git commit …", intern=FALSE)` → `&&` 이하가 `git add`의 pathspec이 되어 **auto-baseline 커밋이 한 번도 생성되지 않았고** exit status마저 버려졌다. ★그 상태에서 `.git_rollback()`의 `git reset --hard <이전 SHA>`는 미커밋 작업을 파괴한다 — 안전장치가 정반대로 작동 |
| ✅ 수리 | `ops/cert_backfill_audit.R:697` | ⑤ | 2026-07-26 CBA-06(선행 수리). `"2>&1 \| grep -E …"`가 내부 Rscript의 리터럴 argv로 전달 |
| ✅ 수리 | `worktask/cert_rules.R:444,430` | ①③ | `d384c016` |
| ✅ 수리 | `08_Tests/integration/*.R` 3종 | ②③④ | `f18f6c90`·`d384c016` |
| ⚠ **미수리(실동작 영향)** | `tools/paper_recharge_daily.R:60` | ② | 최상위 `on.exit(unlink(lock_dir))` → **lock 영구 미해제**. 이후 실행이 stale lock(<3600s)을 보고 `quit(status=0)`로 **조용히 skip** |
| ⚠ **미수리(실동작 영향)** | `validation/v8_readiness_gate.R:341` | bare python3 | 같은 파일 `:240`은 `py_bin` 사용 — **한쪽만 수리됨**. rc 49 → 해당 check가 조용히 미집계 |
| ○ 잠복 | `validation/v8_readiness_gate.R:74` | ① | `run_cmd(env=)`. 호출부 10곳 전부 `env` 미전달이라 현재는 dormant |
| ○ 잠복(스테일) | `factor_db/factor_db_daily_*.R` 9파일 × 2 | ③ | `error=` 폴백이 **구 프로젝트 위치**(`바탕 화면`, 2026-06-10 이전)를 가리킴. 발화 시 husk로 유입 |
| ○ 잠복(스테일) | `factor_db/compute_regime.R:54-55` · `rcpp_helpers.R:53` | ③ | 후보 목록 내 구 경로 |
| ○ 경미 | `08_Tests/hooks/test_cert_rules.R:82` | ② | `tempfile()` 대상이라 R이 세션 종료 시 회수 — 실피해 없음 |
| ○ 경미 | `search/build_index.R:632` | ② | `close(con)` 미발화. R 종료 시 자동 close |

**✅ 동반 수리(같은 계열)**: `run_all_hooks.sh` 집계가 요약을 `tail -1`로 집던 탓에 마지막 줄이 경고·stderr 인터리브로 밀리면 그 suite가 UNREPORTED(=1 fail)로 계상되고 **통과 건수가 통째로 사라졌다**(실측 1/7 빈도: `27/0/27` ↔ `17/1/18`, 드롭분 = seq_gate 10건). → **뒤에서부터 첫 유효 요약 JSON 라인**을 집도록 교체. 계약 검사기가 이 배터리 위에 얹히므로, 집계가 flaky하면 계약도 flaky해진다.
⚠ 다만 러너는 여전히 **각 suite를 2회 실행**한다(표시용 `run_test` + 집계 루프). 중복 실행 제거는 미수리 — 부작용 있는 suite에서 위험.

**✅ 동반 수리 2 — 금칙 ③의 테스트-하네스 재발 (2026-08-02, `4c74ba12`)**: `test_ast_spec_gate.sh` D4/D5가 `$ROOT`를 **Windows python**에 그대로 넘겼다. 그런데 이 문서가 안내하는 실행형 `CLAUDE_PROJECT_DIR="$PWD"`는 Git Bash에서 **MSYS 형 `/c/...`**를 만들고, Windows python은 그 경로를 열지 못한다. 거기에 `2>/dev/null`이 `FileNotFoundError`를 삼켜 빈 값이 되면서 **schema.json은 멀쩡한데 "게이트-schema 동기 실패"로 오보**했다(배터리 2 fail의 정체 — 읽는 사람을 schema 수정으로 오도한다). → mixed 형 정본 idiom `cygpath -m`(`bootstrap.sh:20-22`) 적용 + `2>&1 | tail -1`로 실패 사유 표면화. 변형 fixture(`falsification`→`string`, `sig_date` 제거)로 검사가 여전히 FAIL함을 확인(오탐 제거이지 검사 사망이 아님).
★**계약 확장**: 금칙 ③은 `.R` 안의 리터럴만이 아니라 **bash → Windows python 인자 전달**에서도 재발한다. `test_r_portability.R`은 `.R`만 스캔하므로 이 표면을 구조적으로 못 본다(`.sh` resolver 공백을 자매 검사기가 메우는 것과 같은 구조). 쉘에서 경로를 python·R에 넘길 때는 `cygpath -m`을 거칠 것 — POSIX 형은 bash에선 유효하고 Windows 인터프리터에선 무효라, **한쪽에서만 죽어 환경 의존 red로 보인다**.

---

## 강제 (teeth)

`08_Tests/hooks/test_r_portability.R` — 라이브 존을 스캔해 금칙 5종을 검출하고 **baseline 래칫**으로 판정한다:

- **신규 위반 → FAIL** (baseline 밖 항목)
- **baseline 역행 방지**: 수리돼 사라진 항목이 baseline에 남아 있으면 FAIL(`--write-baseline`으로 갱신 요구). 원장은 **줄어드는 방향으로만** 움직인다.
- `run_all_hooks.sh` 배터리 편입 — 매 실행 검사. **이 suite 자체 = 7/7**(래칫 2축 + 위반 주입 4종 + 오검출 통제 1 — 축 구성이 바뀔 때만 움직이는 안정 수치).
  ★**배터리 전체 통과 수는 여기 적지 않는다.** 구 표기 "34/34"(발효 2026-07-25)가 스테일이 된 이유가 이것이다 — 다른 세션이 suite를 계속 붙여 2026-08-02 하루에도 34→459→495→501로 움직였다(30분 만에 495→501 실측). 문서에 박은 순간 썩는 수치이고, 어긋남을 계약 위반으로 오독하게 만든다. **판정 기준은 "배터리 전체 PASS 여부"이지 통과 *건수*가 아니다.** 건수 정본은 `.cache/test_results/hook_dryrun_results.json`.
  ★아래 자매 검사기 줄의 `11/11`은 *suite* 수치인데 구 문구가 이 줄과 똑같아 서로 다른 것을 가리키고 있었다 — 이제 둘 다 라벨을 붙인다.

`08_Tests/hooks/test_resolve_project_marker.sh` — 쉘 resolver 2벌의 **루트 marker 게이트**(금칙 ③)와
**계열 분기**(금칙 ④ 위 절)를 검사한다. `test_r_portability.R`은 `.R`만 스캔하므로 `.sh` resolver를
구조적으로 못 본다 — 그 공백을 메우는 자매 검사기다. `run_all_hooks.sh` 배터리 편입(**이 suite 자체 = 11/11**, 2026-08-02 실측).

- 축: 위반 주입(marker 없는 후보 수락 여부) × 2벌 · 기각 WARN 발화 · 양성 통제 · 역슬래시 정규화 ·
  self-inference 기각→glob 낙하 · **우선순위 양방향**(hooks=CPD ∧ ops=QM_ROOT) · CPD도 marker 게이트 통과 요구
- **돌연변이 축 내장**: 게이트를 구판 `[ -d "$c" ]`로 되돌린 사본을 만들어 위반 주입 축이 실제로
  뒤집히는지 확인한다. 안 뒤집히면 그 "통과"는 계측 사망이다 — 오탐 제거와 검사 사망은 겉보기가 같다.
- 위반 주입 fixture는 `02_Infrastructure/`를 갖췄으나 marker는 없는 임시 디렉토리를 쓴다.
  구 branch 2가 `-d "$_cand/02_Infrastructure"`만 봤으므로, 이게 없으면 헐거운 검사도 통과한다.

`08_Tests/hooks/test_lineage_git_state.R` — 금칙 ⑤의 **행동 수준** 자매 검사기(2026-08-02 신설, 배터리 편입 **11/11**).
정적 스캔은 "쉘 문법이 argv에 있다"까지만 본다. 결손이 **JSON까지 명시 라벨로 도달하는지**는 못 본다 —
그리고 구 구현의 실제 실패가 정확히 거기였다(`capture_git_state()`가 `git_state_error`를 **계산해 놓고
`build_lineage_entry()`가 entry에 안 실었다**). 그래서 이 검사기는 함수 반환값이 아니라 **직렬화된 파일**을 읽어 판정한다.

- 축: 정상경로 실측(40-hex SHA · dirty 측정됨 · 오류라벨 없음) × **위반 주입**(비-리포 디렉토리 +
  `GIT_CEILING_DIRECTORIES`로 상위 리포 탐색 차단 → git exit 128 강제) × 직렬화 관통 × seed 결정성
- **핵심 회귀 가드**: 주입 상태에서 `git_dirty == FALSE`면 FAIL. 미측정이 `FALSE`로 내려앉는 것이 구 결함의 형태다.
- **돌연변이로 검출력 실증**(2026-08-02): 수리를 구판으로 되돌린 사본에서 4축이 실제로 뒤집힘
  (`injected_dirty_not_false` · `json_dirty_null` · `json_error_label_present` · `seed_task_deterministic`).
  안 뒤집혔다면 그 11/11은 계측 사망이다.

**위반 주입 8종 내장**(위반 주입 테스트): 금칙 5종 각각의 합성 위반 fixture(⑤는 redirect·chain·pipe 3형태)를 실제로 잡는지 + 정본 패턴을 오검출하지 않는지 자체 검증. 실효 실증 — 최초 구현의 검출기 ①은 `system2\([^)]*env=`였는데 인자 안의 `)`(예: `args = c("-c", code)`)에서 멈춰 **다중행 호출을 놓쳤고, 위반 주입 테스트가 이를 적발**했다(괄호 균형 파서로 교체 후 `data/build_cache.R` 등 추가 검출). 래칫 검출력도 실증 — 합성 위반 주입 시 `exit 1`, 제거 시 `exit 0`.

> 검사기 자체가 "잘못된 것을 재는" 실패가 이 리포지토리의 반복 부류다(존재→유효성, substring→ID, mtime→최신성). 그래서 위반 주입 테스트 없는 검사기는 이 계약에서 인정하지 않는다. 위 ① 사례가 그 규정의 첫 회수다.

> 검사기 자체가 "잘못된 것을 재는" 실패가 이 리포지토리의 반복 부류다(존재→유효성, substring→ID, mtime→최신성). 그래서 위반 주입 테스트 없는 검사기는 이 계약에서 인정하지 않는다.

---

## 참조
- `.claude/rules/python-policy.md`(자매) · `answer-principles.md`(자체합성·회피표현) · `measurement-graduation.md`
- 정본 선례: `02_Infrastructure/worktask/state_machine.R:248-252`(env) · `cert_rules.R:430-437`(절대경로·QVEST_PY)
- 메모리: `reference-r-windows-system2-onexit-traps` · `reference-python3-windows-stub-use-qvest-py` · `reference-rscript-e-korean-segfault`
- 커밋: `f18f6c90` → `97730b4c` / `d384c016` → `2cfa7100`
