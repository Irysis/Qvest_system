# Qvest v8.0 Upgrade Plan — Opus 4.8-Native · Polyglot · Workflow-Orchestrated

**작성**: 2026-05-29 (Session 85) · Q-Lead
**상태**: PLAN (검토 대기 — 구현 미착수)
**전제**: 도훈 mandate 2026-05-29 — (1) Python 전면 허용, (2) 에이전트별 최신 QEPM 리서치 스타일 skill 부여, (3) Opus 4.8 에이전트 구축 공식 가이드 정합, (4) Dynamic Workflow 적극 도입 검토, (5) 버전 bump 추론.
**검증 기반**: Anthropic 1차 문서 (building-effective-agents / claude-4-best-practices / dynamic workflows / sub-agents / model-config). 2차 출처(수치)는 미검증 명시.

---

## 0. 버전 추론 — 왜 v8.0.0인가

| 계보 | 정체성 |
|---|---|
| v5.x | v53/v55 TeamCreate + Hook |
| v6.x | QEPM 3-Agent WorkTask + Harness Kernel |
| v7.x | **Hardening** — "검증 가능한 소프트웨어 커널" (우회불가 실행계약) |
| **v8.0** | **Opus 4.8-Native + Polyglot(R+Python) + Workflow-Orchestrated** |

**MAJOR bump 근거**:
1. **헌법 breaking change** — "R only"(핵심 Level 0 법)를 "R+Python 동등"으로 개정. 하위호환 깨짐 → MAJOR.
2. **오케스트레이션 패러다임 전환** — 수동 Q-Lead 순차 spawn → 코드화된 Dynamic Workflow 병행. 아키텍처 골격 변경.
3. CLAUDE.md 릴리스 표가 이미 "v8 readiness gate" / "v8 후속(이연)"을 예고 → 본 업그레이드가 그 v8.0의 실체.

→ **권고: `Qvest v8.0.0 — Opus 4.8 Native Polyglot Workflow`**. (도훈 최종 확정 사항. v7.3 점진안도 가능하나, Python 헌법 개정만으로도 MAJOR 정당.)

---

## 1. Workstream 1 — Python First-Class (헌법 개정)

**현실 추인**: Cycle 1/2 ML 전체(XGBoost/LightGBM/NGBoost, venv `qvest_ml`)가 이미 Python. 헌법 "R only"가 현실과 괴리 상태. 본 WS는 정식화 + 가드레일.

| 변경 | 파일 | 내용 |
|---|---|---|
| 헌법 | `CLAUDE.md` `## Core Rules` | "R only (tidyverse + data.table). Python은 hook router 외 strategies 금지" → **"R + Python 공히 허용. 언어 선택은 도구적. PIT C1~C15 / Backtest Contract v1.0 / Production Constraints / lockbox-scope는 언어 무관 동일 적용"** |
| 신규 규칙 | `.claude/rules/python-policy.md` (Level 1) | venv 표준(`/home/quant/.venvs/qvest_ml/`), 한글경로 회피 패턴, parquet I/O 규약, **Python backtest는 검증된 표준함수만(자체합성 금지 — answer-principles 정합)**, R↔Python 경계 |
| 계약 확장 | `02_Infrastructure/contracts/` | Python backtest의 10-component `bt_result` 동등 보장 (R `build_bt_result` 위임 OR Python 검증 동등 구현). `metric_type` 라벨 동일 |
| Hook 확장 | `answer_principles_grep.sh` / `backtest_contract_audit.sh` | `prod(1+r)` / `cumprod` / `0.8*r1+0.2*r2` 자체합성 탐지를 `.py`까지 확장 |

**리스크**: Python backtest 자체합성이 R보다 탐지 어려움 → hook 확장 필수. **난이도 ⭐⭐⭐**.

---

## 2. Workstream 2 — 에이전트별 QEPM 리서치 스타일 Skill

`research_philosophy.md` 7 Modern Trends(이미 Level 0)를 역할별 **실행 skill**로 operationalize → 각 `.claude/agents/*.md` frontmatter `skills:` 필드 부착 (Claude Code 공식 지원 확인).

| Agent | 신규 skill | 7-Trend 매핑 | 강제 hook 연계 |
|---|---|---|---|
| alpha-research | `qvest-alpha-style` | ① Factor Zoo 축소(economic_rationale + redundancy_cluster_id) ② Cost-aware loss(−E[ret]+γ\|Δw\|) ③ Uncertainty-aware(μ̃=μ̂−k·SE) | feature_registry_economic_rationale_check / ml_cost_aware_audit / ml_uncertainty_audit |
| risk-research | `qvest-risk-style` | ⑤ Risk model 고도화(crowding_score_per_factor + concentration) | risk_crowding_score_check |
| optimizer-research | `qvest-opt-style` | ④ Direct Portfolio Learning(features→weights) ⑥ Implementation discipline(TO≤6/yr, [0,0.20], Σw=1) | worktask_constraint_enforcer |
| judge / governor | `qvest-attribution-style` | ⑦ Attribution(Brinson + Carhart 4) feedback loop | attribution_quarterly_trigger |

**효과**: 7 trend가 "헌법 텍스트"에서 "agent 실행 절차"로 전환. **난이도 ⭐⭐** (skill 4종 작성 + frontmatter 1줄).

---

## 3. Workstream 3 — Opus 4.8 Prompt 정합 (1차 검증 반영)

| 우선 | 항목 | 구현 (검증된 레버) | 출처 | 난이도 |
|---|---|---|---|---|
| 1 | Judge/Governor 추론 강화 | `judge.md`+`governor.md` frontmatter **`effort: xhigh`** (지능민감 판정). draft 단계는 high | claude-4-best-practices §Calibrating effort | ⭐⭐ |
| 2 | Codex Round effort tiering | 1차 critic `effort: high` → near-call(HIGH≥5 / AX near-fail) 시 2차 `effort: max`. (self-correction 체이닝 = 공식 권장 패턴) | §Chain complex prompts | ⭐⭐⭐ |
| 3 | scope 명시 규율 | 4.8 리터럴 해석 → 모든 rule/hook 메시지에 적용범위 명시("모든 X, 첫 항목만 아님"). `_shared_prefix.md` 점검 | §More literal instruction following | ⭐⭐ |
| 4 | subagent spawn 명시 | 4.8 기본 적게 spawn → CLAUDE.md 병렬규칙에 "언제 spawn/직접" 명시 (병렬·격리·독립 workstream만 spawn, 단순/순차/단일파일은 직접) | §Controlling subagent spawning | ⭐⭐ |
| 5 | hallucination/scope 가드 | agent prefix에 `<investigate_before_answering>` + overengineering 가드 (PIT/answer-principles 보강) | §Minimizing hallucinations | ⭐⭐ |
| 6 | mid-task system 메시지 | 캐시 안 깨고 instruction 갱신 (Opus 4.8 신규) — caching.md에 반영 | migration guide | ⭐⭐⭐ |

---

## 4. Workstream 4 — Dynamic Workflow 도입 (신규 패러다임)

**공식 정의**: JS 스크립트가 subagent를 background 오케스트레이션. 중간결과는 script var(Q-Lead context 절감). adversarial cross-review / multi-angle 패턴 내장. resumable. v2.1.154+.

**Qvest 매핑 (적용처)**:

| Qvest 절차 | 현재 | Workflow 전환안 | 정합 패턴 |
|---|---|---|---|
| Cycle 다중-track 리서치 (Cycle 2 4-track) | Q-Lead 수동 4 spawn + 수동 4-way 비교 | `parallel()` fan-out → 통합 비교 stage | parallelization |
| WT lifecycle (alpha→risk→opt→forge→judge→gov) | 순차 수동 spawn + Hook 강제 | `pipeline()` 6-stage (Hook 검증 유지) | orchestrator-workers |
| Codex Round | PostToolUse async + 수동 대기 | workflow 내 evaluator stage (draft→critic→refine) | evaluator-optimizer |
| AX-008 Verification Triangulation | 수동 Forge+Codex+Architect 2/3 | adversarial review stage (독립 agent 상호검토) | "adversarial review" 공식 패턴 |

**도입 방식 (점진)**:
1. 신규 saved workflow `/qvest-multi-track` (`.claude/workflows/`) — Cycle 다중 hypothesis 병렬 리서치 1건부터 파일럿.
2. Hook 계약 **유지** (workflow가 spawn한 agent도 acceptEdits + allowlist 상속 → PIT/role/codex hook 그대로 발동).
3. 검증 후 WT lifecycle 전체를 `/qvest-worktask-pipeline` workflow로 확장.

**핵심 이점**: ① Q-Lead context 토큰 대폭 절감(중간결과 분리) ② 재현·재실행 가능한 오케스트레이션 ③ 4-track류 작업 자동 fan-out.
**리스크**: research preview · 토큰 다량 소비 → 명시 opt-in 유지. Hook이 workflow agent에도 발동하는지 파일럿 검증 필수. **난이도 ⭐⭐⭐⭐**.

---

## 5. Workstream 5 — Harness Opus 4.8 Perf Optimization

하네스 엔지니어링 평가(Session 85)에서 도출. **추론성능 최적화 제1목적**. 보존선(PIT/Codex/Positive Hook/safety_guard) 불가침.

| # | 항목 | 무엇을 / 왜 | 난이도 |
|---|---|---|---|
| 1 | **effort 도입** | 전 agent `model: opus`만, `effort:` 부재 → Judge/Gov `xhigh` / alpha·risk·opt `high` / 기계적 검증 `low~medium`. 4.8 최대 성능 레버 무료 사용 | ⭐⭐ |
| 2 | **prompt prefix 슬림화** | `*_init.md`(25KB)+`_shared_prefix.md`(21KB) 매 spawn Read ≈ **~12K tok** 작업전 적재 → 4.8 과잉thinking+캐시비용. lean core(~4KB)+나머지 `skills:` just-in-time → **spawn당 ~12K→~4K tok** | ⭐⭐⭐ |
| 3 | **role/sequence hook 3세대 통합** | `unified_agent_guard`(v52)+`role_objective_guard`(v6.1)+`agent_role_guard`(v6.4) 동시 registered(~818줄 중복) → v6.4 단일화 + hook router 수렴. Pre 21개 매 Write 발동 latency↓ | ⭐⭐⭐ |
| 4 | **axiom 주입 경량화** | 매 spawn 8 AX 전문(~600tok) → AX 코드+포인터, 전문 on-demand (WS7과 연계) | ⭐⭐ |
| 5 | **방어 레이어 재평가** | `rationalization_detector`+`answer_principles_grep` = pre-4.8 "합리화 엔진" 전제. 4.8 정직·리터럴에서 오탐 비용 측정 후 통합 (PIT/Codex 유지) | ⭐⭐⭐ |
| 6 | **cruft 삭제** | `telegram-protocol` skill(DEPRECATED) / FS-only hook 4종 / `auto_commit·push_on_stop` 미등록(WARN_7) 정리 | ⭐ |

**근거**: 하네스 핵심 명제("LLM=합리화 엔진→Hook으로 이동")는 4.6/4.7엔 정확했으나 4.8(정직·리터럴·effort 구동)에선 ① 일부 방어레이어 필요성↓ ② prompt bloat 상대비용↑ ③ effort 레버 미사용. 골격은 유지, 컨텍스트 de-bloat + effort 채택.

---

## 6. Workstream 6 — Codex Round 재계층화 (T0/T1/T2)

4.8가 self-review 1차 효용을 올렸으므로 전건 9~15분 full Codex는 과잉. **cross-model 독립성의 본질 가치는 유지**(homogeneous critic = 상관 오류, ens3 실증). stakes로 tier:

| Tier | 대상 | 방식 |
|---|---|---|
| **T0 (skip)** | 저stakes·기계적(schedule/format) | 4.8 self-check |
| **T1 (self-critique)** | 중stakes 리서치 draft | 별도 Opus subagent refute-mode (effort:xhigh) |
| **T2 (full cross-model)** | 의사결정 임계: alpha graduation / Forge SR·backtest / governor admit / fabrication 위험 | Codex(이종 모델) 필수 |

→ ~70%(T0/T1) 빠른 self-loop, ~30%만 full Codex. AX-008(2/3 독립) 보전 + 비용↓. "독립 모델"이 본질 → Codex 비싸면 다른 이종 모델 설정화. **난이도 ⭐⭐⭐⭐**.

---

## 7. Workstream 7 — Axiom Engine 4.8 Recalibration

엔진 골격(JSON SOT + health gate + lcode_harvester + enforcement) 재구축 불필요. 4.8 특화 calibration:

| # | 항목 | 내용 | 난이도 |
|---|---|---|---|
| 1 | **AX-000 reframing (최우선)** | "한계란 없다/모든 목표 달성 가능"을 리터럴 4.8가 받으면 정직한 infeasibility 보고 억제·overconfidence → answer-principles "불확실성 명시"와 충돌. 이번 세션 alphaF/ens3의 정직한 DSR FAIL·no-premium 보고가 그 반례. **문안 확정(도훈 승인 ①, 2026-05-29)** ↓ | ⭐⭐ |

**확정 AX-000 문안 (옵션 ① 방법-한계 reframe, 도훈 승인 2026-05-29)**:
> AX-000 [IMMUTABLE]: 한계는 대개 법칙이 아니라 방법의 한계다. 모든 목표는 충분한 엄밀함·창의성·반복으로 달성 가능하다는 전제로 임한다. 단, 실증·PIT·수리로 입증된 한계는 부정할 대상이 아니라 정직히 보고할 발견이며, 포기는 가용한 모든 방법을 소진한 뒤에만 정당하다.

**구현 footprint (4 파일 + health gate)**: ① `qepm/memory/axioms/active/AX-000.json`(primary SOT) ② `.claude/rules/axioms.md`(documented — memory_knowledge_health hard 3: primary↔documented 일치 의무) ③ `02_Infrastructure/prompts/_shared_prefix.md`(injection) ④ `CLAUDE.md` Axioms 요약 line + `.cache/axiom_core.json`(derived, bootstrap regen). 적용 후 `memory_knowledge_health.R` HARD 0 검증 의무.
| 2 | **AX 주입 경량화** | WS5 #4와 동일 (코드+포인터) | ⭐⭐ |
| 3 | **enforcement 재calibration** | AX-002(프로세스 정직 = 대전제) advisory→block 격상 검토(4.8 리터럴 오탐 calibration). stale candidate 90+d 정리 + 세션 학습(heterogeneous-critic / homogeneous-ensemble-fail / DSR universal gate) candidate 평가 | ⭐⭐⭐ |

---

## 8. Workstream 8 — Research Reasoning-Performance & Measurement ⭐ (도훈 thesis 핵심)

기존 WS5/6/7은 **컨텍스트·비용·강제**를 최적화하나, "리서치 추론성능 향상 → 성능향상"이라는 업그레이드 핵심 lens에서 **리서치 추론 품질 레버 + 측정 루프**가 누락. 본 WS가 그 공백을 메움.

| # | 항목 | 내용 | 출처 | 난이도 |
|---|---|---|---|---|
| 1 | **추론성능 측정 루프 (THE gap)** | 아키텍처 변경이 실제로 리서치 산출을 개선했는지 측정 부재 → "perf 향상"이 unmeasured. 기준 WT 1건 before/after 회귀(IC/DSR 추론 품질 · latency · token · Codex 통과율) eval harness. "measure & iterate"(building-effective-agents) | building-effective-agents | ⭐⭐⭐ |
| 2 | **adaptive thinking (effort와 별개)** | 연구 추론(alpha 가설/risk 진단)에 `thinking:{type:"adaptive"}` — interleaved 추론으로 품질↑. WS3 effort와 보완 | best-practices §Calibrating effort and thinking | ⭐⭐⭐ |
| 3 | **multi-context-window 연구 (memory-native)** | overnight Cycle(1/2 다중 window)에 "context 자동 compaction → 상태 persist 후 continue, token budget로 조기중단 금지" 패턴 + 구조화 state(JSON). 장기 연구 throughput | best-practices §Long-horizon reasoning | ⭐⭐⭐ |
| 4 | **model routing (Opus 통일 정책 재검토)** | 현 caching.md "전 agent Opus 통일"(Sonnet fabrication 사건 후 설정). 기계적 substep(데이터 fetch/parse/format)을 Haiku 4.5 또는 `effort:low`로 라우팅 → Opus 추론 budget을 alpha discovery에 집중. **단 fabrication 이력 고려해 T2급(SR/admit)은 Opus 유지** | cookbooks (Haiku as subagent) | ⭐⭐⭐⭐ |
| 5 | **JIT factor/data retrieval** | `active_factor_registry.json`(133개+근거) → 필요 factor만 inject. 연구 agent context bloat↓ = 추론 품질↑ (C15 정합 심화) | best-practices §Context engineering | ⭐⭐⭐ |
| 6 | **구조화 연구 scaffold (skill)** | "competing hypotheses + confidence tracking + 자기비판 + hypothesis tree" 연구 패턴을 skill로 (WS2 연계) | best-practices §Research | ⭐⭐ |

**핵심**: #1 측정 루프가 없으면 WS3~7의 효과를 입증 못 함 → 도훈 thesis 자체가 unverified. #1을 v8.0 게이트로 의무화.

---

## 9. 실행 순서 (승인 후)

1. **WS8-1 측정 루프 먼저 구축** (before/after 비교 기준선 — 모든 변경의 효과 입증 전제)
2. **WS1** 헌법 개정(R+Python) + `python-policy.md` + 계약/hook 확장 (atomic commit)
3. **WS5-6 cruft 삭제 + WS5-1 effort 도입** (저위험·고ROI 선행)
4. **WS2** skill 4종 + **WS8-6 연구 scaffold skill** + agent frontmatter `skills:` 부착
5. **WS5-2 prefix 슬림화** + **WS5-4/WS7-2 axiom 주입 경량화** + **WS8-5 JIT retrieval**
6. **WS3 + WS8-2 adaptive thinking** Opus 4.8 prompt 정합 (Judge/Gov xhigh)
7. **WS5-3 role-hook 통합** + **WS6 Codex T0/T1/T2** + **WS8-4 model routing**(신중)
8. **WS7-1 AX-000 reframing**(도훈 승인 완료 ①) + **WS7-3 enforcement** + **WS8-3 multi-window**
9. **WS5-5 방어레이어 재평가** (오탐 측정 기반)
9. **WS4** `/qvest-multi-track` workflow 파일럿 (Hook 발동 검증) → 성공 시 lifecycle 확장
10. **검증 게이트**: 1 WT end-to-end 파일럿 + v8 readiness gate strict 통과 + memory_health HARD 0
11. **릴리스**: `qvest_v8_0_sot.md` 발행 + CLAUDE.md Active Version v8.0 + L-code 적립

---

## 10. 검증 미충족 (출처 명시)
- Fast Mode 가격/SWE-Bench 수치: 2차 출처(Axios/9to5Mac)만 → **미검증, anchor 금지**.
- Claude Code subagent frontmatter가 `thinking:{type:adaptive}`를 직접 노출하는지: `effort`는 확인, adaptive thinking은 API 파라미터 — 파일럿 시 확인 필요.
- Managed Agents `agent_toolset_20260401` coordinator API: API SDK 레벨 — Claude Code Agent-tool 모델과 별개, 직접 적용 안 함.

## 11. 보존 원칙 (폐기 금지)
우회불가 Hook 계약 / PIT C1~C15 강제 / Codex Round / Positive Hook+Certificate / memory-axiom SOT 는 **보강 대상이지 폐기 대상 아님**. Dynamic Workflow는 이들을 대체하지 않고 **그 위에서 오케스트레이션**한다.

---

## 참고 (1차 출처)
- [Building effective agents](https://www.anthropic.com/engineering/building-effective-agents)
- [Prompting best practices (Opus 4.8 포함)](https://platform.claude.com/docs/en/docs/build-with-claude/prompt-engineering/claude-4-best-practices)
- [Orchestrate subagents at scale with dynamic workflows](https://code.claude.com/docs/en/workflows)
- [Create custom subagents](https://code.claude.com/docs/en/sub-agents) · [Model configuration](https://code.claude.com/docs/en/model-config)
- [anthropics/claude-code (공식 prompt-snippet 플러그인 패턴)](https://github.com/anthropics/claude-code)
