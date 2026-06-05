# Qvest Dual-Mode Design SOT — Alpha-Searching (lean) / QEPM (full)

**버전**: v0.2 **DRAFT (도훈 승인 대기)** · 2026-05-30
**상태**: 설계 문서. **구현 전 도훈 승인 필수** (헌법 Active Path 변경 — CLAUDE.md ## Active Path).
**계보**: v8.0.0 단일 QEPM 파이프라인 → dual-mode 분리 제안. v0.1(advisory-only triage) → **v0.2(contract-backed lean lane, 도훈 2026-05-30 재설계)**.
**작성 근거**: 도훈 mandate 2026-05-30 — "정석 QEPM만 있어 비용 과다. 2모드 분리. 알파서칭은 초기버전 + PIT 개선 + **실제 전기간 백테까지**."
**도훈 결정 (2026-05-30)**:
- 알파서칭이 **전기간 백테 실측** 수행. **고정 top-N EW 의무 폐기** → 논문의 비중결정 방법론 차용.
- 논문 비중 차용 시 **risk / optimizer 에이전트만 SKIP** (forge는 **lean 모드 유지** — Forge 전용 `optimized-backtest` 코딩 스킬 재사용). 설계 = **implementer(신설 role)**, 측정 = lean-forge → self-grading firewall(AX-008) 유지. PIT 2중(implementer #1 + Judge #2). (구 v0.2 "forge 스킵"은 2026-05-31 정정 — optimized-backtest 스킬이 Forge 소유라 살림.)
- 코드 작성 단계에서도 **PIT 검증 → 2중 검증** (code-stage + Judge-stage).
- 승격 전략은 **Governor부터 QEPM 편입**. Governor 기각 시 **옛 S5(Mutation) 차용 → 강화 위해 full QEPM 재진입**.

---

## 1. 동기 (비용 비대칭)

- 정석 QEPM 1회 = 6 agent × Codex Round(각 9~15분) + challenge_note + 5 cert + admission. 후보 하나에 막대한 비용.
- 실증: standalone alpha 16/16 FAIL ([[learning-gate-calibration-longonly]] / [[reference-alpha-trends-2024-2026]]). 자기완결 논문 전략은 risk/opt 통합이 불필요한데도 6-agent 전부 거치는 게 낭비.
- funnel 맹아 존재(`reference_creative_alpha_idea_bank` cheap-test + creative funnel 커밋). 본 설계 = **자기완결 논문전략을 위한 lean authoritative lane** 명문화.

---

## 2. 두 lane 정의

| | **Alpha-Searching (lean)** | **QEPM (full)** |
|---|---|---|
| 대상 | **자기완결 논문전략** (신호+비중+유니버스+리밸런스 명시) | 신호만 있는 알파 / lean에서 기각돼 강화 필요한 전략 |
| 진입 | 논문 → **implementer(신설)** → **lean-forge** | WorkTask (lean 기각분 S5 / 신호-only 알파) |
| 비중 | **논문 차용** (EW 의무 폐기) | optimizer 결정 (MVO/HRP/CVaR/etc) |
| 백테 | **전기간 실측, `build_bt_result` 계약 경유** (§3) | forge `build_bt_result` |
| 에이전트 | **implementer → lean-forge → Judge → Governor** (risk/opt agent SKIP) | alpha→risk→optimizer→forge→judge→governor |
| PIT | **2중** — code-stage(#1) + Judge(#2) | code + Judge |
| Codex Round | **Judge만** (구현 agent는 선택) | 6 role 전부 |
| 권위 | **authoritative (계약 경유 backtested)** | authoritative |
| admission | Governor (수동 + 도훈 confirm) | Governor (동일) |
| 산출물 위치 | `stage_artifacts/alpha_search/{idea_id}/` → 승격 시 canonical 복사 | `qepm/mailbox/worktask/{WT_ID}/` |

---

## 2.5 Lane3 — Factor Rotation Mode (meta-layer, 도훈 2026-06-05)

Lane1/Lane2는 **모듈을 생산**. **Lane3 = 그 모듈 풀을 국면(regime) 조건부로 *배합*하는 meta-layer**(생성 없이 소비). 단일 모듈 long-only SR 천장 ~2.0 → SR 2.5는 앙상블 레벨에서.

| | **Factor Rotation (Lane3)** |
|---|---|
| 대상 | Lane1/2가 생산한 STR 모듈 풀 (frozen 소비) |
| 진입 | `/factor-rotation <track∈{regime-engine, allocation}>` → `dispatch-orchestrator` |
| 구조 | 1모드 2트랙: Track1 레짐엔진(정의+예측, 학술기반) → Track2 배분 |
| 적재 | 모든 모드 산출물 `register_module()` 경유 표준화(sim_result.rds + module_catalog). QEPM=native |
| 풀 admission | **RCMA**(overall 등급 아닌 국면조건부, 방어형 CRISIS + 공격형 확장 specialist 양방향) |
| 백테 | `run_wf_ensemble` → `build_bt_result` 실측 → `essence_score` (자체합성 금지) |
| 게이트 | OOS_retention≥0.7 → DSR≥0.5 HARD → placebo → holdout |
| 산출물 | `FR_XXXX` (운용체계, STR과 구분) → `factor_rotation_registry.json` |
| admission | **governor 정지** (book sleeve = STR or FR(1 sleeve), book_state 수동 + 도훈 confirm) |
| SOT | `.claude/skills/factor-rotation/SKILL.md` · `.claude/rules/factor-rotation.md` |

---

## 3. ⭐ 권위 = 계약(contract), 에이전트 아님 — load-bearing 불변식

**risk/optimizer 에이전트만 스킵** (논문이 비중 제공 → Σ·최적화 불요). forge는 **lean 모드로 유지.** 권위는 *에이전트*가 아니라 **`build_bt_result()` 계약**에서 나온다 (measurement-graduation §1).

- 알파서칭 전기간 백테는 **반드시 `02_Infrastructure/contracts/build_bt_result()` 10-component 경유** (audit_bt_result + `metric_type=backtested` + register_bt_result). 포트 수익률 구성 = `Return.portfolio()`. → proxy 아닌 authoritative-grade.
- **lean-forge**(forge lean 모드)가 이 계약 백테를 실행 — Forge 전용 `optimized-backtest` 코딩 스킬(Rcpp/data.table/arrow) 재사용. **implementer(설계) ≠ lean-forge(측정)** 분리로 self-grading firewall(AX-008) 유지.
- 비중을 논문이 주므로 **risk(Σ)·optimizer(weight 최적화) 통합이 없음** → 그 두 에이전트가 redundant. forge는 *통합*이 아니라 *실행*이라 살림.
- ❌ 계약 우회 자체 백테(`prod(1+r)`/`cumprod`/수동 Sharpe) = proxy 사고 재발(FLOW screen 3.55→forge 2.35) = **AX-002 위반**. 이 조건 위반 시 lean lane 전체 무효.
- v0.1의 "advisory-only" 엄격함은 폐기 → **계약 경유라는 다른 기전으로 무결성 달성** (완화 아님).

---

## 3.5 스코어 = 계약-실측 본질지표 5개 (bloat 금지) ⭐ 도훈 mandate 2026-05-30

**Qvest 본질 = 리스크 대비 수익률 극대화.** 스코어는 그것만 실측해 말한다.

- **헤드라인 5지표** (lean/full 공통, `build_bt_result` 한 번에 산출, 전부 `metric_type=backtested` 계약-실측):
  **net Sharpe · net IR · portfolio-α t (NW lag-3) · MDD · Calmar.**
- **등급(A/B/C/F) 유지 — 단 계약-실측 지표로만** (18-component proxy 합산 폐기). 임계 전부 문서화된 값(새로 지어낸 것 없음):
  - **A (Standalone, 단독운용)**: hard_fail 없음 + **PORT_t ≥ 2.95** (Harvey-Liu-Zhu) + **OOS retention ≥ 0.7** (활성 Sharpe OOS/IS, 과적합 게이트) + **Sharpe ≥ 0.8** + **CAGR ≥ 16%** + **Calmar ≥ 0.64** (=16%/25% 도출, 위험조정). **DSR ≥ 0.5는 다중검정 스타일(n_trials>1: ML스윕/optimizer서치/앙상블)에서만 추가 게이트** — 1논문/1알파엔 부적용(PORT_t가 이미 문헌 다중검정 반영). 도훈 mandate 2026-05-31.
  - **B (Component, 포트 기여)**: hard_fail 없음 + PORT_t ≥ 2.0 + **net IR > 0.2** (judge Gate C). 알파는 유효하나 A의 absolute 바(Sharpe/CAGR) 미달.
  - **C (Ensemble, 블렌드에서만)**: hard_fail 없음 + positive alpha (PORT_t > 0 AND net IR > 0)이나 B 미달.
  - **F (Fail)**: hard_fail (PIT 위반 / MDD 한도초과 / 집중 위반) OR PORT_t ≤ 0 OR net IR ≤ 0.
  - PORT_t·DSR 미산출(계약 미경유 legacy)이면 등급 `uncertain` — 추정으로 A/B 부여 금지([[feedback-verified-numbers-only]]).
- **추정/proxy 숫자로 게이트 통과·소통 금지** ([[feedback-verified-numbers-only]]). 측정 안 된 값은 "측정 안 됨"으로 정직 표기.
- **legacy `hurdle_gate.R` 18-component**(novelty_bonus/saturation_penalty/confidence_mult/combinat + `prod(1+r)`·수동 Sharpe·full-sample β) = **proxy → 진단용 retain only, 게이트/소통 권위 없음.** 본질에서 비대해진 패치 누적분.

## 4. PIT 2중 검증 (도훈 명시) — 초기버전 결함 제거

**code-stage (#1)**: 구현 직후 —
- `02_Infrastructure/validation/pit_enforcement.R` (C1~C15) + `lookahead_detector.R` 자동탐지.
- forward label 사용 시 `validate_label_direction()` + `bear_date_audit.R` PASS 의무 (Cycle 50 shift-convention 사건 재발 방지, 언어무관).
- `data_table_shift_convention.md` 준수 (R `shift` / Python `.shift()` 방향 명시).
- lockbox-scope: 알파서칭 = 정규 discovery → SIGNAL_CUTOFF 적용.

**Judge-stage (#2)**: Gate A(PIT) 재검 + Gate B~F. **독립 재검증** (구현자 자기검증 신뢰 안 함 — AX-008 triangulation 정합).

---

## 5. Lean lane 에이전트 흐름 + 갭 처리

```
implementer(신설): 논문 → 전략스펙(signal + 논문비중 + 유니버스 + 리밸) → PIT#1
   → lean-forge: optimized run_all.R (optimized-backtest 스킬) + Return.portfolio + build_bt_result 계약 백테
   → essence_score 등급
   → Judge: PIT#2 + Gate A~F (Codex Round 유지) + 경량 crowding/concentration 인라인(갭1)
   → [pass] 승격 → Governor
```

**갭 1 — risk 에이전트 스킵 = Σ/crowding/tail 부재.** Judge Gate D(crowding)/E(concentration) + Governor admission이 소비.
- **처리**: Judge가 **concentration(holdings에서 자명) + 경량 crowding_score 인라인 산출(advisory 라벨)**. full tail/stress는 **S5-on-reject로 이연**.
- Governor 진입 시 **book-marginal ΔIR ≥ 0.05 (수익률 시계열로 계산, book_optimizer.R 재사용) + crowding sanity 유지** (measurement-graduation §4 불변). 리스크 뷰 부족이 admit 막으면 = reject 사유 → S5. **risk 영구면제 아님, reject 시 회수.**

**갭 2 — lean lane은 자기완결 논문에만.** 진입 precondition: **논문이 비중결정 방법론 명시했는가.**
- YES → lean lane.
- NO (신호만) → 비중결정 부재 → **QEPM full lane** (optimizer 필요). lean 부적격.

---

## 6. 승격 → QEPM (Governor부터) + S5 기각-강화 루프 (도훈)

```
승격 전략 → Governor PG0~PG3
   → [ADMIT] book_state.json (수동 + 도훈 confirm — 비가역 자본게이트)
   → [DEFER/REJECT] → 옛 S5(Mutation) 차용
        → full QEPM(alpha→risk→optimizer→forge→judge→governor)로 강화
          (overlay / risk-aware sizing / optimizer 비중 재설계 / 직교성 보강)
        → 재심사
```
- S5 Mutation = 전략 강화 단계 (pit.md "오버레이는 S5 Mutation 또는 Optimizer/Forge에서만"). 기각이 폐기가 아니라 **full QEPM 머신으로 escalate해 강화** — lean(빠름)과 full(강함)의 자연스러운 계층.
- 승격 자동화(문턱) — 단 events.jsonl + telegram 로깅 + **도훈 veto** + 동시 in-flight rate-cap(OOM 교훈). 문턱 = `constraint_defaults.json::alpha_search_promotion` (Judge PASS + portfolio-α t≥2.95 + net_IR>0.2, measurement-graduation §3 정합).

---

## 7. Integrity Wall (격리 + hook)

- 네임스페이스: 알파서칭 작업물 `stage_artifacts/alpha_search/{idea_id}/`. **승격(Judge PASS) 시에만** canonical 이름 복사 → QEPM 편입 (artifact-naming.md 정합).
- 신규 hook `alpha_search_wall.sh` (PreToolUse[W]): **계약 미경유** 백테 수치가 registry/methodology/book_state로 쓰이면 block. (계약 경유분은 허용 — §3.)
- 기존 정합: `backtest_contract_audit.sh` (audit FAIL 차단) + `discovery_graduation_gate.sh` (graduation은 Governor 영역).

---

## 8. 재사용 자산

| 단계 | 자산 |
|---|---|
| 논문→코드 | `alpha-research` agent (신규 팩터 직접설계 가능) + `kr-inverse-pattern-miner` |
| PIT | `pit_enforcement.R` + `lookahead_detector.R` + `bear_date_audit.R` |
| 전기간 백테 | `02_Infrastructure/contracts/build_bt_result()` (10-component 계약) |
| FF5/Carhart/FM | `ff5_attribution.R` + `carhart_4factor.R` (Judge attribution 입력) |
| 스코어/진단 | `strategy_analyzer.R` + `hurdle_gate.R` |
| 차트2 | `reports/report_charts.R` |
| 텔레그램 | `telegram/telegram_notify.R` (`tg_agent_brief`) |
| Judge/Governor | `judge` / `governor` agent (입력만 alpha_search bt_result로 적응) |
| 병렬 | `qvest-multi-track` skill |

---

## 9. 구현 작업 목록 (승인 후)

1. **implementer role 신설** (`.claude/agents/strategy-implementer.md`) — 논문→전략스펙(signal+논문비중+유니버스+리밸)+PIT#1. precondition(비중방법론 명시) 분기. `agent_role_guard`에 **lean-mode weight 작성 예외** 등록(optimizer 부재 → weight 충돌 상대 없음).
2. **lean-forge 모드** — forge가 자기완결 전략을 `optimized-backtest` 스킬로 run_all.R + `Return.portfolio` + `build_bt_result` 실행(3-package 통합 없이). → essence_score 등급.
3. **`/alpha-search` entrypoint** skill — idea_id 입력 → implementer → lean-forge → essence_score fast-lane.
4. Judge 적응 — alpha_search `bt_result` 입력 수용 + 경량 crowding/concentration 인라인(갭1) + Gate A PIT#2 (Codex 유지).
5. Governor 적응 — alpha_search 승격분 PG entry + book-marginal ΔIR(수익률 기반) + S5-on-reject 라우팅.
6. S5 Mutation 경로 — 기각 전략 → full QEPM 강화 (risk/opt/overlay 투입).
7. `alpha_search_wall.sh` hook + settings.json 등록 (격리 네임스페이스 → registry/book 차단).
8. `constraint_defaults.json::alpha_search_promotion` 문턱 블록.
9. CLAUDE.md Active Path dual-lane 명문화 + 본 SOT 정식 발행.

---

## 10. 결정 (2026-05-31 잠금)

- **갭1** ✅: Judge 경량 crowding/concentration 인라인 + Governor book-marginal 유지 + full risk/tail은 S5-on-reject 회수.
- **Codex Round** ✅: implementer 생략(설계만 — lean-forge 측정 분리로 firewall 확보) / **Judge 유지**(무결성).
- **승격 veto** ✅: 별도 hold 없음 — **Governor admission이 이미 수동+도훈 confirm**(비가역 자본게이트)이라 그것이 human checkpoint. 승격은 events.jsonl+telegram 로깅만.
- **command** ✅: `/alpha-search` **독립 command**.
- **batch 동시성** ✅: build_bt_result ~8GB/건 → **동시 ≤ 2**(OOM 교훈).

---

## 11. Change log
- 2026-05-31 v0.3 DRAFT: 아키텍처 정정 — "forge 스킵" → **risk/opt agent만 스킵, forge는 lean 모드 유지**(Forge 전용 optimized-backtest 코딩 스킬 소유). **implementer role 신설**(설계) ≠ lean-forge(측정) firewall(AX-008). 등급=essence_score, 포트수익률 구성=Return.portfolio(R 브릿지, 언어무관). §10 결정 5건 잠금. 스코어 체계(essence_score)·스킬 계약정합은 구현 완료(커밋 30547ef/f898fd6).
- 2026-05-30 v0.2 DRAFT: 도훈 재설계 반영 — lean lane이 전기간 백테 실측(계약경유) + EW의무폐기/논문비중 + (구)forge 스킵 + Judge부터 + PIT 2중 + Governor부터 편입 + S5 기각-강화 루프. 권위 기전을 advisory→contract-backed로 전환. 갭2건 명시. (v0.3에서 forge 스킵 정정.)
- 2026-05-30 v0.1 DRAFT: 초안 (advisory-only triage). v0.2로 대체.
