## F1 — 사전 고정 중간분위 밴드 {4,5,6} vs top-25, net(15bps)
## 사전등록: preregistration_f1.json (측정 전 작성)
## ★겹침률 발행 = 직전 라운드의 항등식 대조(음성대조 퇴화) 재발 방지
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
DATA_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
CODE_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.claude/worktrees/jovial-mcnulty-f7d018"
setwd(DATA_ROOT)
OUT <- file.path(CODE_ROOT, "stage_artifacts/fq170_band_cost_20260809")
source(file.path(CODE_ROOT, "02_Infrastructure/contracts/canonical_screen_bt.R"))
source(file.path(CODE_ROOT, "02_Infrastructure/contracts/required_effect_size.R"))
stopifnot("series" %in% names(formals(required_effect)))

PRE <- fromJSON(file.path(OUT, "preregistration_f1.json"), simplifyVector = FALSE)
cat(sprintf("[prereg] 규칙 %d개 고정 · 밴드 = %s\n",
            length(PRE$decision_rules_fixed_before_results), PRE$design_fixed_before_results$band))

B   <- readRDS("stage_artifacts/WT_D20260809_003/merged_panel.rds")
P   <- readRDS("stage_artifacts/WT_D20260809_001/p0_panels.rds")
ret <- as.data.table(P$ret)[!is.na(Ret_1m)]; liq <- as.data.table(P$liq)
X <- merge(as.data.table(B), ret[, .(Date,Ticker,Ret_1m)], by=c("Date","Ticker"))
X <- merge(X, liq[, .(Date,Ticker,adv)], by=c("Date","Ticker"), all.x=TRUE)
X <- X[is.na(adv) | adv >= 2e8]
cat(sprintf("[입력 실측] %d행 · %d개월 · %s ~ %s\n", nrow(X), uniqueN(X$Date), min(X$Date), max(X$Date)))

COST <- 0.0015; W <- 1/25; BAND <- c(4L,5L,6L)

mats <- list(
  list(tag="M26_Revenue_Mom", col="M26_Revenue_Mom", shape="MONOTONE_TOP"),
  list(tag="M01_PATHQ",       col="M01_PATHQ",       shape="MONOTONE_TOP"),
  list(tag="Q01_EB",          col="Q01_EB",          shape="HUMP"),
  list(tag="D03_EWMA",        col="D03_EWMA",        shape="INVERTED"),
  list(tag="z_neutral",       col="z_neutral",       shape="HUMP"))

rows <- list()
for (m in mats) {
  D <- X[!is.na(get(m$col))]
  D[, nmo := .N, by=Date]; D <- D[nmo >= 125L]
  D[, rk := frank(-get(m$col), ties.method="first"), by=Date]
  D[, q  := cut(frank(get(m$col), ties.method="first"),
                breaks=quantile(seq_len(.N), probs=seq(0,1,length.out=11L)),
                include.lowest=TRUE, labels=FALSE), by=Date]
  ds <- sort(unique(D$Date)); rr <- list(); ht <- list(); hb <- list(); ov <- numeric(0)
  for (dt in ds) {
    S <- D[Date == dt]
    tp <- S[rk <= 25L][order(rk)]
    bd <- S[q %in% BAND][order(rk)][seq_len(min(25L, .N))]
    if (nrow(tp) < 20L || nrow(bd) < 20L) next
    k <- as.character(as.Date(dt))
    ht[[k]] <- tp$Ticker; hb[[k]] <- bd$Ticker
    ov <- c(ov, length(intersect(tp$Ticker, bd$Ticker)) / nrow(tp))
    rr[[k]] <- data.table(Date=as.Date(dt), g_top=mean(tp$Ret_1m), g_bnd=mean(bd$Ret_1m))
  }
  R <- rbindlist(rr)
  cost_of <- function(h) {
    d <- sort(names(h)); sapply(seq_along(d), function(i) {
      cur <- h[[d[i]]]; prv <- if (i==1L) character(0) else h[[d[i-1]]]
      u <- unique(c(cur,prv)); COST * sum(abs(W*(u %in% cur) - W*(u %in% prv)))
    })
  }
  R[, `:=`(c_top = cost_of(ht), c_bnd = cost_of(hb))]
  R[, d_net := (g_bnd - c_bnd) - (g_top - c_top)]
  R[, d_gross := g_bnd - g_top]
  bar <- required_effect(nrow(R), t_threshold=2.0, series=R$d_net)
  rows[[length(rows)+1L]] <- data.table(
    material=m$tag, shape=m$shape, n_months=nrow(R), overlap=mean(ov),
    gross_ann=mean(R$d_gross)*12*100, net_ann=mean(R$d_net)*12*100,
    cost_drag=(mean(R$d_gross)-mean(R$d_net))*12*100,
    t_net=.nw_t_mean(R$d_net, lag=3L),
    bar_ann=bar$required_annual*100, nw_src=bar$nw_inflation_source)
}
S <- rbindlist(rows)
nn <- c("overlap","gross_ann","net_ann","cost_drag","t_net","bar_ann")
S[, (nn) := lapply(.SD, function(z) round(z,3)), .SDcols=nn]
print(S[])

# ── 사전등록 판정 (G1~G4) ────────────────────────────────────────────────────
S[, degenerate := overlap > 0.50]
if (any(S$degenerate)) cat(sprintf("\n★G4 퇴화 arm 제외: %s\n", paste(S[degenerate==TRUE, material], collapse=", ")))
V  <- S[degenerate == FALSE]
tr <- V[shape != "MONOTONE_TOP"]; nc <- V[shape == "MONOTONE_TOP"]
g1_tr <- sum(tr$net_ann > 0 & tr$t_net >= 2.0)
g1_nc <- nrow(nc) >= 1L && all(nc$net_ann < 0)
g3    <- any(nc$net_ann > 0 & nc$t_net >= 2.0)
verdict <- {
  if (nrow(tr) < 2L || nrow(nc) < 1L) "INSUFFICIENT_NONDEGENERATE_ARMS"
  else if (g3) "G3_SHAPE_CLAIM_REJECTED"
  else if (g1_tr >= 2L && g1_nc) "G1_MID_BAND_SUPPORTED"
  else "G2_CONFIG_SCOPED_NEGATIVE"
}
cat(sprintf("\n=== 사전등록 판정 ===\ntreatment 충족 %d/%d · negative control 전부 음 %s · 겹침 최대 %.3f\n",
            g1_tr, nrow(tr), g1_nc, max(S$overlap)))
cat(sprintf("판정: %s\n★G5: 자본 자격 주장 없음\n", verdict))

fwrite(S, file.path(OUT,"f1_fixed_band_summary.csv"))
write_json(list(round_id=PRE$round_id, verdict=verdict, band=BAND,
                treatment_hits=g1_tr, negctrl_all_negative=g1_nc, results=S),
           file.path(OUT,"f1_result.json"), pretty=TRUE, auto_unbox=TRUE, digits=NA)
