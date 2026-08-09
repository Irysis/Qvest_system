#!/usr/bin/env Rscript
# =============================================================================
# p1c_turnover_build.R — HOLDINGS_LOG 에서 월별 회전율 실측 (proxy 아님).
#   turnover_m = 0.5 * sum_over_union_tickers |w_m - w_{m-1}|   (name-level, 리밸런스 시점)
#   PIT: 리밸런스 m 의 회전율은 Signal_Date(=m-1 월말)에 확정 → 월 m 종료 시점에 기지(旣知).
#   산출: stage_artifacts/.../turnover_monthly.rds  (data.table: module_id, ym, turnover)
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
PROJ <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", ""))
if (!nzchar(PROJ)) PROJ <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(PROJ); OUT <- file.path(PROJ, "stage_artifacts/scrap_ensemble_20260809")
sink(file.path(OUT, "p1c_turnover.log"), split = TRUE)

P  <- readRDS(file.path(OUT, "p0_panel.rds"))
MP <- fromJSON(file.path(PROJ, "06_Registry/module_performance.json"), simplifyVector = FALSE)

ids <- P$scrap_ok
cat(sprintf("=== INPUT: %d scrap ids, registry %d modules ===\n", length(ids), length(MP$modules)))

res <- vector("list", length(ids)); nfail <- 0L; nmiss <- 0L; nhold <- 0L
for (j in seq_along(ids)) {
  sid <- ids[j]; ent <- MP$modules[[sid]]
  if (is.null(ent) || is.null(ent$sim_result_path)) { nmiss <- nmiss + 1L; next }
  p <- file.path(PROJ, ent$sim_result_path)
  if (!file.exists(p)) { nmiss <- nmiss + 1L; next }
  s <- tryCatch(readRDS(p), error = function(e) NULL)
  if (is.null(s) || !("HOLDINGS_LOG" %in% names(s))) { nfail <- nfail + 1L; next }
  H <- as.data.table(s$HOLDINGS_LOG)
  if (!all(c("Exec_Date","Ticker","Weight") %in% names(H)) || !nrow(H)) { nfail <- nfail + 1L; next }
  nhold <- nhold + 1L
  H <- H[is.finite(Weight) & !is.na(Ticker) & !is.na(Exec_Date)]
  # 같은 (Exec_Date,Ticker) 중복행은 비중 합산
  W <- H[, .(w = sum(Weight)), by = .(Exec_Date, Ticker)]
  setorder(W, Exec_Date, Ticker)
  dts <- sort(unique(W$Exec_Date))
  if (length(dts) < 2) next
  prev <- NULL; out <- vector("list", length(dts))
  for (k in seq_along(dts)) {
    cur <- W[Exec_Date == dts[k], .(Ticker, w)]
    if (is.null(prev)) { to <- NA_real_ } else {
      mg <- merge(prev, cur, by = "Ticker", all = TRUE, suffixes = c(".p", ".c"))
      mg[is.na(w.p), w.p := 0]; mg[is.na(w.c), w.c := 0]
      to <- 0.5 * sum(abs(mg$w.c - mg$w.p))
    }
    out[[k]] <- data.table(Exec_Date = dts[k], turnover = to)
    prev <- cur
  }
  O <- rbindlist(out)
  O[, ym := format(Exec_Date, "%Y%m")]
  res[[j]] <- O[!is.na(turnover), .(module_id = sid, turnover = sum(turnover)), by = ym]
  if (j %% 40 == 0) cat(sprintf("  ... %d/%d\n", j, length(ids)))
}
TO <- rbindlist(res[!vapply(res, is.null, logical(1))])
cat(sprintf("\n결과: 모듈 %d개서 회전율 산출 (registry 결측 %d, HOLDINGS_LOG 결손/로드실패 %d, HOLDINGS_LOG 보유 %d)\n",
            uniqueN(TO$module_id), nmiss, nfail, nhold))
cat(sprintf("  행수=%d  ym 범위 %s..%s\n", nrow(TO), min(TO$ym), max(TO$ym)))
cat(sprintf("  turnover 분포: min=%.4f q25=%.4f median=%.4f q75=%.4f max=%.4f\n",
            min(TO$turnover), quantile(TO$turnover,.25), median(TO$turnover),
            quantile(TO$turnover,.75), max(TO$turnover)))
cat(sprintf("  ★ 0.5*sum|Δw| 정의이므로 이론 상한 1.0 초과 여부: n(>1.0)=%d\n", sum(TO$turnover > 1.0)))
# 월별 리밸런스 빈도 실측 (월 1회인지)
nper <- TO[, .N, by = module_id]
cat(sprintf("  모듈당 회전율 관측 개월수: median=%.0f min=%d max=%d\n",
            median(nper$N), min(nper$N), max(nper$N)))
saveRDS(TO, file.path(OUT, "turnover_monthly.rds"))
cat("\n[done] saved turnover_monthly.rds\n"); sink()
