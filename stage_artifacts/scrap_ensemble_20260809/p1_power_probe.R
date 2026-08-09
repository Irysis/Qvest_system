#!/usr/bin/env Rscript
# p1_power_probe.R — Return.portfolio 타이밍/정합 확인 (본 계산 전 사전 확인)
suppressPackageStartupMessages({ library(data.table); library(xts); library(PerformanceAnalytics) })
PROJ <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", ""))
if (!nzchar(PROJ)) PROJ <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(PROJ); OUT <- file.path(PROJ, "stage_artifacts/scrap_ensemble_20260809")

P <- readRDS(file.path(OUT, "p0_panel.rds"))
PAN <- P$PAN; scrap_ok <- P$scrap_ok
cat(sprintf("PAN dim=%dx%d  scrap_ok=%d elite_ok=%d start=%s\n",
            nrow(PAN), ncol(PAN), length(P$scrap_ok), length(P$elite_ok), P$start_ym))
cat("ym head/tail: ", head(PAN$ym,2), " ... ", tail(PAN$ym,2), "\n")
cat("bm range: ", sprintf("%.4f", range(PAN$bm, na.rm=TRUE)), "\n")

sub <- PAN[ym >= P$start_ym & is.finite(bm)]; setorder(sub, ym)
M0  <- as.matrix(sub[, ..scrap_ok])
cov_m <- colSums(is.finite(M0)); keep <- which(cov_m >= 253)
rows <- complete.cases(M0[, keep, drop = FALSE])
M <- M0[rows, keep, drop = FALSE]; ids <- scrap_ok[keep]; bmv <- sub$bm[rows]; ymv <- sub$ym[rows]
cat(sprintf("=== INPUT 실측: %d months x %d modules ; ym %s..%s ===\n",
            nrow(M), ncol(M), ymv[1], ymv[length(ymv)]))
cat(sprintf("월수익 단위 실측: median|r|=%.5f  max|r|=%.4f (소수 단위면 <1)\n",
            median(abs(M)), max(abs(M))))

dts <- as.Date(paste0(substr(ymv,1,4), "-", substr(ymv,5,6), "-01"))
X <- xts(M, order.by = dts)
t0 <- Sys.time()
pr <- Return.portfolio(X[, 1:12], weights = rep(1/12, 12), rebalance_on = "months")
t1 <- Sys.time()
cat(sprintf("Return.portfolio 1회: %.3f s ; 반환 행수=%d (입력 %d)\n",
            as.numeric(difftime(t1,t0,units="secs")), nrow(pr), nrow(X)))
cat("반환 index head: ", format(head(index(pr),2)), " tail: ", format(tail(index(pr),2)), "\n")
cat("cols: ", colnames(pr), "\n")
