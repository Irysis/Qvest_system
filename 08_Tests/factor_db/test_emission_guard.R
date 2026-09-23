#==============================================================================
# test_emission_guard.R — factor DB 배출 감시 + compute_consensus 도달성 상설 검사
#
# 왜 있나 (FQ-163, 2026-08-08):
#   compute_consensus.R 의 7개 블록이 `if ("<metric>" %in% names(cons))` 로 게이트돼
#   있었는데 성능 리팩터가 `cons` 를 (Ticker, Date) 2열로 줄이면서 조건이 **영구
#   거짓**이 됐다. C10/C11/C13/C14/C15/C17/C18 이 440개 월 파일 전 구간 0행.
#   ★아무 경보도 없었다 — 빌더가 "등재된 팩터가 실제로 나왔는가"를 묻지 않았기 때문.
#   수리만 하면 같은 계통이 다시 생긴다. 그래서 감시(emission_guard)를 놓고,
#   그 감시가 **살아 있는지**를 이 검사가 지킨다. 검사 없는 가드는 무력화돼도
#   "경보 0건"으로만 보인다.
#
# 구조 6축:
#   A. 양성 대조 — 수리된 블록이 합성 입력에서 실제로 행을 낸다
#                  (0 이 '진짜 없음'인지 '계측 사망'인지 구별하는 기준선)
#   B. 위반 주입 — .cons_history 를 영구 NULL 로 돌연변이시키면 블록들이 사라지고
#                  그 상태를 감시가 **경고로 잡는가**
#   C. 오탐 없음 — 정상 상태에서 감시가 침묵하는가 (양방향)
#   D. vintage   — 초기 연도의 정당한 결측을 경고로 오분류하지 않는가
#   E. PIT       — C18 이 sig_date 이후 수익을 읽지 않는가 (미래참조 주입)
#   F. 짝 계약   — 코드의 .CONSENSUS_DEPRECATED 와 registry lifecycle 이 일치하는가
#                  + 기준선 파일이 수리된 팩터를 묻어버리지 않았는가
#   G. 배선      — 빌더가 실제로 감시를 호출하고, write 전에 부르는가
#   H. 지속 결손 — 회귀(R) 다음 달에도 이력 있는 결손이 WARN 으로 남는가 (Class P,
#                  2026-09-24 DATA-INV13-ACC) + 돌연변이 2종(P 제거 · 이력 조건 제거)
#
# 단독 실행: Rscript 08_Tests/factor_db/test_emission_guard.R
# 배터리   : 08_Tests/hooks/run_all_hooks.sh (SUITES 배열)
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })

.resolve_proj <- function() {
  cands <- c(Sys.getenv("CLAUDE_PROJECT_DIR", unset = ""),
             Sys.getenv("QM_ROOT", unset = ""),
             "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
  cands <- gsub("\\\\", "/", cands[nzchar(cands)])
  marker <- "02_Infrastructure/factor_db/emission_guard.R"
  hit <- cands[file.exists(file.path(cands, marker))]
  if (length(hit) == 0L) stop("project root 미발견 — CLAUDE_PROJECT_DIR 설정 필요")
  hit[1]
}
PROJ <- .resolve_proj()
setwd(PROJ)

CONS_SRC     <- "02_Infrastructure/factor_db/compute_consensus.R"
GUARD_SRC    <- "02_Infrastructure/factor_db/emission_guard.R"
BUILDER_SRC  <- "02_Infrastructure/factor_db/factor_db_builder.R"
REGISTRY     <- "02_Infrastructure/factor_db/factor_registry.json"
BASELINE     <- "02_Infrastructure/factor_db/emission_expected_absent.json"

PASS <- 0L; FAIL <- 0L
ok  <- function(id, msg) { PASS <<- PASS + 1L; cat(sprintf("  [PASS] %-34s %s\n", id, msg)) }
bad <- function(id, msg) { FAIL <<- FAIL + 1L; cat(sprintf("  [FAIL] %-34s %s\n", id, msg)) }

source(GUARD_SRC)

#==============================================================================
# 합성 픽스처 — 실제 22M행 RAWDATA 없이 compute_consensus 를 구동한다
#==============================================================================
SIG <- as.Date("2020-06-30")
TICKERS <- sprintf("A%05d", 1:6)

make_consensus <- function(last_sue_date = as.Date("2020-06-29")) {
  sue_dates <- c(as.Date(c("2020-01-31","2020-02-28","2020-03-31","2020-04-30","2020-05-29")),
                 last_sue_date)
  sue <- CJ(Ticker = TICKERS, Date = sue_dates)
  set.seed(11)
  sue[, sue := rep(c(0.5, 0.4, 0.3, 0.2, 0.1, 0.6), each = 1L, length.out = .N) +
        seq_len(.N) / 1000]
  esbr <- CJ(Ticker = TICKERS, Date = as.Date(c("2020-03-31","2020-04-30","2020-05-29","2020-06-25")))
  esbr[, esbr := seq_len(.N) / 100]
  rev1 <- CJ(Ticker = TICKERS, Date = as.Date(c("2020-03-31","2020-06-25")))
  rev1[, revenue_fy1 := 1000 + seq_len(.N) * 7]
  op1 <- CJ(Ticker = TICKERS, Date = as.Date(c("2020-03-31","2020-06-25")))
  op1[, op_profit_fy1 := 100 + seq_len(.N) * 3]
  eps1m <- CJ(Ticker = TICKERS, Date = as.Date("2020-06-25"))
  eps1m[, eps_chg_1m := seq_len(.N) / 50]
  list(sue = sue, esbr = esbr, revenue_fy1 = rev1, op_profit_fy1 = op1, eps_chg_1m = eps1m)
}

# RAWDATA: 2020-05-20 ~ 2020-07-05 영업일. post_spike 로 sig_date **이후** 값을 바꾼다.
make_rawdata <- function(post_spike = 0.0) {
  d <- seq(as.Date("2020-05-20"), as.Date("2020-07-05"), by = "day")
  d <- d[!(format(d, "%u") %in% c("6","7"))]
  rd <- CJ(Ticker = TICKERS, Date = d)
  set.seed(7)
  rd[, Ret := round(rnorm(.N, 0, 0.01), 6)]
  rd[, BM_Ret := round(rep(rnorm(length(d), 0, 0.005), times = length(TICKERS)), 6)]
  rd[Date > SIG, Ret := post_spike]        # ★미래 구간만 조작
  rd[Date > SIG, BM_Ret := 0]
  rd[, Close := 10000]
  rd[, Sector := "IT"]
  setkey(rd, Date, Ticker)
  rd[]
}

# compute_consensus 를 (선택적으로 돌연변이시켜) 격리 env 에 로드
load_compute_consensus <- function(mutate = c("none", "cons_history_null")) {
  mutate <- match.arg(mutate)
  code <- readLines(CONS_SRC, warn = FALSE)
  if (mutate == "cons_history_null") {
    # ★위반 주입: 원천 이력 조회를 영구 NULL 로 만든다 = 리팩터가 만들었던
    #   "게이트가 영원히 거짓" 상태의 재현.
    i <- grep("^.cons_history <- function", code, fixed = FALSE)
    if (length(i) != 1L) stop("돌연변이 지점 미발견 — .cons_history 정의 1건이어야 함")
    code[i] <- ".cons_history <- function(CONSENSUS, metric, sig_d) { return(NULL) } ; .unused <- function(CONSENSUS, metric, sig_d) {"
  }
  tf <- tempfile(fileext = ".R"); on.exit(unlink(tf), add = TRUE)
  writeLines(code, tf)
  e <- new.env(parent = globalenv())
  suppressWarnings(suppressMessages(source(tf, local = e)))
  e
}

run_cc <- function(env, CONS, RD) {
  suppressWarnings(env$compute_consensus(RAWDATA = RD, sig_date = SIG,
                                         FUND = NULL, CONSENSUS = CONS))
}

REPAIRED  <- c("C10_SUE_Persistence", "C11_Earnings_Streak",
               "C13_Revision_Breadth_3m", "C15_Forecast_Error_Trend",
               "C18_Earnings_CAR_3d")
DEPRECATED <- c("C14_Revenue_Surprise", "C17_OP_Revision")

#==============================================================================
cat("\n=== A. 양성 대조 — 수리된 블록이 실제로 행을 내는가 ===\n")
#==============================================================================
env_ok <- load_compute_consensus("none")
CONS   <- make_consensus()
RD     <- make_rawdata(0.0)
out_ok <- run_cc(env_ok, CONS, RD)

if (!is.data.table(out_ok) || nrow(out_ok) == 0L) {
  bad("A0_fixture_produces_rows", "합성 픽스처가 아무 행도 못 냄 — 이후 축 전부 공허")
} else {
  ok("A0_fixture_produces_rows", sprintf("%d행 / %d팩터", nrow(out_ok), uniqueN(out_ok$Factor_Name)))
}
for (f in REPAIRED) {
  n <- out_ok[Factor_Name == f, .N]
  if (n > 0L) ok(paste0("A_", f), sprintf("%d행", n))
  else        bad(paste0("A_", f), "0행 — 수리가 도달하지 않음")
}
# 양성 대조(원래 살아 있던 블록)가 같은 실행에 있어야 0 의 의미를 읽을 수 있다
n_c01 <- out_ok[Factor_Name == "C01_SUE", .N]
if (n_c01 > 0L) {
  ok("A_control_C01_SUE", sprintf("%d행 (살아있던 블록 정상)", n_c01))
} else {
  bad("A_control_C01_SUE", "★양성 대조 사망 — 픽스처/계측 자체를 의심할 것")
}

# 정본 위임분은 계산되지만 배출되지 않는다
for (f in DEPRECATED) {
  if (out_ok[Factor_Name == f, .N] == 0L) ok(paste0("A_dep_", f), "배출 보류(정본 위임) 확인")
  else bad(paste0("A_dep_", f), "deprecated 인데 배출됨 — registry 와 어긋남")
}

#==============================================================================
cat("\n=== E. PIT — C18 이 sig_date 이후 수익을 읽지 않는가 (미래참조 주입) ===\n")
#==============================================================================
# 구 코드는 발표일 프록시를 sig_d 까지 허용한 뒤 [ad-3, ad+3] 창을 썼다.
# 픽스처의 최신 SUE 는 2020-06-29 → 구 규칙이면 창이 07-02 까지 벌어져 미래를 읽는다.
# 미래 구간 수익만 바꿔 두 번 계산했을 때 값이 달라지면 = 누출.
c18_a <- run_cc(env_ok, CONS, make_rawdata(post_spike =  0.00))
c18_b <- run_cc(env_ok, CONS, make_rawdata(post_spike =  0.50))   # 미래에 +50% 주입
va <- c18_a[Factor_Name == "C18_Earnings_CAR_3d"][order(Ticker)]$Raw_Value
vb <- c18_b[Factor_Name == "C18_Earnings_CAR_3d"][order(Ticker)]$Raw_Value
if (length(va) == 0L || length(vb) == 0L) {
  bad("E1_c18_computed", "C18 미산출 — PIT 축이 공허해짐")
} else if (isTRUE(all.equal(va, vb))) {
  ok("E1_c18_no_lookahead", sprintf("미래 수익 조작에 불변 (%d종목)", length(va)))
} else {
  bad("E1_c18_no_lookahead", "★sig_date 이후 수익이 C18 에 반영됨 = 미래참조")
}

#==============================================================================
cat("\n=== B. 위반 주입 — 게이트를 영구 거짓으로 만들면 감시가 잡는가 ===\n")
#==============================================================================
env_mut <- load_compute_consensus("cons_history_null")
out_mut <- run_cc(env_mut, CONS, RD)
lost <- REPAIRED[!REPAIRED %in% unique(out_mut$Factor_Name)]
if (length(lost) == length(REPAIRED)) {
  ok("B1_mutation_kills_blocks", sprintf("돌연변이가 %d종을 전부 침묵시킴", length(lost)))
} else {
  bad("B1_mutation_kills_blocks",
      sprintf("돌연변이 후에도 %d종 생존 — A축 통과가 수리 덕이 아닐 수 있음",
              length(REPAIRED) - length(lost)))
}

# 그 침묵 상태를 감시가 경고로 잡는가
reg_meta_syn <- data.table(
  Factor_Name = c(REPAIRED, "C01_SUE", "M26_Revenue_Mom"),
  category    = "consensus", status = "active")
ledger_syn <- rbindlist(lapply(c("202004","202005"), function(y)
  data.table(ym = y, Factor_Name = c(REPAIRED, "C01_SUE", "M26_Revenue_Mom"), n_rows = 100L)))

prod_mut <- out_mut[, .(n_rows = .N, n_tickers = uniqueN(Ticker)), by = Factor_Name]
prod_mut <- rbindlist(list(prod_mut, data.table(Factor_Name = "M26_Revenue_Mom",
                                                n_rows = 100L, n_tickers = 6L)), fill = TRUE)
rep_mut <- factor_emission_check(prod_mut, reg_meta_syn, ledger_syn, "202006")
if (rep_mut$verdict == "WARN" && length(rep_mut$class_R_regression) >= length(REPAIRED)) {
  ok("B2_guard_fires_on_mutation",
     sprintf("회귀 %d종 경고: %s", length(rep_mut$class_R_regression),
             paste(head(rep_mut$class_R_regression, 3), collapse = ",")))
} else {
  bad("B2_guard_fires_on_mutation",
      sprintf("감시가 침묵 — verdict=%s 회귀=%d", rep_mut$verdict,
              length(rep_mut$class_R_regression)))
}

# ★원 사고의 형태: 한 번도 난 적 없는 팩터(델타 감시로는 원리적으로 못 잡음)
ledger_never <- rbindlist(lapply(c("202004","202005"), function(y)
  data.table(ym = y, Factor_Name = c("C01_SUE", "M26_Revenue_Mom"), n_rows = 100L)))
rep_never <- factor_emission_check(
  data.table(Factor_Name = c("C01_SUE","M26_Revenue_Mom"), n_rows = 100L, n_tickers = 6L),
  reg_meta_syn, ledger_never, "202006")
if (length(rep_never$class_S_silent) == length(REPAIRED)) {
  ok("B3_class_S_catches_never_produced",
     sprintf("구조적 침묵 %d종 검출 (원 C10 사고 형태)", length(rep_never$class_S_silent)))
} else {
  bad("B3_class_S_catches_never_produced",
      sprintf("전 구간 0행을 못 잡음 — 검출 %d/%d",
              length(rep_never$class_S_silent), length(REPAIRED)))
}

# 돌연변이로 검출력 실증: Class S 판정을 지운 가드는 B3 를 통과시켜선 안 된다
broken_check <- function(produced, reg_meta, ledger, ym, baseline = NULL) {
  r <- factor_emission_check(produced, reg_meta, ledger, ym, baseline)
  r$class_S_silent <- character(0); r$warnings <- character(0); r$verdict <- "OK"; r
}
rep_broken <- broken_check(
  data.table(Factor_Name = c("C01_SUE","M26_Revenue_Mom"), n_rows = 100L, n_tickers = 6L),
  reg_meta_syn, ledger_never, "202006")
if (length(rep_broken$class_S_silent) == 0L) {
  ok("B4_mutation_detectability", "Class S 를 제거하면 B3 가 실패한다 = 케이스가 공허하지 않음")
} else {
  bad("B4_mutation_detectability", "돌연변이 가드가 여전히 검출 — B3 가 다른 이유로 통과 중")
}

#==============================================================================
cat("\n=== C. 오탐 없음 — 정상 상태에서 침묵하는가 ===\n")
#==============================================================================
prod_ok <- data.table(Factor_Name = c(REPAIRED, "C01_SUE", "M26_Revenue_Mom"),
                      n_rows = 100L, n_tickers = 6L)
rep_ok <- factor_emission_check(prod_ok, reg_meta_syn, ledger_syn, "202006")
if (rep_ok$verdict == "OK" && length(rep_ok$warnings) == 0L) {
  ok("C1_no_false_alarm", "전부 산출된 달에 경고 0")
} else {
  bad("C1_no_false_alarm", sprintf("정상인데 경고 발화: %s",
                                   paste(rep_ok$warnings, collapse = " | ")))
}

# 기준선에 선언된 결측은 Class S 를 유발하지 않는다 (단 기록은 남는다)
bl <- data.table(Factor_Name = REPAIRED, reason = "선언된 결측",
                 diagnosed = TRUE, declared_ym = "202006")
rep_bl <- factor_emission_check(
  data.table(Factor_Name = c("C01_SUE","M26_Revenue_Mom"), n_rows = 100L, n_tickers = 6L),
  reg_meta_syn, ledger_never, "202006", baseline = bl)
if (length(rep_bl$class_S_silent) == 0L && rep_bl$n_absent == length(REPAIRED)) {
  ok("C2_baseline_suppresses", "기준선 선언분은 경고 억제 + 결측 기록은 유지")
} else {
  bad("C2_baseline_suppresses",
      sprintf("억제 실패 (silent=%d absent=%d)", length(rep_bl$class_S_silent), rep_bl$n_absent))
}

#==============================================================================
cat("\n=== D. vintage — 초기 연도의 정당한 결측을 오분류하지 않는가 ===\n")
#==============================================================================
# DART 계열처럼 201501 부터 나오는 팩터. 200506 빌드에선 없는 게 정상이다.
reg_v <- data.table(Factor_Name = c("C01_SUE","LATE_FACTOR"), category = "x", status = "active")
led_v <- rbindlist(list(
  data.table(ym = c("200504","200505"), Factor_Name = "C01_SUE", n_rows = 50L),
  data.table(ym = c("201501","201502"), Factor_Name = c("C01_SUE","C01_SUE"), n_rows = 50L),
  data.table(ym = c("201501","201502"), Factor_Name = "LATE_FACTOR", n_rows = 50L)))
rep_v <- factor_emission_check(data.table(Factor_Name = "C01_SUE", n_rows = 50L, n_tickers = 5L),
                               reg_v, led_v, "200506")
if (length(rep_v$warnings) == 0L) {
  ok("D1_vintage_not_flagged", "초기 연도 결측(후대에만 존재하는 팩터) 경고 없음")
} else {
  bad("D1_vintage_not_flagged", sprintf("vintage 결측을 경고로 오분류: %s",
                                        paste(rep_v$warnings, collapse = " | ")))
}
# 같은 팩터가 후대에 사라지면 그건 잡아야 한다 (D1 이 과잉 관용이 아님을 확인)
rep_v2 <- factor_emission_check(data.table(Factor_Name = "C01_SUE", n_rows = 50L, n_tickers = 5L),
                                reg_v, led_v, "201503")
if (length(rep_v2$class_R_regression) == 1L && rep_v2$class_R_regression == "LATE_FACTOR") {
  ok("D2_late_regression_caught", "동일 팩터가 후대에 사라지면 회귀로 검출")
} else {
  bad("D2_late_regression_caught", "vintage 관용이 회귀까지 삼킴 (과잉 관용)")
}

# 가드는 어떤 입력에도 빌드를 멈추지 않는다
crashed <- tryCatch({
  factor_emission_check(NULL, reg_v, NULL, "200506"); FALSE
}, error = function(e) TRUE)
if (!crashed) {
  ok("D3_never_stops_build", "빈 산출/빈 원장에서도 stop 하지 않음")
} else {
  bad("D3_never_stops_build", "가드가 예외로 빌드를 죽임 — 설계 원칙 ① 위반")
}

#==============================================================================
cat("\n=== F. 짝 계약 — 코드 deprecated ↔ registry lifecycle ↔ 기준선 ===\n")
#==============================================================================
dep_code <- names(env_ok$.CONSENSUS_DEPRECATED)
reg_meta_real <- emission_registry_meta(REGISTRY)
dep_reg <- reg_meta_real[status == "deprecated", Factor_Name]
if (setequal(dep_code, intersect(dep_reg, grep("^C[0-9]", dep_reg, value = TRUE)))) {
  ok("F1_code_registry_paired", sprintf("코드/registry deprecated 일치: %s",
                                        paste(sort(dep_code), collapse = ",")))
} else {
  bad("F1_code_registry_paired",
      sprintf("불일치 — 코드=%s registry=%s", paste(sort(dep_code), collapse = ","),
              paste(sort(dep_reg), collapse = ",")))
}
bl_real <- emission_load_baseline(BASELINE)
buried <- intersect(bl_real$Factor_Name, REPAIRED)
if (length(buried) == 0L) {
  ok("F2_baseline_does_not_bury_fix", sprintf("기준선 %d종에 수리 대상 없음", nrow(bl_real)))
} else {
  bad("F2_baseline_does_not_bury_fix",
      sprintf("★수리한 팩터가 기준선에 묻힘: %s", paste(buried, collapse = ",")))
}
unknown_bl <- setdiff(bl_real$Factor_Name, reg_meta_real$Factor_Name)
if (length(unknown_bl) == 0L) {
  ok("F3_baseline_names_exist", "기준선 항목 전부 registry 에 실재")
} else {
  bad("F3_baseline_names_exist",
      sprintf("registry 에 없는 기준선 항목: %s", paste(unknown_bl, collapse = ",")))
}

# 죽은 변수 `cons` 가 되살아나 같은 계통을 다시 만들지 않는지
cc_code <- readLines(CONS_SRC, warn = FALSE)
cc_live <- cc_code[!grepl("^\\s*#", cc_code)]
if (!any(grepl("names(cons)", cc_live, fixed = TRUE))) {
  ok("F4_no_names_cons_gate", "`names(cons)` 게이트 잔재 없음 (주석 제외)")
} else {
  bad("F4_no_names_cons_gate", "★`names(cons)` 게이트 재등장 — 원 사고 기전 복귀")
}

#==============================================================================
cat("\n=== G. 배선 — 빌더가 감시를 실제로 호출하는가 ===\n")
#==============================================================================
b <- readLines(BUILDER_SRC, warn = FALSE)
call_i  <- grep("factor_emission_guard(", b, fixed = TRUE)
call_i  <- call_i[!grepl("^\\s*#", b[call_i])]
write_i <- grep("write_parquet(result, out_path)", b, fixed = TRUE)
if (length(call_i) >= 1L) {
  ok("G1_guard_called", sprintf("빌더 %d행에서 호출", call_i[1]))
} else {
  bad("G1_guard_called", "★빌더가 감시를 호출하지 않음 — 파일만 있고 배선 없음")
}

if (length(call_i) >= 1L && length(write_i) >= 1L && min(call_i) < min(write_i)) {
  ok("G2_called_before_write", sprintf("호출 %d행 < write %d행", min(call_i), min(write_i)))
} else {
  bad("G2_called_before_write", "write 이후에 호출되거나 write 지점 미발견")
}
if (any(grepl("emission_guard.R", b, fixed = TRUE))) {
  ok("G3_guard_sourced", "emission_guard.R source 배선 존재")
} else {
  bad("G3_guard_sourced", "source 누락")
}

#==============================================================================
cat("\n=== H. 지속 결손(Class P) — 회귀 다음 달에도 경고가 남는가 ===\n")
#==============================================================================
# 실사고 형태(2026-09-24): INV13 3종이 202607 까지 산출 → 202608 회귀(Class R 경고) →
#   202609 는 absent_streak=2 인데 verdict OK. 직전 빌드만 비교하는 R 은 결손 둘째 달부터
#   원리적으로 침묵한다. 새 문턱은 없다: streak 1 = R, streak ≥2 ∧ 이력 있음 = P.
P_F <- c("INV13_Foreign_Resid_Individual_126d", "INV13_Foreign_Resid_Individual_21d",
         "INV13_Foreign_Resid_Individual_63d")
LIVE <- "INV01_Foreign_NetBuy_20d"
reg_p <- data.table(Factor_Name = c(P_F, LIVE, "NEVER_FACTOR"),
                    category = "investor", status = "active")
led_p <- rbindlist(list(
  rbindlist(lapply(c("202606", "202607"), function(y)
    data.table(ym = y, Factor_Name = c(P_F, LIVE), n_rows = 3000L))),
  data.table(ym = "202608", Factor_Name = LIVE, n_rows = 3000L)))
prod_live <- data.table(Factor_Name = LIVE, n_rows = 3000L, n_tickers = 3000L)
# NEVER_FACTOR = 한 번도 산출된 적 없는 결측(vintage/미탑재) — 기준선 선언. P 대상이 아니다.
bl_p <- data.table(Factor_Name = "NEVER_FACTOR", reason = "선언된 결측",
                   diagnosed = TRUE, declared_ym = "202001")

run_p <- function(chk, ym, ledger, produced = prod_live, baseline = bl_p)
  chk(produced, reg_p, ledger, ym, baseline)

# H0 대조: 결손 첫 달(202608)은 R 의 몫 — P 와 겹치지 않는다
r0 <- run_p(factor_emission_check, "202608", led_p[ym < "202608"])
if (setequal(r0$class_R_regression, P_F) && length(r0$class_P_persistent) == 0L &&
    r0$verdict == "WARN") {
  ok("H0_first_month_is_class_R", "결손 첫 달 = 회귀 3종 · 지속결손 0 (R/P 분리)")
} else {
  bad("H0_first_month_is_class_R", sprintf("R=%s P=%s verdict=%s",
      paste(r0$class_R_regression, collapse = ","), paste(r0$class_P_persistent, collapse = ","), r0$verdict))
}

# H1 원 사고: 결손 둘째 달(202609) — 구판은 OK 였다
r1 <- run_p(factor_emission_check, "202609", led_p)
h1_pass <- function(r) identical(sort(as.character(r$class_P_persistent)), sort(P_F)) &&
  length(r$class_R_regression) == 0L && r$verdict == "WARN" &&
  any(grepl("지속 결손", r$warnings, fixed = TRUE))
if (h1_pass(r1)) {
  st <- r1$absent_streak[Factor_Name %in% P_F]
  ok("H1_second_month_still_warn", sprintf("202609 지속결손 %d종(streak %s) → WARN",
                                           length(r1$class_P_persistent),
                                           paste(unique(st$consecutive_absent), collapse = ",")))
} else {
  bad("H1_second_month_still_warn", sprintf("★결손 둘째 달 침묵 — P=%s R=%s verdict=%s",
      paste(r1$class_P_persistent, collapse = ","), paste(r1$class_R_regression, collapse = ","), r1$verdict))
}

# H2 복구 전까지 유지: 셋째 달(202610)도 WARN
led_p3 <- rbindlist(list(led_p, data.table(ym = "202609", Factor_Name = LIVE, n_rows = 3000L)))
r2 <- run_p(factor_emission_check, "202610", led_p3)
if (setequal(r2$class_P_persistent, P_F) && r2$verdict == "WARN" &&
    all(r2$absent_streak[Factor_Name %in% P_F]$consecutive_absent == 3L)) {
  ok("H2_persists_until_recovery", "셋째 달(streak 3)에도 경고 유지")
} else {
  bad("H2_persists_until_recovery", sprintf("P=%s verdict=%s",
      paste(r2$class_P_persistent, collapse = ","), r2$verdict))
}

# H3 오탐 없음: 복구된 달엔 침묵
r3 <- run_p(factor_emission_check, "202609", led_p,
            produced = data.table(Factor_Name = c(LIVE, P_F), n_rows = 3000L, n_tickers = 3000L))
if (length(r3$class_P_persistent) == 0L && r3$verdict == "OK") {
  ok("H3_recovered_is_silent", "복구되면 지속결손 0 · verdict OK")
} else {
  bad("H3_recovered_is_silent", sprintf("복구 후에도 발화: %s", paste(r3$warnings, collapse = " | ")))
}

# H4 래칫: 이력 있는 결손도 기준선 선언분은 억제하되 기록한다 (Class S 와 같은 규칙)
bl_decl <- rbindlist(list(bl_p, data.table(Factor_Name = P_F[1], reason = "선언된 중단",
                                           diagnosed = TRUE, declared_ym = "202609")))
r4 <- run_p(factor_emission_check, "202609", led_p, baseline = bl_decl)
if (identical(as.character(r4$class_P_declared), P_F[1]) &&
    setequal(r4$class_P_persistent, P_F[-1])) {
  ok("H4_baseline_ratchet", "선언 1종은 class_P_declared 로 기록 · 나머지 2종 경고")
} else {
  bad("H4_baseline_ratchet", sprintf("declared=%s P=%s",
      paste(r4$class_P_declared, collapse = ","), paste(r4$class_P_persistent, collapse = ",")))
}

# H5 실제 기준선이 INV13 을 묻지 않는가 (F2 와 같은 계통의 인계철선)
buried_p <- intersect(bl_real$Factor_Name, P_F)
if (length(buried_p) == 0L) {
  ok("H5_baseline_does_not_bury_inv13", "기준선에 INV13 없음")
} else {
  bad("H5_baseline_does_not_bury_inv13", sprintf("★INV13 이 기준선에 묻힘: %s", paste(buried_p, collapse = ",")))
}

# H6·H7 돌연변이 — H1 이 공허하지 않음을 실증. 가드 원문 한 줄을 바꿔 격리 env 에 로드.
load_guard_mutant <- function(from, to) {
  code <- readLines(GUARD_SRC, warn = FALSE)
  i <- which(code == from)
  if (length(i) != 1L) return(NULL)
  code[i] <- to
  tf <- tempfile(fileext = ".R"); on.exit(unlink(tf), add = TRUE)
  writeLines(code, tf)
  e <- new.env(parent = globalenv())
  invisible(capture.output(suppressWarnings(suppressMessages(source(tf, local = e)))))
  e
}
# H6: Class P 제거(= 구판 동작) → H1 이 red 가 되어야 한다
m6 <- load_guard_mutant("    persistent <- sort(setdiff(p_all, baseline$Factor_Name))",
                        "    persistent <- character(0)")
if (is.null(m6)) {
  bad("H6_mutant_no_class_P_detected", "돌연변이 지점 미발견 — 검출력 실증 불가")
} else {
  rm6 <- run_p(m6$factor_emission_check, "202609", led_p)
  if (!h1_pass(rm6) && rm6$verdict == "OK") {
    ok("H6_mutant_no_class_P_detected", "P 를 지운 가드는 202609 에 OK → H1 red (구판 재현)")
  } else {
    bad("H6_mutant_no_class_P_detected", sprintf("돌연변이가 여전히 통과 — verdict=%s", rm6$verdict))
  }
}
# H7: '이력 있음' 조건 — 한 번도 난 적 없는 결측은 P 가 아니라 S(구조적 침묵)의 몫이다.
#   기준선 없이 돌려 NEVER_FACTOR 가 S 로만 가고 P 로 새지 않는지(실물) → 조건을 지운
#   돌연변이에선 P 로 새는지(검출력)를 짝으로 잰다.
bl_empty <- bl_p[0L]
p_excludes_never <- function(r) setequal(r$class_P_persistent, P_F) &&
  !("NEVER_FACTOR" %in% r$class_P_persistent)
r7 <- run_p(factor_emission_check, "202609", led_p, baseline = bl_empty)
if (p_excludes_never(r7) && "NEVER_FACTOR" %in% r7$class_S_silent) {
  ok("H7_history_condition", "이력 없는 결측은 S 로만 — P 는 이력 있는 3종뿐")
} else {
  bad("H7_history_condition", sprintf("P=%s S=%s", paste(r7$class_P_persistent, collapse = ","),
                                      paste(r7$class_S_silent, collapse = ",")))
}
m7 <- load_guard_mutant(
  "    p_all <- streak[consecutive_absent >= 2L & !is.na(last_seen_ym), Factor_Name]",
  "    p_all <- streak[consecutive_absent >= 2L, Factor_Name]")
if (is.null(m7)) {
  bad("H7m_mutant_no_history_cond_detected", "돌연변이 지점 미발견 — 검출력 실증 불가")
} else {
  rm7 <- run_p(m7$factor_emission_check, "202609", led_p, baseline = bl_empty)
  if (!p_excludes_never(rm7)) {
    ok("H7m_mutant_no_history_cond_detected", "이력 조건을 지우면 NEVER_FACTOR 가 P 로 새어 H7 red")
  } else {
    bad("H7m_mutant_no_history_cond_detected", sprintf("과잉 경보 미검출 — P=%s",
        paste(rm7$class_P_persistent, collapse = ",")))
  }
}

cat(sprintf("\nTOTAL: %d pass / %d fail\n", PASS, FAIL))
cat(toJSON(list(test = "emission_guard", pass = PASS, fail = FAIL,
                total = PASS + FAIL), auto_unbox = TRUE), "\n", sep = "")
if (FAIL > 0) quit(status = 1)
