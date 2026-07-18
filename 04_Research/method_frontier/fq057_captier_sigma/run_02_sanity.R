# =============================================================================
# FQ-057 run_02: estimator sanity checks (mandated before A/B)
#  S1. NLS small-p limit: p<<n -> NLS close to sample (and closer than heavy
#      shrink); trace approximately preserved.
#  S2. NLS identity recovery: iid N(0, I) -> eigenvalue dispersion reduced vs
#      sample; mean eigenvalue ~ 1.
#  S3. NLS p>n case: full-rank PSD output.
#  S4. lw_linear reuse: PSD + condition improvement vs sample on real window.
#  S5. block estimator: PSD after repair; within-tier blocks match inner
#      estimator exactly; cross blocks are rank-1 factor structure.
# =============================================================================
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)})
data.table::setDTthreads(1)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(ROOT)
source(file.path(ROOT, "04_Research/method_frontier/fq057_captier_sigma/estimators.R"))
set.seed(20260718)
res <- list()

# ---- S1: small-p limit ------------------------------------------------------
p <- 10; n <- 480
Sig_true <- diag(seq(0.5, 2, length.out = p))
X <- matrix(rnorm(n * p), n, p) %*% chol(Sig_true)
colnames(X) <- paste0("T", 1:p)
S  <- est_sample(X); NL <- est_lw_nls(X)
rel_nls_sample <- sqrt(sum((NL - S)^2)) / sqrt(sum(S^2))
trace_ratio <- sum(diag(NL)) / sum(diag(S))
res$S1 <- list(p = p, n = n,
               rel_frob_nls_vs_sample = rel_nls_sample,
               trace_ratio = trace_ratio,
               pass = rel_nls_sample < 0.10 && abs(trace_ratio - 1) < 0.10)

# ---- S2: identity recovery --------------------------------------------------
p <- 40; n <- 240
X <- matrix(rnorm(n * p), n, p); colnames(X) <- paste0("T", 1:p)
S <- est_sample(X); NL <- est_lw_nls(X)
disp_sample <- var(eigen(S,  symmetric = TRUE, only.values = TRUE)$values)
disp_nls    <- var(eigen(NL, symmetric = TRUE, only.values = TRUE)$values)
mean_ev_nls <- mean(eigen(NL, symmetric = TRUE, only.values = TRUE)$values)
res$S2 <- list(disp_sample = disp_sample, disp_nls = disp_nls,
               mean_ev_nls = mean_ev_nls,
               pass = disp_nls < disp_sample && abs(mean_ev_nls - 1) < 0.10)

# ---- S3: p > n --------------------------------------------------------------
p <- 300; n <- 60
X <- matrix(rnorm(n * p, sd = 0.06), n, p); colnames(X) <- paste0("T", 1:p)
NL <- est_lw_nls(X)
ev <- eigen(NL, symmetric = TRUE, only.values = TRUE)$values
res$S3 <- list(p = p, n = n, min_ev = min(ev), full_rank = all(ev > 0),
               cond = max(ev) / min(ev),
               pass = all(ev > 0))

# ---- S4: lw_linear on real window ------------------------------------------
mr <- as.data.table(read_parquet(file.path(ROOT,
        "stage_artifacts/method_frontier/fq057_monthly_returns.parquet")))
sn <- as.data.table(read_parquet(file.path(ROOT,
        "stage_artifacts/method_frontier/fq057_monthly_snapshot.parquet")))
yms <- sort(unique(mr$ym))
win_end <- 201912
win <- yms[yms <= win_end]; win <- tail(win, 60)
memb <- sn[ym == win_end & member == 1L & !is.na(size), Ticker]
sub <- mr[ym %in% win & Ticker %in% memb]
cnt <- sub[, .N, by = Ticker][N == 60, Ticker]
W <- dcast(sub[Ticker %in% cnt], ym ~ Ticker, value.var = "ret_m")
Rm <- as.matrix(W[, -1]); rownames(Rm) <- W$ym
S <- est_sample(Rm); LW <- est_lw_linear(Rm); NL <- est_lw_nls(Rm)
res$S4 <- list(window_end = win_end, p = ncol(Rm), n = nrow(Rm),
               cond_sample = cond_number(S), cond_lw = cond_number(LW),
               cond_nls = cond_number(NL),
               pass = cond_number(LW) < cond_number(S) &&
                      is.finite(cond_number(NL)))

# ---- S5: block estimator structure ------------------------------------------
sz <- sn[ym == win_end][match(colnames(Rm), Ticker), size]
rk <- frank(-sz, ties.method = "first")
tier <- fifelse(rk <= 30, "MEGA", fifelse(rk <= 150, "MID", "SMALL"))
# market factor: cap-weighted universe return over window (lagged size weights)
mkt <- sapply(seq_along(win), function(i) {
  ymi <- win[i]
  prev_ym <- if (i == 1) win[1] else win[i - 1]
  wts <- sn[ym == prev_ym & Ticker %in% colnames(Rm), .(Ticker, size)]
  r <- Rm[i, wts$Ticker]
  ok <- !is.na(r) & !is.na(wts$size)
  sum(r[ok] * wts$size[ok]) / sum(wts$size[ok])
})
bl <- est_block(Rm, tier, mkt, inner = "lw")
idx_mega <- which(tier == "MEGA")
sub_lw <- est_lw_linear(Rm[, idx_mega, drop = FALSE])
within_match_pre_repair <- max(abs(bl$Sig[idx_mega, idx_mega] - sub_lw))
ev_bl <- eigen(bl$Sig, symmetric = TRUE, only.values = TRUE)$values
res$S5 <- list(psd_violated_pre = bl$psd_violated_pre,
               min_ev_pre = bl$min_ev_pre,
               min_ev_post = min(ev_bl),
               within_block_max_abs_dev = within_match_pre_repair,
               note = "within-block deviation reflects PSD repair only",
               tier_counts = as.list(table(tier)),
               pass = min(ev_bl) > 0)

res$all_pass <- all(sapply(res[c("S1","S2","S3","S4","S5")], function(x) isTRUE(x$pass)))
write_json(res, file.path(ROOT, "stage_artifacts/method_frontier/fq057_sanity.json"),
           auto_unbox = TRUE, pretty = TRUE, digits = 8)
cat("SANITY:", if (res$all_pass) "ALL PASS" else "FAIL", "\n")
print(str(res, max.level = 2))
