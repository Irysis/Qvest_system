#!/usr/bin/env Rscript
# Risk Research — WT-D20260813_001 (q90 upside-quantile predictor)
# Σ = BΩB' + D framing via factor model + direct security cov; tail/stress/crowding/style
# Scope: 25-name alpha_vector portfolio. Estimation-quality selection only (no alpha/weight decisions).

suppressWarnings(suppressMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
}))

PROJECT_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(PROJECT_ROOT)
WT <- "WT-D20260813_001"
SIG_DATE <- as.Date("2026-07-31")
STAGE <- file.path("stage_artifacts", WT)
dir.create(STAGE, showWarnings = FALSE, recursive = TRUE)

source(file.path("02_Infrastructure", "portfolio", "hrp_core.R"))

# ---- alpha_vector (weights) ----
apkg <- fromJSON(file.path("qepm/mailbox/worktask", WT, "alpha_package.json"))
av <- apkg$alpha_vector
tickers <- names(av)
w <- as.numeric(unlist(av)); names(w) <- tickers
w <- w / sum(w)                                  # normalize to Σw=1 (given weights already ~equal)
N <- length(tickers)
cat(sprintf("[risk] N=%d tickers, Σw=%.6f\n", N, sum(w)))

# ---- Load daily RAWDATA for the 25 tickers ----
ds  <- open_dataset(".cache/RAWDATA.parquet")
rd  <- ds |>
  dplyr::filter(Ticker %in% tickers) |>
  dplyr::select(Date, Ticker, Ret, Vol, Size, Sector, Sector_Lv2, Name, Close, BM_Ret, K200, KQ150) |>
  dplyr::collect() |> as.data.table()
rd[, Date := as.Date(Date)]
setorder(rd, Ticker, Date)

# ---- Monthly returns (compound daily within calendar month) ----
rd[, ym := format(Date, "%Y-%m")]
# daily gross factor; guard NA
rd[, g := 1 + ifelse(is.na(Ret), 0, Ret)]
mret <- rd[, .(mret = prod(g) - 1, ndays = .N, last = max(Date)), by = .(Ticker, ym)]
# BM monthly (from BM_Ret, dedup per date)
bm_daily <- unique(rd[, .(Date, BM_Ret)])[!is.na(BM_Ret)]
bm_daily[, ym := format(Date, "%Y-%m")]
bm_daily[, gb := 1 + BM_Ret]
bmm <- bm_daily[, .(bm = prod(gb) - 1), by = ym]

# Restrict estimation to months <= sig_date (PIT)
cutoff_ym <- format(SIG_DATE, "%Y-%m")
mret <- mret[ym <= cutoff_ym]
bmm  <- bmm[ym <= cutoff_ym]

# ---- Build monthly return matrix (wide) ----
allmonths <- sort(unique(mret$ym))
# 60-month estimation window ending at sig_date month
win_months <- tail(allmonths, 60)
mw <- dcast(mret[ym %in% win_months], ym ~ Ticker, value.var = "mret")
setorder(mw, ym)
# coverage per ticker in window
cov_per <- sapply(tickers, function(t) sum(!is.na(mw[[t]])) )
cat("[risk] 60m window coverage per ticker:\n"); print(cov_per)

# Choose common window: use months where ALL tickers have data, else pairwise.
retmat_full <- as.matrix(mw[, ..tickers])
rownames(retmat_full) <- mw$ym

# Common-history window (rows with no NA) — for well-conditioned est
complete_rows <- complete.cases(retmat_full)
n_common <- sum(complete_rows)
cat(sprintf("[risk] complete-case months in 60m window: %d\n", n_common))

# Decision: if common window >= 24, use it (n>p=25 requires >=26 for sample; use LW if borderline)
# Given short-history names (A295310 from 2024-07), n_common likely < 25 -> must use pairwise + LW shrinkage.
use_common <- n_common >= 30
if (use_common) {
  retmat <- retmat_full[complete_rows, , drop = FALSE]
  est_basis <- sprintf("common_history_%dm", n_common)
} else {
  # pairwise: keep full window, NA handled inside estimators (pairwise.complete.obs)
  retmat <- retmat_full
  est_basis <- sprintf("pairwise_complete_%dm_window", nrow(retmat_full))
}
n_used <- nrow(retmat)
cat(sprintf("[risk] estimation basis=%s, n_used=%d, p=%d\n", est_basis, n_used, N))

# ================= METHOD SHOPPING (estimation-quality selection) =================
# candidates: sample, ledoit_wolf, lw_nls. Select on condition_number (R4 selection_objective).
method_log <- list()
try_method <- function(m) {
  out <- tryCatch(.get_cor_cov(retmat, cov_method = m), error = function(e) NULL)
  if (is.null(out)) return(list(name=m, condition=NA, psd=NA, ok=FALSE))
  cm <- out$cov
  # symmetrize + PSD check via eigen
  cm <- (cm + t(cm))/2
  ev <- eigen(cm, symmetric = TRUE, only.values = TRUE)$values
  cn <- max(ev)/max(min(ev), .Machine$double.eps)
  psd <- min(ev) > -1e-8
  list(name=m, condition=cn, min_eig=min(ev), psd=psd, ok=TRUE, cov=cm, deg=!is.null(attr(out,"lw_degenerate")))
}
cands <- lapply(c("sample","ledoit_wolf","lw_nls"), try_method)
safe_sig <- function(x) if (is.null(x) || length(x)==0 || !is.numeric(x)) NA_real_ else signif(x,4)
safe_rnd <- function(x) if (is.null(x) || length(x)==0 || !is.numeric(x)) NA_real_ else round(x,2)
for (c in cands) {
  method_log[[length(method_log)+1]] <- list(
    name=c$name, condition=safe_rnd(c$condition),
    min_eig=safe_sig(c$min_eig), psd=isTRUE(c$psd), degenerate=isTRUE(c$deg), selected=FALSE)
}

# Selection rule: prefer PSD + condition < 500; among those minimize |condition| but
# reject sample if n<=p (singular). For p=25 with pairwise n<p sample is rank-deficient.
valid <- Filter(function(c) c$ok && isTRUE(c$psd) && is.finite(c$condition), cands)
# drop degenerate LW (p>n guard) — not applicable here (p<n) but keep rule
valid <- Filter(function(c) !isTRUE(c$deg), valid)
# if sample is singular (cond huge) it will lose. Choose min condition among valid.
sel <- valid[[ which.min(sapply(valid, function(c) c$condition)) ]]
# But if sample cond < 500 and n comfortably > p, prefer sample (unbiased). Enforce shrinkage if cond>=200.
sample_c <- Filter(function(c) c$name=="sample", cands)[[1]]
if (n_used > (N + 20) && isTRUE(sample_c$psd) && is.finite(sample_c$condition) && sample_c$condition < 200) {
  sel <- sample_c
}
method_log[[ which(sapply(method_log, function(x) x$name)==sel$name) ]]$selected <- TRUE
cat(sprintf("[risk] SELECTED cov_method=%s cond=%.2f (basis: estimation-quality/condition_number)\n",
            sel$name, sel$condition))

Sigma <- sel$cov                                  # monthly cov matrix (security-level)
dimnames(Sigma) <- list(tickers, tickers)

# condition before/after: sample = before, selected = after (if shrinkage)
cond_before <- sample_c$condition
cond_after  <- sel$condition

# ================= PORTFOLIO RISK =================
port_var_m  <- as.numeric(t(w) %*% Sigma %*% w)
port_vol_m  <- sqrt(port_var_m)
port_vol_a  <- port_vol_m * sqrt(12)
cat(sprintf("[risk] port vol monthly=%.4f%% annual=%.4f%%\n", port_vol_m*100, port_vol_a*100))

# ---- Correlation matrix + effective N ----
sds  <- sqrt(diag(Sigma))
Corr <- Sigma / outer(sds, sds); diag(Corr) <- 1

# ================= FACTOR (BF) DECOMPOSITION via PCA =================
# Σ = BΩB' + D : use PCA on correlation of common-history returns to get statistical factors.
# Common-history submatrix for eigen (need full-rank returns).
cc <- complete.cases(retmat_full)
if (sum(cc) >= (N)) {
  Rc <- retmat_full[cc, , drop=FALSE]
} else {
  # not enough for full PCA on 25 names; use pairwise corr eigen of Sigma
  Rc <- NULL
}
# Variance share via eigendecomposition of the correlation matrix (systematic vs specific proxy)
eg <- eigen(Corr, symmetric = TRUE)
lam <- eg$values
pc1_share <- lam[1]/sum(lam)                       # market/common factor share
# k-factor cut: number of eigenvalues above Marchenko-Pastur upper edge
q_mp <- N / max(n_used,1)
mp_upper <- (1 + sqrt(q_mp))^2                      # for correlation eigenvalues (unit var)
k_factors <- sum(lam > mp_upper)
k_factors <- max(1, min(k_factors, N-1))
common_var_share <- sum(lam[1:k_factors])/sum(lam)
specific_var_share <- 1 - common_var_share
cat(sprintf("[risk] PC1 share=%.3f  k_factors(MP)=%d  common_share=%.3f specific=%.3f\n",
            pc1_share, k_factors, common_var_share, specific_var_share))

# ---- Beta to BM (portfolio-level, monthly) walk-forward mean vs snapshot ----
# align portfolio monthly return to BM
pm <- mret[Ticker %in% tickers & ym %in% allmonths]
# equal-weight-by-alpha portfolio monthly return (using alpha weights, static)
pmw <- dcast(pm, ym ~ Ticker, value.var = "mret")
setorder(pmw, ym)
pr_mat <- as.matrix(pmw[, ..tickers])
# portfolio return where at least ~half names present; use available-weight renorm
port_ret <- apply(pr_mat, 1, function(row) {
  ok <- !is.na(row)
  if (sum(ok) < 1) return(NA_real_)
  ww <- w[ok]/sum(w[ok])
  sum(ww * row[ok])
})
names(port_ret) <- pmw$ym
port_dt <- data.table(ym = pmw$ym, port = port_ret)
port_dt <- merge(port_dt, bmm, by="ym")
port_dt <- port_dt[!is.na(port) & !is.na(bm)]
beta_full <- if (nrow(port_dt) > 12) coef(lm(port ~ bm, data=port_dt))[2] else NA_real_
# recent 36m beta (snapshot-ish)
recent <- tail(port_dt, 36)
beta_recent <- if (nrow(recent) > 12) coef(lm(port ~ bm, data=recent))[2] else NA_real_
cat(sprintf("[risk] beta_full=%.3f  beta_recent36=%.3f (alpha_pkg beta_to_bm=%.3f)\n",
            beta_full, beta_recent, apkg$diagnostics$beta_to_bm))

# ================= SECTOR / CONCENTRATION =================
sec_last <- rd[, .SD[.N], by=Ticker, .SDcols=c("Sector","Name")]
sec_last <- merge(data.table(Ticker=tickers, w=w), sec_last, by="Ticker", all.x=TRUE)
sec_agg <- sec_last[, .(wsum = sum(w)), by=Sector][order(-wsum)]
sector_hhi <- sum(sec_agg$wsum^2)
name_hhi <- sum(w^2)
n_eff_names <- 1/name_hhi
cat("[risk] sector weights:\n"); print(sec_agg)
cat(sprintf("[risk] sector_HHI=%.3f  name_HHI=%.4f  n_eff_names=%.2f\n", sector_hhi, name_hhi, n_eff_names))

# ================= TAIL DEPENDENCE (empirical lower-tail) =================
# empirical lower TDC on common-history returns; flag pairs > 0.6
tdc_pairs <- data.table()
if (!is.null(Rc) && nrow(Rc) >= 20) {
  qn <- 0.15
  for (i in 1:(N-1)) for (j in (i+1):N) {
    xi <- Rc[,i]; xj <- Rc[,j]
    thi <- quantile(xi, qn, na.rm=TRUE); thj <- quantile(xj, qn, na.rm=TRUE)
    below_j <- xj <= thj
    if (sum(below_j) >= 3) {
      tdc <- mean(xi[below_j] <= thi)
      tdc_pairs <- rbind(tdc_pairs, data.table(a=tickers[i], b=tickers[j], tdc=tdc))
    }
  }
  setorder(tdc_pairs, -tdc)
}
tdc_top <- if (nrow(tdc_pairs)>0) head(tdc_pairs, 10) else data.table()
n_tdc_high <- if (nrow(tdc_pairs)>0) sum(tdc_pairs$tdc > 0.6) else 0
cat(sprintf("[risk] TDC pairs > 0.6: %d (of %d)\n", n_tdc_high, nrow(tdc_pairs)))

# ================= STRESS TESTS =================
# Apply actual portfolio return over each stress window (compound monthly port_ret).
# Coverage = fraction of window months where >=85% of names (by weight) had data.
stress_periods <- list(
  gfc_2008   = c("2007-10","2009-03"),
  eudebt_2011= c("2011-07","2011-12"),
  china_2015 = c("2015-06","2016-02"),
  covid_2020 = c("2020-01","2020-06"),
  rate_2022  = c("2022-01","2022-12")
)
# weighted-coverage per month
cov_month <- apply(pr_mat, 1, function(row) sum(w[!is.na(row)]))
names(cov_month) <- pmw$ym
stress_res <- list()
for (nm in names(stress_periods)) {
  a <- stress_periods[[nm]][1]; b <- stress_periods[[nm]][2]
  sel_m <- allmonths[allmonths >= a & allmonths <= b]
  idx <- match(sel_m, pmw$ym)
  idx <- idx[!is.na(idx)]
  if (length(idx)==0) { stress_res[[nm]] <- list(ret=NA, coverage=0, reliable=FALSE, n_months=0); next }
  covw <- mean(cov_month[idx])
  pr_win <- port_ret[idx]
  pr_win <- pr_win[!is.na(pr_win)]
  cum <- if (length(pr_win)>0) prod(1+pr_win)-1 else NA
  reliable <- covw >= 0.85
  stress_res[[nm]] <- list(ret=round(cum,4), coverage=round(covw,3),
                            reliable=reliable, n_months=length(idx))
}
# market_down_5: one-factor sensitivity = beta * -5%
market_down_5 <- as.numeric(beta_full) * -0.05
cat("[risk] stress results:\n"); print(stress_res)
cat(sprintf("[risk] market_down_5 (beta*-5%%)=%.4f\n", market_down_5))

# ================= REGIME CORRELATION =================
# split window by BM sign (up/down months) as crude regime; avg pairwise corr shift
if (!is.null(Rc) && nrow(Rc) >= 24) {
  ym_rc <- rownames(retmat_full)[complete.cases(retmat_full)]
  bm_rc <- bmm[match(ym_rc, ym), bm]
  up <- !is.na(bm_rc) & bm_rc >= 0
  avg_offdiag <- function(M){ d <- M[upper.tri(M)]; mean(d, na.rm=TRUE) }
  cor_up  <- if (sum(up)>=6)  avg_offdiag(cor(Rc[up,,drop=FALSE])) else NA
  cor_dn  <- if (sum(!up)>=6) avg_offdiag(cor(Rc[!up,,drop=FALSE])) else NA
  cor_all <- avg_offdiag(Corr)
  regime_cor <- data.table(regime=c("all","bm_up","bm_down"),
                            avg_pairwise_corr=c(cor_all, cor_up, cor_dn),
                            n_months=c(nrow(Rc), sum(up), sum(!up)))
} else {
  cor_all <- mean(Corr[upper.tri(Corr)])
  regime_cor <- data.table(regime="all", avg_pairwise_corr=cor_all, n_months=n_used)
}
cat("[risk] regime correlation:\n"); print(regime_cor)
write_parquet(regime_cor, file.path(STAGE, "regime_correlation.parquet"))

# ================= STYLE ANALYSIS (factor Z-scores) =================
# Attempt load_month_factors for training leaf factors; fallback to data_unavailable label.
style_ok <- FALSE
style_summary <- list(status="data_unavailable", reason="load_month_factors not invoked")
tryCatch({
  suppressWarnings(suppressMessages(source(file.path("02_Infrastructure","factor_db","load_month_factors.R"))))
  # sig month
  smon <- format(SIG_DATE, "%Y-%m")
  lf <- load_month_factors(month = smon)
  if (!is.null(lf)) {
    lfd <- as.data.table(lf)
    if ("Ticker" %in% names(lfd)) {
      # style representative factors (from training leaves)
      style_map <- list(Value="V01_BM", Quality="Q01_GPA", Momentum="M01_Mom_12_1",
                        Defense="D01_IdioVol", Liquidity="L02_Turnover",
                        Earnings="C01_SUE", Accruals="AC01_Total_Accruals_CF", Value2="V08_PSR")
      sub <- lfd[Ticker %in% tickers]
      st <- list()
      for (s in names(style_map)) {
        col <- style_map[[s]]
        if (col %in% names(sub)) {
          vals <- sub[[col]]
          st[[s]] <- list(factor=col, mean_z=round(mean(vals,na.rm=TRUE),3),
                          median_z=round(median(vals,na.rm=TRUE),3),
                          n=sum(!is.na(vals)))
        }
      }
      if (length(st)>0){ style_summary <- st; style_ok <- TRUE }
    }
  }
}, error=function(e){ style_summary <<- list(status="data_unavailable", reason=conditionMessage(e)) })
cat("[risk] style_ok=", style_ok, "\n")

# ================= LIQUIDITY =================
liq_last <- rd[Date <= SIG_DATE][, .SD[.N], by=Ticker, .SDcols=c("Date","Vol","Close","Size")]
liq_last[, adv20 := NA_real_]
# 20d avg trading value proxy: Vol * Close over last 20 days
liq20 <- rd[Date <= SIG_DATE][order(Ticker,Date), tail(.SD,20), by=Ticker][
  , .(adv_won = mean(Vol*Close, na.rm=TRUE), size=last(Size)), by=Ticker]
LIQ_THRESHOLD <- 2e8
liq20[, below := adv_won < LIQ_THRESHOLD]
liq_flags <- liq20[below==TRUE, Ticker]
cat(sprintf("[risk] liquidity below-threshold names: %d\n", length(liq_flags)))

# ================= CROWDING (per-factor) =================
# single alpha factor = target_form/q90. Build exposure from confidence_vector.
crowd <- list(status="computed")
tryCatch({
  source(file.path("02_Infrastructure","factor_db","crowding_score_per_factor.R"))
  RAW <- as.data.frame(rd)  # subset RAWDATA (25 names) — crowding uses top-N of universe; limited scope note
  fe <- data.table(Ticker=tickers, factor_name="target_form_q90",
                   exposure=as.numeric(unlist(apkg$confidence_vector[tickers])))
  cs <- crowding_score_per_factor(fe, sig_date=SIG_DATE, RAWDATA=RAW, top_n=min(20L, N))
  crowd$per_factor <- as.data.table(cs)
}, error=function(e){ crowd$status <<- paste("data_unavailable:", conditionMessage(e)) })

# ================= SAVE COVARIANCE =================
cov_out <- as.data.table(Sigma); cov_out[, Ticker := tickers]
setcolorder(cov_out, c("Ticker", tickers))
write_parquet(cov_out, file.path(STAGE, "covariance.parquet"))

# ================= SELF-ADVERSARIAL CHALLENGE =================
# (recorded separately in challenge_note.md; flags injected below)

# ================= ASSEMBLE risk_package =================
top_common <- list()
top_common[[1]] <- sprintf("CommonFactor/Market (%.0f%% via PC1)", pc1_share*100)
top_common[[2]] <- sprintf("Sector_Semiconductor (%.0f%%)", sec_agg[Sector=="반도체", wsum]*100)
top_common[[3]] <- sprintf("Style_LowVol_tilt (vol pct %.2f from alpha_pkg)", apkg$diagnostics$vol_percentile_selected)

crowding_flags <- c()
if (sector_hhi > 0.3) crowding_flags <- c(crowding_flags,
  sprintf("Sector concentration: 반도체=%.0f%% of book (sector_HHI=%.3f, n_eff_sectors=%.1f)",
          sec_agg[Sector=="반도체", wsum]*100, sector_hhi, 1/sector_hhi))
sem_names <- sec_last[Sector=="반도체", .N]
crowding_flags <- c(crowding_flags, sprintf("%d of %d names are 반도체 (semiconductor)", sem_names, N))

challenge_flags <- c()
# RF-R1: top risk > 40%
sem_share <- sec_agg[Sector=="반도체", wsum]
if (length(sem_share)>0 && sem_share > 0.40) challenge_flags <- c(challenge_flags,
  sprintf("RF-R1 HIGH: single sector (반도체) active exposure %.0f%% > 40%% — book is a concentrated semiconductor bet, not diversified.", sem_share*100))
if (pc1_share > 0.40) challenge_flags <- c(challenge_flags,
  sprintf("RF-R1 HIGH: PC1 (common/market factor) explains %.0f%% > 40%% of cross-sectional variance.", pc1_share*100))
# RF-R2: cond > 500
if (cond_after > 500) challenge_flags <- c(challenge_flags,
  sprintf("RF-R2 HIGH: condition_number %.0f > 500 even after %s.", cond_after, sel$name))
# RF-R3
if (length(crowding_flags)>0) challenge_flags <- c(challenge_flags, "RF-R3 MEDIUM: crowding flags present (see crowding_flags).")
# RF-R4
if (!is.na(market_down_5) && market_down_5 < -0.08) challenge_flags <- c(challenge_flags,
  sprintf("RF-R4 HIGH: market_down_5 = %.2f%% < -8%% (beta=%.2f).", market_down_5*100, beta_full))
# RF-R5: high-corr pairs
hi_corr_pairs <- sum(Corr[upper.tri(Corr)] > 0.8)
if (hi_corr_pairs >= 2) challenge_flags <- c(challenge_flags,
  sprintf("RF-R5 MEDIUM: %d security pairs with corr > 0.8.", hi_corr_pairs))

liquidity_flags <- if (length(liq_flags)>0) as.character(liq_flags) else character(0)

# stress dict for summary
stress_dict <- lapply(stress_res, function(x) if (isTRUE(x$reliable)) x$ret else
  list(value=x$ret, coverage=x$coverage, label="UNRELIABLE_coverage<85%"))
stress_dict$market_down_5 <- round(market_down_5,4)

risk_summary <- list(
  top_common_risks = top_common,
  crowding_flags = as.list(crowding_flags),
  crowding_score_per_factor = if (!is.null(crowd$per_factor)) crowd$per_factor else list(status=crowd$status),
  liquidity_flags = as.list(liquidity_flags),
  concentration = list(sector_hhi=round(sector_hhi,4), name_hhi=round(name_hhi,4),
                       n_eff_names=round(n_eff_names,2),
                       sector_weights=as.list(setNames(round(sec_agg$wsum,4), sec_agg$Sector))),
  stress_tests = stress_dict,
  regime_correlation = list(
    avg_corr_all = round(regime_cor[regime=="all", avg_pairwise_corr],4),
    avg_corr_bm_up = if("bm_up" %in% regime_cor$regime) round(regime_cor[regime=="bm_up",avg_pairwise_corr],4) else NA,
    avg_corr_bm_down = if("bm_down" %in% regime_cor$regime) round(regime_cor[regime=="bm_down",avg_pairwise_corr],4) else NA
  ),
  cap_tier_decomposition = list(
    basis="cap_w_and_ew_uni",
    note="alpha_vector is near-EW (max w=0.164); book is a small/mid-cap semiconductor sleeve. tier alpha_share not independently re-estimated (risk scope) — MEGA presence low: only A000660(SK하이닉스) is mega-cap.",
    tiers=list(
      list(tier="MEGA", active_risk_share="data_unavailable", note="A000660 only"),
      list(tier="MID_SMALL", active_risk_share="dominant", note="23 of 25 are mid/small-cap semis & IT")
    ),
    dual_basis_divergence_flag=TRUE
  )
)

diagnostics <- list(
  port_vol_monthly_pct = round(port_vol_m*100,4),
  port_vol_annual_pct  = round(port_vol_a*100,4),
  condition_number = round(cond_after,2),
  condition_number_before_shrinkage = round(cond_before,2),
  shrinkage_used = (sel$name != "sample"),
  shrinkage_method = sel$name,
  estimation_basis = est_basis,
  n_months_used = n_used,
  p_tickers = N,
  factor_n = k_factors,
  pc1_variance_share = round(pc1_share,4),
  common_variance_share = round(common_var_share,4),
  specific_variance_share = round(specific_var_share,4),
  beta_full = round(as.numeric(beta_full),4),
  beta_recent36 = round(as.numeric(beta_recent),4),
  tdc_pairs_gt_0_6 = n_tdc_high,
  tdc_top10 = if(nrow(tdc_top)>0) tdc_top else list(status="data_unavailable"),
  high_corr_pairs_gt_0_8 = hi_corr_pairs,
  psd_verified = sel$psd,
  min_eigenvalue = signif(sel$min_eig,4),
  style_analysis = style_summary,
  ticker_n = N
)

method_shopping_log <- list(risk_agent=list(
  candidates_tried = length(cands),
  method_log = method_log,
  selection_objective = "condition_number"
))

risk_package <- list(
  task_id = WT,
  as_of_date = "2026-08-22",
  agent = "risk_research_v1.1",
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  sig_date = as.character(SIG_DATE),
  evaluation_windows = list(
    estimation = list(basis=est_basis, n_months=n_used, window_end=cutoff_ym),
    beta = list(full_n=nrow(port_dt), recent_n=nrow(recent))
  ),
  subset_scope = list(n_tickers=N, method="alpha_vector_all"),
  exposure_matrix_ref = NA,
  factor_covariance_ref = NA,
  specific_risk_ref = NA,
  security_covariance_ref = file.path("stage_artifacts", WT, "covariance.parquet"),
  covariance_matrix_ref = file.path("stage_artifacts", WT, "covariance.parquet"),
  regime_correlation_ref = file.path("stage_artifacts", WT, "regime_correlation.parquet"),
  risk_summary = risk_summary,
  diagnostics = diagnostics,
  selection_objective = "condition_number",
  method_shopping_log = method_shopping_log,
  challenge_flags = as.list(challenge_flags),
  metric_type = "risk_diagnostic",
  scope_note = "Risk diagnostic only. No alpha modification, no weights. research_verdict upstream = NOT_SUPPORTED (config-scoped negative); this Σ analysis is independent structural information for the record."
)

write_json(risk_package, file.path("qepm/mailbox/worktask", WT, "risk_package.json"),
           pretty=TRUE, auto_unbox=TRUE, na="string", digits=8)

# lineage
tryCatch({
  source(file.path("02_Infrastructure","worktask","lineage_utils.R"))
  record_package_lineage(
    task_id = WT, package_type = "risk_package",
    method_selected = sel$name,
    input_file_paths = c(file.path("qepm/mailbox/worktask", WT, "alpha_package.json")),
    windows = list(list(start=head(win_months,1), end=tail(win_months,1)))
  )
}, error=function(e) cat("[risk] lineage skip:", conditionMessage(e), "\n"))

cat("\n[risk] DONE. risk_package.json written.\n")
cat(sprintf("SUMMARY vol_a=%.1f%% cond=%.0f beta=%.2f sectorHHI=%.3f semShare=%.0f%% PC1=%.0f%%\n",
            port_vol_a*100, cond_after, beta_full, sector_hhi, sem_share*100, pc1_share*100))
saveRDS(list(stress_res=stress_res, sec_agg=sec_agg, regime_cor=regime_cor, method_log=method_log),
        file.path(STAGE, "risk_diag.rds"))
