# =============================================================================
# summarize_timing.R — 시험 실행 결과(run_equivalence.R run 의 .rds)로 달별 시간표와 322개월 × 2변형 투영을 낸다
# 사용: Rscript summarize_timing.R <out.json> old_sr=<a.rds,b.rds> old_vm=<…> new_sr=<…> new_vm=<…> sys=<YYYY-MM-DD,…> [lane_log=<path>] [W=6]
#   old_*  = 구판 순차 실행(달마다 주 프로세스 시간) · new_sr = 새 판 병렬(달마다 작업자 시간 · 캐시 없음)
#   new_vm = 새 판 vol_min(SSL 캐시 적중) · sys = 투영용 계통 표본(신호월 12개마다 1개) · lane_log = 레인 로그(구판 달별 시간 참고)
# 투영(가정): 새 판 sr_opt 합 = 322 × mean(계통 표본의 작업자 시간) · 구판 = 그 합 × median(같은 달 구판/새 판 비)
#   · vol_min: 구판 = 구판 sr_opt + 322 × mean(같은 달 구판 vol_min − 구판 sr_opt) · 새 판 = 322 × mean(계통 표본의 캐시 적중 시간)
#   · 새 판 벽시계 = (sr_opt 합 + vol_min 합) / W(작업자 · 부하 불균형 무시 — 아래 하한 · 상한 함께)
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
a <- commandArgs(TRUE)
out <- a[1]
kv <- function(k, d = "") { x <- sub(paste0("^", k, "="), "", grep(paste0("^", k, "="), a, value = TRUE)); if (length(x)) x[1] else d }
rd <- function(k) {
  fs <- strsplit(kv(k), ",", fixed = TRUE)[[1]]
  rbindlist(lapply(fs[nzchar(fs)], function(f) {
    R <- readRDS(f)
    rbindlist(lapply(R$months, function(m) data.table(date = as.Date(m$date), secs = m$secs, hit = isTRUE(m$hit), note = m$note)))
  }))
}
O <- rd("old_sr"); OV <- rd("old_vm"); N <- rd("new_sr"); NV <- rd("new_vm")
sys <- as.Date(strsplit(kv("sys"), ",", fixed = TRUE)[[1]])
W <- as.integer(kv("W", "6"))
pnum <- function(note, k) suppressWarnings(as.integer(sub(paste0(".*\\b", k, "=([0-9]+).*"), "\\1", note)))
P <- merge(O[, .(date, old_sr = secs, p = pnum(note, "p"))], OV[, .(date, old_vm = secs)], by = "date", all = TRUE)
P <- merge(P, N[, .(date, new_sr = secs)], by = "date", all.x = TRUE)
P <- merge(P, NV[, .(date, new_vm = secs, new_vm_hit = hit)], by = "date", all.x = TRUE)
P[, ratio_sr := old_sr / new_sr]
setorder(P, date)
S <- N[date %in% sys]; SV <- NV[date %in% sys]
n_all <- 322L
new_sr_tot <- n_all * mean(S$secs); new_vm_tot <- n_all * mean(SV$secs)
rat <- stats::median(P$ratio_sr, na.rm = TRUE)
old_sr_tot <- new_sr_tot * rat
old_vm_tot <- old_sr_tot + n_all * mean(P$old_vm - P$old_sr, na.rm = TRUE)
lane <- NULL
lp <- kv("lane_log")
if (nzchar(lp) && file.exists(lp)) {
  L <- grep("^\\[engine\\] [0-9]{4}-[0-9]{2}-[0-9]{2} p0=", readLines(lp, warn = FALSE), value = TRUE)
  lane <- data.table(date = as.Date(substr(L, 10, 19)), secs = as.numeric(sub(".*\\(([0-9]+)s\\)$", "\\1", L)))
}
res <- list(
  paired = P, systematic_months = length(sys), systematic_new_sr_mean_s = mean(S$secs), systematic_new_vm_mean_s = mean(SV$secs),
  ratio_old_over_new_sr = list(median = rat, min = min(P$ratio_sr, na.rm = TRUE), max = max(P$ratio_sr, na.rm = TRUE)),
  lane_old_sr_first_months = if (is.null(lane)) NULL else list(n = nrow(lane), mean_s = mean(lane$secs), sum_s = sum(lane$secs)),
  projection_322 = list(
    old_sequential = list(sr_opt_h = old_sr_tot / 3600, vol_min_h = old_vm_tot / 3600, total_h = (old_sr_tot + old_vm_tot) / 3600,
                          total_days = (old_sr_tot + old_vm_tot) / 86400),
    new = list(workers = W, sr_opt_cpu_h = new_sr_tot / 3600, vol_min_cpu_h = new_vm_tot / 3600,
               wall_h_ideal = (new_sr_tot + new_vm_tot) / W / 3600,
               wall_h_with_tail = ((new_sr_tot + new_vm_tot) / W + max(N$secs)) / 3600),
    speedup_ideal = (old_sr_tot + old_vm_tot) / ((new_sr_tot + new_vm_tot) / W)),
  made_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"))
print(P[, .(date, p, old_sr = round(old_sr), new_sr = round(new_sr), ratio_sr = round(ratio_sr, 2), old_vm = round(old_vm), new_vm = round(new_vm, 1))])
cat(sprintf("systematic(n=%d): new sr_opt mean %.1fs · new vol_min(cache) mean %.1fs · ratio old/new median %.2f (%.2f-%.2f)\n",
            length(sys), mean(S$secs), mean(SV$secs), rat, res$ratio_old_over_new_sr$min, res$ratio_old_over_new_sr$max))
cat(sprintf("projection 322 months: old sequential %.1f h (sr_opt %.1f + vol_min %.1f) = %.1f days · new W=%d wall %.1f h (ideal) .. %.1f h (+longest month) · speedup x%.0f\n",
            (old_sr_tot + old_vm_tot) / 3600, old_sr_tot / 3600, old_vm_tot / 3600, (old_sr_tot + old_vm_tot) / 86400, W,
            res$projection_322$new$wall_h_ideal, res$projection_322$new$wall_h_with_tail, res$projection_322$speedup_ideal))
if (!is.null(lane)) cat(sprintf("lane log (old engine, sr_opt): %d months mean %.0fs sum %.0fs\n", nrow(lane), mean(lane$secs), sum(lane$secs)))
writeLines(toJSON(res, auto_unbox = TRUE, pretty = TRUE, digits = 6, na = "null", null = "null", Date = "ISO8601"), out)
