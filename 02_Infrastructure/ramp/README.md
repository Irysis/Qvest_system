# ramp/ — 퇴역 RAMP 모드의 남은 파일 (2026-10-14 정리)

RAMP 모드는 v9.21 에 퇴임했다. 2026-10-14 정리로 나머지 164개 파일(러너 · 디버그 · 탐색 · 설정)과 그 게이트 검사(`08_Tests/ramp/test_gate3_4.R`)는
`C:/qm_archive/reorg_20261014/02_Infrastructure/ramp/` 로 갔다(목록 = `00_Lawbook/reorg_20261014_manifest.json` · 태그 `pre-reorg-20261014`).

남은 3개는 **다른 살아 있는 코드가 경로로 부른다** — 옮기려면 호출부를 같이 고칠 것.

| 파일 | 소비자 |
|---|---|
| `factor_validation.R` | `portfolio/ppure_paper_track.R`(source) · `08_Tests/ramp/test_liquidity_ruler.R` — 유동성 t−1 규약(`data/liquidity_basis.R` 를 부른다) |
| `ramp_io.R` | `factor_validation.R` 가 source |
| `run_nosignal_queue_audit_r46.R` | `ops/auto_spawn_queue.R` 안내문 · `.claude/agents/dispatch-orchestrator.md` — 무신호 대조 감사 |
