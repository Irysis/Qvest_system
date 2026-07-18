# =============================================================================
# FQ-057 NP4 run_04: 기전 진단 (사전등록 판정 이후의 진단 — 판정 변경 없음)
#  Q1 gross vs net: 격차가 비용 기인인가 (gross paired t)
#  Q2 실현 active vol: lw_nls가 위험이라도 줄였나 (TE 실현치)
#  Q3 포트 유사도: arm 간 실제로 얼마나 다른 포트였나 (L1 거리·보유 overlap)
#  Q4 부기간: pre/post-2017 paired t (cohort decay 국면 분해)
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
  library(sandwich); library(lmtest)
})
data.table::setDTthreads(1)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(ROOT)
OUT_DIR <- file.path(ROOT, "stage_artifacts/method_frontier")

SER <- as.data.table(read_parquet(file.path(OUT_DIR, "np4_series.parquet")))
W   <- as.data.table(read_parquet(file.path(OUT_DIR, "np4_weights.parquet")))
MET <- as.data.table(read_parquet(file.path(OUT_DIR, "np4_cell_meta.parquet")))

nw_t <- function(x, lag = 3L) {
  fit <- lm(x ~ 1)
  ct <- lmtest::coeftest(fit, vcov. = sandwich::NeweyWest(fit, lag = lag, prewhite = FALSE))
  c(mean = unname(ct[1, 1]), t = unname(ct[1, 3]))
}

out <- list()
for (sc in c("S1", "S2")) {
  A <- SER[scenario == sc & arm == "lw_linear"][order(date)]
  B <- SER[scenario == sc & arm == "lw_nls"][order(date)]
  stopifnot(identical(A$date, B$date))
  # Q1 gross paired
  g_diff <- (B$gross - A$benchmark_ret) - (A$gross - A$benchmark_ret)  # = B$gross - A$gross
  q1 <- nw_t(g_diff)
  # Q2 realized active vol / net vol
  q2 <- list(active_vol_ann_A = sd(A$active) * sqrt(12),
             active_vol_ann_B = sd(B$active) * sqrt(12),
             net_vol_ann_A = sd(A$ret_net) * sqrt(12),
             net_vol_ann_B = sd(B$ret_net) * sqrt(12))
  # Q3 포트 유사도 (리밸 시점 target weights)
  wa <- W[scenario == sc & arm == "lw_linear"]
  wb <- W[scenario == sc & arm == "lw_nls"]
  mm <- merge(wa[, .(ym, Ticker, wA = w)], wb[, .(ym, Ticker, wB = w)],
              by = c("ym", "Ticker"), all = TRUE)
  mm[is.na(wA), wA := 0]; mm[is.na(wB), wB := 0]
  sim <- mm[, .(l1 = sum(abs(wA - wB)),
                overlap_n = sum(wA > 1e-6 & wB > 1e-6),
                nA = sum(wA > 1e-6), nB = sum(wB > 1e-6)), by = ym]
  q3 <- list(mean_l1_distance = mean(sim$l1),
             mean_overlap_names = mean(sim$overlap_n),
             mean_names_A = mean(sim$nA), mean_names_B = mean(sim$nB))
  # Q4 subperiod paired (net active diff)
  d <- B$active - A$active
  pre  <- d[A$date <  as.Date("2017-01-01")]
  post <- d[A$date >= as.Date("2017-01-01")]
  q4 <- list(pre2017 = nw_t(pre), post2017 = nw_t(post),
             n_pre = length(pre), n_post = length(post))
  # arm별 부기간 PORT_t
  q5 <- list(
    A_pre_t  = nw_t(A$active[A$date < as.Date("2017-01-01")])[["t"]],
    A_post_t = nw_t(A$active[A$date >= as.Date("2017-01-01")])[["t"]],
    B_pre_t  = nw_t(B$active[B$date < as.Date("2017-01-01")])[["t"]],
    B_post_t = nw_t(B$active[B$date >= as.Date("2017-01-01")])[["t"]])
  out[[sc]] <- list(q1_gross_paired = as.list(round(q1, 5)),
                    q2_realized_vol = lapply(q2, function(z) round(z, 4)),
                    q3_portfolio_similarity = lapply(q3, function(z) round(z, 3)),
                    q4_subperiod_paired = q4, q5_subperiod_arm_t = lapply(q5, function(z) round(z, 3)))
}
# cell meta 요약 (soft violation·hhi)
cm <- MET[, .(mean_n = mean(n_names), mean_hhi = mean(hhi),
              soft_viol_months = sum(!is.na(soft_violation))), by = .(scenario, arm)]
out$cell_meta <- cm

write_json(out, file.path(OUT_DIR, "np4_mechanism.json"), auto_unbox = TRUE,
           pretty = TRUE, digits = 6)
print(out)
cat("[done] run_04 mechanism\n")
