# Qvest 헌법 변경 이력 (CLAUDE.md에서 분리, 2026-06-10 P2 다이어트)

> CLAUDE.md는 "현재 유효한 헌법"만 담는다. 버전 연혁·릴리스 상세는 본 파일이 SOT.
> 최신 릴리스 상세: `qvest_v8_4_asymmetry_ml_sot.md` (**v8.4 — 주력 SOT**) · `qvest_v8_3_alpha_discovery_sot.md` (v8.3) · `qvest_v8_1_sot.md` (v8.1) · `qvest_v8_0_upgrade_plan.md` (v8.0)

## Release Status (v6.4.0 → v8.4)

| Release | 일자 | 핵심 |
|---|---|---|
| ✅ **문서 정합 — INDEX 재동기** | 2026-08-16 | `00_Lawbook/INDEX.md` v8.1.0 3-Mode(2026-06-12) → **v8.4 4-Mode** 갱신 — 2개월·헌법 4회 전이(v8.2→v8.3→AST v1.1→v8.4)분 낙후 복구. 실측 대조로 **구판 오류 3건 적발**: `state_transitions.json` 위치 오기(`worktask/` → 실제 `02_Infrastructure/hooks/policies/`) · 텔레그램 경로 오기(`qepm/telegram/` → 실제 `02_Infrastructure/telegram/`) · `qepm/memory/methodology_memory.md`를 **부재 파일인데 존재하는 양 기재**. 갱신 내역: §0 헌법 계층 4단 신설(CLAUDE.md → `.claude/rules/` → `docs/rules/` → `00_Lawbook/`) · §1 SOT를 v8.4/v8.3/AST v1.1까지 확장 · §5 axiom **"8건(000~005,007,008)" → 실측 active 4건(000/001/002/008) + Distilled 강등 4건** · v8.3/v8.4 운영 SOT(`alpha_frontier_queue`·`layer_bottleneck_map`·`hypothesis_index`·`method_registry`·`continuity_cases`) 추가 · §7 Skills/Agents/Commands 신설 · Self-Adversarial 절 모델명 하드코딩 제거(CLAUDE.md Active Version 정본 위임). **낙후 기전 진단 = 개수 박제(`8 axioms`/`30 hook`/`203 paper notes`) + 경로 축약** → Maintenance에 규약 3종 명문화(숫자 박제 금지 / 루트 기준 전체 경로 / 갱신 후 경로 전수 검증). 검증: 문서 백틱 경로 72개 기계 추출 → 실참조 전부 존재. 파생 칩 `task_da53ea06`(확장 룰 축약 ~25건 정규화 + 문맥-인지 경로 검사기 — `harness.md`/`codex-round.md`의 `codex_round_contract.json` 위치 오기 포함). |
| ✅ **v8.4** | 2026-08-13 | **비대칭 알파 중심 재편** (도훈 mandate). 주력 교체: v8.3 도달 경로 ①(비-return 신규 원천)을 **주력에서 해제** → **기존 데이터풀 총동원 + ML·수리통계·매크로로 시장 비대칭 알파 도출**. 근거 = `ml_complexity` **126건 원장 재판독**에서 ML 트랙이 자본 게이트를 하나도 통과 못 함: **MDD ≤25% 충족 0/84** · **PORT_t ≥2.95 = 0/10**(범위 −1.377~2.362) · **oos_retention ≥0.7 = 2/17**(음수 10건·중앙 −0.481). 죽은 자리 = ①결합기(동일 3짝 metric 클러스터 16+9건 = 84의 30% — 다른 결합 규칙이 같은 점을 낸다) ②사이징/selection ③평균 예측기. ⇒ **표적을 평균 → 분포로 교체**(조건부 분위·왜도·꼬리초과확률). **4 lane**: A 분포-표적 학습(1순위, 평균-표적 대조군 동반 의무) · D 매크로 상태 조건부(2순위) · B 일별 축 정보 회수(PIT 최우선) · C 수리통계 구조 추정. **금지 4종**(경로-scoped, INV-7): ML 결합기 · ML 사이징/selection · 표적이 "다음 달 평균 수익률"인 ML 라운드(대조군으로만) · sweep의 DSR 회피. 큐 FQ-233/234/235/236. 불변: Graduation HARD 3종 · cap-w 게이트 권위 · 6-agent · Production Constraints(INV-7) · governor 수동 · v8.3 골격. SOT `qvest_v8_4_asymmetry_ml_sot.md`. ⚠**자기정정 6건 동반** — 초판의 "126건 전부가 평균 표적·분포 표적 0건"은 **근거 없음**(`key_metrics`에 표적 필드가 없어 셀 수 없고 metric 보유는 84/126). 정직 서술 = "분포를 표적으로 명시한 라운드를 찾지 못했다"(미발견이지 부재 증명 아님). |
| ✅ **AST 계층 v1.1 채택** | 2026-07-25 | 도훈 원안 v1.0 → 4-agent 실측 검증(wf_f40cca21) → 수정 6건(M1 escape 리프 4종·M2 registry 승격·M3 3중 구조 예방·M4 essence_score 사이드카·M5 judge advisory 한정·M6 N≥30) 반영 채택. **Step 0: C4 연간 availability = 익년 3/31 확정**(pit.md 개정 — 구 'annual 5월' 폐기, xlsx Q4 +45d는 수리 항목). field_dictionary = `06_Registry/ast_field_map_v0.json`(전 데이터 58그룹 실측 전수, wf_85fe98c6 — 부산물: 멤버십 2026-03-31 종점·벤치 date32 미병합·SJM 스테일 적발, 칩 2건 발행). SOT `qvest_ast_v1_1_sot.md`. graduation HARD 3종·6-agent·헌장 자율성 불변. |
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

- **문서 정합** — 2026-08-16 — `00_Lawbook/INDEX.md` 재동기(v8.1.0 → v8.4). INDEX Maintenance 규약("인프라 reorg / 헌법 버전 전이 시 INDEX 갱신 + CHANGELOG 기록 의무") 이행 기록. ★**본 CHANGELOG 자신도 같은 낙후를 겪고 있었다** — 위 v8.4 행은 이때 함께 소급 기재됐다(2026-08-13 전이 시점에 기록되지 않음). 이는 "규약은 있는데 강제하는 기계가 없다"는 구조 문제의 직접 증거이며, 낙후 탐지 자동화가 후속 검토 항목으로 열려 있다. 상세 = Release Status 표 2026-08-16 행.
- **v8.4** — 2026-08-13 — 비대칭 알파 중심 재편 (도훈 mandate). ML 트랙 126건이 자본 게이트를 **하나도** 통과하지 못한 실측(MDD 0/84 · PORT_t 0/10 · oos_retention 2/17)을 근거로 **표적을 평균에서 분포로 교체**. 미소비 표면 = factor DB(331 전수 book-marginal 통과 0, 계열 15종이 구속 해상도)가 아니라 **일별 축**(9,005 거래일 · `flow_features_daily` 1.25GB/9.36M행) — 알파 리서치가 전부 월간 횡단면이라, **월간으로 접는 순간 분포 정보가 소멸**한다(비대칭은 접히기 전에만 관측된다). 매크로는 **이미 적재 중**(lag 1d)이라 신규 수집 불요이나 착수 전 4확인 의무: `fred_macro_wide` 파생 5일 정체 · 계열별 시차 7~73일 불균질 · `macro_regime` 월말스탬프 마지막 행이 **진행 중인 달**이라 월중 조회 시 동월 look-ahead · flow 패널 43일 정체. 비-return FQ-001~005 주력 해제는 **구조 판결 아님** — 2건은 도훈이 데이터 게이트를 닫았고(08-09 공매도/신용대차) 3건은 실측 negative이며, 부활 조건은 SOT §1(INV-7). ⚠**과거 ML 실패의 부활과 구분할 것**: 죽은 것은 ML을 결합기·사이징·평균 예측기로 쓴 경로이고, v8.4는 **표적 자체를 분포로 바꾸는** 미측정 축이다. SOT `qvest_v8_4_asymmetry_ml_sot.md`.
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

> ⚠ 아래 한 줄은 **2026-07-24 이관 시점의 verbatim 스냅샷**이라 "현재 active"가 그때 기준(v8.3)이다 — 보존 원칙상 원문을 고치지 않는다. **현행 계보는 위 Release Status 표가 권위**: … → v8.2 → v8.3 → AST v1.1 → **v8.4** (2026-08-13~ 현재 active).

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
