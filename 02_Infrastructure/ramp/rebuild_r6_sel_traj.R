#==============================================================================
# rebuild_r6_sel_traj.R — R6 선별 궤적(_ramp_r6_sel_20260711.rds) 재생성 + 파리티 검증
#
# 2026-08-08 신설. 근거:
#   `.cache/_ramp_r6_sel_20260711.rds` 부재로 소비자 10곳(R7·R10~R15·ppure_paper_track·
#   d3_dossier)이 fail-closed 되어 **P-pure 연구 레인(FQ-024/025/026)이 4주간 닫혀 있었다**.
#   그런데 재생성 비용은 실측 **8.3초**였다 — 카드에 '비용 미상'으로 적혀 있었고
#   Boruta 스크립트라 비싸다고 가정한 것이 그 4주를 유지시켰다.
#
# ★왜 바이너리 사본이 아니라 이 스크립트가 정본인가:
#   `.gitignore:21` 이 `*.rds` 를 전부 제외하므로 74KB 사본을 outputs/ 에 둬도 **추적되지 않는다**.
#   반면 선별 궤적은 **결정적 함수**이므로(패널 + 상수 → 궤적) 레시피가 곧 산출물이고,
#   레시피는 리뷰 가능하며 파리티 관문 덕분에 **조용히 드리프트할 수 없다**.
#
# ★파리티 관문 (저장 전 필수):
#   07-11 요약(outputs/ramp/r6_portt_boruta_summary_20260711.json — **추적됨**)에 기록된
#   persistence 통계와 대조해 일치할 때만 저장한다. 같은 파일명에 다른 궤적을 놓으면
#   하류 R10~R15 가 조용히 갈리기 때문이다(값이 아니라 **정체**를 검사).
#   실측 일치: W36 n_anchor 37 · rank_ac 0.8590/0.0741 | W60 33 · 0.9181/0.0432 (소수 4자리)
#
# 사용:  Rscript -e "source('02_Infrastructure/ramp/rebuild_r6_sel_traj.R')"
#        RAMP_R6_SEL_FORCE=1 이면 기존 파일이 있어도 재생성(기본은 존재 시 중단)
#==============================================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(sandwich); library(lmtest); library(jsonlite)
})

rebuild_r6_sel_traj <- function(root = Sys.getenv("QM_ROOT", "."),
                                force = nzchar(Sys.getenv("RAMP_R6_SEL_FORCE", ""))) {
  op <- setwd(root); on.exit(setwd(op), add = TRUE)   # 함수 안이므로 on.exit 발화함 (r-portability ②)

  RUNTAG  <- "20260711"
  CACHE   <- file.path(".cache", sprintf("_ramp_r6_sel_%s.rds", RUNTAG))
  SUMMARY <- sprintf("outputs/ramp/r6_portt_boruta_summary_%s.json", RUNTAG)
  PANELF  <- "outputs/ramp/r6_factor_deployzone_active.parquet"
  ## 원본 run_ramp_r6_portt_boruta.R 의 상수. CADENCE 는 기록 앵커 수(37/33)로 역산 확정.
  WINDOWS <- c(36L, 60L); KPOOL <- c(10L, 20L); CADENCE <- 6L

  if (file.exists(CACHE) && !force)
    stop("[r6_sel] 이미 존재: ", CACHE, " — 덮어쓰려면 RAMP_R6_SEL_FORCE=1")
  for (f in c(SUMMARY, PANELF)) if (!file.exists(f)) stop("[r6_sel] 전제 부재: ", f)

  J <- fromJSON(SUMMARY, simplifyVector = FALSE)
  PANEL <- as.data.table(read_parquet(PANELF))
  stopifnot(all(c("signal_date", "factor_id", "active_bm") %in% names(PANEL)))
  sig_dates <- sort(unique(PANEL$signal_date)); n_sig <- length(sig_dates)

  ## ★vintage 관문 — 패널이 07-11 기록과 같은 판인지 먼저 확인.
  ##   (주의: 이름이 'backup' 인 pre202606ext 판은 256개월/2026-04 로 **다른 vintage** 다.
  ##    이름이 아니라 기록 통계로 대조할 것.)
  if (!identical(as.integer(n_sig), as.integer(J$n_sig)))
    stop(sprintf("[r6_sel] 패널 vintage 불일치: n_sig %d vs 기록 %d — 다른 판으로 재구성하면 하류가 갈린다",
                 n_sig, J$n_sig))

  Pw <- dcast(PANEL, signal_date ~ factor_id, value.var = "active_bm"); setorder(Pw, signal_date)
  PANEL_FACS <- setdiff(names(Pw), "signal_date")
  Pmat <- as.matrix(Pw[, ..PANEL_FACS]); rownames(Pmat) <- as.character(Pw$signal_date)

  ## ── run_ramp_r6_portt_boruta.R:198-221 축자 ──
  trailing_portt <- function(W, a_idx) {
    lo <- a_idx - W; hi <- a_idx - 1L
    if (lo < 1L) return(NULL)
    sub <- Pmat[lo:hi, , drop = FALSE]
    apply(sub, 2, function(x) {
      x <- x[is.finite(x)]; if (length(x) < 12) return(NA_real_)
      m <- lm(x ~ 1)
      as.numeric(coeftest(m, vcov = sandwich::NeweyWest(m, lag = 3, prewhite = FALSE))[1, 3])
    })
  }
  t0 <- proc.time()[["elapsed"]]
  sel_traj <- list()
  for (W in WINDOWS) {
    anchors <- seq(W + 1L, n_sig - 1L, by = CADENCE); tj <- list()
    for (a in anchors) {
      tv <- trailing_portt(W, a); if (is.null(tv)) next
      ord <- names(sort(tv[is.finite(tv)], decreasing = TRUE))
      tj[[as.character(a)]] <- list(anchor_idx = a, anchor_date = as.character(sig_dates[a]),
        trailing_t = tv, ranked = ord,
        pool = setNames(lapply(KPOOL, function(k) head(ord, k)), paste0("K", KPOOL)))
    }
    sel_traj[[as.character(W)]] <- list(anchors = anchors, traj = tj)
  }
  elapsed <- round(proc.time()[["elapsed"]] - t0, 1)

  ## ── 파리티 관문 ──
  report <- list(); ok_all <- TRUE
  for (W in WINDOWS) {
    k <- as.character(W); tr <- sel_traj[[k]]$traj; rec <- J$persistence[[k]]
    TT <- do.call(cbind, lapply(tr, function(x) x$trailing_t))
    ac <- vapply(2:ncol(TT), function(i) {
      a <- TT[, i - 1]; b <- TT[, i]; g <- is.finite(a) & is.finite(b)
      if (sum(g) < 3) NA_real_ else cor(rank(a[g]), rank(b[g])) }, numeric(1))
    ac <- ac[is.finite(ac)]
    okv <- c(anchor = length(tr) == rec$n_anchor,
             mean   = abs(mean(ac) - rec$rank_ac_mean) < 5e-3,
             sd     = abs(sd(ac)   - rec$rank_ac_sd)   < 5e-3)
    ok_all <- ok_all && all(okv)
    report[[k]] <- list(n_anchor = length(tr), rec_n_anchor = rec$n_anchor,
                        rank_ac_mean = round(mean(ac), 4), rec_mean = rec$rank_ac_mean,
                        rank_ac_sd = round(sd(ac), 4), rec_sd = rec$rank_ac_sd, ok = okv)
    message(sprintf("[r6_sel] W%-3d anchors %2d/%2d · rank_ac %.4f/%.4f · sd %.4f/%.4f · %s",
      W, length(tr), rec$n_anchor, mean(ac), rec$rank_ac_mean, sd(ac), rec$rank_ac_sd,
      if (all(okv)) "OK" else "**불일치**"))
  }
  if (!ok_all)
    stop("[r6_sel] ★파리티 실패 — 저장하지 않는다. 07-11 궤적과 다른 것을 같은 파일명에 놓으면 하류가 조용히 갈린다.")

  if (!dir.exists(".cache")) dir.create(".cache", recursive = TRUE)
  saveRDS(sel_traj, CACHE)
  message(sprintf("[r6_sel] 저장 %s (%.1f KB · 소요 %.1f초 · 파리티 통과)",
                  CACHE, file.size(CACHE) / 1024, elapsed))
  invisible(list(path = CACHE, elapsed_sec = elapsed, parity = report, parity_ok = ok_all))
}

## main-guard: source() 로 부르면 즉시 실행, 다른 스크립트가 함수만 쓰려면 RAMP_R6_SEL_NORUN=1
if (!nzchar(Sys.getenv("RAMP_R6_SEL_NORUN", ""))) {
  .r <- try(rebuild_r6_sel_traj(), silent = TRUE)
  if (inherits(.r, "try-error")) message("[r6_sel] ", conditionMessage(attr(.r, "condition")))
}
