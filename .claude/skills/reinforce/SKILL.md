---
name: reinforce
description: 강화 (v10.01 · 2026-10-13) — ①2계층 강화 절차(무한 · 원장 reinforce_ledger_l2 · 축 = 국면식별/전략결합 · A 면 2계층 = l2_judge_request.json(관문 없음) → Judge(PIT) · 트리거 정본 = judge.md §스폰 조건) ②처방 도구 상자(셀 엔진 rf_cell_engine.R · 블록 어휘 reinforce_program.json · 팩터/비중/오버레이 등록부와 픽커 · 오버레이 신설 검증 G1/G2 · A 자격 관문). 1계층 고정 격자 강화 러너는 2026-10-13 퇴역(코드 삭제) — 1계층 처방은 research-program SKILL(P4 조립·처방 루프)이 맡는다. 원장 L1 은 충실구현 소비 기록만 남는다.
---

# 강화 (v10.01 — 2계층 강화 + 처방 도구 상자)

**v10.01 에서 바뀐 것 (2026-10-13 도훈 지시 · 설계 `04_Research/01_reports/l1_prescription_redesign_20261013/README.md`)**
- 1계층 **고정 격자 강화 러너**(reinforce_auto_parallel · 블록 L-code · B1/B5 LLM 설계 · 승격 사슬 · 결합 착수 · 디렉터)는 **퇴역**했다 — 코드 삭제, 롤백 태그 `pre-v10.01-prescription-20261013`(구판 이 문서 전문도 그 태그에 있다).
- 왜: 37칸 좌표 하강은 Calmar·낙폭 목표 영역에 닿지 못했고(1,101칸 중 Calmar ≥0.64 = 0), 승자 선택은 PORT_t 원시 최댓값이었으며, 설계 에이전트는 논문 이해를 받지 못했다(설계 §1).
- 1계층의 "처방"은 이제 **리서치 프로그램**(P0 실현 가능성 지도 → P1 수익 · P2 방어 · P3 구성 → P4 조립·처방 루프)이 한다 — `.claude/skills/research-program/SKILL.md`. 이 문서는 ①2계층 강화와 ②그 프로그램들이 빌려 쓰는 **도구 상자**만 다룬다.
- 원장 L1(`reinforce_ledger_l1.json`)은 충실구현 **소비 기록**이다 — 검증기가 entry 를 열고 즉시 park 한다(논문 선택기의 소비 판정 정본).

## 1. 2계층 강화 — 상한과 축

| 상한 | keyword_axis | 원장 |
|---|---|---|
| **무한**(A 달성까지 — 교훈 지속 주입 · 도훈) | `regime_identification`(국면 식별 — SJM/HMM/BOCPD/forecaster · label gate) · `strategy_combination`(dispatcher · Black-Litterman · top-k · shrinkage · HRP) | `06_Registry/reinforce_ledger_l2.json` |

매 시도는 새 근거·새 축이어야 한다(같은 아이디어 재탕 = 실패의 재생산). 무인 레인 = `02_Infrastructure/ops/rf_l2_auto.sh`(스위치 `l2_auto.enabled` · 요청 `06_Registry/l2_unit_request.json`). 2계층 절차 본문 = `.claude/skills/strategy-rotation/SKILL.md`.

## 2. 시도 1회의 절차 (원장 writer = `02_Infrastructure/reinforcement/reinforce_ledger.R`)

1. **교훈 주입(착수 전 의무)** — `rf_lessons_digest(2, "<base_id>")` + `Rscript 02_Infrastructure/tools/hypothesis_index.R lookup <축 키워드>` + 해당 키의 기존 L-code. 공리는 스폰 시 `axiom_context_inject.sh` 가 주입한다.
2. **아이디어** — 논문 후속 연구 · 인용 논문 · 추론 가능한 확장. 근거 논문은 **선택**(도훈 2026-09-03) — 원장은 `evidence`(paper/method/none)를 남긴다. 같은 뿌리 논문 3회 연속 = 경고(한 논문 매몰 금지).
3. **사전 등록** — `rf_append_attempt(2, base_id, idea, keyword_axis, root_papers, wt_id = NULL)`. 아이디어·근거·기대 등급을 결과 **전에** 적고, 결과를 본 뒤 고쳐 쓰지 않는다.
4. **실행** — `run_wf_ensemble` 재실측(strategy-rotation SKILL 절차) → `essence_score` 등급. ★**단일 측정 · 체인 완주**: 한 시도 = 후보 하나 · 세션이 대비 arm 배터리를 얹지 않는다 · 어떤 음성 판정도 체인을 멈추지 않는다(종점 = 등급). 계약이 내부에서 부르는 검사(PIT · audit · essence)는 그대로 돈다 — 끄면 지름길이다.
5. **결과 기록** — `rf_record_result(2, base_id, n, grade, essence, artifacts, l_code, lessons)`.
6. **L-code** — `emit_lcode(mode = "reinforcement", ...)` · C/F 면 next_probe ≥2.
7. **텔레그램** — `tg_agent_brief(..., title = "[2계층·강화 n] {전략} — {축} (등급 {g})")`(분모 없음). 양식 = qvest-telegram SKILL.
8. **분기** — Grade A → **2계층** = `06_Registry/l2_judge_request.json`(`status=pending` · `rf_l2_auto.R` 발행 · 관문 없음 — A 자격 관문은 1계층 충실구현·프로그램 라운드 경로) → Judge(PIT 전담 · `.claude/agents/judge.md`) → `rf_record_judge(...)` → PASS = BOOK 후보(도훈 confirm) · FAIL = 등급 무효 · 수리 후 재측정. 미달 → 다음 시도. 등급 미발행(NA)은 체인이 실제로 막혔을 때만 — 막힌 지점을 사유로 적는다.

## 3. 처방 도구 상자 (1계층 프로그램이 빌려 쓴다 — 자산이지 절차가 아니다)

| 도구 | 정본 | 쓰임 |
|---|---|---|
| 셀 엔진 | `02_Infrastructure/reinforcement/rf_cell_engine.R` (+ `rf_sleeve.R` · `rf_capcore.R` · `rf_rebalance.R` · `rf_base_cache.R`) | 셀 스펙 → FACTORS/PORTFOLIO. 기저 신호 캐시 · 오버레이 층 합성 · 구조 방어 슬리브 · 집행 주기 · 커버리지 분모 |
| 측정 어댑터 | `02_Infrastructure/ops/rf_cell_worker.R` | 셀 스펙 → `run_paper_replication`(실투형) → essence |
| 블록 어휘 | `06_Registry/reinforce_program.json` (축 정본 = `rf_spec_axes.R`) | B1 멀티팩터 · B2 비중 · B3 유니버스 · B4 결합 · B5 리스크 오버레이 · B6 집행 주기 · B7 구조 방어 — **순서·칸 수 강제는 폐지**(설계 §4). 처방 담당이 어휘로 쓴다 |
| 등록부 · 픽커 | 팩터 `factor_registry.json` + `ops/rf_factor_arms.R`(as-of 선정 · C1/C14) · 비중 `weight_catalog.json` + `ops/rf_weight_arms.R` · 오버레이 `overlay_catalog.json` + `ops/rf_overlay_arms.R` | 후보 재료. 선정 통계는 as-of 만(pit.md C1 D-E) |
| 새 오버레이 검증 | `rf_overlay_admit.R`(+`ops/rf_overlay_admit_cli.R`) · `overlay_probe.R` · `ops/rf_overlay_audit.sh`(G1 적대 감사) · `rf_overlay_adversary.R`(G2) | 새 코드 처방(방어 장치)을 측정 전에 누출·퇴화·중복 검사 |
| A 자격 관문 | `rf_runner_gates.R::rf_a_eligibility`(충실구현 어댑터 = `run_paper_replication.R` §11) | A 후보 → Judge 트리거 · 보류 사유 코드. 관문 단독 추출 = MC7 이후(rf_block_design · rf_lane_rules 정리와 함께) |
| 유기적 강화 부품 | `rf_organic_guard.R` · `rf_organic_write.R` · `rf_organic_ledger_adapter.R` · `ops/rf_organic_cmd.R` | 경계 판정 · 단일 writer · write-ahead — 처방 루프 안전장치로 승계 예정(설계 §4) |

## 경계 (HARD)

- **Q-Lead 는 오케스트레이션만** — 자체 리서치·백테·수치 산출 금지. 측정은 R 계약(AX-008).
- PIT C1~C15 계층 무관 불변 · 등급 권위 = essence_score 하나 · 정보 경계 τ_D = 2022-12-31(처방 입력).
- 하드코딩 금지 — 수치는 논문 근거·데이터 추정·등록부에서 온다.
- 퇴역 코드(고정 격자 러너 · 기계 사다리 · 디렉터 · B1/B5 설계 레인)는 재기동·재작성 금지 — 필요하면 롤백 태그에서 읽는다.
- 페르소나 = `02_Infrastructure/docs/rules/quant-identity.md`.

## 참조

`.claude/skills/research-program/SKILL.md`(1계층) · `.claude/skills/strategy-rotation/SKILL.md`(2계층) · `.claude/rules/lean-loop.md` · `.claude/agents/judge.md` · `02_Infrastructure/book/book_registry.R`(BOOK)
