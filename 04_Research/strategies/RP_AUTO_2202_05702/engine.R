# =============================================================================
# engine.R — RP_AUTO_2202_05702  (재구현 2판 · 1판은 engine.rejected1.R)
# Yuxuan Huang · Luiz Fernando Capretz · Danny Ho,
#   "Machine Learning for Stock Prediction Based on Fundamental Analysis"
#   arXiv:2202.05702 (IEEE SSCI 2021) — https://arxiv.org/abs/2202.05702
#   본문 = r.jina.ai PDF 텍스트 프록시(/html/v1 = 404 · 2022 논문 HTML 렌더 없음)
#
# ★라벨·변경 전수 신고·러너 사양·감사 응답의 정본 = FIDELITY.json.
#   이 주석은 아무것도 결정하지 않는다. 코드 옆 ★changed(n) = FIDELITY.json changed 항목 번호.
#
# ── 1판이 기각된 두 지점 · 이 판의 정정 ────────────────────────────────────────
#   [A] 식 (5) 분모. 논문은 Δx_t = (x_t − x_{t−1}) / x_{t−1} × 100% 를 **인쇄**한다 —
#       분모는 부호 있는 x_{t−1}. 1판(engine.rejected1.R:101)은 |x_{t−1}| 로 나눠
#       직전값이 음수인 모든 관측에서 부호를 뒤집었고, 그 판의 양성 대조(:121-123)는
#       뒤집힌 값을 정답으로 못박고 있었다. 이 판은 **식 (5) 그대로**(부호 유지 · ×100)이고
#       양성 대조가 `.pch(3, -6) = -150 < 0` 을 단언해 |·| 회귀를 차단한다(§2).
#       부수: P/B·P/E 의 분모 가드도 1판의 '> 0' 에서 **'≠ 0'**(수학적 미정의만 제외)로
#       최소화했다 — 논문은 어떤 가드도 인쇄하지 않는다 ★changed(6).
#   [B] 학습 범위. 논문 IV절 B항 'Local Learning' 은 global learning 을 **측정하고 기각**한 뒤
#       "we built one model for each stock for all three algorithms" 로 종목당 모델 1개를 쓴다
#       (70종 → RF 70개 · V절 'predict the quarterly relative return of each of the 70 stocks').
#       1판은 분기당 전 종목 pooled 로 1회 적합 = 논문이 기각한 쪽이었다. 이 판은 §7 이
#       **종목 루프 안에서** 그 종목 자신의 과거만으로 적합한다(표준화·결측 대치 통계도 그 종목
#       학습집합에서). 학습집합 하한도 종목 단위(분기 수)로 바뀐다 ★changed(5)(9).
#
# 논문 기전(그대로): 분기 공시 지표를 식 (5) 백분율 변화로 추세제거 → 식 (6) 표준화(학습집합
#   통계) · 결측은 평균 대치 → **종목별** Random Forest 로 다음 분기의 **벤치마크 대비
#   상대수익**을 회귀 → 예측 상대수익으로 정렬해 **상위 1/3** 동일가중 보유 · **분기** 리밸.
#   입력 = 논문이 RF 중요도로 골라 인쇄한 Table 3 top 6 중 KR 가용 5종.
#
# 산출: FACTORS(Date, Ticker, Score)          — 예측이 난 종목 전부 · Score = 예측 상대수익
#       PORTFOLIO(Date, Ticker, Weight, Leg)  — 상위 1/3 EW 롱 Σw=+1 (engine_direct)
#
# PIT(C1~C15) 구조 보장:
#   · 시그널일 t 의 특성 = t 이하 정보뿐. 회계 특성 = 공시 가용일(usable) ≤ t 인 최신 관측
#     (분기 5/15·8/15·11/15 · 4분기 = 익년 3/31 — pit.md C4). 패널의 Factor_Date 열은
#     쓰지 않는다(xlsx 경로가 4분기에도 일률 +45d ≈ 익년 2/14 라 3/31 대비 공격적).
#   · 표적 y(s) = 분기 s+1 의 상대수익이고 분기 s+1 마지막 거래일에 실현된다. 종목별 학습집합은
#     그 종목의 si < s 행만 쓰므로 si <= s-1 → 실현일 <= t(s) (§7 이 매 적합에서 재단언).
#   · 표준화·결측 대치 통계는 그 적합의 학습집합에서만(확장창 · 전 표본 통계 0건).
#   · 횡단면 정렬은 그날 예측 집합 안에서만. 팩터 DB 미사용(C15 무관) · 부호 반전 없음(C13 무관).
#   · 음수 shift · 미래 인덱싱 0건. 표적은 (Ticker, si-1) 조인으로 붙이고 소비 시점에 잘린다.
# =============================================================================

suppressWarnings(suppressMessages({
  library(data.table)
  library(arrow)
  library(dplyr)
  library(ranger)
}))

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
stopifnot(exists("BM_DT"), is.data.table(BM_DT))
.TAG <- "[RP_AUTO_2202_05702]"
.t0  <- Sys.time()
.REQ <- c("Date", "Ticker", "Close", "Size", "K200", "KQ150")
if (!all(.REQ %in% names(RAWDATA)))
  stop(sprintf("%s RAWDATA 필수 열 부재: %s", .TAG, paste(setdiff(.REQ, names(RAWDATA)), collapse = ", ")))

# =============================================================================
# 0. 상수 — 논문 명시값 + 논문이 침묵하는 규약(전부 FIDELITY.json changed 신고)
# =============================================================================
.START      <- as.Date("2005-01-01")   # 고정 축 — 이 날 이후 시그널만 발행
.TOP_DIV    <- 3L                      # 논문: "top one third stocks with the highest ranking"
.MIN_N      <- 6L                      # ★changed(9) 상위 1/3 정의역(n %/% 3 >= 2)
.CARRY_DAYS <- 400L                    # ★changed(7) 회계 관측 가용일 이후 캐리 상한(달력일)
.MC_ROLL    <- 30L                     # ★changed(7) 기간말 시총 조회 캐리(직전 거래일 탐색)
.BM_ROLL    <- 10L                     # ★changed(8) 벤치 레벨 조회 캐리
.MIN_TR_TK  <- 12L                     # ★changed(9) **종목별** 학습집합 하한(분기 수 · 논문 53)
.DET_MIN    <- 100L                    # ★changed(6) 분기 유량 형식 판별 표본 하한(종목-연도)
.SEED_BASE  <- 220205702L              # ★changed(10) 시드 기준값(논문 번호에서 온 임의 상수)
.RF_TREES   <- 100L                    # ★changed(2) sklearn RandomForestRegressor n_estimators 기본값
.RF_MINNODE <- 1L                      # ★changed(2) sklearn min_samples_split=2/min_samples_leaf=1 → 완전성장
.FEATS      <- c("d_pb", "rr", "d_bv", "d_pe", "d_liab")
.FEAT_PAPER <- c("P/B", "Relative Return", "Book Value", "P/E", "Liability")
.ITEMS      <- c("TotalEquity", "TotalLiab", "NetIncome", "Revenue")
.NP         <- length(.FEATS)
stopifnot(.NP == length(.FEAT_PAPER))

# =============================================================================
# 1. 루트·캐시 (표지 파일 검증 · 셸 연산자 미사용)
# =============================================================================
.find_root <- function() {
  cands <- c(Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""),
             if (exists("PROJECT_ROOT", inherits = TRUE)) as.character(get("PROJECT_ROOT", inherits = TRUE))[1] else "",
             getwd())
  marker <- "02_Infrastructure/hooks/qvest_hook_router.py"
  for (p in cands) {
    if (!nzchar(p)) next
    p <- gsub("\\\\", "/", p)
    if (file.exists(file.path(p, marker))) return(p)
  }
  stop(sprintf("%s 프로젝트 루트를 찾지 못함(표지 %s) — CLAUDE_PROJECT_DIR/QM_ROOT 확인", .TAG, marker))
}
.ROOT  <- .find_root()
.CACHE <- if (exists("CACHE_DIR", inherits = TRUE)) as.character(get("CACHE_DIR", inherits = TRUE))[1] else file.path(.ROOT, ".cache")
cat(sprintf("%s root %s · cache %s\n", .TAG, .ROOT, .CACHE))

# =============================================================================
# 2. 헬퍼 + 양성 대조 (구현 결함 = 중단 · 조용한 F 방지)
# =============================================================================
# ★논문 식 (5): Δx_t = (x_t − x_{t−1}) / x_{t−1} × 100%  — 분모는 **부호 있는** 직전값.
#   0 분모만 제외한다(수학적 미정의 · 논문은 가드를 인쇄하지 않는다 · changed(6)).
.pch  <- function(v, l) fifelse(is.finite(v) & is.finite(l) & l != 0, (v - l) / l * 100, NA_real_)
# 비율의 분모 가드도 **0 만** 제외 — 부호는 보존한다(음수 자본·적자 기업도 논문 원천에 있다).
.rdiv <- function(a, b) fifelse(is.finite(a) & is.finite(b) & b != 0, a / b, NA_real_)
# 공시 가용일 — pit.md C4: 분기 고정일 5/15·8/15·11/15 · 4분기(= 결산) 익년 3/31
#   ★한 번에 유효한 날짜 문자열만 만든다 — 두 분기를 두 갈래로 지어 fifelse 로 고르면
#   버려지는 갈래가 "YYYY-14-15" 같은 무효 문자열이 되고, as.Date 는 **벡터의 첫 원소**로
#   형식을 정하므로 첫 행이 4분기면 통째로 에러가 난다(무효 갈래는 만들지 않는다).
.usable_of <- function(fy, qn) {
  yr <- fifelse(qn == 4L, fy + 1L, fy)
  mo <- fifelse(qn == 4L, 3L, qn * 3L + 2L)
  dy <- fifelse(qn == 4L, 31L, 15L)
  return(as.Date(sprintf("%04d-%02d-%02d", yr, mo, dy)))
}
# 상위 1/3 종목수 — 정수 나눗셈 n %/% 3 (논문 'one third' 의 정수화 · changed(9))
#   ★floor(n * (1/3)) 은 배정도에서 6 → 1, 3 → 0 을 낸다. 양성 대조가 이 자리를 잡는다.
.k_top <- function(n) as.integer(n) %/% .TOP_DIV

local({
  # ── 식 (5) — 부호 있는 분모 ──────────────────────────────────────────────
  .o <- .pch(c(120, 12, -6, 5, 3), c(100, NA, 11, 0, -6))
  .e <- c(20, NA_real_, (-6 - 11) / 11 * 100, NA_real_, (3 - (-6)) / (-6) * 100)
  if (!isTRUE(all.equal(.o, .e)))
    stop(sprintf("%s 식 (5) 백분율 변화 검산 실패", .TAG))
  # ★1판 회귀 차단 — |직전값| 분모면 +150 이 나온다. 식 (5) 는 −150.
  if (!(is.finite(.pch(3, -6)) && .pch(3, -6) < 0 && isTRUE(all.equal(.pch(3, -6), -150))))
    stop(sprintf("%s 식 (5) 부호 검산 실패 — 음수 직전값에서 부호가 살아 있어야 한다(절대값 분모 금지)", .TAG))
  # ── 비율 분모 가드 — 0 만 제외 · 부호 보존 ───────────────────────────────
  if (!isTRUE(all.equal(.rdiv(c(10, 10, 10), c(2, 0, -2)), c(5, NA, -5))))
    stop(sprintf("%s 비율 분모 가드 검산 실패", .TAG))
  # ── 공시 가용일 ──────────────────────────────────────────────────────────
  u <- .usable_of(c(2010L, 2010L, 2010L, 2010L), c(1L, 2L, 3L, 4L))
  if (!identical(as.character(u), c("2010-05-15", "2010-08-15", "2010-11-15", "2011-03-31")))
    stop(sprintf("%s 공시 가용일 검산 실패", .TAG))
  # ── 상위 1/3 정수화 ──────────────────────────────────────────────────────
  if (!identical(.k_top(c(70L, 6L, 350L)), c(23L, 2L, 116L)))
    stop(sprintf("%s 상위 1/3 종목수 검산 실패", .TAG))
  # ── 상대수익: 종목 +20% · 벤치 +5% → 0.15 ────────────────────────────────
  if (!isTRUE(all.equal((120 / 100 - 1) - (105 / 100 - 1), 0.15)))
    stop(sprintf("%s 상대수익 검산 실패", .TAG))
  # ── TTM 항등: 단일기 유량 FY1 = 1,2,3,4 · FY2 = 5,6,7,8 → TTM(FY2,q1) = 2+3+4+5 = 14 ──
  y1 <- cumsum(c(1, 2, 3, 4)); y2 <- cumsum(c(5, 6, 7, 8))
  if (!isTRUE(all.equal(y2[1] + y1[4] - y1[1], 14)))
    stop(sprintf("%s TTM 항등 검산 실패", .TAG))
  cat(sprintf("%s 양성 대조 통과 — 식 (5) 부호 있는 분모(−150) · 비율 가드(0 만 제외) · 공시 가용일 · 상위 1/3 정수화 · 상대수익 · TTM 항등\n", .TAG))
})

# 종목별 표준화(식 (6)) — 학습집합 mean/sd. 결측·상수열은 학습집합 평균(표준화 후 0).
.zfit <- function(Xtr, Xte) {
  for (cc in seq_len(ncol(Xtr))) {
    v  <- Xtr[, cc]
    ok <- is.finite(v)
    m  <- if (any(ok)) mean(v[ok]) else NA_real_
    s  <- if (sum(ok) >= 2L) stats::sd(v[ok]) else NA_real_
    if (!is.finite(m) || !is.finite(s) || s <= 0) {
      Xtr[, cc] <- 0; Xte[, cc] <- 0
    } else {
      a <- (v - m) / s;          a[!is.finite(a)] <- 0; Xtr[, cc] <- a
      b <- (Xte[, cc] - m) / s;  b[!is.finite(b)] <- 0; Xte[, cc] <- b
    }
  }
  return(list(tr = Xtr, te = Xte))
}
# ── .zfit 양성 대조: 결측은 학습집합 평균 → 0 · 상수열 → 0 · 시험행은 학습 통계로 ──
local({
  Xtr <- matrix(c(1, 2, 3, NA, 7, 7, 7, 7), ncol = 2)
  Xte <- matrix(c(2, 9), ncol = 2)
  z <- .zfit(Xtr, Xte)
  if (!isTRUE(all.equal(z$tr[4, 1], 0)) || !isTRUE(all.equal(z$tr[2, 1], 0)) ||
      !isTRUE(all.equal(z$tr[1, 2], 0)) || !isTRUE(all.equal(z$te[1, 1], 0)) ||
      !isTRUE(all.equal(z$te[1, 2], 0)))
    stop(sprintf("%s 표준화·평균대치 검산 실패", .TAG))
})

# =============================================================================
# 3. 시그널 격자 = 각 달력분기 마지막 거래일 (완결 분기만)  ★changed(3)
#    열 정체: Close = 수정주가 · Size = 시가총액(KRW) · K200/KQ150 = 그날 멤버십 플래그
# =============================================================================
.cal <- sort(unique(RAWDATA$Date))
.CAL <- data.table(Date = .cal)
.CAL[, qi := year(Date) * 4L + ((month(Date) - 1L) %/% 3L)]
.QE <- .CAL[, .(Date = max(Date)), by = qi]
setorder(.QE, qi)
.n_qe_all <- nrow(.QE)
.QE <- .QE[qi < max(qi)]                      # 마지막 = 진행 중 분기 → 제외(부분 분기)
.QE[, si := seq_len(.N)]
if (nrow(.QE) < 20L) stop(sprintf("%s 분기말 격자 %d개 — RAWDATA 범위 확인", .TAG, nrow(.QE)))

.rd <- RAWDATA[Date %in% .QE$Date & is.finite(Close) & Close > 0,
               .(Date, Ticker, Close, Size, K200, KQ150)]
.rd[, Ticker := as.character(Ticker)]
.rd[, ELIG := (K200 == TRUE | KQ150 == TRUE) %in% TRUE]
.rd[, c("K200", "KQ150") := NULL]
.rd[, Size := as.numeric(Size)]
.ndup <- sum(duplicated(.rd, by = c("Ticker", "Date")))
if (.ndup > 0L) {
  cat(sprintf("%s (Ticker,Date) 중복 %d행 — 첫 행만 유지\n", .TAG, .ndup))
  .rd <- unique(.rd, by = c("Ticker", "Date"))
}
.rd[.QE, on = "Date", si := i.si]
.tk_elig <- sort(unique(.rd$Ticker[.rd$ELIG]))
if (length(.tk_elig) < 50L)
  stop(sprintf("%s 적격 이력 종목 %d — 멤버십 플래그 확인", .TAG, length(.tk_elig)))
.rd <- .rd[Ticker %in% .tk_elig]
setorder(.rd, Ticker, si)
cat(sprintf("%s 격자 %d분기말(%s ~ %s · 진행 분기 제외 %d) × 적격 이력 종목 %d = %d행\n",
            .TAG, nrow(.QE), as.character(min(.QE$Date)), as.character(max(.QE$Date)),
            .n_qe_all - nrow(.QE), length(.tk_elig), nrow(.rd)))

# =============================================================================
# 4. 벤치마크 분기수익 + 상대수익(특성 rr) + 표적 y  ★changed(8)
#    논문 표적 = "stock's quarterly relative returns with respect to the DJIA"
# =============================================================================
if ("BM_Close" %in% names(BM_DT)) {
  .bm <- BM_DT[is.finite(BM_Close) & BM_Close > 0, .(Date, lvl = as.numeric(BM_Close))]
  .bm_src <- "BM_Close(공표 지수 포인트)"
} else {
  if (!"BM_Ret" %in% names(BM_DT)) stop(sprintf("%s BM_DT 에 BM_Close 도 BM_Ret 도 없음", .TAG))
  .b0 <- BM_DT[is.finite(BM_Ret), .(Date, BM_Ret = as.numeric(BM_Ret))]
  setorder(.b0, Date)
  .b0[, lvl := cumprod(1 + BM_Ret)]
  .bm <- .b0[, .(Date, lvl)]
  .bm_src <- "BM_Ret 누적(BM_Close 열 부재 · changed(8))"
  rm(.b0)
}
if (!inherits(.bm$Date, "Date")) .bm[, Date := as.Date(Date)]
.bm <- unique(.bm, by = "Date")
setorder(.bm, Date)
.bmj <- .bm[.QE[, .(Date)], on = "Date", roll = .BM_ROLL]
.QE[, bml := .bmj$lvl]
rm(.bmj)
setorder(.QE, si)
.QE[, bml_l := shift(bml)]
.QE[, bmr := fifelse(is.finite(bml) & is.finite(bml_l) & bml_l > 0, bml / bml_l - 1, NA_real_)]
if (.QE[si >= 2L, mean(is.finite(bmr))] < 0.9)
  stop(sprintf("%s 벤치 분기수익 커버리지 %.1f%% — 벤치 패널 확인", .TAG, 100 * .QE[si >= 2L, mean(is.finite(bmr))]))

.P <- copy(.rd)
.P[, si_l := shift(si), by = Ticker]
.P[, cl_l := shift(Close), by = Ticker]
.P[.QE, on = "si", bmr := i.bmr]
.P[, rr := NA_real_]
.P[is.finite(si_l) & si_l == si - 1L & is.finite(cl_l) & cl_l > 0 & is.finite(bmr),
   rr := (Close / cl_l - 1) - bmr]
.P[, c("si_l", "cl_l", "bmr") := NULL]
# 표적 = 다음 분기의 상대수익. (Ticker, si-1) 조인으로 붙이고, 소비는 §7 에서 잘린다.
.LB <- .P[is.finite(rr), .(Ticker, si_dec = si - 1L, y = rr)]
.P[, y := NA_real_]
.P[.LB, on = .(Ticker, si = si_dec), y := i.y]
rm(.LB)
cat(sprintf("%s 벤치 원천 = %s · 상대수익 유한 %d행(적격 %.1f%%) · 표적 유한 %d행\n",
            .TAG, .bm_src, .P[is.finite(rr), .N],
            100 * .P[ELIG == TRUE, mean(is.finite(rr))], .P[is.finite(y), .N]))

# =============================================================================
# 5. 회계 관측 패널 — 자본총계 · 부채총계 · TTM 순이익 → P/B · Book Value · P/E · Liability
#    ★분기 해상도 유지를 위해 두 원천을 합친다 ★changed(7):
#      (A) .cache/fundamental_merged.parquet 의 **비-DART**(QuantiWise xlsx 분기) 원값
#      (B) .cache/fundamental_dart_quarterly.parquet (DART 분기 · 유량은 이미 TTM)
#      (C) .cache/fundamental_merged.parquet 의 **DART 사업연도**(연 1회 · qn=4) — 잔여 보전
#    우선순위 B > A > C. (A) 만 읽으면 2016년부터 관측이 연 1회가 되어 '연속 관측 간 변화'가
#    통째로 결측이 된다 — 이 판은 그 침묵 실패를 막는다.
# =============================================================================
.tkfix <- function(v) {
  ov <- function(x) length(intersect(unique(x), .tk_elig)) / max(1L, length(.tk_elig))
  cands <- list(raw = v, strip = sub("^A", "", v), add = paste0("A", v))
  ovs <- vapply(cands, ov, numeric(1))
  pick <- names(ovs)[which.max(ovs)]
  return(list(v = cands[[pick]], pick = pick, ovs = ovs))
}

# ── (A)(C) fundamental_merged ────────────────────────────────────────────────
.fm_path <- file.path(.CACHE, "fundamental_merged.parquet")
if (!file.exists(.fm_path))
  stop(sprintf("%s 회계 패널 부재: %s — 입력 4종 중 3종의 원천. data_gap 적재 대상", .TAG, .fm_path))
.fm <- as.data.table(dplyr::collect(dplyr::filter(arrow::open_dataset(.fm_path, format = "parquet"),
                                                  Item %in% .ITEMS)))
if (!all(c("Ticker", "Period", "Item", "Value", "Source") %in% names(.fm)))
  stop(sprintf("%s 회계 패널 스키마 불일치: %s", .TAG, paste(names(.fm), collapse = ",")))
.fm <- .fm[, .(Ticker = as.character(Ticker), Period = as.character(Period),
               Item = as.character(Item), Value = as.numeric(Value), Source = as.character(Source))]
.fm <- .fm[is.finite(Value)]
.fm[, fy := as.integer(substr(Period, 1L, 4L))]
.fm[, mm := as.integer(substr(Period, 5L, 6L))]
.fm <- .fm[is.finite(fy) & mm %in% c(3L, 6L, 9L, 12L)]
.fm[, qn := mm %/% 3L]
.fm[, is_dart := Source == "DART"]
.tf <- .tkfix(.fm$Ticker)
if (max(.tf$ovs) <= 0)
  stop(sprintf("%s 회계 패널이 적격 종목과 0건 교차(raw %.3f · strip %.3f · add %.3f)",
               .TAG, .tf$ovs[["raw"]], .tf$ovs[["strip"]], .tf$ovs[["add"]]))
.fm[, Ticker := .tf$v]
cat(sprintf("%s merged 종목코드 형식 = %s (교차율 raw %.3f · strip %.3f · add %.3f)\n",
            .TAG, .tf$pick, .tf$ovs[["raw"]], .tf$ovs[["strip"]], .tf$ovs[["add"]]))
.fm <- .fm[Ticker %in% .tk_elig]
if (nrow(.fm) == 0L) stop(sprintf("%s 회계 패널 교차 0행", .TAG))
setorder(.fm, Ticker, Item, fy, qn, is_dart)
.fm <- unique(.fm, by = c("Ticker", "Item", "fy", "qn", "is_dart"))
.fx <- .fm[is_dart == FALSE]     # (A) xlsx 분기
.fd <- .fm[is_dart == TRUE]      # (C) DART 사업연도
rm(.fm)

# (A-1) 유량 형식 판별: 매출 4기 합 ÷ 4기값 중앙값 > 3 → 단일기 유량, 아니면 누적  ★changed(6)
if (.fx[Item == "Revenue", .N] == 0L)
  stop(sprintf("%s xlsx 매출 행 0 — 분기 유량 형식을 판별할 수 없다(추정 금지)", .TAG))
.rvw <- dcast(.fx[Item == "Revenue"], Ticker + fy ~ qn, value.var = "Value")
for (.cc in c("1", "2", "3", "4")) if (!.cc %in% names(.rvw)) .rvw[, (.cc) := NA_real_]
setnames(.rvw, c("1", "2", "3", "4"), c("v1", "v2", "v3", "v4"))
.rvw <- .rvw[is.finite(v1) & is.finite(v2) & is.finite(v3) & is.finite(v4) & v4 > 0]
if (nrow(.rvw) < .DET_MIN)
  stop(sprintf("%s 유량 형식 판별 표본 %d < %d — 판별 불가(추정 금지)", .TAG, nrow(.rvw), .DET_MIN))
.rat_med <- stats::median((.rvw$v1 + .rvw$v2 + .rvw$v3 + .rvw$v4) / .rvw$v4)
.SINGLE_Q <- .rat_med > 3
cat(sprintf("%s xlsx 유량 형식 = %s (매출 4기합/4기값 중앙 %.2f · n=%d)\n",
            .TAG, if (.SINGLE_Q) "단일기 유량" else "누적(YTD)", .rat_med, nrow(.rvw)))
rm(.rvw)

# (A-2) 순이익 → 누적(YTD) → TTM
if (.fx[Item == "NetIncome", .N] == 0L)
  stop(sprintf("%s xlsx 순이익 행 0 — P/E 입력의 원천. data_gap 적재 대상", .TAG))
.niw <- dcast(.fx[Item == "NetIncome"], Ticker + fy ~ qn, value.var = "Value")
for (.cc in c("1", "2", "3", "4")) if (!.cc %in% names(.niw)) .niw[, (.cc) := NA_real_]
setnames(.niw, c("1", "2", "3", "4"), c("n1", "n2", "n3", "n4"))
.Y <- .niw
rm(.niw)
if (isTRUE(.SINGLE_Q)) {
  .Y[, u1 := n1]
  .Y[, u2 := n1 + n2]
  .Y[, u3 := n1 + n2 + n3]
  .Y[, u4 := n1 + n2 + n3 + n4]
} else {
  .Y[, u1 := n1]; .Y[, u2 := n2]; .Y[, u3 := n3]; .Y[, u4 := n4]
}
.Y[, c("n1", "n2", "n3", "n4") := NULL]
setorder(.Y, Ticker, fy)
.Y[, fy_l := shift(fy), by = Ticker]
.Y[, p1 := shift(u1), by = Ticker]
.Y[, p2 := shift(u2), by = Ticker]
.Y[, p3 := shift(u3), by = Ticker]
.Y[, p4 := shift(u4), by = Ticker]
.Y[!(is.finite(fy_l) & fy_l == fy - 1L), c("p1", "p2", "p3", "p4") := NA_real_]
.Y[, t1 := u1 + p4 - p1]
.Y[, t2 := u2 + p4 - p2]
.Y[, t3 := u3 + p4 - p3]
.Y[, t4 := u4]
.TTM <- melt(.Y[, .(Ticker, fy, t1, t2, t3, t4)], id.vars = c("Ticker", "fy"),
             measure.vars = c("t1", "t2", "t3", "t4"), variable.name = "qv", value.name = "ttm")
.TTM[, qn := as.integer(sub("^t", "", as.character(qv)))]
.TTM <- .TTM[is.finite(ttm), .(Ticker, fy, qn, ttm)]
rm(.Y)

# (A-3) 시점 항목 + TTM → 관측 블록
if (.fx[Item %in% c("TotalEquity", "TotalLiab"), .N] == 0L)
  stop(sprintf("%s xlsx 자본총계·부채총계 행 0 — P/B·Book Value·Liability 의 원천", .TAG))
.bsx <- dcast(.fx[Item %in% c("TotalEquity", "TotalLiab")], Ticker + fy + qn ~ Item, value.var = "Value")
for (.cc in c("TotalEquity", "TotalLiab")) if (!.cc %in% names(.bsx)) .bsx[, (.cc) := NA_real_]
.OBS_X <- merge(.bsx, .TTM, by = c("Ticker", "fy", "qn"), all = TRUE)
.OBS_X[, src := "xlsx_q"]
rm(.bsx, .TTM, .fx)

# (C) DART 사업연도 — NetIncome = 사업연도 합계 = 4분기 시점의 TTM. qn != 4 행은 TTM 아님 → NA.
.OBS_D <- NULL; .n_d_nonq4 <- 0L
if (nrow(.fd) > 0L) {
  .bsd <- dcast(.fd, Ticker + fy + qn ~ Item, value.var = "Value")
  for (.cc in c("TotalEquity", "TotalLiab", "NetIncome")) if (!.cc %in% names(.bsd)) .bsd[, (.cc) := NA_real_]
  .n_d_nonq4 <- .bsd[qn != 4L, .N]
  .OBS_D <- .bsd[, .(Ticker, fy, qn, TotalEquity, TotalLiab,
                     ttm = fifelse(qn == 4L, NetIncome, NA_real_), src = "dart_a")]
  rm(.bsd)
}
rm(.fd)

# (B) DART 분기 패널 — 있으면 쓴다(없으면 큰 소리로 알리고 A+C 로 진행) ★changed(7)
.dq_path <- file.path(.CACHE, "fundamental_dart_quarterly.parquet")
.OBS_Q <- NULL
.dq_note <- "미사용"
if (file.exists(.dq_path)) {
  .dq_need <- c("Ticker", "bsns_year", "quarter", "TotalEquity", "TotalLiab", "NetIncome")
  .dsq <- arrow::open_dataset(.dq_path, format = "parquet")
  if (all(.dq_need %in% names(.dsq))) {
    .dq <- as.data.table(dplyr::collect(dplyr::select(.dsq, dplyr::all_of(.dq_need))))
    .dq <- .dq[, .(Ticker = as.character(Ticker), fy = as.integer(bsns_year), qn = as.integer(quarter),
                   TotalEquity = as.numeric(TotalEquity), TotalLiab = as.numeric(TotalLiab),
                   ttm = as.numeric(NetIncome))]
    .dq <- .dq[is.finite(fy) & qn %in% 1:4]
    .tfq <- .tkfix(.dq$Ticker)
    .dq[, Ticker := .tfq$v]
    .dq <- .dq[Ticker %in% .tk_elig]
    if (nrow(.dq) > 0L) {
      .dq[, src := "dart_q"]
      setorder(.dq, Ticker, fy, qn)
      .OBS_Q <- unique(.dq, by = c("Ticker", "fy", "qn"))
      .dq_note <- sprintf("%d행 · %d종 · FY%d~%d · 코드형식 %s",
                          nrow(.OBS_Q), uniqueN(.OBS_Q$Ticker), min(.OBS_Q$fy), max(.OBS_Q$fy), .tfq$pick)
    } else .dq_note <- "적격 종목 교차 0행"
    rm(.dq)
  } else {
    .dq_note <- sprintf("스키마 불일치(결손 %s)", paste(setdiff(.dq_need, names(.dsq)), collapse = ","))
  }
  rm(.dsq)
} else .dq_note <- "파일 없음"
if (is.null(.OBS_Q))
  cat(sprintf("%s ⚠ DART 분기 패널 %s — 2016년 이후 회계 관측이 연 1회가 되어 '연속 관측 간 변화'가 그 구간에서 결측이 된다(아래 연도별 커버리지 확인)\n",
              .TAG, .dq_note))
else
  cat(sprintf("%s DART 분기 패널 = %s\n", .TAG, .dq_note))

# ── 세 블록 합치기 (우선순위 dart_q > xlsx_q > dart_a) ───────────────────────
.OBS <- rbindlist(list(.OBS_Q, .OBS_X, .OBS_D), use.names = TRUE, fill = TRUE)
rm(.OBS_Q, .OBS_X, .OBS_D)
.OBS <- .OBS[is.finite(fy) & qn %in% 1:4]
.OBS[, prio := fifelse(src == "dart_q", 1L, fifelse(src == "xlsx_q", 2L, 3L))]
setorder(.OBS, Ticker, fy, qn, prio)
.OBS <- unique(.OBS, by = c("Ticker", "fy", "qn"))

# ── 기간말 시가총액 → P/B · P/E (비율은 회계기간 말 가격 기준 · 소비는 공시 가용일) ──
.OBS[, pend := as.Date(sprintf("%04d-%02d-01", fifelse(qn == 4L, fy + 1L, fy),
                               fifelse(qn == 4L, 1L, qn * 3L + 1L))) - 1L]
.MC <- RAWDATA[Ticker %in% .tk_elig & is.finite(Size) & Size > 0,
               .(Ticker = as.character(Ticker), Date, Size = as.numeric(Size))]
.MC <- unique(.MC, by = c("Ticker", "Date"))
setorder(.MC, Ticker, Date)
.mcj <- .MC[.OBS[, .(Ticker, pend)], on = .(Ticker, Date = pend), roll = .MC_ROLL]
.OBS[, mc := .mcj$Size]
rm(.MC, .mcj)
.OBS[, pb   := .rdiv(mc, TotalEquity)]
.OBS[, pe   := .rdiv(mc, ttm)]
.OBS[, bv   := fifelse(is.finite(TotalEquity), TotalEquity, NA_real_)]
.OBS[, liab := fifelse(is.finite(TotalLiab), TotalLiab, NA_real_)]

# ── 식 (5) 추세제거 — **연속 회계분기**(fqi 차 1) ∧ **같은 원천**일 때만 ★changed(6)(7)
setorder(.OBS, Ticker, fy, qn)
.OBS[, fqi := fy * 4L + qn]
.OBS[, fqi_l := shift(fqi), by = Ticker]
.OBS[, src_l := shift(src), by = Ticker]
.OBS[, pb_l := shift(pb), by = Ticker]
.OBS[, pe_l := shift(pe), by = Ticker]
.OBS[, bv_l := shift(bv), by = Ticker]
.OBS[, lb_l := shift(liab), by = Ticker]
.OBS[, lag_q  := is.finite(fqi_l) & (fqi_l == fqi - 1L)]
.OBS[, lag_ok := lag_q & !is.na(src_l) & (src_l == src)]
.n_seam <- .OBS[lag_q %in% TRUE & lag_ok %in% FALSE, .N]
.OBS[lag_ok %in% FALSE, c("pb_l", "pe_l", "bv_l", "lb_l") := NA_real_]
.OBS[, d_pb   := .pch(pb, pb_l)]
.OBS[, d_pe   := .pch(pe, pe_l)]
.OBS[, d_bv   := .pch(bv, bv_l)]
.OBS[, d_liab := .pch(liab, lb_l)]
.OBS[, usable := .usable_of(fy, qn)]
setorder(.OBS, Ticker, usable, prio)
.OBS <- unique(.OBS, by = c("Ticker", "usable"))
cat(sprintf("%s 회계 관측 %d행(%d종 · FY%d~%d · 원천 dart_q %d / xlsx_q %d / dart_a %d · DART 비-Q4 %d · 원천 이음매 결측화 %d) · 기간말 시총 %.1f%% · 자본총계 %.1f%% · TTM 순이익 %.1f%% · 연속분기 직전값 %.1f%%\n",
            .TAG, nrow(.OBS), uniqueN(.OBS$Ticker), min(.OBS$fy), max(.OBS$fy),
            .OBS[src == "dart_q", .N], .OBS[src == "xlsx_q", .N], .OBS[src == "dart_a", .N],
            .n_d_nonq4, .n_seam,
            100 * .OBS[, mean(is.finite(mc))], 100 * .OBS[, mean(is.finite(TotalEquity))],
            100 * .OBS[, mean(is.finite(ttm))], 100 * .OBS[, mean(lag_ok %in% TRUE)]))

# =============================================================================
# 6. 시그널 격자에 회계 특성 as-of 부착 (가용일 <= 시그널일 · 캐리 <= 400일)  ★changed(7)
# =============================================================================
.FJ <- .OBS[, .(Ticker, usable, d_pb, d_pe, d_bv, d_liab, bv_lvl = bv)]
setorder(.FJ, Ticker, usable)
.jn <- .FJ[.P[, .(Ticker, Date)], on = .(Ticker, usable = Date), roll = .CARRY_DAYS]
.P[, c("d_pb", "d_pe", "d_bv", "d_liab", "bv_lvl") :=
     .jn[, .(d_pb, d_pe, d_bv, d_liab, bv_lvl)]]
rm(.jn, .FJ, .OBS)
cat(sprintf("%s 특성 부착 — 적격행 커버리지 %s · 회계 관측 있는 적격행 %.1f%%\n", .TAG,
            paste(sprintf("%s %.1f%%", .FEATS,
                          100 * c(.P[ELIG == TRUE, mean(is.finite(d_pb))], .P[ELIG == TRUE, mean(is.finite(rr))],
                                  .P[ELIG == TRUE, mean(is.finite(d_bv))], .P[ELIG == TRUE, mean(is.finite(d_pe))],
                                  .P[ELIG == TRUE, mean(is.finite(d_liab))])), collapse = " · "),
            100 * .P[ELIG == TRUE, mean(is.finite(bv_lvl))]))
.cvy <- .P[ELIG == TRUE & year(Date) >= 2005L, .(p = 100 * mean(is.finite(d_pb))), by = .(yr = year(Date))]
setorder(.cvy, yr)
cat(sprintf("%s 연도별 d_pb 커버리지 — %s\n", .TAG,
            paste(sprintf("%d:%.0f", .cvy$yr, .cvy$p), collapse = " ")))

# =============================================================================
# 7. Random Forest — ★**종목별 모델 1개**(논문 IV.B 'Local Learning')  ★changed(2)(5)(9)(10)
#    "we built one model for each stock for all three algorithms" — 종목 루프 안에서만 적합한다.
#    확장창: 종목 i 의 분기 s 예측 학습집합 = 그 종목의 si < s 행 중 표적 유한.
#    si' < s ⇒ si' <= s-1 ⇒ 표적 실현 분기 si'+1 <= s = 결정 분기 (매 적합에서 재단언).
# =============================================================================
.M <- .P[ELIG == TRUE & is.finite(rr) & is.finite(bv_lvl)]
if (nrow(.M) == 0L) stop(sprintf("%s 모델 패널 0행 — 특성 커버리지 확인", .TAG))
.pred_si <- sort(unique(.M[Date >= .START, si]))
if (!length(.pred_si)) stop(sprintf("%s 예측 대상 분기 0개 — .START 이후 격자 확인", .TAG))
setkeyv(.M, c("Ticker", "si"))
.tk_list <- .M[, sort(unique(Ticker))]

.out  <- vector("list", length(.tk_list))
.trsz <- vector("list", length(.tk_list))
.n_fit <- 0L; .n_short <- 0L
for (.ti in seq_along(.tk_list)) {
  .tk <- .tk_list[.ti]
  .d  <- .M[.(.tk), nomatch = 0L]                    # 이 종목 행만 (si 오름차순)
  .n  <- nrow(.d)
  .tst <- which((.d$si %in% .pred_si) & (.d$Date >= .START))
  if (!length(.tst)) next
  .X    <- as.matrix(.d[, .FEATS, with = FALSE])
  .yv   <- as.numeric(.d$y)
  .siv  <- as.integer(.d$si)
  .hasy <- is.finite(.yv)
  .pv   <- rep(NA_real_, .n)
  .trn  <- rep(NA_integer_, .n)
  for (.i in .tst) {
    .tr <- which(.hasy & (seq_len(.n) < .i))
    if (length(.tr) < .MIN_TR_TK) { .n_short <- .n_short + 1L; next }
    # PIT 재단언 — 학습 표적은 si+1 분기말에 실현된다. 실현 분기 <= 결정 분기여야 한다.
    if (max(.siv[.tr]) + 1L > .siv[.i])
      stop(sprintf("%s PIT: %s 학습 표적 실현 분기 %d > 결정 분기 %d",
                   .TAG, .tk, max(.siv[.tr]) + 1L, .siv[.i]))
    .z <- .zfit(.X[.tr, , drop = FALSE], .X[.i, , drop = FALSE])
    # 시드 = (분기, 종목) 단사 — 곱수 1e5 > 종목수라 (si,ti) 쌍이 겹치지 않고, %% 로 상한도 막는다
    .sd_i <- as.integer((.SEED_BASE + .siv[.i] * 100000 + .ti) %% 2147483647)
    set.seed(.sd_i)
    .fit <- ranger(x = .z$tr, y = .yv[.tr],
                   num.trees = .RF_TREES, mtry = .NP, min.node.size = .RF_MINNODE,
                   replace = TRUE, sample.fraction = 1, splitrule = "variance",
                   num.threads = 1L, seed = .sd_i, verbose = FALSE)
    .pv[.i]  <- as.numeric(predict(.fit, data = .z$te, num.threads = 1L)$predictions)[1]
    .trn[.i] <- length(.tr)
    .n_fit <- .n_fit + 1L
  }
  .ok <- which(is.finite(.pv))
  if (length(.ok)) {
    .out[[.ti]]  <- data.table(Date = .d$Date[.ok], Ticker = .tk, Score = .pv[.ok])
    .trsz[[.ti]] <- .trn[!is.na(.trn)]
  }
  if (.ti %% 100L == 0L || .ti == length(.tk_list))
    cat(sprintf("%s   종목 %d/%d · 누적 적합 %d · 경과 %.1f분\n",
                .TAG, .ti, length(.tk_list), .n_fit,
                as.numeric(difftime(Sys.time(), .t0, units = "mins"))))
}
.tr_sizes <- unlist(.trsz, use.names = FALSE)
if (!length(.tr_sizes)) stop(sprintf("%s 적합 0회 — 종목별 학습집합 하한 %d분기 확인", .TAG, .MIN_TR_TK))
FACTORS <- rbindlist(Filter(Negate(is.null), .out), use.names = TRUE)
if (nrow(FACTORS) == 0L) stop(sprintf("%s FACTORS 0행 — 종목별 학습집합 하한·커버리지 확인", .TAG))
setorder(FACTORS, Date, -Score, Ticker)
cat(sprintf("%s 종목별 RF 적합 %d회(종목 %d · 학습집합 %d분기 미달로 건너뜀 %d) · 학습집합 분기수 최소/중앙/최대 %d/%d/%d · FACTORS %d행 %d분기(%s ~ %s) · 분기당 예측 %d~%d종\n",
            .TAG, .n_fit, uniqueN(FACTORS$Ticker), .MIN_TR_TK, .n_short,
            min(.tr_sizes), as.integer(stats::median(.tr_sizes)), max(.tr_sizes),
            nrow(FACTORS), uniqueN(FACTORS$Date),
            as.character(min(FACTORS$Date)), as.character(max(FACTORS$Date)),
            FACTORS[, .N, by = Date][, min(N)], FACTORS[, .N, by = Date][, max(N)]))

# =============================================================================
# 8. PORTFOLIO — 예측 상대수익 상위 1/3 동일가중 롱 (논문 'Buy' 포트폴리오)  ★changed(9)
#    동률은 (Score 내림차순, 종목코드)로 결정론적으로 깬다.
# =============================================================================
PORTFOLIO <- FACTORS[is.finite(Score), {
  .SD2 <- .SD[order(-Score, Ticker)]
  k <- .k_top(nrow(.SD2))
  if (nrow(.SD2) < .MIN_N || k < 2L) NULL else data.table(Ticker = .SD2$Ticker[1:k], Weight = 1 / k, Leg = "long")
}, by = Date, .SDcols = c("Ticker", "Score")]
if (nrow(PORTFOLIO) == 0L) stop(sprintf("%s PORTFOLIO 0행", .TAG))
setcolorder(PORTFOLIO, c("Date", "Ticker", "Weight", "Leg"))
.nb <- PORTFOLIO[, .(n = .N, sw = sum(Weight)), by = Date]
if (max(abs(.nb$sw - 1)) > 1e-9) stop(sprintf("%s 비중 합 != 1 (최대 편차 %.3g)", .TAG, max(abs(.nb$sw - 1))))
cat(sprintf("%s PORTFOLIO %d행 · %d분기 리밸 · 보유 %d~%d종(중앙 %d) · Σw=1 · 롱온리 · 소요 %.1f분\n",
            .TAG, nrow(PORTFOLIO), nrow(.nb), min(.nb$n), max(.nb$n),
            as.integer(stats::median(.nb$n)), as.numeric(difftime(Sys.time(), .t0, units = "mins"))))
cat(sprintf("%s adapted(기전 = 논문 그대로: 식 (5) 백분율 변화 → 식 (6) 학습집합 표준화 → **종목별** RF 로 다음 분기 상대수익 회귀 → 상위 1/3 EW 분기 리밸) · 입력 %d종 = %s · 설비투자 = data_gap · 정본 = FIDELITY.json\n",
            .TAG, .NP, paste(.FEAT_PAPER, collapse = " · ")))
