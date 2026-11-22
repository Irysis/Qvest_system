# round_core v4 변경분 점검 2 (diff review · 출시 전 수리)

- 점검자: 격리 교차 점검자(isolated — v4 설계 · 구현 · 이번 수리에 참여하지 않았습니다)
- 대상: 커밋 `7037cd6cc`(부모 쪽 v4 = `25b5193d0`) — `v4/standing.R` · `v4/p4.R` · `v4/p1.R` · `v4/rules.R` · README v4 절 9 · `08_Tests/programs/test_round_core_v4.R`
- 점검 시각: 2026-11-13 19:00 ~ 19:30 KST
- **판정: revise**
- **건수: 필수 1 · 권고 6 · 선택 7**

---

## §0. 열어 본 것 · 돌린 것

**변경분**
- `git show 7037cd6cc` · `git diff 25b5193d0 7037cd6cc` — round_core 쪽 변경은 이 커밋 하나, 파일 6개뿐입니다. v1 · v2 · v3 · `RELEASES.json` 변경 0. 작업 트리 = 커밋. 그 뒤 커밋 `0c1dffe4f` 는 P4C01 설계 초안 문서 1개(코어 무접촉)입니다.
- 앞 점검 `isolation_review_v4.md` · 판단 T4 `20261113_0915_T4.md` · 철학 P1 `philosophy/20261113_0933_P1_P1S03.md` · 판단 T1 `20261113_0935_T1.md`(머리 · C-054 · N1 ~ N4).
- 현행 코드: `standing.R`(1 ~ 420 · 740 ~ 1160 · 1286 ~ 1627) · `p4.R`(1 ~ 500 · 690 ~ 1110 · 1160 ~ 1175 · 1720 ~ 1800) · `p1.R`(전부 앞부분) · `rules.R`(전부) · README v4 절.
- 코어 밖(규칙 · 코드만): `contracts/factor_db_vintage.R`(fdv_stale · fdv_measured_at) · `ops/rf_cell_worker.R:30-46` · `factor_db/fc_engine_gen.R` · `fc_combiner_gen.R`(decision 상수 · family_root · 본문 함수가 읽는 필드) · `ops/standing_board_run.sh` · `round.sh` 판 고르기.
- 규칙 기록: 등록부 P1 라운드 목록(P1S03 미등록 · v4 로 등록된 라운드 0) · `RELEASES.json` 구조(v1 ~ v3 status = released) · `factor_db_vintage.json` 항목 id · 완료 시각 · 범위 · 결정 기록부 FACTOR-SPINE-STAGE1-20261112(status · decision) · 판단 원장 구조(키 · 보류 요청 상태 개수만) · P1S03 초안 `round_spec.json`(core_version · report · track · pins) · 시드 칸 사양 selection_accounting · `tools/init_p1s03.R`(grep) · FC_* `own_spec.json` decision.

**계산 · 실행**
- 코어 매니페스트 재계산(pins.R 규칙 · CRLF): v1 `e70ac0af` · v2 `f7e5ce59` · v3 `4d00113a` = RELEASES · v4 = `a75d012374e1a836eb60885c007a98b6`(커밋 문구와 같음).
- 시험 1회: `cd 04_Research/strategies && R_ENVIRON_USER=<빈 파일> QM_ROOT=C:/Users/99922/OneDrive/Quant_Module_Moltbot Rscript ../../08_Tests/programs/test_round_core_v4.R` → **63 ok · 0 FAIL · 167초**. 전후 `git status`(06_Registry · 04_Research/programs · stage_artifacts/programs) 같음 · 등록부 · 판 표식 원장 · 결과 원장 · RELEASES md5 같음.
- 읽기 전용 탐침 5개(스크래치 폴더 · 등록부 쓰기 없음 · 값은 합성이거나 규칙 기록뿐):
  ① 실제 등록부 `rc_standing_source_cells` — unverified 0행 · 칸 수 P1R03 15 · P1R04 30(P1R01 · P1R02 = 0) · FC_* 30 전부 원천 = P1R03 + P1R04 · 칸 45 · remeasure TRUE · 계보 불일치 0.
  ② P1R03 `*_C0` 15 ↔ P1R04 `*_R0` 15 — 같은 엔진 md5 · 칸 사양 의미 서명(`.rcp4_spec_key`) 15/15 같음 · 판 표식 원장에 RAWDATA-SEAM-0330-REPAIR-20261113(완료 11-13 09:36:10 · 범위 all).
  ③ 합성 규칙 · 합성 판단 원장 · 임시 루트 영수증으로 관문 함수 직접 호출(아래 R-A · R-B · R-D).
  ④ 시드 n_family 대조(아래 M3). ⑤ family_root 의존(아래 R-F).

**정보 경계**
- `verdict.json` · `results/**/full/` · P1R03 `evaluation_visible.json` · `authoritative_remeasure.json` · finalize · selection_reality_check · 텔레그램 로그는 열지 않았습니다. 판 표식 판정(fdv_stale)은 권위 기록을 여는 함수라 실제 산출 폴더에는 돌리지 않았습니다.
- 철학 P1 · 판단 T1 리뷰 본문에 τ_D 이전 보는 창 요약 수치(β 범위 · t 범위)가 있어 눈에 들어왔습니다. 근거로 쓰지 않았습니다. 시험 · 탐침 출력에 성과 값은 없습니다.

---

## §1. 항목 표

| 항목 | 결과 | 근거(file:line · 재도출) |
|---|---|---|
| M1 시드 자체 사양 우회 | **해소** | 엔진 속성 판독 standing.R:372-380(갈래 own_spec ∨ 인계 origin ∨ 엔진 옆 own_spec.json) · 열 own_spec_engine · own_resolved · family_root :393 · 시드 인계 기록 :1056-1079(.rcs_own_handoff :858-865) · 풀 관문 p4.R:182-183 · :245-267 · 사슬 원천 시행 p4.R:942-955 · 기저 칸 논문 메타 p4.R:453 · 시험 S1(test:603) · C8(:757). 잔여 = 선택 S-d · S-e · 새 필수 M3(시드 회계) |
| M2 수용된 보류 요청 | **해소**(그 결함) · 새 권고 R-A | 갈래 ① closed = "withdrawn" p4.R:302 · 해제 = 상설 판 영수증 p4.R:351-356 · 쓰기 도우미 상설 판 허용 p4.R:383-390 · 시험 S2(test:614). 해제가 보류 요청과 묶이지 않음 → R-A |
| R1 +1 없음 조건 | **해소** | remeasure = 같은 md5 · variant · 같은 계보 standing.R:826 · 불일치 :827 → 입구 사유 :948 · enqueue 거부 :1018 · 시행 수 :1029-1037 · 시험 O3b(test:433) · O5(:450) |
| R3 선언 없음 | **부분** · 권고 R-C | 관문은 있음 standing.R:94 · :949-955 · 시험 O6. 그러나 두 생성기가 모든 산출에 resolved 결정 id 를 적는다 fc_engine_gen.R:41 · :357 · fc_combiner_gen.R:28 · :149(실제 30/30 = FACTOR-SPINE-STAGE1 · resolved) → 생성기 산출에는 늘 열림 |
| R4 원천 라운드 판독 틈 | **해소**(md5 핀 기준) | (i) 풀 = 원장 ∪ 지금 p4.R:251-254 · 시험 P7(:549) · (ii) unverified standing.R:779 · :781 · :787 · :802 → 사슬 거부 p4.R:950-954 · 시험 C8. 잔여 = 선택 S-b |
| R5 출시 전 v3 판독 | **해소** | standing.R:868-877 · :1291 — 갈래 lane 은 바로 통과(:869) · 실제 RELEASES(v1 ~ v3 released) = 거부 · v4 항목 = 통과(시험 S3 :620). P1S02 = v3 코드 · 등록 라운드(P1R04 등)는 판정 경로가 달라 무관 · 무인 실행기는 판마다 실패를 적고 다음 판으로 간다(standing_board_run.sh:109-130). 잔여 = 선택 S-d |
| R6 N5 채택 강제 | **해소** | p4_rules_v3 p4.R:53-56 · 방향 문턱(통과 1 요구) :709-711 · 검사 문구 :748-752 · 새 등록 = v3 만 :933-934 · 시험 C0b(:682) · C4 |
| R7 저위험 집합 | **해소** | RC_P4_LOWRISK_HOLD = defense · risk · regime · liquidity · crowding p4.R:93-95(정본 상수 하나) · README 9 같은 집합 · 시험 P6(:540) |
| S1 when 의존 | **해소** · 새 권고 R-B | 고정점 rules.R:143-149 · cols 판독 실패 = 시험 창 :136 · 시험 V4(:122). 규칙 '열'을 metric 으로 읽는 길은 안 닫힘 → R-B |
| S2 영수증 항목 손상 | **해소** | p4.R:336-338(그 엔진만 미해소) · 시험 P8(:559) |
| S3 닫기 원천 셈 | **해소** | .rcp4_src_expected p4.R:1035-1042 · 닫기 :1747-1748 · finalize source_trials_count :1789-1790 · 시험 C6(:731) |
| S6 생성기 자동 핀 | **해소** | standing.R:1537-1538 · 시험 I1(:173). 잔여 = 선택 S-g |
| C-035 ② 다시 만든 엔진 | **해소** · 권고 R-F | .rcs_own_source 엔진 md5 ∪ 계보 standing.R:816-828 — 입구 :947 · enqueue :1017 · 자격 표 :379 · 풀 p4.R:253 · 사슬 p4.R:948 이 같은 함수 · 시험 O3b. 계보 열쇠가 사양 md5 보호 밖 → R-F |
| C-036 시행 수 = 원천 칸 수 | **부분** · 필수 M3 | enqueue standing.R:1029-1032 → 실제 30 = max(2, 45) = 45(탐침 ①). 시드(자체 사양 행)는 칸 사양 값 그대로(:1065 · :1072-1073) — P1S03 FVALU 시드 = 2 · standing-check 기준도 옛 규칙(:1600-1605) |
| C-037 저위험 키 · 표기 | **부분** · 권고 R-D | (가) 집합 p4.R:93 · (다) label_class :259-260 · :273 · chain_registered :962-963 · 영수증 lowrisk_tag :339 · :397-398 · :407 · 시험 P6. 꼬리표는 영수증에만 → R-D · 닫기 기록 승계 없음(S-f) · 해제 id 내용 미검사(R2 · README 알려진 한계 2) |
| C-046 통과 보고 판정 줄 | **해소** | 판정 줄 = IS t(α) · IS 상승 포착률만 standing.R:1403 · :1415 · 보고 열 + 고정 문구 :1404-1405 · :1416 · :58 · OOS 줄 따로 :1406 · :1417 · 시험 S4(:627). '일 요약 통과 엔진 P2 한 줄'은 없음(S-f) |
| C-048 같은 계보 | **부분** | 풀 family_root 열 p4.R:273 · 블렌드 걸음 꼬리표 :1086-1089 · :1094-1108 · :1172 · 시험 P9(:563). rx_validate · 닫기 결론에는 안 실림(S-f) |
| C-049 철학 줄 소실 | **부분** · 새 권고 R-E | 상수 p1.R:10-15 · rc_init_p1 :118 · rc_init_standing_p1 standing.R:1535 · 시험 I1. 줄 1 · 2 는 FC 엔진 문장인데 레인 판 · 모든 P1 라운드에 들어감 → R-E · 원천 라운드 결론 범위 대조 경고 없음(S-f) |
| C-054 원천 시행 판 표식 | **해소** | 칸마다 판 표식 p4.R:990-999 · 갈음 = 같은 엔진 md5 · 같은 칸 사양 서명 · 현재 판 확인(stale FALSE)만 :1015-1032 · 없으면 missing ':stale' 거부 :995 · 수리 id 기록 :136 · :997 · 원장 줄 있음(탐침 ②) · 실제 15쌍 서명 같음 · 시험 C7(:743). 잔여 = 선택 S-a |
| C-058 통과 보고 단위 | **해소** | RC_STANDING_REPORT_PASS standing.R:56 · 사양 검사 :188-190 · 보고 :1389-1396 · :1421-1446 · 인자 :1516 · :1529 · 시험 S5(:638) |
| (점검 요청) n_family 45 | 의도와 같음 · 시드 예외 | 30/30 원천 = P1R03 15 + P1R04 30(탐침 ①) = C-036 (가) · C-038 (가)의 사슬 원천 시행 집합과 같은 크기. 판 표식 갈음 뒤 닫기의 고유 경로는 30(기록 45 · README 9 S3 ③ 의도 · finalize 에 기록 수 · 고유 수 · 손상 수를 남김). 시드는 2 → M3 |
| (점검 요청) v1 ~ v3 · RELEASES · 레인 동작 | **변화 없음** | diff 0 · 매니페스트 = RELEASES · 시험 A1 · O4(실제 RP_AUTO_* 52 = v3 표) · P4(레인 행 = v3 · 레인 풀 md5 = v3) · C3. v4 레인 판의 의도된 변화 = 보고 문구 · 결론 범위 기본 줄 · 새 사슬 p4_rules_v3(README 9) |

---

## §2. 지적

### 필수

#### M3. 자체 사양 시드의 n_family 가 C-036 새 규칙을 따르지 않습니다 — P1S03 FVALU 시드 = 2, 같은 엔진 스캔 행이면 45

- **근거**
  - 새 규칙은 `rc_standing_enqueue` 에만 있습니다(standing.R:1029-1032 · max(계보 최댓값, 원천 칸 수)). 시드는 칸 사양의 n_family 를 그대로 원장에 적습니다(standing.R:1065 · :1072-1073).
  - P1S03 초안 시드 `specs/P1S03_FVALU_RX0.json` 의 n_family_at_registration = **2** 입니다. 초안 도구가 `rc_standing_nf_prior` 로 정합니다(`tools/init_p1s03.R:13`).
  - standing-check 의 시드 대조 기준도 `rc_standing_nf_prior` 입니다(standing.R:1600-1605). 탐침: nf_prior(FC:value) = 2 · 새 규칙 값 = 45 · 시드 엔진 md5 의 원천 = P1R03 + P1R04. 그래서 검사는 2 를 "같음"으로 통과시킵니다.
  - 스캔은 같은 md5 를 duplicate 로 뺍니다(standing.R:998-999). FVALU 의 P1S03 항목은 시드 하나뿐입니다.
  - 셀 워커는 n_family_at_registration 을 그대로 DSR 의 N(n_trials_cumulative)으로 씁니다(rf_cell_worker.R:39-46).
- **왜**
  - C-036 수용 문구는 "자체 사양 행 n_family = 원천 칸 수"입니다. M1 수리로 시드도 자체 사양 행(own_spec_engine TRUE)이 됐는데, 그 행만 N = 2 입니다.
  - 그래서 T4 C2 가 짚은 "종전 DSR(N = 2)로 단독 A" 길이 FVALU(이 판의 양성 대조 · 사슬 1호 기저 1순위)에 그대로 남습니다. C2 의 반증 조건("P1S03 자체 사양 행의 n_trials_cumulative ≥ 원천 라운드 칸 수")도 시드 행에서 충족되지 않습니다.
  - 코어 검사가 옛 값을 보증하므로, P1S03 v2 를 같은 도구로 다시 만들어도 2 가 나옵니다.
- **고치는 법**
  - 코어에 자체 사양 회계 함수 하나를 둡니다(예: `rc_standing_own_nf(engine, fam)` = max(rc_standing_nf_prior, `.rcs_own_source` 칸 수) · remeasure 가 아니면 +1). enqueue · 시드 만들기 · standing-check 가 같은 함수를 씁니다.
  - `rc_standing_validate` 에서 자체 사양 시드(갈래 own_spec 또는 엔진 옆 own_spec.json)의 n_family_at_registration 이 그 값보다 작으면 거부합니다.
  - P1S03 v2 시드 사양은 45 로 다시 만듭니다. 시험 1건(시드 2 = 거부 · 45 = 통과).

### 권고

#### R-A (M2 잔여). 상설 판 영수증의 해제가 보류 요청과 묶이지 않습니다 — 앞서 쓴(또는 다른 리뷰를 근거로 한) 영수증이 뒤의 보류 요청을 조용히 풉니다
- **근거**: p4.R:354-355 `hold = (a$hold && !s_ok) || …` · s_ok = 영수증의 그 엔진 hold = false ∧ 영수증이 가리킨 리뷰에 보류 없음(기본 닫힘 집합 · p4.R:283 · :342). 영수증 p2_review_id 가 보류 요청을 낸 리뷰인지, 영수증 written_at 이 보류 요청 at 보다 뒤인지 보지 않습니다. 영수증은 판 하나에 파일 하나이고 쓸 때마다 통째로 바뀝니다(p4.R:407-412). 그래서 다른 엔진을 풀 때 앞 엔진의 hold = false 를 다시 적게 됩니다.
- **탐침**(합성 원장 · 임시 루트): 영수증(R-A 근거 · 11-14) + 뒤 리뷰 R-B 의 accepted 보류 요청(11-15) → state **ok**. 갈래 ① = R-B 만이어도 ok. 영수증을 지우면 hold(대조).
- **왜**: M2 의 뜻(보류의 결정은 도훈 · 수용만으로 풀리지 않는다)이 해제 쪽에서 다시 느슨해집니다. 저위험 해제는 결정 기록부 resolved id 를 요구하는데(p4.R:421-427), 철학 보류 해제는 기계 근거를 요구하지 않습니다. README 알려진 한계 2 는 "결정 id 를 기계로 요구하지 않는다"만 적고, "시점이 앞선 영수증"은 적지 않았습니다.
- **고치는 법**: 갈래 ① 보류 요청(withdrawn 아님)이 있는 엔진은 상설 판 영수증 항목이 (가) written_at ≥ 그 보류 요청의 at 이고 (나) release_decision(결정 기록부 resolved) 또는 released_holds = [도전 id] 를 가질 때만 풉니다. 시험: 앞선 영수증 + 뒤 보류 = hold · 뒤 영수증 + 결정 id = 해소.

#### R-B (S1 인접). 시험 창 규칙의 '열'을 metric 으로 읽는 판정 규칙을 두 검사가 모두 못 잡습니다
- **근거**: `rc_rules_test_ids`(rules.R:131-151) · `rc_rules_test_window_use`(p1.R:20-33)는 metric · cols 이름의 `_test$` 와 report 의 when 만 따라갑니다. 앞 규칙의 열(test_hold 같은 규칙 id)은 `rc_rules_apply` 가 판정 표에 붙이므로(rules.R:113-121) 뒤 규칙이 `metric = "test_hold"` 로 읽을 수 있습니다.
- **탐침**(합성 규칙): q_leak(threshold · metric = test_hold) · qualify(all_of 안 metric = test_hold) → `rc_rules_validate` 통과 · `rc_rules_test_window_use` = 빈 값 · `rc_rules_test_ids` = test_hold 만. 시험 창 부호만 다른 두 칸의 qualify = TRUE / FALSE. 보는 창 표에 q_leak · qualify 열이 남습니다.
- **왜**: τ_D 경계(판정 규칙은 보는 창 정보만)의 기계 검사가 우회됩니다. S1 수리는 when 의존만 닫았습니다. 지금 P1 템플릿에는 그런 규칙이 없습니다(잠복 · 손으로 고친 사양에서 열림).
- **고치는 법**: 두 함수가 같은 고정점을 씁니다 — 집합 = {`_test$` 열을 읽는 규칙} ∪ {집합 안 규칙 id 를 metric · cols · when 으로 읽는 규칙}. `rc_rules_test_window_use` 는 그 집합(최상위 report 제외)이 판정 규칙에 닿으면 거부합니다. 시험 1건.

#### R-C (R3 잔여). 선언 관문은 생성기 산출에 늘 열립니다 — 상설 형제 칸은 사슬 원천 시행에도 없습니다
- **근거**: 선언 ② = own_spec decision 이 결정 기록부 resolved(standing.R:952-953). 두 생성기는 모든 산출에 같은 결정 id 를 적습니다(fc_engine_gen.R:41 · :357 · fc_combiner_gen.R:28 · :149 — FACTOR-SPINE-STAGE1-20261112 · resolved · 실제 30/30). 같은 계보 상설 형제 칸은 원천 시행에 들지 않습니다(README 알려진 한계 5 · p4.R:975-1004 = 등록 라운드 사전등록 칸만).
- **왜**: 앞 점검 R3 의 걱정(생성기로 싸게 많이 만들어 상설 판에서 거르면 그 선택이 재채점 시행 집합에 남지 않는다)이 그대로입니다. README 는 두 한계를 따로 적었지만, 합치면 이 길이 열립니다. 지금 30 개는 원천 md5 라운드로 선언돼 영향이 없습니다.
- **고치는 법**: (가) 결정 항목에 기계 판독 범위(엔진 md5 목록 또는 개수 상한)를 두고 선언 ② 는 그 안일 때만 인정, 또는 (나) 생성기가 엔진마다 등록부 선언 줄(kind own_spec · md5)을 남기게, 그리고 (다) 같은 계보 상설 형제 칸(판정된 것)을 사슬 원천 시행에 넣습니다.

#### R-D (C-037 잔여). lowrisk_tag 는 영수증에만 있어, 영수증 없이 갈래 ① 로 해소되면 꼬리표 카테고리는 관문 없이 듭니다
- **근거**: 꼬리표 = 확인된 영수증 항목뿐(p4.R:359-361). 풀 관문 = 가족 ∩ 집합 ∨ 꼬리표(p4.R:258-259). 갈래 ① 확인만으로 state ok(p4.R:356). 쓰기 도우미는 범위 안 엔진의 release_decision 없는 hold = false 를 거부하지 않습니다(p4.R:392-407 · T4 C3 (나) 뒷부분).
- **탐침**: 영수증 없음 + 갈래 ① 확인 → state ok · lowrisk_tag FALSE · releases 0.
- **왜**: P1R04 결론 범위 [29] 의 "사이드카 저위험 쏠림 꼬리표 카테고리(조건 없이)" 확인이 세션이 영수증을 쓰는 데 기댑니다. 지금은 기술적(ITECH)처럼 가족 집합 밖의 꼬리표 카테고리가 해당합니다.
- **고치는 법**: 사이드카 출력(원천 라운드 results/ 의 기계 파일 · 성과 무참조)을 풀이 읽어 같은 사유로 겁니다. 또는 꼬리표 파일이 있는 원천 라운드는 그 라운드 영수증(갈래 ②)을 필수로 둡니다.

#### R-E (C-049 새 결함). P1 표준 철학 줄 1 · 2 는 FC 엔진 문장인데, 레인 판과 모든 rc_init_p1 라운드에 기본으로 들어갑니다
- **근거**: p1.R:11("추첨 행운 해당 없음(결정론 엔진)") · :12("구성원 점수는 값이 있는 것의 평균") · p1.R:118 · standing.R:1535(갈래 무관). 시험 I1 은 레인 판에도 같은 네 줄을 기대합니다(test:173-176). 근거 도전(C-20261112-020 · 025)은 P1R03 · P1R04(FC 엔진) 결론 범위에서 왔습니다.
- **왜**: 레인 엔진(ML 논문 재현 — 학습 난수 있음 · 구성원 평균 아님)의 사전등록 결론 범위에 사실이 아닌 문장이 "지우려면 사유"로 박힙니다. 철학 감독이 실패 형태 표의 추첨 행운(시드 띠)을 이 줄로 "해당 없음" 처리할 수 있습니다.
- **고치는 법**: 줄 3 · 4 만 공통으로 두고, 줄 1 · 2 는 갈래 own_spec(엔진 = 생성기 산출)에서만 넣습니다. I1 기대도 갈래별로 나눕니다.

#### R-F (C-035 ② 잔여). 계보 열쇠 family_root 가 사양 md5 보호 밖입니다 — 다시 만든 엔진은 family_root 가 바뀌면 계보 원천 시행이 조용히 빠집니다
- **근거**: family_root 는 own_spec 최상위 키입니다(core 밖 · `.rcs_own_core_md5` 대상 아님 · standing.R:879 · :908-909). 생성기 본문 함수도 쓰지 않습니다(fce_engine_text · fcc_engine_text 가 읽는 것 = core · spec_id · declared_at · engine · supersedes_engine_md5). 원천 md5 칸이 없는 엔진에는 불일치 검사(standing.R:948)도 걸리지 않습니다.
- **탐침**: 새 md5 · FC:value → 원천 P1R03 + P1R04 · 45칸 / 새 md5 · FC:value_v2 → 원천 없음 · 0칸 · 불일치 0 · 검증 불가 0. 사슬 등록은 원천 없음으로 그대로 통과합니다.
- **왜**: C-035 ②(다시 만든 엔진도 앞선 계보 시행을 물려받는다)의 fail-closed 가 생성기 개정(이름 규칙 변경)이나 손 편집 한 번으로 깨집니다.
- **고치는 법**: 입구가 family_root 를 core 에서 다시 유도해 대조합니다(가족 하나 = "FC:<가족>" · 전체 = "FC:total" — fc_engine_gen.R:348 · fc_combiner_gen.R:140 과 같은 규칙). 또는 family_root 를 spec_md5 에 넣습니다. supersedes_engine_md5 가 가리키는 앞 엔진의 원천 라운드를 계보에 더하면 이름이 바뀌어도 이어집니다.

### 선택

- **S-a (C-054 잔여)** 판 표식 판정 불가(na) 원천 칸은 갈음도 거부도 없이 남습니다(p4.R:991 · :973 주석 "기저 풀과 같이"). 사슬 시행 집합은 닫기 재채점(A 관문) 입력이라 기저 풀 진단 열과 목적이 다릅니다. na = 거부가 맞습니다(셀 워커 산출은 실행 id 가 있어 실제로는 드뭅니다).
- **S-b (R4 잔여)** 검증 불가 판독이 엔진 md5 로만 걸립니다(standing.R:787 · :802 · :824). 계보로 든 라운드나 원장 source_rounds 에만 있는 라운드가 사전등록 md5 ≠ 등록부가 돼도 사슬 등록은 거부하지 않습니다(p4.R:949-951 — enqueue 는 거부한다 standing.R:1021-1022). 등록부에 prereg 경로가 없는 라운드는 조용히 건너뜁니다(standing.R:777). 고침: 사슬 등록에서 rids ⊄ attr(now, "rounds") 면 거부 · prereg 경로 없음 = "*".
- **S-c** 블렌드 부품(자체 사양 엔진)의 원천 시행은 닫기 시행 집합에 들지 않습니다(p4.R:1747-1748 = 기저 source_trials 만). 지금 FC 30 은 원천 라운드가 같아 영향이 없습니다. 원천이 다른 부품을 섞는 사슬부터 생깁니다.
- **S-d (R5 잔여)** 판정 출시 관문은 판 갈래로만 겁니다(standing.R:869). 자체 사양 엔진을 시드로 둔 레인 판은 출시 전에도 판정합니다(README 알려진 한계 1 이 적음). 항목의 own_spec_engine 으로 걸면 닫힙니다.
- **S-e** 시드는 입구 검사(계보 불일치 R1 · 선언 R3)를 지나지 않습니다. `.rcs_own_handoff`(standing.R:858-865)가 o$mismatch 를 버립니다. 시드 칸 사양 family_root ≠ own_spec family_root 를 알리지 않습니다.
- **S-f** 일부만 실린 수리: C-048 꼬리표는 걸음 원장에만(p4.R:1172 — rx_validate · 닫기 결론 없음) · C-037 label_class 는 풀 · chain_registered 에만(닫기 기록 없음) · C-046 "일 요약 통과 엔진 P2 한 줄" 없음 · C-049 "원천 라운드 결론 범위 철학 줄 대조 경고(standing-check)" 없음.
- **S-g (S6 잔여)** 생성기 자동 핀은 `rc_init_standing_p1` 만 넣습니다(standing.R:1537-1538). `rc_standing_validate` 는 갈래 own_spec 에서 scan.generators ⊂ pins.files 를 요구하지 않습니다(손 사양 · pins 를 통째 바꾸는 사양 — init_p1s03.R:61 은 통째 바꾸지만 생성기를 넣습니다).

---

## §3. 확인하지 못한 것

- 실제 P1R03 · P1R04 산출 폴더의 판 표식 값 — `fdv_stale` 이 권위 기록을 열어 돌리지 않았습니다. 갈음이 실제로 일어나는지(P1R04 R0 가 이음매 수리 완료 11-13 09:36:10 뒤 측정인지)는 사슬 등록 때 기계가 판정합니다(없으면 거부 — fail-closed).
- 시드(reference) 칸의 A 띠가 A 자격 관문(`rf_a_eligibility`)에서 보류되는지 — 셀 워커 N 경로까지만 읽었습니다(M3 의 실제 위험 크기).
- `sr_regrade` 의 기대 id(폴더 이름) 변별력 · 실제 재채점 동작.
- C15 스캐너 · `superfan_watch.py` · `ops/chain_tick.sh` 와의 상호작용.
- `rx_round.R`(rx_validate)는 코어 밖이라 C-048 꼬리표 여부만 grep 으로 봤습니다.
- 생성기 재생성 결정성 · 가중 단정 실행(W)은 시험 결과에 기댔습니다.
