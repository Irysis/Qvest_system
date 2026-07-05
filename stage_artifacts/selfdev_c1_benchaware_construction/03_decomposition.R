# 03_decomposition.R — mandated analyses:
#  (A) Mega-cap drag decomposition of the EW baseline's active return.
#      active_t = sum_i (w_port_i - w_bm_i) * r_i   [Brinson-style allocation, single period]
#      Split into: contribution from the top-2 (later top-3) mega-cap names vs the residual (rest).
#      This isolates how much of the wall is CONSTRUCTION (underweighting mega-caps) vs SELECTION.
#  (B) Active-share of each key variant vs the cap-weighted benchmark (closet-index test).
#      active_share_t = 0.5 * sum_i |w_port_i - w_bm_i|   (over full universe union).
#      Requires per-name BM weights = cap-share within the universe (our BM proxy = cap-weight of union).
#
# NOTE on BM weights: the true KOSPI200 total-return index weights the 200 K200 names by cap.
#   Our universe is K200 U KQ150. We approximate per-name BM weight = cap-share within the K200-only
#   set (since the benchmark is KOSPI200). We compute BM weights over K200 members only.
#   This is the honest matched denominator for active-share; KQ150-only names have bm_i=0.

suppressPackageStartupMessages({ library(data.table); library(arrow) })
setDTthreads(1)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
WD   <- file.path(ROOT, "stage_artifacts/selfdev_c1_benchaware_construction")

# rebuild panel with K200 flag so we can form BM weights over K200
suppressPackageStartupMessages(library(arrow))
rd <- as.data.table(read_parquet(file.path(ROOT, ".cache/RAWDATA.parquet")))
rd <- rd[, .(Date, Ticker, K200, KQ150, Close, Vol, Size, Ret)]
rd[, Date := as.Date(Date)]; setorder(rd, Ticker, Date)
rd[, ym := as.Date(cut(Date, "month"))]
rd[, dvalue := Close * Vol]; rd[, adv20 := frollmean(dvalue, 20, align="right"), by=Ticker]
rd[, .grp := .GRP, by=.(Ticker, ym)]; me <- rd[rd[, .I[.N], by=.grp]$V1]
setorder(me, Ticker, ym); me[, close_prev := shift(Close,1), by=Ticker]; me[, mret := Close/close_prev-1]
me[, lr := log1p(mret)]; me[, cs := cumsum(fifelse(is.na(lr),0,lr)), by=Ticker]
me[, cnt := cumsum(as.integer(!is.na(lr))), by=Ticker]
me[, cs_lag1 := shift(cs,1), by=Ticker]; me[, cs_lag12 := shift(cs,12), by=Ticker]
me[, cnt_lag1 := shift(cnt,1), by=Ticker]; me[, cnt_lag12 := shift(cnt,12), by=Ticker]
me[, mom_12_1 := exp(cs_lag1-cs_lag12)-1]; me[(cnt_lag1-cnt_lag12)<11, mom_12_1 := NA_real_]
me[, Ret_1m := shift(mret,-1), by=Ticker]
me[, in_univ := (K200==TRUE | KQ150==TRUE)]
P <- me[in_univ==TRUE & Date>=as.Date("2005-01-01") & Date<=as.Date("2026-06-01"),
        .(Date=ym, Ticker, K200, mcap_t=Size, adv20_t=adv20, mom_12_1, Ret_1m)]
P <- P[is.finite(adv20_t) & adv20_t>=2e8 & is.finite(mom_12_1) & is.finite(Ret_1m) & is.finite(mcap_t)]
dts <- sort(unique(P$Date))

WMAX <- 0.20; TOP_N <- 25L
cap_renorm <- function(w, wmax=WMAX){ w<-pmax(w,0); if(sum(w)==0) return(w); w<-w/sum(w)
  for(it in 1:50){ over<-w>wmax+1e-12; if(!any(over)) break; ex<-sum(w[over]-wmax); w[over]<-wmax
    fr<- !over & w>0; if(!any(fr)){w[over]<-wmax; break}; w[fr]<-w[fr]+ex*w[fr]/sum(w[fr]) }; w/sum(w) }

# ---------- (A) Mega-cap drag decomposition of EW baseline ----------
# Per month: BM weights over K200 members (cap-share). Port = EW top-25 by momentum.
# allocation contribution_i = (w_port_i - w_bm_i) * (r_i - r_bm), where r_bm = BM return that month
#   (Brinson pure allocation w.r.t. benchmark). Sum over i = total active return (approx, single-level).
# Attribute to: anchor set (top-K by cap in universe) vs rest.
drag_decomp <- function(Kset = 2L){
  rows <- vector("list", length(dts))
  for (i in seq_along(dts)) {
    D <- dts[i]; m <- P[Date==D]
    if (nrow(m) < TOP_N) next
    # BM weights: cap-share among K200 members this month
    k2 <- m[K200==TRUE]
    if (nrow(k2)==0) next
    k2[, w_bm := mcap_t/sum(mcap_t)]
    bm <- merge(m, k2[,.(Ticker,w_bm)], by="Ticker", all.x=TRUE); bm[is.na(w_bm), w_bm := 0]
    r_bm <- sum(bm$w_bm * bm$Ret_1m)   # reconstructed cap-weighted K200 return (proxy)
    # EW top-25 by momentum
    setorder(bm, -mom_12_1); sel <- bm$Ticker[seq_len(TOP_N)]
    bm[, w_port := ifelse(Ticker %in% sel, 1/TOP_N, 0)]
    # anchor = top-K by cap in universe
    setorder(bm, -mcap_t); anch <- bm$Ticker[seq_len(Kset)]
    bm[, contrib := (w_port - w_bm) * (Ret_1m - r_bm)]
    c_anch <- sum(bm[Ticker %in% anch]$contrib)
    c_rest <- sum(bm[!Ticker %in% anch]$contrib)
    rows[[i]] <- data.table(Date=D, active=sum(bm$contrib), c_anchor=c_anch, c_rest=c_rest,
                            wbm_anch=sum(bm[Ticker %in% anch]$w_bm),
                            wport_anch=sum(bm[Ticker %in% anch]$w_port))
  }
  rbindlist(rows)
}
dd2 <- drag_decomp(2L); dd3 <- drag_decomp(3L)
sumtab <- function(dd, K){
  data.table(K=K,
    mean_active_ann = mean(dd$active)*12,
    mean_anchor_drag_ann = mean(dd$c_anchor)*12,
    mean_rest_ann = mean(dd$c_rest)*12,
    anchor_share_of_active = mean(dd$c_anchor)/mean(dd$active),
    mean_bm_wt_on_anchor = mean(dd$wbm_anch),
    mean_port_wt_on_anchor = mean(dd$wport_anch),
    mean_underweight = mean(dd$wbm_anch - dd$wport_anch))
}
DRAG <- rbindlist(list(sumtab(dd2,2L), sumtab(dd3,3L)))
fwrite(DRAG, file.path(WD, "drag_decomposition.csv"))
cat("\n===== (A) MEGA-CAP DRAG DECOMPOSITION (EW top-25 baseline) =====\n")
cat("active_ann = mean monthly active x12 (allocation attribution vs cap-weighted K200 proxy)\n")
print(DRAG[, .(K, active_ann=round(mean_active_ann,4), anchor_drag_ann=round(mean_anchor_drag_ann,4),
               rest_ann=round(mean_rest_ann,4), anchor_share=round(anchor_share_of_active,3),
               bm_wt_anchor=round(mean_bm_wt_on_anchor,3), port_wt_anchor=round(mean_port_wt_on_anchor,3),
               underweight=round(mean_underweight,3))])

# ---------- (B) Active-share of key variants (closet-index test) ----------
# active_share = 0.5 * sum |w_port - w_bm| over universe union (bm over K200 cap-share).
active_share <- function(build_fn, tag){
  vals <- numeric(0)
  for (i in seq_along(dts)) {
    D <- dts[i]; m <- P[Date==D]; if (nrow(m) < TOP_N) next
    k2 <- m[K200==TRUE]; if (nrow(k2)==0) next
    k2[, w_bm := mcap_t/sum(mcap_t)]
    wt <- build_fn(m)   # returns data.table(Ticker,w)
    a <- merge(m[,.(Ticker)], wt, by="Ticker", all.x=TRUE); a[is.na(w), w:=0]
    a <- merge(a, k2[,.(Ticker,w_bm)], by="Ticker", all.x=TRUE); a[is.na(w_bm), w_bm:=0]
    vals <- c(vals, 0.5*sum(abs(a$w - a$w_bm)))
  }
  data.table(tag=tag, active_share=mean(vals))
}
bf_ew <- function(m){ setorder(m,-mom_12_1); s<-m$Ticker[1:TOP_N]; data.table(Ticker=s, w=1/TOP_N) }
bf_capw <- function(m){ setorder(m,-mom_12_1); s<-m[1:TOP_N]; data.table(Ticker=s$Ticker, w=cap_renorm(s$mcap_t)) }
bf_anch2ew <- function(m){ setorder(m,-mcap_t); anch<-m$Ticker[1:2]; rest<-m[!Ticker%in%anch]; setorder(rest,-mom_12_1)
  sel<-rest[1:(TOP_N-2)]; data.table(Ticker=c(anch,sel$Ticker), w=cap_renorm(c(rep(0.20,2), rep(0.60/(TOP_N-2),TOP_N-2)))) }
bf_anch2alpha <- function(m){ setorder(m,-mcap_t); anch<-m$Ticker[1:2]; rest<-m[!Ticker%in%anch]; setorder(rest,-mom_12_1)
  sel<-rest[1:(TOP_N-2)]; sc<-pmax(sel$mom_12_1-min(sel$mom_12_1)+1e-6,1e-6)
  data.table(Ticker=c(anch,sel$Ticker), w=cap_renorm(c(rep(0.20,2), 0.60*sc/sum(sc)))) }

AS <- rbindlist(list(
  active_share(bf_ew, "V1_EW_top25"),
  active_share(bf_capw, "V2_CapW_top25"),
  active_share(bf_anch2ew, "V4_Anchor2_EWfill"),
  active_share(bf_anch2alpha, "V5_Anchor2_AlphaFill")
))
fwrite(AS, file.path(WD, "active_share.csv"))
cat("\n===== (B) ACTIVE SHARE vs cap-weighted K200 (closet-index test) =====\n")
cat("active_share -> 1 = fully active; -> 0 = closet index (holding the benchmark).\n")
print(AS[, .(tag, active_share=round(active_share,3))])
cat("\n[decomp] DONE\n")
