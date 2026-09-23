# =============================================================================
# engine.R — RP_AUTO_2202_05702
# Yuxuan Huang · Luiz Fernando Capretz · Danny Ho,
#   "Machine Learning for Stock Prediction Based on Fundamental Analysis"
#   arXiv:2202.05702 (IEEE SSCI 2021) — https://arxiv.org/abs/2202.05702
#   본문 = r.jina.ai PDF 텍스트 프록시(2022 논문 · arxiv html 렌더 없음 · /html/v1 = 404)
#
# ★라벨(adapted)·변경 전수 신고·러너 사양·감사 응답의 정본 = FIDELITY.json.
#   이 주석은 아무것도 결정하지 않는다. 코드 옆 ★changed(n) = FIDELITY.json changed 항목 번호.
#
# 논문 기전(그대로): 분기 공시 지표를 "consecutive observations 간 백분율 변화"로 추세제거하고,
#   표적 = 다음 분기의 **벤치마크 대비 상대수익**(stock quarterly return − index quarterly return)을
#   Random Forest 로 회귀. 예측 상대수익으로 유니버스를 정렬해 **상위 1/3** 을 동일가중 보유,
#   **분기** 리밸런싱. 학습집합 통계(mean/sd)로 표준화하고 결측은 평균 대치.
#   입력은 논문이 RF 중요도로 고른 top 6 (Table 3): P/B · Relative Return · Book Value ·
#   P/E · Capital Expenditure · Liability.
#
# 이 구현: 입력 5종(P/B · Relative Return · Book Value · P/E · Liability — 설비투자는
#   KR 원천 결손 data_gap · changed(4)) 을 RAWDATA(수정종가 · 시가총액 · 멤버십) + 회계 패널
#   (.cache/fundamental_merged.parquet 원값 · 자본총계 · 부채총계 · 순이익)에서 만들고,
#   시그널 격자 = **각 달력분기 마지막 거래일**(하네스가 시그널일을 리밸일로 읽는다 · changed(3)).
#   모델은 매 시그널 분기마다 확장창으로 재적합(논문의 고정 60/20/20 분할은 2005~ 전기간
#   시그널을 낼 수 없다 · changed(5)).
#
# 산출: FACTORS(Date, Ticker, Score)          — 그 분기말 적격 종목 전부 · Score = RF 예측 상대수익
#       PORTFOLIO(Date, Ticker, Weight, Leg)  — 상위 1/3 EW 롱 Σw=+1 (engine_direct)
#
# PIT(C1~C15) 구조 보장:
#   · 시그널일 t 의 특성 = t 이하 정보뿐. 가격 특성 = t 까지의 수정종가. 회계 특성 = 공시
#     가용일(usable) ≤ t 인 최신 관측(분기 5/15·8/15·11/15 · 4분기 = 익년 3/31 — pit.md C4).
#     Factor_Date 열은 쓰지 않는다(xlsx 경로가 4분기에도 일률 +45d ≈ 익년 2/14 라 3/31 대비 공격적 —
#     pit.md C4 경고). 가용일은 엔진이 SOT 규약으로 직접 계산한다.
#   · 표적 y(s) = 분기 s+1 의 상대수익이고 분기 s+1 마지막 거래일에 실현된다. 시그널 분기 s_pred 의
#     학습집합은 si <= s_pred - 1 로만 구성 → 실현일 <= t(s_pred) (구조적 상한 · 아래 §7 단언).
#   · 표준화·결측 대치 통계는 그 학습집합에서만 낸다(전 표본 통계 0건 · 확장창).
#   · 횡단면 정렬은 그날 집합 안에서만. 팩터 DB 미사용 · 유동성 스크린 없음(논문 우선).
#   · 음수 shift · lead() · 미래 인덱싱 0건. 표적은 (Ticker, si-1) 조인으로 붙이고 소비 시점에
#     si <= s_pred - 1 로 잘린다.
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
.MIN_TR_ROW <- 200L                    # ★changed(9) 학습집합 하한(행)
.MIN_TR_PER <- 4L                      # ★changed(9) 학습집합 하한(분기 수)
.DET_MIN    <- 100L                    # ★changed(6) 분기 유량 형식 판별 표본 하한(종목-연도)
.SEED_BASE  <- 220205702L              # ★changed(10) 시드 = 논문 번호(임의 상수) + 분기 인덱스
.RF_TREES   <- 100L                    # ★changed(2) sklearn RandomForestRegressor n_estimators 기본값
.RF_MINNODE <- 1L                      # ★changed(2) sklearn min_samples_split=2/min_samples_leaf=1 → 완전성장
.RF_THREADS <- 4L                      # ★changed(2) 스레드 고정(재현성)
.FEATS      <- c("d_pb", "rr", "d_bv", "d_pe", "d_liab")
.FEAT_PAPER <- c("P/B", "Relative Return", "Book Value", "P/E", "Liability")
.ITEMS      <- c("TotalEquity", "TotalLiab", "NetIncome", "Revenue")
stopifnot(length(.FEATS) == length(.FEAT_PAPER))

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
# 논문 추세제거: "percentage change between consecutive observations for all features".
#   부호가 바뀌는 항(순이익 파생 P/E)이 있어 분모는 |직전값| (논문 미명시 · changed(6))
.pch  <- function(v, l) fifelse(is.finite(v) & is.finite(l) & abs(l) > 0, (v - l) / abs(l), NA_real_)
.sdiv <- function(a, b) fifelse(is.finite(a) & is.finite(b) & b > 0, a / b, NA_real_)   # 양(+) 분모만
.mu1  <- function(v) { ok <- is.finite(v); if (!any(ok)) return(0); return(mean(v[ok])) }
.sd1  <- function(v) { ok <- is.finite(v); if (sum(ok) < 2L) return(0); return(stats::sd(v[ok])) }
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
# 상위 1/3 종목수 — floor(n/3) (논문 'one third' 의 정수화 · changed(9))
#   ★정수 나눗셈으로 센다 — floor(n * (1/3)) 은 배정도에서 6 → 1, 3 → 0 을 낸다
#   (6 * 0.3333333333333333 = 1.9999999999999998). 양성 대조가 이 자리를 잡는다.
.k_top <- function(n) as.integer(n) %/% .TOP_DIV

local({
  if (!isTRUE(all.equal(.pch(c(120, 12, -6, 5, 3), c(100, NA, 11, 0, -6)),
                        c(0.2, NA, (-6 - 11) / 11, NA, (3 + 6) / 6))))
    stop(sprintf("%s 백분율 변화 검산 실패", .TAG))
  if (!isTRUE(all.equal(.sdiv(c(10, 10, 10), c(2, 0, -2)), c(5, NA, NA))))
    stop(sprintf("%s 분모 가드 검산 실패", .TAG))
  u <- .usable_of(c(2010L, 2010L, 2010L, 2010L), c(1L, 2L, 3L, 4L))
  if (!identical(as.character(u), c("2010-05-15", "2010-08-15", "2010-11-15", "2011-03-31")))
    stop(sprintf("%s 공시 가용일 검산 실패", .TAG))
  if (!identical(.k_top(c(70L, 6L, 350L)), c(23L, 2L, 116L)))
    stop(sprintf("%s 상위 1/3 종목수 검산 실패", .TAG))
  # 상대수익: 종목 +20% · 벤치 +5% → 0.15
  if (!isTRUE(all.equal((120 / 100 - 1) - (105 / 100 - 1), 0.15)))
    stop(sprintf("%s 상대수익 검산 실패", .TAG))
  # TTM 항등: 단일기 유량 FY1 = 1,2,3,4 · FY2 = 5,6,7,8 → TTM(FY2,q1) = 2+3+4+5 = 14
  y1 <- cumsum(c(1, 2, 3, 4)); y2 <- cumsum(c(5, 6, 7, 8))
  if (!isTRUE(all.equal(y2[1] + y1[4] - y1[1], 14)))
    stop(sprintf("%s TTM 항등 검산 실패", .TAG))
  # 표준화: 결측은 학습집합 평균(표준화 후 0)
  v <- c(1, 2, 3, NA); m <- .mu1(v); s <- .sd1(v)
  z <- (v - m) / s; z[!is.finite(z)] <- 0
  if (!isTRUE(all.equal(m, 2)) || !isTRUE(all.equal(z[4], 0)) || !isTRUE(all.equal(z[2], 0)))
    stop(sprintf("%s 표준화·평균대치 검산 실패", .TAG))
  cat(sprintf("%s 양성 대조 통과 — 백분율 변화 · 분모 가드 · 공시 가용일(5/15·8/15·11/15·익년 3/31) · 상위 1/3 정수화 · 상대수익 · TTM 항등 · 표준화 평균대치\n", .TAG))
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
cat(sprintf("%s 격자 %d분기말(%s ~ %s · 진행 분기 제외 %d) × 적격 이력 종목 %d = %d행 · 마지막 분기말 적격 %d종\n",
            .TAG, nrow(.QE), as.character(min(.QE$Date)), as.character(max(.QE$Date)),
            .n_qe_all - nrow(.QE), length(.tk_elig), nrow(.rd),
            .rd[si == max(.QE$si), sum(ELIG)]))

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
# 표적 = 다음 분기의 상대수익. (Ticker, si-1) 조인으로 붙이고, 소비는 §7 에서 si <= s_pred-1 로 잘린다.
.LB <- .P[is.finite(rr), .(Ticker, si_dec = si - 1L, y = rr)]
.P[, y := NA_real_]
.P[.LB, on = .(Ticker, si = si_dec), y := i.y]
rm(.LB)
cat(sprintf("%s 벤치 원천 = %s · 상대수익 유한 %d행(적격 %d행 중 %.1f%%) · 표적 유한 %d행\n",
            .TAG, .bm_src, .P[is.finite(rr), .N], .P[ELIG == TRUE, .N],
            100 * .P[ELIG == TRUE, mean(is.finite(rr))], .P[is.finite(y), .N]))

# =============================================================================
# 5. 회계 관측 패널 — 자본총계 · 부채총계 · 순이익(TTM) → P/B · Book Value · P/E · Liability
#    원천 = .cache/fundamental_merged.parquet 의 원값 행 (Item/Value/Source long)  ★changed(6)(7)
# =============================================================================
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

# ── 종목코드 형식 정합 (두 패널 다 QuantiWise 계열이지만 접두 A 유무를 데이터로 판별) ★changed(7)
.ov <- function(v) length(intersect(unique(v), .tk_elig)) / max(1L, length(.tk_elig))
.cands <- list(raw = .fm$Ticker, strip = sub("^A", "", .fm$Ticker), add = paste0("A", .fm$Ticker))
.ovs <- vapply(.cands, .ov, numeric(1))
.pick <- names(.ovs)[which.max(.ovs)]
if (max(.ovs) <= 0)
  stop(sprintf("%s 회계 패널이 적격 종목과 0건 교차(raw %.3f · strip %.3f · add %.3f) — 종목코드 형식 확인",
               .TAG, .ovs[["raw"]], .ovs[["strip"]], .ovs[["add"]]))
if (!identical(.pick, "raw")) .fm[, Ticker := .cands[[.pick]]]
cat(sprintf("%s 종목코드 형식 = %s (교차율 raw %.3f · strip %.3f · add %.3f)\n",
            .TAG, .pick, .ovs[["raw"]], .ovs[["strip"]], .ovs[["add"]]))
.fm <- .fm[Ticker %in% .tk_elig]
if (nrow(.fm) == 0L) stop(sprintf("%s 회계 패널 교차 0행", .TAG))
setorder(.fm, Ticker, Item, fy, qn, -is_dart)
.fm <- unique(.fm, by = c("Ticker", "Item", "fy", "qn"))

# ── (a) 유량 형식 판별: 매출 4기 합 ÷ 4기값 중앙값 > 3 → 단일기 유량, 아니면 누적  ★changed(6)
#    DART 행(사업연도 합계)은 판별 표본에서 제외한다 — 섞으면 비율이 무너진다.
.rvw <- dcast(.fm[Item == "Revenue" & is_dart == FALSE], Ticker + fy ~ qn, value.var = "Value")
for (.cc in c("1", "2", "3", "4")) if (!.cc %in% names(.rvw)) .rvw[, (.cc) := NA_real_]
setnames(.rvw, c("1", "2", "3", "4"), c("v1", "v2", "v3", "v4"))
.rvw <- .rvw[is.finite(v1) & is.finite(v2) & is.finite(v3) & is.finite(v4) & v4 > 0]
if (nrow(.rvw) < .DET_MIN)
  stop(sprintf("%s 유량 형식 판별 표본 %d < %d — 판별 불가(추정 금지)", .TAG, nrow(.rvw), .DET_MIN))
.rat <- (.rvw$v1 + .rvw$v2 + .rvw$v3 + .rvw$v4) / .rvw$v4
.rat_med <- stats::median(.rat)
.SINGLE_Q <- .rat_med > 3
cat(sprintf("%s 유량 형식 = %s (매출 4기합/4기값 중앙 %.2f · n=%d)\n",
            .TAG, if (.SINGLE_Q) "단일기 유량" else "누적(YTD)", .rat_med, nrow(.rvw)))
rm(.rvw)

# ── (b) 순이익 → 누적(YTD) → TTM. DART 행은 그 자체가 사업연도 합계 = YTD(4기).
.niw <- dcast(.fm[Item == "NetIncome"], Ticker + fy ~ qn, value.var = "Value")
.ndw <- dcast(.fm[Item == "NetIncome"], Ticker + fy ~ qn, value.var = "is_dart")
for (.cc in c("1", "2", "3", "4")) {
  if (!.cc %in% names(.niw)) .niw[, (.cc) := NA_real_]
  if (!.cc %in% names(.ndw)) .ndw[, (.cc) := NA]
}
setnames(.niw, c("1", "2", "3", "4"), c("n1", "n2", "n3", "n4"))
setnames(.ndw, c("1", "2", "3", "4"), c("f1", "f2", "f3", "f4"))
.Y <- merge(.niw, .ndw[, .(Ticker, fy, f4)], by = c("Ticker", "fy"), all.x = TRUE)
rm(.niw, .ndw)
if (isTRUE(.SINGLE_Q)) {
  .Y[, u1 := n1]
  .Y[, u2 := n1 + n2]
  .Y[, u3 := n1 + n2 + n3]
  .Y[, u4 := fifelse(f4 %in% TRUE, n4, n1 + n2 + n3 + n4)]
} else {
  .Y[, u1 := n1]; .Y[, u2 := n2]; .Y[, u3 := n3]; .Y[, u4 := n4]
}
.Y[, c("n1", "n2", "n3", "n4", "f4") := NULL]
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

# ── (c) 시점 항목(자본총계 · 부채총계) + 기간말 시가총액 → P/B · P/E · Book Value · Liability
.bsw <- dcast(.fm[Item %in% c("TotalEquity", "TotalLiab")], Ticker + fy + qn ~ Item, value.var = "Value")
for (.cc in c("TotalEquity", "TotalLiab")) if (!.cc %in% names(.bsw)) .bsw[, (.cc) := NA_real_]
.OBS <- merge(.bsw, .TTM, by = c("Ticker", "fy", "qn"), all = TRUE)
rm(.bsw, .TTM)
.OBS <- .OBS[is.finite(fy) & qn %in% 1:4]
# 기간말 = 그 기간 마지막 달의 말일 (다음 달 1일 − 1일 · 무효 문자열 미생성)
.OBS[, pend := as.Date(sprintf("%04d-%02d-01", fifelse(qn == 4L, fy + 1L, fy),
                               fifelse(qn == 4L, 1L, qn * 3L + 1L))) - 1L]
.MC <- RAWDATA[Ticker %in% .tk_elig & is.finite(Size) & Size > 0,
               .(Ticker = as.character(Ticker), Date, Size = as.numeric(Size))]
.MC <- unique(.MC, by = c("Ticker", "Date"))
setorder(.MC, Ticker, Date)
.mcj <- .MC[.OBS[, .(Ticker, pend)], on = .(Ticker, Date = pend), roll = .MC_ROLL]
.OBS[, mc := .mcj$Size]
rm(.MC, .mcj)
.OBS[, pb   := .sdiv(mc, TotalEquity)]
.OBS[, pe   := .sdiv(mc, ttm)]
.OBS[, bv   := fifelse(is.finite(TotalEquity), TotalEquity, NA_real_)]
.OBS[, liab := fifelse(is.finite(TotalLiab), TotalLiab, NA_real_)]
# 논문 추세제거 = consecutive observations 간 백분율 변화 (연속 회계분기만)
setorder(.OBS, Ticker, fy, qn)
.OBS[, fqi := fy * 4L + qn]
.OBS[, fqi_l := shift(fqi), by = Ticker]
.OBS[, pb_l := shift(pb), by = Ticker]
.OBS[, pe_l := shift(pe), by = Ticker]
.OBS[, bv_l := shift(bv), by = Ticker]
.OBS[, lb_l := shift(liab), by = Ticker]
.OBS[!(is.finite(fqi_l) & fqi_l == fqi - 1L), c("pb_l", "pe_l", "bv_l", "lb_l") := NA_real_]
.OBS[, d_pb   := .pch(pb, pb_l)]
.OBS[, d_pe   := .pch(pe, pe_l)]
.OBS[, d_bv   := .pch(bv, bv_l)]
.OBS[, d_liab := .pch(liab, lb_l)]
.OBS[, usable := .usable_of(fy, qn)]
setorder(.OBS, Ticker, usable)
.OBS <- unique(.OBS, by = c("Ticker", "usable"))
cat(sprintf("%s 회계 관측 %d행(%d종 · %d~%d) · 기간말 시총 %.1f%% · 자본총계 %.1f%% · 부채총계 %.1f%% · TTM 순이익 %.1f%% · P/B %.1f%% · P/E %.1f%%\n",
            .TAG, nrow(.OBS), uniqueN(.OBS$Ticker), min(.OBS$fy), max(.OBS$fy),
            100 * .OBS[, mean(is.finite(mc))], 100 * .OBS[, mean(is.finite(TotalEquity))],
            100 * .OBS[, mean(is.finite(TotalLiab))], 100 * .OBS[, mean(is.finite(ttm))],
            100 * .OBS[, mean(is.finite(pb))], 100 * .OBS[, mean(is.finite(pe))]))
rm(.fm)

# =============================================================================
# 6. 시그널 격자에 회계 특성 as-of 부착 (가용일 <= 시그널일 · 캐리 <= 400일)  ★changed(7)
# =============================================================================
.FJ <- .OBS[, .(Ticker, usable, d_pb, d_pe, d_bv, d_liab, bv_lvl = bv)]
setorder(.FJ, Ticker, usable)
.jn <- .FJ[.P[, .(Ticker, Date)], on = .(Ticker, usable = Date), roll = .CARRY_DAYS]
.P[, c("d_pb", "d_pe", "d_bv", "d_liab", "bv_lvl") :=
     .jn[, .(d_pb, d_pe, d_bv, d_liab, bv_lvl)]]
rm(.jn, .FJ, .OBS)
.cov_txt <- paste(sprintf("%s %.1f%%", .FEATS,
                          100 * c(.P[ELIG == TRUE, mean(is.finite(d_pb))], .P[ELIG == TRUE, mean(is.finite(rr))],
                                  .P[ELIG == TRUE, mean(is.finite(d_bv))], .P[ELIG == TRUE, mean(is.finite(d_pe))],
                                  .P[ELIG == TRUE, mean(is.finite(d_liab))])), collapse = " · ")
cat(sprintf("%s 특성 부착 완료 — 적격행 커버리지 %s · 회계 관측 있는 적격행 %.1f%%\n",
            .TAG, .cov_txt, 100 * .P[ELIG == TRUE, mean(is.finite(bv_lvl))]))

# =============================================================================
# 7. Random Forest — 확장창 재적합(매 시그널 분기) · 학습집합 통계로 표준화·평균대치  ★changed(2)(5)(9)(10)
#    표적 실현 시점 <= 결정일: 학습집합 = si <= s_pred - 1 (아래 단언)
# =============================================================================
.M <- .P[ELIG == TRUE & is.finite(rr) & is.finite(bv_lvl)]
if (nrow(.M) == 0L) stop(sprintf("%s 모델 패널 0행 — 특성 커버리지 확인", .TAG))
.pred_si <- sort(unique(.M[Date >= .START, si]))
if (!length(.pred_si)) stop(sprintf("%s 예측 대상 분기 0개 — .START 이후 격자 확인", .TAG))
.si_date <- setNames(as.character(.QE$Date), as.character(.QE$si))

.zcols <- .FEATS
.out <- vector("list", length(.pred_si))
.n_fit <- 0L; .n_skip <- 0L; .lab_max_gap <- -Inf
for (.ii in seq_along(.pred_si)) {
  .s <- .pred_si[.ii]
  .tr <- .M[si <= .s - 1L & is.finite(y)]
  .te <- .M[si == .s]
  if (nrow(.tr) < .MIN_TR_ROW || uniqueN(.tr$si) < .MIN_TR_PER || nrow(.te) < .MIN_N) {
    .n_skip <- .n_skip + 1L
    next
  }
  # PIT 재단언: 학습행 si 의 표적은 si+1 분기말에 실현된다 → 실현 인덱스 <= 결정 분기
  .lab_max <- max(.tr$si) + 1L
  if (.lab_max > .s)
    stop(sprintf("%s PIT: 학습 표적 실현 분기 %d > 결정 분기 %d", .TAG, .lab_max, .s))
  .lab_max_gap <- max(.lab_max_gap, .lab_max - .s)
  .mu <- vapply(.zcols, function(cc) .mu1(.tr[[cc]]), numeric(1))
  .sg <- vapply(.zcols, function(cc) .sd1(.tr[[cc]]), numeric(1))
  .zmk <- function(dt) as.data.frame(setNames(lapply(.zcols, function(cc) {
    v <- (dt[[cc]] - .mu[[cc]]) / .sg[[cc]]
    v[!is.finite(v)] <- 0     # 결측·상수열 = 학습집합 평균(표준화 후 0) — 논문 mean substitution
    v
  }), .zcols))
  .Ztr <- .zmk(.tr)
  .Ztr$y <- as.numeric(.tr$y)
  .Zte <- .zmk(.te)
  set.seed(.SEED_BASE + .s)
  .fit <- ranger(dependent.variable.name = "y", data = .Ztr,
                 num.trees = .RF_TREES, mtry = length(.zcols), min.node.size = .RF_MINNODE,
                 replace = TRUE, sample.fraction = 1, splitrule = "variance",
                 num.threads = .RF_THREADS, seed = .SEED_BASE + .s, verbose = FALSE)
  .pr <- as.numeric(predict(.fit, data = .Zte, num.threads = .RF_THREADS)$predictions)
  .out[[.ii]] <- data.table(Date = .te$Date, Ticker = .te$Ticker, Score = .pr)
  .n_fit <- .n_fit + 1L
  if (.n_fit <= 3L || .n_fit %% 20L == 0L)
    cat(sprintf("%s   적합 %d/%d — 분기말 %s · 학습 %d행(%d분기) · 예측 %d종 · 경과 %.1f분\n",
                .TAG, .n_fit, length(.pred_si), .si_date[[as.character(.s)]],
                nrow(.tr), uniqueN(.tr$si), nrow(.te),
                as.numeric(difftime(Sys.time(), .t0, units = "mins"))))
}
FACTORS <- rbindlist(Filter(Negate(is.null), .out), use.names = TRUE)
if (nrow(FACTORS) == 0L) stop(sprintf("%s FACTORS 0행 — 학습집합 하한·커버리지 확인", .TAG))
setorder(FACTORS, Date, -Score, Ticker)
cat(sprintf("%s RF 적합 %d회(건너뜀 %d · 학습집합 하한 %d행/%d분기 미달) · 표적 실현−결정 최대 간격 %d분기 · FACTORS %d행 %d분기(%s ~ %s)\n",
            .TAG, .n_fit, .n_skip, .MIN_TR_ROW, .MIN_TR_PER, as.integer(.lab_max_gap),
            nrow(FACTORS), uniqueN(FACTORS$Date),
            as.character(min(FACTORS$Date)), as.character(max(FACTORS$Date))))

# =============================================================================
# 8. PORTFOLIO — 예측 상대수익 상위 1/3 동일가중 롱 (논문 'Buy' 포트폴리오)  ★changed(9)
#    동률은 (Score 내림차순, 종목코드)로 결정론적으로 깬다.
# =============================================================================
PORTFOLIO <- FACTORS[is.finite(Score), {
  .SD2 <- .SD[order(-Score, Ticker)]
  k <- .k_top(nrow(.SD2))
  if (k < 2L) NULL else data.table(Ticker = .SD2$Ticker[1:k], Weight = 1 / k, Leg = "long")
}, by = Date, .SDcols = c("Ticker", "Score")]
if (nrow(PORTFOLIO) == 0L) stop(sprintf("%s PORTFOLIO 0행", .TAG))
setcolorder(PORTFOLIO, c("Date", "Ticker", "Weight", "Leg"))
.nb <- PORTFOLIO[, .(n = .N, sw = sum(Weight)), by = Date]
if (max(abs(.nb$sw - 1)) > 1e-9) stop(sprintf("%s 비중 합 != 1 (최대 편차 %.3g)", .TAG, max(abs(.nb$sw - 1))))
cat(sprintf("%s PORTFOLIO %d행 · %d분기 리밸 · 보유 %d~%d종(중앙 %d) · Σw=1 · 롱온리 · 소요 %.1f분\n",
            .TAG, nrow(PORTFOLIO), nrow(.nb), min(.nb$n), max(.nb$n),
            as.integer(stats::median(.nb$n)), as.numeric(difftime(Sys.time(), .t0, units = "mins"))))
cat(sprintf("%s adapted(기전 = 논문 그대로: 분기 회계 지표의 기간대비 변화 → RF 로 다음 분기 상대수익 회귀 → 상위 1/3 EW 분기 리밸) · 입력 %d종 = %s · 설비투자 = data_gap · 정본 = FIDELITY.json\n",
            .TAG, length(.FEATS), paste(.FEAT_PAPER, collapse = " · ")))
