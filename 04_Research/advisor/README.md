# 04_Research/advisor — QEPM 어드바이저 산출 존

`/advisor`(정본 = `.claude/skills/qvest-advisor/SKILL.md` · 도훈 결정 `QEPM-ADVISOR-MODE` 2026-09-25)의 자문·메모·측정 기록이 쌓이는 곳이다.
어드바이저 에이전트(alpha-hypothesis · alpha-research · risk-research · optimizer-research)가 쓸 수 있는 **유일한** 경로다.

## 디렉터리 규약

요청 1건 = 디렉터리 1개: `04_Research/advisor/<YYYYMMDD>_<slug>/` (slug = 영소문자·숫자·하이픈, 40자 이하).
같은 아이디어를 다시 다루면 새 디렉터리를 만들지 않고 기존 디렉터리를 잇는다(계보 = 디렉터리 · 시행 수는 `trials.jsonl` 에서 센다).

| 파일 | 쓰는 이 | 내용 |
|---|---|---|
| `input.md` | Q | 입력 원문 · 원문 링크 · 추출 6종(신호·비중·유니버스·리밸·주장 성과·전처리) |
| `alpha_hypothesis.md` | alpha-hypothesis | 기전·가설·반증 조건·국면 경계·과거 negative·근거 문헌 |
| `alpha.md` | alpha-research(선택) | 팩터 소싱·신호공학·데이터 가용성·선례 |
| `risk.md` | risk-research | β·크라우딩·국면 노출·낙폭 구조·집중·꼬리 진단 |
| `optimizer.md` | optimizer-research | 축 선언에 맞는 비중법·회전·비용·`portfolio_spec` 초안 |
| `memo.md` | Q | 종합 메모(정본) — 스킬 ③ 머리글 순서 · §11 측정 설계는 측정 뒤 고치지 않는다 |
| `engine.R` · `measure_<k>.R` | Q(측정 승인 뒤) | 엔진 1파일(FACTORS/PORTFOLIO 계약) · `run_paper_replication` 호출 사본(사전 선언의 기계 판) |
| `trials.jsonl` | Q(측정 뒤 append) | 시행 기록 1줄/측정 — `k·run_id·out_dir·strategy_id·selection_type·n_trials_cumulative·n_trials_basis·measured_at·approval`. 계보 N 의 원천이며 원장이 아니다 |

## 두지 않는 것

- 등급·성과 수치의 사본 — 정본은 러너 산출물 `stage_artifacts/replication/<run_id>/authoritative_remeasure.json` 이고, 여기는 그 경로만 적는다.
- 원장·BOOK·`grade_a_queue`·`judge_request*` 의 사본이나 초안, WT 산출물(`request.json`·`*_package.json`).
- 측정 산출물 복사본(러너가 `stage_artifacts/replication/` 에 쓴다).

## 경계

- 측정은 도훈 승인 뒤 정본 계약(`run_paper_replication` → essence 권위 등급 · 시행 회계)만.
- A 는 1계층과 같은 경로(`rf_a_eligibility` 관문 → Judge(PIT) → BOOK(도훈 confirm))만 — 어드바이저는 Judge 를 스폰하지 않는다.
- QEPM WT 체인(forge·dossier·`/worktask promote`)은 동결(`QEPM-R0-FREEZE`).
- 검사 = `08_Tests/worktask/test_qepm_advisor_contract.R`.
