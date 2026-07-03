## run_fof_base_diagnosis.R — FoF 기저 진단 + 공정 재시험 (도훈 "돌려" 2026-06-30)
## 증언 후속: 첫 슬라이스 기저가 (1) neutralized_z(시장중립 잔차 — 롱온리가 못 먹음) (2) 11군 flat-EW(죽은 군 희석)로
##            약하게 지어짐. 공정 기저(z + 비-희석)로 재시험하고 "왜 낮았나"를 중립화/희석/근본으로 분해.
## ARM (전부 canonical_screen_bt top25 EW long-only, 동일 forward·15bps·ADV 2e8):
##  A0 : neutralized_z + flat-EW(1/11)           [옛 기저 재현 — sanity]
##  A1 : z            + flat-EW(1/11)            [중립화 penalty 격리 = 공정 기저]
##  A1m: z            + momentum-centric static  [희석 penalty 진단 — hindsight, PIT 주장 아님]
##  B1 : z            + momentum-tilt(동적)       [공정 기저 A1 위 타이밍 재확인]
## 분해: A0→A1 = 중립화 penalty / A1→A1m = 희석 penalty / A1 vs B1 = 타이밍 lift(paired-NW-t lag3)
suppressPackageStartupMessages({library(data.table); library(arrow); library(sandwich); library(lmtest)})
setDTthreads(1); try(arrow::set_io_thread_count(1), silent=TRUE)
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/contracts/canonical_screen_bt.R")
OUT <- "04_Research/factor_rotation/fof_first_slice"
con <- file(file.path(OUT,"_fof_base_diag.txt"),"w",encoding="UTF-8")
w <- function(...) writeLines(paste0(...), con)
zc <- function(x){ m<-mean(x,na.rm=TRUE); s<-sd(x,na.rm=TRUE); if(is.na(s)||s<1e-9) x-m else (x-m)/s }

fam_of <- function(fid){ p<-toupper(substr(fid,1,2)); p1<-substr(p,1,1)
  if(p1=="V") "Value" else if(p1=="M"&&p!="MA") "Momentum" else if(p1=="Q") "Quality"
  else if(p1=="D") "LowRisk" else if(p1=="L") "Size_Liquidity" else if(p1=="S"&&p!="SE") "Size_Liquidity"
  else if(p1=="R") "Reversal" else if(p=="GR") "Growth_Profit" else if(p=="AC") "Accruals"
  else if(p1=="C"&&p!="CR") "Consensus" else if(p=="CR") "Credit" else if(p=="IN") "Growth_Profit"
  else if(p=="XF") "Composite" else if(p=="MA") "Macro" else if(p=="TR") "Size_Liquidity" else "Composite" }
shu2grp <- list(
  Value=c("Value"), Momentum=c("Momentum","ResidMom","SUE"), Quality=c("Quality","GPA","EarnStab"),
  LowRisk=c("LowVol","LowBeta","TailRisk"), Size_Liquidity=c("Size","Liquidity"), Reversal=c("Reversal"),
  Growth_Profit=c("Growth","Investment","Issuance"), Accruals=c("Accrual"),
  Consensus=c("Consensus","ForeignFlow","SmartMoney","Crowding"))
SHU_USED <- unlist(shu2grp); names(SHU_USED)<-NULL
SHU_GAP_GRP <- c("Credit","Composite")

w("================ FoF 기저 진단 + 공정 재시험 ================")
w(sprintf("실행: %s", as.character(Sys.time())))

## ── 1) 신호 2종(z, neutralized_z) 동시 로드 → 11군 group_z ──
sc <- as.data.table(read_parquet("outputs/ramp/pure_factor_scores.parquet",
        col_select=c("signal_date","security_id","factor_id","z","neutralized_z")))
sc[, signal_date := as.Date(signal_date)]
sc[, family := sapply(factor_id, fam_of)]
sc <- sc[family != "Macro"]
w(sprintf("\npure_factor_scores: %d행, 신호컬럼 z/neutralized_z, 팩터군 %d", nrow(sc), length(unique(sc$family))))

build_group_z <- function(sigcol){
  g <- sc[, .(zz = mean(get(sigcol), na.rm=TRUE)), by=.(signal_date, security_id, family)]
  g[, gz := zc(zz), by=.(signal_date, family)]
  g[, .(signal_date, security_id, family, gz)]
}
grpN <- build_group_z("neutralized_z")
grpZ <- build_group_z("z")
GRP_FAMS <- sort(unique(grpZ$family)); nG <- length(GRP_FAMS)
w(sprintf("경제군 %d: %s", nG, paste(GRP_FAMS, collapse=", ")))

## ── 2) family 12-1m momentum (shumulvey, PIT trailing) → 경제군 momentum ──
shu <- as.data.table(read_parquet("outputs/ramp/shumulvey_index_returns_broad.parquet"))
shu[, Date := as.Date(Date)]; shu[, ym := format(Date,"%Y-%m")]
fam_cols <- intersect(SHU_USED, names(shu))
mret <- shu[, lapply(.SD, function(x){ x[is.na(x)]<-0; prod(1+x)-1 }), by=ym, .SDcols=fam_cols]
mend <- shu[, .(meom=max(Date)), by=ym]; mret <- merge(mret, mend, by="ym"); setorder(mret, meom)
fmom_lag <- function(lret_mat, skip_recent){
  T<-nrow(lret_mat); F<-ncol(lret_mat); out<-matrix(NA_real_,T,F)
  for(t in seq_len(T)){ hi<-t-1-skip_recent; lo<-t-12
    if(lo>=1 && hi>=lo) out[t,]<-colSums(lret_mat[lo:hi,,drop=FALSE],na.rm=TRUE) }
  out }
lmat <- as.matrix(log1p(as.matrix(mret[, ..fam_cols])))
fmom_std <- fmom_lag(lmat, 1L)
rownames(fmom_std)<-as.character(mret$meom); colnames(fmom_std)<-fam_cols
grp_mom <- function(fmom_mat){ dt<-data.table(meom=rownames(fmom_mat))
  for(g in GRP_FAMS){ if(g %in% names(shu2grp)){ mem<-intersect(shu2grp[[g]],colnames(fmom_mat))
      dt[[g]]<-rowMeans(fmom_mat[,mem,drop=FALSE],na.rm=TRUE) } else dt[[g]]<-NA_real_ }
  dt }
gm_std <- grp_mom(fmom_std)

## ── 3) 군가중 스킴 ──
W_flat <- setNames(rep(1/nG, nG), GRP_FAMS)
W_momc <- setNames(rep(0, nG), GRP_FAMS)   # momentum-centric static (hindsight 진단)
if("Momentum"%in%GRP_FAMS) W_momc["Momentum"]<-0.7
if("Consensus"%in%GRP_FAMS) W_momc["Consensus"]<-0.3
W_momc <- W_momc/sum(W_momc)
arm_b_weights <- function(gm){ meoms<-gm$meom; Wlist<-list()
  momg<-intersect(names(shu2grp),GRP_FAMS)
  for(i in seq_along(meoms)){ mv<-unlist(gm[i,..momg]); mv<-mv[is.finite(mv)]
    if(length(mv)<3) next
    z<-(mv-mean(mv))/(sd(mv)+1e-12); raw<-pmax(z,0); if(sum(raw)<1e-9) raw[]<-1
    wm<-raw/sum(raw); wfull<-setNames(rep(0,nG),GRP_FAMS); wfull[names(wm)]<-wm
    if(length(SHU_GAP_GRP)>0) wfull[SHU_GAP_GRP]<-mean(wm)
    wfull<-wfull/sum(wfull); Wlist[[as.character(meoms[i])]]<-wfull }
  Wlist }
WB <- arm_b_weights(gm_std)

## ── 4) 종목 score 구성 ──
build_scores <- function(grp_panel, wscheme=NULL, Wlist=NULL){
  out <- copy(grp_panel); out[, ym := format(signal_date,"%Y-%m")]
  if(is.null(Wlist)){ out[, wg := wscheme[family]] }
  else { wdt<-rbindlist(lapply(names(Wlist), function(k) data.table(ym=format(as.Date(k),"%Y-%m"),
            family=names(Wlist[[k]]), wg=as.numeric(Wlist[[k]]))))
    out<-merge(out, wdt, by=c("ym","family"), all.x=TRUE); out<-out[!is.na(wg)] }
  s <- out[, .(score=sum(wg*gz,na.rm=TRUE)), by=.(signal_date, security_id)]
  s[, score := zc(score), by=signal_date]; s }
## 6-arm 2(signal: neutralized/z) × 3(weight: flat/mom-centric/mom-tilt)
scA0 <- build_scores(grpN, W_flat); scA0m<- build_scores(grpN, W_momc); scB0 <- build_scores(grpN, Wlist=WB)
scA1 <- build_scores(grpZ, W_flat); scA1m<- build_scores(grpZ, W_momc); scB1 <- build_scores(grpZ, Wlist=WB)
ALL <- list(scA0,scA0m,scB0,scA1,scA1m,scB1)
common <- Reduce(intersect, lapply(ALL, function(x) unique(x$signal_date)))
common <- sort(as.Date(common, origin="1970-01-01"))
cl <- function(x) x[signal_date%in%common]
scA0<-cl(scA0); scA0m<-cl(scA0m); scB0<-cl(scB0); scA1<-cl(scA1); scA1m<-cl(scA1m); scB1<-cl(scB1)
w(sprintf("공통 signal_date %d개월 (%s ~ %s)", length(common), as.character(min(common)), as.character(max(common))))

## ── 5) canonical_screen_bt ──
bo<-readRDS(".cache/_bo_fwdgic.rds"); fwd<-bo$fwd
ret_dt<-as.data.table(fwd$returns_dt)[,.(Date=as.Date(Date),Ticker,Ret_1m)]
bench_dt<-as.data.table(fwd$bench_dt)[,.(Date=as.Date(Date),BM_Ret)]
liq_dt<-as.data.table(fwd$liq_dt)[,.(Date=as.Date(Date),Ticker,adv)]
run_arm <- function(sdt,id) canonical_screen_bt(scores_dt=sdt[,.(Date=as.Date(signal_date),Ticker=security_id,score)],
  returns_dt=ret_dt, bench_dt=bench_dt, top_n=25L, cost_bps_oneway=15, liq_dt=liq_dt, liq_min=2e8, run_id=id, strategy_id=id)
csA0<-run_arm(scA0,"A0"); csA0m<-run_arm(scA0m,"A0m"); csB0<-run_arm(scB0,"B0")
csA1<-run_arm(scA1,"A1"); csA1m<-run_arm(scA1m,"A1m"); csB1<-run_arm(scB1,"B1")

w("\n=== 6-arm 실측 (signal × weight, metric_type=canonical_screen advisory) ===")
ff<-function(cs,nm) w(sprintf("  [%-30s] port_t=%+.2f (p=%.3f) | net_SR=%+.3f | IR=%+.3f | TO=%.0f%%",
  nm, cs$portfolio_alpha_t_nw_lag3, cs$portfolio_alpha_t_pvalue, cs$net_sr, cs$information_ratio, 100*cs$turnover_annual))
ff(csA0,"A0  neutralized + flat"); ff(csA0m,"A0m neutralized + mom-centric"); ff(csB0,"B0  neutralized + mom-tilt")
ff(csA1,"A1  z + flat"); ff(csA1m,"A1m z + mom-centric"); ff(csB1,"B1  z + mom-tilt")

pt<-function(cs) cs$portfolio_alpha_t_nw_lag3
w("\n=== 분해 (port_t, neutralized 신호 고정 = 부호정렬 confound 없음) ===")
w(sprintf("  희석 penalty (flat→mom-centric): A0 %+.2f → A0m %+.2f  (Δ=%+.2f) ★", pt(csA0), pt(csA0m), pt(csA0m)-pt(csA0)))
w(sprintf("  동적타이밍 vs 정적집중: 정적 A0m %+.2f vs 동적 B0 %+.2f  (Δ=%+.2f)", pt(csA0m), pt(csB0), pt(csB0)-pt(csA0m)))
w(sprintf("  신호 z 민감도 (flat): A0(neut) %+.2f vs A1(z) %+.2f  [⚠ z 부호정렬 미검증 — 참고만]", pt(csA0), pt(csA1)))

## paired NW-t: 동적 타이밍(B0)이 정적 집중(A0m) 초과? (진짜 신규부분 검정, neutralized)
ptest <- function(csX, csA){
  prA<-as.data.table(csA$period_returns)[,.(date=as.Date(date),a=ret_net-benchmark_ret)]
  prB<-as.data.table(csX$period_returns)[,.(date=as.Date(date),b=ret_net-benchmark_ret)]
  D<-merge(prA,prB,by="date"); D[,d:=b-a]; fit<-lm(d~1,data=D)
  nw<-coeftest(fit,vcov=sandwich::NeweyWest(fit,lag=3,prewhite=FALSE)); c(t=as.numeric(nw[1,3]),p=as.numeric(nw[1,4]),n=nrow(D)) }
tB0_A0m <- ptest(csB0,csA0m); tB0_A0 <- ptest(csB0,csA0)
w("\n=== 핵심 검정 (paired-NW-t lag3) ===")
w(sprintf("  동적 mom-tilt(B0) − 정적 mom-centric(A0m): t=%+.2f (p=%.3f) → 타이밍이 정적집중 초과? %s",
          tB0_A0m["t"], tB0_A0m["p"], ifelse(tB0_A0m["t"]>2,"YES","NO(timing 무가치)")))
w(sprintf("  동적 mom-tilt(B0) − flat(A0): t=%+.2f (p=%.3f) → 타이밍이 dilution탈출? %s",
          tB0_A0["t"], tB0_A0["p"], ifelse(tB0_A0["t"]>1.5,"부분 YES","미미")))

saveRDS(list(csA0=csA0,csA0m=csA0m,csB0=csB0,csA1=csA1,csA1m=csA1m,csB1=csB1,
             tB0_A0m=tB0_A0m,tB0_A0=tB0_A0), file.path(OUT,"_fof_base_diag.rds"))
cat(sprintf("DIAG6|A0=%.3f A0m=%.3f B0=%.3f A1=%.3f A1m=%.3f B1=%.3f | dilution_d=%.3f | timing_vs_static_t=%.3f\n",
  pt(csA0),pt(csA0m),pt(csB0),pt(csA1),pt(csA1m),pt(csB1), pt(csA0m)-pt(csA0), tB0_A0m["t"]))
close(con); cat("FOF_BASE_DIAG_DONE\n")
