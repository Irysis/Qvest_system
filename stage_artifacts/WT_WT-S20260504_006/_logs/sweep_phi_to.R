## Quick sweep: φ_TO calibration
suppressPackageStartupMessages({library(arrow); library(data.table); library(quadprog); library(jsonlite); library(digest)})
PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(PROJECT_ROOT)
source("02_Infrastructure/factor_db/factor_db_connector.R")

ART_DIR <- file.path(PROJECT_ROOT, "stage_artifacts/WT_WT-S20260504_006")
WT001_DIR <- file.path(PROJECT_ROOT, "stage_artifacts/WT_WT-S20260504_001")

Gamma_beta <- as.data.table(read_parquet(file.path(ART_DIR, "Gamma_beta_freeze.parquet")))
chars12 <- c("L26_Log_MktCap","V01_BM","V02_EP","M01_Mom_12_1","M02_Mom_6_1",
             "Q01_GPA","Q02_ROE","Q03_ROA","Q07_Earnings_Stability","D02_Beta",
             "R01_VaR_95","L02_Turnover")
Gamma_mat <- as.matrix(Gamma_beta[match(chars12, characteristic), .(LF1, LF2, LF3, LF4, LF5)])

W_S1_001 <- fread(file.path(WT001_DIR, "weights_variants/S1.csv"))
W_S1_001[, as_of_date := as.IDate(as_of_date)]
unique_dates <- sort(unique(W_S1_001$as_of_date))
W_S1_001[, sig_date_for_db := as_of_date - 1L]

solve_qp_hedge <- function(alpha_vec, B_mat, gamma, eps_diag, ub, phi_to=0, w_prev_aligned=NULL) {
  N <- length(alpha_vec)
  D <- gamma * (B_mat %*% t(B_mat)) + (eps_diag + phi_to) * diag(N)
  D <- (D + t(D))/2
  ev <- eigen(D, symmetric=TRUE, only.values=TRUE)$values
  if (min(ev) < 1e-10) D <- D + (1e-10 - min(ev) + 1e-12) * diag(N)
  if (is.null(w_prev_aligned)) {
    d <- as.numeric(alpha_vec)
  } else {
    d <- as.numeric(alpha_vec) + phi_to * as.numeric(w_prev_aligned)
  }
  Amat <- cbind(rep(1, N), diag(N), -diag(N))
  bvec <- c(1, rep(0, N), rep(-ub, N))
  meq <- 1
  res <- tryCatch(solve.QP(Dmat=D, dvec=d, Amat=Amat, bvec=bvec, meq=meq), error=function(e) list(error=e$message))
  if (!is.null(res$error)) return(list(w=NULL, error=res$error))
  w <- res$solution; w[w<0]<-0; w[w>ub]<-ub; s<-sum(w); if(s>0) w <- w/s
  list(w=w, error=NULL)
}

selected_gamma <- 1000
phi_grid <- c(0, 1, 3, 10, 30, 100, 300, 1000, 3000, 10000)

# Cache factor_db loads
fdb_cache <- list()
years_span <- as.numeric(difftime(max(unique_dates), min(unique_dates), units="days"))/365.25

run_one_phi <- function(phi_to) {
  prev_w_hedge <- NULL
  prev_basket <- character(0)
  total_to <- 0
  total_lfc_red <- numeric(0)
  for (k in seq_along(unique_dates)) {
    d <- unique_dates[k]
    basket <- W_S1_001[as_of_date == d]
    sig_d_db <- d - 1L
    key <- as.character(sig_d_db)
    if (is.null(fdb_cache[[key]])) {
      fdb_m <- tryCatch(load_month_factors(sig_d_db), error=function(e) NULL)
      if (is.null(fdb_m)) { fdb_cache[[key]] <<- NULL; next }
      fdb_m_w <- dcast(fdb_m[Factor_Name %in% chars12], Ticker ~ Factor_Name, value.var="Z_Score_Aligned")
      med_m <- apply(as.matrix(fdb_m_w[, chars12, with=FALSE]), 2, median, na.rm=TRUE)
      med_m[is.na(med_m)] <- 0
      fdb_cache[[key]] <<- list(fdb_w=fdb_m_w, med_m=med_m)
    }
    cache_e <- fdb_cache[[key]]
    if (is.null(cache_e)) { Z_m <- matrix(0, nrow=nrow(basket), ncol=length(chars12)) }
    else {
      fdb_m_w <- cache_e$fdb_w
      Z_m <- as.matrix(fdb_m_w[match(basket$Ticker, fdb_m_w$Ticker), chars12, with=FALSE])
      for (j in seq_along(chars12)) Z_m[is.na(Z_m[,j]), j] <- cache_e$med_m[j]
    }
    B_t <- Z_m %*% Gamma_mat
    alpha_t <- basket$Weight
    if (!is.null(prev_w_hedge)) {
      w_prev_aligned <- prev_w_hedge[basket$Ticker]
      w_prev_aligned[is.na(w_prev_aligned)] <- 0
    } else { w_prev_aligned <- NULL }
    res_h <- solve_qp_hedge(alpha_t, B_t, gamma=selected_gamma, eps_diag=1e-4, ub=0.20,
                            phi_to=phi_to, w_prev_aligned=w_prev_aligned)
    w_hedge <- if (is.null(res_h$w)) alpha_t else res_h$w
    # turnover (round-trip per period)
    if (!is.null(prev_w_hedge)) {
      union_keys <- union(names(prev_w_hedge), basket$Ticker)
      pv <- setNames(rep(0, length(union_keys)), union_keys)
      cv <- setNames(rep(0, length(union_keys)), union_keys)
      pv[names(prev_w_hedge)] <- prev_w_hedge
      cv[basket$Ticker] <- w_hedge
      total_to <- total_to + sum(abs(cv - pv))
    }
    # LFC reduction
    B_T <- t(B_t)
    LFC_S1 <- sqrt(sum((B_T %*% alpha_t)^2))
    LFC_h  <- sqrt(sum((B_T %*% w_hedge)^2))
    total_lfc_red <- c(total_lfc_red, 100*(1 - LFC_h/max(LFC_S1, 1e-12)))
    prev_w_hedge <- setNames(w_hedge, basket$Ticker)
  }
  to_annual_rt <- total_to / years_span
  to_annual_oneway <- to_annual_rt / 2
  list(phi=phi_to, to_one_way=to_annual_oneway, to_round_trip=to_annual_rt,
       lfc_red_mean=mean(total_lfc_red, na.rm=TRUE),
       lfc_red_median=median(total_lfc_red, na.rm=TRUE))
}

cat("=== φ_TO sweep ===\n")
results <- list()
for (phi in phi_grid) {
  t0 <- Sys.time()
  r <- run_one_phi(phi)
  cat(sprintf("  φ=%-6g  one-way TO=%.3f (%5.1f%%/yr)  LFC red mean=%5.1f%%  med=%5.1f%%  (%.1fs)\n",
              r$phi, r$to_one_way, 100*r$to_one_way, r$lfc_red_mean, r$lfc_red_median,
              as.numeric(difftime(Sys.time(), t0, units="secs"))))
  results[[as.character(phi)]] <- r
}

write_json(results, file.path(ART_DIR, "_logs/phi_to_sweep.json"), auto_unbox=TRUE, pretty=TRUE)
cat("\nWritten: _logs/phi_to_sweep.json\n")
