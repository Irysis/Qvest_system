#==============================================================================
# test_fdb_state_gate.R — 월 팩터 DB 빌드의 상태 기준 게이트 상설 검사 (W-05)
#
# 왜 있나 (2026-09-23 도훈 승인 "상태 기준 게이트로 수리"):
#   구판 update_factor_db_daily() 는 build_sig <- today 였다. 스케줄(00:03)은 그날
#   종가가 RAWDATA 에 들어오기 전이라 말일 00:03 빌드가 전일 데이터를 말일 날짜로
#   라벨링했고(factor_db_202608 = 08-31 라벨 · 08-28 데이터), 익월 1일엔 ym 이 바뀌어
#   전월을 다시 보지 않았다 — 전월 스냅샷이 영구히 미완. 09-30·10-01 에 재발 예정이었다.
#
# 구조:
#   A. 계획 함수 시나리오 — 09-30/10-01/10-02 스케줄 · 레거시 202608 · 미래 라벨 ·
#      신선도 · 공휴일 말일 (양성 대조 + 위반 주입)
#   B. 데이터 경계 가드 — build_factor_db 가 쓰는 술어 그대로
#   C. 실행 E2E — 스텁 빌더로 상태 파일·IC 호출·실패 시 상태 파일 무잔존
#   D. 검사력 — 같은 시나리오를 git HEAD 의 구판 함수에 걸면 red 여야 한다
#   E. 돌연변이 — 직전 달 확정 줄을 지우면 A 의 확정 단정이 red 여야 한다
#   F. 배선 — build_factor_db 가 가드를 로드 직후·사이드카를 저장 직후 부른다
#
# 단독 실행: Rscript 08_Tests/factor_db/test_fdb_state_gate.R
# 배터리   : 08_Tests/hooks/run_all_hooks.sh (SUITES 배열)
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite); library(arrow) })

.resolve_proj <- function() {
  cands <- c(Sys.getenv("CLAUDE_PROJECT_DIR", unset = ""),
             Sys.getenv("QM_ROOT", unset = ""),
             "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
  cands <- gsub("\\\\", "/", cands[nzchar(cands)])
  marker <- "02_Infrastructure/factor_db/factor_db_builder.R"
  hit <- cands[file.exists(file.path(cands, marker))]
  if (length(hit) == 0L) stop("project root 미발견 — CLAUDE_PROJECT_DIR 설정 필요")
  hit[1]
}
PROJ <- .resolve_proj()
BUILDER <- file.path(PROJ, "02_Infrastructure/factor_db/factor_db_builder.R")

N_PASS <- 0L; N_FAIL <- 0L
chk <- function(id, cond, msg = "") {
  if (isTRUE(cond)) { N_PASS <<- N_PASS + 1L; cat(sprintf("  PASS %s\n", id)) }
  else { N_FAIL <<- N_FAIL + 1L; cat(sprintf("  FAIL %s %s\n", id, msg)) }
}

NEED <- c(".fdb_gap_months", ".fdb_asof_path", ".fdb_write_asof", ".fdb_read_asof",
          ".fdb_assert_sig_within_data", ".fdb_snap_date", ".fdb_last_weekday",
          ".fdb_update_plan", "update_factor_db_daily")
# 빌더 전체를 source 하지 않는다(설정·모듈 적재) — 필요한 정의만 파스해 격리 환경에 올린다.
load_defs <- function(lines, names_wanted, env) {
  ex <- parse(text = lines, keep.source = FALSE, encoding = "UTF-8")
  got <- character(0)
  for (e in ex) {
    if (is.call(e) && identical(e[[1]], as.name("<-")) && is.name(e[[2]]) &&
        as.character(e[[2]]) %in% names_wanted) {
      eval(e, env); got <- c(got, as.character(e[[2]]))
    }
  }
  got
}
SRC <- sub("\r$", "", readLines(BUILDER, encoding = "UTF-8", warn = FALSE))
mk_env <- function(lines = SRC, wanted = NEED) {
  env <- new.env(parent = globalenv())
  got <- load_defs(lines, wanted, env)
  env$.GOT <- got
  env
}
E <- mk_env()
chk("F0_defs_loaded", setequal(E$.GOT, NEED), paste(setdiff(NEED, E$.GOT), collapse = ","))

TMP <- file.path(tempdir(), sprintf("fdb_gate_%d", Sys.getpid()))
new_dir <- function(tag) { d <- file.path(TMP, tag); unlink(d, recursive = TRUE); dir.create(d, recursive = TRUE); d }
mkfile <- function(dir, ym, d)
  write_parquet(data.table(Date = as.Date(d), Ticker = c("A000001", "A000002"),
                           Factor_Name = "X", Raw_Value = 1), file.path(dir, sprintf("factor_db_%s.parquet", ym)))
mkasof <- function(env, dir, ym, d, asof) env$.fdb_write_asof(ym, d, d, asof, fdb_dir = dir)

wk <- function(a, b, drop = character(0)) {
  x <- seq(as.Date(a), as.Date(b), by = "day")
  x <- x[!(as.POSIXlt(x)$wday %in% c(0L, 6L))]
  x[!(format(x) %in% drop)]
}
CHUSEOK <- c("2026-09-24", "2026-09-25")
RAW_TO <- function(end, drop = CHUSEOK) wk("2026-07-01", end, drop)

plan_of <- function(env, raw, dir, as_of) env$.fdb_update_plan(raw, fdb_dir = dir, as_of = as.Date(as_of))
has <- function(pl, ym, sig, reason_pat = ".")
  any(pl$plan$ym == ym & pl$plan$sig == as.Date(sig) & grepl(reason_pat, pl$plan$reason))

# 정상 기저: 202607·202608 확정, 202609 는 09-22 스냅샷
base_dir <- function(env, tag) {
  d <- new_dir(tag)
  mkfile(d, "202607", "2026-07-31"); mkasof(env, d, "202607", "2026-07-31", "2026-08-03")
  mkfile(d, "202608", "2026-08-31"); mkasof(env, d, "202608", "2026-08-31", "2026-09-01")
  mkfile(d, "202609", "2026-09-22"); mkasof(env, d, "202609", "2026-09-22", "2026-09-22")
  d
}

run_A <- function(env, label = "") {
  res <- list()
  # A1 — 09-30 00:03: RAWDATA 는 09-29 까지. 구판은 sig=09-30 으로 빌드했다.
  d <- base_dir(env, "a1"); p <- plan_of(env, RAW_TO("2026-09-29"), d, "2026-09-30")
  res$A1_no_future_sig <- all(p$plan$sig <= as.Date("2026-09-29")) && p$raw_d == as.Date("2026-09-29")
  res$A1_no_build_needed <- nrow(p$plan) == 0L
  # A2 — 10-01 00:03: RAWDATA 09-30 도착. 202609 를 09-30 으로 확정, 202610 은 만들지 않는다.
  d <- base_dir(env, "a2"); p <- plan_of(env, RAW_TO("2026-09-30"), d, "2026-10-01")
  res$A2_final_sep <- has(p, "202609", "2026-09-30", "current_month_final") && isTRUE(p$ic_refresh)
  res$A2_no_oct <- !any(p$plan$ym == "202610")
  # A3 — 10-02 00:03, 10-01 실행 누락: 202609 확정 + 202610 신규
  d <- base_dir(env, "a3"); p <- plan_of(env, RAW_TO("2026-10-01"), d, "2026-10-02")
  res$A3_finalize_sep <- has(p, "202609", "2026-09-30", "^finalize_snap")
  res$A3_new_oct <- has(p, "202610", "2026-10-01", "current_missing")
  # A4 — 확정 뒤 정상 진행: 202609(asof 09-30) 재빌드 없음, IC 도 없음
  d <- base_dir(env, "a4"); mkfile(d, "202609", "2026-09-30"); mkasof(env, d, "202609", "2026-09-30", "2026-09-30")
  p <- plan_of(env, RAW_TO("2026-10-01"), d, "2026-10-02")
  res$A4_steady <- !any(p$plan$ym == "202609") && has(p, "202610", "2026-10-01") && !isTRUE(p$ic_refresh)
  # A5 — 레거시 202608(08-31 라벨): 사이드카 부재 / data_asof 08-28 → 확정 재빌드, asof 충분 → 없음
  d <- base_dir(env, "a5"); unlink(env$.fdb_asof_path("202608", d))
  p <- plan_of(env, RAW_TO("2026-09-23"), d, "2026-09-24")
  res$A5_no_asof <- has(p, "202608", "2026-08-31", "finalize_no_asof")
  mkasof(env, d, "202608", "2026-08-31", "2026-08-28"); p <- plan_of(env, RAW_TO("2026-09-23"), d, "2026-09-24")
  res$A5_stale_asof <- has(p, "202608", "2026-08-31", "^finalize_asof")
  mkasof(env, d, "202608", "2026-08-31", "2026-09-22"); p <- plan_of(env, RAW_TO("2026-09-23"), d, "2026-09-24")
  res$A5_final_ok <- !any(p$plan$ym == "202608")
  # A6 — 미래 라벨(09-30 스냅샷인데 데이터는 09-29): 데이터 날짜로 교정
  d <- base_dir(env, "a6"); mkfile(d, "202609", "2026-09-30")
  p <- plan_of(env, RAW_TO("2026-09-29"), d, "2026-09-30")
  res$A6_future_label <- has(p, "202609", "2026-09-29", "current_future_label")
  # A7 — 주간 신선도: 9일 뒤처짐 → 재빌드, 6일 → 없음
  d <- base_dir(env, "a7"); mkfile(d, "202609", "2026-09-14")
  res$A7_stale <- has(plan_of(env, RAW_TO("2026-09-23"), d, "2026-09-24"), "202609", "2026-09-23", "current_stale")
  mkfile(d, "202609", "2026-09-17")
  res$A7_fresh <- nrow(plan_of(env, RAW_TO("2026-09-23"), d, "2026-09-24")$plan) == 0L
  # A8 — 공휴일 말일(09-30 휴장 가정): 09-29 는 말일 확정이 아니고, 익월 데이터 도착 시 09-29 로 확정
  d <- base_dir(env, "a8"); drop <- c(CHUSEOK, "2026-09-30")
  p <- plan_of(env, RAW_TO("2026-09-29", drop), d, "2026-09-30")
  res$A8_not_final_early <- nrow(p$plan) == 0L
  p <- plan_of(env, RAW_TO("2026-10-01", drop), d, "2026-10-02")
  res$A8_finalize_on_next <- has(p, "202609", "2026-09-29", "^finalize_snap")
  # A9 — gap: 202608 파일이 없으면 그 달 마지막 거래일로 채운다(경계 = 데이터)
  d <- base_dir(env, "a9"); unlink(file.path(d, "factor_db_202608.parquet")); unlink(file.path(d, "factor_db_202609.parquet"))
  p <- plan_of(env, RAW_TO("2026-09-23"), d, "2026-09-24")
  res$A9_gap <- has(p, "202608", "2026-08-31", "gap") && has(p, "202609", "2026-09-23", "current_missing")
  # A10 — 달력 today 는 판정에 쓰지 않는다(RAWDATA 가 멈춘 날: 계획 동일 + 경고)
  d <- base_dir(env, "a10")
  p1 <- plan_of(env, RAW_TO("2026-09-23"), d, "2026-09-24"); p2 <- plan_of(env, RAW_TO("2026-09-23"), d, "2026-10-05")
  res$A10_today_invariant <- identical(p1$plan, p2$plan) && !is.na(p2$warn) && is.na(p1$warn)
  res
}

cat("[A] 계획 함수 시나리오\n")
RA <- run_A(E)
for (k in names(RA)) chk(k, RA[[k]])

cat("[B] 데이터 경계 가드\n")
chk("B1_future_sig_rejected", inherits(tryCatch(E$.fdb_assert_sig_within_data("2026-09-30", as.Date("2026-09-29")),
                                                error = function(e) e), "error"))
chk("B2_boundary_ok", isTRUE(E$.fdb_assert_sig_within_data("2026-09-29", as.Date("2026-09-29"))))
chk("B3_unreadable_max_rejected", inherits(tryCatch(E$.fdb_assert_sig_within_data("2026-09-29", -Inf),
                                                    error = function(e) e), "error"))
chk("B4_last_weekday", E$.fdb_last_weekday(as.Date("2026-10-15")) == as.Date("2026-10-30") &&
      E$.fdb_last_weekday(as.Date("2026-09-01")) == as.Date("2026-09-30"))
d <- new_dir("b5"); dir.create(file.path(d, "_asof")); writeLines("{not json", E$.fdb_asof_path("202609", d))
chk("B5_corrupt_asof_is_null", is.null(E$.fdb_read_asof("202609", d)))

cat("[C] 실행 E2E (스텁 빌더)\n")
CALLS <- list(); IC_N <- 0L
stub_build <- function(raw) function(sig, save = TRUE, force = FALSE) {
  E$.fdb_assert_sig_within_data(sig, max(raw))           # 실제 빌더와 같은 가드
  ym <- format(as.Date(sig), "%Y%m")
  mkfile(CUR_DIR, ym, sig); E$.fdb_write_asof(ym, sig, sig, max(raw), fdb_dir = CUR_DIR)
  CALLS[[length(CALLS) + 1L]] <<- list(ym = ym, sig = as.Date(sig), force = force)
  invisible(NULL)
}
stub_ic <- function() IC_N <<- IC_N + 1L
CUR_DIR <- base_dir(E, "c1"); raw <- RAW_TO("2026-09-30")
st <- file.path(CUR_DIR, "_asof", "_last_update.txt"); writeLines(c("raw_ym=199901", "built=199901"), st)
out <- capture.output(r <- E$update_factor_db_daily(raw_dates = raw, build_fn = stub_build(raw), ic_fn = stub_ic,
                                                    fdb_dir = CUR_DIR, as_of = as.Date("2026-10-01")))
S <- readLines(st)
chk("C1_built_and_state", identical(r$built, "202609") && "raw_ym=202609" %in% S && "built=202609" %in% S &&
      IC_N == 1L && length(CALLS) == 1L && CALLS[[1]]$sig == as.Date("2026-09-30") && isTRUE(CALLS[[1]]$force),
    paste(S, collapse = " | "))
chk("C2_sidecar_after_build", E$.fdb_read_asof("202609", CUR_DIR)$data_asof == as.Date("2026-09-30"))
# 재실행은 아무것도 하지 않는다(멱등)
CALLS <- list(); IC_N <- 0L
out <- capture.output(r2 <- E$update_factor_db_daily(raw_dates = raw, build_fn = stub_build(raw), ic_fn = stub_ic,
                                                     fdb_dir = CUR_DIR, as_of = as.Date("2026-10-01")))
chk("C3_idempotent", length(CALLS) == 0L && IC_N == 0L && "built=" %in% readLines(st))
# 빌드가 죽으면: 상태 파일엔 built 가 비고(어제 값 잔존 금지), IC 도 부르지 않는다
CUR_DIR <- base_dir(E, "c4"); st4 <- file.path(CUR_DIR, "_asof", "_last_update.txt")
writeLines(c("raw_ym=202609", "built=202609"), st4); IC_N <- 0L
out <- capture.output(E$update_factor_db_daily(raw_dates = raw, build_fn = function(...) stop("boom"),
                                               ic_fn = stub_ic, fdb_dir = CUR_DIR, as_of = as.Date("2026-10-01")))
S4 <- readLines(st4)
chk("C4_failed_build_not_reported_as_built", "built=" %in% S4 && IC_N == 0L && any(grepl("\\[ERROR\\] 202609", out)),
    paste(S4, collapse = " | "))

cat("[D] 검사력 — 수리 이전 구판(커밋 100314c30)에 같은 시나리오\n")
# ★HEAD 가 아니라 수리 직전 커밋에 고정한다 — 자동 커밋(20:28)이 진행 중이던 수리를 HEAD 에
#   담자 'HEAD = 구판' 전제가 조용히 사라졌다. 구판 판본은 역사라 움직이지 않는다.
OLD_REV <- "100314c30"
OLD <- tryCatch(suppressWarnings(system2("git", c("-C", shQuote(PROJ), "show",
                                 paste0(OLD_REV, ":02_Infrastructure/factor_db/factor_db_builder.R")),
                        stdout = TRUE, stderr = FALSE)), error = function(e) character(0))
OLD <- sub("\r$", "", OLD)
if (!any(grepl("build_sig       <- today", OLD, fixed = TRUE))) {
  N_FAIL <- N_FAIL + 1L
  cat(sprintf("  FAIL D0_old_revision_available — %s 구판 판독 불가(얕은 클론·git 부재) — 검사력 미측정\n", OLD_REV))
} else {
  OE <- mk_env(OLD, c(".fdb_gap_months", "update_factor_db_daily"))
  old_run <- function(today, raw, dir) {
    OE$Sys.Date <- function() as.Date(today)
    OE$FACTOR_DB_DIR <- dir
    rp <- file.path(dir, "raw.parquet"); write_parquet(data.table(Date = raw), rp); OE$RAWDATA_CACHE <- rp
    calls <- list()
    OE$build_factor_db <- function(sig, save = TRUE, force = FALSE) {
      calls[[length(calls) + 1L]] <<- list(ym = format(as.Date(sig), "%Y%m"), sig = as.Date(sig)); invisible(NULL) }
    OE$compute_all_factor_ic_monthly <- function() invisible(NULL)
    OE$.load_base_data <- function(...) invisible(NULL)
    OE$.fdb_env <- new.env(); OE$.fdb_env$trading_dates <- raw
    invisible(capture.output(OE$update_factor_db_daily()))
    calls
  }
  c1 <- old_run("2026-09-30", RAW_TO("2026-09-29"), base_dir(E, "d1"))
  chk("D1_old_code_builds_future_label", any(vapply(c1, function(x) x$sig > as.Date("2026-09-29"), logical(1))),
      "구판이 09-30 00:03 에 데이터 없는 09-30 라벨을 빌드해야 검사가 결함을 잡는다는 증거")
  c2 <- old_run("2026-10-01", RAW_TO("2026-09-30"), base_dir(E, "d2"))
  chk("D2_old_code_misses_sep_final", !any(vapply(c2, function(x) x$ym == "202609" && x$sig == as.Date("2026-09-30"), logical(1))),
      "구판은 10-01 에 202609 를 09-30 으로 확정하지 않는다")
}

cat("[E] 돌연변이 — 직전 달 확정 줄 제거\n")
MUT <- SRC[!grepl("if (!is.na(why)) add(P_ym, P_td, TRUE, why)", SRC, fixed = TRUE)]
chk("E0_mutation_applied", length(MUT) == length(SRC) - 1L)
ME <- mk_env(MUT)
RM <- run_A(ME)
chk("E1_mutant_red", !isTRUE(RM$A3_finalize_sep) && !isTRUE(RM$A5_no_asof) && !isTRUE(RM$A8_finalize_on_next),
    "확정 줄이 없으면 A3·A5·A8 이 red 여야 한다")

cat("[F] 배선 — build_factor_db\n")
bf_expr <- parse(text = paste(SRC[grep("^build_factor_db <- function", SRC):length(SRC)], collapse = "\n"),
                 n = 1L, keep.source = FALSE)[[1]][[3]]
bf <- paste(deparse(body(eval(bf_expr))), collapse = "\n")
i_load <- regexpr(".load_base_data()", bf, fixed = TRUE); i_guard <- regexpr(".fdb_assert_sig_within_data(", bf, fixed = TRUE)
i_mod  <- regexpr(".preload_modules()", bf, fixed = TRUE)
i_save <- regexpr("write_parquet(result, out_path)", bf, fixed = TRUE); i_asof <- regexpr(".fdb_write_asof(", bf, fixed = TRUE)
chk("F1_guard_after_load_before_compute", i_load > 0 && i_guard > i_load && i_mod > i_guard)
chk("F2_sidecar_after_save", i_save > 0 && i_asof > i_save)
DR <- sub("\r$", "", readLines(file.path(PROJ, "02_Infrastructure/data/daily_refresh.sh"), encoding = "UTF-8", warn = FALSE))
chk("F3_gate_reads_build_state", any(grepl("_asof/_last_update.txt", DR, fixed = TRUE)) &&
      !any(grepl('^_eg_ym="\\$\\(date \\+%Y%m\\)"$', DR)))

unlink(TMP, recursive = TRUE)
cat(sprintf("\n[test_fdb_state_gate] %d PASS / %d FAIL\n", N_PASS, N_FAIL))
if (N_FAIL > 0L) quit(status = 1L)
