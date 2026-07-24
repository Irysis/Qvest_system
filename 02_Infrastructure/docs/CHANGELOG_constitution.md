# Qvest 헌법 변경 이력 (CLAUDE.md에서 분리, 2026-06-10 P2 다이어트)

> CLAUDE.md는 "현재 유효한 헌법"만 담는다. 버전 연혁·릴리스 상세는 본 파일이 SOT.
> 최신 릴리스 상세: `qvest_v8_3_alpha_discovery_sot.md` (v8.3) · `qvest_v8_1_sot.md` (v8.1) · `qvest_v8_0_upgrade_plan.md` (v8.0)

## Release Status (v6.4.0 → v8.3)

| Release | 일자 | 핵심 |
|---|---|---|
| ✅ **v8.3 + Fable 5 정합 패치** | 2026-07-24 | Fable 5 하네스 전수 감사(57-agent 워크플로우 + 2-렌즈 적대검증, finding 115 = keep 45/변경 70) — 도훈 의뢰 "Fable 5 정합 + 과잉 훅/스킬/프롬프트 비판 점검". **모델**: 세션 = `claude-fable-5`, 에이전트 `model: opus` 핀 11종 전제거(무핀=상속, 폴백=한도 시 opus) · caching.md 전면 재작성(1h TTL·≤270s wakeup 폐기·TeamCreate/Codex 절 삭제). **훅**: 주입형 fail-open 하드게이트 4종 env-경유 수리 · 전달 0 훅 6종 additionalContext 복원(0ab8b039 회귀) · ★axiom_context_inject SyntaxError 수리(07-13 이후 Agent 공리주입 침묵 결손) · Read/W·E 조기-exit(비매치 Read 0.8→0.16s) · sr_provenance_pre_certifier dispatch 해제(no-op 실증) · milestone push 브랜치 버그 → 등록 48 distinct(직접 32+라우터 16), battery **11/11 PASS**. **스킬**: telegram-protocol 스텁·worktask 구스킬 삭제, style 스킬 게이트수치·DPL 광고 현행화, MG changelog 8.3KB·qvest.md Version 8KB 이관(autoload 다이어트). 보고서 `04_Research/01_reports/fable5_harness_audit_20260724.md`. **당일 도훈 승인·실행: C1**(codex 유령 플러그인 해제 — 미설치 실증, DEPRECATION.md 동시 개정) · **C5**(CLAUDE.md 역사 블록 → 본 파일 "이관 아카이브", 24.2→21.8KB) · **C6**(_shared_prefix 중복 스텁화 21.9→15.2KB — answer_principles/backtest_contract 포인터화·stage_order/s0_debate 삭제·telegram v7 스텁, health Hard 0). **C2~C4·C7~C10도 07-25 도훈 일괄 승인·실행** — C2 Read 훅 2건·C9 SubagentStop 해제(→ 등록 45 distinct = 직접 29+라우터 16) · C10 milestone legacy 레인 제거 · C7 exec/mon opus 재핀(예외 2종) · C3 skillOverrides(off 2+user-invocable 3 스텁) · C4 inverse-miner 재작성 · C8 스케줄러 opus 폴백. battery 11/11·harness_health 27/27. **C1~C10 전량 실행 — 감사 큐 소화**. |
| ✅ **v8.3** | 2026-07-10 | 알파 발굴 중심 재편 (도훈 mandate "실제 알파를 발굴하기 위한 목적으로 아키텍처 재편"). 5축 병렬 조사 → 마찰점 F1~F10 → move M1~M11: **M1** alpha 단계 selection_objective에 canonical_port_t 1급 추가(IC advisory 강등, stale 졸업기준 measurement-graduation §3 정합화) · **M2** canonical_screen_bt에 diag_ew_universe/diag_cap_tier 비파괴 진단(cap-w HARD 권위 불변) · **M5** 상설 frontier 큐 `06_Registry/alpha_frontier_queue.json` · **M6** hypothesis_index in-flight WT 인덱싱 · **M7** 주입면 현행화(settled-neg frontier 광고 제거+revival 주입) · **M8 경량** DPL_FEATURE 발급 중단·FR_RCMA 조건부화 · **M9** cluster_extractor 스키마 보존 · **M4** 인입 체인 백로그 합류+침묵정지 경보화. 불변: HARD 3종·6-agent·Production Constraints·governor 수동. 동반: 텔레그램 v7(비전공자 3장치, 전문용어 유지). SOT `qvest_v8_3_alpha_discovery_sot.md`. |
| ✅ **v8.2** | 2026-06-30 | Codex Critic Round 제거 — Opus 4.8 자체 적대검증(self-adversarial challenge)으로 중복, AX-008 Codex→Self-Adversarial 치환(3-source 2/3 불변). QEPM 5단계 draft→codex→challenge_note→final → in-agent self-adversarial. 자산 archive(`_archive_codex_round_v8_2/`) + `qvest-codex-round` skill DELETED. S0 Debate codex·RAMP Codex·codex CLI 플러그인은 별개 유지. |
| ✅ **v8.1.1** | 2026-06-10 | 완벽 수리 + P2 구조 개편. OneDrive canonical 단일화(도훈 mandate) · hook 47/47 부활 · Python/arrow/codex 체인 복구 · env 3중 안전망(QM_ROOT/QVEST_PY/.Renviron) · 헌법모순 일소(max25/TO11 전 계층) · 게이트 2계층(screening tier 신설) · rules autoload 16→6 다이어트 · axiom harvest 백필(corpus 95). |
| ✅ **v8.1.0** | 2026-06-05 | 3-Mode 헌법(각자 평가·자가발전) + 실측-only 거버넌스 + register_module 자동흐름 + Axiom r7 복원. |
| ✅ **v8.0.0** | 2026-05-29 | R+Python 1급 · SR 2.5 · measurement-graduation(WS1/2/3) · agent effort · Dynamic Workflow. |
| ✅ **v7.2.1** | 2026-05-02 | Memory Knowledge Hardening. Axiom JSON SOT (8 active) + memory_health 12-check + 15 readiness + auto-push hook. 도훈 audit 32 critical 모두 반영. |
| ✅ **v7.2.0** | 2026-05-02 | v8 readiness gate 14-check write mode strict PASS + CHANGELOG + 3-day soak. |
| ✅ **v7.1.0-lite** | 2026-05-02 | Solo Operator productivity 5 sprint (qvest_search + qvest_wt + INDEX.md + 3 workflow examples). 15 atomic commits. |
| ✅ **v7.0.1** | 2026-05-02 | 도훈 흠 4건 fix (synthetic cleanup / cert_rules data layer / harness_health hook 제거 / qvest_observe error masking). |
| ✅ **v7.0.0** | 2026-05-02 | Hardening 7 sprint. "검증 가능한 소프트웨어 커널" — 우회 불가능한 실행 계약. 14 schema + sm_validated_advance + events.jsonl + qvest_observe + legacy_write_block. E2E 12/12 PASS. |
| ✅ **v6.4.0** | 2026-05-01 | Harness Kernel Stabilization. Sprint 0+1+2+3 9-phase. Codex 3중 장치 + 5 Cert + State Machine. |

**검증 기록**: v7.2.1 strict run (2026-05-02, 구 WSL 머신): 30/30 hooks · 15/15 readiness · memory_health hard 0. **v8.1.1 (2026-06-10, 현 머신)**: hook 47/47 + 차단 4종 실증 · readiness pass 12/fail 0 · bootstrap BOOT_FAILS=0 · memory_health hard 0 (HARD_7 신설 포함).

**v8 후속 (이연)**:
- v7.3 candidate: AX-002/003/004/005 advisory → block 강화 / AX-007/008 hook hard-block 검토
- v7.x ext: SQLite event DB (현 JSONL fallback) / Daily brief Telegram SLO / Dashboard Shiny UI
- v8.x: qvest_hook_router 단일 진입 전환(이벤트당 1 spawn — 1주 soak 후), daily_refresh 구조 전환

## 변경 이력 (상세)

- **v8.3** — 2026-07-10 — 알파 발굴 중심 재편 (도훈 mandate). 진단: 인입 고갈(논문 큐 empty + 헤드리스 claude 지출한도 침묵 정지) · IC-first 선별(전이 벽 부정합) · cap-w 벤치 monoculture(아티팩트 기각) · screen-tier/지식 환류 단절. 이행: worktask schema/guard/prompt PORT_t-정합 + canonical_screen_bt dual-basis 진단 + frontier 큐 + hypothesis_index in-flight + inject 현행화 + 인입 경보화 + hurdle_gate dead 라벨 정리 + 텔레그램 v7. 게이트·제약·6-agent 불변. SOT `qvest_v8_3_alpha_discovery_sot.md` (M3/M10/M11 등 staged 항목 포함).
- **v8.2** — 2026-06-30 — Codex Critic Round 제거 (도훈 mandate). QEPM 파이프라인 외부 Codex 적대검증을 폐지하고 메인 에이전트 Opus 4.8 자체 적대검증(self-adversarial challenge)으로 통합 — 중복 제거. AX-008 Verification Triangulation의 source를 `Forge + Codex + Architect` → `Forge + Self-Adversarial + Architect`로 치환(3-source 중 2/3 PASS 불변). 연계: settings.json 훅 3개 등록 제거 · state_transitions.json `codex_critic_response` required 제거 · 6 agent 정의 self-adversarial 전환 · `qvest-codex-round` skill DELETED · 스크립트/프롬프트 archive(`02_Infrastructure/hooks/_archive_codex_round_v8_2/` · `02_Infrastructure/prompts/_archive_codex_round_v8_2/`) · `codex-round.md` = DEPRECATED 스텁. **유지(별개 시스템)**: S0 Debate codex · RAMP "Codex"(역할명) · enabledPlugins `codex@openai-codex`(S0/RAMP codex CLI). inventory SOT: `00_Lawbook/DEPRECATION.md`.
- **v8.1.1** — 2026-06-10 — 완벽 수리(아키텍처 전수 감사 → hook 전멸·메모리 단절·인터프리터 전멸 복구) + P2 구조 개편(게이트 2계층 / rules 다이어트 / 측정 사다리 / axiom 3축 충전 / MCP 재구축). 커밋 95ad9513 · 93da0bbf 외.
- **v8.1.0** — 2026-06-05 — 3-Mode 헌법 승격 + alpha-search 표준(논문 완전 복제·K200∪KQ150·2005~) + bootstrap 패치.
- **v8.0.0** — 2026-05-29 — Axiom 엔진 리뉴얼(r7 복원) + 측정 무결성 + Graduation 허들 재설계.
- **v7.2.1** — 2026-05-02 Session 76 — Memory Knowledge Hardening release (도훈 audit 32 critical 반영). Axiom JSON SOT (active 8건) + memory_health 12-check + 15 readiness + auto-push Stop hook. 신규 SOT `qvest_v7_2_1_sot.md` 발행. L-273~L-275.
- **v7.2.0** — 2026-05-02 — v8 readiness gate 14 check write mode strict PASS + CHANGELOG v7.2.0 entry + 3-day soak.
- **v7.1.0-lite** — 2026-05-02 — Solo Operator productivity (qvest_search + qvest_wt + INDEX.md + 3 examples). 15 atomic commits.
- **v7.0.1** — 2026-05-02 — Hardening patch (도훈 흠 4건 fix).
- **v7.0.0** — 2026-05-02 — Hardening 7 sprint release. "검증 가능한 소프트웨어 커널" 패러다임 (Codex 외부 평가 "SW 아키텍처 약함" → 우회 불가능한 실행 계약). L-272.
- **v6.4.0** — 2026-05-01 Session 75 — Harness Kernel Stabilization release. Sprint 0+1+2+3 9-phase. Codex 3중 장치 + 5 Cert + State Machine + dry-run 30/30 + E2E 10/10. L-269~L-271.
- **v6.4 Sprint 1** — 2026-05-01 Session 75 — Active SOT 단일화 + CLAUDE.md 경량화 (436 → ~270 lines) + skills/rules 8 신규.
- **v6.3.3** — 2026-05-01 — v6.0 Codex Critic Round 3중 장치 영구 정착 (L-269)
- **v6.3.2** — 2026-05-01 — Cert Auto-Issuance Paths 명문화 + Layer 4 deferred
- **v6.31** — 2026-04-28 — Charter v1.2 §10 Certification System
- **v6.0** — 2026-04-23 — QEPM 3-Agent WorkTask 도입
- **v5.5** — 2026-04-19 — v55 strict
- **v5.3** — 2026-04-13 — v53 TeamCreate + Hook 17종

(구 plan 참조였던 `/home/quant/.claude/plans/nifty-tickling-hinton.md`는 WSL 시대 경로 — 도달 불가, 내용은 v6.4 SOT에 흡수됨.)

---

## 이관 아카이브 (2026-07-24 도훈 승인 C5 — CLAUDE.md 역사 블록 다이어트, 원문 verbatim 보존)

> CLAUDE.md "헌법만" 원칙(2026-06-10 P2) 정합 — 아래 블록들은 CLAUDE.md에서 본 파일로 이관되고 본문에는 포인터만 남음. 내용 무손실.

### 계보 (구 CLAUDE.md 표기)

v6.4.0 → v7.0.0 → v7.0.1 → v7.1.0-lite → v7.2.0 → v7.2.1 → v8.0.0 → v8.1.0 → v8.2 → **v8.3** (현재 active)

### v8.1 핵심 (구 CLAUDE.md 블록 — 3-Mode 정립 + 실측-only + 모듈 자동흐름, 도훈 mandate 2026-06-05)

- **3-Mode 헌법**: alpha-search 제1원칙(**논문 완전 복제** + 유니버스 K200∪KQ150 고정 + 기간 2005~ 고정) · factor-rotation Lane3(모듈 국면배합, RCMA 등급무관 양방향) · Axiom **r7 원전 복원**(5축 boolean-AND + 3-mode 2-tier + INV-1~7)
- **실측-only 거버넌스**: measurement-graduation(real-computation 의무 · portfolio-α t forge-authoritative · oos_retention≥0.7·calmar≥0.64 HARD · DSR 다중검정스타일only · book-marginal ΔIR≥0.05). proxy 손계산 graduation 폐지
- **모듈 표준화 + 자동흐름**: `register_module` 공용계약(**contract_pass+backtested+frozen+hash/build/cost floor 필수, 등급은 무관**) · 계약 미충족 산출은 `module_quarantine` 보존 · `build_module_performance`는 FR input-floor allowlist 소비 · run_factor_rotation 신선도 자동인식 · ML/DPL register 다리(register_research_outputs) · **E2E 4축 배선 닫힘**(자본게이트 book confirm+실주문 2버튼만 수동)
- **KR 데이터 한계 reference**: value/BM 2002-08~ · M08_ResidMom 1995~ · factor DB 1990~ (`feedback-alpha-search-paper-replication`)
- **부팅 패치(v8.1)**: bootstrap에 RAWDATA K200/KQ150 컬럼 검증 + 데이터 캐시 존재·신선도 검증 추가
- **v8.0 흡수(retain)**: R+Python 1급 · SR 2.5 · agent effort(judge/gov xhigh) · axiom_context_inject · harness_perf_eval · artifact-naming
- **미완(후속)**: residual momentum 사이클 register/factor_analysis 디버깅 · WT_WT-* cleanup · axiom global 실가동

### Multi-Agent Team v53 절 (구 CLAUDE.md)

v53 TeamCreate 패턴은 v8.1에서 Agent tool spawn으로 대체됨. TeammateIdle/TaskCompleted hook은 settings.json에서 등록 해제 (스크립트는 FS retain — `02_Infrastructure/docs/rules/harness.md` 참조). tmux rc listener는 v8.0에서 폐지. 상세: `.claude/skills/qvest-worktask/SKILL.md` Section 7.

### Release Status 상세 (구 CLAUDE.md — 이전 버전·검증 이력)

- 이전: **v8.2** (2026-06-30 도훈 mandate — Codex Critic Round 제거, Opus 4.8 자체 적대검증 대체. 훅 3개 archive · AX-008 Codex→Self-Adversarial 3-source 2/3 불변 · state_transitions codex required 제거 · qvest-codex-round skill 삭제 · codex-round.md DEPRECATED. 별개 S0/RAMP Codex 유지 — 단 enabledPlugins는 2026-07-24 C1로 해제)
- 이전: **v8.1.1** (2026-06-10 완벽 수리 + P2 구조 개편 — hook 47/47 부활(당시 기준) · OneDrive canonical · 게이트 2계층 · rules autoload 6 코어)
- 최근 검증: (v8.3+F5 패치) hook_e2e_battery 11/11 PASS · router selftest PASS (2026-07-24) / (v8.2) router selftest PASS · hook_e2e_battery 10/11(codex 케이스 제거, 잔여 FAIL=python3 환경) · health HARD-fail 0 (2026-06-30) / (v8.1.1) hook 차단 4종 실증 · readiness pass 12/fail 0 · bootstrap BOOT_FAILS=0 (2026-06-10)
