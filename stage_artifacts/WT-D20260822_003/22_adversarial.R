## WT-D20260822_003 / FQ-234 NP2 — Self-Adversarial Challenge (v8.2, 의무)
## 전부 **비바인딩**. R1 게이트를 대체하지 않는다. 결과가 R1 을 약화시켜도 그대로 보고한다.
##  A1 통제 강도: raw 와 rank 를 **동시에** 넣은 4축 통제 (내 사전등록 논거의 반증)
##  A2 순열 위약: Date 내 score 셔플 — 배관이 없는 신호를 만들어내지 않는지 (차단 실효)
##  A3 대안 설명: 과거 12M 실현 왜도 + 과거 12M vol 을 통제에 추가 (MAX/복권수요 repackaging?)
##  A4 이미 관측된 분할(2015-07-01) 재현 — 신규 증거로 계상하지 않고 대조만
suppressMessages({ library(data.table); library(arrow); library(jsonlite) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
SRC <- file.path(ROOT, "stage_artifacts/WT-D20260813_006")
OUT <- file.path(ROOT, "stage_artifacts/WT-D20260822_003")
source("02_Infrastructure/contracts/distribution_target_screen.R")
set.seed(20260822)

S <- as.data.table(read_parquet(file.path(SRC, "alpha_scores.parquet"))); S[, Date := as.Date(Date)]
fwd <- readRDS(file.path(SRC, "fwd.rds"))
RET <- as.data.table(fwd$returns_dt)[, .(Date = as.Date(Date), Ticker, Ret_1m)]
LIQ <- as.data.table(fwd$liq_dt)[, .(Date = as.Date(Date), Ticker, adv)]

SCORES  <- S[is.finite(absorb_raw), .(Date, Ticker, score = absorb_raw)]
WIN2 <- list(early = as.Date(c("2000-01-01", "2015-12-01")),
             late  = as.Date(c("2015-12-01", "2026-06-01")))
AX <- c("median_spread","skew_spread","skew_slope","tail_up_prob_diff",
        "tail_dn_prob_diff","qspread_p10","qspread_p90")

grab <- function(res) {
  o <- list()
  for (wn in names(res$windows)) {
    a <- res$windows[[wn]]$orthogonalized$axes
    o[[wn]] <- if (is.null(a)) NULL else
      as.list(vapply(AX, function(x) as.numeric(a[[x]]$nw_t), numeric(1)))
  }
  list(orth_nw_t = o,
       survived_any = res$survival$survived_axes_any_window,
       survived_all = res$survival$survived_axes_all_windows,
       verdict = res$survival$verdict,
       sign_agreement = res$sign_agreement$verdict,
       control_cols = res$control_spec$cols,
       transform = res$control_spec$transform)
}
go <- function(scores, control, cols, transform, id, windows = WIN2) {
  grab(canonical_distribution_screen(
    scores_dt = scores, returns_dt = RET, control_dt = control, control_cols = cols,
    control_transform = transform, n_quantiles = 5L, q_hi = 5L, q_lo = 1L,
    quantile_probs = c(0.10, 0.90), tail_threshold_mode = "fixed",
    tail_fixed_up = 0.20, tail_fixed_dn = -0.20, winsorize_probs = c(0.01, 0.99),
    liq_dt = LIQ, liq_min = 2e8, windows = windows, nw_lag = 3L, t_min_survive = 2.0,
    run_id = id, spec_id = "FQ234_absorb_w3_corr",
    prereg_ref = "stage_artifacts/WT-D20260822_003/PREREG_NP2.json"))
}

J <- list(wt_id = "WT-D20260822_003", role = "self-adversarial (non-binding)",
          generated_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"))

## ── A1. raw + rank 동시 통제 (4축) ───────────────────────────────────────────
## 내 사전등록 논거는 "rank 가 항상 더 강한 통제" 였다. 보조 진단(median R^2: 선형
## 0.2805 vs 순위 0.2760)이 그 논거를 반증한다 — 두 통제축의 선호가 반대다
## (win_vol 은 |r| > |rho|, log_size 는 |rho| > |r|). 그렇다면 둘 다 넣은 통제가
## 어느 한쪽보다 엄하다. 여기서 죽으면 R1 의 강도 주장은 그만큼 내려간다.
C4 <- copy(S[, .(Date, Ticker, win_vol, log_size)])
C4[, `:=`(win_vol_rk  = (frank(win_vol) / .N) - 0.5,
          log_size_rk = (frank(log_size) / .N) - 0.5), by = Date]
J$A1_raw_plus_rank_4axis <- go(SCORES, C4,
  c("win_vol", "log_size", "win_vol_rk", "log_size_rk"), "raw", "NP2_adv_4axis")
cat("[A1] done\n")

## ── A2. 순열 위약 (Date 내 score 셔플) — 배관 차단 실효 ──────────────────────
PERM <- copy(SCORES)[, score := sample(score), by = Date]
J$A2_permutation_placebo <- go(PERM, S[, .(Date, Ticker, win_vol, log_size)],
  c("win_vol", "log_size"), "rank", "NP2_adv_perm")
cat("[A2] done\n")

## ── A3. 과거 12M 실현 왜도·변동성 추가 통제 (MAX/복권수요 대안 설명) ─────────
## PIT: Date t 의 통제는 Ret_1m 의 **t 이전** 12개 관측만 쓴다(전방 미사용).
##      Ret_1m[t] 은 t->t+1 수익이므로 t-12..t-1 의 Ret_1m 은 t 시점 기지 정보.
setorder(RET, Ticker, Date)
sk <- function(v) { v <- v[is.finite(v)]; s <- sd(v)
  if (length(v) < 8L || !is.finite(s) || s <= 0) return(NA_real_)
  mean((v - mean(v))^3) / s^3 }
LAG <- RET[, {
  n <- .N; out_sk <- rep(NA_real_, n); out_sd <- rep(NA_real_, n)
  if (n >= 13L) for (i in 13:n) {
    w <- Ret_1m[(i - 12):(i - 1)]
    out_sk[i] <- sk(w); out_sd[i] <- sd(w[is.finite(w)])
  }
  .(Date = Date, lag_skew12 = out_sk, lag_sd12 = out_sd)
}, by = Ticker]
C5 <- merge(S[, .(Date, Ticker, win_vol, log_size)], LAG, by = c("Date", "Ticker"), all.x = TRUE)
J$A3_coverage <- list(n_rows = nrow(C5),
                      n_lag_skew_finite = sum(is.finite(C5$lag_skew12)),
                      n_lag_sd_finite = sum(is.finite(C5$lag_sd12)),
                      note = "결측행은 계약이 직교화에서 제외한다(control_spec$n_rows_after 로 기록됨). 결측을 0 으로 위장하지 않는다.")
J$A3_add_lagged_skew_vol <- go(SCORES, C5,
  c("win_vol", "log_size", "lag_skew12", "lag_sd12"), "rank", "NP2_adv_lagskew")
cat("[A3] done\n")

## ── A4. 이미 관측된 분할(2015-07-01) 재현 — 대조 전용 ────────────────────────
J$A4_seen_split_20150701_rank <- go(SCORES, S[, .(Date, Ticker, win_vol, log_size)],
  c("win_vol", "log_size"), "rank", "NP2_adv_seensplit",
  windows = list(early = as.Date(c("2000-01-01", "2015-07-01")),
                 late  = as.Date(c("2015-07-01", "2026-06-01"))))
J$A4_note <- "이 분할의 raw 결과는 본 라운드 착수 전에 이미 관측됐다(PREREG_NP2 §contamination_disclosure). 신규 증거 아님 — 분할점 민감도 대조로만 읽는다."
cat("[A4] done\n")

dt_assert_no_capital_fields(J, "NP2 adversarial")
write_json(J, file.path(OUT, "np2_adversarial.json"),
           auto_unbox = TRUE, pretty = TRUE, digits = NA, na = "null", null = "null")

for (k in c("A1_raw_plus_rank_4axis", "A2_permutation_placebo",
            "A3_add_lagged_skew_vol", "A4_seen_split_20150701_rank")) {
  z <- J[[k]]; cat("\n==", k, "| verdict", z$verdict, "\n")
  for (wn in names(z$orth_nw_t))
    cat("  ", wn, ":", paste(sprintf("%s=%.2f", AX, unlist(z$orth_nw_t[[wn]])), collapse = "  "), "\n")
  cat("   any:", paste(z$survived_any, collapse = ", "), "\n")
  cat("   all:", paste(z$survived_all, collapse = ", "), "\n")
}
cat("\n[done]\n")
