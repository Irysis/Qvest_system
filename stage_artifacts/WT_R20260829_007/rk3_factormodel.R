# RK3 — BARRA-style 다요인 위험모형: B (노출) · f (요인수익) · u (잔차)
suppressWarnings(suppressMessages({library(data.table); library(arrow); library(jsonlite)}))
ROOT <- Sys.getenv("QM_ROOT"); if(!nzchar(ROOT)) ROOT <- getwd(); setwd(ROOT); Sys.setenv(CLAUDE_PROJECT_DIR=ROOT)
OUT <- file.path(ROOT,"stage_artifacts/WT_R20260829_007")
pn  <- readRDS(file.path(OUT,"panel.rds")); SIG <- as.data.table(pn$SIG)
fwd <- pn$fwd; RET <- as.data.table(fwd$returns_dt)   # Date(=신호월말 t), Ticker, Ret_1m (t -> t+1)
A   <- as.data.table(read_parquet(file.path(OUT,"alpha_scores.parquet")))
ME  <- sort(unique(A$Date))                            # 259 + as_of
univ <- A[,.(Date,Ticker)]                             # alpha 가 쓴 적격 유니버스(PIT 시변)

X <- merge(univ, SIG, by=c("Date","Ticker"), all.x=TRUE)
X <- merge(X, RET[,.(Date,Ticker,Ret_1m)], by=c("Date","Ticker"), all.x=TRUE)
cat("[RK3] panel rows",nrow(X)," months",uniqueN(X$Date)," NA sector",sum(is.na(X$Sector)),"\n")

zwin <- function(v, w=3){ v <- as.numeric(v); ok <- is.finite(v)
  if(sum(ok)<5) return(rep(0,length(v)))
  m <- mean(v[ok]); s <- stats::sd(v[ok]); if(!is.finite(s)||s==0) s <- 1
  z <- (v-m)/s; z[!is.finite(z)] <- 0; pmax(pmin(z,w),-w) }

X[, `:=`(
  SIZE   = zwin(log(pmax(Size,1))),
  MOM    = zwin(jt6),
  REV    = zwin(mret),
  VOL    = zwin(rv63),
  LIQ    = zwin(log(pmax(amih20,1e-14))),   # 높을수록 비유동
  INDMOM = zwin(ind6),
  SIGNAL = zwin(fh252)
), by=Date]
STY <- c("SIZE","MOM","REV","VOL","LIQ","INDMOM","SIGNAL")
X[, sec := fifelse(is.na(Sector),"기타",Sector)]
# 월별 소수 섹터 통합
X[, nsec_m := .N, by=.(Date,sec)]
X[nsec_m < 6L, sec := "기타"]
SECS <- sort(unique(X$sec))
cat("[RK3] 섹터",length(SECS),"· 스타일",length(STY),"\n")

X[, wcap := sqrt(pmax(Size,1))]
X[, wcap := wcap/sum(wcap), by=Date]
X[, r1 := Ret_1m]
X[, r1 := pmax(pmin(r1, quantile(r1, .99, na.rm=TRUE)), quantile(r1, .01, na.rm=TRUE)), by=Date]

months <- ME[ME <= max(RET$Date)]
FR <- vector("list", length(months)); RES <- vector("list", length(months)); BLIST <- list()
for(ii in seq_along(months)){
  d <- months[ii]; xd <- X[Date==d & is.finite(r1)]
  if(nrow(xd) < 60) next
  sec_d <- sort(unique(xd$sec)); S <- length(sec_d)
  Dm <- matrix(0, nrow(xd), S, dimnames=list(NULL, sec_d))
  Dm[cbind(seq_len(nrow(xd)), match(xd$sec, sec_d))] <- 1
  wc <- xd$wcap/sum(xd$wcap); wsec <- as.numeric(t(Dm) %*% wc)
  last <- which.max(wsec)
  Tm <- matrix(0, S, S-1); idx <- setdiff(seq_len(S), last)
  Tm[cbind(idx, seq_len(S-1))] <- 1; Tm[last,] <- -wsec[idx]/wsec[last]
  Bfull <- cbind(MKT=1, Dm, as.matrix(xd[, ..STY]))
  Xr <- cbind(MKT=1, Dm %*% Tm, as.matrix(xd[, ..STY]))
  W <- xd$wcap
  fit <- tryCatch(lm.wfit(Xr, xd$r1, w=W), error=function(e) NULL)
  if(is.null(fit)) next
  g <- fit$coefficients; g[!is.finite(g)] <- 0
  fsec <- as.numeric(Tm %*% g[2:S]); names(fsec) <- sec_d
  fvec <- c(MKT=unname(g[1]), fsec, setNames(unname(g[(S+1):(S+length(STY))]), STY))
  FR[[ii]] <- data.table(Date=d, factor=names(fvec), fret=as.numeric(fvec))
  resid <- xd$r1 - as.numeric(Xr %*% g)
  RES[[ii]] <- data.table(Date=d, Ticker=xd$Ticker, resid=resid, r2w=1-sum(W*resid^2)/sum(W*(xd$r1-sum(W*xd$r1)/sum(W))^2))
  BLIST[[as.character(d)]] <- data.table(Date=d, Ticker=xd$Ticker, sec=xd$sec, Size=xd$Size,
                                          as.data.table(Bfull[, c("MKT", STY), drop=FALSE]))
}
FR <- rbindlist(FR); RES <- rbindlist(RES); BB <- rbindlist(BLIST, fill=TRUE)
cat("[RK3] 요인수익 월",uniqueN(FR$Date)," 요인",uniqueN(FR$factor),"\n")
cat("[RK3] 평균 가중 R2:", round(mean(unique(RES[,.(Date,r2w)])$r2w, na.rm=TRUE),4),"\n")
Fw <- dcast(FR, Date~factor, value.var="fret")
saveRDS(list(X=X, FR=FR, Fw=Fw, RES=RES, BB=BB, STY=STY, SECS=SECS, months=months),
        file.path(OUT,"rk3_objects.rds"))
print(round(sapply(Fw[,-1], function(v) c(mean=mean(v,na.rm=TRUE)*12, sd=sd(v,na.rm=TRUE)*sqrt(12)))[, c("MKT",STY)],4))
cat("[RK3] done\n")
