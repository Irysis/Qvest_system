# FQ-057 run_05: challenge-support checks
#  A. tier boundary sensitivity (MID/SMALL cut 100 vs 150 vs 200) on Phase C shares
#  B. warning provenance: run one A/B window with warning capture
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)})
data.table::setDTthreads(1)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(ROOT)
source(file.path(ROOT, "04_Research/method_frontier/fq057_captier_sigma/estimators.R"))
OUT_DIR <- file.path(ROOT, "stage_artifacts/method_frontier")
mr <- as.data.table(read_parquet(file.path(OUT_DIR, "fq057_monthly_returns.parquet")))
sn <- as.data.table(read_parquet(file.path(OUT_DIR, "fq057_monthly_snapshot.parquet")))
yms <- sort(unique(mr$ym))
AS_OF <- max(yms)
memb <- sn[ym == AS_OF & member == 1L & !is.na(size), .(Ticker, size)]
win <- tail(yms[yms <= AS_OF], 60)
sub <- mr[ym %in% win & Ticker %in% memb$Ticker]
full <- sub[, .N, by = Ticker][N == 60, Ticker]
Wc <- dcast(sub[Ticker %in% full], ym ~ Ticker, value.var = "ret_m")
Rm <- as.matrix(Wc[, -1]); uni <- colnames(Rm)
sz <- memb[match(uni, Ticker), size]
rk <- frank(-sz, ties.method = "first")
Sig <- est_lw_nls(Rm)
H <- fread(file.path(ROOT, paste0("05_Production/2.Factor_Model/",
      "2-3.STR_1715_on_M4_R05_noLayer4_PG2/02_holdings_universe/",
      "20260701_noLayer4_weights_cap_0p20.csv")))
Heq <- H[Ticker != "CASH"]
w_book <- setNames(rep(0, length(uni)), uni)
ok <- Heq$Ticker %in% uni
w_book[Heq$Ticker[ok]] <- Heq$Weight[ok]
w_capw <- setNames(sz / sum(sz), uni)
w_ew <- setNames(rep(1/length(uni), length(uni)), uni)
tier_shares <- function(w_active, Sig, tier) {
  m <- as.numeric(Sig %*% w_active); tv <- sum(w_active * m)
  tapply(w_active * m, tier, sum) / tv
}
sens <- list()
for (cut in c(100, 150, 200)) {
  tr <- fifelse(rk <= 30, "MEGA", fifelse(rk <= cut, "MID", "SMALL"))
  sens[[as.character(cut)]] <- list(
    capw = round(tier_shares(w_book - w_capw, Sig, tr), 4),
    ew   = round(tier_shares(w_book - w_ew,   Sig, tr), 4))
}
cat("--- tier boundary sensitivity (cap-w | ew) ---\n")
print(sens)
write_json(sens, file.path(OUT_DIR, "fq057_tier_boundary_sensitivity.json"),
           auto_unbox = TRUE, pretty = TRUE, digits = 6)

# B. warning provenance on one window (2012-07 = former failing window)
t_end <- 201207
win2 <- tail(yms[yms <= t_end], 60)
memb2 <- sn[ym == t_end & member == 1L & !is.na(size), .(Ticker, size)]
sub2 <- mr[ym %in% win2 & Ticker %in% memb2$Ticker]
full2 <- sub2[, .N, by = Ticker][N == 60, Ticker]
W2 <- dcast(sub2[Ticker %in% full2], ym ~ Ticker, value.var = "ret_m")
Rm2 <- as.matrix(W2[, -1])
ws <- character(0)
withCallingHandlers({
  invisible(est_lw_nls(Rm2))
}, warning = function(w) { ws <<- c(ws, conditionMessage(w)); invokeRestart("muffleWarning") })
cat("--- warnings from est_lw_nls on 201207 window ---\n")
print(unique(ws))
cat("done\n")
