#!/usr/bin/env Rscript
# =============================================================================
# p0_inventory.R — 폐지줍기 라운드 P0: 재고 실측 (착수 전 사전 확인)
#
# 목적: "C/F 등급 폐지 풀로 앙상블이 성립할 여지가 있는가"를 라운드 설계 전에 실측.
#   ★ 첫 출력은 입력 실측(행수·관측단위·범위) — 입력 형태 가정 금지 규약.
#   metric_type = diagnostic_precheck (졸업 주장 아님. 자본 판정 아님)
#
# 산출: stage_artifacts/scrap_ensemble_20260809/p0_inventory.json
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(jsonlite); library(xts); library(PerformanceAnalytics)
})
PROJ <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", ""))
if (!nzchar(PROJ)) PROJ <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(PROJ)
OUT <- file.path(PROJ, "stage_artifacts/scrap_ensemble_20260809")
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)

cat("=== [0] INPUT SHAPE ASSERTION ===\n")
MP <- fromJSON(file.path(PROJ, "06_Registry/module_performance.json"), simplifyVector = FALSE)
mods <- MP$modules
cat(sprintf("module_performance: n_modules=%d generated=%s metric_type=%s\n",
            length(mods), MP$generated, MP$metric_type))
grades <- vapply(mods, function(m) as.character(m$grade %||% NA), character(1))
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a
grades <- vapply(mods, function(m) if (is.null(m$grade)) NA_character_ else as.character(m$grade), character(1))
print(table(grades, useNA = "ifany"))

# ---- 폐지 풀 정의: grade C 또는 F ----
scrap_ids <- names(mods)[grades %in% c("C", "F")]
elite_ids <- names(mods)[grades %in% c("A", "B")]
cat(sprintf("\nSCRAP pool (C|F) = %d · ELITE pool (A|B) = %d\n", length(scrap_ids), length(elite_ids)))

# ---- NAV 로드 ----
load_daily <- function(sid) {
  p <- file.path(PROJ, mods[[sid]]$sim_result_path)
  if (!file.exists(p)) return(NULL)
  s <- tryCatch(readRDS(p), error = function(e) NULL)
  if (is.null(s) || is.null(s$DAILY_NAV_DT)) return(NULL)
  d <- as.data.table(s$DAILY_NAV_DT)
  if (!all(c("Date", "Strategy_Ret") %in% names(d))) return(NULL)
  list(ret = d[, .(Date = as.Date(Date), r = as.numeric(Strategy_Ret))],
       bm  = if (!is.null(s$bm_xts)) data.table(Date = as.Date(index(s$bm_xts)),
                                                bm = as.numeric(s$bm_xts[, 1])) else NULL)
}

cat("\n=== [1] LOADING NAVs ===\n")
t0 <- Sys.time()
loaded <- list(); bmref <- NULL; bmref_n <- 0L; bmref_src <- NA_character_
fail <- character(0)
all_ids <- c(scrap_ids, elite_ids)
for (sid in all_ids) {
  x <- load_daily(sid)
  if (is.null(x)) { fail <- c(fail, sid); next }
  loaded[[sid]] <- x$ret
  if (!is.null(x$bm) && nrow(x$bm) > bmref_n) { bmref <- x$bm; bmref_n <- nrow(x$bm); bmref_src <- sid }
}
cat(sprintf("loaded=%d  failed=%d  elapsed=%.1fs\n", length(loaded), length(fail),
            as.numeric(difftime(Sys.time(), t0, units = "secs"))))
if (length(fail)) cat("  fail sample:", paste(head(fail, 5), collapse = ", "), "\n")
cat(sprintf("bm reference: src=%s n=%d span %s..%s\n", bmref_src, bmref_n,
            as.character(min(bmref$Date)), as.character(max(bmref$Date))))

scrap_ok <- intersect(scrap_ids, names(loaded))
elite_ok <- intersect(elite_ids, names(loaded))
cat(sprintf("SCRAP loadable=%d  ELITE loadable=%d\n", length(scrap_ok), length(elite_ok)))

# ---- 관측 단위 실측 (일간인지 확인 — 가정 금지) ----
smp <- loaded[[scrap_ok[1]]]
gaps <- as.numeric(diff(sort(unique(smp$Date))))
cat(sprintf("\n[obs unit] sample module %s: n_rows=%d span %s..%s median_gap=%.1f days (mode gap=%s)\n",
            scrap_ok[1], nrow(smp), as.character(min(smp$Date)), as.character(max(smp$Date)),
            median(gaps), names(sort(table(gaps), decreasing = TRUE))[1]))

# ---- 월간 패널 구축 (일간 -> 월간, 계약 표준 apply.monthly) ----
cat("\n=== [2] MONTHLY PANEL ===\n")
to_monthly <- function(dt) {
  x <- xts(dt$r, order.by = dt$Date)
  m <- apply.monthly(x, Return.cumulative)
  data.table(ym = format(index(m), "%Y%m"), r = as.numeric(m))
}
ML <- lapply(loaded, to_monthly)
PAN <- Reduce(function(a, b) merge(a, b, by = "ym", all = TRUE),
              lapply(names(ML), function(s) { z <- copy(ML[[s]]); setnames(z, "r", s); z }))
setorder(PAN, ym)
bm_m <- to_monthly(setnames(copy(bmref), "bm", "r"))
setnames(bm_m, "r", "bm")
PAN <- merge(PAN, bm_m, by = "ym", all.x = TRUE)
setorder(PAN, ym)
cat(sprintf("panel: %d months (%s..%s) x %d modules\n", nrow(PAN), min(PAN$ym), max(PAN$ym), length(ML)))

breadth_s <- PAN[, .(n = rowSums(!is.na(.SD))), by = ym, .SDcols = scrap_ok]
breadth_e <- PAN[, .(n = rowSums(!is.na(.SD))), by = ym, .SDcols = elite_ok]
setorder(breadth_s, ym)
cat("SCRAP breadth by decade:\n")
print(breadth_s[, .(min = min(n), median = as.numeric(median(n)), max = max(n)), by = .(dec = substr(ym, 1, 3))])
first10 <- breadth_s[n >= 10, min(ym)]; first30 <- breadth_s[n >= 30, min(ym)]; first60 <- breadth_s[n >= 60, min(ym)]
cat(sprintf("first month with SCRAP breadth >=10: %s  >=30: %s  >=60: %s\n", first10, first30, first60))

# ---- [3] 폐지 풀 naive EW baseline (계약 함수만) ----
cat("\n=== [3] NAIVE EW BASELINE (metric_type=diagnostic_precheck) ===\n")
ew_stats <- function(ids, from_ym, label) {
  sub <- PAN[ym >= from_ym]
  M <- as.matrix(sub[, ..ids])
  # 각 월 가용 모듈 EW (NA 제외) — 손Σ 아님: 동일가중 평균은 Return.portfolio 로 재구성
  keep <- rowSums(!is.na(M)) >= 3
  sub <- sub[keep]; M <- M[keep, , drop = FALSE]
  W <- !is.na(M); W <- W / rowSums(W); M[is.na(M)] <- 0
  Rx <- xts(M, order.by = as.Date(paste0(sub$ym, "01"), "%Y%m%d"))
  Wx <- xts(W, order.by = index(Rx))
  pr <- Return.portfolio(Rx, weights = Wx, rebalance_on = NA)
  bmx <- xts(sub$bm, order.by = index(Rx))
  ok <- is.finite(as.numeric(pr)) & is.finite(as.numeric(bmx))
  pr <- pr[ok]; bmx <- bmx[ok]
  act <- pr - bmx
  ar <- table.AnnualizedReturns(pr, scale = 12)
  mdd <- as.numeric(maxDrawdown(pr))
  cagr <- as.numeric(ar[1, 1]); shp <- as.numeric(ar[3, 1])
  calmar <- if (mdd > 0) cagr / mdd else NA_real_
  # active t (NW lag-3 는 forge 소관 — 여기선 plain t, 라벨 명시)
  tt <- as.numeric(t.test(as.numeric(act))$statistic)
  cat(sprintf("%-22s n_m=%3d  CAGR=%6.2f%%  SR=%5.3f  MDD=%5.1f%%  Calmar=%5.3f  active_t(plain)=%6.3f\n",
              label, length(pr), 100 * cagr, shp, 100 * mdd, calmar, tt))
  list(label = label, n_months = length(pr), cagr = cagr, sharpe = shp, mdd = mdd,
       calmar = calmar, active_t_plain = tt, from_ym = from_ym)
}
start_ym <- first30
res <- list()
res$scrap_ew <- ew_stats(scrap_ok, start_ym, "SCRAP(C|F) EW")
res$elite_ew <- ew_stats(elite_ok, start_ym, "ELITE(A|B) EW [대조]")
res$all_ew   <- ew_stats(c(scrap_ok, elite_ok), start_ym, "ALL EW [대조]")
# 벤치
{
  sub <- PAN[ym >= start_ym & is.finite(bm)]
  bx <- xts(sub$bm, order.by = as.Date(paste0(sub$ym, "01"), "%Y%m%d"))
  ar <- table.AnnualizedReturns(bx, scale = 12); mdd <- as.numeric(maxDrawdown(bx))
  cat(sprintf("%-22s n_m=%3d  CAGR=%6.2f%%  SR=%5.3f  MDD=%5.1f%%  Calmar=%5.3f\n",
              "BENCHMARK", nrow(sub), 100 * ar[1, 1], ar[3, 1], 100 * mdd, ar[1, 1] / mdd))
  res$bm <- list(cagr = as.numeric(ar[1, 1]), sharpe = as.numeric(ar[3, 1]), mdd = mdd)
}

# ---- [4] 중복도: 폐지 풀 내부 상관 (gross vs active) ----
cat("\n=== [4] REDUNDANCY (gross vs active corr) ===\n")
sub <- PAN[ym >= start_ym]
Ms <- as.matrix(sub[, ..scrap_ok])
cg <- cor(Ms, use = "pairwise.complete.obs")
Ma <- Ms - matrix(sub$bm, nrow = nrow(Ms), ncol = ncol(Ms))
ca <- cor(Ma, use = "pairwise.complete.obs")
ut <- function(m) m[upper.tri(m)]
cat(sprintf("SCRAP gross  corr: median=%.3f  q25=%.3f q75=%.3f  frac>0.8=%.3f\n",
            median(ut(cg), na.rm = TRUE), quantile(ut(cg), .25, na.rm = TRUE),
            quantile(ut(cg), .75, na.rm = TRUE), mean(ut(cg) > 0.8, na.rm = TRUE)))
cat(sprintf("SCRAP active corr: median=%.3f  q25=%.3f q75=%.3f  frac>0.8=%.3f\n",
            median(ut(ca), na.rm = TRUE), quantile(ut(ca), .25, na.rm = TRUE),
            quantile(ut(ca), .75, na.rm = TRUE), mean(ut(ca) > 0.8, na.rm = TRUE)))
ev <- eigen(cor(Ma[complete.cases(Ma), , drop = FALSE]))$values
cat(sprintf("SCRAP active PC1 share=%.3f  PC1-3 share=%.3f  eff-N(participation)=%.1f\n",
            ev[1] / sum(ev), sum(ev[1:3]) / sum(ev), sum(ev)^2 / sum(ev^2)))

# ---- [5] MDD 축: 폐지 모듈의 하락월 방어 산포 (사용자 지적 축) ----
cat("\n=== [5] MDD LEVER HEADROOM — 하락월 조건부 산포 ===\n")
bmv <- sub$bm
tail_idx <- which(is.finite(bmv) & bmv <= -0.10)
mild_idx <- which(is.finite(bmv) & bmv < 0 & bmv > -0.10)
up_idx   <- which(is.finite(bmv) & bmv >= 0)
cat(sprintf("months: tail(bm<=-10%%)=%d  mild(-10%%<bm<0)=%d  up=%d  total=%d\n",
            length(tail_idx), length(mild_idx), length(up_idx), length(bmv)))
defen <- function(idx, lab) {
  if (length(idx) < 3) { cat(sprintf("  %s: n<3 skip\n", lab)); return(NULL) }
  d <- colMeans(Ma[idx, , drop = FALSE], na.rm = TRUE)  # active in those months
  d <- d[is.finite(d)]
  cat(sprintf("  %-26s n_m=%3d  active mean across modules=%+.3f%%  sd=%.3f%%  best=%+.3f%% worst=%+.3f%%  frac>0=%.3f\n",
              lab, length(idx), 100 * mean(d), 100 * sd(d), 100 * max(d), 100 * min(d), mean(d > 0)))
  as.list(c(n_months = length(idx), mean = mean(d), sd = sd(d), best = max(d), frac_pos = mean(d > 0)))
}
res$tail <- defen(tail_idx, "TAIL (bm<=-10%)")
res$mild <- defen(mild_idx, "MILD (-10%<bm<0)")
res$up   <- defen(up_idx,   "UP   (bm>=0)")

# ---- [6] 오라클 상한 (ex-post 최선 모듈 = 착수 가치의 천장) ----
cat("\n=== [6] ORACLE CEILING (ex-post, 착수 가치 상한 — PIT 아님·라벨 명시) ===\n")
orc <- function(k, lab) {
  M <- Ms
  n <- nrow(M)
  pick <- matrix(0, n, ncol(M))
  for (i in seq_len(n)) {
    v <- M[i, ]; ok <- which(is.finite(v))
    if (length(ok) < k) next
    top <- ok[order(v[ok], decreasing = TRUE)[1:k]]
    pick[i, top] <- 1 / k
  }
  keep <- rowSums(pick) > 0
  Mz <- M; Mz[!is.finite(Mz)] <- 0
  Rx <- xts(Mz[keep, , drop = FALSE], order.by = as.Date(paste0(sub$ym[keep], "01"), "%Y%m%d"))
  Wx <- xts(pick[keep, , drop = FALSE], order.by = index(Rx))
  pr <- Return.portfolio(Rx, weights = Wx, rebalance_on = NA)
  ar <- table.AnnualizedReturns(pr, scale = 12); mdd <- as.numeric(maxDrawdown(pr))
  cat(sprintf("  %-26s CAGR=%6.2f%%  SR=%5.3f  MDD=%5.1f%%  Calmar=%5.3f\n",
              lab, 100 * ar[1, 1], ar[3, 1], 100 * mdd, ar[1, 1] / mdd))
  list(cagr = as.numeric(ar[1, 1]), sharpe = as.numeric(ar[3, 1]), mdd = mdd,
       calmar = as.numeric(ar[1, 1]) / mdd)
}
res$oracle_k10 <- orc(10, "ORACLE top-10 of SCRAP")
res$oracle_k25 <- orc(25, "ORACLE top-25 of SCRAP")

res$meta <- list(
  metric_type = "diagnostic_precheck",
  note = "P0 사전 확인. 졸업 판정 아님. active t 는 plain(NW 미적용) — 권위 t 는 forge NW lag-3.",
  n_scrap_loaded = length(scrap_ok), n_elite_loaded = length(elite_ok),
  n_failed = length(fail), panel_months = nrow(PAN),
  start_ym = start_ym, bm_src = bmref_src,
  grade_table = as.list(table(grades))
)
write_json(res, file.path(OUT, "p0_inventory.json"), auto_unbox = TRUE, digits = NA, pretty = TRUE)
saveRDS(list(PAN = PAN, scrap_ok = scrap_ok, elite_ok = elite_ok, start_ym = start_ym),
        file.path(OUT, "p0_panel.rds"))
cat(sprintf("\n[done] -> %s\n", file.path(OUT, "p0_inventory.json")))
