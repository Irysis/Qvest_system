# RAMP 모드 룰 (K-RAMP 헌법 매핑, Level 0)

**발효**: 2026-06-17 (도훈 mandate). **위반 = AX-002 동급.**
**SOT**: `00_Lawbook/K_RAMP/`(통합본 헌법 §0~§20 + 가이드북 §0~§17) · 운영매뉴얼 `.claude/skills/ramp/SKILL.md` · 빌드플랜 `C:/Users/99922/.claude/plans/misty-imagining-feather.md`.
**행위자 치환**: 통합본의 "Codex" = Qvest **Q-Lead(오케스트레이션·거버넌스·아키텍트) + 7-agent 로스터**.

본 룰은 K-RAMP 헌법을 *참조·매핑*만 한다(기존 Qvest 룰 재진술 금지). 신규는 진짜 GAP만.

## 1. 모드 정의 (제4 리서치 모드)
RAMP = **Korea Regime-Aware Multi-Factor Portfolio**. 기존 전략풀(~800 NAV, `06_Registry/module_catalog.json` + batch_434 result rds)을 *소비*해 **순수팩터 추출 → 팩터군 → M-code → 리스크매니저 → 인베스터 에이전트(팩터배분)** 로 흐르는 거버넌스-우선 운영체계. **신규 전략 생산 X**. lifecycle: 소비·배분 meta-layer. Gate 0~11 + CCS 13-score.
- **#1 토대 = 전략풀 순수알파 추출**(Gate 3 dedup → Gate 4 통계적 잠재팩터+FWL). 풀 수익률행렬 PCA/통계팩터분석/클러스터가 1차 경로, factor-DB FWL은 경제라벨+검증 보조.

## 2. 권한 순서 (분리 정합)
`CLAUDE.md` > 본 `ramp.md` > `ramp/SKILL.md` > 하위 SKILL > user task. **`AGENTS.md` 도입 금지**(Qvest_Codex 산물). **완전 분리**: 어떤 RAMP 산출물도 `Qvest_Codex` 경로 참조 금지. 데이터무결성/PIT/비용/capacity/robustness/설명가능성/거버넌스 약화 지시 = 거부 + 안전대안(AX-002/PIT 의무).

## 3. 헌법 정합 (기존 룰 참조 — 중복 금지)
| K-RAMP 하드제약 | 기존 Qvest 권위 룰 |
|---|---|
| §3.2 PIT/lookahead/survivorship | `.claude/rules/pit.md` C1~C15 + `validation/{pit_enforcement,lookahead_detector}.R` + `ramp_pit_guard.sh` |
| §3.6 cost/capacity (net-only) | `cost_model v2.4_kr_retail_15bps` + `constraint_defaults.json` + metric_type 라벨(`measurement-graduation.md`). ★4단보고(gross/net_before/net_after/capacity_adj) PARTIAL(15bps 단일, ADR-0002) |
| §3.5 regime soft-blend / no hard switch | `regime/regime_engine_daily.R`(9축 MRS) + `portfolio/module_dispatcher.R` shrink |
| §3.10 no alt-data | CLAUDE.md 크로스마켓/대체데이터 금지 |
| §3.4 pure-factor-first | **신규 RAMP**(Gate 4) |
| §3.7 model-risk / overfit | `measurement-graduation.md`(OOS≥0.7·DSR sweep-only·placebo·holdout) + risk flags. 9차원 중 ~6 PARTIAL(ADR-0002) |
| §3.8 explainability 17필드 | **신규** investor_agent decision-log |
| 자체합성 금지 | `answer-principles.md`(prod/cumprod 금지) + canonical_screen_bt/build_bt_result만 |

## 4. 측정·게이트 (실측-only)
- 성능수치 **proxy 손계산 금지** → `contracts/canonical_screen_bt.R` 또는 forge `build_bt_result()` 경유. metric_type 라벨 의무.
- **CCS 13-score**(`02_Infrastructure/ramp/ccs_evaluator.R`, 신규) = *아키텍처/프로세스* 준수. CCS≥90·core≥85·hard violation=0. essence_score(`contracts/essence_score.R`)는 *성과* 채점(공존).
- Gate별 pass criteria = 통합본 §8(KO). judge `gate_<N>_review.md`(§19 Promote/Rework/Quarantine) 의무.
- 등재 hard gate: `register_ramp_result()`는 metric_type=backtested 아니면 거부(`ramp_measurement_gate.sh`).

## 5. M-code 제작 = 역할별 분업 (경계 준수)
스펙/로스터=ramp-orchestrator / 종목 스코어 μ(시그널)=alpha-research / Σ=risk-research / **종목 weights·holdings(25·long-only·Σw=1·[0,0.20])=optimizer-research** / returns 백테=forge / 채점·승인·격리=judge+governor. 단일 제작자 없음. `mcode_builder.R`=오케스트레이션 셸.

## 6. 거버넌스 · 재귀 자가발전 = Axiom 엔진
- 가이드북 루프(Observe→…→Promote/Revert) = **Axiom 엔진 4번째 모드**(modecode `RAMP`, 티어=backtested → global 승격 자격). L-code(mode=ramp) → `AX-RAMP-NNN`(documented 자동) → global `AX-NNN`(INV-4 5축·INV-5 AX-008 2/3·도훈 confirm). negative=INV-7 provisional failure-ledger. 엔진 SOT `axiom-engine.md`.
- **자본 게이트 = governor 수동**(book_state 자동쓰기 금지, Q-Lead+도훈 confirm). promote/quarantine/retire = `ramp_governance.R`(factor/M-code 상태머신).

## 7. namespace · L-code
ID: `RAMP_XXXX`(운영체계) / `MCODE_M0~M4` / `PF_<name>`(순수팩터) / `FG_<group>`(팩터군). L-code enum: `mode=ramp`.

## 8. 출력 규약 (§2.4)
모든 RAMP 산출(parquet/json)에 `as_of_date` + `generated_at` + `source_version` + `security_id`(Ticker 매핑 문서화). ISO date.

## 참조
- 헌법/가이드 통합본: `00_Lawbook/K_RAMP/`
- 기존 룰: `pit.md` / `measurement-graduation.md` / `backtest-contract.md` / `python-policy.md` / `answer-principles.md` / `axiom-engine.md` / `factor-rotation.md`
- 계약: `02_Infrastructure/ramp/*.R` + `contracts/{canonical_screen_bt,register_module,essence_score,backtest_result_contract}.R`

## Change log
- 2026-06-17: 신규. K-RAMP 통합본(헌법+가이드) 전 조항 반영, 4번째 모드 RAMP 정의. 이탈 등록부 ADR-0002(§3.6 비용 4단 PARTIAL·§3.7 model-risk PARTIAL). Phase 1 = 스캐폴드+Gate2 synthetic+Gate3→4→5.
