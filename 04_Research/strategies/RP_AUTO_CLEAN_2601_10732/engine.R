# =============================================================================
# engine.R — RP_AUTO_CLEAN_2601_10732  (r2 · 재구현)
#
# 논문: Chorok Lee, "Regime-Dependent Predictive Structure Between Equity
#   Factors: Evidence from Granger Causality", arXiv:2601.10732v1 (2026-01-06)
#   ★v1 고정(트리아지가 읽은 판). 같은 arXiv id 의 v2 는 제목·내용이 다른 논문이다.
#
# 거래 규칙(§5.2 · Table 6, 원문): "During Crisis regime, go long SMB when HML
#   return over the past 9 days is positive, short SMB when negative."
#   비위기 국면 = 무포지션(논문은 Crisis 안에서만 거래).
#
# 국면(§3.2): 6계열(MKT-RF·SMB·HML·RMW·CMA·MOM) 일간 수익 벡터에 다변량
#   Student-t HMM(K=3). Crisis = 평균 ‖x‖ 최대 상태(Table 1 = 0.83/1.49/3.33).
#
# ★r1 기각 수정(단일 규모 분할): r1 은 규모 분기점을 `by = .(Date, SORT)` 로
#   잡아 Small/Big 분할이 정렬(BM·OP·INV)마다 갈렸다. §3.1 이 원천으로 지목한
#   Ken French 라이브러리 규약은 형성일당 **단일** 규모 분기점이고, 그래서
#   "SMB (Small Minus Big) is the average return on the nine small stock
#   portfolios minus the average return on the nine big stock portfolios" 가
#   성립한다. r2 는 §3-c 에서 형성일당 분기점을 1개만 산출해(by = Date) 전
#   정렬에 공통 적용한다 — 한 종목의 size 라벨이 그 형성일에 유일해지므로
#   ① 세 정렬 기여 부호가 같고(롱·숏 동시 편입 구조적으로 불가)
#   ② 다리별 Σ|w| = 1 이 정확히 성립한다(§6 의 18칸 완전성 요건 아래).
#
# 산출: PORTFOLIO(Date, Ticker, Weight, Leg) — construction = engine_direct
#   (SMB = 소형 9칸 Σw=+1 · 대형 9칸 Σw=−1 의 스프레드. 숏 다리를 버리면
#    논문 전략이 아니다.)
#
# ★변경·보충·창·상수·팩터 대응의 신고는 FIDELITY.json 이 유일한 통로다.
#   이 주석은 신고가 아니다.
# =============================================================================

suppressWarnings(suppressMessages({
  library(data.table)
}))

# ── 0. 뿌리 · 팩터 DB 연결자(C15 유일 경로) ─────────────────────────────────
.rp_root <- function() {
  cand <- c(Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""),
            if (exists("PROJECT_ROOT", inherits = TRUE)) as.character(get("PROJECT_ROOT", inherits = TRUE)) else "",
            getwd())
  for (p in cand)
    if (nzchar(p) && file.exists(file.path(p, "02_Infrastructure", "config.R"))) return(p)
  cur <- normalizePath(getwd(), winslash = "/", mustWork = FALSE)
  repeat {
    if (file.exists(file.path(cur, "02_Infrastructure", "config.R"))) return(cur)
    up <- dirname(cur); if (identical(up, cur)) break; cur <- up
  }
  stop("[engine] project root not found")
}
if (!exists("load_month_factors", mode = "function"))
  suppressMessages(source(file.path(.rp_root(), "02_Infrastructure", "factor_db", "factor_db_connector.R")))

# ── 1. 상수 (전부 FIDELITY.json::constants 에 신고) ──────────────────────────
.K_REGIMES       <- 3L        # paper §3.2 — BIC 로 K=3
.GC_LAG_DAYS     <- 9L        # paper §5.2 / Table 3 — HML→SMB 9 거래일
.FORM_MONTH      <- 6L        # Fama-French 형성월(6월 말)
.SIZE_BP         <- 0.5       # FF 2x3 — 규모 중위 분할(형성일당 1개 · 전 정렬 공통)
.CHAR_BP_LO      <- 0.3       # FF 2x3 — 특성 30분위
.CHAR_BP_HI      <- 0.7       # FF 2x3 — 특성 70분위
.QTL_TYPE        <- 7L        # 보충 — quantile 보간형(R 기본값을 명시로 고정)
.MOM_WIN_MONTHS  <- 11L       # FF prior (2-12) = 11개월
.MOM_SKIP_MONTHS <- 1L        # FF prior (2-12) = 당월 1개월 건너뜀
.N_BUCKETS       <- 6L        # 2 규모 x 3 특성 — 정렬 성립 요건
.N_LEVELS        <- 3L        # 특성 3분할(30/70)
.N_SMB_CELLS     <- 18L       # 거래일 요건 — 3정렬 x 6버킷 전부 비지 않을 것
.N_SMB_LEG_CELLS <- 9L        # SMB 다리당 칸 수(3정렬 x 3특성) — 칸당 1/9
.MIN_FORM_N      <- 30L       # 보충 — 분기점 모집단 · 정렬 모집단 최소 종목수
.HOLD_MONTHS_ANN <- 12L       # FF — 6월 형성 정렬의 보유 개월(7월~익년 6월)
.HOLD_MONTHS_MOM <- 1L        # FF — 월말 형성 모멘텀 정렬의 보유 개월
.RF_DAILY        <- 0         # 보충 — 무위험 일수익 패널 부재(MKT-RF 의 RF)
.HMM_BURNIN_DAYS <- 1260L     # 보충 — 논문 자료 1990 → 거래 1995(5년)
.HMM_MAX_ITER    <- 200L      # 보충 — EM 반복 상한
.HMM_TOL         <- 1e-5      # 보충 — EM 수렴 허용오차(상대)
.HMM_RIDGE       <- 1e-10     # 보충 — 공분산 특이성 방지 ridge
.HMM_NU_INIT     <- 8         # 보충 — 자유도 초기값
.HMM_NU_LO       <- 2.1       # 보충 — 자유도 하한(2 이하면 분산 비유한)
.HMM_NU_HI       <- 100       # 보충 — 자유도 상한
.HMM_MIN_STATE_W <- 1e-6      # 보충 — 상태 사후질량 하한(미달 = 직전 모수 유지)
.HMM_A_DIAG      <- 0.98      # 보충 — 전이행렬 초기 대각(국면 지속성)
.HMM_CHOL_JITTER <- 1e-6      # 보충 — chol 실패 시 상대 jitter
.HMM_EPS         <- 1e-300    # 보충 — 0 분모 방지 바닥
.FLAT_W          <- 1e-6      # 보충 — 무포지션 표현(하네스가 Weight==0 행을 버린다)
.FLAT_N          <- 2L        # 보충 — 무포지션 토큰 종목수(± 상쇄 쌍)
.LEG_GROSS       <- 1         # FF 스프레드 — 다리별 Σ|w| = 1
.FDB_COV_MIN     <- 0.05      # 보충 — 팩터 DB 커버리지 하한(연결자 기본값을 명시로 고정)
.FDB_HML         <- "V01_BM"            # 팩터 DB — Book-to-Market
.FDB_RMW         <- "Q01_GPA"           # 팩터 DB — Gross Profit to Assets
.FDB_CMA         <- "Q06_Asset_Growth"  # 팩터 DB — Asset Growth(등록부가 부호 정렬)
.SORT_ANN        <- c("HML", "RMW", "CMA")   # 6월 형성 정렬 3종
.SORT_MOM        <- "MOM"                    # 월말 형성 정렬

.sig_from <- if (exists(".RP_START_DATE", inherits = TRUE)) as.Date(get(".RP_START_DATE", inherits = TRUE)) else min(RAWDATA$Date)

# ── 2. 패널 — 위생 유니버스(계약 주입 플래그) · VW 가중 = 전일 시총 ─────────
.dates <- sort(unique(RAWDATA$Date))

.SZ <- RAWDATA[, .(Date, Ticker, Size)]
setkey(.SZ, Ticker, Date)
.SZ[, w_vw := shift(Size, 1L), by = Ticker]      # ME_{t-1} — 당일 시총 사용 금지(t-1)
PX <- merge(RAWDATA[(K200 == 1 | KQ150 == 1) & is.finite(Ret), .(Date, Ticker, Ret)],
            .SZ[is.finite(w_vw) & w_vw > 0, .(Date, Ticker, w_vw)],
            by = c("Date", "Ticker"))
rm(.SZ); invisible(gc(verbose = FALSE))
PX[, mi := year(Date) * 12L + month(Date)]       # 보유월 지수
PX[, wr := w_vw * Ret]
cat(sprintf("[engine] 패널 %d행 · %s~%s · 종목 %d\n", nrow(PX),
            format(min(PX$Date)), format(max(PX$Date)), uniqueN(PX$Ticker)))

# ── 3. 형성 — 2x3 정렬(규모 x 특성) ─────────────────────────────────────────
.ME <- data.table(Date = .dates)[, .(Date = max(Date)), by = .(mi = year(Date) * 12L + month(Date))]
.ME[, mon := month(Date)]
.form_ann <- .ME[mon == .FORM_MONTH, Date]       # 6월 말(그 달 패널 마지막 거래일)
.form_mom <- .ME$Date                            # 매 월말

# 3-a. 특성값 — 6월 형성 3종은 팩터 DB(Z_Score_Aligned 만 · C13/C15)
.fdb_map <- c(.FDB_HML, .FDB_RMW, .FDB_CMA)
names(.fdb_map) <- .SORT_ANN
CH_ANN <- rbindlist(lapply(.form_ann, function(fd) {
  z <- tryCatch(load_month_factors(fd, coverage_min = .FDB_COV_MIN,
                                   factor_names = unname(.fdb_map)), error = function(e) NULL)
  if (is.null(z) || !nrow(z)) return(NULL)
  ad <- attr(z, "factor_db_asof_date")
  if (length(ad) != 1L || is.na(ad) || as.Date(ad) > fd) return(NULL)   # 패널 기준일 > 형성일 = fail-closed
  data.table(Date = fd, Ticker = as.character(z$Ticker),
             SORT = names(.fdb_map)[match(as.character(z$Factor_Name), .fdb_map)],
             CH = as.numeric(z$Z_Score_Aligned))
}), use.names = TRUE, fill = TRUE)
if (nrow(CH_ANN)) CH_ANN <- CH_ANN[!is.na(SORT) & is.finite(CH)]
cat(sprintf("[engine] 6월 형성 특성: 형성일 %d개 · 적재 %d개\n",
            length(.form_ann), if (nrow(CH_ANN)) uniqueN(CH_ANN$Date) else 0L))

# 3-b. 특성값 — 모멘텀은 월수익 11개월 누적(당월 건너뜀 · 가격 원천)
MR <- RAWDATA[is.finite(Ret), .(lr = sum(log1p(Ret))),
              by = .(Ticker, mi = year(Date) * 12L + month(Date))]
GR <- CJ(Ticker = unique(MR$Ticker), mi = seq(min(MR$mi), max(MR$mi)))
GR <- merge(GR, MR, by = c("Ticker", "mi"), all.x = TRUE)
setorder(GR, Ticker, mi)
GR[, cum11 := frollsum(shift(lr, .MOM_SKIP_MONTHS), .MOM_WIN_MONTHS), by = Ticker]
CH_MOM <- GR[is.finite(cum11), .(Ticker, mi, CH = expm1(cum11))]
rm(MR, GR); invisible(gc(verbose = FALSE))

# 3-c. ★규모 분기점 — 형성일당 1개(by = Date) · 전 정렬 공통
#   모집단 = 그 형성일의 위생 유니버스 ∩ finite Size > 0 (정렬·특성 가용성과 무관)
#   원천 규약의 단일 규모 분할을 그대로 복원한다 — 정렬별 분기점 금지.
.SIZE_POP <- RAWDATA[(K200 == 1 | KQ150 == 1) & is.finite(Size) & Size > 0, .(Date, Ticker, Size)]
SZBP <- .SIZE_POP[as.integer(Date) %in% as.integer(.form_mom),
                  .(sz_bp = quantile(Size, .SIZE_BP, names = FALSE, na.rm = TRUE, type = .QTL_TYPE),
                    n_pop = .N), by = Date][n_pop >= .MIN_FORM_N]
cat(sprintf("[engine] 규모 분기점 %d 형성일 · 모집단 %d~%d종목 (형성일당 1개 · 전 정렬 공통)\n",
            nrow(SZBP), if (nrow(SZBP)) min(SZBP$n_pop) else 0L,
            if (nrow(SZBP)) max(SZBP$n_pop) else 0L))

# 3-d. 2x3 버킷 — 공통 규모 분할 x 그 정렬의 특성 30/70
.mem_at  <- function(dts) PX[as.integer(Date) %in% as.integer(dts), .(Date, Ticker)]
.size_at <- function(dts) .SIZE_POP[as.integer(Date) %in% as.integer(dts)]
.sort_23 <- function(F1) {
  .empty <- data.table(Date = as.Date(character(0)), Ticker = character(0),
                       SORT = character(0), grp = character(0))
  if (!nrow(F1)) return(.empty)
  F1 <- merge(F1, SZBP[, .(Date, sz_bp)], by = "Date")   # 공통 분기점 없는 형성일 = 정렬 없음
  if (!nrow(F1)) return(.empty)
  F1[, n_f := .N, by = .(Date, SORT)]
  F1 <- F1[n_f >= .MIN_FORM_N]
  if (!nrow(F1)) return(.empty)
  F1[, sz_hi := Size > sz_bp]                            # ★단일 분할(동점 = S)
  F1[, c_lo := quantile(CH, .CHAR_BP_LO, names = FALSE, na.rm = TRUE, type = .QTL_TYPE), by = .(Date, SORT)]
  F1[, c_hi := quantile(CH, .CHAR_BP_HI, names = FALSE, na.rm = TRUE, type = .QTL_TYPE), by = .(Date, SORT)]
  F1[, lev := 1L + as.integer(CH > c_lo) + as.integer(CH > c_hi)]
  F1[, grp := paste0(ifelse(sz_hi, "B", "S"), lev)]
  F1[, nb := uniqueN(grp), by = .(Date, SORT)]
  F1[nb == .N_BUCKETS, .(Date, Ticker, SORT, grp)]
}

B_ANN <- if (nrow(CH_ANN)) {
  .sort_23(merge(merge(CH_ANN, .size_at(.form_ann), by = c("Date", "Ticker")),
                 .mem_at(.form_ann), by = c("Date", "Ticker")))
} else data.table(Date = as.Date(character(0)), Ticker = character(0), SORT = character(0), grp = character(0))

F_MOM <- merge(.size_at(.form_mom), .mem_at(.form_mom), by = c("Date", "Ticker"))
F_MOM[, mi := year(Date) * 12L + month(Date)]
F_MOM <- merge(F_MOM, CH_MOM, by = c("Ticker", "mi"))
F_MOM[, SORT := .SORT_MOM]
B_MOM <- .sort_23(F_MOM[, .(Date, Ticker, SORT, Size, CH)])

# 3-e. 보유월 전개 — 6월 형성 = 7월~익년 6월 · 월말 형성 = 익월
.expand <- function(B, k) {
  if (!nrow(B)) return(data.table(mi = integer(0), Ticker = character(0), SORT = character(0), grp = character(0)))
  b <- B[, .(Ticker, SORT, grp, mi0 = year(Date) * 12L + month(Date) + 1L)]
  out <- b[rep(seq_len(nrow(b)), each = k)]
  out[, mi := mi0 + rep(seq_len(k) - 1L, times = nrow(b))]
  out[, mi0 := NULL]
  out
}
ASG <- rbind(.expand(B_ANN, .HOLD_MONTHS_ANN), .expand(B_MOM, .HOLD_MONTHS_MOM),
             use.names = TRUE)
cat(sprintf("[engine] 버킷 배정 %d행 · 정렬 %s\n", nrow(ASG), paste(sort(unique(ASG$SORT)), collapse = "/")))

# ── 4. 일간 버킷 VW 수익 → 6계열 ────────────────────────────────────────────
BK <- rbindlist(lapply(sort(unique(ASG$SORT)), function(s) {
  dj <- merge(PX, ASG[SORT == s], by = c("mi", "Ticker"), allow.cartesian = TRUE)
  if (!nrow(dj)) return(NULL)
  out <- dj[, .(r = sum(wr) / sum(w_vw)), by = .(Date, SORT, grp)]
  rm(dj); out
}), use.names = TRUE)
if (!nrow(BK)) BK <- data.table(Date = as.Date(character(0)), SORT = character(0), grp = character(0), r = numeric(0))
BK[, sz := substr(grp, 1L, 1L)]
BK[, lev := as.integer(substr(grp, 2L, 2L))]

# HML·RMW·CMA·MOM = 1/2(S_hi + B_hi) − 1/2(S_lo + B_lo) · SMB = avg(9 small) − avg(9 big)
SPR <- BK[, .(v = mean(r[lev == .N_LEVELS]) - mean(r[lev == 1L]), nb = .N),
          by = .(Date, SORT)][nb == .N_BUCKETS]
SMB <- BK[SORT %in% .SORT_ANN, .(v = mean(r[sz == "S"]) - mean(r[sz == "B"]), nb = .N),
          by = .(Date, SORT)][nb == .N_BUCKETS][, .(SMB = mean(v), k = .N), by = Date][k == length(.SORT_ANN)]
MKT <- PX[, .(MKT = sum(wr) / sum(w_vw) - .RF_DAILY), by = Date]

FS <- if (nrow(SPR)) dcast(SPR[, .(Date, SORT, v)], Date ~ SORT, value.var = "v") else
  data.table(Date = MKT$Date)
FS <- merge(FS, SMB[, .(Date, SMB)], by = "Date", all = TRUE)
FS <- merge(FS, MKT, by = "Date", all = TRUE)
.cols6 <- c("MKT", "SMB", "HML", "RMW", "CMA", "MOM")
for (cc in .cols6) if (!cc %in% names(FS)) FS[, (cc) := NA_real_]
setorder(FS, Date)
FSX <- FS[Reduce(`&`, lapply(.cols6, function(cc) is.finite(FS[[cc]]))), c("Date", .cols6), with = FALSE]
cat(sprintf("[engine] 6계열 완전관측 %d일 · %s~%s\n", nrow(FSX),
            if (nrow(FSX)) format(min(FSX$Date)) else "-", if (nrow(FSX)) format(max(FSX$Date)) else "-"))

# ── 5. 다변량 Student-t HMM — 확장창 재적합 · 필터 상태(평활 금지) ──────────
.mvt_ld <- function(X, mu, S, nu) {
  d <- ncol(X)
  R <- tryCatch(chol(S), error = function(e)
    chol(S + diag(.HMM_CHOL_JITTER * (1 + mean(diag(S))), d)))
  u <- backsolve(R, t(X) - mu, transpose = TRUE)
  dl <- colSums(u * u)
  list(l = lgamma((nu + d) / 2) - lgamma(nu / 2) - (d / 2) * log(nu * pi) -
         sum(log(diag(R))) - ((nu + d) / 2) * log1p(dl / nu), delta = dl)
}

.hmm_fit <- function(X, K) {
  n <- nrow(X); d <- ncol(X)
  nrm <- sqrt(rowSums(X * X))
  g0 <- pmin(K, 1L + (rank(nrm, ties.method = "first") - 1L) %/% ceiling(n / K))
  mu <- matrix(0, K, d); S <- vector("list", K); nu <- rep(.HMM_NU_INIT, K)
  for (k in seq_len(K)) {
    Xi <- X[g0 == k, , drop = FALSE]
    mu[k, ] <- colMeans(Xi)
    S[[k]] <- stats::cov(Xi) + diag(.HMM_RIDGE, d)
  }
  A <- matrix((1 - .HMM_A_DIAG) / (K - 1), K, K); diag(A) <- .HMM_A_DIAG
  pri <- rep(1 / K, K); ll_prev <- -Inf; gm <- NULL; it <- 0L
  for (it in seq_len(.HMM_MAX_ITER)) {
    LB <- matrix(0, n, K); DL <- matrix(0, n, K)
    for (k in seq_len(K)) { e <- .mvt_ld(X, mu[k, ], S[[k]], nu[k]); LB[, k] <- e$l; DL[, k] <- e$delta }
    rmax <- do.call(pmax, lapply(seq_len(K), function(k) LB[, k]))
    B <- exp(LB - rmax)
    al <- matrix(0, n, K); cs <- numeric(n)
    a <- pri * B[1, ]; cs[1] <- sum(a); al[1, ] <- a / cs[1]
    for (t in 2:n) {
      a <- as.vector(al[t - 1L, ] %*% A) * B[t, ]
      cs[t] <- sum(a); al[t, ] <- if (cs[t] > 0) a / cs[t] else as.vector(al[t - 1L, ] %*% A)
    }
    ll <- sum(log(cs[cs > 0])) + sum(rmax)
    be <- matrix(0, n, K); be[n, ] <- 1
    for (t in (n - 1L):1L) be[t, ] <- as.vector(A %*% (B[t + 1L, ] * be[t + 1L, ])) / max(cs[t + 1L], .HMM_EPS)
    gm <- al * be
    gs <- rowSums(gm); gs[gs <= 0] <- 1
    gm <- gm / gs
    M <- B * be / pmax(cs, .HMM_EPS)
    Anum <- A * (t(al[1:(n - 1L), , drop = FALSE]) %*% M[2:n, , drop = FALSE])
    Anum[!is.finite(Anum) | Anum < 0] <- 0
    rs <- rowSums(Anum); rs[rs <= 0] <- 1
    A <- Anum / rs
    pri <- gm[1, ]
    for (k in seq_len(K)) {
      sg <- sum(gm[, k])
      if (!is.finite(sg) || sg < .HMM_MIN_STATE_W) next          # 상태 소멸 = 직전 모수 유지
      uu <- (nu[k] + d) / (nu[k] + DL[, k])
      gu <- gm[, k] * uu
      if (!(sum(gu) > 0)) next
      mu[k, ] <- colSums(gu * X) / sum(gu)
      Xc <- t(t(X) - mu[k, ])
      S[[k]] <- crossprod(Xc * sqrt(gu)) / sg + diag(.HMM_RIDGE, d)
      cst <- sum(gm[, k] * (log(uu) - uu)) / sg
      f <- function(v) log(v / 2) - digamma(v / 2) + 1 + cst + digamma((v + d) / 2) - log((v + d) / 2)
      nu[k] <- tryCatch(stats::uniroot(f, c(.HMM_NU_LO, .HMM_NU_HI))$root, error = function(e) nu[k])
    }
    if (is.finite(ll) && abs(ll - ll_prev) < .HMM_TOL * (1 + abs(ll_prev))) { ll_prev <- ll; break }
    ll_prev <- ll
  }
  mn <- vapply(seq_len(K), function(k) sum(gm[, k] * nrm) / max(sum(gm[, k]), .HMM_EPS), numeric(1))
  list(pri = pri, A = A, mu = mu, S = S, nu = nu, crisis = which.max(mn), iter = it, mean_norm = mn)
}

.hmm_filter <- function(X, fit) {
  n <- nrow(X); K <- length(fit$pri)
  LB <- matrix(0, n, K)
  for (k in seq_len(K)) LB[, k] <- .mvt_ld(X, fit$mu[k, ], fit$S[[k]], fit$nu[k])$l
  rmax <- do.call(pmax, lapply(seq_len(K), function(k) LB[, k]))
  B <- exp(LB - rmax)
  al <- matrix(0, n, K)
  a <- fit$pri * B[1, ]; al[1, ] <- if (sum(a) > 0) a / sum(a) else fit$pri
  for (t in 2:n) {
    pr <- as.vector(al[t - 1L, ] %*% fit$A)
    a <- pr * B[t, ]
    al[t, ] <- if (sum(a) > 0) a / sum(a) else pr
  }
  al
}

X6 <- if (nrow(FSX)) as.matrix(FSX[, .cols6, with = FALSE]) else matrix(0, 0, length(.cols6))
crisis_flag <- rep(NA, nrow(FSX))
if (nrow(X6) > .HMM_BURNIN_DAYS + 1L) {
  i_first <- .HMM_BURNIN_DAYS + 1L
  yr <- year(FSX$Date)
  i_year <- which(!duplicated(yr))
  fit_at <- sort(unique(c(i_first, i_year[i_year > i_first])))
  for (j in seq_along(fit_at)) {
    i0 <- fit_at[j]
    i1 <- if (j < length(fit_at)) fit_at[j + 1L] - 1L else nrow(X6)
    fit <- .hmm_fit(X6[1:(i0 - 1L), , drop = FALSE], .K_REGIMES)
    al <- .hmm_filter(X6[1:i1, , drop = FALSE], fit)
    crisis_flag[i0:i1] <- (max.col(al[i0:i1, , drop = FALSE], ties.method = "first") == fit$crisis)
  }
  cat(sprintf("[engine] HMM 재적합 %d회 · 위기 판정일 %d / %d\n", length(fit_at),
              sum(crisis_flag, na.rm = TRUE), sum(!is.na(crisis_flag))))
} else {
  cat("[engine] ★6계열 관측이 번인에 못 미쳐 국면 미산출 — 신호 0\n")
}

# ── 6. 거래 규칙(§5.2) → PORTFOLIO ──────────────────────────────────────────
SIG <- if (nrow(FSX)) data.table(Date = FSX$Date, crisis = crisis_flag,
                                 h9 = frollsum(FSX$HML, .GC_LAG_DAYS)) else
  data.table(Date = as.Date(character(0)), crisis = logical(0), h9 = numeric(0))
SIG <- SIG[Date >= .sig_from & !is.na(crisis) & is.finite(h9)]
SIG[, pos := 0L]
SIG[crisis & h9 > 0, pos := 1L]
SIG[crisis & h9 < 0, pos := -1L]

.d_act <- SIG[pos != 0L, Date]
.d_flat <- SIG[pos == 0L, Date]

# SMB 스프레드 = 소형 9칸 avg(+1) − 대형 9칸 avg(−1) · 칸 안 VW
#   단일 규모 분할이라 한 종목의 side 는 그 보유월에 유일하다(롱·숏 동시 편입 불가).
POS <- if (length(.d_act)) {
  pp <- merge(PX[as.integer(Date) %in% as.integer(.d_act), .(Date, Ticker, mi, w_vw)],
              ASG[SORT %in% .SORT_ANN], by = c("mi", "Ticker"), allow.cartesian = TRUE)
  pp[, n_cell := uniqueN(paste0(SORT, grp)), by = Date]
  pp <- pp[n_cell == .N_SMB_CELLS]               # 18칸 완전 = 다리별 Σ|w| = 1 성립 요건
  pp[, w_in := w_vw / sum(w_vw), by = .(Date, SORT, grp)]
  pp[, side := ifelse(substr(grp, 1L, 1L) == "S", 1, -1)]
  .n_mix <- pp[, .(ns = uniqueN(side)), by = .(Date, Ticker)][ns > 1L, .N]
  cat(sprintf("[engine] 양다리 동시 편입 종목일 %d (단일 규모 분할이면 0)\n", .n_mix))
  pp[, Weight := side * w_in * .LEG_GROSS / .N_SMB_LEG_CELLS]
  out <- pp[, .(Weight = sum(Weight)), by = .(Date, Ticker)]
  out <- merge(out, SIG[pos != 0L, .(Date, pos)], by = "Date")
  out[, Weight := Weight * pos]
  .lg <- out[, .(gl = sum(Weight[Weight > 0]), gs = -sum(Weight[Weight < 0])), by = Date]
  if (nrow(.lg))
    cat(sprintf("[engine] 다리 총노출 롱 %.4f~%.4f · 숏 %.4f~%.4f (목표 1)\n",
                min(.lg$gl), max(.lg$gl), min(.lg$gs), max(.lg$gs)))
  else
    cat("[engine] ★18칸 요건을 만족한 거래일이 없어 포지션 없음 — 직전 보유 이월\n")
  out[abs(Weight) > 0, .(Date, Ticker, Weight)]
} else data.table(Date = as.Date(character(0)), Ticker = character(0), Weight = numeric(0))

FLAT <- if (length(.d_flat)) {
  fb <- RAWDATA[as.integer(Date) %in% as.integer(.d_flat) & (K200 == 1 | KQ150 == 1) &
                  is.finite(Size) & Size > 0 & is.finite(Vol) & Vol > 0 & is.finite(Ret),
                .(Date, Ticker, Size)]
  setorder(fb, Date, -Size)
  ft <- fb[, .(Ticker = Ticker[seq_len(min(.FLAT_N, .N))],
               rk = seq_len(min(.FLAT_N, .N))), by = Date]
  rbind(ft[rk == 1L, .(Date, Ticker, Weight = .FLAT_W)],
        ft[rk == 2L, .(Date, Ticker, Weight = -.FLAT_W)])
} else data.table(Date = as.Date(character(0)), Ticker = character(0), Weight = numeric(0))

PORTFOLIO <- rbind(POS, FLAT, use.names = TRUE)
PORTFOLIO <- PORTFOLIO[is.finite(Weight) & Weight != 0]
PORTFOLIO[, Leg := ifelse(Weight > 0, "long", "short")]
setorder(PORTFOLIO, Date, Ticker)
PORTFOLIO <- PORTFOLIO[, .(Date, Ticker, Weight, Leg)]

cat(sprintf("[engine] 신호일 %d (롱 %d · 숏 %d · 무포지션 %d) · PORTFOLIO %d행 · %s~%s\n",
            uniqueN(SIG$Date), SIG[pos == 1L, .N], SIG[pos == -1L, .N], length(.d_flat),
            nrow(PORTFOLIO),
            if (nrow(PORTFOLIO)) format(min(PORTFOLIO$Date)) else "-",
            if (nrow(PORTFOLIO)) format(max(PORTFOLIO$Date)) else "-"))
