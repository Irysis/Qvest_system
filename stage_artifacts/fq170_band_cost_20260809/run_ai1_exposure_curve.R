## AI1 — 밴드 노출 곡선 (조건-안 경로 완결)
## 사전등록(측정 전 고정, 이 주석이 정본):
##  AG2: 밴드 3.2종(13% 노출) → gap t 1.409 미달. AE1: 25종(100%) → 절대 PORT_t 1.713 미달.
##  ⇒ 두 끝점만 재본 상태. 중간(8·12·18종)을 재서 곡선을 완성한다.
##  구성: base = M26 top-25 에서 M26 하위 m 종을 D03 D3~D4 상위(M26 기준)로 교체. m in {3,8,12,18,25}.
##  판정량 = **절대 basis** — canonical_screen_bt 경유 PORT_t(NW3, cap-w). proxy 금지.
##   AJ1 최적점 존재: 어느 m 에서 PORT_t >= 2.95 → 자본 트랙 재개
##   AJ2 전 구간 미달: 조건-안 수렴. 부활 조건 = 비-return 원천 결합
##  AJ3 자본 자격 주장은 AJ1 충족 시에만
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
cat(sprintf("[입력 실측] %d행 · %d개월\n", nrow(D), uniqueN(D$Date)))

rows <- list()
for (m in c(0L,3L,8L,12L,18L,25L)) {
  # score: 유지 종목(M26 상위 25-m)은 높은 점수, 교체분(D3~D4 중 M26 상위 m)은 그 다음
  S <- D[, {
    keepN <- 25L - m
    keep <- if (keepN > 0L) .SD[order(rk)][seq_len(min(keepN,.N))]$Ticker else character(0)
    pool <- .SD[q %in% 3:4 & !(Ticker %in% keep)][order(rk)][seq_len(min(m,.N))]$Ticker
    sel  <- c(keep, pool)
    .(Ticker = .SD$Ticker,
      score = ifelse(.SD$Ticker %in% sel, 1000 - frank(-.SD$M26_Revenue_Mom, ties.method="first"), -1e6))
  }, by = Date]
  r <- try(canonical_screen_bt(S[, .(Date,Ticker,score)], ret[, .(Date,Ticker,Ret_1m)], bench,
        top_n = 25L, cost_bps_oneway = 15, liq_dt = liq[, .(Date,Ticker,adv)], liq_min = 2e8,
        run_id = paste0("AI1_m", m), strategy_id = paste0("AI1_m", m)), silent = TRUE)
  if (inherits(r,"try-error")) { cat(sprintf("m=%d 실패\n", m)); next }
  rows[[length(rows)+1L]] <- data.table(m_band = m,
    PORT_t = round(r$portfolio_alpha_t_nw_lag3,3), IR = round(r$information_ratio,3),
    alpha_ann = round(r$alpha_annualized*100,3), turn = round(r$turnover_annual,2),
    EWuni_t = round(r$diag_ew_universe$portfolio_alpha_t_nw_lag3 %||% NA_real_,3))
}
R <- rbindlist(rows); print(R[])
best <- R[which.max(PORT_t)]
verdict <- if (max(R$PORT_t, na.rm=TRUE) >= 2.95) "AJ1_OPTIMUM_EXISTS" else "AJ2_ALL_BELOW"
cat(sprintf("\n최대 PORT_t = %.3f @ m=%d\n판정: %s\n★AJ3: 자본 자격 주장 없음\n",
            best$PORT_t, best$m_band, verdict))
fwrite(R, file.path(OUT,"ai1_exposure_curve.csv"))
write_json(list(verdict=verdict, best_m=best$m_band, best_t=best$PORT_t, results=R),
           file.path(OUT,"ai1_result.json"), pretty=TRUE, auto_unbox=TRUE, digits=NA)
