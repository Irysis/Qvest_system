#!/usr/bin/env Rscript
#==============================================================================
# test_rf_spec_axes.R — 축 등록부 단일화 · B4 6축 · 대조 칸 제외 **양방향 검사** (결정 B4-SIX-AXIS-AND-CARRY-AXES · 2026-09-26)
#
# 재는 것(판정 = rf_spec_axes.R · rf_runner_gates.R 순수 함수 · 배선 = 러너 등록 루프·예산 블록을 소스에서 추출해 실행 · 부작용은 스텁 · tempdir 만 쓴다):
#   A 등록부 — 검사(rf_axes_check) · 격자 계약(rf_axes_grid_contract) · 위반 주입(블록 중복 · 모드 어휘 · union 을 팩터 밖에 · 축 삭제 · 결합 칸 삭제)
#   B 서명 정합(행동) — sig=always 축은 값이 바뀌면 서명이 바뀌고 등록부 default = 서명 기본값 · if_present 축은 없으면 구판 서명과 비트 동일 ·
#     부기 필드(control·combo_plan·overlay_cell·floor_source …)는 서명 불변 · 돌연변이: 서명이 안 접는 축을 등록부에 넣으면 검출
#   C 러너 등록 루프 추출 실행 — ★실사례 재현(RP_20260913_084807_skipped_base_promo1 모양: carry.rebalance = buffer_2x):
#     B1 칸이 carry 의 rebalance·defense_sleeve 를 싣는다 · 바닥 우선(바닥이 준 축은 carry 가 덮지 않는다) · B6·B7 overlay_cell = [] ·
#     B4 7칸(전결합 = 6축 승자 · LOO 는 정확히 한 축만 base) · ★돌연변이(등록부에서 rebalance 삭제 → B1 칸이 buffer_2x 를 잃는다 = red)
#   D 대조 칸 제외 — B7_40·B7_41 을 코드 통로로 알아본다(스펙 control 필드 없는 과거 칸 포함) · 승자·바닥·승격 best·A(always-on)에서 빠진다 ·
#     ★양성 대조(제외가 없으면 argmax 는 대조 칸을 고른다) · ★돌연변이(격자 control 태그 삭제 → 대조 칸이 승자로 뽑힌다 = red)
#   E 결합 칸 재도출 — 모드 exclude_axis(기본 = 결정 B3-TRIM-VS-B4-SIX (A))·drop_referencing·keep_loo · 진단 블록 투영 · 동결(기록된 combo_plan) ·
#     설정 어휘 밖 = 기본 · ★판독 실패(스펙 소실) ≠ 기록 부재(수리 전 칸) — 러너 절 추출 실행(E7 · 10-03)
#   F 승격 carry · carry 바닥 — 구판 구성과 키·값 동일(순서만 등록부 순서) · 돌연변이(축 삭제 → carry 에서 빠진다)
#   G 예산 — 격자 칸 합 기본(37) · 원장 게이트 값(.cur = 파일 값)과 달라 entry 예산이 기록된다 · 추출 실행 · 원장 값이 더 크면 그대로 ·
#     승계 순서 스위치(config spec_axes.inherit_order — 같은 절이 tick 당 1회 해석 · 어휘 밖 = 기본 + 로그)
#   I 셀 초기값(rf_axes_cell_init)·무처치 판정(rf_axes_same_as_carry) — 구판 리터럴을 참조 구현으로 두고 격자 전 칸·합성 쌍에서 비트 동일 ·
#     돌연변이(등록부 축 삭제 → 슬리브만 다른 칸이 무처치로 닫힌다 · B6 칸 처치 소실) · 서명 정본 미적재 fail-closed
#   H 배선(AST) — 러너가 등록부 함수를 부르고 구판 축 목록 리터럴(switch B2 = "weighting" … · overlay_cell c("B1","B2","B3") · 셀 초기값 · 무처치)이 남아 있지 않다
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
invisible(capture.output(suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_promote.R")))))
RUNNER <- file.path(ROOT, "02_Infrastructure/ops/reinforce_auto_parallel.R")
src <- readLines(RUNNER, warn = FALSE, encoding = "UTF-8")
PROG <- fromJSON(file.path(ROOT, "06_Registry/reinforce_program.json"), simplifyVector = FALSE)
same <- function(a, b) identical(as.character(toJSON(a %||% NULL, auto_unbox = TRUE, digits = NA, null = "null")),
                                  as.character(toJSON(b %||% NULL, auto_unbox = TRUE, digits = NA, null = "null")))   # JSON 왕복(정수/실수) 무관 비교
wj <- function(x, p) { dir.create(dirname(p), recursive = TRUE, showWarnings = FALSE); write(toJSON(x, auto_unbox = TRUE, pretty = TRUE, null = "null", digits = NA), p); p }
.mkenv <- function() { env <- new.env(parent = globalenv()); env$.LOG <- list()
  env$jlog <- function(event, ...) env$.LOG[[length(env$.LOG) + 1L]] <- c(list(event = event), list(...)); env }
.logs <- function(env, ev) Filter(function(z) identical(as.character(z$event), ev), env$.LOG)
.first_after <- function(i0, re) { if (is.na(i0)) return(NA_integer_); k <- which(grepl(re, src[(i0 + 1L):length(src)]))[1]; if (is.na(k)) NA_integer_ else i0 + k }
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

cat("\n=== C. 러너 등록 루프 — 추출 실행 ===\n")
i_r0 <- grep("^\\.seen_sig <- list\\(\\)", src)[1]
i_r1 <- grep("^if \\(!length\\(jobs\\)\\) \\{", src)[1] - 1L
## ★추출 끝 = 배치 등록 루프 문장의 끝(파서 srcref). 다른 갈래가 루프 **뒤**에 붙인 문장(예: O0a 시행 로그 — tick 상태 pending·first 참조)은
##   이 검사가 재는 등록 루프가 아니다. 줄 앵커(if (!length(jobs)) { 직전)만 쓰면 그런 삽입마다 스텁 밖 변수로 추출 실행이 죽는다
##   (배포 순서 시뮬 B5FIX→CTRL→AXIS→HUMAN→CORE 최종판 실측: object 'pending' not found).
.loop_end <- function(i0, i1) {
  ex <- tryCatch(parse(text = src[i0:i1], keep.source = TRUE), error = function(e) NULL)
  if (is.null(ex)) return(i1)
  sr <- attr(ex, "srcref")
  k <- which(vapply(seq_along(ex), function(j) startsWith(deparse(ex[[j]])[1], "if (!length(jobs)) for (CELL in batch)"), logical(1)))
  if (length(k)) i0 + sr[[k[1]]][3] - 1L else i1
}
if (!is.na(i_r0) && !is.na(i_r1)) i_r1 <- .loop_end(i_r0, i_r1)
i_bc0 <-grep("^\\.beats_carry <- function\\(w, tag\\) \\{", src)[1]; i_bc1 <- .first_after(i_bc0, "^\\}\\s*$")
i_wf0 <- grep("^\\.win_factors <- function\\(w\\) \\{", src)[1]; i_wf1 <- .first_after(i_wf0, "^\\}\\s*$")
RR <- file.path(TMPD, "reg_root")
for (dd in c("02_Infrastructure/ops", "06_Registry", "stage_artifacts/l_code/reinforcement", "wdir"))
  dir.create(file.path(RR, dd), recursive = TRUE, showWarnings = FALSE)
invisible(file.copy(file.path(ROOT, "06_Registry/reinforce_program.json"), file.path(RR, "06_Registry/"), overwrite = TRUE))
writeLines("rf_preflight <- function(SPEC, BID) SPEC", file.path(RR, "02_Infrastructure/ops/rf_preflight.R"))
RB2  <- list(kind = "rank_buffer", mult = 2, label = "buffer_2x")
RB3  <- list(kind = "interval", k = 3, phase = 0, label = "interval_k3_p0")
DS5  <- list(kind = "factor_topk", k = 5, select = "ic_bad_rank_asof", rank = 1)
OVc  <- list(kind = "dd_brake", arm_id = "dd_brake_q")
W0   <- list(kind = "catalog", catalog_id = "lean:ivol", label = "ivol")
W2   <- list(kind = "catalog", catalog_id = "lean:score_pure", label = "score_pure")
CARRY <- list(factors = list(list(kind = "db", id = "F_A")), weighting = W0, universe = list(kind = "k200_kq150"),
              universe_reset_from = list(kind = "k200_kq150"), overlay = OVc, rebalance = RB2, defense_sleeve = NULL,
              source_cell = "B6_36", source_spec = "x.json")
run_reg <- function(seg_text, E, batch, wbest = NULL, winners = list(), wbest_src = "none", ax_env = NULL, cfg = list()) {
  env <- .mkenv(); env$ROOT <- RR; env$BID <- E$base_id; env$E <- E; env$batch <- batch; env$jobs <- list()
  env$CFG <- cfg   # 러너 등록 루프가 get0("CFG") 로 승계 순서를 해석한다(C4 = 설정 스위치 끝-끝 · 무효값 로그는 예산 절 ③ — G5)
  env$PROG <- PROG; env$WDIR <- file.path(RR, "wdir"); env$MAX_RETRY <- 2L
  env$led <- list(entries = list(E)); env$w1 <- winners[["B1"]]; env$.b4_win <- winners
  env$w2 <- winners[["B2"]]; env$w3 <- winners[["B3"]]; env$.w5_overlay <- (winners[["B5"]] %||% list())$overlay %||% E$carry$overlay
  env$.wbest_spec <- wbest; env$.wbest_src <- wbest_src; env$.wbest_code <- NA_character_; env$.carry_base <- NA_real_; env$.base_paper <- NULL
  env$.REC <- list(); env$.N <- 0L
  env$rf_append_attempt <- function(...) { env$.N <- env$.N + 1L; list(n = env$.N) }
  env$rf_record_result <- function(layer, bid, n, ...) { env$.REC[[length(env$.REC) + 1L]] <- c(list(n = n), list(...)); invisible(TRUE) }
  env$.append_fail_count <- function(code, bid) 0L
  env$.rac_gate_apply <- function(spec, sp, CELL, n, path) "run"
  env$rf_load <- function(layer, root) list(entries = list(E))
  env$.rf_find <- function(L, bid) NA_integer_
  env$rf_root_papers_for <- function(SPEC, base_paper = NULL, cell_paper = NULL, root = NULL) list(papers = list(), families = character(0), unmapped_families = character(0))
  env$.COVIDX <- "stub"; env$rf_coverage_find <- function(sig, idx, exclude_base = NULL) data.frame()
  if (!is.null(ax_env)) for (nm in names(ax_env)) assign(nm, ax_env[[nm]], envir = env)
  unlink(list.files(env$WDIR, full.names = TRUE))
  env$.err <- tryCatch({
    invisible(capture.output(eval(parse(text = paste(c(src[i_bc0:i_bc1], src[i_wf0:i_wf1]), collapse = "\n")), envir = env)))
    invisible(capture.output(eval(parse(text = seg_text), envir = env))); NULL }, error = function(e) conditionMessage(e))
  env$specs <- lapply(env$jobs, function(j) tryCatch(fromJSON(j$spec, simplifyVector = FALSE), error = function(e) NULL))
  names(env$specs) <- vapply(env$jobs, function(j) j$code, "")
  env
}
if (any(is.na(c(i_r0, i_r1, i_bc0, i_bc1, i_wf0, i_wf1)))) ng("C0 등록 루프 추출 실패", paste(i_r0, i_r1, i_bc0, i_wf0)) else {
  seg <- paste(src[i_r0:i_r1], collapse = "\n")
  EP <- list(base_id = "T_AXIS_promo1", status = "active", carry = CARRY, parent = list(base_id = "T_PARENT", cell = "B6_36", best_port_t = 2.2), attempts = list())
  b1 <- list(code = "B1_1", label = "f1", block = "B1", axis = "multifactor", factors = list(list(kind = "db", id = "F_B")))
  e1 <- run_reg(seg, EP, list(b1))
  s1 <- e1$specs[["B1_1"]]
  chk(is.null(e1$.err) && same(s1[["rebalance"]], RB2) && same(s1$weighting, W0) && same(s1[["overlay"]], OVc) &&
      identical(.fkeys(s1$factors), c("db:F_A", "db:F_B")) && is.null(s1[["defense_sleeve"]]),
      "C1 ★실사례 재현 — 승격 entry B1 칸이 carry 의 rebalance(buffer_2x)·비중·오버레이를 싣는다(구판: rebalance 없음 = 월간)",
      paste(e1$.err %||% "", toJSON(s1[["rebalance"]], auto_unbox = TRUE)))
  ## 돌연변이 — 등록부에서 rebalance 축을 지우면 같은 칸이 buffer_2x 를 잃는다(검사가 등록부를 실제로 재는가)
  axm <- Filter(function(a) !identical(a$axis, "rebalance"), RF_SPEC_AXES)
  .g_fill <- get("rf_axes_carry_fill", envir = globalenv())
  em <- run_reg(seg, EP, list(b1), ax_env = list(rf_axes_carry_fill = function(SPEC, carry, block, from_floor = character(0), ...)
                                                   .g_fill(SPEC, carry, block, from_floor, ax = axm)))
  chk(is.null(em$.err) && is.null(em$specs[["B1_1"]][["rebalance"]]),
      "C2 돌연변이 — 등록부에서 rebalance 삭제 → B1 칸 rebalance 소실(red 재현 · 파생이 등록부를 따른다)", em$.err %||% "")
  ## 바닥 우선 — B3 칸: 바닥(B2 승자 비중 W2 · 바닥에는 rebalance 없음) · carry(W0 · buffer_2x)
  FL <- list(factors = list(list(kind = "db", id = "F_A"), list(kind = "db", id = "F_B")), weighting = W2, universe = list(kind = "k200_kq150"),
             overlay = OVc, overlay_cell = list())
  b3 <- list(code = "B3_12", label = "K200", block = "B3", axis = "universe", universe = list(kind = "index", flag = "K200"))
  e3 <- run_reg(seg, EP, list(b3), wbest = FL, wbest_src = "attempt")
  s3 <- e3$specs[["B3_12"]]
  chk(is.null(e3$.err) && same(s3$weighting, W2) && same(s3[["rebalance"]], RB2) && identical(s3$universe$flag, "K200"),
      "C3 승계 순서 floor > carry — 바닥이 준 비중(B2 승자)은 carry 가 덮지 않고, 바닥에 없는 rebalance 는 carry 가 채운다 · 자기 축(유니버스)은 셀 값",
      paste(e3$.err %||% "", s3$weighting$label %||% "?", toJSON(s3[["rebalance"]], auto_unbox = TRUE)))
  ## 구판 순서(carry > floor) 스위치 — 설정 한 줄(spec_axes.inherit_order)로 같은 칸이 carry 비중으로(구판 거동 재현 · 되돌림 경로 실재 · 코드 수정 없음)
  e3l <- run_reg(seg, EP, list(b3), wbest = FL, wbest_src = "attempt", cfg = list(spec_axes = list(inherit_order = list("carry", "floor"))))
  chk(is.null(e3l$.err) && same(e3l$specs[["B3_12"]]$weighting, W0) && same(e3l$specs[["B3_12"]][["rebalance"]], RB2),
      "C4 설정 spec_axes.inherit_order = [carry, floor] → 구판 거동(B3 칸 비중 = carry) · 설정 부재 = C3(floor > carry)", e3l$.err %||% "")
  ## B6·B7 overlay_cell = [] (자기 층 없음) · B6 자기 축 = 셀 값 · B7 는 바닥 rebalance 가 없어 carry 가 채운다
  b6 <- list(code = "B6_34", label = "q", block = "B6", axis = "execution_cadence", rebalance = RB3)
  b7 <- list(code = "B7_37", label = "s", block = "B7", axis = "structural_defense", defense_sleeve = DS5)
  e67 <- run_reg(seg, EP, list(b6, b7), wbest = FL, wbest_src = "attempt")
  s6 <- e67$specs[["B6_34"]]; s7 <- e67$specs[["B7_37"]]
  chk(is.null(e67$.err) && same(s6[["rebalance"]], RB3) && same(s7[["defense_sleeve"]], DS5) && same(s7[["rebalance"]], RB2) &&
      identical(s6$overlay_cell, list()) && identical(s7$overlay_cell, list()),
      "C5 B6·B7 — 자기 축은 셀 값(k3 · 슬리브) · B7 에 carry buffer_2x · 둘 다 overlay_cell = [](바닥 B5 층 오귀속 차단)", e67$.err %||% "")
  ## B4 — 6축 승자 전부 · 7칸 · LOO 는 정확히 한 축만 base
  WIN <- list(B1 = list(factors = list(list(kind = "db", id = "F_A"), list(kind = "db", id = "F_W"))),
              B2 = list(weighting = W2), B3 = list(universe = list(kind = "size_band", q_lo = 0, q_hi = 0.3333)),
              B5 = list(overlay = list(OVc, list(kind = "vol_scale", arm_id = "vol_median"))), B6 = list(rebalance = RB3), B7 = list(defense_sleeve = DS5))
  plan <- rf_axes_combo_cells(PROG, character(0))
  e4 <- run_reg(seg, EP, plan$cells, winners = WIN)
  full <- e4$specs[["B4_21"]]
  wv <- list(factors = .fkeys(WIN$B1$factors), weighting = W2, universe = WIN$B3$universe, overlay = WIN$B5$overlay, rebalance = RB3, defense_sleeve = DS5)
  bv <- list(factors = .fkeys(CARRY$factors), weighting = W0, universe = list(kind = "k200_kq150"), overlay = OVc, rebalance = RB2, defense_sleeve = NULL)
  val <- function(s, a) if (identical(a, "factors")) .fkeys(s$factors) else s[[a]]
  full_ok <- !is.null(full) && all(vapply(axn, function(a) same(val(full, a), wv[[a]]), logical(1)))
  loo_code <- c(factors = "B4_22", weighting = "B4_23", universe = "B4_24", overlay = "B4_25", rebalance = "B4_43", defense_sleeve = "B4_44")
  loo_ok <- vapply(axn, function(x) { s <- e4$specs[[loo_code[[x]]]]; if (is.null(s)) return(FALSE)
    all(vapply(axn, function(a) same(val(s, a), if (identical(a, x)) bv[[a]] else wv[[a]]), logical(1))) }, logical(1))
  chk(is.null(e4$.err) && length(e4$jobs) == 7L && full_ok && all(loo_ok),
      "C6 B4 7칸 — 전결합 = 6축 승자 값 · LOO 6칸은 **정확히 한 축만** base(carry → default) · 나머지 다섯 축은 승자 값",
      paste(e4$.err %||% "", length(e4$jobs), full_ok, paste(axn[!loo_ok], collapse = ",")))
  sig_b4 <- vapply(e4$specs, .spec_sig, "")
  chk(!anyDuplicated(sig_b4) && identical(full$combo_plan$mode, "exclude_axis"),
      "C7 B4 7칸 서명 서로 다름(중복 종결 없음) · 스펙에 결합 계획(combo_plan) 부기")
  ## B4 — 승자 없음(B6·B7 블록 미측정) → base(carry) · carry 없는 entry 면 default(키 없음)
  e4b <- run_reg(seg, EP, plan$cells[1], winners = WIN[c("B1", "B2", "B3", "B5")])
  E0 <- EP; E0$carry <- NULL; E0$base_id <- "T_AXIS_base"
  e4c <- run_reg(seg, E0, plan$cells[1], winners = WIN[c("B1", "B2", "B3", "B5")])
  chk(is.null(e4b$.err) && same(e4b$specs[["B4_21"]][["rebalance"]], RB2) && is.null(e4c$.err) &&
      is.null(e4c$specs[["B4_21"]][["rebalance"]]) && is.null(e4c$specs[["B4_21"]][["defense_sleeve"]]),
      "C8 승자 없는 축 — 승격 entry 는 carry(buffer_2x) · 기저 entry 는 default(키 없음 = 월간) — 현행 B5 원리")
}

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
pb <- rf_promote_best(list(base_id = "T", carry = NULL, attempts = list(A37, A40, A41)), CTX)
chk(identical(pb$i, 1L) && all(grepl("control_cell", pb$excluded)), "D5 승격 best(carry 원천) — 대조 칸 제외", paste(pb$i, paste(pb$excluded, collapse = ",")))
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
## E7 ★판독 실패 ≠ 기록 부재(10-03 · 7308 tick 모의 실측) — 스펙을 하나도 못 읽으면 동결 판정 불가(NA · unreadable) → 러너는 현 계획.
##   구판(둘을 같은 값으로 접음)은 진단 블록이 있는 tick 에 keep_loo 로 LOO-진단 칸(B4_24)을 되살렸다. 러너 절을 추출 실행해 끝-끝으로 잰다.
fzU <- rf_axes_combo_frozen(list(list(n = 1L, cell_code = "B4_21"), list(n = 2L, cell_code = "B4_22")), function(a) NULL)
i_t0 <- grep('^\\.b4_trim <- if \\(exists\\("rf_structure_rules", mode = "function"\\)\\)', src)[1]
i_tp <- grep("^if \\(!is.null\\(\\.b4_plan\\)\\) \\{", src)[1]; i_t1 <- .first_after(i_tp, "^\\}\\s*$")
run_b4plan <- function(att, wdir_files = list()) {
  env <- .mkenv(); env$PROG <- PROG; env$CFG <- list(); env$BID <- "T_B4FZ"; env$E <- list(base_id = "T_B4FZ", attempts = att)
  env$WDIR <- file.path(TMPD, "wd_b4fz"); unlink(env$WDIR, recursive = TRUE); dir.create(env$WDIR, showWarnings = FALSE)
  for (nm in names(wdir_files)) wj(wdir_files[[nm]], file.path(env$WDIR, nm))
  env$cells <- list(list(code = "B1_1", block = "B1"))
  env$rf_structure_rules <- function(P) list(rules = list(list(id = "B3-STRUCTURAL-TRIM", block = "B3", state = "diag", keep = "B3_11")))
  env$.err <- tryCatch({ eval(parse(text = paste(src[i_t0:i_t1], collapse = "\n")), envir = env); NULL }, error = function(e) conditionMessage(e))
  env }
if (any(is.na(c(i_t0, i_tp, i_t1)))) ng("E7 결합 계획 절 추출 실패", paste(i_t0, i_tp, i_t1)) else {
  att2 <- list(list(n = 1L, cell_code = "B4_21", essence = list(cell_code = "B4_21", spec = file.path(TMPD, "gone_B4_21.json"))))
  eU <- run_b4plan(att2)                                   # 스펙 소실 → 현 계획(B3 진단 → exclude_axis · B4_24 없음)
  eL <- run_b4plan(att2, list("spec_B4_21__T_B4FZ.json" = list(code = "B4_21")))   # WDIR 스펙은 있는데 combo_plan 없음 → 수리 전 칸 keep_loo
  cU <- vapply(Filter(function(c) identical(c$block, "B4"), eU$cells), function(c) c$code, "")
  cL <- vapply(Filter(function(c) identical(c$block, "B4"), eL$cells), function(c) c$code, "")
  chk(is.na(fzU$mode) && identical(fzU$source, "unreadable") && identical(fzU$n, 2L) &&
      is.null(eU$.err) && length(.logs(eU, "b4_combo_frozen_unreadable")) == 1L && !("B4_24" %in% cU) && length(cU) == 6L &&
      is.null(eL$.err) && !length(.logs(eL, "b4_combo_frozen_unreadable")) && "B4_24" %in% cL && length(cL) == 7L,
      "E7 판독 실패 ≠ 기록 부재 — 스펙 소실 = unreadable(NA) → 러너 현 계획(B3 진단 · 6칸 · B4_24 없음 · 로그 1줄) · 스펙 있음·계획 없음 = 수리 전 칸 keep_loo(7칸)",
      paste(eU$.err %||% "", paste(cU, collapse = ","), "|", eL$.err %||% "", paste(cL, collapse = ",")))
}

cat("\n=== F. 승격 carry · carry 바닥 ===\n")
ws <- list(factors = list(list(kind = "db", id = "F_A")), weighting = W2, universe = list(kind = "index", flag = "KQ150"),
           overlay = OVc, rebalance = RB2, defense_sleeve = DS5, overlay_cell = OVc)
TR <- file.path(TMPD, "promo_root"); dir.create(file.path(TR, "06_Registry"), recursive = TRUE, showWarnings = FALSE)
invisible(wj(list(blocks = list(), standing_cells = list()), file.path(TR, "06_Registry/reinforce_program.json")))
cy <- rf_promote_carry(ws, ws$factors, list(cell_code = "B6_36"), "s.json", root = TR)
legacy <- list(factors = ws$factors, weighting = ws$weighting, rebalance = ws[["rebalance"]], defense_sleeve = ws[["defense_sleeve"]],
               universe = list(kind = "k200_kq150"), universe_reset_from = ws$universe, overlay = OVc, source_cell = "B6_36", source_spec = "s.json")
chk(setequal(names(cy), names(legacy)) && all(vapply(names(legacy), function(k) identical(cy[[k]], legacy[[k]]), logical(1))),
    "F1 승격 carry — 구판 구성과 키 집합·값 동일(rebalance·defense_sleeve 포함 · 유니버스 리셋 + 출처) · 순서만 등록부 순서")
cym <- { axm2 <- Filter(function(a) !identical(a$axis, "defense_sleeve"), RF_SPEC_AXES)
  c(rf_axes_promote_carry(ws, ws$factors, list(overlay = OVc), axm2)) }
chk(!("defense_sleeve" %in% names(cym)) && ("defense_sleeve" %in% names(cy)), "F2 돌연변이 — 등록부에서 defense_sleeve 삭제 → carry 에서 빠진다(파생이 등록부를 따른다)")
fs <- rf_carry_floor_spec(CARRY)
old_fs <- { s <- list(factors = CARRY$factors %||% list(), weighting = CARRY$weighting, universe = CARRY[["universe"]] %||% list(kind = "k200_kq150"))
  if (!is.null(CARRY[["overlay"]])) s$overlay <- CARRY[["overlay"]]; if (!is.null(CARRY[["rebalance"]])) s$rebalance <- CARRY[["rebalance"]]
  if (!is.null(CARRY[["defense_sleeve"]])) s$defense_sleeve <- CARRY[["defense_sleeve"]]; s }
chk(all(vapply(names(old_fs), function(k) identical(fs[[k]], old_fs[[k]]), logical(1))) && identical(fs$floor_source, "carry") &&
    is.null(fs[["defense_sleeve"]]), "F3 carry 바닥 스펙 — 구판과 축 값 동일(여섯 축 · 없는 축은 키 없음) + 출처 표식")
fs0 <- rf_carry_floor_spec(list(factors = NULL, weighting = NULL))
chk(identical(fs0$factors, list()) && identical(fs0$weighting, list(kind = "ew")) && identical(fs0$universe, list(kind = "k200_kq150")),
    "F4 carry 가 비중·팩터를 안 가지면 — 팩터 = 빈 목록 · 비중·유니버스 = 등록부 default(구판: 비중 NULL → 누적에서 셀 EW 로 같은 결과)")

cat("\n=== G. 예산 — 격자 칸 합 기본 · 원장 게이트 값과 대조 ===\n")
chk(identical(rf_grid_slots_total(PROG), 37L) && identical(rf_budget_base(35L, PROG), 37L) && identical(rf_budget_base(40L, PROG), 40L) &&
    identical(rf_budget_base(NULL, PROG), 37L), "G1 격자 칸 합 37(6블록×5 + B4 7) · 기본 = max(원장 값, 격자 합) — 올리기만")
i_c0 <- grep("^cells <- do\\.call\\(c, lapply\\(PROG\\$blocks", src)[1]
i_c1 <- grep("^\\} else MAXA <- \\.cur", src)[1]
if (is.na(i_c0) || is.na(i_c1)) ng("G2 예산 블록 추출 실패", paste(i_c0, i_c1)) else {
  BR <- file.path(TMPD, "bud_root")
  for (dd in c("02_Infrastructure/ops", "02_Infrastructure/reinforcement", "06_Registry", ".cache/rf_b1_design", ".cache/rf_block_design"))
    dir.create(file.path(BR, dd), recursive = TRUE, showWarnings = FALSE)
  invisible(file.copy(file.path(ROOT, "02_Infrastructure/ops/rf_b1_design_lib.R"), file.path(BR, "02_Infrastructure/ops/"), overwrite = TRUE))
  for (f in c("rf_block_design.R", "rf_runner_gates.R", "rf_spec_sig.R", "rf_spec_axes.R"))
    invisible(file.copy(file.path(ROOT, "02_Infrastructure/reinforcement", f), file.path(BR, "02_Infrastructure/reinforcement/"), overwrite = TRUE))
  invisible(wj(PROG, file.path(BR, "06_Registry/reinforce_program.json")))
  invisible(wj(list(arms = list(list(id = "pg2_risk_overlay_v1", kind = "pg2_risk_overlay", status = "active", basis = "b"))), file.path(BR, "06_Registry/overlay_catalog.json")))
  run_budget <- function(E, ledger_max, cfg = list()) {
    env <- .mkenv(); env$ROOT <- BR; env$BID <- E$base_id; env$E <- E; env$led <- list(max_attempts = ledger_max, entries = list(E)); env$CFG <- cfg
    env$PROG <- PROG; env$MAXA <- as.integer(E$max_attempts %||% ledger_max); env$.BUD <- list()
    env$rf_record_entry_budget <- function(layer, base_id, max_attempts, reason, root) { env$.BUD[[length(env$.BUD) + 1L]] <- list(v = as.integer(max_attempts), r = reason); invisible(max_attempts) }
    old_rr <- Sys.getenv("QVEST_RF_ROOT", unset = NA); Sys.setenv(QVEST_RF_ROOT = BR)
    on.exit(if (is.na(old_rr)) Sys.unsetenv("QVEST_RF_ROOT") else Sys.setenv(QVEST_RF_ROOT = old_rr), add = TRUE)
    env$.err <- tryCatch({ invisible(capture.output(eval(parse(text = paste(src[i_c0:i_c1], collapse = "\n")), envir = env))); NULL },
                         error = function(e) conditionMessage(e))
    env }
  AB5 <- list(n = 1L, cell_code = "B5_16", essence = list(cell_code = "B5_16", port_t = 1))   # B5 가 이미 측정 — 상주 칸 미삽입(예산 = 격자 기본만)
  eb <- run_budget(list(base_id = "T_BUD", status = "active", attempts = list(AB5), attempts_used = 1L), 35L)
  bud <- eb$.BUD
  chk(is.null(eb$.err) && length(bud) == 1L && identical(bud[[1]]$v, 37L) && identical(as.integer(eb$MAXA), 37L) && grepl("기본 37", bud[[1]]$r),
      "G2 새 entry(설계 초과 없음 · 원장 파일 35) — 예산 기본 37 로 재도출 · 원장 게이트 값(.cur = 35)과 달라 entry 예산이 기록된다(B4 7칸이 안 잘린다)",
      paste(eb$.err %||% "", if (length(bud)) bud[[1]]$v else "기록 없음", if (length(bud)) substr(bud[[1]]$r, 1, 60) else ""))
  eb2 <- run_budget(list(base_id = "T_BUD2", status = "active", attempts = list(AB5), attempts_used = 1L, max_attempts = 44L), 35L)
  chk(is.null(eb2$.err) && !length(eb2$.BUD) && identical(as.integer(eb2$MAXA), 44L),
      "G3 entry 예산이 이미 더 크면(7308 = 44) 그대로 — 기록 없음 · MAXA 44")
  ## 돌연변이 — .cur 를 원장 기본(격자 상향 값)으로 되돌리면 새 entry 에서 기록이 사라진다(원장 게이트는 파일 35 에서 거부 → B4 절단)
  segb <- sub(".cur  <- as.integer(E$max_attempts %||% .led_max_file %||% 25L)", ".cur  <- as.integer(E$max_attempts %||% led$max_attempts %||% 25L)",
              paste(src[i_c0:i_c1], collapse = "\n"), fixed = TRUE)
  envm <- .mkenv(); envm$ROOT <- BR; envm$BID <- "T_BUDM"; envm$E <- list(base_id = "T_BUDM", attempts = list(AB5), attempts_used = 1L); envm$led <- list(max_attempts = 35L, entries = list())
  envm$PROG <- PROG; envm$MAXA <- 35L; envm$.BUD <- list(); envm$CFG <- list()
  envm$rf_record_entry_budget <- function(layer, base_id, max_attempts, reason, root) { envm$.BUD[[length(envm$.BUD) + 1L]] <- as.integer(max_attempts); invisible(max_attempts) }
  errm <- tryCatch({ invisible(capture.output(eval(parse(text = segb), envir = envm))); NULL }, error = function(e) conditionMessage(e))
  chk(!identical(segb, paste(src[i_c0:i_c1], collapse = "\n")) && is.null(errm) && !length(envm$.BUD),
      "G4 돌연변이 — .cur 를 격자 상향 값으로 두면 entry 예산 기록이 사라진다(원장 게이트 = 파일 35 → B4 마지막 칸 거부 · red 재현)")
  ## 승계 순서 스위치 — 같은 절이 tick 당 1회 해석(.axio) · 무효값은 기본 + 로그(조용한 통과 없음)
  eo1 <- run_budget(list(base_id = "T_IO1", status = "active", attempts = list(AB5), attempts_used = 1L, max_attempts = 44L), 35L)
  eo2 <- run_budget(list(base_id = "T_IO2", status = "active", attempts = list(AB5), attempts_used = 1L, max_attempts = 44L), 35L,
                    cfg = list(spec_axes = list(inherit_order = list("carry", "floor"))))
  eo3 <- run_budget(list(base_id = "T_IO3", status = "active", attempts = list(AB5), attempts_used = 1L, max_attempts = 44L), 35L,
                    cfg = list(spec_axes = list(inherit_order = list("floor", "zzz"))))
  lg3 <- .logs(eo3, "spec_axes_inherit_order_invalid")
  chk(is.null(eo1$.err) && identical(eo1$.axio$order, c("floor", "carry")) && identical(eo1$.axio$source, "default") && !length(.logs(eo1, "spec_axes_inherit_order_invalid")) &&
      is.null(eo2$.err) && identical(eo2$.axio$order, c("carry", "floor")) && identical(eo2$.axio$source, "config") &&
      is.null(eo3$.err) && identical(eo3$.axio$order, c("floor", "carry")) && !isTRUE(eo3$.axio$valid) && length(lg3) == 1L,
      "G5 승계 순서 스위치(러너 절 추출 실행) — 부재 = floor > carry · config [carry, floor] 채택 · 어휘 밖 = 기본 + 로그 1줄",
      paste(eo1$.err %||% "", eo2$.err %||% "", eo3$.err %||% "", length(lg3)))
}
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

cat("\n=== H. 배선 (AST — 호출·리터럴) ===\n")
ex <- parse(RUNNER, encoding = "UTF-8", keep.source = FALSE)
calls <- unique(all.names(ex))   # 파스 트리의 이름(함수 호출 이름 포함 · 주석 제외)
need <- c("rf_axes_accumulate", "rf_axes_carry_fill", "rf_axes_b4_assemble", "rf_axes_block_winners", "rf_axes_combo_cells",
          "rf_axes_combo_frozen", "rf_axes_no_layer_blocks", "rf_axes_grid_contract", "rf_budget_base", "rf_axes_diag_mode", "rf_control_codes",
          "rf_axes_inherit_order", "rf_axes_cell_init", "rf_axes_same_as_carry")
chk(all(need %in% calls) && any(grepl("order = rf_axes_inherit_order(get0(\"CFG\", ifnotfound = list()))$order", src, fixed = TRUE)),
    "H1 러너가 등록부 함수 14종을 부른다(누적·carry 병합·B4 조립·승자·재도출·동결·overlay_cell·계약·예산·모드·대조 코드·승계 순서·셀 초기값·무처치) · carry 병합이 해석된 순서를 쓴다",
    paste(setdiff(need, calls), collapse = ","))
code <- sub("#.*$", "", src)
lit <- c('B6 = "rebalance"', 'B7 = "defense_sleeve"', 'CELL$block %in% c("B1", "B2", "B3")', '.w5_overlay', 'w2$weighting', 'w3$universe',
         '!is.null(E$carry$weighting)) SPEC$weighting', 'defense_sleeve = CELL[["defense_sleeve"]]', '.same_axis(SPEC[["defense_sleeve"]], E$carry',
         'weighting = CELL$weighting %||%')
left <- lit[vapply(lit, function(p) any(grepl(p, code, fixed = TRUE)), logical(1))]
chk(!length(left), "H2 구판 축 목록 리터럴 제거(누적 switch · overlay_cell 블록 목록 · B4 w2/w3/w5 · carry 병합 세 줄 · 셀 초기값 네 축 · 무처치 여섯 줄)", paste(left, collapse = " | "))

cat(sprintf('{"test":"rf_spec_axes","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
unlink(TMPD, recursive = TRUE, force = TRUE)
quit(status = if (FAIL > 0L) 1L else 0L)
