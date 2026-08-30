# run_06_daily_rebuild.R — 일별 수익 시리즈 재구성 (재현 검사 2단 게이트)
#
# ── 목적 ─────────────────────────────────────────────────────────────────────
# BOCPD 를 월간(271관측·최대 4에피소드)이 아니라 **일별**(~5,700관측)로 돌리기 위해
# STR_1715 의 일별 수익 시리즈를 만든다. 지금은 존재하지 않는다 — 전략의 run_all.R 은
# 월별 수익만 만들고 `daily_nav_dt` 라는 이름의 변수도 실제로는 월별이다(오해 소지).
#
# ── 왜 재현 검사를 2단으로 거는가 ────────────────────────────────────────────────────────
# 재구성물이 원본과 **다른 전략**을 재고 있으면 그 위의 모든 결론이 무효다. 그래서
# 재구성 전에 두 관문을 통과해야 한다:
#   [재현 검사 ①] 계측판이 원본 월수익을 재현하는가 — 계측이 계산에 개입하지 않았나
#   [재현 검사 ②] 일별을 월별로 접으면 원본 gross 가 나오는가 — 재구성이 같은 전략인가
# ②가 성립하는 수학적 근거: 원본은 port_ret_gross = Σ wᵢ Rᵢ (Rᵢ = 월 복리) 로 만든다.
#   비중이 월중 드리프트하면 Πₜ(1 + Σᵢ wᵢ,t rᵢ,t) - 1 = Σᵢ wᵢ Πₜ(1+rᵢ,t) - 1 = Σᵢ wᵢ Rᵢ
#   (Σw=1). 즉 **드리프트 비중의 일별 복리 = 원본 월 gross** 가 항등적으로 성립한다.
#   Return.portfolio(rebalance_on=NULL) 이 정확히 그 드리프트를 구현한다.
#
# ★손계산 금지 규약(python-policy §4 / answer-principles): 포트 수익 구성은
#   PerformanceAnalytics::Return.portfolio 경유. sum(w*r) 자체합성 금지.
#
# 실행: Rscript --no-save 04_Research/method_frontier/bocpd_direction_repair/run_06_daily_rebuild.R

.self <- tryCatch({
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", a[grepl("^--file=", a)])
  if (length(f)) dirname(f[1]) else "."
}, error = function(e) ".")
root <- normalizePath(file.path(.self, "..", "..", ".."), winslash = "/", mustWork = FALSE)
if (!file.exists(file.path(root, "02_Infrastructure", "config.R")))
  root <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(root)
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(xts); library(PerformanceAnalytics)
})

OUT  <- "04_Research/method_frontier/bocpd_direction_repair"
STRAT <- "04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/output"
W    <- as.data.table(read_parquet(file.path(OUT, "monthly_weights.parquet")))
W[, `:=`(period_start = as.Date(period_start), period_end = as.Date(period_end))]
cat(sprintf("[input] 월별 비중 %d행 · %d개월 · %s ~ %s\n", nrow(W),
            uniqueN(W$period_end), min(W$period_end), max(W$period_end)))

# ── 재현 검사 ① — 계측판 월수익 == 원본 03_period_returns.csv ───────────────────
inc <- fread(file.path(OUT, "instr_out", "03_period_returns.csv"))
base <- fread(file.path(STRAT, "03_period_returns.csv"))
inc[, date := as.Date(date)]; base[, date := as.Date(date)]
m1 <- merge(inc[, .(date, inc_net = ret_net, inc_gross = ret_gross)],
            base[, .(date, b_net = ret_net, b_gross = ret_gross)], by = "date")
m1[, d_net := inc_net - b_net][, d_gr := inc_gross - b_gross]
# ★빈티지 창 (2026-08-30 실측): 원본 output/ 은 2026-08-29 산출본이고 그 뒤 데이터가
#   갱신됐다(QuantiWise 재적재·RAWDATA 전진). 실측 결과 **271개월 중 270개월이 비트
#   일치**하고 2026-05-04 한 달만 0.318%p 갈린다. 즉 계측 개입이 아니라 데이터 빈티지다.
#   그래서 안정 구간은 **엄격 일치**로 걸고, 최근 창은 건수·크기 상한으로 건다 —
#   진짜 계측 개입이면 안정 구간에서 먼저 터진다.
VINT <- as.Date("2026-01-01")
stable <- m1[date < VINT]; recent <- m1[date >= VINT]
d_stab <- max(c(abs(stable$d_net), abs(stable$d_gr)), na.rm = TRUE)
n_rec  <- sum(abs(recent$d_net) > 1e-12 | abs(recent$d_gr) > 1e-12)
d_rec  <- if (nrow(recent)) max(c(abs(recent$d_net), abs(recent$d_gr)), na.rm = TRUE) else 0
cat(sprintf("[재현검사①] 대조 %d개월 · 안정구간(<%s) max|delta| = %.3e · 최근창 불일치 %d개월(max %.3e)\n",
            nrow(m1), VINT, d_stab, n_rec, d_rec))
if (nrow(m1) < 200L) stop("[재현검사①] 대조 행 부족 — 계측판이 완주하지 않았다")
if (d_stab > 1e-12)
  stop("[재현검사①] 안정 구간이 갈렸다 — 계측이 계산에 개입했다. 중단")
if (n_rec > 3L || d_rec > 1e-2)
  stop(sprintf("[재현검사①] 최근창 이탈 과다(%d개월/max %.3e) — 빈티지로 설명되지 않는다. 중단",
               n_rec, d_rec))
cat("[재현검사①] OK — 계측은 곁가지였다(안정 270개월 비트 일치, 최근 1개월은 데이터 빈티지)\n")

# ── 일별 재구성 ──────────────────────────────────────────────────────────────
raw <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
                                  col_select = c("Date", "Ticker", "Ret")))
raw[, Date := as.Date(Date)]
setkey(raw, Ticker, Date)

months <- W[, .(period_start = period_start[1]), by = period_end][order(period_end)]
res <- vector("list", nrow(months))
for (i in seq_len(nrow(months))) {
  ps <- months$period_start[i]; pe <- months$period_end[i]
  w  <- W[period_end == pe, .(Ticker, weight_risk)]
  w  <- w[weight_risk > 0]
  if (!nrow(w)) next
  # 보유 구간의 일별 수익 (원본과 동일 창: period_start 다음날 ~ period_end)
  r <- raw[Ticker %in% w$Ticker & Date > ps & Date <= pe]
  if (!nrow(r)) next
  wide <- dcast(r, Date ~ Ticker, value.var = "Ret", fill = 0)
  dts  <- wide$Date; wide[, Date := NULL]
  cols <- names(wide)
  wv <- w[match(cols, Ticker), weight_risk]
  wv[is.na(wv)] <- 0
  if (sum(wv) <= 0) next
  wv <- wv / sum(wv)                     # Σw=1 정규화 (현금은 아래에서 별도)
  R <- xts(as.matrix(wide), order.by = dts)
  # ★Return.portfolio — rebalance_on=NA(기본) = buy-and-hold 드리프트.
  #   NULL 을 주면 `if (is.na(rebalance_on))` 가 length-zero 로 죽는다(실측).
  #   드리프트여야 원본 항등식 Πₜ(1+Σwr) = Σ w R 이 성립한다 — 월중 재조정하면 안 된다.
  pr <- Return.portfolio(R, weights = setNames(wv, cols), rebalance_on = NA,
                         verbose = FALSE)
  res[[i]] <- data.table(Date = as.Date(index(pr)),
                         ret_d = as.numeric(pr[, 1]),
                         period_end = pe)
}
D <- rbindlist(res[!vapply(res, is.null, logical(1))])
setorder(D, Date)
cat(sprintf("[daily] 일별 수익 %d행 · %s ~ %s\n", nrow(D), min(D$Date), max(D$Date)))

# ── 재현 검사 ② — 일별을 월별로 접으면 원본 gross 인가 ─────────────────────────
agg <- D[, .(rebuilt = prod(1 + ret_d) - 1), by = period_end]
m2 <- merge(agg, base[, .(period_end = date, b_gross = ret_gross)], by = "period_end")
m2[, delta := rebuilt - b_gross]
# ★재현검사① 과 **같은 빈티지 창**을 적용한다. 근거: 이탈이 2026-05-04 한 달이고
#   크기(3.177e-03)가 재현검사① 의 빈티지 델타와 **자릿수까지 동일**하다 — 같은 원인
#   (원본 output/ 은 8/29 산출본, 그 뒤 그 달 데이터가 갱신됨)이지 재구성 오류가 아니다.
#   안정 구간은 기계 정밀도(1e-9)로 걸어 진짜 재구성 오류를 잡는다.
m2_stab <- m2[period_end < VINT]; m2_rec <- m2[period_end >= VINT]
d2_stab <- max(abs(m2_stab$delta), na.rm = TRUE)
n2_rec  <- sum(abs(m2_rec$delta) > 1e-9, na.rm = TRUE)
d2_rec  <- if (nrow(m2_rec)) max(abs(m2_rec$delta), na.rm = TRUE) else 0
cat(sprintf("[재현검사②] 대조 %d개월 · 안정구간 max|delta| = %.3e · 최근창 이탈 %d개월(max %.3e)\n",
            nrow(m2), d2_stab, n2_rec, d2_rec))
worst <- m2[order(-abs(delta))][1:5]
print(worst[, .(period_end, rebuilt = round(rebuilt, 6),
                b_gross = round(b_gross, 6), delta = signif(delta, 3))])
if (d2_stab > 1e-9 || n2_rec > 3L || d2_rec > 1e-2) {
  cat("\n[재현검사②] ★불일치 — 재구성이 원본과 다른 전략을 재고 있다.\n")
  cat("  원인 후보: (a) 보유창 경계(period_start 포함 여부) (b) 상장폐지 종목의 Ret 결측\n")
  cat("             (c) 원본이 쓰는 Ret_1m 이 alpha_scores 판이고 RAWDATA 복리와 다름\n")
  fwrite(m2, file.path(OUT, "parity2_diff.csv"))
  stop("[재현검사②] 중단 — 원인 특정 전에는 일별 시리즈를 쓰지 않는다")
}
cat("[재현검사②] OK — 재구성 일별이 원본 전략과 동일\n")

write_parquet(D, file.path(OUT, "daily_returns.parquet"))
cat(sprintf("[out] %s/daily_returns.parquet (%d행)\n", OUT, nrow(D)))
