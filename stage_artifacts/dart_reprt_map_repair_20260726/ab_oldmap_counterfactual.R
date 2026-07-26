#==============================================================================
# ab_oldmap_counterfactual.R — 동일 raw 로 구 매핑 재현 (교란 제거 A/B)
#
# 왜: 수리 전 산출물(.cache/… 17:14)은 **구 raw**(20:27 FY2025 백필 이전)로
#     만들어졌다. 행수 차이를 매핑 효과로 귀속하면 오귀속이다.
#     → 같은 현재 raw 로 구 매핑을 재현해 매핑 단독 효과만 분리한다.
#
# 추가 정합 검사: TTM(q4) Revenue == 사업보고서(11011) 연간 Revenue 인가.
#   올바른 매핑이면 개별분기 Q1+Q2+Q3+Q4 = 연간 → 항등식이 성립해야 한다.
#   구 매핑은 누적기간이 엉킨 상계라 성립하지 않는다.
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow) })

ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(ROOT)
source(file.path(ROOT, "02_Infrastructure", "config.R"))
source(file.path(ROOT, "02_Infrastructure", "data", "data_collector_dart.R"))
source(file.path(ROOT, "02_Infrastructure", "data", "data_collector_dart_quarterly.R"))

OUTDIR <- file.path(ROOT, "stage_artifacts", "dart_reprt_map_repair_20260726")

raw <- as.data.table(read_parquet(DART_QUARTERLY_RAW, mmap = FALSE))

run_with_map <- function(map_dt, label) {
  assign("REPRT_MAP", map_dt, envir = globalenv())
  p <- dart_parse_quarterly(copy(raw))
  ind <- dart_extract_individual_quarters(p)
  cat(sprintf("[%s] parsed=%d individual=%d\n", label, nrow(p), nrow(ind)))
  ind
}

MAP_NEW <- data.table(reprt_code = c("11013","11012","11014","11011"),
                      quarter = c(1L,2L,3L,4L), label = c("1Q","반기","3Q","사업보고서"))
MAP_OLD <- data.table(reprt_code = c("11014","11012","11013","11011"),
                      quarter = c(1L,2L,3L,4L), label = c("1Q","반기","3Q","사업보고서"))

ind_new <- run_with_map(MAP_NEW, "NEW")
ind_old <- run_with_map(MAP_OLD, "OLD")

# ── 정합 검사: 개별분기 4개 합 == 연간(11011 thstrm) ──────────────────────────
# 연간 Revenue 원본 (11011 의 파싱값 = 연간 누적)
assign("REPRT_MAP", MAP_NEW, envir = globalenv())
parsed_all <- dart_parse_quarterly(copy(raw))
annual <- parsed_all[reprt_code == "11011", .(Ticker, bsns_year, Rev_annual = Revenue)]

check_identity <- function(ind, label) {
  s <- ind[, .(Rev_sum4 = sum(Revenue, na.rm = TRUE), nq = sum(!is.na(Revenue))),
           by = .(Ticker, bsns_year)][nq == 4L]
  m <- merge(s, annual, by = c("Ticker", "bsns_year"))
  m <- m[is.finite(Rev_annual) & Rev_annual > 0]
  m[, relerr := abs(Rev_sum4 - Rev_annual) / Rev_annual]
  hit <- mean(m$relerr < 1e-6)
  cat(sprintf("[%s] 항등식 Q1+Q2+Q3+Q4 == 연간Revenue : %d/%d = %.1f%% 일치 | 중앙 상대오차 %.4f\n",
              label, sum(m$relerr < 1e-6), nrow(m), hit * 100, median(m$relerr)))
  invisible(m)
}
m_new <- check_identity(ind_new, "NEW")
m_old <- check_identity(ind_old, "OLD")

# ── 음수 flow 비율 (누적차분 오염 지표) ──────────────────────────────────────
neg_rate <- function(ind, label) {
  for (q in 2:4) {
    v <- ind[quarter == q & !is.na(Revenue), Revenue]
    cat(sprintf("[%s] q%d Revenue<0 비율 = %.1f%% (%d/%d)\n",
                label, q, mean(v < 0) * 100, sum(v < 0), length(v)))
  }
}
neg_rate(ind_new, "NEW"); neg_rate(ind_old, "OLD")

# ── Factor_Date vs 실접수일 (개별분기 레벨) ─────────────────────────────────
rc <- unique(raw[!is.na(rcept_no), .(Ticker, bsns_year, reprt_code,
                                     rcept_date = as.Date(substr(rcept_no, 1, 8), "%Y%m%d"))])
rc <- rc[, .(rcept_date = min(rcept_date, na.rm = TRUE)), by = .(Ticker, bsns_year, reprt_code)]

la_report <- function(ind, map_dt, label) {
  x <- merge(ind[, .(Ticker, bsns_year, quarter, Factor_Date)],
             map_dt[, .(reprt_code, quarter)], by = "quarter", allow.cartesian = TRUE)
  x <- merge(x, rc, by = c("Ticker", "bsns_year", "reprt_code"))
  x[, la := as.integer(as.Date(Factor_Date) - rcept_date)]
  out <- x[, .(n = .N, med_la = median(la), la_neg = sum(la < 0),
               pct = round(100 * mean(la < 0), 1)), by = reprt_code][order(reprt_code)]
  cat(sprintf("\n[%s] Factor_Date - 실접수일 (음수=look-ahead)\n", label)); print(out)
  out
}
o_new <- la_report(ind_new, MAP_NEW, "NEW")
o_old <- la_report(ind_old, MAP_OLD, "OLD")

saveRDS(list(new = o_new, old = o_old), file.path(OUTDIR, "ab_lookahead.rds"))
cat("\n[done]\n")
