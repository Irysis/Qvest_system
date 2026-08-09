#!/usr/bin/env Rscript
# =============================================================================
# p1e — [5b] 에서 P0 §5 기준값 재현 FALSE. 범위·개월수는 정확 일치인데 mean/sd 만 다름.
#   가설 H1: P0 §5 의 상태별 산포는 **dedup 이전 191 모듈** 위에서 계산됐다
#            (중복 그룹이 그 크기만큼 가중돼 평균이 끌림). 내 값은 dedup 85 기준.
#   ★ 어느 쪽이 맞는지가 아니라 **어느 모집단 위의 수치인지**를 확정한다.
# =============================================================================
suppressPackageStartupMessages({ library(data.table) })
PROJ <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", ""))
if (!nzchar(PROJ)) PROJ <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(PROJ); OUT <- file.path(PROJ, "stage_artifacts/scrap_ensemble_20260809")
sink(file.path(OUT, "p1e_discrepancy.log"), split = TRUE)

P <- readRDS(file.path(OUT, "p0_panel.rds")); PAN <- P$PAN; scrap_ok <- P$scrap_ok
sub <- PAN[ym >= P$start_ym & is.finite(bm)]; setorder(sub, ym)
Mall <- as.matrix(sub[, ..scrap_ok]); cov_m <- colSums(is.finite(Mall)); keep <- which(cov_m >= 253)
rows_ok <- complete.cases(Mall[, keep, drop = FALSE])
M <- Mall[rows_ok, keep, drop = FALSE]; bmv <- sub$bm[rows_ok]
C <- cor(M); diag(C) <- 0; hi <- which(C >= 0.999, arr.ind = TRUE); hi <- hi[hi[,1] < hi[,2], , drop=FALSE]
comp <- local({ par <- seq_len(ncol(M)); fnd <- function(x){ while(par[x]!=x) x <- par[x]; x }
  if (nrow(hi)) for (r in seq_len(nrow(hi))) { a<-fnd(hi[r,1]); b<-fnd(hi[r,2]); if(a!=b) par[b]<-a }
  vapply(seq_len(ncol(M)), fnd, integer(1)) })
reps <- vapply(unique(comp), function(g) which(comp==g)[1], integer(1))

st <- ifelse(bmv <= -0.05, "DOWN", ifelse(bmv >= 0.05, "SURGE", "FLAT"))
A191 <- M - matrix(bmv, nrow(M), ncol(M))
A85  <- A191[, reps, drop = FALSE]
cat(sprintf("창 %d개월 | 상태 개월수 DOWN=%d SURGE=%d FLAT=%d\n",
            nrow(M), sum(st=="DOWN"), sum(st=="SURGE"), sum(st=="FLAT")))
cat(sprintf("모집단: 191(dedup 전) vs %d(dedup 후)\n\n", ncol(A85)))

ref <- list(DOWN=c(1.700,1.318,-1.015,7.358), SURGE=c(-2.026,1.345,-7.638,0.049), FLAT=c(0.482,0.290,NA,NA))
cat(sprintf("%-6s %-8s %8s %8s %9s %9s   %s\n","상태","모집단","mean","sd","min","max","P0 mean 일치"))
res <- list()
for (s in c("DOWN","SURGE","FLAT")) {
  for (lab in c("191","85")) {
    Ax <- if (lab=="191") A191 else A85
    v <- 100 * colMeans(Ax[st == s, , drop = FALSE])
    hit <- abs(mean(v) - ref[[s]][1]) < 0.02
    cat(sprintf("%-6s %-8s %+8.3f %8.3f %+9.3f %+9.3f   %s\n",
                s, lab, mean(v), sd(v), min(v), max(v), if (hit) "★일치" else "불일치"))
    res[[paste0(s,"_",lab)]] <- c(mean=mean(v), sd=sd(v))
  }
}
cat("\n=== 판정 ===\n")
h1 <- all(vapply(c("DOWN","SURGE","FLAT"), function(s)
        abs(res[[paste0(s,"_191")]]["mean"] - ref[[s]][1]) < 0.02, logical(1)))
h2 <- all(vapply(c("DOWN","SURGE","FLAT"), function(s)
        abs(res[[paste0(s,"_85")]]["mean"] - ref[[s]][1]) < 0.02, logical(1)))
cat(sprintf("  H1 (P0 §5 = 191 기준) : %s\n", h1))
cat(sprintf("  H2 (P0 §5 =  85 기준) : %s\n", h2))
# 중복 그룹 크기가 평균을 어느 방향으로 끄는지
gs <- vapply(unique(comp), function(g) sum(comp==g), integer(1))
vd85 <- 100*colMeans(A191[st=="DOWN", reps, drop=FALSE])
cat(sprintf("\n  중복 그룹 크기 vs DOWN active 상관 = %+.3f  (음수면 큰 그룹이 낮은 값 → 191 평균이 아래로 끌림)\n",
            cor(gs, vd85)))
cat(sprintf("  최대 그룹 크기 = %d (그룹 %d개 중), 그 그룹 DOWN active = %+.3f%%/m\n",
            max(gs), length(gs), vd85[which.max(gs)]))
cat(sprintf("  가중평균(그룹크기 가중, =191 재현) = %+.3f  vs 비가중(85) = %+.3f\n",
            sum(gs*vd85)/sum(gs), mean(vd85)))
cat("\n[done]\n"); sink()
