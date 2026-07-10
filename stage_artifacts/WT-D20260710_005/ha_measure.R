# H-a: 정정공시(restatement) 빈도/강도 disclosure-quality signal.
# PIT: rcept_dt (공시 접수일, public timestamp) <= 월말 sig_date t; forward = month t+1 realized return.
# 자체합성 금지: 성과는 canonical_screen_bt(build_benchmark_compare) 경유. book-marginal = paired NW-t.
suppressMessages({library(data.table); library(arrow)})
setDTthreads(1)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT  <- file.path(ROOT,"stage_artifacts/WT-D20260710_005")
CK   <- file.path(OUT,"disc_ck")
source(file.path(ROOT,"02_Infrastructure/contracts/canonical_screen_bt.R"))

# ---- 1. Combine fetched disclosure metadata ----
cat("[1] combine disc checkpoints...\n"); flush.console()
files <- list.files(CK, pattern="\\.csv$", full.names=TRUE)
cat("  checkpoint files:", length(files), "\n")
D <- rbindlist(lapply(files, function(f){
  x <- tryCatch(fread(f, colClasses="character"), error=function(e) NULL)
  if(is.null(x)||nrow(x)==0) return(NULL)
  x
}), fill=TRUE)
D <- D[!is.na(stock_code) & nchar(stock_code)==6]
D[, Ticker := paste0("A", stock_code)]
D[, rd := as.IDate(as.character(rcept_dt), format="%Y%m%d")]
D <- D[!is.na(rd)]
D[, is_restate := as.integer(grepl("정정", report_nm))]
D[, is_restate_strict := as.integer(grepl("^\\[기재정정\\]|^기재정정", report_nm))]
D[, ym := as.integer(format(rd,"%Y%m"))]
cat(sprintf("  rows=%d tickers=%d date=%s..%s restate=%d strict=%d\n",
  nrow(D), uniqueN(D$Ticker), as.character(min(D$rd)), as.character(max(D$rd)),
  sum(D$is_restate), sum(D$is_restate_strict)))

# data depth per firm
depth <- D[, .(first_rd=min(rd), n_fil=.N, n_restate=sum(is_restate)), by=Ticker]
cat(sprintf("  depth: firms w/ first_rd<=2005-12=%d | median first_rd=%s | median n_fil=%.0f\n",
  as.integer(sum(depth$first_rd<=as.IDate("2005-12-31"))), as.character(as.IDate(median(depth$first_rd))), as.numeric(median(depth$n_fil))))
saveRDS(D, file.path(OUT,"ha_disc_panel.rds"))

# ---- 2. Monthly signal grid: trailing restatement metrics (PIT rcept_dt<=t) ----
cat("[2] monthly trailing restatement signal (PIT)...\n"); flush.console()
# monthly sig grid = score_eff months (universe/return anchor)
seff <- as.data.table(read_parquet(file.path(OUT,"..","WT_D20260425_010/alpha_scores.parquet"),
  col_select=c("Date","Ticker","score_eff","Ret_1m")))
seff[, sdate := as.IDate(as.character(Date))]
seff[, ym := as.integer(format(sdate,"%Y%m"))]
seff <- seff[is.finite(score_eff)&is.finite(Ret_1m)]
mgrid <- seff[, .(sdate=max(sdate)), by=ym]   # month-end sig date per ym

# For each (firm, sig month), trailing-W-month counts using rcept_dt <= sig month-end.
# efficient: expand D to monthly counts then rolling-sum over trailing window.
Dmo <- D[, .(n_fil=.N, n_restate=sum(is_restate), n_restate_s=sum(is_restate_strict)), by=.(Ticker, ym)]
# full (Ticker x ym) grid over observed months to allow rolling windows incl zero months
all_ym <- sort(unique(seff$ym))
firms  <- unique(D$Ticker)
G <- CJ(Ticker=firms, ym=all_ym)
G <- merge(G, Dmo, by=c("Ticker","ym"), all.x=TRUE)
for(c in c("n_fil","n_restate","n_restate_s")) G[is.na(get(c)),(c):=0L]
setorder(G, Ticker, ym)
roll <- function(x,w) frollsum(x, w, align="right", na.rm=TRUE)
for(w in c(12L,24L)){
  G[, paste0("fil_",w)     := roll(n_fil,w), by=Ticker]
  G[, paste0("res_",w)     := roll(n_restate,w), by=Ticker]
  G[, paste0("ress_",w)    := roll(n_restate_s,w), by=Ticker]
}
# signals: restate_rate (res/fil), restate_count (res), for 12/24M. quality = -rate (low restate=high quality)
G[, rate_24  := res_24 / pmax(fil_24,1)]
G[, rate_12  := res_12 / pmax(fil_12,1)]
G[, cnt_24   := res_24]
G[, cnt_12   := res_12]
G[, rate_s24 := ress_24 / pmax(fil_24,1)]
# require minimum filing history to define rate (avoid tiny-denominator noise)
G[, has_hist := as.integer(fil_24 >= 4)]
saveRDS(G, file.path(OUT,"ha_signal_grid.rds"))
cat(sprintf("  grid rows=%d firms=%d months=%d | has_hist rows=%d | mean rate_24=%.3f\n",
  nrow(G), uniqueN(G$Ticker), uniqueN(G$ym), sum(G$has_hist), mean(G[has_hist==1]$rate_24)))

# ---- 3. Merge to score_eff universe + forward return + Size + liq + benchmark ----
cat("[3] merge return/size/liq/bench...\n"); flush.console()
raw <- as.data.table(read_parquet(file.path(ROOT,".cache/RAWDATA.parquet"),
  col_select=c("Date","Ticker","Size","Vol","Close","BM_Ret")))
raw[, sdate := as.IDate(as.character(Date))]
raw[, ym := as.integer(format(sdate,"%Y%m"))]
# 20d ADV (trading value) at month-end: mean(Close*Vol) trailing 20d -> use month-end proxy = last Close*Vol avg
setkey(raw, Ticker, sdate)
raw[, tv := as.numeric(Close)*as.numeric(Vol)]
raw[, adv20 := frollmean(tv, 20, align="right"), by=Ticker]
me_raw <- raw[raw[, .I[.N], by=.(Ticker,ym)]$V1, .(Ticker, ym, Size=as.numeric(Size), adv=adv20)]
# monthly benchmark compound — ONE market return per trading day (BM_Ret duplicated across tickers)
bmd <- raw[, .(BM_Ret = BM_Ret[1]), by=.(sdate, ym)]
setorder(bmd, sdate)
bm <- bmd[, .(BM_Ret = prod(1+BM_Ret, na.rm=TRUE)-1), by=ym]

P <- merge(seff[, .(Ticker, ym, sdate, score_eff, Ret_1m)], G, by=c("Ticker","ym"), all.x=TRUE)
P <- merge(P, me_raw, by=c("Ticker","ym"), all.x=TRUE)
for(c in c("rate_24","rate_12","cnt_24","cnt_12","rate_s24")) P[is.na(get(c)), (c):=0]
P[is.na(has_hist), has_hist:=0L]
saveRDS(list(P=P, bm=bm), file.path(OUT,"ha_panel_merged.rds"))
cat("  merged rows=", nrow(P), " months=", uniqueN(P$ym), "\n", sep="")
cat("DONE_PART1\n")
