# v2_f2.R — 주장 D (F2 개인 순매수, log(시총) 단일 통제 충분성) 반증 시도
suppressPackageStartupMessages({library(data.table); library(arrow); library(sandwich); library(lmtest)})
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260808_001")
IN9 <- file.path(ROOT, "stage_artifacts/WT_D20260802_009")
VER <- file.path(ROOT, "stage_artifacts/wt001_verify")
say <- function(fmt,...) cat(sprintf(paste0("[f2] ",fmt,"\n"), ...))
nw_t <- function(x, lag=3L){ x<-x[is.finite(x)]; if(length(x)<12L) return(NA_real_); f<-lm(x~1)
  tryCatch(as.numeric(lmtest::coeftest(f, vcov.=sandwich::NeweyWest(f,lag=lag,prewhite=FALSE))[1,3]), error=function(e) NA_real_) }
FILT <- c("D03_EWMA","Q01_EB")

fwd <- readRDS(file.path(OUT,"fwd_cache.rds"))
returns_dt <- as.data.table(fwd$returns_dt)[, .(Date=as.Date(Date),Ticker,Ret_1m)]
liq_dt <- as.data.table(fwd$liq_dt)[, .(Date=as.Date(Date),Ticker,adv)]
BASE  <- as.data.table(read_parquet(file.path(IN9,"base_panel.parquet")))[, Date:=as.Date(Date)]
TUNED <- as.data.table(read_parquet(file.path(IN9,"tuned_panel.parquet")))[, Date:=as.Date(Date)]
RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet", col_select=c("Date","Ticker","Size","K200","KQ150")))[, Date:=as.Date(Date)]
RAW[, ym:=format(Date,"%Y-%m")]; MEND <- sort(RAW[, .(Date=max(Date)), by=ym]$Date)
RAWME <- RAW[Date %in% MEND]; rm(RAW); gc(verbose=FALSE)
UNIV <- RAWME[(K200==TRUE|KQ150==TRUE), .(Date,Ticker)]; SIZE <- RAWME[, .(Date,Ticker,Size)]
score_of <- function(f){ sc <- if (f %in% BASE$Factor_Name) BASE[Factor_Name==f,.(Date,Ticker,score=z)]
  else TUNED[Factor_Name==f,.(Date,Ticker,score=score)]; merge(sc[!is.na(score)],UNIV,by=c("Date","Ticker")) }
E <- merge(score_of("M01_PATHQ"), liq_dt, by=c("Date","Ticker"), all.x=TRUE)
E <- E[is.na(adv)|adv>=2e8][, adv:=NULL]; setorder(E,Date,-score); E[, rk:=seq_len(.N), by=Date]
E <- E[Date %in% returns_dt$Date]
FZ <- rbindlist(lapply(c(FILT,"M01_PATHQ"), function(f) score_of(f)[,.(Date,Ticker,fz=score,F_=f)]))
FZ <- merge(FZ, E[,.(Date,Ticker)], by=c("Date","Ticker"))

IND <- as.data.table(read_parquet(".cache/investor_stock/investor_individual.parquet",
        col_select=c("Date","Ticker","NetBuy")))[, Date:=as.Date(Date)]
say("INPUT investor_individual nrow=%d DAILY n_day=%d %s~%s", nrow(IND), uniqueN(IND$Date), min(IND$Date), max(IND$Date))
IND[, ym:=format(Date,"%Y-%m")]
INM <- IND[, .(nb=sum(NetBuy,na.rm=TRUE)), by=.(ym,Ticker)]; rm(IND); gc(verbose=FALSE)
SIGM <- data.table(Date=sort(unique(E$Date)))[, ym:=format(Date,"%Y-%m")]
INM <- merge(INM, SIGM, by="ym")[, ym:=NULL]
INM <- merge(INM, SIZE, by=c("Date","Ticker"))[is.finite(Size)&Size>0]
INM <- merge(INM, liq_dt, by=c("Date","Ticker"), all.x=TRUE)
INM[, `:=`(nb_norm=nb/Size, lsz=log(Size), ladv=log(pmax(adv,1)), lturn=log(pmax(adv,1)/Size))]
INM[, lsz2 := lsz^2]
say("INM nrow=%d n_month=%d | adv 결측 %d (%.1f%%)", nrow(INM), uniqueN(INM$Date), sum(!is.finite(INM$ladv)), 100*mean(!is.finite(INM$ladv)))

fmb <- function(f, rhs) {
  D <- merge(FZ[F_==f, .(Date,Ticker,fz)], INM[, .(Date,Ticker,nb_norm,lsz,lsz2,ladv,lturn)], by=c("Date","Ticker"))
  vars <- c("fz","nb_norm", rhs)
  s <- D[, {
    ok <- Reduce(`&`, lapply(vars, function(v) is.finite(get(v))))
    if (sum(ok)>=30L && sd(fz[ok])>1e-8 && sd(nb_norm[ok])>1e-12) {
      z <- function(v) { u <- v[ok]; (u-mean(u))/sd(u) }
      dd <- data.table(y=z(nb_norm), x=z(fz))
      for (r in rhs) dd[[r]] <- z(get(r))
      fml <- as.formula(paste("y ~ x", if (length(rhs)) paste("+", paste(rhs, collapse="+")) else ""))
      cf <- coef(lm(fml, data=dd))
      .(b=unname(cf["x"]), n=sum(ok))
    } else .(b=NA_real_, n=sum(ok))
  }, by=Date][is.finite(b)]
  list(b=mean(s$b), t=nw_t(s$b), n_month=nrow(s), n_avg=mean(s$n))
}
specs <- list(raw=character(0), size=c("lsz"), size2=c("lsz","lsz2"), adv=c("ladv"),
              size_adv=c("lsz","ladv"), size_turn=c("lsz","lturn"))
F2 <- list()
for (f in c(FILT,"M01_PATHQ")) {
  say("--- %s ---", f)
  for (nm in names(specs)) {
    rhs <- specs[[nm]]
    r <- fmb(f, rhs)
    F2[[paste(f,nm,sep="|")]] <- r
    say("  %-10s rhs={%s}: 기울기 %+.4f  NW3 t %+.2f  n_month=%d n_avg=%.0f",
        nm, paste(rhs,collapse=","), r$b, r$t, r$n_month, r$n_avg)
  }
}
# 팩터 z 간 / 통제변수 간 횡단면 상관
D <- merge(dcast(FZ, Date+Ticker~F_, value.var="fz"), INM[,.(Date,Ticker,lsz,ladv,lturn,nb_norm)], by=c("Date","Ticker"))
cc <- D[, .(d03_lsz=cor(D03_EWMA,lsz,use="pair"), d03_lturn=cor(D03_EWMA,lturn,use="pair"),
            q01_lsz=cor(Q01_EB,lsz,use="pair"), q01_lturn=cor(Q01_EB,lturn,use="pair"),
            m01_lturn=cor(M01_PATHQ,lturn,use="pair"),
            nb_lturn=cor(nb_norm,lturn,use="pair"), nb_lsz=cor(nb_norm,lsz,use="pair")), by=Date]
say("횡단면 상관 중앙값: D03~lsz %+.3f  D03~lturn %+.3f | Q01~lsz %+.3f  Q01~lturn %+.3f | M01~lturn %+.3f | nb_norm~lturn %+.3f  nb_norm~lsz %+.3f",
    median(cc$d03_lsz,na.rm=TRUE), median(cc$d03_lturn,na.rm=TRUE), median(cc$q01_lsz,na.rm=TRUE),
    median(cc$q01_lturn,na.rm=TRUE), median(cc$m01_lturn,na.rm=TRUE), median(cc$nb_lturn,na.rm=TRUE), median(cc$nb_lsz,na.rm=TRUE))
saveRDS(list(F2=F2, cor=cc), file.path(VER,"v2_res.rds"))
say("=== v2 완료 ===")
