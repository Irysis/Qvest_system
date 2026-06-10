suppressMessages({library(data.table)})
root <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
p <- fread(file.path(root, "stage_artifacts/WT_WT-D20260610_001/period_returns_sleeve.csv"))
p[, Date := as.Date(Date)]
setorder(p, Date)
af <- 12
# absolute sleeve net SR + CAGR + MDD (PerformanceAnalytics-consistent geometric)
r <- p$ret_net
n <- length(r)
abs_sr <- mean(r)/sd(r)*sqrt(af)
cagr <- prod(1+r)^(af/n) - 1
nav <- cumprod(1+r)
peak <- cummax(nav); dd <- nav/peak - 1; mdd <- min(dd)
# benchmark
br <- p$BM_Ret
bm_cagr <- prod(1+br)^(af/n)-1
bm_sr <- mean(br)/sd(br)*sqrt(af)
cat(sprintf("ABSOLUTE sleeve (net, top-25 EW, 15bps): SR=%.3f CAGR=%.3f MDD=%.3f\n", abs_sr, cagr, mdd))
cat(sprintf("Benchmark (KOSPI200 TR over overlap):    SR=%.3f CAGR=%.3f\n", bm_sr, bm_cagr))
cat(sprintf("ACTIVE (sleeve-bench):                    SR=%.3f mean/mo=%.5f\n", mean(p$active)/sd(p$active)*sqrt(af), mean(p$active)))
# pre/post 2017 absolute and active
for (cut in c("2017-01-01")) {
  pre <- p[Date < as.Date(cut)]; post <- p[Date >= as.Date(cut)]
  cat(sprintf("\n[pre %s] n=%d abs_SR=%.3f active_SR=%.3f active_mean=%.5f active_t(simple)=%.3f\n",
    cut, nrow(pre), mean(pre$ret_net)/sd(pre$ret_net)*sqrt(af),
    mean(pre$active)/sd(pre$active)*sqrt(af), mean(pre$active),
    mean(pre$active)/(sd(pre$active)/sqrt(nrow(pre)))))
  cat(sprintf("[post %s] n=%d abs_SR=%.3f active_SR=%.3f active_mean=%.5f active_t(simple)=%.3f\n",
    cut, nrow(post), mean(post$ret_net)/sd(post$ret_net)*sqrt(af),
    mean(post$active)/sd(post$active)*sqrt(af), mean(post$active),
    mean(post$active)/(sd(post$active)/sqrt(nrow(post)))))
}
# placebo: random top-25 each month active SR distribution? skip — report book-marginal proxy
cat("\n[done]\n")
