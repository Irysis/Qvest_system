# qepm — QEPM 라이브 운영 데이터 루트 (이름은 legacy, 심장부는 현행)

이 폴더 이름은 구 R 패키지 시절 유산이지만, **시스템 심장부 4개가 여기 있다 — 삭제·이동 금지**:
1. `mailbox/governor/book_state.json` — 라이브 자본 상태 (PG2 현행 book, 비가역 자본 게이트의 SOT)
2. `memory/axioms/active/AX-*.json` — Axiom SOT Primary authoritative (헌법 지정 단일 진실)
3. `registry/backtest_registry.csv` — 백테스트 결과 등재 권위 레지스트리 (Backtest Contract v1.0)
4. `mailbox/worktask/` — WT 6-에이전트 핸드오프 mailbox + WT 166건 아카이브

기타 하위 구조:
- `observability/` — 부팅 readiness·캐시 신선도·메모리 헬스 로그 착지점 (bootstrap/훅 현행 사용)
- `scripts/hybrid_mode.R` — Q-Lead 하이브리드 모드 (hybrid_commit/status/queue/daily_digest)
- `research/results/` — hybrid R0 raw artifact store (전략별 bt_result CSV 덤프)
- `R/` `config/` `prompts/` `schemas/` — v55 R 패키지 잔재 (legacy 보존, 신규 사용 금지)

찾는 것이 있다면: 현재 자본/북 상태 → `mailbox/governor/book_state.json` · 백테 등재 이력 → `registry/backtest_registry.csv` · 공리 원문 → `memory/axioms/active/`. 전체 지도는 루트 `ARTIFACTS.md` 참조 (이 존은 INDEX.md 없음).
