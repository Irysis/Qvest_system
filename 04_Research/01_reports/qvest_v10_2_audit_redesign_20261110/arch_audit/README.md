# Qvest v10.2 아키텍처 전체 감사 — 산출물 색인 (2026-11-10)

도훈 지시(11-10): 시스템 아키텍처 전체(데이터 리프레시 · DB 관리 · 모닝브리핑 · 논문 수집 · 1계층 리서치와 강화 사슬 · 2계층 · 지식 축적과 재귀 개선 루프 ·
BOOK · 사용자 지시 리서치 · 텔레그램 규칙 · 시험)를 감사하고, 실운용 오류 · 업데이트 누락을 시나리오 시험으로 막고, 쓰지 않는 프로세스 · 배선 · 옛 시험을 삭제해 속도를 높인다.

이 폴더는 그 감사의 원자료다. 요약 · 결론은 상위 문서 `../README.md`(v10.2 설계 · 감사 절)와 `02_Infrastructure/docs/CHANGELOG_constitution.md` 에 있다.

## 어떻게 했나

1. **영역별 감사 레인 13개**(에이전트 · 읽기 + 소유 범위 안 수리 + 시나리오 시험): 데이터(A) · 모닝/텔레그램(B) · 논문(C) · 충실구현(D) ·
   1계층 라운드 코어와 강화 사슬(E1) · 처방 도구 상자(E2) · 구성 엔진(E3) · 2계층/BOOK(F) · 시험(H1) · 죽은 배선과 속도(H2) · 지식 루프(K) · QEPM/어드바이저(Q) · 골든 재핀(T).
2. **삭제 후보 검증**(워크플로): 레인이 낸 후보 → 묶음 61개의 검증자(호출자 · 예약 작업 · 스킬 문서 · 등록부 참조) → dead 판정분 반박 검증 →
   삭제 뒤 남는 코드의 비주석 참조 재검색 → 전략 · 생산 · 산출물 폴더까지 넓힌 재검색.
3. **적대적 검토 2회**(워크플로 · 단위마다 두 관점으로 결함 탐색 → 발견마다 독립 반박 검증): 1차 8단위(확정 25) · 2차 8단위(확정 43).
4. **확정 결함 수리**(워크플로 · 묶음별 수리 → 독립 검증 → 재수리) + 총괄(Q)의 직접 검증(시험 재실행) 뒤 묶음별 커밋.

## 폴더

| 경로 | 내용 |
|---|---|
| `lanes/audit_*.md` | 레인별 감사 보고(배선 지도 · 시나리오 표 · 수리한 결함 · 못 고친 결함과 패치 제안 · 업데이트 누락 감지 표 · 결정 필요 항목) |
| `lanes/audit_common_brief.md` | 레인 공통 지침(금칙 · 시험 규칙) |
| `lists/dead_*.tsv` | 레인별 '안 쓰는 것' 후보 원목록 |
| `lists/deleted_428.txt` | 삭제 적용 목록(커밋 `1bccf16c9` · 롤백 = 태그 `pre-v10.2-prune-20261110`) |
| `lists/delete_held_refs_39.txt` | 남은 코드 참조 때문에 보류했던 39개 — 도훈 11-10 저녁 결정(PRUNE-EXTRA-DELETIONS-20261110) 뒤 닫힌 집합 검증을 거쳐 55개 삭제(커밋 `1ace33edc`) |
| `review/held_closure_result.json` · `review/fix_reports/held_apply/` | 보류 묶음의 닫힌 집합 검증 결과(묶음별 삭제 · 유지 · 동반 수정) · 삭제 적용과 독립 검증 보고 |
| `review/fix_reports/papers/` | 논문 수집 질의 재편 · 순서 규칙의 설계 · 독립 검증 · 재수리 보고 |
| `lists/delete_held_manual.tsv` | 수동 보류(구 전략이 source 하는 3개 · BOOK 위기 감시 보고 3개 · 쓰이고 있는 등록부 1개) |
| `lists/delete_unsure_48.tsv` · `keep_live_44.tsv` · `keep_refuted_7.tsv` · `untracked_not_deleted_45.txt` | 검증자가 불확실 · 살아 있음 · 반박으로 뒤집힘 · 추적 밖(되돌릴 수 없어 손대지 않음) |
| `lists/tests_inventory.tsv` · `tests_delete_plan.tsv` | 시험 477개 분류(KEEP · DELETE · TRIM · ORPHAN · FIX · DECIDE · REPIN)와 삭제 계획 |
| `lists/r_portability_violations.tsv` | R 이식성 규약 신규 위반 39건(생산 코드 — 미수리 · 소유 파일에서 고칠 것) |
| `review/adversarial_wave1_confirmed.json` · `_dropped.json` | 1차 적대적 검토 확정 25건 · 기각 |
| `review/adversarial_wave2_confirmed.json` · `_dropped.json` | 2차 적대적 검토 확정 43건 · 기각 |
| `review/fix_reports/` | 수리 워크플로의 묶음별 보고(수리 · 독립 검증 · 재수리) |
| `review/fa_notch_asof_audit.md` | 팩터 조정 알파 노치의 as-of 재검(요인 표본 거르기 미래참조 → 빌더 v1.1) |
| `review/golden_repin_report.md` | 골든 4종 재핀 근거 |
| `review/judgment_backfill_draft.md` | 판단 원장 소급 초안(이 세션 14건은 기록 완료 · 다른 세션 10건은 미기록) |
| `review/doc_drift_fixes.md` | 낡은 규칙 문서 정정안(적용 완료 — 커밋 `8aa5fb63a`) |
| `procedures/scheduled_tasks_20261110.md` | 예약 작업 일괄 정리 절차(도훈이 일반 PowerShell 에서 실행) |

## 읽는 순서

1. 무엇이 P/L 우상향을 막고 있었나 → `lanes/audit_E1_l1.md` §7 · `lanes/audit_D_replication.md` · `lanes/audit_C_papers.md`
2. 실운용 오류 · 업데이트 누락 → `lanes/audit_A_data.md` · `lanes/audit_B_morning_tg.md`
3. 무엇을 지웠나 · 왜 남겼나 → `lists/`
4. 수리가 믿을 만한가 → `review/adversarial_wave*_confirmed.json` 과 `review/fix_reports/`
