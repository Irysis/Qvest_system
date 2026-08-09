#==============================================================================
# b6_rollover_family_scope.R — 롤오버가 SE02 만의 문제인가, 계열 전체인가
#
# b5 확정: eps_1y 는 매년 **4월 첫 영업일**에 live 종목의 95~99.7% 가 동시에
#   바뀌고, 큰 점프의 78.6% 가 상향(중앙 +43%). = FY1 회계연도 롤오버.
#   ⇒ 4/1 을 가로지르는 창의 차분은 개정이 아니라 **기준 회계연도 교체**다.
#
# 그렇다면 내가 "정본 exemplar" 로 삼으려던 C14/C17/M26/M28
#   (revenue_fy1 / op_profit_fy1, sig_date - 63L) 도 같은 오염을 갖는가?
#   63일 창은 4/30 · 5/31 sig 에서 4/1 을 가로지른다.
#   ★exemplar 자체가 오염이면 "계열 정합" 이라는 tie-break 근거가 무너진다.
#
# 그리고 벤더 자체 개정률(eps_chg_1m/3m)은 롤오버를 보정하는가?
#   보정한다면 4월 값이 평월과 다르지 않아야 한다. 보정 안 하면 4월에 튄다.
#   ★이 답이 수리 설계를 가른다(자체 계산 vs 벤더 컬럼 차용).
#
# 읽기 전용.
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
ROOT <- gsub("\\\\", "/", ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/infra/se02_window_bakeoff_20260810")
CD   <- file.path(ROOT, ".cache/consensus")
TOL  <- 1e-12

rd <- function(m){ h <- as.data.table(read_parquet(file.path(CD, paste0(m,".parquet"))))
  h[, Date := as.Date(Date)]; h <- h[!is.na(get(m)), .(Ticker, Date, value = get(m))]
  setorderv(h, c("Ticker","Date")); h[] }

#==============================================================================
# S1 — 롤오버 지문 스캔: 레벨 계열 전부
#==============================================================================
LEVELS <- c("eps_1y", "revenue_fy1", "op_profit_fy1", "bps_1y", "dps_1y", "target_price")
s1 <- list(); s1b <- list()
for (m in LEVELS) {
  h <- rd(m)
  h[, prev_v := shift(value), by = Ticker]
  h[, chg := !is.na(prev_v) & abs(value - prev_v) > TOL]
  lv <- h[, .(n_live = .N), by = Date]
  cg <- h[chg == TRUE, .(n_chg = .N), by = Date]
  bd <- merge(lv, cg, by = "Date", all.x = TRUE); bd[is.na(n_chg), n_chg := 0L]
  bd[, frac := n_chg/n_live][, mon := substr(format(Date,"%m"),1,2)]
  # 4월 첫 영업일 = 각 연도 4월의 최소 Date
  apr1 <- bd[mon == "04"][, .SD[which.min(Date)], by = .(yr = format(Date,"%Y"))]
  s1[[m]] <- data.table(metric = m,
    n_years            = nrow(apr1),
    apr1_frac_med      = median(apr1$frac),
    apr1_frac_min      = min(apr1$frac),
    other_days_frac_med= median(bd[!(Date %in% apr1$Date), frac]),
    lift               = median(apr1$frac) / max(median(bd[!(Date %in% apr1$Date), frac]), 1e-9))
  ch <- h[chg == TRUE & abs(prev_v) > 1e-8]
  ch[, rel := (value - prev_v)/abs(prev_v)][, mon := substr(format(Date,"%m"),1,2)]
  big <- ch[abs(rel) > 0.20]
  s1b[[m]] <- data.table(metric = m,
    apr_bigjump_frac_pos = big[mon=="04", mean(rel > 0)],
    apr_bigjump_rel_med  = big[mon=="04", median(rel)],
    oth_bigjump_frac_pos = big[mon!="04", mean(rel > 0)],
    oth_bigjump_rel_med  = big[mon!="04", median(rel)])
}
S1 <- rbindlist(s1); S1B <- rbindlist(s1b)
cat("== S1 4월 첫 영업일 동시 변경률 (롤오버 지문) ==\n"); print(S1)
cat("\n== S1b 4월 큰 점프의 방향 (롤오버면 상향 편향) ==\n"); print(S1B)
fwrite(S1, file.path(OUT, "b6_s1_rollover_fingerprint.csv"))
fwrite(S1B, file.path(OUT, "b6_s1b_bigjump_direction.csv"))

#==============================================================================
# S2 — 벤더 자체 개정률(eps_chg_1m/3m)은 롤오버를 보정하는가
#      보정 O: 4월 중앙값이 평월과 유사. 보정 X: 4월에 +43% 급 튐.
#==============================================================================
s2 <- list()
for (m in c("eps_chg_1m", "eps_chg_3m")) {
  h <- rd(m); h[, mon := substr(format(Date,"%m"),1,2)]
  s2[[m]] <- h[, .(metric = m, n = .N, med = median(value),
                   p90 = as.numeric(quantile(value,.90)),
                   frac_pos = mean(value > 0)), by = mon][order(mon)]
}
S2 <- rbindlist(s2)
cat("\n== S2 벤더 자체 개정률의 월별 분포 (4월이 튀면 벤더도 미보정) ==\n")
print(S2[metric == "eps_chg_1m"])
print(S2[metric == "eps_chg_3m"])
fwrite(S2, file.path(OUT, "b6_s2_vendor_by_month.csv"))

#==============================================================================
# S3 — 63일 창이 4/1 을 가로지르는 sig 월 (exemplar 오염 범위 산정)
#==============================================================================
me <- function(y, m) (if(m==12L) as.Date(sprintf("%d-01-01",y+1L))
                      else as.Date(sprintf("%d-%02d-01",y,m+1L))) - 1L
rows <- list()
for (L in c(21L, 35L, 63L, 91L, 126L, 252L)) {
  hit <- 0L; det <- c()
  for (m in 1:12) {
    sig <- me(2024L, m); lo <- sig - L
    # 창 [lo, sig] 안에 어떤 연도의 4월 1일이 들어오는가
    aprs <- as.Date(sprintf("%d-04-01", 2022:2025))
    if (any(aprs > lo & aprs <= sig)) { hit <- hit + 1L; det <- c(det, sprintf("%02d", m)) }
  }
  rows[[length(rows)+1L]] <- data.table(lag_days = L, n_sig_months_spanning_apr1 = hit,
                                        months = paste(det, collapse = ","))
}
S3 <- rbindlist(rows)
cat("\n== S3 창이 4/1 롤오버를 가로지르는 sig 월수 (2024 역년 기준) ==\n"); print(S3)
fwrite(S3, file.path(OUT, "b6_s3_contaminated_months.csv"))

cat("\n[b6 완료]\n")
