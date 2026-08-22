# 후속 패치: verdict_with_power 를 외부 기준 sd(prereg 0.06162)로 재판정 + S2 진단
suppressWarnings(suppressMessages({library(arrow); library(data.table)}))
root <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
Sys.setenv(CLAUDE_PROJECT_DIR = root, QM_ROOT = root)
WT <- file.path(root, "qepm/mailbox/worktask/WT-D20260822_012")
source(file.path(root, "02_Infrastructure/contracts/backtest_result_contract.R"))
source(file.path(root, "02_Infrastructure/contracts/canonical_screen_bt.R"))
source(file.path(root, "02_Infrastructure/contracts/required_effect_size.R"))
res <- readRDS(file.path(WT, "_measure_res.rds"))
o <- file(file.path(WT, "_patch_out.txt"), open = "wt"); L <- function(...) { cat(...,"\n"); cat(...,"\n",file=o) }

e1 <- res$E1_primary
e1_t <- e1$port_t_nw3
e1_mean_monthly <- e1$active_return_mean_annual / 12
n_alg <- e1$n_aligned

# (A) 외부 기준 sd = prereg 무조건부 전표본 sd 0.06162 (arm 자신 아님 → 재진술 회피)
PREREG_SD <- 0.06162
vw_ext <- verdict_with_power(observed_t = e1_t, observed_monthly = e1_mean_monthly,
                            n = n_alg, t_threshold = 2.0,
                            sd_monthly = PREREG_SD, design = "full")
L("=== verdict (외부 기준 sd = prereg 0.06162) ===")
L("verdict:", vw_ext$verdict)
L("note:", vw_ext$note)
L(sprintf("implied_t_threshold=%.3f  reachable=%s", vw_ext$implied_t_threshold,
          as.character(vw_ext$negative_powered_reachable)))
L(sprintf("required_annual(t2.0)=%.4f  관측 mean_active_ann=%.4f (부호 %s)",
          vw_ext$required$required_annual, e1$active_return_mean_annual,
          if (e1$active_return_mean_annual < 0) "음(-)" else "양(+)"))

# (B) 판정 해석: 관측 t 가 음수(-1.14)이고 mean_active 도 음수 → '효과 부재/역방향'.
#     underpowered 라벨은 |효과|<필요치를 뜻하지만 부호가 음(-)이므로 '가설 방향(양+) 성립 아님'.
L("\n=== 판정 해석 ===")
signdir <- if (e1$active_return_mean_annual < 0) "역방향(음)" else "정방향(양)"
L(sprintf("E1 활성수익 부호 = %s. 가설은 '정렬국면서 양(+) 회복' 을 예측 — 관측은 음(-).", signdir))
L("→ '미결(검정력)' 이 아니라, 가설 방향에 대한 증거가 음(-)이다. 다만 |t|=1.14 로 유의 음(-)도 아님.")

# (C) S2 진단 재실행 (denom>0 & finite 강제, lm 유효표본 확인)
L("\n=== S2 재진단 ===")
mb <- as.data.table(read_parquet(file.path(root,".cache/macro_beta_scores.parquet")))
setnames(mb,"Score","score"); mb[,Date:=as.Date(Date)]
fm <- as.data.table(read_parquet(file.path(root,".cache/fred_macro.parquet"))); fm[,Date:=as.Date(Date)]
sig_dates <- sort(unique(mb$Date))
sn <- c("Term_Spread","VIX","KRW_USD")
mac <- fm[Series%in%sn & Frequency=="d",.(Date,Series,Value)]
mw <- dcast(mac,Date~Series,value.var="Value"); setorder(mw,Date)
for(cc in sn){ v<-mw[[cc]]; if(anyNA(v)) mw[[cc]]<-nafill(v,type="locf") }
mw[,d20_ts:=shift(Term_Spread,1)-shift(Term_Spread,21)]
mw[,d20_vix:=shift(VIX,1)-shift(VIX,21)]
mw[,d20_krw:=shift(KRW_USD,1)-shift(KRW_USD,21)]
lab_at<-function(rd){sub<-mw[Date<=rd & !is.na(d20_ts)&!is.na(d20_vix)&!is.na(d20_krw)]; if(!nrow(sub)) return(data.table(d20_ts=NA_real_,d20_vix=NA_real_,d20_krw=NA_real_)); sub[.N,.(d20_ts,d20_vix,d20_krw)]}
reg<-data.table(Date=sig_dates,rbindlist(lapply(sig_dates,lab_at)))
sgn<-function(x)fifelse(x>0,1L,fifelse(x<0,-1L,0L))
reg[,s1:=sgn(d20_ts)][,s2:=sgn(d20_vix)][,s3:=sgn(d20_krw)]
reg[,aligned:=(s1!=0L)&(s2!=0L)&(s3!=0L)&(s1==s2)&(s2==s3)]
z_roll<-function(x){n<-length(x);out<-rep(NA_real_,n);for(i in seq_len(n)){lo<-max(1L,i-36L);w<-x[lo:(i-1L)];s<-if(length(w)>=6)sd(w,na.rm=TRUE)else NA_real_;if(is.finite(s)&&s>0)out[i]<-x[i]/s};out}
reg[,z1:=z_roll(d20_ts)][,z2:=z_roll(d20_vix)][,z3:=z_roll(d20_krw)]
reg[,denom:=abs(z1)+abs(z2)+abs(z3)]
reg[,Ct:=fifelse(is.finite(denom)&denom>0, abs(z1+z2+z3)/denom, NA_real_)]
L(sprintf("Ct finite (aligned): %d / %d", reg[aligned==TRUE & is.finite(Ct),.N], reg[aligned==TRUE,.N]))

# active 시계열은 저장된 res 에 없으므로 uncond canonical 재산출 필요 → 대신 전표본 active 재빌드
source(file.path(root,"02_Infrastructure/ramp/factor_validation.R"))
rawdata<-as.data.table(read_parquet(file.path(root,".cache/RAWDATA.parquet"),
  col_select=c("Date","Ticker","K200","KQ150","Close","Vol","Size"))); rawdata[,Date:=as.Date(Date)]
fwd<-build_monthly_forward_returns(rawdata,sig_dates,liq_daily=rawdata[,.(Date,Ticker,Vol,Close)])
returns_dt<-fwd$returns_dt[,.(Date=as.Date(Date),Ticker,Ret_1m)]
bench_dt<-fwd$bench_dt[,.(Date=as.Date(Date),BM_Ret)]
liq_dt<-fwd$liq_dt[,.(Date=as.Date(Date),Ticker,adv)]
setattr(liq_dt,"liq_ruler",fwd$liq_ruler)
univ<-unique(returns_dt[,.(Date,Ticker)]); mb<-merge(mb,univ,by=c("Date","Ticker"))
cs_all<-canonical_screen_bt(mb[!is.na(score),.(Date,Ticker,score)],returns_dt,bench_dt,top_n=25L,
  cost_bps_oneway=15,liq_dt=liq_dt,liq_min=2e8,run_id="s2_uncond",strategy_id="S2U",diag_dual_basis=FALSE)
pr<-as.data.table(cs_all$period_returns); pr[,active:=ret_net-benchmark_ret]; pr[,Date:=as.Date(date)]
# ★S2 degeneracy: aligned(3/3 동부호) 월에서는 정의상 |Σz|=Σ|z| → Ct≡1 (상수).
#   aligned-only 회귀는 Ct 분산이 0 이라 기울기 NA (설계 실현상 무정보).
#   진단 목적(정합강도 단조성)을 살리려면 전표본(aligned+mixed, Ct∈[1/3,1])에서 회귀한다.
ct_aligned_range <- range(reg[aligned==TRUE & is.finite(Ct), Ct])
L(sprintf("Ct in aligned months: range [%.4f, %.4f] (3/3 동부호 → 정의상 1.0 상수 → aligned-only 회귀 무정보)",
          ct_aligned_range[1], ct_aligned_range[2]))
m2f<-merge(pr[,.(Date,active)],reg[is.finite(Ct),.(Date,Ct,aligned)],by="Date")
m2f<-m2f[is.finite(active)&is.finite(Ct)]
L(sprintf("S2 full-sample rows=%d, Ct range [%.4f, %.4f]", nrow(m2f), min(m2f$Ct), max(m2f$Ct)))
if(nrow(m2f)>=12 && sd(m2f$Ct)>0){
  fit<-lm(active~Ct,data=m2f); sl<-coef(fit)[["Ct"]]
  tval<-summary(fit)$coefficients["Ct","t value"]
  L(sprintf("S2 full-sample slope(active~Ct)=%.5f (t=%.3f)  sign=%s",
            sl, tval, if(sl>0)"positive"else"negative"))
  L("  해석: 양수=정합강도 클수록 활성수익 高(기전 형태 지지) / 음수=역.")
  res$s2_concordance<-list(n=nrow(m2f),slope=sl,t=tval,
    sign=if(is.finite(sl)&&sl>0)"positive"else"negative",
    note="full-sample (aligned Ct≡1 상수라 aligned-only 무정보). Ct∈[1/3,1] 전표본 회귀.")
} else { L("S2: 유효 표본/분산 부족"); res$s2_concordance<-list(n=nrow(m2f),slope=NA_real_,note="degenerate") }

res$E1_primary$verdict_with_power_external_sd <- vw_ext$verdict
res$E1_primary$verdict_note_external_sd <- vw_ext$note
res$E1_primary$verdict_implied_t <- vw_ext$implied_t_threshold
res$E1_primary$required_annual_t2 <- vw_ext$required$required_annual
res$E1_primary$direction <- signdir
saveRDS(res, file.path(WT,"_measure_res.rds"))
close(o); cat("PATCH_DONE\n")
