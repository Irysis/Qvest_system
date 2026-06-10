# Research Philosophy (Level 0 Constitutional Reference)

**Authoritative SOT**: `02_Infrastructure/docs/qvest_research_philosophy.md` (v1.0, 2026-05-14)

**7 QEPM Modern Trends** (모든 cycle reference, 도훈 mandate 2026-05-14):

1. **Factor Zoo 축소** — Validation > Discovery. `economic_rationale` + `redundancy_cluster_id` 필수
2. **Cost-aware Alpha** — Net > Gross. ML loss `-E[ret] + γ·|Δw|` 통합 (Jensen-Kelly-Malamud-Pedersen 2022)
3. **Uncertainty-aware Forecasting** — CI > Point Estimate. `μ̃ = μ̂ - k·SE(μ̂)` (Liao 2025 RFS)
4. **Direct Portfolio Learning** — Integration > Two-stage. Features → weights 직접 (You-Zhang 2025) — Phase 3
5. **Risk Model 고도화** — Σ + Crowding + Concentration. `crowding_score_per_factor` 필수 (Acadian 2026)
6. **Implementation Discipline** — TO ≤ 11.0/yr (도훈 mandate 2026-05-29, 기존 6.0에서 완화 — KR alpha turnover-intensive 반영. 비용 15bps 계속 차감 + net>cost 입증 의무) + LIQ 2e8 + max 25 + [0, 0.20] + Σw=1 (Hook 강제)
7. **Attribution & Feedback Loop** — factor + selection + cost + residual 분해. 분기별 자동 (Brinson + Carhart 4)

## Update Mechanism

- **분기별 review** (3개월) — arxiv MCP 학술 검색 + 도훈 amend approval
- **Trigger-based 보강** — paradigm shift / Codex 외부 발견 / 도훈 직접 mandate
- **Amendment 절차**: SOT 본문 → CLAUDE.md → 본 file → methodology_active.md L-code → (선택) axiom_signals.json

## Cross-reference

- 본문 7 principles + Phase Roadmap + Hook 정합: `02_Infrastructure/docs/qvest_research_philosophy.md`
- Axioms: `.claude/rules/axioms.md` (AX-009 Net-of-Cost candidate)
- PIT: `.claude/rules/pit.md` (C1~C15 정합 의무)
- Charter §13 (v1.8 candidate): `02_Infrastructure/worktask/common_charter.md`
- L-code inherit: L-316/L-317/L-318/L-319/L-320 (Session 81)

## 위반 = AX-002 동급

본 7 principles 위반은 process honesty (AX-002) 위반 동급으로 처리. 단 Phase 1/2/3 미도입 영역은 grace period (도입 전까지 warn only).
