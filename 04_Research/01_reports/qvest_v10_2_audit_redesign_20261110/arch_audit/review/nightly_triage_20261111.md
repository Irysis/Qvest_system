# 11-11 02:19 밤 배터리 실패 16개 스위트 분류 (nightly 층)

결과 파일 사본: C:\Users\User\AppData\Local\Temp\claude\594eba70e8c297ec\9fe22a2f-3836-40d8-8087-87fddf9c12ec\scratchpad\hook_dryrun_results_20261111_0219.json
수리 전 판 재현은 모두 스크래치 사본 루트(`git show` / `git archive`)에서 했다. 작업 트리는 되돌리지 않았다.

## (a) 분류표

| # | 스위트 | 분류 | 근거 | 조치 |
|---|---|---|---|---|
| 1 | hooks/test_r_portability.R 23/40 | 기존 결함 | 총괄 지정 | 없음 |
| 2 | hooks/test_cluster_power.R 24/1 | 다른 세션 소관 | F3: 등록부 실측 16 ↔ 상수 15. `factor_db/custom_factors.json` · `factor_registry.json` 이 미커밋(M) | 없음 |
| 3 | programs/test_tau_d_date_nonbmp.R (exit 1) | **회귀** (a0c0ef417 → 3bec690f1 · c0a4b6212) | 72bae6a27 판 32/32 통과. a0c0ef417 · 3bec690f1 · c0a4b6212 판에서는 모두 `could not find function ".rc_tau_alt_hits"` 오류. 시험이 이름 목록으로만 함수를 꺼내서, 새로 생긴 도우미를 못 가져왔다. 또 C · E3 · E4 는 rx_round.R 의 옛 정규식 줄을 겨냥하고 있었다 | 시험 재조준(수리 단위 A) |
| 4 | hooks/test_map_freshness_content.R 39/11 | 기존 결함 (데이터) | 11-01 이전 판(311d47bd3) 감시기 · 시험 · 지도로도 같은 11건 실패. `06_Registry/layer_bottleneck_map.md` 가 09-24 에 깨진 글자(표 3행)로 다시 생겼다. v9 에서 보관소로 옮겨졌는데 이 파일이 있어서 SKIP 분기를 타지 않는다. 배선 지도 생성기와는 무관 | 없음 |
| 5 | programs/test_paper_atlas_run.sh 3/2 | 기존 결함 (시험이 운영 등록부에 묶임) | 10-14 판 5/5. 10-20 판 · 11-01 판 · 사다리 태그 판 · HEAD 는 3/2. 섞어서 돌려도(옛 코드+새 등록부, 새 코드+옛 등록부) 같다. 시험이 운영 `research_programs.json` 을 복사하는데, 10-14~20 사이 재료 큐에 논문이 차서 '일감 0' 전제가 깨졌다. 1ace33edc · e3ba30299 와는 무관 | 없음 |
| 6 | programs/test_mechanism_atlas.R 10/1 | 기존 결함 (같은 원인) | HEAD 코드에 10-14 등록부를 쓰면 11/11 통과. 10-20 등록부 · 사다리 태그 · HEAD 등록부를 쓰면 C2 실패. 운영 큐의 P1 논문이 65편이라 `ma_pending(10)` 상한 안에 시험 논문이 들지 못한다 | 없음 |
| 7 | reinforcement/test_rf_fidelity_audit.R 63/4 | 기존 결함 (10-20 109d910a1c) | cca32d753(10-20 11시 이전) 67/67. 109d910a1c 바로 뒤 판 · 사다리 태그 판 63/4. 109d910a1c 가 감사 상충 분기에 `.slot_book_lock()` 을 넣었는데, D7 · D8 샌드박스 환경에는 그 정의가 없다 | 없음 |
| 8 | ops/test_rf_audit_not_run_blocks_open.R 38/2 | C5 = **회귀** (15be6c097) · C4 = 기존 | 사다리 태그 · e04aa187a 판 39/1(C4만 실패). 15be6c097 판부터 38/2(C5 추가). 15be6c097 이 '거두기만' 모드(RP_WITHDRAW_ONLY=1 · 측정 없음)로 검증기를 두 번째로 직접 호출한다. C4 는 11-01 판에서도 실패: 호출 줄 형식 `rp_verify; VRC=$?` 가 시험 정규식 `rp_verify; exit` 과 다르다 | C5 재조준(수리 단위 B) · C4 는 그대로 |
| 9 | reinforcement/test_rf_weight_arms_explore.R 5/1 | 기존 (데이터 상태) | 원장 L1 기준으로 shrinkage 계열이 이미 측정됨(3칸). 09-25 원장 · 사다리 태그 원장도 같다. 설계상 측정되면 탐색 슬롯이 사라진다(자기 제한). E1 의 전제가 소멸했다 | 없음 |
| 10 | ops/test_orphan_run_scan.py 8/1 | 기존 결함 (스캐너 창) | 08-22 로그는 남아 있다. 스캐너가 `sorted(glob)[-180:]` 로 이름순 마지막 180개만 보는데, 이름순으로 그 로그 뒤에 오는 로그가 10-15 에 이미 242개였다. 날짜가 아니라 이름순이 결함 | 없음 |
| 11 | book/test_book_rebalance_preflight.py (exit 1) | 환경 | 러너 해석기 QVEST_PY = 시스템 Py 3.15 라 `import pandas` 에서 실패. venv 로 돌리면 18/18 통과. BOOK writer · 데이터 신선도와는 무관. 러너의 .py 호출 방식은 11-10 전후 같다(11-08 환경 전환부터) | 없음 |
| 12 | contracts/test_matched_controls.R 66/1 | 기존 결함 (10-17) | K4 실패: 위기 줄에 '크기·노출 짝 N' 이 없다. b330260ac(10-17)가 그 표기를 줄에서 머리글 '(괄호 = 크기·노출 짝 대조)'로 옮겼고, 시험은 10-15 판 그대로다 | 없음 |
| 13 | contract_regression/test_label_eligibility_gate.R 21/1 | 데이터 상태 (11-06 의도된 변경) | G0 문턱 > 300개월인데 병합이 275개월. b57a3003d(11-06 MSM as-of 전환 · D1 A)가 통합 국면 신호를 2004-01 부터로 잘랐다(2004-01~2026-11 = 275). G1~G3 판정은 통과 | 없음 |
| 14 | factor_db/test_inv13_beta_asof.R 14/2 | 기존 (재계산 대기 · 의도된 빨강) | A1 · B2 실패. 7028345c4(11-10) 커밋 메시지가 'INV01~13 재계산 필요 — 의도된 빨강'으로 기록 | 없음 |
| 15 | data/test_global_macro_ingest.py 4/3 | 환경 | QVEST_PY 4/3 · venv 10/0 | 없음 |
| 16 | data/test_qw_ext_ingest.py (exit 1) | 환경 | QVEST_PY 는 `import pyarrow` 에서 실패 · venv 9/9 | 없음 |

## (b) 수리 뒤 실행 결과
- test_tau_d_date_nonbmp.R → `{"pass":32,"fail":0,"total":32}` rc 0
  - 양성 대조: util.R 의 perl = TRUE 2곳을 지운 사본 루트에서 A1~A3 FAIL, 이어서 crash(rc 1) → 빨강
- test_rf_audit_not_run_blocks_open.R → 39/1. 남은 1 = C4(기존). C5 OK
  - 양성 대조: 레인 사본에서 `RP_WITHDRAW_ONLY=1` 을 지우면 C5 FAIL '측정 2 · 거두기 0 · 줄 552,585'

## (c) 고친 파일 (수리 단위별)
**A. 정보 경계 날짜 검사 시험 재조준** — `08_Tests/programs/test_tau_d_date_nonbmp.R`
- 무엇: util.R 은 최상위 정의를 전부 꺼낸다(도우미 · 정규식 상수 포함). C 는 '멈춘다'에 더해 '멈춤 사유에 YYYY-MM-DD 가 있다'를 잰다. E3 는 'rx_round.R 에 따로 둔 날짜 정규식 없음 · rc_input_issues 사용'을 잰다. E4 는 perl 을 뺀 util.R 사본을 tempdir 루트에 두고 .rx_assert_clean 이 그 루트를 읽게 한다.
- 왜: a0c0ef417 · 3bec690f1 이 가림 · 누출 검사에 표기 변형 도우미를 붙였고, c0a4b6212 가 처방 입력 검사를 rc_input_issues 한 구현으로 묶었다. 새 검사에는 τ_D 뒤 '연도' 검사도 있어서 perl 을 빼도 '2024' 로 멈춘다. 그래서 '멈춤'만 재면 BMP 밖 문자 뒤 날짜를 놓치는 결함을 판별하지 못한다 → 사유 문자열로 같은 성질을 잰다.

**B. 레인 검증기 직접 호출 수 단언 재조준** — `08_Tests/ops/test_rf_audit_not_run_blocks_open.R`
- 무엇: C5 는 '측정 호출 = rp_verify 본문 안 정확히 1줄'을 유지한다. 바로 앞 줄에 `RP_WITHDRAW_ONLY=1` 이 붙은 거두기 호출은 따로 세고, 그것도 1개 이하여야 한다.
- 왜: 15be6c097 이 되살림 상한 초과 경로에 측정 없는 거두기 호출을 추가했다. 표식 없는 직접 호출이 늘면 여전히 빨개진다(돌연변이로 확인).

생산 코드 변경 없음. 스테이징 · 커밋 없음.

## (d) 고치지 않은 것 · 총괄 결정 사항
1. 11-10 감사가 낸 회귀가 아닌 것(4~7 · 8 의 C4 · 9~16)은 지시대로 손대지 않았다. 이 중 시험 쪽 낡음(5 · 6 · 7 · 8 의 C4 · 9 · 10 · 12 · 13)은 10월부터 빨강이다. 각각 시험 재조준 대상인지 결정이 필요하다.
   - 5 · 6: 운영 등록부를 복사하지 말고 빈 큐 픽스처를 쓰기
   - 7: D7 · D8 샌드박스에 `.slot_book_lock` 대역 넣기
   - 8 C4: 호출 줄 정규식 갱신
   - 9: E1 을 '미측정 계열이 있을 때' 픽스처 원장으로
   - 10: 스캐너를 날짜순 창으로 고치기(생산 코드)
   - 12: K4 를 머리글 표기로
   - 13: G0 문턱을 2004-01 시작 기준으로 재도출
2. 11 · 15 · 16 (환경): 러너가 .py 를 시스템 Py 3.15(pandas · pyarrow 없음)로 돌린다. 러너가 pandas 쓰는 스위트를 venv 로 돌릴지, 시험이 venv 로 다시 실행할지 정해야 한다(suite_tiers.tsv · 러너는 총괄 작업 중이라 건드리지 않음).
3. 4: `06_Registry/layer_bottleneck_map.md`(09-24 깨진 글자 · 보관된 지도의 부활) 삭제 또는 복원 결정. 삭제하면 시험이 SKIP 분기로 간다.
4. 14: INV01~13 재계산 뒤 재핀.
5. 리프레시 잠금이 잡혀 있는 동안 측정했다(벤치 · 국면 파일은 오늘 08:24 · 09:21 에 갱신). 13 의 275개월은 그 영향이 아니라 2004 절단 때문이다.
