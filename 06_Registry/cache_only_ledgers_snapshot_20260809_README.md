# `.cache` 전용 사건 원장 스냅샷 (2026-08-09)

**라이브가 아니다.** 네 원장 모두 여전히 `.cache/` 에만 append 되며, 이 폴더의
`*_snapshot_20260809.*` 는 그 시점 사본일 뿐이다.

## ★`.cache` 는 저장소 밖이다

`.cache -> /c/qm_cache` (심볼릭 링크). "gitignore 되어 있다"는 과소 서술이고, 진짜 성질은
**저장소 작업이 절대 닿지 않는 위치**라는 것이다. fresh clone 은 물론이고 `C:\qm_cache` 를
비우면 저장소에 흔적조차 남지 않는다.

⚠계측 함정: `find .cache -type f` 는 **0** 을 낸다(심볼릭 디렉터리에 미진입).
`find -L .cache` 또는 끝 슬래시 `find .cache/` 는 235. `.claude`·`08_Tests` 는 정상이라
"점-디렉터리 문제"로 오진하기 쉽다. **`.cache` 계측에는 `ls` 또는 R `list.files()` 를 쓸 것.**

## 원장 4종 (실측 2026-08-09)

| 원장 | 레코드 | writer | 스냅샷 |
|---|---|---|---|
| `.cache/round_closures.jsonl` | 371 | `02_Infrastructure/contracts/close_round.R:126` | `round_closures_snapshot_20260809.jsonl` (367) |
| `.cache/hygiene_manifest.log` | 933 | `02_Infrastructure/ops/weekly_cleaner_sweep.R:99` | `hygiene_manifest_snapshot_20260809.jsonl` |
| `.cache/continuity_blocks.jsonl` | 77 | `02_Infrastructure/hooks/research_continuity_guard.sh` | `continuity_blocks_snapshot_20260809.jsonl` |
| `.cache/failure_revival_history.jsonl` | 42 | `02_Infrastructure/ops/failure_revival_monitor.R` | `failure_revival_history_snapshot_20260809.jsonl` |

round_closures 스냅샷은 367건 시점이고 이후 세션 중 4건이 더 쌓였다(라이브 371).

## 정답 패턴 (항구 수리는 이걸 복제할 것)

`02_Infrastructure/validation/benchmark_source_parity.R:255-265` — 현재 상태는
`.cache/benchmark_parity_latest.json`(재생성 가능), **사건 이력은**
`06_Registry/benchmark_parity_history.jsonl`(추적).

## ★스냅샷을 낼 때의 함정 — 확장자

이 저장소의 `.gitignore` 는 **확장자 단위**로 막는다(`*.csv` 24행, `*.log`).
"추적되는 디렉터리에 쓰면 된다"가 아니라 **확장자까지 확인**해야 한다.
실제로 오늘 색인을 `.csv` 로, 위생 원장을 `.log` 로 냈다가 둘 다 다시 무시되어 재발행했다.
⇒ 스냅샷은 `.jsonl` / `.json` / `.md` 로 낼 것. 낸 뒤 `git check-ignore` 로 확인할 것.

## 한정

- 원장 목록은 **하한**이다. 탐지 스캐너가 R 전용이라 `.sh`/`.py` writer 는 사각이며
  (continuity_blocks 가 그 증거 — 셸 writer라 AST 스캐너가 못 봄), 두 판본의 D1 개수가
  둘 다 3건이었으나 **집합이 달랐다**(개수 일치는 우연).
- 항구 수리는 별도 태스크. 이 파일들은 보존일 뿐이다.
