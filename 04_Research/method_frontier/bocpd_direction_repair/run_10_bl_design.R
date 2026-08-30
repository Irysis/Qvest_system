# run_10_bl_design.R — 설계판(BL 연속 비중) 구현 후 기존 전략과 성과 비교
#
# ── 왜 ───────────────────────────────────────────────────────────────────────
# 도훈 지시(2026-08-30): "구현해서 기존 전략과 비교해보자. 성과가 좋으면 반영하면 되니까."
#
# WT-D20260430_001 설계 문서는 3기둥이었다:
#   A. 위험감지 = 매크로 국면 ∪ BOCPD(전략 자기수익 변화점)
#   B. 알파 감쇠 = Lee 2025 쌍곡 적합
#   C. 동적 배분 = **Black-Litterman** (2자산: 전략 슬리브 vs 현금)
#      prior 0.5/0.5 · view = sigmoid(decay_view x (1 - combined_regime)) · 사후비중 ∈[0,1]
#
# 그런데 구현은 C기둥을 **결정 경로에 연결하지 않았다**. black_litterman_2asset() 이
# 매달 weight_str1715 를 계산하는데(factor_engine.R:396-440) 그 결과는 view_BL
# (posterior_mu_str) 만 보고용으로 저장되고, 실제 비중은 손으로 쓴 3분기 if-else
# 사다리가 정한다(:621-641). combined_regime · conjunction_score · CONJUNCTION_THRESHOLD
# 도 전부 죽은 코드다. 설계 문서를 읽은 사람은 결합 논리가 작동한다고 믿게 된다.
#
# ── 이 라운드 ────────────────────────────────────────────────────────────────
# BL 경로를 **설계대로 살려** m4_scalar 를 만들고, 소비 경로 전체(m4 -> 게이트 -> β_R05)에
# 태워 현행과 비교한다. 파라미터는 전부 **소스에 이미 있는 값**을 그대로 쓴다 — 새로
# 고르지 않는다(스윕 금지).
#
# ★재현 검사: 내가 옮긴 BL 이 원본과 같은 함수인지 먼저 건다. 원본이 저장해 둔
#   view_BL(posterior_mu_str) 을 재현해야 한다(양성 대조). 재현 못 하면 다른 모델이다.
#
# 실행: Rscript --no-save 04_Research/method_frontier/bocpd_direction_repair/run_10_bl_design.R

.self <- tryCatch({
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", a[grepl("^--file=", a)])
  if (length(f)) dirname(f[1]) else "."
}, error = function(e) ".")
root <- normalizePath(file.path(.self, "..", "..", ".."), winslash = "/", mustWork = FALSE)
if (!file.exists(file.path(root, "02_Infrastructure", "config.R")))
  root <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(root)
suppressPackageStartupMessages({ library(data.table); library(arrow) })

OUT <- "04_Research/method_frontier/bocpd_direction_repair"
SRC <- "qepm/mailbox/worktask/WT-D20260430_001/stage_artifacts/factor_engine.R"

# ── 원본에서 BL 함수·상수를 **그대로 추출**(재구현 금지) ─────────────────────
src <- readLines(SRC, warn = FALSE, encoding = "UTF-8")
i0 <- grep("^black_litterman_2asset <- function", src)
ends <- grep("^#===", src); i1 <- min(ends[ends > i0]) - 1L
.g <- function(pat) {
  m <- regmatches(paste(src, collapse = "\n"), regexpr(pat, paste(src, collapse = "\n"), perl = TRUE))
  if (!length(m)) stop(sprintf("상수 추출 실패: %s", pat))
  eval(parse(text = sub("^[A-Za-z_0-9]+ *<- *", "", sub(" *#.*$", "", m))))
}
BL_TAU <- .g("BL_TAU <- [^\n]+"); BL_OMEGA_SCALE <- .g("BL_OMEGA_SCALE <- [^\n]+")
WARMUP_MONTHS <- .g("WARMUP_MONTHS <- [^\n]+")
eval(parse(text = paste(src[i0:i1], collapse = "\n")))
cat(sprintf("[const] BL_TAU=%.4f OMEGA_SCALE=%.2f WARMUP=%d (소스 재도출)\n",
            BL_TAU, BL_OMEGA_SCALE, WARMUP_MONTHS))

# ── 패널 (원본이 저장한 입력·중간값 그대로 사용) ─────────────────────────────
p <- as.data.table(read_parquet(
  "qepm/mailbox/worktask/WT-D20260430_001/stage_artifacts/alpha_scores.parquet"))
p[, Date := as.Date(Date)]; p <- unique(p, by = "Date")[order(Date)]
p <- p[!is.na(ret_net)][order(Date)]; p[, obs := seq_len(.N)]

# ── 재현 검사: BL 을 원본 입력으로 돌려 view_BL 을 재현하는가 ───────────────
bl_run <- function(vs, vc, i) {
  if (i < WARMUP_MONTHS || is.na(vs))
    return(list(weight_str1715 = 1.0, posterior_mu_str = 0.012))
  black_litterman_2asset(prior_mu_str = 0.012, view_str = vs, view_confidence = vc)
}
bl <- lapply(seq_len(nrow(p)), function(i) bl_run(p$view_str[i], p$view_confidence[i], i))
mu_rep <- vapply(bl, function(z) z$posterior_mu_str, numeric(1))
d_mu <- max(abs(mu_rep - p$view_BL), na.rm = TRUE)
cat(sprintf("[재현검사] view_BL 재현 max|delta| = %.3e\n", d_mu))
if (d_mu > 1e-10)
  stop("[재현검사] BL 재현 실패 — 내가 옮긴 것이 원본과 다른 함수다. 중단")
cat("[재현검사] OK — 원본 BL 그대로\n")

w_bl <- vapply(bl, function(z) z$weight_str1715, numeric(1))
cat(sprintf("[BL] 비중 분포: min %.3f q25 %.3f 중앙 %.3f q75 %.3f max %.3f · <0.999 인 달 %d/%d\n",
            min(w_bl), quantile(w_bl, .25), median(w_bl), quantile(w_bl, .75),
            max(w_bl), sum(w_bl < 0.999), length(w_bl)))

# ── 소비 경로 (run_09 과 동일 배선) ──────────────────────────────────────────
D <- as.data.table(read_parquet(file.path(OUT, "daily_bocpd.parquet")))
D[, Date := as.Date(Date)]
mon <- D[, .(mass_d = last(mass_d)), by = period_end][order(period_end)]
mon[, mass_d_lag := shift(mass_d)]
ae <- as.data.table(read_parquet("stage_artifacts/WT_D20260718_007/ae_regime_signal_ext.parquet"))
ae[, ym := format(as.Date(decision_date), "%Y-%m")]
prl <- fread("qepm/mailbox/worktask/WT-H20260513_001/output/period_returns_layer5.csv")
prl[, ym := format(as.Date(anchor_date), "%Y-%m")]

J <- data.table(period_end = p$Date, ym = format(p$Date, "%Y-%m"), ret = p$ret_net,
                cash = p$Cash_Pct_lag, mass_m = p$bocpd_short_run_mass_lag,
                decay = p$decay_signal, decayR2 = p$decay_R2,
                w_impl = p$weight_str1715, w_bl = w_bl, obs = p$obs)
J <- merge(J, mon[, .(period_end, mass_d_lag)], by = "period_end", all.x = TRUE)
J <- merge(J, unique(ae[, .(ym, ae_fire = fire_seq)], by = "ym"), by = "ym", all.x = TRUE)
J <- merge(J, unique(prl[, .(ym, beta = beta_R05_V5)], by = "ym"), by = "ym", all.x = TRUE)
setorder(J, period_end)
J[is.na(beta), beta := 1.0]; J[is.na(ae_fire), ae_fire := 0L]
J[, baseline_cash := fifelse(is.na(cash), 0, cash)]

WARM <- 12L; TH <- 0.60
J[, decay_strong := as.integer(decay >= 0.7 & decayR2 >= 0.05)]
J[is.na(decay_strong), decay_strong := 0L]

mk_ladder <- function(bfire) {
  bw <- 1 - J$baseline_cash
  fifelse((J$baseline_cash == 0) & (J$decay_strong == 1L | bfire == 1L), 0.92, bw)
}
f_none <- rep(0L, nrow(J))
f_mon  <- as.integer(!is.na(J$mass_m)     & J$mass_m     >= TH & J$obs > WARM)
f_day  <- as.integer(!is.na(J$mass_d_lag) & J$mass_d_lag >= TH & J$obs > WARM)

chain <- function(m4, label) {
  m4f <- as.integer(m4 < 0.999)
  gate <- fifelse(m4f == 1L & J$ae_fire == 1L, 0.70, 1.00)
  list(label = label, r = gate * J$beta * J$ret, n_m4 = sum(m4f), n_gate = sum(gate < 1))
}
# ★설계판: BL 사후비중을 m4_scalar 로 쓴다. 단 baseline(매크로) 이 이미 현금을 잡은 달은
#   원 정책대로 baseline 에 양보한다(DEFER) — 그 규칙은 설계·구현 공통이다.
m4_bl <- fifelse(J$baseline_cash > 0, 1 - J$baseline_cash, J$w_bl)

runs <- list(chain(mk_ladder(f_none), "① 현행 (사다리·BOCPD off)"),
             chain(mk_ladder(f_mon),  "② 사다리 + 월간 BOCPD"),
             chain(mk_ladder(f_day),  "③ 사다리 + 일별 BOCPD"),
             chain(m4_bl,             "④ ★설계판 (BL 연속비중)"))

perf <- function(z) {
  r <- z$r; nav <- cumprod(1 + r); n <- length(r)
  cagr <- nav[n]^(12 / n) - 1; dd <- nav / cummax(nav) - 1
  data.table(판 = z$label, m4발화 = z$n_m4, 게이트 = z$n_gate,
             CAGR = cagr, MDD = min(dd), Calmar = cagr / abs(min(dd)),
             SR = mean(r) / sd(r) * sqrt(12),
             최악10 = mean(sort(r)[1:round(n * 0.10)]), NAV = nav[n])
}
res <- rbindlist(lapply(runs, perf))
cat(sprintf("\n=== 소비 경로 전체 성과 (n=%d, %s ~ %s) ===\n",
            nrow(J), min(J$period_end), max(J$period_end)))
print(res[, .(판, m4발화, 게이트, CAGR = sprintf("%.2f%%", CAGR * 100),
              MDD = sprintf("%.2f%%", MDD * 100), Calmar = round(Calmar, 4),
              SR = round(SR, 4), 최악10 = sprintf("%.2f%%", 최악10 * 100),
              NAV = round(NAV, 1))])
cat("\n=== 현행(①) 대비 ===\n")
for (i in 2:nrow(res))
  cat(sprintf("  %s → Calmar %+.4f · SR %+.4f · CAGR %+.2f%%p · MDD %+.2f%%p · 최악10 %+.2f%%p · NAV %+.1f%%\n",
              res$판[i], res$Calmar[i] - res$Calmar[1], res$SR[i] - res$SR[1],
              (res$CAGR[i] - res$CAGR[1]) * 100, (res$MDD[i] - res$MDD[1]) * 100,
              (res$최악10[i] - res$최악10[1]) * 100, (res$NAV[i] / res$NAV[1] - 1) * 100))
fwrite(res, file.path(OUT, "bl_design_performance.csv"))
cat(sprintf("\n[out] %s/bl_design_performance.csv\n", OUT))
