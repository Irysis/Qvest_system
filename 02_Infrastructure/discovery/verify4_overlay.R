#==============================================================================
# Phase 0 #4 book-marginal — 발굴신호 + 현 book 오버레이(M4×AR×R05) vs score_eff + 동일 오버레이
#   β_combined = m4_weight_lag × beta_threshold_lag × beta_R05_V5 (period_returns_layer5).
#   overlay_ret[realized] = β[realized] × base_net[decision=realized-1].  (cash leg=0)
#   ★ base_series = seed42(낙관 상단). ΔSR이 결정타.
#==============================================================================
suppressPackageStartupMessages({ library(data.table) })
ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR","C:/Users/99922/OneDrive/Quant_Module_Moltbot")
bs <- fread(file.path(ROOT,".cache/discovery/base_series.csv"))   # ym(decision), A_net, B_net, bm
L5 <- fread(file.path(ROOT,"05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/04_backtest_results/period_returns_layer5.csv"))
L5[, beta := m4_weight_lag * beta_threshold_lag * beta_R05_V5]
L5[, rym := substr(realized_ym,1,7)]
betamap <- setNames(L5$beta, L5$rym)
bookmap <- setNames(L5$ret_L5_V5, L5$rym)   # 실제 book 실현수익(overlay 적용)

# decision ym → realized ym (+1month)
addm <- function(x){ d<-as.Date(paste0(x,"-01")); format(seq(d,by="month",length.out=2)[2],"%Y-%m") }
bs[, realized := sapply(ym, addm)]
bs[, beta := betamap[realized]]
bs[, book := bookmap[realized]]
bs <- bs[!is.na(beta)]
bs[, A_ov := beta * A_net][, B_ov := beta * B_net]

mdd <- function(r){ r<-r[!is.na(r)]; nav<-cumprod(1+r); 1-min(nav/cummax(nav)) }
st <- function(r){ r<-r[!is.na(r)]; n<-length(r); cagr<-prod(1+r)^(12/n)-1; m<-mdd(r)
  list(SR=mean(r)/sd(r)*sqrt(12), CAGR=cagr, MDD=m, calmar=cagr/m) }
row <- function(nm,r){ s<-st(r); cat(sprintf("  %-22s absSR %.2f  CAGR %.1f%%  MDD %.1f%%  calmar %.2f\n",nm,s$SR,s$CAGR*100,s$MDD*100,s$calmar)); s }

cat("============ #4 book-marginal + 오버레이 (OOS",nrow(bs),"월, base=seed42 상단) ============\n")
cat("\n[bare, 오버레이 前]\n"); row("A score_eff bare", bs$A_net); row("B discovery bare", bs$B_net)
cat("\n[overlay 後 = book-level]\n")
sA<-row("A score_eff + overlay", bs$A_ov); sB<-row("B discovery + overlay", bs$B_ov)
sBook<-row("실제 book (ret_L5_V5)", bs$book)
cat(sprintf("\n★ ΔSR(B_ov - A_ov) %+.3f  | Δcalmar %+.3f   (book-marginal 게이트 ΔIR>=0.05 비교)\n",
            sA$SR*-1+sB$SR, sB$calmar-sA$calmar))
cat(sprintf("   B_ov vs 실제book: ΔSR %+.3f\n", sB$SR-sBook$SR))

cat("\n[sub-period overlay ΔSR — 오버레이가 최근 회복시키나?]\n")
for(sp in list(c("2010-01","2015-12"),c("2016-01","2020-12"),c("2021-01","2026-12"))){
  g<-bs[ym>=sp[1] & ym<=sp[2]]
  if(nrow(g)>10) cat(sprintf("  %s~%s (n%d): A_ov SR %.2f | B_ov SR %.2f | ΔSR %+.3f\n",
    sp[1],sp[2],nrow(g), st(g$A_ov)$SR, st(g$B_ov)$SR, st(g$B_ov)$SR-st(g$A_ov)$SR))
}
