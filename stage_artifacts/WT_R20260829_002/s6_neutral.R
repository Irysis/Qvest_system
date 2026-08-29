# S6 — post-neutralization IC (size) + 잔여 진단 (WT-R20260829_002)
suppressWarnings(suppressMessages({library(data.table); library(jsonlite); library(sandwich); library(lmtest)}))
ROOT <- Sys.getenv("QM_ROOT"); if (!nzchar(ROOT)) ROOT <- getwd(); setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_R20260829_002")
O <- readRDS(file.path(OUT,"s2_objects.rds"))
S <- O$S; R <- O$R; SIZE <- O$SIZE
nwt <- function(x){x<-x[is.finite(x)]; m<-lm(x~1); as.numeric(coeftest(m,vcov=NeweyWest(m,lag=3,prewhite=FALSE))[1,3])}

D <- merge(S, R[,.(Date,Ticker,Ret_1m)], by=c("Date","Ticker"))
D <- merge(D, SIZE, by=c("Date","Ticker"), all.x=TRUE)
D <- D[is.finite(Size) & Size>0]
D[, lsz := log(Size)]
D[, score_n := residuals(lm(score ~ lsz)), by=Date]

ic_raw <- D[, .(ic=cor(score, Ret_1m, method="spearman")), by=Date][is.finite(ic)]
ic_neu <- D[, .(ic=cor(score_n, Ret_1m, method="spearman")), by=Date][is.finite(ic)]
out <- list(
  rank_ic_raw = mean(ic_raw$ic), rank_ic_raw_t_nw = nwt(ic_raw$ic),
  post_neutralization_ic = mean(ic_neu$ic), post_neutralization_ic_t_nw = nwt(ic_neu$ic),
  retention = mean(ic_neu$ic)/mean(ic_raw$ic), n_months = nrow(ic_raw),
  neutralization = "cross-sectional OLS residual vs log(Size), per month",
  note = "RF-A4 축(post-neutral IC < 0.3 x rank_ic 이면 HIGH) 판정 입력")
write_json(out, file.path(OUT,"s6_neutral.json"), pretty=TRUE, auto_unbox=TRUE, digits=8)
print(unlist(out[1:6]))
