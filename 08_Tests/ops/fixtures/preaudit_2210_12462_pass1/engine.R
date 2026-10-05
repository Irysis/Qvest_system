# ===========================================================================
# engine.R — RP_AUTO_CLEAN_2210_12462
# "Factor Investing with a Deep Multi-Factor Model" (arXiv:2210.12462)
#
# fidelity = adapted.  무엇을 남기고 무엇을 바꿨는지는 FIDELITY.json 이 유일한
# 통로다(이 주석은 통로가 아니다 — 신고는 전부 그 파일에 있다).
#
# 산출: PORTFOLIO(Date, Ticker, Weight, Leg)
#       portfolio_spec = {"construction":"engine_direct"}  (논문 비중 그대로)
#
# 기전(논문 Methodology): 종목의 멀티팩터 컨텍스트를 세 계층으로 분해하고
#   ① 원 컨텍스트 C          (Eq 1)
#   ② 업종 잔차  C_I = C - H_I,   H_I = 업종 그래프 이웃 영향   (Eq 2~4)
#   ③ 지수 잔차  C_U = C_I - H_U, H_U = 유니버스 그래프 이웃 영향 (Eq 5~6)
#   세 계층을 **함께** 써서 딥팩터를 만든다(Eq 8). 가중은 누적 팩터수익과
#   ICIR 를 최대화하는 비음(nonneg) attention 벡터다(Eq 9~13).
#   랭킹 상위 10% 동일가중·월간 리밸.
#
# PIT: 모든 학습 통계는 **실현 완료일(Usable_Date)이 결정일보다 엄격히 앞선**
#   관측만 쓴다(확장창). 전표본 통계 없음. 횡단면 통계는 그 날짜 단면만.
#   팩터 DB 는 load_month_factors() 경유(C15) · Z_Score_Aligned 만 소비(C13).
# ===========================================================================

suppressWarnings(suppressMessages({
  library(data.table)
}))

# ---- 상수 (전부 FIDELITY.json::constants 에 신고) --------------------------
TOP_FRAC            <- 0.10                 # paper: "10% most attractive stocks"
HORIZONS            <- c(3L, 5L, 10L, 15L, 20L)  # paper: k-forward trading days
N_LEVELS            <- 3L                   # paper Eq 8: C || C_I || C_U 3계층 concat
MIN_TRAIN_MONTHS    <- 66L                  # paper: 1st train block 2010/1/1~2015/6/30
RETRAIN_MONTHS      <- c(1L, 7L)            # paper: train set extended every six months
ICIR_FLOOR          <- 0                    # paper Eq 10 softmax => nonneg weights
START_DATE          <- as.Date("2005-01-01")     # harness H3
MIN_STOCKS          <- 30L                  # supplement: 단면 하한
MIN_FACTORS_PRESENT <- 5L                   # supplement: 그 달 존재 팩터 하한
ZERO_SD_EPS         <- 1e-12                # supplement: 분모 가드

# 논문의 5개 그룹(reversal · value · size · momentum · quality)에 대응.
# 지표별 대응·등록부 정의·이탈은 FIDELITY.json::factor_mapping 에 전부 신고.
FACTOR_IDS <- c(
  "M11_ST_Reversal", "M12_LR_Reversal",                                  # reversal
  "V01_BM", "V02_EP", "V03_CFP", "V08_PSR",                              # value
  "S01_Size",                                                            # size
  "M01_Mom_12_1", "M02_Mom_6_1", "M03_Mom_3_1", "M10_Intermediate_Mom",  # momentum
  "Q01_GPA", "Q02_ROE", "Q03_ROA", "Q05_Accrual", "Q06_Asset_Growth",
  "Q13_Fin_Leverage"                                                     # quality
)

# 컨텍스트·IC 패널 시작 = 측정 시작 − 논문 최초 학습블록(66개월). 측정 창
# 이전 구간은 학습에만 쓰이고 산출되지 않는다(아래 START_DATE 필터).
PANEL_START <- seq(START_DATE, by = "-1 month",
                   length.out = MIN_TRAIN_MONTHS + 1L)[MIN_TRAIN_MONTHS + 1L]

# ---- 인프라 적재 (C15 유일 경로) ------------------------------------------
.ENG_ROOT <- local({
  cand <- c(Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""),
            if (exists("PROJECT_ROOT", inherits = TRUE))
              as.character(get("PROJECT_ROOT", inherits = TRUE))[1] else "",
            getwd())
  hit <- NA_character_
  for (p in cand)
    if (nzchar(p) && file.exists(file.path(p, "02_Infrastructure", "config.R"))) { hit <- p; break }
  if (is.na(hit)) stop("[2210.12462] project root not found")
  hit
})
source(file.path(.ENG_ROOT, "02_Infrastructure", "factor_db", "factor_db_connector.R"))

# ---- 도우미 ---------------------------------------------------------------
.mkey <- function(d) as.integer(format(as.Date(d), "%Y%m"))

# 횡단면 z — **한 날짜의 단면 통계만** 쓴다(시계열·전표본 통계 아님).
# Z_Score_Aligned 는 팩터 DB 전체 단면에서 표준화된 값이라, 우리 유니버스
# 부분집합에서는 sd != 1 이다. 계층 간 축척을 맞추기 위해 다시 표준화한다.
.xs_z <- function(M) {
  for (j in seq_len(ncol(M))) {
    v <- M[, j]
    v[!is.finite(v)] <- 0
    s <- sd(v)
    M[, j] <- if (is.finite(s) && s > ZERO_SD_EPS) (v - mean(v)) / s else 0
  }
  M
}

# 그래프 이웃 영향 = 균일 attention(이웃 단면 평균). GAT 의 attention 파라미터는
# 논문 미공개이므로 균일 가중 극한을 쓴다. 단독 노드는 잔차가 정확히 0 이 되고,
# 이는 self-loop GAT 의 거동과 같다.
.nbr_mean <- function(M, g) {
  g <- as.character(g)
  s <- rowsum(M, group = g, reorder = FALSE)
  n <- as.vector(table(factor(g, levels = rownames(s))))
  (s / n)[match(g, rownames(s)), , drop = FALSE]
}

# 팩터 패널 적재. 요청월 파일이 없어 closest-earlier 가 대체 적재되면(연결자
# 거동) 그 달은 버린다 — stale 값이 패널·IC 에 섞이지 않게.
.load_fac <- function(sig_d) {
  out <- NULL
  ok <- tryCatch({
    suppressWarnings(invisible(capture.output(
      out <- load_month_factors(sig_d, factor_names = FACTOR_IDS))))
    TRUE
  }, error = function(e) FALSE)
  if (!isTRUE(ok) || is.null(out) || !nrow(out)) return(NULL)
  asof <- attr(out, "factor_db_asof_date")
  if (length(asof) != 1L || is.na(asof)) return(NULL)
  if (!identical(.mkey(asof), .mkey(sig_d))) return(NULL)
  out
}

# 한 시그널일의 3계층 컨텍스트 X (n x 3m). 실패·미달이면 NULL(그 달 산출 없음).
.build_ctx <- function(sig_d, UNI) {
  u <- UNI[[as.character(as.integer(sig_d))]]
  if (is.null(u) || nrow(u) < MIN_STOCKS) return(NULL)
  f <- .load_fac(sig_d)
  if (is.null(f)) return(NULL)
  f <- f[Ticker %in% u$Ticker & is.finite(Z_Score_Aligned)]
  if (!nrow(f)) return(NULL)
  f <- unique(f, by = c("Ticker", "Factor_Name"))
  if (uniqueN(f$Factor_Name) < MIN_FACTORS_PRESENT) return(NULL)

  W <- dcast(f, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")
  gap <- setdiff(FACTOR_IDS, names(W))
  if (length(gap)) W[, (gap) := 0]
  if (nrow(W) < MIN_STOCKS) return(NULL)

  M0 <- as.matrix(W[, FACTOR_IDS, with = FALSE])
  M0[!is.finite(M0)] <- 0

  kk  <- u[match(W$Ticker, u$Ticker)]
  ind <- as.character(kk$Sector)
  ind[is.na(ind) | !nzchar(ind)] <- "NA_IND"
  idx <- ifelse(!is.na(kk$K200) & kk$K200 == TRUE, "K200", "KQ150")

  C_I <- M0  - .nbr_mean(M0,  ind)      # Eq 3~4  업종 중성화
  C_U <- C_I - .nbr_mean(C_I, idx)      # Eq 5~6  지수(유니버스) 중성화

  X <- cbind(.xs_z(M0), .xs_z(C_I), .xs_z(C_U))
  colnames(X) <- c(paste0("L0_", FACTOR_IDS), paste0("L1_", FACTOR_IDS),
                   paste0("L2_", FACTOR_IDS))
  rownames(X) <- W$Ticker
  X
}

# ---- 달력 · 시그널일(월 마지막 거래일) ------------------------------------
all_dates <- sort(unique(RAWDATA$Date))
.mk       <- .mkey(all_dates)
sig_dates <- all_dates[c(.mk[-1] != .mk[-length(.mk)], TRUE)]
sig_dates <- sig_dates[sig_dates >= PANEL_START]
pos       <- match(as.integer(sig_dates), as.integer(all_dates))
if (!length(sig_dates)) stop("[2210.12462] 시그널일 0 — RAWDATA 달력 확인")

# ---- 유니버스 (시그널일 당일 멤버십 · PIT 시변) ---------------------------
UNI_DT <- RAWDATA[as.integer(Date) %in% as.integer(sig_dates) &
                    (K200 == TRUE | KQ150 == TRUE),
                  .(Di = as.integer(Date), Ticker, Sector, K200, KQ150)]
UNI_DT <- unique(UNI_DT, by = c("Di", "Ticker"))
UNI    <- split(UNI_DT, by = "Di", keep.by = FALSE)

# ---- k-forward 실현수익용 가격판 (필요 날짜만) ----------------------------
pk       <- as.vector(outer(pos, HORIZONS, "+"))
pk       <- pk[pk >= 1L & pk <= length(all_dates)]
need_pos <- sort(unique(c(pos, pk)))
need_i   <- as.integer(all_dates[need_pos])
sel_rows <- as.integer(RAWDATA$Date) %in% need_i
PX <- RAWDATA[sel_rows, .(Di = as.integer(Date), Ticker, Close)]
PX <- PX[is.finite(Close) & Close > 0]
PX <- unique(PX, by = c("Di", "Ticker"))
PW <- dcast(PX, Ticker ~ Di, value.var = "Close")
PM <- as.matrix(PW[, -1L, with = FALSE])
rownames(PM) <- PW$Ticker
rm(PX, PW, sel_rows, UNI_DT); invisible(gc(verbose = FALSE))

# ---- 1) 컨텍스트 패널 + IC 패널 -------------------------------------------
# IC[s,k,j] = 시그널월 s 의 컨텍스트 열 j 와 s 이후 k 거래일 실현수익의 순위상관.
# IC_USABLE_DATE[s,k] = 그 수익이 실현 완료된 날 = 이 관측을 쓸 수 있는 가장
#   이른 날. 학습은 IC_USABLE_DATE < 결정일 인 관측만 본다(아래 .block_weights).
NCOL_X <- N_LEVELS * length(FACTOR_IDS)
IC_VAL <- matrix(NA_real_, nrow = length(sig_dates) * length(HORIZONS), ncol = NCOL_X)
IC_K             <- integer(nrow(IC_VAL))
IC_USABLE_DATE   <- rep(NA_integer_, nrow(IC_VAL))
CTX <- vector("list", length(sig_dates))
rr  <- 0L

for (ii in seq_along(sig_dates)) {
  s <- sig_dates[ii]
  X <- .build_ctx(s, UNI)
  CTX[[ii]] <- X
  if (is.null(X)) next
  key0 <- as.character(as.integer(s))
  if (!(key0 %in% colnames(PM))) next
  p0 <- PM[, key0]
  tk <- rownames(X)
  a  <- p0[tk]
  for (hh in seq_along(HORIZONS)) {
    kq <- HORIZONS[hh]
    pe <- pos[ii] + kq
    if (pe > length(all_dates)) next
    key1 <- as.character(as.integer(all_dates[pe]))
    if (!(key1 %in% colnames(PM))) next
    FwdCum <- PM[, key1][tk] / a - 1
    good   <- is.finite(FwdCum)
    if (sum(good) < MIN_STOCKS) next
    rr <- rr + 1L
    IC_K[rr]           <- kq
    IC_USABLE_DATE[rr] <- as.integer(all_dates[pe])
    IC_VAL[rr, ] <- suppressWarnings(as.vector(
      cor(X[good, , drop = FALSE], FwdCum[good], method = "spearman")))
  }
}
IC_VAL         <- IC_VAL[seq_len(rr), , drop = FALSE]
IC_K           <- IC_K[seq_len(rr)]
IC_USABLE_DATE <- IC_USABLE_DATE[seq_len(rr)]

# ---- 2) 가중 (Eq 8~13 의 닫힌형 대체) -------------------------------------
# 한 head(k)의 가중: w_j ∝ max(ICIR_j, 0), Σw = 1.
#   ICIR_j = mean(IC_j) / sd(IC_j) — 분자는 누적 팩터수익에 단조, 분모는 안정성.
#   비음·합1 은 논문 Eq 10 softmax 의 성질이다.
.head_weights <- function(rows_idx) {
  if (!length(rows_idx)) return(NULL)
  V    <- IC_VAL[rows_idx, , drop = FALSE]
  nobs <- colSums(is.finite(V))
  mu   <- colMeans(V, na.rm = TRUE)
  sg   <- apply(V, 2L, sd, na.rm = TRUE)
  mu[!is.finite(mu)] <- 0                     # 관측 전무 열 → 기여 0
  sg[!is.finite(sg)] <- 0
  w   <- rep(ICIR_FLOOR, length(mu))          # 자격 미달 열의 가중 = 0
  okj <- sg > ZERO_SD_EPS & nobs >= MIN_TRAIN_MONTHS
  w[okj] <- pmax(mu[okj] / sg[okj], ICIR_FLOOR)
  if (!any(w > ICIR_FLOOR)) return(NULL)
  w / sum(w)
}

# 블록 가중 = head 별 가중의 k∈K 균등 평균(Eq 13 이 k 를 균등 평균한다).
.block_weights <- function(sig_d) {
  cut_i <- as.integer(sig_d)
  ok    <- which(IC_USABLE_DATE < cut_i)        # 실현 완료가 결정일보다 엄격히 앞선 것만
  if (!length(ok)) return(NULL)
  acc <- NULL; nh <- 0L
  for (hh in seq_along(HORIZONS)) {
    w <- .head_weights(ok[IC_K[ok] == HORIZONS[hh]])
    if (is.null(w)) next
    acc <- if (is.null(acc)) w else acc + w
    nh  <- nh + 1L
  }
  if (is.null(acc) || nh == 0L) return(NULL)
  acc / nh
}

# ---- 3) 산출 (6개월 블록마다 재학습 · 블록 내 가중 고정) ------------------
OUT  <- vector("list", length(sig_dates))
Wcur <- NULL
n_rt <- 0L
for (ii in seq_along(sig_dates)) {
  s  <- sig_dates[ii]
  mo <- as.integer(format(s, "%m"))
  if (mo %in% RETRAIN_MONTHS) {
    wnew <- .block_weights(s)
    if (!is.null(wnew)) { Wcur <- wnew; n_rt <- n_rt + 1L }
  }
  if (is.null(Wcur) || s < START_DATE) next
  X <- CTX[[ii]]
  if (is.null(X)) next
  sc <- as.vector(X %*% Wcur)
  nn <- length(sc)
  if (nn < MIN_STOCKS || !all(is.finite(sc))) next
  ktop <- max(1L, as.integer(round(nn * TOP_FRAC)))
  pick <- rownames(X)[order(sc, decreasing = TRUE)[seq_len(ktop)]]
  OUT[[ii]] <- data.table(Date = s, Ticker = pick, Weight = 1 / ktop, Leg = "long")
}

PORTFOLIO <- rbindlist(OUT[!vapply(OUT, is.null, logical(1))], use.names = TRUE)
if (!nrow(PORTFOLIO))
  stop("[2210.12462] PORTFOLIO 0행 — 가중 미산출(IC 학습창 부족) 또는 컨텍스트 전무")

# ---- 진단 (거동 변경 아님 · 로그만) ---------------------------------------
.nsec <- vapply(UNI, function(d) uniqueN(d$Sector), integer(1))
cat(sprintf(paste0("[2210.12462] sig=%d · ctx=%d · IC rows=%d · retrain=%d · ",
                   "sector/date median=%d · hold %s~%s · n/date median=%d\n"),
            length(sig_dates), sum(!vapply(CTX, is.null, logical(1))), rr, n_rt,
            as.integer(stats::median(.nsec)),
            format(min(PORTFOLIO$Date)), format(max(PORTFOLIO$Date)),
            as.integer(stats::median(PORTFOLIO[, .N, by = Date]$N))))
