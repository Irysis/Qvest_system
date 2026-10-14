# 04_Research — 리서치 존 (2026-10-14 정리판)

코드는 `02_Infrastructure/`, 등록부는 `06_Registry/`, 측정 산출물은 `stage_artifacts/` 에 있다. 여기는 **리서치 실행 단위와 그 문서**가 산다.
전체 지도 = `00_Lawbook/INDEX.md` · 파일별 역할(자동 생성) = `INDEX.md`.

| 폴더 | 무엇 | 상태 |
|---|---|---|
| `programs/` | v10.01 1계층 리서치 프로그램 — `<프로그램>/<라운드>/`(사전등록 · 측정 · 평가 · 종료 스크립트) · `_lib/` 공용 도구 · `_supervision/` 감독 기록 | 현행 |
| `strategies/` | 논문 엔진 — 충실구현 `RP_AUTO_*`(청정 레인 `RP_AUTO_CLEAN_*`) · 셀 기저 · 옛 `STR_*` 결과 | 현행 |
| `01_reports/` | 보고서 · 설계안 `<주제>_YYYYMMDD/` — 현행 설계(v10.01 = `l1_prescription_redesign_20261013/`) + 코드 · 룰이 근거로 인용하는 것 · `weekly/`(주간 증류) · `monitoring/`(BOOK 추적) · `audits/` | 현행 |
| `factor_rotation/` | 2계층 실행(`run_wf_ensemble.R`) · 2계층 풀 시계열 · FR 출력 | 현행(2계층) |
| `regime_comparison/` | 국면 신호(데이터 갱신이 `msm_update.R` 를 부른다 · KTRI · 파생 지표) | 현행(데이터) |
| `decision_framework/` | 약세 예측 파이프라인 데이터 — 부팅 점검 · 아침 브리핑 · 신선도 감사가 읽는다 | 현행(소비 중 · 옮기지 말 것) |
| `l2_role_rotation/` | 2계층 역할 슬리브 연구(10-10) | 현행(2계층) |
| `advisor/` · `paper_notes/` · `dart_census/` | QEPM 어드바이저 · 논문 노트(검색 색인 원천) · DART 감사 입력 | 현행(도구 입력) |
| `90_legacy/` | 정리 전부터 있던 v5x~v6 사료 | 읽기 전용 |

루트 파일: `grade_a_catalog.json`(모듈 등록 · `register_module.R`) · `lessons_sent.json`(텔레그램 교훈 발송 기록) · `strategy_postmortem.md`(실패 교훈 누적) · `paper_ensemble_hypotheses.md`.

**새 리서치를 둘 곳**: 1계층 라운드 = `programs/<프로그램>/<라운드>/` · 보고서 · 설계안 = `01_reports/<주제>_YYYYMMDD/README.md` · 논문 엔진 = `strategies/RP_AUTO_<id>/`(레인이 만든다).
여기 바로 아래에 새 주제 폴더를 만들지 않는다.

**옮긴 것(10-14)**: v10 이전 실험 20개 폴더(composition_search · korea_research · method_frontier · pg2_* · ramp · meta · 02_experiments …)와
코드가 인용하지 않는 보고서 53건 → `C:/qm_archive/reorg_20261014/` · 목록 = `00_Lawbook/reorg_20261014_manifest.json` · 추적 파일 복원 = `git checkout pre-reorg-20261014 -- <경로>`.
