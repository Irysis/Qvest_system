export const meta = {
  name: 'qvest-dossier-pipeline',
  description: 'QEPM 파이프라인 (v10) — 채택 alpha 1건을 risk→optimizer→forge 자동 진행 후 권위 등급(essence) 산출. Grade A 일 때만 Judge(PIT 전담) 스폰. BOOK 등록은 수동(도훈 confirm).',
  whenToUse: '탐색(alpha fan-out) 또는 강화 프로세스에서 후보가 정해진 뒤, 그 후보를 등급 판정까지 자동으로 완주시킬 때. args={wt_id, candidate_tag, n_trials_cumulative, overlay_sr_basis, incumbent_note}. 전제: alpha_package.json(canonical)이 해당 WT mailbox에 승격되어 있어야 함.',
  phases: [
    { title: 'Risk', detail: 'risk-research → Σ+tail+stress+crowding+style' },
    { title: 'Optimizer', detail: 'optimizer-research → weights (TO 11.0, long-only)' },
    { title: 'Forge', detail: 'forge → 통합 backtest + 권위 등급(essence A/B/C/F)' },
    { title: 'Judge', detail: 'Grade A 한정 — judge(PIT 전담) 검증 (v10)' },
    { title: 'Dossier', detail: 'escalation 집계 + BOOK 등록 권고 (등록은 수동)' },
  ],
}

// ── args (Q-Lead inline JSON 권장 — named 호출 args 취약 시 scriptPath 편집) ──
const wt = (args && args.wt_id) || 'WT-MISSING'
const tag = (args && args.candidate_tag) || 'CAND'
const nTrials = (args && args.n_trials_cumulative) || 1
const overlaySR = (args && args.overlay_sr_basis) || false
const incumbentNote = (args && args.incumbent_note) || 'STR_1715(consensus revision+Q07+M08+Q25+regime overlay) = BOOK 등록 1호(구 PG2).'
const stageDir = `stage_artifacts/WT_${wt.replace(/-/g, '_')}_${tag}`

// 공통 가드 prefix — workflow agent엔 Agent-matcher hook(axiom_context_inject) 미발동 → AX 명시.
// Write/Bash hook(constraint_enforcer / backtest_contract_audit)은 정상 발동.
const GUARD =
  `[전제] WT ${wt} candidate=${tag}. canonical handoff 이름 사용(alpha_package.json/risk_package.json/optimization_package.json/forge_package.json/judge_verdict.json — artifact-naming 정책).\n` +
  `제약: PIT C1~C15 strict (★v10 2026-08-29: lockbox 폐지 — 가용 데이터 전기간 사용, 반박 금지) / **long-only weights≥0 (도훈 mandate 2026-05-29 온리-롱 전용)** / max 25 names (도훈 mandate 20→25) / Σw=1 (v10: 비중 상한 폐지) / 유동성 2e8 / 15bps / **회전율 hard cap 11.0/yr** / 백테스트 자체합성 금지(PerformanceAnalytics/R-bridge).\n` +
  `[AX 전제 — workflow agent hook 미발동, 명시] AX-002 PIT 정직(우회=미래참조) / AX-001 v3 방어형 처분은 전기간 등급 단독 금지(defensive_score 계약) / AX-008 v2.0 결정 수치는 R 계약 산출만 인용(손계산·재구성 금지 · 독립 검증 = Judge) / AX-000 입증된 한계 정직보고. 전문 .claude/rules/axioms.md.\n` +
  `[정체성] 최정상급 퀀트 — 최신 수리통계·ML 적극, 과적합·데이터 스누핑에 냉소적(실증 성과 폄하는 금지). 모든 수치 결정에 근거 논문 원문 링크 필수(quant-identity.md).\n` +
  `Self-Adversarial Challenge 의무: finalize 직전 약점 ≥3건 자가 제기 → ACCEPT/PARTIAL/REBUTTAL 분류 → challenge_note.md 기록 → final. No Silent Override — 제약 완화/도달불가/충돌은 infeasibility_report로 surface(침묵 default 금지).\n` +
  `완료 시 tg_agent_brief 텔레그램 brief(한글 컨텍스트 첫섹션, 핵심kv 정량결과만, 약어 한글풀이, tg_send 직접금지).`

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
const FORGE_SCHEMA = { type: 'object', required: ['sharpe', 'cagr', 'mdd', 'bt_audit_status', 'essence_grade', 'summary'], properties: {
  sharpe: { type: 'number' }, cagr: { type: 'number' }, mdd: { type: 'number' }, turnover_yr: { type: 'number' },
  bt_audit_status: { type: 'string', description: 'PASS/FAIL — audit_bt_result' }, pit_clean: { type: 'boolean' },
  essence_grade: { type: 'string', description: 'A/B/C/F/NA — essence_score(bt_result) 권위 등급 (AX-008: 측정은 Forge 소관, authoritative_remeasure.json 산출)' },
  port_t: { type: 'number', description: 'portfolio_alpha_t_nw_lag3' }, summary: { type: 'string' } } }
const JUDGE_SCHEMA = { type: 'object', required: ['pit_pass', 'violations', 'summary'], properties: {
  pit_pass: { type: 'boolean', description: 'PIT C1~C15 전 축 clean 여부 — v10 Judge 는 PIT 전담(자본 심사 없음)' },
  violations: { type: 'array', items: { type: 'string' } },
  reproduction_match: { type: 'boolean', description: '엔진 재실행 등급 재현 일치' },
  lag1_cliff: { type: 'boolean', description: '신호 1개월 지연 시 성과 절벽 (동월 누출 의심)' },
  summary: { type: 'string' } } }

function failDossier(stage, obj) {
  return { wt_id: wt, candidate: tag, status: 'PIPELINE_HALTED', halted_at: stage, stage_result: obj,
    escalations: (obj && (obj.escalations || obj.infeasibility)) || [],
    note: `${stage} 단계 blocking → 후속 비용 절약 위해 중단. BOOK 미진입(자동 등록 없음). 원인 검토 후 재진입.` }
}

// ── Stage 1: Risk ──
phase('Risk')
log(`${wt}/${tag} QEPM 파이프라인 시작 (v10 — long-only, TO 11.0, 누적 trial ${nTrials})`)
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
  `weight 방법 자율비교(≥3, **long-only만** — long-short 금지). 방법 선택의 근거 논문 원문 링크 필수. ` +
  `**SR 2.5 도달 판단은 ${overlaySR ? '리스크 오버레이 적용 가정' : 'clean realized-monthly'} 기준으로 추정**. 도달 불가 시 AX-000 정직보고+infeasibility. ` +
  `종목 합산 ≤25(슬리브 조합 시에도 — 도훈 mandate 2026-05-29 20→25). portfolio CVaR 상한 설정.\n` +
  `산출물: qepm/mailbox/worktask/${wt}/optimization_package.json(+draft+challenge_note_optimizer.md) + ${stageDir}/weights.csv.`,
  { label: `opt:${tag}`, phase: 'Optimizer', agentType: 'optimizer-research', schema: OPT_SCHEMA })
if (!opt || opt.blocking) return failDossier('Optimizer', opt)

// ── Stage 3: Forge (백테 + 권위 등급 — v10: QEPM 의 종점은 등급 평가) ──
phase('Forge')
const forge = await agent(
  `${GUARD}\nforge. 3-package(alpha/risk/optimization) read-only 통합 → run_all.R + backtest. Pure function(target_weights/cov/alpha 수정 금지). ` +
  `bt_result 10-component(build_bt_result R-bridge) + audit_bt_result + **essence_score(selection_type 정직 기재) → authoritative_remeasure.json 산출, essence_grade 반환**(v10: QEPM 종점 = 등급 평가). ${overlaySR ? '오버레이 적용 시나리오 SR도 산출.' : ''}\n` +
  `산출물: qepm/mailbox/worktask/${wt}/forge_package.json + ${stageDir}/bt_result.rds + authoritative_remeasure.json.`,
  { label: `forge:${tag}`, phase: 'Forge', agentType: 'forge', schema: FORGE_SCHEMA })
if (!forge || forge.bt_audit_status === 'FAIL') return failDossier('Forge', forge)

// ── Stage 4: Judge — ★v10: Grade A 일 때만 스폰 (PIT 전담 검증) ──
let judge = null
if (forge.essence_grade === 'A') {
  phase('Judge')
  judge = await agent(
    `${GUARD}\njudge (v10 PIT 전담). Grade A 확정 전략의 PIT 검증만 수행 — 등급 재채점·자본 심사 금지.\n` +
    `검증 축: ①PIT C1~C15 코드 감사 ②detect_lookahead 독립 재실행 ③overlay/regime 신호 t-1 타이밍(C5) ④lag-1 스트레스(신호 1개월 지연 재측정 — 절벽 = 동월 누출 의심) ⑤재현 검증(엔진 재실행 → 등급 재현) ⑥n_trials/selection_type 정직성.\n` +
    `산출물: qepm/mailbox/worktask/${wt}/judge_verdict.json (schema judge_verdict_v2).`,
    { label: `judge:${tag}`, phase: 'Judge', agentType: 'judge', schema: JUDGE_SCHEMA })
  if (!judge) return failDossier('Judge', judge)
} else {
  log(`${tag} essence_grade=${forge.essence_grade} — Grade A 미달, Judge 미스폰(v10). 강화 프로세스 대상.`)
}

// ── Dossier 집계 (BOOK 미진입 — 자동 등록 없음) ──
phase('Dossier')
const escalations = [
  ...(risk.escalations || []), ...(opt.infeasibility || []),
  ...((judge && judge.violations) || []).map((v) => `judge_pit_violation:${v}`),
]
const bookReady = forge.essence_grade === 'A' && !!judge && judge.pit_pass && opt.constraints_ok && forge.bt_audit_status === 'PASS'
log(`${tag} dossier 완료. grade=${forge.essence_grade} judge_pit=${judge ? judge.pit_pass : 'N/A(미스폰)'} → book_ready=${bookReady}`)

return {
  wt_id: wt, candidate: tag, status: 'DOSSIER_COMPLETE',
  n_trials_cumulative: nTrials, overlay_sr_basis: overlaySR,
  risk: risk.summary, optimizer: opt.summary, forge: forge.summary, judge: judge ? judge.summary : 'NOT_SPAWNED (grade < A — v10)',
  key_metrics: { essence_grade: forge.essence_grade, port_t: forge.port_t, sharpe: forge.sharpe,
    sr_overlay_assumed: opt.sr_overlay_assumed, mdd: forge.mdd,
    net_sharpe: opt.net_sharpe, book_ir: opt.book_ir,
    turnover_yr: forge.turnover_yr, n_names: opt.n_names, style_return_cor_vs_str1715: risk.style_return_cor_vs_str1715 },
  escalations,
  book_ready: bookReady,
  book_boundary: '★ 본 워크플로우는 judge(PIT)까지만. BOOK 등록(book_registry.R::register_book_entry)은 Q-Lead+도훈 수동 confirm — 자동 등록 없음(v10: governor 폐지, BOOK 이 승계).',
  recommendation: bookReady
    ? `BOOK 등록 자격 충족(Grade A + PIT PASS). 도훈 confirm 후 register_book_entry 검토. escalation ${escalations.length}건 사전 검토 의무.`
    : (forge.essence_grade === 'A'
        ? `Grade A 이나 PIT 미통과 — 위반 수리 후 재측정·재검증(등급 무효 가능).`
        : `Grade ${forge.essence_grade} — 강화 프로세스 대상(1계층 ≤20회 / 2계층 무한). 원장에 attempt 기록.`),
}
