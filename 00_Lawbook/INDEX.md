# Qvest Index

**3개월 후 도훈이 즉시 찾을 수 있게** — 1 page navigation + debug map.
**v10.2 — 2계층 리서치(팩터전략/전략로테이션) · BOOK · Judge=PIT 전담 · 강화 LLM 재귀 루프(횡단면 오버레이 축)** (2026-09-03 갱신. 직전 v10.1, 전문은 `CHANGELOG_constitution.md`)

> ★**숫자 박제 금지** — 이 문서가 v8.1에서 2개월 낙후된 기전이 "8 axioms / 30 hook / 203 paper notes" 같은 **개수 하드코딩**이었다. 개수·목록은 아래 *확인 명령*으로 위임하고, 본문은 **어디를 보는지**만 적는다.

---

## 0. 헌법 계층 (어디가 정본인가)

| 층 | 위치 | 성격 |
|---|---|---|
| 1 | `CLAUDE.md` (루트) | **현행 헌법 본문** — 모델 표기·모드·제약의 단일 정본 |
| 2 | `.claude/rules/` | **autoload 2종 (v9 2026-08-23)**: pit / lean-loop. 나머지(axioms · backtest-contract · measurement-graduation · python-policy)는 같은 폴더에 있으나 `paths:` 프론트매터로 **경로 트리거 지연 적재**. `answer-principles`는 `02_Infrastructure/docs/rules/`로 이동 |
| 3 | `02_Infrastructure/docs/rules/` | 확장 룰 (on-demand Read, **효력 동일**) — harness / axiom-engine / r-portability / continuity-firewall / caching / factor-db / lockbox-scope / artifact-{naming,storage} / strategy-rotation / ramp(퇴임·사료) / research_philosophy / data_table_shift_convention |
| 4 | `00_Lawbook/` (본 폴더) | **원전 법전** + INDEX + DEPRECATION — 2·3층의 상당수가 여기서 파생 |

세션 모델명은 **여기 재기입하지 않는다** — 정본은 `CLAUDE.md` Active Version 절 (재기입 지점이 동시 낙후된 전례).

## 1. Active SOT

- `.claude/rules/lean-loop.md` — **1계층 루프 정본 (v10)** (입력·축 2층·충실구현 6단계·강화 분기·예산)
- `.claude/skills/strategy-rotation/SKILL.md` — 2계층 정본 (논문 온디맨드·B+ 풀 2단 게이트·강화 무한·Judge→BOOK)
- `.claude/skills/reinforce/SKILL.md` — 강화 프로세스 정본 (L1 ≤20회 / L2 무한 · 원장 reinforce_ledger_l1/l2)
- `02_Infrastructure/docs/rules/quant-identity.md` — 페르소나 정본 (최정상급 퀀트 · 냉소는 방법론 · 논문 근거 의무)
- `06_Registry/book/book_registry.json` — BOOK 정본 (writer = `02_Infrastructure/book/book_registry.R` 경유만)
- `02_Infrastructure/docs/qvest_v8_4_asymmetry_ml_sot.md` — v8.4 리서치 방향 SOT (비대칭 알파: 4 lane A/D/B/C, 금지 4종, 부활 조건 — v9에서도 방향 근거로 retain)
- `02_Infrastructure/docs/qvest_v8_3_alpha_discovery_sot.md` — v8.3 발굴 재편 (골격 승계 — dual-basis · 프론티어 큐 · 지식 환류)
- `02_Infrastructure/docs/qvest_v8_1_sot.md` — v8.1 설계 SOT (measurement governance + module flow)
- `02_Infrastructure/docs/qvest_ast_v1_1_sot.md` — AST 계층 v1.1 (alpha 3층 스펙 + PIT 3중 예방)
- `02_Infrastructure/docs/qvest_modes_sot.md` — 모드 헌법 (모드별 자기평가 + 공유 정직 게이트)
- `02_Infrastructure/docs/qvest_v8_0_upgrade_plan.md` — v8.0 base (retain) · `qvest_v6_4_sot.md` — v6.4 base (read-only)
- `02_Infrastructure/docs/qvest_legacy_boundary.md` — v55/S0~S7 격리 정책
- `02_Infrastructure/docs/CHANGELOG_constitution.md` — 버전 계보·릴리스 상세 (CLAUDE.md에서 분리)
- `00_Lawbook/DEPRECATION.md` — active vs legacy 자산 inventory + EOL

## 2. Daily Use CLI

| Command | 용도 |
|---|---|
| `/qvest` | Session start + bootstrap (gap 확인 + harness health) |
| `/worktask` | WT lifecycle CRUD (QEPM 모드) |
| `/alpha-search` · `/strategy-rotation <track>` | 진입점 (기본 1단계 · 소비 계층). ★강화 프로세스는 무인 러너 뒤 자동 · `/ramp` 는 v9.21 모드 퇴임 |
| ~~`/qlead`~~ | ★v10 2026-09-03 퇴역 — `.claude/commands_retired_v10/`. 세션 진입점은 `/qvest` 하나 |
| `02_Infrastructure/observability/qvest_observe wt <ID>` | Per-WT timeline JSON (rebuild + dump) |
| `02_Infrastructure/observability/qvest_wt <ID>` | Per-WT ASCII pretty · `--active` book admit · `--recent N` |
| `02_Infrastructure/search/qvest_search "<q>" [--type T] [--rebuild]` | Unified search (lcode/wt/cert/paper/axiom/registry/lawbook) |
| `02_Infrastructure/tools/qvest_v8_ready --strict --json --no-write` | v8 readiness gate |
| `bash 08_Tests/hooks/run_all_hooks.sh` | hook dry-run 배터리 |

**지식 적립 2단 — 둘 다 해야 다음 라운드 Step 0 lookup에 도달**:
```bash
python 02_Infrastructure/axiom/lcode_harvester.py          # L-code → .cache/lcode_corpus.json
Rscript 02_Infrastructure/tools/hypothesis_index.R build   # ★build 필수
```
⚠ `hypothesis_index.R`을 **인자 없이 부르면 usage만 찍고 exit 0** — 호출자가 재빌드된 줄 오인한다(2026-08-13 실측: corpus엔 들어갔는데 index엔 없던 L-code 3건).

## 3. Debug Map

| 증상 | 1차 확인 file |
|---|---|
| Hook block 원인 추적 | `02_Infrastructure/hooks/qvest_hook_router.py` (policy 단일 진입) |
| Cert 발급 실패 | `02_Infrastructure/worktask/cert_rules.R` + `02_Infrastructure/hooks/policies/cert_rules.json` |
| State transition 거부 | `02_Infrastructure/worktask/state_machine.R` + `02_Infrastructure/hooks/policies/state_transitions.json` |
| Schema invalid | `02_Infrastructure/schemas/{packages,certs,state}/` (Draft-07) |
| Telegram 미발송/중복 | `02_Infrastructure/telegram/` + `qvest-telegram` skill — ★섹션 타입은 **항목 수**가 결정(bullet은 2개 이상), 실패는 JSONL 기록 |
| Stop hook이 턴을 block | `02_Infrastructure/axiom/continuity_gate.py` + `02_Infrastructure/docs/rules/continuity-firewall.md` — 통과는 `close_round()`(next_probe≥2·소비면·부활조건) |
| WT phase jump | `state_machine.R::sm_validated_advance` (force_waiver=TRUE 필요) |
| Cert backfill | `02_Infrastructure/ops/cert_backfill_audit.R` (--auto / --manual / --dry-run) |
| Measurement Coherence DRIFTED | `02_Infrastructure/portfolio/measurement_basis_audit.R` + bootstrap 자동 |
| FR pool에 proxy 유입 의심 | `02_Infrastructure/contracts/register_module.R` + `06_Registry/module_quarantine.json` |
| Search index stale | `02_Infrastructure/search/build_index.R` (`qvest_search --rebuild`) |
| R 스크립트가 Windows에서 조용히 실패 | `02_Infrastructure/docs/rules/r-portability.md` 금칙 6종 + `08_Tests/hooks/test_r_portability.R` |
| 과거 값이 소급 재서술됨 | append-only 계약: `02_Infrastructure/regime/{m4,regime}_append_only.R` — 원인은 대개 **전체표본 통계 or 외부 개정** |
| 부팅에 `boot-currency` WARN | `02_Infrastructure/ops/boot_currency_check.sh` (C0~C8c) — 문서가 헌법보다 낡았다는 뜻. WARN-only이나 **세션이 즉시 수리**가 원칙 |
| 산출물 위치 판단 | `02_Infrastructure/docs/rules/artifact-storage.md` + `06_Registry/hygiene_report.json` |

## 4. Flow 1-liners

**Hook flow**:
```
Tool → PreToolUse (safety_guard / axiom / agent_role / worktask_*)
     → Tool exec
     → PostToolUse (artifact_validator / pipeline_trigger / cert certifier / lineage_recorder)
     → Stop (auto_commit + research_continuity_guard)
```

**Cert flow (5 type, PostToolUse 자동 발급)**:
- `alpha_discovery` — alpha_package.json 4 AND (cor < 0.95 + mech ≥ 50 + factor_specs ≥ 1 + harvey_t ≥ 3)
- `sr_provenance` — forge_package.json 4 field (sr_realized + measurement_basis + weights_csv_dates + density)
- `forge_package_validated` — forge_package.json 8 field
- `schedule_fidelity` — optimization_package.json density ≥ 0.95 OR infeasibility_report
- `governor_concord` — book_state ↔ admission match (or with_waiver)

**State machine (11 phase)**:
```
SPEC_APPROVED → ALPHA_DONE → RISK_DONE → OPTIMIZER_DONE → FORGE_DONE
              → JUDGE_PASSED → GOVERNOR_ADMITTED → COMPLETED
              (또는 ABORTED / JUDGE_FAILED / GOVERNOR_REJECTED → ABORTED)
```

**Self-Adversarial Challenge** (v8.2 — 외부 Codex Round 폐지, 모든 agent spawn):
```
1. Draft 작성 → 2. 메인 세션 모델 자체 적대검증 (모델 정본 = CLAUDE.md Active Version 절)
3. challenge_note.md 의무 (ACCEPT/PARTIAL/REBUTTAL) → 4. Final
- AX-008 3-source(Forge + Self-Adversarial + Architect) 중 2/3 PASS
- 구 codex_round_* 훅 폐지 (2026-06-30 도훈 mandate, 자산 archive: DEPRECATION.md)
```

## 5. Memory & Registry

**Axiom (2-Tier)** — `qepm/memory/axioms/`:
- `active/AX-{000,001,002,008}.json` — **active Law 4건**. AX-003/004/005/007은 2026-07-05 **Distilled 강등**(`deprecated/`, INV-7 재도전 대상 — enforcement 대상 아님)
- `active/modes/{alpha_search,factor_rotation,qepm,ramp}/` — mode-local `AX-<MODE>-NNN` (★디렉터리는 full name, 코드는 AS/FR/QPM/RAMP로 다름) · `candidates/` — pending
- `axiom_sot_map.json` — Documented ↔ JSON 매핑 · 엔진 SOT = `02_Infrastructure/docs/rules/axiom-engine.md`

**Knowledge**:
- `qepm/memory/README.md` — Memory layer SOT/lifecycle · `methodology_memory_v55_extensions.md` — active L-codes
- `06_Registry/knowledge_index.json` / `.md` — 지식 인덱스 (`02_Infrastructure/ops/build_knowledge_index.R` 산출 — ★루트 `ops/`는 **부재**, 접두 필수)
- `06_Registry/hypothesis_index.json` — **가설 검색면** (발굴 착수 전 lookup 의무. 빌더 = `02_Infrastructure/tools/hypothesis_index.R build`)
- `06_Registry/distilled_knowledge.json` · `revival_signals.json` — Distilled 탐색지도 + 부활신호

**v8.3/v8.4 운영 SOT** (발굴 착수 전 확인 의무):
- `06_Registry/alpha_frontier_queue.json` — **"다음에 뭘 시도할지" 상설 큐 SOT**. `dohoon_decision` 항목 세션 임의 착수 금지
- `06_Registry/layer_bottleneck_map.md` — "목표 갭이 어느 계층에 막혀 있나" 상시 실측 지도. 자율 라운드 선택은 이 지도를 따름
- `06_Registry/method_registry.json` — 논문 레인 등재 어댑터 (`register_method()`) · `continuity_cases.json` — Continuity Firewall 자가발전

**Registry / Observability**:
- `06_Registry/{strategy_registry,module_catalog,module_performance,module_quarantine,paper_registry}.json`
- `06_Registry/live_track/<ID>/` — 라이브 페이퍼트래킹 + holdout_interval
- `qepm/observability/events.jsonl` — append-only event ledger · `timelines/wt_*.json` — per-WT cache (regenerable)

> 개수·최근갱신·크기는 **자동 생성 존 INDEX**가 권위: `06_Registry/INDEX.md` (+ `02_Infrastructure` / `04_Research` / `08_Tests` / 루트 `ARTIFACTS.md`). 재생성 `Rscript 02_Infrastructure/tools/build_artifact_index.R` — **그 4개는 직접 수정 금지**(덮어씀). 본 파일은 수동 유지 대상이라 안전.

## 6. Schema Locations

- `02_Infrastructure/schemas/packages/` — alpha / risk / optimization / forge / judge_verdict / governor_admission
- `02_Infrastructure/schemas/certs/` — alpha_discovery / sr_provenance / schedule_fidelity / forge_package_validated / governor_concord
- `02_Infrastructure/schemas/state/` — book_state / governance_log / artifact_lineage / axiom
- 검증: `python 02_Infrastructure/hooks/qvest_hook_router.py validate-schema --schema <name> --package <path>`

## 7. Skills · Agents · Tests

- **Skills** `.claude/skills/` — 진입점(alpha-search/strategy-rotation/book/book-rebalance) · 절차(qvest-worktask/qvest-telegram/cleaner/reinforce) · 스타일(qvest-{alpha,risk,opt,attribution}-style) · 디버그(qvest-hook-debug) · 발굴(factor-db-discovery/kr-inverse-pattern-miner). ★퇴역(v10 2026-09-03) = `.claude/skills_retired_v10/`: ramp · execution · monitoring · qvest-cert-paths · ensemble-design · pg2-allocation · axiom-io
- **Agents** `.claude/agents/` — QEPM 체인(alpha-hypothesis → alpha-research → risk-research → optimizer-research → forge) + judge(PIT 전담, Grade A 후) + 1계층 alpha-search + 2계층 dispatch-orchestrator + BOOK book-tracker + ondemand architect. ★퇴역 = `.claude/agents_retired_v10/`: governor · execution · monitoring(→book-tracker) · blender · ramp-orchestrator · strategy-implementer. 상세 = CLAUDE.md
- **Commands** `.claude/commands/` — qvest / worktask / alpha-search / strategy-rotation / book. ★퇴역 = `.claude/commands_retired_v10/`: ramp(v9.21 모드 퇴임) · qlead(v10 진입점 일원화)
- **Tests** `08_Tests/` — 진입점 `08_Tests/hooks/run_all_hooks.sh`(hook dry-run) · `08_Tests/contract_regression/run_contract_regression.R` · `08_Tests/integration/test_wt_lifecycle_e2e.R` · `08_Tests/integration/_e2e_cleanup_guard.sh`(CI gate). 스위트별 정체 = `08_Tests/INDEX.md`
- **Examples** `02_Infrastructure/docs/examples/qvest_workflows/` — 표준 WT 3종 (discovery happy / cert_fail / pit_violation)

## 8. Version Tags

| Tag | 내용 |
|---|---|
| `v6.4.0` | Harness Kernel Stabilization |
| `v7.0.x` | Hardening Release + Residue Hardening Patch |
| `v7.1.0-lite` | Solo Operator Productivity (qvest_search + qvest_wt + INDEX) |
| `v7.2.x` | v8.0 Design Readiness Gate + Memory Knowledge Hardening |
| `v8.0` | R/Python 1급 + 실측-only 거버넌스 (measurement-graduation) |
| `v8.1` | 3-Mode 헌법 + 논문 완전 복제 + register_module 표준화 |
| `v8.2` | Codex Round 제거 → Self-Adversarial Challenge |
| `v8.3` | 알파 발굴 중심 재편 (dual-basis · 프론티어 큐 · 지식 환류) |
| **`v8.4`** | **비대칭 알파 중심 재편** — ML·수리통계 분포-표적 4 lane, 비-return 주력 해제 |

계보 상세·검증 이력 = `02_Infrastructure/docs/CHANGELOG_constitution.md`

## Maintenance

> ★**낙후는 이제 기계가 알린다 (2026-08-16)** — `02_Infrastructure/ops/boot_currency_check.sh`가 매 부팅에 감시(**WARN-only**, 차단 아님):
> **C8a** CLAUDE.md Active Version ↔ 본 문서 헤더 버전 · **C8c** CLAUDE.md "★ Active SOT" 나열 ⊆ 본 문서 §1 인용.
> 갱신은 여전히 **사람 몫**이다(이 문서는 자동 생성 대상이 아니다 — 담는 게 파일 목록이 아니라 판단이라서). 기계는 "어긋났다"까지만 말한다.
> ⇒ **헤더 4행의 `vX.Y` 표기는 파서 계약**이다. 포맷을 바꾸면 C8a가 먼저 깨진다. 부분 갱신 시에도 이 줄을 함께 고칠 것 — 낙후 원인 1위가 "본문은 고치면서 배너를 안 고친 것"이었다(07-03·07-04 두 번 편집됐는데 헤더는 06-12 그대로 → 한 문서 안에 세 vintage 공존).
> 검사 자신의 위반 주입 테스트 = `08_Tests/hooks/test_boot_currency.sh` (13/13, 실제 구판으로 검출력 실증).

- 인프라 reorg / 헌법 버전 전이 시 본 INDEX.md 갱신 (CHANGELOG에 "INDEX.md update" 의무)
- **자동생성 X** — Lawbook churn 결합 회피. `build_artifact_index.R`의 4개 존 INDEX와 역할이 다르다(그쪽=파일 인벤토리, 여기=**항해도**)
- ★**갱신 시 개수를 다시 박제하지 말 것** — 낙후의 기전이 그것이었다. 개수가 필요하면 확인 명령이나 존 INDEX로 위임한다
- ★**경로는 루트 기준 전체 경로로** — 축약(`ops/…`·`docs/rules/…`)은 grep으로 안 걸리고, 실제로 구판이 `state_transitions.json`·텔레그램 경로를 2개월간 틀린 자리로 가리키고 있었다. 예외는 바로 위 헤더가 상위 경로를 명시한 목록(§5 axiom 하위)뿐
- 갱신 후 **경로 전수 검증**(문서의 백틱 경로를 기계 추출 → `test -e`)을 돌릴 것 — 손으로 고른 목록은 빠뜨린다
- 새 CLI 추가 시 §2 + (해당하면) §3 update · 새 모드/룰 층 추가 시 §0 update
