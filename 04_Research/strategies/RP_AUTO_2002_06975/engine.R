# =============================================================================
# engine.R — RP_AUTO_2002_06975  (1판 · 2026-09-13)
# Masaya Abe · Kei Nakagawa, "Cross-sectional Stock Price Prediction using Deep Learning
#   for Actual Investment Management"  arXiv:2002.06975 (v1 2020-02-17)
#   https://arxiv.org/abs/2002.06975 — 본문 = r.jina.ai PDF 텍스트 프록시(2020 논문 · arxiv html 렌더 없음)
#
# ★라벨(adapted)·변경 전수 신고·러너 사양의 정본 = FIDELITY.json. 이 주석은 아무것도 결정하지 않는다.
#   코드 옆 ★changed(n) 표식 = FIDELITY.json changed 의 항목 번호.
#
# 논문 기전(그대로): 매일 종가 시점에 33 팩터(Table 1)를 유니버스 안 오름차순 순위/최대순위 로 0~1 재척도 →
#   DNN(Table 2 DNN5: 300-300-150-150-50 · dropout 50-50-30-30-10% · ReLU · batch norm · Adam · MSE ·
#   mini-batch 500 · 20 epoch · truncated normal 초기화 sd=sqrt(2/M)) 으로 5일 뒤 수익
#   y_{t+5} = p^c_{t+5}/p^o_{t+1} − 1 의 **횡단면 순위 재척도값**을 회귀 → 최신 1,000 일치 학습집합으로
#   5영업일마다 재학습 → 예측 점수 상위 5분위 EW 롱 / 하위 5분위 EW 숏.
#
# 이 구현: 특성 32종(No.32 설비투자 증가율은 KR 패널에 항목이 없어 제외 · changed(9)) 을 RAWDATA(가격·거래량·
#   시총) + QuantiWise 컨센서스(영업이익 FY1 · 목표주가) + 재무 패널(DART 연간 + QuantiWise 분기 → 연간) 에서
#   원값으로 계산하고, 그날 K200∪KQ150 적격 집합 안에서 순위 재척도. DNN 학습·예측은 venv torch(CPU)
#   파이썬 서브프로세스(아래 .PY_SRC · 이 파일이 매 실행 _work/ 에 써 넣는다)가 맡는다.
#   하네스가 월간 집행이라 시그널은 **각 달력월 마지막 거래일 1행**만 낸다(changed(3)) — 그 날 유효한 모델
#   = 5영업일 격자에서 그 날 이전 마지막 갱신점 u 의 모델(학습집합 = s ∈ [u−1004, u−5] · 표적이 u 까지 실현된 집합).
#
# 산출: FACTORS(Date, Ticker, Score)          — 그날 적격 종목 전부 · Score = DNN 예측(순위 척도)
#       PORTFOLIO(Date, Ticker, Weight, Leg)  — 상위 5분위 롱 EW Σ=+1 / 하위 5분위 숏 EW Σ=−1
#
# PIT(C1~C15) 구조 보장: 시그널일 t 의 특성 = t 이하 데이터(수익·거래대금 = t 까지의 종가·거래량, 컨센서스 =
#   t 이하 관측, 재무 = usable(FY+1 3/31) ≤ t). 학습 표적 y_s 는 s+5 종가로 실현되며 파이썬이 lab_i ≤ u_i 를
#   단언하고 R 이 diag 로 재단언한다. 전 표본 통계 0건(순위 = 그날 횡단면 · 창 = 롤링) · 팩터 DB 미사용.
#   유동성 스크린 없음(논문 우선 · changed(2)).
# =============================================================================

suppressWarnings(suppressMessages({
  library(data.table)
  library(arrow)
}))

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
.TAG <- "[RP_AUTO_2002_06975]"
.t0 <- Sys.time()
.REQ <- c("Date", "Ticker", "Close", "Vol", "Size", "K200", "KQ150")
if (!all(.REQ %in% names(RAWDATA)))
  stop(sprintf("%s RAWDATA 필수 열 부재: %s", .TAG, paste(setdiff(.REQ, names(RAWDATA)), collapse = ", ")))
.HAS_OPEN <- "Open" %in% names(RAWDATA)

# =============================================================================
# 0. 상수 — 논문 명시값 + 논문이 침묵하는 규약(전부 FIDELITY.json changed 신고)
# =============================================================================
.RET_K    <- c(1L, 2L, 3L, 5L, 10L, 20L, 40L, 60L)   # Table 1 No.1~8: k일 전 대비 수익 (changed(7) 해석)
.TV_LONG  <- 60L                                     # Table 1 No.9: 60일 평균 거래대금
.TV_SHORT <- c(5L, 10L, 20L)                         # Table 1 No.10~12: 5/10/20일 평균 ÷ 60일 평균
.CONS_K   <- c(5L, 10L, 20L)                         # Table 1 No.13~18: 5/10/20일 전 대비 전망 변화
.HORIZON  <- 5L                                      # 표적 = p^c_{t+5}/p^o_{t+1} − 1
.N_TRAIN  <- 1000L                                   # "latest 1,000 sets of training data"
.UPD_EVERY <- 5L                                     # "updated every five business days"
.QUINT    <- 5L                                      # top / bottom quintile
.START    <- as.Date("2005-01-01")                   # 고정 축 — 이 날 이후 시그널만 발행
.ANCHOR   <- as.Date("2001-01-01")                   # ★changed(3) 5영업일 갱신 격자 앵커(첫 거래일 ≥ 이 날)
.GRID_FROM <- as.Date("2000-06-01")                  # ★changed(12) 격자 시작(학습창 1,000일 + 특성 창 60일 선행)
.CONS_ROLL <- 7L                                     # ★changed(7) 컨센서스 관측 → 거래일 격자 캐리 상한(달력일)
.FUND_ROLL <- 456L                                   # ★changed(8) 연간 재무 usable 이후 캐리 상한(달력일 ≈ 15개월)
.MIN_N    <- 10L                                     # ★changed(11) 5분위 정의역(다리당 ≥ 2)
.SEED_BASE <- 20020697L                              # ★changed(6) 시드 = 논문 번호(임의 상수) + 월 인덱스
.N_WORKERS_MAX <- 4L                                 # ★changed(15) 파이썬 워커 프로세스 상한
.FEATS <- sprintf("x%02d", 1:32)
.FEAT_NAMES <- c("ret_1d", "ret_2d", "ret_3d", "ret_5d", "ret_10d", "ret_20d", "ret_40d", "ret_60d",
                 "tv_60d", "tv_5d/60d", "tv_10d/60d", "tv_20d/60d",
                 "op_fcst_chg_5d", "op_fcst_chg_10d", "op_fcst_chg_20d",
                 "tp_chg_5d", "tp_chg_10d", "tp_chg_20d",
                 "B/P", "E/P", "DY", "S/P", "CF/P", "ROE", "ROA", "ROIC", "accruals", "asset_turnover",
                 "current_ratio", "equity_ratio", "asset_growth", "invest_to_asset")
stopifnot(length(.FEATS) == length(.FEAT_NAMES))

# =============================================================================
# 1. 루트·캐시·파이썬 해석 (r-portability: 표지 파일 검증 · env= 미사용 · 셸 연산자 미사용)
# =============================================================================
.find_root <- function() {
  cands <- c(Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""),
             if (exists("PROJECT_ROOT", inherits = TRUE)) as.character(get("PROJECT_ROOT", inherits = TRUE))[1] else "",
             getwd())
  marker <- "02_Infrastructure/hooks/qvest_hook_router.py"
  for (p in cands) {
    if (!nzchar(p)) next
    p <- gsub("\\\\", "/", p)
    if (file.exists(file.path(p, marker))) return(p)
  }
  stop(sprintf("%s 프로젝트 루트를 찾지 못함(표지 %s) — CLAUDE_PROJECT_DIR/QM_ROOT 확인", .TAG, marker))
}
.ROOT  <- .find_root()
.CACHE <- if (exists("CACHE_DIR", inherits = TRUE)) as.character(get("CACHE_DIR", inherits = TRUE))[1] else file.path(.ROOT, ".cache")
.WD    <- file.path(.ROOT, "04_Research", "strategies", "RP_AUTO_2002_06975", "_work")
dir.create(.WD, recursive = TRUE, showWarnings = FALSE)
.PY <- file.path(.ROOT, ".venv_qvest_ml", "Scripts", "python.exe")
if (!file.exists(.PY)) .PY <- Sys.getenv("QVEST_PY", "")
if (!nzchar(.PY) || !file.exists(.PY))
  stop(sprintf("%s 파이썬 실행기 부재(.venv_qvest_ml/Scripts/python.exe · QVEST_PY) — DNN 학습 불가", .TAG))
.probe <- suppressWarnings(system2(.PY, c("-c", shQuote("import torch, pyarrow, pandas, numpy; print(torch.__version__)")),
                                   stdout = TRUE, stderr = TRUE))
.probe_st <- attr(.probe, "status"); .probe_st <- if (is.null(.probe_st)) 0L else as.integer(.probe_st)
if (.probe_st != 0L)
  stop(sprintf("%s venv 파이썬에서 torch/pyarrow/pandas/numpy import 실패(rc %d): %s", .TAG, .probe_st,
               paste(.probe, collapse = " | ")))
cat(sprintf("%s root %s · cache %s · python %s (torch %s)\n", .TAG, .ROOT, .CACHE, .PY, paste(.probe, collapse = " ")))

# =============================================================================
# 2. 헬퍼 + 양성 대조 (구현 결함 = 중단 · 조용한 F 방지)
# =============================================================================
# 논문 전처리: "ranking each input value in ascending order by stock universe at each day and then dividing by
#   the maximum rank value" — 동률 = 평균 순위 · 결측 = 0.5(중앙값 대치 · 논문 미명시 · changed(10))
.rank01 <- function(x) {
  ok <- is.finite(x); out <- rep(0.5, length(x)); n <- sum(ok)
  if (n >= 1L) { r <- frank(x[ok], ties.method = "average"); out[ok] <- r / max(r) }
  out
}
.sdiv <- function(a, b) fifelse(is.finite(a) & is.finite(b) & b > 0, a / b, NA_real_)      # 양(+) 분모만 (changed(8))
.chg  <- function(v, k) {                                                                  # (F_t − F_{t−k}) / |F_{t−k}| (changed(7))
  l <- shift(v, k)
  fifelse(is.finite(v) & is.finite(l) & abs(l) > 0, (v - l) / abs(l), NA_real_)
}
.nz <- function(x) fifelse(is.finite(x), x, 0)                                             # 차입·현금 결측 = 0 (DART ROIC 규약)

local({
  r <- .rank01(c(3, NA, 1, 2, 2))
  if (!isTRUE(all.equal(r, c(1, 0.5, 0.25, 0.625, 0.625)))) stop(sprintf("%s 순위 재척도 검산 실패", .TAG))
  if (!isTRUE(all.equal(.rank01(c(NA_real_, NA_real_)), c(0.5, 0.5)))) stop(sprintf("%s 전 결측 순위 검산 실패", .TAG))
  # 합성 12일 종목: 종가 = 100·1.01^i, 시가 = 종가·0.99 — k일 수익·표적 정렬을 폐형과 대조
  d <- data.table(Ticker = "T", Date = as.Date("2020-01-01") + 0:11, di = 1:12)
  d[, Close := 100 * 1.01^(0:11)]; d[, Open := Close * 0.99]
  d[, r5 := Close / shift(Close, 5L) - 1, by = Ticker]
  if (!isTRUE(all.equal(d$r5[6], 1.01^5 - 1))) stop(sprintf("%s k일 수익 검산 실패", .TAG))
  d[, lab_end := Close / shift(Open, .HORIZON - 1L) - 1, by = Ticker]
  lab <- d[, .(s_date = shift(Date, .HORIZON), lab_i = di, y_raw = lab_end), by = Ticker][!is.na(s_date) & is.finite(y_raw)]
  d[lab, on = .(Ticker, Date = s_date), c("y_raw", "lab_i") := .(i.y_raw, i.lab_i)]
  # 집합 s = 1행(Date 01-01): 표적 = Close[6]/Open[2] − 1, 실현 인덱스 6
  want <- d$Close[6] / d$Open[2] - 1
  if (!isTRUE(all.equal(d$y_raw[1], want)) || !identical(d$lab_i[1], 6L)) stop(sprintf("%s 표적 정렬 검산 실패", .TAG))
  if (!all(is.na(d$y_raw[8:12]))) stop(sprintf("%s 표적 말단 결측 검산 실패", .TAG))
  ch <- .chg(c(10, 11, 12, -6, 0, 3), 2L)
  if (!isTRUE(all.equal(ch, c(NA, NA, 0.2, (-6 - 11) / 11, -1, (3 + 6) / 6)))) stop(sprintf("%s 전망 변화율 검산 실패", .TAG))
  cat(sprintf("%s 양성 대조 통과 — 순위 재척도 · k일 수익 · 표적 정렬(s→s+5 · 시가 s+1) · 전망 변화율\n", .TAG))
})

# =============================================================================
# 3. 거래일 격자 × 적격 이력 종목 (RAWDATA 비파괴)  ★changed(1)(12)
#    열 정체: Close·Open = 수정주가 · Vol = 주식수 거래량 · Size = 시가총액(KRW) · K200/KQ150 = 그날 멤버십 플래그
# =============================================================================
.cal <- sort(unique(RAWDATA$Date)); .cal <- .cal[.cal >= .GRID_FROM]
.CAL <- data.table(Date = .cal, di = seq_along(.cal))
.cols <- c(.REQ, if (.HAS_OPEN) "Open")
.rd <- RAWDATA[Date >= .GRID_FROM & is.finite(Close) & Close > 0, .cols, with = FALSE]
.rd[, Ticker := as.character(Ticker)]
.rd[, MEM := (K200 == TRUE | KQ150 == TRUE) %in% TRUE]
.rd[, c("K200", "KQ150") := NULL]
if (!.HAS_OPEN) .rd[, Open := NA_real_]
.rd[, Open := as.numeric(Open)]; .rd[!is.finite(Open) | Open <= 0, Open := NA_real_]          # 0·결측 시가 = 센티널 → NA (changed(10))
.rd[, Vol := as.numeric(Vol)]; .rd[, Size := as.numeric(Size)]
.ndup <- sum(duplicated(.rd, by = c("Ticker", "Date")))
if (.ndup > 0L) { cat(sprintf("%s (Ticker,Date) 중복 %d행 — 첫 행만 유지\n", .TAG, .ndup)); .rd <- unique(.rd, by = c("Ticker", "Date")) }
.mem_tk <- sort(unique(.rd$Ticker[.rd$MEM]))
if (length(.mem_tk) < 50L) stop(sprintf("%s 적격 이력 종목 %d — 멤버십 플래그 확인", .TAG, length(.mem_tk)))
.rd <- .rd[Ticker %in% .mem_tk]
.G <- CJ(Ticker = .mem_tk, Date = .cal)
.G <- .rd[.G, on = .(Ticker, Date)]
.G[is.na(MEM), MEM := FALSE]
.G[.CAL, on = "Date", di := i.di]
setorder(.G, Ticker, Date)
.n_raw <- nrow(.rd); rm(.rd)
cat(sprintf("%s 격자 %d거래일(%s ~ %s) × 적격 이력 종목 %d = %d행 (관측 %d행) · Open 열 %s · 마지막 날 적격 %d종\n",
            .TAG, nrow(.CAL), as.character(min(.cal)), as.character(max(.cal)), length(.mem_tk), nrow(.G), .n_raw,
            if (.HAS_OPEN) "있음" else "없음(표적 진입가 = 종가 대체 · changed(10))",
            .G[Date == max(.cal), sum(MEM)]))

# =============================================================================
# 4. 가격·거래량 특성 (Table 1 No.1~12) + 표적 — 종목별 행 이동 = 거래일 이동(격자가 달력 완비)
# =============================================================================
.G[, (.FEATS[1:8]) := lapply(.RET_K, function(k) Close / shift(Close, k) - 1), by = Ticker]
.G[, dv := fifelse(is.finite(Vol) & Vol > 0, Vol * Close, NA_real_)]                           # 거래대금 KRW ≈ 거래량 × 수정종가 (changed(7))
.G[, tv60 := frollmean(dv, .TV_LONG, na.rm = TRUE, hasNA = TRUE), by = Ticker]
.G[, c("tv5", "tv10", "tv20") := lapply(.TV_SHORT, function(k) frollmean(dv, k, na.rm = TRUE, hasNA = TRUE)), by = Ticker]
.G[, x09 := fifelse(is.finite(tv60) & tv60 > 0, tv60, NA_real_)]
.G[, x10 := .sdiv(tv5, tv60)]; .G[, x11 := .sdiv(tv10, tv60)]; .G[, x12 := .sdiv(tv20, tv60)]
.G[, c("dv", "tv60", "tv5", "tv10", "tv20") := NULL]
# 표적: 행 r 에서 Close[r]/Open[r−4] − 1 = 집합 s = r−5 의 5일 수익(진입 = s+1 시가 · 청산 = s+5 종가 · 실현일 = r).
#   집합 s 에 붙이되 실현 인덱스 lab_i 를 함께 실어 학습 시점 u 에서 lab_i ≤ u 를 단언한다(파이썬 + R 이중).
.G[, lab_end := Close / shift(Open, .HORIZON - 1L) - 1, by = Ticker]
if (!.HAS_OPEN) .G[, lab_end := Close / shift(Close, .HORIZON) - 1, by = Ticker]              # changed(10) 시가 열 부재 시만
.LAB <- .G[, .(s_date = shift(Date, .HORIZON), lab_i = di, y_raw = lab_end), by = Ticker]
.LAB <- .LAB[!is.na(s_date) & is.finite(y_raw)]
.G[.LAB, on = .(Ticker, Date = s_date), c("y_raw", "lab_i") := .(i.y_raw, i.lab_i)]
rm(.LAB); .G[, lab_end := NULL]
.n_ext_d <- .G[MEM == TRUE & is.finite(x01), sum(abs(x01) > 0.5)]
.n_ext_y <- .G[MEM == TRUE & is.finite(y_raw), sum(abs(y_raw) > 1)]
cat(sprintf("%s 가격 특성 8 + 거래대금 특성 4 + 표적 완료 · 적격행 |1일 수익|>50%% %d건 · |5일 표적|>100%% %d건 (원천 이음매 결함이 남아 있으면 여기 드러난다 — 값 절단 없음)\n",
            .TAG, .n_ext_d, .n_ext_y))

# =============================================================================
# 5. 컨센서스 특성 (Table 1 No.13~18) — QuantiWise 영업이익 FY1 · 목표주가 (논문 I/B/E/S 의 KR 대응 · changed(7))
# =============================================================================
.read_cons <- function(metric) {
  p <- file.path(.CACHE, "consensus", paste0(metric, ".parquet"))
  if (!file.exists(p)) stop(sprintf("%s 컨센서스 패널 부재: %s — Table 1 No.13~18 원천. data_gap 적재 대상", .TAG, p))
  d <- as.data.table(read_parquet(p))
  if (!all(c("Date", "Ticker", metric) %in% names(d))) stop(sprintf("%s 컨센서스 %s 스키마 불일치: %s", .TAG, metric, paste(names(d), collapse = ",")))
  d <- d[, c("Date", "Ticker", metric), with = FALSE]
  setnames(d, metric, "v")
  if (!inherits(d$Date, "Date")) d[, Date := as.Date(Date)]
  d[, Ticker := as.character(Ticker)]
  d <- d[is.finite(v) & Ticker %in% .mem_tk]
  d <- unique(d, by = c("Ticker", "Date"))
  setorder(d, Ticker, Date)
  d
}
.op <- .read_cons("op_profit_fy1")
.tp <- .read_cons("target_price")
if (nrow(.op) == 0L || nrow(.tp) == 0L)
  stop(sprintf("%s 컨센서스 패널이 적격 종목과 0행 교차(op %d · tp %d) — Ticker 형식(A######) 확인", .TAG, nrow(.op), nrow(.tp)))
.G[, op := .op[.G[, .(Ticker, Date)], on = .(Ticker, Date), roll = .CONS_ROLL, x.v]]           # 관측 ≤ t · 캐리 ≤ 7달력일
.G[, tp := .tp[.G[, .(Ticker, Date)], on = .(Ticker, Date), roll = .CONS_ROLL, x.v]]
.G[, (.FEATS[13:15]) := lapply(.CONS_K, function(k) .chg(op, k)), by = Ticker]
.G[, (.FEATS[16:18]) := lapply(.CONS_K, function(k) .chg(tp, k)), by = Ticker]
cat(sprintf("%s 컨센서스: 영업이익 FY1 %d행(%s~%s) · 목표주가 %d행(%s~%s) · 적격행 커버리지 op %.1f%% · tp %.1f%%\n",
            .TAG, nrow(.op), as.character(min(.op$Date)), as.character(max(.op$Date)),
            nrow(.tp), as.character(min(.tp$Date)), as.character(max(.tp$Date)),
            100 * .G[MEM == TRUE, mean(is.finite(op))], 100 * .G[MEM == TRUE, mean(is.finite(tp))]))
.G[, c("op", "tp") := NULL]; rm(.op, .tp); gc(verbose = FALSE)

# =============================================================================
# 6. 스케줄 — 월말 시그널 · 5영업일 갱신 격자 · 학습창 [u−1004, u−5]  ★changed(3)(5)
# =============================================================================
.CAL[, MI := year(Date) * 12L + month(Date)]
.me <- .CAL[, .(Date = max(Date), di = max(di)), by = MI]
setorder(.me, MI)
.me <- .me[MI < max(MI) & Date >= .START]                                                     # 마지막 달력월 = 부분월 → 제외
.anchor_i <- .CAL[Date >= .ANCHOR, min(di)]
.grid5 <- .CAL[di >= .anchor_i & ((di - .anchor_i) %% .UPD_EVERY) == 0L, di]
.SCH <- .me[, {
  u <- max(.grid5[.grid5 <= di])
  .(pred_i = di, u_i = u, smax_i = u - .HORIZON, smin_i = u - .HORIZON - (.N_TRAIN - 1L))
}, by = .(MI, Date)]
.n_sched_all <- nrow(.SCH)
.SCH <- .SCH[smin_i >= 1L]
setorder(.SCH, pred_i)
.SCH[, k := seq_len(.N)]
.SCH[, seed := .SEED_BASE + k]
if (nrow(.SCH) < 12L) stop(sprintf("%s 스케줄 월 %d개 — 격자 범위 확인", .TAG, nrow(.SCH)))
.PANEL_FROM_I <- min(.SCH$smin_i)
cat(sprintf("%s 스케줄 %d개월(%s ~ %s · 학습창 미달로 제외 %d) · 갱신 격자 앵커 %s · 첫 달: 갱신 %s · 학습집합 %s ~ %s\n",
            .TAG, nrow(.SCH), as.character(min(.SCH$Date)), as.character(max(.SCH$Date)), .n_sched_all - nrow(.SCH),
            as.character(.CAL$Date[.anchor_i]), as.character(.CAL$Date[.SCH$u_i[1]]),
            as.character(.CAL$Date[.SCH$smin_i[1]]), as.character(.CAL$Date[.SCH$smax_i[1]])))

# =============================================================================
# 7. 재무 특성 (Table 1 No.19~31, 33) — fundamental_merged.parquet 원값 → 연간(FY) → usable FY+1 3/31  ★changed(8)(9)
#    학습·예측에 쓰는 행 = 적격(MEM) ∧ di ≥ 첫 학습창 시작 — 여기서부터 패널 .P 로 좁힌다
# =============================================================================
.P <- .G[MEM == TRUE & di >= .PANEL_FROM_I]
rm(.G); gc(verbose = FALSE)
.FLOW_ITEMS <- c("Revenue", "OperatingProfit", "PretaxIncome", "TaxExpense", "NetIncome", "OperatingCF", "Dividends")
.BS_ITEMS   <- c("TotalAssets", "CurrentAssets", "CurrentLiab", "TotalEquity", "TangibleAssets", "Inventory",
                 "CashAndEquiv", "ShortTermBorr", "LongTermBorr")
.FUND_ITEMS <- c(.FLOW_ITEMS, .BS_ITEMS)
.fm_path <- file.path(.CACHE, "fundamental_merged.parquet")
if (!file.exists(.fm_path)) stop(sprintf("%s 재무 패널 부재: %s — Table 1 No.19~33 원천. data_gap 적재 대상", .TAG, .fm_path))
.fm <- as.data.table(dplyr::collect(dplyr::filter(arrow::open_dataset(.fm_path),
                                                  Item %in% .FUND_ITEMS, Source %in% c("DART", "XLSX"))))
if (!all(c("Ticker", "Period", "Item", "Value", "Source") %in% names(.fm)))
  stop(sprintf("%s 재무 패널 스키마 불일치: %s", .TAG, paste(names(.fm), collapse = ",")))
.fm[, Ticker := as.character(Ticker)]
.fm <- .fm[Ticker %in% .mem_tk & is.finite(Value)]
if (nrow(.fm) == 0L) stop(sprintf("%s 재무 패널이 적격 종목과 0행 교차 — Ticker 형식 확인", .TAG))
.fm[, Period := as.character(Period)]
.fm[, FY := as.integer(substr(Period, 1L, 4L))]
.fm[, MM := as.integer(substr(Period, 5L, 6L))]
.fm <- .fm[is.finite(FY) & MM %in% c(3L, 6L, 9L, 12L)]
# (a) 유량 항목 — DART 행 = 사업연도 합계 그대로 · XLSX 행 = 분기 관측 → 연간화. XLSX 분기값이 단일분기 유량인지
#     누적(YTD)인지는 패널 문서가 못 박지 않아 데이터 형식으로 판별한다: 매출 4분기 합 ÷ 12월 분기값 중앙값이 3 을 넘으면
#     단일분기(합산), 아니면 누적(12월 값 채택). 성과와 무관한 형식 판별이며 로그에 남긴다(changed(8)).
.fx <- .fm[Item %in% .FLOW_ITEMS]
.xq <- .fx[Source == "XLSX", .(n_q = uniqueN(MM), s4 = sum(Value), q4 = sum(Value[MM == 12L]), has12 = any(MM == 12L)),
           by = .(Ticker, FY, Item)]
.rr <- .xq[Item == "Revenue" & n_q == 4L & q4 > 0 & s4 > 0, s4 / q4]
.rr_med <- if (length(.rr)) median(.rr) else NA_real_
.XFLOW_QTR <- is.finite(.rr_med) && .rr_med > 3
.xa <- if (isTRUE(.XFLOW_QTR)) .xq[n_q == 4L, .(Ticker, FY, Item, Value = s4)] else .xq[has12 == TRUE, .(Ticker, FY, Item, Value = q4)]
.da <- .fx[Source == "DART" & MM == 12L, .(Ticker, FY, Item, Value)]
.fl <- rbind(.da[, pri := 1L], .xa[, pri := 2L])
setorder(.fl, Ticker, FY, Item, pri)
.fl <- unique(.fl, by = c("Ticker", "FY", "Item"))[, pri := NULL]
# (b) 시점 항목 — 12월 말 값 (분기 3/6/9 는 쓰지 않는다 · 결산월 12 기준 = changed(8))
.bs <- .fm[Item %in% .BS_ITEMS & MM == 12L, .(Ticker, FY, Item, Value)]
.FA <- dcast(rbind(.fl, .bs), Ticker + FY ~ Item, value.var = "Value")
for (it in .FUND_ITEMS) if (!it %in% names(.FA)) .FA[, (it) := NA_real_]
.n_ni_x <- .FA[!is.finite(NetIncome) & is.finite(PretaxIncome) & is.finite(TaxExpense), .N]
.FA[!is.finite(NetIncome) & is.finite(PretaxIncome) & is.finite(TaxExpense), NetIncome := PretaxIncome - TaxExpense]   # XLSX 에 순이익 항목 없음 (changed(8))
setorder(.FA, Ticker, FY)
.FA[, FY_prev := shift(FY), by = Ticker]
.FA[, TA_prev := shift(TotalAssets), by = Ticker]
.FA[, TAN_prev := shift(TangibleAssets), by = Ticker]
.FA[, INV_prev := shift(Inventory), by = Ticker]
.FA[!(is.finite(FY_prev) & FY_prev == FY - 1L), c("TA_prev", "TAN_prev", "INV_prev") := NA_real_]           # 직전 연도만
.FA[, nopat := fifelse(is.finite(OperatingProfit) & is.finite(TaxExpense) & is.finite(PretaxIncome) & PretaxIncome != 0,
                       OperatingProfit * (1 - TaxExpense / PretaxIncome), NA_real_)]                          # DART 정의
.FA[, invcap := fifelse(is.finite(TotalEquity), TotalEquity + .nz(ShortTermBorr) + .nz(LongTermBorr) - .nz(CashAndEquiv), NA_real_)]
.FA[, f_roe := .sdiv(NetIncome, TotalEquity)]
.FA[, f_roa := .sdiv(NetIncome, TotalAssets)]
.FA[, f_roic := .sdiv(nopat, invcap)]
.FA[, f_acc := fifelse(is.finite(NetIncome) & is.finite(OperatingCF) & is.finite(TotalAssets) & TotalAssets > 0,
                       (NetIncome - OperatingCF) / TotalAssets, NA_real_)]
.FA[, f_at := .sdiv(Revenue, TotalAssets)]
.FA[, f_cr := .sdiv(CurrentAssets, CurrentLiab)]
.FA[, f_er := .sdiv(TotalEquity, TotalAssets)]
.FA[, f_ag := fifelse(is.finite(TotalAssets) & is.finite(TA_prev) & TA_prev > 0, TotalAssets / TA_prev - 1, NA_real_)]
.FA[, f_ita := fifelse(is.finite(TangibleAssets) & is.finite(TAN_prev) & is.finite(Inventory) & is.finite(INV_prev) &
                         is.finite(TA_prev) & TA_prev > 0,
                       ((TangibleAssets - TAN_prev) + (Inventory - INV_prev)) / TA_prev, NA_real_)]           # LSZ(2008) 정의 (changed(9))
.FA[, f_div := fifelse(is.finite(Dividends), abs(Dividends), NA_real_)]
.FA[, usable := as.Date(sprintf("%d-03-31", FY + 1L))]                                                    # C4: 사업연도 익년 3/31 (changed(8))
.FA <- .FA[, .(Ticker, usable, FY, TotalEquity, NetIncome, f_div, Revenue, OperatingCF,
               f_roe, f_roa, f_roic, f_acc, f_at, f_cr, f_er, f_ag, f_ita)]
setorder(.FA, Ticker, usable)
.fcols <- c("FY", "TotalEquity", "NetIncome", "f_div", "Revenue", "OperatingCF",
            "f_roe", "f_roa", "f_roic", "f_acc", "f_at", "f_cr", "f_er", "f_ag", "f_ita")
.tmp <- .FA[.P[, .(Ticker, Date)], on = .(Ticker, usable = Date), roll = .FUND_ROLL]                  # usable ≤ Date · 캐리 ≤ 456일
.P[, (.fcols) := .tmp[, .fcols, with = FALSE]]
rm(.tmp, .fx, .xq, .xa, .da, .fl, .bs, .fm)
.P[, x19 := .sdiv(TotalEquity, Size)]
.P[, x20 := .sdiv(NetIncome, Size)]
.P[, x21 := .sdiv(f_div, Size)]
.P[, x22 := .sdiv(Revenue, Size)]
.P[, x23 := .sdiv(OperatingCF, Size)]
.P[, x24 := f_roe]; .P[, x25 := f_roa]; .P[, x26 := f_roic]; .P[, x27 := f_acc]; .P[, x28 := f_at]
.P[, x29 := f_cr]; .P[, x30 := f_er]; .P[, x31 := f_ag]; .P[, x32 := f_ita]
.fund_cov <- .P[, mean(is.finite(FY))]
.P[, (.fcols) := NULL]
cat(sprintf("%s 재무: FY 행 %d(%d종 · FY %d~%d) · XLSX 분기값 형식 = %s(매출 4분기합/12월값 중앙 %s · n=%d) · XLSX 순이익 = 세전−법인세 대치 %d행 · 패널 커버리지 %.1f%%\n",
            .TAG, nrow(.FA), uniqueN(.FA$Ticker), min(.FA$FY), max(.FA$FY),
            if (isTRUE(.XFLOW_QTR)) "단일분기 유량(4분기 합산)" else "누적(12월 값 채택)",
            if (is.finite(.rr_med)) sprintf("%.2f", .rr_med) else "NA", length(.rr), .n_ni_x, 100 * .fund_cov))
if (.fund_cov <= 0) stop(sprintf("%s 재무 패널 커버리지 0 — Ticker 형식 또는 usable 규약 확인", .TAG))
rm(.FA)

# =============================================================================
# 8. 순위 재척도 (그날 적격 집합 안 · 특성 32 + 표적) → 패널 파케이  ★changed(10)
# =============================================================================
.na_pre  <- .P[Date <  .START, lapply(.SD, function(v) 100 * mean(!is.finite(v))), .SDcols = .FEATS]
.na_post <- .P[Date >= .START, lapply(.SD, function(v) 100 * mean(!is.finite(v))), .SDcols = .FEATS]
.P[, (.FEATS) := lapply(.SD, .rank01), by = Date, .SDcols = .FEATS]
.P[, y := NA_real_]
.P[is.finite(y_raw), y := .rank01(y_raw), by = Date]
.P[!is.finite(y), lab_i := NA_integer_]
.P[, lab_i := as.integer(lab_i)]
.PN <- .P[, c("di", "Ticker", .FEATS, "y", "lab_i"), with = FALSE]
.panel_path <- file.path(.WD, "panel.parquet"); .sched_path <- file.path(.WD, "schedule.parquet")
.pred_path  <- file.path(.WD, "pred.parquet");  .diag_path  <- file.path(.WD, "diag.parquet")
write_parquet(.PN, .panel_path)
write_parquet(.SCH[, .(k, pred_i, u_i, smin_i, smax_i, seed)], .sched_path)
cat(sprintf("%s 패널 %d행 × 특성 %d (%s ~ %s · 표적 있는 행 %d) → %s\n", .TAG, nrow(.PN), length(.FEATS),
            as.character(min(.P$Date)), as.character(max(.P$Date)), sum(is.finite(.PN$y)), .panel_path))
cat(sprintf("  특성 결측률(순위 전 · 결측 = 0.5 대치) 2005 이전 / 이후: %s\n",
            paste(sprintf("%s %.0f/%.0f%%", .FEAT_NAMES, as.numeric(.na_pre[1, ]), as.numeric(.na_post[1, ])), collapse = " · ")))
rm(.PN); gc(verbose = FALSE)

# =============================================================================
# 9. DNN5 — 파이썬(venv torch · CPU) 서브프로세스. 스크립트 본문은 여기 있고 매 실행 _work/ 에 써 넣는다.  ★changed(4)(5)(6)(15)
# =============================================================================
.PY_SRC <- r"---(
# dnn_rolling.py — RP_AUTO_2002_06975 (Abe & Nakagawa 2020, Table 2 DNN5). Written by engine.R on every run; do not edit.
import os
import sys
import math
import time
import numpy as np
import pandas as pd
import pyarrow as pa
import pyarrow.parquet as pq
import torch
import torch.nn as nn
from concurrent.futures import ProcessPoolExecutor

HIDDEN = [300, 300, 150, 150, 50]          # Table 2 DNN5 hidden layers
DROPOUT = [0.50, 0.50, 0.30, 0.30, 0.10]   # Table 2 DNN5 dropout rates
EPOCHS = 20                                # Table 2 DNN5 epochs
BATCH = 500                                # paper: mini-batch size 500
LR = 1e-3                                  # not stated -> TensorFlow Adam default
BN_EPS = 1e-3                              # not stated -> TensorFlow batch_normalization default
BN_MOMENTUM = 0.01                         # TensorFlow decay 0.99 == torch momentum 0.01
PANEL = None
FEATS = None


class DNN(nn.Module):
    def __init__(self, m):
        super().__init__()
        layers = []
        prev = m
        for h, p in zip(HIDDEN, DROPOUT):
            layers.append(self.linear(prev, h))
            layers.append(nn.BatchNorm1d(h, eps=BN_EPS, momentum=BN_MOMENTUM))
            layers.append(nn.ReLU())
            layers.append(nn.Dropout(p))
            prev = h
        layers.append(self.linear(prev, 1))
        self.net = nn.Sequential(*layers)

    @staticmethod
    def linear(fan_in, fan_out):
        lin = nn.Linear(fan_in, fan_out)
        sd = math.sqrt(2.0 / fan_in)       # paper: tf.truncated_normal, mean 0, std sqrt(2/M), M = fan-in
        nn.init.trunc_normal_(lin.weight, mean=0.0, std=sd, a=-2.0 * sd, b=2.0 * sd)
        nn.init.zeros_(lin.bias)
        return lin

    def forward(self, x):
        return self.net(x).squeeze(1)


def fit_predict(X, y, Xp, seed):
    torch.manual_seed(seed)
    gen = torch.Generator()
    gen.manual_seed(seed)
    model = DNN(X.shape[1])
    opt = torch.optim.Adam(model.parameters(), lr=LR)
    lossf = nn.MSELoss()
    Xt = torch.from_numpy(X)
    yt = torch.from_numpy(y)
    n = Xt.shape[0]
    steps = 0
    skipped = 0
    last = float("nan")
    model.train()
    for _ in range(EPOCHS):
        perm = torch.randperm(n, generator=gen)
        for b in range(0, n, BATCH):
            idx = perm[b:b + BATCH]
            if idx.numel() < 2:            # batch norm needs at least 2 rows (declared)
                skipped += 1
                continue
            opt.zero_grad()
            loss = lossf(model(Xt[idx]), yt[idx])
            loss.backward()
            opt.step()
            steps += 1
            last = float(loss.item())
    model.eval()
    with torch.no_grad():
        pred = model(torch.from_numpy(Xp)).numpy()
    return pred, steps, skipped, last


def load_panel(path):
    global PANEL, FEATS
    torch.set_num_threads(1)
    t = pq.read_table(path).to_pandas()
    FEATS = [c for c in t.columns if c[0] == "x" and c[1:].isdigit()]
    for c in FEATS:
        t[c] = t[c].astype(np.float32)
    PANEL = t


def run_task(task):
    k, pred_i, u_i, smin_i, smax_i, seed = task
    P = PANEL
    tr = P[(P["di"] >= smin_i) & (P["di"] <= smax_i) & P["y"].notna()]
    pr = P[P["di"] == pred_i]
    diag = dict(k=k, pred_i=pred_i, u_i=u_i, smin_i=smin_i, smax_i=smax_i,
                n_train=int(len(tr)), n_days=int(tr["di"].nunique()) if len(tr) else 0,
                max_lab_i=int(tr["lab_i"].max()) if len(tr) else -1,
                n_pred=int(len(pr)), steps=0, skipped=0, last_loss=float("nan"), secs=0.0)
    if len(tr) == 0 or len(pr) == 0:
        return k, None, diag
    if diag["max_lab_i"] > u_i:
        raise RuntimeError("PIT: a training label is realized after the update day (max_lab_i %d > u_i %d)" % (diag["max_lab_i"], u_i))
    X = tr[FEATS].to_numpy(dtype=np.float32)
    y = tr["y"].to_numpy(dtype=np.float32)
    Xp = pr[FEATS].to_numpy(dtype=np.float32)
    t0 = time.time()
    pred, steps, skipped, last = fit_predict(X, y, Xp, seed)
    out = pd.DataFrame({"pred_i": np.repeat(pred_i, len(pr)), "Ticker": pr["Ticker"].to_numpy(),
                        "Score": pred.astype(np.float64)})
    diag.update(steps=steps, skipped=skipped, last_loss=last, secs=time.time() - t0)
    return k, out, diag


def synthetic_check(seed):
    # positive control: a known rank-target structure must be learned by the same fit_predict routine
    rng = np.random.default_rng(seed)
    n, m, npred = 20000, 32, 5000
    X = rng.uniform(0.0, 1.0, size=(n, m)).astype(np.float32)
    w = rng.normal(size=m).astype(np.float32)
    f = X @ w + 0.5 * np.sin(6.0 * X[:, 0])
    y = (pd.Series(f).rank(method="average") / n).to_numpy(dtype=np.float32)
    Xp = rng.uniform(0.0, 1.0, size=(npred, m)).astype(np.float32)
    fp = Xp @ w + 0.5 * np.sin(6.0 * Xp[:, 0])
    pred, steps, skipped, last = fit_predict(X, y, Xp, seed)
    rho = float(pd.Series(pred).corr(pd.Series(fp), method="spearman"))
    return rho, steps


def main():
    wd = sys.argv[1]
    panel_path = os.path.join(wd, "panel.parquet")
    sched_path = os.path.join(wd, "schedule.parquet")
    pred_path = os.path.join(wd, "pred.parquet")
    diag_path = os.path.join(wd, "diag.parquet")
    for p in (pred_path, diag_path):
        if os.path.exists(p):
            os.remove(p)
    sched = pq.read_table(sched_path).to_pandas()
    torch.set_num_threads(1)
    t0 = time.time()
    rho, steps = synthetic_check(int(sched["seed"].iloc[0]) + 7)
    print("[dnn] positive control (synthetic rank target): spearman %.3f after %d steps (%.0fs)" % (rho, steps, time.time() - t0), flush=True)
    if not rho > 0.8:
        print("[dnn] positive control FAILED - the training loop does not learn a known structure; aborting", flush=True)
        sys.exit(3)
    tasks = [tuple(int(v) for v in row) for row in sched[["k", "pred_i", "u_i", "smin_i", "smax_i", "seed"]].to_numpy()]
    ncpu = os.cpu_count() or 2
    cap = int(sys.argv[2]) if len(sys.argv) > 2 else 4
    workers = max(1, min(cap, ncpu - 1))
    print("[dnn] %d months to fit, %d worker processes (1 torch thread each), torch %s" % (len(tasks), workers, torch.__version__), flush=True)
    outs = []
    diags = []
    t1 = time.time()
    done = 0
    with ProcessPoolExecutor(max_workers=workers, initializer=load_panel, initargs=(panel_path,)) as ex:
        for k, out, diag in ex.map(run_task, tasks, chunksize=1):
            diags.append(diag)
            if out is not None:
                outs.append(out)
            done += 1
            if done % 12 == 0 or done == len(tasks):
                print("[dnn]   %d/%d months | n_train %d | steps %d | loss %.4f | %.1f min elapsed" % (done, len(tasks), diag["n_train"], diag["steps"], diag["last_loss"], (time.time() - t1) / 60.0), flush=True)
    if not outs:
        print("[dnn] no predictions produced", flush=True)
        sys.exit(4)
    pred = pd.concat(outs, ignore_index=True)
    pq.write_table(pa.Table.from_pandas(pred, preserve_index=False), pred_path)
    dg = pd.DataFrame(diags)
    dg["synthetic_rho"] = rho
    pq.write_table(pa.Table.from_pandas(dg, preserve_index=False), diag_path)
    print("[dnn] done: %d prediction rows over %d months in %.1f min" % (len(pred), len(outs), (time.time() - t1) / 60.0), flush=True)


if __name__ == "__main__":
    main()
)---"
.script <- file.path(.WD, "dnn_rolling.py")
writeLines(.PY_SRC, .script, useBytes = TRUE)
.old_utf8 <- Sys.getenv("PYTHONUTF8", unset = NA)
Sys.setenv(PYTHONUTF8 = "1")
cat(sprintf("%s DNN5 학습·예측 시작 — %d개월 · 워커 ≤ %d · %.1f분 경과\n", .TAG, nrow(.SCH), .N_WORKERS_MAX,
            as.numeric(difftime(Sys.time(), .t0, units = "mins"))))
.rc <- system2(.PY, c(shQuote(.script), shQuote(.WD), as.character(.N_WORKERS_MAX)), stdout = "", stderr = "")
if (is.na(.old_utf8)) Sys.unsetenv("PYTHONUTF8") else Sys.setenv(PYTHONUTF8 = .old_utf8)
.rc <- if (is.null(.rc) || length(.rc) == 0L) 1L else as.integer(.rc)
if (.rc != 0L) stop(sprintf("%s 파이썬 DNN 러너 실패(rc %d) — 위 로그 확인(양성 대조 실패 = rc 3 · 예측 0 = rc 4 · PIT 단언 실패 = 트레이스백)", .TAG, .rc))
if (!file.exists(.pred_path) || !file.exists(.diag_path)) stop(sprintf("%s 파이썬 산출 파케이 부재", .TAG))
.PR <- as.data.table(read_parquet(.pred_path))
.DG <- as.data.table(read_parquet(.diag_path))
.PR[, pred_i := as.integer(pred_i)]; .PR[, Ticker := as.character(Ticker)]; .PR[, Score := as.numeric(Score)]
for (cc in c("k", "pred_i", "u_i", "smin_i", "smax_i", "n_train", "n_days", "max_lab_i", "n_pred", "steps", "skipped"))
  .DG[, (cc) := as.integer(get(cc))]

# ── PIT 재단언 (R 측 · 파이썬을 신뢰하지 않는다) ──
.bad <- .DG[n_train > 0L & !(max_lab_i <= u_i & u_i <= pred_i & smin_i >= 1L & (smax_i - smin_i + 1L) == .N_TRAIN & n_days <= .N_TRAIN)]
if (nrow(.bad) > 0L)
  stop(sprintf("%s PIT/창 단언 실패 %d개월 (예: k %d · max_lab_i %d · u_i %d · pred_i %d · n_days %d)", .TAG, nrow(.bad),
               .bad$k[1], .bad$max_lab_i[1], .bad$u_i[1], .bad$pred_i[1], .bad$n_days[1]))
.rho <- as.numeric(.DG$synthetic_rho[1])
if (!is.finite(.rho) || .rho <= 0.8) stop(sprintf("%s 파이썬 양성 대조 미기록/미달(rho %s)", .TAG, as.character(.rho)))
.DG[.CAL, on = .(pred_i = di), Date := i.Date]

# =============================================================================
# 10. 조립 — 5분위 롱숏 EW (engine_direct) + FACTORS · 검산 · 요약(성과 수치 없음 — 등급은 계약이 낸다)  ★changed(11)
# =============================================================================
.PR[.CAL, on = .(pred_i = di), Date := i.Date]
FACTORS <- .PR[is.finite(Score) & !is.na(Date), .(Date, Ticker, Score)]
if (nrow(FACTORS) == 0L) stop(sprintf("%s 예측 행 0", .TAG))
.rows_p <- list(); .diag_p <- list(); .n_skip <- 0L
for (d in sort(unique(FACTORS$Date))) {
  d <- as.Date(d, origin = "1970-01-01")
  md <- FACTORS[Date == d]
  N <- nrow(md); nq <- N %/% .QUINT
  if (N < .MIN_N || nq < 2L) { .n_skip <- .n_skip + 1L; next }
  o_hi <- order(-md$Score, md$Ticker)                       # 내림차순 · 동률 = 종목코드(선택 규칙 · 결정론)
  o_lo <- order(md$Score, md$Ticker)
  hi <- md$Ticker[o_hi[seq_len(nq)]]; lo <- md$Ticker[o_lo[seq_len(nq)]]
  if (length(intersect(hi, lo)) > 0L) stop(sprintf("%s %s 롱·숏 교차 — N %d nq %d", .TAG, as.character(d), N, nq))
  .rows_p[[length(.rows_p) + 1L]] <- data.table(
    Date = d, Ticker = c(hi, lo),
    Weight = c(rep(1 / nq, nq), rep(-1 / nq, nq)),           # 5분위 내 EW · 롱 Σ=+1 / 숏 Σ=−1
    Leg = rep(c("long", "short"), c(nq, nq)))
  .diag_p[[length(.diag_p) + 1L]] <- data.table(Date = d, N = N, nq = nq)
}
if (length(.rows_p) == 0L) stop(sprintf("%s PORTFOLIO 행 0 (건너뛴 달 %d)", .TAG, .n_skip))
PORTFOLIO <- rbindlist(.rows_p, use.names = TRUE)
setorder(PORTFOLIO, Date, Leg, Ticker)
setorder(FACTORS, Date, Ticker)
.chk <- PORTFOLIO[, .(gl = sum(Weight[Weight > 0]), gs = -sum(Weight[Weight < 0])), by = Date]
.badw <- .chk[abs(gl - 1) > 1e-9 | abs(gs - 1) > 1e-9]
if (nrow(.badw) > 0L) stop(sprintf("%s 다리 총노출 검산 실패 %d건 (예: %s gL %.6f / gS %.6f)", .TAG, nrow(.badw),
                                   as.character(.badw$Date[1L]), .badw$gl[1L], .badw$gs[1L]))
if (anyDuplicated(PORTFOLIO, by = c("Date", "Ticker")) > 0L) stop(sprintf("%s PORTFOLIO (Date,Ticker) 중복", .TAG))
if (anyDuplicated(FACTORS, by = c("Date", "Ticker")) > 0L)   stop(sprintf("%s FACTORS (Date,Ticker) 중복", .TAG))
if (max(FACTORS$Date) > max(RAWDATA$Date)) stop(sprintf("%s 시그널일이 RAWDATA 범위 밖", .TAG))
.DP <- rbindlist(.diag_p, use.names = TRUE)
.DGo <- .DG[n_train > 0L]
.mins <- as.numeric(difftime(Sys.time(), .t0, units = "mins"))
cat(sprintf("%s adapted(기전 = 논문 그대로: 33→32 팩터 유니버스 안 순위/최대순위 0~1 · 표적 = 5일 수익(시가 t+1→종가 t+5) 순위 재척도 · DNN5 300-300-150-150-50 dropout 50-50-30-30-10%% ReLU BN Adam MSE batch 500 epoch 20 trunc-normal sqrt(2/M) · 최신 1,000일 학습집합 · 5영업일 갱신 격자 · 상위/하위 5분위 EW 롱숏): 유니버스 K200∪KQ150 · 유동성 스크린 없음 · 월말 시그널만 발행(하네스 월간 집행) · 팩터 DB 미사용\n",
            .TAG))
cat(sprintf("  발행 %d개월 (%s ~ %s) · 건너뛴 달 %d · 예측 N %d~%d(중앙 %d) · 5분위 %d~%d종/다리 · 학습행 %d~%d(중앙 %d) · 학습일수 %d~%d · 갱신일 지연 0~%d거래일\n",
            nrow(.DP), as.character(min(.DP$Date)), as.character(max(.DP$Date)), .n_skip,
            min(.DP$N), max(.DP$N), as.integer(median(.DP$N)), min(.DP$nq), max(.DP$nq),
            min(.DGo$n_train), max(.DGo$n_train), as.integer(median(.DGo$n_train)), min(.DGo$n_days), max(.DGo$n_days),
            max(.DGo$pred_i - .DGo$u_i)))
cat(sprintf("  DNN: 양성 대조 spearman %.3f · 스텝/월 %d~%d · 건너뛴 미니배치(행<2) 합 %d · 최종 학습 MSE 중앙 %.4f · 월당 %.0f초 · 총 %.1f분\n",
            .rho, min(.DGo$steps), max(.DGo$steps), sum(.DGo$skipped), median(.DGo$last_loss), median(.DGo$secs), .mins))
cat(sprintf("  PORTFOLIO %d행 · FACTORS %d행 · 러너 사양 = FIDELITY 파일 portfolio_spec(engine_direct · ew · monthly) · commission_paper = null(논문 비용 무명시 → gross 병기)\n",
            nrow(PORTFOLIO), nrow(FACTORS)))
rm(.P, .PR, .DG, .SCH, .CAL, .me); gc(verbose = FALSE)

PORTFOLIO <- PORTFOLIO[, .(Date, Ticker, Weight, Leg)]
FACTORS   <- FACTORS[, .(Date, Ticker, Score)]
