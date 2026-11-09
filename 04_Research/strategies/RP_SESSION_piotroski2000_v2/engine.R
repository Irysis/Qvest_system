# =============================================================================
# engine.R — Piotroski (2000) F_SCORE 충실구현 · 퀀티 재무 DB v2 직접 판독 (세션 · 2026-11-09)
# =============================================================================
# 논문: Piotroski, J. D. (2000). "Value Investing: The Use of Historical Financial Statement
#   Information to Separate Winners from Losers." JAR 38 (Suppl.): 1-41. https://doi.org/10.2307/2672906
#   (원문 판독본 = Chicago GSB Selected Paper 84 판 · 2002-01 — §2.3 신호 정의 · §3 표본 · 표 1 변수 정의 · 표 3)
#
# 원문 정의(그대로):
#   ROA   = 특별항목 전 순이익 / 기초 총자산            F_ROA     = 1{ROA > 0}
#   CFO   = 영업활동현금흐름 / 기초 총자산              F_CFO     = 1{CFO > 0}
#   ΔROA  = ROA_t − ROA_{t-1}                         F_ΔROA    = 1{ΔROA > 0}
#   ACCRUAL = (특별항목 전 순이익 − CFO) / 기초 총자산   F_ACCRUAL = 1{CFO > ROA}
#   ΔLEVER = Δ(장기부채(유동성 대체분 포함) / 평균 총자산) F_ΔLEVER = 1{레버리지 하락}
#   ΔLIQUID = Δ(유동자산 / 유동부채, 기말)              F_ΔLIQUID = 1{개선}
#   EQ_OFFER = 1{직전 회계연도에 보통주 발행 없음}(현금흐름표 · 자금원천표로 식별 — 각주 11)
#   ΔMARGIN = Δ(매출총이익 / 매출)                     F_ΔMARGIN = 1{> 0}
#   ΔTURN  = Δ(매출 / 기초 총자산)(본문 §2.3.3 · 표 1 은 평균 총자산 — 본문을 대표로)  F_ΔTURN = 1{> 0}
#   F_SCORE = 아홉 지표 합(0~9) · High = 8~9 · Low = 0~1
#   표본 = 회계연도말 BM(장부 자본 / 회계연도말 시가총액) 최상위 5분위 · 분위 경계 = **직전 회계연도** BM 분포(각주 6)
#   수익 = 회계연도말 뒤 다섯째 달 초부터 1년 매수 후 보유 · 상장폐지 수익 = 0(§3.2)
#
# 변형(.RP_VARIANT · 기본값 = 대표 "hl" · 도훈 10-17 '모든 방법론' · FIDELITY.json variants):
#   hl   = High(8~9) 롱 − Low(0~1) 숏 · 동일가중(초록 '23% 연' · 표 3 High—Low) ← 대표
#   ha   = High(8~9) 롱 − 고 BM 전체 숏(표 3 High—All) · 같은 종목의 롱/숏은 순비중으로 합친다(수익 동일)
#   rank = 연간 순위 합 RANK_SCORE 5분위 최상 − 최하(§4.2 대안 방법 · 분위 경계 = 직전 회계연도 분포)
#
# PIT: 회계연도 t 값의 가용일 = max(그 기업-연도에 쓴 모든 행의 Factor_Date(t · t-1 · t-2), 익년 3/31(C4))
#   → 편입 신호일(t+1 년 4월 마지막 거래일)보다 늦으면 그해 그 기업은 표본에서 빠진다(직전 연도로 대체하지 않는다).
#   BM 시가총액 = 회계연도말(12월 마지막 거래일) RAWDATA Size · 분위 경계 = 직전 회계연도 분포(편입 1년 전 확정).
#   편입 멤버십 = 신호일 당일 측정 축 플래그(K200|KQ150 — 러너가 위생 멤버십으로 주입).
#   ★편입일 이후 정보 0 — 신호일 d 의 비중은 Factor_Date ≤ d 인 행 · Date ≤ d 인 RAWDATA 행만으로 만든다(lag 규약 C4).
# 산출: PORTFOLIO(Date, Ticker, Weight, Leg) · FACTORS(Date, Ticker, Score) · SIGNAL_BREADTH(Date, breadth)
# =============================================================================

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
suppressMessages({ library(data.table); library(arrow) })

.PV <- if (exists(".RP_VARIANT", inherits = TRUE)) as.character(get(".RP_VARIANT", inherits = TRUE))[1] else "hl"
if (!.PV %in% c("hl", "ha", "rank")) stop("[piotroski2000] 미지원 변형: ", .PV)
.P_ROOT <- get0("PROJECT_ROOT", ifnotfound = Sys.getenv("QM_ROOT", ""))
.P_FQ   <- file.path(.P_ROOT, ".cache", "fundamental_v2", "fund_v2_quarterly.parquet")
.P_FM   <- file.path(.P_ROOT, ".cache", "qw_fund_v2", "fiscal_month.parquet")
stopifnot(file.exists(.P_FQ), file.exists(.P_FM))
.P_START <- if (exists(".RP_START_DATE", inherits = TRUE)) as.Date(get(".RP_START_DATE", inherits = TRUE)) else min(RAWDATA$Date)
.P_DIAG_DIR <- tryCatch(dirname(get("factor_engine_path", inherits = TRUE)), error = function(e) NA_character_)

# ---- 1. v2 분기 표 — 쓰는 항목만 ----------------------------------------------------------
.P_FLOW  <- c("IncomeContOps", "NetIncome", "OperatingCF", "Revenue", "GrossProfit", "COGS",
              "EquityChangeCF", "ExtraGainGAAP", "ExtraLossGAAP")
.P_STOCK <- c("TotalAssets", "CurrentAssets", "CurrentLiab", "LongTermBorr", "Bonds", "CurrentBorr",
              "CurrentBonds", "EquityParent", "TotalEquity", "PreferredCapital")
.pq <- as.data.table(dplyr::collect(dplyr::select(dplyr::filter(arrow::open_dataset(.P_FQ), Item %in% c(.P_FLOW, .P_STOCK)),
                                                  Ticker, Period, Item, Value, Factor_Date, Check)))
.pq[, `:=`(yr = as.integer(substr(Period, 1L, 4L)), mm = substr(Period, 5L, 6L))]
.pq <- .pq[mm %in% c("03", "06", "09", "12") & is.finite(Value)]
.pq <- unique(.pq, by = c("Ticker", "Period", "Item"))
# 12월 결산만(현행 결산월 표 + 행 단위 non_dec_fy 표식 둘 다 · 비12월 결산 = 표본 제외 신고)
.pfm <- as.data.table(arrow::read_parquet(.P_FM))
# (결산월 표는 종목 선별만 — 재무 값 결합이 아니다 · 재무 가용일 lag 는 아래 avail(C4 · 익년 3/31 · Factor_Date)에서 강제)
.p_dectk <- .pfm[FiscalMonth == "12", unique(Ticker)]
.p_nondec_rows <- unique(.pq[Check == "non_dec_fy", .(Ticker, yr)])
.pq <- .pq[Ticker %in% .p_dectk]

# 회계연도 연간값 — 손익 · 현금흐름 = 네 분기 단독값 합(네 분기 모두 있어야 · 특별손익 · 자본증감은 있는 분기만)
.pfl <- .pq[Item %in% .P_FLOW, .(V = sum(Value), nq = uniqueN(mm),
                                 fd = suppressWarnings(max(Factor_Date, na.rm = TRUE))), by = .(Ticker, yr, Item)]
.pfl[nq < 4L & !Item %in% c("ExtraGainGAAP", "ExtraLossGAAP", "EquityChangeCF"), V := NA_real_]
.pst <- .pq[Item %in% .P_STOCK & mm == "12", .(V = Value[1L], fd = Factor_Date[1L]), by = .(Ticker, yr, Item)]
.pfd <- rbind(.pfl[is.finite(V), .(Ticker, yr, fd)], .pst[, .(Ticker, yr, fd)])[!is.na(fd) & is.finite(as.numeric(fd)),
         .(fd = max(fd)), by = .(Ticker, yr)]
.PY <- merge(dcast(.pfl, Ticker + yr ~ Item, value.var = "V"), dcast(.pst, Ticker + yr ~ Item, value.var = "V"),
             by = c("Ticker", "yr"), all = TRUE)
for (.cc in c(.P_FLOW, .P_STOCK)) if (!.cc %in% names(.PY)) .PY[, (.cc) := NA_real_]
.PY <- merge(.PY, .pfd, by = c("Ticker", "yr"), all.x = TRUE)
.PY <- .PY[!.p_nondec_rows, on = c("Ticker", "yr")]
# 장부 자본(BE)이 쓰는 항목의 가용일 — BM 5분위 경계 표본의 as-of 판정용(pit.md C1 · 2026-11-09 Q 검토 수리).
#   BE = EquityParent(없으면 TotalEquity) − PreferredCapital → 실제로 쓴 자본 항목의 Factor_Date 와 우선주자본금(있으면)의 Factor_Date 최대
.p_bef <- dcast(.pst[Item %in% c("EquityParent", "TotalEquity", "PreferredCapital")], Ticker + yr ~ Item, value.var = "fd")
for (.cc in c("EquityParent", "TotalEquity", "PreferredCapital")) if (!.cc %in% names(.p_bef)) .p_bef[, (.cc) := as.Date(NA)]
for (.cc in c("EquityParent", "TotalEquity", "PreferredCapital")) if (!inherits(.p_bef[[.cc]], "Date")) set(.p_bef, j = .cc, value = as.Date(as.numeric(.p_bef[[.cc]]), origin = "1970-01-01"))
.p_bev <- dcast(.pst[Item %in% c("EquityParent", "TotalEquity")], Ticker + yr ~ Item, value.var = "V")
for (.cc in c("EquityParent", "TotalEquity")) if (!.cc %in% names(.p_bev)) .p_bev[, (.cc) := NA_real_]
.p_bef <- merge(.p_bef, .p_bev[, .(Ticker, yr, use_ep = is.finite(EquityParent))], by = c("Ticker", "yr"), all.x = TRUE)
.p_bef[, fd_be := pmax(fifelse(use_ep %in% TRUE, EquityParent, TotalEquity), PreferredCapital, na.rm = TRUE)]
.p_bef[is.na(fifelse(use_ep %in% TRUE, EquityParent, TotalEquity)), fd_be := as.Date(NA)]   # 자본 항목 가용일이 없으면 판정 불가 = 경계 표본 제외
.PY <- merge(.PY, .p_bef[, .(Ticker, yr, fd_be)], by = c("Ticker", "yr"), all.x = TRUE)
rm(.p_bef, .p_bev)
rm(.pq, .pfl, .pst, .pfd); invisible(gc(verbose = FALSE))

# 특별항목 전 순이익: 계속사업이익(중단사업 제외 = Compustat IB) − (K-GAAP 특별이익 − 특별손실 · 세전 — 세효과 미분리 보충)
.PY[, IB := fifelse(is.finite(IncomeContOps), IncomeContOps, NetIncome) -
            (fcoalesce(ExtraGainGAAP, 0) - fcoalesce(ExtraLossGAAP, 0))]
# 장기부채(유동성 대체분 포함 — 표 1) = 장기차입금 + 사채(전환 · 신주인수권 · 교환사채 포함) + 유동성차입금 + 유동성사채 · 결측 = 0(총자산이 있으면)
.PY[is.finite(TotalAssets), LTD := fcoalesce(LongTermBorr, 0) + fcoalesce(Bonds, 0) + fcoalesce(CurrentBorr, 0) + fcoalesce(CurrentBonds, 0)]
.PY[, GPx := fifelse(is.finite(GrossProfit), GrossProfit, Revenue - COGS)]
.PY[, EQC := fifelse(is.finite(OperatingCF), fcoalesce(EquityChangeCF, 0), NA_real_)]   # 현금흐름표가 있는 해만
.PY[, BE := fifelse(is.finite(EquityParent), EquityParent, TotalEquity) - fcoalesce(PreferredCapital, 0)]

# 전년 · 전전년 값(연도 키 결합 — 빈 해는 결측 · shift 로 건너뛰지 않는다)
.p_l1 <- .PY[, .(Ticker, yr = yr + 1L, TA1 = TotalAssets, IB1 = IB, LTD1 = LTD, CA1 = CurrentAssets, CL1 = CurrentLiab,
                 GP1 = GPx, REV1 = Revenue, fd1 = fd)]
.p_l2 <- .PY[, .(Ticker, yr = yr + 2L, TA2 = TotalAssets, fd2 = fd)]
.PS <- merge(merge(.PY, .p_l1, by = c("Ticker", "yr"), all.x = TRUE), .p_l2, by = c("Ticker", "yr"), all.x = TRUE)
rm(.p_l1, .p_l2)

.PS[, `:=`(ROA = IB / TA1, CFO = OperatingCF / TA1, ROA_p = IB1 / TA2,
           LEV = LTD / ((TotalAssets + TA1) / 2), LEV_p = LTD1 / ((TA1 + TA2) / 2),
           LIQ = CurrentAssets / CurrentLiab, LIQ_p = CA1 / CL1,
           MAR = GPx / Revenue, MAR_p = GP1 / REV1,
           TURN = Revenue / TA1, TURN_p = REV1 / TA2)]
.PS[, `:=`(dROA = ROA - ROA_p, ACC = ROA - CFO, dLEV = LEV - LEV_p, dLIQ = LIQ - LIQ_p, dMAR = MAR - MAR_p, dTURN = TURN - TURN_p)]
.PS[, complete := is.finite(ROA) & is.finite(CFO) & is.finite(dROA) & is.finite(dLEV) & is.finite(dLIQ) &
                  is.finite(dMAR) & is.finite(dTURN) & is.finite(EQC) &
                  TA1 > 0 & TA2 > 0 & TotalAssets > 0 & CurrentLiab > 0 & CL1 > 0 & Revenue > 0 & REV1 > 0]
.PS[, `:=`(F_ROA = as.integer(ROA > 0), F_CFO = as.integer(CFO > 0), F_dROA = as.integer(dROA > 0),
           F_ACC = as.integer(CFO > ROA), F_dLEV = as.integer(dLEV < 0), F_dLIQ = as.integer(dLIQ > 0),
           F_EQ = as.integer(EQC <= 0), F_dMAR = as.integer(dMAR > 0), F_dTURN = as.integer(dTURN > 0))]
.PS[, FSCORE := F_ROA + F_CFO + F_dROA + F_ACC + F_dLEV + F_dLIQ + F_EQ + F_dMAR + F_dTURN]
# 가용일(C4 재강제 · lag 규약): 이 기업-연도에 쓴 t · t-1 · t-2 행의 Factor_Date 최대와 익년 3/31 중 늦은 날
.PS[, avail := pmax(fd, fd1, fd2, as.Date(sprintf("%d-03-31", yr + 1L)), na.rm = TRUE)]

# ---- 2. BM(회계연도말) · 멤버십 -------------------------------------------------------------
.p_rd <- RAWDATA[, .(Date, Ticker, Size, K200, KQ150)]
.p_rd[, mem := (fcoalesce(as.numeric(K200), 0) > 0) | (fcoalesce(as.numeric(KQ150), 0) > 0)]
.p_rd[, `:=`(y = as.integer(format(Date, "%Y")), m = as.integer(format(Date, "%m")))]
.p_dates <- sort(unique(RAWDATA$Date))
.p_dec <- .p_rd[m == 12L & is.finite(Size) & Size > 0, .SD[which.max(Date)], by = .(Ticker, y), .SDcols = c("Date", "Size", "mem")]
setnames(.p_dec, c("y", "Date", "Size", "mem"), c("yr", "fye_date", "ME", "mem_fye"))
.PS <- merge(.PS, .p_dec, by = c("Ticker", "yr"), all.x = TRUE)
.PS[, BM := fifelse(is.finite(BE) & BE > 0 & is.finite(ME) & ME > 0, BE / ME, NA_real_)]
# 편입 신호일 = 회계연도 다음 해 4월 마지막 거래일(→ 하네스 집행 = 5월 첫 거래일 = '다섯째 달 초')
.p_form <- data.table(Date = .p_dates)[as.integer(format(Date, "%m")) == 4L, .(form_date = max(Date)), by = .(yr = as.integer(format(Date, "%Y")) - 1L)]
.p_form <- .p_form[form_date >= .P_START & form_date <= max(.p_dates)]
# 분위 경계 = 직전 회계연도 BM 분포의 80 백분위(그해 회계연도말 측정 축 멤버 · BM 산출 가능) — ★as-of(pit.md C1 · 2026-11-09 수리):
#   경계를 쓰는 편입일 d(FY yr 표본 편입) 기준으로 FY yr−1 행 중 장부 자본 가용일 max(fd_be, 익년 3/31) ≤ d 인 행만 쓴다.
#   (수리 전 판은 FY yr−1 행 전부를 써서 d 이후에야 쓸 수 있는 장부가가 경계에 섞였다 — 정정 공시 늦은 접수 등)
.p_cs <- .PS[is.finite(BM) & mem_fye %in% TRUE, .(Ticker, yr = yr + 1L, BM, av_cut = pmax(fd_be, as.Date(sprintf("%d-03-31", yr + 1L))))]
.p_cs <- merge(.p_cs, .p_form, by = "yr")
.p_cut <- .p_cs[, .(cut80_prior = if (sum(av_cut <= form_date, na.rm = TRUE) > 0L)
                      as.numeric(stats::quantile(BM[av_cut <= form_date & !is.na(av_cut)], 0.8, type = 7)) else NA_real_,
                    n_cut = sum(av_cut <= form_date, na.rm = TRUE), n_cut_late = sum(is.na(av_cut) | av_cut > form_date)), by = yr]
.PS <- merge(.PS, .p_cut, by = "yr", all.x = TRUE)
.PS <- merge(.PS, .p_form, by = "yr")
rm(.p_cs)
.p_memf <- .p_rd[Date %in% .p_form$form_date, .(Ticker, form_date = Date, mem_form = mem)]
.PS <- merge(.PS, .p_memf, by = c("Ticker", "form_date"), all.x = TRUE)
rm(.p_rd, .p_dec, .p_memf); invisible(gc(verbose = FALSE))

.PS[, `:=`(ok_mem = mem_form %in% TRUE, ok_av = !is.na(avail) & avail <= form_date)]
.PS[, pool := ok_mem & ok_av & is.finite(BM)]                                   # 선정 전 후보(BM 산출 가능 · 가용 · 멤버)
.PS[, hbm := pool & is.finite(cut80_prior) & BM >= cut80_prior]                  # 고 BM 5분위
.PS[, cand := hbm & complete]                                                     # 아홉 신호 전부 산출 가능

# ---- 3. 변형별 비중 -----------------------------------------------------------------------
.p_rank01 <- function(x) { n <- length(x); if (n < 2L) return(rep(0.5, n)); (frank(x, ties.method = "average") - 1) / (n - 1) }
.C <- .PS[cand == TRUE]
if (identical(.PV, "rank")) {
  # 순위 합: 좋은 쪽이 높게(ACCRUAL · ΔLEVER 는 낮을수록 좋다 → 부호를 바꿔 순위) · EQ_OFFER 는 지표 자체를 순위
  .C[, RS := .p_rank01(ROA) + .p_rank01(CFO) + .p_rank01(dROA) + .p_rank01(-ACC) + .p_rank01(-dLEV) +
            .p_rank01(dLIQ) + .p_rank01(F_EQ) + .p_rank01(dMAR) + .p_rank01(dTURN), by = yr]
  .p_rq <- .C[, .(q20 = as.numeric(stats::quantile(RS, 0.2, type = 7)), q80 = as.numeric(stats::quantile(RS, 0.8, type = 7)), n_prior = .N), by = yr]
  # 5분위 경계는 직전 분포에 관측이 5개 이상일 때만 정의된다(5분위 하나에 1개) — FY2002 처럼 후보 1개뿐인 해의 '분위'로 다음 해를 가르지 않는다
  .p_rq[n_prior < 5L, `:=`(q20 = NA_real_, q80 = NA_real_)]
  .p_rq[, yr := yr + 1L]
  .C <- merge(.C, .p_rq, by = "yr", all.x = TRUE)
  .C[, grp := fifelse(is.finite(q80) & RS >= q80, "H", fifelse(is.finite(q20) & RS <= q20, "L", NA_character_))]
  .C[, Score := RS]
} else {
  .C[, grp := fifelse(FSCORE >= 8L, "H", fifelse(FSCORE <= 1L, "L", NA_character_))]
  .C[, Score := as.numeric(FSCORE)]
}
.p_pf <- .C[, {
  nH <- sum(grp %in% "H"); nL <- sum(grp %in% "L"); nA <- .N
  if (identical(.PV, "ha")) {
    if (nH < 1L || nA <= nH) NULL else
      .(Ticker = Ticker, Weight = fifelse(grp %in% "H", 1 / nH - 1 / nA, -1 / nA))
  } else {
    if (nH < 1L || nL < 1L) NULL else
      .(Ticker = c(Ticker[grp %in% "H"], Ticker[grp %in% "L"]),
        Weight = c(rep(1 / nH, nH), rep(-1 / nL, nL)))
  }
}, by = .(Date = form_date)]
.p_pf[, Leg := fifelse(Weight > 0, "long", "short")]
PORTFOLIO <- .p_pf[, .(Date, Ticker, Weight, Leg)]
FACTORS <- .C[, .(Date = form_date, Ticker, Score)]
SIGNAL_BREADTH <- .PS[pool == TRUE, .(breadth = .N), by = .(Date = form_date)]

# ---- 4. 진단(편입일별 표본 · 신고용) -------------------------------------------------------
.p_diag <- .PS[, .(fy = yr[1], n_cut = n_cut[1], n_cut_late = n_cut_late[1], n_fy_rows = .N, n_mem = sum(ok_mem), n_late = sum(ok_mem & !ok_av & is.finite(BM)),
                   n_pool = sum(pool), cut80_prior = cut80_prior[1], n_hbm = sum(hbm), n_cand = sum(cand),
                   n_cfo_missing_hbm = sum(hbm & !is.finite(CFO)),
                   n_f89 = sum(cand & FSCORE >= 8L), n_f01 = sum(cand & FSCORE <= 1L),
                   fscore_mean = mean(FSCORE[cand]),
                   # 사후 진단(비중에 안 쓴다): 가용일이 편입일보다 늦어 빠진 고 BM 기업의 F 분포 — 정정 미룸 제외가 Low 를 비우는지 본다
                   n_late_hbm = sum(ok_mem & !ok_av & is.finite(BM) & BM >= cut80_prior & complete, na.rm = TRUE),
                   n_late_hbm_f01 = sum(ok_mem & !ok_av & is.finite(BM) & BM >= cut80_prior & complete & FSCORE <= 1L, na.rm = TRUE),
                   n_late_hbm_f89 = sum(ok_mem & !ok_av & is.finite(BM) & BM >= cut80_prior & complete & FSCORE >= 8L, na.rm = TRUE),
                   avail_max_cand = max(avail[cand]), avail_max_pool = max(avail[pool])),
               by = .(form_date)][order(form_date)]
.p_diag <- merge(.p_diag, PORTFOLIO[, .(n_long = sum(Weight > 0), n_short = sum(Weight < 0)), by = .(form_date = Date)],
                 by = "form_date", all.x = TRUE)
.p_diag[, variant := .PV]
if (!is.na(.P_DIAG_DIR) && dir.exists(.P_DIAG_DIR))
  tryCatch(fwrite(.p_diag, file.path(.P_DIAG_DIR, sprintf("engine_diag_%s.csv", .PV))), error = function(e) NULL)
cat(sprintf("[piotroski2000] 변형 %s — 편입일 %d개 · 비중 행 %d · 롱 평균 %.1f · 숏 평균 %.1f · 후보(고 BM ∧ 9신호) 평균 %.1f\n",
            .PV, uniqueN(PORTFOLIO$Date), nrow(PORTFOLIO),
            mean(.p_diag$n_long, na.rm = TRUE), mean(.p_diag$n_short, na.rm = TRUE), mean(.p_diag$n_cand, na.rm = TRUE)))
rm(.C, .PS, .PY, .p_pf, .p_diag, .p_form, .p_cut); invisible(gc(verbose = FALSE))
