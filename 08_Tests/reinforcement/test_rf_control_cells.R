#!/usr/bin/env Rscript
#==============================================================================
# test_rf_control_cells.R — P1-06 통제 칸(carry 재현 B1_0 · null-factor 희석 B1_N*) **양방향 검사** (2026-09-25)
#
# 재는 것 (판정은 정본 rf_runner_gates.R 순수 함수 · 배선은 러너 블록을 소스에서 추출해 실행 · 부작용은 스텁 · tempdir 만 쓴다):
#   A 격자 정본 — 통제 칸 형식 · 코드 유일/격자·설계 코드와 불충돌 · seed 서로 다름 · null ≥ 2(rf_prereg_se_null 최소) ·
#     칸 수 = parallel_cells − 1 · E3 허용오차 = floor v2 설정 F1p.e3_tolerance(단일 수치 두 자리 패리티) · B5 상주 소비자 무영향
#   B 삽입 판정(rf_control_plan) — carry entry 첫 B1 삽입 · carry 없음 · B1 선측정(중간 삽입 금지) · 시도 존재(항상) · inactive · 형식 오류 ·
#     seed 중복 · 격자 코드 충돌 · B1 머리 삽입 · 픽커 자리 보존
#   C 제외 술어 — rf_is_control(코드·스펙 두 통로) · rf_candidate_facts/keep(control_cell) · rf_promote_best · rf_a_eligibility(always-on) ·
#     rf_lineage_measured(exclude_codes · 기본값 = 구판) — 각 항목에 '빼지 않으면 통제 칸이 뽑힌다' 양성 대조
#   D 러너 배선 추출 실행 — ①격자·예산 블록: 통제 칸 B1 머리 · 예산 +5 · carry 없으면 로그·예산 불변
#     ②등록 루프(스텁 원장·커버리지): 통제 칸은 측정 job 이 된다(무처치·서명 dedup·전 entry 커버리지 면제) ·
#     ★돌연변이: 면제를 지우면 재현 칸이 '측정 0회'로 닫히고 E3 가 red(unmeasured_terminal · inherited) — 무처치 면제·dedup 면제 각각
#   E E3(rf_carry_replay_check) — pass · 같은 판본 불일치 fail · 계열 불일치 fail · 판본 다름(공통 창 동일/다름) · fail_spec(carry 축 소실) ·
#     문서화 변환(유니버스 리셋) · 규약 다름 · 미측정 종결 · 승계 · 부재 · 설정 부재
#   F rf_carry_base_resolve — 재현 PT 우선 · red 면 부모 기록 · 재현 없으면 rf_carry_base_info 와 비트 동일
#   G rf_null_dilution_values — ok · 미측정 · 규약 혼합 · 판본 불일치 · 승계 NA · 부분집합 인자 없음 · (rf_prereg.R 있으면) SE 사슬
#   H 엔진 null_perm — 결정론 · seed 민감 · 접두 안정(PIT) · 접두 안정(종목 교체 · H4b 2026-09-26) · 전역 난수 복원 · seed 부재 = 측정 무효 · detect_lookahead CLEAN
#   I 알림층 — 축포(통제 칸 제외 · 돌연변이 통제) · 블록 L-code(최고·직전 최고에서 제외 · 통제 줄)
# 부작용 없음: 운영 원장·로그·설정 무접촉. 모든 쓰기는 tempdir() 아래(루트 밖).
#==============================================================================
suppressMessages({ library(jsonlite); library(data.table) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
PASS <- 0L; FAIL <- 0L; SKIPS <- list()
ok <- function(m) { PASS <<- PASS + 1L; cat("  OK  ", m, "\n") }
ng <- function(m, why = "") { FAIL <<- FAIL + 1L; why <- paste(as.character(unlist(why)), collapse = " ")
  cat("  FAIL", m, if (length(why) && nzchar(why)) paste0(" — ", why) else "", "\n") }
skip <- function(axis, reason, missing) { SKIPS[[length(SKIPS) + 1L]] <<- list(axis = axis, reason = reason, missing = missing)
  cat("  SKIP", axis, "—", reason, "\n") }
TMPD <- file.path(tempdir(), sprintf("rf_ctl_%d", Sys.getpid())); dir.create(TMPD, recursive = TRUE, showWarnings = FALSE)
if (startsWith(normalizePath(TMPD, winslash = "/", mustWork = FALSE), normalizePath(ROOT, winslash = "/", mustWork = FALSE)))
  stop("tempdir 가 루트 안이다 — 쓰기 격리 불가")
invisible(capture.output(suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_spec_sig.R")))))
invisible(capture.output(suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_block_design.R")))))
invisible(capture.output(suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_runner_gates.R")))))
invisible(capture.output(suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_promote.R")))))
RUNNER <- file.path(ROOT, "02_Infrastructure/ops/reinforce_auto_parallel.R")
src <- readLines(RUNNER, warn = FALSE, encoding = "UTF-8")
.first_after <- function(i0, re) { if (is.na(i0)) return(NA_integer_); k <- which(grepl(re, src[(i0 + 1L):length(src)]))[1]; if (is.na(k)) NA_integer_ else i0 + k }
.mkenv <- function() { env <- new.env(parent = globalenv()); env$.LOG <- list()
  env$jlog <- function(event, ...) env$.LOG[[length(env$.LOG) + 1L]] <- c(list(event = event), list(...)); env }
.ev_of <- function(env) vapply(env$.LOG, function(z) as.character(z$event), character(1))
.logs  <- function(env, ev) Filter(function(z) identical(as.character(z$event), ev), env$.LOG)
wj <- function(x, p) { dir.create(dirname(p), recursive = TRUE, showWarnings = FALSE); write(toJSON(x, auto_unbox = TRUE, pretty = TRUE, null = "null", digits = NA), p); p }

PROG <- fromJSON(file.path(ROOT, "06_Registry/reinforce_program.json"), simplifyVector = FALSE)
CTL <- rfbd_control_cells(ROOT)
CODES <- vapply(CTL, function(x) as.character(x$code), character(1))
RC <- Filter(function(x) identical(x$control, "carry_replay"), CTL)
NC <- Filter(function(x) identical(x$control, "null_factor"), CTL)

cat("=== A. 격자 정본 (reinforce_program.json standing_cells[control]) ===\n")
if (length(RC) == 1L && length(NC) >= 2L && !anyDuplicated(CODES) && all(startsWith(CODES, "B1_")))
  ok(sprintf("A1 통제 칸 %d개 — carry_replay 1 · null_factor %d(≥2 = rf_prereg_se_null 최소) · 코드 유일 · B1_ 접두", length(CTL), length(NC))) else
  ng("A1 통제 칸 형식", paste(CODES, collapse = ","))
gcodes <- unlist(lapply(PROG$blocks, function(b) vapply(b$cells, function(c) as.character(c$code), character(1))))
design_like <- grepl("^B1_[1-9][0-9]*$", CODES)
if (!length(intersect(CODES, gcodes)) && !any(design_like))
  ok("A2 통제 코드는 격자 칸·B1 설계 코드(sprintf('B1_%d', 1..))와 겹치지 않는다") else ng("A2 코드 충돌", paste(intersect(CODES, gcodes), CODES[design_like]))
seeds <- vapply(NC, function(x) suppressWarnings(as.integer(x$seed %||% NA)), integer(1))
if (all(!is.na(seeds)) && !anyDuplicated(seeds)) ok("A3 null seed 정수 · 서로 다름") else ng("A3 seed", paste(seeds, collapse = ","))
CFGA <- tryCatch(fromJSON(file.path(ROOT, "06_Registry/reinforce_auto_config.json"), simplifyVector = FALSE), error = function(e) list())
npar <- suppressWarnings(as.integer(CFGA$parallel_cells %||% NA))
if (is.finite(npar) && identical(length(CTL), npar)) ok(sprintf("A4 통제 칸 수 %d = parallel_cells(%d) — 통제 배치 1개", length(CTL), npar)) else
  ng("A4 칸 수 ≠ parallel_cells(설정이 바뀌었으면 도훈 결정으로 재보정)", paste(length(CTL), npar))
tol <- suppressWarnings(as.numeric(RC[[1]]$e3$tolerance %||% NA))
fv <- tryCatch(fromJSON(file.path(ROOT, "06_Registry/prereg/reference_floors_v2.config.json"), simplifyVector = FALSE), error = function(e) NULL)
if (is.null(fv)) skip("A5", "floor v2 설정 부재 — 허용오차 패리티 미대조", "06_Registry/prereg/reference_floors_v2.config.json") else {
  ftol <- suppressWarnings(as.numeric(fv$floors$F1p$e3_tolerance %||% NA))
  if (is.finite(tol) && is.finite(ftol) && identical(tol, ftol)) ok(sprintf("A5 E3 허용오차 %g = floor v2 F1p.e3_tolerance(두 자리 패리티)", tol)) else ng("A5 허용오차 불일치", paste(tol, ftol))
}
std <- rfbd_standing_cells(ROOT)
if (length(std) >= 1L && all(vapply(std, function(x) is.null(x$control), logical(1))) && identical(as.character(std[[1]]$code), "B5_31") &&
    !length(intersect(rfbd_standing_picks(ROOT), CODES)))
  ok("A6 rfbd_standing_cells 는 통제 칸을 돌려주지 않는다 — B5 상주 소비자(러너 B5 루프·상주 pick·기전 지도·B5 설계 프롬프트) 무영향") else ng("A6 상주 목록 오염")
## ★B4-SIX-AXIS(2026-09-26): 코드 판독기는 standing 통제(CODES) ∪ 격자 블록 대조 칸(B7_40·B7_41 — 같은 control 태그 · rfbd_grid_control_cells)을 돌려준다.
GCODES <- vapply(rfbd_grid_control_cells(ROOT), function(x) as.character(x$code), character(1))
if (setequal(rfbd_control_codes(ROOT), c(CODES, GCODES)) && setequal(rf_control_codes(ROOT), c(CODES, GCODES)) && !length(intersect(CODES, GCODES)))
  ok(sprintf("A7 rfbd_control_codes = rf_control_codes = standing 통제 %d + 격자 대조 %d(%s)", length(CODES), length(GCODES), paste(GCODES, collapse = ","))) else ng("A7 코드 판독기")

cat("\n=== B. 삽입 판정 (rf_control_plan · 순수) ===\n")
CAR <- list(factors = list(list(kind = "db", id = "F_A")), weighting = list(kind = "ew"), universe = list(kind = "k200_kq150"))
att <- function(code, n = 1L, pt = 1, spec = NULL, extra = list()) c(list(n = as.integer(n), cell_code = code,
  essence = list(cell_code = code, port_t = pt, spec = spec %||% "")), extra)
gridB1 <- lapply(sprintf("B1_%d", 1:5), function(cd) list(code = cd, label = cd, block = "B1", axis = "multifactor"))
gridB2 <- lapply(sprintf("B2_%d", 6:10), function(cd) list(code = cd, label = cd, block = "B2", axis = "weighting"))
G <- c(gridB1, gridB2)
p1 <- rf_control_plan(list(carry = CAR, attempts = list()), CTL, G)
if (length(p1$cells) == length(CTL) && all(vapply(p1$cells, function(z) z$.reason, "") == "carry_entry_first_b1") && !length(p1$skipped))
  ok("B1 carry entry · 시도 0 → 통제 칸 전부 삽입(carry_entry_first_b1)") else ng("B1 삽입", paste(length(p1$cells), length(p1$skipped)))
p2 <- rf_control_plan(list(carry = NULL, attempts = list()), CTL, G)
if (!length(p2$cells) && all(vapply(p2$skipped, function(z) z$reason, "") == "no_carry")) ok("B2 carry 없음(기저 entry) → 0칸 · 사유 no_carry") else ng("B2 carry 없음")
p3 <- rf_control_plan(list(carry = CAR, attempts = list(att("B1_1"))), CTL, G)
if (!length(p3$cells) && all(vapply(p3$skipped, function(z) z$reason, "") == "b1_measured_before_controls"))
  ok("B3 통제 없이 B1 이 이미 측정됨 → 중간 삽입 금지(b1_measured_before_controls)") else ng("B3 중간 삽입")
CTLi <- lapply(CTL, function(x) { x$active <- FALSE; x })
p4 <- rf_control_plan(list(carry = CAR, attempts = list(att(CODES[1]), att("B1_1", 2L))), CTLi, G)
if (length(p4$cells) == 1L && identical(p4$cells[[1]]$code, CODES[1]) && identical(p4$cells[[1]]$.reason, "attempt_exists") &&
    all(vapply(p4$skipped, function(z) z$reason, "") == "inactive"))
  ok("B4 시도가 있는 통제 칸은 inactive 여도 얹는다(재개·커서 일관) · 나머지는 inactive") else ng("B4 시도 존재")
bad <- c(CTL, list(list(code = "B1_X", block = "B1", control = "weird"), list(code = "B2_9Z", block = "B2", control = "null_factor", seed = 9),
                   list(code = "B1_N9", block = "B1", control = "null_factor", active = TRUE, applies_to = "carry_present"),
                   list(code = "B1_N8", block = "B1", control = "null_factor", active = TRUE, applies_to = "carry_present", seed = seeds[1]),
                   list(code = "B1_1", block = "B1", control = "null_factor", active = TRUE, applies_to = "carry_present", seed = 77L)))
p5 <- rf_control_plan(list(carry = CAR, attempts = list()), bad, G)
rs <- setNames(vapply(p5$skipped, function(z) z$reason, ""), vapply(p5$skipped, function(z) z$code, ""))
if (identical(unname(rs[c("B1_X", "B2_9Z", "B1_N9", "B1_N8", "B1_1")]),
              c("control_malformed", "control_block_not_b1", "null_seed_missing", "null_seed_duplicate", "control_code_collides_with_grid")) &&
    length(p5$cells) == length(CTL))
  ok("B5 형식 거부 5종(종류·블록·seed 부재·seed 중복·격자 코드 충돌) — 정상 칸은 그대로") else ng("B5 형식 거부", paste(names(rs), rs, collapse = ";"))
ins <- rf_control_insert(G, p1$cells)
cds <- vapply(ins, function(c) c$code, "")
if (identical(cds[seq_along(CODES)], CODES) && identical(cds[length(CODES) + 1L], "B1_1") && !any(vapply(ins, function(c) !is.null(c$.reason), TRUE)))
  ok("B6 B1 머리 삽입 · 판정 사유(.reason)는 셀에서 떼어낸다") else ng("B6 삽입 위치", paste(cds, collapse = ","))
ins2 <- rf_control_insert(gridB2, p1$cells)
if (identical(vapply(ins2, function(c) c$code, "")[seq_along(CODES)], CODES)) ok("B7 B1 칸이 없으면 맨 앞") else ng("B7")
rc1 <- rf_control_cell(RC[[1]]); nc1 <- rf_control_cell(NC[[1]])
if (!length(rc1$factors) && identical(nc1$factors[[1]]$kind, "null_perm") && identical(as.integer(nc1$factors[[1]]$seed), seeds[1]) &&
    isTRUE(rc1$standing) && isTRUE(nc1$standing) && rf_control_exempt(rc1) && rf_control_exempt(nc1) && !rf_control_exempt(gridB1[[1]]) &&
    identical(rf_batch_open_slots(c(p1$cells[1:2], gridB1[1:2])), c(3L, 4L)))
  ok("B8 셀 모양 — 재현 = 팩터 0 · null = null_perm(seed) · standing(회피 면제·픽커 자리 보존) · control 면제 술어") else ng("B8 셀 모양")

cat("\n=== C. 제외 술어 ===\n")
CTX <- rf_runner_ctx(ROOT, regime = "close_t1")
sp_ok <- wj(list(code = "X", factors = list(list(kind = "db", id = "F_B")), universe = list(kind = "k200_kq150")), file.path(TMPD, "sp_ok.json"))
sp_ctl <- wj(list(code = "Z9_9", control = "carry_replay", factors = list(), universe = list(kind = "k200_kq150")), file.path(TMPD, "sp_ctl.json"))
mr <- list(exec_price = "close_t1")
aR <- att("B1_1", 1L, 2.0, sp_ok, list(measurement_regime = mr)); aR$essence$window_deviation_months <- 0
aC <- att(CODES[1], 2L, 3.0, sp_ok, list(measurement_regime = mr)); aC$essence$window_deviation_months <- 0
aS <- att("B1_7", 3L, 3.5, sp_ctl, list(measurement_regime = mr)); aS$essence$window_deviation_months <- 0
if (rf_is_control(aC, CTX) && rf_is_control(aS, CTX) && !rf_is_control(aR, CTX))
  ok("C1 rf_is_control — 코드 통로(B1_0) · 스펙 통로(control 필드 · 코드가 격자에 없어도) · 정규 칸 FALSE") else ng("C1 판별")
fC <- rf_candidate_facts(aC, CTX, "regime"); fR <- rf_candidate_facts(aR, CTX, "regime")
if (identical(fC$fail, "control_cell") && !length(fR$fail)) ok("C2 rf_candidate_facts — 통제 칸 control_cell(역할 축 무관) · 정규 칸 통과") else ng("C2", paste(fC$fail, fR$fail))
env <- .mkenv()
kept <- rf_candidates_keep(list(aR, aC, aS), CTX, role = "winner_B1", log = env$jlog, base_id = "T")
lg <- .logs(env, "candidates_excluded")
if (length(kept) == 1L && identical(kept[[1]]$cell_code, "B1_1") && length(lg) == 1L && grepl("control_cell=2", lg[[1]]$by_reason))
  ok("C3 rf_candidates_keep — 통제 2칸 제외 · 로그 by_reason control_cell=2(조용한 제외 없음)") else ng("C3", length(kept))
pts <- vapply(list(aR, aC, aS), function(a) a$essence$port_t, 1)
if (which.max(pts) != 1L) ok("C4 양성 대조 — 제외가 없으면 argmax 는 통제 칸(PT 3.5)을 고른다") else ng("C4 대조 설계")
Eprom <- list(base_id = "T_PROM", carry = CAR, attempts = list(aR, aC, aS))
pb <- rf_promote_best(Eprom, CTX)
if (identical(pb$i, 1L) && all(grepl("control_cell", pb$excluded))) ok("C5 rf_promote_best — 통제 칸은 승격 best 가 아니다(부모 PT 가 더 높아도)") else ng("C5 승격 best", paste(pb$i, paste(pb$excluded, collapse = ",")))
el <- rf_a_eligibility(list(carry = CAR), aC, NULL, rf_a_ctx(CTX, list(), "T"))
elR <- rf_a_eligibility(list(carry = CAR), aR, NULL, rf_a_ctx(CTX, list(), "T"))
if (!isTRUE(el$eligible) && "control_cell" %in% el$codes && !("control_cell" %in% elR$fired) && !("control_cell" %in% RF_A_HOLD_CODES))
  ok("C6 rf_a_eligibility — 통제 칸 always-on 보류 control_cell(설정 집합 밖 · 끌 수 없다) · 정규 칸 미발화") else ng("C6 A 관문", paste(el$codes, collapse = "+"))
Gz <- rf_a_gate_config(ROOT); Gz$active[] <- FALSE
elz <- rf_a_eligibility(list(carry = CAR), aC, NULL, rf_a_ctx(CTX, list(), "T", gate = Gz))
if ("control_cell" %in% elz$codes) ok("C7 보류 코드 전부 off 여도 control_cell 은 발행을 막는다") else ng("C7 always-on")
ents <- list(list(base_id = "L1", attempts = list(aR, aC, att(CODES[2], 3L, 1.5), att("B1_2", 4L, NA))))
n0 <- rf_lineage_measured(ents, "L1"); n1 <- rf_lineage_measured(ents, "L1", exclude_codes = CODES)
if (identical(n0, 3) && identical(n1, 1)) ok("C8 rf_lineage_measured — 기본값 = 구판(3칸 · 통제 포함) · exclude_codes = 통제 2칸 제외(1칸)") else ng("C8 N", paste(n0, n1))

cat("\n=== D. 러너 배선 — 추출 실행 ===\n")
## D-① 격자·예산 블록 (cells <- … ~ } else MAXA <- .cur)
i_c0 <- grep("^cells <- do\\.call\\(c, lapply\\(PROG\\$blocks", src)[1]
i_c1 <- grep("^\\} else MAXA <- \\.cur$", src)[1]
mk_root <- function(tag, prog) {
  R0 <- file.path(TMPD, paste0("bud_", tag)); unlink(R0, recursive = TRUE, force = TRUE)
  for (dd in c("02_Infrastructure/ops", "02_Infrastructure/reinforcement", "06_Registry", ".cache/rf_b1_design", ".cache/rf_block_design"))
    dir.create(file.path(R0, dd), recursive = TRUE, showWarnings = FALSE)
  file.copy(file.path(ROOT, "02_Infrastructure/ops/rf_b1_design_lib.R"), file.path(R0, "02_Infrastructure/ops/"), overwrite = TRUE)
  for (f in c("rf_block_design.R", "rf_runner_gates.R", "rf_spec_sig.R"))
    file.copy(file.path(ROOT, "02_Infrastructure/reinforcement", f), file.path(R0, "02_Infrastructure/reinforcement/"), overwrite = TRUE)
  wj(prog, file.path(R0, "06_Registry/reinforce_program.json"))
  wj(list(arms = list(list(id = "pg2_risk_overlay_v1", kind = "pg2_risk_overlay", status = "active", basis = "b"))), file.path(R0, "06_Registry/overlay_catalog.json"))
  R0
}
blk <- function(id, axis, codes) list(id = id, axis = axis, n = length(codes), cells = lapply(codes, function(cd) list(code = cd, label = cd)))
mk_prog <- function(ctl = TRUE) {
  p <- list(schema = "reinforce_program_v1",
            blocks = list(blk("B1", "multifactor", sprintf("B1_%d", 1:5)), blk("B2", "weighting", sprintf("B2_%d", 6:10)),
                          blk("B3", "universe", sprintf("B3_%d", 11:15)), blk("B5", "risk_overlay", sprintf("B5_%d", 16:20)),
                          blk("B4", "combination", sprintf("B4_%d", 21:25))),
            standing_cells = c(list(list(code = "B5_31", block = "B5", label = "상주", overlay_pick = "pg2_risk_overlay_v1")), if (ctl) CTL else list()))
  p
}
run_budget <- function(R0, E, prog) {
  env <- .mkenv(); env$ROOT <- R0; env$BID <- E$base_id; env$E <- E; env$led <- list(max_attempts = 25L)
  env$PROG <- fromJSON(as.character(toJSON(prog, auto_unbox = TRUE, null = "null")), simplifyVector = FALSE)
  env$MAXA <- as.integer(E$max_attempts %||% 25L); env$.BUD <- list()
  env$rf_record_entry_budget <- function(layer, base_id, max_attempts, reason, root) { env$.BUD[[length(env$.BUD) + 1L]] <- as.integer(max_attempts); invisible(max_attempts) }
  old_rr <- Sys.getenv("QVEST_RF_ROOT", unset = NA); owd <- getwd(); Sys.setenv(QVEST_RF_ROOT = R0)
  on.exit({ setwd(owd); if (is.na(old_rr)) Sys.unsetenv("QVEST_RF_ROOT") else Sys.setenv(QVEST_RF_ROOT = old_rr) }, add = TRUE)
  env$.err <- tryCatch({ invisible(capture.output(eval(parse(text = paste(src[i_c0:i_c1], collapse = "\n")), envir = env))); NULL },
                       error = function(e) conditionMessage(e))
  env
}
if (is.na(i_c0) || is.na(i_c1) || i_c1 <= i_c0) ng("D1 격자·예산 블록 추출 실패", paste(i_c0, i_c1)) else {
  RA <- mk_root("ctl", mk_prog(TRUE))
  ea <- run_budget(RA, list(base_id = "T_CTL_promo1", status = "active", carry = CAR, attempts = list()), mk_prog(TRUE))
  cda <- vapply(ea$cells, function(c) as.character(c$code), "")
  li <- .logs(ea, "control_cells_inserted")
  if (is.null(ea$.err) && identical(cda[seq_along(CODES)], CODES) && identical(as.integer(ea$.auto), 25L + 1L + length(CODES)) &&
      length(li) == 1L && identical(as.integer(li[[1]]$n), length(CODES)) && identical(as.integer(ea$.n_standing_inserted), 1L + length(CODES)))
    ok(sprintf("D1 carry entry — 통제 %d칸 B1 머리 · 예산 %d = 25 + 상주 B5_31 1(B5 측정 전) + 통제 %d · 로그 1줄", length(CODES), ea$.auto, length(CODES))) else
    ng("D1 통제 삽입·예산", paste(ea$.err %||% "", paste(cda[1:6], collapse = ","), ea$.auto, ea$.n_standing_inserted))
  eb <- run_budget(RA, list(base_id = "T_CTL_base", status = "active", attempts = list()), mk_prog(TRUE))
  if (is.null(eb$.err) && !any(grepl("^B1_(0|N)", vapply(eb$cells, function(c) as.character(c$code), ""))) &&
      !any(c("control_cells_inserted", "control_cells_skipped") %in% .ev_of(eb)) && identical(as.integer(eb$.auto), 26L))
    ok("D2 carry 없는 entry — 통제 칸 0 · 통제 로그 0(no_carry 는 적용 범위 밖) · 예산 26(상주 B5_31 만)") else ng("D2 기저 entry", paste(eb$.err %||% "", eb$.auto))
  ec <- run_budget(RA, list(base_id = "T_CTL_mid", status = "active", carry = CAR, attempts = list(att("B1_1"))), mk_prog(TRUE))
  sk <- .logs(ec, "control_cells_skipped")
  if (is.null(ec$.err) && length(sk) == 1L && identical(sk[[1]]$reasons, "b1_measured_before_controls") && identical(as.integer(ec$.auto), 26L))
    ok("D3 B1 선측정 carry entry — 삽입 0 · 건너뜀 1줄(b1_measured_before_controls) · 예산 불변") else ng("D3", paste(ec$.err %||% "", length(sk)))
  RN <- mk_root("noctl", mk_prog(FALSE))
  en <- run_budget(RN, list(base_id = "T_CTL_promo1", status = "active", carry = CAR, attempts = list()), mk_prog(FALSE))
  if (is.null(en$.err) && identical(as.integer(en$.auto), 26L) && !any(c("control_cells_inserted", "control_cells_skipped") %in% .ev_of(en)))
    ok("D4 돌연변이 통제 — 격자에 통제 칸이 없으면 삽입·로그 0 · 예산 26(구판과 같다)") else ng("D4", paste(en$.err %||% "", en$.auto))
}

## D-② 등록 루프 (.seen_sig <- list() ~ if (!length(jobs)) { 직전) — 스텁 원장·커버리지·기록
i_r0 <- grep("^\\.seen_sig <- list\\(\\)$", src)[1]
i_r1 <- grep("^if \\(!length\\(jobs\\)\\) \\{$", src)[1] - 1L
## ★B4-SIX-AXIS(2026-09-26): 추출 끝 = 배치 등록 루프 문장의 끝(파서 srcref). 다른 갈래가 루프 **뒤**에 붙인 문장(예: O0a 시행 로그 —
##   tick 상태 pending·first 참조)은 이 검사가 재는 등록 루프가 아니다 — 줄 앵커만 쓰면 그런 삽입마다 스텁 밖 변수로 추출 실행이 죽는다
##   (배포 순서 시뮬 B5FIX→CTRL→AXIS→HUMAN→CORE 최종판 실측: D5·D7·D9 object 'pending' not found).
if (!is.na(i_r0) && !is.na(i_r1)) i_r1 <- local({
  ex <- tryCatch(parse(text = src[i_r0:i_r1], keep.source = TRUE), error = function(e) NULL)
  if (is.null(ex)) i_r1 else {
    sr <- attr(ex, "srcref")
    k <- which(vapply(seq_along(ex), function(j) startsWith(deparse(ex[[j]])[1], "if (!length(jobs)) for (CELL in batch)"), logical(1)))
    if (length(k)) i_r0 + sr[[k[1]]][3] - 1L else i_r1 } })
i_bc0 <- grep("^\\.beats_carry <- function\\(w, tag\\) \\{$", src)[1]; i_bc1 <- .first_after(i_bc0, "^\\}$")
i_wf0 <- grep("^\\.win_factors <- function\\(w\\) \\{$", src)[1]; i_wf1 <- .first_after(i_wf0, "^\\}$")
RR <- file.path(TMPD, "reg_root")
for (dd in c("02_Infrastructure/ops", "02_Infrastructure/reinforcement", "06_Registry", "stage_artifacts/l_code/reinforcement", "wdir"))
  dir.create(file.path(RR, dd), recursive = TRUE, showWarnings = FALSE)
invisible(file.copy(file.path(ROOT, "06_Registry/reinforce_program.json"), file.path(RR, "06_Registry/"), overwrite = TRUE))
writeLines("rf_preflight <- function(SPEC, BID) SPEC", file.path(RR, "02_Infrastructure/ops/rf_preflight.R"))
run_reg <- function(seg_text, E, batch, parent_sig_prefix) {
  env <- .mkenv(); env$ROOT <- RR; env$BID <- E$base_id; env$E <- E; env$batch <- batch; env$jobs <- list()
  env$PROG <- PROG; env$WDIR <- file.path(RR, "wdir"); env$MAX_RETRY <- 2L
  env$led <- list(entries = list(E)); env$w1 <- NULL; env$w2 <- NULL; env$w3 <- NULL; env$.w5_overlay <- NULL
  env$.wbest_spec <- NULL; env$.wbest_src <- "none"; env$.wbest_code <- NA_character_; env$.carry_base <- NA_real_; env$.base_paper <- NULL
  env$.REC <- list(); env$.N <- 0L
  env$rf_append_attempt <- function(...) { env$.N <- env$.N + 1L; list(n = env$.N) }
  env$rf_record_result <- function(layer, bid, n, ...) { env$.REC[[length(env$.REC) + 1L]] <- c(list(n = n), list(...)); invisible(TRUE) }
  env$.append_fail_count <- function(code, bid) 0L
  env$.rac_gate_apply <- function(spec, sp, CELL, n, path) "run"
  env$rf_load <- function(layer, root) list(entries = list(E))
  env$.rf_find <- function(L, bid) NA_integer_
  env$rf_root_papers_for <- function(SPEC, base_paper = NULL, cell_paper = NULL, root = NULL) list(papers = list(), families = character(0), unmapped_families = character(0))
  env$.COVIDX <- "stub"
  env$rf_coverage_find <- function(sig, idx, exclude_base = NULL)
    if (startsWith(sig, parent_sig_prefix)) data.frame(base_id = "T_PARENT", cell_code = "B1_3", grade = "B") else data.frame()
  env$.err <- tryCatch({
    invisible(capture.output(eval(parse(text = paste(c(src[i_bc0:i_bc1], src[i_wf0:i_wf1]), collapse = "\n")), envir = env)))
    invisible(capture.output(eval(parse(text = seg_text), envir = env))); NULL }, error = function(e) conditionMessage(e))
  env
}
if (any(is.na(c(i_r0, i_r1, i_bc0, i_bc1, i_wf0, i_wf1)))) ng("D5 등록 루프 추출 실패", paste(i_r0, i_r1, i_bc0, i_wf0)) else {
  seg <- paste(src[i_r0:i_r1], collapse = "\n")
  EP <- list(base_id = "T_REG_promo1", status = "active", carry = CAR, parent = list(base_id = "T_PARENT", cell = "B1_3", best_port_t = 2.5), attempts = list())
  bat <- list(rf_control_cell(RC[[1]]), rf_control_cell(NC[[1]]), list(code = "B1_1", label = "reg", block = "B1", axis = "multifactor",
                                                                      factors = list(list(kind = "db", id = "F_B"))))
  carry_prefix <- "db:F_A|"   # 부모 칸(전 entry 커버리지)의 서명 = carry 그대로의 서명
  er <- run_reg(seg, EP, bat, carry_prefix)
  jc <- vapply(er$jobs, function(j) j$code, "")
  rc <- vapply(er$.REC, function(r) as.character(r$n), "")
  spec_rep <- tryCatch(fromJSON(er$jobs[[1]]$spec, simplifyVector = FALSE), error = function(e) NULL)
  spec_nul <- tryCatch(fromJSON(er$jobs[[2]]$spec, simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(er$.err) && identical(jc, c(RC[[1]]$code, NC[[1]]$code, "B1_1")) && !length(er$.REC) &&
      identical(spec_rep$control, "carry_replay") && identical(.fkeys(spec_rep$factors), "db:F_A") &&
      identical(.fkeys(spec_nul$factors), sort(c("db:F_A", sprintf("null_perm:null_perm_s%d", seeds[1])))) &&
      identical(as.integer(spec_nul$control_seed), seeds[1]))
    ok("D5 스테이징 러너 — 재현·null·정규 3칸 모두 측정 job · 종결 기록 0 · 재현 스펙 = carry · null = carry+null_perm · control 부기") else
    ng("D5 등록 루프", paste(er$.err %||% "", paste(jc, collapse = ","), length(er$.REC)))
  if (identical(.spec_sig(spec_rep), .spec_sig(c(list(code = "P"), spec_rep[setdiff(names(spec_rep), c("code", "control", "control_seed"))]))))
    ok("D6 control·control_seed 는 부기 필드 — .spec_sig 불변") else ng("D6 서명 오염")
  ## ★돌연변이 — 면제를 지운다(전부 / 무처치만 / dedup 만). 재현 칸이 측정 0회로 닫히면 E3 가 red 여야 한다.
  mut <- list(all = gsub("rf_control_exempt(CELL)", "FALSE", seg, fixed = TRUE),
              no_treat = sub("if (!is.null(E$carry) && !rf_control_exempt(CELL)) {", "if (!is.null(E$carry)) {", seg, fixed = TRUE),
              dedup = sub(".ctl_cell <- rf_control_exempt(CELL)", ".ctl_cell <- FALSE", seg, fixed = TRUE))
  for (mn in names(mut)) {
    if (identical(mut[[mn]], seg)) { ng(sprintf("D7 돌연변이 %s 가 소스에 적용되지 않았다(앵커 부재)", mn)); next }
    em <- run_reg(mut[[mn]], EP, bat, carry_prefix)
    jm <- vapply(em$jobs, function(j) j$code, "")
    r1 <- Filter(function(r) identical(as.integer(r$n), 1L), em$.REC)
    closed <- !(RC[[1]]$code %in% jm) && length(r1) == 1L && isTRUE(r1[[1]]$terminal)
    ## 닫힌 모양 그대로 원장 attempt 를 만들어 E3 에 넣는다 — 측정 0회 = red
    a_closed <- c(list(n = 1L, cell_code = RC[[1]]$code), if (length(r1)) list(grade = r1[[1]]$grade, terminal = TRUE, terminal_reason = r1[[1]]$terminal_reason,
                                                                             essence = r1[[1]]$essence) else list())
    e3m <- rf_carry_replay_check(list(carry = CAR, parent = EP$parent, attempts = list(a_closed)), list(), CTX)
    if (is.null(em$.err) && closed && isTRUE(e3m$red) && e3m$verdict %in% c("unmeasured_terminal", "inherited"))
      ok(sprintf("D7 돌연변이 %-8s — 재현 칸이 측정 0회로 닫힘(%s) → E3 red(%s)", mn, substr(r1[[1]]$terminal_reason %||% "", 1, 24), e3m$verdict)) else
      ng(sprintf("D7 돌연변이 %s", mn), paste(em$.err %||% "", paste(jm, collapse = ","), closed, e3m$verdict))
  }
  ## 승계 경로(같은 entry 중복 · cell_duplicate_inherited) — 면제가 없으면 재현 칸이 앞 칸 결과를 물려받는다 = inherited red
  a_inh <- list(n = 2L, cell_code = RC[[1]]$code, grade = "B", essence = list(cell_code = RC[[1]]$code, port_t = 2.5, inherited_from = "B1_3"))
  e3i <- rf_carry_replay_check(list(carry = CAR, parent = EP$parent, attempts = list(a_inh)), list(), CTX)
  if (isTRUE(e3i$red) && identical(e3i$verdict, "inherited")) ok("D8 승계로 닫힌 재현 칸(essence$inherited_from) → E3 red(inherited) — 공허 통과 금지") else ng("D8 승계", e3i$verdict)
  ## 정규 칸만의 배치는 스테이징 전후 같은 결과(통제 칸이 없으면 등록 루프는 구판 거동)
  bat2 <- list(list(code = "B1_1", label = "reg", block = "B1", axis = "multifactor", factors = list(list(kind = "db", id = "F_B"))),
               list(code = "B1_2", label = "nt", block = "B1", axis = "multifactor", factors = list(list(kind = "db", id = "F_A"))))
  e2 <- run_reg(seg, EP, bat2, carry_prefix); e2m <- run_reg(mut$all, EP, bat2, carry_prefix)
  s2 <- function(e) paste(c(vapply(e$jobs, function(j) j$code, ""), vapply(e$.REC, function(r) paste(r$n, r$grade), "")), collapse = "|")
  if (is.null(e2$.err) && identical(s2(e2), s2(e2m)) && grepl("무처치|carry 와 동일", paste(vapply(e2$.REC, function(r) r$grade %||% "", ""), collapse = " ")))
    ok("D9 통제 칸 없는 배치 — 면제 유무와 무관하게 같은 결과(B1_2 = carry 동일 → 무처치 종결 유지)") else ng("D9 정규 배치 패리티", paste(s2(e2), "vs", s2(e2m)))
}
## D-③ 정적 배선 — 순서·자리 (판정은 위 추출 실행이 한다 · 여기는 배선 존재)
code <- sub("#.*$", "", src)
at <- function(p) { i <- grep(p, code, fixed = TRUE); if (length(i)) i[1] else NA_integer_ }
w <- c(std_end = at('jlog("standing_cell_inserted"'), ctl = at("rf_control_plan(E, rfbd_control_cells(ROOT), cells)"),
       bud = at("rf_budget_auto(led$max_attempts"), carry = at(".carry_bi <- rf_carry_base_resolve(E, led$entries, .RCTX, base = .carry_bi)"),
       lin = at("rf_lineage_measured(led$entries, .lineage_ids, exclude_codes = rf_control_codes(ROOT))"),
       e3 = at('jlog("carry_replay_e3"'), tele = at('.blk_now <- if (!is.null(first))'))
if (!anyNA(w) && w[["std_end"]] < w[["ctl"]] && w[["ctl"]] < w[["bud"]] && w[["e3"]] < w[["tele"]])
  ok("D10 배선 순서 — B5 상주 루프 → 통제 삽입 → 예산 재도출 · 기준선 = rf_carry_base_resolve · N = exclude_codes · E3 기록은 수집 뒤·알림 앞") else
  ng("D10 배선", paste(names(w), w, collapse = " "))

## D-④ B1 규칙 픽커 블록 추출 실행 — 통제 칸 자리 보존(비상주 슬롯만) · 통제 칸뿐이면 픽커 미호출 · 돌연변이(전 슬롯 덮어쓰기) red
i_p0 <- grep("^\\.b1_slots <- if \\(length\\(batch\\)\\) rf_batch_open_slots\\(batch\\) else integer\\(0\\)$", src)[1]
i_pb <- grep('^if \\(length\\(batch\\) && identical\\(first\\$block, "B1"\\) && !length\\(\\.b1_design\\) && length\\(\\.b1_slots\\)\\) \\{$', src)[1]
i_p1 <- .first_after(i_pb, "^\\}$")
PR0 <- file.path(TMPD, "pick_root"); dir.create(file.path(PR0, "02_Infrastructure/ops"), recursive = TRUE, showWarnings = FALSE)
writeLines(c("rf_pick_factor_sets <- function(n, exclude = character(0), seed_offset = 0L, depths = NULL, fallback_paper = NULL, root = NULL) {",
             "  .PICKN <<- c(.PICKN, n)",
             "  list(cells = lapply(seq_len(n), function(i) list(code = 'grid', label = sprintf('%d팩터 직교(p%d)', 1L, i),",
             "                      factors = list(list(kind = 'db', id = sprintf('P%d', i))), selection_basis = 'asof_ic', selection_asof = '2005-01-01')),",
             "       picked_ids = sprintf('P%d', seq_len(n)), seed_id = 's', seed_offset = seed_offset, n_available = 10L, max_rho = 0,",
             "       substrate_asof = 'x', excluded_no_ic = list(), excluded_axis = list())",
             "}"), file.path(PR0, "02_Infrastructure/ops/rf_factor_arms.R"))
run_pick <- function(seg_text, batch) {
  env <- .mkenv(); env$batch <- batch; env$first <- batch[[1]]; env$.b1_design <- list(); env$ROOT <- PR0
  env$E <- list(attempts = list()); env$led <- list(entries = list()); env$PROG <- PROG; env$.base_paper <- NULL
  env$.err <- tryCatch({ invisible(capture.output(eval(parse(text = seg_text), envir = env))); NULL }, error = function(e) conditionMessage(e))
  env
}
if (any(is.na(c(i_p0, i_pb, i_p1))) || i_pb != i_p0 + 1L) ng("D11 B1 픽커 블록 추출 실패", paste(i_p0, i_pb, i_p1)) else {
  pseg <- paste(src[i_p0:i_p1], collapse = "\n")
  regc <- function(cd) list(code = cd, label = cd, block = "B1", axis = "multifactor")
  .PICKN <- integer(0)
  ep <- run_pick(pseg, list(rf_control_cell(RC[[1]]), rf_control_cell(NC[[1]]), regc("B1_1"), regc("B1_2")))
  cdp <- vapply(ep$batch, function(c) as.character(c$code), "")
  if (is.null(ep$.err) && identical(.PICKN, 2L) && identical(cdp, c(RC[[1]]$code, NC[[1]]$code, "B1_1", "B1_2")) &&
      identical(ep$batch[[1]], rf_control_cell(RC[[1]])) && identical(ep$batch[[2]], rf_control_cell(NC[[1]])) &&
      identical(ep$batch[[3]]$factors[[1]]$id, "P1") && identical(ep$batch[[4]]$selection_basis, "asof_ic"))
    ok("D11 B1 픽커 — 비상주 슬롯 2개만 요청 · 통제 칸은 모양 그대로 · 정규 칸만 픽으로 채움(코드 유지)") else
    ng("D11 B1 픽커", paste(ep$.err %||% "", paste(.PICKN, collapse = ","), paste(cdp, collapse = ",")))
  .PICKN <- integer(0)
  ep2 <- run_pick(pseg, list(rf_control_cell(RC[[1]]), rf_control_cell(NC[[1]])))
  if (is.null(ep2$.err) && !length(.PICKN) && !("factor_arms_fallback" %in% .ev_of(ep2)))
    ok("D12 통제 칸뿐인 배치 — 픽커 미호출 · 폴백(전표본 표식) 미발화") else ng("D12", paste(ep2$.err %||% "", length(.PICKN)))
  mseg <- sub(".b1_slots <- if (length(batch)) rf_batch_open_slots(batch) else integer(0)", ".b1_slots <- seq_along(batch)", pseg, fixed = TRUE)
  .PICKN <- integer(0)
  em <- run_pick(mseg, list(rf_control_cell(RC[[1]]), rf_control_cell(NC[[1]]), regc("B1_1"), regc("B1_2")))
  if (!identical(mseg, pseg) && is.null(em$.err) && identical(.PICKN, 4L) && is.null(em$batch[[1]]$control))
    ok("D13 돌연변이(전 슬롯 픽) — 통제 칸이 픽 셀로 덮여 control 표식이 사라진다(= 이 자리 보존이 방어선)") else ng("D13 돌연변이", paste(em$.err %||% "", paste(.PICKN, collapse = ",")))
}

## D14 B1 픽커 실패 폴백(격자 스냅샷 · 전표본 표식 부기) — 통제 칸에는 selection_basis 를 싣지 않는다(정규 칸만 full_sample_ic)
PR1 <- file.path(TMPD, "pick_root_fail"); dir.create(file.path(PR1, "02_Infrastructure/ops"), recursive = TRUE, showWarnings = FALSE)
writeLines("rf_pick_factor_sets <- function(...) list(cells = list())", file.path(PR1, "02_Infrastructure/ops/rf_factor_arms.R"))
if (!is.na(i_p0) && !is.na(i_p1)) {
  envf <- .mkenv(); envf$batch <- list(rf_control_cell(RC[[1]]), list(code = "B1_1", label = "reg", block = "B1", axis = "multifactor", basis = "x · substrate 2026-07-31"))
  envf$first <- envf$batch[[1]]; envf$.b1_design <- list(); envf$ROOT <- PR1; envf$E <- list(attempts = list()); envf$led <- list(entries = list())
  envf$PROG <- PROG; envf$.base_paper <- NULL
  envf$.err <- tryCatch({ invisible(capture.output(eval(parse(text = paste(src[i_p0:i_p1], collapse = "\n")), envir = envf))); NULL }, error = function(e) conditionMessage(e))
  if (is.null(envf$.err) && "factor_arms_fallback" %in% .ev_of(envf) && is.null(envf$batch[[1]]$selection_basis) &&
      identical(envf$batch[[2]]$selection_basis, "full_sample_ic") && identical(envf$batch[[2]]$selection_asof, "2026-07-31"))
    ok("D14 픽커 실패 폴백 — 정규 칸만 selection_basis=full_sample_ic(A 보류 표식) · 통제 칸은 표식 없음(격자 스냅샷 칸이 아니다)") else
    ng("D14 폴백 표식", paste(envf$.err %||% "", envf$batch[[1]]$selection_basis %||% "NULL", envf$batch[[2]]$selection_basis %||% "NULL"))
}

cat("\n=== E. E3 — rf_carry_replay_check ===\n")
mk_art <- function(tag, pt, snap = "snapshot_20260925", endd = "2026-09-24", dates = as.Date("2020-01-01") + 0:59, rets = NULL, holds = NULL,
                   exec = "close_t1", dv = NULL) {
  d <- file.path(TMPD, "art", tag); dir.create(d, recursive = TRUE, showWarnings = FALSE)
  rets <- rets %||% (sin(seq_along(dates)) / 100)
  holds <- holds %||% data.frame(date = rep(dates[c(1, 21, 41)], each = 3), ticker = rep(c("A", "B", "C"), 3), target_weight = 1 / 3)
  saveRDS(list(period_returns = data.frame(date = dates, ret_net = rets), holdings = holds), file.path(d, "bt_result.rds"))
  wj(list(data_snapshot_id = snap, end_date = endd), file.path(d, "00_manifest.json"))
  mrx <- list(exec_price = exec); if (!is.null(dv)) mrx$data_vintage <- dv
  wj(list(essence = list(portfolio_alpha_t_nw_lag3 = pt), measurement_regime = mrx, bt_result_path = file.path(d, "bt_result.rds")),
     file.path(d, "authoritative_remeasure.json"))
  d
}
spec_p <- list(factors = list(list(kind = "db", id = "F_A")), base_weight = 0.5, weighting = list(kind = "ew"),
               universe = list(kind = "k200_kq150"), base_signal = list(kind = "engine", path = "X/engine.R"))
.SPN <- 0L
mk_att <- function(code, n, pt, spec, art, exec = "close_t1", extra = list()) {
  .SPN <<- .SPN + 1L   # 스펙 경로는 호출마다 유일 — ctx 판독 캐시(spec|경로)가 앞 시나리오 내용을 돌려주지 않게
  sp <- wj(c(list(code = code), spec), file.path(TMPD, "spec", sprintf("%s_%s_%d_%d.json", code, basename(art), n, .SPN)))
  c(list(n = as.integer(n), cell_code = code, grade = "B", artifacts = art, measurement_regime = list(exec_price = exec),
         essence = list(cell_code = code, port_t = pt, spec = sp, window_deviation_months = 0)), extra)
}
PAR <- function(art, pt = 2.5, spec = spec_p, exec = "close_t1") list(base_id = "T_PAR", attempts = list(mk_att("B1_3", 3L, pt, spec, art, exec)))
CHILD <- function(rep_att, carry = CAR) list(base_id = "T_PAR_promo1", carry = carry, parent = list(base_id = "T_PAR", cell = "B1_3", best_port_t = 2.5),
                                              attempts = list(rep_att))
rcode <- RC[[1]]$code
aP <- mk_art("par", 2.5); aRp <- mk_art("rep_same", 2.5)
spec_r <- c(spec_p, list(control = "carry_replay"))
chk <- function(E, P, series = TRUE) rf_carry_replay_check(E, list(P), CTX, series = series)
e <- chk(CHILD(mk_att(rcode, 1L, 2.5, spec_r, aRp)), PAR(aP))
if (identical(e$verdict, "pass") && isTRUE(e$e3_strict) && isTRUE(e$e3_history) && isTRUE(e$use_as_carry_base) && !isTRUE(e$red))
  ok("E1 같은 규약·스펙·판본 · |ΔPT| 0 · 계열 동일 → pass(strict · history · 기준선 사용)") else ng("E1 pass", paste(e$verdict, paste(e$reasons, collapse = "|")))
e <- chk(CHILD(mk_att(rcode, 1L, 2.51, spec_r, mk_art("rep_pt", 2.51))), PAR(aP))
if (identical(e$verdict, "fail") && isTRUE(e$red) && !isTRUE(e$use_as_carry_base)) ok("E2 같은 판본인데 PT 차 0.01 → fail(red · 기준선 미사용)") else ng("E2", e$verdict)
aRs <- mk_art("rep_ser", 2.5, rets = sin(seq_len(60)) / 100 + c(rep(0, 59), 1e-3))
e <- chk(CHILD(mk_att(rcode, 1L, 2.5, spec_r, aRs)), PAR(aP)); e0 <- chk(CHILD(mk_att(rcode, 1L, 2.5, spec_r, aRs)), PAR(aP), series = FALSE)
if (identical(e$verdict, "fail") && isFALSE(e$e3_history) && identical(e0$verdict, "pass"))
  ok("E3 PT 는 같고(3자리) 일간 계열이 다르면 계열 대조가 fail 로 잡는다 · 계열 미대조(tick 경로)는 PT 만 본다") else ng("E3 계열", paste(e$verdict, e0$verdict))
aRx <- mk_art("rep_ext", 2.7, snap = "snapshot_20260926", endd = "2026-09-25", dates = as.Date("2020-01-01") + 0:69,
              rets = c(sin(1:60) / 100, rep(0.001, 10)))
e <- chk(CHILD(mk_att(rcode, 1L, 2.7, spec_r, aRx)), PAR(aP))
if (identical(e$verdict, "not_comparable") && isTRUE(e$e3_history) && isTRUE(e$use_as_carry_base) && is.na(e$e3_strict) &&
    identical(e$facts$series$dates, "a_extends_b"))
  ok("E4 판본 다름(다음 날 · 날짜 연장) · 공통 창 계열·보유 동일 → not_comparable · history TRUE · 기준선 사용") else ng("E4", paste(e$verdict, e$e3_history))
aRy <- mk_art("rep_rev", 2.7, snap = "snapshot_20260926", endd = "2026-09-25", dates = as.Date("2020-01-01") + 0:69,
              rets = c(sin(1:60) / 100 + 2e-3, rep(0.001, 10)))
e <- chk(CHILD(mk_att(rcode, 1L, 2.7, spec_r, aRy)), PAR(aP))
if (identical(e$verdict, "not_comparable") && isFALSE(e$e3_history) && !isTRUE(e$red))
  ok("E5 판본 다름 · 공통 창 계열 다름 → history FALSE(개정·누출·경로 차이 — 가르지 않고 사실만) · red 아님") else ng("E5", paste(e$verdict, e$e3_history))
spec_pr <- c(spec_p, list(rebalance = list(kind = "rank_buffer", mult = 2)))
e <- chk(CHILD(mk_att(rcode, 1L, 2.5, spec_r, aRp)), PAR(aP, spec = spec_pr))
if (identical(e$verdict, "fail_spec") && isTRUE(e$red) && identical(e$facts$spec_diff_axes, "rebalance") && !isTRUE(e$use_as_carry_base))
  ok("E6 부모 승자에 rebalance 가 있는데 재현(B1 조립 경로)에 없다 → fail_spec red(축 rebalance) — carry 축 소실 검출") else ng("E6 fail_spec", paste(e$verdict, e$facts$spec_diff_axes))
spec_pu <- modifyList(spec_p, list(universe = list(kind = "kq150")))
e <- chk(CHILD(mk_att(rcode, 1L, 2.2, spec_r, mk_art("rep_u", 2.2)), carry = c(CAR, list(universe_reset_from = list(kind = "kq150")))), PAR(aP, spec = spec_pu))
if (identical(e$verdict, "not_comparable") && identical(e$facts$documented_transforms, "universe") && isTRUE(e$use_as_carry_base) && !isTRUE(e$red))
  ok("E7 유니버스 리셋(carry universe_reset_from) = 문서화 변환 → not_comparable · 재현 PT 가 기준선") else ng("E7", paste(e$verdict, e$facts$documented_transforms))
e <- chk(CHILD(mk_att(rcode, 1L, 2.5, spec_r, aRp)), PAR(mk_art("par_leg", 2.5, exec = "close_d_legacy"), exec = "close_d_legacy"))
if (identical(e$verdict, "not_comparable") && isTRUE(e$use_as_carry_base) && grepl("규약 다름", paste(e$reasons, collapse = "")))
  ok("E8 부모 legacy 규약 · 재현 close_t1 → not_comparable · 재현 PT 가 현행 규약 기준선") else ng("E8", e$verdict)
e <- chk(CHILD(list(n = 1L, cell_code = rcode, terminal = TRUE, terminal_reason = "무처치(carry 동일)")), PAR(aP))
e2 <- chk(CHILD(list(n = 1L, cell_code = rcode)), PAR(aP))
e3 <- chk(list(carry = CAR, attempts = list()), PAR(aP))
if (identical(e$verdict, "unmeasured_terminal") && isTRUE(e$red) && identical(e2$verdict, "pending") && !isTRUE(e2$red) && identical(e3$verdict, "absent"))
  ok("E9 측정 없이 종결 = red · 등록만(재개 대상) = pending · 칸 없음 = absent") else ng("E9", paste(e$verdict, e2$verdict, e3$verdict))
cfgX <- .rfg_control_cfg(CTX); cfgX$cells <- lapply(cfgX$cells, function(x) { x$e3 <- NULL; x })
ex <- rf_carry_replay_check(CHILD(mk_att(rcode, 1L, 2.5, spec_r, aRp)), list(PAR(aP)), CTX, cfg = cfgX)
if (identical(ex$verdict, "config_missing") && !isTRUE(ex$use_as_carry_base)) ok("E10 e3.tolerance 부재 → config_missing(fail-closed · 판정·기준선 사용 안 함)") else ng("E10", ex$verdict)
e <- chk(CHILD(mk_att(rcode, 1L, 2.5, spec_r, mk_art("rep_fp", 2.5, dv = list(raw = list(size = 1, mtime = "t1"))))),
         PAR(mk_art("par_fp", 2.5, dv = list(raw = list(size = 1, mtime = "t0")))))
if (identical(e$verdict, "not_comparable") && identical(unname(e$facts$vintage_strength), c("file_stamp", "file_stamp")))
  ok("E11 재측정 판 data_vintage(파일 도장)가 다르면 같은 날이어도 판본 다름 — 약한 키(snapshot_day)보다 강한 키 우선") else ng("E11", e$verdict)

cat("\n=== F. carry 기준선 해석 — rf_carry_base_resolve ===\n")
P0 <- PAR(aP)
r <- rf_carry_base_resolve(CHILD(mk_att(rcode, 1L, 2.61, spec_r, mk_art("rep_f1", 2.61, snap = "snapshot_20260926", endd = "2026-09-25"))), list(P0), CTX)
if (identical(r$source, "replay") && identical(r$why, "ok") && isTRUE(abs(r$value - 2.61) < 1e-12) && identical(r$parent_value, 2.5))
  ok("F1 재현 칸이 서면 기준선 = 재현 PT(원장 값) · source replay · 부모 값은 parent_value 로 병기") else ng("F1", paste(r$source, r$value))
r <- rf_carry_base_resolve(CHILD(mk_att(rcode, 1L, 2.9, spec_r, aRp)), list(PAR(aP, spec = spec_pr)), CTX)
if (identical(r$source, "parent") && identical(r$e3_verdict, "fail_spec")) ok("F2 E3 red(fail_spec) → 부모 기록 경로(rf_carry_base_info) · 사유 병기") else ng("F2", paste(r$source, r$e3_verdict))
Enone <- CHILD(mk_att("B1_1", 1L, 2.0, spec_p, aRp)); b0 <- rf_carry_base_info(Enone, list(P0), CTX); b1 <- rf_carry_base_resolve(Enone, list(P0), CTX)
if (identical(b1$value, b0$value) && identical(b1$why, b0$why) && identical(b1$source, "parent") && identical(b1$e3_verdict, "absent"))
  ok("F3 재현 칸 없음 → rf_carry_base_info 와 값·사유 동일(구판 거동)") else ng("F3", paste(b0$value, b1$value))
Pl <- PAR(mk_art("par_leg2", 2.5, exec = "close_d_legacy"), exec = "close_d_legacy")
bi <- rf_carry_base_info(CHILD(mk_att(rcode, 1L, 2.3, spec_r, aRp)), list(Pl), CTX)
br <- rf_carry_base_resolve(CHILD(mk_att(rcode, 1L, 2.3, spec_r, aRp)), list(Pl), CTX)
if (!is.finite(bi$value) && identical(br$source, "replay") && isTRUE(abs(br$value - 2.3) < 1e-12))
  ok("F4 부모 legacy(구판: 기준선 NA · 게이트 무발화) → 재현 PT 2.3 이 현행 규약 기준선") else ng("F4", paste(bi$value, br$value))
if (!("rf_carry_base_resolve" %in% all.names(parse(file.path(ROOT, "02_Infrastructure/ops/reinforce_auto_next_paper.R"), keep.source = FALSE))))
  ok("F5 승격 판정(next_paper)은 여전히 rf_carry_base_info — live 승격 규칙 불변(안건)") else ng("F5 승격 규칙이 바뀌었다")

## F6 러너 기준선 블록 추출 실행(.carry_bi <- rf_carry_base_info( ~ .beats_carry 앞) — 재현 칸이 서면 러너의 .carry_base 가 재현 PT
i_cb0 <- grep("^\\.carry_bi <- rf_carry_base_info\\(E, led\\$entries, \\.RCTX\\)$", src); i_cb1 <- grep("^\\.beats_carry <- function", src)[1] - 1L
run_cb <- function(E, entries) { env <- .mkenv(); env$E <- E; env$led <- list(entries = entries); env$.RCTX <- CTX; env$BID <- E$base_id %||% "T"
  env$.err <- tryCatch({ invisible(capture.output(eval(parse(text = paste(src[i_cb0:i_cb1], collapse = "\n")), envir = env))); NULL }, error = function(e) conditionMessage(e)); env }
if (length(i_cb0) != 1L || is.na(i_cb1) || i_cb1 <= i_cb0) ng("F6 기준선 블록 추출 실패", paste(length(i_cb0), i_cb1)) else {
  f6a <- run_cb(CHILD(mk_att(rcode, 1L, 2.61, spec_r, mk_art("rep_f6", 2.61, snap = "snapshot_20260926", endd = "2026-09-25"))), list(P0))
  f6b <- run_cb(Enone, list(P0))
  if (is.null(f6a$.err) && isTRUE(abs(f6a$.carry_base - 2.61) < 1e-12) && is.null(f6b$.err) && identical(f6b$.carry_base, b0$value))
    ok("F6 러너 기준선 블록(추출 실행) — 재현 칸이 서면 .carry_base = 재현 PT 2.61 · 없으면 rf_carry_base_info 값 그대로") else
    ng("F6 러너 기준선", paste(f6a$.err %||% "", f6a$.carry_base, f6b$.err %||% "", f6b$.carry_base))
}

cat("\n=== G. null 희석 판독기 — rf_null_dilution_values ===\n")
mk_null_E <- function(vals, regs = NULL, snaps = NULL, inh = NULL) {
  at <- list(mk_att(rcode, 1L, 2.5, spec_r, mk_art("gn_rep", 2.5)))
  for (k in seq_along(NC)) {
    v <- vals[k]; if (is.na(v)) next
    a <- mk_att(NC[[k]]$code, k + 1L, v, spec_r, mk_art(sprintf("gn_%d_%s", k, snaps[k] %||% "s"), v, snap = snaps[k] %||% "snapshot_20260925",
                                                          exec = regs[k] %||% "close_t1"), exec = regs[k] %||% "close_t1")
    if (!is.null(inh) && isTRUE(inh[k])) a$essence$inherited_from <- "B1_3"
    at[[length(at) + 1L]] <- a
  }
  list(base_id = "T_NULL", carry = CAR, attempts = at)
}
vv <- 2.5 + c(-0.21, -0.05, -0.12, 0.03)[seq_along(NC)]
g <- rf_null_dilution_values(mk_null_E(vv), CTX, "port_t")
if (identical(g$status, "ok") && isTRUE(all.equal(unname(g$delta), vv - 2.5)) && identical(g$n_finite, length(NC)) && isTRUE(g$complete))
  ok(sprintf("G1 전부 측정 · 같은 규약·판본 → ok · delta = 값 − 재현(%d칸)", length(NC))) else ng("G1", paste(g$status, paste(g$reasons, collapse = "|")))
g2 <- rf_null_dilution_values(mk_null_E(replace(vv, 2, NA)), CTX, "port_t")
g3 <- rf_null_dilution_values(mk_null_E(vv, regs = c("close_t1", "close_d_legacy", "close_t1", "close_t1")), CTX, "port_t")
g4 <- rf_null_dilution_values(mk_null_E(vv, snaps = c("snapshot_20260925", "snapshot_20260926", "snapshot_20260925", "snapshot_20260925")), CTX, "port_t")
g5 <- rf_null_dilution_values(mk_null_E(vv, inh = c(FALSE, TRUE, FALSE, FALSE)), CTX, "port_t")
if (identical(g2$status, "incomplete") && identical(g3$status, "invalid") && identical(g4$status, "invalid") && identical(g5$status, "incomplete"))
  ok("G2 미측정 = incomplete · 규약 혼합 = invalid · 판본 불일치 = invalid · 승계 칸 = NA(incomplete) — 부분 SE 금지") else
  ng("G2", paste(g2$status, g3$status, g4$status, g5$status))
if (identical(names(formals(rf_null_dilution_values)), c("E", "ctx", "metric", "cfg")))
  ok("G3 부분집합 인자 없음(E · ctx · metric · cfg) — 격자의 active null 칸 전부를 읽는다(seed 쇼핑 경로 0)") else ng("G3 formals", paste(names(formals(rf_null_dilution_values)), collapse = ","))
PRE <- file.path(ROOT, "02_Infrastructure/reinforcement/rf_prereg.R")
if (!file.exists(PRE) || !file.exists(file.path(ROOT, "06_Registry/prereg/prereg_config.json"))) {
  skip("G4", "rf_prereg.R(P2-01) 미배포 — SE 사슬 대조 생략", "02_Infrastructure/reinforcement/rf_prereg.R")
} else {
  PR <- new.env(parent = globalenv())
  invisible(capture.output(suppressMessages(sys.source(PRE, envir = PR, keep.source = FALSE))))
  RT <- file.path(TMPD, "pre_root"); dir.create(file.path(RT, "02_Infrastructure"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(RT, "06_Registry/prereg"), recursive = TRUE, showWarnings = FALSE)
  file.copy(file.path(ROOT, "02_Infrastructure/config.R"), file.path(RT, "02_Infrastructure/"), overwrite = TRUE)
  file.copy(file.path(ROOT, "06_Registry/prereg/prereg_config.json"), file.path(RT, "06_Registry/prereg/"), overwrite = TRUE)
  se <- tryCatch(PR$rf_prereg_se_null(g$delta, root = RT), error = function(e) conditionMessage(e))
  cse <- tryCatch(PR$rf_prereg_combine_se(se_null = se$se, se_boot = se$se / 2, sources = c("null_dilution", "block_bootstrap"), root = RT),
                  error = function(e) conditionMessage(e))
  forb <- tryCatch({ PR$rf_prereg_combine_se(se_null = se$se, sources = "phase_pair", root = RT); "no_error" }, error = function(e) "stopped")
  art <- tryCatch(PR$rf_prereg_artifact(c(se, list(cells = g[c("codes", "seeds", "values", "delta", "replay", "artifacts")])), "PR-CTL-TEST", "port_t_null_se",
                                        measurement_regime = list(exec_price = "close_t1"), root = RT), error = function(e) conditionMessage(e))
  aj <- if (is.list(art)) tryCatch(fromJSON(file.path(RT, art$artifact), simplifyVector = FALSE), error = function(e) NULL) else NULL
  if (is.list(se) && isTRUE(abs(se$se - stats::sd(vv - 2.5)) < 1e-12) && identical(se$contract, "null_dilution") &&
      is.list(cse) && identical(cse$used, "null_dilution") && identical(forb, "stopped") &&
      !is.null(aj) && identical(aj$contract, "null_dilution") && isTRUE(abs(as.numeric(aj$se) - se$se) < 1e-12) &&
      identical(unlist(aj$cells$codes), g$codes))
    ok("G4 판독기 → rf_prereg_se_null(se = sd(delta)) → combine(max · 위상쌍 거부) → rf_prereg_artifact(null_dilution · 칸 출처 동봉) 사슬") else
    ng("G4 SE 사슬", paste(if (is.character(se)) se else "", if (is.character(cse)) cse else "", forb, if (is.character(art)) art else ""))
}

cat("\n=== H. 엔진 null_perm (rf_cell_engine.R) ===\n")
set.seed(20260925)
mk_raw <- function(end = as.Date("2007-12-31"), nT = 60L) {
  d <- seq(as.Date("2004-01-01"), end, by = "day"); d <- d[!(format(d, "%u") %in% c("6", "7"))]
  tk <- sprintf("T%03d", seq_len(nT))
  set.seed(7)
  X <- rbindlist(lapply(tk, function(t) { r <- stats::rnorm(length(d), 0, 0.02)
    data.table(Date = d, Ticker = t, Close = 10000 * exp(cumsum(r)), Vol = 1e6, K200 = TRUE, KQ150 = FALSE, Size = 1e12, Sector_Lv2 = "S") }))
  X
}
RAW_FULL <- mk_raw()
spec_e <- function(fs) list(code = "B1_N1", fixed_axes = PROG$fixed_axes, base_signal = list(kind = "mom_12_1"), base_weight = PROG$fixed_axes$base_weight,
                            factors = fs, weighting = list(kind = "ew"), universe = list(kind = "k200_kq150"))
run_engine <- function(spec, raw) {
  sp <- wj(spec, tempfile(tmpdir = TMPD, fileext = ".json"))
  env <- new.env(parent = globalenv()); env$RAWDATA <- data.table::copy(raw); env$BM_DT <- NULL
  old <- Sys.getenv("RF_CELL_SPEC", unset = NA); Sys.setenv(RF_CELL_SPEC = sp)
  on.exit(if (is.na(old)) Sys.unsetenv("RF_CELL_SPEC") else Sys.setenv(RF_CELL_SPEC = old), add = TRUE)
  err <- tryCatch({ invisible(capture.output(sys.source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_cell_engine.R"), envir = env))); NULL },
                  error = function(e) conditionMessage(e))
  list(err = err, F = if (exists("FACTORS", envir = env, inherits = FALSE)) data.table::copy(env$FACTORS) else NULL)
}
nf <- function(s) list(list(kind = "null_perm", id = sprintf("null_perm_s%d", s), seed = s))
set.seed(99); u_ref <- stats::runif(3)
set.seed(99); h1 <- run_engine(spec_e(nf(1L)), RAW_FULL); u_after <- stats::runif(3)
h1b <- run_engine(spec_e(nf(1L)), RAW_FULL)
h2 <- run_engine(spec_e(nf(2L)), RAW_FULL)
h0 <- run_engine(spec_e(list()), RAW_FULL)
key <- function(F) paste(F$Date, F$Ticker, round(F$Score, 12))
if (is.null(h1$err) && !is.null(h1$F) && nrow(h1$F) > 0 && identical(key(h1$F), key(h1b$F)))
  ok(sprintf("H1 결정론 — 같은 seed 두 번 = 비트 동일(FACTORS %d행)", nrow(h1$F))) else ng("H1", h1$err %||% "")
selset <- function(F) F[, paste(sort(Ticker), collapse = ","), by = Date]$V1
if (is.null(h2$err) && !identical(selset(h1$F), selset(h2$F)) && !identical(selset(h1$F), selset(h0$F)))
  ok("H2 seed 민감 · 무정보 팩터가 선정에 닿는다(seed 1 ≠ seed 2 ≠ 기저 단독 — 처치 전달)") else ng("H2", h2$err %||% "")
if (identical(u_ref, u_after)) ok("H3 전역 난수 상태 복원 — 엔진 뒤 runif 가 엔진 앞 seed 흐름과 같다") else ng("H3 난수 상태 오염")
hT <- run_engine(spec_e(nf(1L)), RAW_FULL[Date <= as.Date("2006-06-30")])
cmn <- h1$F[Date <= as.Date("2006-05-31")]; cmT <- hT$F[Date <= as.Date("2006-05-31")]
if (is.null(hT$err) && nrow(cmn) > 0 && identical(key(cmn), key(cmT)))
  ok("H4 접두 안정(PIT) — 뒤 데이터를 잘라도 과거 달의 null 점수·선정이 비트 동일(월별 seed = 시작일 대비 달 순번)") else ng("H4 접두", hT$err %||% "")
## H4b 접두 안정 — 종목 교체가 있는 픽스처(적대 검증 2026-09-26 추가). H4 픽스처는 60종이 전 기간 상장이라 '미래 종목 집합으로 순열'
##   (그 날짜 패널이 아니라 전 기간 종목 합집합) 돌연변이를 못 가른다 — 뒤에 상장한 T999(2006-01~ · mom_12_1 은 2007 부터 정의)를 넣는다.
##   양성 대조: T999 가 뒤 달 패널에 실재(전 기간 판의 2007 월 null 점수·선정이 T999 없는 판과 달라진다).
RAW_LATE <- data.table::copy(RAW_FULL[Ticker == "T001" & Date >= as.Date("2006-01-02")]); RAW_LATE[, Ticker := "T999"]
RAW_LATE <- rbind(RAW_FULL, RAW_LATE)
hL <- run_engine(spec_e(nf(1L)), RAW_LATE); hLT <- run_engine(spec_e(nf(1L)), RAW_LATE[Date <= as.Date("2006-06-30")])
cL <- if (is.null(hL$F)) NULL else hL$F[Date <= as.Date("2006-05-31")]; cLT <- if (is.null(hLT$F)) NULL else hLT$F[Date <= as.Date("2006-05-31")]
late_in <- !is.null(hL$F) && !is.null(h1$F) && !identical(key(hL$F[Date >= as.Date("2007-01-31")]), key(h1$F[Date >= as.Date("2007-01-31")]))
if (is.null(hL$err) && is.null(hLT$err) && late_in && length(cL) && nrow(cL) > 0 && identical(key(cL), key(cLT)))
  ok("H4b 접두 안정(PIT · 종목 교체) — 뒤에 상장한 종목이 있어도 과거 달 null 점수·선정 비트 동일(양성 대조: 그 종목이 2007 월 결과를 바꾼다)") else
  ng("H4b 접두(종목 교체)", paste(hL$err %||% "", hLT$err %||% "", "late_in=", late_in))
hE <- run_engine(spec_e(list(list(kind = "null_perm", id = "null_perm_sNA"))), RAW_FULL)
if (!is.null(hE$err) && grepl("측정 무효", hE$err)) ok("H5 seed 부재 → '측정 무효'(러너 구조적 종결 어휘) — 조용한 무작위 없음") else ng("H5", hE$err %||% "no error")
LD <- file.path(ROOT, "02_Infrastructure/validation/lookahead_detector.R")
if (!file.exists(LD)) skip("H6", "lookahead_detector.R 부재", LD) else {
  LE <- new.env(); invisible(capture.output(suppressMessages(sys.source(LD, envir = LE))))
  la <- tryCatch(LE$detect_lookahead(file.path(ROOT, "02_Infrastructure/reinforcement/rf_cell_engine.R"), verbose = FALSE), error = function(e) conditionMessage(e))
  clean <- is.list(la) && isTRUE(la$clean) && isTRUE(la$scanned)
  if (clean) ok("H6 detect_lookahead(rf_cell_engine.R) CLEAN — null_perm 분기가 C7 패턴에 안 걸린다") else ng("H6 lookahead", if (is.character(la)) la else toJSON(la, auto_unbox = TRUE))
}

cat("\n=== I. 알림층 — 축포 · 블록 L-code ===\n")
FAN <- file.path(ROOT, "02_Infrastructure/ops/rf_grade_fanfare.R")
FE <- new.env(); invisible(capture.output(suppressMessages(sys.source(FAN, envir = FE))))
Ef <- list(attempts = list(list(n = 1L, cell_code = rcode, grade = "B"), list(n = 2L, cell_code = "B1_1", grade = "C")))
Ef2 <- list(attempts = list(list(n = 1L, cell_code = rcode, grade = "B"), list(n = 2L, cell_code = "B1_1", grade = "B")))
bc <- c(CODES, "B1_1")
f1 <- FE$rf_fanfare_new_grade(Ef, bc, control_codes = CODES); f1m <- FE$rf_fanfare_new_grade(Ef, bc, control_codes = character(0))
f2 <- FE$rf_fanfare_new_grade(Ef2, bc, control_codes = CODES)
if (is.na(f1) && identical(f1m, "B") && identical(f2, "B"))
  ok("I1 축포 — 통제 칸 B 만이면 울리지 않는다(통제 제외를 끄면 울린다 = 돌연변이 통제) · 정규 칸 B 는 울린다") else ng("I1", paste(f1, f1m, f2))
LR <- file.path(TMPD, "lc_root")
for (dd in c("02_Infrastructure/ops", "02_Infrastructure/axiom", "02_Infrastructure/reinforcement", "06_Registry")) dir.create(file.path(LR, dd), recursive = TRUE, showWarnings = FALSE)
invisible(file.copy(file.path(ROOT, "02_Infrastructure/reinforcement/rf_block_design.R"), file.path(LR, "02_Infrastructure/reinforcement/"), overwrite = TRUE))
invisible(file.copy(file.path(ROOT, "06_Registry/reinforce_program.json"), file.path(LR, "06_Registry/"), overwrite = TRUE))
writeLines(c("library(data.table)",
             "rf_notify_table <- function(base_id) list(entry = list(base_id = base_id, block_order = c('B1', 'B2')), tab = .LC_TAB)",
             "rf_next_block <- function(entry, bid, prog, root = NULL) list(id = 'B2', src = 'grid')",
             "rf_insights <- function(blk) character(0)"), file.path(LR, "02_Infrastructure/ops/rf_auto_notify.R"))
writeLines("emit_lcode <- function(...) { .LC_CAP <<- list(...); list(l_code = 'L-TEST') }", file.path(LR, "02_Infrastructure/axiom/lcode_emit.R"))
.LC_TAB <- data.table(n = 1:7, code = c(CODES, "B1_1", "B1_2"), grade = c("B", rep("C", length(CODES) - 1L), "C", "C"),
                      port_t = c(3.1, 2.9, 1.2, 1.0, 0.9, 2.0, 1.5)[seq_len(length(CODES) + 2L)], inherited = FALSE,
                      sr = NA_real_, cagr = NA_real_, mdd = NA_real_, calmar = 0.3, oos = NA_real_)
LCF <- file.path(ROOT, "02_Infrastructure/ops/rf_block_lcode.R")
LCE <- new.env(parent = globalenv()); invisible(capture.output(suppressMessages(sys.source(LCF, envir = LCE))))
.LC_CAP <- NULL
invisible(capture.output(r <- tryCatch(LCE$rf_emit_block_lcode("T_LC", nrow(.LC_TAB), root = LR, dry_run = TRUE), error = function(e) conditionMessage(e))))
cap <- .LC_CAP
if (!is.null(cap) && grepl("최고 B1_1", cap$lesson_text) && !grepl(sprintf("최고 %s", rcode), cap$lesson_text) &&
    grepl("통제 칸(P1-06", cap$lesson_text, fixed = TRUE) && identical(as.numeric(cap$portfolio_alpha_t), 2.0) &&
    grepl("등급 A0/B0/C2/F0", cap$lesson_text, fixed = TRUE))
  ok("I2 블록 L-code — 최고·등급 집계에서 통제 칸 제외(최고 B1_1 2.0 · B 0) · 통제 줄 따로") else ng("I2 L-code", if (is.character(r)) r else substr(cap$lesson_text %||% "", 1, 200))

cat(sprintf('{"test":"rf_control_cells","pass":%d,"fail":%d,"skipped":%d,"total":%d,"skips":%s}\n', PASS, FAIL, length(SKIPS), PASS + FAIL,
            as.character(toJSON(SKIPS, auto_unbox = TRUE))))
unlink(TMPD, recursive = TRUE, force = TRUE)
quit(status = if (FAIL > 0L) 1L else 0L)
