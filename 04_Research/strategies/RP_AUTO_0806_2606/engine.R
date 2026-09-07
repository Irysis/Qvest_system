# =============================================================================
# engine.R — RP_AUTO_0806_2606  (재구현 2판 · 2026-09-07 — 1판 engine.rejected1.R 은 충실도 감사 misdeclared)
# "Anomalous Returns in a Neural Network Equity-Ranking Predictor"
#   J.B. Satinover · D. Sornette — arXiv:0806.2606 (2008-06-16)  https://arxiv.org/abs/0806.2606
#
# ★라벨·변경 전수 신고·러너 사양·감사 지적별 조치의 정본 = FIDELITY.json. 이 주석은 아무것도 결정하지 않는다.
#
# 감사 지적 5건 → 이 판의 조치 (FIDELITY.json audit_response 와 동일)
#   [signal-1] 'single hidden layer and recurrence' — recurrence 는 여전히 미구현(원문 미정의). kept 에서 자르지 않고
#              changed(11b) 에 원문 그대로 인용·사유 기재.
#   [signal-2] 표적 ±5SD 절단 — 제거. 표적 = 다음 분기 가격 변화율 원값(학습 분할 평균·SD 아핀 표준화만).
#   [signal-3] 이익 입력 열 — 종목별 '가용한 최근 k번째' 슬롯 → **회계분기 캘린더 정렬 열**(열 j = 직전 종료 분기 − (j−1),
#              전 종목 동일 분기) + **사이클 단위 최종 열 제외**(§3.2, C4 일정에서 파생) + 행 단위 PIT 가용.
#   [portfolio-1] 다리 총노출 — 트랜치는 다리당 k=100·총노출 1.0(검산). 3사이클 합성 북의 상쇄분은 월별 실측 출력
#              (.COMP: gl/gs/net/n_drop), FIDELITY 는 '≈1.0' 대신 정확한 기전과 실측 기대치를 적는다.
#   [portfolio-2] 재정규화 — 존재하지 않는 재정규화 주장 삭제. 러너와 동일 규칙(그 날짜 RAWDATA 행 + 플래그)의 멤버십을
#              엔진이 먼저 적용하고 이탈 비중은 재분배하지 않는다(현금) — 러너 필터는 0행 제거가 되어야 한다.
#
# 산출: PORTFOLIO(Date, Ticker, Weight, Leg) = H100 3사이클 합성 북 · FACTORS(Date, Ticker, Score) = 전 적격 종목 예측.
# PIT(C1~C15)는 구조로 보장 — 시그널 d = 월 마지막 거래일, 집행 = 익월 첫 거래일(러너), 모든 창의 종점 = d(=t−1).
# =============================================================================

suppressWarnings(suppressMessages({
  library(data.table)
}))

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
.REQ <- c("Date", "Ticker", "Close", "Vol", "K200", "KQ150")
if (!all(.REQ %in% names(RAWDATA)))
  stop(sprintf("[RP_AUTO_0806_2606] RAWDATA 필수 열 부재: %s",
               paste(setdiff(.REQ, names(RAWDATA)), collapse = ", ")))

# =============================================================================
# 0. 상수 — 논문값 / 고정 축 / 구현 상수(논문 미명시 — FIDELITY.json changed 전수 신고)
# =============================================================================
.N_LAG     <- 10L      # 논문 §3.2: ten preceding quarterly changes (가격·이익 각각)
.N_TRAINQ  <- 10L      # 논문 §3.5: freshly trained on (ten quarters of) data
.HOLD_M    <- 3L       # 논문 Abstract: held fixed for one quarter · §4.1.1 월간 시작점 3개 → 중첩 트랜치 3개
.N_TOP     <- 100L     # 논문 T100 (선택 칸 = H100)
.N_BOT     <- 100L     # 논문 B100
.EARN_DROP <- 0.30     # 논문 §3.2: 30% of the earnings figures are removed at random before ranking

.SIG_FROM  <- as.Date("2005-01-01")   # 고정 축 시작
.LIQ       <- 2e8                     # adv20(t−1) 하한 KRW — 고정 축

.VAL_FRAC     <- 0.20            # 학습 표본 중 무작위 검증 비율 (논문 'selected a-priori at random' — 비율 미명시)
.HID          <- c(4L, 8L, 16L)  # 은닉 유닛 후보 (논문 GA 로 'exact net architecture' 결정 — 값 미명시)
.N_INIT       <- 5L              # 초기화 횟수 (논문 'multiple initializations' — 횟수 미명시)
.MAX_EPOCH    <- 300L            # 전배치 역전파 최대 에폭 (미명시)
.PATIENCE     <- 20L             # 검증 MSE 무개선 허용 에폭 = 'optimization of training iterations' 의 수치화
.LR           <- 0.01            # 학습률 (미명시)
.MOM          <- 0.9             # 모멘텀 (미명시)
.UNDERFIT_TOL <- 0.02            # 'Under-fitting is greatly preferred': 최소 검증 MSE ×(1+tol) 안의 가장 작은 은닉 수
.MIN_TRAIN    <- 100L            # 학습 표본 하한 (우리 상수 — 미달 월은 트랜치 미형성·출력)
.SEED_BASE    <- 20080616L       # 난수 seed 기저(논문 제출일) + 월 인덱스 → 결정론적 재현

# =============================================================================
# 1. 보조 함수
# =============================================================================
.as_flag <- function(x) {
  if (is.logical(x)) return(x %in% TRUE)
  if (is.numeric(x)) return(is.finite(x) & x != 0)
  toupper(trimws(as.character(x))) %in% c("TRUE", "T", "1", "Y", "YES")
}
.ym <- function(mi) sprintf("%d-%02d", (mi - 1L) %/% 12L, (mi - 1L) %% 12L + 1L)

# 횡단면 순위 → [−1, 1] (논문: 'relative rank scaled around zero' — 범위는 우리 선택). 동률 = 평균 순위. 결측 = 0(중립).
.rank_unit <- function(v) {
  out <- numeric(length(v))
  ok  <- is.finite(v)
  m   <- sum(ok)
  if (m >= 2L) {
    r <- rank(v[ok], ties.method = "average")
    out[ok] <- 2 * (r - 1) / (m - 1) - 1
  }
  out
}
.rank_cols <- function(M) { if (ncol(M) > 0L) for (j in seq_len(ncol(M))) M[, j] <- .rank_unit(M[, j]); M }

# 달력 보조: 월말일 · 분기 인덱스(y*4 + {0:3월,1:6월,2:9월,3:12월}) · 분기말일 · 이익 패널 생산자의 PIT 가용일 규약(C4)
.m_end   <- function(y, m) as.Date(sprintf("%d-%02d-01", y + as.integer(m == 12L), m %% 12L + 1L)) - 1L
.q_of    <- function(y, m) y * 4L + m %/% 3L - 1L                 # 달 m 까지 종료된 가장 최근 분기
.q_end   <- function(q) .m_end(q %/% 4L, 3L * (q %% 4L + 1L))
.q_sched <- function(q) {                                         # parse_fundamental_xlsx.R:205 규약 재도출
  mo <- 3L * (q %% 4L + 1L)
  fifelse(mo == 12L, as.Date(sprintf("%d-03-31", q %/% 4L + 1L)), .q_end(q) + 45L)
}

# =============================================================================
# 2. 일간 패널 → 시점 멤버십(러너 규칙 동일) · 유동성(t−1) · 월말 종가 패널   (RAWDATA 비파괴 — 러너가 재사용)
# =============================================================================
.t0 <- Sys.time()
.rd <- RAWDATA[is.finite(Close) & Close > 0,
               .(Date, Ticker = as.character(Ticker), Close, TV = Close * Vol,
                 MEM = .as_flag(K200) | .as_flag(KQ150))]
if (!inherits(.rd$Date, "Date")) .rd[, Date := as.Date(Date)]
setorder(.rd, Ticker, Date)
.ndup <- sum(duplicated(.rd, by = c("Ticker", "Date")))
if (.ndup > 0L) {
  cat(sprintf("[RP_AUTO_0806_2606] (Ticker,Date) 중복 %d행 — 첫 행만 유지\n", .ndup))
  .rd <- unique(.rd, by = c("Ticker", "Date"))
}
.rd[, ADV20_L1 := shift(frollmean(TV, 20L, align = "right"), 1L), by = Ticker]   # C10: t−1 유동성(시그널일 제외)
.rd[, TV := NULL]
.rd[, MI := year(Date) * 12L + month(Date)]

# 시장 월말(그 달 마지막 거래일). RAWDATA 의 마지막 달은 진행 중(부분월)으로 보고 제외한다.
.me <- .rd[, .(MEnd = max(Date)), by = MI]
setorder(.me, MI)
.MI_LAST <- max(.me$MI)
.me <- .me[MI < .MI_LAST]
if (nrow(.me) == 0L) stop("[RP_AUTO_0806_2606] 완결 월 0개 — RAWDATA 날짜 범위 확인")

.rs <- .rd[MI < .MI_LAST]
rm(.rd); gc(verbose = FALSE)
.rs[, MEnd := .me$MEnd[match(MI, .me$MI)]]

# 시점 멤버십 = 러너 .apply_universe 와 같은 술어: 그 날짜(월말 d)에 RAWDATA 행이 있고 K200|KQ150 플래그가 참 (C6)
.memd <- .rs[Date == MEnd & MEM, .(MI, Ticker)]

# 종목별 월간 마지막 관측(종가·유동성·월말일 관측 여부) — 한 종목·한 달에 한 행
.n <- nrow(.rs)
.lastrow <- c(.rs$Ticker[-1L] != .rs$Ticker[-.n] | .rs$MI[-1L] != .rs$MI[-.n], TRUE)
.mp <- .rs[.lastrow, .(Ticker, MI, Close, ADV20_L1, OnMEnd = Date == MEnd)]
rm(.rs); gc(verbose = FALSE)

# 형성 적격(시점별): 멤버십(d 당일 행) ∧ adv20(t−1) ≥ 2e8 (C10)
.el <- .mp[OnMEnd & is.finite(ADV20_L1) & ADV20_L1 >= .LIQ, .(MI, Ticker)]
.el <- .el[.memd, on = c("MI", "Ticker"), nomatch = 0L]
.EL   <- split(.el$Ticker, .el$MI)       # 형성 적격 집합
.MEMD <- split(.memd$Ticker, .memd$MI)   # 시점 멤버십(합성 북 행 필터 — 러너와 동일)
rm(.el); gc(verbose = FALSE)

# 월말 종가 행렬 P[월, 종목] → 분기 가격 변화율 QC[i, ] = P[i, ]/P[i−3, ] − 1  (논문: quarterly percent price change)
.wide <- dcast(.mp, MI ~ Ticker, value.var = "Close")
setorder(.wide, MI)
.MIs <- .wide$MI
if (any(diff(.MIs) != 1L))
  stop("[RP_AUTO_0806_2606] 월 인덱스가 연속이 아님 — 거래 데이터가 통째로 빈 달이 있다")
.TK <- setdiff(names(.wide), "MI")
.P  <- as.matrix(.wide[, .TK, with = FALSE])
rm(.wide)
.NR <- nrow(.P)
.QC <- matrix(NA_real_, .NR, ncol(.P), dimnames = list(NULL, .TK))
if (.NR > 3L) .QC[4L:.NR, ] <- .P[4L:.NR, , drop = FALSE] / .P[1L:(.NR - 3L), , drop = FALSE] - 1
rm(.P, .mp); gc(verbose = FALSE)
cat(sprintf("[RP_AUTO_0806_2606] 월말 종가 패널 %d개월 (%s ~ %s) × %d종 | 마지막 부분월 %s 제외 | 멤버십 시점 %d개월 | %.1f분\n",
            length(.MIs), .ym(min(.MIs)), .ym(max(.MIs)), length(.TK), .ym(.MI_LAST), length(.MEMD),
            as.numeric(difftime(Sys.time(), .t0, units = "mins"))))

# =============================================================================
# 3. 분기 이익 패널 (QuantiWise xlsx 분기 → 주당순이익 → 직전 분기 대비 변화율 · 회계분기 캘린더 정렬 · PIT 가용일)
#    이익 = (PretaxIncome − TaxExpense) / ISSD(수정 발행주식수)  ← 논문 VL 분기 EPS 의 KR 대응
#    변화율 g_q = (E_q − E_{q−1}) / |E_{q−1}| (연속 분기만 · 분모 0 = NA)
#    가용일 AVn = max(Factor_Date_q, Factor_Date_{q−1}) — 두 분기가 모두 공표된 뒤에만 입력 (C4 lag)
# =============================================================================
.cache_dir <- local({
  cd <- if (exists("CACHE_DIR", inherits = TRUE)) as.character(get("CACHE_DIR", inherits = TRUE))[1L] else ""
  if (!nzchar(cd)) {
    root <- Sys.getenv("QM_ROOT", "")
    if (!nzchar(root)) root <- Sys.getenv("CLAUDE_PROJECT_DIR", "")
    if (!nzchar(root) && exists("PROJECT_ROOT", inherits = TRUE))
      root <- as.character(get("PROJECT_ROOT", inherits = TRUE))[1L]
    if (nzchar(root)) cd <- file.path(root, ".cache")
  }
  cd
})
if (!nzchar(.cache_dir) || !dir.exists(.cache_dir))
  stop("[RP_AUTO_0806_2606] 캐시 디렉터리를 찾지 못함 (CACHE_DIR / QM_ROOT / CLAUDE_PROJECT_DIR) — 이익 패널 접근 불가라 중단")
.fx_path <- file.path(.cache_dir, "fundamental_xlsx.parquet")
if (!file.exists(.fx_path))
  stop(sprintf("[RP_AUTO_0806_2606] 분기 이익 패널 부재: %s — 논문 입력(이익 변화율)을 지킬 수 없어 중단", .fx_path))
.fx <- as.data.table(arrow::read_parquet(.fx_path,
                                         col_select = c("Ticker", "Item", "Value", "Period_Date", "Factor_Date")))
.fx <- .fx[Item %in% c("PretaxIncome", "TaxExpense", "ISSD") & is.finite(Value)]
if (nrow(.fx) == 0L) stop("[RP_AUTO_0806_2606] 이익 패널에 PretaxIncome/TaxExpense/ISSD 0행")
.fx[, Ticker := as.character(Ticker)]
if (!inherits(.fx$Period_Date, "Date")) .fx[, Period_Date := as.Date(Period_Date, tz = "Asia/Seoul")]
if (!inherits(.fx$Factor_Date, "Date")) .fx[, Factor_Date := as.Date(Factor_Date, tz = "Asia/Seoul")]
.fw <- dcast(.fx, Ticker + Period_Date + Factor_Date ~ Item, value.var = "Value",
             fun.aggregate = function(x) x[1L])
for (.cc in c("PretaxIncome", "TaxExpense", "ISSD")) if (!.cc %in% names(.fw)) .fw[, (.cc) := NA_real_]
.fw[, NI  := fifelse(is.finite(PretaxIncome) & is.finite(TaxExpense), PretaxIncome - TaxExpense, NA_real_)]
.fw[, EPS := fifelse(is.finite(NI) & is.finite(ISSD) & ISSD > 0, NI / ISSD, NA_real_)]
.fw[, QI  := year(Period_Date) * 4L + (month(Period_Date) - 1L) %/% 3L]   # 회계분기 → 달력 분기 인덱스
.fw[, FDn := as.numeric(Factor_Date)]                                     # 가용일(일수) — 패널 생산자 규약이 정본
.fw <- .fw[is.finite(QI) & is.finite(FDn)]
setorder(.fw, Ticker, QI, Period_Date)
.nq_dup <- sum(duplicated(.fw, by = c("Ticker", "QI")))
if (.nq_dup > 0L) {
  cat(sprintf("[RP_AUTO_0806_2606] (Ticker,분기) 중복 %d행(비표준 결산월) — 그 분기의 마지막 Period_Date 만 유지\n", .nq_dup))
  .fw <- .fw[!duplicated(.fw, by = c("Ticker", "QI"), fromLast = TRUE)]
}
.n_sched_mis <- sum(as.numeric(.q_sched(.fw$QI)) != .fw$FDn, na.rm = TRUE)   # 규약 재도출 대조(진단)
setorder(.fw, Ticker, QI)
.fw[, `:=`(EPS_L1 = shift(EPS), QI_L1 = shift(QI), FDn_L1 = shift(FDn)), by = Ticker]
.fw[, G := fifelse(is.finite(EPS) & is.finite(EPS_L1) & EPS_L1 != 0 & (QI - QI_L1) == 1L,
                   (EPS - EPS_L1) / abs(EPS_L1), NA_real_)]
.fw[, AVn := pmax(FDn, FDn_L1)]                              # 두 분기 가용일의 늦은 쪽 (lag 반영)
.EQ <- .fw[is.finite(QI), .(Ticker, QI, G, AVn)]
if (sum(is.finite(.EQ$G)) == 0L) stop("[RP_AUTO_0806_2606] 분기 이익 변화율 0행 — 패널 항목·주식수 확인")
.ET  <- sort(unique(.EQ$Ticker))
.QI0 <- min(.EQ$QI); .QI1 <- max(.EQ$QI); .NQ <- .QI1 - .QI0 + 1L
.GM  <- matrix(NA_real_, length(.ET), .NQ)   # 변화율 [종목 × 달력분기]
.AM  <- .GM                                  # 가용일(일수) [종목 × 달력분기]
.eidx <- cbind(match(.EQ$Ticker, .ET), .EQ$QI - .QI0 + 1L)
.GM[.eidx] <- .EQ$G
.AM[.eidx] <- .EQ$AVn
cat(sprintf(paste0("[RP_AUTO_0806_2606] 이익 패널: 원행 %d → 분기행 %d · 변화율 유한 %d · %d종 · 분기 %s ~ %s · ",
                   "가용일 %s ~ %s · 가용일 규약 재도출 불일치 %d행\n"),
            nrow(.fx), nrow(.EQ), sum(is.finite(.EQ$G)), length(.ET),
            as.character(.q_end(.QI0)), as.character(.q_end(.QI1)),
            as.character(as.Date(min(.EQ$AVn, na.rm = TRUE), origin = "1970-01-01")),
            as.character(as.Date(max(.EQ$AVn, na.rm = TRUE), origin = "1970-01-01")), .n_sched_mis))
rm(.fx, .fw, .EQ, .eidx); gc(verbose = FALSE)

# 시점 d 의 이익 입력 행렬 — 열 j ↔ 달력 분기 q0 − (j−1) (전 종목 동일 분기 = 논문의 고정 열),
#   행 단위 PIT: 그 종목의 가용일 AVn ≤ d 인 값만, 아니면 NA. cols = 이 사이클에서 쓰는 열 번호(1..10 또는 2..10).
.earn_mat <- function(dnum, tk, q0, cols) {
  M  <- matrix(NA_real_, length(tk), length(cols))
  ri <- match(tk, .ET)
  ok <- which(!is.na(ri))
  if (length(ok) == 0L) return(M)
  rr <- ri[ok]
  for (jj in seq_along(cols)) {
    ci <- q0 - (cols[jj] - 1L) - .QI0 + 1L
    if (ci < 1L || ci > .NQ) next
    g <- .GM[rr, ci]
    a <- .AM[rr, ci]
    g[is.na(a) | a > dnum] <- NA_real_
    M[ok, jj] <- g
  }
  M
}

# 논문 §3.2 '최종 이익 열은 그 사이클에서 가용 불가면 입력에서 통째로 제외' — 사이클 = 월간 시작점(월 %% 3).
#   C4 가용일 규약(Q1~Q3 +45일 · Q4 익년 3/31)에서 파생: 달 m 의 월말에 직전 종료 분기 q0(m)의 이익이 규약상 가용한가.
#   사이클의 네 달 중 하나라도 가용하면 그 사이클은 열을 쓴다(가용하지 않은 달의 값은 행 단위 PIT 로 NA→0).
.ref_y <- year(.me$MEnd[1L]) + 1L
.U1_MONTH <- vapply(1:12, function(m) {
  d <- .m_end(.ref_y, m)
  as.numeric(.q_sched(.q_of(.ref_y, m))) <= as.numeric(d)
}, logical(1L))
.U1_CYCLE <- vapply(0:2, function(r) any(.U1_MONTH[which((1:12) %% 3L == r)]), logical(1L))   # 인덱스 = 월 %% 3 + 1
cat(sprintf("[RP_AUTO_0806_2606] 최종 이익 열(직전 종료 분기) 규약상 가용 — 1~12월: %s | 사이클(월%%3 = 0/1/2 → %s) → 입력 열 수 %s\n",
            paste(ifelse(.U1_MONTH, "Y", "n"), collapse = ""),
            paste(ifelse(.U1_CYCLE, "USE", "DROP"), collapse = "/"),
            paste(ifelse(.U1_CYCLE, 2L * .N_LAG, 2L * .N_LAG - 1L), collapse = "/")))

# =============================================================================
# 4. 시점별 입력 행렬 X(s) · 표적 y(s) [다음 분기 가격 변화율 원값] — 월말마다 1회 구성
#    가격 블록: QC[i], QC[i−3], …, QC[i−27]  (ten preceding quarterly changes, 최근순) → 열별 횡단면 순위
#    이익 블록: .earn_mat (캘린더 정렬 · 사이클별 열 집합) → 열별 30% 무작위 제거(논문) → 열별 횡단면 순위
#    원자료 입력이 하나도 없는 종목(상장 직후 등)은 순위 대상에서 제외 — §3.1 '신규 상장은 순위 불가' 의 최소 독법
# =============================================================================
.build_inputs <- function(i, d, tk, mi) {
  ci <- match(tk, .TK)
  XP <- matrix(NA_real_, length(tk), .N_LAG)
  for (k in seq_len(.N_LAG)) {
    r <- i - 3L * (k - 1L)
    if (r >= 1L) XP[, k] <- .QC[r, ci]
  }
  ecols <- if (.U1_CYCLE[mi %% 3L + 1L]) seq_len(.N_LAG) else 2L:.N_LAG
  q0 <- .q_of((mi - 1L) %/% 12L, (mi - 1L) %% 12L + 1L)
  XE <- .earn_mat(as.numeric(d), tk, q0, ecols)
  keep <- (rowSums(is.finite(XP)) + rowSums(is.finite(XE))) > 0
  n_nodata <- sum(!keep)
  tk <- tk[keep]; XP <- XP[keep, , drop = FALSE]; XE <- XE[keep, , drop = FALSE]
  if (length(tk) < 2L) return(NULL)
  ecov <- mean(rowSums(is.finite(XE)) > 0)          # 진단: 이익 입력이 하나라도 있는 종목 비율(제거 전)
  for (j in seq_len(ncol(XE))) {
    ok <- which(is.finite(XE[, j]))
    nd <- as.integer(round(.EARN_DROP * length(ok)))
    if (nd > 0L) XE[ok[sample.int(length(ok), nd)], j] <- NA_real_
  }
  list(tk = tk, X = cbind(.rank_cols(XP), .rank_cols(XE)), ecov = ecov,
       n_ecol = ncol(XE), n_nodata = n_nodata)
}

.MI_SIG0 <- (year(.SIG_FROM) * 12L + month(.SIG_FROM)) - (.HOLD_M - 1L)   # 첫 트랜치 = 2004-11 (2005-01 합성용)
.MI_PRE0 <- .MI_SIG0 - 3L * .N_TRAINQ
.pre <- list()
for (mi in seq(.MI_PRE0, max(.me$MI))) {
  i <- match(mi, .MIs)
  if (is.na(i)) next
  tk <- .EL[[as.character(mi)]]
  if (is.null(tk) || length(tk) < 2L) next
  tk <- tk[tk %chin% .TK]
  if (length(tk) < 2L) next
  d <- .me[MI == mi]$MEnd[1L]
  set.seed(.SEED_BASE + mi)
  bi <- .build_inputs(i, d, tk, mi)
  if (is.null(bi)) next
  y  <- if (i + .HOLD_M <= .NR) .QC[i + .HOLD_M, match(bi$tk, .TK)] else rep(NA_real_, length(bi$tk))
  .pre[[as.character(mi)]] <- list(tk = bi$tk, X = bi$X, y = y, d = d, ecov = bi$ecov,
                                   n_ecol = bi$n_ecol, n_nodata = bi$n_nodata)
}
if (length(.pre) == 0L) stop("[RP_AUTO_0806_2606] 입력 행렬 0개 — 적격 종목/월말 확인")
cat(sprintf("[RP_AUTO_0806_2606] 입력 행렬 %d개월 구성 (%s ~ %s) | %.1f분\n",
            length(.pre), .ym(min(as.integer(names(.pre)))), .ym(max(as.integer(names(.pre)))),
            as.numeric(difftime(Sys.time(), .t0, units = "mins"))))

# =============================================================================
# 5. 단일 은닉층 역전파 MLP — 다중 초기화 × 은닉 크기 후보를 블록 대각 한 네트워크로 동시 학습
#    (헤드 간 가중치 공유 0 = 독립 네트워크 K×|HID| 개와 수학적으로 동일)
#    은닉 tanh · 출력 선형 · 손실 = 헤드별 MSE · 전배치 경사하강 + 모멘텀 · 헤드별 검증 조기종료
#    표적 = 다음 분기 가격 변화율 원값을 학습 분할의 평균·SD 로 아핀 표준화(순서 보존) — 절단 없음(논문에 없음)
#    반환 = 선택 은닉 크기의 헤드들(각자 최적 에폭)의 예측 평균 (논문: multiple initializations aggregated)
# =============================================================================
.fwd <- function(X, W1, b1, W2, b2) {
  Hd <- tanh(X %*% W1 + rep(b1, each = nrow(X)))
  list(Hd = Hd, out = Hd %*% W2 + rep(b2, each = nrow(X)))
}
.ann_fit_predict <- function(Xtr, ytr, Xpr, seed) {
  set.seed(seed)
  n <- nrow(Xtr); p <- ncol(Xtr)
  nv  <- max(1L, as.integer(floor(n * .VAL_FRAC)))
  iv  <- sample.int(n, nv)
  itr <- setdiff(seq_len(n), iv)
  if (length(itr) < 2L) return(NULL)
  mu  <- mean(ytr[itr]); sdv <- sd(ytr[itr])
  if (!is.finite(sdv) || sdv <= 0) return(NULL)
  yz <- (ytr - mu) / sdv
  Xa <- Xtr[itr, , drop = FALSE]; ya <- yz[itr]; na <- length(itr)
  Xv <- Xtr[iv,  , drop = FALSE]; yv <- yz[iv]

  hs  <- rep(.HID, each = .N_INIT)             # 헤드 → 은닉 유닛 수
  H   <- length(hs); tot <- sum(hs)
  blk <- rep(seq_len(H), times = hs)           # 은닉 유닛 → 헤드
  W1  <- matrix(runif(p * tot, -1, 1) / sqrt(p), p, tot)
  b1  <- runif(tot, -1, 1) / sqrt(p)
  M2  <- matrix(0, tot, H); M2[cbind(seq_len(tot), blk)] <- 1
  W2  <- sweep(M2 * matrix(runif(tot * H, -1, 1), tot, H), 2L, sqrt(hs), "/")
  b2  <- numeric(H)
  vW1 <- 0 * W1; vb1 <- 0 * b1; vW2 <- 0 * W2; vb2 <- 0 * b2
  bv <- rep(Inf, H); be <- integer(H); since <- integer(H); alive <- rep(TRUE, H)
  pb <- matrix(NA_real_, nrow(Xpr), H)
  ep <- 0L
  for (ep in seq_len(.MAX_EPOCH)) {
    f   <- .fwd(Xa, W1, b1, W2, b2)
    E   <- (f$out - ya) * (2 / na)             # d MSE_h / d out  (헤드별)
    gW2 <- crossprod(f$Hd, E) * M2
    gb2 <- colSums(E)
    dH  <- (E %*% t(W2)) * (1 - f$Hd^2)        # 블록 대각 W2 → 은닉 유닛은 자기 헤드의 오차만 받는다
    gW1 <- crossprod(Xa, dH)
    gb1 <- colSums(dH)
    vW1 <- .MOM * vW1 - .LR * gW1; W1 <- W1 + vW1
    vb1 <- .MOM * vb1 - .LR * gb1; b1 <- b1 + vb1
    vW2 <- .MOM * vW2 - .LR * gW2; W2 <- W2 + vW2
    vb2 <- .MOM * vb2 - .LR * gb2; b2 <- b2 + vb2
    vm  <- colMeans((.fwd(Xv, W1, b1, W2, b2)$out - yv)^2)
    imp <- alive & is.finite(vm) & (vm < bv)
    if (any(imp)) {
      pp <- .fwd(Xpr, W1, b1, W2, b2)$out
      bv[imp] <- vm[imp]; be[imp] <- ep; since[imp] <- 0L
      pb[, imp] <- pp[, imp, drop = FALSE]
    }
    since[alive & !imp] <- since[alive & !imp] + 1L
    alive <- alive & (since < .PATIENCE)
    if (!any(alive)) break
  }
  # 은닉 크기 선택: 초기화 평균 검증 MSE 가 최소 ×(1+tol) 안에 드는 가장 작은 크기 (under-fitting 선호)
  mv <- vapply(.HID, function(h) {
    j <- which(hs == h & is.finite(bv)); if (length(j)) mean(bv[j]) else NA_real_ }, numeric(1L))
  if (!any(is.finite(mv))) return(NULL)
  hmin <- min(mv, na.rm = TRUE)
  hsel <- .HID[which(is.finite(mv) & mv <= (1 + .UNDERFIT_TOL) * hmin)][1L]
  jj   <- which(hs == hsel & is.finite(bv))
  list(pred = rowMeans(pb[, jj, drop = FALSE]), hsel = hsel, mv = mv,
       ep_med = as.integer(median(be[jj])), n_tr = na, n_val = nv, n_heads = length(jj), ep_run = ep)
}

# =============================================================================
# 6. 월별 루프 — (a) 트랜치: 직전 10분기 학습 → 예측 내림차순 → T100 롱 / B100 숏 (다리당 총노출 1.0 검산)
#                 (b) 합성 북: 최근 3개 월간 시작점 트랜치의 1/3 평균(순netting) → 시점 멤버십(러너 규칙) 적용 → 발행
# =============================================================================
.rows_f <- list(); .rows_p <- list(); .diag <- list(); .tranche <- list(); .comp <- list()
.nskip <- 0L
.MI_OUT0 <- year(.SIG_FROM) * 12L + month(.SIG_FROM)
for (mi in seq(.MI_SIG0, max(.me$MI))) {
  pr   <- .pre[[as.character(mi)]]
  d_mi <- .me[MI == mi]$MEnd[1L]

  # ---- (a) 트랜치 형성 ----
  if (is.null(pr)) {
    .nskip <- .nskip + 1L
    cat(sprintf("[RP_AUTO_0806_2606] %s 입력 없음 — 트랜치 미형성\n", .ym(mi)))
  } else {
    tr <- lapply(seq_len(.N_TRAINQ), function(k) .pre[[as.character(mi - 3L * k)]])
    tr <- Filter(Negate(is.null), tr)
    if (length(tr)) {
      pdim <- vapply(tr, function(z) ncol(z$X), integer(1L))   # 같은 사이클 = 같은 열 집합이어야 한다
      if (any(pdim != ncol(pr$X)))
        cat(sprintf("[RP_AUTO_0806_2606] %s 학습 분기 %d개 열 수 불일치 — 제외\n", .ym(mi), sum(pdim != ncol(pr$X))))
      tr <- tr[pdim == ncol(pr$X)]
    }
    if (length(tr) == 0L) {
      .nskip <- .nskip + 1L
      cat(sprintf("[RP_AUTO_0806_2606] %s 학습 분기 0 — 트랜치 미형성\n", .ym(mi)))
    } else {
      Xtr <- do.call(rbind, lapply(tr, `[[`, "X"))
      ytr <- unlist(lapply(tr, `[[`, "y"), use.names = FALSE)
      ok  <- is.finite(ytr)
      Xtr <- Xtr[ok, , drop = FALSE]; ytr <- ytr[ok]
      if (nrow(Xtr) < .MIN_TRAIN) {
        .nskip <- .nskip + 1L
        cat(sprintf("[RP_AUTO_0806_2606] %s 학습 표본 %d < %d — 트랜치 미형성\n", .ym(mi), nrow(Xtr), .MIN_TRAIN))
      } else {
        fit <- .ann_fit_predict(Xtr, ytr, pr$X, seed = .SEED_BASE + 1000L + mi)
        if (is.null(fit) || !all(is.finite(fit$pred))) {
          .nskip <- .nskip + 1L
          cat(sprintf("[RP_AUTO_0806_2606] %s 학습 실패(검증 개선 헤드 0 또는 비유한 예측) — 트랜치 미형성\n", .ym(mi)))
        } else {
          score <- fit$pred
          n <- length(pr$tk)
          .rows_f[[length(.rows_f) + 1L]] <- data.table(Date = pr$d, Ticker = pr$tk, Score = score)
          # 트랜치: 예측 내림차순 → 상위 k 롱 EW(+1/k) · 하위 k 숏 EW(−1/k). 다리 중첩 불가 → k ≤ floor(N/2) (N<200 에서만 구속)
          o  <- order(-score, pr$tk)
          kl <- min(.N_TOP, n %/% 2L); ks <- min(.N_BOT, n %/% 2L)
          if (kl < 1L || ks < 1L) {
            .nskip <- .nskip + 1L
            cat(sprintf("[RP_AUTO_0806_2606] %s 적격 %d종 — 다리 구성 불가\n", .ym(mi), n))
          } else {
            w <- numeric(n)
            w[o[seq_len(kl)]] <- 1 / kl
            w[o[(n - ks + 1L):n]] <- w[o[(n - ks + 1L):n]] - 1 / ks
            trn <- data.table(Ticker = pr$tk, W = w)[W != 0]
            gl_t <- sum(trn$W[trn$W > 0]); gs_t <- -sum(trn$W[trn$W < 0])
            if (abs(gl_t - 1) > 1e-9 || abs(gs_t - 1) > 1e-9)
              stop(sprintf("[RP_AUTO_0806_2606] %s 트랜치 다리 총노출 검산 실패 (gL %.6f / gS %.6f)", .ym(mi), gl_t, gs_t))
            .tranche[[as.character(mi)]] <- trn
            ymax <- max(abs(ytr))
            .diag[[length(.diag) + 1L]] <- data.table(
              Date = pr$d, N = n, p = ncol(pr$X), n_ecol = pr$n_ecol, n_nodata = pr$n_nodata,
              n_train = fit$n_tr, n_val = fit$n_val, hsel = fit$hsel, n_heads = fit$n_heads,
              ep_med = fit$ep_med, ep_run = fit$ep_run, ecov = pr$ecov, kl = kl, ks = ks,
              ymax = ymax, n_y3 = sum(abs(ytr) > 3),
              mv4 = fit$mv[1L], mv8 = fit$mv[2L], mv16 = fit$mv[3L])
            cat(sprintf(paste0("[RP_AUTO_0806_2606] %s | N=%d(무자료 제외 %d) p=%d(이익열 %d) train=%d(+%d val) | 이익입력 보유율 %.0f%% | ",
                               "표적 max|y| %.2f (|y|>3: %d) | valMSE h4/h8/h16 = %.3f/%.3f/%.3f → h=%d (헤드 %d · 최적 에폭 중앙 %d · 실행 %d) | ",
                               "L%d/S%d | %.1f분\n"),
                        as.character(pr$d), n, pr$n_nodata, ncol(pr$X), pr$n_ecol, fit$n_tr, fit$n_val, 100 * pr$ecov,
                        ymax, sum(abs(ytr) > 3),
                        fit$mv[1L], fit$mv[2L], fit$mv[3L], fit$hsel, fit$n_heads, fit$ep_med, fit$ep_run, kl, ks,
                        as.numeric(difftime(Sys.time(), .t0, units = "mins"))))
          }
        }
      }
    }
  }

  # ---- (b) 합성 북 = 최근 3개 월간 시작점 트랜치의 평균 (논문: results are averaged over all three possible monthly starting points)
  #      트랜치가 빠진 달은 남은 트랜치 평균. 같은 종목의 롱·숏이 트랜치 간에 만나면 순netting(합성 총노출 < 1.0 의 유일한 원인 ①).
  #      시점 멤버십(러너 규칙) 적용 — 이탈 종목은 그 달부터 빠지고 그 비중은 재분배하지 않는다(현금 · 원인 ②).
  if (mi >= .MI_OUT0 && !is.na(d_mi)) {
    parts <- lapply(0L:(.HOLD_M - 1L), function(j) .tranche[[as.character(mi - j)]])
    parts <- Filter(Negate(is.null), parts)
    np <- length(parts)
    if (np > 0L) {
      agg  <- rbindlist(parts)[, .(Weight = sum(W) / np), by = Ticker]
      net0 <- sum(agg$Weight)
      agg  <- agg[abs(Weight) > 1e-12]
      memd <- .MEMD[[as.character(mi)]]
      if (is.null(memd)) memd <- character(0L)
      inm  <- agg$Ticker %chin% memd
      drop_l <- sum(agg$Weight[!inm & agg$Weight > 0]); drop_s <- -sum(agg$Weight[!inm & agg$Weight < 0])
      agg  <- agg[inm]
      if (nrow(agg))
        .rows_p[[length(.rows_p) + 1L]] <- data.table(
          Date = d_mi, Ticker = agg$Ticker, Weight = agg$Weight,
          Leg = ifelse(agg$Weight > 0, "long", "short"))
      .comp[[length(.comp) + 1L]] <- data.table(
        Date = d_mi, n_tranche = np, net0 = net0,
        gl = sum(agg$Weight[agg$Weight > 0]), gs = -sum(agg$Weight[agg$Weight < 0]),
        n_long = sum(agg$Weight > 0), n_short = sum(agg$Weight < 0),
        n_drop = sum(!inm), drop_l = drop_l, drop_s = drop_s)
    }
  }
}

# =============================================================================
# 7. PORTFOLIO · FACTORS 조립 · 검산 · 요약
# =============================================================================
if (length(.rows_p) == 0L)
  stop(sprintf("[RP_AUTO_0806_2606] 발행 행 0 — 트랜치 미형성 월 %d (입력 행렬 %d개월)", .nskip, length(.pre)))
PORTFOLIO <- rbindlist(.rows_p, use.names = TRUE)
PORTFOLIO <- PORTFOLIO[Date >= .SIG_FROM]
if (nrow(PORTFOLIO) == 0L) stop("[RP_AUTO_0806_2606] 고정 축 시작 이후 행 0")
setorder(PORTFOLIO, Date, Leg, Ticker)
FACTORS <- rbindlist(.rows_f, use.names = TRUE)
FACTORS <- FACTORS[is.finite(Score)]
setorder(FACTORS, Date, Ticker)

.COMP <- rbindlist(.comp, use.names = TRUE)
.bad <- .COMP[abs(net0) > 1e-9]                                   # 멤버십 적용 전 합성 북 = 달러중립(구성상)
if (nrow(.bad) > 0L)
  stop(sprintf("[RP_AUTO_0806_2606] 합성 북 달러중립 검산 실패 %d건 (예: %s net %.6f)",
               nrow(.bad), as.character(.bad$Date[1L]), .bad$net0[1L]))
.dupw <- sum(duplicated(PORTFOLIO, by = c("Date", "Ticker")))
if (.dupw > 0L) stop(sprintf("[RP_AUTO_0806_2606] PORTFOLIO (Date,Ticker) 중복 %d", .dupw))
.dupf <- sum(duplicated(FACTORS, by = c("Date", "Ticker")))
if (.dupf > 0L) stop(sprintf("[RP_AUTO_0806_2606] FACTORS (Date,Ticker) 중복 %d", .dupf))

.DIAG <- rbindlist(.diag, use.names = TRUE)
.CS   <- .COMP[Date >= .SIG_FROM]
cat(sprintf(paste0("[RP_AUTO_0806_2606] adapted(논문 절차 · 유니버스 K200∪KQ150 · recurrence 미구현): ",
                   "20입력(가격 10분기 + 이익 ≤10분기 캘린더 정렬 · 순위 [−1,1] · 이익 30%% 무작위 제거) → ",
                   "단일 은닉층 역전파 MLP(초기화 %d × 은닉 %s · 검증 조기종료 · under-fit 선택) · 직전 %d분기 학습 → ",
                   "예측 내림차순 T%d 롱 / B%d 숏 EW · 1분기 보유 · 월간 시작점 3개 평균(합성 북)\n",
                   "  트랜치 %d개 (%s ~ %s · 미형성 %d) · 적격 N %d~%d · 다리 %d~%d종 · 입력 열 p %d~%d · 이익입력 보유율 중앙 %.0f%% · ",
                   "선택 은닉 h4/h8/h16 = %d/%d/%d회 · 표적 max|y| 최대 %.2f(|y|>3 총 %d행)\n",
                   "  합성 북 %d행·%d개월 (%s ~ %s) · 트랜치<3 인 달 %d · 보유 롱 %d~%d / 숏 %d~%d (최대 %d종) · ",
                   "다리 총노출 평균 gL %.3f / gS %.3f (최소 %.3f / %.3f) · 순노출 평균 %+.4f · 멤버십 이탈 평균 %.1f종/월(비중 %.4f) · %.1f분\n",
                   "  ★러너 사양 = FIDELITY.json portfolio_spec (engine_direct) · commission_paper = null (논문 비용 무명시 → gross 병기)\n"),
            .N_INIT, paste(.HID, collapse = "/"), .N_TRAINQ, .N_TOP, .N_BOT,
            nrow(.DIAG), as.character(min(.DIAG$Date)), as.character(max(.DIAG$Date)), .nskip,
            min(.DIAG$N), max(.DIAG$N), min(.DIAG$kl), max(.DIAG$kl), min(.DIAG$p), max(.DIAG$p),
            100 * median(.DIAG$ecov),
            sum(.DIAG$hsel == 4L), sum(.DIAG$hsel == 8L), sum(.DIAG$hsel == 16L), max(.DIAG$ymax), sum(.DIAG$n_y3),
            nrow(PORTFOLIO), uniqueN(PORTFOLIO$Date), as.character(min(PORTFOLIO$Date)), as.character(max(PORTFOLIO$Date)),
            sum(.CS$n_tranche < .HOLD_M), min(.CS$n_long), max(.CS$n_long), min(.CS$n_short), max(.CS$n_short),
            max(.CS$n_long + .CS$n_short),
            mean(.CS$gl), mean(.CS$gs), min(.CS$gl), min(.CS$gs), mean(.CS$gl - .CS$gs),
            mean(.CS$n_drop), mean(.CS$drop_l + .CS$drop_s),
            as.numeric(difftime(Sys.time(), .t0, units = "mins"))))
PORTFOLIO <- PORTFOLIO[, .(Date, Ticker, Weight, Leg)]
FACTORS   <- FACTORS[, .(Date, Ticker, Score)]
