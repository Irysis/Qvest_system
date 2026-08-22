## run_dfa_t3_identity_r41.R — R41: T3 의 정체 확정 — 알파인가, 베타≠1 효과인가, 대형주 효과인가
## 세 가지를 가른다:
##  (a) PORT_t 는 mean(r - r_parent) 를 보므로 알파와 (beta-1)*E[r_parent] 를 **섞는다**.
##      회귀 r = alpha + beta*r_parent + e 로 분리한다(NW lag-3).
##  (b) ★무신호 대조군: 매 분기 유니버스 시총 상위 25종 cap-w + 상한 0.20.
##      팩터 신호를 전혀 안 쓴다. T3 가 이것과 구별되지 않으면 T3 의 초과수익은 대형주 효과다.
##  (c) T0/T1/M2 도 같은 분해로 병기해 맥락을 준다.
suppressPackageStartupMessages({library(data.table); library(arrow)})
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
suppressMessages({library(sandwich); library(lmtest)})
IRf  <- function(x){ x<-x[is.finite(x)]; if(length(x)<12) return(NA); mean(x)/sd(x)*sqrt(12) }
nwt1 <- function(x){ x<-x[is.finite(x)]; m<-lm(x~1); as.numeric(coeftest(m, vcov=NeweyWest(m,lag=3,prewhite=FALSE))[1,3]) }
MDD  <- function(r){ n<-cumprod(1+r); min(n/cummax(n)-1) }
CAGR <- function(r) prod(1+r)^(12/length(r))-1

Z29 <- readRDS(".cache/_dfa_r29.rds"); Z39 <- readRDS(".cache/_dfa_r39.rds")
mon <- Z29$mon; ym <- mon$ym; MKT <- mon$Market; NM <- nrow(mon)
k <- intersect(Z29$k, Z39$k); ymk <- ym[k]; mk <- MKT[k]

## ── (b) 무신호 대조군: 분기 리밸 시총 상위 25종 cap-w + 상한 0.20 ──
rd <- as.data.table(read_parquet(".cache/rawdata.parquet",
        col_select=c("Date","Ticker","Ret","Size","K200","KQ150")))
rd[, Date:=as.Date(Date)]; rd <- rd[is.finite(Ret)]
rd[, inuniv := (!is.na(K200)&K200==1)|(!is.na(KQ150)&KQ150==1)]; rd <- rd[inuniv==TRUE]
rd[, ymm:=format(Date,"%Y-%m")]
MR  <- rd[, .(mret=prod(1+Ret)-1), by=.(Ticker,ymm)]
UNI <- rd[is.finite(Size)&Size>0, .SD[which.max(Date)], by=.(Ticker,ymm), .SDcols="Size"]
cap_w <- function(w, cap=0.20, it=200){ w<-w/sum(w)
  for (i in 1:it) { ov<-w>cap+1e-12; if(!any(ov)) break
    ex<-sum(w[ov]-cap); w[ov]<-cap; fr<-!ov
    if(!any(fr)||sum(w[fr])<=0) break; w[fr]<-w[fr]+ex*w[fr]/sum(w[fr]) }; w/sum(w) }
rebal_m <- seq(13, NM, by=3)
BIG <- rep(NA_real_, NM); prev <- NULL
for (i in seq_along(rebal_m)) { m0 <- rebal_m[i]
  mend <- if (i<length(rebal_m)) rebal_m[i+1]-1 else NM
  d <- m0-1; if (d<1) next
  u <- UNI[ymm==ym[d]][order(-Size)][1:min(25,.N)]
  if (nrow(u)<10) next
  cur <- setNames(cap_w(u$Size, 0.20), u$Ticker)
  tov <- if (is.null(prev)) 1 else { al<-union(names(cur),names(prev))
    sum(abs(ifelse(is.na(cur[al]),0,cur[al])-ifelse(is.na(prev[al]),0,prev[al])), na.rm=TRUE) }
  for (mm in m0:mend) { rr <- MR[ymm==ym[mm]][match(names(cur),Ticker), mret]; rr[!is.finite(rr)] <- 0
    BIG[mm] <- sum(cur*rr) - (if (mm==m0) (15/1e4)*tov else 0)
    dd <- cur*(1+rr); cur <- dd/sum(dd) }
  prev <- cur }

ARM <- list(T0=Z29$PR[,"T0"], T1=Z29$PR[,"T1"], M2=Z39$PR[,"M2"], T3=Z29$PR[,"T3"], BIG25=BIG)
kk <- k[is.finite(BIG[k])]; b <- MKT[kk]; ymk2 <- ym[kk]

cat("=== [1] 알파/베타 분해 — PORT_t 는 알파와 (β−1)·E[시장] 을 섞는다 ===\n")
cat(sprintf("  E[parent] 연율 = %+.4f\n\n", 12*mean(b)))
cat(sprintf("  %-6s %-6s %9s %8s %9s %10s %10s\n","팔","창","alpha(yr)","beta","t(alpha)","PORT_t","베타기여(yr)"))
res <- list()
for (w in c("full","clean")) {
  ix <- if (w=="full") seq_along(kk) else which(ymk2 >= "2015-07")
  for (a in names(ARM)) {
    x <- ARM[[a]][kk][ix]; y <- b[ix]
    fit <- lm(x ~ y); ct <- coeftest(fit, vcov=NeweyWest(fit, lag=3, prewhite=FALSE))
    al <- 12*ct[1,1]; be <- ct[2,1]; ta <- ct[1,3]
    pt <- nwt1(x - y); bc <- (be-1)*12*mean(y)
    cat(sprintf("  %-6s %-6s %+9.4f %8.4f %+9.3f %+10.3f %+10.4f\n", a, w, al, be, ta, pt, bc))
    res[[paste(a,w)]] <- c(alpha=al, beta=be, t_alpha=ta, port_t=pt, beta_contrib=bc)
  }
  cat("\n")
}
cat("=== [2] ★무신호 대조 — T3 vs BIG25(시총 상위 25종, 팩터 신호 미사용) ===\n")
for (w in c("full","clean")) {
  ix <- if (w=="full") seq_along(kk) else which(ymk2 >= "2015-07")
  t3 <- ARM$T3[kk][ix]; bg <- ARM$BIG25[kk][ix]; y <- b[ix]
  d <- t3 - bg
  cat(sprintf("  [%-5s] n=%3d | T3 활성 %+.4f/yr · BIG25 활성 %+.4f/yr | T3−BIG25 %+.4f/yr NW-t %+.3f\n",
      w, length(ix), 12*mean(t3-y), 12*mean(bg-y), 12*mean(d), nwt1(d)))
  cat(sprintf("           T3 calmar %.4f vs BIG25 %.4f | T3 IR %+.3f vs BIG25 %+.3f | 상관 %.4f\n",
      CAGR(t3)/abs(MDD(t3)), CAGR(bg)/abs(MDD(bg)), IRf(t3-y), IRf(bg-y), cor(t3,bg)))
}
cat("\n=== [3] 판정 ===\n")
tf <- res[["T3 full"]]; tc <- res[["T3 clean"]]
ixc <- which(ymk2 >= "2015-07")
dc <- ARM$T3[kk][ixc] - ARM$BIG25[kk][ixc]
cat(sprintf("  T3 alpha(vs parent, 베타 통제) : full %+.4f/yr t=%+.3f | clean %+.4f/yr t=%+.3f\n",
    tf["alpha"], tf["t_alpha"], tc["alpha"], tc["t_alpha"]))
cat(sprintf("  T3 의 PORT_t 중 베타 기여분     : full %+.4f/yr (PORT_t 가 섞어 보는 부분)\n", tf["beta_contrib"]))
cat(sprintf("  T3 − BIG25 (무신호 대조)        : clean %+.4f/yr NW-t %+.3f\n", 12*mean(dc), nwt1(dc)))
alpha_real <- (abs(tc["t_alpha"]) >= 1.96) || (abs(nwt1(dc)) >= 1.96)
cat(sprintf("\n  ★T3 는 %s\n", ifelse(alpha_real,
  "무신호 대조 또는 베타-통제 알파에서 유의 — screen-tier 소비 후보로 유지",
  "베타-통제 알파도 무신호 대조도 유의하지 않음 — 사실상 대형주 포트폴리오. screen-tier 등재 근거 없음")))
saveRDS(list(res=res, BIG=BIG, kk=kk), ".cache/_dfa_r41.rds")
cat("\nR41_DONE\n")
