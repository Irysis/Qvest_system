#!/usr/bin/env Rscript
#==============================================================================
# test_rf_spec_axes.R — 축 등록부 단일화 · B4 6축 · 대조 칸 제외 **양방향 검사** (결정 B4-SIX-AXIS-AND-CARRY-AXES · 2026-09-26)
#
# 재는 것(판정 = rf_spec_axes.R · rf_runner_gates.R 순수 함수 · tempdir 만 쓴다):
#   A 등록부 — 검사(rf_axes_check) · 격자 계약(rf_axes_grid_contract) · 위반 주입(블록 중복 · 모드 어휘 · union 을 팩터 밖에 · 축 삭제 · 결합 칸 삭제)
#   B 서명 정합(행동) — sig=always 축은 값이 바뀌면 서명이 바뀌고 등록부 default = 서명 기본값 · if_present 축은 없으면 구판 서명과 비트 동일 ·
#     부기 필드(control·combo_plan·overlay_cell·floor_source …)는 서명 불변 · 돌연변이: 서명이 안 접는 축을 등록부에 넣으면 검출
#   D 대조 칸 제외 — B7_40·B7_41 을 코드 통로로 알아본다(스펙 control 필드 없는 과거 칸 포함) · 승자·바닥·A(always-on)에서 빠진다 ·
#     ★양성 대조(제외가 없으면 argmax 는 대조 칸을 고른다) · ★돌연변이(격자 control 태그 삭제 → 대조 칸이 승자로 뽑힌다 = red)
#   E 결합 칸 재도출 — 모드 exclude_axis(기본 = 결정 B3-TRIM-VS-B4-SIX (A))·drop_referencing·keep_loo · 진단 블록 투영 · 동결(기록된 combo_plan) ·
#     설정 어휘 밖 = 기본 · ★판독 실패(스펙 소실) ≠ 기록 부재(수리 전 칸) — 판정 함수 rf_axes_combo_frozen(E7 · 10-03)
#   F carry 축 파생 · carry 바닥 — 돌연변이(등록부 축 삭제 → rf_axes_promote_carry 에서 빠진다 · 양성 대조 = 전 등록부) · carry 바닥 스펙 구판과 축 값 동일
#   G 예산 — 격자 칸 합 기본(37) · rf_budget_base = max(원장 값, 격자 합)(올리기만) · 승계 순서 해석 rf_axes_inherit_order(어휘 밖·중복 = 기본)
#   I 셀 초기값(rf_axes_cell_init)·무처치 판정(rf_axes_same_as_carry) — 구판 리터럴을 참조 구현으로 두고 격자 전 칸·합성 쌍에서 비트 동일 ·
#     돌연변이(등록부 축 삭제 → 슬리브만 다른 칸이 무처치로 닫힌다 · B6 칸 처치 소실) · 서명 정본 미적재 fail-closed
# (v10.01 2026-10-13) 고정 격자 러너 퇴역으로 C0~C8(러너 등록 루프 추출 실행) · D5(승격 best rf_promote_best) · E7 의 러너 결합 계획 절 추출 실행 반쪽 ·
#   F1(승격 carry rf_promote_carry — rf_promote.R) · G2~G5(러너 예산·승계 순서 절 추출 실행 · rf_b1_design_lib.R) · H1·H2(러너 AST 배선 · 구판 리터럴 부재) 삭제 —
#   대상 코드가 없다(롤백 태그 pre-v10.01-prescription-20261013). F2 양성 대조는 퇴역 래퍼 대신 rf_axes_promote_carry(전 등록부) 직접 호출.
#   등록부 함수(rf_axes_*)는 rf_spec_axes.R 에 남아 함수 단위로만 잰다(실소비자 없음 — 배선 재표적 대상 없음 · 격자 reinforce_program.json 은 그대로).
# 부작용 없음: 운영 원장·로그·설정 무접촉. 모든 쓰기는 tempdir() 아래(루트 밖).
#==============================================================================
suppressMessages({ library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat("  OK  ", m, "\n") }
ng <- function(m, why = "") { FAIL <<- FAIL + 1L; why <- paste(as.character(unlist(why)), collapse = " ")
  cat("  FAIL", m, if (length(why) && nzchar(why)) paste0(" — ", why) else "", "\n") }
chk <- function(cond, m, why = "") if (isTRUE(cond)) ok(m) else ng(m, why)
TMPD <- file.path(tempdir(), sprintf("rf_axes_%d", Sys.getpid())); dir.create(TMPD, recursive = TRUE, showWarnings = FALSE)
if (startsWith(normalizePath(TMPD, winslash = "/", mustWork = FALSE), normalizePath(ROOT, winslash = "/", mustWork = FALSE)))
  stop("tempdir 가 루트 안이다 — 쓰기 격리 불가")
invisible(capture.output(suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_spec_sig.R")))))
invisible(capture.output(suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_block_design.R")))))
invisible(capture.output(suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_runner_gates.R")))))
PROG <- fromJSON(file.path(ROOT, "06_Registry/reinforce_program.json"), simplifyVector = FALSE)
same <- function(a, b) identical(as.character(toJSON(a %||% NULL, auto_unbox = TRUE, digits = NA, null = "null")),
                                  as.character(toJSON(b %||% NULL, auto_unbox = TRUE, digits = NA, null = "null")))   # JSON 왕복(정수/실수) 무관 비교
wj <- function(x, p) { dir.create(dirname(p), recursive = TRUE, showWarnings = FALSE); write(toJSON(x, auto_unbox = TRUE, pretty = TRUE, null = "null", digits = NA), p); p }
.mkenv <- function() { env <- new.env(parent = globalenv()); env$.LOG <- list()
  env$jlog <- function(event, ...) env$.LOG[[length(env$.LOG) + 1L]] <- c(list(event = event), list(...)); env }
.logs <- function(env, ev) Filter(function(z) identical(as.character(z$event), ev), env$.LOG)
AX <- rf_axes()
axn <- rf_axes_names(AX)

cat("=== A. 등록부 · 격자 계약 ===\n")
chk(!length(rf_axes_check()) && identical(axn, c("factors", "weighting", "universe", "overlay", "rebalance", "defense_sleeve")),
    "A1 등록부 검사 통과 · 여섯 축(factors·weighting·universe·overlay·rebalance·defense_sleeve)", rf_axes_check())
## ★위반 주입 픽스처는 위치가 아니라 이름·끝 원소로 잡는다(10-03) — 등록부에서 축을 지우는 돌연변이에서도 A1 뒤 검사가 계속 돌아
##   어느 소비자가 그 축을 잃는지(C·F·I) 판정까지 남는다(위치 [[6]] 이면 축 삭제 돌연변이가 여기서 subscript 오류로 끊겼다).
.ai <- function(a, nm, alt) { i <- which(vapply(a, function(x) as.character(x$axis), "") == nm); if (length(i)) i[1] else alt }
.nl <- length(RF_SPEC_AXES)
bad <- list(
  dup_block = { a <- RF_SPEC_AXES; a[[.nl]]$block <- a[[.nl - 1L]]$block; a },
  bad_mode  = { a <- RF_SPEC_AXES; a[[.nl]]$combine <- "merge"; a },
  union_off = { a <- RF_SPEC_AXES; a[[.ai(a, "weighting", 2L)]]$combine <- "union"; a },
  stack_off = { a <- RF_SPEC_AXES; a[[.ai(a, "rebalance", .nl)]]$combine <- "stack"; a },
  combo_own = { a <- RF_SPEC_AXES; a[[.nl]]$block <- "B4"; a })
hits <- vapply(bad, function(a) length(rf_axes_check(a)) > 0L, logical(1))
chk(all(hits) && inherits(tryCatch(rf_axes(bad$dup_block), error = function(e) e), "error"),
    "A2 위반 주입 5종(블록 중복 · 모드 어휘 밖 · union 을 팩터 밖에 · stack 을 오버레이 밖에 · 결합 블록 소유) 전부 검출 · rf_axes() 는 stop(fail-closed)",
    paste(names(hits)[!hits], collapse = ","))
gc0 <- rf_axes_grid_contract(PROG)
chk(!length(gc0), "A3 운영 격자 ↔ 등록부 계약 통과(블록·승자 기준·결합 7칸·requires·n)", gc0)
ax_minus <- Filter(function(a) !identical(a$axis, "defense_sleeve"), RF_SPEC_AXES)
gcm <- rf_axes_grid_contract(PROG, ax_minus)
chk(any(grepl("B7", gcm)) && any(grepl("초과", gcm)),
    "A4 돌연변이 — 등록부에서 defense_sleeve 삭제 → 계약 red(B7 무소유 · 결합 칸 초과)", gcm)
pg <- PROG; ib4 <- which(vapply(pg$blocks, function(b) identical(b$id, "B4"), logical(1)))
pg$blocks[[ib4]]$cells <- Filter(function(c) !identical(c$code, "B4_44"), pg$blocks[[ib4]]$cells)
gcx <- rf_axes_grid_contract(pg)
chk(any(grepl("부족", gcx)) && any(grepl("n\\(7\\)", gcx)), "A5 위반 주입 — 격자 결합 칸 B4_44 삭제 → 계약 red(칸 부족 · n ≠ 칸 수)", gcx)

cat("\n=== B. 서명 정합(행동) ===\n")
S0 <- list(code = "X", factors = list(list(kind = "db", id = "F_A")), base_weight = 0.5, weighting = list(kind = "ew"),
           universe = list(kind = "k200_kq150"), base_signal = list(kind = "engine", path = "e.R"))
alt <- list(factors = list(list(kind = "db", id = "F_Z")), weighting = list(kind = "catalog", catalog_id = "lean:cvar", label = "cvar"),
            universe = list(kind = "index", flag = "K200"), overlay = list(kind = "dd_brake", arm_id = "dd_brake_q"),
            rebalance = list(kind = "rank_buffer", mult = 2, label = "buffer_2x"),
            defense_sleeve = list(kind = "factor_topk", k = 5, select = "ic_bad_rank_asof", rank = 1))
alt$foo_axis <- list(kind = "x")
sig_check <- function(ax) {   # 등록부 축마다: 값을 바꾸면 서명이 바뀌는가 · always 축의 default = 서명 기본값인가 → 어긋난 축 이름
  bad <- vapply(ax, function(a) {
    s1 <- S0; s1[[a$axis]] <- alt[[a$axis]]
    moved <- !identical(.spec_sig(s1), .spec_sig(S0))
    dflt <- if (identical(a$sig, "always") && !is.null(a$default)) { s2 <- S0; s2[[a$axis]] <- NULL; s3 <- S0; s3[[a$axis]] <- a$default
      identical(.spec_sig(s2), .spec_sig(s3)) } else TRUE
    !(moved && dflt) }, logical(1))
  vapply(ax, function(a) a$axis, "")[bad] }
chk(!length(sig_check(AX)), "B1 여섯 축 전부 — 값을 바꾸면 서명이 바뀐다 · always 축의 등록부 default = 서명 기본값(키 없음과 같은 서명)", sig_check(AX))
ip <- vapply(Filter(function(a) identical(a$sig, "if_present"), AX), function(a) {
  s1 <- S0; s1[a$axis] <- list(NULL); identical(.spec_sig(s1), .spec_sig(S0)) &&
    !grepl(a$axis, .spec_sig(S0), fixed = TRUE) }, logical(1))
chk(length(ip) == 2L && all(ip), "B2 if_present 축(rebalance·defense_sleeve) — 없거나 null 이면 구판 서명과 비트 동일")
bk <- S0; bk$control <- "sign_flip"; bk$control_seed <- 3L; bk$combo_plan <- list(mode = "exclude_axis", trimmed = list("B3"))
bk$overlay_cell <- list(); bk$floor_source <- "carry"; bk$selection_basis <- "asof_ic"; bk$selection_accounting <- list(n = 3)
chk(identical(.spec_sig(bk), .spec_sig(S0)), "B3 부기 필드(control·combo_plan·overlay_cell·floor_source·selection_*) — 서명 불변")
ax_foo <- c(RF_SPEC_AXES, list(list(axis = "foo_axis", block = "B8", combine = "replace", carry = "winner", b4_base = "carry",
                                    default = NULL, sig = "if_present", label_ko = "가짜")))
chk(!length(rf_axes_check(ax_foo)) && identical(sig_check(ax_foo), "foo_axis"),
    "B4 돌연변이 — 서명(.spec_sig)이 안 접는 축(foo_axis)을 등록부에 넣으면 등록부 검사는 통과해도 B1 판정식이 그 축을 red 로 잡는다")

## 공용 축 값 픽스처(구 C 절 — 러너 등록 루프 추출 실행 · v10.01 삭제 — 에서 남긴 정의 · F·I 가 쓴다)
RB2  <- list(kind = "rank_buffer", mult = 2, label = "buffer_2x")
RB3  <- list(kind = "interval", k = 3, phase = 0, label = "interval_k3_p0")
DS5  <- list(kind = "factor_topk", k = 5, select = "ic_bad_rank_asof", rank = 1)
OVc  <- list(kind = "dd_brake", arm_id = "dd_brake_q")
W0   <- list(kind = "catalog", catalog_id = "lean:ivol", label = "ivol")
W2   <- list(kind = "catalog", catalog_id = "lean:score_pure", label = "score_pure")
CARRY <- list(factors = list(list(kind = "db", id = "F_A")), weighting = W0, universe = list(kind = "k200_kq150"),
              universe_reset_from = list(kind = "k200_kq150"), overlay = OVc, rebalance = RB2, defense_sleeve = NULL,
              source_cell = "B6_36", source_spec = "x.json")

cat("\n=== D. 대조 칸 제외(정본 술어 재사용 — rf_is_control · rf_candidate_facts · rf_a_eligibility) ===\n")
CTX <- rf_runner_ctx(ROOT, regime = "close_t1")
mr <- list(exec_price = "close_t1")
spx <- function(code, extra = list()) wj(c(list(code = code, universe = list(kind = "k200_kq150")), extra), file.path(TMPD, sprintf("sp_%s.json", code)))
at7 <- function(code, n, pt, cal, extra_spec = list()) { a <- list(n = as.integer(n), cell_code = code, grade = "C", measurement_regime = mr,
  essence = list(cell_code = code, port_t = pt, calmar = cal, spec = spx(code, extra_spec), window_deviation_months = 0)); a }
A37 <- at7("B7_37", 1, 0.467, 0.246); A40 <- at7("B7_40", 2, 0.496, 0.209); A41 <- at7("B7_41", 3, 1.026, 0.247)
gcodes <- vapply(rfbd_grid_control_cells(ROOT), function(x) as.character(x$code), "")
chk(setequal(gcodes, c("B7_40", "B7_41")) && all(c("B7_40", "B7_41") %in% rf_control_codes(ROOT)) && all(c("B7_40", "B7_41") %in% rfbd_control_codes(ROOT)),
    "D1 격자 대조 칸 = B7_40·B7_41(control 태그) — rfbd_control_codes · rf_control_codes 가 standing 통제와 합쳐 돌려준다", paste(gcodes, collapse = ","))
chk(rf_is_control(A40, CTX) && rf_is_control(A41, CTX) && !rf_is_control(A37, CTX),
    "D2 rf_is_control — 코드 통로로 B7_40·B7_41 을 알아본다(스펙 control 필드 없는 과거 칸) · 처치 칸 B7_37 은 아니다")
env <- .mkenv()
kept <- rf_candidates_keep(list(A37, A40, A41), CTX, role = "winner_B7", log = env$jlog, base_id = "T")
lg <- .logs(env, "candidates_excluded")
cal <- vapply(list(A37, A40, A41), function(a) a$essence$calmar, 1)
chk(length(kept) == 1L && identical(kept[[1]]$cell_code, "B7_37") && length(lg) == 1L && grepl("control_cell=2", lg[[1]]$by_reason) &&
    identical(which.max(cal), 3L),
    "D3 블록 승자(calmar) — 대조 2칸 제외 → B7_37 · ★양성 대조: 제외가 없으면 argmax 는 부호 반전 B7_41(0.247 > 0.246 · 7308 실측값)")
fl <- rf_candidates_keep(list(A37, A40, A41), CTX, role = "floor", log = NULL)
chk(length(fl) == 1L && identical(fl[[1]]$cell_code, "B7_37"), "D4 바닥 후보 — 대조 칸 제외(PORT_t 최고 B7_41 1.026 이 바닥이 되지 않는다)")
A41a <- A41; A41a$grade <- "A"
el <- rf_a_eligibility(list(carry = NULL), A41a, NULL, rf_a_ctx(CTX, list(), "T"))
chk(!isTRUE(el$eligible) && "control_cell" %in% el$codes, "D6 A 자격 — 대조 칸 A 는 always-on 보류 control_cell(발행 없음 · 등급 불변)", paste(el$codes, collapse = "+"))
## B4 입력 승자 — rf_axes_block_winners 가 .winner_of 모양(규약 자격 → argmax)으로 대조 칸을 뺀다
wfn <- function(atts) function(b, by) { c0 <- Filter(function(a) startsWith(a$cell_code, paste0(b, "_")), atts)
  c1 <- rf_candidates_keep(c0, CTX, role = paste0("winner_", b)); if (!length(c1)) return(NULL)
  v <- vapply(c1, function(a) as.numeric(a$essence[[by]]), 1); list(code = c1[[which.max(v)]]$cell_code) }
bw <- rf_axes_block_winners(PROG, wfn(list(A37, A40, A41)))
chk(identical(bw[["B7"]]$code, "B7_37") && identical(attr(bw, "missing_blocks"), character(0)),
    "D7 B4 입력 승자 — B7 = B7_37(대조 제외) · 승자 기준 = 격자 select_winner_by(calmar)")
## ★돌연변이 — 격자에서 control 태그를 지운 격리 루트 → 대조 칸이 승자·바닥으로 뽑힌다(red)
MR <- file.path(TMPD, "mut_root"); dir.create(file.path(MR, "06_Registry"), recursive = TRUE, showWarnings = FALSE)
pm <- PROG; ib7 <- which(vapply(pm$blocks, function(b) identical(b$id, "B7"), logical(1)))
pm$blocks[[ib7]]$cells <- lapply(pm$blocks[[ib7]]$cells, function(c) { c$control <- NULL; c })
invisible(wj(pm, file.path(MR, "06_Registry/reinforce_program.json")))
CTXm <- rf_runner_ctx(MR, regime = "close_t1")
keptm <- rf_candidates_keep(list(A37, A40, A41), CTXm, role = "winner_B7")
vm <- vapply(keptm, function(a) a$essence$calmar, 1)
chk(length(keptm) == 3L && identical(keptm[[which.max(vm)]]$cell_code, "B7_41") && !rf_is_control(A41, CTXm),
    "D8 돌연변이 — 격자 control 태그 삭제 → 대조 제외가 꺼지고 B7 승자 = 부호 반전 B7_41(red 재현 · 표식이 판정을 실제로 움직인다)")

cat("\n=== E. 결합 칸 재도출 (결합 대상 축 = 등록부 축 − 진단 모드 블록) ===\n")
cds <- function(p) vapply(p$cells, function(c) as.character(c$code), "")
usek <- function(p) vapply(p$cells, function(c) paste(sort(unlist(c$combo$use)), collapse = "+"), "")
p0 <- rf_axes_combo_cells(PROG, character(0))
chk(identical(cds(p0), c("B4_21", "B4_22", "B4_23", "B4_24", "B4_25", "B4_43", "B4_44")) && !length(p0$drop),
    "E1 진단 블록 없음 — 7칸(전결합 + LOO 6) · 모드 무관")
pA <- rf_axes_combo_cells(PROG, "B3", mode = "exclude_axis")
chk(identical(cds(pA), c("B4_21", "B4_22", "B4_23", "B4_25", "B4_43", "B4_44")) && identical(pA$drop, "B4_24") &&
    !any(grepl("B3", usek(pA))) && identical(sort(unlist(pA$cells[[1]]$combo$use)), c("B1", "B2", "B5", "B6", "B7")),
    "E2 (A) exclude_axis — B3 진단: 전결합 5축 + LOO 5 · LOO-B3(B4_24)는 전결합과 같아 돌지 않는다 · 어느 칸도 B3 를 안 쓴다", paste(usek(pA), collapse = " "))
pB <- rf_axes_combo_cells(PROG, "B3", mode = "drop_referencing")
chk(identical(cds(pB), c("B4_21", "B4_24")) && identical(pB$drop, c("B4_22", "B4_23", "B4_25", "B4_43", "B4_44")) && identical(pB$keep_widest, "B4_21"),
    "E3 (B) drop_referencing — 구조 규칙 현행과 같은 결과(B3 참조 칸 절단 · 가장 넓은 B4_21 보존 → B4 = 전결합 + LOO-B3 두 칸)")
LANE <- file.path(ROOT, "02_Infrastructure/reinforcement/rf_lane_rules.R")
if (file.exists(LANE)) {
  LE <- new.env(parent = globalenv()); invisible(capture.output(suppressMessages(sys.source(LANE, envir = LE))))
  hd <- LE$rf_structure_combo_drop(PROG, "B3", "B4")
  chk(identical(hd$drop, pB$drop) && identical(hd$keep_widest, pB$keep_widest), "E3b (B) = HUMAN rf_structure_combo_drop(같은 격자) 비트 동일")
} else cat("  SKIP E3b — rf_lane_rules.R 부재(구조 규칙 미배포 · 통합 뒤 대조)\n")
pC <- rf_axes_combo_cells(PROG, "B3", mode = "keep_loo")
chk(identical(cds(pC), cds(p0)) && identical(usek(pC), usek(p0)), "E4 (C) keep_loo — 절단 없음(7칸 그대로)")
m1 <- rf_axes_diag_mode(list()); m2 <- rf_axes_diag_mode(list(b4_combo = list(diag_mode = "drop_referencing")))
m3 <- rf_axes_diag_mode(list(b4_combo = list(diag_mode = "zzz")))
chk(identical(m1$mode, "exclude_axis") && identical(m1$source, "default") && identical(m2$mode, "drop_referencing") && identical(m2$source, "config") &&
    identical(m3$mode, "exclude_axis") && !isTRUE(m3$valid), "E5 모드 스위치 — 부재 = exclude_axis · config 값 · 어휘 밖 = 기본 + valid FALSE")
spB4 <- wj(list(code = "B4_21", combo_plan = list(mode = "drop_referencing", trimmed = list("B3"))), file.path(TMPD, "sp_b4.json"))
fz <- rf_axes_combo_frozen(list(list(n = 1L, cell_code = "B4_21", essence = list(cell_code = "B4_21", spec = spB4))),
                           function(a) fromJSON(a$essence$spec, simplifyVector = FALSE))
spL <- wj(list(code = "B4_22", weighting = list(kind = "ew")), file.path(TMPD, "sp_b4_legacy.json"))   # 수리 전 칸 — 스펙은 있고 combo_plan 이 없다
fz0 <- rf_axes_combo_frozen(list(list(n = 1L, cell_code = "B4_22", essence = list(cell_code = "B4_22", spec = spL))),
                            function(a) fromJSON(a$essence$spec, simplifyVector = FALSE))
fzN <- rf_axes_combo_frozen(list(list(n = 1L, cell_code = "B2_6")), function(a) NULL)
chk(identical(fz$mode, "drop_referencing") && identical(fz$trimmed, "B3") && identical(fz0$source, "legacy_unrecorded") &&
    identical(fz0$mode, "keep_loo") && is.null(fzN),
    "E6 동결 — 결합 칸 시도가 있으면 기록된 계획 · 스펙은 읽히는데 기록 없는 과거 칸이면 절단 없는 계획 · 결합 시도 없으면 NULL(현 계획)")
## E7 ★판독 실패 ≠ 기록 부재(10-03 · 7308 tick 모의 실측) — 스펙을 하나도 못 읽으면 동결 판정 불가(NA · unreadable).
##   구판(둘을 같은 값으로 접음)은 진단 블록이 있는 tick 에 keep_loo 로 LOO-진단 칸(B4_24)을 되살렸다.
##   (v10.01) 러너 결합 계획 절 추출 실행(끝-끝) 반쪽은 러너 퇴역으로 삭제 — 판정 함수 rf_axes_combo_frozen 만 잰다(대조 = E6 의 fz0).
fzU <- rf_axes_combo_frozen(list(list(n = 1L, cell_code = "B4_21"), list(n = 2L, cell_code = "B4_22")), function(a) NULL)
chk(is.na(fzU$mode) && identical(fzU$source, "unreadable") && identical(fzU$n, 2L) && identical(fz0$source, "legacy_unrecorded") && identical(fz0$mode, "keep_loo"),
    "E7 판독 실패 ≠ 기록 부재 — 결합 칸 스펙을 하나도 못 읽으면 unreadable(NA · n=2) · 스펙은 읽히는데 계획 없는 칸(fz0)은 legacy_unrecorded(keep_loo)",
    paste(fzU$mode, fzU$source, fzU$n, "|", fz0$source, fz0$mode))

cat("\n=== F. carry 축 파생 · carry 바닥 (승격 carry F1 은 v10.01 삭제) ===\n")
ws <- list(factors = list(list(kind = "db", id = "F_A")), weighting = W2, universe = list(kind = "index", flag = "KQ150"),
           overlay = OVc, rebalance = RB2, defense_sleeve = DS5, overlay_cell = OVc)
cy <- rf_axes_promote_carry(ws, ws$factors, list(overlay = OVc))   # 양성 대조 — 전 등록부(v10.01: 구 rf_promote_carry 래퍼 퇴역 → 축 파생 정본 직접)
cym <- { axm2 <- Filter(function(a) !identical(a$axis, "defense_sleeve"), RF_SPEC_AXES)
  c(rf_axes_promote_carry(ws, ws$factors, list(overlay = OVc), axm2)) }
chk(!("defense_sleeve" %in% names(cym)) && ("defense_sleeve" %in% names(cy)) && identical(cy[["defense_sleeve"]], DS5),
    "F2 돌연변이 — 등록부에서 defense_sleeve 삭제 → carry 에서 빠진다(파생이 등록부를 따른다 · 양성 대조 = 전 등록부 rf_axes_promote_carry 는 슬리브를 싣는다)")
fs <- rf_carry_floor_spec(CARRY)
old_fs <- { s <- list(factors = CARRY$factors %||% list(), weighting = CARRY$weighting, universe = CARRY[["universe"]] %||% list(kind = "k200_kq150"))
  if (!is.null(CARRY[["overlay"]])) s$overlay <- CARRY[["overlay"]]; if (!is.null(CARRY[["rebalance"]])) s$rebalance <- CARRY[["rebalance"]]
  if (!is.null(CARRY[["defense_sleeve"]])) s$defense_sleeve <- CARRY[["defense_sleeve"]]; s }
chk(all(vapply(names(old_fs), function(k) identical(fs[[k]], old_fs[[k]]), logical(1))) && identical(fs$floor_source, "carry") &&
    is.null(fs[["defense_sleeve"]]), "F3 carry 바닥 스펙 — 구판과 축 값 동일(여섯 축 · 없는 축은 키 없음) + 출처 표식")
fs0 <- rf_carry_floor_spec(list(factors = NULL, weighting = NULL))
chk(identical(fs0$factors, list()) && identical(fs0$weighting, list(kind = "ew")) && identical(fs0$universe, list(kind = "k200_kq150")),
    "F4 carry 가 비중·팩터를 안 가지면 — 팩터 = 빈 목록 · 비중·유니버스 = 등록부 default(구판: 비중 NULL → 누적에서 셀 EW 로 같은 결과)")

cat("\n=== G. 예산 — 격자 칸 합 기본 · 승계 순서 해석 (러너 절 추출 G2~G5 는 v10.01 삭제) ===\n")
chk(identical(rf_grid_slots_total(PROG), 37L) && identical(rf_budget_base(35L, PROG), 37L) && identical(rf_budget_base(40L, PROG), 40L) &&
    identical(rf_budget_base(NULL, PROG), 37L), "G1 격자 칸 합 37(6블록×5 + B4 7) · 기본 = max(원장 값, 격자 합) — 올리기만")
io_d <- rf_axes_inherit_order(list()); io_c <- rf_axes_inherit_order(list(spec_axes = list(inherit_order = c("carry", "floor"))))
io_x <- rf_axes_inherit_order(list(spec_axes = list(inherit_order = c("carry", "carry")))); io_n <- rf_axes_inherit_order(NULL)
chk(identical(io_d$order, RF_AXES_INHERIT_ORDER) && identical(io_c$order, c("carry", "floor")) && !isTRUE(io_x$valid) &&
    identical(io_x$order, RF_AXES_INHERIT_ORDER) && identical(io_n$source, "default"),
    "G6 rf_axes_inherit_order 단위 — 기본·설정·중복(무효 → 기본)·NULL 설정")

cat("\n=== I. 셀 초기값 · 무처치 판정 — 구판 리터럴과 비트 동일(격자 전 칸) + 돌연변이 ===\n")
## 구판 식(러너 2026-09-25 판 리터럴)을 여기 **참조 구현**으로 둔다 — 새 파생이 격자 전 칸·합성 칸에서 같은 값을 내는지 잰다.
old_init <- function(CELL) list(weighting = CELL$weighting %||% list(kind = "ew"), universe = CELL$universe %||% list(kind = "k200_kq150"),
                                rebalance = CELL[["rebalance"]], defense_sleeve = CELL[["defense_sleeve"]])
old_same <- function(SPEC, carry) identical(.fkeys(SPEC$factors), .fkeys(carry$factors %||% list())) &&
  .same_axis(SPEC$weighting, carry$weighting %||% list(kind = "ew")) &&
  .same_axis(SPEC$universe,  carry$universe  %||% list(kind = "k200_kq150")) &&
  .same_axis(SPEC$overlay,   carry$overlay   %||% list()) &&
  .same_axis(SPEC[["rebalance"]], carry[["rebalance"]] %||% list()) &&
  .same_axis(SPEC[["defense_sleeve"]], carry[["defense_sleeve"]] %||% list())
gcells <- do.call(c, lapply(PROG$blocks, function(b) lapply(b$cells, function(c) { c$block <- b$id; c$axis <- b$axis; c })))
gcells <- c(gcells, PROG$standing_cells %||% list(), list(list(code = "X_1"), list(code = "X_2", weighting = list(kind = "hrp"), rebalance = RB3)))
js <- function(x) as.character(toJSON(x, auto_unbox = TRUE, null = "null", digits = NA))
eq_init <- vapply(gcells, function(c) identical(js(old_init(c)), js(rf_axes_cell_init(c))) && identical(names(old_init(c)), names(rf_axes_cell_init(c))), logical(1))
chk(all(eq_init), sprintf("I1 셀 초기값(교체 축) — 격자 전 칸 + 상주·합성 %d칸에서 구판 리터럴과 키·순서·값(JSON) 동일", length(gcells)),
    paste(vapply(gcells[!eq_init], function(c) as.character(c$code), ""), collapse = ","))
spx <- c(list(code = "Z", factors = NULL), rf_axes_cell_init(list(code = "Z")))
chk("rebalance" %in% names(spx) && is.null(spx[["rebalance"]]) && identical(js(spx), js(c(list(code = "Z", factors = NULL), old_init(list(code = "Z"))))),
    "I2 러너 조립 모양 — c(list(…, factors = NULL), 초기값) 이 NULL 값 키를 보존(구판 list(…) 와 JSON 동일)")
CY <- list(factors = list(list(kind = "db", id = "F_A")), weighting = W0, universe = list(kind = "k200_kq150"), overlay = OVc, rebalance = RB2)
S0 <- list(factors = list(list(kind = "db", id = "F_A")), weighting = W0, universe = list(kind = "k200_kq150"), overlay = OVc, rebalance = RB2,
           overlay_cell = list())
vars <- list(S0, within(S0, factors <- c(factors, list(list(kind = "db", id = "F_B")))), within(S0, weighting <- W2),
             within(S0, universe <- list(kind = "index", flag = "K200")), within(S0, overlay <- NULL), within(S0, overlay <- list(OVc, list(kind = "vol_scale", arm_id = "v"))),
             within(S0, rebalance <- RB3), within(S0, rebalance <- NULL), c(S0, list(defense_sleeve = DS5)))
carries <- list(CY, within(CY, overlay <- NULL), within(CY, rebalance <- NULL), list(factors = NULL, weighting = NULL), c(CY, list(defense_sleeve = DS5)))
pairs <- expand.grid(i = seq_along(vars), j = seq_along(carries))
eq_same <- mapply(function(i, j) identical(old_same(vars[[i]], carries[[j]]), rf_axes_same_as_carry(vars[[i]], carries[[j]])), pairs$i, pairs$j)
n_true <- sum(mapply(function(i, j) rf_axes_same_as_carry(vars[[i]], carries[[j]]), pairs$i, pairs$j))
chk(all(eq_same) && n_true >= 1L && n_true < nrow(pairs),
    sprintf("I3 무처치 판정 — 스펙 %d × carry %d = %d쌍에서 구판 여섯 줄과 같은 값(무처치 %d쌍 · 처치 %d쌍 — 양쪽 다 나온다)",
            length(vars), length(carries), nrow(pairs), n_true, nrow(pairs) - n_true), sum(!eq_same))
## 돌연변이 — 등록부에서 축을 지우면 파생이 따라 빠진다(검사가 등록부를 실제로 잰다 · 없는 축은 grep 에 안 걸린다)
axm_ds <- Filter(function(a) !identical(a$axis, "defense_sleeve"), RF_SPEC_AXES)
sd <- c(S0, list(defense_sleeve = DS5))
chk(!rf_axes_same_as_carry(sd, CY) && isTRUE(rf_axes_same_as_carry(sd, CY, ax = axm_ds)),
    "I4 돌연변이 — 등록부에서 defense_sleeve 삭제 → 슬리브만 다른 칸이 무처치로 닫힌다(red 재현 · 판정이 등록부를 따른다)")
axm_rb <- Filter(function(a) !identical(a$axis, "rebalance"), RF_SPEC_AXES)
b6c <- list(code = "B6_34", block = "B6", rebalance = RB3)
chk(same(rf_axes_cell_init(b6c)[["rebalance"]], RB3) && !("rebalance" %in% names(rf_axes_cell_init(b6c, ax = axm_rb))),
    "I5 돌연변이 — 등록부에서 rebalance 삭제 → B6 칸 초기값에서 집행 주기 처치가 빠진다(조용한 무처치 재현)")
f_iso <- rf_axes_same_as_carry; environment(f_iso) <- new.env(parent = baseenv())   # 서명 정본(.same_axis · .fkeys)이 안 보이는 격리 환경
chk(inherits(tryCatch(f_iso(S0, CY, ax = AX), error = function(e) e), "error") && isTRUE(rf_axes_same_as_carry(S0, CY)),
    "I6 서명 정본 미적재 → stop(fail-closed — 무처치로 조용히 닫는 판 금지) · 적재 시 정상 판정(양성 대조)")


cat(sprintf('{"test":"rf_spec_axes","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
unlink(TMPD, recursive = TRUE, force = TRUE)
quit(status = if (FAIL > 0L) 1L else 0L)
