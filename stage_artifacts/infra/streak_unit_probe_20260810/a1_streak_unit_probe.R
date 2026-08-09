#==============================================================================
# a1_streak_unit_probe.R — C11_Earnings_Streak / M25_Earnings_Mom_Streak 판정
#
# 물음: streak 이 연속 양수 **분기**를 세는가, 연속 양수 **영업일**을 세는가.
#
# ★판별식은 FQ-218 의 `mean == latest` 를 베낄 수 없다. streak 은 평균이 아니라
#   카운트다. 평균에서는 창이 붕괴하면 이동평균이 **항등변환**이 되어 정보가 사라진다.
#   카운트에서는 창이 붕괴해도 정보가 사라지지 않고 **단위가 바뀐다**(분기 → 행).
#   그러므로 재야 할 것이 다르다:
#
#   D1 단위 시험      : s_rows / s_qtr 비. 단위가 분기면 정확히 1, 일간이면 ~60
#   D2 릴리스-독립 시험: 릴리스가 없는 달에도 값이 커지는가 (Δs between month-ends
#                        within one release epoch). 분기 카운트면 Δ=0, 행 카운트면 Δ≈21
#   D3 입도 시험      : 횡단면 고유값 수 / 종목수. 분기 카운트면 낮고(동률 많음)
#                        일간 카운트면 높다
#   D4 소비 영향 시험 : ★단위가 틀려도 **순위가 보존되면** 소비면(z-score·랭킹)은
#                        불변일 수 있다. z 는 winsorize 후 (x-mean)/sd = **아핀 불변**
#                        이므로 s_rows = a*s_qtr + b 가 정확히 성립하면 영향 0이다.
#                        그래서 rho_spearman · z 차이 · top-quintile Jaccard 를 잰다.
#                        D1~D3 가 결함을 말해도 D4 가 결정한다 — 재빌드의 근거는
#                        "단위가 틀렸다"가 아니라 "소비되는 값이 달라진다"이다.
#
# 양성 대조: 같은 실행에서 C10 구코드(mean(x[1:4])) 의 mean==latest 가 1.0 으로
#            재현되는가 (계측 생존 확인). 음성 대조: C01(latest 1개)·M26(63일 lag).
#
# 읽기 전용. factor_db 재빌드 없음.
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow) })

ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
ROOT <- gsub("\\\\", "/", ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/infra/streak_unit_probe_20260810")
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)
source(file.path(ROOT, "02_Infrastructure/factor_db/factor_z_standard.R"))

SUE <- as.data.table(read_parquet(file.path(ROOT, ".cache/consensus/sue.parquet")))
SUE[, Date := as.Date(Date)]
SUE <- SUE[!is.na(sue), .(Ticker, Date, value = sue)]
cat(sprintf("[load] sue: %s행 %d티커 %s..%s\n", format(nrow(SUE), big.mark = ","),
            uniqueN(SUE$Ticker), min(SUE$Date), max(SUE$Date)))

#-- 릴리스 epoch (달력만 사용 = PIT 자명). 실측 근거: sue 값 변경은 100% 월초이고
#   4/6/9/12월에 각 ~25% (p1_change_month_dist.csv / p2_pit_convention.csv).
#   경계 = 4/1, 6/1, 9/1, 12/1 → epoch = [12/1,4/1) [4/1,6/1) [6/1,9/1) [9/1,12/1)
epoch_id <- function(d) {
  y <- year(d); m <- month(d)
  yy <- fifelse(m <= 3L, y - 1L, y)
  ss <- fifelse(m <= 3L, 3L, fifelse(m <= 5L, 0L, fifelse(m <= 8L, 1L,
        fifelse(m <= 11L, 2L, 3L))))
  as.integer(yy) * 4L + as.integer(ss)
}

#-- 현행 구현 (compute_consensus.R:351-357 / compute_momentum.R:349-355 축자 복제)
streak_rows_prod <- function(h) {
  hh <- copy(h); setorderv(hh, c("Ticker", "Date"), c(1L, -1L))
  hh[, {
    s <- 0L
    for (i in seq_len(.N)) {
      if (!is.na(value[i]) && value[i] > 0) s <- s + 1L else break
    }
    list(s_rows = as.numeric(s))
  }, by = Ticker]
}

#-- 값-런 dedup (FQ-218 .cons_quarters 와 같은 창 정의)
streak_runs_dedup <- function(h) {
  hh <- copy(h); setorderv(hh, c("Ticker", "Date"), c(1L, 1L))
  hh[, newrun := is.na(shift(value)) | Ticker != shift(Ticker) |
                 abs(value - shift(value)) > 1e-12]
  hh[, runid := cumsum(newrun)]
  rt <- hh[, .(Ticker = Ticker[1L], value = value[1L], run_start = min(Date)), by = runid]
  setorderv(rt, c("Ticker", "run_start"), c(1L, -1L))
  rt[, {
    s <- 0L
    for (i in seq_len(.N)) { if (value[i] > 0) s <- s + 1L else break }
    list(s_runs = as.numeric(s))
  }, by = Ticker]
}

#-- 릴리스 epoch 리샘플: epoch 당 마지막 관측 1개 → 연속 양수 epoch 카운트
#   (동률 병합 없음. epoch 결번은 streak 을 끊는다 = 커버리지 공백을 연속으로 안 봄)
streak_epoch <- function(h) {
  hh <- copy(h)
  hh[, ep := epoch_id(Date)]
  setorderv(hh, c("Ticker", "ep", "Date"), c(1L, 1L, 1L))
  ee <- hh[, .(value = value[.N]), by = .(Ticker, ep)]
  setorderv(ee, c("Ticker", "ep"), c(1L, -1L))
  ee[, {
    s <- 0L; prev_ep <- NA_integer_
    for (i in seq_len(.N)) {
      if (i > 1L && (prev_ep - ep[i]) != 1L) break
      if (value[i] > 0) { s <- s + 1L; prev_ep <- ep[i] } else break
    }
    list(s_qtr = as.numeric(s))
  }, by = Ticker]
}

#-- 양성 대조: C10 구코드 vs 신코드 (계측이 살아있는지)
pc_c10 <- function(h) {
  hh <- copy(h); setorderv(hh, c("Ticker", "Date"), c(1L, -1L))
  old <- hh[, .(mean4 = mean(value[1:min(4L, .N)]), latest = value[1L]), by = Ticker]
  old[, eq := abs(mean4 - latest) < 1e-12]
  mean(old$eq)
}

SIG <- as.Date(c("2005-06-30", "2008-12-31", "2011-06-30", "2014-03-31",
                 "2017-09-29", "2020-06-30", "2023-03-31", "2026-06-30"))

topset <- function(v, tk, n) tk[order(-v, tk)][seq_len(min(n, length(v)))]

res <- list()
for (sd_ in SIG) {
  sd_ <- as.Date(sd_, origin = "1970-01-01")
  h <- SUE[Date <= sd_]
  if (!nrow(h)) { cat(sprintf("[skip] %s 관측 0\n", sd_)); next }

  a <- streak_rows_prod(h)
  b <- streak_runs_dedup(h)
  c_ <- streak_epoch(h)
  m <- merge(merge(a, b, by = "Ticker"), c_, by = "Ticker")

  pos <- m[s_qtr >= 1L]
  z_rows <- z_safe_winsorize(m$s_rows)
  z_qtr  <- z_safe_winsorize(m$s_qtr)
  dz <- abs(z_rows - z_qtr)

  t1 <- topset(m$s_rows, m$Ticker, ceiling(0.2 * nrow(m)))
  t2 <- topset(m$s_qtr,  m$Ticker, ceiling(0.2 * nrow(m)))
  t1b <- topset(m$s_rows, m$Ticker, 25L); t2b <- topset(m$s_qtr, m$Ticker, 25L)

  res[[as.character(sd_)]] <- data.table(
    sig_date = sd_, n_ticker = nrow(m),
    # D1 단위
    frac_unit_match = if (nrow(pos)) mean(pos$s_rows == pos$s_qtr) else NA_real_,
    ratio_median    = if (nrow(pos)) median(pos$s_rows / pos$s_qtr) else NA_real_,
    ratio_p95       = if (nrow(pos)) as.numeric(quantile(pos$s_rows / pos$s_qtr, .95)) else NA_real_,
    frac_zero_agree = mean((m$s_rows == 0) == (m$s_qtr == 0)),
    s_rows_med = median(m$s_rows), s_rows_max = max(m$s_rows),
    s_qtr_med  = median(m$s_qtr),  s_qtr_max  = max(m$s_qtr),
    s_runs_med = median(m$s_runs), s_runs_max = max(m$s_runs),
    # D3 입도
    distinct_rows = uniqueN(m$s_rows), distinct_qtr = uniqueN(m$s_qtr),
    distinct_ratio_rows = uniqueN(m$s_rows) / nrow(m),
    distinct_ratio_qtr  = uniqueN(m$s_qtr)  / nrow(m),
    # D4 소비 영향
    rho_rows_qtr  = suppressWarnings(cor(m$s_rows, m$s_qtr,  method = "spearman")),
    rho_rows_runs = suppressWarnings(cor(m$s_rows, m$s_runs, method = "spearman")),
    rho_qtr_runs  = suppressWarnings(cor(m$s_qtr,  m$s_runs, method = "spearman")),
    max_abs_dz    = suppressWarnings(max(dz, na.rm = TRUE)),
    frac_dz_gt_05 = mean(dz > 0.5, na.rm = TRUE),
    jaccard_q5 = length(intersect(t1, t2)) / length(union(t1, t2)),
    overlap_top25 = length(intersect(t1b, t2b)) / 25,
    # 양성 대조
    pc_c10_old_eq_latest = pc_c10(h)
  )
  cat(sprintf("[%s] n=%4d  unit_match=%.4f  ratio_med=%.1f  rho(rows,qtr)=%.4f  J5=%.3f  PC_C10old=%.4f\n",
              sd_, nrow(m), res[[as.character(sd_)]]$frac_unit_match,
              res[[as.character(sd_)]]$ratio_median, res[[as.character(sd_)]]$rho_rows_qtr,
              res[[as.character(sd_)]]$jaccard_q5, res[[as.character(sd_)]]$pc_c10_old_eq_latest))
}
R <- rbindlist(res)
fwrite(R, file.path(OUT, "a1_streak_discriminants.csv"))

#-- D2 릴리스-독립 시험: 같은 epoch 안 연속 월말에서 값이 커지는가
cat("\n== D2 릴리스-독립 (같은 릴리스 epoch 내 월말 3점) ==\n")
D2SETS <- list(c("2018-06-29", "2018-07-31", "2018-08-31"),   # epoch [6/1, 9/1)
               c("2012-09-28", "2012-10-31", "2012-11-30"),   # epoch [9/1, 12/1)
               c("2022-12-29", "2023-01-31", "2023-02-28"))   # epoch [12/1, 4/1)
d2 <- list()
for (k in seq_along(D2SETS)) {
  ds <- as.Date(D2SETS[[k]])
  prev <- NULL
  for (sd_ in ds) {
    sd_ <- as.Date(sd_, origin = "1970-01-01")
    h <- SUE[Date <= sd_]
    a <- streak_rows_prod(h); c_ <- streak_epoch(h)
    cur <- merge(a, c_, by = "Ticker")
    if (!is.null(prev)) {
      j <- merge(prev, cur, by = "Ticker", suffixes = c("_0", "_1"))
      j <- j[s_rows_0 > 0]
      d2[[length(d2) + 1L]] <- data.table(
        epoch_set = k, from = prev_date, to = sd_, n = nrow(j),
        d_rows_median = median(j$s_rows_1 - j$s_rows_0),
        d_rows_p90 = as.numeric(quantile(j$s_rows_1 - j$s_rows_0, .90)),
        frac_rows_changed = mean(j$s_rows_1 != j$s_rows_0),
        d_qtr_median = median(j$s_qtr_1 - j$s_qtr_0),
        frac_qtr_changed = mean(j$s_qtr_1 != j$s_qtr_0))
    }
    prev <- cur; prev_date <- sd_
  }
}
D2 <- rbindlist(d2)
fwrite(D2, file.path(OUT, "a2_release_independence.csv"))
print(D2)

#-- C11 vs M25 동일성 (같은 원천·같은 식이면 값이 같아야)
cat("\n== C11 vs M25 (코드 축자 대조는 별도, 여기선 산출값) ==\n")
h <- SUE[Date <= as.Date("2024-06-28")]
a <- streak_rows_prod(h)
cat(sprintf("  C11/M25 공통 구현 산출: n=%d  median=%.0f  max=%.0f\n",
            nrow(a), median(a$s_rows), max(a$s_rows)))

cat("\n---- 판정 규칙 ----\n")
cat(" frac_unit_match ~0 이고 ratio_median >> 1  ⇒ 단위가 분기 아니라 행 (결함 확정)\n")
cat(" d_rows_median > 0 (릴리스 없는 달에 증가)  ⇒ 분기 경계와 무관하게 증가 (결함 확정)\n")
cat(" rho_rows_qtr ~1.000 & jaccard_q5 ~1.000    ⇒ 순위 보존 = 소비 영향 없음 (재빌드 불요)\n")
cat(" rho_rows_qtr < 1  또는 jaccard_q5 < 1      ⇒ 소비되는 값이 다름 (재빌드 필요)\n")
cat(sprintf("\n[out] %s\n", OUT))
