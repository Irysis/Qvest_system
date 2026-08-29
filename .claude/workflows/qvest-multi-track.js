export const meta = {
  name: 'qvest-multi-track',
  description: 'QEPM 다중-track 병렬 alpha 리서치 — N 가설 fan-out → cross-comparison 통합 (Cycle 2 4-track 패턴 codify)',
  whenToUse: '한 theme에 대해 여러 alpha 가설/스펙을 병렬 탐색하고 4-way 비교가 필요할 때. args = {wt_id, tracks:[{tag,prompt}], cutoff}',
  phases: [
    { title: 'Alpha Tracks', detail: 'track별 alpha-research 병렬 spawn' },
    { title: 'Synthesize', detail: 'cross-comparison 통합 + 최강 track 선정' },
  ],
}

// args: { wt_id, tracks: [{tag, prompt}], cutoff }  (Q-Lead가 inline JSON으로 전달)
const wt = (args && args.wt_id) || 'WT-MULTI'
const tracks = (args && args.tracks) || []
const cutoff = (args && args.cutoff) || '2023-12-22'

const ALPHA_SCHEMA = {
  type: 'object',
  required: ['tag', 'rank_ic', 'icir', 'harvey_t_portfolio', 'dsr', 'ax001_v2_ratio', 'net_sr', 'turnover_yr', 'verdict'],
  properties: {
    tag: { type: 'string' },
    rank_ic: { type: 'number' }, icir: { type: 'number' },
    harvey_t_rankIC: { type: 'number' },
    harvey_t_portfolio: { type: 'number', description: 'portfolio-alpha 회귀 t (rank-IC t와 구분 — Cycle 2 교훈)' },
    dsr: { type: 'number' }, ax001_v2_ratio: { type: 'number' },
    net_sr: { type: 'number' }, turnover_yr: { type: 'number' },
    package_path: { type: 'string' },
    verdict: { type: 'string', description: 'PASS/REVISE/DROP + 근거' },
  },
}

phase('Alpha Tracks')
log(`${wt}: ${tracks.length} track 병렬 alpha-research (lockbox ${cutoff})`)

// 병렬 fan-out — 각 track 독립 alpha-research (PIT/role hook은 spawn agent에 그대로 발동. v8.2: codex hook 등록 해제)
const results = await parallel(tracks.map((t) => () =>
  agent(
    `WT ${wt} Track ${t.tag} — alpha-research. ${t.prompt}\n` +
    `제약: PIT lockbox ${cutoff} strict / 25 names (도훈 mandate 2026-05-29 20→25) / Σw=1 (v10: 비중 상한 폐지) / 15bps / AX-007 회피.\n` +
    `qvest-alpha-style 적용: economic_rationale + net-of-cost loss + μ̃ uncertainty + IC t-stat≠portfolio-alpha t 구분.\n` +
    `[AX 전제 — workflow agent엔 axiom_context_inject hook 미발동, 본 프롬프트가 명시] AX-002 PIT 정직성(우회=미래참조) / AX-001 v2 crisis 조건부 평가 / AX-007 multi-sleeve 예외 / AX-000 입증된 한계는 정직 보고. 전문 .claude/rules/axioms.md.\n` +
    `Self-Adversarial Challenge 의무(v8.2 — Codex Round 대체): finalize 직전 약점 ≥3건 자가 제기 → challenge_note.md 기록 → final. 산출: stage_artifacts/WT_${wt.replace(/-/g,'_')}_${t.tag}/ + alpha_package_${t.tag}.json.`,
    { label: `alpha:${t.tag}`, phase: 'Alpha Tracks', agentType: 'alpha-research', schema: ALPHA_SCHEMA }
  )
)).then((r) => r.filter(Boolean))

phase('Synthesize')
// 통합은 Q-Lead(메인)가 stage gate artifact로 — workflow는 raw 비교만 반환
const ranked = results.slice().sort((a, b) => (b.icir || 0) - (a.icir || 0))
log(`완료 ${results.length}/${tracks.length} track. ICIR 최강: ${ranked[0]?.tag} (${ranked[0]?.icir})`)

return {
  wt_id: wt,
  cutoff,
  tracks: results,
  ranking_by_icir: ranked.map((r) => ({ tag: r.tag, icir: r.icir, dsr: r.dsr, net_sr: r.net_sr, verdict: r.verdict })),
  note: 'cross-comparison 최종 판정 + Forge 진입 결정은 Q-Lead(메인)가 도훈 confirm 후. DSR/Harvey-portfolio가 binding gate.',
}
