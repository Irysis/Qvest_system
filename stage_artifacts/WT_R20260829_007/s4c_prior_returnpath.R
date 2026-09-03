# S4c — 재귀속 잔여축: 선행 런의 **수익 구성 경로**(일간 Ret 복리, 월간 sanity 방화벽 없음)
#   strategy_analyzer.R: Period_Ret = prod(1+Ret) over [exec_d, next_exec]  (RAWDATA 일간 Ret, na.rm)
#   본 라운드: Ret_1m = Close_{t+1}/Close_t - 1  (build_monthly_forward_returns, |ret| 방화벽 (-1, 5])
suppressWarnings(suppressMessages({
  library(data.table); library(jsonlite); library(arrow); library(sandwich); library(lmtest)}))
ROOT <- Sys.getenv("QM_ROOT"); if (!nzchar(ROOT)) ROOT <- getwd(); setwd(ROOT)
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_R20260829_007")
B <- readRDS(file.path(OUT, "s4b_objects.rds")); Q <- B$Q
ME <- sort(unique(Q$Date))

RAW <- as.data.table(arrow::read_parquet(".cache/RAWDATA.parquet", col_select = c("Date","Ticker","Ret")))
RAW[, Date := as.Date(Date)]
RAW <- RAW[Date >= min(ME) & Date <= as.Date("2026-08-31") & Ticker %in% unique(Q$Ticker)]
adates <- sort(unique(RAW$Date))
segs <- rbindlist(lapply(seq_len(length(ME)-1L), function(i) {
  e0 <- adates[adates > ME[i]][1]; e1 <- adates[adates > ME[i+1]][1]
  if (is.na(e0) || is.na(e1)) return(NULL)
  x <- RAW[Date >= e0 & Date <= e1, .(pret = prod(1 + Ret, na.rm = TRUE) - 1), by = Ticker]
  x[, Date := ME[i]][] }), fill = TRUE)
Q2 <- merge(Q, segs, by = c("Date","Ticker"))
cat(sprintf("[S4c] pret 매칭 %d rows | pret range [%.2f, %.2f] | |pret|>5 인 건수 %d (월간 방화벽이 잡는 대상)\n",
            nrow(Q2), min(Q2$pret, na.rm=TRUE), max(Q2$pret, na.rm=TRUE), sum(Q2$pret > 5, na.rm=TRUE)))
cat(sprintf("[S4c] cor(pret, Ret_1m) = %.4f | mean|pret - Ret_1m| = %.5f\n",
            cor(Q2$pret, Q2$Ret_1m, use="pairwise"), mean(abs(Q2$pret - Q2$Ret_1m), na.rm=TRUE)))

nw_prior <- function(x) { x <- x[!is.na(x)]; T_n <- length(x); if (T_n < 5) return(NA_real_)
  xb <- mean(x); L <- max(1, floor(T_n^(1/3))); v <- var(x)
  for (j in seq_len(L)) v <- v + 2*(1 - j/(L+1))*cov(x[1:(T_n-j)], x[(j+1):T_n])
  xb/sqrt(max(v/T_n, 1e-20)) }
zsd <- function(v) (v - mean(v, na.rm=TRUE))/max(sd(v, na.rm=TRUE), 1e-8)

run <- function(scorecol, retcol, wins = NULL, lbl = "") {
  d <- Q2[is.finite(get(scorecol)) & is.finite(Size) & Size > 0 & is.finite(m12) & is.finite(get(retcol)),
          .(Date, S = get(scorecol), lnS = log(Size), M = m12, Y = get(retcol))]
  if (!is.null(wins)) d <- d[, Y := pmin(pmax(Y, -1), wins)]
  co <- d[, { if (.N < 30L) NULL else { m <- copy(.SD)
      m[, `:=`(Sz = zsd(S), Lz = zsd(lnS), Mz = zsd(M))]
      f <- tryCatch(lm(Y ~ Sz + Lz + Mz, data = m), error=function(e) NULL)
      if (is.null(f)) NULL else as.list(coef(f)) } }, by = Date]
  list(label = lbl, score = scorecol, ret = retcol, winsor_cap = wins, n_months = nrow(co),
       lambda_score = mean(co$Sz, na.rm=TRUE), t_score = nw_prior(co$Sz),
       t_size = nw_prior(co$Lz), t_mom = nw_prior(co$Mz)) }

G <- list(
  A_prior_ret_prior_def  = run("prior_score", "pret", NULL, "선행 수익경로(일간복리, 무방화벽) x 선행 정의"),
  B_prior_ret_gh_def     = run("fh252",       "pret", NULL, "선행 수익경로 x GH2004 정의"),
  C_firewalled_prior_def = run("prior_score", "Ret_1m", NULL, "본 라운드 수익경로(방화벽) x 선행 정의"),
  D_prior_ret_capped     = run("prior_score", "pret", 5.0, "선행 수익경로 + 방화벽 상한만 적용"))
cat("\n===== 수익 구성 경로 축 =====\n")
for (nm in names(G)) { x <- G[[nm]]
  cat(sprintf("%-24s lambda=%+8.5f t(Score)=%+7.3f | t(Size)=%+7.3f t(Mom)=%+7.3f n=%d\n",
              nm, x$lambda_score, x$t_score, x$t_size, x$t_mom, x$n_months)) }
cat("선행 런 보고치: lambda +0.00494 t +3.199 | Size t -3.225 | Mom t -1.886 (n=254)\n")

write_json(list(
  meta = list(wt_id = "WT-R20260829_007", test_id = "F4c — 수익 구성 경로 재귀속",
              metric_type = "cross_sectional_regression", envelope_applicability = "NOT_APPLICABLE"),
  return_path_comparison = list(
    cor_pret_vs_Ret1m = cor(Q2$pret, Q2$Ret_1m, use="pairwise"),
    mean_abs_diff = mean(abs(Q2$pret - Q2$Ret_1m), na.rm=TRUE),
    pret_max = max(Q2$pret, na.rm=TRUE), pret_min = min(Q2$pret, na.rm=TRUE),
    n_above_firewall = sum(Q2$pret > 5, na.rm=TRUE)),
  grid = G), file.path(OUT, "s4c_prior_returnpath.json"), pretty = TRUE, auto_unbox = TRUE, digits = 8, na = "null")
cat("\n[S4c] done\n")
