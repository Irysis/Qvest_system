# =============================================================================
# fe_b3_11_kospi_all.R — 규칙기반 고속강화 B3-11 (rulefast 11/20)
#   신호·비중 = RF_B1_5_MomIlliq 완전 동일 (모멘텀 12-1 rankZ 50% + Amihud rankZ 50%,
#   long-only top-25 EW, 월간). 바꾸는 것은 적용 유니버스 하나뿐.
#   K200∪KQ150 멤버십 제약 제거 → 상장 전수(KOSPI 라벨 패널 전체) · adv20>=2e8(t-1) 유지.
# =============================================================================
# 원장: reinforce_ledger_l1.json entry RP_20260829_122020_9192_rulefast, attempt n=11
# 근거 논문 (하드코딩 금지 — 수치 결정 뿌리):
#   - 유니버스 축: Hong, Lim & Stein (2000, JF 55(1)) "Bad News Travels Slowly"
#     https://onlinelibrary.wiley.com/doi/10.1111/0022-1082.00206
#     정보 확산이 느린 소형·저애널리스트커버리지 종목에서 모멘텀이 강하다.
#   - 모멘텀 12-1: Jegadeesh & Titman (1993, JF 48(1))
#     https://www.bauer.uh.edu/rsusmel/phd/jegadeesh-titman93.pdf
#   - 비유동성 프리미엄: Amihud (2002, JFM 5(1))
#     https://www.sciencedirect.com/science/article/pii/S1386418101000246
#
# ===== 유니버스 필터 값 결정 근거 (사전 실측, 2026-08-29 · .cache/rawdata.parquet) =====
#   만다트는 `Market` 열로 KOSPI 를 판별하라 했으나, 실측 분포는 판별력이 없다:
#     · 패널 전체(14,076,135행) Market 값 = {"KOSPI" 10,043,504 / NA 4,032,631}.
#       **"KOSDAQ" 값은 0행** — 시장 구분 라벨이 아니다.
#     · 알려진 코스닥 종목이 모두 "KOSPI" 로 라벨돼 있다(실측 2023-06):
#       A247540 에코프로비엠 · A086520 에코프로 · A091990 셀트리온헬스케어 ·
#       A035760 CJ ENM · A263750 펄어비스 · A293490 카카오게임즈 — 전부 Market="KOSPI",
#       KQ150=1. 즉 Market=="KOSPI" 는 KOSPI 를 고르지 않는다.
#     · NA 는 시장이 아니라 **소스 커버리지 결손**이다: source="quantiwise_update" 행이
#       메타를 못 싣는다. 2026년 월말은 15,250행 전량 NA(= 2026 유니버스 전멸),
#       3,076개 종목이 같은 종목인데 날짜에 따라 NA↔KOSPI 를 오간다(간헐 churn).
#   ⇒ Market=="KOSPI" 리터럴 적용은 (a)코스닥 제외 실패 (b)2026 구간 블랙아웃 주입
#      (c)2% 간헐 churn 주입 — 유니버스 효과가 아니라 라벨 결손을 재는 것이 된다.
#   ⇒ 채택: **멤버십 무제약(상장 전수) + adv20>=2e8(t-1)**. Market 값집합이 {KOSPI, NA}
#      뿐이므로 이것이 "Market 라벨이 표현할 수 있는 최대 유니버스"와 동치이며,
#      라벨 커버리지 결손만 제거한 형태다. 리터럴판 규모는 아래 진단에 병기한다.
#
# ===== C6 생존편향 (급소) =====
#   rawdata 는 상장폐지 종목을 담는다 — 실측: 전체 3,257 종목 중 마지막 관측이
#   2026년 이전인 종목 692개(2005년 종료 53 · 2010년 84 · 2015년 26 · 2020년 24 …).
#   즉 패널은 생존자 스냅샷이 아니다. 다만 멤버십 제약을 풀면 소형주 비중이 커지므로
#   상폐 커버리지의 완전성(특히 정리매매 구간 수익 반영)이 기준선보다 더 민감해진다 —
#   한계로 보고한다.
#
# ===== PIT (C1~C15) =====
#   - C15: Amihud 는 factor DB parquet 직접 load 금지 — load_month_factors() 경유.
#   - C14/C13: Z_Score_Aligned 만 소비. NEGATE/FLIP 없음.
#   - C10: 유동성 필터 adv20 은 t-1 기준 — frollmean(20) 후 shift(1).
#   - C2: 모멘텀 = shift(21)/shift(252) 과거 윈도우만.
#   - C1: rank-Z 는 sig_date 시점 cross-section 내에서만.
#   - C6: 상폐 종목 포함 패널 (위 참조).
# =============================================================================

suppressPackageStartupMessages(library(data.table))
stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
setorder(RAWDATA, Ticker, Date)

local({
  conn <- file.path(Sys.getenv("CLAUDE_PROJECT_DIR",
                               "C:/Users/99922/OneDrive/Quant_Module_Moltbot"),
                    "02_Infrastructure", "factor_db", "factor_db_connector.R")
  if (!exists("load_month_factors", mode = "function")) source(conn)
})

ILLIQ_FACTOR <- "L01_Amihud"   # B1-5 와 동일 — 선택 근거는 B1-5 헤더(방향 전구간 +1)

# ---- 월말(시그널) 그리드 ----
RAWDATA[, .ym := format(Date, "%Y-%m")]
.month_ends <- sort(RAWDATA[, .(Date = max(Date)), by = .ym]$Date)
RAWDATA[, .ym := NULL]
.month_ends <- .month_ends[.month_ends >= as.Date("2004-11-01")]

# ---- 유니버스: 멤버십 무제약(상장 전수) + adv20 >= 2e8 (C10: t-1, shift 1) ----
RAWDATA[, .TV := Close * Vol]
RAWDATA[, .AvgTV20 := shift(frollmean(.TV, 20L, align = "right"), 1L), by = Ticker]
.liq_ok <- RAWDATA[Date %in% .month_ends & is.finite(.AvgTV20) & .AvgTV20 >= 2e8]
.mem <- .liq_ok[, .(Date, Ticker)]
setkey(.mem, Date, Ticker)

# ---- 유니버스 규모 진단 (기준선 대비 배수 · Market 리터럴판 규모 병기) ----
.uni_diag <- .liq_ok[, .(n_wide      = .N,
                         n_idx       = sum((K200 == TRUE | KQ150 == TRUE), na.rm = TRUE),
                         n_mkt_kospi = sum(Market == "KOSPI", na.rm = TRUE),
                         n_mkt_na    = sum(is.na(Market))), by = Date]
RAWDATA[, c(".TV", ".AvgTV20") := NULL]
rm(.liq_ok)

# ---- 모멘텀 12-1 (JT1993): 과거 윈도우만 ----
RAWDATA[, .Mom := shift(Close, 21L) / shift(Close, 252L) - 1, by = Ticker]
.mom_all <- RAWDATA[Date %in% .month_ends & is.finite(.Mom), .(Date, Ticker, Mom = .Mom)]
RAWDATA[, .Mom := NULL]
setkey(.mom_all, Date, Ticker)

# ---- rank-Z (B1-5 와 동일) ----
.rank_z <- function(x) {
  r <- frank(x, ties.method = "average", na.last = "keep")
  mu <- mean(r, na.rm = TRUE); s <- sd(r, na.rm = TRUE)
  if (!is.finite(s) || s <= 0) return(rep(NA_real_, length(x)))
  (r - mu) / s
}

.factor_list <- vector("list", length(.month_ends))
.cov_diag <- vector("list", length(.month_ends))
for (i in seq_along(.month_ends)) {
  d <- .month_ends[i]
  uni_tk <- .mem[.(d), Ticker, nomatch = 0L]
  if (length(uni_tk) < 30L) next

  fdt <- tryCatch(load_month_factors(d, coverage_min = 0.05,
                                     factor_names = ILLIQ_FACTOR),
                  error = function(e) NULL)
  if (is.null(fdt) || nrow(fdt) == 0) next
  ilq <- fdt[Factor_Name == ILLIQ_FACTOR & is.finite(Z_Score_Aligned),
             .(Ticker, Ilq = Z_Score_Aligned)]

  .iqr_full <- IQR(ilq$Ilq, na.rm = TRUE)
  .iqr_uni  <- IQR(ilq[Ticker %in% uni_tk, Ilq], na.rm = TRUE)

  ilq <- ilq[Ticker %in% uni_tk]
  mom <- .mom_all[.(d), .(Ticker, Mom), nomatch = 0L][Ticker %in% uni_tk]

  cmb <- merge(ilq, mom, by = "Ticker")
  .cov_diag[[i]] <- data.table(Date = d, n_uni_liq = length(uni_tk),
                               n_amihud = nrow(ilq), n_scored = nrow(cmb),
                               iqr_full = .iqr_full, iqr_uni = .iqr_uni)
  if (nrow(cmb) < 30L) next
  cmb[, Zm := .rank_z(Mom)]
  cmb[, Zi := .rank_z(Ilq)]
  cmb <- cmb[is.finite(Zm) & is.finite(Zi)]
  if (nrow(cmb) < 30L) next
  cmb[, Score := 0.5 * Zm + 0.5 * Zi]   # 50/50 (B1-5 고정 — 변경 금지)
  cmb[, Date := d]
  .factor_list[[i]] <- cmb[, .(Date, Ticker, Score)]
}

FACTORS <- rbindlist(Filter(Negate(is.null), .factor_list), use.names = TRUE)

.cov_dt <- rbindlist(Filter(Negate(is.null), .cov_diag), use.names = TRUE)
.dg <- merge(.uni_diag, .cov_dt, by = "Date", all.y = TRUE)
.OUTD <- file.path(Sys.getenv("CLAUDE_PROJECT_DIR",
                   "C:/Users/99922/OneDrive/Quant_Module_Moltbot"),
                   "04_Research/strategies/RF_B3_11_KOSPI_All")
saveRDS(.dg, file.path(.OUTD, "universe_diag.rds"))
.dg2 <- .dg[Date >= as.Date("2005-01-01")]
cat(sprintf("[fe_b3_11][UNI-diag] 월별 중앙값 — 상장전수+adv20 n=%d | 기준선(K200uKQ150+adv20) n=%d | 배수 %.2fx | Amihud 교집합 n=%d | 최종 스코어 n=%d\n",
            as.integer(median(.dg2$n_wide)), as.integer(median(.dg2$n_idx)),
            median(.dg2$n_wide) / median(.dg2$n_idx),
            as.integer(median(.dg2$n_amihud)), as.integer(median(.dg2$n_scored))))
cat(sprintf("[fe_b3_11][MKT-diag] Market 리터럴판 참고 — Market=='KOSPI' n 중앙값 %d · Market NA n 중앙값 %d (2026 월말 전량 NA = 리터럴 적용 시 블랙아웃)\n",
            as.integer(median(.dg2$n_mkt_kospi)), as.integer(median(.dg2$n_mkt_na))))
cat(sprintf("[fe_b3_11][IQR-diag] %s aligned-Z IQR — full-panel median %.3f | 유니버스 내 median %.3f (잔존율 %.0f%%)\n",
            ILLIQ_FACTOR, median(.dg2$iqr_full), median(.dg2$iqr_uni),
            100 * median(.dg2$iqr_uni / .dg2$iqr_full)))
cat(sprintf("[fe_b3_11] Mom(12-1) rankZ + %s rankZ 50/50 | FACTORS rows=%d | months=%d | tickers=%d\n",
            ILLIQ_FACTOR, nrow(FACTORS), uniqueN(FACTORS$Date), uniqueN(FACTORS$Ticker)))
