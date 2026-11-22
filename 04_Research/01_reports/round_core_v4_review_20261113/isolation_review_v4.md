# round_core v4 격리 교차 점검 (isolation review · v3 → v4)

- 점검자: 격리 교차 점검자(isolated — 이 변경의 설계 · 구현에 참여하지 않았습니다)
- 대상: 커밋 `25b5193d0`(부모 `e7d2fcf40`) — `04_Research/programs/_lib/round_core/v4/` 20파일 · README v4 절 · `08_Tests/programs/test_round_core_v4.R`
- 점검 시각: 2026-11-13 09:00 ~ 09:35 KST
- **판정: revise**
- **건수: 필수 2 · 권고 8 · 선택 6**

---

## §0. 열어 본 것 · 돌린 것

**코드 · 문서**
- `git show --stat / --name-status 25b5193d0` — 바뀐 파일은 README · v4 20파일 · 시험 1개뿐입니다(v1 · v2 · v3 · RELEASES.json 없음). 작업 트리도 깨끗합니다.
- `diff -r v3 v4` — 머리말 · 판 표기 · 고정 경로만 다른 파일 15개, 실제 변경은 `driver.R` · `rules.R` · `fingerprint.sh` · `standing.R` · `p4.R`(+ `util.R` RC_VERSION · `load.R` · `measure_cell.R` 경로).
- v4 전문 또는 해당 구간: `standing.R`(전부) · `p4.R`(기저 풀 · 철학 관문 · 영수증 쓰기 · 사슬 등록 · 원천 시행 · 걸음 판정 · 닫기 · 설계 입력) · `driver.R` · `rules.R` · `p1.R` · `pins.R` · `load.R` · `util.R` 앞부분 · `fingerprint.sh`. README v4 절. 시험 파일 전부.
- 규칙 쪽 기록(성과 값 없음): 등록부 P1 라운드 목록 · P1R03/P1R04 사전등록 구조(칸 역할 · 핀 개수)와 칸 사양의 `selection_accounting.family_root` · `base_signal.path` · FC_* `own_spec.json` 구조(키 · family_root · core.families · generator) · P1R03 `round_spec.json` conclusion_scope(키워드 줄) · **P1S03 초안**(`round_spec.json` 구조 · 시드 칸 사양 · `DESIGN.md` 키워드 줄) · 판단 원장(리뷰 · 도전 구조, C-20261112-021/023/026 · C-20261113-002/011/017, 보류 요청 상태 개수) · 결정 기록부(FACTOR-SPINE-STAGE1 · LOWBETA-ENGINES-BASE-USE-20261113 · CHARTER-GAP-LOWBETA-DEFENSE-LABEL-20261113) · `superfan_protocol.md` §5 · §11 · `q_judgment_ledger.py` 상태 정의 · `factor_spine_design_20261111/README.md` §3-6 · 두 생성기의 최상위 문장 · `daily_refresh.sh` [6e].

**계산 · 실행**
- 코어 매니페스트를 `rc_core_manifest` 와 같은 규칙(CRLF)으로 다시 계산했습니다: v1 · v2 · v3 = RELEASES 값과 같음 · v4 = `320611fa0e08dc70e3db51e9e502dcaa`(커밋 문구와 같음).
- 시험 1회: `cd 04_Research/strategies && R_ENVIRON_USER=<빈 파일> QM_ROOT=C:/Users/99922/OneDrive/Quant_Module_Moltbot Rscript ../../08_Tests/programs/test_round_core_v4.R` → **46 ok · 0 FAIL · 282초**(빌더 기록 206초). 실행 전후 관련 경로 git status 같음 · `.cache/round_core/perf` · `state` 무접촉.

**정보 경계**
- `verdict.json` · `results/**/full/` · `authoritative_remeasure.json` · `selection_reality_check.json` · `finalize.json` · 텔레그램 로그 · 측정 기록 `results/<code>.json` 은 열지 않았습니다.
- P1R03 `evaluation_visible.json` 은 `"test_hold"` 키가 있는지만 grep 개수로 봤습니다(값은 보지 않음).
- 결정 기록부 LOWBETA · CHARTER-GAP 항목의 recommendation 문구에 요약 수치(β 범위 · 최대낙폭 배수)가 들어 있어 눈에 들어왔습니다. 시점은 확인하지 않았고, 이 점검의 근거로 쓰지 않았습니다.

---

## §1. 항목 표

| # | 항목 | 결과 | 근거(file:line) |
|---|---|---|---|
| 1 | 보는 창 누출 수리(`_test$` + 시험 창 규칙 열) | **통과**(P1 템플릿) · 선택 S1 | driver.R:91 · rules.R:129-149 · p1.R:5-6 · :93-99 · 시험 V1-V3 |
| 2 | 자체 사양 입구(기본값 · 사양 검사 · `.rcs_scan_own_dir` · 원천 칸 · 새 사유 · enqueue 시행 수) | **부분** — 필수 M1 · 권고 R1 · R3 | standing.R:57-61 · :146-172 · :739-856 · :878-896 · :970-985 · 시험 O1-O3 · W1-W3 |
| 3 | 입구 갈래(판 번호 · 옛 판 받기 정지 · editions · 원장 머리 · 두 갈래 자격) | **통과** · 선택 S5 | standing.R:110-113 · :148-152 · :233 · :284-289 · :295-308 · :376-385 · 시험 T0-T4 · Q1-Q3 |
| 4 | 기저 풀 관문(philosophy_unread · philosophy_hold · lowrisk_confirm_pending · 영수증 쓰기) | **부분** — 필수 M1 · M2 · 권고 R2 · R4 · R7 | p4.R:158-246 · :250-371 · 시험 P0-P5 |
| 5 | 사슬 원천 시행(등록 거부 · source_trials · 닫기 시행 집합 · 기대 수 · 기대 id) | **부분** — 필수 M1(시드 기저면 통째로 건너뜀) · 권고 R4 · 선택 S3 | p4.R:876-894 · :900-924 · :1602-1607 · :1648 · 시험 C0-C2 · C5 |
| 6 | N5 β 비대칭에 blend | **통과**(값 계산) · 권고 R6(채택 강제 없음) | p4.R:58 · :1290 · :47-48 · :688 · 시험 C4 |
| 7 | 지문에 `.cache/factor_combinable` | **통과** | fingerprint.sh:20-21(LF · d 함수 같은 형식) · 시험 F1 · daily_refresh.sh:975-985(야간 빌드는 리프레시 잠금 안) |
| a | v1 · v2 · v3 · RELEASES.json 무변경 | **통과** | name-status · 매니페스트 재계산 = RELEASES · 시험 A1 |
| b | v4 안에 v3 경로 | **통과** | `round_core/v[123]` grep 0 · load.R:14-15 · driver.R:117 · standing.R:1399 · measure_cell.R:6 |
| c | 누출 수리 범위 · p2/p3 보는 창 | **통과** | P1 표 열 = RC_P1_COLS + 최상위 규칙 열(rules.R:113-121) → `*_test` 4열 + test_hold 제거 · p2.R:1327 · p3.R:374 `writes_visible = TRUE` 라 driver 분기 밖 · p2/p3 본문은 머리말만 다름 |
| d | 원천 시행 — 조용한 누락 · 이중 셈 | **부분** — 필수 M1 · 권고 R4 · 선택 S3 | 아래 §2 |
| e | 같은 갈래 옛 판 판정이 새 판을 덮는가 | **통과** | standing.R:376(`by = .(.grp, track)` 최대 판만) · :288(같은 갈래 더 높은 판만 정지) |
| f | 영수증 없음 · 손상 = 닫힘 | **부분** — 필수 M2 · 선택 S2 | p4.R:259 · :287-304 · :164-165(원장 · 기록부 판독 불가 = 닫힘은 맞음) |
| g | 범위 밖 동작 변화(복사 코드) | **통과** — 찾은 것은 모두 README 에 적힌 의도 변경 | 레인 입구 orientation_layer 거부(standing.R:169-171) · 레인 사양 `track: lane`(:1339) · 원장 머리 track(:233) · 지문 줄은 모든 v4 측정에 적용 · blend N5 는 레인 기저 사슬에도 적용 · 규칙 문서 문구. 레인 경로 v3 동등 = 시험 O4(RP_AUTO 51개) · P4 · Q2 · C3 |

---

## §2. 지적

### 필수

#### M1. 시드로 들어온 자체 사양 엔진은 v4 관문과 원천 시행을 모두 건너뜁니다 — 지금 P1S03 초안이 바로 이 경우입니다

- **근거**
  - v4 관문과 원천 시행은 `origin == "own_spec"` 일 때만 켜집니다: 기저 풀 p4.R:225 · 사슬 등록 p4.R:876.
  - origin 은 standing.R:353 에서 정합니다. `source = "seed"` 면 무조건 `"seed"` 입니다. 시드 넣기(standing.R:908-925)는 handoff 를 적지 않아서 families · source_rounds · own_spec 도 NA 입니다(standing.R:364-367).
  - 스캔은 시드를 먼저 넣고(standing.R:970) 스캔 행을 나중에 넣습니다. 같은 엔진 md5 는 `duplicate` 로 빠집니다(standing.R:870-871).
  - P1S03 초안(`04_Research/programs/P1_RETURN/P1S03_own_spec_qualification` · core_version v4 · track own_spec)의 시드 `P1S03_FVALU_RX0` 는 FC_FAM_value 재측정입니다(`specs/P1S03_FVALU_RX0.json` · remeasure_of P1R03_FVALU_C0). `DESIGN.md:19` 도 "첫 scan 에서 FC_FAM_value 는 duplicate 로 빠진다"고 적습니다. 그래서 FC_FAM_value 의 상설 판정은 시드 항목 하나뿐이고, 그 행의 origin 은 seed 입니다.
  - 그런데 `DESIGN.md:30` · `:41` 은 이 통과 칸에 philosophy_unread · philosophy_hold 와 "사슬 등록 때 원천 라운드 전 칸"이 걸린다고 적습니다. 코드는 걸지 않습니다.
  - 시험은 시드를 공유 측정(P0R01 E2 · 엔진 경로 없음)으로만 둡니다(test_round_core_v4.R:137). 사양 있는 자체 사양 시드는 시험 밖입니다.
- **왜**
  - FC_FAM_value 는 이 판의 양성 대조이고 블렌딩 사슬 1호의 유력한 기저 · 부품입니다(`DESIGN.md:8` · `:13`).
  - 시드가 통과하면 철학 P2 판독 없이 기저 풀 자격을 얻습니다. 블렌딩 부품 검사(p4.R:963)도 풀 자격만 보므로 부품으로도 바로 쓰입니다.
  - 그 기저로 사슬을 등록하면 P1R03 15칸 + P1R04 30칸이 재채점 시행 집합에 들어가지 않습니다. P1R03 결론 범위 6 · C-20261112-026(수용)이 막으라고 한 선택 편의가 그대로 남습니다(fail-open). 저위험 가족 시드였다면 lowrisk_confirm_pending 도 건너뜁니다.
- **고치는 법**
  - 자체 사양 여부를 handoff origin 이 아니라 "원장 갈래 = own_spec" 또는 "엔진 폴더에 own_spec.json 있음"으로 정합니다. `rc_standing_qualified` 에 이 판정 열을 따로 두고(seed 표기는 그대로), p4.R:225 · :876 이 그 열을 쓰게 합니다.
  - 자체 사양으로 판정된 행은 families(own_spec core.families) · source_rounds(`rc_standing_source_cells` 와 같은 md5 대조)를 그 자리에서 채웁니다. 못 채우면 기저 풀에서 뺍니다(fail-closed).
  - 또는 자체 사양 판의 `.rcs_enqueue_seeds` 가 스캔 행과 같은 handoff(origin own_spec · families · source_rounds · own_spec md5)를 함께 적게 합니다.
  - 시험에 양방향을 더합니다: 사양 있는 자체 사양 시드가 통과 → 기저 풀 철학 관문이 걸림 · 사슬 등록 때 source_trials 수집 / 레인 판 시드는 지금과 같음.

#### M2. 수용(accepted)된 철학 보류 요청은 갈래 ①(상설 pass 기록)에서 보류가 아니게 됩니다

- **근거**
  - `.rcp4_p2_review` 는 보류 요청 가운데 상태가 accepted · withdrawn · escalated · settled 인 것을 "열린 보류"에서 뺍니다(p4.R:259).
  - 판단 원장 도구의 상태 정의: 열림 = open · rebutted · countered / 닫힘 = accepted · disagreement · withdrawn · escalated · closed_note(`02_Infrastructure/programs/q_judgment_ledger.py:58-59`). 규약 §5 는 "수용 → 닫힘(accepted)"(superfan_protocol.md:81), §11 은 "보류 요청의 결정은 도훈"(superfan_protocol.md:162)입니다.
  - 실제 판단 원장의 보류 요청 6건은 모두 accepted 입니다(상태 개수만 셌습니다). Q 가 보류 요청에 응답하는 보통 길이 수용이라는 뜻입니다.
  - 시험 P2 는 보류 상태를 rebutted 로만 둡니다(test_round_core_v4.R:417).
- **왜**
  - philosophy_hold 의 뜻은 "도훈 확인 대기"입니다(p4.R:76). 수용 = Q 가 보류에 동의하고 도훈 결정을 기다리는 상태인데, 코드는 그 순간 보류를 풉니다.
  - 갈래 ①에는 엔진 단위 hold 표기가 없어서 다른 막는 길도 없습니다. P1S03 통과 엔진(갈래 ①이 주 경로)에 철학 P2 가 보류를 걸면, Q 가 수용하는 즉시 기저 풀 자격이 열립니다(fail-open). 실무 흐름에서 이 관문은 거의 발화하지 않습니다.
- **고치는 법**
  - 기저 풀 판독에서 갈래 ① 리뷰의 보류 요청은 withdrawn 이 아니면 보류로 봅니다.
  - 푸는 길은 엔진 단위 영수증으로 둡니다. `rc_philosophy_receipt_write` 가 상설 판 디렉터리에도(엔진 = 그 판 원장 항목) 쓸 수 있게 하고, `.rcp4_philosophy_state` 가 상설 판 자기 영수증도 읽게 합니다(hold = false · 필요하면 release_decision resolved).
  - 갈래 ②는 지금처럼 영수증 엔진 항목을 정본으로 둡니다(Q 가 수용한 보류를 엔진 hold 로 적음). 리뷰 단위 accepted 보류로 모든 엔진을 막지는 않게 합니다(P1R03 리뷰 R-20261113-002 에도 accepted 보류가 있습니다).
  - 시험: 보류 요청 accepted · 영수증 없음 = philosophy_hold / 같은 엔진 영수증 hold false = 해소.

### 권고

#### R1. 시행 수 "+1 없음" 조건이 주장보다 넓습니다
- **근거**: standing.R:884 의 조건은 `own && length(srcr) && nf0 >= 1L` 입니다. srcr 는 같은 엔진 md5 를 칸으로 등록한 P1 라운드(standing.R:832), nf0 는 모든 사전등록 · 상설 원장의 계보 최댓값입니다(standing.R:420-441). 원천 라운드가 "그 계보로, 변형(variant)으로" 회계했는지는 보지 않습니다. `rc_standing_source_cells` 가 family_root · n_family 를 돌려주지만 쓰지 않습니다(standing.R:757-759). family_root 는 own_spec 최상위 키라 core md5(spec_md5) 보호 밖입니다.
- **지금 자료**: P1R03 · P1R04 칸 45개의 family_root 는 own_spec family_root 와 모두 같습니다(불일치 0). 그래서 지금 결과는 같습니다.
- **왜**: 원천 라운드가 다른 계보로 회계했거나 reference(무가산)로만 등록했는데, 같은 계보에 다른 엔진 회계가 있으면 +1 이 빠집니다(과소 회계).
- **고치는 법**: srcr 를 "원천 칸 role = variant ∧ family_root = 이 엔진 own_spec family_root"인 라운드로 좁힙니다. 원천 칸 family_root ≠ own_spec family_root 면 입구 사유(예: own_spec_family_mismatch)로 뺍니다.

#### R2. release_decision 은 "결정 기록부 resolved"만 봅니다
- **근거**: p4.R:360-363 · :365-371 · 쓰기 p4.R:349. 결정 내용(허용 · 보류 유지 · 제외)과 대상 엔진은 보지 않습니다.
- **왜**: "보류 유지"로 resolved 된 결정 id 나, 다른 엔진(예: T1 판)에 관한 결정 id 를 적어도 풀립니다. 엔진 단위 해제(LOWBETA 정정 지시)를 기계가 지키지 못하고, 영수증을 쓰는 쪽의 정확성에 기댑니다.
- **고치는 법**: 결정 항목에 기계 판독 필드(예: `releases = [엔진 경로 …]` 또는 `effect = release` + 범위)를 두고, reader · writer 가 "그 엔진 ∈ 범위 ∧ 효과 = 해제"를 확인합니다. 필드가 없는 결정은 해제로 세지 않습니다. 당장은 RELEASES known_limits 에 적습니다.

#### R3. 설계 §3-6 (a)의 `own_spec_undeclared` 가 빠졌고, 뺀 이유가 기록되지 않았습니다
- **근거**: `factor_spine_design_20261111/README.md:193`(선언 기록 = 등록부 인계 줄 · origin own_spec · 엔진 md5 · 선언 시각). v4 사유 목록(standing.R:63-83)과 README v4 절에 없습니다. 입구는 FC_* 폴더의 자기 정합(사양 md5 · 생성기 md5 · 재생성)만 봅니다(standing.R:788-846). declared_at 도 core 밖입니다.
- **왜**: 생성기로 만든 FC_* 폴더는 선언 없이 모두 상설 판으로 흐릅니다. 생성기는 변형을 싸게 많이 만듭니다. 원천 라운드가 없는 엔진은 원천 시행도 없어서, 많이 만들어 상설 판에서 거르면 그 선택이 재채점 시행 집합에 남지 않습니다(계보 n_family 만 오릅니다).
- **고치는 법**: 선언 검사를 넣거나(등록부 인계 줄 · 결정 id resolved · 원천 라운드 ≥ 1 중 하나 필수), 일부러 뺐다면 README v4 절 · RELEASES known_limits 에 이유를 적습니다.

#### R4. 원천 라운드 판독에 틈이 둘 있습니다
- **근거**
  - (i) 기저 풀 철학 관문은 스캔 때 원장에 적힌 source_rounds 만 봅니다(p4.R:227). 사슬 등록은 지금 등록부까지 합칩니다(p4.R:880-882). 스캔 뒤 등록된 원천 라운드의 영수증 hold 는 풀이 보지 못합니다.
  - (ii) `rc_standing_source_cells` 는 사전등록 md5 ≠ 등록부(standing.R:745) · 칸 사양 md5 ≠ 등록(:753) · 핀에 엔진 없음(:756)이면 그 라운드를 조용히 건너뜁니다. 사슬 시행에 쓰일 때 이것은 누락입니다(그 라운드가 엔진을 쟀어도 시행 집합에 들어가지 않고 거부도 없습니다).
- **고치는 법**: (i) 풀도 등록 시점처럼 "원장 source_rounds ∪ 지금 md5 대조 라운드"로 영수증을 읽습니다. (ii) 사전등록 pins.files 에 이 엔진 md5 가 있는데 검증이 안 되는 라운드는 사슬 등록에서 missing(`<round>:<검증 불가>`)으로 거부합니다.

#### R5. v3 코어가 자체 사양 원장을 관문 없이 읽습니다(README 알려진 한계 1) — 막는 기계 장치가 없습니다
- **근거**: README v4 절 "알려진 한계" 1 · 시험 P4(v3 는 자체 사양 행 ON 에 자격). P1S03 은 core_version v4 라 RELEASES 출시와 무관하게 등록 · 측정됩니다. `round.sh - p4-pool` 의 기본 판은 RELEASES 마지막 판(round.sh:35) = 지금 v3 입니다.
- **왜**: 출시 순서를 사람이 지켜야만 닫힙니다. v3 로 만든 사슬 판(core_version v3)은 원천 시행 · 철학 관문 없이 자체 사양 기저를 받습니다.
- **고치는 법**: v4 안에서 막습니다. 예: 자체 사양 갈래 판정(`rc_standing_judge`)이 RELEASES 마지막 판 < v4 면 멈춤, 또는 자체 사양 원장 줄 schema 를 따로 둬 v3 판독기(`rc_standing_ledger_read`)가 "사슬 끊김"으로 건너뛰게 함(v4 는 둘 다 읽음). 최소한 P1S03 측정 전에 RELEASES v4 를 넣습니다.

#### R6. blend N5 는 값만 계산합니다 — 채택 규칙에 넣지 않으면 막지 않습니다
- **근거**: p4.R:1290(값) · 채택 = 등록된 규칙만(p4.R:1291-1293) · 필수 지표 RC_P4_REQUIRED(p4.R:47-48)에 beta_asym_ok_vis 없음 · 검사 p4.R:688. README v4 절 7 은 "막는다"고 적습니다. C-20261113-011(수용)의 대안은 "사슬 1호 채택 규칙에서 blend 걸음도 beta_asym_ok_vis = 1 필수"입니다.
- **왜**: 사슬 판 작성자가 규칙을 빠뜨리면 하락 β ≥ 상승 β 인 blend 걸음이 채택됩니다. "필수"를 기계가 보증하지 않습니다.
- **고치는 법**: 새 규칙 판(p4_rules_v3)에서 beta_asym_ok_vis ≥ 1 을 필수 지표 · 방향 문턱에 넣거나, 최소한 `rc_p4_chain_check` 가 blend 블록을 쓸 수 있는 사슬에 그 규칙을 요구합니다. README 문구는 "값 계산 · 규칙은 사슬 판"으로 고칩니다.

#### R7. 저위험 가족 집합이 브리프와 다릅니다(코드 3 · 브리프 4)
- **근거**: `RC_P4_LOWRISK_HOLD = defense · risk · regime`(p4.R:82). README v4 절 5 · P1S03 `DESIGN.md:41` 과 같습니다(C-20261112-021 문언 FDEFE · FRISK · FREGI · 결론 범위 11). 브리프는 defense · risk · liquidity · regime 입니다. 생성기 `FCE_DEF_FAMILIES`(fc_engine_gen.R:51)와 결론 범위 12 는 4 가족입니다(용도 = 방향 · 원천 셈). C-20261113-017 응답은 철학 보류 C-010 이 보류를 유동성 · 쏠림 · 토탈로 넓혔다고 적습니다.
- **왜**: 유동성 · 쏠림 엔진(특히 P1R04 T1 판)은 도훈 결정 id 없이 영수증 hold = false 만으로 풀립니다. 의도라면 괜찮지만, 문서마다 집합이 달라 다음 판에서 어긋나기 쉽습니다.
- **고치는 법**: 의도를 하나로 정합니다. 3 가족이면 README · RELEASES known_limits 에 "유동성 · 쏠림은 영수증 hold 로만"을 적고, 4(+쏠림)이면 상수에 더합니다(LOWBETA 결정 id 로 바로 풀립니다). 상수는 한 곳(생성기 상수 또는 등록부)에서 읽습니다.

#### R8. (운영 · 코드 밖) P1R03 보는 창 파일에 test_hold 열이 남아 있습니다
- **근거**: `04_Research/programs/P1_RETURN/P1R03_factor_family_composites/results/evaluation_visible.json` 에 `"test_hold"` 키가 있습니다(개수만 확인 · 값 안 봄). README v4 절 1 도 적습니다. 다른 `evaluation_visible.json` · stage_artifacts 보는 창 파일에는 없습니다.
- **왜**: 보는 창 파일은 처방 · 리뷰 레인이 열어도 되는 파일입니다. τ_D 뒤 정보(시험 창 연 알파 부호)가 그 레인에 남습니다.
- **고치는 법**: 그 파일을 격리하거나 v4 규칙으로 파생본을 다시 씁니다(판정 · verdict.json 무변경). 이미 그 파일을 읽은 리뷰 · 라운드(P1R04 등)의 exposures 에 적습니다.

### 선택

- **S1.** `rc_rules_test_ids` 는 report 의 `when` 의존을 따라가지 않습니다(rules.R:129-142 · report 평가 :104-108). report B 의 when 이 test_hold 면 B 열의 NA 모양에 시험 창 정보가 실립니다. 지금 P1 템플릿에는 없습니다. 고침: when 이 시험 창 규칙이면 그 report 도 시험 창 규칙으로 세고 고정점까지 반복합니다.
- **S2.** 영수증 `engines` 항목이 목록이 아니면 `e$hold` 가 오류를 내 `rc_p4_base_pool` 전체가 멈춥니다(p4.R:300). 닫힌 쪽이지만 레인 행까지 막습니다(v10.2 "막지 않는다"). 고침: `is.list(e)` 가 아니면 그 엔진만 unread.
- **S3.** 닫기 셈(p4.R:1604-1607): ① srcs 에서 NA 를 뺀 뒤 기대 수를 셉니다 — 기록 수(`length(st$reg$source_trials)`)로 세면 손상 기록이 관문에서 걸립니다. ② 같은 산출 경로가 두 번 오면 trials 는 unique 인데 기대 수는 더해져 거짓 막힘이 납니다 — 경로 정규화 뒤 unique 로 셉니다. ③ 같은 전략(T0 엔진 · 표준 구성)이 P1R03 변형 + P1R04 reference 로 두 번 들어갑니다 — 보수적이지만 상설 판의 "재측정 = +1 없음"과 셈법이 다릅니다(의도를 한 줄 적습니다).
- **S4.** 자체 사양 입구는 `exclude_combination` · `long_leg_window` 를 쓰지 않습니다(standing.R:173-174 는 검사만 · `.rcs_scan_own_dir` 에 사용 없음). 문서에 "자체 사양 = 해당 없음"을 적거나 검사를 갈래별로 나눕니다.
- **S5.** 자체 사양 갈래가 판 3 이상이 되면 v3 레인 판 2(P1S02)의 enqueue 가 v3 규칙(갈래를 모르고 번호만 봄)으로 막힙니다. 그 전에 레인 갈래를 v4 판으로 옮기거나 알려진 한계에 적습니다.
- **S6.** 생성기 파일 자동 핀이 없습니다(README 알려진 한계 3). P1S03 초안은 pins.files 에 두 생성기 · factor_combinable.R 을 손으로 넣어서 지금은 막혀 있습니다. orientation_layer 허용 조건 ②가 생성기 본문에 달려 있으니, `rc_init_standing_p1` 이 own_spec 이면 scan.generators 를 pins.files 에 자동으로 넣게 합니다.

---

## §3. 확인하지 못한 것

- v3 경로로 실제 사슬 판이 만들어지는지: v3 `rc_p4_base_cell_spec` 가 자체 사양 · 시드 행의 논문 메타를 측정 산출(`authoritative_remeasure.json`)에서 찾는지 확인하지 못했습니다(파일 금지). 풀 자격(시험 P4)과 블렌딩 부품 경로까지는 확인했습니다.
- P1R03 · P1R04 측정 산출 폴더 이름(basename 고유성 · 기대 id 의 변별력): 측정 기록에 전기간 수치가 있어 열지 않았습니다.
- `sr_regrade` · `src_gate` 실제 동작: 코드만 읽었습니다(시험 C5 의 가짜 재채점 외 실행 없음).
- 생성기 본문 함수(`fce_engine_text` · `fcc_engine_text`)의 재생성 결정성: 시험 O1(실제 30개 통과)에 기댔습니다.
- 코어 밖 소비자: `superfan_watch.py` 의 갈래 인식 · `ops/chain_tick.sh` 무인 틱과의 상호작용은 보지 않았습니다.
- C15 스캐너(`c15_load_path_scan.R`)는 돌리지 않았습니다. v3 · v4 의 parquet 직접 읽기 줄이 같다는 것만 diff 로 확인했습니다.
- P2 · P3 라운드가 자체 사양 엔진을 기저로 쓴 경우 원천 시행에 들어가지 않는 점(설계 범위 = P1 라운드)은 판단하지 않았습니다. `factors` 축 블렌딩으로 저위험 가족 팩터를 직접 섞는 길도 이 변경 범위 밖이라 보지 않았습니다.
