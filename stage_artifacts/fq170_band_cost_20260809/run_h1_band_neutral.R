## H1 — 밴드-중립 선별로 밴드 가설을 **처음으로** 검정
## 사전등록: preregistration_h1.json (측정 전 작성)
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
DATA_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
CODE_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.claude/worktrees/jovial-mcnulty-f7d018"
setwd(DATA_ROOT)
OUT <- file.path(CODE_ROOT, "stage_artifacts/fq170_band_cost_20260809")
source(file.path(CODE_ROOT, "02_Infrastructure/contracts/canonical_screen_bt.R"))
source(file.path(CODE_ROOT, "02_Infrastructure/contracts/required_effect_size.R"))
stopifnot("series" %in% names(formals(required_effect)))
PRE <- fromJSON(file.path(OUT, "preregistration_h1.json"), simplifyVector = FALSE)
cat(sprintf("[prereg] 규칙 %d개 고정\n", length(PRE$decision_rules_fixed_before_results)))

B <- readRDS("stage_artifacts/WT_D20260809_003/merged_panel.rds")
P <- readRDS("stage_artifacts/WT_D20260809_001/p0_panels.rds")
ret <- as.data.table(P$ret)[!is.na(Ret_1m)]; liq <- as.data.table(P$liq)
X <- merge(as.data.table(B), ret[, .(Date,Ticker,Ret_1m)], by=c("Date","Ticker"))
X <- merge(X, liq[, .(Date,Ticker,adv)], by=c("Date","Ticker"), all.x=TRUE)
X <- X[is.na(adv) | adv >= 2e8]
cat(sprintf("[입력 실측] %d행 · %d개월\n", nrow(X), uniqueN(X$Date)))

COST <- 0.0015; BAND <- c(4L,5L,6L); NDRAW <- 20L
mats <- list(
  list(tag="M26_Revenue_Mom", shape="MONOTONE_TOP"), list(tag="M01_PATHQ", shape="MONOTONE_TOP"),
  list(tag="Q01_EB", shape="HUMP"), list(tag="D03_EWMA", shape="INVERTED"), list(tag="z_neutral", shape="HUMP"))

cost_of <- function(h, w) {           # h: list(date -> tickers), w: 종목당 비중
  d <- sort(names(h)); sapply(seq_along(d), function(i) {
    cur <- h[[d[i]]]; prv <- if (i==1L) character(0) else h[[d[i-1]]]
    u <- unique(c(cur,prv)); COST * sum(abs(w*(u %in% cur) - w*(u %in% prv)))
  })
}

rows <- list()
for (m in mats) {
  sc <- m$tag
  D <- X[!is.na(get(sc))]
  D[, nmo := .N, by=Date]; D <- D[nmo >= 125L]
  D[, rk := frank(-get(sc), ties.method="first"), by=Date]
  D[, q  := cut(frank(get(sc), ties.method="first"),
                breaks=quantile(seq_len(.N), probs=seq(0,1,length.out=11L)),
                include.lowest=TRUE, labels=FALSE), by=Date]
  ds <- sort(unique(D$Date))
  keep <- ds[sapply(ds, function(dt) { S <- D[Date==dt]; sum(S$rk<=25L)>=20L && sum(S$q %in% BAND)>=25L })]
  Dk <- D[Date %in% keep]

  # arm_top
  ht <- split(Dk[rk<=25L]$Ticker, Dk[rk<=25L]$Date)
  g_top <- Dk[rk<=25L, .(g=mean(Ret_1m)), by=Date][order(Date)]
  c_top <- cost_of(ht[order(names(ht))], 1/25)
  eff_top <- Dk[rk<=25L, mean(q)]

  # arm_band_ew (밴드 전체)
  Bd <- Dk[q %in% BAND]
  g_bew <- Bd[, .(g=mean(Ret_1m), n=.N), by=Date][order(Date)]
  hb_ew <- split(Bd$Ticker, Bd$Date)
  c_bew <- sapply(seq_along(hb_ew), function(i) {
    d <- sort(names(hb_ew)); cur <- hb_ew[[d[i]]]; prv <- if (i==1L) character(0) else hb_ew[[d[i-1]]]
    u <- unique(c(cur,prv)); COST*sum(abs((1/length(cur))*(u %in% cur) - (if(!length(prv)) 0 else 1/length(prv))*(u %in% prv)))
  })
  eff_bew <- mean(Bd$q)

  # arm_band_rand25 — 무작위 25종 x NDRAW
  draw_net <- matrix(NA_real_, nrow=length(keep), ncol=NDRAW)
  eff_r <- numeric(NDRAW)
  for (k in seq_len(NDRAW)) {
    set.seed(20260809L + k)
    sel <- Bd[, .SD[sample(.N, 25L)], by=Date]
    g <- sel[, .(g=mean(Ret_1m)), by=Date][order(Date)]
    h <- split(sel$Ticker, sel$Date)
    cc <- cost_of(h[order(names(h))], 1/25)
    draw_net[, k] <- (g$g - cc) - (g_top$g - c_top)
    eff_r[k] <- mean(sel$q)
  }
  net_rand <- rowMeans(draw_net)
  ann_per_draw <- colMeans(draw_net)*12*100

  net_bew <- (g_bew$g - c_bew) - (g_top$g - c_top)
  bar <- required_effect(length(net_rand), t_threshold=2.0, series=net_rand)

  rows[[length(rows)+1L]] <- data.table(
    material=sc, shape=m$shape, n_months=length(keep),
    eff_dec_top=eff_top, eff_dec_band=mean(eff_r), band_n=mean(g_bew$n),
    net_rand_ann=mean(net_rand)*12*100, t_rand=.nw_t_mean(net_rand, lag=3L),
    draw_sd_ann=sd(ann_per_draw),
    net_bew_ann=mean(net_bew)*12*100, t_bew=.nw_t_mean(net_bew, lag=3L),
    bar_ann=bar$required_annual*100, nw_src=bar$nw_inflation_source)
}
S <- rbindlist(rows)
nn <- setdiff(names(S), c("material","shape","n_months","nw_src"))
S[, (nn) := lapply(.SD, function(z) round(z,3)), .SDcols=nn]
print(S[, .(material, shape, eff_dec_top, eff_dec_band, net_rand_ann, t_rand, draw_sd_ann, bar_ann)])
cat("\n"); print(S[, .(material, band_n, net_bew_ann, t_bew, nw_src)])

# ── 판정 (H1a~H1e) ───────────────────────────────────────────────────────────
off <- S[abs(eff_dec_band - 5.0) > 0.5]
if (nrow(off)) cat(sprintf("\n★H1d 경보 — 유효분위가 밴드중심 ±0.5 밖: %s\n",
                           paste(sprintf("%s(%.2f)", off$material, off$eff_dec_band), collapse=", ")))
tr <- S[shape != "MONOTONE_TOP"]; nc <- S[shape == "MONOTONE_TOP"]
h_tr <- sum(tr$net_rand_ann > 0 & tr$t_rand >= 2.0)
h_nc <- all(nc$net_rand_ann < 0)
h_c  <- any(nc$net_rand_ann > 0 & nc$t_rand >= 2.0)
verdict <- {
  if (h_c) "H1c_SHAPE_CLAIM_REJECTED"
  else if (h_tr >= 2L && h_nc) "H1a_BAND_HYPOTHESIS_SUPPORTED"
  else "H1b_CONFIG_SCOPED_NEGATIVE"
}
cat(sprintf("\n=== 사전등록 판정 ===\ntreatment %d/3 · negctrl 전부 음 %s · draw sd 최대 %.3f%%p\n",
            h_tr, h_nc, max(S$draw_sd_ann)))
cat(sprintf("판정: %s\n★H1f: 자본 자격 주장 없음\n", verdict))

fwrite(S, file.path(OUT,"h1_band_neutral_summary.csv"))
write_json(list(round_id=PRE$round_id, verdict=verdict, band=BAND, n_draws=NDRAW,
                treatment_hits=h_tr, negctrl_all_negative=h_nc, results=S),
           file.path(OUT,"h1_result.json"), pretty=TRUE, auto_unbox=TRUE, digits=NA)
