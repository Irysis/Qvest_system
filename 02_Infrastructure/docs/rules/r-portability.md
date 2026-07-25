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

## 금칙 4종 (위반 시 수리 의무)

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
- 절대경로 판정에 `startsWith(p, "/")` 쓰지 말 것 → drive-letter·UNC·`~`를 인식할 것:
  `grepl("^([A-Za-z]:)?[/\\\\]", p) || grepl("^~", p)`
- 임시 디렉토리는 `"/tmp/..."`(→`C:/tmp/...`) 대신 `tempfile()`.

### ④ 루트 resolver 우선순위 = `CLAUDE_PROJECT_DIR` 먼저
`~/.Renviron`이 `QM_ROOT`를 고정하므로 **쉘 `export`로 덮이지 않는다**(실측). 실행 루트를 바꾸려면 `CLAUDE_PROJECT_DIR`를 쓴다.

리포지토리에 resolver가 두 계열로 갈려 있다:

| 계열 | 파일 |
|---|---|
| `CLAUDE_PROJECT_DIR` → `QM_ROOT` (**표준**) | `cert_rules.R .qvest_find_root` · `essence_backfill.R` · `distilled.R` · `close_round.R` · `constraint_firewall.R` |
| `QM_ROOT` → `CLAUDE_PROJECT_DIR` (예외) | `config.R:13-20` |

호출자와 피호출 모듈이 다른 계열이면 **worktree 실행에서 root가 갈린다** — 테스트는 main에 상대경로로 쓰고 모듈은 worktree에서 찾아 **존재하는 파일이 "package not found"로 기각**된다(실측). main 단독 실행에선 두 값이 같아 **잠복**하므로, worktree 검증에서만 터진다. 신규 코드는 표준 계열을 따를 것.

### (동반) bare `python3` 금지
별도 규칙으로 이미 확립 — `python3`는 Windows Store 스텁("Python" 출력 후 rc 49). `QVEST_PY` → venv 순 해석.
메모리 `reference-python3-windows-stub-use-qvest-py` · 훅은 `_shared_parse.sh` `QVEST_PY_BIN` 체인.

---

## 위반 원장 (2026-07-25 실측 스캔)

**정본 = `08_Tests/hooks/_r_portability_baseline.json`** (기계 생성, 재생성 `Rscript 08_Tests/hooks/test_r_portability.R --write-baseline`).
스캔 범위 = **라이브 존** `02_Infrastructure` · `08_Tests` · `qepm/scripts` (531 .R). 아카이브 존(`stage_artifacts/` · `qepm/mailbox/` · `04_Research/strategies/`)은 재실행 대상이 아니므로 제외.

**발효 시점 원장 = 60건.** 금칙별 분포는 baseline 파일 참조. ★수치가 초기 육안 grep(≈12건)보다 5배 큰 이유: 육안 스캔은 `/mnt/c/Users/User|바탕 화면`만 봤고, 계약 검출기는 `"/tmp/` 리터럴과 resolver 우선순위 역전까지 본다. **검사기를 만들고 나서야 표면의 실제 크기를 알았다** — 이것이 문서-only 규칙을 인정하지 않는 이유다.

아래 표는 그중 **판단이 필요한 항목**만 발췌한다(전량은 baseline).

| 상태 | 위치 | 금칙 | 비고 |
|---|---|---|---|
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

---

## 강제 (teeth)

`08_Tests/hooks/test_r_portability.R` — 라이브 존을 스캔해 금칙 4종을 검출하고 **baseline 래칫**으로 판정한다:

- **신규 위반 → FAIL** (baseline 밖 항목)
- **baseline 역행 방지**: 수리돼 사라진 항목이 baseline에 남아 있으면 FAIL(`--write-baseline`으로 갱신 요구). 원장은 **줄어드는 방향으로만** 움직인다.
- `run_all_hooks.sh` 배터리 편입 — 매 실행 검사(현행 **34/34**, 소요 ~10s).

**음성 통제 5종 내장**(이빨 테스트): 금칙 4종 각각의 합성 위반 fixture를 실제로 잡는지 + 정본 패턴을 오검출하지 않는지 자체 검증. 실효 실증 — 최초 구현의 검출기 ①은 `system2\([^)]*env=`였는데 인자 안의 `)`(예: `args = c("-c", code)`)에서 멈춰 **다중행 호출을 놓쳤고, 음성 통제가 이를 적발**했다(괄호 균형 파서로 교체 후 `data/build_cache.R` 등 추가 검출). 래칫 이빨도 실증 — 합성 위반 주입 시 `exit 1`, 제거 시 `exit 0`.

> 검사기 자체가 "잘못된 것을 재는" 실패가 이 리포지토리의 반복 부류다(존재→유효성, substring→ID, mtime→최신성). 그래서 음성 통제 없는 검사기는 이 계약에서 인정하지 않는다. 위 ① 사례가 그 규정의 첫 회수다.

> 검사기 자체가 "잘못된 것을 재는" 실패가 이 리포지토리의 반복 부류다(존재→유효성, substring→ID, mtime→최신성). 그래서 음성 통제 없는 검사기는 이 계약에서 인정하지 않는다.

---

## 참조
- `.claude/rules/python-policy.md`(자매) · `answer-principles.md`(자체합성·회피표현) · `measurement-graduation.md`
- 정본 선례: `02_Infrastructure/worktask/state_machine.R:248-252`(env) · `cert_rules.R:430-437`(절대경로·QVEST_PY)
- 메모리: `reference-r-windows-system2-onexit-traps` · `reference-python3-windows-stub-use-qvest-py` · `reference-rscript-e-korean-segfault`
- 커밋: `f18f6c90` → `97730b4c` / `d384c016` → `2cfa7100`
