#!/usr/bin/env Rscript
#==============================================================================
# build_kr_factor_returns.R — 한국 Fama-French 팩터 수익(일간 · 월간) + 파마-맥베스 통제 특성(월간)
#   v1.0 (2026-11-09 · 도훈 "재빌드 뒤 갱신해주고 팩터조정알파 및 파마-맥베스 분석에 쓰이는
#   기초데이터도 데일리로 최신화") · 설정 정본 = 06_Registry/kr_factor_returns.json(출처 · 정의 전부)
#
# 왜 새로 짰나 — 구판(.cache/kr_factor_returns_v2.parquet ·
#   99_Archive/reorg_20261014/04_Research/worktask_scratch/WT-D20260425_009/step0_kr_ff5_backfill.R):
#   ① HML · RMW · CMA = 월말 '하루' 수익의 차(RAWDATA Ret = 일간 수익) — 월간 수익이 아니다(월 표준편차 ≈ 1%)
#   ② RF = 0(FIXME) — 시장 노출 < 1 인 전략의 알파가 (1 − β)·RF 만큼 부풀었다
#   ③ MKT · SMB · WML = 만든 경로를 찾을 수 없는 더 오래된 파일 · ④ 2026-03-04 에서 멈춤(부분월 행 포함)
#
# 구성(설정 annual_sort · momentum · definitions):
#   유니버스 = 측정 축 epoch 멤버(contracts/measurement_axis.R::ma_membership)
#   연 1회 6월 말 구성 · 7월 ~ 이듬해 6월 보유: Size(6월 말 시총 · Big = 상위 누적 90%) ×
#     B/M(BE t−1 / ME t−1 12월) · OP((영업이익 − 이자비용)/BE) · INV(TA t−1 / TA t−2 − 1) — 특성 30/70 = Big 분위
#   월 1회 월말 구성: Size × 직전 t−12 ~ t−2 수익(모멘텀)
#   PIT: 재무 값은 Factor_Date ≤ 구성일 · 구성일 종가로 정렬 · 다음 거래일부터 보유 · RF = 전 거래일 CD91
#   수익 = 일간 상한 가치가중(전날 시총을 직전 월말 Big 시총 80 분위에서 자른다 · Jensen-Kelly-Pedersen 2023 · 설정 weighting)
#     → 월간 = 포트폴리오 일간 수익을 달 안에서 복리 → 요인 = 포트폴리오 수익의 조합 · 시장(MKT) = 상한 없는 가치가중
#
# 쓰기: Rscript 02_Infrastructure/data/build_kr_factor_returns.R [--out DIR] [--to YYYY-MM-DD] [--no-vintage]
#   기본 --out = <root>/.cache (운영 경로). 후보를 먼저 보려면 --out 에 스크래치 폴더를 준다.
#   source() 하면 함수만 싣는다(시험 = 08_Tests/data/test_kr_factor_returns.R).
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a
KRF_BUILDER <- "build_kr_factor_returns.R v1.0"

krf_root <- function() {
  # 순서 = CLAUDE_PROJECT_DIR → QM_ROOT (r-portability 금칙 ④ — ~/.Renviron 의 QM_ROOT 는 export 로 못 덮는다)
  r <- Sys.getenv("CLAUDE_PROJECT_DIR", "")
  if (!nzchar(r)) r <- Sys.getenv("QM_ROOT", "")
  if (!nzchar(r)) stop("[krf] CLAUDE_PROJECT_DIR · QM_ROOT 미설정 — 루트를 지어내지 않는다")
  gsub("\\\\", "/", r)
}

krf_config <- function(root = krf_root()) {
  p <- file.path(root, "06_Registry", "kr_factor_returns.json")
  if (!file.exists(p)) stop("[krf] 설정 없음: ", p)
  cfg <- fromJSON(p, simplifyVector = TRUE)
  need <- c("version", "start_date", "lookback_start", "universe", "fundamentals", "rf", "annual_sort", "momentum", "weighting", "guards", "chars", "outputs")
  miss <- setdiff(need, names(cfg))
  if (length(miss)) stop("[krf] 설정 키 없음: ", paste(miss, collapse = ","))
  cfg
}

## ── 작은 도구 ────────────────────────────────────────────────────────────────
.ym_add <- function(ym, k) {                       # YYYYMM 정수 + k 개월
  i <- (ym %/% 100L) * 12L + (ym %% 100L - 1L) + as.integer(k)
  as.integer((i %/% 12L) * 100L + (i %% 12L) + 1L)
}
.ym_of <- function(d) as.integer(format(d, "%Y%m"))
# 보유연도(= 그 수익을 담는 정렬의 구성 연도) — 구성월 다음 달부터 이듬해 구성월까지
.krf_hold_year <- function(ym, formation_month) ifelse((ym %% 100L) > formation_month, ym %/% 100L, ym %/% 100L - 1L)
KRF_FUND_ITEMS <- c("EquityParent", "TotalEquity", "NonControllingInt", "PreferredCapital", "TotalAssets", "OperatingProfit", "InterestExp")

# 월말 f 의 직전 수익 C[f − skip] / C[f − skip − lb] − 1 (모멘텀 t−12 ~ t−2) — 정렬 · 특성 패널 공용
.krf_prior <- function(SNAP, skip, lb) {
  P <- SNAP[is.finite(Close) & Close > 0, .(Ticker, ym, Close)]
  E <- copy(P)[, ym := .ym_add(ym, skip)]; setnames(E, "Close", "C_end")
  B <- copy(P)[, ym := .ym_add(ym, skip + lb)]; setnames(B, "Close", "C_beg")
  X <- merge(E, B, by = c("Ticker", "ym"))
  X[, .(Ticker, ym, mom = C_end / C_beg - 1)]
}

# 시총 상위 누적 share 까지 = Big(그 문턱을 넘기는 종목까지 Big) — FF (2012) §2
.krf_size_split <- function(me, share) {
  o <- order(me, decreasing = TRUE)
  before <- cumsum(me[o]) - me[o]
  big <- logical(length(me))
  big[o] <- (before / sum(me)) < share
  big
}

# 특성 30/70 분위(Big 종목 분위) 라벨 — Big 이 min_big 미만이면 NULL(지어내지 않는다)
.krf_sort_labels <- function(Ticker, big, x, lo, mid, hi, bp, min_big) {
  xb <- x[big]
  if (length(xb) < min_big) return(NULL)
  q <- stats::quantile(xb, bp, names = FALSE, type = 7)
  g <- ifelse(x <= q[1], lo, ifelse(x >= q[2], hi, mid))
  data.table(Ticker = Ticker, port = paste0(ifelse(big, "B", "S"), g), bp_lo = q[1], bp_hi = q[2])
}

## ── 재무: 연간(달력연도) 값 + 그 값을 쓸 수 있는 날 ─────────────────────────
#' FUND: data.table(Ticker, Period(YYYYMM 문자), Item, Value, Factor_Date(Date)) — v2 1단계 표의 열
#' @return data.table(Ticker, fy, BE, BE_d, TA, TA_d, OPN, OPN_d)
krf_annual_fund <- function(FUND) {
  F <- FUND[Item %in% KRF_FUND_ITEMS & is.finite(Value) & !is.na(Factor_Date),
            .(Ticker, Period = as.character(Period), Item, Value = as.numeric(Value), Factor_Date = as.Date(Factor_Date))]
  F[, `:=`(fy = as.integer(substr(Period, 1, 4)), mo = substr(Period, 5, 6))]
  F <- F[mo %in% c("03", "06", "09", "12")]
  dup <- F[, .N, by = .(Ticker, Period, Item)][N > 1L]
  if (nrow(dup)) stop("[krf] 재무 표 같은 (종목 · 기간 · 항목) 겹침 ", nrow(dup), "건 — 날짜 순서 계약 위반(조용히 고르지 않는다)")
  bs <- F[mo == "12"]
  A <- unique(F[, .(Ticker, fy)])
  for (it in c("EquityParent", "TotalEquity", "NonControllingInt", "PreferredCapital", "TotalAssets")) {
    s <- bs[Item == it, .(Ticker, fy, v = Value, d = Factor_Date)]
    setnames(s, c("v", "d"), c(it, paste0(it, "_d")))
    A <- merge(A, s, by = c("Ticker", "fy"), all.x = TRUE)
  }
  fl <- F[Item %in% c("OperatingProfit", "InterestExp"), .(v = sum(Value), nq = .N, d = max(Factor_Date)), by = .(Ticker, fy, Item)]
  A <- merge(A, fl[Item == "OperatingProfit" & nq == 4L, .(Ticker, fy, OP4 = v, OP4_d = d)], by = c("Ticker", "fy"), all.x = TRUE)
  A <- merge(A, fl[Item == "InterestExp", .(Ticker, fy, IE = v, IE_d = d)], by = c("Ticker", "fy"), all.x = TRUE)
  ep <- is.finite(A$EquityParent)
  A[, BE0 := fifelse(ep, EquityParent, TotalEquity - fcoalesce(NonControllingInt, 0))]
  A[, BE0_d := fifelse(ep, EquityParent_d, pmax(TotalEquity_d, NonControllingInt_d, na.rm = TRUE))]
  A[, BE := BE0 - fcoalesce(PreferredCapital, 0)]
  A[, BE_d := pmax(BE0_d, PreferredCapital_d, na.rm = TRUE)]
  A[, OPN := OP4 - fcoalesce(IE, 0)]
  A[, OPN_d := fifelse(is.finite(OP4), pmax(OP4_d, IE_d, na.rm = TRUE), as.Date(NA))]
  A[, .(Ticker, fy, BE, BE_d, TA = TotalAssets, TA_d = TotalAssets_d, OPN, OPN_d)]
}

## ── 달력 · 월말 표본 ────────────────────────────────────────────────────────
krf_calendar <- function(RAW, min_rows) {
  cnt <- RAW[, .N, by = Date][N >= min_rows]
  cal <- data.table(Date = sort(cnt$Date))
  cal[, ym := .ym_of(Date)]
  list(cal = cal, me = cal[, .(me_date = max(Date)), by = ym])
}

#' 월말 행(그 달 마지막 거래일에 있는 종목 행) — ME = Size · 멤버 여부
krf_snap <- function(RAW, ME) {
  S <- merge(RAW[, .(Date, Ticker, Size, Close, member)], ME, by.x = "Date", by.y = "me_date")
  S[, .(Ticker, ym, me_date = Date, ME = Size, Close, member)]
}

## ── 연간 정렬(6월 말) ───────────────────────────────────────────────────────
krf_annual_labels <- function(SNAP, AF, years, cfg) {
  share <- as.numeric(cfg$annual_sort$big_share); bp <- as.numeric(cfg$annual_sort$char_breakpoints)
  mb <- as.integer(cfg$guards$min_big_for_breakpoints); fm <- as.integer(cfg$annual_sort$formation_month)
  L <- list(); D <- list()
  for (t in years) {
    f_ym <- t * 100L + fm; d_ym <- (t - 1L) * 100L + 12L
    J <- SNAP[ym == f_ym & member %in% TRUE & is.finite(ME) & ME > 0, .(Ticker, fdate = me_date, ME_f = ME)]
    if (nrow(J) < mb) next
    fdate <- J$fdate[1L]
    J <- merge(J, SNAP[ym == d_ym & is.finite(ME) & ME > 0, .(Ticker, ME_dec = ME)], by = "Ticker", all.x = TRUE)
    J <- merge(J, AF[fy == t - 1L, .(Ticker, BE, BE_d, TA1 = TA, TA1_d = TA_d, OPN, OPN_d)], by = "Ticker", all.x = TRUE)
    J <- merge(J, AF[fy == t - 2L, .(Ticker, TA2 = TA, TA2_d = TA_d)], by = "Ticker", all.x = TRUE)
    # ★PIT — 구성일까지 쓸 수 없던 값은 없는 것으로 친다(Factor_Date > 구성일 · 결측 날짜)
    J[is.na(BE_d) | BE_d > fdate, BE := NA_real_]
    J[is.na(OPN_d) | OPN_d > fdate, OPN := NA_real_]
    J[is.na(TA1_d) | TA1_d > fdate, TA1 := NA_real_]
    J[is.na(TA2_d) | TA2_d > fdate, TA2 := NA_real_]
    J[, big := .krf_size_split(ME_f, share)]
    sorts <- list(
      BM  = list(J[is.finite(ME_dec) & is.finite(BE) & BE > 0, .(Ticker, big, x = BE / ME_dec)], "L", "N", "H"),
      OP  = list(J[is.finite(BE) & BE > 0 & is.finite(OPN), .(Ticker, big, x = OPN / BE)], "W", "N", "R"),
      INV = list(J[is.finite(TA1) & is.finite(TA2) & TA2 > 0, .(Ticker, big, x = TA1 / TA2 - 1)], "C", "N", "A"))
    for (s in names(sorts)) {
      S <- sorts[[s]][[1]]
      lb <- .krf_sort_labels(S$Ticker, S$big, S$x, sorts[[s]][[2]], sorts[[s]][[3]], sorts[[s]][[4]], bp, mb)
      if (!is.null(lb)) L[[length(L) + 1L]] <- lb[, `:=`(fy = t, sort = s)]
      D[[length(D) + 1L]] <- data.table(fy = t, sort = s, fdate = fdate, n_universe = nrow(J), n_sort = nrow(S),
                                        n_big = sum(S$big), ok = !is.null(lb))
    }
  }
  list(labels = rbindlist(L, use.names = TRUE), diag = rbindlist(D, use.names = TRUE))
}

## ── 모멘텀 정렬(매월 말) ────────────────────────────────────────────────────
krf_mom_labels <- function(SNAP, cfg, from_ym) {
  share <- as.numeric(cfg$momentum$big_share); bp <- as.numeric(cfg$momentum$char_breakpoints)
  mb <- as.integer(cfg$guards$min_big_for_breakpoints)
  PR <- .krf_prior(SNAP, as.integer(cfg$momentum$skip_months), as.integer(cfg$momentum$lookback_months))
  U <- SNAP[ym >= from_ym & member %in% TRUE & is.finite(ME) & ME > 0, .(Ticker, ym, ME)]
  U[, big := .krf_size_split(ME, share), by = ym]          # Size 분할은 직전 수익 유무와 무관하게 그 월말 멤버 전체로
  U <- merge(U, PR, by = c("Ticker", "ym"))
  U <- U[is.finite(mom)][, x := mom]
  L <- U[, { r <- .krf_sort_labels(Ticker, big, x, "L", "N", "W", bp, mb); if (is.null(r)) NULL else r }, by = ym]
  D <- U[, .(n_sort = .N, n_big = sum(big)), by = ym]
  setnames(L, "ym", "fym")
  list(labels = L, diag = D)
}

## ── 가중 상한(직전 월말 Big 종목 시총의 cap_quantile 분위 · JKP 2023) ─────────
#' @return data.table(fym, cap) — 그 월말에 잡은 상한(다음 달 일간 가중에 쓴다) · weighting.rule = vw 면 NULL
krf_caps <- function(SNAP, cfg) {
  w <- cfg$weighting
  rule <- as.character(w$rule %||% "vw")
  if (identical(rule, "vw")) return(NULL)
  if (!identical(rule, "capped_vw")) stop("[krf] weighting.rule 미지원: ", rule, " (vw | capped_vw)")
  if (!identical(as.character(w$cap_set), "big") || !identical(as.character(w$cap_update), "monthly"))
    stop("[krf] weighting.cap_set = big · cap_update = monthly 만 구현돼 있다")
  qq <- as.numeric(w$cap_quantile)
  if (length(qq) != 1L || !is.finite(qq) || qq <= 0 || qq >= 1) stop("[krf] weighting.cap_quantile 판독 실패(0~1 사이 수 하나)")
  U <- SNAP[member %in% TRUE & is.finite(ME) & ME > 0, .(ym, ME)]
  U[, big := .krf_size_split(ME, as.numeric(cfg$annual_sort$big_share)), by = ym]
  U[big == TRUE, .(cap = stats::quantile(ME, qq, names = FALSE, type = 7)), by = .(fym = ym)]
}

## ── 일간 가치가중 포트폴리오 수익 ──────────────────────────────────────────
#' RD: data.table(Date, Ticker, Ret, ME_l1, W, hy, fym) — Ret 유한 · ME_l1 > 0 만 · W = 요인 포트폴리오 가중(상한 적용 전날 시총)
#'   요인 포트폴리오 = W 가중 · 시장(MKT) = ME_l1 가중(시장 포트폴리오는 상한 없음)
krf_daily_ports <- function(RD, LA, LM, UM) {
  vw <- function(X) X[is.finite(W) & W > 0, .(r = sum(W * Ret) / sum(W), n = .N), by = .(Date, port)]
  out <- list()
  for (s in c("BM", "OP", "INV")) {
    Ls <- LA[sort == s, .(Ticker, hy = fy, port)]
    out[[s]] <- vw(RD[Ls, on = .(Ticker, hy), nomatch = 0L])[, sort := s]
  }
  out[["MOM"]] <- vw(RD[LM[, .(Ticker, fym, port)], on = .(Ticker, fym), nomatch = 0L])[, sort := "MOM"]
  X <- RD[UM, on = .(Ticker, fym), nomatch = 0L]
  out[["MKT"]] <- X[, .(r = sum(ME_l1 * Ret) / sum(ME_l1), n = .N), by = .(Date)][, `:=`(port = "MKT", sort = "MKT")]
  rbindlist(out, use.names = TRUE)
}

## ── 요인 = 포트폴리오 수익의 조합(FF 1993 · 2015 · French UMD) ──────────────
#' P: data.table(k, sort, port, r) — k = Date(일간) 또는 ym(월간)
krf_factors <- function(P) {
  w <- function(s, lo, hi) {
    x <- dcast(P[sort == s], k ~ port, value.var = "r")
    nm <- c(paste0("S", c(lo, "N", hi)), paste0("B", c(lo, "N", hi)))
    for (n in setdiff(nm, names(x))) x[, (n) := NA_real_]
    data.table(k = x$k,
               smb = (x[[nm[1]]] + x[[nm[2]]] + x[[nm[3]]]) / 3 - (x[[nm[4]]] + x[[nm[5]]] + x[[nm[6]]]) / 3,
               hl  = (x[[nm[3]]] + x[[nm[6]]]) / 2 - (x[[nm[1]]] + x[[nm[4]]]) / 2)
  }
  bm <- w("BM", "L", "H");  setnames(bm, c("smb", "hl"), c("SMB_BM", "HML"))
  op <- w("OP", "W", "R");  setnames(op, c("smb", "hl"), c("SMB_OP", "RMW"))
  iv <- w("INV", "C", "A"); setnames(iv, c("smb", "hl"), c("SMB_INV", "AMC"))
  iv[, CMA := -AMC][, AMC := NULL]                                  # CMA = 보수적(낮은 INV) − 공격적
  mo <- w("MOM", "L", "W"); setnames(mo, c("smb", "hl"), c("SMB_MOM", "WML"))
  mk <- P[sort == "MKT", .(k, MKT_TOTAL = r, n_mkt = n)]
  F <- Reduce(function(a, b) merge(a, b, by = "k", all = TRUE), list(mk, bm, op, iv, mo[, .(k, WML)]))
  F[, SMB5 := (SMB_BM + SMB_OP + SMB_INV) / 3]
  F[, SMB := SMB_BM]                                                # 3요인판 SMB(French 3-factor 파일과 같은 정의)
  F[]
}

## ── RF: 전 거래일 CD91 ──────────────────────────────────────────────────────
krf_rf_daily <- function(RFY, dates) {
  dates <- sort(unique(as.Date(dates)))
  Y <- unique(RFY[is.finite(y), .(Date = as.Date(Date), y)], by = "Date")
  setkey(Y, Date)
  Q <- data.table(Date = dates, prev = c(as.Date(NA), head(dates, -1L)))
  Q[, y := Y[data.table(Date = Q$prev), x.y, on = .(Date), roll = TRUE]]
  Q[is.na(prev), y := NA_real_]
  Q[, RF := (1 + y / 100)^(1 / 252) - 1]
  Q[, .(Date, RF, rf_yield_pct = y)]
}

## ── 파마-맥베스 통제 특성(월말) ─────────────────────────────────────────────
krf_chars <- function(SNAP, AF, cfg, from_ym) {
  age <- as.integer(cfg$chars$max_fiscal_age_years)
  PR <- .krf_prior(SNAP, as.integer(cfg$momentum$skip_months), as.integer(cfg$momentum$lookback_months))
  C <- SNAP[ym >= from_ym & is.finite(ME) & ME > 0, .(Ticker, ym, Date = me_date, member, ME)]
  C <- merge(C, PR[, .(Ticker, ym, mom_2_12 = mom)], by = c("Ticker", "ym"), all.x = TRUE)
  # 그 월말까지 쓸 수 있던 가장 최근 회계연도(BE 공개일 기준 — 늦게 정정된 옛 연도가 새 연도를 밀어내지 않게 누적 최대)
  ev <- AF[!is.na(BE_d), .(Ticker, d = BE_d, fy)]
  setorder(ev, Ticker, d, fy)
  ev[, fy_best := cummax(fy), by = Ticker]
  ev <- ev[, .(fy_best = max(fy_best)), by = .(Ticker, d)]
  setkey(ev, Ticker, d)
  C[, fy_used := ev[data.table(Ticker = C$Ticker, d = C$Date), x.fy_best, on = .(Ticker, d), roll = TRUE]]
  C[!is.na(fy_used) & fy_used < as.integer(ym %/% 100L) - age, fy_used := NA_integer_]
  a <- AF[, .(Ticker, fy_used = fy, BE, BE_d, OPN, OPN_d, TA1 = TA, TA1_d = TA_d)]
  C <- merge(C, a, by = c("Ticker", "fy_used"), all.x = TRUE)
  C <- merge(C, AF[, .(Ticker, fy_used = fy + 1L, TA2 = TA, TA2_d = TA_d)], by = c("Ticker", "fy_used"), all.x = TRUE)
  C[is.na(BE_d) | BE_d > Date, BE := NA_real_]
  C[is.na(OPN_d) | OPN_d > Date, OPN := NA_real_]
  C[is.na(TA1_d) | TA1_d > Date, TA1 := NA_real_]
  C[is.na(TA2_d) | TA2_d > Date, TA2 := NA_real_]
  C[, `:=`(log_me = log(ME),
           bm  = ifelse(is.finite(BE) & BE > 0, BE / ME, NA_real_),
           op  = ifelse(is.finite(BE) & BE > 0 & is.finite(OPN), OPN / BE, NA_real_),
           inv = ifelse(is.finite(TA1) & is.finite(TA2) & TA2 > 0, TA1 / TA2 - 1, NA_real_))]
  setorder(C, Date, Ticker)
  C[, .(Date, ym, Ticker, member, log_me, bm, op, inv, mom_2_12, fy_used)]
}

## ── 조립(순수 함수 — 시험이 합성 자료로 부른다) ─────────────────────────────
#' RAW: data.table(Date, Ticker, Close, Size, Ret, member) — member = 측정 축 멤버(논리)
#' FUND: v2 1단계 표 행 · RFY: data.table(Date, y = 연 %)
krf_build <- function(RAW, FUND, RFY, cfg, to = NULL) {
  st <- as.Date(cfg$start_date)
  if (anyDuplicated(RAW, by = c("Date", "Ticker"))) stop("[krf] RAWDATA (Date, Ticker) 겹침 — 중단")
  setorder(RAW, Ticker, Date)
  RAW[, ME_l1 := shift(Size, 1L), by = Ticker]
  if (!is.null(to)) RAW <- RAW[Date <= as.Date(to)]
  K <- krf_calendar(RAW, as.integer(cfg$guards$trading_day_min_rows))
  RAW <- RAW[Date %in% K$cal$Date]
  SNAP <- krf_snap(RAW, K$me)
  AF <- krf_annual_fund(FUND)
  last <- max(K$cal$Date)
  yrs <- seq(as.integer(format(st, "%Y")) - 1L, as.integer(format(last, "%Y")))
  ANN <- krf_annual_labels(SNAP, AF, yrs, cfg)
  st_ym <- .ym_of(st)
  MOM <- krf_mom_labels(SNAP, cfg, .ym_add(st_ym, -1L))
  UM <- SNAP[member %in% TRUE & is.finite(ME) & ME > 0, .(Ticker, fym = ym)]
  RD <- RAW[Date >= st & is.finite(Ret) & is.finite(ME_l1) & ME_l1 > 0, .(Date, Ticker, Ret, ME_l1)]
  RD[, ym := .ym_of(Date)]
  fm <- as.integer(cfg$annual_sort$formation_month)
  RD[, `:=`(hy = .krf_hold_year(ym, fm), fym = .ym_add(ym, -1L))]
  CAP <- krf_caps(SNAP, cfg)
  if (is.null(CAP)) RD[, W := ME_l1] else {
    RD[CAP, cap := i.cap, on = .(fym)]
    RD[, W := fifelse(is.finite(cap), pmin(ME_l1, cap), NA_real_)]           # 직전 월말 상한 — 없으면 가중 없음(지어내지 않는다)
  }
  PD <- krf_daily_ports(RD, ANN$labels, MOM$labels, UM)
  capped_share <- if (is.null(CAP)) 0 else RD[is.finite(cap), mean(ME_l1 > cap)]
  ext <- RD[, .(n_abs_gt50 = sum(abs(Ret) > 0.5)), by = .(y = as.integer(format(Date, "%Y")))]
  rm(RD); gc(verbose = FALSE)
  # 일간 요인
  RFd <- krf_rf_daily(RFY, K$cal$Date[K$cal$Date >= st])
  FD <- krf_factors(PD[, .(k = Date, sort, port, r, n)])
  setnames(FD, "k", "Date")
  FD <- merge(FD, RFd, by = "Date", all.x = TRUE)
  FD[, MKT := MKT_TOTAL - RF]
  # 월간: 포트폴리오 일간 수익을 달 안에서 복리(그 달 거래일 전부 있어야 — 빠지면 NA)
  nd <- K$cal[, .(n_td = .N), by = ym]
  PD[, ym := .ym_of(Date)]
  PM <- PD[, .(r = prod(1 + r) - 1, n_days = .N, n_avg = mean(n), n_min = min(n)), by = .(sort, port, ym)]
  PM <- merge(PM, nd, by = "ym", all.x = TRUE)
  PM[n_days < n_td, r := NA_real_]
  RFm <- merge(RFd[, .(ym = .ym_of(Date), RF)][, .(RF = if (anyNA(RF)) NA_real_ else prod(1 + RF) - 1, n_rf = .N), by = ym], nd, by = "ym")
  RFm[n_rf < n_td, RF := NA_real_]
  FM <- krf_factors(PM[, .(k = ym, sort, port, r, n = n_avg)])
  setnames(FM, "k", "ym")
  FM <- merge(FM, RFm[, .(ym, RF)], by = "ym", all.x = TRUE)
  FM[, MKT := MKT_TOTAL - RF]
  FM <- merge(FM, K$me, by = "ym", all.x = TRUE)
  setnames(FM, "me_date", "Date")
  # 완결 월만 — 마지막 달은 그 달에 남은 평일이 없을 때만 싣는다(공휴일 판정 없이 보수적으로)
  lm <- .ym_of(last)
  m1 <- as.Date(sprintf("%04d-%02d-01", lm %/% 100L, lm %% 100L))
  m_end <- seq(m1, by = "1 month", length.out = 2L)[2L] - 1L
  rest <- if (last < m_end) seq(last + 1L, m_end, by = "day") else as.Date(character(0))
  if (any(as.integer(format(rest, "%u")) <= 5L)) FM <- FM[ym < lm]
  nsort <- ANN$labels[, .N, by = .(fy, sort)]
  FM[, hy := .krf_hold_year(ym, fm)]
  FM <- merge(FM, nsort[sort == "BM", .(hy = fy, n_obs_meta = as.numeric(N))], by = "hy", all.x = TRUE)
  FM[, hy := NULL]
  cols <- c("Date", "MKT", "SMB", "HML", "WML", "RMW", "CMA", "RF", "n_obs_meta", "SMB5", "SMB_BM", "SMB_OP", "SMB_INV", "MKT_TOTAL", "ym")
  setcolorder(FM, intersect(cols, names(FM)))
  setorder(FM, ym); setorder(FD, Date)
  CH <- krf_chars(SNAP, AF, cfg, st_ym)
  PMo <- merge(PM, K$me, by = "ym", all.x = TRUE)
  setnames(PMo, "me_date", "Date")
  list(daily = FD[Date >= st], monthly = FM[ym >= st_ym], ports_monthly = PMo[ym >= st_ym][order(sort, port, ym)],
       chars = CH, caps = CAP,
       diag = list(annual = ANN$diag, mom = MOM$diag, ret_abs_gt50_by_year = ext, last_date = last,
                   weighting = as.character(cfg$weighting$rule %||% "vw"), capped_row_share = capped_share))
}

## ── 입력 적재(실자료) ───────────────────────────────────────────────────────
krf_load_inputs <- function(root, cfg) {
  src <- fromJSON(file.path(root, cfg$fundamentals$registry), simplifyVector = TRUE)
  if (!identical(as.character(src$active), as.character(cfg$fundamentals$requires_active_source)))
    stop("[krf] 재무 원천 active = '", src$active, "' — 설정은 '", cfg$fundamentals$requires_active_source, "' 를 요구(fail-closed)")
  lb <- as.Date(cfg$lookback_start)
  cols <- c("Date", "Ticker", "Close", "Vol", "Size", "Ret", "AdminStock", "TradingHalt", "UnfaithfulDisc")
  RAW <- as.data.table(read_parquet(file.path(root, ".cache", "rawdata.parquet"), col_select = tidyselect::all_of(cols)))
  RAW[, Date := as.Date(Date)]
  RAW <- RAW[Date >= lb]
  # 측정 축 멤버십 — 정본 계약(위생 · 20일 거래대금 t−1 · 동전주 바닥)
  source(file.path(root, "02_Infrastructure", "contracts", "measurement_axis.R"), local = TRUE)
  ep <- ma_epoch(NULL, root)
  setorder(RAW, Ticker, Date)
  RAW[, member := ma_membership(RAW, ep)]
  RAW[, c("Vol", "AdminStock", "TradingHalt", "UnfaithfulDisc") := NULL]
  fp <- file.path(root, cfg$fundamentals$table)
  items <- KRF_FUND_ITEMS
  FUND <- as.data.table(open_dataset(fp) |> dplyr::filter(Item %in% items) |>
                          dplyr::select(dplyr::all_of(c("Ticker", "Period", "Item", "Value", "Factor_Date"))) |> dplyr::collect())
  bp <- file.path(root, cfg$rf$bond_path)
  RFY <- as.data.table(read_parquet(bp))[Series == cfg$rf$series, .(Date = as.Date(Date), y = as.numeric(Value))]
  if (!nrow(RFY)) stop("[krf] RF 계열 없음: ", cfg$rf$series)
  fi <- function(p) { x <- file.info(p); list(path = .krf_rel(p, root), size = unname(x$size), mtime = format(x$mtime, "%Y-%m-%dT%H:%M:%S")) }
  list(RAW = RAW, FUND = FUND, RFY = RFY, epoch = ep,
       inputs = list(rawdata = fi(file.path(root, ".cache", "rawdata.parquet")), fundamentals = fi(fp), rf = fi(bp),
                     fundamental_source_active = src$active))
}

## ── 쓰기 ────────────────────────────────────────────────────────────────────
.krf_rel <- function(p, base) {                    # 정규식 없이 접두 제거(한글 · 특수 문자 경로 안전)
  p <- gsub("\\\\", "/", p); b <- paste0(sub("/+$", "", gsub("\\\\", "/", base)), "/")
  if (startsWith(p, b)) substring(p, nchar(b) + 1L) else p
}

.krf_content_md5 <- function(DT, cols) {
  tf <- tempfile(fileext = ".csv")
  on.exit(unlink(tf), add = TRUE)
  X <- DT[, cols, with = FALSE]
  for (c in cols) if (is.numeric(X[[c]])) set(X, j = c, value = ifelse(is.na(X[[c]]), "NA", sprintf("%.12g", X[[c]])))
  fwrite(X, tf, eol = "\n")
  unname(tools::md5sum(tf))
}

.krf_atomic_parquet <- function(DT, path) {
  tmp <- paste0(path, ".tmp_", Sys.getpid())
  write_parquet(DT, tmp)
  if (file.exists(path) && !file.remove(path)) { unlink(tmp); stop("[krf] 기존 파일 제거 실패: ", path) }
  if (!file.rename(tmp, path)) stop("[krf] 이름 바꾸기 실패: ", path)
}

krf_summary <- function(FM) {
  f <- c("MKT", "SMB", "SMB5", "HML", "RMW", "CMA", "WML", "RF")
  rbindlist(lapply(intersect(f, names(FM)), function(c) {
    x <- FM[[c]]; ok <- is.finite(x)
    data.table(factor = c, n = sum(ok), first = if (any(ok)) format(min(FM$Date[ok])) else NA_character_,
               mean_pct = round(100 * mean(x[ok]), 4), sd_pct = round(100 * stats::sd(x[ok]), 4),
               t_simple = round(mean(x[ok]) / (stats::sd(x[ok]) / sqrt(sum(ok))), 3))
  }))
}

krf_write <- function(res, out, cfg, inputs, epoch, vintage = TRUE) {
  dir.create(out, recursive = TRUE, showWarnings = FALSE)
  o <- cfg$outputs
  .krf_atomic_parquet(res$daily, file.path(out, o$daily))
  .krf_atomic_parquet(res$monthly, file.path(out, o$monthly))
  .krf_atomic_parquet(res$ports_monthly, file.path(out, o$ports_monthly))
  .krf_atomic_parquet(res$chars, file.path(out, o$chars_monthly))
  mcols <- c("Date", "MKT", "SMB", "HML", "WML", "RMW", "CMA", "RF", "SMB5")
  md5m <- .krf_content_md5(res$monthly, mcols)
  vint <- NULL
  if (isTRUE(vintage)) {
    vd <- file.path(out, o$vintage_dir); dir.create(vd, showWarnings = FALSE)
    vint <- file.path(vd, paste0(substr(md5m, 1, 12), ".parquet"))
    if (!file.exists(vint)) write_parquet(res$monthly, vint)
  }
  ad <- res$diag$annual
  meta <- list(
    schema = "kr_factor_returns_meta_v1", builder = KRF_BUILDER, cfg_version = cfg$version,
    built_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    epoch = epoch$id, universe = epoch$universe, inputs = inputs,
    weighting = list(rule = res$diag$weighting, cap_quantile = cfg$weighting$cap_quantile %||% NA,
                     capped_row_share = round(res$diag$capped_row_share, 4)),
    last_input_date = format(res$diag$last_date),
    daily = list(rows = nrow(res$daily), first = format(min(res$daily$Date)), last = format(max(res$daily$Date))),
    monthly = list(rows = nrow(res$monthly), first = format(min(res$monthly$Date)), last = format(max(res$monthly$Date)),
                   content_md5 = md5m, content_cols = mcols,
                   vintage_file = if (is.null(vint)) NULL else .krf_rel(vint, out)),
    summary_monthly = krf_summary(res$monthly),
    annual_sorts = ad[, .(fy, sort, fdate = format(fdate), n_universe, n_sort, n_big, ok)],
    momentum_sort_n = list(median = stats::median(res$diag$mom$n_sort), min = min(res$diag$mom$n_sort)),
    ret_abs_gt50_by_year = res$diag$ret_abs_gt50_by_year,
    columns = list(MKT = "시장 초과수익 = MKT_TOTAL − RF", RF = "CD91 전 거래일 금리의 일간 환산 복리(월간 = 그 달 복리)",
                   SMB = "3요인판(B/M 정렬)", SMB5 = "5요인판(B/M · OP · INV 정렬 평균)", WML = "모멘텀(UMD)",
                   n_obs_meta = "그 보유연도 B/M 정렬 종목 수")
  )
  writeLines(toJSON(meta, auto_unbox = TRUE, pretty = TRUE, digits = NA, na = "null", null = "null"),
             file.path(out, o$meta), useBytes = TRUE)
  invisible(meta)
}

## ── 실행 ────────────────────────────────────────────────────────────────────
krf_main <- function(args = commandArgs(trailingOnly = TRUE)) {
  root <- krf_root()
  arg <- function(k) { i <- match(k, args); if (is.na(i) || i == length(args)) NULL else args[i + 1L] }
  out <- arg("--out") %||% file.path(root, ".cache")
  to <- arg("--to")
  t0 <- Sys.time()
  cfg <- krf_config(root)
  cat(sprintf("[krf] %s · 설정 %s · out = %s\n", KRF_BUILDER, cfg$version, out))
  I <- krf_load_inputs(root, cfg)
  cat(sprintf("[krf] 입력: RAWDATA %s행 · 재무 %s행 · RF %s일 · epoch %s (%.0fs)\n", format(nrow(I$RAW), big.mark = ","),
              format(nrow(I$FUND), big.mark = ","), format(nrow(I$RFY), big.mark = ","), I$epoch$id,
              as.numeric(difftime(Sys.time(), t0, units = "secs"))))
  res <- krf_build(I$RAW, I$FUND, I$RFY, cfg, to = to)
  meta <- krf_write(res, out, cfg, I$inputs, I$epoch, vintage = !("--no-vintage" %in% args))
  cat(sprintf("[krf] 일간 %d행(%s~%s) · 월간 %d행(%s~%s) · 특성 %d행 · 월간 내용 md5 %s (%.0fs)\n",
              meta$daily$rows, meta$daily$first, meta$daily$last, meta$monthly$rows, meta$monthly$first, meta$monthly$last,
              nrow(res$chars), substr(meta$monthly$content_md5, 1, 12), as.numeric(difftime(Sys.time(), t0, units = "secs"))))
  print(meta$summary_monthly)
  invisible(meta)
}

if (sys.nframe() == 0L) krf_main()
