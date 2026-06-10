#!/usr/bin/env Rscript
# =============================================================================
# ep_orthogonality.R — EP(Basu 1977 earnings-yield) 직교성 확정.
#   alpha-search가 Carhart4 알파 t=+2.13(momentum 직교)만 확정 → 본 스크립트가 상관·OOS retention 채움.
# 산출:
#   ① EP vs STR_1715(reference book sleeve) 월간 수익/active 상관
#   ② EP vs momentum 계열(residual momentum 152406/185153, raw 095531) 상관 (Carhart4 직교 교차검증)
#   ③ EP vs 풀 전체 모듈 상관 분포 (top-5 최고상관 = 가장 안 직교한 모듈)
#   ④ EP standalone OOS retention (IS/OOS 60/40 active Sharpe 유지율)
# PIT: 모듈 frozen(배분 모드 — 재백테 금지). 월간 정렬, 실측 NAV만.
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite); library(xts) })
PROJ <- Sys.getenv("CLAUDE_PROJECT_DIR", "G:/Quant_Module_Moltbot"); setwd(PROJ)
`%||%` <- function(a,b) if(is.null(a)||length(a)==0||all(is.na(a))) b else a
sr <- function(r){ r<-r[is.finite(r)]; if(length(r)<6||sd(r)==0) return(NA_real_); mean(r)/sd(r)*sqrt(12) }

EP_ID <- "STR_AS_20260605_202226_37668"

# ── helper: sim_result(daily) → monthly returns DT(ym, r, bm) ──
load_monthly <- function(sim_path){
  s <- tryCatch(readRDS(file.path(PROJ, sim_path)), error=function(e) NULL)
  if(is.null(s)||is.null(s$DAILY_NAV_DT)) return(NULL)
  d <- as.data.table(s$DAILY_NAV_DT)[, .(Date=as.Date(Date), r=Strategy_Ret)]
  bm <- if(!is.null(s$bm_xts)) data.table(Date=as.Date(index(s$bm_xts)), bm=as.numeric(s$bm_xts[,1])) else NULL
  if(!is.null(bm)) d <- merge(d, bm, by="Date", all.x=TRUE) else d[, bm:=0]
  d[, ym:=format(Date,"%Y%m")]
  d[!is.finite(r), r:=0]; d[!is.finite(bm), bm:=0]
  d[, .(r=prod(1+r)-1, bm=prod(1+bm)-1), by=ym]
}

# ── EP monthly ──
EPm <- load_monthly(file.path("04_Research/strategies", EP_ID, "sim_result.rds"))
EPm[, act := r - bm]
cat(sprintf("[EP] %d months %s~%s | active Sharpe(full)=%.3f\n",
            nrow(EPm), EPm$ym[1], tail(EPm$ym,1), sr(EPm$act)))

# ── STR_1715 monthly (reference sleeve — 03_period_returns.csv ret_net + benchmark) ──
pr <- fread(file.path(PROJ,"04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/output/03_period_returns.csv"))
bmr <- fread(file.path(PROJ,"04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/output/05_benchmark_returns.csv"))
s1715 <- data.table(ym=format(as.Date(pr$date),"%Y%m"), r=pr$ret_net)
# benchmark_returns: align by date
bmr_col <- names(bmr)[sapply(bmr, is.numeric)][1]
b1715 <- data.table(ym=format(as.Date(bmr$date),"%Y%m"), bm=bmr[[bmr_col]])
s1715 <- merge(s1715, b1715, by="ym", all.x=TRUE); s1715[!is.finite(bm), bm:=0]
s1715[, act := r - bm]

# ── ① EP vs STR_1715 (월간 overlap) ──
ov <- merge(EPm[,.(ym, ep_r=r, ep_act=act)], s1715[,.(ym, s_r=r, s_act=act)], by="ym")
cat(sprintf("[1715 overlap] %d months\n", nrow(ov)))
cor_ret_1715  <- cor(ov$ep_r, ov$s_r, use="complete.obs")
cor_act_1715  <- cor(ov$ep_act, ov$s_act, use="complete.obs")

# ── ② EP vs momentum 계열 ──
mom_ids <- c(
  resid_mom_full   = "STR_AS_20260605_185153_35464",  # Residual momentum 풀구간
  resid_mom_decile = "STR_AS_20260605_152406_36892",  # Residual momentum decile
  raw_mom_121      = "STR_AS_20260605_095531_37468",   # 12-1 raw momentum
  resid_mom_36m    = "STR_AS_20260605_135743_30748"    # 잔차모멘텀 SMB
)
mom_cor <- list()
for(nm in names(mom_ids)){
  mm <- load_monthly(file.path("04_Research/strategies", mom_ids[nm], "sim_result.rds"))
  if(is.null(mm)){ mom_cor[[nm]] <- NA; next }
  mm[, act := r - bm]
  o2 <- merge(EPm[,.(ym, ep_r=r, ep_act=act)], mm[,.(ym, m_r=r, m_act=act)], by="ym")
  mom_cor[[nm]] <- list(n=nrow(o2),
                        cor_ret=round(cor(o2$ep_r, o2$m_r, use="complete.obs"),3),
                        cor_act=round(cor(o2$ep_act, o2$m_act, use="complete.obs"),3))
}

# ── ③ EP vs 풀 전체 (module_performance.json 적재 모듈) ──
MP <- fromJSON(file.path(PROJ,"06_Registry/module_performance.json"), simplifyVector=FALSE)
pool_ids <- names(MP$modules)
pool_cor <- data.table(id=character(), n=integer(), cor_ret=numeric(), cor_act=numeric())
for(sid in pool_ids){
  pth <- MP$modules[[sid]]$sim_result_path
  if(is.null(pth)) next
  mm <- load_monthly(pth)
  if(is.null(mm)) next
  mm[, act := r - bm]
  o3 <- merge(EPm[,.(ym, ep_r=r, ep_act=act)], mm[,.(ym, m_r=r, m_act=act)], by="ym")
  if(nrow(o3) < 24) next
  pool_cor <- rbind(pool_cor, data.table(id=sid, n=nrow(o3),
                       cor_ret=cor(o3$ep_r, o3$m_r, use="complete.obs"),
                       cor_act=cor(o3$ep_act, o3$m_act, use="complete.obs")))
}
setorder(pool_cor, -cor_ret)
cat(sprintf("[pool] EP vs %d modules (n>=24m)\n", nrow(pool_cor)))
cat("  cor_ret  분위: min/median/mean/max =", paste(round(c(min(pool_cor$cor_ret), median(pool_cor$cor_ret), mean(pool_cor$cor_ret), max(pool_cor$cor_ret)),3), collapse=" / "), "\n")
cat("  Top-5 최고 수익상관 모듈:\n"); print(head(pool_cor[,.(id, n, cor_ret=round(cor_ret,3), cor_act=round(cor_act,3))],5))
cat("  cor_act  분위: min/median/mean/max =", paste(round(c(min(pool_cor$cor_act), median(pool_cor$cor_act), mean(pool_cor$cor_act), max(pool_cor$cor_act)),3), collapse=" / "), "\n")

# ── ④ EP OOS retention (IS/OOS 60/40 active Sharpe 유지) ──
nM <- nrow(EPm); cut <- floor(nM*0.60)
is_sr  <- sr(EPm$act[1:cut]); oos_sr <- sr(EPm$act[(cut+1):nM])
oos_ret <- if(is.finite(is_sr) && is_sr != 0) oos_sr/is_sr else NA_real_
# net (raw) Sharpe도
is_nsr <- sr(EPm$r[1:cut]); oos_nsr <- sr(EPm$r[(cut+1):nM])
cat(sprintf("[EP OOS] IS active SR=%.3f / OOS active SR=%.3f → retention=%.3f | IS net SR=%.3f / OOS net SR=%.3f\n",
            is_sr, oos_sr, oos_ret, is_nsr, oos_nsr))

# ── 직교성 평결 ──
# 직교 = (vs 1715 수익상관 낮음 <0.6) & (vs momentum active 상관 낮음 <0.4) & (OOS active retention 유지 >0.5)
max_pool_ret <- max(pool_cor$cor_ret)
med_pool_ret <- median(pool_cor$cor_ret)
orth_vs_1715  <- cor_ret_1715 < 0.60
orth_vs_mom   <- all(sapply(mom_cor, function(x) if(is.list(x)) abs(x$cor_act) < 0.40 else TRUE))
oos_ok        <- is.finite(oos_ret) && oos_ret > 0.50
verdict <- if(orth_vs_1715 && orth_vs_mom && oos_ok) "EP_ORTHOGONAL_CONFIRMED" else
           if(orth_vs_mom && oos_ok) "EP_MOM_ORTHOGONAL_PARTIAL (vs 1715 상관 높음)" else
           if(orth_vs_1715 && oos_ok) "EP_1715_ORTHOGONAL_PARTIAL (vs momentum 상관 높음)" else
           "EP_NOT_CLEARLY_ORTHOGONAL"

res <- list(schema_version="v1.0", generated=as.character(Sys.time()),
  module=EP_ID, idea="Basu(1977) Earnings-Yield value premium high-EP decile long-only",
  n_months=nM, date_range=c(EPm$ym[1], tail(EPm$ym,1)),
  ep_active_sharpe_full=round(sr(EPm$act),3), ep_net_sharpe_full=round(sr(EPm$r),3),
  vs_STR1715=list(n_overlap=nrow(ov), cor_return=round(cor_ret_1715,3), cor_active=round(cor_act_1715,3)),
  vs_momentum=mom_cor,
  vs_pool=list(n_modules=nrow(pool_cor),
               cor_return_min=round(min(pool_cor$cor_ret),3), cor_return_median=round(med_pool_ret,3),
               cor_return_mean=round(mean(pool_cor$cor_ret),3), cor_return_max=round(max_pool_ret,3),
               top5_highest_cor=lapply(1:min(5,nrow(pool_cor)), function(i) list(id=pool_cor$id[i], cor_ret=round(pool_cor$cor_ret[i],3), cor_act=round(pool_cor$cor_act[i],3)))),
  oos_retention=list(is_active_sr=round(is_sr,3), oos_active_sr=round(oos_sr,3), active_retention=round(oos_ret,3),
                     is_net_sr=round(is_nsr,3), oos_net_sr=round(oos_nsr,3)),
  verdict=verdict)
write_json(res, file.path(PROJ,"04_Research/factor_rotation/output/ep_orthogonality.json"),
           auto_unbox=TRUE, pretty=TRUE, na="null", digits=4)
cat(sprintf("\n★ EP 직교성 평결: %s\n  vs1715 cor_ret=%.3f cor_act=%.3f | pool cor_ret median=%.3f max=%.3f | OOS active retention=%.3f\n",
            verdict, cor_ret_1715, cor_act_1715, med_pool_ret, max_pool_ret, oos_ret))
cat("저장: 04_Research/factor_rotation/output/ep_orthogonality.json\n")
