# close_round 원장 스냅샷 (2026-08-09)

**이것은 라이브 원장이 아니다.** 라이브는 `.cache/round_closures.jsonl` 이며 계속 append 된다.

## 왜 있나
`close_round()` 는 `.cache/last_round_closure.json`(덮어씀) + `.cache/round_closures.jsonl`(append)
**두 곳에만** 쓴다. `.gitignore:5` 의 `.cache/` 로 둘 다 추적되지 않으므로 **fresh clone 이나 새 worktree 는
라운드 이력이 0건**이다. 라운드 내용(기전 진단·next_probe·소비면·증거·부활조건)의 다른 사본은 없다.

## 한정
- 스냅샷 시점 이후 라운드는 여기 없다. 시점 = 2026-08-09.
- 레코드 367건, 기간 2026-07-15 ~ 2026-08-09.
- 항구 수리(`close_round()` 가 추적 경로에 이중쓰기)는 **별도 태스크**. 이 파일은 보존일 뿐이다.

## 색인
`round_closures_snapshot_20260809_index.csv` = round_id / closed_at / verdict_type / layer /
next_probes 수 / evidence_refs 수.
