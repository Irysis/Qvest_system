#!/usr/bin/env Rscript
## P1S03 사양 v4 — 초안 v3 뒤 판 표식 보충 줄(D2 줄 묶음) 반영 · 규칙 · 문턱 · 입구 · 시드 불변(v3 생성기 init_p1s03_v3.R 를 고친 사본 · 바꾼 곳 = 판 표식 글(D2 줄 묶음) · 노출 [4] · 점검 v3 반영)
##   v3 → v4 이유: 11-14 21:5x 이음매 세션 정정 — D2 팩터 DB 재계산이 밸류 · 성장 7팩터의 퀀티 채움 행을 빠뜨려 판 표식 원장에 보충 줄
##     D2-XF-FILL-RESTORE-20261114(결정 = D2 · 범위 7팩터)가 D2 뒤에 붙었다 → 측정 자료 판 = 원장 마지막 줄(D2 줄 묶음의 끝) 뒤 · 글은 D2 줄 묶음 전부를 적는다.
##     자체 사양 칸은 범위와 무관하게 모든 판 표식 줄에 걸린다(factor_db_vintage.R — 엔진 칸은 선언 팩터가 없다) — 보충 줄 앞에 잰 칸은 기저 자격이 없다.
##   (v3 머리 — 유지) v2 → v3 이유: v2 글(11-14 16:14)은 D1 줄이 생기기 전 판이고, 도훈 D2 채택(RAWDATA-INTERNAL-BREAK-FILL-D2D3-20261114 — RAWDATA 원천 단절 행의 Ret 을
##     시가총액 기준 실수익으로 채움 · IS 값이 바뀐다)으로 'IS 구간은 판 표식 수리 범위 밖' 전제가 D2 에는 맞지 않는다 → T0 기대 = 같은 자료 판(D2 뒤) P1R04 기준 칸.
##   (v2 머리 — 유지) 반영: 격리 점검 v1 · 철학 P1 R-20261113-006 · 판단 T1 R-20261113-007 · 코어 v4 출시 전 수리(M1 · M2 · T4 C-035~038).
##   실행 조건(모두 — 아니면 중단): 등급 v3.5 핀(317a9c0e0) · 06_Registry/factor_db_vintage.json 마지막 줄이 D2 줄 묶음(decision 에 RAWDATA-INTERNAL-BREAK-FILL-D2D3-20261114) ·
##     P1R04 평가 산출 없음(노출 줄 'Q 는 P1R04 판정을 보지 않았다'가 사실이어야 한다) · drafts.json 의 초안 v3 점검 기록 있음 — 그다음 round.sh draft(v4) → 변경분 점검(좁게) → 등록.
##   실행: Rscript 04_Research/programs/P1_RETURN/P1S03_own_spec_qualification/tools/init_p1s03_v4.R   (작업 디렉터리 = 저장소 루트)
suppressMessages(source("04_Research/programs/_lib/round_core/v4/load.R"))
stopifnot(identical(RC_VERSION, "v4"))
root <- rc_root()
rd <- "04_Research/programs/P1_RETURN/P1S03_own_spec_qualification"
f1 <- file.path(rd, "specs/P1S03_FVALU_RX0.json")
## 실행 조건 먼저(어느 파일도 쓰기 전) — 등록본 없음(변경분 점검 v2 S-4) · D1 · D2 판 표식 · P1R04 평가 산출 없음
for (pf0 in c(file.path(root, "stage_artifacts/programs/P1_RETURN/P1S03_own_spec_qualification/prereg.json"), file.path(root, rd, "prereg.json")))
  if (file.exists(pf0)) stop("[init_p1s03_v4] 이미 등록됐다(", pf0, ") — 생성기를 다시 돌리면 R2(사양 md5 · seed_md5_not_prereg)로 판이 멈춘다 · 고칠 일은 새 판")
VINT <- "RAWDATA-SEAM-0330-REPAIR-20261113"                 # 판 표식 id(06_Registry/factor_db_vintage.json) — 사양 글에 τ_D 뒤 날짜를 쓰지 않는다(F-4)
VD1 <- "PRICE-CONTINUITY-FACTORS-20261113"                  # D1(가격 수준 팩터 연속 가격 · 202603 뒤 달만 · IS 무영향 설계 — 이음매 세션 11-14 16:23)
D2DEC <- "RAWDATA-INTERNAL-BREAK-FILL-D2D3-20261114"        # 도훈 D2 결정 id(판 표식 줄의 decision 에 있어야 한다)
VE <- rc_json_read(file.path(root, "06_Registry/factor_db_vintage.json"))[["entries"]]
ids <- vapply(VE, function(e) as.character(e[["id"]]), "")
if (!(VD1 %in% ids)) stop("[init_p1s03_v4] D1 판 표식 줄 없음 — 중단")
VL <- VE[[length(VE)]]; VLAST <- as.character(VL[["id"]])
if (VLAST %in% c(VINT, VD1) || !grepl(D2DEC, paste(unlist(VL[c("decision", "note")]), collapse = " "), fixed = TRUE))
  stop("[init_p1s03_v4] D2 판 표식 줄 대기 — 마지막 줄 ", VLAST, " 의 decision · note 에 ", D2DEC, " 없음")
if (file.exists(file.path(root, "04_Research/programs/P1_RETURN/P1R04_combiner_t1_icw/results/evaluation_visible.json")))
  stop("[init_p1s03_v4] P1R04 평가 산출이 있다 — 노출 줄을 고친 뒤(판정을 본 상태) 다시")
DV <- rc_json_read(file.path(root, rd, "drafts.json"))[["versions"]]
RV3 <- if (length(DV) >= 3L) DV[[3]][["review"]] else NULL
if (is.null(RV3)) stop("[init_p1s03_v4] 초안 v3 점검 기록 없음(drafts.json) — round.sh reviewed 3 먼저")
## D2 줄 묶음 = D1 줄 뒤에서 decision · note 에 D2 결정 id 를 단 줄 전부(원장 순서) — 글은 id · 범위만 쓴다(τ_D 뒤 날짜를 쓰지 않는다 · F-4)
D2NOTE <- c("RAWDATA-INTERNAL-BREAK-FILL-D2D3-20261114" = "D2 — RAWDATA 원천 단절 행 Ret 정정",
            "D2-XF-FILL-RESTORE-20261114" = "D2 보충 — D2 팩터 DB 재계산에서 빠진 퀀티 채움 행 복원")
D2S <- Filter(function(e) grepl(D2DEC, paste(unlist(e[c("decision", "note")]), collapse = " "), fixed = TRUE), VE[seq_along(VE) > match(VD1, ids)])
if (!length(D2S) || !identical(as.character(D2S[[length(D2S)]][["id"]]), VLAST)) stop("[init_p1s03_v4] D2 줄 묶음의 끝이 원장 마지막 줄이 아니다 — 중단")
d2desc <- function(e) {
  id <- as.character(e[["id"]]); sc <- e[["scope"]]
  rng <- if (is.list(sc) && length(sc[["factors"]])) paste0(" · 범위 ", length(sc[["factors"]]), "팩터") else if (identical(sc, "all")) " · 범위 전체" else ""
  paste0(id, "(", if (!is.na(D2NOTE[id])) D2NOTE[[id]] else "D2 보충 줄", rng, ")")
}
VD2TXT <- paste(vapply(D2S, d2desc, ""), collapse = " · ")
is_main <- vapply(D2S, function(e) identical(as.character(e[["id"]]), D2DEC), TRUE)
if (sum(is_main) != 1L) stop("[init_p1s03_v4] D2 줄 묶음에 D2 줄(id = 결정 id)이 하나가 아니다 — 중단")
VD2MAIN <- d2desc(D2S[[which(is_main)]])                                     # P1R03(앞 자료 판)과 다를 까닭 = D2(RAWDATA Ret 정정)
VD2SUP <- if (any(!is_main)) paste(vapply(D2S[!is_main], d2desc, ""), collapse = " · ") else ""   # 보충 줄 = 측정 시작 조건(D2 재계산에서 빠진 행 복원)
VTXT <- paste0("판 표식 ", VINT, " · ", VD1, "(D1)")   # IS 무영향으로 설계된 두 수리(D2 는 아래에 따로 — IS 값이 바뀐다)
VMEAS <- paste0("판 표식 원장 마지막 줄 ", VLAST, " 완료 뒤 측정분만(D2 줄 묶음: ", VD2TXT, " — 도훈 결정 ", D2DEC,
                " · 완료 판독 = 계약 contracts/factor_db_vintage.R 의 fdv_ledger · fdv_stamp — 진행 중 줄이 남으면 측정 전)")
## 시드 칸 사양 다시 만들기(코어 v4 출시판 rc_standing_own_seed_spec — 변경분 점검 2 M3 · 판단 T4 C-036: 자체 사양 시드도 같은 엔진 스캔 행과 같은 시행 수 규칙)
##   바뀌는 잎은 selection_accounting 의 n_family_at_registration · n_trials_basis 두 칸뿐이어야 한다(엔진 · 구성 · 축 · 라벨 불변 — 아니면 중단)
old_seed <- rc_json_read(f1)
new_seed <- rc_standing_own_seed_spec("04_Research/programs/P1_RETURN/P1R03_factor_family_composites/specs/P1R03_FVALU_C0.json", "P1S03_FVALU_RX0", root = root)
cj <- function(x) as.character(jsonlite::toJSON(x, auto_unbox = TRUE, null = "null", digits = NA))
leaf <- function(a, b, path) {
  if (is.list(a) && is.list(b) && !is.null(names(a)) && !is.null(names(b))) unlist(lapply(union(names(a), names(b)), function(k) leaf(a[[k]], b[[k]], paste0(path, ".", k))))
  else if (identical(cj(a), cj(b))) character(0) else path
}
ch <- leaf(old_seed, new_seed, "seed")
if (!all(ch %in% c("seed.selection_accounting.n_family_at_registration", "seed.selection_accounting.n_trials_basis")))
  stop("시드 칸 사양이 시행 회계 밖에서 바뀐다 — 중단: ", paste(setdiff(ch, c("seed.selection_accounting.n_family_at_registration", "seed.selection_accounting.n_trials_basis")), collapse = ", "))
rc_json_write(new_seed, f1)
cat(sprintf("[init_p1s03_v4] 시드 칸 사양 다시 만듦 — n_family %s → %s · md5 %s\n", old_seed$selection_accounting$n_family_at_registration,
            new_seed$selection_accounting$n_family_at_registration, rc_md5(f1)))
seeds <- list(list(code = "P1S03_FVALU_RX0", engine = "FVALU", role = "reference", spec = f1))

purpose <- paste0(
  "P1 엔진 자격 규칙(P1R01 승계 — 판 1 · 판 2 · P1R03 · P1R04 와 같은 자격 규칙 · 같은 문턱 · P1R04 는 보고 규칙 test_hold 가 없다)을 자체 사양 입구 갈래(track own_spec)의 판 1 로 등록한다. ",
  "입구 = 팩터 척추 생성기가 만든 점수 패널 엔진(04_Research/strategies/FC_* · own_spec.json — 카테고리 동일가중 합성 T0 · 시점별 IC 가중 결합 T1)이다. ",
  "새 결합기 단계는 새 생성기 파일이라 입구 사유 own_generator_unknown 으로 빠지고 새 판으로 받는다(생성기 파일은 이 판 핀). ",
  "표준 구성(롱온리 25종 동일가중 · 15bps · 유동성 2억 원 · 활성 측정 축)으로 재서 기저 풀(P4 강화 사슬의 기저 · 블렌딩 부품)의 자격을 준다. ",
  "기저 풀 자격 = 상설 판 통과만(도훈 결정 P4-BASE-POOL-GRADE-PATH-TAU-20261111) — P1R03 · P1R04 라운드 판정은 연구 질문(합성 · 결합 개선)의 판정이고 기저 자격을 주지 않는다. ",
  "시드 = P1R03 자격 엔진 FVALU(밸류 카테고리 동일가중)의 같은 판본 재측정 — 이 판 경로가 아는 답을 그대로 내는지 보는 양성 대조다(사다리 루프 ① 기준점부터). 스캔 항목 = 나머지 29(FC_FAM_value 는 시드와 같은 엔진이라 duplicate).")
hypothesis <- paste0(
  "자격 = IS β-통제 t(α) ≥ tier_graduation 하한 ∧ IS 상승 포착 ≥ 0.55(P1R01 승계 · 위기별 하락노출 · OOS α 는 보고 전용). ",
  "기대: 시드 FVALU 의 IS 값(t_alpha_vis · uc_vis · beta_vis) = 같은 사양 · 같은 자료 판에서 잰 P1R04_FVALU_R0 의 값(결정론 엔진 · 같은 표준 구성). ",
  "T0 15 = 같은 자료 판(", VLAST, " 뒤)에서 잰 P1R04 기준 칸과 같은 판정(15/15 — 결정론 엔진 · 같은 표준 구성). ",
  "P1R03 칸(앞 자료 판)과의 판정 일치도 기록한다 — ", VTXT, " 는 IS 무영향으로 설계됐지만 D2 는 IS 수익률 일부 행을 정정하므로 경계 칸은 달라질 수 있다",
  if (nzchar(VD2SUP)) paste0("(D2 보충 줄 ", VD2SUP, " 은 D2 재계산에서 빠진 행을 되돌리는 수리라 P1R03 과 다를 까닭이 아니라 측정 시작 조건이다)") else "", ". ",
  "T1 15 의 판정은 엔진마다 독립 · 선택 없음 — P1R04 의 결합 개선 판정(기준 엔진 대비 증분 알파)과 별개인 엔진 자격만이다. ",
  "같은 카테고리의 T0 · T1 은 같은 계보(family_root FC:<카테고리>)다 — 독립 원천 둘로 세지 않는다.")

exposures <- list(
  "Q 는 P1R03 의 IS 판정 파일(evaluation_visible.json — 자격 8/15)과 그 파일에 코어 v3 결함으로 남은 보고 규칙 열(test_hold — 자격 칸의 OOS 연 알파 > 0 여부)을 본 상태다(P1R04 노출 고지와 같다). 규칙 · 문턱은 P1 템플릿 승계로 고정(재량 없음) · 코어 v4 는 그 열을 IS 파일에서 뺀다.",
  "P1R03 의 철학 P2(R-20261113-002)도 test_hold 열이 남은 그 IS 판정 파일을 읽었다(코어 v3 결함 · 판단 T1 C-20261113-057). 이 판의 규칙 · 입구에는 그 열이 없다.",
  "Q 는 앞선 라운드 보고(사람 쪽)로 OOS(τ_D 뒤) 성과를 본 상태다(이음매 세션의 D1 재측정 통지에 실린 P1R03 7 엔진 시험 창 Calmar 포함 — 11-14) — 판정 규칙은 IS 열만 쓴다(코어 검사 rc_rules_test_window_use · OOS α 는 보고 전용).",
  "Q 는 P1R03 산출물(T0 15 엔진)의 IS 구간 NAV · 위기 하락노출 · 보유를 P1R04 차트 배치 시험(가짜 짝 · IS 전용 · 판정 무관)에서 본 상태다 — OOS 구간은 그리지 않았다.",
  paste0("초안 v4 는 등급 v3.5 핀 교체 · D1 · D2 줄 묶음(D2 · D2 보충) 판 표식 뒤 · P1R04 재측정 결과 전에 만들었다(원 세션 11-14 결정 — lean-loop 5 '막지 않는다'로 교체를 P1S02 · P1R04 측정 앞에 뒀고, D2 채택으로 측정을 D2 뒤로 미뤘다). Q 는 P1R04 의 판정을 보지 않았다 — 11-13 측정은 D1 예고로 결과 전(10칸 완료 · 11번째 칸 측정 중) 중단했고 부분 산출은 평가 없이 보관했다(P1R04 DESIGN §10). 11-14 D2 완료 뒤 띄운 측정 셸은 측정 시작 전(데이터 지문 안정 대기 중) D2 보충 줄 소식으로 멈췄다(P1R04 results 빔 · 등록 직전 P1R04 평가 산출 없음을 다시 확인한다). 초안 v1 → v4 에서 바뀐 것(변경분 점검 v2 R-1): 시드 칸 시행 수 2 → 45(같은 엔진 스캔 행과 같은 규칙 rc_standing_own_nf · 판단 T4 C-036) · ",
  "기대 구체화(시드 아는 답 = 같은 자료 판 P1R04_FVALU_R0 IS 값 · T0 15 비교 상대와 '원천 판정과 다름' 표식 — 판단 T1 C-055 · C-056) · 통과 보고 단위 push_each → daily_summary(C-058) · 등급 v3.5 핀(6파일 — grade_v3.R · matched_controls.R · essence_score.R · diagnosis_packet.R · grade_v3.json · matched_controls.json) · 감독 · 점검 지적 문장 · 회계 문구 · 코어 판(v4) · 자료 판 글(D1 · D2 줄 묶음 판 표식). ",
         "자격 규칙 · 문턱 · 입구 · 갈래 · 판 번호 · 시드 엔진 · 구성 · 축은 초안 v1 과 같다."),
  "팩터 방향 격리 재판정(밸류 · 성장 · 컨센서스 · 쏠림 73 · 성과 무참조 · 11-13)의 결과(불일치 3 · 불명 9)를 본 상태다 — 입구 · 판정 규칙에 쓰지 않는다(결론 범위 방향 줄).",
  "입구 규칙(자체 사양 입구 기본값 RC_STANDING_SCAN_OWN_DEFAULT · 방향 층 engine_native + orientation_layer)은 코어 v4 의 정적 검사(생성기 재생성 md5 · 본문 실행 단정)로만 정했다 — 성과와 무관.",
  "Q 는 등록 전 입구 미리보기(scan --dry-run · 사유 코드별 디렉터리 수 · 성과 수치 없음)를 본 상태이며, 미리보기 뒤 입구 규칙을 바꾸지 않았다.")

conclusion_scope <- list(
  "자격 엔진 목록 = P4 기저 후보(활성 측정 축 · 같은 epoch 비교만). 자격 ≠ 권위 등급 · Judge · BOOK.",
  "미달 = 표준 구성(롱온리 ≤25종 동일가중 · 15bps · 활성 축 · 월말 신호 · 월간 집행)에서 이 규칙 미달 — 그 카테고리 · 결합 방식의 기각이 아니다(연구 질문의 판정은 P1R03 · P1R04 라운드).",
  "입구 제외(사유 코드) = 측정하지 않음 — 판정이 아니다. 자체 사양 입구 사유: own_spec_missing(사양 없음 · 판독 불가 · schema ≠ fc_own_spec_v0 · core md5 ≠ spec_md5) · own_generator_unknown(생성기 목록 밖 — 새 결합기 생성기는 새 판) · own_generator_mismatch(생성기 · 엔진 md5 불일치 · 재생성 본문 불일치 — 손 편집 · 부호 층 변조) · 코어 v4 의 선언 · 계보 검사 사유.",
  paste0("시드 FVALU = 양성 대조. 아는 답 = 같은 사양 · 같은 자료 판에서 잰 P1R04_FVALU_R0 의 IS 값(t_alpha_vis · uc_vis · beta_vis)과 같음(결정론 엔진 · 같은 표준 구성 — 부동소수 허용 1e-9). ",
         "세션이 tick_hold 를 둔 채 scan → 시드만 measure-item → judge 로 시드를 먼저 판정 · 대조하고, 같으면 tick_hold 를 지운다(DESIGN §8 — 무인 틱은 대기 항목을 한 번에 판정 · 발송한다). ",
         "다르면 자료 판 · 판 경로 원인을 확인하기 전에는 나머지 판정을 읽지 않는다. 통과해도 새 증거가 아니다 — 원장 회계는 무가산(결정론 재측정 · 새 시행 아님)이고, 칸의 시행 수 n_family 는 같은 엔진 스캔 행과 같은 규칙(rc_standing_own_nf · 판단 C-036 · 원천 P1R03 + P1R04)이다."),
  paste0("T0 15 의 기대 = 같은 자료 판(", VLAST, " 뒤)의 P1R04 기준 칸과 같은 판정. P1R03 칸(앞 자료 판 — D2 정정 전)과 판정이 다른 칸은 '원천 판정과 다름' 표식을 달고, ",
         "자료 판 원인(판 표식 ", VD2MAIN, " · 팩터 DB 판)을 기록한 뒤에만 기저 풀에서 쓴다",
         if (nzchar(VD2SUP)) paste0("(보충 줄 ", VD2SUP, " 은 측정 시작 조건 — P1R03 과 다를 까닭으로 세지 않는다)") else "", ". P1R04 기준 칸과 다른 칸은 판 경로 원인부터 본다(같은 자료 판이라 달라질 까닭이 없다). ",
         "T1 15 는 P1R04 변형 칸과 같은 판정이 기대값이다(같은 엔진 · 같은 구성 · 같은 자료 판)."),
  paste0("측정 자료 판: ", VMEAS, " 기저 자격을 받는다(06_Registry/factor_db_vintage.json · contracts/factor_db_vintage.R). 사슬 원천 시행도 낡은 산출은 같은 엔진 · 같은 구성의 현재 판 산출로 갈음한다(코어 v4 · 판단 T1 C-20261113-054)."),
  "순서(판단 · 철학 C-20261113-050): 등급 v3.5 핀 교체(도훈 결정 GRADE-CR-NOTCH-BETA-SELECTION-20261113) 뒤 이 판 등록 · 측정 → 블렌딩 사슬 1호 등록 · 닫기. 사슬 1호 닫기 재채점(--regrade-write)은 v3.5 발효 뒤 — 그 전 닫기는 --regrade-dry-run.",
  paste0("같은 카테고리의 T0 · T1 은 같은 계보(family_root FC:<카테고리>)다 — 둘 다 통과해도 독립 원천 둘이 아니다. 같은 카테고리 T0 · T1 블렌드(또는 토탈과 그 카테고리)는 한 원천의 결합 가중 시행이다 — ",
         "기저 풀 family_root 열 · 블렌드 걸음 꼬리표 same_lineage_blend(코어 v4) · 헌장 빈칸 9 A′ (b) '두 엔진'으로 세지 않는다(P1R04 결론 범위 승계)."),
  paste0("원천 셈 두 판(T0 · T1 같은 셈법 · 철학 C-20261113-011 · 034 (3)): 이름 셈 = 토탈 ≠ 원천 · 저위험 4 카테고리(방어 · 위험 · 유동성 · 국면) = 한 원천(P1R03 결론 범위) · ",
         "측정 셈 = 쏠림 · 토탈도 저β 원천으로 넣은 셈 — 보고에 둘 다 싣는다."),
  paste0("기저 풀(코어 v4)은 통과 칸에 철학 P2 판독(상설 pass 기록의 P2 또는 원천 라운드 · 이 판 영수증 — 수용된 보류 요청도 영수증으로 풀기 전까지 보류)과 저위험 확인을 요구한다. ",
         "저위험 확인 집합 = 방어 · 위험 · 국면 · 유동성 · 쏠림(토탈은 겹침) + 영수증 lowrisk_tag 엔진 + 원천 라운드 기계 꼬리표(results/lowrisk_tags.json 의 참 · 판독 불가 = 꼬리표 — P1R04 변환기 tools/p1r04_lowrisk_tags.R) — 엔진 단위 release_decision 이 있어야 풀린다. ",
         "P1R03 저β 5(방어 · 위험 · 유동성 · 쏠림 · 토탈)는 도훈 결정 LOWBETA-ENGINES-BASE-USE-20261113 으로 기저 사용 허용 · 표기 '저β 수익 엔진'(풀 label_class 열) · 방어 주장 없음. ",
         "T1 의 같은 카테고리 엔진(IDEFE · IRISK · IREGI · ILIQU · ICROW · ITOTAL)과 P1R04 사이드카 저위험 쏠림 꼬리표 카테고리는 그 결정을 승계하지 않는다(P1R04 결론 범위 · 철학 C-20261113-027) — 도훈 확인 전 lowrisk_confirm_pending."),
  "'방어' 표기는 시가총액 × β 무작위 대조 포트폴리오 통과 ∧ 최대낙폭이 시장보다 뚜렷이 작을 때만이다(도훈 결정 CHARTER-GAP-LOWBETA-DEFENSE-LABEL-20261113) — 이 판의 위기 하락노출 열(원장 · 통과 보고)은 시장 대비 귀속 전 원값이라 방어 근거로 쓰지 않는다(통과 push 는 판정 줄과 보고 열을 나눈다 — 코어 v4).",
  "통과 엔진마다 철학 P2 한 줄(방향 · 실패 형태 · 귀속)을 그 엔진의 다음 보고에 싣는다(P1S02 결론 범위 승계 · 철학 C-20261113-046).",
  paste0("팩터 방향: 밸류 · 컨센서스 · 쏠림(과 토탈)에는 방향 격리 재판정 불일치 구성원이 하나씩 있다(V23_RAFI_Weight · C08_Coverage · CR05_Short_Pressure_Proxy). 이 판의 결과는 등록부 방향 결과다. ",
         "등록부를 방향 정책 경로로 고치면 그 카테고리 엔진은 새 엔진(md5 변경 · 시행 +1)으로 다시 입구를 지난다. 방향 수정은 시드 판정 뒤에 한다 — 그 전에 고치면 시드 엔진이 단정으로 멈추거나 새 md5 가 되어 양성 대조를 잃는다."),
  "T1 의 가중은 측정 축 밖(전 종목 · 위생 · 동전주 바닥 · 유동성 필터 없는 순위 IC)에서 배운다 — 소형주 착시의 두 번째 경로(P1R04 결론 범위 · 철학 C-20261113-028). 다음 결합기도 측정 축 위 IC 가 생길 때까지 같은 한계를 적는다.",
  "T1 의 저위험 몫은 정적 비율이 아니라 달마다 바뀌는 as-of 무게다(P1R04 사이드카 tools/p1r04_lowrisk_share.R) — 사이드카 저위험 쏠림 꼬리표 카테고리는 저위험 묶음으로 센다(영수증 lowrisk_tag).",
  "이 판의 T1 자격 엔진은 블렌딩 사슬 1호의 기저 · 부품이 아니다 — 사슬 2호부터다(P1R04 결론 범위 · 판단 C-20261113-004).",
  "기대수익 부호 = 등록부 방향(registry) — 과거 음성: P2R04 방어 틸트 β 짝 0/8(사실 기록 · 금지 목록 아님) · 같은 카테고리의 방어 방향판 = 같은 계보 시행 +1(P1R03 결론 범위 승계).",
  "T1 대체 규칙: 카테고리 엔진은 구성원 가중이 모두 0 인 달 동일가중 점수 · 토탈 T1 은 가중 0 인 카테고리를 그 달 빼고 모든 구성원이 0 일 때만 T0 점수 · 정보계수 이력 36개월 미만 팩터 = 가중 0(엔진 규칙 · 판정 무관).",
  paste0("자격 지표 하나가 계산되지 않아도 다른 지표가 미달이면 미달로 판정한다(어느 값이 와도 미달 — 3치 논리). ",
         "모든 자격 지표가 통과이거나 미정인데 하나라도 계산되지 않으면 판정하지 않고 다시 평가한다."),
  paste0("시험: 이 판은 새 시험 묶음을 돌리지 않는다(도훈 11-12 · 11-13 — 등록 시험은 직전 결과 + 핀 동일로 갈음). 갈음 = 코어 v4 출시 시험(RELEASES.json v4 항목 · 매니페스트) · ",
         "P1R03 등록 시험 test_fc_engine_gen.R(6724f1c8 · 9/0) · P1R04 등록 시험 test_fc_combiner_gen.R(aee44109 · 12/0) + 핀(코어 매니페스트 · 생성기 md5) · 입구 재생성 md5 대조."),
  paste0("알려진 한계: superfan_watch.py scan_stale 은 갈래를 모른다(레인 판 2 가 있는 동안 이 판 스캔 정체가 그 규칙에 안 보인다) · ",
         "원천 라운드 칸이 영구 실패하면 그 칸을 원천으로 가진 사슬 등록이 막힌다(빠지면 거부 — 의도) · 기저 신호 캐시 키에 결합용 뷰 · IC 원장이 없다(첫 측정 전 캐시 시각 확인 · 인프라 과제)."))

td <- tempfile("p1s03_v4_"); dir.create(td, recursive = TRUE)
tsp <- rc_init_standing_p1(td, "P1S03_own_spec_qualification", seeds, purpose, hypothesis, edition = 1L,
                           scan = list(source = "own_spec"), exposures = exposures, conclusion_scope = conclusion_scope, tests = list(), root = root)
sp <- rc_json_read(tsp)
bc <- file.path(rd, "behavior_card_cfg_at_prereg.json")                    # 판 폴더 사본(초안 v1 때 사본) — 지금 정본과 같아야 한다
if (!identical(rc_md5(bc), rc_md5(file.path(root, "06_Registry/behavior_card.json")))) stop("행동 카드 설정 사본 ≠ 지금 정본 — 사본을 새로 떠야 한다")
sp[["behavior_card_cfg"]] <- rc_rel(bc, root)
pf <- unique(c(unlist(sp[["pins"]][["files"]]),
               "02_Infrastructure/reinforcement/rf_base_cache.R", "02_Infrastructure/reinforcement/rf_base_align.R",
               "02_Infrastructure/replication/replication_harness.R", "02_Infrastructure/contracts/backtest_result_contract.R",
               "02_Infrastructure/validation/lookahead_detector.R", "02_Infrastructure/contracts/save_bt_result.R",
               "02_Infrastructure/reinforcement/rf_rebalance.R", "02_Infrastructure/factor_db/factor_db_connector.R",
               "02_Infrastructure/portfolio/weight_catalog.R", "02_Infrastructure/factor_db/factor_combinable.R",
               "02_Infrastructure/factor_db/factor_z_standard.R", "02_Infrastructure/portfolio/advanced_weights.R",
               "02_Infrastructure/methods/method_registry.R",
               "02_Infrastructure/factor_db/fc_engine_gen.R", "02_Infrastructure/factor_db/fc_combiner_gen.R", "06_Registry/factor_combinable.json"))
sp[["pins"]] <- list(files = as.list(pf),
  basis = paste0("pins.R '핀 = 판정에 닿는 전체' — 판 2(P1S02) 목록 승계 + 자체 사양 입구의 판정 경로: 생성기 둘(fc_engine_gen.R · fc_combiner_gen.R — 입구가 엔진 본문을 다시 만들어 대조하는 함수) · ",
                 "결합용 뷰 설정(06_Registry/factor_combinable.json — 엔진 입력 뷰의 정의 · P1R03 · P1R04 와 같다). ",
                 "제외 = factor_registry.json(공유 등록부 — 다른 세션이 맞춤 팩터를 수시로 더한다 · 엔진은 own_spec 의 부호 s_reg 를 고정하고 본문 실행 단정이 결합용 뷰 부호표(뷰 빌드 때 등록부)와 대조한다 — ",
                 "방향 변경은 다음 뷰 빌드에서 엔진을 멈춘다 · 그 전에는 선언 부호 그대로) · own_spec.json(엔진이 실행 때 읽지 않는다 — 시드는 칸 사양으로 넣고 스캔 항목은 넣을 때 own_spec_md5 를 원장에 남긴다) · ",
                 "factor_dup_scan.R(dedup FALSE 라 값에 닿지 않음 · 판 2 제외 사유 승계) · 결합용 뷰 저장본 · IC 원장(자료면 — 한 측정 안의 변화는 측정 지문 · 자료 판은 판 표식이 다룬다 · ",
                 "기저 신호 캐시 키에는 둘 다 없다 — 첫 측정 전 캐시 시각 확인 · DESIGN §8) · ",
                 "06_Registry/research_programs.json · 06_Registry/decision_register.json(판정 규칙 입력이 아니라 입구 · 회계 · 기저 풀 관문 입력 — 원천 라운드 · 선언 · 시행 수 · 저위험 해제를 정하고, ",
                 "넣을 때 원장에 원천 라운드 · 가족이 남는다 · 핀하면 등록부 쓰기마다 판이 멈춘다 — 변경분 점검 v2 S-3 · 원천 라운드 재핀은 등록부 prereg_md5 도 함께 고쳐야 선언 검증이 산다(9662d7983 처럼))."))
sp[["changes_after_review"]] <- list(
  "격리 점검 v1(prereg_draft_review_v1.md · revise) → 초안 v2: F-1 = 코어 v4 출시 전 수리(시드도 자체 사양 판정 · 관문 · 원천 시행 — 격리 M1 · 판단 T4 C-035) · F-4 사양 글의 τ_D 뒤 날짜 → 판 표식 id · IS 무영향 = '예상' · F-5(1) 캐시 키 문장 정정 · S-1 문장 정밀도 · S-2 핀 제외 목록 · S-4 시험 갈음 포인터.",
  "판 폴더 정정(사양 밖 · 등록 커밋 포함): F-2 시드 먼저 판정 뒤 tick_hold 해제 절차 · F-3 해제 조건에 RELEASES v4 · F-5(2) 첫 측정 전 캐시 시각 확인 · S-3 standing-check(standing_rules.md) · S-6 방향 수정은 시드 판정 뒤.",
  paste0("변경분 격리 점검 v2(prereg_draft_review_v2.md · revise · 필수 M-1 · 권고 R-1 · 선택 S-1~S-7) → 초안 v3: M-1 자료 판 글(D1 줄 ", VD1, " · D2 채택 ", D2DEC,
         " — IS 값이 바뀌어 T0 기대의 비교 상대 = 같은 자료 판 P1R04 기준 칸 · 판 표식 = ", D2DEC, ") · R-1 노출 줄 '바뀐 것' 목록(시드 시행 수 · 기대 구체화 · 통과 보고 단위) · ",   # 초안 v3 기록 그대로(그때 VLAST = D2 줄)
         "S-2 노출 OOS 연도 표기 → τ_D 뒤 · S-3 핀 근거에 등록부 · 결정 기록부 제외 사유 · S-6 저위험 확인 셋째 길(원천 라운드 기계 꼬리표). ",
         "판 폴더: DESIGN §8 ① D2 줄 · ③ P1R04 의 D2 뒤 재측정 · 평가 끝 · tick_hold · S-1 낡은 줄 · S-4 생성기 재실행 가드(v2 생성기 중단 · v3 등록본 있으면 중단) · S-5 등록 직전 standing-check · P1R04 평가 산출 없음 · S-7 시드 대조 지문 줄."),
  paste0("변경분 격리 점검 v3(", basename(RV3[["file"]]), " · ", RV3[["verdict"]], " · 필수 M-1 · 선택 S-1 · S-2) → 초안 v4: M-1 판 표식 보충 줄 ", VLAST,
         "(D2 줄 묶음의 끝 · 이음매 세션 정정) — (a) 가설 · 결론 범위 판 표식 글을 줄별로(D2 = P1R03 과 다를 까닭 · 보충 줄 = 측정 시작 조건) · ",
         "(b) 완료 판독 = 계약(fdv_ledger · fdv_stamp) · (c) 판 폴더 DESIGN §8 · tick_hold = 원장 마지막 줄 완료 · ",
         "S-1 노출 [2] 의 11-14 시험 창 노출 고지(5f7528c44 · 규칙 고정 뒤 · 판정 무관 — 초안 v3 에서 들어갔는데 변경 기록에 없었다) · ",
         "S-2 노출 [4] '바뀐 것'에 등급 v3.5 핀(6파일) · 11-13 부분 측정 = 10칸 완료 · 11번째 칸 측정 중 중단 · 노출 [4] 에 11-14 D2 뒤 측정 셸 중단(측정 시작 전 · results 빔)."))
sp[["changes_after_superfan"]] <- list(
  "철학 P1 R-20261113-006: C-046 통과 push 판정 줄 / 보고 열 분리(코어 v4) + P2 한 줄 약속 · C-047 저위험 집합 + 유동성 · 쏠림(코어 v4) · C-048 family_root 열 · same_lineage_blend(코어 v4) + 원천 셈 두 판 · 같은 계보 블렌드 줄 · C-049 원천 라운드 철학 줄 + 코어 기본 결론 범위 · C-050 순서 줄 · N1 RELEASES v4 · N2 T0 15 판정 일치.",
  "판단 T1 R-20261113-007: C-054 원천 시행 판 검사 · 갈음(코어 v4) · C-055 아는 답 = P1R04_FVALU_R0 IS 값 일치 · 시드 먼저 · C-056 '원천 판정과 다름' 표식 · 15/15 기대 · C-057 노출 2줄 · C-058 통과 보고 = 일 요약 · C-060 알려진 한계 줄.")
if (!is.null(sp[["standing_cfg"]][["report"]])) sp[["standing_cfg"]][["report"]][["pass"]] <- "daily_summary"   # 판단 T1 C-20261113-058 — 통과마다 push 대신 일 요약(코어가 허용하는 값일 때만 — 검사가 거르면 중단)
rc_standing_validate(sp, root)
out <- file.path(rd, "round_spec.json")
rc_json_write(sp, out)
cat(sprintf("[init_p1s03_v4] 사양 %s · md5 %s · 핀 %d · 결론 범위 %d · 노출 %d · 갈래 %s · 판 %s · 통과 보고 %s\n", out, rc_md5(out), length(pf),
            length(sp[["conclusion_scope"]]), length(sp[["exposures"]]), sp[["standing_cfg"]][["track"]], sp[["standing_cfg"]][["edition"]],
            sp[["standing_cfg"]][["report"]][["pass"]] %||% "?"))
