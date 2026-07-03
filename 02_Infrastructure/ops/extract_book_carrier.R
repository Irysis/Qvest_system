#!/usr/bin/env Rscript
# extract_book_carrier.R — 현 book(PG2 admitted 전략)의 *faithful per-stock 캐리어*를 1회 추출·캐시 (도훈 mandate 2026-06-18, carrier-fix).
#
# 왜 재작성됐나(2026-06-18): v1 캐리어는 alpha_scores$Ret_1m(trailing/contemporaneous 컬럼)을 종목수익으로 썼는데,
#   실증 결과 전략 실현수익을 재현 못 함(top20 EW CAGR 15.6% vs 진실 ret_orig 48.9%, cor 0.12). Production 패널도 동일 Ret_1m이라 무효.
#   전략 run_all.R(353-373)은 종목수익을 RAWDATA forward 복리 prod(1+Ret)-1 over (start_d,end_d]로 산출 → 본 추출기가 그 엔진을 그대로 복제.
# 산출: 월별 *실제 보유종목 + 전략 tilt weight + forward 실현수익* → 06_Registry/book_carrier/. H1 가중 A/B가 선택을 고정하고 가중만 바꾼다.
# 자가검증: Σ(weight_strategy × ret_fwd)가 전략 03_period_returns.csv ret_gross를 재현하는지 join 대조(통과 = faithful).
# ★PG2 변경 시: book_carrier_sources.json에 새 전략 매핑 추가/갱신 후 재실행. (book_state가 새 admitted를 가리키면 자동 추종.)
# 단일스레드 권장(arrow segfault 회피): OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 ARROW_NUM_THREADS=1.
suppressMessages({ library(data.table); library(arrow); library(jsonlite) })
`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0 && !all(is.na(a))) a else b
root <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
if (dir.exists(root)) setwd(root)

# 전략 production 가중 함수(verbatim) — linear_tilt_qd / linear_tilt_to_penalty_qd / normalize_long_only
source("02_Infrastructure/portfolio/strategy_tilt_weights.R")

# 1) book_state → admitted 전략
bs <- fromJSON("qepm/mailbox/governor/book_state.json", simplifyVector = TRUE)
admitted <- as.character(bs$admitted_ids)[1]
if (is.na(admitted) || !nzchar(admitted)) stop("[carrier] book_state admitted_ids 비어있음")
cat(sprintf("[carrier] admitted strategy = %s\n", admitted))

# 2) config 매핑 (PG2 변경 시 갱신 지점) — alpha_scores + 엔진 파라미터
cfg <- fromJSON("02_Infrastructure/config/book_carrier_sources.json", simplifyVector = FALSE)
src <- cfg[[admitted]]
if (is.null(src)) stop(sprintf("[carrier] book_carrier_sources.json에 '%s' 매핑 없음 — PG2 변경 시 추가 요.", admitted))
asp   <- src$alpha_scores
scol  <- src$score_col %||% "score_eff"
topn  <- as.integer(src$top_n %||% 20L)
minn  <- as.integer(src$min_names %||% 15L)
liq   <- as.numeric(src$liq_threshold %||% 2e8)
lam   <- as.numeric(src$lambda %||% 1.5)
phi   <- as.numeric(src$tophi %||% 3.0)
ub    <- as.numeric(src$ub_weight %||% 0.20)
ubcr  <- as.numeric(src$ub_weight_crisis %||% 0.10)
cbps  <- as.numeric(src$commission_bps %||% 15)
rawp  <- src$rawdata %||% ".cache/rawdata.parquet"
valp  <- src$validation_period_returns %||% NA_character_   # 03_period_returns.csv (있으면 자가검증)
stopifnot("[carrier] alpha_scores 없음" = file.exists(asp), "[carrier] rawdata 없음" = file.exists(rawp))

# 3) 입력 로드 (run_all.R [4]와 동일)
alpha_scores <- as.data.table(read_parquet(asp)); setkey(alpha_scores, Date, Ticker)
if (!all(c(scol, "regime_state") %in% names(alpha_scores))) stop("[carrier] score_eff/regime_state 컬럼 누락")
raw <- as.data.table(read_parquet(rawp, col_select = c("Date","Ticker","Close","Vol","Ret"))); setkey(raw, Date, Ticker)
raw[, TradingAmt := Close * Vol]
sig_dates <- sort(unique(alpha_scores[!is.na(get(scol)), Date]))
cat(sprintf("[carrier] alpha_scores %s rows | sig_dates=%d (%s~%s) | raw %s rows\n",
            format(nrow(alpha_scores), big.mark=","), length(sig_dates),
            as.character(min(sig_dates)), as.character(max(sig_dates)), format(nrow(raw), big.mark=",")))

# 4) walk-forward 복제 (run_all.R 285-405 verbatim 로직 — 종목수익 = RAWDATA forward 복리)
rows <- vector("list", length(sig_dates) - 1L)   # per-stock 보유 행
mret <- vector("list", length(sig_dates) - 1L)   # per-month recon 포트수익
w_prev <- NULL
for (i in seq_len(length(sig_dates) - 1L)) {
  sig_label <- sig_dates[i]; next_sig <- sig_dates[i + 1L]
  start_d <- min(raw[Date >= sig_label]$Date)
  if (length(start_d) == 0L || is.na(start_d) || is.infinite(start_d)) next
  end_d <- { nxt <- min(raw[Date >= next_sig]$Date); if (length(nxt)==0L || is.na(nxt) || is.infinite(nxt)) max(raw$Date) else nxt }

  panel_t <- alpha_scores[Date == sig_label & !is.na(get(scol))]
  if (nrow(panel_t) == 0L) next
  regime_i <- panel_t$regime_state[1L]
  setorder(panel_t, -score_eff)
  N_elig <- nrow(panel_t); N_tgt <- min(topn, N_elig)
  if (N_tgt < minn && N_elig >= minn) N_tgt <- minn
  if (N_tgt < 5L) next
  picks <- panel_t[seq_len(N_tgt)]
  alpha_t <- setNames(picks$score_eff, picks$Ticker)

  # 유동성 필터 PIT (t-30..t-1)
  liq_data <- raw[Date >= (start_d - 30L) & Date < start_d, .(ADV = mean(TradingAmt, na.rm=TRUE)), by = Ticker]
  liquid <- liq_data[ADV >= liq, Ticker]
  tk_liq <- intersect(names(alpha_t), liquid)
  if (length(tk_liq) < 5L) tk_liq <- names(alpha_t)   # fallback
  alpha_liq <- alpha_t[tk_liq]
  if (is.null(names(alpha_liq)) || length(alpha_liq) < 5L) next

  ub_use <- if (identical(regime_i, "CRISIS")) min(ub, ubcr) else ub
  w_raw <- tryCatch(
    linear_tilt_to_penalty_qd(alpha_liq, lambda = lam, w_prev = w_prev, phi = phi, lb = 0, ub = ub_use),
    error = function(e) linear_tilt_qd(alpha_liq, lambda = lam, lb = 0, ub = ub_use))
  names(w_raw) <- names(alpha_liq)
  w_risk <- normalize_long_only(w_raw, lb = 0, ub = ub_use, target_sum = 1)   # cash=0 (M4 outer)

  # forward 종목수익 (C2: > start_d, <= end_d) — prod(1+Ret)-1
  pd <- raw[Date > start_d & Date <= end_d, .(Date, Ticker, Ret)]
  sret <- pd[, .(ret_fwd = prod(1 + Ret, na.rm = TRUE) - 1), by = Ticker]
  held <- data.table(Ticker = names(w_risk), weight_strategy = as.numeric(w_risk), score = as.numeric(alpha_liq[names(w_risk)]))
  held <- merge(held, sret, by = "Ticker", all.x = TRUE)
  held[is.na(ret_fwd), ret_fwd := 0]
  held[, `:=`(decision_date = sig_label, eval_date = end_d, regime = regime_i)]
  setorder(held, -score); held[, rank := seq_len(.N)]
  rows[[i]] <- held[, .(decision_date, eval_date, regime, Ticker, score, weight_strategy, ret_fwd, rank, selected = TRUE)]
  mret[[i]] <- data.table(eval_date = end_d, decision_date = sig_label, regime = regime_i,
                          n_held = nrow(held), port_ret_gross_recon = sum(held$weight_strategy * held$ret_fwd))
  w_prev <- setNames(as.numeric(w_risk), names(w_risk))
}
P <- rbindlist(rows, use.names = TRUE, fill = TRUE)
M <- rbindlist(mret, use.names = TRUE, fill = TRUE); setorder(M, eval_date)
if (nrow(P) == 0L) stop("[carrier] 추출 행 0 — 입력/로직 점검")

# 5) 자가검증 — recon vs 전략 03_period_returns.csv ret_gross
val <- NULL
if (!is.na(valp) && file.exists(valp)) {
  pr <- fread(valp); pr[, eval_date := as.Date(date)]
  val <- merge(M[, .(eval_date, port_ret_gross_recon)], pr[, .(eval_date, ret_gross = as.numeric(ret_gross))], by = "eval_date")
  if (nrow(val) >= 5) {
    val[, diff := port_ret_gross_recon - ret_gross]
    mdd <- function(r){ cum <- cumprod(1+r); min(cum/cummax(cum)-1, na.rm=TRUE) }
    sr_recon <- mean(M$port_ret_gross_recon)/sd(M$port_ret_gross_recon)*sqrt(12)
    cagr_recon <- (prod(1+M$port_ret_gross_recon)^(12/nrow(M))-1)*100
    cat(sprintf("\n[carrier:VALIDATE] aligned=%d | cor=%.5f | max|diff|=%.2e | mean|diff|=%.2e\n",
                nrow(val), cor(val$port_ret_gross_recon, val$ret_gross), max(abs(val$diff)), mean(abs(val$diff))))
    cat(sprintf("[carrier:VALIDATE] recon gross SR=%.3f CAGR=%.2f%% MDD=%.1f%% (목표 L1 base ≈ SR1.66/CAGR44/MDD40.7)\n",
                sr_recon, cagr_recon, mdd(M$port_ret_gross_recon)*100))
    pass <- max(abs(val$diff)) < 1e-4
    cat(sprintf("[carrier:VALIDATE] FAITHFUL=%s (max|diff| < 1e-4 기준)\n", pass))
  }
}

# 6) 저장 (CSV=엑셀 readable + parquet=하니스용 + meta + validation)
outdir <- "06_Registry/book_carrier"; dir.create(outdir, recursive = TRUE, showWarnings = FALSE)
safe_id <- gsub("[^A-Za-z0-9_]+", "_", admitted)
csv_path <- file.path(outdir, sprintf("carrier_%s.csv", safe_id))
pq_path  <- file.path(outdir, sprintf("carrier_%s.parquet", safe_id))
fwrite(P, csv_path); write_parquet(P, pq_path)
fwrite(M, file.path(outdir, sprintf("carrier_%s_monthly.csv", safe_id)))
if (!is.null(val)) fwrite(val, file.path(outdir, sprintf("carrier_%s_validation.csv", safe_id)))
meta <- list(
  strategy = admitted, source_alpha_scores = asp, rawdata = rawp, score_col = scol,
  engine = "run_all.R 285-405 verbatim (top_n by score → liq PIT t-30..t-1 → linear_tilt_to_penalty_qd → forward prod(1+Ret)-1)",
  params = list(top_n = topn, min_names = minn, liq_threshold = liq, lambda = lam, tophi = phi,
                ub_weight = ub, ub_weight_crisis = ubcr, commission_bps = cbps, cash = "0 (M4 outer)"),
  n_months = length(unique(P$decision_date)), n_rows_held = nrow(P),
  date_min = as.character(min(P$decision_date)), date_max = as.character(max(P$decision_date)),
  return_source = "RAWDATA forward 복리 (ret_fwd) — alpha_scores$Ret_1m 폐기",
  validated_against = valp %||% NA, book_state_updated_at = bs$updated_at %||% NA,
  csv = csv_path, parquet = pq_path, note = "PG2 변경 시 book_carrier_sources.json 갱신 후 재실행. 하니스는 parquet(ret_fwd,weight_strategy)을 읽는다."
)
write(toJSON(meta, pretty = TRUE, auto_unbox = TRUE, na = "null"), file.path(outdir, "carrier_meta.json"))
cat(sprintf("\n[carrier] saved: %d months, %d held rows → %s (+csv,+monthly,+validation,+meta)\n",
            meta$n_months, nrow(P), pq_path))
