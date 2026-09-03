#==============================================================================
# forge_diag_cf.R — 오버레이 한계기여의 forge-권위 재현 (WT-R20260829_004)
#
# optimizer 실측 주장: ①오버레이 한계기여가 5채널 전부 음수 ②무조건화 IV(C2_IV_off)가
# 모든 ON 구성을 지배. 그 주장은 weighted_screen basis(월별 가중수익 집계) 위에서 났다.
# 여기서는 같은 주장을 **forge basis(일별 share-based NAV + 15bps delta + 계약 build_bt_result)**
# 위에서 재현한다.
#
# ★PURE FUNCTION 유지: 비교 대상 비중 패널은 내가 만든 것이 아니라 optimizer 가
#   o2_objects.rds 에 발행한 W/RESC 패널을 **그대로** 소비한다(재선택·재가중 0).
#   authoritative = W2_IV 단 하나이며, 아래 표는 진단(diagnostic)이다.
#==============================================================================
source("run_all.R")   # forge_sim.rds 캐시 경유 — 권위 경로 불변

CF_PATH <- file.path(STAGE_DIR, "forge_cf.rds")

.mk_bt <- function(panel, tag) {
  NET <- .replay(panel, COMMISSION)
  GRS <- .replay(panel, 0)
  dn  <- copy(NET$nav)
  ng  <- copy(GRS$nav); setnames(ng, "NAV", "NAV_gross")
  dn  <- merge(dn, ng, by = "Date", all.x = TRUE)
  dn[is.na(NAV_gross), NAV_gross := NAV]
  dn[, Strategy_Ret := NAV / shift(NAV) - 1]
  dn <- dn[!is.na(Strategy_Ret)]
  sx <- xts(dn$Strategy_Ret, order.by = dn$Date); names(sx) <- "Strategy"
  ba <- BM_DT[Date %in% dn$Date]
  bx <- xts(ba$BM_Ret, order.by = ba$Date); names(bx) <- "Benchmark"
  s2 <- list(DAILY_NAV_DT = dn, PORTFOLIO_LOG = NET$plog, HOLDINGS_LOG = NET$hlog,
             strategy_xts = sx, bm_xts = bx, cost_model_version = "v2.4_delta")
  sp <- spec; sp$strategy_id <- paste0("CF_", tag)
  sp$strategy_name <- paste0("counterfactual ", tag, " (optimizer-emitted weight panel, forge basis)")
  sp$weighting_method <- tag
  b <- build_bt_result(s2, sp, run_id = paste0("FORGE_CF_", tag), strategy_id = paste0("CF_", tag),
                       strategy_version = "forge_v10_cf", benchmark_id = "KOSPI200",
                       benchmark_name = "KOSPI 200 (BM_Ret)",
                       transaction_cost_bps = 15, slippage_bps = 0, risk_free_rate = 0,
                       frequency = "daily", annualization_factor = 252,
                       universe_id = "K200_KQ150",
                       code_version = "WT-R20260829_004/forge_diag_cf.R",
                       created_by_agent = "Forge")
  b
}

.row <- function(b, tag) {
  M  <- as.data.table(b$metrics); BC <- as.data.table(b$benchmark_compare)
  g  <- function(n) { v <- M[metric_name == n, metric_value]; if (length(v)) as.numeric(v[1]) else NA_real_ }
  gb <- function(n) { v <- BC[metric_name == n, active_value]; if (length(v)) as.numeric(v[1]) else NA_real_ }
  data.table(tag = tag, CAGR = g("CAGR"), SR = g("Sharpe"), MDD = g("MDD"),
             Calmar = g("Calmar"), net_IR = gb("Information_Ratio"),
             PORT_t = gb("Portfolio_Alpha_t_NW_lag3"),
             alpha_ann = gb("Alpha_Annualized"), excess_tot = gb("Excess_Total_Return"))
}

if (file.exists(CF_PATH) && !identical(Sys.getenv("FORGE_FORCE_CF"), "1")) {
  CF <- readRDS(CF_PATH)
} else {
  o2 <- readRDS(file.path(STAGE_DIR, "o2_objects.rds"))
  panels <- list(
    W1_EW      = as.data.table(o2$RES$W1_EW$W)[,      .(Date, Ticker, w)],
    W5_WCH_IV  = as.data.table(o2$RES$W5_WCH_IV$W)[,  .(Date, Ticker, w)],
    C1_EW_off  = as.data.table(o2$RESC$C1_EW_off$W)[, .(Date, Ticker, w)],
    C2_IV_off  = as.data.table(o2$RESC$C2_IV_off$W)[, .(Date, Ticker, w)]
  )
  CF <- list()
  for (nm in names(panels)) {
    cat("[cf] replay:", nm, "\n")
    CF[[nm]] <- .mk_bt(panels[[nm]], nm)
  }
  saveRDS(CF, CF_PATH)
}

TAB <- rbindlist(c(list(.row(bt, "W2_IV (ADOPTED, authoritative)")),
                   lapply(names(CF), function(n) .row(CF[[n]], n))))
cat("\n=== forge-basis method comparison (일별 share-based NAV · 15bps delta · 동일 기간) ===\n")
print(TAB, digits = 4)

## 오버레이 한계기여 = (overlay ON) - (overlay OFF), 같은 비중방법 짝
mg <- function(a, b, nm) {
  ra <- TAB[grepl(a, tag, fixed = TRUE)][1]; rb <- TAB[tag == b][1]
  data.table(pair = nm,
             d_Calmar = ra$Calmar - rb$Calmar, d_SR = ra$SR - rb$SR,
             d_netIR = ra$net_IR - rb$net_IR, d_PORT_t = ra$PORT_t - rb$PORT_t,
             d_CAGR = ra$CAGR - rb$CAGR)
}
MARG <- rbindlist(list(mg("W2_IV (ADOPTED", "C2_IV_off", "IV: overlay ON - OFF"),
                       mg("W1_EW", "C1_EW_off", "EW: overlay ON - OFF")))
cat("\n=== 오버레이 한계기여 (forge basis) ===\n"); print(MARG, digits = 4)

DOM <- TAB[which.max(Calmar)]
cat(sprintf("\n=== Calmar 최댓값 구성 = %s (Calmar %.4f) ===\n", DOM$tag, DOM$Calmar))

saveRDS(list(TAB = TAB, MARG = MARG), file.path(STAGE_DIR, "forge_cf_summary.rds"))
fwrite(TAB,  file.path(STAGE_DIR, "forge_cf_table.csv"))
fwrite(MARG, file.path(STAGE_DIR, "forge_cf_marginal.csv"))
cat("=== forge_diag_cf.R done ===\n")
