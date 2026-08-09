## WT-D20260809_001 P0 — 입력 실측 + 검정력 바 + CH-B(꼬리/단조성)
## 사전등록: stage_artifacts/WT_D20260809_001/preregistration.json (측정 전 작성 완료)
## metric_type = canonical_screen_diag. 자본 주장 없음.
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/WT_D20260809_001")
say  <- function(fmt, ...) { cat(sprintf(paste0("[p0] ", fmt, "\n"), ...)); flush.console() }

source("02_Infrastructure/config.R")
source("02_Infrastructure/ramp/factor_validation.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")   # .nw_t_mean 경유 로드
source("02_Infrastructure/contracts/required_effect_size.R")

## 사전등록 무결성 확인 (파싱 가능해야 측정 자격)
PRE <- fromJSON(file.path(OUT, "preregistration.json"), simplifyVector = FALSE)
say("사전등록 파싱 OK — 채널 %d / 처분규칙 %d",
    length(PRE$channels), length(PRE$disposition_rules_fixed_before_results))

## ---- 1. 입력 실측 (첫 출력 — 가정 금지) --------------------------------------
say("=== 1. 입력 실측 ===")
A <- as.data.table(read_parquet("stage_artifacts/WT_D20260808_002/alpha_scores.parquet"))
A[, Date := as.Date(Date)]
say("  scores  : %d행 · %d개월 · 관측단위 (월말 Date x Ticker) · %s ~ %s",
    nrow(A), uniqueN(A$Date), min(A$signal_ym), max(A$signal_ym))
say("  컬럼    : %s", paste(names(A), collapse = ", "))
decl <- PRE$input_declared
ok_rows <- nrow(A) == decl$expected_rows
ok_mon  <- uniqueN(A$Date) == decl$expected_months
say("  선언대조: 행 %d==%d %s · 월 %d==%d %s",
    nrow(A), decl$expected_rows, ok_rows, uniqueN(A$Date), decl$expected_months, ok_mon)
if (!ok_rows || !ok_mon) { say("★선언 불일치 — 측정 중단"); quit(status = 1) }

RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
        col_select = c("Date","Ticker","Close","Vol","Size","K200","KQ150")))
RAW[, Date := as.Date(Date)]
say("  RAWDATA : %d행 · 관측단위 daily · 고유일자 %d · %s ~ %s",
    nrow(RAW), uniqueN(RAW$Date), min(RAW$Date), max(RAW$Date))
ME <- sort(RAW[, .(Date = max(Date)), by = .(ym = format(Date, "%Y-%m"))]$Date)
RAWME <- RAW[Date %in% ME]; rm(RAW); gc(FALSE)
fwd <- build_monthly_forward_returns(RAWME, ME)
ret <- fwd$returns_dt; bench <- fwd$bench_dt; liq <- fwd$liq_dt
size_dt <- RAWME[, .(Date, Ticker, Size)]
say("  ret %d행 · bench %d행 · liq %d행 (계약함수 build_monthly_forward_returns)",
    nrow(ret), nrow(bench), nrow(liq))

saveRDS(list(A = A, ret = ret, bench = bench, liq = liq, size_dt = size_dt),
        file.path(OUT, "p0_panels.rds"))

## ---- 2. 검정력 바 (FQ-161 착수 전 의무) --------------------------------------
say("=== 2. 검정력 바 (required_effect) ===")
pow_rows <- list()
for (n in c(283L)) {
  for (sd_lab in c("spread25ew_default", "m26_fmb_own")) {
    sd_m <- if (sd_lab == "spread25ew_default") SPREAD_SD_MONTHLY_25EW else 0.0104712780894609
    r <- required_effect(n = n, t_threshold = 2.95, sd_monthly = sd_m, design = "full")
    say("  t*=2.95 n=%d sd=%s(%.4f) -> 필요 월 %.5f = 연 %.3f%%",
        n, sd_lab, sd_m, r$required_monthly, r$required_annual * 100)
    pow_rows[[length(pow_rows) + 1L]] <- data.table(
      n = n, sd_label = sd_lab, sd_monthly = sd_m, t_threshold = 2.95,
      required_monthly = r$required_monthly, required_annual_pct = r$required_annual * 100)
  }
}
POW <- rbindlist(pow_rows)
say("  ★해석 규약: sd 가 arm 자신이면 바는 t 검정의 재진술이다(verdict_with_power 주석).")
say("  ★관측 M26 FMB 효과 = 월 0.00167 = 연 2.004%% (WT-002 실측)")

## ---- 3. CH-B 꼬리/단조성 -----------------------------------------------------
say("=== 3. CH-B decile 단조성 ===")
S <- A[, .(Date, Ticker, score = M26_Revenue_Mom)][!is.na(score)]
S <- merge(S, ret[, .(Date, Ticker, Ret_1m)], by = c("Date","Ticker"))
S <- S[!is.na(Ret_1m)]
say("  merge 후: %d행 · %d개월", nrow(S), uniqueN(S$Date))

L <- as.data.table(liq)[, .(Date, Ticker, adv)]
S <- merge(S, L, by = c("Date","Ticker"), all.x = TRUE)

decile_run <- function(D, tag, min_n = 30L) {
  D <- copy(D)
  D[, n_mo := .N, by = Date]
  D <- D[n_mo >= min_n]
  D[, dec := cut(frank(score, ties.method = "first"),
                 breaks = quantile(seq_len(.N), probs = seq(0, 1, 0.1)),
                 include.lowest = TRUE, labels = FALSE), by = Date]
  D[, univ_ew := mean(Ret_1m), by = Date]
  M <- D[, .(ret_ew = mean(Ret_1m), univ = univ_ew[1], n = .N), by = .(Date, dec)]
  M[, excess := ret_ew - univ]
  res <- M[, .(mean_excess_m = mean(excess),
               ann_excess_pct = mean(excess) * 12 * 100,
               t_nw3 = .nw_t_mean(excess, lag = 3L),
               n_months = .N,
               avg_n = mean(n)), by = dec][order(dec)]
  sp <- suppressWarnings(cor(res$dec, res$mean_excess_m, method = "spearman"))
  top <- res[dec == 10, mean_excess_m]; bot <- res[dec == 1, mean_excess_m]
  lss <- abs(top) / (abs(top) + abs(bot))
  say("  --- %s (개월 %d · 월평균 종목 %.0f) ---", tag, uniqueN(D$Date), mean(res$avg_n))
  for (i in seq_len(nrow(res)))
    say("    D%-2d  연초과 %+7.3f%%  t_NW3 %+6.3f  (월 %d, 평균 %0.f종)",
        res$dec[i], res$ann_excess_pct[i], res$t_nw3[i], res$n_months[i], res$avg_n[i])
  say("    ★단조성 spearman(dec, excess) = %+.3f", sp)
  say("    ★D10 연초과 %+.3f%% (t %+.2f) / D1 연초과 %+.3f%% (t %+.2f)",
      res[dec == 10, ann_excess_pct], res[dec == 10, t_nw3],
      res[dec == 1, ann_excess_pct], res[dec == 1, t_nw3])
  say("    ★long_side_share = |D10| / (|D10|+|D1|) = %.3f  (사전선언 문턱 0.40)", lss)
  ## D10-D1 스프레드(공매도 불가 — 정보용 진단이며 실행가능 주장 아님)
  W <- dcast(M[dec %in% c(1, 10)], Date ~ dec, value.var = "excess")
  setnames(W, c("Date","d1","d10"))
  W <- W[!is.na(d1) & !is.na(d10)]
  spread_t <- .nw_t_mean(W$d10 - W$d1, lag = 3L)
  say("    [정보용] D10-D1 스프레드 연 %+.3f%% t_NW3 %+.3f — long-only 미실행(공매도 불가)",
      mean(W$d10 - W$d1) * 12 * 100, spread_t)
  list(tag = tag, table = res, spearman = sp, long_side_share = lss,
       top_ann = res[dec == 10, ann_excess_pct], top_t = res[dec == 10, t_nw3],
       bot_ann = res[dec == 1, ann_excess_pct], bot_t = res[dec == 1, t_nw3],
       spread_ann = mean(W$d10 - W$d1) * 12 * 100, spread_t = spread_t,
       n_months = uniqueN(D$Date))
}

B_liq  <- decile_run(S[is.na(adv) | adv >= 2e8], "primary: 유동성필터 adv>=2e8")
B_full <- decile_run(S,                          "robustness: 유동성필터 미적용")

saveRDS(list(power = POW, chb_liq = B_liq, chb_full = B_full),
        file.path(OUT, "p0_results.rds"))
say("=== P0 완료 → p0_results.rds / p0_panels.rds ===")
