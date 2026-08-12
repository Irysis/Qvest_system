## AK2 — 회전 저감이 cap-w PORT_t 2.137 을 문턱에 다가가게 하는가
## 사전등록(측정 전 고정, 이 주석이 정본):
##  AI1 m=12 arm: cap-w PORT_t 2.137 · 회전 12.28/yr. 회전은 base(M26 월간 리밸) 성질이다.
##  레버 = **보유기간 연장**(h개월마다만 리밸, 사이 기간 홀드). h in {1,2,3,6}.
##   ★M26 라운드 선례: 회전 -68% 에 비용절감 1.20%p ~= 신호손실 1.17%p **1:1 교환** → 레버 아님.
##     여기서도 1:1 이면 같은 결론, 비대칭이면 레버.
##  판정 = canonical_screen_bt 절대 basis(cap-w PORT_t) · proxy 금지.
##   AP1 레버: 어느 h 에서 PORT_t >= 2.95
##   AP2 1:1 교환: PORT_t 가 h 에 대해 평평(최대-최소 < 0.3) → 회전은 레버 아님(M26 선례 재현)
##   AP3 악화: h 증가에 PORT_t 단조 감소 → 신호가 빠르게 감쇠(월간이 최적)
##  AP4 자본 자격 주장은 AP1 충족 시에만
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
DATA_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
CODE_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.claude/worktrees/jovial-mcnulty-f7d018"
setwd(DATA_ROOT)
OUT <- file.path(CODE_ROOT, "stage_artifacts/fq170_band_cost_20260809")
source(file.path(CODE_ROOT, "02_Infrastructure/contracts/canonical_screen_bt.R"))

P <- readRDS("stage_artifacts/WT_D20260809_001/p0_panels.rds")
ret <- as.data.table(P$ret)[!is.na(Ret_1m)]; liq <- as.data.table(P$liq)
bench <- unique(as.data.table(P$bench)[!is.na(BM_Ret), .(Date, BM_Ret)])[order(Date)]
B <- as.data.table(readRDS("stage_artifacts/WT_D20260809_003/merged_panel.rds"))
D <- merge(B[!is.na(M26_Revenue_Mom) & !is.na(D03_EWMA)], ret[, .(Date,Ticker,Ret_1m)], by=c("Date","Ticker"))
D <- merge(D, liq[, .(Date,Ticker,adv)], by=c("Date","Ticker"), all.x=TRUE)
D <- D[is.na(adv) | adv >= 2e8]
D[, nmo := .N, by=Date]; D <- D[nmo >= 125L]
D[, rk := frank(-M26_Revenue_Mom, ties.method="first"), by=Date]
D[, q  := cut(frank(D03_EWMA, ties.method="first"),
              breaks=quantile(seq_len(.N), probs=seq(0,1,length.out=11L)),
              include.lowest=TRUE, labels=FALSE), by=Date]
ds <- sort(unique(D$Date))
cat(sprintf("[입력 실측] %d행 · %d개월\n", nrow(D), length(ds)))

pick <- function(dt, m = 12L) {            # m=12 arm 선택 (AI1 정본)
  S <- D[Date == dt][order(rk)]
  keep <- S[seq_len(min(25L-m, .N))]$Ticker
  pool <- S[q %in% 3:4 & !(Ticker %in% keep)][order(rk)][seq_len(min(m,.N))]$Ticker
  c(keep, pool)
}
rows <- list()
for (h in c(1L,2L,3L,6L)) {
  # h개월마다만 재선택, 사이 기간은 직전 보유 유지
  hold <- vector("list", length(ds)); last <- NULL
  for (i in seq_along(ds)) {
    if ((i-1L) %% h == 0L || is.null(last)) last <- pick(ds[i])
    hold[[i]] <- last
  }
  S <- rbindlist(lapply(seq_along(ds), function(i)
    data.table(Date = ds[i], Ticker = hold[[i]], score = 1000 - seq_along(hold[[i]]))))
  r <- try(canonical_screen_bt(S, ret[, .(Date,Ticker,Ret_1m)], bench,
        top_n = 25L, cost_bps_oneway = 15, liq_dt = liq[, .(Date,Ticker,adv)], liq_min = 2e8,
        run_id = paste0("AK2_h", h), strategy_id = paste0("AK2_h", h)), silent = TRUE)
  if (inherits(r,"try-error")) { cat(sprintf("h=%d 실패\n", h)); next }
  rows[[length(rows)+1L]] <- data.table(hold_months = h,
    PORT_t = round(r$portfolio_alpha_t_nw_lag3,3), IR = round(r$information_ratio,3),
    alpha_ann = round(r$alpha_annualized*100,3), turn = round(r$turnover_annual,2),
    EWuni_t = round(r$diag_ew_universe$portfolio_alpha_t_nw_lag3,3))
}
R <- rbindlist(rows); print(R[])
spread <- max(R$PORT_t) - min(R$PORT_t)
verdict <- {
  if (max(R$PORT_t) >= 2.95) "AP1_TURNOVER_IS_LEVER"
  else if (spread < 0.30) "AP2_ONE_TO_ONE_TRADEOFF"
  else if (which.max(R$PORT_t) == 1L) "AP3_MONTHLY_OPTIMAL_DECAY"
  else "AP2b_PARTIAL"
}
cat(sprintf("\nPORT_t 범위 %.3f~%.3f (폭 %.3f) · 회전 %.2f→%.2f\n판정: %s\n★AP4: 자본 자격 주장 없음\n",
            min(R$PORT_t), max(R$PORT_t), spread, R$turn[1], R$turn[nrow(R)], verdict))
fwrite(R, file.path(OUT,"ak2_turnover.csv"))
write_json(list(verdict=verdict, results=R), file.path(OUT,"ak2_result.json"),
           pretty=TRUE, auto_unbox=TRUE, digits=NA)
