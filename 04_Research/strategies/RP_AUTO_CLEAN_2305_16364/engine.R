# =============================================================================
# E2EAI — End-to-End Deep Learning Framework for Active Investing
#   arXiv:2305.16364v1
#     §4.1 팩터선택 게이트      Eq (1) M_f^t = 1_{>=γ_f}(softmax(MLP(F_o^t))) · Eq (2)
#     §4.2 컨텍스트 인코더      Eq (3) C_t = MLP(BatchNorm(F_t))
#          관계중성화 블록      Eq (4)(5) C̄_I = C − GAT(C;G_I) · C̄_U = RNB(C̄_I;G_U)
#          K 지평 심층팩터      Eq (6) f_k = LeakyReLU(W_[k]^T(C ‖ C̄_I ‖ C̄_U)), k=3,5,10,15,20
#     §4.3 directional buffer   Algo 1 line 7  d_f = sgn(b_f), b_f ← 1e-6 + Σ IC(r,f)
#          자동 종목선택        Eq (9) A_p,k = softmax(LeakyReLU(W_a,k^T(C ‖ (f_k∘d_f,k))))
#                               Eq (10) W_k  = softmax(1_{>=γ_p}(A_p,k))      ← softmax 2단
#     §4.4 손실                 L_p = L_ret + L_up, θ = 0.10
#
#   fidelity = adapted. 무엇을 남기고 무엇을 바꿨는지의 정본 신고는
#   같은 디렉터리의 FIDELITY.json 이다 (이 주석이 아니다).
#
#   산출: PORTFOLIO(Date, Ticker, Weight, Leg) — 논문 Eq (10) 이 낸 비중 그대로
#   입력: 호출자 환경의 RAWDATA / BM_DT
#
#   PIT 구조 보장 (정적 검출기 통과를 근거로 삼지 않는다):
#     * 특징 = load_month_factors(월말 t) 의 Z_Score_Aligned (C15·C13 경유).
#       반환 패널의 as-of 가 t 와 같은 달이고 t 이하일 때만 쓴다(그 밖은 그 달 생략).
#     * 표적 = (P[t+k] − P[t+1]) / P[t+1] (거래일 격자). 학습창에 들어가는 월은
#       **최대 지평의 청산일 <= t** 인 월만이다 — 지평별 분기 없이 한 창.
#     * 전 표본 통계 0. 월 단위 횡단면 연산(표준화·업종평균·softmax)만 쓴다.
#     * 학습 파라미터·directional buffer 는 매 신호일 t 의 학습창에서만 갱신된다.
#
#   ★앞 판(engine.rejected1.R) 대비 되돌린 지점 — 전부 논문 원문 방향:
#     (a) Eq (1) 게이트가 F_o^t 를 **읽는다**(앞 판은 자유 로짓만 — §4.1 이 기각한
#         static selection 이었다). 종목축 치환불변 풀링 MLP.
#     (b) Eq (9)+(10) **softmax 2단** 복원(앞 판은 로짓 1단). 임계 γ_p 는 Eq (10)
#         정의역대로 확률 A 에 건다(앞 판은 비정규화 로짓 순위).
#     (c) Eq (9) W_a,k 는 지평별 파라미터(앞 판은 K 공유).
#     (d) 표적 R_k^t = 원수익(앞 판은 월 횡단면 평균 제거판).
#     (e) 보유 비중 = 그 달 Eq (10) 산출 W_k 그대로(앞 판은 K 평균 → 상위 25 재정규화 —
#         채점 대상과 보유 대상이 갈렸다). 지평은 보유창에 대응하는 k=20 한 칸.
#     (f) 학습 종료 = 마지막 반복(앞 판은 목적함수 argmin 반복 채택 = 미신고 조기종료).
#     (g) 팩터 z 절단·softmax 전 활성 절단 폐지(softmax 는 최대값 차감 — 수치 항등).
#     (h) 월말 유니버스 전 종목이 횡단면에 남는다(앞 판은 팩터 전결측 종목이 탈락).
#     (i) 게이트 '유지 팩터 하한 10종' 폐지 — 1_{>=γ_f} 그대로(§4.1 집중 기전 복원).
# =============================================================================

suppressWarnings(suppressMessages({
  library(data.table)
  library(matrixStats)
}))

# ---- 상수 — 전부 FIDELITY.json::constants 에 신고된다 ------------------------
KH            <- c(3L, 5L, 10L, 15L, 20L)   # paper §4.2 k-forward trading days
K_HOLD        <- 20L                        # 보유 비중으로 쓰는 지평(= 월 보유창)
THETA         <- 0.10                       # paper §4.4 allocation upper bound
B_F_INIT      <- 1e-6                       # paper Algo 1 line 3  b_f <- 1e-6
N_AXIS        <- 25L                        # 고정 축 — 보유 종목수 상한
H_DIM         <- 8L                         # encoder hidden width m_1 (supplement)
HG_DIM        <- 4L                         # gate MLP hidden width (supplement)
LEAKY_A       <- 0.01                       # LeakyReLU slope (supplement)
LR            <- 0.05                       # RMS-normalized step size (supplement)
N_EPOCH_FIRST <- 200L                       # 최초 적합 반복 (supplement)
N_EPOCH_WARM  <- 5L                         # warm start 반복 (supplement)
SEED          <- 16364L                     # init seed (supplement)
INIT_SD       <- 0.10                       # init sd (supplement)
NORM_CAP      <- 10.0                       # parameter block Frobenius cap (supplement)
EPS           <- 1e-8                       # denominator guard (supplement)
MIN_POOL      <- 10L                        # 팩터 풀 크기 하한 (supplement)
MIN_STOCKS    <- 30L                        # 월 최소 횡단면 (supplement)
MIN_FIN       <- 2L                         # 표준화 최소 관측수 (supplement)
MIN_TRAIN_M   <- 36L                        # 최소 학습 월수 (supplement)
COV_MIN       <- 0.05                       # connector coverage 기본값 (harness)
N_PER_FAM     <- 3L                         # 군별 풀 상한 (supplement)
POOL_MAX      <- 21L                        # 풀 총 상한 (supplement)
START_LOAD_D  <- "2000-01-01"               # 학습용 적재 시작 (supplement)
EMIT_START_D  <- "2005-01-01"               # 측정 시작 = 축 (harness)

KMAX <- max(KH)                             # 파생 — 학습창 성숙 판정 지평
KN   <- length(KH)                          # 파생 — paper K
KHI  <- which(KH == K_HOLD)                 # 파생 — 보유 지평 열 인덱스

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
.gmean <- function(M, gi, gc) rowsum(M, gi, reorder = TRUE) / gc
# 블록 대각 구조 — 월(또는 월×업종) 안에서만 평균을 뺀다. 시계열 통계 아님.
.demean <- function(M, gi, gc) M - .gmean(M, gi, gc)[gi, , drop = FALSE]
# 파라미터 블록 노름 상한 (attention 과집중·발산 수치 방어)
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
if (!all(c("Date", "Ticker", "Close") %in% names(RD)))
  stop("[E2EAI] RAWDATA 에 Date/Ticker/Close 가 없다 — 표적 수익 구성 불가")
# §4.2 의 업종 그래프는 업종 분류가 있어야 성립한다(논문 CITIC 분류 자리).
# 라벨이 없으면 C̄_U 블록이 항등 0 이 되어 심층팩터 입력 1/3 이 죽는다 — fail-closed.
if (!("Sector" %in% names(RD)))
  stop("[E2EAI] RAWDATA 에 Sector 열이 없다 — 논문 §4.2 업종 그래프 구성 불가(fail-closed)")

ALLD <- sort(unique(RD$Date))
nD   <- length(ALLD)
mtag <- format(ALLD, "%Y%m")
MEI  <- which(!duplicated(mtag, fromLast = TRUE))          # 각 월의 마지막 거래일
MEI  <- MEI[ALLD[MEI] >= as.Date(START_LOAD_D)]
if (!length(MEI)) stop("[E2EAI] 월말 거래일 격자 구성 실패")
MED  <- ALLD[MEI]

# 가격 조회용 종목 집합(상위집합) — 날짜별 선택은 UNI 가 하므로 선별 효과 없다.
uni_tk <- unique(RD[K200 == TRUE | KQ150 == TRUE, Ticker])
if (!length(uni_tk)) stop("[E2EAI] K200/KQ150 멤버 종목 0")

# 필요한 날짜만: 진입일(t+1) + 청산일(t+k)
.pi <- unique(c(MEI + 1L, as.vector(outer(MEI, KH, "+"))))
.pi <- .pi[.pi >= 1L & .pi <= nD]
PXD <- ALLD[sort(unique(.pi))]

PX <- RD[Date %in% PXD & Ticker %in% uni_tk & is.finite(Close) & Close > 0,
         .(Date, Ticker, Close)]
if (!nrow(PX)) stop("[E2EAI] 진입·청산일 가격 0행 — 표적 구성 불가")
# (Date,Ticker) 중복은 먼저 접는다 — 남으면 같은 셀을 덮어써 조용히 한 값만 남는다.
PX  <- unique(PX, by = c("Date", "Ticker"))
PXT <- sort(unique(PX$Ticker))
PXC <- as.character(PXD)
PXM <- matrix(NA_real_, length(PXT), length(PXC), dimnames = list(PXT, PXC))
PXM[cbind(match(PX$Ticker, PXT), match(as.character(PX$Date), PXC))] <- PX$Close
rm(PX)

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
cat(sprintf("[E2EAI] universe rows %d | tickers %d | sectors %d | month-ends %d\n",
            nrow(UNI), uniqueN(UNI$Ticker), uniqueN(UNI$Sector), length(MEI)))

# =============================================================================
# 2. 팩터 풀 — 논문 7군(§5) ↔ 인프라 경제계열 군. 풀 기준일 = 첫 측정 월말.
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
  unique(pan, by = c("Ticker", "Factor_Name"))
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
if (length(POOL) < MIN_POOL)
  stop(sprintf("[E2EAI] 팩터 풀 %d종 — 하한 %d 미달(fail-closed)", length(POOL), MIN_POOL))
M_DIM   <- length(POOL)
GAMMA_F <- 1 / M_DIM                  # paper §4.1 γ_f 미명시 → 균일 attention 수준
rm(.p0, .u0, .cv)
cat(sprintf("[E2EAI] factor pool = %d (anchor %s) | %s\n",
            M_DIM, format(PANCH), paste(POOL, collapse = ",")))

# =============================================================================
# 3. 월별 패널
#    XO = 원팩터 패널 F_o^t (Eq (1) 게이트 입력 — 재표준화 전)
#    X  = BatchNorm 등가(월 횡단면 표준화) 패널 (Eq (3) 입력)
#    Y  = (P[t+k] − P[t+1]) / P[t+1]  (§3 · §5 거래일 격자)
#    ★월말 유니버스 멤버는 팩터 커버리지와 무관하게 전원 횡단면에 남는다
#      (논문 §5 에 데이터 가용성 기반 종목 제외 규칙이 없다).
# =============================================================================
.build_month <- function(j) {
  ti    <- MEI[j]
  adate <- ALLD[ti]
  ur    <- UNI[.(adate), nomatch = NULL]
  if (nrow(ur) < MIN_STOCKS) return(NULL)
  pan <- .load_panel(adate, POOL)
  if (is.null(pan)) return(NULL)
  tk <- ur$Ticker
  n  <- length(tk)

  XO <- matrix(NA_real_, n, M_DIM, dimnames = NULL)
  pan <- pan[Ticker %in% tk & Factor_Name %in% POOL]
  if (!nrow(pan)) return(NULL)
  ri <- match(pan$Ticker, tk)
  ci <- match(pan$Factor_Name, POOL)
  XO[cbind(ri, ci)] <- pan$Z_Score_Aligned

  # BatchNorm 등가 = 그 달 횡단면 표준화. 결측은 **표준화 뒤에** 0(= 그 달 평균)으로
  # 채운다 — 채운 뒤 표준화하면 대체값이 −mu/sd 로 밀려 인공 신호가 생긴다.
  X <- XO
  for (cc in seq_len(M_DIM)) {
    v  <- X[, cc]
    fi <- is.finite(v)
    if (sum(fi) < MIN_FIN) { X[, cc] <- 0.0; next }
    mm <- mean(v[fi])
    ss <- sqrt(mean((v[fi] - mm)^2))
    if (!is.finite(ss) || ss < EPS) { X[, cc] <- 0.0; next }
    X[, cc] <- (v - mm) / ss
  }
  X[!is.finite(X)] <- 0.0
  XO[!is.finite(XO)] <- 0.0        # 게이트 풀링 입력의 결측도 중립값 0

  # 업종 그룹 (relational neutralization 의 industry 이웃)
  sec <- ur$Sector
  sec[is.na(sec) | !nzchar(sec)] <- "UNKNOWN"

  # 표적: 진입 t+1 종가 → 청산 t+k 종가
  Y <- matrix(NA_real_, n, KN)
  exit_d <- as.Date(NA)
  if (ti + KMAX <= nD) {
    dn <- as.character(ALLD[c(ti + 1L, ti + KH)])
    if (all(dn %in% PXC)) {
      pri <- match(tk, rownames(PXM))
      ce  <- PXM[pri, dn[1L]]
      for (kk in seq_len(KN)) Y[, kk] <- PXM[pri, dn[kk + 1L]] / ce - 1.0
      Y[!is.finite(Y)] <- NA_real_
      exit_d <- ALLD[ti + KMAX]
    }
  }
  list(adate = adate, tick = tk, XO = XO, X = X, sec = sec, Y = Y,
       cmp = stats::complete.cases(Y), exit_d = exit_d)
}

# =============================================================================
# 4. 학습 상태(expanding) — 월이 "최대 지평 청산 완료" 가 되는 순간에만 적재된다
# =============================================================================
.stk_new <- function() list(
  XO = matrix(0.0, 0L, M_DIM), X = matrix(0.0, 0L, M_DIM),
  Y  = matrix(0.0, 0L, KN),
  mi = integer(0), si = integer(0), mc = integer(0), sc = integer(0),
  ms = integer(0), me = integer(0), G = 0L, S = 0L)

.stk_append <- function(S, mo) {
  keep <- mo$cmp
  if (sum(keep) < MIN_STOCKS) return(S)
  n  <- sum(keep)
  g  <- S$G + 1L
  sj <- as.integer(factor(mo$sec[keep]))
  nsg <- max(sj)
  S$XO <- rbind(S$XO, mo$XO[keep, , drop = FALSE])
  S$X  <- rbind(S$X,  mo$X[keep, , drop = FALSE])
  S$Y  <- rbind(S$Y,  mo$Y[keep, , drop = FALSE])   # 원수익 R_k^t (§4.4) — 변환 없음
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

# 추론용 1개월 상태 — 표적은 쓰지 않는다(0 으로 둔다).
.stk_one <- function(mo) {
  n  <- nrow(mo$X)
  sj <- as.integer(factor(mo$sec))
  list(XO = mo$XO, X = mo$X, Y = matrix(0.0, n, KN),
       mi = rep.int(1L, n), si = sj, mc = n,
       sc = as.integer(tabulate(sj, nbins = max(sj))),
       ms = 1L, me = n, G = 1L, S = max(sj))
}

# =============================================================================
# 5. 모형 — 순전파/역전파
#    Eq(1) gate(F_o) -> Eq(3) encoder -> Eq(4)(5) RNB -> Eq(6) K deep factors
#    -> Algo1:7 directional buffer -> Eq(9) attention -> Eq(10) allocation
# =============================================================================
.par_init <- function() {
  set.seed(SEED)
  list(wg1 = stats::rnorm(HG_DIM, 0, INIT_SD),      # Eq (1) MLP 1층 (원소별 공유)
       bg1 = rep(0.0, HG_DIM),
       wg2 = stats::rnorm(HG_DIM, 0, INIT_SD),      # Eq (1) MLP 출력층
       W1  = matrix(stats::rnorm(M_DIM * H_DIM, 0, INIT_SD), M_DIM, H_DIM),
       b1  = rep(0.0, H_DIM),
       V   = matrix(stats::rnorm(3L * H_DIM * KN, 0, INIT_SD), 3L * H_DIM, KN),
       P   = matrix(stats::rnorm((H_DIM + 1L) * KN, 0, INIT_SD), H_DIM + 1L, KN),
       bp  = rep(0.0, KN))
}

# ---- Eq (1)(2) 팩터선택 게이트 — 입력은 그 달 원팩터 패널 F_o^t -------------
# MLP(F_o^t): ℝ^{n×m} → ℝ^m. 종목수 n 이 월마다 변하므로 종목축 치환불변 형태로
# 쓴다 — 원소별 공유 1층 tanh → 종목축 평균 풀링 → 선형 사영 → 팩터축 softmax.
.gate <- function(PAR, S, cache) {
  Pl <- vector("list", HG_DIM)
  Dl <- if (isTRUE(cache)) vector("list", HG_DIM) else NULL
  s  <- matrix(0.0, S$G, M_DIM)
  for (c in seq_len(HG_DIM)) {
    Tc <- tanh(S$XO * PAR$wg1[c] + PAR$bg1[c])
    Pc <- rowsum(Tc, S$mi, reorder = TRUE) / S$mc
    Pl[[c]] <- Pc
    if (isTRUE(cache)) Dl[[c]] <- 1.0 - Tc * Tc   # tanh' — 역전파 재계산 회피
    s <- s + Pc * PAR$wg2[c]
  }
  e <- exp(s - rowMaxs(s))                       # softmax (최대값 차감 = 수치 항등)
  a <- e / rowSums(e)
  # 1_{>=γ_f} — 확률벡터의 최대값은 항상 1/m 이상이므로 유지 팩터는 최소 1 개다.
  # (유지 종목수 하한 같은 보조 규칙을 두지 않는다 — §4.1 의 집중 기전을 가린다.)
  msk <- a >= GAMMA_F
  gh <- a * msk
  sg <- pmax(rowSums(gh), EPS)
  ns <- rowSums(msk)
  list(a = a, msk = msk, gh = gh, sg = sg, ns = ns,
       gv = gh * (ns / sg), Pl = if (isTRUE(cache)) Pl else NULL, Dl = Dl)
}

# ---- Eq (9)(10) attention(1단) → 임계 → 생존 종목 softmax(2단) --------------
# γ_p ∈ (0,1] 는 확률 A 에 걸리는 하한이다(논문 정의역). 값 미명시 →
# γ_p^t = max(1/n , A 의 N_AXIS 번째 큰 값) 로 실현한다: 균일 attention 미달은
# 떨어지고(자동 선택 — 보유수가 25 보다 적을 수 있다), 상한은 고정 축 25 다.
.alloc <- function(ZP, S) {
  n <- nrow(ZP)
  A <- matrix(0.0, n, KN)
  W <- matrix(0.0, n, KN)
  for (g in seq_len(S$G)) {
    ii <- S$ms[g]:S$me[g]
    ng <- length(ii)
    zz <- ZP[ii, , drop = FALSE]
    ez <- exp(zz - rep(colMaxs(zz), each = ng))
    aa <- ez / rep(colSums(ez), each = ng)       # Eq (9) softmax
    A[ii, ] <- aa
    lo <- 1.0 / ng
    nn <- min(N_AXIS, ng)
    for (k in seq_len(KN)) {
      av  <- aa[, k]
      o   <- order(-av, seq_len(ng))             # 동점은 (점수 내림, 행번호) 결정적
      sel <- o[seq_len(nn)]
      thr <- max(lo, av[sel[nn]])                # γ_p^t
      sel <- sel[av[sel] >= thr]
      ex  <- numeric(ng)
      ex[sel] <- exp(av[sel])                    # Eq (10) softmax (생존 종목)
      W[ii, k] <- ex / sum(ex)
    }
  }
  list(A = A, W = W)
}

.fb <- function(PAR, S, dbuf, grad) {
  n <- nrow(S$X); h <- H_DIM
  gt <- .gate(PAR, S, grad)
  Xg <- S$X * gt$gv[S$mi, , drop = FALSE]                  # Eq (2) 선택 팩터 패널
  Z1 <- Xg %*% PAR$W1 + rep(PAR$b1, each = n)
  C0 <- tanh(Z1)                                           # Eq (3) C_t
  CI <- .demean(C0, S$si, S$sc)                            # Eq (5) C̄_I (industry)
  CU <- .demean(CI, S$mi, S$mc)                            # Eq (5) C̄_U (cross-industry)
  HC <- cbind(C0, CI, CU)
  ZF <- HC %*% PAR$V
  nf <- ZF < 0
  F0 <- ZF; F0[nf] <- ZF[nf] * LEAKY_A                     # Eq (6) f_k, k=1..K

  FD   <- F0 * rep(dbuf, each = n)                         # f_k ∘ d_{f,k}
  Epre <- C0 %*% PAR$P[seq_len(h), , drop = FALSE] +
          FD * rep(PAR$P[h + 1L, ], each = n) +
          rep(PAR$bp, each = n)                            # Eq (9) W_{a,k}^T(C ‖ ·)
  np <- Epre < 0
  ZP <- Epre; ZP[np] <- Epre[np] * LEAKY_A                 # LeakyReLU
  al <- .alloc(ZP, S)
  A  <- al$A; Wt <- al$W

  obj <- (sum(Wt * (-S$Y)) + sum(pmax(Wt - THETA, 0.0))) / (S$G * KN)
  out <- list(obj = obj, Wt = Wt, F0 = F0)
  if (!isTRUE(grad)) return(out)

  # L_p = L_ret + L_up 의 ∂/∂W
  q   <- (-S$Y + (Wt > THETA)) / (S$G * KN)
  # Eq (10) softmax (생존 종목) Jacobian — 비생존은 Wt = 0 이라 같은 식으로 0 이 된다
  sq  <- rowsum(q * Wt, S$mi, reorder = TRUE)
  gA  <- Wt * (q - sq[S$mi, , drop = FALSE])
  # Eq (9) softmax (전 횡단면) Jacobian
  sa  <- rowsum(gA * A, S$mi, reorder = TRUE)
  gZ  <- A * (gA - sa[S$mi, , drop = FALSE])
  dl  <- matrix(1.0, n, KN); dl[np] <- LEAKY_A
  gE  <- gZ * dl

  gP  <- rbind(t(C0) %*% gE, colSums(gE * FD))
  gbp <- colSums(gE)
  gC  <- gE %*% t(PAR$P[seq_len(h), , drop = FALSE])

  gF0 <- gE * rep(PAR$P[h + 1L, ], each = n) * rep(dbuf, each = n)
  dlf <- matrix(1.0, n, KN); dlf[nf] <- LEAKY_A
  gZF <- gF0 * dlf
  gV  <- t(HC) %*% gZF
  gHC <- gZF %*% t(PAR$V)

  gC  <- gC + gHC[, seq_len(h), drop = FALSE]
  gCI <- gHC[, h + seq_len(h), drop = FALSE]
  gCU <- gHC[, 2L * h + seq_len(h), drop = FALSE]
  gCI <- gCI + .demean(gCU, S$mi, S$mc)                    # C̄_U = C̄_I − mean_month
  gC  <- gC  + .demean(gCI, S$si, S$sc)                    # C̄_I = C0 − mean_industry

  gZ1 <- gC * (1.0 - C0 * C0)
  gW1 <- t(Xg) %*% gZ1
  gb1 <- colSums(gZ1)
  gXg <- gZ1 %*% t(PAR$W1)

  # 게이트 역전파: gv = (a∘msk)·ns/Σ(a∘msk)  →  softmax  →  풀링 MLP
  ggv   <- rowsum(S$X * gXg, S$mi, reorder = TRUE)
  inner <- rowSums(ggv * gt$gh) / gt$sg
  dgh   <- (gt$ns / gt$sg) * (ggv - inner)
  da    <- dgh * gt$msk
  gs    <- gt$a * (da - rowSums(gt$a * da))
  gwg2  <- vapply(seq_len(HG_DIM), function(c) sum(gs * gt$Pl[[c]]), numeric(1))
  gwg1  <- numeric(HG_DIM); gbg1 <- numeric(HG_DIM)
  for (c in seq_len(HG_DIM)) {
    Dc <- (gs * (PAR$wg2[c] / S$mc))[S$mi, , drop = FALSE] * gt$Dl[[c]]
    gwg1[c] <- sum(Dc * S$XO)
    gbg1[c] <- sum(Dc)
  }

  out$gr <- list(wg1 = gwg1, bg1 = gbg1, wg2 = gwg2,
                 W1 = gW1, b1 = gb1, V = gV, P = gP, bp = gbp)
  out
}

# ---- Algo 1 line 3·7: b_f ← 1e-6 + Σ_t IC(r_t, f_t) · d_f = sgn(b_f) -------
.dsign <- function(F0, S) {
  fc <- .demean(F0, S$mi, S$mc)
  yc <- .demean(S$Y, S$mi, S$mc)
  nu <- rowsum(fc * yc, S$mi, reorder = TRUE)
  d1 <- rowsum(fc * fc, S$mi, reorder = TRUE)
  d2 <- rowsum(yc * yc, S$mi, reorder = TRUE)
  cm <- nu / sqrt(pmax(d1 * d2, EPS))            # 월별 Pearson 횡단면 IC
  cm[!is.finite(cm)] <- 0.0
  d <- sign(B_F_INIT + colSums(cm))
  d[d == 0] <- 1.0                               # b_f 초기값이 양수라 발동 불가(방어)
  as.numeric(d)
}

.train <- function(PAR, S, dbuf, nep) {
  for (it in seq_len(nep)) {
    r <- .fb(PAR, S, dbuf, TRUE)
    if (!is.finite(r$obj)) break
    g <- r$gr
    if (!all(vapply(g, function(z) all(is.finite(z)), logical(1)))) break
    dbuf <- .dsign(r$F0, S)                      # 배치 뒤 누산 부호(다음 반복에 적용)
    PAR$wg1 <- .capn(.stepn(PAR$wg1, g$wg1, LR), NORM_CAP)
    PAR$bg1 <- .capn(.stepn(PAR$bg1, g$bg1, LR), NORM_CAP)
    PAR$wg2 <- .capn(.stepn(PAR$wg2, g$wg2, LR), NORM_CAP)
    PAR$W1  <- .capn(.stepn(PAR$W1,  g$W1,  LR), NORM_CAP)
    PAR$b1  <- .capn(.stepn(PAR$b1,  g$b1,  LR), NORM_CAP)
    PAR$V   <- .capn(.stepn(PAR$V,   g$V,   LR), NORM_CAP)
    PAR$P   <- .capn(.stepn(PAR$P,   g$P,   LR), NORM_CAP)
    PAR$bp  <- .capn(.stepn(PAR$bp,  g$bp,  LR), NORM_CAP)
  }
  list(par = PAR, dbuf = dbuf)                   # 마지막 반복 그대로(조기종료 없음)
}

# =============================================================================
# 6. 메인 루프 — 월말마다: 패널 적재 -> (적격이면) 재학습 -> 그 달 비중 산출
# =============================================================================
PAR  <- NULL
DBUF <- rep(1.0, KN)                             # sgn(b_f), b_f = 1e-6 > 0
STK  <- .stk_new()
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
.mature <- function(P, S, adate) {
  if (!length(P)) return(list(P = P, S = S))
  kp <- logical(length(P))
  for (i in seq_along(P)) {
    if (P[[i]]$exit_d <= adate) S <- .stk_append(S, P[[i]]) else kp[i] <- TRUE
  }
  list(P = P[kp], S = S)
}

N_SKIP <- 0L                                     # 진단 — 패널 부재·적재 실패 월 수
for (j in seq_along(MEI)) {
  adate <- ALLD[MEI[j]]
  mo <- tryCatch(.build_month(j), error = function(e) NULL)
  if (is.null(mo)) N_SKIP <- N_SKIP + 1L
  PEND <- .park(PEND, mo)
  .mt  <- .mature(PEND, STK, adate)
  PEND <- .mt$P
  STK  <- .mt$S

  # 적재 전 구간이거나 그 달 패널이 없다 — 산출 없음(하네스가 직전 보유 이월).
  if (adate < EMIT_D || is.null(mo)) next
  if (STK$G < MIN_TRAIN_M) next

  if (is.null(PAR)) {
    PAR <- .par_init()
    tr  <- .train(PAR, STK, DBUF, N_EPOCH_FIRST)
  } else {
    tr  <- .train(PAR, STK, DBUF, N_EPOCH_WARM)
  }
  PAR <- tr$par; DBUF <- tr$dbuf

  pr <- tryCatch(.fb(PAR, .stk_one(mo), DBUF, FALSE), error = function(e) NULL)
  if (is.null(pr)) next
  wv <- pr$Wt[, KHI]                             # Eq (10) W_k, k = K_HOLD
  if (!all(is.finite(wv))) next
  sel <- which(wv > 0.0)
  if (!length(sel)) next
  OUTL[[length(OUTL) + 1L]] <- data.table(
    Date = adate, Ticker = mo$tick[sel], Weight = wv[sel], Leg = "long")
}

PORTFOLIO <- if (length(OUTL)) rbindlist(OUTL, use.names = TRUE) else
  data.table(Date = as.Date(character(0)), Ticker = character(0),
             Weight = numeric(0), Leg = character(0))
setorder(PORTFOLIO, Date, -Weight)
if (!nrow(PORTFOLIO))
  stop(sprintf(paste0("[E2EAI] 적격 신호월 0 — PORTFOLIO 공백(fail-closed). ",
                      "학습 적재월 %d(하한 %d) · 팩터 풀 %d · 월말 %d · 패널부재월 %d. ",
                      "팩터 DB 월 파일 as-of 불일치 또는 학습창 하한 미충족을 보라."),
               STK$G, MIN_TRAIN_M, M_DIM, length(MEI), N_SKIP))
cat(sprintf(paste0("[E2EAI] PORTFOLIO %d rows | %d dates | n/date %.0f~%.0f | %s~%s",
                   " | train months %d | skipped months %d\n"),
            nrow(PORTFOLIO), uniqueN(PORTFOLIO$Date),
            min(PORTFOLIO[, .N, by = Date]$N), max(PORTFOLIO[, .N, by = Date]$N),
            format(min(PORTFOLIO$Date)), format(max(PORTFOLIO$Date)), STK$G, N_SKIP))
