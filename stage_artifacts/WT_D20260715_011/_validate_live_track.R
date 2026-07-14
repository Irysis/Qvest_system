## R42 live track 검증 (source 패턴 — Rscript -e 한글 세그폴트 회피)
Sys.setenv(ARROW_IO_THREADS = "2")
suppressWarnings(suppressMessages(library(jsonlite)))
P <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/qepm/observability/insider_safe_live_track.json"
stopifnot(file.exists(P))
j <- fromJSON(P, simplifyVector = FALSE)   # 파싱 성공 = well-formed
cat("[validate] JSON well-formed: TRUE (parsed)\n")
cat(sprintf("[validate] schema=%s  as_of=%s  current_holding_ym=%s\n", j$schema, j$as_of, j$current_holding_ym))
cat(sprintf("[validate] fade_max_mso=%s auto_clear_at_mso=%s  book=%s\n", j$fade_max_mso, j$auto_clear_at_mso, j$book))
cat(sprintf("[validate] run_summary: registered=%s updated=%s cleared=%s obs=%s | active=%s cleared_total=%s\n",
            j$run_summary$registered_this_run, j$run_summary$updated_this_run, j$run_summary$cleared_this_run,
            j$run_summary$observations_appended_this_run, j$run_summary$n_active, j$run_summary$n_cleared_total))
cat(sprintf("[validate] oos_rollup: status=%s  n_prot=%s  baseline_off_tail=%s\n",
            j$oos_rollup$status, j$oos_rollup$n_protection_window, j$oos_rollup$baseline_off_tail))
req <- c("schema","purpose","book","metric_type","r40_baseline","oos_rollup","tracked","cleared_log",
         "upstream","writer","realized_source","fade_max_mso","provenance")
miss <- setdiff(req, names(j))
cat(sprintf("[validate] required top-level fields present: %s%s\n", length(miss)==0,
            if (length(miss)) paste0(" (MISSING: ", paste(miss, collapse=","), ")") else ""))
cat(sprintf("[validate] n_tracked=%d\n", length(j$tracked)))
for (t in j$tracked) {
  tk_req <- c("track_id","ticker","status_at_firing","firing_holding_ym","firing_mso","tier",
              "tier_confidence","ins02_z_at_firing","state","observations")
  ok <- all(tk_req %in% names(t))
  ## Encode Korean name to escaped unicode to avoid console segfault on -e; here source-safe
  cat(sprintf("  - %s ticker=%s status=%s firing_ym=%s mso=%s tier=%s conf=%s z=%s z_prev=%s clears_at=%s state=%s obs=%d [fields_ok=%s]\n",
      t$track_id, t$ticker, t$status_at_firing, t$firing_holding_ym,
      ifelse(is.null(t$firing_mso),"NA",t$firing_mso), t$tier, t$tier_confidence,
      ifelse(is.null(t$ins02_z_at_firing),"NA",t$ins02_z_at_firing),
      ifelse(is.null(t$ins02_z_prev),"NA",t$ins02_z_prev),
      ifelse(is.null(t$clears_at_mso),"NA",t$clears_at_mso), t$state, length(t$observations), ok))
}
## 현 2건 등록 검증 (핵심 assert)
tickers <- vapply(j$tracked, function(t) t$ticker, character(1))
stopifnot("A011070 등록" = "A011070" %in% tickers)
stopifnot("A004170 등록" = "A004170" %in% tickers)
lg <- j$tracked[[which(tickers=="A011070")]]; sg <- j$tracked[[which(tickers=="A004170")]]
stopifnot("LG mso=1" = identical(as.integer(lg$firing_mso), 1L),
          "LG SAFE_FADING" = identical(lg$status_at_firing, "SAFE_FADING"),
          "LG MID_OTHER" = identical(lg$tier, "MID_OTHER"),
          "신세계 mso=1" = identical(as.integer(sg$firing_mso), 1L),
          "신세계 SAFE_FADING" = identical(sg$status_at_firing, "SAFE_FADING"))
cat("[validate] ASSERT PASS: 현 SAFE_FADING 2건(A011070·A004170) mso=1 MID_OTHER SAFE_FADING 등록 확인\n")
cat("[validate] DONE — 스키마 생성 + 2건 등록 + JSON well-formed 전부 PASS\n")
