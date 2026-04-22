<!-- Qvest Shared Prefix — 모든 agent init이 상단에서 참조하는 단일 SOT -->
<!-- DO NOT duplicate this content into individual init files. Reference only. -->
<!-- 갱신 시 .cache/axiom_core.json ↔ CLAUDE.md §Axioms와 동기화 필수. -->
<!-- cache_control: stable prefix. ephemeral 1h breakpoint 권장 위치 (Anthropic API 호출 시). -->
<!-- 본 파일 변경 = prefix cache invalidation. 변경은 axiom 승격/폐기 시점만 허용. -->

<axioms level="0" immutable="true">
- **AX-000**: 한계란 없다. 불가능은 없다. 모든 목표는 달성 가능하다.
- **AX-001 v2**: 방어형 팩터는 조건부 성과로 평가한다. 전기간 SR/CAGR/MDD 기준 적용 금지 (Grade F 오판). 평가축: 위기 구간 crisis_alpha + Core 대비 MDD 완화 + bad/normal IC ratio. multi-sleeve 조건부 비중.
- **AX-002**: 하네스 내 성과만 유효하다. 프로세스 우회 = 판단의 미래참조 = C1 위반 동급.
- **AX-003** [empirical/negative] market=KR, family=value: EP_STANDALONE + LOW_TURNOVER value standalone 실패. 근거 L-132/135.
- **AX-004** [methodological/negative] market=KR, family=quality_profitability: GP·Cash-profitability single-signal long-only 구조적 실패. EXCLUSION: multi-axis quality composite(Novy-Marx GP + Piotroski + Ohlson + Q07) + multi-sleeve 내 Q07 defense sleeve는 scope 밖. 근거 L-133/134/139.
- **AX-005 v1.2** [methodological/negative] market=KR, family=defense, universe=top20_long_only: low-beta/Q07+D25/multi-source 4-axis composite 모두 구조적 실패. ICIR 0.74~0.94 강해도 MDD 77~94%. EXCLUSION은 necessary not sufficient (Gate13 signal-portfolio translation PASS 동시 충족 필수). 근거 L-136/140/165/166.
- **AX-007** [methodological/negative] roles=[defense, core_secondary], structure=single_sleeve_long_only_top20: signal-portfolio translation 메커니즘 단절. 예외 4종(multi-sleeve / long-short / 50+ 분산 / ML sizing + regime-conditional + AX-001 v2 crisis_alpha≥4/6). 근거 L-160/165/166.
- **AX-008** [methodological/process]: Verification Triangulation Mandate — Forge self-check 단독 검증 불충분. Forge + Codex + Architect 3-source 중 최소 2-source PASS 필수. Gate0 확장. 근거 L-159/167/168.

계층: AX-code(Lv0 공리) > PIT C1-C15(Lv1) > L-code(Lv2 교훈) > Signals(Lv3 가변). 위반 = 즉시 중단.
</axioms>

<pit_core level="0">
매 데이터 접근 전 3질문:
1. 이 데이터는 의사결정 시점에 알 수 있었는가?
2. 이후 결과가 판단에 영향을 미치지 않는가?
3. '괜찮다' 느끼는 이유가 결과를 이미 알기 때문은 아닌가?

핵심 규칙:
- C1: full-sample 통계 금지 (rolling/expanding만)
- C2: same-day circular 금지 (t-1 lag)
- C4: 재무제표 lag (연간→5월, 분기→45일)
- C5: overlay t-1, C9: VT/DD lag, C11: 데이터 시간축 검증
- C13: Z_Score_Aligned만 사용 (manual sign flip 금지)
- C14: IC usable_date <= sig_date, C15: load_month_factors() 경유

금지 합리화 표현 (자동 감지): "영향 미미", "관행적 허용", "보수적이면 괜찮다", "이미 반영되어 있을 것", "백테스트 기간이 길어 상쇄"
</pit_core>

<stage_order>
V6.0 순서: S0(Scout) → S1(Forge) → S2(Forge) → S3(Scout) → S4(auto) → S5/S6 → S7 → PG0~PG3.
- Forge는 Scout s0_record 없이 자체 가설 생성 금지.
- S3(직교성) + S4(한계기여) 산출물 없이 S6(Judge) 진입 불가.
- S4 완료 시 pipeline driver가 sg_determine_role() + sg_role_admission() 자동 호출.
- Stage skip 금지. sg_can_advance(factor_id, target) FALSE 반환 시 진행 금지.
- S5 진입 시 sg_generate_research_slate() 4슬롯 자동 생성.
</stage_order>

<s0_debate_consensus level="0" version="v55">
- 점수제 폐기. stance(APPROVE/APPROVE_CONDITIONAL/REVISE/REJECT) + veto_flag + critical_concerns/supporting_arguments 기반.
- Full 5인 또는 Compact 3인(QVEST_DEBATE_MODE=compact).
- 필수 역할: codex_critic(flag only, no veto) / risk_manager(veto: tail_risk) / governor(veto: admission_rule|gap_misaligned) / quant(veto: PIT|kr_empirical_hard_fail) / academic(veto: mechanism). Compact는 judge(veto: PIT) 대체 가능.
- S0_VERDICT 필수 필드: verdict, consensus_tier(UNANIMOUS/MAJORITY/MINORITY/DEADLOCK), consensus_tally{approve,approve_conditional,revise,reject,veto_count}, final_stances(role별 r1/final/stance_change/veto_flag), transcript.rounds(R1+R2 이상), consensus_points + unresolved_disputes, debaters[N].
- Q-Lead가 debaters에 포함되면 REJECT. Q-Lead는 집계만.
- 세부: @.claude/skills/s0-debate/SKILL.md, @02_Infrastructure/hooks/s0_verdict_router.sh
</s0_debate_consensus>

<telegram_protocol>
- 이모지 필수 + 에이전트 태그 ([Q-Lead]/[Scout]/[Forge]/[Judge]/[Governor]/[Risk Mgr]/[Alert])
- 성과 포맷: Grade/Score/SR/CAGR/MDD + 강점/약점 각 1줄
- 백테스트 결과 = equity_curve.png + annual_returns.png 필수 (tg_send_photo())
- API: source("02_Infrastructure/telegram/telegram_notify.R") 후 tg_send() + tg_send_photo()
- 한글 기본. 줄바꿈·섹션·들여쓰기.
</telegram_protocol>

<parallel_tool_calls>
독립 작업 2건 이상이면 Agent 도구로 병렬 스폰. RAM 80% 이하일 때만 추가 스폰.
코드 작성과 실행 분리: 메인이 코드 작성, Agent로 실행을 백그라운드 스폰, 메인은 즉시 다음 작업.
순차 대기(코드작성→실행→10분대기→다음) 패턴 금지.
</parallel_tool_calls>

<production_constraints>
- 종목수 ≤ 20 (슬리브 조합 포함 최종 포트폴리오 기준)
- 유동성 필터 ≥ 2억원 (LIQ_THRESHOLD = 2e8)
- 롱온리 기본. 백테스트 커미션 15bps.
- 05_Production/ 수정 금지 (promote_to_production()만 예외). 01_Literature/ read-only.
</production_constraints>
