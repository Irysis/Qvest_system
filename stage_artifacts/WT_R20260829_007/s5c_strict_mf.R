# S5c — strict 판 FF3/Carhart4/FF5 + 중립화 후 IC + 데실 단조성 (발행 사양 기준 재산출)
suppressWarnings(suppressMessages({
  library(data.table); library(jsonlite); library(xts); library(sandwich); library(lmtest)}))
ROOT <- Sys.getenv("QM_ROOT"); if (!nzchar(ROOT)) ROOT <- getwd(); setwd(ROOT)
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT)
`%or%` <- function(a,b) if (is.null(a) || length(a)==0L || !is.finite(a[1])) b else a
OUT <- file.path(ROOT, "stage_artifacts/WT_R20260829_007")
O5b <- readRDS(file.path(OUT, "s5b_objects.rds")); O4 <- readRDS(file.path(OUT, "s4_objects.rds"))
O2 <- readRDS(file.path(OUT, "s2_objects.rds"))
pr <- O5b$pr_s; X <- O5b$X; P <- O4$P; R <- O2$R

mf <- tryCatch({
  source(file.path(ROOT, "02_Infrastructure/factor_portfolios.R"), local = TRUE)
  fdt <- load_kr_factor_returns()
  run_multifactor_regression(xts(pr$ret_net, order.by = as.Date(pr$date)),
                             xts(pr$benchmark_ret, order.by = as.Date(pr$date)), fdt) },
  error = function(e) list(error = conditionMessage(e)))
mf_out <- if (!is.null(mf$error)) list(error = mf$error) else
  setNames(lapply(names(mf), function(nm) list(model = nm, alpha_monthly = mf[[nm]]$alpha,
    alpha_annual_pct = 100*12*mf[[nm]]$alpha, alpha_t = mf[[nm]]$alpha_tstat,
    adj_r2 = mf[[nm]]$adj_r2 %or% NA_real_)), names(mf))
cat("[S5c] strict multifactor:\n")
if (is.null(mf$error)) for (nm in names(mf_out))
  cat(sprintf("   %-10s alpha=%+6.2f%%/yr t=%+6.3f\n", nm, mf_out[[nm]]$alpha_annual_pct, mf_out[[nm]]$alpha_t))

D <- merge(P[, .(Date, Ticker, Size, rv63, Ret_1m)], X[, .(Date, Ticker, fh_lag1d)], by = c("Date","Ticker"))
D <- D[is.finite(fh_lag1d) & is.finite(Ret_1m)]
ic  <- D[, .(ic = cor(fh_lag1d, Ret_1m, method="spearman"), n=.N), by=Date][n>=30]
D[, fh_resid := { f <- lm(fh_lag1d ~ log(pmax(Size,1)) + rv63, data=.SD); r <- rep(NA_real_, .N)
                  k <- as.integer(names(residuals(f))); r[k] <- residuals(f); r }, by = Date]
icn <- D[is.finite(fh_resid), .(ic = cor(fh_resid, Ret_1m, method="spearman"), n=.N), by=Date][n>=30]
D[, dec := as.integer(pmin(10L, 1L + floor((frank(fh_lag1d, ties.method="first")-0.5)/.N*10))), by = Date]
decs <- D[, .(r_ann = 12*mean(Ret_1m)), by = dec][order(dec)]
mono <- cor(decs$dec, decs$r_ann, method="spearman")
cat(sprintf("[S5c] strict rank_IC %.4f | post-neut IC %.4f (retention %.3f) | monotonicity %.3f\n",
            mean(ic$ic), mean(icn$ic), mean(icn$ic)/mean(ic$ic), mono))
cat(sprintf("[S5c] 데실 연율수익(%%): %s\n", paste(sprintf("%.1f", 100*decs$r_ann), collapse=" ")))

write_json(list(multifactor_alpha = mf_out,
                rank_ic = mean(ic$ic),
                post_neutralization_ic = mean(icn$ic),
                post_neutralization_retention = mean(icn$ic)/mean(ic$ic),
                monotonicity_spearman = mono, decile_ann_returns = decs$r_ann,
                note = "발행 사양(strict-PIT) 기준 재산출. 중립화 = log(Size) + 실현변동성(63d) 단면 회귀 잔차."),
           file.path(OUT, "s5c_strict_mf.json"), pretty = TRUE, auto_unbox = TRUE, digits = 8, na = "null")
cat("[S5c] done\n")
