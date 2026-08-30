# run_09_chain_performance.R — ★소비 경로 전체로 재측정 (도훈 지적 2026-08-30)
#
# ── 왜 다시 재는가 ───────────────────────────────────────────────────────────
# run_08 은 BOCPD 발화월에 현금 8%(Case D)를 직접 얹어 쟀다. **그건 이 팔이 실제로 하는
# 일이 아니다.** 도훈 지적: "M4에 포함시켜서 테스트 해봐야하는거 아냐?"
#
# 실제 전파 경로:
#   BOCPD 발화 → m4_scalar 1.00 → 0.92(Case D) 또는 0.80(Case C)
#              → m4_fires = (m4_scalar < 0.999) = 1
#              → **AE 도 발화 중이면** 게이트 1.00 → 0.70      ← 실제 용량 30%
#              → invested = 게이트 × β_R05 → 현금 = 1 - invested
# 즉 팔의 국소 효과(8%)가 아니라 **게이트 계단(30%)** 이 진짜 용량이고, AE 발화가
# 그 전달을 조건짓는다. run_08 은 이 전달을 태우지 않아 용량을 3.75배 과소평가했다.
#
# ── 설계 ─────────────────────────────────────────────────────────────────────
# 세 판을 같은 체인에 태워 비교한다(문턱·용량 전부 기존 코드값, 스윕 없음):
#   ① 현행           BOCPD 미발화 (MODE=off) — 실제 배포 상태
#   ② 월간 BOCPD 켬  mass_m >= 0.60 (가드 정정판: warm-up = 관측 개월수)
#   ③ 일별 BOCPD 켬  mass_d >= 0.60 (일별 재구성판, 재현검사 통과)
# decay 팔은 세 판 모두 동일하게 살려 둔다 — BOCPD 만의 기여를 보려면 나머지가 같아야 한다.
#
# 실행: Rscript --no-save 04_Research/method_frontier/bocpd_direction_repair/run_09_chain_performance.R

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

# ── 입력 ─────────────────────────────────────────────────────────────────────
p <- as.data.table(read_parquet(
  "qepm/mailbox/worktask/WT-D20260430_001/stage_artifacts/alpha_scores.parquet"))
p[, Date := as.Date(Date)]; p <- unique(p, by = "Date")[order(Date)]

D <- as.data.table(read_parquet(file.path(OUT, "daily_bocpd.parquet")))
D[, Date := as.Date(Date)]
mon <- D[, .(mass_d = last(mass_d)), by = period_end][order(period_end)]
mon[, mass_d_lag := shift(mass_d)]

ae <- as.data.table(read_parquet("stage_artifacts/WT_D20260718_007/ae_regime_signal_ext.parquet"))
ae[, decision_date := as.Date(decision_date)]

prl <- fread("qepm/mailbox/worktask/WT-H20260513_001/output/period_returns_layer5.csv")
prl[, anchor_date := as.Date(anchor_date)]

# ── 체인 조립 ────────────────────────────────────────────────────────────────
J <- merge(p[, .(period_end = Date, ret = ret_net, cash = Cash_Pct_lag,
                 mass_m = bocpd_short_run_mass_lag,
                 decay = decay_signal, decayR2 = decay_R2)],
           mon[, .(period_end, mass_d_lag)], by = "period_end", all.x = TRUE)
# ★연-월로 조인한다 — 날짜 형식이 다르다(실측 2026-08-30):
#   AE decision_date = 월 **1일**(2026-09-01) / m4 패널 Date = 월 **첫 거래일**(2026-05-04).
#   정확 일치로 붙이면 271개월 중 155개월이 비고, 그 달들은 ae_fire=0 으로 강제돼
#   **BOCPD 발화가 게이트로 전달되지 못한다**. 즉 조인 결함이 "효과 없음"을 만들어낸다.
#   진단 줄(AE 결측 N)이 이것을 드러냈다 — 결측 수를 찍지 않았으면 못 봤다.
J[, ym := format(period_end, "%Y-%m")]
ae[, ym := format(decision_date, "%Y-%m")]
prl[, ym := format(anchor_date, "%Y-%m")]
J <- merge(J, unique(ae[, .(ym, ae_fire = fire_seq)], by = "ym"), by = "ym", all.x = TRUE)
J <- merge(J, unique(prl[, .(ym, regime, beta = beta_R05_V5)], by = "ym"),
           by = "ym", all.x = TRUE)
J <- J[!is.na(ret)][order(period_end)]
J[, obs := seq_len(.N)]
cat(sprintf("[chain] %d개월 · beta 결측 %d · AE 결측 %d\n",
            nrow(J), sum(is.na(J$beta)), sum(is.na(J$ae_fire))))
# 결측 처리: β 결측 = 1.0(개입 없음) · AE 결측 = 0(전달 안 됨 — 보수적)
J[is.na(beta), beta := 1.0]
J[is.na(ae_fire), ae_fire := 0L]

WARM <- 12L; TH <- 0.60
# decay 팔 (세 판 공통)
J[, decay_strong := as.integer(decay >= 0.7 & decayR2 >= 0.05)]
J[is.na(decay_strong), decay_strong := 0L]
J[, baseline_cash := fifelse(is.na(cash), 0, cash)]

# m4_scalar 재구성: baseline 우선, clean 인 달에만 팔이 개입
mk_m4 <- function(bocpd_fire) {
  bw <- 1 - J$baseline_cash
  ov <- (J$baseline_cash == 0) & (J$decay_strong == 1L | bocpd_fire == 1L)
  fifelse(ov, 0.92, bw)                     # Case D (기존 코드값)
}
f_none <- rep(0L, nrow(J))
f_mon  <- as.integer(!is.na(J$mass_m)     & J$mass_m     >= TH & J$obs > WARM)
f_day  <- as.integer(!is.na(J$mass_d_lag) & J$mass_d_lag >= TH & J$obs > WARM)

chain_ret <- function(bocpd_fire, label) {
  m4 <- mk_m4(bocpd_fire)
  m4_fires <- as.integer(m4 < 0.999)
  gate <- fifelse(m4_fires == 1L & J$ae_fire == 1L, 0.70, 1.00)
  invested <- gate * J$beta
  list(label = label, r = invested * J$ret, invested = invested,
       n_bocpd = sum(bocpd_fire), n_gate = sum(gate < 1))
}
runs <- list(chain_ret(f_none, "① 현행 (BOCPD off)"),
             chain_ret(f_mon,  "② 월간 BOCPD 켬"),
             chain_ret(f_day,  "③ 일별 BOCPD 켬"))

perf <- function(r, label, extra) {
  nav <- cumprod(1 + r); n <- length(r); yrs <- n / 12
  cagr <- nav[n]^(1 / yrs) - 1
  dd <- nav / cummax(nav) - 1
  data.table(판 = label, CAGR = cagr, MDD = min(dd), Calmar = cagr / abs(min(dd)),
             SR = mean(r) / sd(r) * sqrt(12),
             최악10 = mean(sort(r)[1:round(n * 0.10)]), NAV = nav[n],
             BOCPD발화 = extra$n_bocpd, 게이트발화 = extra$n_gate)
}
res <- rbindlist(lapply(runs, function(z) perf(z$r, z$label, z)))

cat(sprintf("\n=== 소비 경로 전체 성과 (n=%d, %s ~ %s) ===\n",
            nrow(J), min(J$period_end), max(J$period_end)))
print(res[, .(판, BOCPD발화, 게이트발화,
              CAGR = sprintf("%.2f%%", CAGR * 100), MDD = sprintf("%.2f%%", MDD * 100),
              Calmar = round(Calmar, 4), SR = round(SR, 4),
              최악10 = sprintf("%.2f%%", 최악10 * 100), NAV = round(NAV, 1))])

cat("\n=== 현행 대비 변화 ===\n")
for (i in 2:3)
  cat(sprintf("  %s → Calmar %+.4f · SR %+.4f · CAGR %+.2f%%p · MDD %+.2f%%p · 최악10 %+.2f%%p · NAV %+.1f%%\n",
              res$판[i], res$Calmar[i] - res$Calmar[1], res$SR[i] - res$SR[1],
              (res$CAGR[i] - res$CAGR[1]) * 100, (res$MDD[i] - res$MDD[1]) * 100,
              (res$최악10[i] - res$최악10[1]) * 100,
              (res$NAV[i] / res$NAV[1] - 1) * 100))

# BOCPD 발화가 실제로 게이트까지 전달된 달 (AE 동시발화 조건)
for (i in 2:3) {
  f <- if (i == 2) f_mon else f_day
  deliv <- sum(f == 1L & J$ae_fire == 1L & J$baseline_cash == 0)
  cat(sprintf("  %s: BOCPD %d발화 중 게이트까지 전달 %d달 (AE 동시발화 조건)\n",
              res$판[i], sum(f), deliv))
}
fwrite(res, file.path(OUT, "chain_performance.csv"))
cat(sprintf("\n[out] %s/chain_performance.csv\n", OUT))
