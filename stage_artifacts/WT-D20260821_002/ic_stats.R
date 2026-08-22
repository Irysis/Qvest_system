## alpha-style 출력 의무 — rank-IC / ICIR / Harvey-t(rank-IC) / arm 간 상관
## ★rank-IC 계열은 measurement-graduation §3 상 ADVISORY. portfolio-alpha t 와 명확히 구분해 보고.
suppressPackageStartupMessages({library(data.table); library(jsonlite)})
setwd(Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
S <- readRDS("stage_artifacts/WT-D20260821_002/step0_inputs.rds")
frd <- as.data.table(S$frd)

nw_t <- function(x, lag = 3L) {
  x <- x[is.finite(x)]; n <- length(x); m <- mean(x); e <- x - m; s <- sum(e^2)/n
  for (l in 1:lag) { w <- 1 - l/(lag+1); s <- s + 2*w*sum(e[(l+1):n]*e[1:(n-l)])/n }
  m/sqrt(s/n)
}

arms <- list(armA = S$panels$armA[, .(Date, Ticker, sc = as.numeric(score))],
             armB = S$panels$armB[, .(Date, Ticker, sc = as.numeric(q50))],
             armC = S$panels$armC[, .(Date, Ticker, sc = as.numeric(score))])

res <- list()
for (nm in names(arms)) {
  X <- merge(as.data.table(arms[[nm]]), frd[, .(Date, Ticker, Ret_1m)], by = c("Date","Ticker"))
  X <- X[is.finite(sc) & is.finite(Ret_1m)]
  ic <- X[, .(ic = suppressWarnings(cor(sc, Ret_1m, method = "spearman")), n = .N), by = Date][is.finite(ic)]
  ic <- ic[order(Date)]
  m <- mean(ic$ic); s <- sd(ic$ic); k <- nrow(ic)
  res[[nm]] <- list(
    n_months_ic = k, rank_ic_mean = m, rank_ic_sd = s,
    icir_monthly = m/s, icir_annualized = m/s*sqrt(12),
    harvey_t_rank_ic_nw3 = nw_t(ic$ic),
    t_iid = m/(s/sqrt(k)),
    ic_hit_rate = mean(ic$ic > 0),
    subperiod = {
      ic[, blk := cut(Date, breaks = 3, labels = c("P1","P2","P3"))]
      as.list(setNames(ic[, .(v = mean(ic)), by = blk]$v, ic[, unique(blk)]))
    })
}
cat("=== rank-IC (ADVISORY — portfolio-alpha t 와 별개) ===\n")
for (nm in names(res)) {
  r <- res[[nm]]
  cat(sprintf("%s: IC %.5f  sd %.4f  ICIR(ann) %.4f  Harvey-t(NW3) %.3f  hit %.3f  n=%d\n",
              nm, r$rank_ic_mean, r$rank_ic_sd, r$icir_annualized,
              r$harvey_t_rank_ic_nw3, r$ic_hit_rate, r$n_months_ic))
  cat(sprintf("   subperiod IC: %s\n", paste(sprintf("%s=%.5f", names(r$subperiod),
                                                     unlist(r$subperiod)), collapse = " | ")))
}

## arm 간 월내 스코어 랭크 상관 (중복성 진단)
M <- merge(merge(as.data.table(arms$armA)[, .(Date,Ticker,a=sc)],
                 as.data.table(arms$armB)[, .(Date,Ticker,b=sc)], by=c("Date","Ticker")),
           as.data.table(arms$armC)[, .(Date,Ticker,cc=sc)], by=c("Date","Ticker"))
cr <- M[, .(ab = cor(a,b,method="spearman"), ac = cor(a,cc,method="spearman"),
            bc = cor(b,cc,method="spearman")), by = Date]
cat("\n=== arm 간 월내 스코어 순위상관 (중앙값) ===\n")
cat(sprintf("  armA~armB %.4f | armA~armC %.4f | armB~armC %.4f\n",
            median(cr$ab), median(cr$ac), median(cr$bc)))
## top-25 편입 중첩
ov <- M[, {sa <- Ticker[order(-a)][1:25]; sb <- Ticker[order(-b)][1:25]; sc2 <- Ticker[order(-cc)][1:25]
           .(ab = length(intersect(sa,sb))/25, ac = length(intersect(sa,sc2))/25)}, by = Date]
cat(sprintf("  top-25 편입 중첩 중앙값: A∩B %.3f | A∩C %.3f\n", median(ov$ab), median(ov$ac)))

write_json(list(rank_ic = res,
                cross_arm_rank_cor_median = list(armA_armB = median(cr$ab),
                                                 armA_armC = median(cr$ac),
                                                 armB_armC = median(cr$bc)),
                top25_overlap_median = list(armA_armB = median(ov$ab), armA_armC = median(ov$ac))),
           "stage_artifacts/WT-D20260821_002/ic_stats.json",
           auto_unbox = TRUE, pretty = TRUE, digits = 8)
