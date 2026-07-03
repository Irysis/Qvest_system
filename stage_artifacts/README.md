# stage_artifacts — 런 불변 아카이브 (754건)

이 폴더는 WorkTask·스테이지 게이트 실행의 불변(immutable) 아카이브다 — 754건. 내부 이름·구조는 하드코딩 참조 때문에 변경 금지, 기존 결과 보존이 헌법 Safety Rule.

주요 하위 구조:
- `WT_*/` (116건+) — WorkTask별 스테이지 산출물 (에이전트 핸드오프·verdict·backtest 패키지)
- `S0_VERDICT_*.json` — 구 S0 가설 판정 기록 (v55 시대, 보존)
- `reports/` — 단발 분석 보고 (예: drawdown_frequency_kr_baseline)
- `paper_recharge/` — 논문 수집 파이프라인 큐/결과 (pg2_reinforcement_queue 등)
- `alpha_search/` — alpha-search 모드 런 산출물
- 루트 낱개 json/md — 게이트 감사·architect 설계·axiom 승격 패킷 등 프로세스 기록

**직접 탐색보다 인덱스 경유 권장**: 가설/검증 이력 → `06_Registry/hypothesis_index.json` · 전체 지도 → 루트 `ARTIFACTS.md` · 기계가독 인덱스 → `06_Registry/artifact_index.json`.
