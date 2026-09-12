# =============================================================================
# engine.R — RP_AUTO_2011_05381  (1판 · 2026-09-12)
# Eric André · Guillaume Coqueret, "Dirichlet policies for reinforced factor portfolios"
#   arXiv:2011.05381 (v1 2020-11-10 · v3 2021-06-25)  https://arxiv.org/abs/2011.05381
#   본문 = r.jina.ai PDF 텍스트 프록시(2020년 논문 · arxiv html 렌더 없음) — 절 단위 질의 8회 (FIDELITY source_paper)
#
# ★라벨(adapted)·변경 전수 신고·러너 사양의 정본 = FIDELITY.json. 이 주석은 아무것도 결정하지 않는다.
#   코드 옆 ★changed(n) 표식 = FIDELITY.json changed 의 항목 번호.
#
# 논문의 기전(§2·§3 축자 요지 — 전문은 FIDELITY kept):
#   상태 X_t = 종목별 특성 벡터 [1, x^(1..K)] (x^(0) = 1 상수 · 특성 12종은 매월 횡단면에서 [−0.5, 0.5] 균등분포로 변환),
#   행동 = 단체(simplex) 위의 비중 w ~ Dirichlet(a_t),  a_t = exp(X_t θ_t)   (F2 · 식 9 · '항상 유효'),
#   보상 = 포트폴리오 수익 ρ_{t+1} = w_t' r_{t+1}                              (부트스트랩 시퀀스 = 수익 보상만 · §3.3),
#   정책 기울기(식 15) ∇_θ ln π(w|X,θ) = Σ_n (ψ(σ) − ψ(a_n) + ln w_n) ∇a_n,  σ = Σ_n a_n,  F2: ∇a_n = a_n x_n,
#   REINFORCE(Table 2) θ ← θ + η γ^t G ∇ln π,  G = Σ_{k>t} γ^{k−t−1} R_k,  기울기는 최대 절댓값으로 나눈다(§4.1),
#   프로토콜(Table 3 · 부트스트랩 열): 매월 t — ①직전 달 데이터 추출 ②N 종목 무작위 선택 ③θ 초기화
#     ④에피소드 i = 1..E: N 종목 복원추출 → 행동(w 표집)·보상 → 식(13) 갱신 ⑤t+1 = 평균 정책 E[w_n] = a_n/σ (식 11) 로 배분.
#   셀 = Fig.2 파라미터(η 0.1 · E 500 · θ_k 초기값 1 · seed 42) · N 100(§4.1) · γ 1(§4.1) · F2 · 부트스트랩(§5.4 유일한 강건 결론).
#
# 산출: PORTFOLIO(Date, Ticker, Weight, Leg) — Weight = a_n/σ (롱온리 · Σw = 1 · 그 달 적격 횡단면 전 종목)
#       FACTORS(Date, Ticker, Score)          — Score = x_n'θ = ln a_n (그 달 비중의 단조 변환 · IC/FMB 진단용)
#
# PIT(C1~C15) 구조 보장: 시그널 d_t = 달 t 의 마지막 거래일(시장 통합). d_t 의 코드 접근 = X_{t−1}(달 t−1 월말 행·창) ·
#   r_t = P_t/P_{t−1} − 1 (d_t 에 실현) · X_t(d_t 당일 행 + d_t 이하 창). 회계 항목 = FD_lag(= max(패널 Factor_Date,
#   익년 3/31)) ≤ d 인 최신 회계연도만 roll join(C4). 전 표본 통계 0건(균등화 = 그 달 횡단면만 · vol/rsi = 종목별 과거 창) ·
#   팩터 DB 미사용(C13/C15 대상 코드 없음) · 유동성 스크린 없음(C10 대상 코드 없음) · 집행 = 익월 첫 거래일(러너 get_execution_date).
# =============================================================================

suppressWarnings(suppressMessages({
  library(data.table)
  library(arrow)
}))

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
.TAG <- "[RP_AUTO_2011_05381]"
.REQ <- c("Date", "Ticker", "Close", "Vol", "Size", "K200", "KQ150")
if (!all(.REQ %in% names(RAWDATA)))
  stop(sprintf("%s RAWDATA 필수 열 부재: %s", .TAG, paste(setdiff(.REQ, names(RAWDATA)), collapse = ", ")))
.t0 <- Sys.time()

# =============================================================================
# 0. 상수 — 논문 명시값(Fig.2 캡션 · §4.1 · Table 1) + 논문이 침묵한 규약(전부 FIDELITY.json changed 신고)
# =============================================================================
.N_ASSETS   <- 100L                    # §4.1 'The most obvious choice is N = 100'
.N_EPIS     <- 500L                    # Fig.2 캡션 'the number of episodes E = 500'
.ETA        <- 0.1                     # Fig.2 캡션 'the learning rate η = 0.1'
.GAMMA      <- 1                       # §4.1 'we set γ = 1' (에피소드 길이 1 이라 무관)
.THETA0     <- 1                       # Fig.2 캡션 'the initial value for all θ_k is 1'
.SEED       <- 42L                     # Fig.2 캡션 'the random seed in 42'                          ★changed(11)
.VOL_WIN    <- 30L                     # Table 1 vol = VOLATILITY_30D (과거 30 거래일)
.RSI_WIN    <- 30L                     # Table 1 rsi = RSI_30D
.MOM_LONG   <- 12L                     # Table 1 mom = 'lagged 12 month value divided by lagged one month value, minus one'
.MOM_SHORT  <- 1L
.OUT_START  <- as.Date("2005-01-01")   # 고정 축(기간 2005-01-01~) — 이 날 이후 시그널만 발행
.MIN_ELIG   <- 20L                     # ★changed(8)  학습·배분 횡단면 하한(미만이면 그 달 발행 없음)
.FY_MAX_AGE <- 2L                      # ★changed(7)  최신 회계연도가 year(d) − 2 보다 오래되면 결측 취급
.SEED_CHK   <- 20201110L               # ★changed(11) 양성 대조 시드 = 논문 v1 게재일(임의 상수)
.FEATS <- c("cap", "pb", "de", "vol", "prof", "inv", "eps", "liq", "rsi", "pe", "dy", "mom")   # Table 1 순서
.K     <- length(.FEATS)
.ACCT_ITEMS <- c("Revenue", "NetIncome", "PretaxIncome", "TaxExpense",
                 "TotalAssets", "TotalEquity", "ShortTermBorr", "LongTermBorr", "Dividends")
.ym <- function(mi) sprintf("%d-%02d", (mi - 1L) %/% 12L, (mi - 1L) %% 12L + 1L)

# 회계 패널 경로 — 코드 루트가 아니라 데이터 루트(.cache)를 잡는다                                     ★changed(7)
.PICK_ROOT <- function() {
  cand <- c(if (exists("PROJECT_ROOT")) as.character(PROJECT_ROOT)[1] else "",
            Sys.getenv("QM_ROOT", ""), Sys.getenv("CLAUDE_PROJECT_DIR", ""))
  for (p in cand)
    if (nzchar(p) && file.exists(file.path(p, ".cache", "fundamental_merged.parquet"))) return(p)
  ""
}
.ROOT <- .PICK_ROOT()
if (!nzchar(.ROOT)) stop(sprintf("%s .cache/fundamental_merged.parquet 을 못 찾음 — PROJECT_ROOT/QM_ROOT 확인", .TAG))
.ACCT_PATH <- file.path(.ROOT, ".cache", "fundamental_merged.parquet")

# =============================================================================
# 1. 일간 패널 → 종목별 일간 특성(vol · rsi) · 월간 종가 패널 · 시장 월말 · 월말 당일 행
#    열 정체: Close = 수정주가 · Vol = 주식수 거래량 · Size = 시가총액(KRW) (compute_liquidity.R:36-63 · krx_build_rawdata.R:308 규약)
# =============================================================================
.rd <- RAWDATA[is.finite(Close) & Close > 0, .(Date, Ticker, Close, Vol, Size, K200, KQ150)]   # ★changed(13)
.rd[, Ticker := as.character(Ticker)]
.rd[, MEM := (K200 == TRUE | KQ150 == TRUE) %in% TRUE]                       # ★changed(1) 러너 .apply_universe 와 같은 술어
.rd[, c("K200", "KQ150") := NULL]
.rd[, Close := as.numeric(Close)]
.rd[, Vol := as.numeric(Vol)]
.rd[, Size := as.numeric(Size)]
if (!inherits(.rd$Date, "Date")) .rd[, Date := as.Date(Date)]
setorder(.rd, Ticker, Date)
.ndup <- sum(duplicated(.rd, by = c("Ticker", "Date")))
if (.ndup > 0L) {
  cat(sprintf("%s (Ticker,Date) 중복 %d행 — 첫 행만 유지\n", .TAG, .ndup))                 # ★changed(13)
  .rd <- unique(.rd, by = c("Ticker", "Date"))
}
.n_rd <- nrow(.rd)
.rd[, MI := year(Date) * 12L + month(Date)]

# (a) vol = 직전 30 로그수익(종목 연속 행 기준 · 30개 전부 유한해야 정의)의 표준편차 — Bloomberg VOLATILITY_30D 의
#     연율화 상수 √260 은 순위에 무관하므로 생략(균등화가 지운다)                                       ★changed(6)(10)
.rd[, lr := log(Close) - log(shift(Close)), by = Ticker]                     # shift = 과거 방향(직전 행)
.rd[, m1 := frollmean(lr, .VOL_WIN), by = Ticker]
.rd[, m2 := frollmean(lr * lr, .VOL_WIN), by = Ticker]
.rd[, vol := sqrt(pmax(m2 - m1 * m1, 0) * .VOL_WIN / (.VOL_WIN - 1))]
.rd[, c("lr", "m1", "m2") := NULL]

# (b) rsi = Wilder RSI(30): 첫 30 변화의 단순평균으로 시드 → 이후 (n−1)/n 지수 평활 · 종목 이력 전체 위에서 재귀   ★changed(6)
.rsi_wilder <- function(p, n) {
  m <- length(p); out <- rep(NA_real_, m)
  if (m <= n) return(out)
  d  <- diff(p)
  u  <- pmax(d, 0); dn <- pmax(-d, 0)
  au0 <- sum(u[1:n]) / n; ad0 <- sum(dn[1:n]) / n
  if (m - 1L > n) {
    au <- c(au0, as.numeric(stats::filter(u[(n + 1L):(m - 1L)] / n,  (n - 1) / n, method = "recursive", init = au0)))
    ad <- c(ad0, as.numeric(stats::filter(dn[(n + 1L):(m - 1L)] / n, (n - 1) / n, method = "recursive", init = ad0)))
  } else { au <- au0; ad <- ad0 }
  rsi <- ifelse(ad > 0, 100 - 100 / (1 + au / ad), ifelse(au > 0, 100, 50))
  out[(n + 1L):m] <- rsi
  out
}
.rd[, rsi := .rsi_wilder(Close, .RSI_WIN), by = Ticker]

# (c) 시장 월말 = 그 달력월의 마지막 거래일(전 종목 통합). 마지막 달력월은 진행 중(부분월)으로 보고 제외.   ★changed(12)
.me <- .rd[, .(MEnd = max(Date)), by = MI]
setorder(.me, MI)
.MI_LAST <- max(.me$MI)
.me <- .me[MI < .MI_LAST]
if (nrow(.me) < 36L) stop(sprintf("%s 완결 월 %d개 — RAWDATA 날짜 범위 확인", .TAG, nrow(.me)))
if (any(diff(.me$MI) != 1L)) stop(sprintf("%s 월 인덱스가 연속이 아님 — 거래 데이터가 통째로 빈 달이 있다", .TAG))

# (d) 월간 종가 패널 = 그 달력월 안 종목의 마지막 관측 종가(행렬: 행 = 달 · 열 = 종목)                       ★changed(9)
.MA <- .rd[, .(P = Close[.N]), by = .(Ticker, MI)]
.wide <- dcast(.MA, MI ~ Ticker, value.var = "P")
setorder(.wide, MI)
.MIs <- .wide$MI
if (any(diff(.MIs) != 1L)) stop(sprintf("%s 월간 종가 패널의 월 인덱스가 연속이 아님", .TAG))
.TK <- setdiff(names(.wide), "MI")
.P  <- as.matrix(.wide[, .TK, with = FALSE])
colnames(.P) <- .TK
rm(.MA, .wide)

# (e) 월말 당일 행 — 멤버십 플래그·cap·liq·vol·rsi 는 전부 이 행(= d 당일 · d 이하 창)에서 읽는다                ★changed(1)(6)
.rd[, MEnd := .me$MEnd[match(MI, .me$MI)]]
.ME_ROWS <- .rd[!is.na(MEnd) & Date == MEnd, .(MI, Date, Ticker, MEM, Close, Vol, Size, vol, rsi)]
setkey(.ME_ROWS, MI)
rm(.rd); gc(verbose = FALSE)
cat(sprintf("%s 일간 행 %d → 월간 패널 %d개월 (%s ~ %s) × %d종 · 완결 월말 %d개 · 마지막 부분월 %s 제외\n",
            .TAG, .n_rd, length(.MIs), .ym(min(.MIs)), .ym(max(.MIs)), length(.TK), nrow(.me), .ym(.MI_LAST)))

# =============================================================================
# 2. 회계 패널 → 회계연도 값 (DART 연간 2015~ + QuantiWise XLSX 분기 1998~ 병합 · 손익 항목의 시간 단위가 원천마다 다르다)
#    손익 = DART 는 1년치 · XLSX 는 분기 개별값(4개 다 있어야 합산) · 상태 항목 = YYYY12 잔액(DART 우선)         ★changed(7)
# =============================================================================
.ac <- as.data.table(read_parquet(.ACCT_PATH,
  col_select = c("Ticker", "Period", "Factor_Date", "Item", "Value", "Source")))
.ac[, Item := as.character(Item)]
.ac[, Source := as.character(Source)]
.ac[, Value := as.numeric(Value)]
.ac <- .ac[Item %chin% .ACCT_ITEMS & is.finite(Value)]
.ac[, Ticker := as.character(Ticker)]
.tk_mem  <- unique(.ME_ROWS$Ticker[.ME_ROWS$MEM])
.ov_raw  <- length(intersect(unique(.ac$Ticker), .tk_mem))
.ac_strip <- sub("^A([0-9]{6})$", "\\1", .ac$Ticker)
.ov_strip <- length(intersect(unique(.ac_strip), .tk_mem))
if (.ov_strip > .ov_raw) .ac[, Ticker := .ac_strip]                          # ★changed(13) 'A005930' → '005930'
rm(.ac_strip)
if (max(.ov_raw, .ov_strip) == 0L)
  stop(sprintf("%s 회계 패널과 구성종목의 티커 교집합 0 — 표기 불일치", .TAG))
if (!inherits(.ac$Factor_Date, "Date")) .ac[, Factor_Date := as.Date(Factor_Date)]
.pc <- as.character(.ac$Period)
.ac[, yv := as.integer(substr(.pc, 1L, 4L))]
.ac[, mv := as.integer(substr(.pc, 5L, 6L))]
rm(.pc)
.ac <- .ac[is.finite(yv) & is.finite(mv) & !is.na(Factor_Date)]
.ac[, isd := Source %chin% "DART"]
.FLOWI  <- c("Revenue", "NetIncome", "PretaxIncome", "TaxExpense", "Dividends")
.STOCKI <- c("TotalAssets", "TotalEquity", "ShortTermBorr", "LongTermBorr")
.a1 <- .ac[isd == TRUE & mv == 12L & Item %chin% .FLOWI,
           .(V = Value[1], FD = max(Factor_Date), pr = 1L), by = .(Ticker, Item, yv)]
.a2 <- .ac[isd == FALSE & mv %in% c(3L, 6L, 9L, 12L) & Item %chin% .FLOWI,
           .(V = sum(Value), nq = .N, FD = max(Factor_Date)), by = .(Ticker, Item, yv)]
.a2 <- .a2[nq == 4L, .(Ticker, Item, yv, V, FD, pr = 2L)]
.st <- .ac[mv == 12L & Item %chin% .STOCKI]
.st[, pr := fifelse(isd, 1L, 2L)]
setorder(.st, Ticker, Item, yv, pr)
.st <- unique(.st, by = c("Ticker", "Item", "yv"))
.FL <- rbind(.a1, .a2, .st[, .(Ticker, Item, yv, V = Value, FD = Factor_Date, pr)], use.names = TRUE)
setorder(.FL, Ticker, Item, yv, pr)
.FL <- unique(.FL, by = c("Ticker", "Item", "yv"))
.n_ac_src <- .ac[, .N, by = Source]
rm(.ac, .a1, .a2, .st); gc(verbose = FALSE)
.FY  <- dcast(.FL, Ticker + yv ~ Item, value.var = "V")
.FAV <- .FL[, .(FD = max(FD)), by = .(Ticker, yv)]                           # 그 기수 값들이 모두 쓸 수 있게 된 날
.FY  <- merge(.FY, .FAV, by = c("Ticker", "yv"))
for (cc in .ACCT_ITEMS) if (!cc %in% names(.FY)) .FY[, (cc) := NA_real_]
rm(.FL, .FAV)
# C4 — 연간 = 익년 3/31 lag 를 엔진에서 다시 강제한다(패널 Factor_Date 가 그보다 이르면 뒤로 민다)            ★changed(7)
.FY[, FD_lag := pmax(FD, as.Date(sprintf("%d-03-31", yv + 1L)))]
.FY[, NI := fifelse(is.finite(NetIncome), NetIncome,
                    fifelse(is.finite(PretaxIncome) & is.finite(TaxExpense), PretaxIncome - TaxExpense, NA_real_))]
.FY[, DEBT := fifelse(is.finite(ShortTermBorr) | is.finite(LongTermBorr),
                      fifelse(is.finite(ShortTermBorr), ShortTermBorr, 0) + fifelse(is.finite(LongTermBorr), LongTermBorr, 0),
                      NA_real_)]
.FY[, DIV := fifelse(is.finite(Dividends), abs(Dividends), 0)]               # 배당 행 없음 = 무배당(0)           ★changed(6)
setorder(.FY, Ticker, yv)
.FY[, yv_p := shift(yv), by = Ticker]                                        # shift = 직전 기수(과거 방향)
.FY[, TA_p := shift(TotalAssets), by = Ticker]
.FY[is.na(yv_p) | yv_p != (yv - 1L), TA_p := NA_real_]                       # 기수가 연속일 때만 인정
.FY[, AG := fifelse(is.finite(TotalAssets) & is.finite(TA_p) & TA_p > 0, TotalAssets / TA_p - 1, NA_real_)]
.FYK <- .FY[, .(Ticker, yv, FD_lag, NI, REV = Revenue, BOOK = TotalEquity, DEBT, DIV, AG)]
setkey(.FYK, Ticker, FD_lag)
.n_fy <- nrow(.FYK)
rm(.FY)
cat(sprintf("%s 회계 패널: 원천 %s · 회계연도 행 %d (%d종 · %d ~ %d) · 사용 가능일 = max(Factor_Date, 익년 3/31) (C4 lag)\n",
            .TAG, paste(sprintf("%s %d", .n_ac_src$Source, .n_ac_src$N), collapse = " / "),
            .n_fy, uniqueN(.FYK$Ticker), min(.FYK$yv), max(.FYK$yv)))

# 시그널일 d 에 쓸 수 있는 최신 회계연도(FD_lag ≤ d · roll join) — 행 순서 = tk 순서
.acct_at <- function(tk, d) {
  q <- data.table(Ticker = tk, FD_lag = rep(d, length(tk)))
  r <- .FYK[q, roll = Inf, on = c("Ticker", "FD_lag")]
  stale <- !is.na(r$yv) & r$yv < (year(d) - .FY_MAX_AGE)                    # ★changed(7) 낡은 기수 = 결측
  if (any(stale)) r[stale, c("NI", "REV", "BOOK", "DEBT", "DIV", "AG") := NA_real_]
  r
}

# =============================================================================
# 3. 정책·기울기·표집 — 식(7)(11)(15) · Table 2 + 양성 대조(실패 = 중단 · 조용한 F 방지)                      ★changed(10)(11)
# =============================================================================
.GUARD <- new.env()
.GUARD$n0 <- 0L                                    # rgamma 언더플로(정확히 0) 치환 건수
.unif <- function(v) frank(v, ties.method = "average") / length(v) - 0.5     # §3.1 균등화 [−0.5, 0.5] (동률 = 평균 순위)
.rdirichlet <- function(a) {                       # 식(7) Dirichlet(a) 표집 = 정규화 감마
  g <- rgamma(length(a), shape = a, rate = 1)
  nz <- is.finite(g) & g <= 0
  if (any(nz)) { g[nz] <- .Machine$double.xmin; .GUARD$n0 <- .GUARD$n0 + sum(nz) }
  g / sum(g)
}
.grad_lnpi <- function(X, a, w) {                  # 식(15) · F2: ∇a_n = a_n x_n
  s <- sum(a)
  as.vector(crossprod(X, (digamma(s) - digamma(a) + log(w)) * a))
}
.dir_logpdf <- function(w, a) lgamma(sum(a)) - sum(lgamma(a)) + sum((a - 1) * log(w))

local({
  set.seed(.SEED_CHK)
  # (a) 해석적 ∇_θ ln π vs 중심차분(Dirichlet 로그밀도 · F2 사슬)
  n <- 7L; X <- cbind(1, matrix(runif(n * .K, -0.5, 0.5), n, .K)); th <- rnorm(.K + 1L, 1, 0.3)
  a <- exp(as.vector(X %*% th)); w <- .rdirichlet(a)
  g <- .grad_lnpi(X, a, w)
  h <- 1e-6; num <- numeric(length(th))
  for (k in seq_along(th)) {
    tp <- th; tp[k] <- tp[k] + h; tm <- th; tm[k] <- tm[k] - h
    num[k] <- (.dir_logpdf(w, exp(as.vector(X %*% tp))) - .dir_logpdf(w, exp(as.vector(X %*% tm)))) / (2 * h)
  }
  rel <- max(abs(g - num) / pmax(abs(g) + abs(num), 1e-8))
  if (!is.finite(rel) || rel > 1e-5)
    stop(sprintf("%s 기울기 검산 실패 — 식(15) 구현 vs 중심차분 상대오차 %.2e (중단)", .TAG, rel))
  # (b) 정책 기울기 항등식 E[R ∇ln π] = ∇_θ E[R] — 몬테카를로 vs 폐형 Σ_i r_i (a_i/σ)(x_i − x̄_a) (표집기 + 스코어 동시 검산)
  n <- 100L; X <- cbind(1, matrix(runif(n * .K, -0.5, 0.5), n, .K)); th <- rep(.THETA0, .K + 1L)
  rr <- 0.5 + 2 * X[, 2L]
  a <- exp(as.vector(X %*% th)); s <- sum(a); p <- a / s
  xbar <- as.vector(crossprod(X, p))
  an <- as.vector(crossprod(sweep(X, 2L, xbar, "-"), rr * p))
  M <- 20000L
  G <- matrix(rgamma(n * M, shape = a, rate = 1), n, M)
  G[G <= 0] <- .Machine$double.xmin
  W <- sweep(G, 2L, colSums(G), "/")
  S <- (digamma(s) - digamma(a)) + log(W)
  R <- as.vector(crossprod(W, rr))
  Rc <- R - sum(R) / M                                                       # 상수 기준선(E[∇ln π] = 0 이라 항등식 불변 · 분산만 줄인다)
  mc <- as.vector(crossprod(X, S * a) %*% Rc) / M
  k <- which.max(abs(an))
  if (abs(mc[k] - an[k]) > 0.2 * abs(an[k]) + 0.01)
    stop(sprintf("%s 정책기울기 항등식 검산 실패 — 성분 %d: MC %.4f vs 폐형 %.4f (중단)", .TAG, k, mc[k], an[k]))
  mw <- rowMeans(W)                                                          # 식(11) E[w_n] = a_n/σ (표집기 평균)
  if (max(abs(mw - p)) > 1e-3)
    stop(sprintf("%s Dirichlet 표집기 평균 검산 실패 — max|E[w] − a/σ| %.2e (중단)", .TAG, max(abs(mw - p))))
  # (c) 균등화 고정 입력 · (d) RSI 고정 입력
  if (!isTRUE(all.equal(.unif(c(3, 1, 2, 2)), c(0.5, -0.25, 0.125, 0.125))))
    stop(sprintf("%s 균등화 검산 실패", .TAG))
  r1 <- .rsi_wilder(10 + 0:30, 30L); r2 <- .rsi_wilder(c(10 + 0:30, 39), 30L)
  r3 <- .rsi_wilder(rep(5, 40), 30L); r4 <- .rsi_wilder(1:30, 30L)
  if (!(all(is.na(r1[1:30])) && abs(r1[31] - 100) < 1e-9 && abs(r2[32] - (100 - 100 / 30)) < 1e-9 &&
        all(abs(r3[31:40] - 50) < 1e-9) && all(is.na(r4))))
    stop(sprintf("%s RSI 검산 실패", .TAG))
  cat(sprintf("%s 검산 통과 — 기울기(식 15) 상대오차 %.1e · 정책기울기 항등식 성분 %d MC %.4f vs 폐형 %.4f · 균등화 · RSI(30) 고정 입력\n",
              .TAG, rel, k, mc[k], an[k]))
})
.GUARD$n0 <- 0L                                    # 검산 중 발생분은 세지 않는다

# =============================================================================
# 4. 월별 루프 — Table 3 부트스트랩 열 그대로: (1) X_t · (2) 직전 달 (X_{t−1}, r_t) 로 REINFORCE · (3) t+1 배분 = a/σ
# =============================================================================
.J <- nrow(.me)
.X  <- vector("list", .J)
.j0 <- which(match(.me$MI, .MIs) > .MOM_LONG)[1]                             # mom 정의역(12개월 선행)
if (is.na(.j0)) stop(sprintf("%s 월간 패널이 13개월 미만 — mom 정의역 없음", .TAG))
.j_out <- which(.me$MEnd >= .OUT_START)[1]
if (is.na(.j_out)) stop(sprintf("%s %s 이후 월말 0 — RAWDATA 날짜 범위 확인", .TAG, as.character(.OUT_START)))
.j_start <- max(.j0, .j_out - 1L)                                            # 첫 발행월의 학습 재료(X_{t−1}) 한 달 전부터
.rows_p <- list(); .rows_f <- list(); .dg <- list(); .TH <- list()
.na_acc <- setNames(numeric(.K), .FEATS); .na_n <- 0L
.n_skip_x <- 0L; .n_skip_tr <- 0L; .n_skip_w <- 0L
.prev_w <- NULL
set.seed(.SEED)                                                              # Fig.2 'random seed 42' — 루프 직전 1회   ★changed(11)
.t_loop <- Sys.time()
for (j in .j_start:.J) {
  mi <- .me$MI[j]; d <- .me$MEnd[j]; im <- match(mi, .MIs)

  # (1) X_t — d 당일 구성종목 · 12 특성 전부 유한(완전 사례) · 그 집합 안에서 균등화                          ★changed(6)(8)
  mr <- .ME_ROWS[.(mi), nomatch = NULL][MEM == TRUE & is.finite(Size) & Size > 0]
  n_mem <- nrow(mr)
  if (n_mem > 0L) {
    tk  <- mr$Ticker
    ac  <- .acct_at(tk, d)
    P1  <- .P[im - .MOM_SHORT, tk]
    P12 <- .P[im - .MOM_LONG, tk]
    sh  <- mr$Size / mr$Close                                                 # 조정 기준 발행주식수(d 시점)
    Fm <- data.table(
      Ticker = tk,
      cap  = mr$Size,
      pb   = fifelse(is.finite(ac$BOOK) & ac$BOOK > 0, mr$Size / ac$BOOK, NA_real_),
      de   = fifelse(is.finite(ac$BOOK) & ac$BOOK > 0 & is.finite(ac$DEBT), ac$DEBT / ac$BOOK, NA_real_),
      vol  = mr$vol,
      prof = fifelse(is.finite(ac$REV) & ac$REV > 0 & is.finite(ac$NI), ac$NI / ac$REV, NA_real_),
      inv  = ac$AG,
      eps  = fifelse(is.finite(ac$NI), ac$NI / sh, NA_real_),
      liq  = mr$Vol,
      rsi  = mr$rsi,
      pe   = fifelse(is.finite(ac$NI) & ac$NI > 0, mr$Size / ac$NI, NA_real_),
      dy   = fifelse(is.finite(ac$DIV) & is.finite(P1) & P1 > 0, (ac$DIV / sh) / P1, NA_real_),
      mom  = fifelse(is.finite(P1) & is.finite(P12) & P1 > 0, P12 / P1 - 1, NA_real_))   # Table 1 문구 축자(FIDELITY changed(6))
    Fv <- as.matrix(Fm[, .FEATS, with = FALSE])
    okf <- is.finite(Fv)
    if (d >= .OUT_START) { .na_acc <- .na_acc + colSums(!okf); .na_n <- .na_n + n_mem }
    ok <- rowSums(okf) == .K
    n_elig <- sum(ok)
    if (n_elig >= .MIN_ELIG) {
      Mx <- apply(Fv[ok, , drop = FALSE], 2L, .unif)
      if (is.null(dim(Mx))) Mx <- matrix(Mx, nrow = n_elig)
      Xj <- cbind(1, Mx)
      dimnames(Xj) <- list(tk[ok], c("cst", .FEATS))
      .X[[j]] <- Xj
    } else .n_skip_x <- .n_skip_x + 1L
  } else { n_elig <- 0L; .n_skip_x <- .n_skip_x + 1L }

  # (2) 학습 — 직전 달 X_{t−1} 과 d 에 실현된 r_t 만. Table 3: N 종목 선택 → θ 초기화 → E 에피소드(N 복원추출 → 표집 → 보상 → 식 13)
  th <- NULL; n_train <- 0L; n_pool <- 0L
  if (j > 1L && !is.null(.X[[j - 1L]]) && im > 1L) {
    Xp  <- .X[[j - 1L]]; tkp <- rownames(Xp)
    rtr <- .P[im, tkp] / .P[im - 1L, tkp] - 1                                # d 에 확정된 직전월→이번월 수익(학습 보상)
    okr <- is.finite(rtr)
    if (sum(okr) >= .MIN_ELIG) {
      Xp <- Xp[okr, , drop = FALSE]; rtr <- rtr[okr]; n_train <- nrow(Xp)
      pool <- sample.int(n_train, min(.N_ASSETS, n_train), replace = FALSE)  # Table 3 step 2 'Randomly pick N assets'  ★changed(4)
      n_pool <- length(pool)
      th <- rep(.THETA0, .K + 1L)                                            # Table 3 step 3 'Initialize θ' (매월)
      for (i in seq_len(.N_EPIS)) {
        idx <- pool[sample.int(n_pool, .N_ASSETS, replace = TRUE)]           # step 5 'randomly choosing (with replacement) N assets'
        Xi  <- Xp[idx, , drop = FALSE]
        a   <- exp(as.vector(Xi %*% th))                                     # 식(9) F2
        w   <- .rdirichlet(a)                                                # 행동 A_s ~ π_θ
        Rr  <- sum(w * rtr[idx])                                             # 보상 R = ρ = w' r (에피소드 길이 1 → G = R)
        g   <- .grad_lnpi(Xi, a, w)                                          # 식(15)
        mg  <- max(abs(g))
        if (is.finite(mg) && mg > 0) th <- th + .ETA * .GAMMA * Rr * (g / mg)   # 식(13) · Table 2 step 5 · §4.1 최대절댓값 정규화
      }
    } else .n_skip_tr <- .n_skip_tr + 1L
  } else .n_skip_tr <- .n_skip_tr + 1L

  # (3) 배분 — 식(11) E[w_n] = a_n/σ 를 d 당일 적격 횡단면 전 종목에 (θ 는 이번 달 학습값)                     ★changed(5)(10)
  if (!is.null(th) && !is.null(.X[[j]]) && d >= .OUT_START) {
    Xj <- .X[[j]]
    sc <- as.vector(Xj %*% th)
    ea <- exp(sc - max(sc)); w <- ea / sum(ea)                               # = a/σ (오버플로 안전 · 값 동일)
    if (all(is.finite(w)) && all(w > 0)) {
      tkj <- rownames(Xj)
      cur <- setNames(w, tkj)
      to  <- if (is.null(.prev_w)) sum(abs(cur)) else {
        u <- union(names(.prev_w), names(cur))
        a1 <- cur[u];     a1[is.na(a1)] <- 0
        b1 <- .prev_w[u]; b1[is.na(b1)] <- 0
        sum(abs(a1 - b1))
      }
      .prev_w <- cur
      .rows_p[[length(.rows_p) + 1L]] <- data.table(Date = d, Ticker = tkj, Weight = w, Leg = "long")
      .rows_f[[length(.rows_f) + 1L]] <- data.table(Date = d, Ticker = tkj, Score = sc)
      .TH[[length(.TH) + 1L]] <- th
      .dg[[length(.dg) + 1L]] <- data.table(
        Date = d, n_mem = n_mem, n_elig = n_elig, n_train = n_train, n_pool = n_pool,
        sigma = sum(exp(sc)), w_max = max(w), n_eff = 1 / sum(w * w), to = to, th0 = th[1L])
      if (length(.rows_p) %% 12L == 0L) {
        o <- order(-abs(th[-1L]))[1:3]
        cat(sprintf("%s   %s · 구성 %d · 적격 %d · 학습 %d(풀 %d) · σ %.1f · w_max %.4f · N_eff %.1f · Σ|Δw| %.3f · θ0 %.3f · |θ| 상위: %s · 경과 %.1f분\n",
                    .TAG, as.character(d), n_mem, n_elig, n_train, n_pool, sum(exp(sc)), max(w), 1 / sum(w * w), to, th[1L],
                    paste(sprintf("%s %+.3f", .FEATS[o], th[-1L][o]), collapse = " "),
                    as.numeric(difftime(Sys.time(), .t_loop, units = "mins"))))
      }
    } else .n_skip_w <- .n_skip_w + 1L                                       # 비유한 비중(θ 발산) — 그 달 발행 없음  ★changed(10)
  }
}

# =============================================================================
# 5. 조립 · 검산 · 요약 (구성 요약 — 성과 수치 선언 아님. 등급은 계약이 낸다)
# =============================================================================
if (length(.rows_p) == 0L)
  stop(sprintf("%s 발행 행 0 — 적격 횡단면 부족 달 %d · 학습 불가 달 %d (회계 패널·멤버십 범위 확인)", .TAG, .n_skip_x, .n_skip_tr))
PORTFOLIO <- rbindlist(.rows_p, use.names = TRUE)
FACTORS   <- rbindlist(.rows_f, use.names = TRUE)
setorder(PORTFOLIO, Date, Ticker)
setorder(FACTORS, Date, Ticker)
.chk <- PORTFOLIO[, .(s = sum(Weight), mn = min(Weight)), by = Date]
.bad <- .chk[abs(s - 1) > 1e-9 | mn <= 0]
if (nrow(.bad) > 0L)
  stop(sprintf("%s 비중 검산 실패 %d건 (예: %s Σw %.9f · min %.3e)", .TAG, nrow(.bad), as.character(.bad$Date[1L]), .bad$s[1L], .bad$mn[1L]))
if (anyDuplicated(PORTFOLIO, by = c("Date", "Ticker")) > 0L) stop(sprintf("%s PORTFOLIO (Date,Ticker) 중복", .TAG))
if (anyDuplicated(FACTORS, by = c("Date", "Ticker")) > 0L)   stop(sprintf("%s FACTORS (Date,Ticker) 중복", .TAG))
if (!all(is.finite(FACTORS$Score))) stop(sprintf("%s FACTORS Score 비유한값 %d건", .TAG, sum(!is.finite(FACTORS$Score))))

.DG  <- rbindlist(.dg, use.names = TRUE)
.THM <- do.call(rbind, .TH)
colnames(.THM) <- c("cst", .FEATS)
.th_mean <- colMeans(.THM); .th_sd <- apply(.THM, 2L, function(z) sqrt(mean((z - mean(z))^2)))
.na_txt <- if (.na_n > 0L) paste(sprintf("%s %.0f%%", .FEATS, 100 * .na_acc / .na_n), collapse = " · ") else "n/a"
.mins <- as.numeric(difftime(Sys.time(), .t0, units = "mins"))
cat(sprintf("%s adapted(기전 = 논문 그대로: Dirichlet 정책 a = exp(Xθ)(F2 · 식 9) · REINFORCE(Table 2 · 식 13/15 · 최대절댓값 정규화) · 부트스트랩 시퀀스(Table 3: 매월 직전 달 (X_{t−1}, r_t) · N %d 풀 → E %d 에피소드 복원추출 · θ_k 초기 %g · η %.2f · γ %g · seed %d) · 배분 = a/σ(식 11) 롱온리 적격 전 종목 · 특성 12종 Table 1 KR 대응물 → 그 달 횡단면 균등화 [−0.5, 0.5]): 유니버스 K200∪KQ150 · 유동성 스크린 없음 · 팩터 DB 미사용 · 회계 = 연간(익년 3/31 lag)\n",
            .TAG, .N_ASSETS, .N_EPIS, .THETA0, .ETA, .GAMMA, .SEED))
cat(sprintf("  발행 %d개월 (%s ~ %s) · 적격 부족(<%d) 달 %d · 학습 불가 달 %d · 비유한 비중 달 %d · 구성 %d~%d(중앙 %d) · 적격 %d~%d(중앙 %d) · 학습 표본 %d~%d · 보유 N = 적격 전 종목(고정 축 25 초과는 논문 배분 정의상 · engine_direct 라 러너가 자르지 않는다)\n",
            nrow(.DG), as.character(min(.DG$Date)), as.character(max(.DG$Date)), .MIN_ELIG, .n_skip_x, .n_skip_tr, .n_skip_w,
            min(.DG$n_mem), max(.DG$n_mem), as.integer(median(.DG$n_mem)),
            min(.DG$n_elig), max(.DG$n_elig), as.integer(median(.DG$n_elig)), min(.DG$n_train), max(.DG$n_train)))
cat(sprintf("  발행월 구성종목 특성 결측률(완전 사례 배제 원인 · 순위 전): %s\n", .na_txt))
cat(sprintf("  σ = Σa %.1f~%.1f(중앙 %.1f) · w_max %.4f~%.4f · N_eff %.1f~%.1f(중앙 %.1f · 1/N 대비 %.2f) · 월간 Σ|Δw| 평균 %.3f(첫 달 제외) · rgamma 언더플로 치환 %d건\n",
            min(.DG$sigma), max(.DG$sigma), median(.DG$sigma), min(.DG$w_max), max(.DG$w_max),
            min(.DG$n_eff), max(.DG$n_eff), median(.DG$n_eff), median(.DG$n_eff / .DG$n_elig),
            if (nrow(.DG) > 1L) mean(.DG$to[-1L]) else NA_real_, .GUARD$n0))
cat(sprintf("  θ 월별 평균±표준편차(Fig.2 대응 · 학습 통계이지 성과 아님): %s\n",
            paste(sprintf("%s %+.3f±%.3f", colnames(.THM), .th_mean, .th_sd), collapse = " · ")))
cat(sprintf("  PORTFOLIO %d행 · FACTORS %d행 · %.1f분 · 러너 사양 = FIDELITY 파일 portfolio_spec(engine_direct) · commission_paper = null(논문 성과 = gross → 병기)\n",
            nrow(PORTFOLIO), nrow(FACTORS), .mins))

rm(.P, .ME_ROWS, .FYK, .X); gc(verbose = FALSE)
PORTFOLIO <- PORTFOLIO[, .(Date, Ticker, Weight, Leg)]
FACTORS   <- FACTORS[, .(Date, Ticker, Score)]
