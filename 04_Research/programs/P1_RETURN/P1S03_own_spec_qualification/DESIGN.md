# P1S03_own_spec_qualification 설계 — P1 상설 자격 · 자체 사양 입구 갈래(track own_spec) 판 1 · round_core v4

작성 2026-11-13 · 사양 생성 = `tools/init_p1s03.R`(초안 v1) → `tools/init_p1s03_v2.R`(초안 v2 · 시드 = 코어 v4 `rc_standing_own_seed_spec`) → `tools/init_p1s03_v3.R`(초안 v3 · D1 · D2 판 표식 글 — 11-14 · 변경분 점검 v2 M-1 · S-1)(재량 없는 생성 함수 rc_init_standing_p1) · 상위 = P1R03 결론 범위 '3개 이상 → 코어 v4 자체 사양 입구 → 블렌딩 사슬'.

## 1. 질문 · 가설
- 질문: 팩터 척추 생성기가 만든 자체 사양 엔진(`04_Research/strategies/FC_*` — 카테고리 등가중 합성 T0 15 · 시점별 IC 가중 결합 T1 15)이 표준 구성에서 P1 수익 엔진 자격을 갖는가 — 기저 풀(P4 강화 사슬의 기저 · 블렌딩 부품) 입구.
- 규칙 = P1 템플릿(P1R01 승계 — IS β-통제 t(α) ≥ `tier_graduation.grade_b_min_portfolio_alpha_t` ∧ IS 상승 포착 ≥ 0.55 · OOS α 보고 전용). 판 1 · 판 2 · P1R03 · P1R04 와 같은 규칙 · 같은 문턱.
- 가설: 시드 FVALU(P1R03 자격 · 밸류 등가중)는 자격 유지 — 이 판 경로의 양성 대조(사다리 루프 ① 기준점부터). 그 밖 엔진은 엔진마다 독립 판정 · 선택 없음.

## 2. 왜 지금 · 무엇과 다른가
- 기저 풀 자격 = 상설 판 통과만(도훈 P4-BASE-POOL-GRADE-PATH-TAU-20261111). P1R03 · P1R04 는 연구 질문(합성 · 결합 개선)의 판정이라 기저 자격을 주지 않는다.
- v3 상설 판은 레인 인계(`lane_handoff`)만 받았다. v4 가 자체 사양 입구(`own_spec`)와 입구 갈래(track)를 더했다 — 판 번호는 갈래마다 1 부터라 레인 판 2(P1S02 · v3)를 막지 않는다.
- 블렌딩 사슬 1호(P4C01)의 부품 = P1R03 자격 8(도훈 LOWBETA-ENGINES-BASE-USE-20261113 으로 저β 5 포함)인데, 그 엔진들이 기저 풀에 들어가려면 이 판의 통과가 먼저다.

## 3. 입구 · 시드
- 입구 = 코어 v4 기본값 `RC_STANDING_SCAN_OWN_DEFAULT`(lane_root `04_Research/strategies` · dir_glob `FC_*` · 생성기 둘 `fc_engine_gen.R::fce_engine_text` · `fc_combiner_gen.R::fcc_engine_text` · 방향 층 engine_native + orientation_layer · 결합 제외 · 정적 PIT).
- 사유: own_spec_missing · own_generator_unknown · own_generator_mismatch(재생성 본문 md5 대조 — 손 편집 · 부호 층 변조 차단).
- 등록 전 미리보기(`scan --dry-run` · 11-13): 디렉터리 30 · 입구 통과 30 · 새 엔진 30(성과 수치 없음).
- 시드 `P1S03_FVALU_RX0` = P1R03 `P1R03_FVALU_C0` 사양 그대로 + 측정 축만 활성(`rc_standing_seed_respec`) · 시행 무가산 · n_family 45(초안 v2 — 같은 엔진 스캔 행과 같은 규칙 rc_standing_own_nf = max(계보 최댓값, 원천 라운드 칸 수) · 원천 P1R03 15 + P1R04 30 · 판단 T4 C-036 · 코어 v4 변경분 점검 2 M3 · 초안 v1 의 2 는 앞선 회계 최댓값이었다). 첫 scan 에서 같은 엔진 md5 의 FC_FAM_value 는 `duplicate` 로 빠진다(rc_standing_enqueue).

## 4. 처치 = 표준 구성
- `rc_p1_cell_spec`(판 2 와 같은 생성 함수 · 핀 fn_md5 80f8311f) — 롱온리 25종 등가중 · 월말 신호 · 15bps · 20일 평균 거래대금 ≥ 2억 원 · 활성 측정 축 `all_hyg_px1000_2000_v1`.

## 5. 판정 규칙
- P1 템플릿 선언 그대로(`.rcs_p1_template_rules` — 사본 없음). 3치 논리(한 지표 미정 ∧ 다른 지표 미달 = 미달 · 모두 통과/미정 ∧ 미정 있음 = 재평가).
- 판정은 엔진마다 독립 · 선택 없음. 시드 미달 = 판 경로부터 확인(다른 판정을 읽기 전).

## 6. 시행 회계
- 자체 사양 행(코어 v4 규칙 — 변경분 점검 v2 S-1 정정): 계보 = own_spec.family_root(FC:<카테고리> · FC:total). 원천 라운드 = 엔진 md5 칸 ∪ 같은 계보 칸의 P1 라운드(T0 · T1 모두 P1R03 + P1R04). 시행 수 n_family = max(계보 최댓값, 원천 라운드 칸 수)(rc_standing_own_nf · standing.R:919-935 · 미리보기 30행 모두 45).
- 시드 = 무가산. 사슬 등록 때 원천 라운드 전 칸이 사슬 시행 집합에 들어간다(코어 v4 rc_p4_source_trials).

## 7. 노출(τ_D) — 사양 `exposures`
- P1R03 IS 판정 파일과 그 파일의 test_hold 열(코어 v3 누출)을 본 상태 · P1R03 IS 구간 NAV · 위기 하락노출 · 보유를 P1R04 차트 배치 시험(가짜 짝 · IS 전용)에서 본 상태 · P1R04 는 판 표식 마지막 줄(보충 줄) 뒤 재측정 전(11-13 부분 측정 = 결과 전 중단 · 평가 없이 보관 — P1R04 DESIGN §10 · Q 는 P1R04 판정을 보지 않았다 · 등록 직전 P1R04 results/evaluation_visible.json 없음을 다시 확인) · 방향 재판정 결과(성과 무참조) · 입구 미리보기. 규칙 · 문턱 재량 없음.
- 등록 뒤 노출(23:13 등록 뒤 · 판정 일치 기록 · 통과 보고에 싣는다): 이음매 세션의 D2 재측정 통지(11-14 23:4x)에 P1R03 IS 자격 8/15 그대로(바뀐 엔진 없음 · 인용 폴더 `P1R03_factor_family_composites/remeasure_d2_20261114/results` · 판 표식 stale = FALSE)와 전 기간 등급 변화 2건 · 토탈 엔진 시험 창 Calmar 가 실렸다(수치는 여기 옮기지 않는다). 이 판은 선택이 없고 규칙 · 문턱은 등록 고정이라 판정에 닿지 않는다. T0 15 의 P1R03 판정 일치 기록 = 등록 글대로 P1R03 원 칸(D2 앞 자료 판) 대조 — 참고 열로 그 D2 재측정분(같은 판 표식 줄 묶음 뒤 IS 판정 · 이음매 세션 A/B 에서 원 칸과 IS 판정 15/15 같음)도 함께 적는다.

## 8. 측정 계획(초안 v4 — 격리 점검 v1 F-2 · F-3 · F-5(2) · S-6 · 판단 T1 C-054 · 055 · 철학 C-050 · N1 · 변경분 점검 v2 · v3)
- 판 폴더 `tick_hold`(등록 커밋에 포함) — 무인 상설 판 틱(`02_Infrastructure/ops/standing_board_run.sh`)이 이 판을 건너뛴다. 무인 틱은 대기 항목 전부를 측정한 뒤 한 번에 판정 · 발송하므로(round.sh standing-measure → judge), 시드를 먼저 보려면 tick_hold 를 둔 채 손으로 잰다.
- 순서(11-14 실제 — 변경분 점검 v2 S-1): 등급 v3.5 핀 교체(317a9c0e0 · P1R04 재측정 앞 — 원 세션 lean-loop 5) → D1 판 표식(PRICE-CONTINUITY-FACTORS-20261113) → D2 판 표식(도훈 RAWDATA-INTERNAL-BREAK-FILL-D2D3-20261114) → D2 보충 줄(D2-XF-FILL-RESTORE-20261114 — 이음매 세션 정정 11-14 21:5x · D2 팩터 DB 재계산에서 빠진 밸류 · 성장 7팩터 퀀티 채움 행 복원) → 이 판 초안 v4 · 변경분 점검 · 등록(새 핀) → P1R04 재측정 · 평가(측정 셸이 원장 마지막 줄 완료 · 이 판 등록본을 기다린다 — ecda88b47) → 아래 해제 절차 → 무인 틱.
- 등록 직전 확인(변경분 점검 v2 S-5 · R-1): `round.sh <판> standing-check`(시드 회계 = 규칙 — rc_register 는 상설 시드 검사를 다시 부르지 않는다) · P1R04 `results/evaluation_visible.json` 없음(노출 줄 'Q 는 P1R04 판정을 보지 않았다') · `rc_pins_mismatches` 0 · 판 표식 원장 마지막 줄(D2 줄 묶음의 끝 — 지금 D2-XF-FILL-RESTORE-20261114 · 뒤에 더 붙으면 그 줄) 완료 = 계약 판독(`contracts/factor_db_vintage.R` — `fdv_ledger` 판독 성공 ∧ `fdv_stamp()` 진행 중 없음 ∧ 마지막 줄 completed_at 채워짐 · 변경분 점검 v3 M-1 (b): Python 판독은 형식이 틀린 완료 시각도 '끝'으로 읽는다) ∧ 원장 마지막 줄 id = 사양 결론 [9] 의 id(지금 D2-XF-FILL-RESTORE-20261114 — 다르면 생성기 · 새 초안 · 변경분 점검 · 변경분 점검 v4 R-1 · 등록 기록 메모에 그때의 마지막 줄 id · completed_at 을 남긴다 · 확인 도구 `tools/p1s03_prereg_gate.R`)(이음매 세션 최종 신호 — 11-14: 수리 줄은 쓰기 직후 진행 중으로 먼저 붙고 팩터 DB 영향 범위 재계산 뒤 completed_at 이 채워진다 · 그 전에 등록하면 남은 수리 작업이 핀 파일에 닿을 때 상설 판은 재핀 길이 없다(standing.R:231 — 새 판)). 초안 생성 · 변경분 점검은 진행 중 줄이 붙은 뒤 먼저 해도 된다(글은 id · 범위만 쓴다).
- 해제 전 조건(모두): ① 판 표식 — `06_Registry/factor_db_vintage.json` 마지막 줄(D2 줄 묶음의 끝 — D2 RAWDATA 원천 단절 행 Ret 정정 · 도훈 RAWDATA-INTERNAL-BREAK-FILL-D2D3-20261114 → 보충 줄 D2-XF-FILL-RESTORE-20261114 · 뒤에 더 붙으면 그 줄)이 완료(계약 판독)다 — 보충 줄 범위에 V 계열 4팩터가 있어 시드(FVALU) · 대조 상대 `P1R04_FVALU_R0` 둘 다 그 줄 완료 뒤에 재야 같은 자료 판 대조가 선다(변경분 점검 v3 M-1 (c))(진행 중 항목 = 아직 · 11-14 세 번 정정 — 변경분 점검 v2 M-1: 자체 사양 칸은 어느 판 표식 수리에도 걸리므로 D2 앞에 잰 칸은 그 줄 뒤 `factor_db_stale` 로 기저 풀에서 빠지고(p4.R:247), 상설 판은 판정한 항목을 다시 재지 않는다(standing.R:1359 — rejudge 판이 든다) · 시드 대조 상대 `P1R04_FVALU_R0` 도 마지막 줄(보충 줄) 뒤 재측정분) ② `RELEASES.json` 에 v4 출시 항목(사양 없는 호출 · `round.sh - p4-pool` 의 기본 판 = v4) ③ P1R04 의 마지막 줄(보충 줄) 뒤 재측정 · 평가 끝(시드 대조 상대 · 한 번에 무거운 작업 하나 · 메모리) ④ 기저 신호 캐시 시각: FC_* 엔진의 `.cache/rf_base_signal/base_v3_<엔진 md5 앞 12>_*.rds` 가 마지막 결합용 뷰 · IC 원장 빌드보다 뒤에 만들어졌는지 확인하고, 아니면 지운다(캐시 키에 뷰 · IC 원장이 없다 · 다시 계산 비용만).
- 해제 절차(세션 · 한 셸): `round.sh <판> scan` → `round.sh <판> measure-item P1S03_FVALU_RX0` → `round.sh <판> judge`(측정된 항목 = 시드뿐) → 시드 IS 값(t_alpha_vis · uc_vis · beta_vis)을 같은 사양 · 같은 자료 판의 `P1R04_FVALU_R0` 값과 대조(허용 1e-9). 같으면 tick_hold 를 지운다. 다르면 tick_hold 를 둔 채 자료 판 · 판 경로 원인을 본다(다른 판정을 읽지 않는다). 두 측정의 데이터 지문(측정 기록 · `.fp_start` / `.fp_end` — equality)을 대조 기록에 함께 적는다 — '같은 자료 판'은 판 표식 상태일 뿐 바이트 동일 자료가 아니다(사이에 밤 갱신이 끼면 RAWDATA · 결합용 뷰 지문이 다르다 · 덧붙이기만이면 IS 값은 같아야 정상). 값이 다르면 지문 차이부터 원인을 기록한다(변경분 점검 v2 S-7).
- 지운 뒤: 매시 틱이 scan → standing-measure → standing-report 를 한다(배리어 · 지문 · 판 표식은 코어가 본다). 통과 보고 = 일 요약(판단 T1 C-058).
- 판정 일치 기록(철학 N2 · 판단 C-056): T1 판정을 읽기 전에 T0 15 의 판정이 같은 자료 판(판 표식 마지막 줄 D2-XF-FILL-RESTORE-20261114 뒤) P1R04 기준 칸과 같은지(기대 15/15 · 밸류 · 성장 카테고리에서 P1R03 과 다르면 원인 기록에 이음매 세션 양성 대조 `check_full_by_factor.R`(수리 명세 = 전 모듈 산출 · IS 한 달 표본)를 함께 적는다 — 변경분 점검 v4 S-3), 그리고 P1R03 칸(앞 자료 판 — D2 정정 전)과 같은지를 양방향(통과 → 통과 · 미달 → 미달)으로 기록한다. P1R03 과 다른 칸은 '원천 판정과 다름' 표식 · 원인(D2 = IS 수익률 일부 행 정정) 기록 뒤에만 기저 풀에서 쓴다. P1R04 기준 칸과 다른 칸은 판 경로 원인부터 본다.
- 방향 수정 순서(S-6): 등록부 방향 수정(V23 · C08 · CR05)은 시드 판정 뒤에 한다 — 그 전에 고치면 시드 엔진이 본문 단정으로 멈추거나 새 md5 가 되어 양성 대조를 잃는다.
- 사슬 1호 닫기 재채점(--regrade-write)은 등급 v3.5 발효 뒤(그 전 닫기는 --regrade-dry-run) — 재개 저널 OP-20261113-P1R04 에 적었다.
- 예상: 30 항목 × 칸당 2.5~3.6분(P1R03 실측) — P1R04 · 이음매 세션의 P1R03 재측정이 같은 자료 판에서 같은 T0 엔진을 먼저 재면 기저 캐시 적중으로 더 짧다.

## 9. 기저 풀로 가는 길(코어 v4 관문)
- 통과 칸 → `round.sh - p4-pool`(기본 판 = v4 · RELEASES 항목 뒤) → 관문: philosophy_unread(상설 pass 기록의 P2 또는 원천 라운드 영수증) · philosophy_hold · lowrisk_confirm_pending(카테고리가 방어 · 위험 · 국면 · 유동성 · 쏠림과 겹치는 엔진 — 토탈 포함 — · 영수증 lowrisk_tag · 원천 라운드 기계 꼬리표 `results/lowrisk_tags.json`(P1R04 변환기 f7c0e32f3 · 판독 불가 = 꼬리표) 은 엔진 단위 release_decision — 변경분 점검 v2 S-6).
- 11-14 모의 판독(읽기만): P1R03 영수증 78bd9969a 로 FC T0 15 중 14 통과 예정(국면 = philosophy_hold) · 원천 라운드 = P1R03 ∪ P1R04.
- P1R03 영수증(`P1R03/results/philosophy_receipt.json`)은 원 세션이 `rc_philosophy_receipt_write` 로 쓴다(hold 0 · 저β 5 의 release_decision = LOWBETA-ENGINES-BASE-USE-20261113 — 그 결정 대상은 P1R03 엔진뿐).
- 사슬 1호(P4C01) = 이 판 통과 + 영수증 해소 + P1R04 30칸 산출(원천 시행) 뒤 등록.

## 10. 알려진 한계
- 감시기 `superfan_watch.py` scan_stale 은 판 번호가 가장 큰 원장 하나만 본다(갈래 모름) — 레인 판 2 가 있는 동안 이 판의 스캔 정체는 그 규칙에 안 보인다(코어 밖 수리 과제).
- 등록 시험 묶음 없음(도훈 11-12 · 11-13) — 코어 v4 시험(출시 전) · 엔진 PIT 값 검사(P1R03 · P1R04 등록 때)를 핀과 입구 재생성 md5 대조가 잇는다.
