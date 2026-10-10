# =============================================================================
# E2EAI — End-to-End Deep Learning Framework for Active Investing
#   arXiv:2305.16364 (§4.1 factor selection gate · §4.2 deep multifactor model
#   + relational neutralization · §4.3 directional buffer + automatic stock
#   selection · §4.4 L_ret + L_up portfolio loss)
#
#   fidelity = adapted.  무엇을 남기고 무엇을 바꿨는지의 정본 신고는
#   같은 디렉터리의 FIDELITY.json 이다 (이 주석이 아니다).
#
#   산출: PORTFOLIO(Date, Ticker, Weight, Leg) — 논문 §4.3 이 만든 비중 그대로
#   입력: 호출자 환경의 RAWDATA / BM_DT
#
#   PIT 구조 보장 (정적 검출기 통과를 근거로 삼지 않는다):
#     * 특징 = load_month_factors(월말 t) 의 Z_Score_Aligned (C15·C13 경유).
#       반환 패널의 as-of 가 t 와 같은 달이고 t 이하일 때만 쓴다(그 밖은 그 달 생략).
#     * 표적 = (P[t+k] - P[t+1]) / P[t+1] (거래일 기준). 학습창에 들어가는 월은
#       **최대 지평의 청산일 <= t** 인 월만이다 — 지평별 분기 없이 한 창.
#     * 전 표본 통계 0. 월 단위 횡단면 연산(표준화·업종평균·softmax)만 쓴다.
#     * 학습 파라미터는 매 신호일 t 의 학습창에서만 갱신된다(warm start = 과거 파라미터).
#
#   ★앞 판 수정(§2 유니버스·업종 그래프 입력): 월말 멤버 + 업종 라벨 한 장을
#     만드는 대목이 data.table 의 `..` 전달 idiom 으로 쓰여 호출 스코프 조회에
#     실패했다(엔진 실행 중단). 그 대목이 구현하려던 것은 §4.2 의 두 그래프
#     (G_I = 같은 업종 · G_U = 그 달 유니버스) 입력이므로, 전달 idiom 없이 열을
#     직접 세워 만든다 — 모형·축·논문 해석은 앞 판과 동일하다.
# =============================================================================

suppressWarnings(suppressMessages(library(data.table)))

# ---- 상수 — 전부 FIDELITY.json::constants 에 신고된다 ------------------------
KH            <- c(3L, 5L, 10L, 15L, 20L)   # paper §4.2 k-forward trading days
H_DIM         <- 8L                         # encoder hidden width (supplement)
THETA         <- 0.10                       # paper §4.4 allocation upper bound
N_AXIS        <- 25L                        # 고정 축 — 보유 종목수
LEAKY_A       <- 0.01                       # LeakyReLU slope (supplement)
LR            <- 0.05                       # RMS-normalized step size (supplement)
N_EPOCH_FIRST <- 200L                       # 최초 적합 epoch (supplement)
N_EPOCH_WARM  <- 5L                         # warm start epoch (supplement)
SEED          <- 16364L                     # init seed (supplement)
INIT_SD       <- 0.10                       # init sd (supplement)
NORM_CAP      <- 10.0                       # parameter Frobenius norm cap (supplement)
Z_CLIP        <- 5.0                        # factor z clip (supplement)
E_CLIP        <- 20.0                       # pre-softmax clamp (supplement)
EPS           <- 1e-8                       # denominator guard (supplement)
MIN_FAC_KEEP  <- 10L                        # gate floor (supplement)
MIN_STOCKS    <- 30L                        # 월 최소 횡단면 (supplement)
MIN_FIN       <- 2L                         # 표준화 최소 관측수 (supplement)
MIN_TRAIN_M   <- 36L                        # 최소 학습 월수 (supplement)
COV_MIN       <- 0.05                       # connector coverage 기본값 (harness)
N_PER_FAM     <- 3L                         # 군별 풀 상한 (supplement)
POOL_MAX      <- 21L                        # 풀 총 상한 (supplement)
START_LOAD_D  <- "2000-01-01"               # 학습용 적재 시작 (supplement)
EMIT_START_D  <- "2005-01-01"               # 측정 시작 = 축

# ---- 인프라 경로 + 팩터 DB 관문 (C15 유일 경로) -----------------------------
.E2E_ROOT <- local({
  ok <- function(p) nzchar(p) && !is.na(p) && dir.exists(p) &&
    file.exists(file.path(p, "02_Infrastructure", "factor_db", "factor_db_connector.R"))
  cand <- c(Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""),
            if (exists("PROJECT_ROOT", inherits = TRUE)) as.character(get("PROJECT_ROOT", inherits = TRUE))[1] else "",
            getwd())
  for (p in cand) if (ok(p)) return(p)
  cur <- getwd()
  repeat {
    if (ok(cur)) return(cur)
    par <- dirname(cur)
    if (identical(par, cur)) break
    cur <- par
  }
  stop("[E2EAI] project root not found (factor_db_connector.R)")
})
if (!exists("load_month_factors", mode = "function")) {
  suppressWarnings(suppressMessages(
    source(file.path(.E2E_ROOT, "02_Infrastructure", "factor_db", "factor_db_connector.R"))))
}

# ---- 도우미 ------------------------------------------------------------------
# 그룹별 열평균 (rowsum = C 수준 그룹합). gi 는 1..G 연속 정수, gc 는 그룹 크기.
.gmean <- function(M, gi, gc) {
  s <- rowsum(M, gi, reorder = TRUE)
  s / gc
}
# 블록 대각 구조 — 월(또는 월×업종) 안에서만 평균을 뺀다. 시계열 통계 아님.
.demean <- function(M, gi, gc) M - .gmean(M, gi, gc)[gi, , drop = FALSE]

# 파라미터 블록 노름 상한 (softmax 과집중·발산 수치 방어)
.capn <- function(M, cap) {
  nn <- sqrt(sum(M * M))
  if (is.finite(nn) && nn > cap) M * (cap / nn) else M
}
# RMS 정규화 스텝 — 원소 업데이트 RMS = LR 로 묶인다(발산 불가).
.stepn <- function(prm, gr, lr) {
  r <- sqrt(mean(gr * gr))
  if (!is.finite(r) || r < EPS) return(prm)
  prm - lr * gr / r
}

# =============================================================================
# 1. 거래일 격자 · 월말 · 유니버스 · 가격 행렬
# =============================================================================
# 호출자 객체를 참조로 고쳐 쓰지 않는다 — 형 보정이 필요할 때만 사본을 만든다.
RD <- RAWDATA
if (!inherits(RD$Date, "Date")) RD <- copy(RD)[, Date := as.Date(Date)]
if (!all(c("K200", "KQ150") %in% names(RD)))
  stop("[E2EAI] RAWDATA 에 K200/KQ150 멤버십 열이 없다 — 유니버스 결합 불가")
# §4.2 의 업종 그래프는 업종 분류가 있어야 성립한다(논문 CITIC 분류 자리).
# 라벨이 없으면 C_U 블록이 항등 0 이 되어 심층팩터 입력 1/3 이 죽는다 — fail-closed.
if (!("Sector" %in% names(RD)))
  stop("[E2EAI] RAWDATA 에 Sector 열이 없다 — 논문 §4.2 업종 그래프 구성 불가(fail-closed)")

ALLD <- sort(unique(RD$Date))
nD   <- length(ALLD)
mtag <- format(ALLD, "%Y%m")
MEI  <- which(!duplicated(mtag, fromLast = TRUE))          # 각 월의 마지막 거래일
MEI  <- MEI[ALLD[MEI] >= as.Date(START_LOAD_D)]
if (!length(MEI)) stop("[E2EAI] 월말 거래일 격자 구성 실패")

KMAX  <- max(KH)
# 가격 조회용 종목 집합(상위집합) — 선택은 날짜별 UNI 가 하므로 선별 효과 없다.
uni_tk <- unique(RD[K200 == TRUE | KQ150 == TRUE, Ticker])
if (!length(uni_tk)) stop("[E2EAI] K200/KQ150 멤버 종목 0")

# 필요한 날짜만: 월말(유니버스·업종) + 진입일(t+1) + 청산일(t+k)
.pi <- unique(c(MEI + 1L, as.vector(outer(MEI, KH, "+"))))
.pi <- .pi[.pi >= 1L & .pi <= nD]
PXD <- ALLD[sort(unique(.pi))]
MED <- ALLD[MEI]

PX  <- RD[Date %in% PXD & Ticker %in% uni_tk, .(Date, Ticker, Close)]
if (!nrow(PX)) stop("[E2EAI] 진입·청산일 가격 0행 — 표적 구성 불가")
# (Date,Ticker) 중복이 남으면 dcast 가 조용히 fun.aggregate=length 로 돌아
# 가격 대신 개수를 깔아버린다 — 침묵 실패를 막는 선제 축약.
PX  <- unique(PX, by = c("Date", "Ticker"))
PXW <- dcast(PX, Ticker ~ Date, value.var = "Close")
PXM <- as.matrix(PXW[, setdiff(names(PXW), "Ticker"), with = FALSE])
rownames(PXM) <- PXW$Ticker
rm(PX, PXW)

# §4.2 relational neutralization 의 두 그래프 입력:
#   G_I = 같은 업종(논문 CITIC 분류 자리 → RAWDATA$Sector)
#   G_U = 그 달 유니버스 전체(cross-industry)
# 월말 신호일마다 (멤버 종목, 업종 라벨) 한 장. 유니버스 = K200 합집합 KQ150(치환).
UNI <- RD[Date %in% MED & (K200 == TRUE | KQ150 == TRUE),
          .(Date, Ticker, Sector = as.character(Sector))]
if (!nrow(UNI)) stop("[E2EAI] 월말 유니버스 0행 — 멤버십 열 확인")
UNI[is.na(Sector) | !nzchar(Sector), Sector := "UNKNOWN"]
UNI <- unique(UNI, by = c("Date", "Ticker"))
setkey(UNI, Date)
PXC <- colnames(PXM)
cat(sprintf("[E2EAI] universe rows %d | tickers %d | sectors %d | month-ends %d\n",
            nrow(UNI), uniqueN(UNI$Ticker), uniqueN(UNI$Sector), length(MEI)))

# =============================================================================
# 2. 팩터 풀 — 논문 7군(§5) ↔ 인프라 경제계열 7군. 풀 기준일 = 첫 측정 월말.
#    선정 통계 = 그 달 패널의 커버리지(종목 수)뿐 — 수익 정보 미사용. 이후 고정.
# =============================================================================
.fam_map <- function() {
  g <- tryCatch(group_factors_by_family(dedup = TRUE), error = function(e) NULL)
  if (is.null(g) || !length(g))
    g <- tryCatch(group_factors_by_family(dedup = FALSE), error = function(e) NULL)
  if (!is.null(g) && length(g)) return(g)
  # 폴백 — 연결자 계열 함수가 라벨 결측에서 깨지면 등록부 category 로 직접 묶는다.
  reg <- if (exists(".load_registry", mode = "function"))
    tryCatch(.load_registry(), error = function(e) NULL) else NULL
  if (is.null(reg) || !length(reg)) return(list())
  cof <- vapply(reg, function(x) {
    v <- x$category
    if (is.null(v) || !length(v)) NA_character_ else as.character(v)[1]
  }, character(1))
  nm <- names(reg)
  keep <- !is.na(cof) & nzchar(nm)
  if (!any(keep)) return(list())
  split(nm[keep], cof[keep])
}
FAM <- .fam_map()
if (!length(FAM)) stop("[E2EAI] 팩터 등록부 계열 지도 적재 실패 — 풀 구성 불가(fail-closed)")
FAM_DT <- rbindlist(lapply(names(FAM), function(g)
  data.table(Factor_Name = as.character(FAM[[g]]), fam = g)), use.names = TRUE)
FAM_DT <- unique(FAM_DT, by = "Factor_Name")
FAM_ALL <- FAM_DT$Factor_Name

.load_panel <- function(adate, want) {
  pan <- tryCatch(load_month_factors(sig_date = adate, coverage_min = COV_MIN,
                                     factor_names = want, dedup = FALSE),
                  error = function(e) NULL)
  if (is.null(pan) || !nrow(pan)) return(NULL)
  af <- attr(pan, "factor_db_asof_date")
  # as-of 방어: 요청월과 다른 달의 파일이 대체 적재됐거나 as-of 가 t 를 넘으면 그 달은 버린다.
  if (is.na(af) || af > adate || !identical(format(af, "%Y%m"), format(adate, "%Y%m"))) return(NULL)
  pan <- pan[is.finite(Z_Score_Aligned)]
  if (!nrow(pan)) return(NULL)
  pan
}

PANCH <- MED[MED >= as.Date(EMIT_START_D)]
if (!length(PANCH)) stop("[E2EAI] 측정 시작 이후 월말이 없다")
PANCH <- PANCH[1L]
.p0 <- .load_panel(PANCH, FAM_ALL)
if (is.null(.p0)) stop("[E2EAI] 풀 기준일 패널 적재 실패 — 풀 확정 불가(fail-closed)")
.u0 <- UNI[.(PANCH), Ticker, nomatch = NULL]
.p0 <- .p0[Ticker %in% .u0]
.cv <- .p0[, .(cov_n = .N), by = Factor_Name]
.cv <- merge(.cv, FAM_DT, by = "Factor_Name")
setorder(.cv, fam, -cov_n, Factor_Name)
POOL <- .cv[, head(Factor_Name, N_PER_FAM), by = fam]$V1
if (length(POOL) > POOL_MAX) {
  .cv2 <- .cv[Factor_Name %in% POOL]
  setorder(.cv2, -cov_n, Factor_Name)
  POOL <- head(.cv2$Factor_Name, POOL_MAX)
  rm(.cv2)
}
POOL <- sort(unique(POOL))
if (length(POOL) < MIN_FAC_KEEP)
  stop(sprintf("[E2EAI] 팩터 풀 %d종 — 하한 %d 미달(fail-closed)", length(POOL), MIN_FAC_KEEP))
M_DIM <- length(POOL)
GAMMA_F <- 1 / M_DIM                    # paper §4.1 threshold: 균일 attention 수준
rm(.p0, .u0, .cv)
cat(sprintf("[E2EAI] factor pool = %d (anchor %s) | %s\n",
            M_DIM, format(PANCH), paste(POOL, collapse = ",")))

# =============================================================================
# 3. 월별 패널 — 특징(X: 월 횡단면 표준화 = BatchNorm 등가) + 표적(Y: k거래일)
# =============================================================================
.build_month <- function(j) {
  ti    <- MEI[j]
  adate <- ALLD[ti]
  ur    <- UNI[.(adate), nomatch = NULL]
  if (nrow(ur) < MIN_STOCKS) return(NULL)
  pan <- .load_panel(adate, POOL)
  if (is.null(pan)) return(NULL)
  pan <- pan[Ticker %in% ur$Ticker]
  if (!nrow(pan)) return(NULL)
  pan <- unique(pan, by = c("Ticker", "Factor_Name"))
  w  <- dcast(pan, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")
  tk <- w$Ticker
  n  <- length(tk)
  if (n < MIN_STOCKS) return(NULL)
  cmn <- intersect(POOL, names(w))
  if (!length(cmn)) return(NULL)
  # 결측은 **표준화 뒤에** 0(= 그 달 횡단면 평균)으로 채운다 — 채운 뒤 표준화하면
  # 대체값이 평균이 아니라 -mu/sd 로 밀려 결측 종목에 인공 신호가 생긴다.
  X <- matrix(NA_real_, nrow = n, ncol = M_DIM, dimnames = list(tk, POOL))
  X[, cmn] <- as.matrix(w[, cmn, with = FALSE])
  X[!is.finite(X)] <- NA_real_
  for (cc in seq_len(M_DIM)) {
    v  <- X[, cc]
    fi <- !is.na(v)
    if (sum(fi) < MIN_FIN) { X[, cc] <- 0.0; next }
    mm <- mean(v[fi])
    ss <- sqrt(mean((v[fi] - mm)^2))
    if (!is.finite(ss) || ss < EPS) { X[, cc] <- 0.0; next }
    X[, cc] <- (v - mm) / ss
  }
  X[!is.finite(X)] <- 0.0
  X[X >  Z_CLIP] <-  Z_CLIP
  X[X < -Z_CLIP] <- -Z_CLIP
  # 업종 그룹 (relational neutralization 의 industry 이웃)
  sec <- ur$Sector[match(tk, ur$Ticker)]
  sec[is.na(sec)] <- "UNKNOWN"
  # 표적: (P[t+k] - P[t+1]) / P[t+1] — 거래일 격자
  Y <- matrix(NA_real_, nrow = n, ncol = length(KH))
  exit_d <- as.Date(NA)
  if (ti + KMAX <= nD) {
    dn <- as.character(ALLD[c(ti + 1L, ti + KH)])
    if (all(dn %in% PXC)) {
      ri <- match(tk, rownames(PXM))
      ce <- PXM[ri, dn[1L]]
      for (kk in seq_along(KH)) Y[, kk] <- PXM[ri, dn[kk + 1L]] / ce - 1.0
      Y[!is.finite(Y)] <- NA_real_
      exit_d <- ALLD[ti + KMAX]
    }
  }
  list(adate = adate, tick = tk, X = X, sec = sec, Y = Y,
       cmp = stats::complete.cases(Y), exit_d = exit_d)
}

# =============================================================================
# 4. 학습 상태(expanding) — 월이 "최대 지평 청산 완료" 가 되는 순간에만 적재된다
# =============================================================================
STK <- list(X = matrix(0.0, 0L, M_DIM), Y = matrix(0.0, 0L, length(KH)),
            mi = integer(0), si = integer(0), mc = integer(0), sc = integer(0),
            ms = integer(0), me = integer(0), G = 0L, S = 0L)

.stk_append <- function(S, mo) {
  keep <- mo$cmp
  if (sum(keep) < MIN_STOCKS) return(S)
  Xa <- mo$X[keep, , drop = FALSE]
  dimnames(Xa) <- NULL
  Ya <- mo$Y[keep, , drop = FALSE]
  # 월 횡단면 평균 제거 — Sum(w)=1 이라 수익 기울기는 불변이고(상수항 소거),
  # 월 간 규모 차이만 사라진다(목적함수 추적 안정화).
  Ya <- Ya - rep(colMeans(Ya), each = nrow(Ya))
  n  <- nrow(Xa)
  g  <- S$G + 1L
  sj <- as.integer(factor(mo$sec[keep]))
  nsg <- max(sj)
  S$X  <- rbind(S$X, Xa)
  S$Y  <- rbind(S$Y, Ya)
  S$mi <- c(S$mi, rep.int(g, n))
  S$si <- c(S$si, S$S + sj)
  S$mc <- c(S$mc, n)
  S$sc <- c(S$sc, as.integer(tabulate(sj, nbins = nsg)))
  S$ms <- c(S$ms, nrow(S$X) - n + 1L)
  S$me <- c(S$me, nrow(S$X))
  S$G  <- g
  S$S  <- S$S + nsg
  S
}

.stk_one <- function(mo) {
  n  <- nrow(mo$X)
  sj <- as.integer(factor(mo$sec))
  list(X = mo$X, Y = matrix(0.0, n, length(KH)),
       mi = rep.int(1L, n), si = sj, mc = n,
       sc = as.integer(tabulate(sj, nbins = max(sj))),
       ms = 1L, me = n, G = 1L, S = max(sj))
}

# =============================================================================
# 5. 모형 — 순전파/역전파 (논문 §4.1~§4.4)
#    gate -> encoder -> industry/universe neutralization -> K deep factor heads
#    -> directional buffer -> automatic stock selection -> softmax weights
# =============================================================================
KN <- length(KH)

.par_init <- function() {
  set.seed(SEED)
  list(u  = rep(0.0, M_DIM),
       W1 = matrix(stats::rnorm(M_DIM * H_DIM, 0, INIT_SD), M_DIM, H_DIM),
       b1 = rep(0.0, H_DIM),
       V  = matrix(stats::rnorm(3L * H_DIM * KN, 0, INIT_SD), 3L * H_DIM, KN),
       p  = stats::rnorm(H_DIM + 1L, 0, INIT_SD),
       bp = 0.0)
}

.gate <- function(u) {
  e <- exp(u - max(u))
  a <- e / sum(e)
  msk <- a >= GAMMA_F
  if (sum(msk) < MIN_FAC_KEEP) {
    thr <- -sort(-a, partial = min(MIN_FAC_KEEP, length(a)))[min(MIN_FAC_KEEP, length(a))]
    msk <- a >= thr
  }
  gh <- a * msk
  s  <- sum(gh)
  ns <- sum(msk)
  g  <- if (s > EPS) gh * (ns / s) else as.numeric(msk)
  list(a = a, msk = msk, gh = gh, s = s, ns = ns, g = g)
}

.fb <- function(PAR, S, dbuf, grad) {
  n <- nrow(S$X); h <- H_DIM
  gt <- .gate(PAR$u)
  Xg <- S$X * rep(gt$g, each = n)
  Z1 <- Xg %*% PAR$W1 + rep(PAR$b1, each = n)
  C0 <- tanh(Z1)
  CI <- .demean(C0, S$si, S$sc)                 # industry neutralization
  CU <- .demean(CI, S$mi, S$mc)                 # cross-industry(universe) neutralization
  HC <- cbind(C0, CI, CU)
  ZF <- HC %*% PAR$V
  nf <- ZF < 0
  F0 <- ZF; F0[nf] <- ZF[nf] * LEAKY_A          # deep factors (K heads)

  bse  <- as.numeric(C0 %*% PAR$p[1:h]) + PAR$bp
  FD   <- F0 * rep(dbuf, each = n)              # directed deep factors
  Epre <- FD * PAR$p[h + 1L] + bse
  clp  <- (Epre > E_CLIP) | (Epre < -E_CLIP)
  Ecl  <- Epre; Ecl[Epre >  E_CLIP] <-  E_CLIP; Ecl[Epre < -E_CLIP] <- -E_CLIP
  np   <- Ecl < 0
  ZP   <- Ecl; ZP[np] <- Ecl[np] * LEAKY_A

  Wt <- matrix(0.0, n, KN)
  for (k in seq_len(KN)) {
    z <- ZP[, k]
    kp <- logical(n)
    for (g in seq_len(S$G)) {
      ii <- S$ms[g]:S$me[g]
      zz <- z[ii]
      nn <- length(zz)
      if (nn <= N_AXIS) {
        kp[ii] <- TRUE
      } else {
        thr <- -sort(-zz, partial = N_AXIS)[N_AXIS]
        sel <- zz >= thr
        if (sum(sel) > N_AXIS) {                # 동점 초과분 결정적 절단
          o <- order(-zz, ii)
          sel <- logical(nn); sel[o[seq_len(N_AXIS)]] <- TRUE
        }
        kp[ii] <- sel
      }
    }
    ex <- exp(z); ex[!kp] <- 0.0
    den <- as.numeric(rowsum(cbind(ex), S$mi, reorder = TRUE))
    Wt[, k] <- ex / pmax(den[S$mi], EPS)
  }

  obj <- (sum(Wt * (-S$Y)) + sum(pmax(Wt - THETA, 0.0))) / (S$G * KN)
  out <- list(obj = obj, Wt = Wt, F0 = F0)
  if (!isTRUE(grad)) return(out)

  q    <- (-S$Y + (Wt > THETA)) / (S$G * KN)
  sqw  <- rowsum(q * Wt, S$mi, reorder = TRUE)
  gZP  <- Wt * (q - sqw[S$mi, , drop = FALSE])
  dl   <- matrix(1.0, n, KN); dl[np] <- LEAKY_A; dl[clp] <- 0.0
  gE   <- gZP * dl

  gp_f  <- sum(gE * FD)
  gbse  <- rowSums(gE)
  gp_h  <- as.numeric(t(C0) %*% gbse)
  gbp   <- sum(gbse)

  gF0 <- gE * PAR$p[h + 1L] * rep(dbuf, each = n)
  dlf <- matrix(1.0, n, KN); dlf[nf] <- LEAKY_A
  gZF <- gF0 * dlf
  gV  <- t(HC) %*% gZF
  gHC <- gZF %*% t(PAR$V)

  gC  <- gHC[, 1:h, drop = FALSE] + outer(gbse, PAR$p[1:h])
  gCI <- gHC[, (h + 1L):(2L * h), drop = FALSE]
  gCU <- gHC[, (2L * h + 1L):(3L * h), drop = FALSE]
  gCI <- gCI + .demean(gCU, S$mi, S$mc)         # CU = CI - mean_month(CI)
  gC  <- gC  + .demean(gCI, S$si, S$sc)         # CI = C0 - mean_industry(C0)

  gZ1 <- gC * (1.0 - C0 * C0)
  gW1 <- t(Xg) %*% gZ1
  gb1 <- colSums(gZ1)
  gXg <- gZ1 %*% t(PAR$W1)
  ggv <- colSums(S$X * gXg)

  sden  <- max(gt$s, EPS)
  dghat <- (gt$ns / sden) * (ggv - sum(ggv * gt$gh) / sden)
  da    <- dghat * gt$msk
  gu    <- gt$a * (da - sum(gt$a * da))

  out$gr <- list(u = gu, W1 = gW1, b1 = gb1, V = gV,
                 p = c(gp_h, gp_f), bp = gbp)
  out
}

.dirbuf <- function(PAR, S, dbuf) {
  f <- .fb(PAR, S, dbuf, FALSE)$F0
  fc <- .demean(f, S$mi, S$mc)
  yc <- .demean(S$Y, S$mi, S$mc)
  nu <- rowsum(fc * yc, S$mi, reorder = TRUE)
  d1 <- rowsum(fc * fc, S$mi, reorder = TRUE)
  d2 <- rowsum(yc * yc, S$mi, reorder = TRUE)
  cm <- nu / sqrt(pmax(d1 * d2, EPS))
  cm[!is.finite(cm)] <- 0.0
  d <- sign(colSums(cm))
  d[d == 0] <- 1.0
  as.numeric(d)
}

.train <- function(PAR, S, dbuf, nep) {
  kept_par <- PAR
  kept_obj <- Inf
  for (it in seq_len(nep)) {
    r <- .fb(PAR, S, dbuf, TRUE)
    if (!is.finite(r$obj)) break
    if (r$obj < kept_obj) { kept_obj <- r$obj; kept_par <- PAR }
    g <- r$gr
    if (!all(vapply(g, function(z) all(is.finite(z)), logical(1)))) break
    PAR$u  <- .stepn(PAR$u,  g$u,  LR)
    PAR$W1 <- .capn(.stepn(PAR$W1, g$W1, LR), NORM_CAP)
    PAR$b1 <- .capn(.stepn(PAR$b1, g$b1, LR), NORM_CAP)
    PAR$V  <- .capn(.stepn(PAR$V,  g$V,  LR), NORM_CAP)
    PAR$p  <- .capn(.stepn(PAR$p,  g$p,  LR), NORM_CAP)
    PAR$bp <- .capn(.stepn(PAR$bp, g$bp, LR), NORM_CAP)
    PAR$u  <- .capn(PAR$u, NORM_CAP)
  }
  rf <- .fb(PAR, S, dbuf, FALSE)
  if (is.finite(rf$obj) && rf$obj < kept_obj) { kept_obj <- rf$obj; kept_par <- PAR }
  kept_par
}

# =============================================================================
# 6. 메인 루프 — 월말마다: 패널 적재 -> (적격이면) 학습 -> 비중 산출
# =============================================================================
PAR  <- NULL
DBUF <- rep(1.0, KN)
PEND <- list()
OUTL <- list()
EMIT_D <- as.Date(EMIT_START_D)

# 청산일이 확정된 달만 대기열에 둔다 — 최대 지평이 데이터 끝을 넘거나 진입·청산일
# 가격 열이 없으면 그 달은 영구히 성숙할 수 없어 대기열에 쌓아두지 않는다.
.park <- function(P, mo) {
  if (is.null(mo) || is.na(mo$exit_d)) return(P)
  P[[length(P) + 1L]] <- mo
  P
}
# 최대 지평 청산이 t 이하로 끝난 월만 학습창에 넣는다 (지평별 분기 없음).
# 대기열과 학습창을 둘 다 돌려준다 — 바깥 변수를 비지역 대입으로 고치지 않는다.
.mature <- function(P, S, adate) {
  if (!length(P)) return(list(P = P, S = S))
  kp <- logical(length(P))
  for (i in seq_along(P)) {
    if (P[[i]]$exit_d <= adate) S <- .stk_append(S, P[[i]]) else kp[i] <- TRUE
  }
  list(P = P[kp], S = S)
}

for (j in seq_along(MEI)) {
  adate <- ALLD[MEI[j]]
  mo <- tryCatch(.build_month(j), error = function(e) NULL)
  PEND <- .park(PEND, mo)
  .mt  <- .mature(PEND, STK, adate)
  PEND <- .mt$P
  STK  <- .mt$S

  # 적재 전 구간이거나 그 달 패널이 없다 — 산출 없음(하네스가 직전 보유 이월).
  if (adate < EMIT_D || is.null(mo)) next
  if (STK$G < MIN_TRAIN_M) next

  first <- is.null(PAR)
  if (first) PAR <- .par_init()
  DBUF <- .dirbuf(PAR, STK, DBUF)
  PAR  <- .train(PAR, STK, DBUF, if (first) N_EPOCH_FIRST else N_EPOCH_WARM)

  pr <- tryCatch(.fb(PAR, .stk_one(mo), DBUF, FALSE), error = function(e) NULL)
  if (is.null(pr)) next
  wv <- rowMeans(pr$Wt)                          # K 지평 포트폴리오 결합(등가중)
  wv[!is.finite(wv) | wv < 0] <- 0.0
  if (sum(wv) <= EPS) next
  nn <- min(N_AXIS, length(wv))
  o  <- order(-wv, seq_along(wv))
  sel <- o[seq_len(nn)]
  wv <- wv[sel]
  if (sum(wv) <= EPS) next
  OUTL[[length(OUTL) + 1L]] <- data.table(
    Date = adate, Ticker = mo$tick[sel], Weight = wv / sum(wv), Leg = "long")
}

PORTFOLIO <- if (length(OUTL)) rbindlist(OUTL, use.names = TRUE) else
  data.table(Date = as.Date(character(0)), Ticker = character(0),
             Weight = numeric(0), Leg = character(0))
PORTFOLIO <- PORTFOLIO[is.finite(Weight) & Weight > 0]
setorder(PORTFOLIO, Date, -Weight)
if (!nrow(PORTFOLIO))
  stop(sprintf(paste0("[E2EAI] 적격 신호월 0 — PORTFOLIO 공백(fail-closed). ",
                      "학습 적재월 %d(하한 %d) · 팩터 풀 %d · 월말 %d. ",
                      "팩터 DB 월 파일 as-of 불일치 또는 학습창 하한 미충족을 보라."),
               STK$G, MIN_TRAIN_M, M_DIM, length(MEI)))
cat(sprintf("[E2EAI] PORTFOLIO %d rows | %d dates | n/date %.0f~%.0f | %s~%s | train months %d\n",
            nrow(PORTFOLIO), uniqueN(PORTFOLIO$Date),
            min(PORTFOLIO[, .N, by = Date]$N), max(PORTFOLIO[, .N, by = Date]$N),
            format(min(PORTFOLIO$Date)), format(max(PORTFOLIO$Date)), STK$G))
