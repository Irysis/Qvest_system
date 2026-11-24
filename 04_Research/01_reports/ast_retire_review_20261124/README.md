# AST 계층 정리안 — 2026-11-24

도훈 11-24 "AST 검사기 아직 기능하는게 있어?" → "네, 정리안 작성. 왠만하면 지우고 싶어".
작성 = 스타일 국면 브리핑 검토 세션. 이 문서는 **승인 전 정리안**이다. 아직 아무것도 지우지 않았다.

## 결론

AST v1.1(2026-07-25 도훈 승인)의 다섯 부분은 지금 실제로 일하지 않는다. 지운다.
- 스펙 언어 · 게이트 훅 · 정적 검사기 · 컴파일러 · 구조특징 사이드카

AST 작업에서 생겼지만 지금은 일반 기능이 된 셋은 남긴다.
- 일간 팩터 접근자
- 등록부 가용일 체계
- 팩터 등재 도메인 표

## 지금 상태 (11-24 재도출)

| 부분 | 증거 | 판정 |
|---|---|---|
| 게이트 훅 `02_Infrastructure/hooks/ast_spec_gate.sh` | 08-23 v9 에서 훅 라우터 폐지와 함께 등록이 풀렸다(`hooks/policies/router_dispatch.json` = RETIRED · `.claude/settings.json` 에 없음). 지금은 시험 배터리(`test_ast_spec_gate.sh` · `ops/hook_e2e_battery.py`) 안에서만 돈다 | 죽음 |
| 검사기 `ast/ast_verify.py` · 컴파일러 `ast/ast_compile.R` · `ast/operator_library.json` | 실행 경로 호출처 0. 원 소비자 QEPM(alpha-hypothesis · alpha-research · 워크태스크)은 09-25 동결. 예약 작업 0 · 무인 레인 · 아침 체인 호출 0(`06_Registry/pit_quarantine.json` 09-24 조사와 같음). 부르는 곳 = 시험뿐 | 죽음 |
| 사이드카 `contracts/ast_sidecar.R` + `essence_score.R` · `canonical_screen_bt.R` 의 기록 블록 | 채점 · 선별 검사마다 `06_Registry/ast_structure_log.jsonl` 에 한 줄씩 쓴다(fail-soft · 채점 무관). 18,303행 · 8.0MB · 깨진 줄 47 · 구조특징이 있는 행 105개(마지막 08-22). 최근 30일 1,720행(채점 1,349 · 선별 371)은 구조특징이 모두 빈 값이고, 내용은 사실상 '모든 채점의 등급 · PORT_t · OOS 기록'이다. 읽는 코드 0. 등록 훅 `arm_gen_read_guard.sh` 는 처방 쪽이 이 파일을 못 읽게 막는다(팩터별 전기간 PORT_t — 09-23 실수신 사고) | 기록만 쌓임 · 정보 경계 위험 표면 |
| 부팅 줄 `ops/bootstrap.sh` 655~679행 | 풀 부트스트랩이 사이드카 실전 수를 센다('Step 5 진입 N ≥ 30'). Step 5 는 한 번도 열리지 않았다 | 죽음 |
| 필드 지도 `06_Registry/ast_field_map_v0.json` | 07-25 자료 원천 인벤토리(58 그룹). 읽는 코드 = 지울 게이트 · 검사기 + C11 시험의 E4 선언 확인뿐. 줄 번호 · 수치는 07-25 판 | 문서로만 남음 |

## 지울 것 — 파일 (git rm · 되살리기 = 태그 `pre-ast-retire-20261124`)

| # | 경로 | 비고 |
|---|---|---|
| 1 | `02_Infrastructure/ast/` 전체 | `ast_compile.R` · `ast_verify.py` · `operator_library.json` · `tests/`(픽스처 5 · `run_fixture_battery.py` · `parity_factor_db_result.json`) — 추적 10개 + 추적 밖 `parity_run.log` · `__pycache__` |
| 2 | `02_Infrastructure/hooks/ast_spec_gate.sh` | 미등록 |
| 3 | `02_Infrastructure/contracts/ast_sidecar.R` | 사이드카 writer · 상태 함수 |
| 4 | `06_Registry/ast_structure_log.jsonl` | 8.0MB(git 이력에는 남는다) |
| 5 | `06_Registry/ast_operator_backlog.json` | AST 연산자 백로그 |
| 6 | `02_Infrastructure/docs/qvest_ast_v1_1_sot.md` | 퇴역 계층의 SOT — 계보는 CHANGELOG 한 줄로 |
| 7 | 시험 4개 | `08_Tests/hooks/test_ast_spec_gate.sh` · `08_Tests/hooks/test_ast_verify_dialect.sh` · `08_Tests/contract_regression/test_ast_sidecar.R` · `08_Tests/contract_regression/test_ast_monthly_asof_label.R` |
| 8 | `06_Registry/ast_field_map_v0.json` | 권고 = 지움. 남기면 낡은 문서로만 남는다 |

합계: 코드 · 문서 · 시험 약 229KB + 로그 8.0MB + 필드 지도 159KB.

## 지울 것 — 코드 블록 (사본 → 검사 → 원자 교체)

1. `02_Infrastructure/contracts/essence_score.R` 1060~1108행 사이드카 블록.
   - 인자 `ast_features` · `strategy_id` · `active_regime` · `sidecar_log` 는 **받기만 하고 무시**한다(설명 주석 1줄).
   - 인자를 지우면 `sidecar_log = FALSE` 를 넘기는 호출이 깨진다: `contracts/remeasure_from_holdings.R:536` · `contracts/selection_accounting.R:144` · 시험 `test_essence_oos_components.R` · `test_grade_v3.R`.
2. `02_Infrastructure/contracts/canonical_screen_bt.R` 412행부터의 사이드카 블록. 인자 `ast_features` 는 무시.
3. `02_Infrastructure/ops/bootstrap.sh` 655~679행 부팅 줄.

## 지울 것 — 목록 · 검사 정리

- `08_Tests/hooks/run_all_hooks.sh` 의 AST 스위트 4줄과 그 주석.
- `02_Infrastructure/ops/hook_e2e_battery.py` 의 `ast_spec_gate` 사례 2개.
- `02_Infrastructure/ops/hook_integrity_check.sh` REQUIRED_DISPATCH 의 `ast_spec_gate.sh` 줄.
- `08_Tests/validation/test_pit_c11_positive_control.R` H절(ast_verify · 돌연변이 4종)과 E4 필드 지도 확인. `test_c11_detector_r1.R` C절(ast_verify 해외 클램프). 나머지 절(C11 검출기 · `pit_verify_fred_lag`)은 그대로 둔다.
- `arm_gen_read_guard.sh` · `hooks/policies/arm_gen_read_guard.json` · 시험 O07 의 `ast_structure_log` 차단 패턴. 파일과 writer 가 함께 없어지므로 권고 = 지움(다른 차단 패턴은 그대로).
- 색인: `00_Lawbook/INDEX.md` · `06_Registry/INDEX.md` · `06_Registry/index_descriptions.json` 의 해당 줄.
- 계보: `02_Infrastructure/docs/CHANGELOG_constitution.md` 퇴역 한 줄 + 결정 등록부 `AST-V11-RETIRE-20261124`(`reinforce_ledger.R::dr_open` → 도훈 결정 → `dr_resolve`).
- 손대지 않는 것:
  - `stranded_repairs_audit.sh` 원장 정규식의 `ast_structure_log`(무해).
  - 자동 생성물(`wiring_map*.json` · `hygiene_report.json` · `artifact_index.json` — 다음 생성 때 따라온다).

## 남길 것

- `02_Infrastructure/factor_db/factor_db_connector.R::load_daily_factors()` — 일간 팩터 정식 접근자(C15). AST v1.1 §3 에서 나왔다.
- 팩터 등록부 가용일 체계 + `factor_db/registry_migrate_ast_v11.py`(DOMAIN_MAP — `add_factor.R` 이 새 팩터 등재 때 읽는다) · `factor_db/registry_validate_availability.py`. 이름에 'ast' 가 있어도 등록부 기능이다.
- 동결된 QEPM 문서의 AST 언급(`.claude/agents/alpha-hypothesis.md` · `.claude/skills/qvest-worktask/SKILL.md` · `02_Infrastructure/prompts/alpha_research_init.md` · `02_Infrastructure/worktask/schema.json`) — 동결 중이라 손대지 않는다. QEPM 을 다시 열면 태그에서 AST 를 되살려야 한다.
- 역사 기록(CHANGELOG 본문 · 훅 MANIFEST · 아카이브 · 원장 텍스트 · `factor_registry.json` 메모)은 그대로 둔다.

## 순서 · 검증

1. 태그 `pre-ast-retire-20261124`.
2. 두 채점 계약은 사본에서 블록을 지운다. 같은 입력으로 옛 · 새 함수를 돌려 반환값이 `identical` 인지 실증한다(합성 bt 몇 개 + 기존 계약 시험).
   - 사이드카가 쓰던 로그 파일에 쓰기 0 인지도 확인한다.
3. 원자 교체 → 파일 git rm → 목록 · 시험 정리.
4. 남은 참조 재검색(비주석 0) + 빠른 층 배터리에서 손댄 스위트만 확인한다(도훈 11-12 '테스트 좀 그만하자').
5. 서술형 커밋 · 결정 등록부 · CHANGELOG.

`02_Infrastructure/factor_db/` 는 남길 것만 있어 손대지 않는다. 그래서 배당 수리 사슬과 무관하게 진행할 수 있다.
채점 계약은 레인이 읽는 중이어도 원자 교체라 안전하다. 이미 읽은 레인은 옛 판으로 끝나고, 채점 값은 같다.

## 얻는 것 · 잃는 것

- 얻는 것:
  - 죽은 코드 약 229KB · 시험 4개 · 부팅 줄 하나가 사라진다.
  - 채점마다 파일을 한 번 더 쓰는 일과 하루 약 60행씩 커지는 8MB 로그가 사라진다.
  - 전기간 등급 · PORT_t 가 한 파일에 쌓이는 정보 경계 위험 표면이 없어진다.
- 잃는 것:
  - QEPM 을 다시 열 때 AST 게이트 · 검사기가 없다(태그에서 되살림).
  - 07-25 자료 원천 인벤토리 문서(필드 지도)가 사라진다(git 이력 · 태그에 남음).
