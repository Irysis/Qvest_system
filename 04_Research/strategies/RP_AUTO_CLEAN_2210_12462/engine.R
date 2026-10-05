# ===========================================================================
# engine.R — RP_AUTO_CLEAN_2210_12462
# "Factor Investing with a Deep Multi-Factor Model" (arXiv:2210.12462v1)
#
# fidelity = adapted.  무엇을 남기고 무엇을 바꿨는지는 FIDELITY.json 이 유일한
# 통로다(이 주석은 통로가 아니다 — 신고는 전부 그 파일에 있다).
#
# 산출: PORTFOLIO(Date, Ticker, Weight, Leg)
#       portfolio_spec = {"construction":"engine_direct"}
#
# 논문 구조(Methodology Eq 1~13 · Experiments):
#   한 번의 실행 = 한 개 광역지수 유니버스. 그 유니버스 안에서
#     Eq 1    C   = MLP(BatchNorm(F))              컨텍스트
#     Eq 2~4  C_I = C   - H_I,  H_I = GAT(M C)     업종 영향 차감
#     Eq 5~6  C_U = C_I - H_U,  H_U = GAT(C_I)     유니버스 영향 차감
#     Eq 7~8  f_k = LeakyReLU(W_k^T (C || C_I || C_U))
#     Eq 13   L   = mean_k mean_t (d_k^t - b_k^t - c_k)   (c = ICIR)
#   를 walk-forward(6개월 블록 · 학습창 종점은 블록 시작 6개월 전)로 적합하고,
#   그 유니버스 구성종목 수의 상위 10% 를 동일가중·월간 리밸로 보유한다.
#   Table 1 이 CSI1000/500/300 별 지표를 따로 보고하므로 유니버스가 실행 단위다
#   → 여기서는 K200 과 KQ150 을 **각각 한 번씩** 돌리고, 측정이 포트폴리오 1개를
#     받으므로 두 슬리브의 선택종목 합집합을 동일가중으로 낸다(FIDELITY.changed).
#
# PIT: 팩터 패널은 as-of(계산 기준일) <= 결정일 인 가장 최근 월판만 쓴다.
#   학습은 앵커일 < (블록 시작 - 6개월) 이고 실현 완료일 < 블록 시작 인 관측만.
#   횡단면 통계는 그 날짜 단면만(전표본 통계 없음). 팩터 DB 는
#   load_month_factors() 경유(C15) · Z_Score_Aligned 만 소비(C13).
# ===========================================================================

suppressWarnings(suppressMessages({
  library(data.table)
}))

# ---- 상수 (전부 FIDELITY.json::constants 에 신고) --------------------------
TOP_FRAC            <- 0.1       # paper: "the 10% most attractive stocks"
HORIZONS            <- c(3L, 5L, 10L, 15L, 20L)   # paper: k-forward trading days
N_LEVELS            <- 3L        # paper Eq 8: C || C_I || C_U
TRAIN_BLOCK_MONTHS  <- 66L       # paper: 1st training block 2010/1/1~2015/6/30
GAP_MONTHS          <- 6L        # paper: train end 2015/6/30 -> test start 2016/1/1
BLOCK_START_MONTHS  <- c(1L, 7L) # paper: six-month test blocks
SHRINK_LAMBDA       <- 0.5       # supplement: covariance shrink (untuned midpoint)
START_DATE          <- as.Date("2005-01-01")      # harness H3
COVERAGE_MIN        <- 0.05      # harness: load_month_factors() default
MIN_XS              <- 30L       # supplement: cross-section floor
MIN_FACTORS_PRESENT <- 5L        # supplement: covered-column floor
MIN_TRAIN_OBS       <- 252L      # supplement: covariance estimation floor
ZERO_SD_EPS         <- 1e-12     # supplement: denominator guard

# 논문의 5개 그룹(reversal · value · size · momentum · quality)에 대응.
# 지표별 대응·등록부 정의·이탈은 FIDELITY.json::factor_mapping 에 전부 신고.
FACTOR_IDS <- c(
  "M11_ST_Reversal", "M12_LR_Reversal",                                  # reversal
  "V01_BM", "V02_EP", "V03_CFP", "V08_PSR",                              # value
  "S01_Size",                                                            # size
  "M01_Mom_12_1", "M02_Mom_6_1", "M03_Mom_3_1", "M10_Intermediate_Mom",   # momentum
  "Q01_GPA", "Q02_ROE", "Q03_ROA", "Q05_Accrual", "Q06_Asset_Growth",
  "Q13_Fin_Leverage"                                                     # quality
)

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

# ---- 도우미 (순수 함수 · 한 날짜 단면 통계만) ------------------------------

# 달 이동 도우미.
.add_months <- function(d, k) seq(d, by = paste0(k, " months"), length.out = 2L)[2L]
.sub_months <- function(d, k) seq(d, by = paste0("-", k, " months"), length.out = 2L)[2L]

# 6개월 테스트블록의 시작일(논문 예시 = 1/1 또는 7/1).
.block_start <- function(d) {
  y <- as.integer(format(d, "%Y")); m <- as.integer(format(d, "%m"))
  as.Date(sprintf("%04d-%02d-01", y, if (m <= 6L) BLOCK_START_MONTHS[1L] else BLOCK_START_MONTHS[2L]))
}

# 횡단면 z — 한 날짜의 단면 통계만(시계열·전표본 통계 아님).
# sd 가 가드 이하인 열은 0 으로 둔다(정보 없음 = 중립).
.xs_z <- function(M) {
  n  <- nrow(M)
  mu <- colMeans(M)
  Mc <- M - rep(mu, each = n)
  sg <- sqrt(colSums(Mc * Mc) / (n - 1L))
  bad <- !is.finite(sg) | sg <= ZERO_SD_EPS
  sg[bad] <- 1
  Z <- Mc / rep(sg, each = n)
  if (any(bad)) Z[, bad] <- 0
  Z
}

# 열 중심화 + 단위노름(상관 계산용). 분산 0 열은 NA 로 표시해 IC 에서 제외된다.
.std_cols <- function(M) {
  n  <- nrow(M)
  Mc <- M - rep(colMeans(M), each = n)
  s  <- sqrt(colSums(Mc * Mc))
  bad <- !is.finite(s) | s <= ZERO_SD_EPS
  s[bad] <- 1
  Z <- Mc / rep(s, each = n)
  if (any(bad)) Z[, bad] <- NA_real_
  Z
}

.col_rank <- function(M) apply(M, 2L, rank)

# 업종 그래프 영향 H_I (Eq 3) = 같은 업종 이웃의 단면 평균(균일 attention 극한).
# 논문 Definition 3 이 업종중성을 "같은 업종 다른 종목 대비 차이"로 정의하므로
# 이 극한이 그 서술과 일치한다. 단독 업종 노드는 잔차가 정확히 0 이 된다.
.grp_mean <- function(M, g) {
  s  <- rowsum(M, group = g, reorder = FALSE)
  lv <- rownames(s)
  n  <- as.integer(table(factor(g, levels = lv)))
  (s / n)[match(g, lv), , drop = FALSE]
}

# 유니버스 그래프 영향 H_U (Eq 5) = 완전그래프 위 유사도 attention 의 rank-1 극한.
#   GAT 는 H_U = A C_I (A = n x n attention). 균일 attention A = (1/n)11^T 는
#   열별 위치이동뿐이어서 뒤따르는 횡단면 표준화에 완전히 소거되고 C_U 가 C_I 와
#   수치적으로 같아진다 — Eq 8 의 세 계층이 두 계층으로 붕괴한다. 그래서 유사도
#   구조를 남기는 rank-1 극한 A = u u^T (u = C_I 의 최대 좌특이벡터)를 쓴다.
#   C_I 는 열합이 0 이라 열공간이 1 벡터와 직교 => u ⊥ 1 이므로 u u^T C_I 는
#   위치이동이 아니고 붕괴가 구조적으로 불가능하다.
.rank1_infl <- function(M) {
  G  <- crossprod(M)
  ev <- tryCatch(eigen(G, symmetric = TRUE), error = function(e) NULL)
  if (is.null(ev)) return(matrix(0, nrow(M), ncol(M)))
  s   <- as.vector(M %*% ev$vectors[, 1L])
  nrm <- sqrt(sum(s * s))
  if (!is.finite(nrm) || nrm <= ZERO_SD_EPS) return(matrix(0, nrow(M), ncol(M)))
  u <- s / nrm
  u %o% as.vector(crossprod(u, M))
}

# ---- 본체 -----------------------------------------------------------------
PORTFOLIO <- local({

  NF <- length(FACTOR_IDS)

  # ---- 1) 달력 · 유니버스(지수별) · 가격판 --------------------------------
  all_dates <- sort(unique(RAWDATA$Date))
  nD <- length(all_dates)
  di <- as.integer(all_dates)
  ymk <- as.integer(format(all_dates, "%Y%m"))
  is_me <- c(ymk[-1L] != ymk[-nD], TRUE)          # 월 마지막 거래일 = 시그널일

  U <- RAWDATA[(K200 == TRUE | KQ150 == TRUE), .(Date, Ticker, Sector, K200)]
  if (!nrow(U)) stop("[2210.12462] RAWDATA 멤버십 행 0 — K200/KQ150 플래그 확인")
  tk_u <- sort(unique(U$Ticker))
  U[, `:=`(ti = match(Ticker, tk_u), dj = match(as.integer(Date), di))]
  U <- U[!is.na(ti) & !is.na(dj)]
  U <- unique(U, by = c("dj", "ti"))
  U[, sec := as.character(Sector)]
  U[is.na(sec) | !nzchar(sec), sec := "NA_IND"]

  # 지수 식별. 양쪽 플래그가 켜진 종목은 K200 군으로만 둔다(이중 보유 방지).
  IDX_NAMES <- c("K200", "KQ150")
  U[, grp := fifelse(!is.na(K200) & K200 == TRUE, IDX_NAMES[1L], IDX_NAMES[2L])]

  mk_mem <- function(sub) {
    setorder(sub, dj, ti)
    byd <- vector("list", nD)
    sp <- split(seq_len(nrow(sub)), sub$dj)
    for (nm in names(sp)) byd[[as.integer(nm)]] <- sp[[nm]]
    list(ti = sub$ti, sec = sub$sec, byd = byd)
  }
  MEM <- lapply(IDX_NAMES, function(g) mk_mem(U[grp == g, .(dj, ti, sec)]))
  names(MEM) <- IDX_NAMES

  # 가격판(유니버스에 한 번이라도 들어온 종목 x 전 거래일). 종가는 유한·양수만.
  PX <- RAWDATA[Ticker %in% tk_u & is.finite(Close) & Close > 0,
                .(ti = match(Ticker, tk_u), dj = match(as.integer(Date), di), Close)]
  PX <- PX[!is.na(ti) & !is.na(dj)]
  PX <- unique(PX, by = c("ti", "dj"))
  PM <- matrix(NA_real_, nrow = length(tk_u), ncol = nD)
  PM[cbind(PX$ti, PX$dj)] <- PX$Close
  rm(PX); invisible(gc(verbose = FALSE))

  # ---- 2) 팩터 패널 (월판 · as-of <= 결정일 인 가장 최근 것) ---------------
  # 월판의 as-of 는 그 달 거래 말일이다. 따라서 월 중 거래일 t 에서 쓸 수 있는
  # 것은 **직전 월판**이고, 월 말일에는 그 달 월판이 쓸 수 있게 된다.
  me_idx <- which(is_me)
  p_asof <- rep(NA_integer_, length(me_idx))
  p_ti   <- vector("list", length(me_idx))
  p_val  <- vector("list", length(me_idx))
  for (q in seq_along(me_idx)) {
    d <- all_dates[me_idx[q]]
    f <- NULL
    okl <- tryCatch({
      suppressWarnings(invisible(capture.output(
        f <- load_month_factors(d, coverage_min = COVERAGE_MIN, factor_names = FACTOR_IDS))))
      TRUE
    }, error = function(e) FALSE)
    if (!isTRUE(okl) || is.null(f) || !nrow(f)) next
    az <- attr(f, "factor_db_asof_date")
    if (length(az) != 1L || is.na(az)) next
    az <- as.Date(az)
    # 요청월과 다른 월이 대체 적재된 달은 버린다(stale 값 차단) · as-of 가 요청일을
    # 넘는 달도 버린다(미래 기준일 차단).
    if (!identical(format(az, "%Y%m"), format(d, "%Y%m")) || az > d) next
    f <- f[Ticker %in% tk_u & is.finite(Z_Score_Aligned)]
    if (!nrow(f)) next
    f <- unique(f, by = c("Ticker", "Factor_Name"))
    W <- dcast(f, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")
    miss <- setdiff(FACTOR_IDS, names(W))
    if (length(miss)) W[, (miss) := NA_real_]
    M <- as.matrix(W[, FACTOR_IDS, with = FALSE])
    M[!is.finite(M)] <- NA_real_
    if (sum(colSums(!is.na(M)) > 0L) < MIN_FACTORS_PRESENT) next
    p_asof[q] <- as.integer(az)
    p_ti[[q]] <- match(W$Ticker, tk_u)
    p_val[[q]] <- M
  }
  keep <- which(!is.na(p_asof))
  if (!length(keep)) stop("[2210.12462] 사용 가능한 팩터 월판 0 — 팩터 DB 가용월 확인")
  p_asof <- p_asof[keep]; p_ti <- p_ti[keep]; p_val <- p_val[keep]
  p_start <- findInterval(p_asof, di)                 # as-of 거래일 인덱스
  pan_of <- findInterval(seq_len(nD), p_start)        # 날짜별 적용 패널(0 = 없음)

  # ---- 3) 컨텍스트 3계층 (Eq 1~6) ----------------------------------------
  # 선택풀 = 그 날 지수 구성종목 **전체**(논문은 결측 팩터 종목의 제외를 서술하지
  # 않는다). 결측 셀은 그 단면 커버 종목의 열평균으로 중립 대입하고, 관측이 하나도
  # 없는 종목은 세 계층 전부 0(중립)으로 둔다.
  build_ctx <- function(tij, secj, pidx) {
    pt  <- p_ti[[pidx]]
    pos <- match(tij, pt)
    Fm  <- matrix(NA_real_, nrow = length(tij), ncol = NF)
    hit <- !is.na(pos)
    if (!any(hit)) return(NULL)
    Fm[hit, ] <- p_val[[pidx]][pos[hit], , drop = FALSE]
    ncov <- colSums(!is.na(Fm))
    if (sum(ncov > 0L) < MIN_FACTORS_PRESENT) return(NULL)
    rcov <- rowSums(!is.na(Fm))
    cm <- colMeans(Fm, na.rm = TRUE)
    cm[!is.finite(cm)] <- 0
    for (j in which(ncov < nrow(Fm))) Fm[is.na(Fm[, j]), j] <- cm[j]
    C0 <- .xs_z(Fm)                                  # Eq 1 (MLP = 항등)
    C1 <- C0 - .grp_mean(C0, secj)                   # Eq 3~4
    C2 <- C1 - .rank1_infl(C1)                       # Eq 5~6
    X <- cbind(C0, .xs_z(C1), .xs_z(C2))             # Eq 8 concat
    if (ncol(X) != N_LEVELS * NF) return(NULL)
    if (any(rcov == 0L)) X[rcov == 0L, ] <- 0
    X
  }

  # ---- 4) 적합 (Eq 13 의 ICIR 항 닫힌형) ----------------------------------
  # IC_t(w) = corr(X_t w, r_{t+k}) = w'B_t / sqrt(w' Omega w) (단위분산 열 기준).
  # Omega 가 학습창에서 근사 일정하면 분모가 mean 과 sd 사이에서 상쇄되어
  # ICIR(w) = mean_t(w'B_t)/sd_t(w'B_t) 이고, 최대해는 w ∝ Sigma^{-1} mu 다
  # (Sigma = cov_t(B_t)). 부호 제약 없음(Eq 8 의 W_k 에 부호 제약이 없다).
  # 중복에 가까운 열이 있어도 Sigma^{-1} 는 가중을 **나눠** 주므로 같은 신호가
  # 두 번 더해지지 않는다. 51 열이 강하게 공선이라 Sigma 를 대각으로 수축한다.
  head_w <- function(B) {
    nobs <- colSums(is.finite(B))
    kc <- nobs >= MIN_TRAIN_OBS
    if (!any(kc)) return(NULL)
    Bk <- B[, kc, drop = FALSE]
    rk <- rowSums(!is.finite(Bk)) == 0L
    if (sum(rk) < MIN_TRAIN_OBS) return(NULL)
    Bk <- Bk[rk, , drop = FALSE]
    mu <- colMeans(Bk)
    S  <- stats::cov(Bk)
    Ss <- (1 - SHRINK_LAMBDA) * S + SHRINK_LAMBDA * diag(diag(S), nrow = ncol(S))
    wk <- tryCatch(as.vector(solve(Ss, mu)), error = function(e) NULL)
    if (is.null(wk) || !all(is.finite(wk))) {
      dv <- diag(S)
      dv[!is.finite(dv) | dv <= ZERO_SD_EPS] <- NA_real_
      wk <- mu / dv
      wk[!is.finite(wk)] <- 0
    }
    w <- numeric(ncol(B)); w[kc] <- wk
    s <- sum(abs(w))
    if (!is.finite(s) || s <= ZERO_SD_EPS) return(NULL)
    w / s
  }

  # ---- 5) 지수별 실행 ----------------------------------------------------
  sel <- list(); nsel <- 0L
  dg <- list()
  for (g in IDX_NAMES) {
    mm <- MEM[[g]]

    # (a) 일별 앵커로 컨텍스트·IC 패널 적립 (논문 "dataset on a daily basis").
    nmax <- nD * length(HORIZONS)
    ICV <- matrix(NA_real_, nrow = nmax, ncol = N_LEVELS * NF)
    IC_anchor <- rep(NA_integer_, nmax)
    IC_Usable_Date <- rep(NA_integer_, nmax)
    IC_k <- rep(NA_integer_, nmax)
    nr <- 0L
    first_j <- NA_integer_
    for (j in seq_len(nD)) {
      rws <- mm$byd[[j]]
      if (is.null(rws) || length(rws) < MIN_XS) next
      pidx <- pan_of[j]
      if (pidx < 1L) next
      tij <- mm$ti[rws]
      X <- build_ctx(tij, mm$sec[rws], pidx)
      if (is.null(X)) next
      if (is.na(first_j)) first_j <- j
      p0 <- PM[tij, j]
      Zfull <- NULL
      for (hh in seq_along(HORIZONS)) {
        kq <- HORIZONS[hh]
        je <- j + kq
        if (je > nD) next
        rz <- PM[tij, je] / p0 - 1
        gd <- is.finite(rz)
        ng <- sum(gd)
        if (ng < MIN_XS) next
        if (ng == length(rz)) {
          if (is.null(Zfull)) Zfull <- .std_cols(.col_rank(X))
          Zx <- Zfull; yv <- rz
        } else {
          Zx <- .std_cols(.col_rank(X[gd, , drop = FALSE])); yv <- rz[gd]
        }
        yz <- rank(yv); yz <- yz - mean(yz)
        yn <- sqrt(sum(yz * yz))
        if (!is.finite(yn) || yn <= ZERO_SD_EPS) next
        nr <- nr + 1L
        IC_anchor[nr] <- di[j]
        IC_Usable_Date[nr] <- di[je]
        IC_k[nr] <- kq
        ICV[nr, ] <- as.vector(crossprod(Zx, yz / yn))
      }
    }
    if (nr < 1L || is.na(first_j)) { dg[[g]] <- "데이터 없음"; next }
    ICV <- ICV[seq_len(nr), , drop = FALSE]
    IC_anchor <- IC_anchor[seq_len(nr)]
    IC_Usable_Date <- IC_Usable_Date[seq_len(nr)]
    IC_k <- IC_k[seq_len(nr)]

    # 이 유니버스의 데이터 시작 = 첫 유효 컨텍스트일(논문의 2010/1/1 대응물).
    pstart <- all_dates[first_j]
    train_min_end <- .add_months(pstart, TRAIN_BLOCK_MONTHS)

    # (b) 블록별 적합 + 월말 산출.
    blk_w <- function(bs) {
      gc_cut <- as.integer(.sub_months(bs, GAP_MONTHS))
      if (gc_cut < as.integer(train_min_end)) return(NULL)
      bi <- as.integer(bs)
      acc <- NULL; nh <- 0L
      for (kq in HORIZONS) {
        tr <- which(IC_k == kq & IC_anchor < gc_cut & IC_Usable_Date < bi)
        if (length(tr) < MIN_TRAIN_OBS) next
        w <- head_w(ICV[tr, , drop = FALSE])
        if (is.null(w)) next
        acc <- if (is.null(acc)) w else acc + w
        nh <- nh + 1L
      }
      if (is.null(acc) || nh < 1L) return(NULL)
      acc / nh
    }

    cur_bs <- NULL; Wc <- NULL; n_blk <- 0L; n_out <- 0L
    for (j in me_idx) {
      s <- all_dates[j]
      if (s < START_DATE) next
      bs <- .block_start(s)
      if (is.null(cur_bs) || bs != cur_bs) {
        cur_bs <- bs
        Wc <- blk_w(bs)
        if (!is.null(Wc)) n_blk <- n_blk + 1L
      }
      if (is.null(Wc)) next
      rws <- mm$byd[[j]]
      if (is.null(rws) || length(rws) < MIN_XS) next
      pidx <- pan_of[j]
      if (pidx < 1L) next
      tij <- mm$ti[rws]
      X <- build_ctx(tij, mm$sec[rws], pidx)
      if (is.null(X)) next
      sc <- as.vector(X %*% Wc)
      if (!all(is.finite(sc))) next
      # 분위 모수 = 그 날 이 지수의 구성종목 수(선택풀 = 멤버십 전체).
      ktop <- max(1L, as.integer(round(length(tij) * TOP_FRAC)))
      pick <- tij[order(sc, decreasing = TRUE)[seq_len(ktop)]]
      nsel <- nsel + 1L
      sel[[nsel]] <- data.table(Date = s, ti = pick)
      n_out <- n_out + 1L
    }
    dg[[g]] <- sprintf("start %s · IC %d행 · 블록 %d · 산출월 %d",
                       format(pstart), nr, n_blk, n_out)
  }

  if (!nsel) stop("[2210.12462] 선택 0 — 학습창 미충족 또는 컨텍스트 전무")
  S <- rbindlist(sel, use.names = TRUE)
  S <- unique(S, by = c("Date", "ti"))
  S[, Weight := 1 / .N, by = Date]
  out <- S[, .(Date, Ticker = tk_u[ti], Weight, Leg = "long")]

  cat(sprintf("[2210.12462] %s | %s\n",
              paste(sprintf("%s: %s", names(dg), unlist(dg)), collapse = " || "),
              sprintf("hold %s~%s · n/date median=%d",
                      format(min(out$Date)), format(max(out$Date)),
                      as.integer(stats::median(out[, .N, by = Date]$N)))))
  out
})
