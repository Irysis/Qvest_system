# FQ-236 Lane D — 차단 관문 1: 결과량 3계열 sd 직접 재산출 + 필요효과 갱신
# 계약: 02_Infrastructure/contracts/required_effect_size.R (nw = 계열 실측 우선)
suppressMessages({library(data.table)})
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
OUT  <- file.path(ROOT, "stage_artifacts", "WT-D20260822_001")

source(file.path(ROOT, "02_Infrastructure/contracts/backtest_result_contract.R"))  # .nw_t_mean
source(file.path(ROOT, "02_Infrastructure/contracts/required_effect_size.R"))

stopifnot(exists(".nw_t_mean"))

read_panel <- function(tag) {
  d <- fread(file.path(OUT, sprintf("outcome_panel_%s.csv", tag)))
  d[, ym_d := as.Date(paste0(ym, "-01"))]
  d[ym_d <= as.Date("2026-07-01")]            # 진행월(2026-08) 제외
}

u <- read_panel("union_liq2e8")
k <- read_panel("k200_liq2e8")

windows <- list(
  list(tag = "UNION_mandated_backfilled", d = u[ym_d >= as.Date("2010-02-01")],
       note = "K200 U KQ150 — KQ150 플래그 최초 2010-01-29. 2015-07 이전은 지수 소급 재구성(백필) 구간"),
  list(tag = "UNION_realtime_only",       d = u[ym_d >= as.Date("2015-07-01")],
       note = "KOSDAQ150 실시간 산출 개시(2015-07) 이후만 — 백필 look-ahead 우려 원천 제거"),
  list(tag = "K200_only_extension",       d = k[ym_d >= as.Date("1998-02-01")],
       note = "★mandate 유니버스 아님(진단 전용) — 길이 확장 축. KOSDAQ150 미포함이므로 다른 유니버스의 다른 양")
)

rows <- list()
for (w in windows) {
  d <- w$d
  for (v in c("Y1a", "Y1b", "Y2")) {
    x <- d[[v]]; x <- x[is.finite(x)]
    n <- length(x)
    if (n < 24) next
    nw_m <- nw_inflation_measured(x, lag = 3L)
    re <- required_effect(n = n, t_threshold = 2.0, sd_monthly = stats::sd(x),
                          design = "full", series = x)
    ac1 <- stats::acf(x, lag.max = 1, plot = FALSE)$acf[2]
    rows[[length(rows) + 1]] <- data.table(
      window = w$tag, outcome = v, n_months = n,
      period = paste(format(min(d$ym_d[is.finite(d[[v]])]), "%Y-%m"),
                     format(max(d$ym_d[is.finite(d[[v]])]), "%Y-%m"), sep = ".."),
      mean = mean(x), sd_monthly = stats::sd(x), ar1 = as.numeric(ac1),
      nw_inflation_measured = nw_m,
      nw_inflation_used = re$nw_inflation, nw_source = re$nw_inflation_source,
      required_monthly = re$required_monthly, required_annual = re$required_annual)
  }
}
res <- rbindlist(rows)
res[, `:=`(required_annual_pct = round(required_annual * 100, 3))]
print(res[, .(window, outcome, n_months, period, sd_monthly = round(sd_monthly, 5),
              ar1 = round(ar1, 3), nw = round(nw_inflation_used, 3), nw_source,
              req_mo = round(required_monthly, 5), req_ann_pct = required_annual_pct)],
      nrows = 100)

# 승계 sd 대조 (차수 판단용, nw_inflation=1 강제 — 역산치가 NW 기포함)
inh <- lapply(c(198L, 133L, 342L, 320L), function(n)
  data.table(n = n, sd_inherited = 0.0669,
             req_ann_pct = round(required_effect(n, sd_monthly = 0.0669,
                                                 nw_inflation = 1)$required_annual * 100, 3)))
inh <- rbindlist(inh)
cat("\n[승계 sd 0.0669 대조 — nw_inflation=1 (역산 NW 기포함)]\n"); print(inh)

fwrite(res, file.path(OUT, "gate1_required_effect.csv"))
cat("\nWROTE", file.path(OUT, "gate1_required_effect.csv"), "\n")
