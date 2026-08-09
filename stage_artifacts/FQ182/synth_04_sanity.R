setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
p0 <- readRDS("stage_artifacts/FQ182/p0.rds"); D <- as.data.frame(p0$D); D$Date <- as.Date(D$Date)
D$yr <- as.integer(format(D$Date,"%Y"))
cat("=== per-year: n, ann vol, n(|ret|>=8%), max ret ===\n")
tb <- do.call(rbind, lapply(split(D, D$yr), function(z)
  data.frame(yr=z$yr[1], n=nrow(z), vol_ann=round(sd(z$BM_Ret)*sqrt(252),3),
             n_big=sum(abs(z$BM_Ret)>=0.08), max_ret=round(max(z$BM_Ret),4),
             min_ret=round(min(z$BM_Ret),4))))
print(tb[order(-tb$vol_ann),][1:8,], row.names=FALSE)
cat("\n=== 2026 rows only ===\n"); print(tb[tb$yr==2026,], row.names=FALSE)
cat("\n=== top 8 |BM_Ret| days ===\n")
o <- D[order(-abs(D$BM_Ret)),][1:8,c("Date","BM_Ret","dd252")]
o$BM_Ret <- round(o$BM_Ret,5); o$dd252 <- round(o$dd252,4); print(o, row.names=FALSE)
cat("\n=== last 25 rows (live episode) ===\n")
print(round(tail(D[,c("BM_Ret","dd252")],25),4))
cat("\n=== sd of BM_Ret: 1991-2025 vs 2026 ===\n")
cat(" pre2026 sd =", sprintf("%.5f", sd(D$BM_Ret[D$yr<2026])),
    " | 2026 sd =", sprintf("%.5f", sd(D$BM_Ret[D$yr==2026])),
    " | ratio =", sprintf("%.2f", sd(D$BM_Ret[D$yr==2026])/sd(D$BM_Ret[D$yr<2026])), "\n")
cat("\n=== R element (monthly?) census ===\n")
R <- p0$R; cat(" class:", class(R)[1], " dim:", paste(dim(R), collapse="x"), "\n"); print(colnames(R))
