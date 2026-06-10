# =============================================================================
# fe_sector_spillover.R — Industry Lead-Lag Spillover Momentum (Hou 2007)
# =============================================================================
# 가설 (Hou 2007 "Industry Information Diffusion and the Lead-Lag Effect in Stock
#   Returns", RFS): 같은 산업 내 대형주(leader, 정보풍부)가 산업 충격을 먼저 반영
#   → 소형 follower가 수 주~수 개월에 걸쳐 따라온다 (느린 산업 정보 확산).
#   long-only: 매 월말 t, 각 종목 j의 신호 S_j = j가 속한 산업 I의 *leader 대형주*의
#   최근 lagged 누적수익. 산업 leader가 오른 산업의 (상대적 소형) follower를 매수.
#
# ★ probe3 목적 = 관계형 long-only 클래스 생사 판정. probe1(가격 lead-lag 상관망)이
#   "직교한 노이즈"(BM_corr 0.77, PORT_t -0.08)였다. 같은 질문을 *경제적 산업 그룹*
#   (PIT-clean 섹터)으로: spillover가 직교한 *알파*를 내는가, 또 노이즈인가?
#   ★ Hou 2007 = 산업 spillover(probe2 재벌 economic-link과 다른 메커니즘). 별도 thesis.
#
# Edge 정의:
#   매 월말 t, 산업 I(Sector_Lv2)별:
#     leaders(I) = I 내 Size(시총) 상위 LEADER_FRAC 종목 (정보풍부 대형주)
#     leader_ret(I) = leaders(I)의 시총-가중(VW) trailing MOM 거래일 누적수익  [모두 ≤ t-1 lagged]
#   follower j(산업 I, 상대적 소형 = I 내 Size 중위 이하 → FOLLOWER_SIDE) 신호:
#     S_j = leader_ret(I_j)
#   long top-N = S_j 상위 EW. (소형 제한이 breadth 막으면 전 종목으로 완화 가능: FOLLOWER_SIDE=all)
#
# ===== PIT (절대) — 02_Infrastructure/docs/rules/data_table_shift_convention.md, AX-002 =====
#   - 섹터 멤버십: RAWDATA$Sector_Lv2 = 시변(time-varying) PIT 시계열 (892/3388 ticker가
#     기간 중 섹터 변경 확인). signal date t의 *그 시점* 섹터만 사용. 현재 스냅샷 금지.
#   - leader 누적수익 = Close[t]/Close[t-MOM]-1, t = signal date(월말). 100% 과거.
#     follower 보유는 run_monthly_simulation이 t→다음달 first-trade로 처리(forward 무누수).
#   - Size(시총) 분류, 유동성(LiqPass, t-1 ADV C10) 모두 ≤ t. C1 rolling / C2 no same-day.
#   - leader_ret은 *예측 신호*지 forward label 아님 (수익 정합은 sim 표준).
#
# 파라미터 sweep (n_trials 누적 의무): MOM(21/63), LEADER_FRAC, FOLLOWER_SIDE, Sector level
#   환경변수로 제어 (기본 = Hou 2007 정합 권장값).
#
# RAWDATA columns: Date, Ticker, Ret, Close, Size, Sector_Lv2, Sector_Lv1?, K200, KQ150, LiqPass
# =============================================================================
stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
stopifnot(all(c("Ret", "Close", "Size", "Sector_Lv2", "LiqPass") %in% names(RAWDATA)))

# ---- 파라미터 (env override; 기본 = 권장값) ---------------------------------
.SP_MOM         <- as.integer(Sys.getenv("SP_MOM",         "21"))   # leader 누적수익 trailing 거래일 (21≈1개월, 63≈3개월)
.SP_LEADER_FRAC <- as.numeric(Sys.getenv("SP_LEADER_FRAC", "0.30")) # 산업 내 시총 상위 비율 = leader
.SP_FOLLOWER    <- Sys.getenv("SP_FOLLOWER",  "small")              # "small"(시총 중위 이하 follower) | "all"(전 종목 follower)
.SP_SECTOR_COL  <- Sys.getenv("SP_SECTOR_COL", "Sector_Lv2")        # "Sector_Lv2"(49, 좁음) | "Sector_Lv1"(27)? RAWDATA엔 Sector_Lv2만 → lv1은 parquet 머지 필요
.SP_MIN_SEC_N   <- as.integer(Sys.getenv("SP_MIN_SEC_N", "4"))      # 산업 내 최소 종목수 (leader/follower 분리 가능)
.SP_MIN_LEAD_N  <- 2L                                               # 산업 leader 최소 수

stopifnot(.SP_SECTOR_COL %in% names(RAWDATA))
setorder(RAWDATA, Ticker, Date)

# ---- 월말 시그널 날짜 -------------------------------------------------------
RAWDATA[, .ym := format(Date, "%Y-%m")]
.month_ends <- sort(RAWDATA[, .(Date = max(Date)), by = .ym]$Date)

# ---- Close wide (leader 누적수익: Close[t]/Close[t-MOM]-1) ------------------
.C <- dcast(RAWDATA[, .(Date, Ticker, Close)], Date ~ Ticker, value.var = "Close")
.cdates <- .C$Date; .C[, Date := NULL]
.Cmat <- as.matrix(.C); .ctk <- colnames(.Cmat)
rm(.C); gc(verbose = FALSE)

# ---- signal date별 universe(섹터/시총/유동성) 스냅샷 (PIT: 그 시점 값만) ----
#   K200/KQ150 멤버십 필터는 run_alpha_search가 별도 적용하므로 여기선 LiqPass + 섹터/시총만.
#   단 leader/follower 분리·leader VW는 신호 정의의 일부라 여기서 처리.
.sec_col <- .SP_SECTOR_COL
.snap <- RAWDATA[Date %in% .month_ends & LiqPass == TRUE & is.finite(Size) & !is.na(get(.sec_col)),
                 .(Date, Ticker, Size, Sector = get(.sec_col))]

# ---- 핵심 루프: signal date별 산업 leader→follower 신호 ----------------------
.sig_list <- vector("list", length(.month_ends))
.k <- 0L
for (.ti in seq_along(.month_ends)) {
  t  <- .month_ends[.ti]
  ci <- match(t, .cdates)
  if (is.na(ci) || ci <= .SP_MOM) next

  snap_t <- .snap[Date == t]
  if (nrow(snap_t) < 20L) next

  # leader 누적수익 (signal date t): Close[t]/Close[t-MOM]-1, 종목별
  cidx <- match(snap_t$Ticker, .ctk)
  c_now  <- .Cmat[ci, cidx]
  c_prev <- .Cmat[ci - .SP_MOM, cidx]
  snap_t[, lead_mom := c_now / c_prev - 1]

  # 산업별: leader = 시총 상위 LEADER_FRAC, leader_ret = leader VW(시총가중) lead_mom
  #   follower = (small) 시총 중위 이하 / (all) 전 종목.
  out_rows <- snap_t[, {
    n <- .N
    if (n < .SP_MIN_SEC_N) {
      .(Ticker = character(0), Score = numeric(0))
    } else {
      ord <- order(-Size)                       # 시총 내림차순
      nlead <- max(.SP_MIN_LEAD_N, as.integer(ceiling(n * .SP_LEADER_FRAC)))
      nlead <- min(nlead, n - 1L)               # 최소 1 follower 보장
      lead_idx <- ord[seq_len(nlead)]
      lm  <- lead_mom[lead_idx]; sz <- Size[lead_idx]
      ok  <- is.finite(lm) & is.finite(sz) & sz > 0
      if (sum(ok) < .SP_MIN_LEAD_N) {
        .(Ticker = character(0), Score = numeric(0))
      } else {
        # leader 산업 신호 = 시총가중 leader 누적수익 (VW). 단일 스칼라 per 산업.
        wlead <- sz[ok] / sum(sz[ok])
        lead_signal <- sum(wlead * lm[ok])
        # follower 집합
        if (.SP_FOLLOWER == "all") {
          fol <- seq_len(n)
        } else {                                # small: 시총 중위 이하 (leader 제외 자연 포함)
          med <- median(Size)
          fol <- which(Size <= med)
        }
        if (length(fol) == 0L) {
          .(Ticker = character(0), Score = numeric(0))
        } else {
          .(Ticker = Ticker[fol], Score = rep(lead_signal, length(fol)))
        }
      }
    }
  }, by = Sector]

  out_rows <- out_rows[is.finite(Score) & nzchar(Ticker)]
  if (!nrow(out_rows)) next
  .k <- .k + 1L
  .sig_list[[.k]] <- data.table(Date = t, Ticker = out_rows$Ticker, Score = out_rows$Score)
}
.sig_list <- .sig_list[seq_len(.k)]

FACTORS <- if (.k > 0L) rbindlist(.sig_list) else
  data.table(Date = as.Date(character(0)), Ticker = character(0), Score = numeric(0))

# 정리
RAWDATA[, .ym := NULL]
rm(.Cmat, .snap); gc(verbose = FALSE)

cat(sprintf("[fe_sector_spillover] Hou 2007 industry lead-lag | MOM=%d leader_frac=%.2f follower=%s sector=%s | rows=%d dates=%d tickers=%d\n",
            .SP_MOM, .SP_LEADER_FRAC, .SP_FOLLOWER, .SP_SECTOR_COL,
            nrow(FACTORS), uniqueN(FACTORS$Date), uniqueN(FACTORS$Ticker)))
