## I3 — 상단 집중(top-10/15 vs top-25) : 이 아크 최초의 **양성 규칙** 검정
## 사전등록: preregistration_i3.json (측정 전 작성)
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
DATA_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
CODE_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.claude/worktrees/jovial-mcnulty-f7d018"
setwd(DATA_ROOT)
OUT <- file.path(CODE_ROOT, "stage_artifacts/fq170_band_cost_20260809")
source(file.path(CODE_ROOT, "02_Infrastructure/contracts/canonical_screen_bt.R"))
source(file.path(CODE_ROOT, "02_Infrastructure/contracts/required_effect_size.R"))
stopifnot("series" %in% names(formals(required_effect)))
PRE <- fromJSON(file.path(OUT, "preregistration_i3.json"), simplifyVector = FALSE)
cat(sprintf("[prereg] 규칙 %d개 고정\n", length(PRE$decision_rules_fixed_before_results)))

B <- readRDS("stage_artifacts/WT_D20260809_003/merged_panel.rds")
P <- readRDS("stage_artifacts/WT_D20260809_001/p0_panels.rds")
ret <- as.data.table(P$ret)[!is.na(Ret_1m)]; liq <- as.data.table(P$liq)
X <- merge(as.data.table(B), ret[, .(Date,Ticker,Ret_1m)], by=c("Date","Ticker"))
X <- merge(X, liq[, .(Date,Ticker,adv)], by=c("Date","Ticker"), all.x=TRUE)
X <- X[is.na(adv) | adv >= 2e8]
cat(sprintf("[입력 실측] %d행 · %d개월\n", nrow(X), uniqueN(X$Date)))

COST <- 0.0015
mats <- list(
  list(tag="M26_Revenue_Mom", grp="MONOTONE_TOP"), list(tag="M01_PATHQ", grp="MONOTONE_TOP"),
  list(tag="Q01_EB", grp="control"), list(tag="D03_EWMA", grp="control"), list(tag="z_neutral", grp="control"))

arm_of <- function(D, N) {
  S <- D[rk <= N]
  g <- S[, .(g=mean(Ret_1m), dec=mean(q), rkm=mean(rk)), by=Date][order(Date)]
  h <- split(S$Ticker, S$Date); h <- h[order(names(h))]
  w <- 1/N
  cc <- sapply(seq_along(h), function(i) {
    cur <- h[[i]]; prv <- if (i==1L) character(0) else h[[i-1]]
    u <- unique(c(cur,prv)); COST*sum(abs(w*(u %in% cur) - w*(u %in% prv)))
  })
  list(net = g$g - cc, gross = g$g, dec = mean(g$dec), rk = mean(g$rkm), dates = g$Date)
}

rows <- list()
for (m in mats) {
  D <- X[!is.na(get(m$tag))]
  D[, nmo := .N, by=Date]; D <- D[nmo >= 125L]
  D[, rk := frank(-get(m$tag), ties.method="first"), by=Date]
  D[, q  := cut(frank(get(m$tag), ties.method="first"),
                breaks=quantile(seq_len(.N), probs=seq(0,1,length.out=11L)),
                include.lowest=TRUE, labels=FALSE), by=Date]
  ok <- D[, .N, by=Date][N >= 125L, Date]; D <- D[Date %in% ok]
  a25 <- arm_of(D, 25L)
  for (N in c(15L, 10L)) {
    aN <- arm_of(D, N)
    stopifnot(identical(aN$dates, a25$dates))
    dn <- aN$net - a25$net; dg <- aN$gross - a25$gross
    bar <- required_effect(length(dn), t_threshold=2.0, series=dn)
    rows[[length(rows)+1L]] <- data.table(
      material=m$tag, grp=m$grp, topN=N, n_months=length(dn),
      eff_dec=aN$dec, eff_rank=aN$rk,
      gross_ann=mean(dg)*12*100, net_ann=mean(dn)*12*100,
      cost_drag=(mean(dg)-mean(dn))*12*100,
      t_net=.nw_t_mean(dn, lag=3L),
      bar_ann=bar$required_annual*100, nw_src=bar$nw_inflation_source)
  }
}
S <- rbindlist(rows)
nn <- c("eff_dec","eff_rank","gross_ann","net_ann","cost_drag","t_net","bar_ann")
S[, (nn) := lapply(.SD, function(z) round(z,3)), .SDcols=nn]
print(S[, .(material, grp, topN, gross_ann, net_ann, cost_drag, t_net, bar_ann)])

tr <- S[grp == "MONOTONE_TOP"]; nc <- S[grp == "control"]
j1_tr <- all(sapply(unique(tr$material), function(mm) {
  z <- tr[material == mm]; any(z$net_ann > 0 & z$t_net >= 2.0) }))
nc_ok <- sum(sapply(unique(nc$material), function(mm) {
  z <- nc[material == mm]; all(z$net_ann <= 0 | z$t_net < 2.0) }))
j3 <- nc_ok == 0L
verdict <- {
  if (j3) "J3_GENERAL_CONCENTRATION_EFFECT"
  else if (j1_tr && nc_ok >= 2L) "J1_SHAPE_DIRECTED_CONCENTRATION_SUPPORTED"
  else "J2_CONFIG_SCOPED_NEGATIVE"
}
cat(sprintf("\n=== 사전등록 판정 ===\nMONOTONE_TOP 전건 충족 %s · control 기대대로 %d/3\n", j1_tr, nc_ok))
cat(sprintf("판정: %s\n★J5: 자본 자격 주장 없음\n", verdict))
if (any(S$gross_ann > 0 & S$net_ann < 0)) cat("★J4: gross 양 / net 음 arm 존재 — 회전 비용 지배\n")

fwrite(S, file.path(OUT,"i3_top_concentration_summary.csv"))
write_json(list(round_id=PRE$round_id, verdict=verdict, results=S),
           file.path(OUT,"i3_result.json"), pretty=TRUE, auto_unbox=TRUE, digits=NA)
