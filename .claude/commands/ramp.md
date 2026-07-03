---
description: RAMP 모드 — 기존 전략풀(~800 NAV)에서 순수팩터 추출→팩터군→M-code→리스크매니저→인베스터 에이전트로 국면-인지 팩터배분 운용체계(RAMP_XXXX)를 만드는 제4 리서치 모드. 거버넌스-우선·Gate 0~11·CCS 13-score·실측-only·governor 정지(자본 수동).
---

# /ramp <stage>

**RAMP** = Korea Regime-Aware Multi-Factor Portfolio. 기존 전략풀을 *소비*해 팩터배분 의사결정을 내리는 운영체계(신규 전략 생산 X). SOT: `02_Infrastructure/docs/rules/ramp.md` + `00_Lawbook/K_RAMP/`(헌법+가이드 통합본) + `.claude/skills/ramp/SKILL.md`(운영매뉴얼).

**진입 시 의무**: `ramp` 스킬 + `ramp.md` 룰 Read 후 착수. 가이드북 루프(Observe→Diagnose→Propose→Implement→Test→Score→Document→Promote/Revert) = Axiom 엔진 4번째 모드(modecode RAMP).

**stage** (Gate 순서, 점프 금지):
- `scaffold` — Gate 0/1: 모드 배선 + config + Axiom 모드 등록 + 거버넌스 아티팩트
- `synthetic` — Gate 2: synthetic 생성기 + 데이터계약 검증(DCCS/BDS)
- `inventory` — Gate 3: 풀 수익률행렬(~800, batch_434 포함) dedup (SDS)
- `purefactor` — Gate 4: 통계적 잠재팩터(PCA/factanal/hclust) + FWL 경제라벨 + canonical_screen 검증 → 승인라이브러리 (PFIS/RDDS)
- `grouping` — Gate 5: 승인 순수팩터 클러스터 → 팩터군 + regime matrix
- `mcode` / `risk` / `agent` / `backtest` — Gate 6~9 (M-code 분업 → 리스크매니저 → 인베스터 에이전트 → 통합백테)
- `govern` — Gate 11: CCS + 재귀 거버넌스(Axiom)

**사용법**:
```
/ramp scaffold
/ramp purefactor
```

**제약(절대)**: 실측-only(자체합성 금지) · PIT C1~C15 · long-only/Σw=1/25종/[0,0.20]/15bps · no hard switch · **Qvest_Codex 경로 참조 금지** · 자본 게이트 governor 수동(도훈 confirm). 위반 = AX-002.

**진입점 스크립트**: `04_Research/ramp/run_ramp.R` (단일) 또는 debug-first `02_Infrastructure/ramp/debug/debug_one_*.R`.
