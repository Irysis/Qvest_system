#==============================================================================
# a6_family_sweep_verify.R — 계통 전수 후보의 **직접 실측** (남의 보고를 판정으로
# 승격하지 않는다). 각 후보마다 원천의 값 변경 간격을 먼저 재고, 그 다음 창이
# 그 단위와 맞는지 본다.
#
# 후보:
#  S1 compute_crowding.R:422-424 SE02_Consensus_Revision
#     date_rank==1 vs ==2 = 인접 **행** 차. 원천 = CONSENSUS eps_1y / target_price
#     → 이 두 지표의 변경 간격을 잰다(FQ-218 은 sue/esbr/revenue/op 만 쟀다)
#  S2 compute_momentum.R:348-355 M25 — C11 과 동일 (a1 에서 이미 판정)
#  S3 compute_regime.R:317/503/510 shift(Value,12) — MACRO 다중 시리즈 stack 에
#     by=Series 없음. 다른 결함 계통. 두 시리즈가 실제로 함께 있는지부터 확인.
#
# ★계측 생존(양성 대조): 같은 판별식을 sue 에 적용하면 결함이 검거되는가.
#
# 읽기 전용.
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
ROOT <- gsub("\\\\", "/", ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/infra/streak_unit_probe_20260810")
CD   <- file.path(ROOT, ".cache/consensus")

# ── S1a: 남은 컨센서스 지표 전부의 관측/변경 리듬 (FQ-218 미측정분 포함) ──────
metrics <- sub("\\.parquet$", "", list.files(CD, pattern = "\\.parquet$"))
metrics <- setdiff(metrics, "ticker_map")
rows <- list()
for (mt in metrics) {
  h <- as.data.table(read_parquet(file.path(CD, paste0(mt, ".parquet"))))
  if (!(mt %in% names(h))) { cat(sprintf("[skip] %s: 값 컬럼 없음 (%s)\n", mt,
      paste(names(h), collapse = ","))); next }
  h[, Date := as.Date(Date)]
  h <- h[!is.na(get(mt)), .(Ticker, Date, value = get(mt))]
  if (!nrow(h)) next
  setorderv(h, c("Ticker", "Date"))
  h[, gap := as.integer(Date - shift(Date)), by = Ticker]
  h[, prev_v := shift(value), by = Ticker]
  h[, changed := !is.na(prev_v) & abs(value - prev_v) > 1e-12]
  ch <- h[changed == TRUE]; setorderv(ch, c("Ticker", "Date"))
  ch[, cg := as.integer(Date - shift(Date)), by = Ticker]
  cg <- ch[!is.na(cg), cg]
  rows[[mt]] <- data.table(
    metric = mt, n_rows = nrow(h), n_ticker = uniqueN(h$Ticker),
    obs_gap_med = median(h$gap, na.rm = TRUE),
    chg_gap_med = if (length(cg)) median(cg) else NA_real_,
    chg_rate = mean(h$changed, na.rm = TRUE),
    # ★핵심 판별: 인접 **행** 차분이 0인 비율 = 행-단위 창의 무력화율
    frac_adjacent_row_unchanged = 1 - mean(h$changed, na.rm = TRUE))
}
S1 <- rbindlist(rows)[order(chg_rate)]
cat("== S1a 컨센서스 지표별 리듬 (인접 행 차분이 0인 비율 = 행-단위 창 무력화율) ==\n")
print(S1)
fwrite(S1, file.path(OUT, "a6_consensus_metric_rhythm.csv"))

# ── S1b: SE02 재현 — compute_crowding.R:422-428 축자 복제 ────────────────────
cat("\n== S1b SE02_Consensus_Revision 재현 (crowding:422-428 축자) ==\n")
se02 <- list()
for (rc in c("eps_1y", "target_price")) {
  p <- file.path(CD, paste0(rc, ".parquet"))
  if (!file.exists(p)) next
  src <- as.data.table(read_parquet(p)); src[, Date := as.Date(Date)]
  for (sd_ in as.Date(c("2008-12-31", "2014-03-31", "2020-06-30", "2026-06-30"))) {
    sd_ <- as.Date(sd_, origin = "1970-01-01")
    cs_pit <- src[Date <= sd_ & !is.na(get(rc))]
    if (!nrow(cs_pit)) next
    cs_pit[, date_rank := frank(-as.numeric(Date)), by = Ticker]
    curr <- cs_pit[date_rank == 1, .(Ticker, val_curr = get(rc))]
    prev <- cs_pit[date_rank == 2, .(Ticker, val_prev = get(rc))]
    rv <- merge(curr, prev, by = "Ticker", all = FALSE)
    rv <- rv[!is.na(val_curr) & !is.na(val_prev) & abs(val_prev) > 1e-8]
    if (!nrow(rv)) next
    rv[, SE02 := (val_curr - val_prev) / abs(val_prev)]
    # 달력-기반 정본 대조 (M26/M28 이 쓰는 63일 lag)
    lagt <- cs_pit[Date <= sd_ - 63L]
    ok <- nrow(lagt) > 0
    if (ok) {
      lagt <- lagt[order(Ticker, -Date)][, .SD[1L], by = Ticker][, .(Ticker, v63 = get(rc))]
      cmp <- merge(rv, lagt, by = "Ticker")
      cmp[, SE02_cal := (val_curr - v63) / abs(v63)]
    }
    se02[[length(se02) + 1L]] <- data.table(
      col = rc, sig_date = sd_, n = nrow(rv),
      frac_exact_zero = mean(abs(rv$SE02) < 1e-12),
      sd_SE02 = sd(rv$SE02),
      n_distinct = uniqueN(round(rv$SE02, 12)),
      frac_zero_cal = if (ok) mean(abs(cmp$SE02_cal) < 1e-12) else NA_real_,
      sd_cal = if (ok) sd(cmp$SE02_cal, na.rm = TRUE) else NA_real_,
      rho_row_vs_cal = if (ok && nrow(cmp) > 20)
        suppressWarnings(cor(cmp$SE02, cmp$SE02_cal, method = "spearman")) else NA_real_)
  }
}
S2 <- rbindlist(se02); print(S2); fwrite(S2, file.path(OUT, "a6_se02_reproduce.csv"))

# 실제 배출 원장 대조
led <- fread(file.path(ROOT, ".cache/factor_db/emission_ledger.csv"))
cat("\n== S1c SE02 배출 원장 ==\n")
print(led[Factor_Name %like% "SE02", .(n_months = uniqueN(ym), first = min(ym), last = max(ym),
                                        med_rows = median(n_rows))])

# ── S3: compute_regime.R MACRO 다중 시리즈 stack ─────────────────────────────
cat("\n== S3 MACRO shift(Value,12) — 두 시리즈 공존 여부 ==\n")
mp <- file.path(ROOT, ".cache/macro_fred.parquet")
if (file.exists(mp)) {
  M <- as.data.table(read_parquet(mp))
  cat(sprintf("  macro_fred.parquet: %s행 컬럼 %s\n", format(nrow(M), big.mark = ","),
              paste(names(M), collapse = ",")))
  scol <- intersect(c("Series", "series", "series_id"), names(M))[1]
  if (!is.na(scol)) {
    print(M[, .N, by = c(scol)][order(-N)][1:20])
    for (pr in list(c("INDPRO", "A191RL1Q225SBEA"), c("CPIAUCSL", "CPIAUCNS"))) {
      have <- pr[pr %in% M[[scol]]]
      cat(sprintf("  쌍 [%s]: 존재 = %s (%d/2)\n", paste(pr, collapse = ", "),
                  paste(have, collapse = ", "), length(have)))
    }
  }
} else cat("  [부재] .cache/macro_fred.parquet — 경로 확인 필요\n")

cat("\n---- 판정 규칙 ----\n")
cat(" frac_adjacent_row_unchanged ~0.99 & 창이 행-단위 ⇒ 결함 (창 무력)\n")
cat(" SE02 frac_exact_zero 높음 & sd_cal >> sd_SE02   ⇒ SE02 결함 확정\n")
cat(" MACRO 쌍이 2/2 존재                              ⇒ shift(,12) 시리즈 교락 확정\n")
