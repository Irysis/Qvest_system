# P1S03_own_spec_qualification 설계 — P1 상설 자격 · 자체 사양 입구 갈래(track own_spec) 판 1 · round_core v4

작성 2026-11-13 · 사양 생성 = `tools/init_p1s03.R`(재량 없는 생성 함수 rc_init_standing_p1 · rc_standing_seed_respec) · 상위 = P1R03 결론 범위 '3개 이상 → 코어 v4 자체 사양 입구 → 블렌딩 사슬'.

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
- 시드 `P1S03_FVALU_RX0` = P1R03 `P1R03_FVALU_C0` 사양 그대로 + 측정 축만 활성(`rc_standing_seed_respec`) · 시행 무가산 · n_family 2(= 계보 FC:value 앞선 회계 최댓값 — P1R03 T0 1 · P1R04 T1 변형 2). 첫 scan 에서 같은 엔진 md5 의 FC_FAM_value 는 `duplicate` 로 빠진다(rc_standing_enqueue).

## 4. 처치 = 표준 구성
- `rc_p1_cell_spec`(판 2 와 같은 생성 함수 · 핀 fn_md5 80f8311f) — 롱온리 25종 등가중 · 월말 신호 · 15bps · 20일 평균 거래대금 ≥ 2억 원 · 활성 측정 축 `all_hyg_px1000_2000_v1`.

## 5. 판정 규칙
- P1 템플릿 선언 그대로(`.rcs_p1_template_rules` — 사본 없음). 3치 논리(한 지표 미정 ∧ 다른 지표 미달 = 미달 · 모두 통과/미정 ∧ 미정 있음 = 재평가).
- 판정은 엔진마다 독립 · 선택 없음. 시드 미달 = 판 경로부터 확인(다른 판정을 읽기 전).

## 6. 시행 회계
- 자체 사양 행: 계보 = own_spec.family_root(FC:<카테고리> · FC:total). 원천 라운드(같은 엔진 md5 를 칸으로 등록한 P1 라운드 — T0 = P1R03 + P1R04 · T1 = P1R04)가 그 계보를 회계했으면 n_family 그대로(같은 시행의 재측정 · +1 없음), 아니면 +1.
- 시드 = 무가산. 사슬 등록 때 원천 라운드 전 칸이 사슬 시행 집합에 들어간다(코어 v4 rc_p4_source_trials).

## 7. 노출(τ_D) — 사양 `exposures`
- P1R03 IS 판정 파일과 그 파일의 test_hold 열(코어 v3 누출)을 본 상태 · P1R03 IS 구간 NAV · 위기 하락노출 · 보유를 P1R04 차트 배치 시험(가짜 짝 · IS 전용)에서 본 상태 · P1R04 는 측정 전 · 방향 재판정 결과(성과 무참조) · 입구 미리보기. 규칙 · 문턱 재량 없음.

## 8. 측정 계획(초안 v2 — 격리 점검 v1 F-2 · F-3 · F-5(2) · S-6 · 판단 T1 C-054 · 055 · 철학 C-050 · N1)
- 판 폴더 `tick_hold`(등록 커밋에 포함) — 무인 상설 판 틱(`02_Infrastructure/ops/standing_board_run.sh`)이 이 판을 건너뛴다. 무인 틱은 대기 항목 전부를 측정한 뒤 한 번에 판정 · 발송하므로(round.sh standing-measure → judge), 시드를 먼저 보려면 tick_hold 를 둔 채 손으로 잰다.
- 순서: 등급 v3.5 핀 교체(P1R04 측정 · 평가 뒤 · v3.5 세션) → 이 판 초안 v2 · 변경분 점검 · 등록(새 핀) → 아래 해제 절차 → 무인 틱.
- 해제 전 조건(모두): ① 판 표식 `RAWDATA-SEAM-0330-REPAIR-20261113` 이 `06_Registry/factor_db_vintage.json` 에 있다(11-13 09:36 완료) ② `RELEASES.json` 에 v4 출시 항목(사양 없는 호출 · `round.sh - p4-pool` 의 기본 판 = v4) ③ P1R04 측정 셸 끝(한 번에 무거운 작업 하나 · 메모리) ④ 기저 신호 캐시 시각: FC_* 엔진의 `.cache/rf_base_signal/base_v3_<엔진 md5 앞 12>_*.rds` 가 마지막 결합용 뷰 · IC 원장 빌드보다 뒤에 만들어졌는지 확인하고, 아니면 지운다(캐시 키에 뷰 · IC 원장이 없다 · 다시 계산 비용만).
- 해제 절차(세션 · 한 셸): `round.sh <판> scan` → `round.sh <판> measure-item P1S03_FVALU_RX0` → `round.sh <판> judge`(측정된 항목 = 시드뿐) → 시드 IS 값(t_alpha_vis · uc_vis · beta_vis)을 같은 사양 · 같은 자료 판의 `P1R04_FVALU_R0` 값과 대조(허용 1e-9). 같으면 tick_hold 를 지운다. 다르면 tick_hold 를 둔 채 자료 판 · 판 경로 원인을 본다(다른 판정을 읽지 않는다).
- 지운 뒤: 매시 틱이 scan → standing-measure → standing-report 를 한다(배리어 · 지문 · 판 표식은 코어가 본다). 통과 보고 = 일 요약(판단 T1 C-058).
- 판정 일치 기록(철학 N2 · 판단 C-056): T1 판정을 읽기 전에 T0 15 의 판정이 P1R03 · P1R04 기준 칸과 같은지 양방향(통과 → 통과 · 미달 → 미달)으로 기록한다. 다른 칸은 '원천 판정과 다름' 표식 · 원인 기록 뒤에만 기저 풀에서 쓴다.
- 방향 수정 순서(S-6): 등록부 방향 수정(V23 · C08 · CR05)은 시드 판정 뒤에 한다 — 그 전에 고치면 시드 엔진이 본문 단정으로 멈추거나 새 md5 가 되어 양성 대조를 잃는다.
- 사슬 1호 닫기 재채점(--regrade-write)은 등급 v3.5 발효 뒤(그 전 닫기는 --regrade-dry-run) — 재개 저널 OP-20261113-P1R04 에 적었다.
- 예상: 30 항목 × 칸당 2.5~3.6분(P1R03 실측) — P1R04 · 이음매 세션의 P1R03 재측정이 같은 자료 판에서 같은 T0 엔진을 먼저 재면 기저 캐시 적중으로 더 짧다.

## 9. 기저 풀로 가는 길(코어 v4 관문)
- 통과 칸 → `round.sh - p4-pool`(기본 판 = v4 · RELEASES 항목 뒤) → 관문: philosophy_unread(상설 pass 기록의 P2 또는 원천 라운드 영수증) · philosophy_hold · lowrisk_confirm_pending(카테고리가 방어 · 위험 · 국면과 겹치는 엔진 — 토탈 포함 — 은 엔진 단위 release_decision).
- P1R03 영수증(`P1R03/results/philosophy_receipt.json`)은 원 세션이 `rc_philosophy_receipt_write` 로 쓴다(hold 0 · 저β 5 의 release_decision = LOWBETA-ENGINES-BASE-USE-20261113 — 그 결정 대상은 P1R03 엔진뿐).
- 사슬 1호(P4C01) = 이 판 통과 + 영수증 해소 + P1R04 30칸 산출(원천 시행) 뒤 등록.

## 10. 알려진 한계
- 감시기 `superfan_watch.py` scan_stale 은 판 번호가 가장 큰 원장 하나만 본다(갈래 모름) — 레인 판 2 가 있는 동안 이 판의 스캔 정체는 그 규칙에 안 보인다(코어 밖 수리 과제).
- 등록 시험 묶음 없음(도훈 11-12 · 11-13) — 코어 v4 시험(출시 전) · 엔진 PIT 값 검사(P1R03 · P1R04 등록 때)를 핀과 입구 재생성 md5 대조가 잇는다.
