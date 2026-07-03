# ============================================================================
# WT-D20260614_002 RISK v2 (Codex REJECT remediation):
#   - ADD explicit MARKET factor to B/Omega (C1: embed dominant common risk)
#   - RMT-filtered Omega as 3rd method (C5) + eigen-floor; report Omega cond
#   - reconcile model EW vol vs realized CORE vol
# Role: risk-research ONLY.
# ============================================================================
suppressMessages({ library(data.table); library(arrow); library(jsonlite) })
Sys.setenv(CLAUDE_PROJECT_DIR = getwd(), QM_ROOT = getwd())
source("02_Infrastructure/config.R")

STYLE <- c("D01_IdioVol","D02_Beta","M07_IndMom","M01_Mom_12_1","M05_Trended_Mom",
           "Q01_GPA","Q04_Piotroski_F","Q09_CFOA","Q07_Earnings_Stability","V01_BM")
AXIS <- c(MKT="market", D01_IdioVol="defense", D02_Beta="defense", M07_IndMom="momentum",
          M01_Mom_12_1="momentum", M05_Trended_Mom="momentum", Q01_GPA="quality",
          Q04_Piotroski_F="quality", Q09_CFOA="quality", Q07_Earnings_Stability="quality", V01_BM="value")
OUT <- "stage_artifacts/WT-D20260614_002"

# ---- inputs ----
panel <- as.data.table(read_parquet(file.path(OUT, "_factor_return_panel.parquet"))); setorder(panel, ym)
# market factor return = BM monthly total return (the systematic factor)
bm <- as.data.table(read_parquet(".cache/benchmark.parquet"))[, .(Date=as.Date(Date), BM_Ret)]
bm[, ym := format(Date, "%Y%m")]
bmm <- bm[, .(MKT = prod(1+BM_Ret, na.rm=TRUE)-1), by=ym]
panel <- merge(panel, bmm, by="ym"); setorder(panel, ym)

FACTORS <- c("MKT", STYLE)   # 11 factors: market + 10 style
Fret <- as.matrix(panel[, ..FACTORS]); rownames(Fret) <- panel$ym

alpha_pkg <- fromJSON("qepm/mailbox/worktask/WT-D20260614_002/alpha_package.json", simplifyVector = TRUE)
alpha_vec <- unlist(alpha_pkg$alpha_vector); names_alpha <- names(alpha_vec)
ai <- readRDS(file.path(OUT, "_alpha_intermediate.rds")); wide <- ai$wide
B_style <- as.matrix(wide[, ..STYLE]); rownames(B_style) <- wide$Ticker
B_style <- B_style[names_alpha, , drop=FALSE]; B_style[!is.finite(B_style)] <- 0

# ---- per-name MARKET BETA (PIT: trailing 36m window ending sig_date) ----
rd <- as.data.table(read_parquet(".cache/RAWDATA.parquet", col_select=c("Date","Ticker","Close")))
rd[, Date := as.Date(Date)]; rd <- rd[Ticker %in% names_alpha & !is.na(Close)]; rd[, ym := format(Date,"%Y%m")]
setorder(rd, Ticker, Date); mer <- rd[, .SD[.N], by=.(Ticker,ym)]; setorder(mer, Ticker, ym)
mer[, mret := Close/shift(Close)-1, by=Ticker]
mer <- mer[ym %in% panel$ym & is.finite(mret)]
stock_wide <- dcast(mer, ym ~ Ticker, value.var="mret"); setkey(stock_wide, ym); stock_wide <- stock_wide[panel$ym]
bm_m <- panel$MKT
beta_vec <- setNames(rep(NA_real_, length(names_alpha)), names_alpha)
for (tk in names_alpha) {
  ri <- stock_wide[[tk]]; ok <- is.finite(ri) & is.finite(bm_m)
  if (sum(ok) < 24) next
  beta_vec[tk] <- cov(ri[ok], bm_m[ok]) / var(bm_m[ok])
}
beta_vec[!is.finite(beta_vec)] <- median(beta_vec, na.rm=TRUE)
# Blume-adjust toward 1 (shrink, standard practice)
beta_vec <- 0.67*beta_vec + 0.33*1.0
B <- cbind(MKT = beta_vec, B_style)   # 60 x 11

# ---- Omega: Ledoit-Wolf + RMT-filter variant (method shopping, 3 candidates) ----
center <- function(X) scale(X, center=TRUE, scale=FALSE)
sample_cov <- function(X) crossprod(center(X))/nrow(X)
ledoit_wolf <- function(X) {
  n<-nrow(X); p<-ncol(X); Xc<-center(X); S<-crossprod(Xc)/n; s<-sqrt(diag(S)); R<-S/(s%o%s)
  rbar<-(sum(R)-p)/(p*(p-1)); F<-rbar*(s%o%s); diag(F)<-diag(S)
  Y<-Xc^2; piMat<-crossprod(Y)/n - S^2; pihat<-sum(piMat); rho_diag<-sum(diag(piMat))
  term<-matrix(0,p,p)
  for(i in 1:p) for(j in 1:p){ if(i==j) next
    term[i,j]<-((s[j]/s[i])*(crossprod(Xc[,i]^2,Xc[,j])/n - S[i,i]*S[i,j]) +
                (s[i]/s[j])*(crossprod(Xc[,j]^2,Xc[,i])/n - S[j,j]*S[i,j]))/2 }
  rho_off<-rbar*sum(term); rhohat<-rho_diag+rho_off; gammahat<-sum((F-S)^2)
  delta<-max(0,min(1,((pihat-rhohat)/gammahat)/n)); list(Sigma=delta*F+(1-delta)*S, shrink=delta)
}
rmt_filter <- function(X) {
  # Marchenko-Pastur eigenvalue clipping on correlation matrix
  n<-nrow(X); p<-ncol(X); S<-sample_cov(X); s<-sqrt(diag(S)); R<-S/(s%o%s)
  ed<-eigen(R, symmetric=TRUE); q<-p/n; lam_max<-(1+sqrt(q))^2
  ev<-ed$values; noise<-ev<=lam_max
  if(any(noise)) ev[noise]<-mean(ev[noise])      # replace noise bulk with its mean
  Rc<-ed$vectors %*% diag(ev) %*% t(ed$vectors); Rc<-(Rc+t(Rc))/2
  diag(Rc)<-1; Sig<-(s%o%s)*Rc; list(Sigma=Sig, lam_max=lam_max, n_signal=sum(!noise))
}
cond_of <- function(M){ev<-eigen(M,symmetric=TRUE,only.values=TRUE)$values; max(ev)/min(ev[ev>1e-12])}

S_samp <- sample_cov(Fret)*12; cn_samp <- cond_of(S_samp)
lw <- ledoit_wolf(Fret); Om_lw <- lw$Sigma*12; cn_lw <- cond_of(Om_lw)
rmt <- rmt_filter(Fret); Om_rmt <- rmt$Sigma*12; cn_rmt <- cond_of(Om_rmt)

# select: prefer lower cond among well-posed; LW vs RMT
cands <- list(
  list(name="sample",      cond=round(cn_samp,2), selected=FALSE, note="11x11, 256 obs; noisy"),
  list(name="ledoit_wolf", cond=round(cn_lw,2),   selected=FALSE, note=sprintf("const-corr target, shrink=%.3f",lw$shrink)),
  list(name="rmt_mp_clip", cond=round(cn_rmt,2),  selected=FALSE, note=sprintf("Marchenko-Pastur clip, n_signal=%d eig",rmt$n_signal))
)
# choose lower-cond of LW/RMT, then eigen-floor to cond<=100 if needed
if (cn_rmt <= cn_lw) { Omega <- Om_rmt; sel <- "rmt_mp_clip"; cands[[3]]$selected<-TRUE
} else { Omega <- Om_lw; sel <- "ledoit_wolf"; cands[[2]]$selected<-TRUE }
cn_omega_pre <- cond_of(Omega)
omega_floored <- FALSE
if (cn_omega_pre > 100) {
  ed<-eigen(Omega,symmetric=TRUE); fl<-max(ed$values)/100; ev2<-pmax(ed$values,fl)
  Omega<-ed$vectors%*%diag(ev2)%*%t(ed$vectors); Omega<-(Omega+t(Omega))/2; omega_floored<-TRUE
}
cn_omega <- cond_of(Omega)
dimnames(Omega) <- list(FACTORS, FACTORS)
Fcorr <- cov2cor(Omega)

# ---- D: specific variance via 11-factor model residual ----
D_vec <- setNames(rep(NA_real_, length(names_alpha)), names_alpha)
fve <- setNames(rep(NA_real_, length(names_alpha)), names_alpha)
for (tk in names_alpha) {
  ri<-stock_wide[[tk]]; ok<-is.finite(ri)
  if(sum(ok)<24){D_vec[tk]<-NA;next}
  pred<-as.numeric(Fret[ok,,drop=FALSE]%*%B[tk,]); resid<-ri[ok]-pred
  D_vec[tk]<-var(resid)*12; fve[tk]<-max(0,1-var(resid)/var(ri[ok]))
}
D_vec[!is.finite(D_vec)]<-median(D_vec,na.rm=TRUE); D_vec<-pmax(D_vec,0.05^2)

# ---- Sigma ----
Sigma <- B %*% Omega %*% t(B) + diag(D_vec); Sigma<-(Sigma+t(Sigma))/2
ev<-eigen(Sigma,symmetric=TRUE,only.values=TRUE)$values; psd<-min(ev)>-1e-10; cn_sigma<-max(ev)/min(ev[ev>1e-12])
sigma_floored<-FALSE
if(!psd||cn_sigma>500){ed<-eigen(Sigma,symmetric=TRUE); fl<-max(ed$values)/500; ev2<-pmax(ed$values,fl)
  Sigma<-ed$vectors%*%diag(ev2)%*%t(ed$vectors);Sigma<-(Sigma+t(Sigma))/2
  ev<-eigen(Sigma,symmetric=TRUE,only.values=TRUE)$values;cn_sigma<-max(ev)/min(ev[ev>1e-12]);psd<-min(ev)>-1e-10;sigma_floored<-TRUE}

# ---- decomposition: EW port ----
w<-setNames(rep(1/length(names_alpha),length(names_alpha)),names_alpha)
ptv<-as.numeric(t(w)%*%Sigma%*%w)
facv<-as.numeric(t(w)%*%(B%*%Omega%*%t(B))%*%w); specv<-as.numeric(t(w)%*%diag(D_vec)%*%w)
xp<-as.numeric(t(B)%*%w); names(xp)<-FACTORS
mfc<-xp*as.numeric(Omega%*%xp); fac_share<-mfc/sum(mfc)
axis_share<-tapply(fac_share, AXIS[FACTORS], sum)
# realized CORE vol reconciliation
btr<-readRDS("stage_artifacts/alpha_search/20260613_021015_217222/bt_result.rds")
pr<-as.data.table(btr$period_returns)[,.(date,ret_net)]; pr[,ym:=format(date,"%Y%m")]
core_m<-pr[,.(r=prod(1+ret_net)-1),by=ym]; realized_core_vol<-sd(core_m$r)*sqrt(12)
model_ew_vol<-sqrt(ptv)
# EW port realized vol (the 60 alpha names, equal weight) for apples-to-apples
ew_real<-rowMeans(as.matrix(stock_wide[,-1]),na.rm=TRUE); ew_real_vol<-sd(ew_real,na.rm=TRUE)*sqrt(12)

# market var share now INSIDE sigma
mkt_var_share_insigma <- (xp["MKT"]*as.numeric(Omega%*%xp)["MKT"])/sum(mfc)
mkt_var_share_insigma <- as.numeric((xp["MKT"]^2*Omega["MKT","MKT"] + xp["MKT"]*sum(xp[-1]*Omega["MKT",-1]))/sum(mfc))
# cleaner: fraction of factor variance attributable to MKT row
mkt_contrib <- xp["MKT"]*as.numeric(Omega%*%xp)["MKT"]; mkt_var_share_insigma <- as.numeric(mkt_contrib/sum(mfc))

saveRDS(list(Omega=Omega,B=B,D_vec=D_vec,Sigma=Sigma,Fcorr=Fcorr,fac_share=fac_share,axis_share=axis_share,
  cn_samp=cn_samp,cn_lw=cn_lw,cn_rmt=cn_rmt,cn_omega_pre=cn_omega_pre,cn_omega=cn_omega,cn_sigma=cn_sigma,
  omega_estimator=sel,omega_floored=omega_floored,sigma_floored=sigma_floored,psd=psd,shrink_lw=lw$shrink,
  cands=cands,facv=facv,specv=specv,ptv=ptv,xp=xp,fve=fve,beta_vec=beta_vec,
  model_ew_vol=model_ew_vol,realized_core_vol=realized_core_vol,ew_real_vol=ew_real_vol,
  mkt_var_share_insigma=mkt_var_share_insigma, FACTORS=FACTORS, STYLE=STYLE, AXIS=AXIS),
  file.path(OUT,"_risk_core_v2.rds"))

cat(sprintf("[v2] cond: samp=%.1f LW=%.1f RMT=%.1f -> Omega(sel=%s,pre=%.1f,floored=%s)=%.1f | Sigma=%.1f PSD=%s\n",
  cn_samp,cn_lw,cn_rmt,sel,cn_omega_pre,omega_floored,cn_omega,cn_sigma,psd))
cat(sprintf("[v2] VOL RECONCILE: model EW vol=%.3f | EW realized vol=%.3f | CORE realized vol=%.3f\n",
  model_ew_vol, ew_real_vol, realized_core_vol))
cat(sprintf("[v2] var shares: factor=%.3f specific=%.3f | MKT-in-Sigma share=%.3f\n",
  facv/ptv, specv/ptv, mkt_var_share_insigma))
cat("[v2] axis var share:\n"); print(round(axis_share,4))
cat("[v2] mean per-name market beta=", round(mean(beta_vec),3), " factor R2 (mean)=", round(mean(fve,na.rm=TRUE),3), "\n")
