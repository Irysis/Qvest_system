export const meta = {
  name: 'qvest-dossier-pipeline',
  description: 'Full-pipeline dossier — 채택 alpha 1건을 risk→optimizer→forge→judge 자동 진행해 admission-ready dossier 생성. governor admit(book_state 쓰기)은 정지(수동+도훈 confirm). 모든 escalation surface.',
  whenToUse: '탐색(alpha fan-out)으로 채택 후보가 정해진 뒤, 그 후보를 판정-직전까지 자동으로 완주시킬 때. args={wt_id, candidate_tag, n_trials_cumulative, overlay_sr_basis, incumbent_note}. 전제: alpha_package.json(canonical)이 해당 WT mailbox에 승격되어 있어야 함.',
  phases: [
    { title: 'Risk', detail: 'risk-research → Σ+tail+stress+crowding+style' },
    { title: 'Optimizer', detail: 'optimizer-research → weights (TO 11.0, long-only)' },
    { title: 'Forge', detail: 'forge → 통합 backtest (bt_result 10-component)' },
    { title: 'Judge', detail: 'judge → Gate 0~18 + PIT + DSR(누적 trial)' },
    { title: 'Dossier', detail: 'escalation 집계 + admission 권고 (admit은 수동)' },
  ],
}

// ── args (Q-Lead inline JSON 권장 — named 호출 args 취약 시 scriptPath 편집) ──
const wt = (args && args.wt_id) || 'WT-MISSING'
const tag = (args && args.candidate_tag) || 'CAND'
const nTrials = (args && args.n_trials_cumulative) || 1
const overlaySR = (args && args.overlay_sr_basis) || false
const incumbentNote = (args && args.incumbent_note) || 'STR_1715(consensus revision+Q07+M08+Q25+regime overlay) 100% PG2 incumbent.'
const stageDir = `stage_artifacts/WT_${wt.replace(/-/g, '_')}_${tag}`

// 공통 가드 prefix — workflow agent엔 Agent-matcher hook(axiom_context_inject) 미발동 → AX 명시.
// Write/Bash hook(sequence_enforcer / constraint_enforcer / backtest_contract_audit)은 정상 발동. (v8.2: codex_round_pre_enforcer 등록 해제 — Codex Round 폐지)
const GUARD =
  `[전제] WT ${wt} candidate=${tag}. canonical handoff 이름 사용(alpha_package.json/risk_package.json/optimization_package.json/forge_package.json/judge_verdict.json — artifact-naming 정책).\n` +
  `제약: PIT lockbox ${cutoff()} strict / **long-only weights≥0 (도훈 mandate 2026-05-29 온리-롱 전용)** / max 25 names (도훈 mandate 20→25) / Σw=1 (v10: 비중 상한 폐지) / 유동성 2e8 / 15bps / **회전율 hard cap 11.0/yr** / 백테스트 자체합성 금지(PerformanceAnalytics/R-bridge).\n` +
  `[AX 전제 — workflow agent hook 미발동, 명시] AX-002 PIT 정직(우회=미래참조) / AX-001 v2 crisis 조건부 / AX-005 KR defense low-vol single-sleeve long-only 실패 / AX-007 multi-sleeve 예외 / AX-008 Verification Triangulation / AX-000 입증된 한계 정직보고. 전문 .claude/rules/axioms.md.\n` +
  `Self-Adversarial Challenge 의무(v8.2 — Codex Round 대체): finalize 직전 약점 ≥3건 자가 제기 → ACCEPT/PARTIAL/REBUTTAL 분류 → challenge_note.md 기록 → final. No Silent Override — 제약 완화/도달불가/충돌은 infeasibility_report로 surface(침묵 default 금지).\n` +
  `완료 시 tg_agent_brief 텔레그램 brief(한글 컨텍스트 첫섹션, 핵심kv 정량결과만, 약어 한글풀이, tg_send 직접금지).`

function cutoff() { return (args && args.cutoff) || '2023-12-22' }

// ── 단계별 차단 판단용 schema (핵심 게이팅 필드만) ──
const RISK_SCHEMA = { type: 'object', required: ['recommended_estimator', 'condition_number', 'tail_tdc', 'blocking', 'summary'], properties: {
  recommended_estimator: { type: 'string' }, condition_number: { type: 'number' }, tail_tdc: { type: 'number' },
  crisis_confirmed: { type: 'boolean' }, style_return_cor_vs_str1715: { type: 'number' },
  blocking: { type: 'boolean', description: 'PIT C-위반/Σ ill-posed 등 진행 불가 시 true' }, escalations: { type: 'array', items: { type: 'string' } }, summary: { type: 'string' } } }
const OPT_SCHEMA = { type: 'object', required: ['method_selected', 'n_names', 'turnover_yr', 'net_sharpe', 'constraints_ok', 'blocking', 'summary'], properties: {
  method_selected: { type: 'string' }, n_names: { type: 'number' }, turnover_yr: { type: 'number' },
  net_sharpe: { type: 'number' }, book_ir: { type: 'number' }, sr_2_5_reachable: { type: 'boolean' },
  sr_overlay_assumed: { type: 'number', description: 'overlay 적용 가정 시 추정 SR' },
  constraints_ok: { type: 'boolean', description: 'long-only/≤25/Σw=1/TO≤11 전부 충족 (v10: 비중 상한 폐지)' },
  blocking: { type: 'boolean' }, infeasibility: { type: 'array', items: { type: 'string' } }, summary: { type: 'string' } } }
const FORGE_SCHEMA = { type: 'object', required: ['sharpe', 'cagr', 'mdd', 'bt_audit_status', 'summary'], properties: {
  sharpe: { type: 'number' }, cagr: { type: 'number' }, mdd: { type: 'number' }, turnover_yr: { type: 'number' },
  bt_audit_status: { type: 'string', description: 'PASS/FAIL — audit_bt_result' }, pit_clean: { type: 'boolean' }, summary: { type: 'string' } } }
const JUDGE_SCHEMA = { type: 'object', required: ['verdict', 'pit_pass', 'dsr', 'harvey_t_portfolio', 'gates_failed', 'summary'], properties: {
  verdict: { type: 'string', description: 'JUDGE_PASSED/JUDGE_FAILED' }, pit_pass: { type: 'boolean' },
  dsr: { type: 'number', description: `누적 N_trials=${nTrials} 반영 deflate` }, harvey_t_portfolio: { type: 'number' },
  mdd: { type: 'number' }, turnover_yr: { type: 'number' }, gates_failed: { type: 'array', items: { type: 'string' } },
  graduation_pass: { type: 'boolean' }, summary: { type: 'string' } } }

function failDossier(stage, obj) {
  return { wt_id: wt, candidate: tag, status: 'PIPELINE_HALTED', halted_at: stage, stage_result: obj,
    escalations: (obj && (obj.escalations || obj.infeasibility)) || [],
    note: `${stage} 단계 blocking → forge/judge 비용 절약 위해 중단. governor 미진입(자동 admit 없음). 원인 검토 후 재진입.` }
}

// ── Stage 1: Risk ──
phase('Risk')
log(`${wt}/${tag} dossier 파이프라인 시작 (long-only, TO 11.0, 누적 trial ${nTrials})`)
const risk = await agent(
  `${GUARD}\nrisk-research. 입력 alpha_package.json(canonical, candidate ${tag}) + ${stageDir}/alpha_scores.parquet.\n` +
  `산출: Σ(Sample/LW/Gerber 비교+조건수+추천) + tail(TDC<0.30) + stress(KR 2008/2020/2022 위기) + crowding(crowding_score_per_factor) + style(FF5+BAB+momentum, vanilla STR_1715 대비 **신호 cor와 realized 수익률 cor 둘 다**). ${incumbentNote}\n` +
  `산출물: qepm/mailbox/worktask/${wt}/risk_package.json(+draft+challenge_note_risk.md) + ${stageDir}/covariance.parquet.`,
  { label: `risk:${tag}`, phase: 'Risk', agentType: 'risk-research', schema: RISK_SCHEMA })
if (!risk || risk.blocking) return failDossier('Risk', risk)

// ── Stage 2: Optimizer ──
phase('Optimizer')
const opt = await agent(
  `${GUARD}\noptimizer-research. 입력 alpha_package.json + risk_package.json + ${stageDir}/covariance.parquet.\n` +
  `weight 방법 자율비교(≥3, **long-only만** — long-short 금지). multi-sleeve blend(${incumbentNote})로 book 기여 정량화. ` +
  `**SR 2.5 도달 판단은 ${overlaySR ? 'PG2 리스크 오버레이(AR_on_M4) 적용 가정' : 'clean realized-monthly'} 기준으로 추정**(직교성은 vanilla 1715). 도달 불가 시 AX-000 정직보고+infeasibility. ` +
  `종목 합산 ≤25(슬리브 조합 시에도 — 도훈 mandate 2026-05-29 20→25). portfolio CVaR 상한 설정.\n` +
  `산출물: qepm/mailbox/worktask/${wt}/optimization_package.json(+draft+challenge_note_optimizer.md) + ${stageDir}/weights.csv.`,
  { label: `opt:${tag}`, phase: 'Optimizer', agentType: 'optimizer-research', schema: OPT_SCHEMA })
if (!opt || opt.blocking) return failDossier('Optimizer', opt)

// ── Stage 3: Forge ──
phase('Forge')
const forge = await agent(
  `${GUARD}\nforge. 3-package(alpha/risk/optimization) read-only 통합 → run_all.R + backtest. Pure function(target_weights/cov/alpha 수정 금지). ` +
  `bt_result 10-component(build_bt_result R-bridge) + audit_bt_result. ${overlaySR ? 'PG2 오버레이 적용 시나리오 SR도 산출.' : ''}\n` +
  `산출물: qepm/mailbox/worktask/${wt}/forge_package.json + ${stageDir}/bt_result.rds.`,
  { label: `forge:${tag}`, phase: 'Forge', agentType: 'forge', schema: FORGE_SCHEMA })
if (!forge || forge.bt_audit_status === 'FAIL') return failDossier('Forge', forge)

// ── Stage 4: Judge ──
phase('Judge')
const judge = await agent(
  `${GUARD}\njudge. Gate 0~18 + PIT C1~C15 독립 재검증 + multi-objective 8지표 + **DSR은 누적 N_trials=${nTrials} 반영 deflate**. ` +
  `forge bt_result(realized portfolio alpha)를 authoritative로. rank-IC t와 portfolio-alpha t 구분(Cycle 2 교훈). lockbox 접근(audit 기록).\n` +
  `산출물: qepm/mailbox/worktask/${wt}/judge_verdict.json.`,
  { label: `judge:${tag}`, phase: 'Judge', agentType: 'judge', schema: JUDGE_SCHEMA })
if (!judge) return failDossier('Judge', judge)

// ── Dossier 집계 (governor 미진입 — 자동 admit 없음) ──
phase('Dossier')
const escalations = [
  ...(risk.escalations || []), ...(opt.infeasibility || []),
  ...(judge.gates_failed || []).map((g) => `judge_gate_fail:${g}`),
]
const admitReady = judge.verdict === 'JUDGE_PASSED' && judge.pit_pass && opt.constraints_ok && forge.bt_audit_status === 'PASS'
log(`${tag} dossier 완료. judge=${judge.verdict} pit=${judge.pit_pass} DSR=${judge.dsr} → admit_ready=${admitReady}`)

return {
  wt_id: wt, candidate: tag, status: 'DOSSIER_COMPLETE',
  n_trials_cumulative: nTrials, overlay_sr_basis: overlaySR,
  risk: risk.summary, optimizer: opt.summary, forge: forge.summary, judge: judge.summary,
  key_metrics: { sharpe: forge.sharpe, sr_overlay_assumed: opt.sr_overlay_assumed, mdd: forge.mdd,
    net_sharpe: opt.net_sharpe, book_ir: opt.book_ir, dsr: judge.dsr, harvey_t_portfolio: judge.harvey_t_portfolio,
    turnover_yr: forge.turnover_yr, n_names: opt.n_names, style_return_cor_vs_str1715: risk.style_return_cor_vs_str1715 },
  escalations,
  admit_ready: admitReady,
  governor_boundary: '★ 본 워크플로우는 judge까지만. governor admit(book_state.json 쓰기)은 Q-Lead+도훈 수동 confirm — 자동 admit 없음(AX-002/AX-008 + 비가역 자본 게이트 보호).',
  recommendation: admitReady
    ? `admission 자격 충족. 도훈 confirm 후 governor 수동 admit 검토. escalation ${escalations.length}건 사전 검토 의무.`
    : `admission 부적격(judge ${judge.verdict}). incumbent retain. escalation/gate_fail 검토 후 재설계 여부 결정.`,
}
