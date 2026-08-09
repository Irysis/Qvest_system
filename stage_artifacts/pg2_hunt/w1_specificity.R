## w1 — 계약 특이성의 남은 후보 2종 (발화율 기각 후)
##  ⓐ**경제적 동조** — 계약수주는 실물 사이클, mega_spread 는 대형-소형 상대성과. 둘 다 경기 국면 연동이면
##     ON월 직교성이 '같은 사이클의 서로 다른 위상' 으로 설명된다. 시계열 상관·리드랙으로 측정.
##  ⓑ**국면-적응성** — 계약 슬리브가 ON/OFF 에 따라 다른 종목을 담으면 상관이 국면별로 갈리는 것이 자연스럽다.
##     보유 겹침률로 측정. ★대조: 다른 재료들의 ON/OFF 겹침률(계약만 낮은가)
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/pg2_hunt")
say  <- function(fmt, ...) { cat(sprintf(paste0("[w1] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/contracts/book_marginal.R")
mi <- function(d) as.integer(format(d,"%Y"))*12L + as.integer(format(d,"%m"))

inc <- bm_load_incumbent(); inc[, m := mi(date)]
Mru <- fread(file.path(ROOT,"stage_artifacts/FQ191/p1_rule.csv"))[, date := as.Date(date)][date < as.Date("2026-01-01")]
B <- "04_Research/method_frontier/fq002_contract_magnitude"
R0 <- as.data.table(read_parquet(file.path(B,"gridx_returns.parquet")))[, Date := as.Date(Date)]
R0 <- R0[!(Ret_1m > 5.0 | Ret_1m < -1.0)]
BM <- as.data.table(read_parquet(file.path(B,"gridx_bench.parquet")))[, Date := as.Date(Date)]
US <- as.data.table(read_parquet(file.path(B,"gridx_universe_size.parquet")))[, Date := as.Date(Date)]
PA <- as.data.table(read_parquet(file.path(B,"panelx_A.parquet")))[, ym := as.integer(ym)]
me <- data.table(Date = sort(unique(R0$Date)))[, ym := as.integer(format(Date,"%Y%m"))]
SC <- merge(me, PA[,.(ym,Ticker,w_amt)], by="ym", allow.cartesian=TRUE)
SC <- merge(SC, US[,.(Date,Ticker,Size)], by=c("Date","Ticker"))
SC[, score := ifelse(is.finite(Size)&Size>0, w_amt/Size, NA_real_)]
SC <- SC[is.finite(score)&score>0, .(Date,Ticker,score)]
rt <- R0[!is.na(Ret_1m), .(Date,Ticker,Ret_1m)]; bd <- BM[,.(Date,BM_Ret)]

## mega_spread 재구성 (FQ138 정의: top10 시총 평균수익 − 전체 중앙값)
SZ <- US[, .(Date, Ticker, Size)]
MS <- merge(rt, SZ, by=c("Date","Ticker"))
MS <- MS[, { o <- order(-Size); t10 <- head(o, 10)
             .(ms = mean(Ret_1m[t10], na.rm=TRUE) - median(Ret_1m, na.rm=TRUE)) }, by = Date]
setorder(MS, Date); MS[, m := mi(Date) + 2L]
say("=== mega_spread 재구성 === %d개월 · 중앙 %+.4f · sd %.4f", nrow(MS), median(MS$ms), sd(MS$ms))

say("=== ⓐ 경제적 동조: 계약 신호 총량 vs mega_spread ===")
AGG <- SC[, .(sig_mean = mean(score), sig_n = .N, sig_sum = sum(score)), by = Date][, m := mi(Date) + 2L]
J <- merge(AGG, MS[, .(m, ms)], by = "m")
say("  겹침 %d개월", nrow(J))
say("  %-16s %10s %10s %10s", "계약 총량 축", "동시 rho", "lead1(계약→ms)", "lag1(ms→계약)")
for (v in c("sig_mean","sig_n","sig_sum")) {
  x <- J[[v]]; y <- J$ms
  c0 <- suppressWarnings(cor(x, y, method="spearman"))
  cl <- suppressWarnings(cor(head(x,-1), tail(y,-1), method="spearman"))   # 계약 t → ms t+1
  cg <- suppressWarnings(cor(tail(x,-1), head(y,-1), method="spearman"))   # ms t → 계약 t+1
  say("  %-16s %+10.3f %+14.3f %+12.3f", v, c0, cl, cg)
}
say("  ★|rho|>0.3 이면 두 계열이 같은 사이클에 연동 = 경제적 동조 지지")

say("=== ⓑ 국면-적응성: ON/OFF 보유 종목이 다른가 ===")
hold_of <- function(S, lab) {
  r <- tryCatch(suppressWarnings(canonical_screen_bt(S, rt, bd, top_n=25L, cost_bps_oneway=15,
        run_id=lab, strategy_id=lab, diag_dual_basis=FALSE, size_dt=US[,.(Date,Ticker,Size)])),
        error=function(e) NULL)
  if (is.null(r)) return(NULL)
  H <- as.data.table(r$holdings)
  hd <- names(H)[which(tolower(names(H)) %in% c("date","period"))[1]]
  ht <- names(H)[which(tolower(names(H)) %in% c("ticker","code"))[1]]
  if (is.na(hd) || is.na(ht) || !nrow(H)) return(NULL)
  data.table(m = mi(as.Date(H[[hd]])) + 2L, Ticker = as.character(H[[ht]]))
}
HC <- hold_of(SC, "C")
if (is.null(HC)) { say("  ★계약 슬리브 holdings 미산출 — 적응성 측정 불가"); quit(status=0) }
LB <- data.table(m = mi(Mru$date) + 2L, on = as.logical(Mru$regime))
HC <- merge(HC, LB, by = "m")
say("  계약 보유 %d행 · %d개월 · ON %d개월", nrow(HC), uniqueN(HC$m), uniqueN(HC[on==TRUE, m]))
setON <- unique(HC[on == TRUE, Ticker]); setOFF <- unique(HC[on == FALSE, Ticker])
say("  ON 고유종목 %d · OFF 고유종목 %d · 교집합 %d · **Jaccard %.3f**",
    length(setON), length(setOFF), length(intersect(setON,setOFF)),
    length(intersect(setON,setOFF))/length(union(setON,setOFF)))
## 월-단위 인접 겹침(연속 두 달 보유 겹침) — 국면 전환 시 교체가 큰가
HC2 <- HC[order(m)]; ms <- sort(unique(HC2$m))
ov <- vapply(seq_along(ms)[-1], function(i) {
  a <- HC2[m == ms[i-1], Ticker]; b <- HC2[m == ms[i], Ticker]
  length(intersect(a,b))/max(length(union(a,b)),1L) }, numeric(1))
sw <- vapply(seq_along(ms)[-1], function(i) {
  as.integer(unique(HC2[m==ms[i], on]) != unique(HC2[m==ms[i-1], on])) }, integer(1))
say("  월간 보유 Jaccard: 국면 유지 시 **%.3f** · 국면 전환 시 **%.3f** (n %d/%d)",
    mean(ov[sw==0], na.rm=TRUE), mean(ov[sw==1], na.rm=TRUE), sum(sw==0), sum(sw==1))
say("  ⇒ 전환 시 겹침이 크게 낮으면 **국면-적응성 지지**")

say("=== 대조: 다른 재료의 ON/OFF 보유 Jaccard (계약만 낮은가) ===")
A <- readRDS(file.path(OUT,"factor_long.rds"))
TB <- fread(file.path(OUT,"c6_full_table.csv"))
FS <- TB[is.finite(short_best)][order(short_best)][1:4, factor]
say("  %-26s %10s %12s", "factor", "ON/OFF Jac", "전환시 Jac")
for (f in FS) {
  S <- A[Factor_Name == f, .(Date, Ticker, score = z)][Date %in% SC$Date]
  H <- hold_of(S, f); if (is.null(H)) next
  H <- merge(H, LB, by="m"); if (!nrow(H)) next
  sN <- unique(H[on==TRUE, Ticker]); sF <- unique(H[on==FALSE, Ticker])
  H2 <- H[order(m)]; mm <- sort(unique(H2$m))
  o2 <- vapply(seq_along(mm)[-1], function(i) {
    a <- H2[m==mm[i-1], Ticker]; b <- H2[m==mm[i], Ticker]
    length(intersect(a,b))/max(length(union(a,b)),1L) }, numeric(1))
  s2 <- vapply(seq_along(mm)[-1], function(i) {
    as.integer(unique(H2[m==mm[i], on]) != unique(H2[m==mm[i-1], on])) }, integer(1))
  say("  %-26s %10.3f %12.3f", substr(f,1,26),
      length(intersect(sN,sF))/max(length(union(sN,sF)),1L), mean(o2[s2==1], na.rm=TRUE))
}
say("=== w1 완료 ===")
