# Qvest Index — 프로젝트 지도

**v10.01 — 목표 역산형 1계층 리서치 · 2계층 로테이션 · BOOK · Judge=PIT 전담 · 행동 카드(위기 방어)** (2026-10-14 정리판)
버전·모델 표기의 단일 출처는 `CLAUDE.md` 첫 줄이다 — 여기 다시 적지 않는다. 버전을 바꾸지 않는 갱신은 `CHANGELOG_constitution.md` 에 "(버전 미변경)" 절로 남긴다.

> 쓰는 법: 요청을 받으면 **§3 찾는 법**에서 첫 파일을 고른다. 개수·목록은 박제하지 않는다(파일시스템 · 등록부가 정본).
> 옛 설계안 · 패치안 · v10 이전 실험은 2026-10-14 정리로 프로젝트 밖 보관소로 갔다(§5).

---

## 0. 정본 계층 — 무엇이 무엇을 이기나

| 층 | 위치 | 성격 |
|---|---|---|
| 1 | `CLAUDE.md` | 헌법 — 버전 · 축 · 등급 · 절대 규칙 · 커밋 규칙 |
| 2 | `.claude/rules/` | 자동 적재 2종(`pit.md` · `lean-loop.md`) + 경로 트리거 4종(axioms · backtest-contract · measurement-graduation · python-policy) |
| 3 | `.claude/skills/` · `.claude/agents/` | 절차와 에이전트 정의(research-program · alpha-search · strategy-rotation · judge …) |
| 4 | `02_Infrastructure/docs/rules/` | 확장 룰 — 필요할 때 읽는다(효력 동일) |
| 5 | `04_Research/01_reports/l1_prescription_redesign_20261013/README.md` | v10.01 설계 정본(결정 D1~D16 · 처방 루프 · 투자철학 헌장 · 에이전트 편성) |
| 6 | `06_Registry/decision_register.json` | 도훈 결정 기록 — 결정 id 로 찾는다(writer `reinforcement/reinforce_ledger.R::dr_open · dr_resolve`) |
| 7 | `02_Infrastructure/docs/CHANGELOG_constitution.md` | 버전 계보 · 변경 이력(최신이 위) |
| 8 | `00_Lawbook/specs/` | 계약 명세 원전 — 결과 계약(`backtest_result_contract.md`) · 답변 원칙 · Judge PIT · 공리 설계(r7) · AX-001 개정 |

## 1. Active SOT (CLAUDE.md ★Active SOT 와 같은 목록 — 부팅 C8c 가 대조한다)

- `.claude/rules/lean-loop.md` — 1계층 루프
- `.claude/skills/research-program/SKILL.md` — 1계층 프로그램 절차(라운드 · 측정 계약 · 처방 루프 도구)
- `.claude/skills/strategy-rotation/SKILL.md` — 2계층
- `02_Infrastructure/docs/CHANGELOG_constitution.md` — 계보
- 함께 보는 것: `02_Infrastructure/docs/rules/quant-identity.md`(페르소나) · `06_Registry/book/book_registry.json`(BOOK · writer `02_Infrastructure/book/book_registry.R`) ·
  `02_Infrastructure/docs/qvest_v8_4_asymmetry_ml_sot.md`(비대칭 표적 방향 근거 · CLAUDE.md 가 retain) · `02_Infrastructure/docs/qvest_ast_v1_1_sot.md`(AST · PIT C4 참조)

## 2. 폴더 지도

| 폴더 | 무엇 | 누가 쓰나 |
|---|---|---|
| `00_Lawbook/` | 이 지도 · 계약 명세(`specs/`) · 정리 원장(`reorg_20261014_manifest.json`) | 사람 · Q(정리 때) |
| `01_Literature/` | 논문 원문 | 읽기 전용 |
| `02_Infrastructure/` | 코드 — 계약(`contracts/`) · 러너(`alpha_search/` · `replication/` · `reinforcement/`) · 프로그램(`programs/`) · 레인(`ops/`) · 훅(`hooks/`) · 데이터(`data/`) · 문서(`docs/`) | Q(수리) |
| `03_Universe/` | 유니버스 원천 | 데이터 갱신 |
| `04_Research/programs/` | v10.01 리서치 프로그램 라운드(P0~P4 · 사전등록 · 측정 · 평가 스크립트) · `_supervision/` 감독 기록 · `_lib/` 공용 도구 | 라운드 |
| `04_Research/strategies/` | 논문 엔진(충실구현 · `RP_AUTO_*` · 청정 레인 `RP_AUTO_CLEAN_*`) · 셀 기저 | 레인 · 세션 |
| `04_Research/01_reports/` | 보고서 · 설계안(`<주제>_YYYYMMDD/`) — 현행 설계 + 코드가 근거로 인용하는 것만 남겼다 | Q |
| `04_Research/factor_rotation/` · `regime_comparison/` · `l2_role_rotation/` | 2계층 실행 코드 · 국면 신호(데이터 갱신이 `msm_update.R` 를 부른다) · 2계층 역할 연구 | 2계층 · 데이터 갱신 |
| `04_Research/advisor/` · `paper_notes/` · `dart_census/` | QEPM 어드바이저 · 논문 노트(검색 색인 원천) · DART 감사 입력 | 해당 도구 |
| `04_Research/90_legacy/` | 정리 전부터 있던 사료 묶음(읽기 전용) | — |
| `05_Production/` | 실운영 — 수정 금지(`promote_to_production()` 만) | — |
| `06_Registry/` | 등록부 · 원장 · 결정 기록 — writer 함수 경유 | writer |
| `08_Tests/` | 검사 배터리(`hooks/run_all_hooks.sh`) | Q |
| `stage_artifacts/` | 측정 산출물(`replication/` · `programs/` · `l_code/`) | 계약 |
| `qepm/` | QEPM(동결) · 관측 로그 | — |

## 3. 찾는 법 — 요청 유형별 첫 파일

| 요청 | 먼저 볼 곳 |
|---|---|
| 지금 상태 · 다음 할 일 | `/qvest` 부팅 · `Rscript -e "source('02_Infrastructure/programs/program_registry.R'); writeLines(pr_status_lines())"` |
| 셀 · 라운드 · 레인 코드의 뜻 · 표준 용어 | `00_Lawbook/GLOSSARY.md`(1계층 용어집 — 단계 · 하는 일 · 담당 에이전트 · 모델/노력) |
| Q 가 스스로 정하는 것 · 도훈에게 올리는 것(자율 판단 근거) | `00_Lawbook/specs/q_autonomy_decision_framework.md` |
| 세션이 끊긴 작업 이어 가기 | 부팅 `Resume:` 줄 · `python -X utf8 02_Infrastructure/programs/session_resume.py show` |
| 인쇄용 PDF 만들기 | `Rscript 00_Lawbook/tools/md_to_print_pdf.R <in.md>` · 서식 규칙 `02_Infrastructure/docs/rules/pdf-output-style.md`(현대하모니 L · M · B) |
| 1계층 라운드 진행 · 처방 루프 | research-program SKILL · `04_Research/programs/<프로그램>/<라운드>/` · 사전등록 `stage_artifacts/programs/` |
| 논문 충실구현 | alpha-search SKILL · 요청 `06_Registry/replication_request.json` · 레인 `02_Infrastructure/ops/rf_replication_auto.sh` |
| 등급 · 성과 수치 | 산출 디렉터리의 `authoritative_remeasure.json`(손계산 금지) · 행동 카드 `behavior_card.json` |
| 측정 축 · 고정 축 | `02_Infrastructure/worktask/constraint_defaults.json::measurement_axis` · `contracts/measurement_axis.R` |
| 왜 이렇게 설계했나 | v10.01 설계 README · `decision_register.json`(결정 id) · CHANGELOG |
| PIT 질문 | `.claude/rules/pit.md` · `02_Infrastructure/validation/` |
| BOOK | `/book` · `06_Registry/book/` |
| 2계층 | strategy-rotation SKILL · `04_Research/factor_rotation/run_wf_ensemble.R` |
| 과거 실험 · 옛 설계 | 기억 카드 → 정리 원장(§5) → 보관소 또는 git 태그 |
| 텔레그램 | qvest-telegram SKILL §0 · `tg_agent_brief()` · 1계층 `prep_send` |
| 커밋 | CLAUDE.md 커밋 규칙(작업 단위 · 그 경로만 · 서술형) |

## 4. 자주 쓰는 명령

| 명령 | 용도 |
|---|---|
| `/qvest` | 부팅 → 계층 질문 |
| `/alpha-search` · research-program(Skill) | 충실구현 1편 · 1계층 라운드 |
| `/strategy-rotation <track>` · `/book` · `/advisor` | 2계층 · BOOK · QEPM 자문 |
| `bash 08_Tests/hooks/run_all_hooks.sh` | 검사 배터리 |
| `bash 02_Infrastructure/ops/boot_currency_check.sh` | 헌법 · 지도 정합(부팅) |
| `Rscript 02_Infrastructure/tools/hypothesis_index.R lookup <kw>` | 과거 negative 조회(사실 기록 · 금지 목록 아님) |
| `bash 04_Research/programs/_lib/run_tick_once.sh` | 무인 충실구현 tick 1회(세션에서) |

## 5. 정리 기록 (2026-10-14)

- 도훈 "삭제할 건 과감하게 삭제하고 폴더를 직관적으로" — 옛 설계 SOT(v6.4~v8.3) · 법전 옛 판(admission v3.x · v1.4 · v55 · v6 개정) · RAMP · v7 DEPRECATION/VERSIONING ·
  v10 이전 실험 폴더 21개 · 코드가 인용하지 않는 보고서 53건 · 루트 잔재를 프로젝트 밖으로 옮겼다.
- 목록과 사유 = `00_Lawbook/reorg_20261014_manifest.json` · 보관소 = `99_Archive/reorg_20261014/<원래 경로>` · 추적 파일 복원 = `git checkout pre-reorg-20261014 -- <경로>`.
- 계약 명세 5건은 `00_Lawbook/Multi_Agent/` · `Axiom_아키텍처/` 에서 `00_Lawbook/specs/` 로 옮기고 참조를 고쳤다.
- 보관소는 확인 뒤 지워도 된다(도훈 판단) — 지우면 미추적 산출물(실험 출력 parquet 등)은 되살릴 수 없다.
