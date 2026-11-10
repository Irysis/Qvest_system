# 실행 프로필 — 읽기 전 주의 (v10 2026-09-03)

`lean.exclude` 는 `QVEST_SUITES_EXCLUDE` 로 **주입될 때만** 효력이 있다:

```bash
QVEST_SUITES_EXCLUDE="$(cat 08_Tests/hooks/profiles/lean.exclude)" bash 08_Tests/hooks/run_all_hooks.sh
```

★**현재 이 변수를 주입하는 소비자는 0** 이다 — `health_full.sh`(`bash run_all_hooks.sh`)도
`suite_totals_watch.sh --collect` 도 env 를 세우지 않는다. 즉 **여기에 이름을 적는 것으로는
아무 스위트도 제외되지 않으며**, 목록에 있는 스위트도 매일 전부 돈다.

- 실제 제외는 파일 이동이다: `08_Tests/**/_archive_v10*/` (편입 검사기 `suite_enrollment_check.sh` 의
  제외 패턴이 `*/_archive*/*` 라서 반드시 `_archive` 접두를 쓸 것 — `_retired_v10` 은 미편입으로 잡힌다).
- 파일 형식: **주석·개행 없이 한 줄 정규식**(`cat` 결과가 그대로 regex 가 된다). 설명은 이 README 에 적는다.
- 목록 자체는 v9 시점 판단의 기록이다. 2026-09-03 에 `test_lockbox_audit_path` 만 제거했다
  (이미 `08_Tests/hooks/_archive_v10_lockbox/` 로 격리돼 존재하지 않는 이름이었다).

## 층 · 병렬 레인 (2026-11-10 v10.2 시험 정리 · H1)

- 정본 = `suite_tiers.tsv`(열: suite · tier · lane · reason). tier = `fast` ⊂ `nightly` ⊂ `weekly`. 배정 없는 스위트 = nightly · serial(러너가 그 수를 찍는다).
- 러너 호출 계약:
  - `bash 08_Tests/hooks/run_all_hooks.sh [--tier fast|nightly|weekly|full] [--jobs N]`
  - 층 우선순위 = `--tier` 인자 > 환경변수 `QVEST_BATTERY_TIER` > `full`(= 전부 · weekly 와 같은 집합).
  - 병렬 슬롯 = `--jobs` > `QVEST_SUITES_JOBS` > 4. lane=parallel 스위트만 병렬, 나머지는 직렬 + 스위트별 등록부 지문.
  - 종료 코드 = 실패 + 미측정(250 상한) · 알 수 없는 층 = 2. 합계 = `.cache/test_results/hook_dryrun_results.json`
    (`tier` · `jobs` · `n_parallel` · `n_selected` · `n_declared` · `n_unassigned_tier` · `timings[]` 포함).
  - `08_Tests/scenarios/test_scn_*.{R,sh,py}` 는 SUITES 에 적지 않아도 자동 편입(러너 `AUTO_ENROLL_GLOBS`).
- `suite_totals_watch.sh --collect` 는 `QVEST_BATTERY_TIER` 를 그대로 러너에 넘기고(없으면 tiers.json 요일 규칙: full_weekday = weekly · 그 밖 = nightly),
  밤 층이면 `nightly.exclude` 예외도 뺀다. 결과 파일이 이번 실행 뒤에 쓰이지 않았으면 총계를 null 로 기록한다.
- 양성 대조 = `08_Tests/hooks/test_runner_parallel_tiers.sh`.
