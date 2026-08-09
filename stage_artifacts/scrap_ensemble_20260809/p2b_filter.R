#!/usr/bin/env Rscript
# p2b_filter.R — 면② 필터 재실행 (에러 가시화. p2 순회에서 루프 출력이 침묵 누락된 원인 격리)
suppressPackageStartupMessages({
  library(data.table); library(jsonlite); library(xts); library(PerformanceAnalytics); library(sandwich)
})
PROJ <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", ""))
if (!nzchar(PROJ)) PROJ <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(PROJ); OUT <- file.path(PROJ, "stage_artifacts/scrap_ensemble_20260809")
sink(file.path(OUT, "p2b_filter.log"), split = TRUE)

P <- readRDS(file.path(OUT,"p0_panel.rds")); PAN <- P$PAN; scrap_ok <- P$scrap_ok
sub <- PAN[ym >= P$start_ym & is.finite(bm)]; setorder(sub, ym)
dts <- as.Date(paste0(sub$ym,"01"),"%Y%m%d")
M0 <- as.matrix(sub[, ..scrap_ok]); keepc <- which(colSums(is.finite(M0)) >= 253)
rowsc <- complete.cases(M0[, keepc, drop=FALSE]); M <- M0[rowsc, keepc, drop=FALSE]
bmw <- sub$bm[rowsc]; dtw <- dts[rowsc]
Cc <- cor(M); diag(Cc) <- 0; hi <- which(Cc>=0.999, arr.ind=TRUE); hi <- hi[hi[,1]<hi[,2],,drop=FALSE]
comp <- local({ par<-seq_len(ncol(M)); f<-function(x){while(par[x]!=x)x<-par[x];x}
  if(nrow(hi)) for(r in seq_len(nrow(hi))){a<-f(hi[r,1]);b<-f(hi[r,2]);if(a!=b)par[b]<-a}
  vapply(seq_len(ncol(M)), f, integer(1)) })
reps <- vapply(unique(comp), function(g) which(comp==g)[1], integer(1))
Mu <- M[, reps, drop=FALSE]; n <- nrow(Mu); K <- ncol(Mu); A <- Mu - matrix(bmw, n, K)
IS0 <- 60L; rows <- (IS0+1):n
cat(sprintf("[0] %d months x %d modules\n", n, K))

run_port <- function(W) {
  pr <- Return.portfolio(xts(Mu[rows,,drop=FALSE], order.by=dtw[rows]),
        weights=xts(W[rows,,drop=FALSE], order.by=dtw[rows]), rebalance_on=NA)
  list(r=as.numeric(pr), rr=tail(rows, length(pr)))
}
ewW <- matrix(0, n, K); ewW[rows, ] <- 1/K
b <- run_port(ewW)
pnw <- function(x,y){ d<-x-y; m<-lm(d~1)
  as.numeric(coef(m)[1]/sqrt(NeweyWest(m, lag=3, prewhite=FALSE))[1,1]) }

cat("=== filter loop (errors visible) ===\n")
res <- list()
for (kex in c(10, 20, 30)) {
  out <- tryCatch({
    W <- matrix(0, n, K)
    for (t in IS0:(n-1)) {
      sc <- colMeans(A[1:t, , drop=FALSE])
      keep <- order(sc)[(kex+1):K]
      W[t+1, keep] <- 1/length(keep)
    }
    z <- run_port(W); L <- min(length(z$r), length(b$r))
    dpm <- mean(z$r[1:L]-b$r[1:L]); tt <- pnw(z$r[1:L], b$r[1:L])
    prx <- xts(z$r, order.by=dtw[z$rr])
    ar <- table.AnnualizedReturns(prx, scale=12); md <- as.numeric(maxDrawdown(prx))
    res[[paste0("ex",kex)]] <- list(delta_pm=dpm, t=tt, sharpe=as.numeric(ar[3,1]),
                                    mdd=md, calmar=as.numeric(ar[1,1])/md)
    sprintf("exclude-bottom-%d: d_vs_EW %+.4f%%/m t_NW3=%+.3f | SR=%.3f MDD=%.1f%% Calmar=%.3f",
            kex, 100*dpm, tt, ar[3,1], 100*md, ar[1,1]/md)
  }, error = function(e) sprintf("exclude-bottom-%d: ERROR — %s", kex, conditionMessage(e)))
  cat(" ", out, "\n")
}
write_json(res, file.path(OUT, "p2b_filter.json"), auto_unbox=TRUE, digits=NA, pretty=TRUE)
cat("[done]\n"); sink()
