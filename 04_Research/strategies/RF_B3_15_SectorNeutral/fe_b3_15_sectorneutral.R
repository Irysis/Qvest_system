# =============================================================================
# fe_b3_15_sectorneutral.R — 규칙기반 고속강화 B3-15 (rulefast 15/20)
#   B1-5 승자 신호(모멘텀 12-1 rankZ 50% + Amihud 비유동성 rankZ 50%)를 그대로 쓰되
#   **랭킹 축을 섹터 내부 횡단면으로 옮기고**, 25종을 섹터별 균등 배분한다.
#   목적: 신호가 종목 선택인가 산업 베팅인가를 분리한다.
# =============================================================================
# 원장: reinforce_ledger_l1.json entry RP_20260829_122020_9192_rulefast, attempt n=15
# 근거 논문 (하드코딩 금지 — 수치 결정 뿌리):
#   - 섹터 중립화 근거: Moskowitz & Grinblatt (1999, JF 54(4)) "Do Industries Explain
#     Momentum?"  https://onlinelibrary.wiley.com/doi/10.1111/0022-1082.00146
#     → 개별종목 모멘텀 수익의 상당부분이 산업 모멘텀에 귀속. 산업을 중립화하면
#       종목선택 성분만 남는다는 것이 본 라운드의 검정 대상.
#   - 모멘텀 12-1: Jegadeesh & Titman (1993, JF 48(1))
#     https://www.bauer.uh.edu/rsusmel/phd/jegadeesh-titman93.pdf
#   - 비유동성 프리미엄: Amihud (2002, JFM 5(1))
#     https://www.sciencedirect.com/science/article/pii/S1386418101000246
#   - 팩터 코드 선택(L01_Amihud) 근거 = B1-5 사전 실측 진단 승계(L09 는 IC 부호 반전).
#
# ===== 배분 규칙 (사전 고정 — 실행 중 조정 금지) =====
# DEF-1 유니버스(월말 시그널일 d): (K200|KQ150) ∧ adv20(t-1) >= 2e8 ∧ Sector_Lv2 유효
# DEF-2 신호: Mom = shift(Close,21)/shift(Close,252)-1 ; Ilq = L01_Amihud Z_Score_Aligned
# DEF-3 섹터 내 rank-Z: 각 섹터 s 내부 횡단면에서 Zm,Zi 계산 → Score = 0.5*Zm + 0.5*Zi
# DEF-4 섹터 자격: 섹터 내 유효종목 n_s >= 3 (n_s=1 은 sd=0 정의불가, n_s=2 는 ±0.707
#       이진값이라 횡단면 rank-Z 로 의미 없음) → n_s<3 섹터는 제외
# DEF-5 배분: S = 자격 섹터 수, base = floor(25/S), rem = 25 - base*S
#       ① 섹터별 base 종목(섹터 내 Score 상위) 배정
#       ② 나머지 rem 슬롯 = 각 섹터의 (base+1)번째 후보를 Score 내림차순으로 비교해
#          상위 rem 개 섹터에 1씩 추가 (= "나머지를 상위 점수 섹터에 배정")
#       ③ 섹터 종목 부족으로 25 를 못 채우면 같은 규칙이 다음 라운드(base+2)로 흘러
#          자동 보전. 구현 = 전체 후보를 (섹터내 순위 r 오름차순, Score 내림차순)으로
#          정렬해 상위 25 를 취하는 것과 동치 — 결정론적, 사후조정 없음.
#       ※ S >= 25 이면 base=0 → 섹터당 최대 1종 (완전 섹터 분산). 이때 섹터 간 비교는
#          섹터 최고 종목의 섹터내 rank-Z 로 하므로 **대형 섹터(n_s 큰)가 구조적으로
#          유리**하다(rank-Z 상단이 더 극단). 이는 규칙의 선언된 성질이지 사후 튜닝 아님.
# DEF-6 비중: EW, Weight = 1/N, Leg="LONG", Σw=1 (섹터 균등 = 섹터당 배정수/25)
#
# ===== PIT (C1~C15) =====
#   - C15: Amihud 는 parquet 직접 load 금지 — load_month_factors() 경유.
#   - C14/C13: Z_Score_Aligned 만 소비. NEGATE/FLIP 없음.
#   - C10: adv20 = frollmean(20) 후 shift(1) — 시그널일 당일 거래대금 미포함.
#   - C2: 모멘텀 = shift(21)/shift(252) 과거 윈도우만.
#   - C1: rank-Z 는 sig_date 시점 섹터내 cross-section 내에서만(full-sample 통계 없음).
#   - ★섹터 라벨 시점 정합: Sector_Lv2 를 **그 날짜(d) 행의 값**으로만 읽는다.
#     패널은 시변(전 구간에 걸쳐 재분류 이벤트 존재) — 최신값 일괄고정이 아님.
#     한계: 재분류가 '발효일'에 기록됐는지 소급 기입인지는 패널 내부로 검증 불가.
# =============================================================================

suppressPackageStartupMessages(library(data.table))
stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
setorder(RAWDATA, Ticker, Date)
stopifnot("Sector_Lv2" %in% names(RAWDATA))

local({
  conn <- file.path(Sys.getenv("CLAUDE_PROJECT_DIR",
                               "C:/Users/99922/OneDrive/Quant_Module_Moltbot"),
                    "02_Infrastructure", "factor_db", "factor_db_connector.R")
  if (!exists("load_month_factors", mode = "function")) source(conn)
})

ILLIQ_FACTOR <- "L01_Amihud"
N_TARGET     <- 25L    # 실투형 축 (lean-loop 축 2층)
MIN_SEC_N    <- 3L     # DEF-4

# ---- 월말(시그널) 그리드 ----
RAWDATA[, .ym := format(Date, "%Y-%m")]
.month_ends <- sort(RAWDATA[, .(Date = max(Date)), by = .ym]$Date)
RAWDATA[, .ym := NULL]
.month_ends <- .month_ends[.month_ends >= as.Date("2004-11-01")]

# ---- 유니버스 + 섹터 라벨 (C10: adv20 t-1) ----
RAWDATA[, .TV := Close * Vol]
RAWDATA[, .AvgTV20 := shift(frollmean(.TV, 20L, align = "right"), 1L), by = Ticker]
.mem <- RAWDATA[Date %in% .month_ends & (K200 == TRUE | KQ150 == TRUE) &
                  is.finite(.AvgTV20) & .AvgTV20 >= 2e8 &
                  !is.na(Sector_Lv2) & nzchar(Sector_Lv2),
                .(Date, Ticker, Sec = Sector_Lv2)]
setkey(.mem, Date)

# ---- 모멘텀 12-1 (JT1993) ----
RAWDATA[, .Mom := shift(Close, 21L) / shift(Close, 252L) - 1, by = Ticker]
.mom_all <- RAWDATA[Date %in% .month_ends & is.finite(.Mom), .(Date, Ticker, Mom = .Mom)]
RAWDATA[, c(".TV", ".AvgTV20", ".Mom") := NULL]
setkey(.mom_all, Date)

.rank_z <- function(x) {
  r <- frank(x, ties.method = "average", na.last = "keep")
  mu <- mean(r, na.rm = TRUE); s <- sd(r, na.rm = TRUE)
  if (!is.finite(s) || s <= 0) return(rep(NA_real_, length(x)))
  (r - mu) / s
}

.pf_list  <- vector("list", length(.month_ends))
.dg_list  <- vector("list", length(.month_ends))

for (i in seq_along(.month_ends)) {
  d <- .month_ends[i]
  uni <- .mem[.(d), .(Ticker, Sec), nomatch = 0L]
  if (nrow(uni) < 30L) next

  fdt <- tryCatch(load_month_factors(d, coverage_min = 0.05,
                                     factor_names = ILLIQ_FACTOR),
                  error = function(e) NULL)
  if (is.null(fdt) || nrow(fdt) == 0) next
  ilq <- fdt[Factor_Name == ILLIQ_FACTOR & is.finite(Z_Score_Aligned),
             .(Ticker, Ilq = Z_Score_Aligned)]
  mom <- .mom_all[.(d), .(Ticker, Mom), nomatch = 0L]

  cmb <- merge(merge(uni, ilq, by = "Ticker"), mom, by = "Ticker")
  if (nrow(cmb) < 30L) next

  # DEF-4 섹터 자격
  cmb[, n_s := .N, by = Sec]
  n_all_sec <- uniqueN(cmb$Sec)
  cmb <- cmb[n_s >= MIN_SEC_N]
  if (!nrow(cmb)) next

  # DEF-3 섹터 내 횡단면 rank-Z (C1: 해당 d 시점 섹터내 표본만)
  cmb[, Zm := .rank_z(Mom), by = Sec]
  cmb[, Zi := .rank_z(Ilq), by = Sec]
  cmb <- cmb[is.finite(Zm) & is.finite(Zi)]
  if (!nrow(cmb)) next
  cmb[, Score := 0.5 * Zm + 0.5 * Zi]

  # DEF-5 배분: 섹터내 순위 r → (r asc, Score desc) 상위 25
  setorder(cmb, Sec, -Score)
  cmb[, r := seq_len(.N), by = Sec]
  setorder(cmb, r, -Score)
  n_take <- min(N_TARGET, nrow(cmb))
  sel <- cmb[seq_len(n_take)]

  S    <- uniqueN(cmb$Sec)
  base <- N_TARGET %/% S
  rem  <- N_TARGET - base * S
  cnt  <- sel[, .N, by = Sec]
  .dg_list[[i]] <- data.table(
    Date = d, n_uni = nrow(uni), n_scored = nrow(cmb),
    n_sec_all = n_all_sec, n_sec_qual = S,
    sec_n_mean = mean(cmb[, .N, by = Sec]$N),
    base = base, rem = rem, n_sel = nrow(sel),
    n_sec_sel = nrow(cnt), max_per_sec = max(cnt$N),
    overflow = as.integer(max(cnt$N) > base + 1L))

  .pf_list[[i]] <- sel[, .(Date = d, Ticker, Weight = 1 / nrow(sel), Leg = "LONG")]
}

PORTFOLIO <- rbindlist(Filter(Negate(is.null), .pf_list), use.names = TRUE)
.dg <- rbindlist(Filter(Negate(is.null), .dg_list), use.names = TRUE)

if (nrow(.dg)) {
  saveRDS(.dg, file.path(Sys.getenv("CLAUDE_PROJECT_DIR",
          "C:/Users/99922/OneDrive/Quant_Module_Moltbot"),
          "04_Research/strategies/RF_B3_15_SectorNeutral/sector_diag.rds"))
  cat(sprintf(paste0("[fe_b3_15][SEC-diag] months=%d | 유니버스 median n=%d | 섹터수(전체/자격) median %d/%d",
              " | 섹터당 종목수 median %.1f | base=0 개월 %d/%d | rem>0 개월 %d | overflow 개월 %d",
              " | 선정섹터수 median %d | 섹터당 최대 median %d\n"),
      nrow(.dg), as.integer(median(.dg$n_uni)),
      as.integer(median(.dg$n_sec_all)), as.integer(median(.dg$n_sec_qual)),
      median(.dg$sec_n_mean), sum(.dg$base == 0L), nrow(.dg),
      sum(.dg$rem > 0L), sum(.dg$overflow == 1L),
      as.integer(median(.dg$n_sec_sel)), as.integer(median(.dg$max_per_sec))))
}
cat(sprintf("[fe_b3_15] 섹터중립 Mom+%s | PORTFOLIO rows=%d | months=%d | tickers=%d | Σw check %.4f\n",
            ILLIQ_FACTOR, nrow(PORTFOLIO), uniqueN(PORTFOLIO$Date),
            uniqueN(PORTFOLIO$Ticker), PORTFOLIO[Date == max(Date), sum(Weight)]))
