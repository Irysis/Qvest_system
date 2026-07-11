# run_timing_luck.R — SPEC-2 리밸 timing-luck 측정 (진단-only, 자본/BOOK 무변경)
# 사전조건: build_spec.R로 spec.json + .sha256 동결 완료. 본 스크립트는 해시 일치 검증 후에만 측정.
# 규율: 실측-only · pin_cache 소비 · 단일스레드 · 포트 수익 구성은 Return.portfolio()만(손계산 금지).
Sys.setenv(OMP_NUM_THREADS = "1", OPENBLAS_NUM_THREADS = "1", ARROW_NUM_THREADS = "1")
suppressMessages({
  library(data.table); library(arrow); library(jsonlite); library(digest)
  library(xts); library(zoo); library(PerformanceAnalytics)
})
setDTthreads(1)

root <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(root)
outdir <- file.path(root, "stage_artifacts/spec2_timing_luck")

# ── 0) 사전등록 스펙 해시 검증 (동결 위반 시 즉시 중단) ────────────────────────
spec_path <- file.path(outdir, "spec.json")
sha_expect <- readLines(file.path(outdir, "spec.json.sha256"), warn = FALSE)[1]
sha_now <- digest(file = spec_path, algo = "sha256")
stopifnot("[SPEC2] spec.json 해시 불일치 — 사전등록 동결 위반" = identical(sha_now, sha_expect))
spec <- fromJSON(spec_path, simplifyVector = TRUE)
cat(sprintf("[SPEC2] spec 해시 검증 OK: %s\n", sha_now))

source(file.path(root, "02_Infrastructure/data/pin_cache.R"))

# ── 1) pinned 입력 로드 ───────────────────────────────────────────────────────
carrier_path <- read_pinned(spec$inputs$carrier$file, spec$inputs$carrier$pin_tag)
car <- as.data.table(read_parquet(carrier_path))
stopifnot(uniqueN(car$decision_date) == spec$inputs$carrier$n_months_expect)

raw_path <- read_pinned(spec$inputs$rawdata$file, spec$inputs$rawdata$pin_tag)
cat("[SPEC2] RAWDATA(pinned) 로드 중 (Date/Ticker/Ret)...\n")
DT <- as.data.table(read_parquet(raw_path, col_select = c("Date", "Ticker", "Ret")))
calendar <- sort(unique(DT$Date))          # 거래일 캘린더 (전 종목 distinct Date)
cat(sprintf("[SPEC2] raw rows=%s | calendar %s~%s (%d일)\n",
            format(nrow(DT), big.mark = ","), as.character(min(calendar)),
            as.character(max(calendar)), length(calendar)))

tks <- sort(unique(car$Ticker))
DT <- DT[Ticker %chin% tks & Date >= as.Date("2003-12-01")]
stopifnot("[SPEC2] carrier 티커가 RAWDATA에 부재" = all(tks %in% unique(DT$Ticker)))
dup_n <- nrow(DT) - uniqueN(DT, by = c("Date", "Ticker"))
stopifnot("[SPEC2] RAWDATA (Date,Ticker) 중복 감지" = dup_n == 0L)
invisible(gc(verbose = FALSE))

# ── 2) anchor / exec 매핑 + 무결 구간 판정 + PIT 가드 ────────────────────────
mm <- sort(unique(car$decision_date)); nM <- length(mm)
anchor_idx_all <- vapply(mm, function(d) which(calendar >= d)[1], integer(1))
stopifnot(!anyNA(anchor_idx_all))
anchor_date_all <- calendar[anchor_idx_all]
offsets <- as.integer(spec$design$offsets_bdays)

# 데이터 공백 감지: 인접 anchor 간 거래일 < max(offset)+1 또는 캘린더일 > 45 → 그 월 홀딩창 오염.
# (실측: 현행+pinned RAWDATA에 2026-03-30~04-29 공백 — 4월 거래일이 04-30 단 하루.
#  연속 NAV는 공백을 건너뛸 수 없으므로 첫 오염 월 직전까지 절단. 판정 규칙 자체는 불변.)
tdays_between <- diff(anchor_idx_all)
cdays_between <- as.numeric(diff(anchor_date_all))
interval_bad <- (tdays_between < max(offsets) + 1L) | (cdays_between > 45)
if (any(interval_bad)) {
  first_bad <- min(which(interval_bad))
  nM_use <- first_bad - 1L
  terminal_idx <- anchor_idx_all[first_bad]   # 마지막 사용 월 홀딩창 종점 = 첫 오염 월 anchor
  deviation_note <- sprintf(
    "RAWDATA 공백으로 측정창 절단: 사용 리밸 %d/%d (decisions %s~%s), NAV 종점 %s. 오염 구간 예: %s→%s 거래일 %d/캘린더일 %.0f",
    nM_use, nM, as.character(mm[1]), as.character(mm[nM_use]), as.character(calendar[terminal_idx]),
    as.character(anchor_date_all[first_bad]), as.character(anchor_date_all[min(first_bad + 1L, nM)]),
    tdays_between[first_bad], cdays_between[first_bad])
  cat(sprintf("[SPEC2][DEVIATION] %s\n", deviation_note))
} else {
  nM_use <- nM
  terminal_idx <- which(calendar >= max(car$eval_date))[1]
  deviation_note <- "없음 — 전 269월 사용"
}
stopifnot(nM_use >= 200L)   # 절단이 과도하면 중단 (표본 보호)
mm <- mm[seq_len(nM_use)]
anchor_idx <- anchor_idx_all[seq_len(nM_use)]
anchor_date <- calendar[anchor_idx]
terminal_date <- calendar[terminal_idx]
stopifnot(max(anchor_idx) + max(offsets) + 1L <= length(calendar))  # 마지막 월 exec+cost일 존재
car <- car[decision_date %in% mm]

exec_mat <- sapply(offsets, function(k) calendar[anchor_idx + k])   # nM_use x 6 (numeric days)
exec_dates <- lapply(seq_along(offsets), function(j) as.Date(exec_mat[, j], origin = "1970-01-01"))
names(exec_dates) <- paste0("k", offsets)
nM <- nM_use

# PIT 가드 (사전등록): 집행일 >= anchor, 집행일 < 다음 월 anchor
next_anchor <- c(anchor_date[-1], terminal_date)
for (j in seq_along(offsets)) {
  exec_date <- exec_dates[[j]]
  stopifnot(all(exec_date >= anchor_date))
  stopifnot(all(exec_date < next_anchor))
}
cat("[SPEC2] PIT 가드 통과: exec >= anchor AND exec < next anchor (전 offset)\n")

# ── 3) 일별 수익 패널 (xts) + 목표비중 행렬 ──────────────────────────────────
wide <- dcast(DT, Date ~ Ticker, value.var = "Ret")
setnafill(wide, fill = 0, cols = setdiff(names(wide), "Date"))
panel <- xts(as.matrix(wide[, -1L]), order.by = wide$Date)
rm(DT, wide); invisible(gc(verbose = FALSE))
tks <- colnames(panel)

Wmat <- matrix(0, nrow = nM, ncol = length(tks), dimnames = list(NULL, tks))
car_split <- split(car[, .(Ticker, weight_strategy)], car$decision_date)
for (m in seq_len(nM)) {
  cm <- car_split[[as.character(mm[m])]]
  Wmat[m, cm$Ticker] <- cm$weight_strategy
}
stopifnot(max(abs(rowSums(Wmat) - 1)) < 1e-8)

# target-delta 회전 (offset 무관 동일 — 구성상 불변): traded(m) = sum|w_m - w_{m-1}| (첫월 buy-in=1)
traded_target <- c(sum(abs(Wmat[1, ])),
                   vapply(2:nM, function(m) sum(abs(Wmat[m, ] - Wmat[m - 1, ])), numeric(1)))
cost_bps <- 15
cost_m <- traded_target * cost_bps / 1e4
cat(sprintf("[SPEC2] target-delta 회전: 연환산 평균 %.2f%%/mo x12 = %.1f%%/yr | 총비용 drag %.3f%%/yr\n",
            mean(traded_target) * 100, mean(traded_target) * 12 * 100, mean(cost_m) * 12 * 100))

# ── 4) offset별 NAV (Return.portfolio — 유일한 포트 수익 구성 경로) ──────────
run_offset <- function(w_dates, tag, cost_per_month = cost_m, cost_charge_lag = 1L,
                       Wm = Wmat, split_cost_dates = NULL) {
  W_xts <- xts(Wm, order.by = w_dates)
  res <- Return.portfolio(panel, weights = W_xts, geometric = TRUE, verbose = TRUE)
  ret_gross <- res$returns
  # 비용 차감: 각 리밸의 target-delta 비용을 exec 직후 첫 수익일에 차감 (사전등록 규약)
  ret_net <- ret_gross
  if (is.null(split_cost_dates)) {
    pos_idx <- vapply(as.numeric(w_dates), function(d) which(as.numeric(index(ret_net)) > d)[1], integer(1))
    stopifnot(!anyNA(pos_idx))
    for (m in seq_along(pos_idx)) ret_net[pos_idx[m]] <- ret_net[pos_idx[m]] - cost_per_month[m]
  } else {
    # tranche: 비용을 두 leg에 50/50 분할 (총액 동일)
    for (leg in split_cost_dates) {
      pos_idx <- vapply(as.numeric(leg$dates), function(d) which(as.numeric(index(ret_net)) > d)[1], integer(1))
      stopifnot(!anyNA(pos_idx))
      for (m in seq_along(pos_idx)) ret_net[pos_idx[m]] <- ret_net[pos_idx[m]] - leg$cost[m]
    }
  }
  # drift-기반 실현 회전 (진단): sum|w_target(m) - EOP@exec(m)|, 첫월=buy-in 1
  eop <- res$EOP.Weight
  traded_real <- rep(NA_real_, nrow(Wm)); traded_real[1] <- sum(abs(Wm[1, ]))
  if (nrow(Wm) >= 2) {
    for (m in 2:nrow(Wm)) {
      r_i <- match(w_dates[m], index(eop))
      if (!is.na(r_i)) {
        eop_row <- as.numeric(eop[r_i, ]); eop_row[is.na(eop_row)] <- 0
        traded_real[m] <- sum(abs(Wm[m, ] - eop_row[match(colnames(Wm), colnames(eop))]))
      }
    }
  }
  cat(sprintf("[SPEC2] %s: NAV %d일 (%s~%s) | 실현회전(drift) 연 %.1f%%\n", tag, nrow(ret_net),
              as.character(index(ret_net)[1]), as.character(index(ret_net)[nrow(ret_net)]),
              mean(traded_real, na.rm = TRUE) * 12 * 100))
  list(tag = tag, gross = ret_gross, net = ret_net, traded_real = traded_real)
}

runs <- list()
for (j in seq_along(offsets)) {
  runs[[paste0("k", offsets[j])]] <- run_offset(exec_dates[[j]], paste0("k", offsets[j]))
}

# ── 5) 하니스 자기검증: k=0 gross vs pinned carrier recon parity ─────────────
recon <- car[, .(ret_recon = sum(weight_strategy * ret_fwd)), by = decision_date][order(decision_date)]
g0 <- runs$k0$gross
eval_end <- car[, .(eval_date = eval_date[1]), by = decision_date][order(decision_date)]$eval_date
par_daily <- vapply(seq_len(nM), function(m) {
  w <- g0[index(g0) > anchor_date[m] & index(g0) <= eval_end[m]]
  if (nrow(w) == 0) return(NA_real_)
  as.numeric(Return.cumulative(w))
}, numeric(1))
ok <- !is.na(par_daily)
parity_cor <- cor(par_daily[ok], recon$ret_recon[ok])
parity_maxdiff <- max(abs(par_daily[ok] - recon$ret_recon[ok]))
cat(sprintf("[SPEC2] parity(k=0 vs carrier recon): n=%d cor=%.6f max|diff|=%.2e\n",
            sum(ok), parity_cor, parity_maxdiff))

# ── 6) 공통창 지표 (사전등록 컨벤션) ─────────────────────────────────────────
common_idx <- Reduce(intersect, lapply(runs, function(r) as.numeric(index(r$net))))
common_dates <- as.Date(common_idx, origin = "1970-01-01")
common_dates <- common_dates[common_dates <= terminal_date]   # 절단 종점 이후(공백 포함) 제외
metrics_one <- function(r_net) {
  x <- r_net[index(r_net) %in% common_dates]
  mo <- apply.monthly(x, Return.cumulative)
  sr <- mean(mo) / sd(mo) * sqrt(12)                       # 판정용 SR (프로젝트 컨벤션)
  tab <- table.AnnualizedReturns(mo, scale = 12, Rf = 0)
  cagr <- as.numeric(tab["Annualized Return", 1])
  sr_geo <- as.numeric(tab["Annualized Sharpe (Rf=0%)", 1])
  mdd <- as.numeric(maxDrawdown(x))
  list(n_days = nrow(x), n_months = nrow(mo), SR = sr, SR_crosscheck_geo = sr_geo,
       CAGR = cagr, MDD = mdd)
}
tbl <- rbindlist(lapply(names(runs), function(nm) {
  m <- metrics_one(runs[[nm]]$net)
  data.table(offset = nm, n_months = m$n_months, SR = m$SR, SR_geo = m$SR_crosscheck_geo,
             CAGR = m$CAGR, MDD = m$MDD,
             turnover_target_yr = mean(traded_target) * 12,
             turnover_realized_yr = mean(runs[[nm]]$traded_real, na.rm = TRUE) * 12,
             cost_drag_yr = mean(cost_m) * 12)
}))
range_SR <- max(tbl$SR) - min(tbl$SR)
thr <- as.numeric(spec$verdict_rule$threshold)
verdict <- if (range_SR < thr) "SETTLED_NULL" else "RANGE_EXCEEDED_TRANCHE_COMPUTED"
cat(sprintf("\n[SPEC2] range_SR = %.4f (threshold %.2f) → %s\n", range_SR, thr, verdict))
print(tbl)

# ── 7) 조건부 tranche (range >= threshold일 때만 — 사전등록 규약) ─────────────
tranche_row <- NULL
if (range_SR >= thr) {
  cat("[SPEC2] tranche(반월 2분할) 추가 산출...\n")
  half_k <- 10L
  t2_idx <- pmin(anchor_idx + half_k, anchor_idx[c(2:nM, NA)] - 1L, na.rm = TRUE)
  t2_idx[nM] <- anchor_idx[nM] + half_k
  t2_dates <- calendar[t2_idx]
  # leg1 (anchor+0): 0.5*w_prev_target + 0.5*w_new_target / leg2 (anchor+10): w_new_target
  W_prev <- rbind(rep(0, ncol(Wmat)), Wmat[-nM, , drop = FALSE])
  W_leg1 <- 0.5 * W_prev + 0.5 * Wmat
  all_dates <- c(anchor_date, as.Date(t2_dates, origin = "1970-01-01"))
  all_W <- rbind(W_leg1, Wmat)
  o <- order(all_dates)
  W_tr <- xts(all_W[o, , drop = FALSE], order.by = all_dates[o])
  res_tr <- Return.portfolio(panel, weights = W_tr, geometric = TRUE, verbose = FALSE)
  ret_tr <- res_tr
  for (leg in list(list(dates = anchor_date, cost = cost_m / 2),
                   list(dates = as.Date(t2_dates, origin = "1970-01-01"), cost = cost_m / 2))) {
    pos_idx <- vapply(as.numeric(leg$dates), function(d) which(as.numeric(index(ret_tr)) > d)[1], integer(1))
    stopifnot(!anyNA(pos_idx))
    for (m in seq_along(pos_idx)) ret_tr[pos_idx[m]] <- ret_tr[pos_idx[m]] - leg$cost[m]
  }
  mt <- metrics_one(ret_tr)
  tranche_row <- data.table(offset = "tranche_halfmonth", n_months = mt$n_months, SR = mt$SR,
                            SR_geo = mt$SR_crosscheck_geo, CAGR = mt$CAGR, MDD = mt$MDD,
                            turnover_target_yr = mean(traded_target) * 12,
                            turnover_realized_yr = NA_real_, cost_drag_yr = mean(cost_m) * 12)
  tbl <- rbind(tbl, tranche_row)
  print(tranche_row)
}

# ── 8) 산출물 저장 ───────────────────────────────────────────────────────────
fwrite(tbl, file.path(outdir, "nav_table.csv"))
mo_list <- lapply(names(runs), function(nm) {
  x <- runs[[nm]]$net[index(runs[[nm]]$net) %in% common_dates]
  mo <- apply.monthly(x, Return.cumulative)
  data.table(month_end = index(mo), offset = nm, ret_net = as.numeric(mo))
})
fwrite(rbindlist(mo_list), file.path(outdir, "nav_monthly.csv"))

verdict_obj <- list(
  spec_id = spec$spec_id, spec_sha256 = sha_now,
  measured_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
  pin_tags = list(carrier = spec$inputs$carrier$pin_tag, rawdata = spec$inputs$rawdata$pin_tag),
  measurement_window_deviation = list(
    n_rebalances_used = nM, n_rebalances_carrier = 269L,
    terminal_date = as.character(terminal_date), note = deviation_note,
    reason = "RAWDATA 2026-03-30~04-29 데이터 공백(4월 거래일 04-30 단 하루) — 연속 NAV가 공백을 건널 수 없어 절단. 판정 규칙(사전등록)은 불변"),
  common_window = list(from = as.character(min(common_dates)), to = as.character(max(common_dates)),
                       n_days = length(common_dates)),
  sr_by_offset = setNames(as.list(round(tbl[offset %in% paste0("k", offsets), SR], 6)),
                          paste0("k", offsets)),
  range_SR = range_SR, threshold = thr, verdict = verdict,
  tranche = if (is.null(tranche_row)) "not_required (range < threshold)" else
    list(SR = tranche_row$SR, CAGR = tranche_row$CAGR, MDD = tranche_row$MDD,
         note = "채택 여부는 G5 도훈 — 본 측정은 채택 권고 아님"),
  turnover_invariance = list(
    target_delta_identical_by_construction = TRUE,
    target_yr = mean(traded_target) * 12,
    realized_drift_yr_by_offset = setNames(as.list(round(
      vapply(runs, function(r) mean(r$traded_real, na.rm = TRUE) * 12, numeric(1)), 6)), names(runs)),
    note = "목표비중 offset-불변이므로 target-delta 회전·비용은 6-NAV 동일. drift-기반 실현회전 차이는 진단 병기."),
  harness_validation = list(parity_k0_vs_carrier_recon_cor = parity_cor,
                            parity_max_abs_diff = parity_maxdiff, n_months = sum(ok)),
  metric_type = spec$metric_type, basis = spec$basis,
  frame_guard = "timing-luck 완화는 실현 경로 분산 축소 레버 — SR 개선 주장 금지 (사전등록 유지)",
  book_impact = "없음 — 진단 측정만, book_state 무변경"
)
write_json(verdict_obj, file.path(outdir, "verdict.json"), auto_unbox = TRUE, pretty = TRUE, digits = 8)
cat(sprintf("\n[SPEC2] DONE — 산출: %s\n", paste(c("nav_table.csv", "nav_monthly.csv", "verdict.json"), collapse = ", ")))
