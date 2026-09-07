# =============================================================================
# engine.R — RP_AUTO_1707_05552  (재구현 2판 · 2026-09-07 · 1판 = engine.rejected1.R)
# Huai-Long Shi · Wei-Xing Zhou, "Wax and wane of the cross-sectional momentum and
#   contrarian effects: Evidence from the Chinese stock markets"
#   arXiv:1707.05552 (2017)  https://arxiv.org/abs/1707.05552
#   원문 2-source(이 세션): arxiv.org/html/1707.05552v1 (LaTeXML 전문) + r.jina.ai 프록시(PDF 텍스트)
#
# ★라벨(adapted)·변경 전수 신고·러너 사양의 정본 = FIDELITY.json. 이 주석은 아무것도 결정하지 않는다.
#   코드 옆 ★changed(n) 표식 = FIDELITY.json changed 의 항목 번호.
#
# 구현 = 논문 1차 설계(J ∈ {1,12,24,36,48,60} · K=1)의 CSCON 포트폴리오 1칸: J=1 · K=1 · 스킵 1개월.
#   §2 Methodology 축자:
#   "for the current month t, individual stocks are ranked according to their historical performance
#    during the previous J months. The winner refers to the decile group with the highest past average
#    return and the loser is the decile group with the lowest past average return."
#   "By longing the loser (winner) and shorting the winner (loser), the CSCON (CSMOM) portfolio is
#    constructed at the beginning of each month during the whole sample period."
#   "we follow the common approach to skip one month between estimation period and the holding period"
#   "K-month buy-and-hold return is obtained by longing or shorting the portfolio formed at the month t
#    and then held for K months"  (Ref [25] 비중첩 · K=1 = 매월 재구성)
#   §3 Data sets: "the dividend-adjusted and split-adjusted monthly returns for all A-share individual
#    stocks" — 종목 선별·유동성·최소관측 규칙 없음.
#
# 2판에서 바뀐 것(1판 감사 지적 반영 — 상세 = FIDELITY.json audit_round1_response):
#   · 유동성 스크린(adv20 ≥ 2e8) 제거 — 논문에 필터 없음 · SOT 충실구현 행 = 논문 우선(paper_faithful).
#     그래서 Vol 열을 읽지 않는다. 유니버스 교체(K200∪KQ150) 외 어떤 스크린도 없다.
#   · 칸 선택 근거 정정(changed(3)) · 원문 경로 정정(changed(14)) · 배당 미조정 확정(changed(6)).
#
# 산출: PORTFOLIO(Date, Ticker, Weight, Leg) — 패자 데실 롱(EW Σ=+1) / 승자 데실 숏(EW Σ=−1)
#       FACTORS(Date, Ticker, Score)          — 전 순위 대상 종목 · Score = −(직전 J개월 평균 월수익) = CSCON 방향
#
# PIT(C1~C15) 구조 보장: 시그널 d = 달 m 의 마지막 거래일. 형성 = 달 m−J .. m−1 의 월수익(달 m 스킵)
#   → 모든 창의 종점 ≤ 달 m−1 말 < d. 집행 = 달 m+1 첫 거래일(러너 get_execution_date). 전 표본 통계 0건 ·
#   멤버십 = d 당일 RAWDATA 행의 K200|KQ150 플래그(러너 .apply_universe 와 같은 술어, C6) ·
#   재무 패널·팩터 DB·오버레이·외부 데이터·난수 미사용.
# =============================================================================

suppressWarnings(suppressMessages({
  library(data.table)
}))

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
.REQ <- c("Date", "Ticker", "Close", "K200", "KQ150")   # Vol 은 읽지 않는다 — 유동성 스크린 없음 ★changed(2)
if (!all(.REQ %in% names(RAWDATA)))
  stop(sprintf("[RP_AUTO_1707_05552] RAWDATA 필수 열 부재: %s",
               paste(setdiff(.REQ, names(RAWDATA)), collapse = ", ")))

# =============================================================================
# 0. 상수 — 출처는 논문 명시값 하나뿐. 그 외 규약은 전부 FIDELITY.json changed 에 신고.
# =============================================================================
.J     <- 1L     # 논문 1차 설계 J ∈ {1,12,24,36,48,60} 중 선택 칸 = 1  ★changed(3): 선택 규칙·논문 내 위상 정직 기재
.K     <- 1L     # 논문 1차 설계 K = 1 (K>1 은 비중첩 buy-and-hold 재구성이 필요 — 이 엔진 밖)
.SKIP  <- 1L     # 논문 §2: 형성과 보유 사이 1개월 스킵 (J 무관 일반 규정)
.NGRP  <- 10L    # 논문 §2: decile group
if (.K != 1L) stop("[RP_AUTO_1707_05552] 이 엔진은 K=1 만 구현한다 (K>1 은 비중첩 buy-and-hold 재구성이 필요)")
if (.J < 1L)  stop("[RP_AUTO_1707_05552] J >= 1 필요")
.ym <- function(mi) sprintf("%d-%02d", (mi - 1L) %/% 12L, (mi - 1L) %% 12L + 1L)

# =============================================================================
# 1. 일간 패널 → 월 인덱스 · 월말 격자 · 멤버십   (RAWDATA 비파괴 — 러너가 재사용)
# =============================================================================
.t0 <- Sys.time()
.rd <- RAWDATA[is.finite(Close) & Close > 0,                                  # ★changed(10) 종가 유한·>0 행만
               .(Date, Ticker = as.character(Ticker), Close,
                 MEM = (K200 == TRUE | KQ150 == TRUE) %in% TRUE)]             # ★changed(1) 러너 .apply_universe 와 같은 술어
if (!inherits(.rd$Date, "Date")) .rd[, Date := as.Date(Date)]
setorder(.rd, Ticker, Date)
.ndup <- sum(duplicated(.rd, by = c("Ticker", "Date")))
if (.ndup > 0L) {
  cat(sprintf("[RP_AUTO_1707_05552] (Ticker,Date) 중복 %d행 — 첫 행만 유지\n", .ndup))   # ★changed(10)
  .rd <- unique(.rd, by = c("Ticker", "Date"))
}
.rd[, MI := year(Date) * 12L + month(Date)]

# 시장 월말 = 그 달력월의 마지막 거래일(전 종목 통합). RAWDATA 의 마지막 달력월은 진행 중(부분월)으로 보고
# 시그널에서 제외한다(집행일이 없다).  ★changed(8)
.me <- .rd[, .(MEnd = max(Date)), by = MI]
setorder(.me, MI)
.MI_LAST <- max(.me$MI)
.me <- .me[MI < .MI_LAST]
if (nrow(.me) == 0L) stop("[RP_AUTO_1707_05552] 완결 월 0개 — RAWDATA 날짜 범위 확인")

# 종목별 월간 종가 = 그 달력월 안의 마지막 관측 종가 (정렬 Ticker, Date 위에서 그룹의 마지막 행)  ★changed(5)
.mp <- .rd[, .(P = Close[.N]), by = .(Ticker, MI)]

# 시그널일 적격 = d 당일 행 존재 ∧ K200|KQ150 플래그. 그 외 스크린 없음 —
# 유동성·거래대금·가격·상장기간·최소관측 전부 없음(논문에도 없다).  ★changed(1)(2)
.rd[, MEnd := .me$MEnd[match(MI, .me$MI)]]
.el <- .rd[!is.na(MEnd) & Date == MEnd & MEM, .(MI, Ticker)]
.EL <- split(.el$Ticker, .el$MI)
.n_rd <- nrow(.rd)
rm(.rd, .el); gc(verbose = FALSE)

# 월간 종가 행렬 P[월, 종목] → 월수익 R[i, ] = P[i, ] / P[i−1, ] − 1
# (연속 두 달의 월말 종가가 다 있어야 정의 · 채우지 않음 · 배당 미조정 가격수익률)  ★changed(5)(6)
.wide <- dcast(.mp, MI ~ Ticker, value.var = "P")
setorder(.wide, MI)
.MIs <- .wide$MI
if (any(diff(.MIs) != 1L))
  stop("[RP_AUTO_1707_05552] 월 인덱스가 연속이 아님 — 거래 데이터가 통째로 빈 달이 있다")   # ★changed(10)
.TK <- setdiff(names(.wide), "MI")
.P  <- as.matrix(.wide[, .TK, with = FALSE])
rm(.wide, .mp)
.NR <- nrow(.P)
if (.NR < .J + .SKIP + 2L)
  stop(sprintf("[RP_AUTO_1707_05552] 월 %d개 — J=%d·스킵 %d 형성창에 부족", .NR, .J, .SKIP))
.R <- matrix(NA_real_, .NR, ncol(.P), dimnames = list(NULL, .TK))
.R[2L:.NR, ] <- .P[2L:.NR, , drop = FALSE] / .P[1L:(.NR - 1L), , drop = FALSE] - 1
rm(.P); gc(verbose = FALSE)
cat(sprintf("[RP_AUTO_1707_05552] 월간 종가 패널 %d개월 (%s ~ %s) × %d종 | 일간 행 %d | 마지막 부분월 %s 시그널 제외 | 시그널 월말 %d개 | 적격 집합 있는 달 %d\n",
            .NR, .ym(min(.MIs)), .ym(max(.MIs)), length(.TK), .n_rd, .ym(.MI_LAST), nrow(.me), length(.EL)))

# =============================================================================
# 2. 월별 루프 — 형성 = 달 m−J .. m−1 (달 m 스킵) 의 월수익 산술평균(논문 'past average return')
#    → 오름차순 10분위 → 그룹 1(패자) 롱 EW Σ=+1 · 그룹 10(승자) 숏 EW Σ=−1
# =============================================================================
.rows_p <- list(); .rows_f <- list(); .diag <- list()
.n_nouniv <- 0L; .n_small <- 0L; .n_warm <- 0L
for (r in seq_len(nrow(.me))) {
  mi <- .me$MI[r]; d <- .me$MEnd[r]
  i  <- match(mi, .MIs)
  if (is.na(i)) next
  r2 <- i - .SKIP                 # 형성 마지막 행 = 달 m−1 의 월수익 (달 m = 스킵)  ★changed(8)
  r1 <- r2 - .J + 1L              # 형성 첫 행     = 달 m−J 의 월수익
  if (r1 < 2L) { .n_warm <- .n_warm + 1L; next }        # R[1, ] 은 정의 불가 — 이력 워밍업(기간 선택 아님)  ★changed(9)

  tk <- .EL[[as.character(mi)]]
  if (is.null(tk) || !length(tk)) { .n_nouniv <- .n_nouniv + 1L; next }
  ci <- match(tk, .TK)
  ok <- !is.na(ci)
  tk <- tk[ok]; ci <- ci[ok]
  if (!length(tk)) { .n_nouniv <- .n_nouniv + 1L; next }

  M   <- .R[r1:r2, ci, drop = FALSE]        # J × n 월수익 (행 = 달 m−J .. m−1) — 행 i 이후 접근 0건
  s   <- colMeans(M)                        # 산술평균 · 창 안 결측이 하나라도 있으면 NA (완전 창 요건)  ★changed(5)
  fin <- is.finite(s)
  n_nohist <- sum(!fin)
  tk <- tk[fin]; s <- s[fin]
  N  <- length(tk)
  if (N < .NGRP) { .n_small <- .n_small + 1L; next }   # 10 그룹이 성립하는 최소 횡단면(정의역 · 스크린 아님)  ★changed(7)

  o   <- order(s, tk)                                  # 오름차순 · 동률 = 종목코드(결정론)  ★changed(7)
  grp <- integer(N)
  grp[o] <- as.integer(ceiling(seq_len(N) * .NGRP / N))   # 1 = 패자(최저 평균수익) … 10 = 승자(최고) · 그룹 크기 차 ≤ 1
  lo <- tk[grp == 1L]; wi <- tk[grp == .NGRP]
  nL <- length(lo); nS <- length(wi)
  if (nL < 1L || nS < 1L) { .n_small <- .n_small + 1L; next }

  .rows_p[[length(.rows_p) + 1L]] <- data.table(
    Date = d, Ticker = c(lo, wi),
    Weight = c(rep(1 / nL, nL), rep(-1 / nS, nS)),       # 데실 내 EW · 롱 Σ=+1 / 숏 Σ=−1  ★changed(4)
    Leg = rep(c("long", "short"), c(nL, nS)))
  .rows_f[[length(.rows_f) + 1L]] <- data.table(Date = d, Ticker = tk, Score = -s)   # CSCON 방향(낮은 평균수익 = 높은 Score)  ★changed(12)
  .diag[[length(.diag) + 1L]] <- data.table(
    Date = d, N = N, nL = nL, nS = nS, n_nohist = n_nohist,
    s_lo = mean(s[grp == 1L]), s_wi = mean(s[grp == .NGRP]))
}

# =============================================================================
# 3. 조립 · 검산 · 요약 (구성 요약 — 성과 수치 선언 아님. 등급은 계약이 낸다)
# =============================================================================
if (length(.rows_p) == 0L)
  stop(sprintf("[RP_AUTO_1707_05552] 발행 행 0 — 워밍업 %d · 적격 집합 없는 달 %d · 횡단면 <%d 인 달 %d",
               .n_warm, .n_nouniv, .NGRP, .n_small))
PORTFOLIO <- rbindlist(.rows_p, use.names = TRUE)
setorder(PORTFOLIO, Date, Leg, Ticker)
FACTORS <- rbindlist(.rows_f, use.names = TRUE)
setorder(FACTORS, Date, Ticker)

.chk <- PORTFOLIO[, .(gl = sum(Weight[Weight > 0]), gs = -sum(Weight[Weight < 0])), by = Date]
.bad <- .chk[abs(gl - 1) > 1e-9 | abs(gs - 1) > 1e-9]
if (nrow(.bad) > 0L)
  stop(sprintf("[RP_AUTO_1707_05552] 다리 총노출 검산 실패 %d건 (예: %s gL %.6f / gS %.6f)",
               nrow(.bad), as.character(.bad$Date[1L]), .bad$gl[1L], .bad$gs[1L]))
if (anyDuplicated(PORTFOLIO, by = c("Date", "Ticker")) > 0L)
  stop("[RP_AUTO_1707_05552] PORTFOLIO (Date,Ticker) 중복")
if (anyDuplicated(FACTORS, by = c("Date", "Ticker")) > 0L)
  stop("[RP_AUTO_1707_05552] FACTORS (Date,Ticker) 중복")

.DG <- rbindlist(.diag, use.names = TRUE)
.mins <- as.numeric(difftime(Sys.time(), .t0, units = "mins"))
cat(sprintf("[RP_AUTO_1707_05552] adapted(구조 = 논문 그대로 · 셀 J=%d · K=%d · 스킵 %d개월 · 입력 = 배당 미조정 가격수익률): 직전 %d개월 평균 월수익 오름차순 10분위 · 패자 데실 롱(EW Σ+1) / 승자 데실 숏(EW Σ−1) · 월간 재구성(비중첩) · 유니버스 K200∪KQ150 · 유동성·가격·기타 스크린 없음\n",
            .J, .K, .SKIP, .J))
cat(sprintf("  리밸 %d개월 (%s ~ %s) · 워밍업 스킵 %d · 적격 집합 없는 달 %d · 횡단면 <%d 인 달 %d · 횡단면 N %d~%d(중앙 %d) · 이력부족 제외 평균 %.1f종/월\n",
            nrow(.DG), as.character(min(.DG$Date)), as.character(max(.DG$Date)), .n_warm, .n_nouniv, .NGRP, .n_small,
            min(.DG$N), max(.DG$N), as.integer(median(.DG$N)), mean(.DG$n_nohist)))
cat(sprintf("  롱 %d~%d / 숏 %d~%d종 (합 최대 %d — 고정 축 25 초과는 논문 데실 정의상 · engine_direct 라 러너가 자르지 않는다) · 형성 평균수익 중앙: 패자 %.2f%% / 승자 %.2f%% (신호값 — 성과 아님)\n",
            min(.DG$nL), max(.DG$nL), min(.DG$nS), max(.DG$nS), max(.DG$nL + .DG$nS),
            100 * median(.DG$s_lo), 100 * median(.DG$s_wi)))
cat(sprintf("  PORTFOLIO %d행 · FACTORS %d행 · %.1f분 · 러너 사양 = FIDELITY.json portfolio_spec(engine_direct) · commission_paper = null(논문 비용 무명시 → gross 병기) · 기간 축(2005-01-01~)은 러너가 적용\n",
            nrow(PORTFOLIO), nrow(FACTORS), .mins))

PORTFOLIO <- PORTFOLIO[, .(Date, Ticker, Weight, Leg)]
FACTORS   <- FACTORS[, .(Date, Ticker, Score)]
