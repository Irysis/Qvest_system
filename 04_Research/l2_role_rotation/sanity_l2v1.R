#==============================================================================
# sanity_l2v1.R — 측정 전 점검(PR-L2-ROLESLEEVE-V1 · MC2_v1 PASS 뒤 · arm 측정 전) — 수익률 미사용
#
# 엔진 v1 을 4 arm(T_var·K·S·EW_all)으로 돌려 비중만 본다(v0 sanity_l2v0.R 와 같은 점검):
#   Σw=1 · w>0 · ≤n_max · 시그널일 = 132 보유월 · 컷오프 이전 · 러너 유니버스 필터가 떨굴 행 0 · detect_lookahead CLEAN ·
#   MC3(슬리브 처치 전달량 mean_m ½Σ_r |w_T,r − w_K,r| ≥ 0.05 — 미달이면 H1 = undetermined) · MC3b(종목 수준 · 보고 전용).
# 전제(운영): verdict_v1/mc2_v1.json 이 있고 pass = TRUE (사전등록 단계 3 진입 관문).
# RAWDATA = .cache/RAWDATA.parquet 필요한 열만 · Date <= data_cutoff.
# 검사 모드(L2V1_TEST=1): L2V1_MANIFEST_PATH(검사 매니페스트) · L2V1_SANITY_OUT(이 디렉터리 밖) · MC2 전제 생략.
# 실행: 이 디렉터리에서 Rscript --no-save -e 'source("sanity_l2v1.R")' · 쓰기 = sanity_v1/ (덮어쓰기 거부)
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite); library(arrow) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
.find_root <- function() {
  for (p in c(Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""), getwd(), dirname(getwd()), dirname(dirname(getwd())))) {
    if (nzchar(p) && file.exists(file.path(p, "02_Infrastructure/config.R"))) return(normalizePath(p, winslash = "/"))
  }
  stop("[sanity_l2v1] 프로젝트 루트 미발견")
}
ROOT <- .find_root(); L2DIR <- file.path(ROOT, "04_Research/l2_role_rotation")
TEST <- identical(Sys.getenv("L2V1_TEST", ""), "1")
if (TEST) {
  OUT <- normalizePath(Sys.getenv("L2V1_SANITY_OUT", ""), winslash = "/", mustWork = FALSE)
  if (!nzchar(Sys.getenv("L2V1_SANITY_OUT", "")) || startsWith(tolower(OUT), tolower(normalizePath(L2DIR, winslash = "/"))))
    stop("[sanity_l2v1] 검사 모드 출력은 이 디렉터리 밖(L2V1_SANITY_OUT)")
  MAN_P <- Sys.getenv("L2V1_MANIFEST_PATH", ""); if (!nzchar(MAN_P)) stop("[sanity_l2v1] 검사 모드는 L2V1_MANIFEST_PATH 필수")
} else {
  OUT <- file.path(L2DIR, "sanity_v1"); MAN_P <- file.path(L2DIR, "work/l2v1_inputs_manifest.json")
  Sys.unsetenv("L2V1_MANIFEST_PATH")
  mc2p <- file.path(L2DIR, "verdict_v1/mc2_v1.json")
  if (!file.exists(mc2p)) stop("[sanity_l2v1] MC2_v1 미측정 — 단계 2 먼저")
  if (!isTRUE(fromJSON(mc2p, simplifyVector = FALSE)$pass)) stop("[sanity_l2v1] MC2_v1 FAIL — 사전등록상 단계 3 없음")
}
out_json <- file.path(OUT, "sanity_v1.json")
if (file.exists(out_json)) stop("[sanity_l2v1] 덮어쓰기 거부: ", out_json)
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)
MAN <- fromJSON(MAN_P, simplifyVector = FALSE)
absp <- function(p) if (grepl("^([A-Za-z]:)?[/\\\\]", p)) p else file.path(ROOT, p)
DESIGN <- fromJSON(absp(MAN$files$design$path), simplifyVector = FALSE)
ARMS <- names(DESIGN$arms)[order(vapply(DESIGN$arms, function(a) as.numeric(a$order), numeric(1)))]
sha <- function(p) digest::digest(file = p, algo = "sha256")
engine <- file.path(L2DIR, "allocator_engine_v1.R")
cutoff <- as.Date(DESIGN$window$data_cutoff)
FX <- fromJSON(absp(MAN$files$reinforce_program_fixed_axes$path), simplifyVector = FALSE)$fixed_axes
n_hm <- length(seq(as.Date(DESIGN$window$first_holding_month), as.Date(DESIGN$window$last_holding_month), by = "month"))

suppressMessages(source(file.path(ROOT, "02_Infrastructure/validation/lookahead_detector.R")))
la <- detect_lookahead(engine, verbose = FALSE)

RAW <- as.data.table(arrow::read_parquet(file.path(ROOT, ".cache/RAWDATA.parquet"),
                                        col_select = c("Date", "Ticker", "K200", "KQ150", "Close", "Vol")))
RAW[, Date := as.Date(Date)]
raw_max_loaded <- max(RAW$Date)
RAW <- RAW[Date <= cutoff & Date >= as.Date("2015-01-01")]
Sys.setenv(L2V1_INPUTS_SHA = sha(MAN_P))
if (TEST) Sys.setenv(L2V1_MANIFEST_PATH = MAN_P)

P <- list(); checks <- list()
for (a in ARMS) {
  Sys.setenv(L2V1_ARM = a, L2V1_DIAG_DIR = file.path(OUT, a))
  e <- new.env(parent = globalenv()); e$RAWDATA <- RAW
  sys.source(engine, envir = e, keep.source = FALSE)
  pf <- copy(e$PORTFOLIO); P[[a]] <- pf
  by_d <- pf[, .(n = .N, s = sum(Weight), mn = min(Weight)), by = Date]
  mem <- unique(RAW[Date %in% unique(pf$Date) & (K200 == TRUE | KQ150 == TRUE), .(Date, Ticker)])
  dropped <- nrow(pf) - nrow(merge(pf, mem, by = c("Date", "Ticker")))
  checks[[a]] <- list(n_signal_dates = nrow(by_d), first_signal = format(min(pf$Date)), last_signal = format(max(pf$Date)),
                      max_abs_sum_minus_1 = max(abs(by_d$s - 1)), min_weight = min(by_d$mn), max_names = max(by_d$n), min_names = min(by_d$n),
                      mean_names = mean(by_d$n), any_na = anyNA(pf), rows_runner_universe_would_drop = dropped,
                      signal_dates_before_cutoff = all(pf$Date < cutoff), max_weight = max(pf$Weight),
                      pass = nrow(by_d) == n_hm && max(abs(by_d$s - 1)) < 1e-9 && min(by_d$mn) > 0 && max(by_d$n) <= as.integer(FX$n_max) &&
                             !anyNA(pf) && dropped == 0L && all(pf$Date < cutoff))
  cat(sprintf("[sanity_l2v1] %s: dates %d · names %d~%d · max|Σw−1| %.2e · drop %d · pass %s\n", a, nrow(by_d), min(by_d$n), max(by_d$n),
              max(abs(by_d$s - 1)), dropped, checks[[a]]$pass))
}
Sys.unsetenv(c("L2V1_ARM", "L2V1_DIAG_DIR", "L2V1_INPUTS_SHA", "L2V1_MANIFEST_PATH"))

# MC3 — 슬리브 처치 전달량 mean_m ½Σ_r |w_T,r(m) − w_K,r|
sw <- function(a) fread(file.path(OUT, a, sprintf("engine_sleeve_weights_%s.csv", a)))
swT <- sw("T_var"); swK <- sw("K")
mc3_tab <- merge(swT[, .(holding_month, role, wT = w_role)], swK[, .(holding_month, role, wK = w_role)], by = c("holding_month", "role"))
MC3 <- mean(mc3_tab[, .(d = 0.5 * sum(abs(wT - wK))), by = holding_month]$d)
stock_l1 <- function(a, b) {
  x <- merge(P[[a]][, .(Date, Ticker, wa = Weight)], P[[b]][, .(Date, Ticker, wb = Weight)], by = c("Date", "Ticker"), all = TRUE)
  x[is.na(wa), wa := 0]; x[is.na(wb), wb := 0]
  mean(x[, .(d = 0.5 * sum(abs(wa - wb))), by = Date]$d)
}
Pser <- unique(swT[, .(holding_month, P_T, P_S)])
emp <- rbindlist(lapply(ARMS, function(a) fread(file.path(OUT, a, sprintf("engine_diag_%s.csv", a)))[, .(arm, any_empty_sleeve, kept_share_of_positive_mass)]))
def_n <- swT[role == "defensive", n_members]
res <- list(
  schema = "l2v1_sanity_v1", prereg_id = "PR-L2-ROLESLEEVE-V1", at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), mode = if (TEST) "test" else "production",
  note = "측정 전 점검 — 엔진 v1 비중만(수익률 미사용). MC3 = 처치 전달 타당성(문턱 0.05). MC3b = 종목 수준 전달량(보고 전용).",
  engine_sha256 = sha(engine), sanity_script_sha256 = sha(file.path(L2DIR, "sanity_l2v1.R")), inputs_manifest = list(path = MAN_P, sha256 = sha(MAN_P)),
  raw = list(path = ".cache/RAWDATA.parquet", max_date_loaded = format(raw_max_loaded), cutoff = format(cutoff)),
  detect_lookahead = list(clean = la$clean, n_violations = length(la$violations %||% list())),
  arms = checks,
  all_pass = all(vapply(checks, function(z) isTRUE(z$pass), logical(1))) && isTRUE(la$clean),
  P = list(n = nrow(Pser), mean_P_T = mean(Pser$P_T), sd_P_T = sd(Pser$P_T), min = min(Pser$P_T), max = max(Pser$P_T),
           share_gt_0_5 = mean(Pser$P_T > 0.5)),
  defensive_members_available = list(min = min(def_n), median = stats::median(def_n), max = max(def_n)),
  empty_sleeve_months = emp[, .(n = sum(any_empty_sleeve %in% TRUE)), by = arm][, setNames(as.list(n), arm)],
  kept_share_median = emp[, .(v = stats::median(kept_share_of_positive_mass, na.rm = TRUE)), by = arm][, setNames(as.list(v), arm)],
  MC3 = list(value = MC3, threshold = 0.05, pass = MC3 >= 0.05, definition = "mean_m ½Σ_r |w_T_var,r(m) − w_K,r| (슬리브 수준)"),
  MC3b_stock_level = list(T_var_vs_K = stock_l1("T_var", "K"), S_vs_K = stock_l1("S", "K"), T_var_vs_S = stock_l1("T_var", "S"),
                          T_var_vs_EW_all = stock_l1("T_var", "EW_all"),
                          definition = "mean_m ½Σ_i |W_a,i(m) − W_b,i(m)| (상위 25 절단·재정규화 뒤 · 보고 전용)"))
writeLines(toJSON(res, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = NA), out_json, useBytes = TRUE)
cat(sprintf("[sanity_l2v1] all_pass=%s · MC3=%.4f (%s) · MC3b(T−K)=%.4f · lookahead clean=%s\n", res$all_pass, MC3,
            if (MC3 >= 0.05) "PASS" else "FAIL", res$MC3b_stock_level$T_var_vs_K, la$clean))
