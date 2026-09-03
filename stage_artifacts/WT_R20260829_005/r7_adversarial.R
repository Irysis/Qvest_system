# ── R7 — Self-Adversarial Challenge 의 정량 근거 (주장 아닌 실측)
suppressWarnings(suppressMessages({library(data.table); library(arrow); library(jsonlite)}))
ROOT <- Sys.getenv("QM_ROOT"); setwd(ROOT)
source(file.path(ROOT, "02_Infrastructure/config.R"))
OUT <- file.path(ROOT, "stage_artifacts/WT_R20260829_005")
set.seed(20260829L)
R1<-readRDS(file.path(OUT,"risk_r1.rds")); R2<-readRDS(file.path(OUT,"risk_r2.rds"))
R3<-readRDS(file.path(OUT,"risk_r3.rds")); R4<-readRDS(file.path(OUT,"risk_r4.rds"))
R5<-readRDS(file.path(OUT,"risk_r5.rds"))
ASSETS<-R2$ASSETS; B<-R2$B; Om<-R2$Omega_d; win_d<-R2$win_d; D<-R1$D
STY<-R2$STY; fac_names<-R2$fac_names

## ── SC-1 비퇴화: 팩터 Sigma 가 표본공분산과 실제로 구별되는가 ───────────────
sub <- intersect(ASSETS, R2$keep_t)
Sf <- R3$Sigma_d[sub, sub]; Ss <- R2$cands$sample$cov[sub, sub]
Sl <- R2$cands$lw_nls$cov[sub, sub]
offv <- function(S){ s<-sqrt(diag(S)); C<-S/outer(s,s); C[upper.tri(C)] }
c_f<-offv(Sf); c_s<-offv(Ss); c_l<-offv(Sl)
cat(sprintf("[SC-1] offdiag corr(factor, sample) = %.4f | corr(lw_nls, sample) = %.4f\n",
            cor(c_f,c_s), cor(c_l,c_s)))
cat(sprintf("[SC-1] mean|rho| factor=%.4f sample=%.4f  | RMS(rho_f - rho_s) = %.4f\n",
            mean(abs(c_f)), mean(abs(c_s)), sqrt(mean((c_f-c_s)^2))))
frob <- function(A,Bq) norm(A-Bq,"F")/norm(Bq,"F")
cat(sprintf("[SC-1] relative Frobenius ||Sf-Ss||/||Ss|| = %.4f ; ||Sl-Ss||/||Ss|| = %.4f\n",
            frob(Sf,Ss), frob(Sl,Ss)))
## 판별력이 실제로 다른가: 동일 무작위 바스켓에 대한 예측 vol 차이
pool<-sub; bl<-replicate(500, sample(pool,25), simplify=FALSE)
pv<-t(sapply(bl, function(b){ w<-rep(1/25,25)
  c(f=sqrt(as.numeric(t(w)%*%Sf[b,b]%*%w)*252), s=sqrt(as.numeric(t(w)%*%Ss[b,b]%*%w)*252)) }))
cat(sprintf("[SC-1] random 25-baskets predicted vol: mean factor=%.4f sample=%.4f | corr=%.4f | mean|diff|=%.4f (%.1f%% of level)\n",
            mean(pv[,1]), mean(pv[,2]), cor(pv[,1],pv[,2]),
            mean(abs(pv[,1]-pv[,2])), 100*mean(abs(pv[,1]-pv[,2]))/mean(pv[,2])))

## ── SC-2 문턱 맞춤 민감도: floor 0.25 vs 0.40 vs 0.50 이 소비량을 바꾸는가 ──
Ds<-R3$Ds; med_v<-R3$med_v
bs <- function(ff){ dv<-setNames(rep(med_v,length(ASSETS)),ASSETS)
  dv[Ds$Ticker]<-pmax(Ds$v_base, ff*med_v); S<-B%*%Om%*%t(B)+diag(dv[ASSETS])
  S<-(S+t(S))/2; dimnames(S)<-list(ASSETS,ASSETS); S }
S25<-bs(0.25); S40<-bs(0.40); S50<-bs(0.50)
bl2<-replicate(500, sample(ASSETS,25), simplify=FALSE)
pv2<-t(sapply(bl2, function(b){ w<-rep(1/25,25)
  c(a=sqrt(as.numeric(t(w)%*%S25[b,b]%*%w)*252), b=sqrt(as.numeric(t(w)%*%S40[b,b]%*%w)*252),
    c=sqrt(as.numeric(t(w)%*%S50[b,b]%*%w)*252)) }))
cat(sprintf("[SC-2] predicted vol across floors: 0.25=%.4f 0.40=%.4f 0.50=%.4f | rank corr(0.25,0.40)=%.4f (0.25,0.50)=%.4f\n",
            mean(pv2[,1]),mean(pv2[,2]),mean(pv2[,3]),
            cor(pv2[,1],pv2[,2],method="spearman"), cor(pv2[,1],pv2[,3],method="spearman")))
cat(sprintf("[SC-2] level shift 0.25->0.40 = %+.2f%% ; 0.25->0.50 = %+.2f%%\n",
            100*(mean(pv2[,2])/mean(pv2[,1])-1), 100*(mean(pv2[,3])/mean(pv2[,1])-1)))

## ── SC-4 레짐 표본의 유효 독립 관측수 (24개월 중첩창) ───────────────────────
RHO<-R4$RHO
eff <- function(sel){ n<-sum(sel); list(n=n, n_eff=n/24, blocks=NA) }
blocks_of <- function(v){ r<-rle(v); sum(r$values) }
for (lbl in c("CRISIS","NORMAL","HIGHVOL","LOWVOL","BULL","BEAR")) {
  sel <- switch(lbl, CRISIS=RHO$regime_crisis=="CRISIS", NORMAL=RHO$regime_crisis=="NORMAL",
                HIGHVOL=RHO$regime_vol=="HIGHVOL", LOWVOL=RHO$regime_vol=="LOWVOL",
                BULL=RHO$regime_dir=="BULL", BEAR=RHO$regime_dir=="BEAR")
  sel[is.na(sel)]<-FALSE
  cat(sprintf("[SC-4] %-8s months=%3d  non-overlapping_eff=%4.1f  episodes(runs)=%2d  mean_rho=%.4f sd=%.4f\n",
              lbl, sum(sel), sum(sel)/24, blocks_of(sel), mean(RHO$rho_bar[sel]), sd(RHO$rho_bar[sel])))
}
## HIGHVOL vs LOWVOL 을 에피소드 단위로 재검 (창당 1관측이 아니라 에피소드당 1관측)
mk_ep <- function(sel){ sel[is.na(sel)]<-FALSE; r<-rle(sel); idx<-cumsum(r$lengths)
  st<-idx-r$lengths+1; v<-c(); for(i in seq_along(r$values)) if(r$values[i]) v<-c(v, mean(RHO$rho_bar[st[i]:idx[i]])); v }
hv<-mk_ep(RHO$regime_vol=="HIGHVOL"); lv<-mk_ep(RHO$regime_vol=="LOWVOL")
cr<-mk_ep(RHO$regime_crisis=="CRISIS"); no<-mk_ep(RHO$regime_crisis=="NORMAL")
tt<-function(a,b) tryCatch(t.test(a,b)$p.value, error=function(e) NA_real_)
cat(sprintf("[SC-4] episode-level: HIGHVOL n=%d mean=%.4f vs LOWVOL n=%d mean=%.4f  p=%.4f\n",
            length(hv),mean(hv),length(lv),mean(lv),tt(hv,lv)))
cat(sprintf("[SC-4] episode-level: CRISIS  n=%d mean=%.4f vs NORMAL  n=%d mean=%.4f  p=%.4f\n",
            length(cr),mean(cr),length(no),mean(no),tt(cr,no)))

## ── SC-6 시장지배가 가중방식에 불변인가 ─────────────────────────────────────
mkt_share <- function(wv){ wv<-wv[ASSETS]; wv[!is.finite(wv)]<-0
  tv<-as.numeric(t(wv)%*%R3$Sigma_d%*%wv); x<-as.numeric(t(B)%*%wv)
  ctr<-x*as.numeric(Om%*%x); c(mkt=ctr[1]/tv, spec=sum(wv^2*R3$dvec_final[ASSETS])/tv) }
w25<-setNames(rep(0,length(ASSETS)),ASSETS); w25[R4$top25]<-1/length(R4$top25)
wew<-setNames(rep(1/length(ASSETS),length(ASSETS)),ASSETS)
wcw<-R5$wb
## 무작위 25종 EW 바스켓 500개의 MKT 분산비중 분포
rs<-t(sapply(bl2, function(b){ wv<-setNames(rep(0,length(ASSETS)),ASSETS); wv[b]<-1/25; mkt_share(wv) }))
for (nm in c("ew_top25","ew_universe340","k200_capw")) {
  v<-mkt_share(switch(nm, ew_top25=w25, ew_universe340=wew, k200_capw=wcw))
  cat(sprintf("[SC-6] %-16s MKT variance share = %.3f  specific = %.3f\n", nm, v["mkt"], v["spec"]))
}
cat(sprintf("[SC-6] random EW 25-baskets: MKT share mean=%.3f sd=%.3f min=%.3f max=%.3f | specific mean=%.3f\n",
            mean(rs[,1]), sd(rs[,1]), min(rs[,1]), max(rs[,1]), mean(rs[,2])))

saveRDS(list(
  sc1 = list(corr_offdiag_factor_vs_sample = cor(c_f,c_s), corr_offdiag_lwnls_vs_sample = cor(c_l,c_s),
             rms_corr_diff = sqrt(mean((c_f-c_s)^2)), frob_factor = frob(Sf,Ss), frob_lwnls = frob(Sl,Ss),
             basket_vol_corr = cor(pv[,1],pv[,2]), basket_vol_meanabsdiff_pct = 100*mean(abs(pv[,1]-pv[,2]))/mean(pv[,2]),
             mean_vol_factor = mean(pv[,1]), mean_vol_sample = mean(pv[,2])),
  sc2 = list(mean_vol_f025 = mean(pv2[,1]), mean_vol_f040 = mean(pv2[,2]), mean_vol_f050 = mean(pv2[,3]),
             spearman_025_040 = cor(pv2[,1],pv2[,2],method="spearman"),
             spearman_025_050 = cor(pv2[,1],pv2[,3],method="spearman"),
             level_shift_040_pct = 100*(mean(pv2[,2])/mean(pv2[,1])-1),
             level_shift_050_pct = 100*(mean(pv2[,3])/mean(pv2[,1])-1)),
  sc4 = list(highvol_ep_n = length(hv), highvol_ep_mean = mean(hv),
             lowvol_ep_n = length(lv), lowvol_ep_mean = mean(lv), p_highvol_lowvol = tt(hv,lv),
             crisis_ep_n = length(cr), crisis_ep_mean = mean(cr),
             normal_ep_n = length(no), normal_ep_mean = mean(no), p_crisis_normal = tt(cr,no)),
  sc6 = list(ew_top25 = mkt_share(w25)["mkt"], ew_universe340 = mkt_share(wew)["mkt"],
             k200_capw = mkt_share(wcw)["mkt"], random_mean = mean(rs[,1]), random_sd = sd(rs[,1]),
             random_min = min(rs[,1]), random_max = max(rs[,1]))),
  file.path(OUT, "risk_r7_adversarial.rds"))
cat("[R7] done\n")
