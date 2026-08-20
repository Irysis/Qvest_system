## run_ramp_shumulvey_v5_verify.R — v5 게이트 4종 + M0↔D1 paired 판정 (FQ-239 P1).
## prereg gates_before_headline: ①assert_overlay_pit ②lag1(T+3 완만감쇠) ③strict A/B(T+0 인플레 문서화) ④placebo 30-seed.
## env: SMV_KEY(검증 대상 결과 키, default f15) / SMV_PLACEBO_N(default 30) / SMV_SKIP_SUBRUNS(1이면 하위실행 생략, 집계만)
## 하위실행 env 전달 = -e 문자열 인자 주입 (r-portability 금칙①: system2(env=) 금지 준수).
suppressPackageStartupMessages({library(data.table)})
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
suppressMessages({library(sandwich);library(lmtest)})
source("02_Infrastructure/validation/overlay_pit_guard.R")

KEY<-Sys.getenv("SMV_KEY","f15")
NPL<-as.integer(Sys.getenv("SMV_PLACEBO_N","30"))
SKIP<-nzchar(Sys.getenv("SMV_SKIP_SUBRUNS",""))
Z<-readRDS(sprintf(".cache/_smv_v5_%s.rds",KEY)); RES<-Z$RES
nwt<-function(x){x<-x[is.finite(x)];if(length(x)<12)return(NA);m<-lm(x~1);as.numeric(coeftest(m,vcov=sandwich::NeweyWest(m,lag=3,prewhite=F))[1,3])}
IRf<-function(x){x<-x[is.finite(x)];if(length(x)<6)return(NA);mean(x)/sd(x)*sqrt(12)}

hd<-function(a_,l_,t_,b_){ i<-RES$arm==a_ & RES$te==t_ & RES$cost_bps==b_ &
    (if(is.na(l_)) is.na(RES$lam_mult) else (!is.na(RES$lam_mult) & RES$lam_mult==l_))
  RES[which(i)][1] }
run_engine<-function(kv){  # kv = named list of SMV_* values → 하위 Rscript 인자 주입
  setenv_str<-paste(sprintf('Sys.setenv(%s="%s")',names(kv),unlist(kv)),collapse="; ")
  code<-paste0(setenv_str,'; source("02_Infrastructure/ramp/run_ramp_shumulvey_v5_daily.R")')
  system2("Rscript", args=c("-e", shQuote(code)), stdout=TRUE, stderr=TRUE)
}

cat("=== v5 verify (KEY=",KEY,") ===\n",sep="")

## ---- 게이트 ①: PIT 구조 검사 (회계 구조상 컷오프 < 적용일 전수) ----
suppressPackageStartupMessages(library(arrow))
R<-as.data.table(read_parquet(Z$idxfile)); R[,Date:=as.Date(Date)]; setorder(R,Date); R<-R[is.finite(Market)]
d<-R$Date; n<-length(d)
## D1: 결정일 T = d[t-2], 적용일 = d[t]
assert_overlay_pit(d[1:(n-2)], d[3:n], label="v5_D1_T+2")
## M0: 결정 = 월말 medates[mi], 적용 = 익월 첫 거래일
me<-Z$medates; ym_all<-format(d,"%Y-%m"); firsts<-d[!duplicated(ym_all)]
mfirst<-firsts[match(format(as.Date(paste0(substr(format(me,"%Y-%m"),1,7),"-01"))+32,"%Y-%m"),format(firsts,"%Y-%m"))]
okm<-is.finite(mfirst)
assert_overlay_pit(me[okm], mfirst[okm], label="v5_M0_nextmonth")
cat("[게이트①] assert_overlay_pit PASS (D1 T+2 전수, M0 익월 전수)\n")

## ---- M0 ↔ D1 paired (헤드라인 셀: TE3, lm=1, 5/15bps) ----
pair_tbl<-list()
for(bps in c(5,15)){
  m0<-hd("M0",NA,3,bps); d1<-hd("D1",1,3,bps)
  if(!nrow(m0)||!nrow(d1)||is.null(m0$series[[1]])||is.null(d1$series[[1]])) next
  s0<-m0$series[[1]]; s1<-d1$series[[1]]
  mm<-intersect(substr(s0$months,1,7), s1$months)
  i0<-match(mm,substr(s0$months,1,7)); i1<-match(mm,s1$months)
  dact<-s1$actM[i1]-s0$actM[i0]
  mktm<-s0$pr[i0]-s0$actM[i0]   # 시장 월수익 복원
  crisis<-which(mktm<=quantile(mktm,0.05,na.rm=TRUE))
  pair_tbl[[length(pair_tbl)+1]]<-data.table(cost_bps=bps, n_common=length(mm),
    d1_IRvsEW=d1$IR_vsEW, m0_IRvsEW=m0$IR_vsEW, dIR=d1$IR_vsEW-m0$IR_vsEW,
    d1_pt=d1$pt_capwt, m0_pt=m0$pt_capwt,
    paired_nwt_actM=nwt(dact),
    crisis_mean_actE_d1=mean(s1$actE[i1][crisis],na.rm=TRUE),
    crisis_mean_actE_m0=mean(s0$actE[i0][crisis],na.rm=TRUE))
}
PAIR<-rbindlist(pair_tbl); cat("\n[M0 vs D1 — 헤드라인 TE3]\n"); print(PAIR,digits=3)

## ---- 게이트 ②③: lag1(T+3) + strict(T+0) — 하위실행 (헤드라인 셀만) ----
fs<-RES$featset[1]
if(!SKIP){
  for(sh in c(3,0)){
    run_engine(list(SMV_IDXFILE=Z$idxfile, SMV_FEATSET=fs, SMV_ARMS="D1", SMV_LAMMULT="1",
                    SMV_TE="3", SMV_SHIFT=as.character(sh), SMV_KEY=sprintf("%s_sh%d",KEY,sh)))
  }
}
sh_rows<-list()
for(sh in c(3,0)){ f<-sprintf(".cache/_smv_v5_%s_sh%d.rds",KEY,sh)
  if(file.exists(f)){ r<-readRDS(f)$RES; r<-r[arm=="D1"&te==3]; sh_rows[[length(sh_rows)+1]]<-r[,!"series"] } }
base_row<-RES[arm=="D1"&(!is.na(lam_mult)&lam_mult==1)&te==3,!"series"]
SH<-rbindlist(c(list(base_row),sh_rows),fill=TRUE)
cat("\n[게이트②③ — shift 사다리: 0(동월성 재현)/2(정본)/3(lag1)]\n"); print(SH[order(acct_shift)],digits=3)
for(bps in c(5,15)){
  a<-SH[cost_bps==bps]
  if(nrow(a)>=3){
    v2<-a[acct_shift==2]$IR_vsEW; v3<-a[acct_shift==3]$IR_vsEW; v0<-a[acct_shift==0]$IR_vsEW
    ab0<-overlay_lookahead_ab(v0, v2, sprintf("D1 %dbps IR_vsEW T+0 vs T+2",bps))
    cat(sprintf("  [%dbps] lag1 감쇠: T+2 %.3f -> T+3 %.3f (Δ %.3f) | T+0 인플레: %.3f -> %.3f\n",bps,v2,v3,v3-v2,v0,v2))
  }
}

## ---- 게이트 ④: placebo (뷰 월-블록 셔플, 헤드라인 D1 TE3 lm1) ----
if(!SKIP){
  for(sd in seq_len(NPL)){
    f<-sprintf(".cache/_smv_v5_%s_p%d.rds",KEY,sd); if(file.exists(f))next
    run_engine(list(SMV_IDXFILE=Z$idxfile, SMV_FEATSET=fs, SMV_ARMS="D1", SMV_LAMMULT="1",
                    SMV_TE="3", SMV_PLACEBO_SEED=as.character(sd), SMV_KEY=sprintf("%s_p%d",KEY,sd)))
    cat(sprintf("  placebo %d/%d done\n",sd,NPL))
  }
}
pl<-list()
for(sd in seq_len(NPL)){ f<-sprintf(".cache/_smv_v5_%s_p%d.rds",KEY,sd)
  if(file.exists(f)){ r<-readRDS(f)$RES; r<-r[arm=="D1"&te==3]; pl[[length(pl)+1]]<-r[,!"series"] } }
if(length(pl)){
  PL<-rbindlist(pl,fill=TRUE)
  for(bps in c(5,15)){
    real<-RES[arm=="D1"&(!is.na(lam_mult)&lam_mult==1)&te==3&cost_bps==bps]$IR_vsEW
    ps<-PL[cost_bps==bps]$IR_vsEW
    if(length(ps)&&length(real))cat(sprintf("[게이트④ placebo %dbps] real IR_vsEW=%.3f | placebo mean=%.3f sd=%.3f | p(placebo>=real)=%.3f (n=%d)\n",
        bps,real,mean(ps,na.rm=TRUE),sd(ps,na.rm=TRUE),mean(ps>=real,na.rm=TRUE),length(ps)))
  }
  fwrite(PL, sprintf("outputs/ramp/smv_v5_placebo_%s.csv",KEY))
}
fwrite(PAIR, sprintf("outputs/ramp/smv_v5_pair_%s.csv",KEY))
fwrite(SH,   sprintf("outputs/ramp/smv_v5_shiftladder_%s.csv",KEY))
cat("V5_VERIFY_DONE\n")
