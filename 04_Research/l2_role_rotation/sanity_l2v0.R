#==============================================================================
# sanity_l2v0.R — 측정 전 점검(PR-L2-ROLESLEEVE-V0 · 사전등록 뒤 · 측정 전) — 수익률 미사용
#
# 엔진을 5 arm 으로 돌려 비중만 본다: Σw=1 · w>0 · ≤n_max · 시그널일 = 132 보유월 · 컷오프 이전 · 러너 유니버스 필터가
#   떨어뜨릴 행 0 · detect_lookahead CLEAN · MC3(슬리브 처치 전달량) · MC3b(종목 처치 전달량 · 보고 전용).
# RAWDATA = .cache/RAWDATA.parquet 에서 필요한 열만(Date·Ticker·K200·KQ150·Close·Vol) · Date <= data_cutoff (러너 절단과 같은 창).
# 실행: 이 디렉터리에서 Rscript --no-save -e 'source("sanity_l2v0.R")'  · 쓰기 = sanity/ (덮어쓰기 거부)
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite); library(arrow) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
.find_root <- function() {
  for (p in c(Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""), getwd(), dirname(getwd()), dirname(dirname(getwd())))) {
    if (nzchar(p) && file.exists(file.path(p, "02_Infrastructure/config.R"))) return(normalizePath(p, winslash = "/"))
  }
  stop("[sanity_l2v0] 프로젝트 루트 미발견")
}
ROOT <- .find_root(); L2DIR <- file.path(ROOT, "04_Research/l2_role_rotation")
OUT <- file.path(L2DIR, "sanity"); out_json <- file.path(OUT, "sanity_v0.json")
if (file.exists(out_json)) stop("[sanity_l2v0] 덮어쓰기 거부: ", out_json)
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)
DESIGN <- fromJSON(file.path(L2DIR, "l2v0_design.json"), simplifyVector = FALSE)
ARMS <- names(DESIGN$arms)[order(vapply(DESIGN$arms, function(a) as.numeric(a$order), numeric(1)))]
sha <- function(p) digest::digest(file = p, algo = "sha256")
engine <- file.path(L2DIR, "allocator_engine.R")
cutoff <- as.Date(DESIGN$window$data_cutoff)
FX <- fromJSON(file.path(ROOT, "06_Registry/reinforce_program.json"), simplifyVector = FALSE)$fixed_axes

# 정적 PIT 탐지(러너 §4 와 같은 함수)
suppressMessages(source(file.path(ROOT, "02_Infrastructure/validation/lookahead_detector.R")))
la <- detect_lookahead(engine, verbose = FALSE)

RAW <- as.data.table(arrow::read_parquet(file.path(ROOT, ".cache/RAWDATA.parquet"),
                                        col_select = c("Date", "Ticker", "K200", "KQ150", "Close", "Vol")))
RAW[, Date := as.Date(Date)]
raw_max_loaded <- max(RAW$Date)
RAW <- RAW[Date <= cutoff & Date >= as.Date("2015-01-01")]
Sys.setenv(L2V0_INPUTS_SHA = sha(file.path(L2DIR, "work/l2v0_inputs_manifest.json")))

P <- list(); checks <- list()
for (a in ARMS) {
  Sys.setenv(L2V0_ARM = a, L2V0_DIAG_DIR = file.path(OUT, a))
  e <- new.env(parent = globalenv()); e$RAWDATA <- RAW
  sys.source(engine, envir = e, keep.source = FALSE)
  pf <- copy(e$PORTFOLIO); P[[a]] <- pf
  by_d <- pf[, .(n = .N, s = sum(Weight), mn = min(Weight)), by = Date]
  # 러너 유니버스 필터(.apply_universe)가 떨어뜨릴 행
  mem <- unique(RAW[Date %in% unique(pf$Date) & (K200 == TRUE | KQ150 == TRUE), .(Date, Ticker)])
  dropped <- nrow(pf) - nrow(merge(pf, mem, by = c("Date", "Ticker")))
  checks[[a]] <- list(n_signal_dates = nrow(by_d), first_signal = format(min(pf$Date)), last_signal = format(max(pf$Date)),
                      max_abs_sum_minus_1 = max(abs(by_d$s - 1)), min_weight = min(by_d$mn), max_names = max(by_d$n), min_names = min(by_d$n),
                      mean_names = mean(by_d$n), any_na = anyNA(pf), rows_runner_universe_would_drop = dropped,
                      signal_dates_before_cutoff = all(pf$Date < cutoff), max_weight = max(pf$Weight),
                      pass = nrow(by_d) == 132L && max(abs(by_d$s - 1)) < 1e-9 && min(by_d$mn) > 0 && max(by_d$n) <= as.integer(FX$n_max) &&
                             !anyNA(pf) && dropped == 0L && all(pf$Date < cutoff))
  cat(sprintf("[sanity_l2v0] %s: dates %d · names %d~%d · max|Σw−1| %.2e · drop %d · pass %s\n", a, nrow(by_d), min(by_d$n), max(by_d$n),
              max(abs(by_d$s - 1)), dropped, checks[[a]]$pass))
}

# MC3 — 슬리브 처치 전달량 mean_m ½Σ_r |w_T,r(m) − w_K,r|
sw <- function(a) fread(file.path(OUT, a, sprintf("engine_sleeve_weights_%s.csv", a)))
swT <- sw("T_var"); swK <- sw("K"); swS <- sw("S")
mc3_tab <- merge(swT[, .(holding_month, role, wT = w_role)], swK[, .(holding_month, role, wK = w_role)], by = c("holding_month", "role"))
mc3_by_m <- mc3_tab[, .(d = 0.5 * sum(abs(wT - wK))), by = holding_month]
MC3 <- mean(mc3_by_m$d)
# MC3b — 종목 처치 전달량(보고 전용) mean_m ½Σ_i |W_T,i − W_K,i|
stock_l1 <- function(a, b) {
  x <- merge(P[[a]][, .(Date, Ticker, wa = Weight)], P[[b]][, .(Date, Ticker, wb = Weight)], by = c("Date", "Ticker"), all = TRUE)
  x[is.na(wa), wa := 0]; x[is.na(wb), wb := 0]
  mean(x[, .(d = 0.5 * sum(abs(wa - wb))), by = Date]$d)
}
Pser <- unique(swT[, .(holding_month, P_T, P_S)])
res <- list(
  schema = "l2v0_sanity_v1", prereg_id = "PR-L2-ROLESLEEVE-V0", at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  note = "측정 전 점검 — 엔진 비중만(수익률 미사용). MC3 = 사전등록 처치 전달 타당성(문턱 0.05). MC3b = 종목 수준 전달량(보고 전용).",
  engine_sha256 = sha(engine), inputs_manifest_sha256 = Sys.getenv("L2V0_INPUTS_SHA"),
  raw = list(path = ".cache/RAWDATA.parquet", max_date_loaded = format(raw_max_loaded), cutoff = format(cutoff)),
  detect_lookahead = list(clean = la$clean, n_violations = length(la$violations %||% list())),
  arms = checks,
  all_pass = all(vapply(checks, function(z) isTRUE(z$pass), logical(1))) && isTRUE(la$clean),
  P = list(n = nrow(Pser), mean_P_T = mean(Pser$P_T), sd_P_T = sd(Pser$P_T), min = min(Pser$P_T), max = max(Pser$P_T),
           share_gt_0_5 = mean(Pser$P_T > 0.5), mean_abs_dev = mean(abs(Pser$P_T - mean(Pser$P_T)))),
  MC3 = list(value = MC3, threshold = 0.05, pass = MC3 >= 0.05,
             definition = "mean_m ½Σ_r |w_T_var,r(m) − w_K,r| (슬리브 수준 · 132 보유월)"),
  MC3b_stock_level = list(T_var_vs_K = stock_l1("T_var", "K"), S_vs_K = stock_l1("S", "K"), T_var_vs_S = stock_l1("T_var", "S"),
                          T_var_vs_K_eq = stock_l1("T_var", "K_eq"), T_var_vs_EW_all = stock_l1("T_var", "EW_all"), K_vs_K_eq = stock_l1("K", "K_eq"),
                          definition = "mean_m ½Σ_i |W_a,i(m) − W_b,i(m)| (상위 25 절단·재정규화 뒤 종목 비중 · 보고 전용)")
)
writeLines(toJSON(res, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = NA), out_json, useBytes = TRUE)
cat(sprintf("[sanity_l2v0] all_pass=%s · MC3=%.4f (%s) · MC3b(T−K)=%.4f · lookahead clean=%s\n", res$all_pass, MC3,
            if (MC3 >= 0.05) "PASS" else "FAIL", res$MC3b_stock_level$T_var_vs_K, la$clean))
