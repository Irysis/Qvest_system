---
name: reinforce
description: 강화 프로세스 (v10) — A등급 미달 전략을 QEPM(alpha→risk→optimizer→forge→등급)으로 강화. 1계층 = 논문당 최대 20회(멀티팩터/비중방법론/리스크오버레이 키워드) · 2계층 = 무한(국면식별/전략결합). 매 시도 = 논문 근거 필수 + Axiom 주입 + L-code 발행. A 달성 시 Judge(PIT) 호출. 원장 = reinforce_ledger_l1/l2.json.
---

# 강화 프로세스 (v10 2026-08-29 — 기계 사다리 퇴역, QEPM 기반 재정의)

**목적 = A등급 달성.** 충실구현(1계층) 또는 로테이션 리서치(2계층)가 A 미달로 끝난
전략을, **논문이 제시한 후속 연구 또는 논문에서 추론 가능한 아이디어**로 강화한다.
구 기계 사다리(reinforce_ladder.R — 고정 3단 arm 스윕)는 퇴역 — 강화는 이제
LLM 주도 심층 리서치이며, "후속 연구까지 포함하여 인뎁스 수준으로 논문 리서치를
진행하라"(도훈)는 뜻이다.

## 상한과 축

| 계층 | 상한 | keyword_axis | 원장 |
|---|---|---|---|
| 1계층 | **논문당 최대 20회** (소진 → exhausted → 새 논문) | `multifactor` / `weighting` / `risk_overlay` / `combination` | `06_Registry/reinforce_ledger_l1.json` |
| 2계층 | **무한** (A 달성까지 — 교훈 지속 주입) | `regime_identification` / `strategy_combination` | `06_Registry/reinforce_ledger_l2.json` |

20회 제한의 목적 = **실패의 재생산 방지**(도훈). 같은 아이디어의 재탕이 아니라
매 시도가 새 논문 근거·새 축이어야 한다.

## 시도 1회의 절차 (원장 writer = `02_Infrastructure/reinforcement/reinforce_ledger.R`)

1. **교훈 주입 (착수 전 의무)** —
   `Rscript -e 'source("02_Infrastructure/reinforcement/reinforce_ledger.R"); print(rf_lessons_digest(<layer>, "<base_id>"))'`
   (직전 attempts 의 등급·교훈) + `Rscript 02_Infrastructure/tools/hypothesis_index.R lookup <축 키워드>`
   (죽은 구성 선례) + 해당 paper_key 의 기존 L-code. Axiom 전제는 에이전트 스폰 시
   `axiom_context_inject.sh` 훅이 자동 주입한다.
2. **아이디어 도출** — 논문의 후속 연구 절, 인용 논문, 또는 추론 가능한 확장.
   **근거 논문 원문 링크 필수** — 없으면 원장이 거부한다(기계 강제).
   같은 뿌리 논문 3회 연속이면 경고(한 논문 매몰 금지 — 교차 논문 탐색).
3. **사전 등록** — `rf_append_attempt(layer, base_id, idea, keyword_axis, root_papers, wt_id)`.
   ★1계층 20회 게이트가 여기서 걸린다 (21번째 = stop + exhausted).
4. **QEPM 실행 (1계층)** — `wt_create(wt_type="reinforcement")` (WT-R) →
   `Workflow(name="qvest-dossier-pipeline", args={wt_id, ...})` 또는 6-agent 수동 체인.
   제약 = **실투형 축**: long-only · ≤25종 · K200∪KQ150 · 15bps · Σw=1
   (★비중 상한 없음 — v10). alpha 가설 설계는 **전기간 데이터** 사용(lockbox 폐지).
   governor 는 부르지 않는다 — QEPM 종점 = essence 등급.
   (2계층은 run_wf_ensemble 재실측 — strategy-rotation SKILL 절차.)
5. **결과 기록** — `rf_record_result(layer, base_id, n, grade, essence, artifacts, l_code, lessons)`.
6. **L-code 발행 (완결 후 의무)** — `emit_lcode(mode="reinforcement", ...)` (prefix RF).
   next_probe 연속성 계약(C/F ≥2건) 준수.
7. **텔레그램** — `tg_agent_brief(agent="AlphaSearch", title="[1계층·강화 n/20] {전략} — {축} (등급 {g})")`.
   2계층은 `[2계층·강화 n]`(무한 — 분모 없음). 양식 = qvest-telegram SKILL.
8. **분기** —
   - **Grade A** → Judge(PIT 전담) 스폰 (`.claude/agents/judge.md`) →
     `rf_record_judge(...)`. PASS → BOOK 등록 후보(도훈 confirm). FAIL → 등급 무효,
     수리 후 재측정(원장 자동 재활성화).
   - **미달** → 다음 시도(1단계부터). 1계층 20회 소진 → 큐의 다음 논문으로.

## 결합 검토 (1계층 — 논문 3편마다 의무)

원장이 논문 3편 소비 시점을 알린다. Q-Lead 는 **착수 여부와 무관하게** 논문 간
아이디어 결합 기회를 검토하고 `rf_record_combination_review(reviewed_papers,
verdict, note)` 로 기록한다. 결합 착수 시 = `keyword_axis="combination"` +
root_papers 복수로 새 시도.

## 경계 (HARD)

- **Q-Lead 는 오케스트레이션만** — 자체 리서치·자체 백테·수치 산출 금지.
  측정은 QEPM 체인(AX-008: 산출은 Forge)이 한다.
- 하드코딩 금지 — 모든 수치(파라미터·문턱·비중)는 논문 근거 또는 데이터 추정.
- PIT C1~C15 계층 무관 불변. 등급 권위 = essence_score 하나.
- 구 기계 사다리(`reinforce_ladder.R`)·구 원장(`reinforce_ladder_ledger.json`)은
  read-only 사료 — 소비·재기동 금지 (`QVEST_LADDER_NORUN` 문서 잔재 무시).
- 페르소나 = `02_Infrastructure/docs/rules/quant-identity.md` (최정상급 퀀트 ·
  방법론을 향한 냉소 · 최신 수리통계/ML 적극 · 리서치는 지난하다).

## 참조

`.claude/rules/lean-loop.md`(1계층 룰) · `.claude/skills/strategy-rotation/SKILL.md`(2계층) ·
`.claude/agents/judge.md`(PIT 검증) · `02_Infrastructure/book/book_registry.R`(BOOK)
