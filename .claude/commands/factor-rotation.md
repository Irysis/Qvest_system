---
description: 팩터 로테이션 모드 — QEPM/alpha-search 생산 모듈을 국면조건부로 배합해 FR_XXXX 운용체계 산출 (모듈 frozen 소비, governor 정지)
---

# /factor-rotation <track>

Qvest 제3 리서치 모드. 신규 알파를 찾지 않고 **이미 생산된 전략 모듈을 국면(regime) 조건부로 배합**해 합성 운용체계(`FR_XXXX`)를 만든다. 모듈을 생산하지 않고 소비하는 meta-layer(Lane3).

**track**:
- `regime-engine` (Track1) — 국면 정의 + 사전예측 강화 (학술논문/헤지펀드 페이퍼 기반). `regime_engine_research.R` / `regime_forecaster.R`.
- `allocation` (Track2) — 모듈 배분. `module_dispatcher.R` → `run_wf_ensemble.R` → `build_bt_result` 실측 → `essence_score`.

**사용법**:
```
/factor-rotation allocation
/factor-rotation regime-engine
```

**동작 (allocation)** — ★ 단일 진입 = `run_factor_rotation.R` (신선도 자동: 새/변경 모듈 감지 시 pool 자동 rebuild → 새 모듈 바로 편입):
1. **신선도 체크 + 풀 적재** — `module_performance.json` mtime vs `04_Research/strategies/*`·`module_catalog` 최신 mtime 비교. stale 시 `build_module_performance.R`(광역 전수, validity=데이터깨짐만, 등급무관) 자동 rebuild → `module_performance.json`
2. **RCMA 국면조건부 admission** — `regime_module_admission.R` → `module_regime_admission.json`. ★overall 등급 아닌 국면성과(방어형 CRISIS + 공격형 확장 specialist 양방향, F-overall이어도 차용)
3. 앙상블 — `run_wf_ensemble.R`(anchored walk-forward, IS-only, 모듈 frozen, admitted pool) → `build_bt_result`(실측) → `essence_score`(DSR/OOS 게이트)
4. FR_XXXX 등재 — `factor_rotation_registry.json`. governor **정지**(book_state 수동)

→ **QEPM/alpha-search가 새 모듈을 만들면**(strategies/ 저장 또는 `register_module`) **다음 `run_factor_rotation.R` 실행에서 자동 편입.** 강제 rebuild: `FR_FORCE_REBUILD=1`.

**모듈 적재 계약**: 모든 모드 산출물은 `register_module()`(`02_Infrastructure/contracts/register_module.R`) 경유 표준화(sim_result.rds + module_catalog). QEPM=native, alpha-search=배선됨.

**실행 방식**: `Skill(factor-rotation)` 또는 `Agent(subagent_type="dispatch-orchestrator", ...)` (Track2 배분 설계).

**제약**: 모듈 frozen(재백테 금지) · 스타일태깅 없음 · dispatcher=book_optimize 래퍼 · 실측-only(자체합성 금지) · governor 정지(book_state 도훈 수동 confirm) · WT-id 미사용. 위반=AX-002.

상세: `.claude/skills/factor-rotation/SKILL.md` · `.claude/rules/factor-rotation.md`.
