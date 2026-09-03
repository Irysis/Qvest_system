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
