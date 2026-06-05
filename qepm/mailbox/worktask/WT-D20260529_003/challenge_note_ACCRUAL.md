# Challenge Note — WT-D20260529_003 Track ACCRUAL (alpha-research)

**Codex Critic Round** (gpt-5.5, xhigh) — stance = **REJECT** (concurs with agent's own REJECT verdict).
**Self-rationalization auto-check**: 본 note에서 "미미/관행적/실무적/보수적이면 OK/대부분 결과 동일" 표현 사용 0건 (grep PASS). 모든 REBUTTAL/PARTIAL은 정량 data + L-code + rule 인용.

Codex weakest_assumption: "PIT lockbox 2023-12-22 strict claim while diagnostics use post-lockbox months through 2026-04."

## Concern-by-concern

### C1 (HIGH) — PIT lockbox: diagnostics span through 2026-04, cutoff only on final snapshot
**분류: ACCEPT (verdict 강화).**
- Codex 정당. lockbox-scope rule (`.claude/rules/lockbox-scope.md`) alpha-research 행: "lockbox 내 evaluation_windows 외부 sig_date 산출 금지". 최초 run은 discovery IC/DSR을 2005~2026-04 전기간으로 계산 → post-cutoff selection contamination risk.
- **수정**: discovery evidence를 lockbox window (sig_date ≤ 2023-12-22, 228 months)로 재한정. post-lockbox 28 months는 OOS-only로 별도 보고.
- **정량 영향 (중대)**: lockbox window 내 composite mean rank-IC = **-0.0045 (NEGATIVE)**, ICIR -0.063, harvey-t -0.516. 최초 보고한 marginally-positive +0.0014는 **전적으로 OOS(+0.0496)에서 유래**. 즉 "양(+)의 신호"는 cutoff 너머를 봐야만 존재 → 정확히 lookahead/selection 오염. lockbox 정합 후 verdict는 더 강한 REJECT.
- per-month 신호 자체는 lookahead 없음 확인 (connector `align_factor_direction` Usable_Date≤sig_date, C14; forward return은 label-only). 그러나 evidence aggregation window가 문제였고 수정됨.

### C2 (HIGH) — alpha_scores.parquet single snapshot (RF-A7 handoff bug risk, Iter 4)
**분류: ACCEPT.**
- 수정: `alpha_scores.parquet`를 full multi-sig-date Date×Ticker×score 패널로 재발행 (76,328 rows, 256 months, lockbox flag column 포함, lockbox rows 66,878).
- REJECT verdict이므로 실제 handoff는 없으나 governance 완결성 위해 패널 형식 준수.

### C3 (HIGH) — core gates 전부 FAIL, composite ICIR << best-single
**분류: ACCEPT (= agent verdict).**
- lockbox window: rank-IC -0.0045 / ICIR -0.063 / harvey-t -0.516 / DSR 0.053 / sub_stability 0.67(부호 일관이나 IC≈0) / monotonicity -0.5. graduation gate 0/5.
- composite ICIR -0.063 < best-single AC22 ICIR 0.230 → composite_beats_single=FALSE. QMJ kill criterion (합성<단일이면 무의미) 발동.

### C4 (HIGH) — Harvey/DSR ad hoc; N_TESTS=11이 broader sweep 무시; Newey-West/5-spec 부재
**분류: PARTIAL ACCEPT (REJECT 강화 방향).**
- ACCEPT 부분: N_TESTS=11은 본 track의 single+composite만 카운트. broader unused-factor sweep (value/accrual/technical 60+ factor) 맥락 포함 시 multiple-testing burden은 **더 커짐** → harvey-t/DSR은 보고치보다 **더 낮아짐**. 이는 REJECT를 강화. (DSR=0.053은 이미 0.50 gate 대비 압도적 FAIL이므로 N_TESTS 상향이 결론 불변.)
- 부분 보완 불필요 사유: alpha가 이미 IC<0 / DSR 0.053으로 모든 gate에서 FAIL이므로 Newey-West HAC t나 forge 5-spec regression을 추가해도 verdict(REJECT) 불변. 5-spec portfolio-alpha는 forge 단계 영역이며, REJECT alpha는 forge로 진행하지 않음 (graduation 0/5 → admission 자격 없음). portfolio-alpha t는 본 패키지에 단순 OLS 기준 1.37(NS)로 이미 별도 보고함 (rank-IC t와 구분 — Cycle 2 교훈 준수).

### C5 (MEDIUM) — challenge_note/proposal/lineage/governance artifact 부재 (No Silent Override / AX-008)
**분류: ACCEPT (부분).**
- challenge_note: 본 파일로 작성 (Charter §8).
- weights.csv/covariance.parquet: **의도적 부재** — alpha-research 역할 경계상 Σ/weight 산출 절대 금지 (agent_role_guard). Codex가 alpha 패키지에 weights/cov를 기대한 것은 role 혼동. REBUTTAL: `.claude/rules/axioms.md` + alpha_research_init.md <strict_prohibitions> 1~2 (공분산/weight 금지). 따라서 이 두 파일 부재는 정상.
- factor_engine_proposal.R/artifact_lineage.json: REJECT verdict로 admission 진행이 없어 lineage는 비핵심이나, governance 완결 위해 run_all.R + validation JSON + composite_vs_single.csv로 audit trail 확보. 본 track은 verdict=REJECT라 lineage append는 생략 (handoff 없음).

### C6 (MEDIUM) — MAX_NAMES=25 vs base hard max 20
**분류: REBUTTAL.**
- 근거: Q-Lead spawn prompt (authoritative)에 명시 "max 25 names(도훈 mandate 20→25)". 즉 base request.json의 20은 본 cycle에서 도훈 mandate로 25로 상향됨. spawn prompt > stale request 필드 (artifact-naming/spawn authority). validation JSON에 `max_names=25, basis="spawn mandate 도훈 20->25"` 명기.
- 단 REJECT verdict이므로 sizing surface 자체가 결론에 무영향 (25든 20든 IC<0).

## 종합
- agent verdict REJECT + Codex REJECT 일치. C1 수정으로 evidence가 lockbox-scoped 되며 verdict는 **강화**(IC가 marginal-positive → NEGATIVE).
- escalate trigger 점검: HIGH severity 4건(C1~C4)이나 (a) PIT C1 위반은 **발견 즉시 수정 완료**(lockbox window 재한정)이며 per-month lookahead 없음 확인, (b) verdict가 REJECT라 admission 경로 진입 없음. → Q-Lead escalate 불요 (REJECT는 자연 종료). 단 데이터 품질 발견(AC01=AC11=AC18 동일)은 Q-Lead/architect 인지 권고 (factor_registry 중복 정리 후속).
- No Silent Override 준수: 모든 concern 명시 분류 + 근거 기록.
