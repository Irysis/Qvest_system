#==============================================================================
# test_inv13_beta_asof.R — INV13 beta 누산기 자체 계산 상설 검사 (DATA-INV13-ACC, 2026-09-24)
#
# 왜 있나:
#   compute_investor.R 의 INV13(Foreign_Resid_Individual 21d/63d/126d) beta 누산기가
#   .fdb_env$INV13_BETA_ACC(세션 메모리)에서 읽히고 없으면 0 에서 시작했다. 일일 증분 빌드는
#   세션당 1~2개월만 빌드하므로 누산 월수가 60 에 못 닿아 INV13 3종이 202608~ 영구 결손 —
#   tryCatch 가 삼켜 무경보였다. 반대로 60 을 넘긴 세션에서 과거 달을 다시 빌드하면 미래 달
#   증분이 beta 에 섞였다(잠재 C1). 수리 = .inv13_beta_asof(): sig 월 이전 월말들로부터 매 호출
#   자체 계산. 이 검사는 그 수리가 (1) 구판 저장값을 재현하고 (2) 세션·순서와 무관하며
#   (3) sig 월 이후 데이터를 보지 않고 (4) 돌연변이를 실제로 잡는지를 지킨다.
#
# ★허용오차 — 사전 선언(결과를 보기 전에 정함):
#   TOL_RAW  = 1e-8    저장 INV13 대비 max|ΔRaw_Value| (종목 집합·행 수는 완전 일치 요구)
#   TOL_BETA = 1e-12   참조 beta 대비 |Δβ|
#   TOL_SAME = 1e-12   같은 sig 재계산(세션 상태 교란·역순 빌드) 간 max|ΔRaw_Value|
# 참조 beta = 진단 재구성(월말 증분 누산 — 구판 저장 202606 INV13 을 R²=1.0000·잔차 sd≈2e-15 로
#   재현한 값): 202606 = -0.595292416327731 (증분 316개월) · 202607 = -0.597112707606409 (317)
#   ★투자자 패널 과거분이 개정되면 이 참조와 저장값이 함께 낡는다 — 그때 red 는 데이터 변경 신호다.
#
# 구조:
#   A. 양성 대조 — 새 세션 단독 1개월 빌드(202606)가 저장 INV13 3종을 재현 + 참조 beta 일치
#   B. 세션·순서 무관성 — 구판 누산기 쓰레기 주입 + 역순(202609 → 202606) 빌드가 A 와 동일
#   C. PIT(C1) — sig 월 첫날 이후 데이터 조작에 beta 불변 · 이전 달 조작엔 반응(민감도 대조)
#   D. 달력 계약 — 빌더 달력이 없으면 투자자 달력으로 대체하지 않는다 · 투자자 달력은 beta 가 어긋난다
#   M. 위반 주입 — a1 캐시 키 붕괴(as-of 단정이 막는다) · a2 키 붕괴+단정 해제(미래 달 증분 혼입
#                  → 202606 재현 실패) · a3 lag 이동(sig 월 증분 포함) · b 구판 n_months 게이트 부활
#                  (단독 빌드 0행)
#
# 데이터: 운영 .cache 를 **읽기만** 한다(mmap=FALSE). 쓰기 = R tempdir 의 돌연변이 소스뿐.
# 단독 실행: Rscript 08_Tests/factor_db/test_inv13_beta_asof.R   (약 2분 — 실데이터 10.5M행)
# 배터리   : 08_Tests/hooks/run_all_hooks.sh (SUITES 배열)
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })

.resolve_proj <- function() {
  cands <- c(Sys.getenv("CLAUDE_PROJECT_DIR", unset = ""),
             Sys.getenv("QM_ROOT", unset = ""),
             "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
  cands <- gsub("\\\\", "/", cands[nzchar(cands)])
  marker <- "02_Infrastructure/factor_db/compute_investor.R"
  hit <- cands[file.exists(file.path(cands, marker))]
  if (length(hit) == 0L) stop("project root 미발견 — CLAUDE_PROJECT_DIR 설정 필요")
  hit[1]
}
PROJ <- .resolve_proj()
setwd(PROJ)
CI_SRC <- "02_Infrastructure/factor_db/compute_investor.R"

TOL_RAW  <- 1e-8
TOL_BETA <- 1e-12
TOL_SAME <- 1e-12
REF_BETA <- c(`202606` = -0.595292416327731, `202607` = -0.597112707606409)
REF_N    <- c(`202606` = 316L, `202607` = 317L)
P_F <- c("INV13_Foreign_Resid_Individual_21d", "INV13_Foreign_Resid_Individual_63d",
         "INV13_Foreign_Resid_Individual_126d")

PASS <- 0L; FAIL <- 0L
ok  <- function(id, msg) { PASS <<- PASS + 1L; cat(sprintf("  [PASS] %-40s %s\n", id, msg)) }
bad <- function(id, msg) { FAIL <<- FAIL + 1L; cat(sprintf("  [FAIL] %-40s %s\n", id, msg)) }
finish <- function() {
  cat(sprintf("\nTOTAL: %d pass / %d fail\n", PASS, FAIL))
  cat(toJSON(list(test = "inv13_beta_asof", pass = PASS, fail = FAIL,
                  total = PASS + FAIL), auto_unbox = TRUE), "\n", sep = "")
  quit(save = "no", status = if (FAIL > 0L) 1L else 0L)
}

data_path <- function(rel) {
  cands <- c(file.path(PROJ, ".cache", rel), file.path("C:/qm_cache", rel))
  hit <- cands[file.exists(cands)]
  if (length(hit)) hit[1] else NA_character_
}
P_INV <- data_path("investor_stock/investor_wide.parquet")
P_RAW <- data_path("RAWDATA.parquet")
P_F06 <- data_path("factor_db/factor_db_202606.parquet")
if (anyNA(c(P_INV, P_RAW, P_F06))) {
  # ★건너뛰지 않는다 — 건너뛴 검사는 초록으로 보인다.
  bad("Z0_data_present", sprintf("실데이터 부재 — investor=%s RAWDATA=%s fdb202606=%s", P_INV, P_RAW, P_F06))
  finish()
}

#------------------------------------------------------------------------------
# 픽스처 — 빌더와 같은 형태로 .fdb_env 를 채운다(INVESTOR · trading_dates)
#------------------------------------------------------------------------------
INV_ALL <- as.data.table(read_parquet(P_INV, mmap = FALSE))
INV_ALL[, Date := as.Date(Date)]
RAWD <- as.data.table(read_parquet(P_RAW, col_select = c("Date", "Ticker", "Size"), mmap = FALSE))
RAWD[, Date := as.Date(Date)]
TD <- sort(unique(RAWD$Date))
ST06 <- as.data.table(read_parquet(P_F06, col_select = c("Ticker", "Factor_Name", "Raw_Value"),
                                   mmap = FALSE))[Factor_Name %in% P_F]

.fdb_env <- new.env(parent = emptyenv())
.fdb_env$INVESTOR <- INV_ALL
.fdb_env$trading_dates <- TD
reset_state <- function() {
  for (k in c("INV13_BETA_CACHE", "INV13_BETA_ACC"))
    if (exists(k, envir = .fdb_env, inherits = FALSE)) rm(list = k, envir = .fdb_env)
}

# compute_investor.R 를 (선택적으로 돌연변이시켜) 격리 env 에 로드. 치환 지점이 정확히 1곳이
# 아니면 NULL — 돌연변이를 못 걸면 검출력 실증도 없다.
load_ci <- function(muts = list()) {
  code <- sub("\r$", "", readLines(CI_SRC, warn = FALSE, encoding = "UTF-8"))
  for (m in muts) {
    i <- which(trimws(code) == trimws(m[[1]]))
    if (length(i) != 1L) return(NULL)
    code[i] <- m[[2]]
  }
  tf <- tempfile(fileext = ".R"); on.exit(unlink(tf), add = TRUE)
  writeLines(enc2utf8(code), tf, useBytes = TRUE)
  e <- new.env(parent = globalenv())
  sys.source(tf, envir = e, keep.source = FALSE, toplevel.env = e)
  e
}
with_warns <- function(expr) {
  w <- character(0)
  val <- withCallingHandlers(expr, warning = function(cnd) {
    w <<- c(w, conditionMessage(cnd)); invokeRestart("muffleWarning") })
  list(value = val, warns = w)
}
run_ci <- function(E, sig) {
  s <- as.Date(sig)
  with_warns(E$compute_investor(RAWD[Date <= s & Date >= s - 1400], s))
}
cmp_stored <- function(out) {
  rbindlist(lapply(P_F, function(f) {
    a <- ST06[Factor_Name == f]; b <- out[Factor_Name == f]
    m <- merge(a, b, by = "Ticker", suffixes = c(".st", ".new"))
    data.table(f = f, n_st = nrow(a), n_new = nrow(b),
               same_set = setequal(a$Ticker, b$Ticker),
               maxd = if (nrow(m)) max(abs(m$Raw_Value.st - m$Raw_Value.new)) else NA_real_)
  }))
}
stored_ok <- function(cs) all(cs$n_st == cs$n_new) && all(cs$same_set) &&
  all(is.finite(cs$maxd)) && all(cs$maxd <= TOL_RAW)
fmt_cs <- function(cs) paste(sprintf("%s:%d/%d max|d|=%.2g", sub(".*_", "", cs$f), cs$n_new, cs$n_st, cs$maxd),
                             collapse = " ")
max_same <- function(a, b) {
  x <- merge(a[Factor_Name %in% P_F], b[Factor_Name %in% P_F], by = c("Ticker", "Factor_Name"), all = TRUE)
  if (!nrow(x) || anyNA(x$Raw_Value.x) || anyNA(x$Raw_Value.y)) return(Inf)
  max(abs(x$Raw_Value.x - x$Raw_Value.y))
}
SIG06 <- as.Date("2026-06-30")
SIG07 <- as.Date("2026-07-31")
SIG09 <- max(TD[TD < as.Date("2026-10-01")])   # 202609 의 마지막 가용 거래일(월 진행 중이면 최신일)

CI <- load_ci()
if (is.null(CI)) { bad("Z1_source_loads", "compute_investor.R 로드 실패"); finish() }
if (!is.function(CI$.inv13_beta_asof)) {
  # 구판(세션 누산기) 코드면 헬퍼가 없다 — 크래시 대신 A1 만 재고 red 로 끝낸다.
  bad("Z2_helper_present", ".inv13_beta_asof 부재 — 세션 누산기 구판으로 보임")
  reset_state()
  A <- run_ci(CI, SIG06); csA <- cmp_stored(A$value)
  if (stored_ok(csA)) ok("A1_fresh_single_build_reproduces", fmt_cs(csA))
  else bad("A1_fresh_single_build_reproduces", sprintf("★재현 실패 — %s", fmt_cs(csA)))
  finish()
}

#==============================================================================
cat("\n=== A. 양성 대조 — 새 세션 단독 1개월 빌드가 저장 INV13 을 재현하는가 ===\n")
#==============================================================================
st_n <- ST06[, .N, by = Factor_Name]
if (setequal(st_n$Factor_Name, P_F) && all(st_n$N >= 1000L)) {
  ok("A0_stored_reference_present", sprintf("저장 202606 INV13 %s", paste(st_n$N, collapse = "/")))
} else {
  bad("A0_stored_reference_present", "★저장 202606 에 INV13 3종이 없음 — 양성 대조 기준 부재")
}
reset_state()   # 이 프로세스의 첫 compute_investor 호출 = 새 세션 단독 1개월 빌드
A <- run_ci(CI, SIG06)
csA <- cmp_stored(A$value)
if (stored_ok(csA)) {
  ok("A1_fresh_single_build_reproduces", fmt_cs(csA))
} else {
  bad("A1_fresh_single_build_reproduces", sprintf("★재현 실패 — %s | warns=%s", fmt_cs(csA),
                                                  paste(head(A$warns, 3), collapse = " / ")))
}
for (ym in names(REF_BETA)) {
  s <- if (ym == "202606") SIG06 else SIG07
  b <- CI$.inv13_beta_asof(INV_ALL[Date < s], s, TD, use_cache = FALSE)
  if (is.finite(b$beta) && abs(b$beta - REF_BETA[[ym]]) <= TOL_BETA && b$n_months == REF_N[[ym]] &&
      b$last_me < as.Date(format(s, "%Y-%m-01"))) {
    ok(paste0("A2_beta_", ym), sprintf("beta=%.15f n=%d last_me=%s", b$beta, b$n_months, format(b$last_me)))
  } else {
    bad(paste0("A2_beta_", ym), sprintf("beta=%.15f (ref %.15f) n=%d (ref %d) last_me=%s",
                                        b$beta, REF_BETA[[ym]], b$n_months, REF_N[[ym]], format(b$last_me)))
  }
}

#==============================================================================
cat("\n=== B. 세션·순서 무관성 — 구판 누산기 쓰레기 + 역순 빌드 ===\n")
#==============================================================================
reset_state()
.fdb_env$INV13_BETA_ACC <- list(SxY = 1e9, Sxx = 1, n_months = 999L)   # 구판이 읽던 자리에 쓰레기
B9 <- run_ci(CI, SIG09)
n9 <- B9$value[Factor_Name %in% P_F, .N, by = Factor_Name]
if (setequal(n9$Factor_Name, P_F) && all(n9$N > 0L)) {
  ok("B1_later_month_emits", sprintf("%s(sig %s) INV13 %s", format(SIG09, "%Y%m"), SIG09, paste(n9$N, collapse = "/")))
} else {
  bad("B1_later_month_emits", sprintf("★%s INV13 미배출 — warns=%s", format(SIG09, "%Y%m"),
                                      paste(head(B9$warns, 3), collapse = " / ")))
}
B6 <- run_ci(CI, SIG06)
dB <- max_same(A$value, B6$value)
csB <- cmp_stored(B6$value)
if (dB <= TOL_SAME && stored_ok(csB)) {
  ok("B2_reverse_order_invariant", sprintf("202609→202606 역순 + 쓰레기 누산기: A 대비 max|d|=%.2g · 저장 재현 유지", dB))
} else {
  bad("B2_reverse_order_invariant", sprintf("★세션 순서/상태 의존 — A 대비 max|d|=%.3g | %s", dB, fmt_cs(csB)))
}
rm(B9, B6); invisible(gc())
b_nc <- CI$.inv13_beta_asof(INV_ALL[Date < SIG06], SIG06, TD, use_cache = FALSE)
b_c  <- CI$.inv13_beta_asof(INV_ALL[Date < SIG06], SIG06, TD, use_cache = TRUE)
if (isTRUE(b_c$cached) && identical(b_c$beta, b_nc$beta) && identical(b_c$n_months, b_nc$n_months)) {
  ok("B3_cache_equals_fresh", "캐시 적중값 = 무캐시 재계산값 (비트 동일)")
} else {
  bad("B3_cache_equals_fresh", sprintf("cached=%s beta %.17g vs %.17g", b_c$cached, b_c$beta, b_nc$beta))
}

#==============================================================================
cat("\n=== C. PIT(C1) — sig 월 이후 데이터에 불변 · 이전 달에는 반응 ===\n")
#==============================================================================
m0 <- as.Date("2026-06-01")
base <- CI$.inv13_beta_asof(INV_ALL, SIG06, TD, use_cache = FALSE)   # 미래 행 포함 전 패널을 넘긴다
X <- INV_ALL[, .(Ticker, Date, Foreign, Individual)]
X[Date >= m0, `:=`(Foreign = -7 * Foreign + 1e9, Individual = 3 * Individual - 5e8)]
X <- rbindlist(list(X, data.table(Ticker = "AFAKE0", Date = seq(m0, by = "day", length.out = 60),
                                  Foreign = 1e12, Individual = -1e12)))
fut <- CI$.inv13_beta_asof(X, SIG06, TD, use_cache = FALSE)
if (identical(fut$beta, base$beta) && identical(fut$n_months, base$n_months) &&
    identical(base$beta, b_nc$beta)) {
  ok("C1_future_invariant", sprintf("sig 월(6월)·이후 행 조작 + 가짜 종목 주입에 beta 비트 불변 (%.15f)", base$beta))
} else {
  bad("C1_future_invariant", sprintf("★미래/당월 데이터가 beta 에 반영 — %.17g vs %.17g", fut$beta, base$beta))
}
X <- INV_ALL[, .(Ticker, Date, Foreign, Individual)]
X[Date >= as.Date("2026-05-01") & Date < as.Date("2026-05-29"), Foreign := -Foreign]
sen <- CI$.inv13_beta_asof(X, SIG06, TD, use_cache = FALSE)
if (is.finite(sen$beta) && abs(sen$beta - base$beta) > 1e-9) {
  ok("C2_sensitivity_control", sprintf("직전 달(5월) 조작엔 반응 Δβ=%.3g — C1 이 공허하지 않음", sen$beta - base$beta))
} else {
  bad("C2_sensitivity_control", "직전 달 조작에도 불변 — C1 불변성이 계측 사망일 수 있음")
}
rm(X); invisible(gc())

#==============================================================================
cat("\n=== D. 달력 계약 — 빌더 달력만 쓴다 ===\n")
#==============================================================================
e1 <- tryCatch({ CI$.inv13_beta_asof(INV_ALL[Date < SIG06], SIG06, trading_dates = NULL, use_cache = FALSE); NULL },
               error = function(e) conditionMessage(e))
if (is.character(e1) && grepl("달력", e1, fixed = TRUE)) {
  ok("D1_no_calendar_stops", "달력 미해결이면 정지(→ compute_investor 는 경고 후 INV13 미배출)")
} else {
  bad("D1_no_calendar_stops", "달력 없이도 값을 냄 — 투자자 달력 대체 의심")
}
inv_cal <- CI$.inv13_beta_asof(INV_ALL[Date < SIG06], SIG06, sort(unique(INV_ALL$Date)), use_cache = FALSE)
if (is.finite(inv_cal$beta) && abs(inv_cal$beta - REF_BETA[["202606"]]) > 1e-6) {
  ok("D2_calendar_is_load_bearing", sprintf("투자자 달력이면 Δβ=%.3g — A2 가 달력 차이를 잡는다", inv_cal$beta - REF_BETA[["202606"]]))
} else {
  bad("D2_calendar_is_load_bearing", "투자자 달력과 빌더 달력이 같은 beta — 달력 대조가 공허")
}
if (identical(CI$.inv13_trading_dates(), TD)) {
  ok("D3_reads_builder_calendar", sprintf(".fdb_env$trading_dates %d일 사용", length(TD)))
} else {
  bad("D3_reads_builder_calendar", ".fdb_env$trading_dates 를 읽지 않음")
}

#==============================================================================
cat("\n=== M. 위반 주입 — 돌연변이를 실제로 잡는가 ===\n")
#==============================================================================
MUT_KEY    <- list("key <- .inv13_cache_key(ym_k, x, me)", '  key <- "MUTANT_CONST_KEY"')
MUT_NOASOF <- list("if (.inv13_asof_ok(hit, m0, sig_d)) { hit$cached <- TRUE; return(hit) }",
                   "      if (TRUE) { hit$cached <- TRUE; return(hit) }")
MUT_LAG    <- list('m0    <- as.Date(format(sig_d, "%Y-%m-01"))   # as-of 컷: sig 월 첫날. 이 날 이후는 보지 않는다',
                   "  m0    <- sig_d + 1L")
MUT_NOEND  <- list("if (!.inv13_asof_ok(out, m0, sig_d))", "  if (FALSE)")
MUT_OLDGATE <- list(".inv13_beta_asof(inv, sig_d),",
  paste0('    (function() { a <- if (exists("INV13_BETA_ACC", envir = get(".fdb_env", envir = .GlobalEnv))) ',
         'get(".fdb_env", envir = .GlobalEnv)$INV13_BETA_ACC else list(SxY = 0, Sxx = 0, n_months = 0L); ',
         'list(beta = if (a$n_months >= 60L && a$Sxx > 1e-10) a$SxY / a$Sxx else NA_real_) })(),'))

# a1: 캐시 키만 붕괴 — 202609 캐시가 202606 에 적중하지만 as-of 단정이 거부해야 한다
Ma1 <- load_ci(list(MUT_KEY))
if (is.null(Ma1)) {
  bad("Ma1_asof_assertion_blocks_stale_cache", "돌연변이 지점 미발견")
} else {
  reset_state()
  invisible(Ma1$.inv13_beta_asof(INV_ALL[Date < SIG09], SIG09, TD))
  r <- with_warns(Ma1$.inv13_beta_asof(INV_ALL[Date < SIG06], SIG06, TD))
  if (abs(r$value$beta - REF_BETA[["202606"]]) <= TOL_BETA && any(grepl("as-of 단정 위반", r$warns, fixed = TRUE))) {
    ok("Ma1_asof_assertion_blocks_stale_cache", "키 붕괴로 202609 캐시가 적중했으나 as-of 단정이 거부 → 재계산값 정확")
  } else {
    bad("Ma1_asof_assertion_blocks_stale_cache", sprintf("beta=%.15f warns=%d", r$value$beta, length(r$warns)))
  }
}
# a2: 키 붕괴 + 단정 해제 = 미래 달 증분 혼입(구판 잠재 C1 형태) → 202606 재현이 red 여야 한다
Ma2 <- load_ci(list(MUT_KEY, MUT_NOASOF))
if (is.null(Ma2)) {
  bad("Ma2_future_increments_detected", "돌연변이 지점 미발견")
} else {
  reset_state()
  invisible(Ma2$.inv13_beta_asof(INV_ALL[Date < SIG09], SIG09, TD))   # 역순: 202609 먼저
  r <- run_ci(Ma2, SIG06)
  cs <- cmp_stored(r$value)
  if (!stored_ok(cs)) {
    ok("Ma2_future_increments_detected", sprintf("미래 달 증분 혼입 → 202606 재현 red (%s)", fmt_cs(cs)))
  } else {
    bad("Ma2_future_increments_detected", "★돌연변이가 재현 대조를 통과 — A1 이 공허")
  }
}
# a3: lag 규약 이동(sig 월 자신의 증분 포함). (i) 끝 단정이 정지로 막고 (ii) 단정을 끄면 재현 대조가 잡는다
Ma3 <- load_ci(list(MUT_LAG))
Ma3b <- load_ci(list(MUT_LAG, MUT_NOEND))
if (is.null(Ma3) || is.null(Ma3b)) {
  bad("Ma3_lag_shift_detected", "돌연변이 지점 미발견")
} else {
  e3 <- tryCatch({ Ma3$.inv13_beta_asof(INV_ALL[Date < SIG06], SIG06, TD, use_cache = FALSE); NULL },
                 error = function(e) conditionMessage(e))
  b3 <- Ma3b$.inv13_beta_asof(INV_ALL[Date < SIG06], SIG06, TD, use_cache = FALSE)
  if (is.character(e3) && grepl("as-of 단정 위반", e3, fixed = TRUE) &&
      is.finite(b3$beta) && abs(b3$beta - REF_BETA[["202606"]]) > TOL_BETA) {
    ok("Ma3_lag_shift_detected", sprintf("(i) 끝 단정이 정지 · (ii) 단정 해제 시 Δβ=%.3g 로 A2 red",
                                         b3$beta - REF_BETA[["202606"]]))
  } else {
    bad("Ma3_lag_shift_detected", sprintf("e3=%s beta=%.15f", if (is.null(e3)) "무정지" else e3, b3$beta))
  }
}
# b: 구판 n_months 게이트 부활(세션 누산기 읽기) → 새 세션 단독 빌드에서 0행이어야 한다(= A1 red)
Mb <- load_ci(list(MUT_OLDGATE))
if (is.null(Mb)) {
  bad("Mb_old_gate_zero_rows", "돌연변이 지점 미발견")
} else {
  reset_state()
  r <- run_ci(Mb, SIG06)
  n13 <- r$value[Factor_Name %in% P_F, .N]
  if (n13 == 0L && !stored_ok(cmp_stored(r$value))) {
    ok("Mb_old_gate_zero_rows", "구판 게이트 부활 → 단독 빌드 INV13 0행 → A1 red (원 결손 재현)")
  } else {
    bad("Mb_old_gate_zero_rows", sprintf("★구판 게이트인데 INV13 %d행 — 돌연변이가 안 걸렸거나 A1 이 공허", n13))
  }
}
reset_state()

finish()
