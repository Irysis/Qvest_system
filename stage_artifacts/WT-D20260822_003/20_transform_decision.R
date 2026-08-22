## WT-D20260822_003 / FQ-234 NP2 — 통제 변환 정본 결정 (사전등록 §3 규칙 집행)
## ★결과량(forward return) 을 **쓰지 않는다**. 입력은 score 와 통제축의 종속성뿐.
##   따라서 이 스크립트는 성과를 보고 무언가를 고르는 경로가 아니다.
suppressMessages({ library(data.table); library(arrow); library(jsonlite) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
SRC <- file.path(ROOT, "stage_artifacts/WT-D20260813_006")
OUT <- file.path(ROOT, "stage_artifacts/WT-D20260822_003")

S <- as.data.table(read_parquet(file.path(SRC, "alpha_scores.parquet")))
S[, Date := as.Date(Date)]
fwd <- readRDS(file.path(SRC, "fwd.rds"))
LIQ <- as.data.table(fwd$liq_dt)[, .(Date = as.Date(Date), Ticker, adv)]

J <- list(
  wt_id = "WT-D20260822_003",
  role = "PREREG_NP2 §control_transform_decision_rule 집행 — 결과량 미사용",
  prereg_ref = "stage_artifacts/WT-D20260822_003/PREREG_NP2.json",
  generated_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S")
)

## ── 0. 패널 census (결손을 정상값으로 내려앉히지 않기 위해 먼저 센다) ────────
J$census <- list(
  n_rows = nrow(S), n_months = uniqueN(S$Date), n_tickers = uniqueN(S$Ticker),
  date_min = as.character(min(S$Date)), date_max = as.character(max(S$Date)),
  na_absorb_raw = sum(!is.finite(S$absorb_raw)),
  na_win_vol    = sum(!is.finite(S$win_vol)),
  na_log_size   = sum(!is.finite(S$log_size)),
  columns = names(S)
)

## 유동성 적용 영향 (사전등록: liq 2e8 적용)
M <- merge(S, LIQ, by = c("Date", "Ticker"), all.x = TRUE)
J$liquidity_census <- list(
  liq_min = 2e8,
  n_rows_before = nrow(M),
  n_adv_missing = sum(is.na(M$adv)),
  n_below_threshold = sum(!is.na(M$adv) & M$adv < 2e8),
  n_rows_after = sum(is.na(M$adv) | M$adv >= 2e8),
  rule = "is.na(adv) | adv >= liq_min (계약 canonical_distribution_screen 내부 규칙과 동일)"
)

## ── 1. 종속성 진단: 월별 횡단면 Pearson r vs Spearman rho ────────────────────
X <- M[(is.na(adv) | adv >= 2e8)][is.finite(absorb_raw) & is.finite(win_vol) & is.finite(log_size)]

dep <- X[, {
  n <- .N
  if (n < 25L) .(n = n, r_vol = NA_real_, s_vol = NA_real_, r_size = NA_real_, s_size = NA_real_)
  else .(n = n,
         r_vol  = suppressWarnings(cor(absorb_raw, win_vol,  method = "pearson")),
         s_vol  = suppressWarnings(cor(absorb_raw, win_vol,  method = "spearman")),
         r_size = suppressWarnings(cor(absorb_raw, log_size, method = "pearson")),
         s_size = suppressWarnings(cor(absorb_raw, log_size, method = "spearman")))
}, by = Date]

med <- function(v) stats::median(abs(v[is.finite(v)]))
mv_r <- med(dep$r_vol);  mv_s <- med(dep$s_vol)
ms_r <- med(dep$r_size); ms_s <- med(dep$s_size)

J$dependence <- list(
  n_months_evaluated = sum(is.finite(dep$r_vol)),
  win_vol  = list(median_abs_pearson = mv_r, median_abs_spearman = mv_s,
                  ratio_spearman_over_pearson = mv_s / mv_r),
  log_size = list(median_abs_pearson = ms_r, median_abs_spearman = ms_s,
                  ratio_spearman_over_pearson = ms_s / ms_r),
  note = paste0("월별 횡단면 상관의 |값| 중앙값. Spearman 이 Pearson 보다 크면 종속이 단조이되 ",
                "선형이 아니라는 신호 — 선형 OLS 직교화는 그만큼 덜 걷어낸다.")
)

## 보조 진단(규칙 입력 아님, 기록만): 선형 R^2 vs 순위-선형 R^2
r2 <- X[, {
  if (.N < 25L) .(r2_lin = NA_real_, r2_rank = NA_real_)
  else {
    zv <- function(v) { s <- sd(v); if (!is.finite(s) || s <= 0) rep(NA_real_, length(v)) else (v - mean(v)) / s }
    rk <- function(v) zv(frank(v))
    f1 <- try(summary(lm(absorb_raw ~ zv(win_vol) + zv(log_size)))$r.squared, silent = TRUE)
    f2 <- try(summary(lm(absorb_raw ~ rk(win_vol) + rk(log_size)))$r.squared, silent = TRUE)
    .(r2_lin  = if (inherits(f1, "try-error")) NA_real_ else f1,
      r2_rank = if (inherits(f2, "try-error")) NA_real_ else f2)
  }
}, by = Date]
J$explained_variance_aux <- list(
  median_r2_linear_controls = stats::median(r2$r2_lin, na.rm = TRUE),
  median_r2_rank_controls   = stats::median(r2$r2_rank, na.rm = TRUE),
  note = "보조 기록 — 사전등록 규칙의 입력이 아니다. rank 통제가 더 많은 분산을 설명하면 raw 잔차에 통제 성분이 남는다는 뜻."
)

## ── 2. 사전등록 규칙 집행 ────────────────────────────────────────────────────
THRESH <- 1.10
trig_vol  <- is.finite(mv_s) && is.finite(mv_r) && mv_s >= mv_r * THRESH
trig_size <- is.finite(ms_s) && is.finite(ms_r) && ms_s >= ms_r * THRESH
primary <- if (trig_vol || trig_size) "rank" else "raw"

J$rule_application <- list(
  rule = "어느 하나라도 median|rho| >= median|r| * 1.10 이면 primary=rank, 아니면 primary=raw",
  threshold = THRESH,
  triggered_win_vol = trig_vol,
  triggered_log_size = trig_size,
  primary_transform = primary,
  companion_transform = if (identical(primary, "rank")) "raw" else "rank",
  sealed_note = paste0("본 값은 canonical_distribution_screen() 호출 **전** 에 확정됐다. ",
                       "측정 후 변경 금지(PREREG_NP2 §prohibitions_self_imposed).")
)

write_json(J, file.path(OUT, "PREREG_NP2_transform_decision.json"),
           auto_unbox = TRUE, pretty = TRUE, digits = NA, na = "null", null = "null")
cat("[transform decision]\n")
cat("  win_vol : |r|", round(mv_r, 4), " |rho|", round(mv_s, 4), " ratio", round(mv_s/mv_r, 4), " trig", trig_vol, "\n")
cat("  log_size: |r|", round(ms_r, 4), " |rho|", round(ms_s, 4), " ratio", round(ms_s/ms_r, 4), " trig", trig_size, "\n")
cat("  PRIMARY =", primary, "\n")
cat("  liq: before", nrow(M), " after", J$liquidity_census$n_rows_after,
    " below", J$liquidity_census$n_below_threshold, " missing", J$liquidity_census$n_adv_missing, "\n")
