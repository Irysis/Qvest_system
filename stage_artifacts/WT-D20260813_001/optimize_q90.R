#==============================================================================
# WT-D20260813_001 — Optimizer Research (q90 pinball)
# metric_type = canonical_screen_diag / tier = screen_diagnostic
# 역할경계: alpha_vector·Σ read-only. weights 결정만.
#==============================================================================
suppressPackageStartupMessages({
  library(arrow); library(data.table); library(jsonlite)
})
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
WT <- "WT-D20260813_001"
SA <- file.path("stage_artifacts", WT)
MB <- file.path("qepm/mailbox/worktask", WT)
source("02_Infrastructure/portfolio/mean_variance_optimizer.R")
source("02_Infrastructure/portfolio/hrp_core.R")

out_log <- c()
logf <- function(...) { m <- paste0(...); out_log[[length(out_log)+1]] <<- m; cat(m, "\n") }

#--- Inputs (read-only) ---
ap <- fromJSON(file.path(MB, "alpha_package.json"), simplifyVector = FALSE)
alpha_vec <- unlist(ap$alpha_vector)
conf_vec  <- unlist(ap$confidence_vector)
tks <- names(alpha_vec)
stopifnot(length(tks) == 25)

covdf <- as.data.frame(read_parquet(file.path(SA, "covariance.parquet")))
rownames(covdf) <- covdf$Ticker
Sigma <- as.matrix(covdf[tks, tks])       # monthly cov, aligned to alpha order
stopifnot(all(rownames(Sigma) == tks))
Sigma_ann <- Sigma * 12                    # annualized for reporting

#--- Sector map (from risk_package concentration; recompute from RAWDATA for per-name) ---
logf("== Liquidity + Sector (RAWDATA 20d avg trading value) ==")
ds <- open_dataset(".cache/RAWDATA.parquet")
# last available date snapshot around sig_date 2026-07-31
raw <- ds |>
  dplyr::filter(Ticker %in% tks) |>
  dplyr::select(Date, Ticker, Close, Vol, Size, Sector, Sector_Lv2) |>
  dplyr::collect() |> as.data.table()
raw <- raw[Date <= as.Date("2026-07-31")]
setorder(raw, Ticker, Date)
# 20d avg trading value = mean(Close*Vol) over last 20 trading days (t-1 PIT: <= sig_date)
liq <- raw[, .(
  tv20 = {
    v <- tail(Close * Vol, 20); mean(v, na.rm = TRUE)
  },
  sector = tail(Sector, 1),
  sector_lv2 = tail(Sector_Lv2, 1),
  size_last = tail(Size, 1)
), by = Ticker]
LIQ_THRESHOLD <- 2e8
liq[, liq_ok := tv20 >= LIQ_THRESHOLD]
liq_flags <- liq[liq_ok == FALSE, .(Ticker, tv20)]
logf(sprintf("  names below 2e8 floor: %d", nrow(liq_flags)))
if (nrow(liq_flags) > 0) print(liq_flags)
sec_map <- setNames(liq$sector, liq$Ticker)[tks]
sec_map[is.na(sec_map)] <- "UNKNOWN"

# semiconductor membership (risk_package: 14 of 25 반도체)
is_semi <- sec_map == "반도체"
logf(sprintf("  semiconductor names: %d / 25", sum(is_semi)))

#==============================================================================
# Snapshot method comparison (as_of = 2026-07-31, current 25-name universe)
#==============================================================================
logf("\n== Method comparison (snapshot, current 25 names) ==")
bounds <- c(0, 0.20)
target_sum <- 1.0

ann_ret <- function(w, mu_monthly) sum(w * mu_monthly) * 12  # expected active/gross ret proxy
port_vol_ann <- function(w) sqrt(as.numeric(t(w) %*% Sigma_ann %*% w))
eff_n <- function(w) 1 / sum(w^2)
semi_wt <- function(w) sum(w[is_semi])
hhi <- function(w) sum(w^2)

# alpha_vector as monthly expected-return proxy (q90 pinball score; NOT re-interpreted, used as mu-hat)
mu <- alpha_vec

results <- list()

## 1) EW baseline (1/N) — Cycle 2 DeMiguel-Garlappi-Uppal reference
w_ew <- setNames(rep(1/25, 25), tks)
results[["EW"]] <- w_ew

## 2) MVO confidence-aware (α̂ = alpha_vec, Σ monthly, λ grid)
# alpha score range 0.104-0.164 -> use as mu directly with lambda tuning
mvo_try <- function(lambda) {
  r <- tryCatch(mvo_weights(
    alpha = mu, cov_matrix = Sigma, confidence = conf_vec,
    lambda = lambda, psi = 0.3, bounds = bounds,
    max_names = 25L, min_names = 15L, hhi_cap = 0.20, alpha_winsor = 2.0,
    active = FALSE
  ), error = function(e) { logf("  MVO err lam=", lambda, ": ", conditionMessage(e)); NULL })
  r
}
mvo_r <- NULL
for (lam in c(2.0, 5.0, 10.0)) {
  rr <- mvo_try(lam)
  if (!is.null(rr)) {
    w <- rr$weights; w <- w[tks]; w[is.na(w)] <- 0
    if (abs(sum(w) - 1) < 1e-6 && max(w) <= 0.2001 && min(w) >= -1e-9) {
      mvo_r <- list(w = w, lambda = lam); break
    }
  }
}
if (is.null(mvo_r)) {
  # fallback: closed-form ridge tilt, project to box
  logf("  MVO registry infeasible -> alpha-tilt fallback")
  a <- (mu - min(mu)); a <- a / sum(a)
  mvo_r <- list(w = setNames(a, tks), lambda = NA)
}
results[["MVO"]] <- setNames(as.numeric(mvo_r$w), tks)

## 3) HRP (Lopez de Prado 2016) — implemented directly from Sigma
hrp_from_cov <- function(S) {
  n <- ncol(S)
  cor_m <- cov2cor(S)
  dist_m <- sqrt(pmax((1 - cor_m) / 2, 0))
  hc <- hclust(as.dist(dist_m), method = "single")
  sort_ix <- hc$order
  get_ivp <- function(idx) { iv <- 1 / diag(S)[idx]; iv / sum(iv) }
  cluster_var <- function(idx) {
    w <- get_ivp(idx); as.numeric(t(w) %*% S[idx, idx, drop=FALSE] %*% w)
  }
  w <- rep(1, n); names(w) <- colnames(S)
  clusters <- list(sort_ix)
  while (length(clusters) > 0) {
    new_clusters <- list()
    for (cl in clusters) {
      if (length(cl) <= 1) next
      half <- floor(length(cl) / 2)
      c1 <- cl[1:half]; c2 <- cl[(half+1):length(cl)]
      v1 <- cluster_var(c1); v2 <- cluster_var(c2)
      alpha <- 1 - v1 / (v1 + v2)
      w[c1] <- w[c1] * alpha
      w[c2] <- w[c2] * (1 - alpha)
      new_clusters <- c(new_clusters, list(c1), list(c2))
    }
    clusters <- new_clusters
  }
  w / sum(w)
}
hrp_w <- tryCatch({
  w <- hrp_from_cov(Sigma); w <- w[tks]
  w <- pmin(w, 0.20); w / sum(w)
}, error = function(e) { logf("  HRP err: ", conditionMessage(e)); NULL })
if (!is.null(hrp_w)) results[["HRP"]] <- setNames(as.numeric(hrp_w), tks)

## 4) ERC (equal risk contribution) — simple iterative
erc_solve <- function(S, iter = 2000) {
  n <- ncol(S); w <- rep(1/n, n)
  for (k in 1:iter) {
    mrc <- as.numeric(S %*% w)
    rc <- w * mrc
    target <- sum(rc) / n
    w <- w * (target / (rc + 1e-12))^0.5
    w <- pmax(w, 0); w <- w / sum(w)
  }
  w
}
w_erc <- erc_solve(Sigma)
# cap at 0.20
w_erc <- pmin(w_erc, 0.20); w_erc <- w_erc / sum(w_erc)
results[["ERC"]] <- setNames(w_erc, tks)

## 5) Alpha-tilt (score-proportional, confidence-weighted) — light, cost-aware
a_conf <- (mu - min(mu) + 1e-6) * conf_vec
w_tilt <- a_conf / sum(a_conf)
w_tilt <- pmin(w_tilt, 0.20); w_tilt <- w_tilt / sum(w_tilt)
results[["AlphaTilt"]] <- setNames(w_tilt, tks)

#==============================================================================
# Sector-capped variants (반도체 <= 50%) applied to selected candidates
#==============================================================================
apply_sector_cap <- function(w, cap = 0.50) {
  w <- w / sum(w)
  sw <- sum(w[is_semi])
  if (sw <= cap + 1e-9) return(w)
  # scale down semis to cap, redistribute to non-semis proportionally
  scale <- cap / sw
  w2 <- w
  w2[is_semi] <- w[is_semi] * scale
  freed <- sum(w) - sum(w2)
  nonsemi <- !is_semi
  w2[nonsemi] <- w2[nonsemi] + freed * (w[nonsemi] / sum(w[nonsemi]))
  # re-enforce 0.20 cap after redistribution
  for (i in 1:50) {
    over <- w2 > 0.20
    if (!any(over)) break
    excess <- sum(w2[over] - 0.20)
    w2[over] <- 0.20
    room <- (!over) & (w2 < 0.20)
    if (!any(room)) break
    w2[room] <- w2[room] + excess * (w2[room] / sum(w2[room]))
  }
  w2 / sum(w2)
}

#==============================================================================
# Evaluate each method
#==============================================================================
metric_row <- function(name, w) {
  data.table(
    method = name,
    exp_active_ret_ann = round(ann_ret(w, mu) - ann_ret(w_ew, mu), 5),  # vs EW as active proxy
    exp_gross_scoresum = round(sum(w * mu), 5),
    port_vol_ann = round(port_vol_ann(w), 4),
    eff_n = round(eff_n(w), 2),
    semi_wt = round(semi_wt(w), 4),
    max_w = round(max(w), 4),
    hhi = round(hhi(w), 4)
  )
}
comp <- rbindlist(lapply(names(results), function(n) metric_row(n, results[[n]])))
logf("\n-- snapshot method table --")
print(comp)

# turnover proxy from current_portfolio unknown at name level -> use EW as neutral prior baseline turnover
# schedule turnover computed below in walk-forward.

fwrite(comp, file.path(SA, "method_comparison_snapshot.csv"))
saveRDS(list(results = results, sec_map = sec_map, is_semi = is_semi, liq = liq,
             mu = mu, conf = conf_vec, Sigma = Sigma),
        file.path(SA, "opt_snapshot.rds"))
writeLines(as.character(unlist(out_log)), file.path(SA, "optimize_log.txt"))
logf("\nSnapshot phase done.")
