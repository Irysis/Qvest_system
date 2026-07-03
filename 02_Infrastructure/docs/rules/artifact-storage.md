# Artifact Storage (산출물 저장 규칙) — Level 1

**발효**: 2026-07-04 (도훈 mandate — "저장 규칙 신설 + 폴더 정리" 구조 재편)
**로드 시점**: 산출물(결과 파일·데이터·보고서·로그·스크립트)의 저장 위치를 판단할 때 on-demand Read.
**적용 대상**: Q-Lead + 모든 agent + hook/스케줄러가 생성하는 모든 파일. 언어(R/Python/셸) 무관.

---

## §1 저장 4원칙 (위치 결정 규칙)

파일을 쓰기 전에 아래 4개 질문 순서로 위치를 결정한다.

| # | 질문 | 위치 | 성격 |
|---|---|---|---|
| ① | 특정 실험 런의 산출인가? | `stage_artifacts/<mode>/<run_id>/` | **불변 기록** — 생성 후 수정·이동 금지 |
| ② | 파이프라인이 재생성하는 canonical 데이터인가? | `outputs/<pipeline>/` | **최신본만** — 재실행 시 overwrite |
| ③ | 기계가 읽는 상태·큐·인덱스인가? | `06_Registry/` | 기계가독 JSON/CSV — 코드가 소비 |
| ④ | 사람이 읽는 보고서·분석인가? | `04_Research/<topic>/` | 사람용 md/차트 — 주제별 디렉토리 |

**각 위치의 정확한 역할 + 예시**:

- **① `stage_artifacts/<mode>/<run_id>/`** — 실험 런 단위 산출(중간 검증 json, 런 로그, verdict, challenge_note 등). 런이 끝나면 그 디렉토리는 감사 증거로 동결된다. 재현이 필요하면 새 run_id로 다시 실행한다(기존 런 덮어쓰기 금지). 예: `stage_artifacts/WT-D20260621_004/`, `stage_artifacts/reports/drawdown_frequency_kr_baseline_20260612.md`(레거시 평면 배치는 retain — 신규는 `<mode>/<run_id>/` 계층 의무).
- **② `outputs/<pipeline>/`** — 파이프라인 재실행이 항상 같은 자리에 다시 만드는 데이터(parquet/rds/csv). "이 파일의 최신본은 어디인가"에 대한 단일 답. 예: `outputs/ramp/pure_factor_scores.parquet`, `outputs/ramp/factor_group_scores.parquet`. 버전 병렬 보관 금지 — 구본이 필요하면 §4 Retention의 격리 절차를 따른다.
- **③ `06_Registry/`** — 레지스트리·큐·상태 파일. 코드가 계약으로 읽는다. 예: `module_catalog.json`, `strategy_registry.json`, `live_track/<ID>/holdout_interval.json`, `overlay_candidate_queue.json`. 쓰기는 반드시 해당 writer 함수(`registry_writer.R`, `register_module` 등) 경유 — 손편집 금지.
- **④ `04_Research/<topic>/`** — 사람용 보고서·분석 md·차트·리서치 스크립트. 주제 디렉토리 하나에 모은다. 예: `04_Research/pg2_forensics/b1_summary.md`, `04_Research/factor_rotation/fof_first_slice/superfactor_literature_survey_20260703.md`.

같은 실험이 데이터+보고서+레지스트리 갱신을 모두 낳으면 **세 곳에 각각** 저장한다(런 증거는 ①, 최신 데이터는 ②, 상태는 ③, 보고서는 ④). "편해서 한 폴더에 전부"는 위반.

## §2 루트 구조 고정 — 신규 루트 항목 생성 금지

루트는 아래 13항목으로 **고정**한다. 새 루트 디렉토리/루트 파일 생성 금지(필요하면 도훈 confirm 후 본 문서 개정이 선행).

```
00_Lawbook/  01_Literature/  02_Infrastructure/  03_Universe/  04_Research/
05_Production/  06_Registry/  08_Tests/  outputs/  qepm/  stage_artifacts/
CHANGELOG.md  CLAUDE.md   (+ ARTIFACTS.md 대시보드)
```

- `05_Production/`, `01_Literature/` = NEVER modify (헌법 Safety Rules).
- 루트에 `_tmp/`, `results/`, `data2/` 류를 만드는 순간 위반 — 4원칙 중 하나로 분류하라.

## §3 02_Infrastructure = 코드 전용

- `02_Infrastructure/`에는 **재사용 코드·설정·문서만**. 산출물(결과 json/parquet/로그)·1회용 스크립트 저장 금지.
- 스크래치(임시 파일·중간 덤프)는 **`.cache/scratch/`**(2026-07-04 기준 미생성 — 최초 사용 시 생성) 또는 세션 scratchpad 디렉토리만 사용.
- `_` 접두 1회용 디버그 스크립트(`_probe_*.R`, `_vfy_*.R`, `_debug_*.txt` 류)는 인프라 디렉토리에 두지 않는다 — 실험 소속이면 `stage_artifacts/<mode>/<run_id>/`, 순수 스크래치면 `.cache/scratch/`. (기존 잔존분은 2026-07-04 재편에서 일괄 정리 — 신규 생성분부터 본 규칙 hard.)

## §4 Retention (보존 기한)

| 대상 | 기한 | 처리 |
|---|---|---|
| 실행 로그 (파이프라인/훅/스케줄러 로그) | **90일** | 기한 경과분 삭제 |
| `.cache/scratch/` | **30일** | 기한 경과분 삭제 |
| superseded canonical 데이터 (`outputs/` 구본) | **격리 후 30일** | 즉시 삭제 금지 — `.cache/superseded/<날짜>/`로 격리 후 30일 뒤 삭제 |
| `stage_artifacts/` 런 기록 | 무기한 | 삭제·이동 금지 (감사 증거) |
| `06_Registry/` | 무기한 | writer 함수 경유 갱신만 |

캐시 vintage 고정 원칙([[project-cache-vintage-pinning]])과 정합: 다중라운드 실험이 소비 중인 canonical 데이터는 실험 종료 전 overwrite 금지 — pinned 스냅샷을 `.cache/`에 두고 소비.

## §5 인덱스 의무

- **`build_artifact_index`** (예정 위치: `02_Infrastructure/tools/build_artifact_index.R` — 2026-07-04 기준 미구현, 재편 후속) 를 주기 실행해 stage_artifacts 런 / outputs canonical / 06_Registry 상태의 머신 인덱스를 갱신한다.
- **`ARTIFACTS.md`** (루트 대시보드) — 위 인덱스의 사람용 요약. 어디에 무엇이 있는지의 단일 진입점. 인덱스 갱신 시 함께 갱신.

## §6 이동 금지 구역

- **`stage_artifacts/` 내부**: 불변 런 기록. 파일 이동·개명·수정 금지 (신규 런 추가만 허용).
- **`qepm/` 내부**: WT mailbox·registry·memory/axioms 등 레지스트리가 경로를 계약으로 참조. 읽기는 자유, 구조 변경 금지.
- **`05_Production/` · `01_Literature/`**: 헌법 NEVER modify.
- 과거 WT mailbox/frozen 기록 안의 구경로 문자열은 **갱신하지 않는다**(불변 기록) — 해석은 §7 이동 로그로 한다.

## §7 2026-07-04 구조 재편 이동 로그

과거 기록(WT mailbox, frozen 아티팩트, 메모리, 커밋 메시지)에 등장하는 구경로는 아래 표로 해석한다. 표는 **신경로 기준**(재편 최종안). 작성 시점(2026-07-04) 미이동분은 상태 표기 — 최종 확정은 메인 세션.

| 구경로 | 신경로 | 내용 | 작성 시점 상태 |
|---|---|---|---|
| `docs/adr/` | `00_Lawbook/K_RAMP/adr/` (RAMP SOT 동거 — 확정 설계) | RAMP ADR 2건 | **이동 완료 2026-07-04** (참조 갱신: ccs_evaluator.R·ramp_required_artifacts.json·K_RAMP 가이드 2편) |
| `tests/baseline/` · `tests/ramp/` | `08_Tests/baseline/` · `08_Tests/ramp/` | 테스트 스위트 | **이동 완료 2026-07-04** (baseline git mv·ramp untracked mv, ccs RS·required_artifacts 갱신, test_gate3_4.R 15 tests PASS) |
| `scripts/ramp/` | `02_Infrastructure/ramp/debug/` (확정 설계 — 디렉토리 통째, `_cache_pool.rds` 18MB 동반) | RAMP 디버그·검증 스크립트 | **이동 완료 2026-07-04** (tracked git mv·rds/log mv, 스크립트 내부 sink/cache 자기참조 + run_ramp_gate3_4.R CACHE_POOL 갱신) |
| `examples/` | `02_Infrastructure/docs/examples/` | qvest_workflows 예제 3종 | **이동 완료 2026-07-04** (git mv. 참조 갱신: search/_query.py·qvest_search·build_index.R 주석/help, qvest-kernel-ci.yml schema_validate ex_root, 00_Lawbook/INDEX.md, examples README replay 경로, v7_2_1 SOT 병기 1줄) |
| `research_output/regime_comparison/` | `outputs/regime/` (확정 설계 — 원칙 ② canonical 데이터. 내부 `output/` 하위 유지) | MSM 일간 RData (DailyRefresh 활성 산출) | **이동 완료 2026-07-04** (untracked mv — *.RData gitignore. 코드 갱신: msm_update.R:239 output_dir·ktri_validation.R:22 out_dir → `outputs/regime/output`. daily_refresh.sh는 msm_update.R source 경로 불변. 빈 research_output/ 제거) |
| `06_Reference/textbook_summaries/` | `02_Infrastructure/docs/reference_textbooks/` (확정 설계 — 1단 평탄화) | 교과서 요약 6편 | **이동 완료 2026-07-04** (git mv. 참조 갱신: prompts/optimizer_research_init.md·risk_research_init.md + Phase5_PoC_validation.md 자기참조. 빈 06_Reference/ 제거) |

부기: 작성 시점 워킹트리에서 registry 디렉토리가 `07_Registry/`로 관측됨(untracked) — 재편 최종 구조는 `06_Registry/`이며 정규화는 메인 세션이 확정한다.

부기 2 (2026-07-04 RAMP 3디렉토리 이동 — 의도적 미갱신 구경로 잔존): ① `CHANGELOG.md:236-237` (`tests/baseline/*` 언급 — 릴리스 이력 불변) ② `04_Research/architecture_audit_20260703_data/confirmed_findings.json` (감사 증거 기록 불변) ③ `04_Research/ramp/run_ramp_gate3_4.R.bak_pre_fullsweep_105537` (백업 스냅샷 — 활성본 `run_ramp_gate3_4.R`만 갱신) ④ `stage_artifacts/`·`qepm/` 내부 전체 (§6). 이들 안의 구경로는 본 §7 표로 해석.

부기 3 (2026-07-04 산출물·참고자료 3건 이동 — 의도적 미갱신 구경로 잔존): ① **legacy v55/S0-S7 스크립트의 `research_output/strategies/`·`research_output/regime_analysis/` 등 참조** (`04_Research/factor_scan.R`·`run_batch_s3.R`·`s3_batch_runner.R`·`s3_complex_runner.R`·`run_dart_strategies.sh`·`regime_analysis/*.R`·`strategies/batch_g12_*`·`rc_batch_runner.sh`·`_batch_s2_icir.R`·`STR_1621/1622 run_s3_orth.R`) — 참조 대상 디렉토리가 이동 이전부터 부재(dead path)·legacy 격리 대상이라 코드 미수정. 재실행 시 본 표+저장 4원칙에 맞게 경로 재지정 필요. ② `07_Registry/paper_registry.json`·`strategy_registry.json`의 `research_output/...` path 필드 — 과거 등록 기록(불변), 본 표로 해석. ③ 05_Production `production_config.json:11`의 `research_output/strategies/...` — NEVER-touch 경계(도훈 수동 갱신 대상). ④ `CHANGELOG.md:130` `examples/qvest_workflows/` — 릴리스 이력 불변. ⑤ 04_Research 과거 보고서·paper_notes·bearish_forecast plan 문서 내 `research_output` 언급 — 사람용 기록 불변. ⑥ `qepm/mailbox/worktask/WT-D20260501_003/` 내 `06_Reference/...` 언급 3건 — frozen WT 기록 불변. ⑦ examples fixture 내부 `examples/qvest_workflows/` 자기서술(challenge_note.md 3건) — synthetic WT 아티팩트 보존(README replay 경로만 갱신). ⑧ `04_Research/strategies/batch_g12_runner_v2.sh:9` 구머신 절대경로(`/mnt/c/Users/User/...`) — 이동 前부터 dead, legacy 보존. ⑨ `qepm/config/config.yaml:19,21` `paths.research_output`/`strategies` 키 — qepm 내부 NEVER-touch + 참조 대상(`research_output/strategies/`)이 이동 前부터 부재(dead key, qepm/R 소비자 grep 0건). qepm 정비 시 본 표 기준 정리 대상.

## §8 집행 (2026-07-04 파일위생 mandate — 신규 파일 자동 정리 체계)

본 규칙의 집행은 2단 메커니즘. 둘 다 **지식 기록이 아닌 죽은 코드·중복·캐시가 표적** — 보존 구역(§6 + stage_artifacts·qepm·05_Production·01_Literature·06_Registry·04_Research/strategies/STR_*)은 어떤 자동 삭제도 닿지 않는다.

1. **훅 (advisory — 쓰기 시점 1선)**: `02_Infrastructure/hooks/artifact_placement_guard.sh` (PreToolUse Write/Edit, `hooks/policies/router_dispatch.json` 등록, soft_fail). 감지 3종 — (a) 루트 직하 무허가 신규 항목(§2) (b) 02_Infrastructure `_` 접두 신규 파일(§3) (c) results/output 명명 산출물성 파일의 4대 존 밖 신규 생성(§1). **additionalContext 경고만 — block 금지** (의도된 예외는 그대로 진행 가능).
2. **일간 감사 (자동정리 + 리포트 — 2선)**: `02_Infrastructure/ops/artifact_hygiene_audit.R` (daily_refresh.sh [7.9], index 재생성 직전, fail-soft). *자동 정리 실삭제*: OS temp의 `qm_`/`qvest_` 접두 로그 90일+(§4) · `.cache/scratch/` 30일+(§4) · 청소 허용 존(02_Infrastructure/04_Research 비-strategies/outputs/.cache/08_Tests) 내 빈 디렉토리. 모든 삭제는 `06_Registry/hygiene_report.json` + `.cache/hygiene_manifest.log`에 기록. *감지·경고만(삭제 안 함)*: 루트 무허가 항목 / 인프라 `_` 파일 / 4대 존 밖 산출물성 데이터 파일 / `index_descriptions.json` 미등재 최상위 항목 → 위반 시 stderr `[hygiene][WARN]` (텔레그램 직접 발송 금지 — daily_refresh 로그로 노출). dry-run: `QVEST_HYGIENE_DRY=1`.

이력: 2026-07-04 6월-동결 스윕 — 죽은 코드·중복·캐시 일괄 정리(untracked 데이터는 `C:/qm_archive/20260704/` 경유, git-tracked는 git rm으로 이력 보존) + 본 집행 체계 가동 (첫 실행: 빈 디렉토리 421건 정리, 실측 2026-07-04).

## 참조
- `CLAUDE.md` Key Paths / Safety Rules · `.claude/rules/backtest-contract.md`(save_bt_result 산출 위치) · `02_Infrastructure/docs/rules/artifact-naming.md`(파일명 규약 — 본 문서는 *위치*, 그쪽은 *이름*) · `02_Infrastructure/contracts/registry_writer.R`

## Change log
- 2026-07-04: §8 집행 신설 — artifact_placement_guard.sh(advisory 훅) + artifact_hygiene_audit.R(일간 자동정리·리포트) + daily_refresh [7.9] 배선 (파일위생 mandate).
- 2026-07-04: 신설 (구조 재편 mandate — 저장 4원칙 + 루트 고정 + 인프라 코드전용 + Retention + 인덱스 + 이동 로그).
