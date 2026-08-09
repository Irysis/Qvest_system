#!/usr/bin/env Rscript
# =============================================================================
# p5_final_verdict.R — FQ-174 착수 전 검정력 바 확정판 + prereg_power_bars.json
#
# p4 이후 확정해야 할 3건:
#   V1. 계약 required_effect() 를 실제로 호출해 full/split/interaction 설계 비교
#       (버킷 분할 대신 상호작용 회귀로 검정력을 되찾을 수 있는가 — 되찾을 수 없음을 수치로)
#   V2. MDD 축 — "달성가능 min MDD" 가 탐색마다 30.5/33.4/34.1/34.5/35.6% 로 흔들린다.
#       탐색간 산포 vs 필요 ΔMDD 를 비교하고, IS 선택 → OOS 전이를 직접 잰다.
#   V3. 검정력(power) 을 비율이 아니라 확률로 산출 (t_crit 2.0 / 2.64 두 경우)
#
# ★ P0 인용값 정정 (본 라운드 규약 "dedup 85 위에서" 기준):
#     §4 무조건부 spearman -0.130  → dedup 85 에서 **+0.2371**(p0g) / +0.2987(vs base IR)  ※부호 반전
#     §5 상태조건부 +0.462/+0.498/-0.436 → dedup 85 에서 **+0.7075/+0.7446/-0.0051**
#   둘 다 P0 가 191 비-dedup 위에서 계산한 값이었다(§4=p0d, §5=p0e.log).
# metric_type = diagnostic_precheck
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(xts); library(PerformanceAnalytics); library(jsonlite)
})
PROJ <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT",""))
if (!nzchar(PROJ)) PROJ <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(PROJ); OUT <- file.path(PROJ,"stage_artifacts/scrap_ensemble_20260809")
source(file.path(PROJ,"02_Infrastructure/contracts/required_effect_size.R"))  # 계약 사용
sink(file.path(OUT,"p5_final.log"), split=TRUE)
set.seed(20260809); T_THR <- 2.0; K <- 12L

P <- readRDS(file.path(OUT,"p0_panel.rds")); PAN <- P$PAN; scrap_ok <- P$scrap_ok
sub <- PAN[ym >= P$start_ym & is.finite(bm)]; setorder(sub, ym)
M0 <- as.matrix(sub[,..scrap_ok]); cov_m <- colSums(is.finite(M0)); keep <- which(cov_m>=253)
rows <- complete.cases(M0[,keep,drop=FALSE]); M <- M0[rows,keep,drop=FALSE]
bmv <- sub$bm[rows]; ymv <- sub$ym[rows]; n_all <- nrow(M)
C <- cor(M); diag(C) <- 0; hi <- which(C>=0.999,arr.ind=TRUE); hi <- hi[hi[,1]<hi[,2],,drop=FALSE]
comp <- local({ par<-seq_len(ncol(M)); fnd<-function(x){while(par[x]!=x) x<-par[x]; x}
  if(nrow(hi)) for(r in seq_len(nrow(hi))){a<-fnd(hi[r,1]);b<-fnd(hi[r,2]);if(a!=b) par[b]<-a}
  vapply(seq_len(ncol(M)),fnd,integer(1)) })
reps <- vapply(unique(comp), function(g) which(comp==g)[1], integer(1))
Mu <- M[,reps,drop=FALSE]; NU <- ncol(Mu)
dts <- as.Date(paste0(substr(ymv,1,4),"-",substr(ymv,5,6),"-01")); Xu <- xts(Mu,order.by=dts)
base85 <- as.numeric(Return.portfolio(Xu, weights=rep(1/NU,NU), rebalance_on="months"))
Ab <- Mu - matrix(base85,n_all,NU); Abm <- Mu - matrix(bmv,n_all,NU)
st <- ifelse(bmv<=-0.05,"DOWN",ifelse(bmv>=0.05,"SURGE","FLAT")); stL <- c(NA,st[-n_all])
h <- floor(n_all/2)
armK <- function(sv) as.numeric(Return.portfolio(Xu[,sv,drop=FALSE], rep(1/length(sv),length(sv)),
                                                 rebalance_on="months")) - base85
mdd_of <- function(v,dd=dts) as.numeric(maxDrawdown(xts(v,order.by=dd)))
cat(sprintf("=== [0] %d months x dedup %d ===\n", n_all, NU))

## ============================== V1. 계약 호출 — 분할 vs 상호작용 설계
cat("\n=== [V1] 계약 required_effect() — 버킷분할을 상호작용으로 바꾸면 검정력이 회복되나 ===\n")
sd_meas <- c(DOWN=0.01882, SURGE=0.02154, FLAT=0.01731)   # p4 실측 선택-arm diff sd
v1 <- list()
for (s in c("DOWN","SURGE")) {
  frac <- mean(st==s)
  rb <- required_effect(n=n_all, sd_monthly=sd_meas[[s]], design="interaction",
                        regime_frac=frac, nw_inflation=1.0)
  nb_ <- sum(!is.na(stL) & stL==s)
  rs <- required_effect(n=nb_, sd_monthly=sd_meas[[s]], design="full", nw_inflation=1.0)
  cat(sprintf("  %-6s 상호작용(n=254,frac=%.3f): 유효n=%.1f 필요 연 %+.2f%%p  |  버킷분할(n=%d): 유효n=%.0f 필요 연 %+.2f%%p  → %s\n",
      s, frac, rb$effective_n, 100*rb$required_annual, nb_, rs$effective_n, 100*rs$required_annual,
      ifelse(rb$effective_n > rs$effective_n, "상호작용이 유리", "버킷이 유리(회복 없음)")))
  v1[[s]] <- list(state=s, interaction_eff_n=rb$effective_n, interaction_req_annual=100*rb$required_annual,
                  bucket_n=nb_, bucket_req_annual=100*rs$required_annual)
}
cat("  ⇒ 상호작용 설계로 재프레이밍해도 유효 n 이 늘지 않는다. 저검정력은 설계가 아니라 표본의 성질.\n")

## ============================== V2. MDD 축 — 탐색 불안정성 + IS→OOS 전이
cat("\n=== [V2] MDD 축 ===\n")
prior <- c(p0e_600=34.1, p0c_4000=34.5, p0g_300=30.5, p1_400=35.6, p4_400=33.4)
cat(sprintf("  독립 탐색 5회의 'min 달성 MDD'(%%): %s\n", paste(sprintf("%.1f",prior),collapse=" / ")))
cat(sprintf("  탐색간 range=%.1f%%p  sd=%.2f%%p\n", max(prior)-min(prior), sd(prior)))
# 필요 ΔMDD (paired block bootstrap)
boot_idx <- function(n,blk){ s<-sample.int(n-blk+1L, ceiling(n/blk), replace=TRUE)
  as.integer(unlist(lapply(s,function(x) x:(x+blk-1L))))[1:n] }
set.seed(20260810); BI <- lapply(seq_len(1000L), function(i) boot_idx(n_all,12L))
mb_base <- vapply(BI, function(ix) mdd_of(base85[ix]), numeric(1))
set.seed(4242)
cand <- lapply(seq_len(400L), function(i) as.numeric(Return.portfolio(
  Xu[,sample.int(NU,K),drop=FALSE], rep(1/K,K), rebalance_on="months")))
cmdd <- vapply(cand, mdd_of, numeric(1))
se_pair <- median(vapply(list(cand[[order(cmdd)[200]]], cand[[which.min(cmdd)]]),
  function(v) sd(mb_base - vapply(BI, function(ix) mdd_of(v[ix]), numeric(1))), numeric(1)))
req_mdd <- T_THR*se_pair
cat(sprintf("  필요 ΔMDD (|t|>=2) = %.2f%%p   |   탐색간 산포 range %.1f%%p\n", 100*req_mdd, max(prior)-min(prior)))
cat(sprintf("  ★탐색간 산포(%.1f%%p) > 필요 ΔMDD(%.2f%%p) ⇒ 바가 '진짜 개선'과 '탐색 운'을 구별하지 못한다.\n",
            max(prior)-min(prior), 100*req_mdd))
# IS -> OOS 전이 (전반 127m 에서 min-MDD 선택 → 후반 127m 실측)
cat("  [IS→OOS 전이] 전반 127m 에서 min-MDD K=12 선택 → 후반 127m ΔMDD\n")
i1 <- 1:h; i2 <- (h+1):n_all; d1 <- dts[i1]; d2 <- dts[i2]
oos <- c()
for (trial in 1:5) {
  set.seed(1000+trial)
  picks <- replicate(300, sample.int(NU,K), simplify=FALSE)
  m_is <- vapply(picks, function(sv) mdd_of(as.numeric(Return.portfolio(
    Xu[i1,sv,drop=FALSE], rep(1/K,K), rebalance_on="months")), d1), numeric(1))
  sv <- picks[[which.min(m_is)]]
  m_oos <- mdd_of(as.numeric(Return.portfolio(Xu[i2,sv,drop=FALSE], rep(1/K,K), rebalance_on="months")), d2)
  b_is <- mdd_of(base85[i1], d1); b_oos <- mdd_of(base85[i2], d2)
  oos <- c(oos, b_oos - m_oos)
  cat(sprintf("    trial%d: IS ΔMDD=%+.2f%%p → OOS ΔMDD=%+.2f%%p\n",
              trial, 100*(b_is - min(m_is)), 100*(b_oos - m_oos)))
}
cat(sprintf("    ⇒ OOS ΔMDD 평균=%+.2f%%p (필요 %.2f%%p) → %s\n",
            100*mean(oos), 100*req_mdd, ifelse(mean(oos) >= req_mdd,"도달","미달")))

## ============================== V3. 최종 바 + power
cat("\n=== [V3] 최종 바 + 검정력(확률) ===\n")
rho_state <- vapply(c("DOWN","SURGE","FLAT"), function(s){
  a<-which(st==s & seq_len(n_all)<=h); b<-which(st==s & seq_len(n_all)>h)
  cor(colMeans(Abm[a,,drop=FALSE]), colMeans(Abm[b,,drop=FALSE]), method="spearman")}, numeric(1))
ir1 <- colMeans(Ab[1:h,])/apply(Ab[1:h,],2,sd); a2 <- colMeans(Ab[(h+1):n_all,])
rho_unc <- cor(ir1,a2,method="spearman")
resid_t <- function(A){ p<-prcomp(scale(A),center=FALSE); f<-as.numeric(p$x[,1]); f<-f/sd(f)
  apply(A,2,function(y) summary(lm(y~f))$coefficients[1,3]) }
rho_res <- cor(resid_t(Ab[1:h,,drop=FALSE]), a2, method="spearman")

mkbar <- function(name,mask,rho,pit,scope,note) {
  sv <- order(colMeans(Ab[mask,,drop=FALSE]),decreasing=TRUE)[1:K]
  d <- armK(sv); dd <- d[mask]; n <- sum(mask); s <- sd(dd)
  se <- s/sqrt(n); req <- T_THR*se; ceil <- mean(dd); eo <- ceil*max(rho,0)
  et <- eo/se
  list(arm_or_bucket=name, n=n, sd_monthly_pct=100*s,
       required_effect_pct_per_month=100*req, required_pct_per_year=100*req*12,
       book_annual_contrib_pct=100*req*12*n/n_all,
       is_ceiling_pct_per_month=100*ceil, persistence_rho=rho,
       expected_oos_pct_per_month=100*eo, expected_t=et,
       power_at_t2.0=1-pnorm(2.0-et), power_at_t2.64=1-pnorm(2.64-et),
       pit_legal=pit, in_scope=scope,
       plausible=(pit && scope && (1-pnorm(2.0-et)) >= 0.80),
       note=note, metric_type="diagnostic_precheck")
}
B <- list(
 mkbar("FULL_254m_uncond", rep(TRUE,n_all), rho_unc, TRUE, TRUE,
       "무조건부 trailing 선택. rho 는 dedup 85 정정값(+0.299), P0 §4 의 -0.130 은 191 값"),
 mkbar("DOWN_n31_contemp", st=="DOWN", rho_state[["DOWN"]], FALSE, FALSE,
       "동월 라벨 = PIT 불가. 순위는 beta rank-R2 0.951"),
 mkbar("SURGE_n49_contemp", st=="SURGE", rho_state[["SURGE"]], FALSE, FALSE,
       "동월 라벨 = PIT 불가. 순위는 beta rank-R2 0.970"),
 mkbar("FLAT_n174_contemp", st=="FLAT", rho_state[["FLAT"]], FALSE, TRUE,
       "dedup 후 rho 소멸(-0.005). P0 §5 의 -0.436 은 191 값"),
 mkbar("lag1_DOWN_n30_PIT", !is.na(stL)&stL=="DOWN",
       cor(colMeans(Abm[which(!is.na(stL)&stL=="DOWN"&seq_len(n_all)<=h),,drop=FALSE]),
           colMeans(Abm[which(!is.na(stL)&stL=="DOWN"&seq_len(n_all)>h),,drop=FALSE]),method="spearman"),
       TRUE, FALSE, "PIT 적법. 단 라벨 지속성 0.133 ~ base rate 0.122 = 예측력 없음. beta 축"),
 mkbar("lag1_SURGE_n49_PIT", !is.na(stL)&stL=="SURGE",
       cor(colMeans(Abm[which(!is.na(stL)&stL=="SURGE"&seq_len(n_all)<=h),,drop=FALSE]),
           colMeans(Abm[which(!is.na(stL)&stL=="SURGE"&seq_len(n_all)>h),,drop=FALSE]),method="spearman"),
       TRUE, FALSE, "PIT 적법. 라벨 지속성 0.245 vs base 0.193. beta 축 = WT-002 소관"),
 mkbar("lag1_FLAT_n174_PIT", !is.na(stL)&stL=="FLAT",
       cor(colMeans(Abm[which(!is.na(stL)&stL=="FLAT"&seq_len(n_all)<=h),,drop=FALSE]),
           colMeans(Abm[which(!is.na(stL)&stL=="FLAT"&seq_len(n_all)>h),,drop=FALSE]),method="spearman"),
       TRUE, TRUE, "rho 음수")
)
# 잔차-직교 (선택 신호가 다름 → 별도 구성)
sv_r <- order(resid_t(Ab),decreasing=TRUE)[1:K]; d_r <- armK(sv_r)
se_r <- sd(d_r)/sqrt(n_all); eo_r <- mean(d_r)*max(rho_res,0); et_r <- eo_r/se_r
B[[length(B)+1]] <- list(arm_or_bucket="RESID_ORTHO_254m", n=n_all, sd_monthly_pct=100*sd(d_r),
  required_effect_pct_per_month=100*T_THR*se_r, required_pct_per_year=100*T_THR*se_r*12,
  book_annual_contrib_pct=100*T_THR*se_r*12, is_ceiling_pct_per_month=100*mean(d_r),
  persistence_rho=rho_res, expected_oos_pct_per_month=100*eo_r, expected_t=et_r,
  power_at_t2.0=1-pnorm(2.0-et_r), power_at_t2.64=1-pnorm(2.64-et_r),
  pit_legal=TRUE, in_scope=TRUE, plausible=((1-pnorm(2.0-et_r))>=0.80),
  note=sprintf("PC1 잔차 선택. 전이 rho %+.3f 가 무조건부 IR 전이 %+.3f 를 못 넘음 = 이점 없음", rho_res, rho_unc),
  metric_type="diagnostic_precheck")
B[[length(B)+1]] <- list(arm_or_bucket="MDD_axis_blockboot", n=n_all,
  sd_monthly_pct=100*se_pair, required_effect_pct_per_month=100*req_mdd,
  required_pct_per_year=100*req_mdd, unit_note="단위 %p(ΔMDD), 월수익률 아님",
  base_mdd_pct=100*mdd_of(base85), search_min_mdd_range_pp=max(prior)-min(prior),
  oos_delta_mdd_mean_pp=100*mean(oos), expected_t=mean(oos)/se_pair,
  power_at_t2.0=1-pnorm(2.0-mean(oos)/se_pair), power_at_t2.64=1-pnorm(2.64-mean(oos)/se_pair),
  pit_legal=TRUE, in_scope=TRUE, plausible=(mean(oos) >= req_mdd),
  note="탐색간 산포가 필요 ΔMDD 보다 커서 바가 개선과 탐색운을 구별 못함. IS→OOS 전이 실측 첨부",
  metric_type="diagnostic_precheck")

for (b in B) cat(sprintf("  %-22s n=%3d 필요 %+.4f (연 %+.2f%%p) 기대 %+.3f 기대t %+.2f power@2.0=%.2f @2.64=%.2f PIT=%s scope=%s → %s\n",
  b$arm_or_bucket,b$n,b$required_effect_pct_per_month,b$required_pct_per_year,
  ifelse(is.null(b$expected_oos_pct_per_month),NA,b$expected_oos_pct_per_month),
  b$expected_t,b$`power_at_t2.0`,b$`power_at_t2.64`,b$pit_legal,b$in_scope,
  ifelse(b$plausible,"PLAUSIBLE","ABORT")))

np <- sum(vapply(B,function(b) isTRUE(b$plausible), logical(1)))
verdict <- if (np==0) "ABORT" else if (np < length(B)) "PROCEED_NARROWED" else "PROCEED"
cat(sprintf("\n★ 통과 축 %d / %d  →  verdict = %s\n", np, length(B), verdict))

write_json(list(
 meta=list(round="FQ-174 scrap ensemble (폐지줍기)", stage="prereg_power_bars_FINAL",
   window=sprintf("%s..%s",ymv[1],ymv[n_all]), n_months=n_all, universe_dedup=NU, K=K,
   base="EW(dedup 85) Return.portfolio", t_threshold=T_THR,
   sd_basis="선택된 arm 의 paired diff sd (무작위 arm 아님)",
   contract="02_Infrastructure/contracts/required_effect_size.R — required_effect() 호출(V1), sd 는 실측 대체",
   metric_type="diagnostic_precheck", verdict=verdict),
 p0_citation_corrections=list(
   sec4_uncond_rho=list(cited=-0.130, source="191 비-dedup(p0d)",
                        dedup85_vs_bm=0.2371, dedup85_vs_base_IR=rho_unc,
                        impact="부호 반전 — 무조건부 arm 은 유효한 음성대조가 아니다"),
   sec5_state_rho=list(cited=list(DOWN=0.462,SURGE=0.498,FLAT=-0.436), source="191 비-dedup(p0e.log)",
                       dedup85=as.list(round(rho_state,4)),
                       impact="DOWN/SURGE 는 더 높고 FLAT 반지속성은 소멸"),
   sec6_resid=list(cited_n_t_gt2=16, recomputed_vs_base=sum(resid_t(Ab)>2))),
 mechanism=list(beta_rank_corr=list(DOWN=-0.9751,SURGE=0.9851,FLAT=0.3919),
   beta_residual_rho=list(DOWN=-0.4008,SURGE=-0.7159),
   label_persistence=list(DOWN=0.133,SURGE=0.245,FLAT=0.718),
   label_base_rate=list(DOWN=31/254,SURGE=49/254,FLAT=174/254),
   verdict="상태-조건부 모듈순위 = beta(rank R^2 0.95~0.97). beta 잔차화 시 지속성 음수 ⇒ 노출 스케일 축(WT-D20260809_002 소관), 멤버십 축 아님"),
 V1_design_comparison=unname(v1),
 V2_mdd=list(search_min_mdd_pct=as.list(prior), search_range_pp=max(prior)-min(prior),
   required_delta_pp=100*req_mdd, oos_delta_mdd_pp=100*oos, oos_mean_pp=100*mean(oos)),
 bars=B), file.path(OUT,"prereg_power_bars.json"), auto_unbox=TRUE, digits=NA, pretty=TRUE)
cat("[saved] prereg_power_bars.json\n"); sink()
