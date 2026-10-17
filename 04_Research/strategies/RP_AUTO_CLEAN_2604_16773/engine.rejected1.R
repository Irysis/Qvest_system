# =============================================================================
# Topological Risk Parity (TRP) — Variant I: rooted-MST allocator
#   Paper : R. Nayar, E. M. Ainasse, D. Kulkarni, "Topological Risk Parity",
#           arXiv:2604.16773v1 (q-fin.PM)
#   Output: PORTFOLIO(Date, Ticker, Weight, Leg) — 부호 있는 롱/숏 비중.
#           러너는 portfolio_spec construction="engine_direct" 로 그대로 소비한다.
#
#   ★신고 정본 = 같은 디렉터리 FIDELITY.json. 이 주석은 통로가 아니다.
#
#   논문 파이프라인 (§4 ~ §5.1 · Appendix A eq 16):
#     활동 필터 m_i=(1/k)Σ|r_it| · A={m_i>eps, |s_i|>tau}            (eq 8)
#     -> 상관 C=corr(R^A) · [-1,1] 클립 · NaN->0 · 대칭화              (§4.2)
#     -> 거리 D_ij = sqrt((1 - C_ij)/2)                                (eq 9)
#     -> MST(완전 가중 그래프) -> 루트 선택(hub = 최대 차수)           (§4.2, §5.1 Step 2)
#     -> 혼합 분할-복제 계수 alpha_u = (1-rho) + rho/b(u)              (eq 10)
#     -> 위상 인자 g_r=1, g_v = alpha_pa(v) * g_pa(v)                  (eq 11-12)
#     -> x_v = s_v * g_v  (원신호 그대로 · 변동성 재조정 없음)         (Step 5)
#     -> w_v = L * x_v / ||x||_1 (||x||_1 > 0 일 때)                   (eq 13)
#
#   Variant II(TRP-SPY/XL · 더미 SPY 루트 + XL* 섹터 ETF 2계층 + eq 14 clip/eta)
#   는 구현하지 않는다 — 사유·귀속은 FIDELITY.json(paper_steps · changed).
# =============================================================================

suppressMessages(library(data.table))

# ---- 0. 입력 계약 (호출자가 환경에 넣는다) ----------------------------------
if (!exists("RAWDATA", inherits = TRUE) || !is.data.table(RAWDATA))
  stop("[TRP] RAWDATA(data.table) 가 환경에 없다 — 호출자 계약")
if (!exists(".RP_START_DATE", inherits = TRUE))
  stop("[TRP] .RP_START_DATE 가 환경에 없다 — 측정 축 시작일은 호출자가 넣는다(리터럴 금지)")
.trp_need <- c("Date", "Ticker", "Ret", "K200", "KQ150")
if (!all(.trp_need %in% names(RAWDATA)))
  stop(sprintf("[TRP] RAWDATA 열 부족: %s", paste(setdiff(.trp_need, names(RAWDATA)), collapse = ", ")))

# ---- 1. 상수 (전부 FIDELITY.json::constants 에 신고) ------------------------
.TRP_RHO          <- 1.0      # eq 10 의 rho — 보수적 등분할 칸(Appendix B · Remark 2 · Prop 3b)
.TRP_LEVERAGE     <- 1.0      # eq 13 의 L (목표 총노출) — 논문 무명시
.TRP_TAU          <- 1e-3     # eq 8 의 tau — 논문 §4.1 기준값
.TRP_EPS_ACT      <- 0.0      # eq 8 의 eps — 논문 "eps>0" 무명시 · 극한 최소값
.TRP_WIN_DAYS     <- 252L     # 창 길이 T (= k) — 논문 무명시
.TRP_MIN_OBS_FRAC <- 0.8      # 창 내 유한 수익 관측 커버리지 하한 — 논문 밖 가드
.TRP_MIN_ACTIVE   <- 2L       # MST 성립 최소 노드 수 — 논문 밖 구조 하한
.TRP_ROOT_MODE    <- "hub"    # §5.1 Step 2 세 규칙 중 선택한 칸(최대 차수)
.SIG_FROM         <- as.Date(.RP_START_DATE)
.TRP_MIN_OBS      <- as.integer(ceiling(.TRP_MIN_OBS_FRAC * .TRP_WIN_DAYS))

# ---- 2. 거래일 격자 · 수익 행렬 · 신호일 · 유니버스 멤버십 ------------------
#   행렬은 색인 공간일 뿐이고(통계 아님), 매 신호일에 읽는 행은 창 [i-251, i] 뿐이다.
.trp_dates <- sort(unique(RAWDATA$Date))
.trp_nd    <- length(.trp_dates)
.trp_tick  <- sort(unique(RAWDATA$Ticker))
.trp_RM    <- matrix(NA_real_, nrow = .trp_nd, ncol = length(.trp_tick))
.trp_RM[match(RAWDATA$Date, .trp_dates) +
        (match(RAWDATA$Ticker, .trp_tick) - 1L) * .trp_nd] <- RAWDATA$Ret

# 신호일 = 각 월 마지막 거래일 · 전체 창이 서는 날 · 측정 축 시작 이후
.trp_mlab <- format(.trp_dates, "%Y-%m")
.trp_sidx <- which(!duplicated(.trp_mlab, fromLast = TRUE) &
                   .trp_dates >= .SIG_FROM &
                   seq_len(.trp_nd) >= .TRP_WIN_DAYS)
if (!length(.trp_sidx)) stop("[TRP] 신호일 0 — 창 길이 · 시작일 확인")
.trp_sdates <- .trp_dates[.trp_sidx]

# 유니버스 = 계약이 K200 플래그에 주입한 측정 축 멤버십(엔진은 플래그만 본다)
UNI <- unique(RAWDATA[as.integer(Date) %in% as.integer(.trp_sdates) &
                      (K200 == 1 | KQ150 == 1), .(Date, Ticker)])
setkey(UNI, Date, Ticker)   # 날짜 안 티커 정렬 고정 = 노드 색인 결정성(동점 = 최소 인덱스)

# ---- 3. MST — Prim (논문 참조 [4]) · 동점 = 최소 인덱스 ---------------------
.trp_mst <- function(Dm) {
  n    <- ncol(Dm)
  inT  <- logical(n); inT[1L] <- TRUE
  dcur <- Dm[1L, ]; src <- rep(1L, n)
  e1   <- integer(n - 1L); e2 <- integer(n - 1L)
  for (k in seq_len(n - 1L)) {
    dcur[inT] <- Inf
    j <- which.min(dcur)
    e1[k] <- src[j]; e2[k] <- j
    inT[j] <- TRUE
    dj  <- Dm[j, ]
    upd <- !inT & (dj < dcur)
    if (any(upd)) { dcur[upd] <- dj[upd]; src[upd] <- j }
  }
  list(e1 = e1, e2 = e2)
}

# ---- 4. 루트(hub) · 지향 · 위상 인자 g (eq 10 ~ 12) -------------------------
#   무향 트리에서 루트를 고정하면 부모/자식은 유일하다(논문 §5.1 Step 2:
#   "any traversal can be used to recover it") — 여기서는 BFS 로 복원한다.
.trp_factors <- function(e1, e2, n, rho) {
  deg  <- tabulate(c(e1, e2), nbins = n)
  root <- which.max(deg)                                   # hub mode · 동점 최소 인덱스
  adj  <- split(c(e2, e1), factor(c(e1, e2), levels = seq_len(n)))
  par  <- rep(NA_integer_, n)
  vis  <- logical(n); vis[root] <- TRUE
  ord  <- integer(n);  ord[1L]  <- root
  hp <- 1L; tp <- 1L
  while (hp <= tp) {
    u  <- ord[hp]; hp <- hp + 1L
    nb <- adj[[u]]
    if (length(nb)) nb <- nb[!vis[nb]]
    if (length(nb)) {
      vis[nb] <- TRUE
      par[nb] <- u
      ord[seq.int(tp + 1L, tp + length(nb))] <- nb
      tp <- tp + length(nb)
    }
  }
  if (tp != n) return(NULL)                                # 비연결 트리 = 구조 트립와이어
  bch  <- tabulate(par[!is.na(par)], nbins = n)            # b(u)
  alph <- rep(NA_real_, n)
  hasc <- bch >= 1L
  alph[hasc] <- (1 - rho) + rho / bch[hasc]                # eq 10
  g <- rep(NA_real_, n); g[root] <- 1                      # eq 11 초기값
  for (q in seq.int(2L, n)) { v <- ord[q]; g[v] <- alph[par[v]] * g[par[v]] }
  g
}

# ---- 5. 월별 배분 -----------------------------------------------------------
.trp_out <- vector("list", length(.trp_sidx))

for (.q in seq_along(.trp_sidx)) {
  i <- .trp_sidx[.q]
  d <- .trp_dates[i]

  cand <- UNI[.(d), Ticker, nomatch = 0L]
  if (length(cand) < .TRP_MIN_ACTIVE) next

  # 창 종점 = 신호일 d — d 종가에 알려진 값만 들어가고 체결은 다음 거래일 종가(H4)
  rws <- seq.int(i - .TRP_WIN_DAYS + 1L, i)
  Wm  <- .trp_RM[rws, match(cand, .trp_tick), drop = FALSE]

  nob <- colSums(is.finite(Wm))
  kp  <- nob >= .TRP_MIN_OBS                               # 커버리지 하한(논문 밖 가드)
  if (sum(kp) < .TRP_MIN_ACTIVE) next
  Wm  <- Wm[, kp, drop = FALSE]; nmk <- cand[kp]
  Wm[!is.finite(Wm)] <- 0                                  # 결측 = 변동 없음(논문 밖 처리)

  m_i <- colSums(abs(Wm)) / .TRP_WIN_DAYS                  # eq 8 의 m_i
  s_0 <- colSums(log1p(Wm))                                # 보충 신호: 창 누적 로그수익
  fi  <- is.finite(s_0)
  if (sum(fi) < .TRP_MIN_ACTIVE) next
  if (!all(fi)) {                                          # 비유한 신호는 중심화 전에 제외
    Wm <- Wm[, fi, drop = FALSE]; nmk <- nmk[fi]; m_i <- m_i[fi]; s_0 <- s_0[fi]
  }
  s_i <- s_0 - mean(s_0)                                   # 횡단면 중심화 = 부호 신호

  act <- (m_i > .TRP_EPS_ACT) & (abs(s_i) > .TRP_TAU)      # eq 8 의 활성 집합 A
  if (sum(act) < .TRP_MIN_ACTIVE) next
  Wa  <- Wm[, act, drop = FALSE]; sa <- s_i[act]; nma <- nmk[act]
  n   <- length(sa)

  Cm <- suppressWarnings(stats::cor(Wa))                   # §4.2
  Cm[!is.finite(Cm)] <- 0                                  # 논문: NaN -> 0
  Cm <- pmin(pmax(Cm, -1), 1)                              # 논문: [-1,1] 클립
  Cm <- (Cm + t(Cm)) / 2                                   # 논문: 대칭화
  diag(Cm) <- 1
  Dm <- sqrt((1 - Cm) / 2)                                 # eq 9

  tr <- .trp_mst(Dm)
  gv <- .trp_factors(tr$e1, tr$e2, n, .TRP_RHO)
  if (is.null(gv)) next

  xv <- sa * gv                                            # eq 13 전 단계(Step 5)
  gx <- sum(abs(xv))
  if (!is.finite(gx) || gx <= 0) next                      # eq 13 전제 ||x||_1 > 0
  wv <- .TRP_LEVERAGE * xv / gx                            # eq 13
  ok <- is.finite(wv) & wv != 0
  if (sum(ok) < .TRP_MIN_ACTIVE) next

  .trp_out[[.q]] <- data.table(Date   = d,
                               Ticker = nma[ok],
                               Weight = wv[ok],
                               Leg    = ifelse(wv[ok] > 0, "long", "short"))
}

PORTFOLIO <- rbindlist(.trp_out, use.names = TRUE)
if (!nrow(PORTFOLIO)) stop("[TRP] PORTFOLIO 0행 — 활성 종목이 서지 않았다")
setorder(PORTFOLIO, Date, Ticker)

cat(sprintf("[TRP] 신호일 %d/%d · 행 %s · 일평균 보유 %.0f종(롱 %.0f · 숏 %.0f) · 창 %d거래일 · rho=%.2f · L=%.2f\n",
            uniqueN(PORTFOLIO$Date), length(.trp_sidx), format(nrow(PORTFOLIO), big.mark = ","),
            nrow(PORTFOLIO) / uniqueN(PORTFOLIO$Date),
            sum(PORTFOLIO$Weight > 0) / uniqueN(PORTFOLIO$Date),
            sum(PORTFOLIO$Weight < 0) / uniqueN(PORTFOLIO$Date),
            .TRP_WIN_DAYS, .TRP_RHO, .TRP_LEVERAGE))

rm(.trp_RM, .trp_out)
invisible(gc(verbose = FALSE))
