## PR-L2 1차 지표(심층 capture Δ · rf_prereg_paired_boot deep_capture) 귀무 위양성 교정 — 몬테카를로 (계기 교정 · 진단 · 등급 아님)
## ★측정 아님: 전략 산출물을 읽지 않는다. 입력 = 합성 계열 + 공표 KOSPI200 월수익(.cache/benchmark.parquet · 심층 월 조건화).
##   판정 계약 rf_prereg_paired_boot 를 그대로 부른다(B·seed·ci_level = prereg_config 고정값 · 블록 규칙 = 설정 auto).
## 사용: Rscript calib_deep_capture.R <ROOT> <out.csv> <scenario> <rep_from> <rep_to> [delta]
##   scenario: adv_B | real_norm | real_t5het | real_t5het_ar | syn_n520 | syn_n1040 | blk_<b>(real_t5het · 블록 길이 고정 what-if)
##   delta   : 대안(참 Δ<0) 크기 — 없으면 귀무(참 Δ = 0)
suppressMessages({ library(data.table); library(arrow) })
a <- commandArgs(trailingOnly = TRUE)
ROOT <- normalizePath(a[1], winslash = "/", mustWork = TRUE); OUT <- a[2]; SC <- a[3]
R0 <- as.integer(a[4]); R1 <- as.integer(a[5]); DELTA <- if (length(a) >= 6) as.numeric(a[6]) else 0
L <- new.env(parent = globalenv())
invisible(capture.output(sys.source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_prereg.R"), envir = L, keep.source = FALSE)))
cfg <- L$rf_prereg_config(ROOT)
ds <- L$.rfp_src(ROOT, "02_Infrastructure/contracts/defensive_score.R", "ds")
THR <- ds$ds_params(ROOT)$deep_threshold
## 공표 KOSPI200 월수익(달력월 복리 · defensive_score::ds_score 와 같은 월 테이블 식) — 2005-01 ~ 마지막 완결월
bm <- as.data.table(read_parquet(file.path(ROOT, ".cache/benchmark.parquet"), col_select = c("Date", "BM_Ret")))
bm <- bm[Date >= as.Date("2005-01-01") & is.finite(BM_Ret)]
bm[, ym := format(Date, "%Y-%m")]
last_full <- format(max(bm$Date), "%Y-%m")
KM <- bm[ym < last_full, .(k = prod(1 + BM_Ret) - 1), by = ym][order(ym)]
kreal <- KM$k
std_t <- function(n, df) rt(n, df) / sqrt(df / (df - 2))
gen <- function(i) {
  if (SC %in% c("adv_B", "syn_n520", "syn_n1040")) {
    n <- switch(SC, adv_B = 260L, syn_n520 = 520L, syn_n1040 = 1040L)
    set.seed(10000 + i)
    k <- 0.008 + 0.055 * rt(n, 4) / sqrt(2)
    b <- 0.8 * k + rnorm(n, 0.002, 0.025); a0 <- 0.8 * k + rnorm(n, 0.002, 0.025)
    return(list(a = a0 - DELTA * k * (k < 0), b = b, k = k, thr = -0.10))
  }
  set.seed(50000 + i)
  k <- kreal; n <- length(k)
  b <- 0.8 * k + rnorm(n, 0.002, 0.02)
  u <- switch(sub("^blk_[0-9]+$", "real_t5het", SC),
    real_norm = rnorm(n, 0, 0.015),
    real_t5het = 0.015 * (1 + 2 * abs(k - median(k)) / sd(k)) * std_t(n, 5),
    real_t5het_ar = { e <- as.numeric(stats::filter(std_t(n, 5), 0.2, method = "recursive")); 0.015 * (1 + 2 * abs(k - median(k)) / sd(k)) * e / sd(e) })
  list(a = b + u - DELTA * k * (k < 0), b = b, k = k, thr = THR)
}
## 블록 길이 what-if — 계약과 같은 식(원형 블록 · 같은 인덱스 짝지음 · 심층 평균비)을 블록 길이만 고정해 다시 부른다(진단 전용 재현)
blk_boot <- function(a, b, k, thr, bl) {
  f <- function(x, kk) { s <- kk < thr; if (sum(s) < 1L || mean(kk[s]) == 0) NA_real_ else mean(x[s]) / mean(kk[s]) }
  obs <- f(a, k) - f(b, k); n <- length(a)
  set.seed(cfg$bootstrap$seed)
  d <- vapply(seq_len(cfg$bootstrap$B), function(j) { ix <- L$.rfp_cb_idx(n, bl); f(a[ix], k[ix]) - f(b[ix], k[ix]) }, numeric(1))
  ok <- is.finite(d); lev <- cfg$bootstrap$ci_level
  if (!is.finite(obs) || mean(ok) < cfg$bootstrap$min_valid_frac) return(list(value = NA, ci_lo = NA, ci_hi = NA, p_gt0 = NA, block_len = bl, valid_frac = mean(ok)))
  q <- stats::quantile(d[ok], c((1 - lev) / 2, 1 - (1 - lev) / 2), names = FALSE, type = 7)
  list(value = obs, ci_lo = q[1], ci_hi = q[2], p_gt0 = mean(d[ok] > 0), block_len = bl, valid_frac = mean(ok))
}
rows <- vector("list", R1 - R0 + 1L)
for (i in R0:R1) {
  g <- gen(i)
  o <- if (grepl("^blk_", SC)) blk_boot(g$a, g$b, g$k, g$thr, as.integer(sub("^blk_", "", SC)))
       else L$rf_prereg_paired_boot(g$a, g$b, "deep_capture", bench = g$k, deep_threshold = g$thr, root = ROOT, cfg = cfg)
  rows[[i - R0 + 1L]] <- data.table(scenario = SC, delta = DELTA, rep = i, n = length(g$k), n_deep = sum(g$k < g$thr),
                                    value = o$value, ci_lo = o$ci_lo, ci_hi = o$ci_hi, p_gt0 = o$p_gt0,
                                    block_len = o$block_len, valid_frac = o$valid_frac)
}
X <- rbindlist(rows)
fwrite(X, OUT)
cat(sprintf("[calib] %s delta=%g reps %d-%d · n=%d · n_deep=%s · 기록 %s\n", SC, DELTA, R0, R1, X$n[1],
            paste(range(X$n_deep), collapse = "~"), OUT))
