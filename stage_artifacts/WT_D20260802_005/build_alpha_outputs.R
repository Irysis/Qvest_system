# =============================================================================
# build_alpha_outputs.R — WT-D20260802_005 회수 확정 후보(IN03_RD_to_Market)의
#   alpha_scores.parquet + advisory 진단 + alpha_vector/confidence_vector 산출
#
# 근거: canonical dual-basis 재실측 (dualbasis_chen_welch_rd_to_market.json)
#   cap-w PORT_t 2.537 (p .011) / EW-uni 3.610 (p .0003) / EW oos~ 0.563
# 규약: C15 — load_month_factors() 경유(fe_factor_combo.R). 성능수치는 재계산하지
#   않는다(canonical JSON이 이미 실측). 여기선 스코어 패널 + advisory IC 진단만.
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
if (!nzchar(Sys.getenv("CLAUDE_PROJECT_DIR"))) Sys.setenv(CLAUDE_PROJECT_DIR = ROOT)
Sys.setenv(FACTOR_NAMES = "IN03_RD_to_Market")
OUT_CANON <- file.path(ROOT, "stage_artifacts", "WT_D20260802_005")   # 정본(언더스코어)
dir.create(OUT_CANON, recursive = TRUE, showWarnings = FALSE)

source(file.path(ROOT, "02_Infrastructure", "config.R"))
source(file.path(ROOT, "02_Infrastructure", "backtest_harness.R"))
source(file.path(ROOT, "02_Infrastructure", "ramp", "factor_validation.R"))

res <- load_rawdata(use_cache = TRUE)
RAWDATA <- res$RAWDATA; BM_DT <- res$BM_DT; rm(res); gc(verbose = FALSE)
if (!inherits(RAWDATA$Date, "Date")) RAWDATA[, Date := as.Date(Date, tz = "Asia/Seoul")]

fe_env <- new.env(parent = environment())
fe_env$RAWDATA <- RAWDATA; fe_env$BM_DT <- BM_DT
source(file.path(ROOT, "02_Infrastructure", "alpha_search", "fe_factor_combo.R"), local = fe_env)
FACTORS <- fe_env$FACTORS; rm(fe_env); gc(verbose = FALSE)
stopifnot(is.data.table(FACTORS), all(c("Date","Ticker","Score") %in% names(FACTORS)))
FACTORS <- FACTORS[Date >= as.Date("2005-01-01")]

# 유니버스 멤버십 (PIT 시변)
.me <- unique(FACTORS$Date)
.mem <- unique(RAWDATA[Date %in% .me & (K200 == TRUE | KQ150 == TRUE), .(Date, Ticker)])
FACTORS <- merge(FACTORS, .mem, by = c("Date","Ticker"))
cat(sprintf("[panel] %d rows | %d dates | %d tickers\n", nrow(FACTORS), uniqueN(FACTORS$Date), uniqueN(FACTORS$Ticker)))

# forward returns (advisory IC용)
RAWDATA[, ym := format(Date, "%Y-%m")]
.MEND <- sort(RAWDATA[, .(Date = max(Date)), by = ym]$Date)
RAWME <- RAWDATA[Date %in% .MEND, .(Date, Ticker, Close, Vol, Size, K200, KQ150)]
fwd <- build_monthly_forward_returns(RAWME, .MEND)
IC_dt <- merge(FACTORS[, .(Date, Ticker, Score)], fwd$returns_dt, by = c("Date","Ticker"))
ic_m <- IC_dt[, .(ic = suppressWarnings(cor(Score, Ret_1m, method = "spearman", use = "complete.obs")), n = .N), by = Date][is.finite(ic)]
setorder(ic_m, Date)

nw_t <- function(x, lag = 3L) { # NW lag-3 t of mean (Newey-West 1987)
  n <- length(x); if (n < 12) return(NA_real_)
  m <- mean(x); e <- x - m; g0 <- sum(e^2)/n
  s <- g0
  for (l in 1:lag) { w <- 1 - l/(lag+1); g <- sum(e[(l+1):n]*e[1:(n-l)])/n; s <- s + 2*w*g }
  m / sqrt(s/n)
}
rank_ic <- mean(ic_m$ic); icir <- rank_ic / sd(ic_m$ic); ic_t <- nw_t(ic_m$ic)
sub <- list(p1 = ic_m[Date <= "2014-12-31"], p2 = ic_m[Date > "2014-12-31" & Date <= "2019-12-31"], p3 = ic_m[Date > "2019-12-31"])
sub_ic <- sapply(sub, function(d) mean(d$ic))
sub_stab <- mean(sign(sub_ic) == sign(rank_ic))
# monotonicity: 분위 5 평균 forward return 단조성 (spearman of decile rank vs mean ret)
IC_dt[, q := cut(frank(Score, ties.method = "average")/.N, breaks = seq(0,1,0.2), labels = FALSE, include.lowest = TRUE), by = Date]
qret <- IC_dt[, .(mret = mean(Ret_1m, na.rm = TRUE)), by = q][order(q)]
mono <- suppressWarnings(cor(qret$q, qret$mret, method = "spearman"))

cat(sprintf("[advisory] rank_ic=%.4f icir=%.3f ic_t_nw=%.2f mono=%.2f sub_ic=[%.4f %.4f %.4f] stab=%.2f\n",
            rank_ic, icir, ic_t, mono, sub_ic[1], sub_ic[2], sub_ic[3], sub_stab))

# z-score (신호일 횡단) + alpha_vector (최신 sig_date, Grinold: alpha = IC * sigma_cs * z)
FACTORS[, z := (Score - mean(Score)) / sd(Score), by = Date]
FACTORS[, z := pmin(pmax(z, -3), 3)]  # winsor 3sd
last_dt <- max(FACTORS$Date)
sigma_cs <- IC_dt[Date >= (last_dt - 1095L),
                  .(s = sd(Ret_1m, na.rm = TRUE)), by = Date][, mean(s, na.rm = TRUE)]
if (!is.finite(sigma_cs)) sigma_cs <- IC_dt[, .(s = sd(Ret_1m, na.rm=TRUE)), by=Date][, mean(s, na.rm=TRUE)]
AV <- FACTORS[Date == last_dt, .(Ticker, z, alpha_hat = rank_ic * sigma_cs * z)]

# confidence: 팩터 커버리지(직전 12신호월 관측/12) x 부기간 안정성 배수
cov12 <- FACTORS[Date > last_dt - 400, .N, by = Ticker][, .(Ticker, cov = pmin(N/12, 1))]
AV <- merge(AV, cov12, by = "Ticker", all.x = TRUE)
AV[is.na(cov), cov := 0.5]
AV[, confidence := round(pmin(pmax(cov * (0.5 + 0.5 * sub_stab), 0), 1), 3)]

write_parquet(FACTORS[, .(Date, Ticker, Score, z)], file.path(OUT_CANON, "alpha_scores.parquet"))
adv <- list(metric_type = "advisory_diagnostic",
            rank_ic = rank_ic, icir = icir, ic_t_nw_lag3 = ic_t, monotonicity = mono,
            subperiod_ic = as.list(setNames(sub_ic, c("2005_2014","2015_2019","2020_2026"))),
            subperiod_stability = sub_stab, n_ic_months = nrow(ic_m),
            sigma_cs_monthly = sigma_cs, last_sig_date = as.character(last_dt),
            alpha_vector_formula = "alpha_hat = rank_ic * sigma_cs(36m cross-sectional monthly ret dispersion) * winsorized_z (Grinold)")
write_json(adv, file.path(OUT_CANON, "advisory_diag_chen_welch.json"), auto_unbox = TRUE, pretty = TRUE, digits = 6)
fwrite(AV[order(-alpha_hat)], file.path(OUT_CANON, "alpha_vector_latest.csv"))
cat(sprintf("[saved] alpha_scores.parquet rows=%d | alpha_vector_latest n=%d | last_sig=%s\n",
            nrow(FACTORS), nrow(AV), as.character(last_dt)))
