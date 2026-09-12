# =============================================================================
# engine.R — RP_AUTO_2001_04185  (1판 · 2026-09-12)
# V. Volpati · M. Benzaquen · Z. Eisler · I. Mastromatteo · B. Tóth · J.-P. Bouchaud (Capital Fund Management),
#   "Zooming In on Equity Factor Crowding"  arXiv:2001.04185 (v1 2020-01-13)
#   https://arxiv.org/abs/2001.04185 — 본문 = r.jina.ai PDF 텍스트 프록시(2023 이전 논문 · arxiv html 렌더 없음)
#
# ★라벨(adapted)·변경 전수 신고·러너 사양의 정본 = FIDELITY.json. 이 주석은 아무것도 결정하지 않는다.
#   코드 옆 ★changed(n) 표식 = FIDELITY.json changed 의 항목 번호.
#
# 논문이 주는 것(§II.A 축자): "let us denote by s_{i,t} the 'signal' followed by an investor, giving the ideal
#   holding of stock i on the close of day t. For example, s_{i,t} would be the ranking of stocks according to
#   their past returns in the case of the Momentum factor. The actual holdings π_{i,t} of the investor is then
#   given by an Exponential Moving Average (EMA):
#       π_{i,t} = A Σ_{t'≤t} s_{i,t'} exp(−(t−t')/D)                                            (1)
#   The factor A sets the overall risk of the portfolio, whereas the slowing down time scale D is chosen as to
#   provide a good compromise between performance and trading costs. The theoretically expected order flow from
#   the strategy on day t is thus given by   Δπ_{i,t} = π_{i,t} − π_{i,t−1}                      (2)"
#   Fig.1 캡션: "The slowed down signal π_{i,t} with slowing down timescale D = 3 months".
#   논문의 원래 산출 = 이 Δπ 와 체결부호·거래량·호가잔량 불균형(식 3·4·7, CFM 체결 데이터) 및 Ancerno 메타오더
#   불균형(식 8)의 상관을 D 의 함수로 잰 크라우딩 진단 — 종목선택 전략이 아니다. 모멘텀 룩백·순위 정규화·D 값은
#   논문이 [14,19](Carhart 1997 · Jegadeesh-Titman 1993)에 위임하거나 스캔한다.
#
# 이 엔진 = 논문이 정의한 **가설적 모멘텀 팩터 투자자의 포지션 과정**(식 1·2)을 전략으로 이식한 것:
#   s_{i,t} = 그날 K200∪KQ150 구성종목의 과거수익(Carhart 1997 / FF prior 2-12 = 12-1개월, 거래일 격자) 횡단면 순위,
#             중심화(rank − (n+1)/2) 후 다리별 총합 1 로 스케일 · 순위 밖 = 0                         (changed(2)(4))
#   π_{i,t} = λ π_{i,t−1} + A s_{i,t},  λ = exp(−1/D), D = 3개월 = 63거래일, A = 1−λ                  (changed(3)(4))
#   보유 ∝ π (롱 = π>0 · 숏 = π<0 · 전 유니버스) — 월말 스냅샷만 집행(하네스 = 익월 첫 거래일 · changed(5))
#   크라우딩 측정은 KRX 거래주체 순매수대금(Ancerno 대응)으로 **진단 전용** 재현 — 산출물에 영향 0 (changed(9))
#
# 산출: PORTFOLIO(Date, Ticker, Weight, Leg) — Weight = π_{i,t} (월말 t · 그날 구성종목 · 0 제외 · 부호 = 다리)
#       FACTORS(Date, Ticker, Score)          — Score = 같은 π (분석기 IC/FMB · 강화 레인용 스냅샷)
#
# PIT(C1~C15) 구조 보장: s_t 는 종가 P_{t−21}, P_{t−252} 만 읽는다(창 종점 t−21 < t) · 순위 = 그날 횡단면만 ·
#   π 는 인과 재귀(과거 s 만) · 멤버십 = 그날 RAWDATA 행 플래그 · 월말 t 시그널 → 집행 익월 첫 거래일 ·
#   산출 경로에 전 표본 통계 0건 · 팩터 DB 미사용(C13/C15 대상 없음) · 유동성 스크린 없음(C10 대상 없음) ·
#   진단 블록(§7)은 산출물 확정 후 실행되고 어떤 값도 산출물로 되돌아가지 않는다.
# =============================================================================

suppressWarnings(suppressMessages({
  library(data.table)
}))

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
.TAG <- "[RP_AUTO_2001_04185]"
.REQ <- c("Date", "Ticker", "Close", "K200", "KQ150")
if (!all(.REQ %in% names(RAWDATA)))
  stop(sprintf("%s RAWDATA 필수 열 부재: %s", .TAG, paste(setdiff(.REQ, names(RAWDATA)), collapse = ", ")))
.t0 <- Sys.time()

# =============================================================================
# 0. 상수 — 논문 명시값(D = 3개월 · 식 1·2) + 논문이 위임·침묵한 규약(전부 FIDELITY.json changed 신고)
# =============================================================================
.D_MONTHS   <- 3L                                  # Fig.1 캡션 'D = 3 months'                          ★changed(3)
.DAYS_MONTH <- 21L                                 # 달 → 거래일 환산(21거래일/월)                       ★changed(3)
.D_DAYS     <- .D_MONTHS * .DAYS_MONTH             # 63
.LAMBDA     <- exp(-1 / .D_DAYS)                   # 식(1) 의 exp(−1/D)
.A_SCALE    <- 1 - .LAMBDA                         # 식(1) 의 A — 정상상태 이득 1                        ★changed(4)
.MOM_LONG   <- 12L * .DAYS_MONTH                   # 252: Carhart(1997) PR1YR / FF prior 2-12 의 12개월  ★changed(2)
.MOM_SKIP   <- 1L * .DAYS_MONTH                    # 21: 최근 1개월 건너뛰기                             ★changed(2)
.OUT_START  <- as.Date("2005-01-01")               # 고정 축(기간 2005-01-01~) — 이 날 이후 월말만 발행
.DIAG_D     <- c(5L, 10L, 21L, 42L, 63L, 84L, 126L, 189L, 252L, 504L)   # 진단 전용 D 격자(거래일)      ★changed(9)
.DIAG_GRP   <- c("Institutional", "Foreign", "Individual")              # 진단 전용 거래주체(순매수대금)  ★changed(9)

# =============================================================================
# 1. 일간 패널 → 행렬 (행 = 시장 거래일 · 열 = K200∪KQ150 에 한 번이라도 속한 종목)
#    Close = 수정주가 (compute_liquidity.R:36-63 · krx_build_rawdata.R:113-114 규약) · Vol = 주식수 거래량(진단 전용)
# =============================================================================
.has_vol <- "Vol" %in% names(RAWDATA)                                        # ★changed(8)(9)
.cols <- c(.REQ, if (.has_vol) "Vol")
.rd <- RAWDATA[is.finite(Close) & Close > 0, .cols, with = FALSE]           # ★changed(8) 종가 유한·>0 행만
.rd[, Ticker := as.character(Ticker)]
.rd[, Close := as.numeric(Close)]
if (.has_vol) .rd[, Vol := as.numeric(Vol)] else .rd[, Vol := NA_real_]
.rd[, MEM := (K200 == TRUE | KQ150 == TRUE) %in% TRUE]                      # ★changed(1) 러너 .apply_universe 와 같은 술어
.rd[, c("K200", "KQ150") := NULL]
if (!inherits(.rd$Date, "Date")) .rd[, Date := as.Date(Date)]
setorder(.rd, Ticker, Date)
.ndup <- sum(duplicated(.rd, by = c("Ticker", "Date")))
if (.ndup > 0L) {
  cat(sprintf("%s (Ticker,Date) 중복 %d행 — 첫 행만 유지\n", .TAG, .ndup))               # ★changed(8)
  .rd <- unique(.rd, by = c("Ticker", "Date"))
}
.CAL <- sort(unique(.rd$Date))                     # 시장 거래일 달력(전 종목 통합 · 1998 이전 토요장 포함)  ★changed(6)
.nT  <- length(.CAL)
.TK  <- sort(unique(.rd$Ticker[.rd$MEM]))          # 한 번이라도 구성종목이었던 종목 — 비구성 종목의 s 는 항상 0
.nK  <- length(.TK)
if (.nK < 2L) stop(sprintf("%s K200/KQ150 구성종목이 %d개 — 멤버십 플래그 확인", .TAG, .nK))
.n_all <- nrow(.rd)
.rd <- .rd[Ticker %in% .TK]
.ri <- match(.rd$Date, .CAL); .ci <- match(.rd$Ticker, .TK)
.P  <- matrix(NA_real_, .nT, .nK); .P[cbind(.ri, .ci)] <- .rd$Close
.M  <- matrix(FALSE, .nT, .nK);    .M[cbind(.ri, .ci)] <- .rd$MEM
.TV <- NULL
if (.has_vol) { .TV <- matrix(NA_real_, .nT, .nK); .TV[cbind(.ri, .ci)] <- .rd$Vol * .rd$Close }   # KRW 거래대금(진단 전용)
.n_mem_rows <- sum(.rd$MEM)
rm(.rd, .ri, .ci); gc(verbose = FALSE)
cat(sprintf("%s 일간 행 %d → 구성종목 이력 %d종 %d행(구성일 %d행) · 달력 %d거래일 (%s ~ %s) · Vol 열 %s\n",
            .TAG, .n_all, .nK, sum(is.finite(.P)), .n_mem_rows, .nT, as.character(.CAL[1L]), as.character(.CAL[.nT]),
            if (.has_vol) "있음(진단 전용)" else "없음(진단의 value 변형 생략)"))

# =============================================================================
# 2. 모멘텀 신호 원값 — Carhart(1997) PR1YR / FF prior 2-12: P[t−21] / P[t−252] − 1 (거래일 격자 · 매일 갱신)  ★changed(2)
#    두 끝점이 그날 관측돼야 정의(채움 0건) · 배당 미포함(수정주가 비율)
# =============================================================================
if (.nT <= .MOM_LONG + 1L) stop(sprintf("%s 달력 %d거래일 — 모멘텀 정의역(%d) 부족", .TAG, .nT, .MOM_LONG))
.MOM <- matrix(NA_real_, .nT, .nK)
.r0  <- .MOM_LONG + 1L
.MOM[.r0:.nT, ] <- .P[(.r0 - .MOM_SKIP):(.nT - .MOM_SKIP), , drop = FALSE] /
                   .P[1L:(.nT - .MOM_LONG), , drop = FALSE] - 1

# =============================================================================
# 3. 신호 s_{i,t} — 그날 구성종목 가운데 모멘텀이 정의된 종목의 횡단면 순위(동률 = 평균) → 중심화 → 다리 총합 1  ★changed(4)
#    순위 밖(비구성·미정의) = 0 (이상적 보유 없음). 양(+) 쪽이 비면(전원 동률) 그날 s = 0.
# =============================================================================
.rank_signal <- function(x) {          # x = 유한 벡터(길이 ≥ 2) → 중심화 순위 / 양쪽 합 (양쪽 합 0 이면 전부 0)
  n   <- length(x)
  rc  <- frank(x, ties.method = "average") - (n + 1) / 2
  pos <- sum(rc[rc > 0])
  if (!(pos > 0)) return(numeric(n))
  rc / pos
}
local({                                # 양성 대조 — 고정 입력에서 순위·중심화·스케일·동률·퇴화 처리 검산(실패 = 중단)
  s4 <- .rank_signal(c(3, 1, 2, 2))
  if (!isTRUE(all.equal(s4, c(1, -1, 0, 0)))) stop(sprintf("%s 순위 신호 검산 실패(동률 입력)", .TAG))
  if (!isTRUE(all.equal(.rank_signal(c(2, 2, 2)), c(0, 0, 0)))) stop(sprintf("%s 순위 신호 검산 실패(퇴화 입력)", .TAG))
  s6 <- .rank_signal(c(6, 5, 4, 3, 2, 1))
  if (abs(sum(s6[s6 > 0]) - 1) > 1e-12 || abs(sum(s6[s6 < 0]) + 1) > 1e-12 || s6[1L] <= s6[2L])
    stop(sprintf("%s 순위 신호 검산 실패(다리 합·단조)", .TAG))
})
.S <- matrix(0, .nT, .nK)
.N_RANK <- integer(.nT)
for (t in seq_len(.nT)) {
  ok <- .M[t, ] & is.finite(.MOM[t, ])
  n  <- sum(ok)
  .N_RANK[t] <- n
  if (n < 2L) next
  .S[t, ok] <- .rank_signal(.MOM[t, ok])
}

# =============================================================================
# 4. 식(1) — π_{i,t} = Σ_{t'≤t} A s_{i,t'} exp(−(t−t')/D) 를 재귀로: π_t = λ π_{t−1} + A s_t, π_0 = 0 (달력 첫날)  ★changed(3)(4)(5)
# =============================================================================
.PI  <- matrix(0, .nT, .nK)
.acc <- numeric(.nK)
for (t in seq_len(.nT)) {
  .acc <- .LAMBDA * .acc + .A_SCALE * .S[t, ]
  .PI[t, ] <- .acc
}
local({                                # 양성 대조 — 재귀 π 가 식(1) 의 명시합과 일치하는지(가장 활동적인 종목 · 달력 마지막 날)
  j  <- order(-colSums(abs(.S)))[1L]
  t  <- .nT
  ex <- sum(.A_SCALE * .S[1L:t, j] * exp(-(t - seq_len(t)) / .D_DAYS))
  if (!is.finite(ex) || abs(ex - .PI[t, j]) > 1e-9)
    stop(sprintf("%s EMA 재귀가 식(1) 명시합과 불일치 (%.6e vs %.6e)", .TAG, ex, .PI[t, j]))
  cat(sprintf("%s 검산 통과 — 순위 신호(고정 입력 3종) · 식(1) 명시합 vs 재귀 |차| %.1e (종목 %s · %s) · D %d거래일 · λ %.5f · A %.5f\n",
              .TAG, abs(ex - .PI[t, j]), .TK[j], as.character(.CAL[t]), .D_DAYS, .LAMBDA, .A_SCALE))
})

# =============================================================================
# 5. 발행 — 달력월 마지막 거래일의 π 스냅샷(하네스 집행 = 익월 첫 거래일 · 보유 1개월)  ★changed(5)(6)(7)
#    마지막 달력월(부분월 가능)은 제외 · 2005-01 이후만 · 행 = 그날 구성종목 ∧ π ≠ 0
# =============================================================================
.YM <- format(.CAL, "%Y-%m")
.me <- which(!duplicated(.YM, fromLast = TRUE))
.me <- .me[.YM[.me] != .YM[.nT]]
.me <- .me[.CAL[.me] >= .OUT_START]
if (!length(.me)) stop(sprintf("%s 발행 대상 월말 0 — RAWDATA 날짜 범위 확인", .TAG))

.rows_p <- vector("list", length(.me)); .rows_f <- vector("list", length(.me)); .dg <- vector("list", length(.me))
.prev_w <- NULL
for (k in seq_along(.me)) {
  t   <- .me[k]
  ok  <- .M[t, ] & (.PI[t, ] != 0)
  w   <- .PI[t, ok]; tk <- .TK[ok]
  cur <- setNames(w, tk)
  to  <- if (is.null(.prev_w)) sum(abs(cur)) else {
    u <- union(names(.prev_w), names(cur))
    a <- cur[u];     a[is.na(a)] <- 0
    b <- .prev_w[u]; b[is.na(b)] <- 0
    sum(abs(a - b))
  }
  .prev_w <- cur
  .dg[[k]] <- data.table(Date = .CAL[t], N = length(w), nL = sum(w > 0), nS = sum(w < 0),
                         GL = sum(w[w > 0]), GS = -sum(w[w < 0]), n_rank = .N_RANK[t],
                         n_mem = sum(.M[t, ]), to = to)
  if (length(w) == 0L) next
  .rows_f[[k]] <- data.table(Date = .CAL[t], Ticker = tk, Score = w)
  .rows_p[[k]] <- data.table(Date = .CAL[t], Ticker = tk, Weight = w, Leg = ifelse(w > 0, "long", "short"))
}

# =============================================================================
# 6. 조립 · 검산 · 요약 (구성 요약 — 성과 수치 선언 아님. 등급은 계약이 낸다)
# =============================================================================
PORTFOLIO <- rbindlist(.rows_p, use.names = TRUE)
FACTORS   <- rbindlist(.rows_f, use.names = TRUE)
if (!nrow(PORTFOLIO)) stop(sprintf("%s PORTFOLIO 행 0 — 구성종목·모멘텀 정의역 확인", .TAG))
setorder(PORTFOLIO, Date, Leg, Ticker)
setorder(FACTORS, Date, Ticker)
if (anyDuplicated(PORTFOLIO, by = c("Date", "Ticker")) > 0L) stop(sprintf("%s PORTFOLIO (Date,Ticker) 중복", .TAG))
if (anyDuplicated(FACTORS, by = c("Date", "Ticker")) > 0L)   stop(sprintf("%s FACTORS (Date,Ticker) 중복", .TAG))
if (!all(is.finite(PORTFOLIO$Weight))) stop(sprintf("%s Weight 비유한값 %d건", .TAG, sum(!is.finite(PORTFOLIO$Weight))))
if (any(PORTFOLIO$Weight == 0))        stop(sprintf("%s Weight 0 행 %d건", .TAG, sum(PORTFOLIO$Weight == 0)))
.DG  <- rbindlist(.dg, use.names = TRUE)
.chk <- PORTFOLIO[, .(gl = sum(Weight[Weight > 0]), gs = -sum(Weight[Weight < 0])), by = Date]
.one_leg <- .chk[gl <= 0 | gs <= 0]
.ext <- rbindlist(lapply(.me, function(t) {
  ok <- .M[t, ] & is.finite(.MOM[t, ])
  if (!any(ok)) return(NULL)
  data.table(Date = .CAL[t], Ticker = .TK[ok], mom = .MOM[t, ok])
}), use.names = TRUE)
.ext_txt <- if (nrow(.ext)) {
  .ext <- .ext[order(-abs(mom))]
  .ext <- .ext[seq_len(min(5L, nrow(.ext)))]
  paste(sprintf("%s %s %+.0f%%", as.character(.ext$Date), .ext$Ticker, 100 * .ext$mom), collapse = " · ")
} else "없음(발행 월말에 모멘텀 정의 종목 0)"
.mins <- as.numeric(difftime(Sys.time(), .t0, units = "mins"))
cat(sprintf("%s adapted(기전 = 논문 §II.A 식(1)(2) 그대로: s = 12-1개월 과거수익 횡단면 순위(중심화 · 다리 합 1) → π = EMA(D = %d개월 = %d거래일 · λ %.5f · A %.5f) → 보유 ∝ π 롱숏 전 유니버스): 유니버스 K200∪KQ150 · 월말 스냅샷만 집행(하네스 월간) · 유동성·가격 스크린 없음 · 팩터 DB 미사용 · 크라우딩 측정 = 진단 전용\n",
            .TAG, .D_MONTHS, .D_DAYS, .LAMBDA, .A_SCALE))
cat(sprintf("  발행 %d개월 (%s ~ %s) · 행 없는 달 %d · 한쪽 다리 없는 달 %d · 구성종목 %d~%d(중앙 %d) · 순위 대상 %d~%d · 보유 N %d~%d(중앙 %d)\n",
            nrow(.DG), as.character(min(.DG$Date)), as.character(max(.DG$Date)), sum(.DG$N == 0L), nrow(.one_leg),
            min(.DG$n_mem), max(.DG$n_mem), as.integer(median(.DG$n_mem)), min(.DG$n_rank), max(.DG$n_rank),
            min(.DG$N), max(.DG$N), as.integer(median(.DG$N))))
cat(sprintf("  다리 총노출 GL %.3f~%.3f(중앙 %.3f) / GS %.3f~%.3f(중앙 %.3f) — A 상수라 1 미만(부호 전환 상쇄 · changed(4)) · 월간 Σ|Δw| 평균 %.3f(첫 달 제외)\n",
            min(.DG$GL), max(.DG$GL), median(.DG$GL), min(.DG$GS), max(.DG$GS), median(.DG$GS),
            if (nrow(.DG) > 1L) mean(.DG$to[-1L]) else NA_real_))
cat(sprintf("  |12-1 모멘텀| 극단 5건(원천 이음매 결함이 남아 있으면 여기 드러난다): %s\n", .ext_txt))
cat(sprintf("  PORTFOLIO %d행 · FACTORS %d행 · 고정 축 25 초과(전 유니버스 보유)는 논문 정의상 · engine_direct 라 러너가 자르지 않는다 · %.1f분 · 러너 사양 = FIDELITY 파일 portfolio_spec(engine_direct) · commission_paper = null(논문 bps 무명시 → gross 병기)\n",
            nrow(PORTFOLIO), nrow(FACTORS), .mins))

# =============================================================================
# 7. 크라우딩 진단 — 논문의 원래 산출(§III · Fig.3 · Fig.4)을 KRX 거래주체 순매수대금(Ancerno 대응)으로 재현  ★changed(9)
#    ★산출물 확정 후 실행 · 어떤 값도 PORTFOLIO/FACTORS 로 돌아가지 않는다 · 전략의 D(63)는 §0 에서 이미 고정.
#    I_sign = sign(순매수대금) (식 8 형) · I_value = 순매수대금 / (Vol×Close) (식 4 형) · Δπ^{(D)} = 식(2) · 구성일만
#    상관 = 종목별 시계열 상관의 평균(논문 'averaged over all the stocks') ± 횡단면 SE(논문의 6개월 블록 재표집 대역이 아님) · 괄호 = 풀링
#    수익-신호 상관(Fig.3 하단 = '전략 평균 이익')은 성과 수치라 계산하지 않는다(계약 소관).
# =============================================================================
.colcor <- function(X, Y, W) {         # 열별 피어슨 상관(마스크 W · 유한 쌍만) + 풀링 상관 — 벡터화(루프 0)
  W <- W & is.finite(X) & is.finite(Y)
  X[!W] <- 0; Y[!W] <- 0
  n   <- colSums(W)
  Sx  <- colSums(X);     Sy  <- colSums(Y)
  Sxx <- colSums(X * X); Syy <- colSums(Y * Y); Sxy <- colSums(X * Y)
  vx  <- n * Sxx - Sx * Sx; vy <- n * Syy - Sy * Sy
  r   <- (n * Sxy - Sx * Sy) / sqrt(vx * vy)
  r[!(n >= 2) | !(vx > 0) | !(vy > 0)] <- NA_real_
  N  <- sum(n); TX <- sum(Sx); TY <- sum(Sy); TXX <- sum(Sxx); TYY <- sum(Syy); TXY <- sum(Sxy)
  pv <- (N * TXX - TX * TX) * (N * TYY - TY * TY)
  pooled <- if (N >= 2 && is.finite(pv) && pv > 0) (N * TXY - TX * TY) / sqrt(pv) else NA_real_
  list(r = r, n = n, pooled = pooled)
}
.crowding_diag <- function() {
  if (!exists("load_investor", mode = "function")) {
    cat(sprintf("%s 진단 생략 — load_investor() 부재(하네스 미적재)\n", .TAG)); return(invisible(NULL)) }
  inv_path <- if (exists("INVESTOR_CACHE")) file.path(get("INVESTOR_CACHE"), "investor_wide.parquet") else ""
  if (!nzchar(inv_path) || !file.exists(inv_path)) {
    cat(sprintf("%s 진단 생략 — 수급 패널 부재(%s)\n", .TAG, inv_path)); return(invisible(NULL)) }
  inv <- load_investor("wide")
  if (is.null(inv) || !nrow(inv)) { cat(sprintf("%s 진단 생략 — 수급 패널 0행\n", .TAG)); return(invisible(NULL)) }
  inv <- as.data.table(inv)
  grp <- intersect(.DIAG_GRP, names(inv))
  if (!length(grp) || !all(c("Date", "Ticker") %in% names(inv))) {
    cat(sprintf("%s 진단 생략 — 수급 패널 열 불일치: %s\n", .TAG, paste(names(inv), collapse = ","))); return(invisible(NULL)) }
  inv <- inv[, c("Date", "Ticker", grp), with = FALSE]
  inv[, Ticker := as.character(Ticker)]
  if (!inherits(inv$Date, "Date")) inv[, Date := as.Date(Date)]
  inv <- inv[Ticker %in% .TK & Date %in% .CAL]
  if (!nrow(inv)) {
    cat(sprintf("%s 진단 생략 — 수급 패널과 구성종목·달력의 교집합 0 (Ticker 표기 불일치?)\n", .TAG)); return(invisible(NULL)) }
  win <- which(.CAL >= min(inv$Date) & .CAL <= max(inv$Date))
  win <- win[win > 1L]
  nW  <- length(win)
  if (nW < 2L) { cat(sprintf("%s 진단 생략 — 창 %d일\n", .TAG, nW)); return(invisible(NULL)) }
  ri   <- match(inv$Date, .CAL[win]); ci <- match(inv$Ticker, .TK)
  keep <- !is.na(ri) & !is.na(ci)
  Wm   <- .M[win, , drop = FALSE]
  IM   <- list()
  for (g in grp) {
    X <- matrix(NA_real_, nW, .nK)
    X[cbind(ri[keep], ci[keep])] <- as.numeric(inv[[g]])[keep]
    IM[[paste(g, "sign")]] <- sign(X)
    if (!is.null(.TV)) IM[[paste(g, "value")]] <- X / .TV[win, , drop = FALSE]
  }
  rm(X)
  yr  <- as.integer(format(.CAL[win], "%Y")); yrs <- sort(unique(yr))
  key <- if ("Institutional sign" %in% names(IM)) "Institutional sign" else names(IM)[1L]
  out <- list(); yearly <- list()
  for (dd in .DIAG_D) {
    lam <- exp(-1 / dd); a <- 1 - lam
    acc <- numeric(.nK); PD <- matrix(0, .nT, .nK)
    for (t in seq_len(.nT)) { acc <- lam * acc + a * .S[t, ]; PD[t, ] <- acc }
    dPi <- PD[win, , drop = FALSE] - PD[win - 1L, , drop = FALSE]
    rm(PD)
    for (nm in names(IM)) {
      cc  <- .colcor(IM[[nm]], dPi, Wm)
      nst <- sum(is.finite(cc$r))
      out[[length(out) + 1L]] <- data.table(D = dd, pair = nm, mean_r = mean(cc$r, na.rm = TRUE),
                                            se = if (nst > 1L) sd(cc$r, na.rm = TRUE) / sqrt(nst) else NA_real_,
                                            n_stocks = nst, pooled = cc$pooled, n_obs = sum(cc$n))
    }
    for (y in yrs) {
      rows <- which(yr == y)
      cc <- .colcor(IM[[key]][rows, , drop = FALSE], dPi[rows, , drop = FALSE], Wm[rows, , drop = FALSE])
      yearly[[length(yearly) + 1L]] <- data.table(year = y, D = dd, mean_r = mean(cc$r, na.rm = TRUE),
                                                  n_stocks = sum(is.finite(cc$r)))
    }
  }
  OUT <- rbindlist(out, use.names = TRUE); YR <- rbindlist(yearly, use.names = TRUE)
  cat(sprintf("%s ── 크라우딩 진단(논문 §III Fig.3 대응 · Ancerno → KRX 거래주체 순매수대금 · 산출물 미사용) ──\n", .TAG))
  cat(sprintf("  창 %s ~ %s (%d거래일) · 종목 %d · 쌍 = %s · 값 = 종목별 상관 평균 %% ± 횡단면 SE (풀링 %%) n = 종목 수 · 논문(미국): 메타오더 +≈1%% @ D 4~6개월 · 체결부호 −≈1%% @ 3~4개월\n",
              as.character(.CAL[win[1L]]), as.character(.CAL[win[nW]]), nW, length(unique(inv$Ticker)),
              paste(names(IM), collapse = " / ")))
  for (dd in .DIAG_D) {
    sub <- OUT[D == dd]
    cat(sprintf("  D %3d(%4.1f개월): %s\n", dd, dd / .DAYS_MONTH,
                paste(sprintf("%s %+.2f±%.2f (%+.2f) n%d", sub$pair, 100 * sub$mean_r, 100 * sub$se,
                              100 * sub$pooled, sub$n_stocks), collapse = " · ")))
  }
  pk <- YR[, .SD[order(-abs(mean_r))[1L]], by = year]
  cat(sprintf("  연도별 argmax_D |상관| (%s · Fig.4 형 · 보고용이지 선택 아님): %s\n", key,
              paste(sprintf("%d D%d %+.2f", pk$year, pk$D, 100 * pk$mean_r), collapse = " · ")))
  invisible(NULL)
}
.diag_res <- tryCatch(.crowding_diag(),
                      error = function(e) cat(sprintf("%s 진단 실패(비치명 — 산출물 무영향): %s\n", .TAG, conditionMessage(e))))

rm(.P, .MOM, .S, .PI, .M, .TV); gc(verbose = FALSE)
PORTFOLIO <- PORTFOLIO[, .(Date, Ticker, Weight, Leg)]
FACTORS   <- FACTORS[, .(Date, Ticker, Score)]
