---
description: 2계층 — 전략 로테이션 리서치 (v10). B등급 이상 모듈을 국면조건부로 배합해 전천후 FR_XXXX 산출. 논문 온디맨드 착수 → 리서치 1단위마다 등급 → 강화 무한 → A → Judge(PIT) → BOOK
---

# /strategy-rotation <track>

**2계층 리서치** (v10 2026-08-29). 1계층이 생산한 **B등급 이상 전략 모듈**을 국면
조건부로 배합해 어느 시장 상황에서나 통하는 전천후 운용체계(`FR_XXXX`)를 만든다.
모듈을 생산하지 않고 소비하는 meta-layer. `/qvest` 2계층 선택 시 기본 진입점.

**track**:
- `regime-engine` (Track1) — 국면 정의 + 사전예측 강화 (학술논문 기반 — 원문 링크 의무).
- `allocation` (Track2) — 모듈 배분. `module_dispatcher.R` → `run_wf_ensemble.R` → `build_bt_result` 실측 → `essence_score`.

**사용법**:
```
/strategy-rotation allocation
/strategy-rotation regime-engine
```

**동작 (allocation)** — 단일 진입 = `run_factor_rotation.R` (신선도 자동 rebuild):
0. **논문 착수** — 세션 온디맨드 검색(arXiv/SSRN MCP)으로 국면식별·전략결합 논문 확보
   → Step 0 지식 대조 + 원장 교훈 주입(`rf_lessons_digest(2L, ...)`). 무인 수집기는 1계층 전용.
1. **풀 적재 (2단 게이트)** — `build_module_performance.R`: ①계약 floor(fr_eligible)
   ②★**grade floor = essence B 이상**(`QVEST_L2_GRADE_FLOOR`, v10 — 구 "등급무관 차용" 폐기)
   → `module_performance.json`(grade_floor 메타 기록). 풀 축소는 지시의 귀결 — 크기 보고.
2. **RCMA 배치 심사** — `regime_module_admission.R` (B+ 풀 **위의** 국면조건부 심사 — 유지).
3. 앙상블 — `run_wf_ensemble.R`(anchored WF, IS-only, 모듈 frozen) → `build_bt_result` → `essence_score`(A/B/C/F).
4. FR_XXXX 등재(grade 포함) + L-code(`strategy_rotation`) + 텔레그램 `[2계층]`.
5. **분기** — A 미달 → **강화 무한**(`Skill(reinforce)`, 원장 `reinforce_ledger_l2.json`,
   축 = 국면식별/전략결합) / **A 달성 → Judge(PIT) → PASS → BOOK 등록**
   (`register_book_entry(kind="rotation_rule")` — 도훈 confirm).

**모듈 적재 계약**: `register_module()` 경유 표준화(+v10 `grade_basis` 기록 의무).
floor 미충족분은 quarantine.

**실행 방식**: `Skill(strategy-rotation)` 또는 `Agent(subagent_type="dispatch-orchestrator", ...)`.

**제약**: 모듈 frozen(재백테 금지) · dispatcher=book_optimize 래퍼 · 실측-only(자체합성 금지) ·
★governor 폐지(v10 — BOOK 이 승계, 등록은 도훈 confirm 수동) · WT-id 미사용 ·
비중 상한 없음(v10) · 모든 수치 결정에 근거 논문 원문 링크. 위반=AX-002.

상세: `.claude/skills/strategy-rotation/SKILL.md` · `02_Infrastructure/docs/rules/strategy-rotation.md`.
