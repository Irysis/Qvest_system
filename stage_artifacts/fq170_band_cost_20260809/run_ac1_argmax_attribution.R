## AC1 — 내 프레임의 Q01 argmax 가 왜 D5 인가 (AA1 이 D8 을 맞는 위치로 확정)
## 사전등록: 프레임 축을 하나씩 켜/꺼 argmax 이동을 귀속한다. 판정 = 어느 축이 D8→D5 를 만드는가.
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
DATA_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
CODE_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.claude/worktrees/jovial-mcnulty-f7d018"
setwd(DATA_ROOT)
OUT <- file.path(CODE_ROOT, "stage_artifacts/fq170_band_cost_20260809")

B <- readRDS("stage_artifacts/WT_D20260809_003/merged_panel.rds")
P <- readRDS("stage_artifacts/WT_D20260809_001/p0_panels.rds")
ret <- as.data.table(P$ret)[!is.na(Ret_1m)]; liq <- as.data.table(P$liq)
X0 <- merge(as.data.table(B), ret[, .(Date,Ticker,Ret_1m)], by=c("Date","Ticker"))
X0 <- merge(X0, liq[, .(Date,Ticker,adv)], by=c("Date","Ticker"), all.x=TRUE)

prof <- function(D) {
  D <- D[!is.na(Q01_EB)]
  D[, q := cut(frank(Q01_EB, ties.method="first"),
               breaks=quantile(seq_len(.N), probs=seq(0,1,length.out=11L)),
               include.lowest=TRUE, labels=FALSE), by=Date]
  D[, u := mean(Ret_1m), by=Date]
  M <- D[, .(ex=mean(Ret_1m)-u[1]), by=.(Date,q)][, .(ann=mean(ex)*12*100), by=q][order(q)]
  list(argmax=M$q[which.max(M$ann)], months=uniqueN(D$Date),
       prof=paste(sprintf("%+.2f", M$ann), collapse=" "))
}
rows <- list()
for (lf in c(TRUE, FALSE)) for (nm in c(0L, 50L, 125L)) {
  D <- if (lf) X0[is.na(adv) | adv >= 2e8] else copy(X0)
  if (nm > 0L) { D[, nmo := .N, by=Date]; D <- D[nmo >= nm] }
  r <- prof(D)
  rows[[length(rows)+1L]] <- data.table(liq=lf, nmo_min=nm, months=r$months, argmax=r$argmax, profile=r$prof)
}
R <- rbindlist(rows)
print(R[, .(liq, nmo_min, months, argmax)])
cat("\n=== 프로파일 원문 ===\n")
for (i in 1:nrow(R)) cat(sprintf("  liq=%-5s nmo>=%-3d [%s]  argmax=%d\n", R$liq[i], R$nmo_min[i], R$profile[i], R$argmax[i]))

amx <- unique(R$argmax)
cat(sprintf("\nargmax 값 집합: %s\n", paste(sort(amx), collapse=", ")))
same_liq <- length(unique(R[nmo_min==125L]$argmax)) == 1L
verdict <- if (length(amx) == 1L) "AC1a_STABLE_NOT_A_FRAME_DEFECT" else "AC1b_FRAME_SENSITIVE"
cat(sprintf("판정: %s\n", verdict))
write_json(list(verdict=verdict, results=R), file.path(OUT,"ac1_result.json"),
           pretty=TRUE, auto_unbox=TRUE, digits=NA)
