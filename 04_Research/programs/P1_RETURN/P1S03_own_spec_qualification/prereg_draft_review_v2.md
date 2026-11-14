# P1S03 사전등록 초안 v2 변경분 격리 점검

- 점검자: 격리 변경분 점검(서브에이전트)입니다. 이 판의 설계 · 구현에 참여하지 않았고, 측정 결과를 보지 않았습니다. 커밋 메시지 · 변경 목록 · `changes_after_*` 는 진술로만 읽고, 판정은 코드 · 파일 재도출로 했습니다. 코어 v4 자체는 다른 점검자 몫(`04_Research/01_reports/round_core_v4_review_20261113/`)이라 이 판이 코어를 맞게 쓰는지만 봤습니다.
- 대상(md5): `prereg_draft.json` v2 **2bb35411156e33b6b16b846832733ce7** · `prereg_draft.md` d8bdf8cf · `round_spec.json` 85a4d6a4 · `specs/P1S03_FVALU_RX0.json` c23f930e · `drafts.json` 34b75304 · `DESIGN.md` 25698444 · `tools/init_p1s03_v2.R` ab776a13 · `tick_hold` 22b28b90 · `behavior_card_cfg_at_prereg.json` 6a2a1d21 · `standing_rules.md` c5470d7b · 코어 v4 매니페스트 95d4a286 · 비교 기준 = 커밋 86c86e8fc 의 v1(`prereg_draft.json` 52741cbc · `round_spec.json` 48bd40f4 · 시드 86737c39)
- 시각: 2026-11-14 16:15 ~ 16:50 KST · HEAD 시작 `9662d7983` · 끝 `9d3321bbf`
  - 점검 중 다른 세션 커밋 10건(f7c0e32f3 · 5963a3e58 · f7497d76d · ab249291e · f01e69016 · 71dfc35ef · 9b409e1af · b8d80fe82 · 1425929ea · 9d3321bbf).
  - 핀 대상 변경은 0건입니다(끝에서 `rc_pins_mismatches` 0 · `rc_standing_validate` PASS 다시 확인).
  - 9d3321bbf 는 v2 파일을 바이트 그대로 커밋했고(md5 불변) `tools/init_p1s03_v3.R`(9fa110e9 · 미실행)를 더했습니다.
- **판정: revise**
- **건수: 필수 1 · 권고 1 · 선택 7**
  - v1 지적 11건(필수 2 · 권고 3 · 선택 6)은 모두 해소됐습니다(코드 · 사양 · 판 폴더 재도출).
  - 규칙 · 문턱 · 입구 · 갈래 · 판 · 핀 · 시드 시행 수(45) · 초안 재생성(손 편집 0)은 재도출과 맞습니다.
  - 필수 M-1 은 v2 설계의 결함이 아닙니다. **점검 중에 자료 판이 바뀌었습니다**(D1 판 표식 줄 16:23:39 · D2 결정 16:31:29). v2 는 등록하지 않고, 초안 v3(이미 커밋된 `init_p1s03_v3.R` — D2 줄 뒤 실행)와 판 폴더 정정(DESIGN §8 ① ③ · tick_hold)으로 갑니다.

## 0. 정보 경계 · 한 일

- 연 것
  - 판 폴더: `round_spec.json` · `prereg_draft.json` · `prereg_draft.md` · `drafts.json` · `DESIGN.md` · `specs/P1S03_FVALU_RX0.json` · `tick_hold` · `tools/init_p1s03_v2.R` 전문 · `tools/init_p1s03_v3.R`(v2 대비 diff) · `prereg_draft_review_v1.md` · v1 사양 3종(git show 86c86e8fc) · 행동 카드 사본은 md5 만.
  - 코어 v4: `standing.R`(128-240 · 287-516 · 800-1274 · 1352-1501 · 1600-1760) · `register.R`(1-155) · `pins.R` 전문 · `spec.R` · `load.R` · `util.R`(1-60 · 60-249) · `p1.R`(머리 · 철학 줄) · `p4.R`(84-140 · 186-190 · 247-272 · 505-512 · 995-1003 · 1585-1633) · `fingerprint.sh` · `round.sh`(grep). `RELEASES.json`(v4 항목). v3 ↔ v4 `cell_eval.R` · `metrics.R` · `rc_p1_table` diff.
  - 엔진 · 계약: `FC_FAM_value/engine.R`(1-124) · `contracts/factor_db_vintage.R`(100-234) · `superfan_watch.py`(470-510) · `superfan_components.json`(scan_stale 규칙) · `standing_board_run.sh`(머리 · grep).
  - 원천 라운드 · 선례: P1R03 · P1R04 사전등록(칸 · 핀 · 시험 기록 · 결론 범위만) · `P1R04_FVALU_R0` · `P1R03_FVALU_C0` 칸 사양 · P1R04 `DESIGN.md` §7-§10 · P1R04 `tools/p1r04_measure.sh`(grep) · P1S02 사전등록(핀만).
  - 등록부 · 원장 · 기록: `research_programs.json`(P1 라운드 상태 · prereg md5) · `factor_db_vintage.json`(id · completed_at · scope 만 — note 는 안 읽음) · `decision_register.json`(D1 · D2 항목의 title · status · decision · decided_at) · `q_judgment_ledger.json`(P1S03 리뷰 · 도전의 id · role · trigger · round · file · grade · status · hold_request · 응답 수만) · `.cache/scheduler_logs/p1r04_measure_state.txt`(셸 상태 1줄).
  - 이름 · 시각만: P1R04 `results/`(비어 있음) · `99_Archive/p1r04_aborted_measure_20261113_1030/`(파일 이름 · 시각) · `stage_artifacts/programs/P1_RETURN/P1R04_*`(prereg.json 만) · P1S03 `results/`(비어 있음) · `.cache` 데이터 파일 mtime(RAWDATA · build_hash · IC 원장 · 결합용 뷰 · FC 기저 캐시).
- 안 연 것: 모든 `results/**` 파일 내용 · `verdict.json` · `evaluation_visible.json` · `authoritative_remeasure.json` · `standing_visible.json` · 상설 원장 본문 · 텔레그램 기록 · 철학 · 판단 리뷰 본문과 도전 문구 · P1R04 보관 폴더 파일 내용 · 판 표식 원장 note.
- 우연 열람(3건 · 이 점검에 쓰지 않음)
  - `git log` 출력 속 다른 과제 커밋(c2eb635a8 · K200 위험 브리핑) 메시지에 그 모형의 OOS 통계가 있었습니다. 이 판과 무관하며 옮겨 적지 않습니다.
  - D1 코드 커밋(dda1e34ca) 메시지에 옛/새 팩터 값 대조(비트 동일 달 · 바뀐 달 · 종목 수)가 있었습니다. 자료 수리 범위이지 전략 성과가 아닙니다.
  - D2 결정 제목에 단절 행 수(자료 결함 크기)가 있었습니다. 전략 성과가 아닙니다. M-1 의 'IS 구간 행 포함' 근거로만 씁니다.
- 원장 판독 함수: `rc_standing_nf_prior` · `rc_standing_known`(`rc_standing_scan` dry-run 안)은 상설 원장을 읽습니다. 출력은 계보 회계 최댓값 · 상태(new/known)만 찍었습니다(v1 과 같은 방식).
- 돌린 것
  - Rscript 5개(스크래치 폴더 · `QM_ROOT`=`C:/Users/99922/OneDrive/Quant_Module_Moltbot` 명시).
    - `verify_v2.R`: 매니페스트 · 사양 검사 2모드 · 생성 함수 핀 · 핀 계산 · 대조 · v1 대비 핀 · 시드 재생성 · `rc_standing_own_nf` · 원천 칸 표 · `rc_standing_scan(dry_run = TRUE)` + 행마다 시행 수 · 규칙 문서 재생성 · 규칙 해석 · τ_D 검사.
    - `init_p1s03_v2_scratch.R`: 생성기 사본입니다. 쓰기 두 곳(시드 · 사양)만 스크래치로 돌렸습니다(diff 2줄).
    - `init_p1s03_v2_vint.R`: 위 사본에서 `VLAST <- VINT` 로 16:13 원장 상태를 재현했습니다.
    - `regen_draft.R`: 스크래치 판 폴더 + v1 `drafts.json` 으로 `rc_draft` 를 돌렸습니다.
    - `pins_end.R`: 끝 재확인입니다.
  - Python: 잎 단위 diff · 목록 diff · 시행 수 독립 재도출(`nf_indep.py` — 코어 R 코드를 쓰지 않는 경로) · 원장 구조 판독.
  - 그 밖: git log/show/diff/status · md5sum · ps · Win32_Process 조회.
  - 쓰기 없음 확인: P1S03 `results/` 비어 있음 · `stage_artifacts/programs/P1_RETURN/P1S03_*` 없음 · `.cache/round_core/perf/` 에 P1S03 기록 없음 · 판 폴더 git 깨끗.
- 쓴 것: 이 파일 1개(저장소). 그 밖은 스크래치 폴더뿐입니다.

## 1. 항목 점검 (1–8)

| # | 항목 | 결과 | 근거(file:line · 재도출) |
|---|---|---|---|
| 1 | v1 지적 해소 | 11/11 해소(표 1-a) · F-3 · F-4 의 판 표식 조건은 점검 중 D1 · D2 로 다시 열림 → M-1 | 표 1-a |
| 2 | v1 → v2 잎 차이 전부 | 설명 안 되는 차이 0 · 자기 서술과 어긋남 1(R-1) | 표 2-a. 사양 잎 118 → 134 · 시드 2잎 · 초안(사양 밖) 8종. 불변: schema · program · round_id · template · core_version · tau_d · standing · standing_cfg(edition · program · track · generator · generator_pin · scan 전 잎 · rejudge · report.fail · superfan) · cells · rules · selection · tests · behavior_card_cfg · rules_resolved · sentences · 패키지 · R 판 |
| 3 | 규칙 · 문턱 · 입구 · 시드 · standing_cfg = v1 | 규칙 · 문턱 · 입구 · 갈래 · 판 = 같음 · **통과 보고 · 회계 문구 · 시드 시행 수는 다름**(모두 감독 · 점검 · 코어로 설명) | rules JSON = `.rcs_p1_template_rules` 산출(재도출 TRUE) · rules_resolved · sentences 잎 0 차이(문턱 2 · 0.55). scan · generator_pin 잎 0 차이 · 지금 `rc_standing_generator_pin()` 차이 0(fn_md5 80f8311f · like_md5 080cfea8). 입구 dry-run 30 · 통과 30 · new 30 · 사유 0 · 선언 전부 source_round. FC_* 엔진은 86c86e8fc 뒤 커밋 · 수정 0(FC_FAM_value faba4b41). 다름: `report.pass` push_each → daily_summary(round_spec.json:58 · 생성기 :122 · 판단 C-20261113-058 노트 · 코어 허용 standing.R:63 · :202-204) · `accounting.rule`(:54 = 코어 생성 문구 standing.R:1654-1657) · 시드 n_family 2 → 45(M3 · C-036). '감독 · 점검 지적만 반영'은 사실이나, 노출 줄의 '시드 · 기대는 v1 과 같다'는 사실 아님 → R-1 |
| 4 | 시드 칸 시행 수 = 같은 엔진 스캔 행 규칙 | 일치(45) · 세 경로 | ① 독립 재도출(Python · 등록부 → 사전등록 → 칸 사양 · 핀 md5): FC_FAM_value md5 faba4b41 칸 = P1R03_FVALU_C0(variant · FC:value) · P1R04_FVALU_R0(reference). FC:value 칸 = 그 둘 + P1R04_IVALU_C0(variant · nf 2). 원천 라운드 {P1R03 15칸 · P1R04 30칸} → n 45 · 재측정 참 · 계보 앞선 최댓값(사전등록 부분) 2 → max(2, 45) = 45 ② `rc_standing_own_nf(FC_FAM_value)` = 45(remeasure · rounds 둘 · n_cells 45 · nf_prior 2 · mismatch 0 · unknown 0 · unverified 0) ③ dry-run 스캔 행 FC_FAM_value(엔진 md5 = 시드 엔진 md5)를 enqueue 와 같은 인자(handoff_rounds = 행 source_rounds · lane_n 1 · nf_prior = `rc_standing_nf_prior`)로 → 45. 30행 모두 45. 시드 사양 :43 = 45 · `rc_standing_validate(check_seeds)` 하한 검사 통과(standing.R:214-231) |
| 5 | 핀 | 일치 · 불일치 0(시작 · 끝) | `rc_pins_compute` 37 = 기본 18(pins.R:6-13) + pins.files 16 + 엔진 1 + 칸 1 + 카드 사본 1(겹침 0) = 초안 37(경로 · md5 · 패키지 · R 판 동일). 매니페스트 95d4a286 = RELEASES v4 = 파일 20 md5 동일. v1 대비: 경로 집합 같음(순서만 — 생성기 둘이 앞 · standing.R:1669-1670 자동 핀) · md5 바뀐 것 = 등급 v3.5 6파일(diagnosis_packet.R 02798823 · essence_score.R f0108804 · grade_v3.R 436debe9 · matched_controls.R 4202199b · grade_v3.json 7677c169 · matched_controls.json 1e3becaa — 디스크 = HEAD 블롭 · 미커밋 변경 0) + 시드 칸 사양 c23f930e · pins.core 4파일(p1.R · p4.R · rules.R · standing.R). 판정 경로: P1S02 spec 핀 13 ⊂ 이 판 · P1R04(재핀 뒤) 핀과 공통 32 md5 전부 같음(시드 대조 상대와 같은 코드 · 같은 패키지 · R 판). 생성기 ⊂ pins.files 검사 통과(standing.R:186-190). 제외 근거 문장 사실: 엔진이 own_spec.json 을 실행 때 읽지 않음(engine.R 은 주석에만 이름 · 팩터 입력은 `fc_load_month` :81) · 부호 · 가족 단정(:93-106) · dedup FALSE(:81) · 캐시 키에 뷰 · IC 원장 없음(rf_base_cache.R md5 3794bc7b = v1 핀 · 키 불변) · 측정 지문은 둘 다 포함(fingerprint.sh:17-21). 공유 등록부 미커밋 변경 = 새 맞춤 팩터 1개 추가뿐(기존 370 팩터 잎 변화 0 — 무영향). 근거 누락 1곳 → S-3 |
| 6 | 글의 사실성 | 노출 · 결론 대체로 맞음 · **판 표식 문장은 지금 원장과 안 맞음(M-1)** · 자기 서술 어긋남(R-1) | 노출 [4](:129) 'P1R04 판정을 보지 않았다' = 기록과 맞음. P1R04 DESIGN.md:92 '측정 중단 1회(11-13 10:31 · 결과 전)' · 보관 폴더에 칸 결과 10개 + 11번째(ICONS) 시작 기록뿐(평가 파일 없음 · 10:04~10:30) · P1R04 `results/` 빔 · stage_artifacts 에 prereg.json 만 · 등록부 registered · 측정 셸 16:29 '보류(세션) — D2 뒤 측정' · 프로세스 없음. 노출 [1] R-20261113-002 = 철학 P2 · P1R03(원장 구조). 판 표식: :9 '곧 더해질 D1 … 줄' · :144 '(그 줄이 이 판 등록 뒤에 생긴다)' ↔ 원장 마지막 줄 PRICE-CONTINUITY-FACTORS-20261113(completed_at 16:23:39 · ab249291e 커밋) → 둘 다 지금 사실 아님. `rc_after_tau_leaks`(사양 글 전부) = 빈 결과. `rc_input_issues`: 등급 표기 0 · τ_D 뒤 연도 = 결정 id 의 YYYYMMDD(관례 · v1 같음) + v2 새 '2023'(:127 → S-2) · 시험 창 수치 적중(OOS … 8/15 · T0 · 0.55 · T4) = IS 판정 수 · 칸 이름 · 문턱 · 판단 번호를 수치로 읽은 오탐(v1 에도 같은 종류). 시드 사양 글 통과 |
| 7 | 사양 검사 · 초안 재생성 | 통과 · 손 편집 0 | `rc_standing_validate(spec)`(check_pin · check_seeds) PASS · 맥락 모드 PASS. 초안: 스크래치 `rc_draft` → md d8bdf8cf = 디스크(바이트 동일) · json 은 drafted_at 만 다름(디스크 시각을 넣으면 2bb35411 = 디스크) · 초안 spec = round_spec.json. 사양: 생성기를 16:13 원장 상태(`VLAST = RAWDATA-SEAM-…`)로 고정하면 85a4d6a4 = 디스크. 지금 원장으로 돌리면 4b7ca76c(가설 · 결론 범위 [9] 두 잎만 다름 → M-1). 시드 재생성 c23f930e = 디스크 = 초안 칸 md5. `standing_rules.md` 재생성 c5470d7b = 디스크. `drafts.json` v2 = (2bb35411 · d8bdf8cf · review null) |
| 8 | 등록 · 첫 측정을 막거나 무효로 만드는 것(새로 생긴 것) | 막는 것 없음 · **무효 위험 1(M-1)** · 시점 의존 1(R-1) | 새로 생긴 것: ① D1 판 표식 줄(16:23:39) → v2 글 두 잎 낡음 ② D2 결정(RAWDATA-INTERNAL-BREAK-FILL-D2D3-20261114 · resolved 16:31:29 · '판 원장 1줄' · 제목 '2000~ 89행 · 측정 축 6행')이 IS 구간 행을 정정 → v2 의 IS 무영향 전제 · T0 기대 · 해제 조건 ①(D1)이 맞지 않음 · D2 줄 전에 잰 칸은 이 판에서 다시 잴 길이 없음(M-1) ③ P1R04 측정 셸이 'D2 뒤'로 보류 → 해제 조건 ③ '셸 끝' 표현이 모호(M-1) ④ P1S02 는 v3.5 핀 불일치로 판 3 새 등록 예정(f7497d76d) — 갈래가 달라 이 판을 안 막음(standing.R:333-336) ⑤ 노출 줄은 등록 시점 사실이어야 함 — D2 뒤 P1R04 재측정과 경쟁(R-1) |

### 1-a. v1 지적별 해소

| v1 | 결과 | 근거(재도출) |
|---|---|---|
| F-1 시드 행이 v4 관문 우회 | 해소(코어 v4) | 자체 사양 시드 = 넣을 때 `.rcs_own_seed_check`(standing.R:1179-1183 → :939-953 계보 · 미등록 원천 · 선언) + 인계 기록 `.rcs_own_handoff`(:1183 → :971-978 origin own_spec · own_spec_md5 · generator · families · source_rounds). 자격 표: origin 은 여전히 seed(:405)지만 관문은 own_spec_engine 열(:408 — 갈래 ∨ 인계 ∨ own_spec.json)로 판정. 기저 풀 qown(p4.R:188) → philosophy_unread · philosophy_hold · lowrisk_confirm_pending(:251-272). 사슬 원천 시행(p4.R:999). 시드 시행 수 = 스캔 행 규칙(항목 4). 잔여 = 시드 선정 사유 문장(P1R03 자격 8 중 FVALU)만 — 시드가 스캔 행과 같은 길을 받게 돼 v1 이 걱정한 '선정이 풀 경로에 닿는' 길은 닫힘(지적 아님) |
| F-2 시드 먼저 판정 | 해소(판 폴더) | DESIGN.md:36-39 · tick_hold:1 · round_spec.json:142. 손 `judge` 는 측정된 항목만(standing.R:312-313 · :1407) → 시드만 판정. tick_hold 는 무인 틱만 막음(standing_board_run.sh:47) |
| F-3 해제 조건 RELEASES v4 | 해소 | DESIGN.md:38 ② · tick_hold:1 · RELEASES v4 released(2026-11-13T20:07:03 · 95d4a286) · 판정 출시 관문(standing.R:981-990 · :1405). 판 표식 조건은 bd39a4b9b 에서 D1 로 바뀐 뒤 D2 로 다시 낡음 → M-1 |
| F-4 τ_D 뒤 날짜 · IS 무영향 근거 | 해소 · 전제 재붕괴 | 사양 글 `rc_after_tau_leaks` = 빈 결과(v1 '2026-03-30' 적중) · IS 무영향 = '예상'(:9) · DESIGN · tick_hold 에 데이터 날짜 없음(DESIGN:3 작성일만). D2 결정으로 '예상' 전제가 깨짐 → M-1 |
| F-5 (1) 캐시 키 문장 | 해소 | :189 '기저 신호 캐시 키에는 둘 다 없다' · 측정 지문 · 판 표식 역할 문장 = 코드(fingerprint.sh:17-21) |
| F-5 (2) · (3) 캐시 시각 · 인프라 과제 | 해소 | DESIGN.md:38 ④ · :159 알려진 한계 · RELEASES v4 known_limits 둘째 줄 |
| S-1 문장 정밀도 5곳 | 해소 | :8(P1R04 test_hold 없음 · 새 결합기 = 새 생성기 → own_generator_unknown · 스캔 29) · :156(T1 대체 규칙 — 카테고리/토탈 구분) · :141(schema ≠ fc_own_spec_v0 · 코어 v4 선언 · 계보 사유) |
| S-2 핀 제외 목록 | 해소 | :189 own_spec.json · factor_dup_scan.R · 등록부 문장(뷰 부호표 · 다음 뷰 빌드에서 멈춤) |
| S-3 standing-check · 규칙 문서 | 해소 | `standing_rules.md` = 재생성 바이트 동일 · 9d3321bbf 커밋 · 시드 회계 = 규칙(45) |
| S-4 시험 갈음 포인터 | 해소 | :158. 시험 파일 md5(test_fc_engine_gen.R 6724f1c8 · test_fc_combiner_gen.R aee44109) = P1R03 · P1R04 등록 시험 기록(9/0 · 12/0). 생성기 md5(e31ad11f · 6b2a6e45) = 두 라운드 핀 = 이 판 핀. RELEASES v4 tests_at_release 71/0(기록 대조만) |
| S-5 회계 문구 ↔ 코드 | 해소(코어) | :54 = standing.R:1654-1657 생성 문구 = `rc_standing_own_nf`(:919-935) · `.rcs_own_source`(:853-869) 동작 |
| S-6 방향 수정 순서 | 해소 | :151 · DESIGN.md:42 |

### 2-a. v1 → v2 잎 차이와 원인

| 잎 | 차이 | 원인(재도출 · 대조) |
|---|---|---|
| `purpose`(:8) | 문장 다시 씀 | S-1 3곳 + C-055('아는 답을 그대로 내는지') + 용어 '등가중 → 동일가중'(변경 목록에는 없음 · 도훈 11-13 용어 결정 — P1R04 DESIGN.md §10 용어 줄) |
| `hypothesis`(:9) | 기대 구체화 · 판 표식 | C-055(IS 값 = P1R04_FVALU_R0) · C-056(T0 15/15) · S-1(T0 15 · T1 15) · F-4(판 표식 id · '예상') · 생성기 :31(D1 글) |
| `standing_cfg.accounting.rule`(:54) | 문구 | 코어 v4 생성 문구(standing.R:1654-1657 · C-036 · R1) |
| `standing_cfg.report.pass`(:58) | push_each → daily_summary | 판단 T1 C-20261113-058(노트) · 생성기 :122 · 코어 허용 값 |
| `exposures`(:124-133) | 6 → 8 | 유지 5(재배열) · 삭제 1(v1[2] 'P1R04 측정 전 · 결과 없음') · 새 3([1] · [2] = C-057 노출 2줄 · [4] = cddd372cc 고지 정정) |
| `conclusion_scope`(:134-160) | 13 → 25 | 글자 그대로 유지 2(v1[0] → [4] · v1[10] → [22]) · 다시 씀 10(v1[1] → [5] 용어 · [2] → [6] S-1 · [3] → [7] F-2 · C-055 · C-036 · [4] → [9] F-4 · D1 · C-054 · [5] → [11] · [12] C-048 · [6] → [13] C-047 · [7] → [14] C-046 · v3.5 표기 · [8] → [16] S-6 · [11] → [21] S-1 · [12] → [23] S-4) · 대체 1(v1[9] → 코어 기본 줄 [3]) · 새 줄(코어 기본 [0]-[3] = p1.R:12-18 · C-049 / [8] C-056 / [10] C-050 / [15] C-046 / [17]-[20] 원천 라운드 줄 C-049 — 문장이 P1R04 결론 범위 [30] · [28] · [14] · P1R03 결론 범위 [11] 에 있음 / [24] C-060) |
| `changes_after_review` · `changes_after_superfan` | [] → 2줄씩 | 기록 |
| `pins.files`(:171-188) | 같은 16 · 순서 | 코어 v4 생성기 자동 핀이 앞(standing.R:1669-1670) + 생성기 :100 `unique(c(…))` |
| `pins.basis`(:189) | 문장 | F-5(1) · S-2 · README 인용 삭제(자동 핀 S-g 로 대체) |
| 시드 `n_family_at_registration` · `n_trials_basis`(시드 :43-44) | 2 → 45 · 근거 문구 | 변경분 점검 2 M3 · C-036 → `rc_standing_own_seed_spec`(standing.R:1627-1638). 생성기 :22-23 이 다른 잎 변화를 막음 · 재생성 = 디스크 |
| 초안 `core.manifest_md5` · `pins.core` | 320611fa → 95d4a286 · p1.R · p4.R · rules.R · standing.R | 7037cd6cc · 028078396(두 커밋이 고친 파일 = 이 넷) → 456babdbc 출시 |
| 초안 `pins.files` md5 7 · `cells[0].md5` · `spec_md5` · `draft_version` · `drafted_at` | — | 등급 v3.5 교체(317a9c0e0 · 6파일) · 시드 · 사양 · 판 번호 · 시각 |

등록 조건(register.R:106-145)의 지금 상태입니다.

- ① 이 점검 = revise → 초안 v3 · 변경분 점검이 필요합니다.
- ② 사양 · 칸 md5 = 초안(v2)입니다.
- ③ 핀 37 · 불일치 0 입니다.
- ④ 시험이 없습니다(빈 목록).
- ⑤ 리허설 필드가 없습니다.
- ⑥ 철학 P1 R-20261113-006 이 있습니다. 파일이 실재하고, 이름 형식(register.R:83)을 지키며, 도전 5건은 accepted · 응답 1씩이고, 열린 보류는 0입니다(구조만 봄). v2 · v3 에 대한 새 P1 리뷰는 없습니다. `rc_p1_check` 는 이를 요구하지 않습니다.
- ⑦ 판 폴더는 9d3321bbf 로 깨끗하고, 코어 폴더도 깨끗합니다.
- ⑧ 미실행입니다.

## 2. 지적

### 필수

**M-1. v2 는 등록 대상이 아닙니다 — 점검 중 자료 판이 바뀌어 v2 의 판 표식 글 · T0 기대 · 해제 조건 ①이 등록 시점 사실과 어긋납니다. 해제 조건 ①대로 D2 줄 전에 재면, 그 판정은 이 판에서 기저 자격을 영영 못 받습니다**

- 근거
  - D1 줄: `06_Registry/factor_db_vintage.json` 마지막 줄이 PRICE-CONTINUITY-FACTORS-20261113 입니다(completed_at 2026-11-14T16:23:39 · scope 23팩터 · 커밋 ab249291e). v2 생성(사양 16:13:43 · 초안 16:14:03) 뒤에 들어왔습니다.
    - v2 글 :9 '곧 더해질 D1(…) 줄' · :144 '(그 줄이 이 판 등록 뒤에 생긴다 — 이 판 측정은 그 뒤)'는 지금 사실이 아닙니다.
    - 생성기 자체 규칙(`tools/init_p1s03_v2.R:29-32` — '등록 때 마지막 줄을 읽어 글을 맞춘다')으로 지금 다시 만들면 사양 md5 는 4b7ca76c 입니다. 이 두 잎만 다르고, 16:13 원장 상태로 고정하면 85a4d6a4 = 디스크입니다.
  - D2 결정: `decision_register.json` RAWDATA-INTERNAL-BREAK-FILL-D2D3-20261114(resolved 2026-11-14T16:31:29 · '판 원장 1줄')입니다. 제목은 '원천 내부 단절 행(101 · 2000~ 89 · 측정 축 6)'이고, 결정 문구의 날짜별 가격제한폭 규칙에 '2015-06-15 전 ±15%'가 있어 IS 구간 행이 들어 있습니다.
    - 원 세션은 'IS 값이 바뀐다'고 적었습니다(9d3321bbf · P1R04 셸 상태 줄). 이 점검은 크기를 재도출하지 않았습니다.
    - 그러면 :9 'T0 15 = P1R03 · P1R04 같은 판정(15/15 — IS 구간은 … 수리 범위 밖으로 예상)'과 :143 'T0 15 의 기대 = P1R03 · P1R04 같은 배치 기준 칸과 같은 판정'의 전제가 깨집니다.
  - 무효 경로
    - DESIGN.md:38 해제 조건 ①은 'D1 줄이 원장에 있다'입니다(지금 충족).
    - 자체 사양 엔진 칸은 선언 팩터를 알 수 없습니다(factor_db_vintage.R:114-120 — base_signal 이 엔진이면 NULL · 이 점검 재실행: 시드 = NULL). 그래서 범위가 무엇이든 모든 수리가 닿습니다(:211).
    - 따라서 D2 줄 전에 잰 이 판의 칸은 D2 줄이 생기는 순간 전부 `factor_db_stale` 로 기저 풀에서 빠집니다(p4.R:247).
    - 상설 판은 판정한 항목을 다시 재지 않습니다(standing.R:1359). 같은 엔진은 rejudge 판이 아니면 다음 판에도 못 들어갑니다(standing.R:1111-1114). 결국 이 판의 판정이 기저 자격 용도로 쓸모없어지고, 새 판(rejudge)이 필요해집니다.
  - 지금 막고 있는 것은 ③(P1R04 측정 셸 끝)과 시드 대조 상대(같은 자료 판의 P1R04_FVALU_R0)가 없다는 사실뿐입니다. 셸은 16:29 '보류(세션) — D2 뒤 측정'으로 멈췄고 프로세스도 없습니다.
    - ③은 '셸 끝'으로만 적혀 있어, 멈춘 셸을 '끝'으로 읽을 수 있습니다.
    - ①은 D1 이면 충분하다고 명시합니다.
- 고치는 법
  - (사양) v2 를 등록하지 않고 초안 v3 로 갑니다. 이미 커밋된 `tools/init_p1s03_v3.R`(9fa110e9)를 D2 판 표식 줄 뒤에 돌립니다. 이 생성기는 D2 줄 · P1R04 평가 산출 없음을 전제로 검사하고, 판 표식 글 · T0 기대 비교 상대 · 노출 줄을 바꿉니다.
  - v3 의 `changes_after_review` 에 '격리 점검 v2(이 파일 · revise) → 초안 v3' 한 줄을 더합니다. v3 생성기 :129-130 은 v2 문구 그대로입니다.
  - (판 폴더 · 등록 커밋에 포함)
    - DESIGN §8 ①을 'D2 판 표식 줄(결정 RAWDATA-INTERNAL-BREAK-FILL-D2D3-20261114)이 원장 마지막 줄 · 그 뒤 IC 원장 · 결합용 뷰 재빌드 끝'으로 고칩니다.
    - ③을 'P1R04 의 D2 뒤 재측정 · 평가 끝(시드 대조 상대 = 그 산출의 P1R04_FVALU_R0)'으로 고칩니다.
    - `tick_hold` 첫 줄의 '판 표식 RAWDATA-SEAM-0330-REPAIR-20261113'(tick_hold:1 — bd39a4b9b 때도 안 고침)을 같은 D2 조건으로 고칩니다.
- 고친 뒤 확인
  - v3 생성기를 그때 원장 상태로 다시 돌려 md5 = 디스크인지 봅니다.
  - v2 → v3 잎 차이가 아래 '초안 v3 를 만들 때' 목록뿐인지 봅니다.
  - 가설 · 결론 범위의 판 표식 id 가 원장 마지막 줄 id 와 같은지 봅니다.
  - `rc_after_tau_leaks` 가 빈 결과인지 봅니다.
  - DESIGN ① ③ · tick_hold 문장이 같은 id 인지 대조합니다.

### 권고

**R-1. 노출 [4]의 '바뀐 것' 서술이 사양 차이와 맞지 않고, P1R04 비노출 문장은 등록 시점에 다시 확인해야 합니다(v3 생성기에도 남음)**

- 근거
  - round_spec.json:129 는 'v2 에서 바꾼 것은 감독 · 점검 지적(문장 · 회계 문구 · 코어 판)뿐이고, 자격 규칙 · 문턱 · 입구 · 시드 · 기대는 초안 v1 과 같다'고 적었습니다. 재도출 결과(표 2-a)는 다릅니다.
    - ① 통과 보고 단위가 바뀌었습니다(push_each → daily_summary · :58).
    - ② 시드 칸 사양이 바뀌었습니다(c23f930e ≠ v1 86737c39 · n_family 2 → 45). '시드 같다'는 엔진 · 구성에만 맞습니다. 같은 사양의 :142 가 바뀐 규칙을 적고 있어 안에서 서로 어긋납니다.
    - ③ 기대가 바뀌었습니다. v1 '시드 자격 유지'에서 v2 'IS 값 = P1R04_FVALU_R0 · T0 15/15 · T1 = P1R04 변형 칸'(C-055 · C-056)이 됐습니다. 따라서 '기대 같다'는 사실이 아닙니다.
    - ④ 등급 v3.5 6파일 핀도 바뀌었습니다(첫 문장에만 있음).
  - v3 생성기 :65 는 '기대'를 빼고 '자료 판 글'을 더했습니다. 그러나 '시드는 초안 v1 과 같다' · 보고 단위 누락은 그대로입니다.
  - 시점: 'Q 는 P1R04 의 판정을 보지 않았다'는 등록본의 노출 고지라 **등록 시점** 사실이어야 합니다. v3 생성기 검사(`init_p1s03_v3.R:24-25` — P1R04 `results/evaluation_visible.json` 없음)는 생성 시점만 봅니다.
    - D2 뒤 P1R04 재측정(P1R04 DESIGN.md:66 '예상 소요 약 90분')과 v3 점검 · 등록이 경쟁합니다. 등록이 늦으면 고지가 거짓이 됩니다. `rc_register` 는 이를 보지 않습니다.
  - 정밀도(작음): '11-13 측정은 … T1 11칸 뒤 중단'은 보관 폴더 이름 · 시각으로 보면 '10칸 완료 · 11번째(ICONS) 측정 중 중단'입니다(10:30 시작 기록 · 결과 파일 없음).
- 고치는 법(v3 노출 줄)
  - '바뀐 것 = 문장 · 회계 문구(코어 v4) · 시드 칸 시행 수 2 → 45(M3 · C-036) · 통과 보고 단위(C-058) · 등급 v3.5 핀 · 기대 구체화(C-055 · C-056) · 자료 판 글(D1 · D2)'로 씁니다.
  - '같은 것 = 자격 규칙 · 문턱 · 입구 · 갈래 · 판 · 시드 엔진 · 구성'으로 씁니다.
  - 등록 직전 P1R04 평가 산출 유무를 다시 봅니다. 있으면 노출 줄을 고친 초안으로 갑니다. 또는 문장을 '초안 v3 생성 시점(…)에 보지 않았다'로 시점을 묶습니다.
- 고친 뒤 확인: v3 노출 문장을 v2 → v3(그리고 v1 → v3) 잎 차이 표와 대조합니다. 등록 커밋 직전 `ls P1R04/results` 결과를 등록 기록 메모에 남깁니다.

### 선택

- **S-1. DESIGN 의 낡은 줄**(사양 불변 · 판 폴더 정정)
  - :3 생성기가 'tools/init_p1s03.R'로 적혀 있습니다. 실제는 v2 · v3 생성기 · `rc_standing_own_seed_spec` 입니다.
  - :19 시드 'n_family 2'는 45 가 맞습니다.
  - :29 원천 라운드 · 시행 수 규칙 'T1 = P1R04 · 회계했으면 그대로 · 아니면 +1'은 v4 규칙과 다릅니다. v4 는 엔진 md5 ∪ 계보이고, T1 도 P1R03 + P1R04 이며, max(최댓값, 45) 입니다(standing.R:919-935 · dry-run 30행 모두 45).
  - :33 'P1R04 는 측정 전'에는 11-13 부분 측정 · 보관을 적어야 합니다.
  - :37 '등급 v3.5 핀 교체(P1R04 측정 · 평가 뒤 · v3.5 세션)'는 실제 순서와 다릅니다. 교체가 P1R04 재측정 앞입니다(cddd372cc · 9662d7983).
- **S-2. 노출 [2](:127) 'OOS(2023~)'의 연도 2023** 이 v2 에서 새로 생긴 `rc_input_issues` 적중입니다. 결정 id 의 YYYYMMDD 는 관례로 v1 과 같습니다.
  - 사전등록 노출 고지 안에서는 성과 수치가 아니라 무방합니다.
  - 이 줄을 결과 원장 · 사슬 판 글로 옮기면 처방 입력 검사(util.R:209-224)가 막습니다. 옮길 때는 'OOS(τ_D 뒤)'로 씁니다.
- **S-3. 핀 근거에 등록부 · 결정 기록부 제외 사유가 없습니다**(:189)
  - `06_Registry/research_programs.json` 은 원천 라운드 · 선언 · 시행 수를 정합니다(standing.R:805-844).
  - `06_Registry/decision_register.json` 은 선언 ② · 저위험 해제를 정합니다(:909-911 · p4.R:268).
  - 둘 다 판정 규칙 입력이 아니라 입구 · 회계 · 기저 풀 관문 입력입니다. 넣을 때 원장에 원천 라운드 · 가족이 남습니다(standing.R:1135-1137). 핀하면 등록부 쓰기마다 판이 멈춥니다. 한 줄 근거면 됩니다.
  - 함께 적을 점: T1 14 + 토탈의 선언은 'source_round'(P1R04 칸)뿐입니다. P1R04 사전등록 md5 가 등록부와 어긋나면 검증 불가로 빠져 own_spec_undeclared 로 입구에서 제외됩니다(standing.R:821 · :1065-1067). 9662d7983 재핀은 등록부도 같이 고쳤습니다(지금 일치). 앞으로의 재핀도 그래야 합니다.
- **S-4. 생성기 재실행 가드가 없습니다**
  - v2 생성기는 시드 칸 사양 · 사양을 존재 검사 없이 덮어씁니다(init_p1s03_v2.R:24 · :125). v3 도 같은 꼴입니다.
  - 등록 뒤 잘못 돌리면 R2(사양 md5 · seed_md5_not_prereg — standing.R:324 · :1214)로 판이 멈춥니다.
  - v2 생성기를 지금 돌리면 D2 없는 글(4b7ca76c)이 나옵니다.
  - 두 생성기 첫머리에 '등록본(stage_artifacts/…/prereg.json) 있으면 중단'을 넣고, v2 머리에 'v3 로 대체됨'을 표시합니다.
- **S-5. 시드 회계는 생성 시점 등록부로 셉니다**
  - `rc_register` 는 상설 사양 검사(check_seeds)를 부르지 않습니다(register.R:109 — `rc_spec_load` 만). 등록 전에 FC 계보 칸을 가진 P1 라운드가 더 등록되면 규칙값이 45 보다 커져도 등록은 통과합니다.
  - 등록 직전 `round.sh <판> standing-check`(시드 회계 = 규칙 · standing.R:1731-1748)를 다시 돌립니다.
- **S-6. 결론 범위 [13](:148)의 저위험 확인 집합 서술에 v4 의 셋째 길이 빠졌습니다**
  - 셋째 길은 원천 라운드 기계 꼬리표 `results/lowrisk_tags.json` 입니다(p4.R:265-266 · 028078396 R-D · P1R04 변환기 f7c0e32f3 · 판독 불가 = 꼬리표).
  - 판정과는 무관합니다. 기저 풀 사유를 읽는 사람을 위한 서술입니다.
- **S-7. 시드 1e-9 대조의 '같은 자료 판'은 판 표식 상태일 뿐, 바이트 동일 자료가 아닙니다**
  - P1R04 기준 칸 측정과 시드 측정 사이에 밤 갱신이 끼면 데이터 지문(RAWDATA · 결합용 뷰)이 다릅니다. 덧붙이기만이면 IS 값은 같아야 정상입니다.
  - DESIGN §8 해제 절차(:39)에 '두 측정의 지문(equality — 측정 기록 · `.fp_start`/`.fp_end`)을 함께 적고, 값이 다르면 지문 차이부터 원인 기록'을 한 줄 더합니다.
  - 대조가 성립하는 전제도 확인했습니다. 두 칸 사양은 메타 잎(code · label · idea · selection_accounting)만 다릅니다. 공통 핀 32 md5 · 행동 카드 사본 md5 · v3 ↔ v4 `cell_eval.R` · `metrics.R` · `rc_p1_table` 본문이 같습니다.

### 초안 v3 를 만들 때(변경분 점검 기준)

- 그대로여야 하는 것
  - rules · cells · selection · standing_cfg(scan · generator_pin · edition · track · report · superfan · accounting) · tests · behavior_card_cfg 를 그대로 둡니다.
  - 핀 37 경로를 그대로 둡니다. 사이에 파일 변경이 없으면 md5 도 같습니다.
  - 시드 칸 사양 c23f930e 를 그대로 둡니다. 등록부 원천 칸이 그대로면 생성기가 두 회계 잎 밖 변화를 막습니다.
  - 노출 [0]-[3] · [5]-[7] 과 결론 범위 [0]-[7] · [10]-[24] 를 그대로 둡니다.
- 바뀌어야 하는 것
  - 사양: 가설(:9) · 결론 범위 [8](T0 기대의 비교 상대) · [9](판 표식 = D2 줄 id) · 노출 [4](R-1) · `changes_after_review` 한 줄(M-1)입니다.
  - 판 폴더: DESIGN §8 ① ③ · tick_hold:1(M-1) · DESIGN 낡은 줄(S-1)입니다.
- 확인 방법
  - v3 생성기를 그 원장 상태로 다시 돌려 md5 = 디스크인지 봅니다.
  - 잎 차이가 위 목록뿐인지 봅니다.
  - 등록 직전에 P1R04 평가 산출 없음 · standing-check 시드 회계 = 규칙 · `rc_pins_mismatches` 0 을 봅니다.

## 3. 못 본 것

- 코어 v4 자체. 028078396 수리분에는 격리 재점검 기록이 없습니다(RELEASES v4 reviews: 'M3 해소는 Q 확인'). 이 점검은 P1S03 이 쓰는 경로(시드 검사 · 시행 수 · 사양 검사 · 갈래 · 출시 관문 · 기저 풀 자체 사양 판정)만 재도출했습니다. M3 는 이 점검의 독립 재계산(항목 4)으로 확인했습니다.
- 시험 묶음 재실행(test_round_core_v4.R 71/0 · 생성기 시험)은 하지 않았습니다. 기록 · md5 대조만 했습니다.
- 측정 · 판정 · 보고 실행(measure-item · judge · standing-report) · 셀 워커 · 기저 정합 관문 · 신선도 관문의 실제 동작은 돌리지 않았습니다.
- D2 의 IS 영향 크기는 결정 기록 제목의 행 수와 원 세션 진술만 봤습니다. 재도출하지 않았습니다.
- v3 생성기 실행 · 산출은 보지 못했습니다. D2 줄이 없어 전제 검사에서 멈춥니다. v2 대비 diff 줄만 읽었습니다.
- 철학 · 판단 리뷰 본문과 도전 문구는 구조 필드만 봤습니다.
- 나머지 29 엔진 본문은 입구 재생성 md5 대조(dry-run 30/30 통과)로 갈음했습니다.
- superfan_watch.py 는 코드 판독만 했습니다. 실행하지 않았습니다.
- 결과 · 판정 파일 · 권위 기록 · 텔레그램 기록 · P1R04 보관 폴더 파일 내용 · 판 표식 원장 note 는 정보 경계로 보지 않았습니다.
