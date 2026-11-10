#!/usr/bin/env Rscript
#==============================================================================
# build_kr_factor_returns.R — 한국 Fama-French 팩터 수익(일간 · 월간) + 파마-맥베스 통제 특성(월간)
#   v1.0 (2026-11-09 · 도훈 "재빌드 뒤 갱신해주고 팩터조정알파 및 파마-맥베스 분석에 쓰이는
#   기초데이터도 데일리로 최신화") · 설정 정본 = 06_Registry/kr_factor_returns.json(출처 · 정의 전부)
#
# 왜 새로 짰나 — 구판(.cache/kr_factor_returns_v2.parquet ·
#   99_Archive/reorg_20261014/04_Research/worktask_scratch/WT-D20260425_009/step0_kr_ff5_backfill.R):
#   ① HML · RMW · CMA = 월말 '하루' 수익의 차(RAWDATA Ret = 일간 수익) — 월간 수익이 아니다(월 표준편차 ≈ 1%)
#   ② RF = 0(FIXME) — 시장 노출 < 1 인 전략의 알파가 (1 − β)·RF 만큼 부풀었다
#   ③ MKT · SMB · WML = 만든 경로를 찾을 수 없는 더 오래된 파일 · ④ 2026-03-04 에서 멈춤(부분월 행 포함)
#
# 구성(설정 annual_sort · momentum · definitions):
#   유니버스 = 측정 축 epoch 멤버(contracts/measurement_axis.R::ma_membership)
#   연 1회 6월 말 구성 · 7월 ~ 이듬해 6월 보유: Size(6월 말 시총 · Big = 상위 누적 90%) ×
#     B/M(BE t−1 / ME t−1 12월) · OP((영업이익 − 이자비용)/BE) · INV(TA t−1 / TA t−2 − 1) — 특성 30/70 = Big 분위
#   월 1회 월말 구성: Size × 직전 t−12 ~ t−2 수익(모멘텀)
#   PIT: 재무 값은 Factor_Date ≤ 구성일 · 구성일 종가로 정렬 · 다음 거래일부터 보유 · RF = 전 거래일 CD91
#   ★v1.1(2026-11-10 · GRADE-V33-NOTCH-ASOF-AND-RULE-CHANGE-PROCEDURE-20261110): v2 1단계 표는 정정 의심 기업-연도를
#     다음 해 사업보고서 뒤로 미룬다(build_fundamental_v2.py:211-224). 그 날짜로 거르면 '나중에 정정될 회사'가 정렬에서
#     빠진다(정정 의심 표지 = 다음 해 보고서를 봐야 생기는 정보 → 표본 선택 미래참조 · 2016~ 정렬 비율 0.66~0.75).
#     v1.1 = 그 기업-연도는 DART 당시 보고서 기록(접수 다음 거래일)을 쓴다(.krf_pick · 병합 표 RS 와 같은 규칙).
#     기록 표(RS)가 없으면 빌드하지 않는다(조용히 v1.0 규칙으로 돌아가지 않는다).
#     진단(11-10 · 규칙 불변): 정렬마다 유니버스 행의 배타 원인(퀀티 · DART 기록 편입 / 퀀티 공시 자체가 구성일 뒤 ·
#     정정 의심인데 기록 없음 · 판 근거 미상 · 정정 의심 기록 날짜 뒤 · 기록 값 없음 · 자료 없음 · 보유 DART 판 접수일 뒤 ·
#     분모 ≤ 0 · 신규 상장)을 연도별로 meta annual_sort_causes 에 싣는다(원인 = v2 표의 Check · Avail_Basis). 보유 DART 판이
#     구성일 뒤 기재정정본인 군(Avail_Basis = dart_rcept · excl_late_dart_version)만 처분 도훈 결정 대기 —
#     meta restated_record.late_version_pending.
#     원인 편입 칸 합 ≠ 정렬 종목 수면 멈춘다(진단이 규칙과 어긋남).
#   수익 = 일간 상한 가치가중(전날 시총을 직전 월말 Big 시총 80 분위에서 자른다 · Jensen-Kelly-Pedersen 2023 · 설정 weighting)
#     → 월간 = 포트폴리오 일간 수익을 달 안에서 복리 → 요인 = 포트폴리오 수익의 조합 · 시장(MKT) = 상한 없는 가치가중
#
# 쓰기: Rscript 02_Infrastructure/data/build_kr_factor_returns.R [--out DIR] [--to YYYY-MM-DD] [--no-vintage]
#   기본 --out = <root>/.cache (운영 경로). 후보를 먼저 보려면 --out 에 스크래치 폴더를 준다.
#   source() 하면 함수만 싣는다(시험 = 08_Tests/data/test_kr_factor_returns.R).
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a
KRF_BUILDER <- "build_kr_factor_returns.R v1.1"

krf_root <- function() {
  # 순서 = CLAUDE_PROJECT_DIR → QM_ROOT (r-portability 금칙 ④ — ~/.Renviron 의 QM_ROOT 는 export 로 못 덮는다)
  r <- Sys.getenv("CLAUDE_PROJECT_DIR", "")
  if (!nzchar(r)) r <- Sys.getenv("QM_ROOT", "")
  if (!nzchar(r)) stop("[krf] CLAUDE_PROJECT_DIR · QM_ROOT 미설정 — 루트를 지어내지 않는다")
  gsub("\\\\", "/", r)
}

krf_config <- function(root = krf_root()) {
  p <- file.path(root, "06_Registry", "kr_factor_returns.json")
  if (!file.exists(p)) stop("[krf] 설정 없음: ", p)
  cfg <- fromJSON(p, simplifyVector = TRUE)
  need <- c("version", "start_date", "lookback_start", "universe", "fundamentals", "rf", "annual_sort", "momentum", "weighting", "guards", "chars", "outputs")
  miss <- setdiff(need, names(cfg))
  if (length(miss)) stop("[krf] 설정 키 없음: ", paste(miss, collapse = ","))
  cfg
}

## ── 작은 도구 ────────────────────────────────────────────────────────────────
.ym_add <- function(ym, k) {                       # YYYYMM 정수 + k 개월
  i <- (ym %/% 100L) * 12L + (ym %% 100L - 1L) + as.integer(k)
  as.integer((i %/% 12L) * 100L + (i %% 12L) + 1L)
}
.ym_of <- function(d) as.integer(format(d, "%Y%m"))
# 보유연도(= 그 수익을 담는 정렬의 구성 연도) — 구성월 다음 달부터 이듬해 구성월까지
.krf_hold_year <- function(ym, formation_month) ifelse((ym %% 100L) > formation_month, ym %/% 100L, ym %/% 100L - 1L)
KRF_FUND_ITEMS <- c("EquityParent", "TotalEquity", "NonControllingInt", "PreferredCapital", "TotalAssets", "OperatingProfit", "InterestExp")

# 월말 f 의 직전 수익 C[f − skip] / C[f − skip − lb] − 1 (모멘텀 t−12 ~ t−2) — 정렬 · 특성 패널 공용
.krf_prior <- function(SNAP, skip, lb) {
  P <- SNAP[is.finite(Close) & Close > 0, .(Ticker, ym, Close)]
  E <- copy(P)[, ym := .ym_add(ym, skip)]; setnames(E, "Close", "C_end")
  B <- copy(P)[, ym := .ym_add(ym, skip + lb)]; setnames(B, "Close", "C_beg")
  X <- merge(E, B, by = c("Ticker", "ym"))
  X[, .(Ticker, ym, mom = C_end / C_beg - 1)]
}

# 시총 상위 누적 share 까지 = Big(그 문턱을 넘기는 종목까지 Big) — FF (2012) §2
.krf_size_split <- function(me, share) {
  o <- order(me, decreasing = TRUE)
  before <- cumsum(me[o]) - me[o]
  big <- logical(length(me))
  big[o] <- (before / sum(me)) < share
  big
}

# 특성 30/70 분위(Big 종목 분위) 라벨 — Big 이 min_big 미만이면 NULL(지어내지 않는다)
.krf_sort_labels <- function(Ticker, big, x, lo, mid, hi, bp, min_big) {
  xb <- x[big]
  if (length(xb) < min_big) return(NULL)
  q <- stats::quantile(xb, bp, names = FALSE, type = 7)
  g <- ifelse(x <= q[1], lo, ifelse(x >= q[2], hi, mid))
  data.table(Ticker = Ticker, port = paste0(ifelse(big, "B", "S"), g), bp_lo = q[1], bp_hi = q[2])
}

# 그 날(at) 공개돼 있던 값: 퀀티 v2 값(공개일 d ≤ at) → 아니면 정정 의심 연도의 DART 당시 기록(접수 다음 거래일 dr ≤ at) → 결측
#   (v1.1 · 정정 의심 표지로 표본을 거르지 않는다 — 날짜는 늦추기만 하고 앞당기지 않는다)
.krf_pick <- function(v, d, vr, dr, at) {
  fifelse(!is.na(d) & d <= at, v, fifelse(!is.na(dr) & dr <= at & is.finite(vr), vr, NA_real_))
}

# 진단 전용(값을 고르지 않는다) — .krf_pick 이 그 값을 어디서 가져왔나 / 왜 결측인가(11-10 · 규칙 불변)
#   quantiwise · dart_record = 쓴 값 · late_restated = 정정 의심 기록의 날짜가 구성일 뒤 ·
#   기록 없음(RS 행 없음)인데 퀀티 판 날짜가 구성일 뒤 = 그 판 날짜의 근거 k(.krf_basis_code)로 가른다:
#     late_dart_version = v2 표가 보유 DART 판 접수일로 Factor_Date 를 미룬 군(Avail_Basis = dart_rcept · 결정 대상) ·
#     late_filing = 퀀티 공시(또는 고정일 규칙) 자체가 구성일 뒤(정당한 PIT 결측) ·
#     late_restated_no_record = 정정 의심(Check = restated)인데 DART 접수일이 없어 기록이 없음 · late_unknown_basis = 근거 열 없음
#   record_no_value = 기록 날짜는 앞인데 값 없음 · no_data = 값 없음
#   ★late_dart_version 처분((i) 결측 유지 = 현행 / (ii) 최초 공시일로 편입)은 도훈 결정 대기 — 여기서는 세기만 한다
.krf_avail_cause <- function(v, d, vr, dr, at, k = NULL) {
  if (is.null(k)) k <- rep(NA_character_, length(v))
  q <- !is.na(d) & d <= at
  late <- is.na(dr) & is.finite(v) & !is.na(d)
  fcase(q & is.finite(v), "quantiwise",
        q, "no_data",
        !is.na(dr) & dr <= at & is.finite(vr), "dart_record",
        !is.na(dr) & dr > at, "late_restated",
        !is.na(dr), "record_no_value",
        late & k %in% "dart_version", "late_dart_version",
        late & k %in% "filing", "late_filing",
        late & k %in% "restated", "late_restated_no_record",
        late, "late_unknown_basis",
        default = "no_data")
}
# 판 날짜 근거(진단 전용) — v2 1단계 표의 Check · Avail_Basis(build_fundamental_v2.py) → restated · dart_version · filing · unknown
.krf_basis_code <- function(check, basis) {
  fcase(check %in% "restated", "restated",
        basis %in% "dart_rcept", "dart_version",
        basis %in% c("qw_report", "rule"), "filing",
        default = "unknown")
}
# 합성 항목(BE · OPN)의 근거 = 합성 날짜(pmax)를 정한 구성 항목의 근거 — ... = (날짜, 근거) 쌍을 차례로(먼저 맞는 쌍)
.krf_bind_k <- function(target, ...) {
  a <- list(...); out <- rep(NA_character_, length(target))
  for (i in seq(1L, length(a), by = 2L)) {
    hit <- is.na(out) & !is.na(target) & !is.na(a[[i]]) & a[[i]] == target
    out[hit] <- a[[i + 1L]][hit]
  }
  out
}
KRF_SORT_CAUSES <- c("sorted_quantiwise", "sorted_dart_record", "excl_late_filing", "excl_late_restated_no_record",
                     "excl_late_unknown_basis", "excl_late_restated", "excl_record_no_value", "excl_no_data",
                     "excl_late_dart_version", "excl_nonpositive", "excl_new_listing")
# 정렬 유니버스 행마다 배타 원인 하나 — causes = 그 정렬이 쓰는 항목별 .krf_avail_cause · pos_ok = 분모 양수(고른 값 기준) ·
#   no_dec = 12월 말 시총 없음(B/M 만 · 신규 상장 — 재무 규칙과 무관하게 빠지므로 먼저 센다)
#   차례: 결정 (ii) 로도 남는 원인을 먼저 센다 → late_dart_version 은 결측 원인 가운데 마지막(그 칸 = 보유 DART 판 날짜만이
#   막은 행 · 분모 부호는 고른 값으로만 알 수 있어 BE ≤ 0 은 그 뒤)
.krf_sort_cause <- function(causes, pos_ok, no_dec = NULL) {
  n <- length(causes[[1L]]); out <- rep(NA_character_, n)
  if (!is.null(no_dec)) out[no_dec] <- "excl_new_listing"
  for (p in c("late_filing", "late_restated_no_record", "late_unknown_basis", "late_restated", "record_no_value", "no_data",
              "late_dart_version")) {
    hit <- is.na(out) & Reduce(`|`, lapply(causes, function(z) z == p))
    out[hit] <- paste0("excl_", p)
  }
  out[is.na(out) & !(pos_ok %in% TRUE)] <- "excl_nonpositive"
  dr <- Reduce(`|`, lapply(causes, function(z) z == "dart_record"))
  out[is.na(out)] <- fifelse(dr[is.na(out)], "sorted_dart_record", "sorted_quantiwise")
  out
}

## ── 재무: 연간(달력연도) 값 + 그 값을 쓸 수 있는 날 ─────────────────────────
#' FUND: data.table(Ticker, Period(YYYYMM 문자), Item, Value, Factor_Date(Date)) — v2 1단계 표의 열
#' RS: 정정 의심 기업-연도의 DART 당시 기록 data.table(Ticker, fy, BE_r, TA_r, OPN_r, R_d) — krf_restated_record() 산출 ·
#'   정정 의심이 없는 자료면 0행 표를 준다(NULL 은 거부 — 기록 없이 v1.0 규칙으로 돌아가지 않는다)
#'   FUND 의 Check · Avail_Basis 열(있으면)은 진단 전용 — 판 날짜 근거 BE_k · TA_k · OPN_k(.krf_basis_code · 값 고르기에 안 쓴다 ·
#'   열이 없으면 unknown)
#' @return data.table(Ticker, fy, BE, BE_d, TA, TA_d, OPN, OPN_d, BE_k, TA_k, OPN_k, BE_r, TA_r, OPN_r, R_d)
krf_annual_fund <- function(FUND, RS) {
  if (missing(RS) || is.null(RS)) stop("[krf] 정정 의심 연도 DART 기록(RS)이 없다 — v1.0 규칙(정정 의심 기업을 정렬에서 뺌 · 표본 선택 미래참조)으로 돌아가지 않는다")
  need_rs <- c("Ticker", "fy", "BE_r", "TA_r", "OPN_r", "R_d")
  if (length(setdiff(need_rs, names(RS)))) stop("[krf] RS 열 없음: ", paste(setdiff(need_rs, names(RS)), collapse = ","))
  if (anyDuplicated(RS, by = c("Ticker", "fy"))) stop("[krf] RS (Ticker, fy) 겹침 — 기업-연도마다 기록 하나")
  col_or_na <- function(c) if (c %in% names(FUND)) as.character(FUND[[c]]) else rep(NA_character_, nrow(FUND))
  F <- data.table(Ticker = FUND$Ticker, Period = as.character(FUND$Period), Item = FUND$Item, Value = as.numeric(FUND$Value),
                  Factor_Date = as.Date(FUND$Factor_Date), k = .krf_basis_code(col_or_na("Check"), col_or_na("Avail_Basis")))
  F <- F[Item %in% KRF_FUND_ITEMS & is.finite(Value) & !is.na(Factor_Date)]
  F[, `:=`(fy = as.integer(substr(Period, 1, 4)), mo = substr(Period, 5, 6))]
  F <- F[mo %in% c("03", "06", "09", "12")]
  dup <- F[, .N, by = .(Ticker, Period, Item)][N > 1L]
  if (nrow(dup)) stop("[krf] 재무 표 같은 (종목 · 기간 · 항목) 겹침 ", nrow(dup), "건 — 날짜 순서 계약 위반(조용히 고르지 않는다)")
  bs <- F[mo == "12"]
  A <- unique(F[, .(Ticker, fy)])
  for (it in c("EquityParent", "TotalEquity", "NonControllingInt", "PreferredCapital", "TotalAssets")) {
    s <- bs[Item == it, .(Ticker, fy, v = Value, d = Factor_Date, k)]
    setnames(s, c("v", "d", "k"), c(it, paste0(it, "_d"), paste0(it, "_k")))
    A <- merge(A, s, by = c("Ticker", "fy"), all.x = TRUE)
  }
  fl <- F[Item %in% c("OperatingProfit", "InterestExp"), .(v = sum(Value), nq = .N, d = max(Factor_Date), k = k[which.max(Factor_Date)]),
          by = .(Ticker, fy, Item)]
  A <- merge(A, fl[Item == "OperatingProfit" & nq == 4L, .(Ticker, fy, OP4 = v, OP4_d = d, OP4_k = k)], by = c("Ticker", "fy"), all.x = TRUE)
  A <- merge(A, fl[Item == "InterestExp", .(Ticker, fy, IE = v, IE_d = d, IE_k = k)], by = c("Ticker", "fy"), all.x = TRUE)
  ep <- is.finite(A$EquityParent)
  A[, BE0 := fifelse(ep, EquityParent, TotalEquity - fcoalesce(NonControllingInt, 0))]
  A[, BE0_d := fifelse(ep, EquityParent_d, pmax(TotalEquity_d, NonControllingInt_d, na.rm = TRUE))]
  A[, BE := BE0 - fcoalesce(PreferredCapital, 0)]
  A[, BE_d := pmax(BE0_d, PreferredCapital_d, na.rm = TRUE)]
  A[, OPN := OP4 - fcoalesce(IE, 0)]
  A[, OPN_d := fifelse(is.finite(OP4), pmax(OP4_d, IE_d, na.rm = TRUE), as.Date(NA))]
  # 판 날짜 근거(진단 전용) — 합성 날짜를 정한 구성 항목의 근거
  A[, BE0_k := fifelse(ep, EquityParent_k, .krf_bind_k(BE0_d, TotalEquity_d, TotalEquity_k, NonControllingInt_d, NonControllingInt_k))]
  A[, BE_k := .krf_bind_k(BE_d, BE0_d, BE0_k, PreferredCapital_d, PreferredCapital_k)]
  A[, OPN_k := fifelse(is.finite(OP4), .krf_bind_k(OPN_d, OP4_d, OP4_k, IE_d, IE_k), NA_character_)]
  out <- A[, .(Ticker, fy, BE, BE_d, TA = TotalAssets, TA_d = TotalAssets_d, OPN, OPN_d, BE_k, TA_k = TotalAssets_k, OPN_k)]
  R <- as.data.table(RS)[, .(Ticker = as.character(Ticker), fy = as.integer(fy), BE_r = as.numeric(BE_r), TA_r = as.numeric(TA_r),
                             OPN_r = as.numeric(OPN_r), R_d = as.Date(R_d))]
  merge(out, R, by = c("Ticker", "fy"), all.x = TRUE)
}

#' 정정 의심 기업-연도의 DART 당시 보고서 기록(v1.1) — 순수 함수(시험이 합성 자료로 부른다)
#'   REST: data.table(Ticker, fy) — v2 1단계 표 Check == "restated" 기업-연도
#'   CK:   data.table(Ticker, FY, DART_Date, DART_Factor_Date) — fund_v2_annual_check(접수일 · 접수 다음 거래일)
#'   FD:   data.table(Ticker, bsns_year, TotalAssets, TotalEquity, OperatingProfit, InterestExp) — fundamental_dart(병합 표 DART_RESTATED 원천)
#'   RAWB: data.table(Ticker, bsns_year, rcept_no, fs_div, account_id, thstrm_amount) — dart_raw_financials 재무상태표 행
#'   BE_r = 보유 판(접수번호 최대 · 회계연도 말 뒤 접수 · 그 판의 접수일 = CK DART_Date) CFS 우선 지배주주지분
#'          (없으면 자본총계 − 비지배지분) − 우선주자본금(없으면 0) · 그 판이 없으면 fundamental_dart 자본총계 − 우선주 0
#'   OPN_r = 영업이익 − 이자비용(없으면 0 · DART 이자비용은 퀀티와 정의가 다르다 — 병합 표와 같은 한계) · R_d = DART_Factor_Date
#' @return list(RS = data.table(Ticker, fy, BE_r, TA_r, OPN_r, R_d), diag = list(...))
krf_restated_record <- function(REST, CK, FD, RAWB) {
  REST <- unique(as.data.table(REST)[, .(Ticker = as.character(Ticker), fy = as.integer(fy))])
  ck <- unique(as.data.table(CK)[!is.na(DART_Factor_Date), .(Ticker = as.character(Ticker), fy = as.integer(FY),
                                                              D_date = as.Date(DART_Date), R_d = as.Date(DART_Factor_Date))])
  if (anyDuplicated(ck, by = c("Ticker", "fy"))) stop("[krf] DART 접수 날짜가 기업-연도마다 하나가 아니다(fund_v2_annual_check) — 중단")
  fd <- as.data.table(FD)[, .(Ticker = as.character(Ticker), fy = as.integer(bsns_year), TA_r = as.numeric(TotalAssets),
                              TE_r = as.numeric(TotalEquity), OP_r = as.numeric(OperatingProfit), IE_r = as.numeric(InterestExp))]
  if (anyDuplicated(fd, by = c("Ticker", "fy"))) stop("[krf] fundamental_dart (Ticker, bsns_year) 겹침 — 중단")
  AID <- c(parent = "EquityAttributableToOwnersOfParent", equity = "Equity", nci = "NoncontrollingInterests",
           pref = "dart_IssuedCapitalOfPreferredStock")                         # 계정 id(ifrs · ifrs-full 접두 제거 뒤)
  rw <- as.data.table(RAWB)[, .(Ticker = as.character(Ticker), fy = as.integer(bsns_year), rcept_no = as.character(rcept_no),
                                fs_div = as.character(fs_div), acc = sub("^ifrs(-full)?_", "", as.character(account_id)),
                                v = suppressWarnings(as.numeric(gsub(",", "", as.character(thstrm_amount)))))]
  rw <- rw[acc %in% AID & is.finite(v)]
  rw[, rd := as.Date(substr(rcept_no, 1L, 8L), format = "%Y%m%d")]
  rw <- rw[!is.na(rd) & rd > as.Date(sprintf("%d-12-31", fy))]                  # 다른 해 보고서 응답 배제(build_fundamental_v2.py:162-164 와 같은 규칙)
  rw <- rw[rw[, .I[rcept_no == max(rcept_no)], by = .(Ticker, fy)]$V1]           # 보유 판
  rw[, fsr := fifelse(fs_div == "CFS", 1L, 2L)]
  rw <- rw[rw[, .I[fsr == min(fsr)], by = .(Ticker, fy)]$V1]
  bw <- rw[, .(parent = v[acc == AID[["parent"]]][1L], equity = v[acc == AID[["equity"]]][1L], nci = v[acc == AID[["nci"]]][1L],
               pref = v[acc == AID[["pref"]]][1L], rd = rd[1L]), by = .(Ticker, fy)]
  bw[, BEP_r := fifelse(is.finite(parent), parent, equity - fcoalesce(nci, 0))]
  X <- merge(REST, ck, by = c("Ticker", "fy"))
  X <- merge(X, fd, by = c("Ticker", "fy"), all.x = TRUE)
  X <- merge(X, bw[, .(Ticker, fy, BEP_r, PREF_r = pref, rd)], by = c("Ticker", "fy"), all.x = TRUE)
  n_ver_mismatch <- X[is.finite(BEP_r) & !is.na(D_date) & rd != D_date, .N]
  X[is.finite(BEP_r) & !is.na(D_date) & rd != D_date, `:=`(BEP_r = NA_real_, PREF_r = NA_real_)]   # 날짜와 다른 판의 값은 쓰지 않는다
  X[, BE_r := fcoalesce(BEP_r, TE_r) - fcoalesce(PREF_r, 0)]
  X[, OPN_r := OP_r - fcoalesce(IE_r, 0)]
  RS <- X[, .(Ticker, fy, BE_r, TA_r, OPN_r, R_d)]
  setorder(RS, Ticker, fy)
  list(RS = RS, diag = list(restated_company_years = nrow(REST), with_dart_date = nrow(RS),
                            without_dart_date = nrow(REST) - nrow(RS), with_be = RS[is.finite(BE_r), .N],
                            with_ta = RS[is.finite(TA_r), .N], with_opn = RS[is.finite(OPN_r), .N],
                            be_from_raw_parent = X[is.finite(BEP_r), .N], raw_version_date_mismatch = n_ver_mismatch))
}

## ── 달력 · 월말 표본 ────────────────────────────────────────────────────────
krf_calendar <- function(RAW, min_rows) {
  cnt <- RAW[, .N, by = Date][N >= min_rows]
  cal <- data.table(Date = sort(cnt$Date))
  cal[, ym := .ym_of(Date)]
  list(cal = cal, me = cal[, .(me_date = max(Date)), by = ym])
}

#' 월말 행(그 달 마지막 거래일에 있는 종목 행) — ME = Size · 멤버 여부
krf_snap <- function(RAW, ME) {
  S <- merge(RAW[, .(Date, Ticker, Size, Close, member)], ME, by.x = "Date", by.y = "me_date")
  S[, .(Ticker, ym, me_date = Date, ME = Size, Close, member)]
}

## ── 연간 정렬(6월 말) ───────────────────────────────────────────────────────
krf_annual_labels <- function(SNAP, AF, years, cfg) {
  share <- as.numeric(cfg$annual_sort$big_share); bp <- as.numeric(cfg$annual_sort$char_breakpoints)
  mb <- as.integer(cfg$guards$min_big_for_breakpoints); fm <- as.integer(cfg$annual_sort$formation_month)
  L <- list(); D <- list(); CZ <- list()
  for (t in years) {
    f_ym <- t * 100L + fm; d_ym <- (t - 1L) * 100L + 12L
    J <- SNAP[ym == f_ym & member %in% TRUE & is.finite(ME) & ME > 0, .(Ticker, fdate = me_date, ME_f = ME)]
    if (nrow(J) < mb) next
    fdate <- J$fdate[1L]
    J <- merge(J, SNAP[ym == d_ym & is.finite(ME) & ME > 0, .(Ticker, ME_dec = ME)], by = "Ticker", all.x = TRUE)
    J <- merge(J, AF[fy == t - 1L, .(Ticker, BE, BE_d, TA1 = TA, TA1_d = TA_d, OPN, OPN_d, BE_r, OPN_r, TA1_r = TA_r, R1_d = R_d,
                                     BE_k, OPN_k, TA1_k = TA_k)], by = "Ticker", all.x = TRUE)
    J <- merge(J, AF[fy == t - 2L, .(Ticker, TA2 = TA, TA2_d = TA_d, TA2_r = TA_r, R2_d = R_d, TA2_k = TA_k)], by = "Ticker", all.x = TRUE)
    # ★PIT — 구성일에 공개돼 있던 값만 쓴다(퀀티 공개일 ≤ 구성일 → 아니면 정정 의심 연도의 DART 당시 기록 → 아니면 결측).
    #   v1.0 은 정정 의심 연도를 결측으로 빼서 '나중에 정정될 회사'를 정렬에서 걸렀다(v1.1 수리 · 머리말)
    cz <- list(BE  = .krf_avail_cause(J$BE,  J$BE_d,  J$BE_r,  J$R1_d, fdate, J$BE_k),
               OPN = .krf_avail_cause(J$OPN, J$OPN_d, J$OPN_r, J$R1_d, fdate, J$OPN_k),
               TA1 = .krf_avail_cause(J$TA1, J$TA1_d, J$TA1_r, J$R1_d, fdate, J$TA1_k),
               TA2 = .krf_avail_cause(J$TA2, J$TA2_d, J$TA2_r, J$R2_d, fdate, J$TA2_k))
    J[, BE  := .krf_pick(BE,  BE_d,  BE_r,  R1_d, fdate)]
    J[, OPN := .krf_pick(OPN, OPN_d, OPN_r, R1_d, fdate)]
    J[, TA1 := .krf_pick(TA1, TA1_d, TA1_r, R1_d, fdate)]
    J[, TA2 := .krf_pick(TA2, TA2_d, TA2_r, R2_d, fdate)]
    J[, big := .krf_size_split(ME_f, share)]
    sorts <- list(
      BM  = list(J[is.finite(ME_dec) & is.finite(BE) & BE > 0, .(Ticker, big, x = BE / ME_dec)], "L", "N", "H"),
      OP  = list(J[is.finite(BE) & BE > 0 & is.finite(OPN), .(Ticker, big, x = OPN / BE)], "W", "N", "R"),
      INV = list(J[is.finite(TA1) & is.finite(TA2) & TA2 > 0, .(Ticker, big, x = TA1 / TA2 - 1)], "C", "N", "A"))
    # 원인 진단(배타 · 정렬 규칙을 바꾸지 않는다) — 편입 칸 합 ≠ 정렬 종목 수면 멈춘다(진단이 규칙과 어긋남 = 조용히 쓰지 않는다)
    why <- list(BM  = .krf_sort_cause(cz["BE"], J$BE > 0, no_dec = !is.finite(J$ME_dec)),
                OP  = .krf_sort_cause(cz[c("BE", "OPN")], J$BE > 0),
                INV = .krf_sort_cause(cz[c("TA1", "TA2")], J$TA2 > 0))
    for (s in names(sorts)) {
      S <- sorts[[s]][[1]]
      tb <- table(factor(why[[s]], levels = KRF_SORT_CAUSES))
      if (sum(tb[c("sorted_quantiwise", "sorted_dart_record")]) != nrow(S))
        stop("[krf] 정렬 원인 진단이 정렬 규칙과 어긋난다(", t, " ", s, " · 편입 ", sum(tb[1:2]), " vs 정렬 ", nrow(S), ") — 중단")
      CZ[[length(CZ) + 1L]] <- as.data.table(c(list(fy = t, sort = s, n_universe = nrow(J)), as.list(setNames(as.integer(tb), KRF_SORT_CAUSES))))
      lb <- .krf_sort_labels(S$Ticker, S$big, S$x, sorts[[s]][[2]], sorts[[s]][[3]], sorts[[s]][[4]], bp, mb)
      if (!is.null(lb)) L[[length(L) + 1L]] <- lb[, `:=`(fy = t, sort = s)]
      D[[length(D) + 1L]] <- data.table(fy = t, sort = s, fdate = fdate, n_universe = nrow(J), n_sort = nrow(S),
                                        n_big = sum(S$big), ok = !is.null(lb))
    }
  }
  list(labels = rbindlist(L, use.names = TRUE), diag = rbindlist(D, use.names = TRUE), causes = rbindlist(CZ, use.names = TRUE))
}

## ── 모멘텀 정렬(매월 말) ────────────────────────────────────────────────────
krf_mom_labels <- function(SNAP, cfg, from_ym) {
  share <- as.numeric(cfg$momentum$big_share); bp <- as.numeric(cfg$momentum$char_breakpoints)
  mb <- as.integer(cfg$guards$min_big_for_breakpoints)
  PR <- .krf_prior(SNAP, as.integer(cfg$momentum$skip_months), as.integer(cfg$momentum$lookback_months))
  U <- SNAP[ym >= from_ym & member %in% TRUE & is.finite(ME) & ME > 0, .(Ticker, ym, ME)]
  U[, big := .krf_size_split(ME, share), by = ym]          # Size 분할은 직전 수익 유무와 무관하게 그 월말 멤버 전체로
  U <- merge(U, PR, by = c("Ticker", "ym"))
  U <- U[is.finite(mom)][, x := mom]
  L <- U[, { r <- .krf_sort_labels(Ticker, big, x, "L", "N", "W", bp, mb); if (is.null(r)) NULL else r }, by = ym]
  D <- U[, .(n_sort = .N, n_big = sum(big)), by = ym]
  setnames(L, "ym", "fym")
  list(labels = L, diag = D)
}

## ── 가중 상한(직전 월말 Big 종목 시총의 cap_quantile 분위 · JKP 2023) ─────────
#' @return data.table(fym, cap) — 그 월말에 잡은 상한(다음 달 일간 가중에 쓴다) · weighting.rule = vw 면 NULL
krf_caps <- function(SNAP, cfg) {
  w <- cfg$weighting
  rule <- as.character(w$rule %||% "vw")
  if (identical(rule, "vw")) return(NULL)
  if (!identical(rule, "capped_vw")) stop("[krf] weighting.rule 미지원: ", rule, " (vw | capped_vw)")
  if (!identical(as.character(w$cap_set), "big") || !identical(as.character(w$cap_update), "monthly"))
    stop("[krf] weighting.cap_set = big · cap_update = monthly 만 구현돼 있다")
  qq <- as.numeric(w$cap_quantile)
  if (length(qq) != 1L || !is.finite(qq) || qq <= 0 || qq >= 1) stop("[krf] weighting.cap_quantile 판독 실패(0~1 사이 수 하나)")
  U <- SNAP[member %in% TRUE & is.finite(ME) & ME > 0, .(ym, ME)]
  U[, big := .krf_size_split(ME, as.numeric(cfg$annual_sort$big_share)), by = ym]
  U[big == TRUE, .(cap = stats::quantile(ME, qq, names = FALSE, type = 7)), by = .(fym = ym)]
}

## ── 일간 가치가중 포트폴리오 수익 ──────────────────────────────────────────
#' RD: data.table(Date, Ticker, Ret, ME_l1, W, hy, fym) — Ret 유한 · ME_l1 > 0 만 · W = 요인 포트폴리오 가중(상한 적용 전날 시총)
#'   요인 포트폴리오 = W 가중 · 시장(MKT) = ME_l1 가중(시장 포트폴리오는 상한 없음)
krf_daily_ports <- function(RD, LA, LM, UM) {
  vw <- function(X) X[is.finite(W) & W > 0, .(r = sum(W * Ret) / sum(W), n = .N), by = .(Date, port)]
  out <- list()
  for (s in c("BM", "OP", "INV")) {
    Ls <- LA[sort == s, .(Ticker, hy = fy, port)]
    out[[s]] <- vw(RD[Ls, on = .(Ticker, hy), nomatch = 0L])[, sort := s]
  }
  out[["MOM"]] <- vw(RD[LM[, .(Ticker, fym, port)], on = .(Ticker, fym), nomatch = 0L])[, sort := "MOM"]
  X <- RD[UM, on = .(Ticker, fym), nomatch = 0L]
  out[["MKT"]] <- X[, .(r = sum(ME_l1 * Ret) / sum(ME_l1), n = .N), by = .(Date)][, `:=`(port = "MKT", sort = "MKT")]
  rbindlist(out, use.names = TRUE)
}

## ── 요인 = 포트폴리오 수익의 조합(FF 1993 · 2015 · French UMD) ──────────────
#' P: data.table(k, sort, port, r) — k = Date(일간) 또는 ym(월간)
krf_factors <- function(P) {
  w <- function(s, lo, hi) {
    x <- dcast(P[sort == s], k ~ port, value.var = "r")
    nm <- c(paste0("S", c(lo, "N", hi)), paste0("B", c(lo, "N", hi)))
    for (n in setdiff(nm, names(x))) x[, (n) := NA_real_]
    data.table(k = x$k,
               smb = (x[[nm[1]]] + x[[nm[2]]] + x[[nm[3]]]) / 3 - (x[[nm[4]]] + x[[nm[5]]] + x[[nm[6]]]) / 3,
               hl  = (x[[nm[3]]] + x[[nm[6]]]) / 2 - (x[[nm[1]]] + x[[nm[4]]]) / 2)
  }
  bm <- w("BM", "L", "H");  setnames(bm, c("smb", "hl"), c("SMB_BM", "HML"))
  op <- w("OP", "W", "R");  setnames(op, c("smb", "hl"), c("SMB_OP", "RMW"))
  iv <- w("INV", "C", "A"); setnames(iv, c("smb", "hl"), c("SMB_INV", "AMC"))
  iv[, CMA := -AMC][, AMC := NULL]                                  # CMA = 보수적(낮은 INV) − 공격적
  mo <- w("MOM", "L", "W"); setnames(mo, c("smb", "hl"), c("SMB_MOM", "WML"))
  mk <- P[sort == "MKT", .(k, MKT_TOTAL = r, n_mkt = n)]
  F <- Reduce(function(a, b) merge(a, b, by = "k", all = TRUE), list(mk, bm, op, iv, mo[, .(k, WML)]))
  F[, SMB5 := (SMB_BM + SMB_OP + SMB_INV) / 3]
  F[, SMB := SMB_BM]                                                # 3요인판 SMB(French 3-factor 파일과 같은 정의)
  F[]
}

## ── RF: 전 거래일 CD91 ──────────────────────────────────────────────────────
krf_rf_daily <- function(RFY, dates) {
  dates <- sort(unique(as.Date(dates)))
  Y <- unique(RFY[is.finite(y), .(Date = as.Date(Date), y)], by = "Date")
  setkey(Y, Date)
  Q <- data.table(Date = dates, prev = c(as.Date(NA), head(dates, -1L)))
  Q[, y := Y[data.table(Date = Q$prev), x.y, on = .(Date), roll = TRUE]]
  Q[is.na(prev), y := NA_real_]
  Q[, RF := (1 + y / 100)^(1 / 252) - 1]
  Q[, .(Date, RF, rf_yield_pct = y)]
}

## ── 파마-맥베스 통제 특성(월말) ─────────────────────────────────────────────
krf_chars <- function(SNAP, AF, cfg, from_ym) {
  age <- as.integer(cfg$chars$max_fiscal_age_years)
  PR <- .krf_prior(SNAP, as.integer(cfg$momentum$skip_months), as.integer(cfg$momentum$lookback_months))
  C <- SNAP[ym >= from_ym & is.finite(ME) & ME > 0, .(Ticker, ym, Date = me_date, member, ME)]
  C <- merge(C, PR[, .(Ticker, ym, mom_2_12 = mom)], by = c("Ticker", "ym"), all.x = TRUE)
  # 그 월말까지 쓸 수 있던 가장 최근 회계연도(BE 공개일 기준 — 늦게 정정된 옛 연도가 새 연도를 밀어내지 않게 누적 최대)
  #   v1.1: 공개일 = 퀀티 공개일과 정정 의심 연도 DART 기록 접수 다음 거래일 가운데 이른 날(그날 어느 판이든 공개돼 있었다)
  ev <- AF[!is.na(BE_d) | (is.finite(BE_r) & !is.na(R_d)),
           .(Ticker, d = pmin(BE_d, fifelse(is.finite(BE_r), R_d, as.Date(NA)), na.rm = TRUE), fy)][!is.na(d)]
  setorder(ev, Ticker, d, fy)
  ev[, fy_best := cummax(fy), by = Ticker]
  ev <- ev[, .(fy_best = max(fy_best)), by = .(Ticker, d)]
  setkey(ev, Ticker, d)
  C[, fy_used := ev[data.table(Ticker = C$Ticker, d = C$Date), x.fy_best, on = .(Ticker, d), roll = TRUE]]
  C[!is.na(fy_used) & fy_used < as.integer(ym %/% 100L) - age, fy_used := NA_integer_]
  a <- AF[, .(Ticker, fy_used = fy, BE, BE_d, OPN, OPN_d, TA1 = TA, TA1_d = TA_d, BE_r, OPN_r, TA1_r = TA_r, R1_d = R_d)]
  C <- merge(C, a, by = c("Ticker", "fy_used"), all.x = TRUE)
  C <- merge(C, AF[, .(Ticker, fy_used = fy + 1L, TA2 = TA, TA2_d = TA_d, TA2_r = TA_r, R2_d = R_d)], by = c("Ticker", "fy_used"), all.x = TRUE)
  C[, BE  := .krf_pick(BE,  BE_d,  BE_r,  R1_d, Date)]
  C[, OPN := .krf_pick(OPN, OPN_d, OPN_r, R1_d, Date)]
  C[, TA1 := .krf_pick(TA1, TA1_d, TA1_r, R1_d, Date)]
  C[, TA2 := .krf_pick(TA2, TA2_d, TA2_r, R2_d, Date)]
  C[, `:=`(log_me = log(ME),
           bm  = ifelse(is.finite(BE) & BE > 0, BE / ME, NA_real_),
           op  = ifelse(is.finite(BE) & BE > 0 & is.finite(OPN), OPN / BE, NA_real_),
           inv = ifelse(is.finite(TA1) & is.finite(TA2) & TA2 > 0, TA1 / TA2 - 1, NA_real_))]
  setorder(C, Date, Ticker)
  C[, .(Date, ym, Ticker, member, log_me, bm, op, inv, mom_2_12, fy_used)]
}

## ── 조립(순수 함수 — 시험이 합성 자료로 부른다) ─────────────────────────────
#' RAW: data.table(Date, Ticker, Close, Size, Ret, member) — member = 측정 축 멤버(논리)
#' FUND: v2 1단계 표 행 · RFY: data.table(Date, y = 연 %) · RS: krf_restated_record()$RS(정정 의심이 없으면 0행 표 · NULL 거부)
krf_build <- function(RAW, FUND, RFY, cfg, to = NULL, RS = NULL) {
  if (is.null(RS)) stop("[krf] krf_build: RS(정정 의심 연도 DART 기록) 없음 — v1.0 규칙으로 돌아가지 않는다")
  st <- as.Date(cfg$start_date)
  if (anyDuplicated(RAW, by = c("Date", "Ticker"))) stop("[krf] RAWDATA (Date, Ticker) 겹침 — 중단")
  setorder(RAW, Ticker, Date)
  RAW[, ME_l1 := shift(Size, 1L), by = Ticker]
  if (!is.null(to)) RAW <- RAW[Date <= as.Date(to)]
  K <- krf_calendar(RAW, as.integer(cfg$guards$trading_day_min_rows))
  RAW <- RAW[Date %in% K$cal$Date]
  SNAP <- krf_snap(RAW, K$me)
  AF <- krf_annual_fund(FUND, RS)
  last <- max(K$cal$Date)
  yrs <- seq(as.integer(format(st, "%Y")) - 1L, as.integer(format(last, "%Y")))
  ANN <- krf_annual_labels(SNAP, AF, yrs, cfg)
  st_ym <- .ym_of(st)
  MOM <- krf_mom_labels(SNAP, cfg, .ym_add(st_ym, -1L))
  UM <- SNAP[member %in% TRUE & is.finite(ME) & ME > 0, .(Ticker, fym = ym)]
  RD <- RAW[Date >= st & is.finite(Ret) & is.finite(ME_l1) & ME_l1 > 0, .(Date, Ticker, Ret, ME_l1)]
  RD[, ym := .ym_of(Date)]
  fm <- as.integer(cfg$annual_sort$formation_month)
  RD[, `:=`(hy = .krf_hold_year(ym, fm), fym = .ym_add(ym, -1L))]
  CAP <- krf_caps(SNAP, cfg)
  if (is.null(CAP)) RD[, W := ME_l1] else {
    RD[CAP, cap := i.cap, on = .(fym)]
    RD[, W := fifelse(is.finite(cap), pmin(ME_l1, cap), NA_real_)]           # 직전 월말 상한 — 없으면 가중 없음(지어내지 않는다)
  }
  PD <- krf_daily_ports(RD, ANN$labels, MOM$labels, UM)
  capped_share <- if (is.null(CAP)) 0 else RD[is.finite(cap), mean(ME_l1 > cap)]
  ext <- RD[, .(n_abs_gt50 = sum(abs(Ret) > 0.5)), by = .(y = as.integer(format(Date, "%Y")))]
  rm(RD); gc(verbose = FALSE)
  # 일간 요인
  RFd <- krf_rf_daily(RFY, K$cal$Date[K$cal$Date >= st])
  FD <- krf_factors(PD[, .(k = Date, sort, port, r, n)])
  setnames(FD, "k", "Date")
  FD <- merge(FD, RFd, by = "Date", all.x = TRUE)
  FD[, MKT := MKT_TOTAL - RF]
  # 월간: 포트폴리오 일간 수익을 달 안에서 복리(그 달 거래일 전부 있어야 — 빠지면 NA)
  nd <- K$cal[, .(n_td = .N), by = ym]
  PD[, ym := .ym_of(Date)]
  PM <- PD[, .(r = prod(1 + r) - 1, n_days = .N, n_avg = mean(n), n_min = min(n)), by = .(sort, port, ym)]
  PM <- merge(PM, nd, by = "ym", all.x = TRUE)
  PM[n_days < n_td, r := NA_real_]
  RFm <- merge(RFd[, .(ym = .ym_of(Date), RF)][, .(RF = if (anyNA(RF)) NA_real_ else prod(1 + RF) - 1, n_rf = .N), by = ym], nd, by = "ym")
  RFm[n_rf < n_td, RF := NA_real_]
  FM <- krf_factors(PM[, .(k = ym, sort, port, r, n = n_avg)])
  setnames(FM, "k", "ym")
  FM <- merge(FM, RFm[, .(ym, RF)], by = "ym", all.x = TRUE)
  FM[, MKT := MKT_TOTAL - RF]
  FM <- merge(FM, K$me, by = "ym", all.x = TRUE)
  setnames(FM, "me_date", "Date")
  # 완결 월만 — 마지막 달은 그 달에 남은 평일이 없을 때만 싣는다(공휴일 판정 없이 보수적으로)
  lm <- .ym_of(last)
  m1 <- as.Date(sprintf("%04d-%02d-01", lm %/% 100L, lm %% 100L))
  m_end <- seq(m1, by = "1 month", length.out = 2L)[2L] - 1L
  rest <- if (last < m_end) seq(last + 1L, m_end, by = "day") else as.Date(character(0))
  if (any(as.integer(format(rest, "%u")) <= 5L)) FM <- FM[ym < lm]
  nsort <- ANN$labels[, .N, by = .(fy, sort)]
  FM[, hy := .krf_hold_year(ym, fm)]
  FM <- merge(FM, nsort[sort == "BM", .(hy = fy, n_obs_meta = as.numeric(N))], by = "hy", all.x = TRUE)
  FM[, hy := NULL]
  cols <- c("Date", "MKT", "SMB", "HML", "WML", "RMW", "CMA", "RF", "n_obs_meta", "SMB5", "SMB_BM", "SMB_OP", "SMB_INV", "MKT_TOTAL", "ym")
  setcolorder(FM, intersect(cols, names(FM)))
  setorder(FM, ym); setorder(FD, Date)
  CH <- krf_chars(SNAP, AF, cfg, st_ym)
  PMo <- merge(PM, K$me, by = "ym", all.x = TRUE)
  setnames(PMo, "me_date", "Date")
  list(daily = FD[Date >= st], monthly = FM[ym >= st_ym], ports_monthly = PMo[ym >= st_ym][order(sort, port, ym)],
       chars = CH, caps = CAP,
       diag = list(annual = ANN$diag, annual_causes = ANN$causes, mom = MOM$diag, ret_abs_gt50_by_year = ext, last_date = last,
                   weighting = as.character(cfg$weighting$rule %||% "vw"), capped_row_share = capped_share))
}

## ── 입력 적재(실자료) ───────────────────────────────────────────────────────
krf_load_inputs <- function(root, cfg) {
  src <- fromJSON(file.path(root, cfg$fundamentals$registry), simplifyVector = TRUE)
  if (!identical(as.character(src$active), as.character(cfg$fundamentals$requires_active_source)))
    stop("[krf] 재무 원천 active = '", src$active, "' — 설정은 '", cfg$fundamentals$requires_active_source, "' 를 요구(fail-closed)")
  lb <- as.Date(cfg$lookback_start)
  cols <- c("Date", "Ticker", "Close", "Vol", "Size", "Ret", "AdminStock", "TradingHalt", "UnfaithfulDisc")
  RAW <- as.data.table(read_parquet(file.path(root, ".cache", "rawdata.parquet"), col_select = tidyselect::all_of(cols)))
  RAW[, Date := as.Date(Date)]
  RAW <- RAW[Date >= lb]
  # 측정 축 멤버십 — 정본 계약(위생 · 20일 거래대금 t−1 · 동전주 바닥)
  source(file.path(root, "02_Infrastructure", "contracts", "measurement_axis.R"), local = TRUE)
  ep <- ma_epoch(NULL, root)
  setorder(RAW, Ticker, Date)
  RAW[, member := ma_membership(RAW, ep)]
  RAW[, c("Vol", "AdminStock", "TradingHalt", "UnfaithfulDisc") := NULL]
  fp <- file.path(root, cfg$fundamentals$table)
  items <- KRF_FUND_ITEMS
  fcols <- c("Ticker", "Period", "Item", "Value", "Factor_Date", "Check", "Avail_Basis")   # Check · Avail_Basis = 정렬 원인 진단 전용
  miss <- setdiff(fcols, names(open_dataset(fp)))
  if (length(miss)) stop("[krf] 재무 표 열 없음: ", paste(miss, collapse = ","), " — 정렬 원인 진단을 가를 수 없다(중단)")
  FUND <- as.data.table(open_dataset(fp) |> dplyr::filter(Item %in% items) |>
                          dplyr::select(dplyr::all_of(fcols)) |> dplyr::collect())
  # v1.1 정정 의심 연도 DART 당시 기록 — 설정 · 세 파일 가운데 하나라도 없으면 빌드하지 않는다(fail-closed · 옛 요인 파일 유지)
  rr <- cfg$fundamentals$restated_record
  rr_keys <- c("check_table", "dart_annual", "dart_raw")
  if (is.null(rr) || length(setdiff(rr_keys, names(rr))))
    stop("[krf] 설정 fundamentals.restated_record 의 ", paste(setdiff(rr_keys, names(rr)), collapse = ","), " 없음 — v1.0 규칙으로 돌아가지 않는다")
  rp <- vapply(rr_keys, function(k) file.path(root, rr[[k]]), character(1))
  if (any(!file.exists(rp))) stop("[krf] 정정 의심 연도 DART 기록 입력 없음: ", paste(rp[!file.exists(rp)], collapse = " | "),
                                  " — 빌드 중단(정정 의심 기업을 정렬에서 빼는 v1.0 규칙으로 돌아가지 않는다)")
  REST <- as.data.table(open_dataset(fp) |> dplyr::filter(Check == "restated") |> dplyr::distinct(Ticker, Period) |> dplyr::collect())
  REST <- unique(REST[, .(Ticker, fy = as.integer(substr(as.character(Period), 1L, 4L)))])
  CK <- as.data.table(read_parquet(rp[["check_table"]], col_select = c("Ticker", "FY", "DART_Date", "DART_Factor_Date")))
  FD <- as.data.table(read_parquet(rp[["dart_annual"]], col_select = c("Ticker", "bsns_year", "TotalAssets", "TotalEquity", "OperatingProfit", "InterestExp")))
  ids <- c(as.vector(outer(c("ifrs_", "ifrs-full_"), c("EquityAttributableToOwnersOfParent", "Equity", "NoncontrollingInterests"), paste0)),
           "dart_IssuedCapitalOfPreferredStock")
  RAWB <- as.data.table(open_dataset(rp[["dart_raw"]]) |> dplyr::filter(sj_div == "BS" & account_id %in% ids) |>
                          dplyr::select(dplyr::all_of(c("Ticker", "bsns_year", "rcept_no", "fs_div", "account_id", "thstrm_amount"))) |>
                          dplyr::collect())
  RR <- krf_restated_record(REST, CK, FD, RAWB)
  bp <- file.path(root, cfg$rf$bond_path)
  RFY <- as.data.table(read_parquet(bp))[Series == cfg$rf$series, .(Date = as.Date(Date), y = as.numeric(Value))]
  if (!nrow(RFY)) stop("[krf] RF 계열 없음: ", cfg$rf$series)
  fi <- function(p) { x <- file.info(p); list(path = .krf_rel(p, root), size = unname(x$size), mtime = format(x$mtime, "%Y-%m-%dT%H:%M:%S")) }
  list(RAW = RAW, FUND = FUND, RFY = RFY, epoch = ep, RS = RR$RS, rs_diag = RR$diag,
       inputs = list(rawdata = fi(file.path(root, ".cache", "rawdata.parquet")), fundamentals = fi(fp), rf = fi(bp),
                     restated_check = fi(rp[["check_table"]]), restated_dart_annual = fi(rp[["dart_annual"]]),
                     restated_dart_raw = fi(rp[["dart_raw"]]),
                     fundamental_source_active = src$active))
}

## ── 쓰기 ────────────────────────────────────────────────────────────────────
.krf_rel <- function(p, base) {                    # 정규식 없이 접두 제거(한글 · 특수 문자 경로 안전)
  p <- gsub("\\\\", "/", p); b <- paste0(sub("/+$", "", gsub("\\\\", "/", base)), "/")
  if (startsWith(p, b)) substring(p, nchar(b) + 1L) else p
}

.krf_content_md5 <- function(DT, cols) {
  tf <- tempfile(fileext = ".csv")
  on.exit(unlink(tf), add = TRUE)
  X <- DT[, cols, with = FALSE]
  for (c in cols) if (is.numeric(X[[c]])) set(X, j = c, value = ifelse(is.na(X[[c]]), "NA", sprintf("%.12g", X[[c]])))
  fwrite(X, tf, eol = "\n")
  unname(tools::md5sum(tf))
}

.krf_atomic_parquet <- function(DT, path) {
  tmp <- paste0(path, ".tmp_", Sys.getpid())
  write_parquet(DT, tmp)
  if (file.exists(path) && !file.remove(path)) { unlink(tmp); stop("[krf] 기존 파일 제거 실패: ", path) }
  if (!file.rename(tmp, path)) stop("[krf] 이름 바꾸기 실패: ", path)
}

krf_summary <- function(FM) {
  f <- c("MKT", "SMB", "SMB5", "HML", "RMW", "CMA", "WML", "RF")
  rbindlist(lapply(intersect(f, names(FM)), function(c) {
    x <- FM[[c]]; ok <- is.finite(x)
    data.table(factor = c, n = sum(ok), first = if (any(ok)) format(min(FM$Date[ok])) else NA_character_,
               mean_pct = round(100 * mean(x[ok]), 4), sd_pct = round(100 * stats::sd(x[ok]), 4),
               t_simple = round(mean(x[ok]) / (stats::sd(x[ok]) / sqrt(sum(ok))), 3))
  }))
}

krf_write <- function(res, out, cfg, inputs, epoch, vintage = TRUE, rs_diag = NULL) {
  dir.create(out, recursive = TRUE, showWarnings = FALSE)
  o <- cfg$outputs
  .krf_atomic_parquet(res$daily, file.path(out, o$daily))
  .krf_atomic_parquet(res$monthly, file.path(out, o$monthly))
  .krf_atomic_parquet(res$ports_monthly, file.path(out, o$ports_monthly))
  .krf_atomic_parquet(res$chars, file.path(out, o$chars_monthly))
  mcols <- c("Date", "MKT", "SMB", "HML", "WML", "RMW", "CMA", "RF", "SMB5")
  md5m <- .krf_content_md5(res$monthly, mcols)
  vint <- NULL
  if (isTRUE(vintage)) {
    vd <- file.path(out, o$vintage_dir); dir.create(vd, showWarnings = FALSE)
    vint <- file.path(vd, paste0(substr(md5m, 1, 12), ".parquet"))
    if (!file.exists(vint)) write_parquet(res$monthly, vint)
  }
  ad <- res$diag$annual
  cz <- res$diag$annual_causes
  bmz <- if (is.data.frame(cz) && nrow(cz) && "sort" %in% names(cz))
    cz[sort == "BM", .(fy, n_universe, excl_late_dart_version,
                       share_late_dart_version = round(excl_late_dart_version / n_universe, 4),
                       excl_late_filing, excl_late_restated_no_record, excl_late_unknown_basis, excl_late_restated)] else NULL
  tot <- function(c) if (is.null(bmz)) 0L else as.integer(sum(bmz[[c]]))
  late_pending <- list(
    ## (2026-11-10 도훈 결정 KRFF-LATE-DART-VERSION-DISPOSITION-20261110) 결측 유지 + 최초 제출본 수집 승인 — 규칙 불변.
    ##   DART 최초 제출본 재무 파이프라인(06_Registry/data_pipeline_queue.json)이 그 판을 공급하면 이 군이 줄어든다.
    status = "decided_keep_missing", decision = "KRFF-LATE-DART-VERSION-DISPOSITION-20261110",
    rule_changed = FALSE, current_rule = "결측 유지((i))",
    options = c("(i) 결측 유지", "(ii) 최초 공시일로 편입"),
    decision_target = "excl_late_dart_version",
    doc = paste("결정 대상 = 보유 DART 판이 구성일 뒤 기재정정본이라 구성일에 쓸 판이 원천에 없는 기업-연도(v2 표 Avail_Basis = dart_rcept ·",
                "Factor_Date 가 보유 판 접수일로 미뤄진 군 = excl_late_dart_version) — 도훈 11-10 결정: 결측 유지(최초 제출본 수집 승인 · 수집 전까지 결측으로 센다).",
                "행마다 원인은 하나다: (ii) 로도 남는 원인(퀀티 공시 자체가 구성일 뒤 = excl_late_filing · 정정 의심인데 DART 기록 없음 =",
                "excl_late_restated_no_record · 근거 미상 = excl_late_unknown_basis · 정정 의심 기록 날짜 뒤 = excl_late_restated ·",
                "자료 없음)을 먼저 세고 excl_late_dart_version 은 결측 원인 가운데 마지막이다 — 결정 대상 칸에는 결정 대상 군만 든다.",
                "B/M 정렬에서 12월 말 시총이 없는 신규 상장은 먼저 excl_new_listing 으로 센다(재무 규칙과 무관하게 빠진다)"),
    bm_by_fy = bmz,
    bm_total_late_dart_version = tot("excl_late_dart_version"),
    bm_total_not_decision_target = list(late_filing = tot("excl_late_filing"), late_restated_no_record = tot("excl_late_restated_no_record"),
                                        late_unknown_basis = tot("excl_late_unknown_basis"), late_restated = tot("excl_late_restated")))
  meta <- list(
    schema = "kr_factor_returns_meta_v1", builder = KRF_BUILDER, cfg_version = cfg$version,
    built_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    epoch = epoch$id, universe = epoch$universe, inputs = inputs,
    weighting = list(rule = res$diag$weighting, cap_quantile = cfg$weighting$cap_quantile %||% NA,
                     capped_row_share = round(res$diag$capped_row_share, 4)),
    last_input_date = format(res$diag$last_date),
    daily = list(rows = nrow(res$daily), first = format(min(res$daily$Date)), last = format(max(res$daily$Date))),
    monthly = list(rows = nrow(res$monthly), first = format(min(res$monthly$Date)), last = format(max(res$monthly$Date)),
                   content_md5 = md5m, content_cols = mcols,
                   vintage_file = if (is.null(vint)) NULL else .krf_rel(vint, out)),
    summary_monthly = krf_summary(res$monthly),
    annual_sorts = ad[, .(fy, sort, fdate = format(fdate), n_universe, n_sort, n_big, ok)],
    annual_sort_causes = cz,
    restated_record = c(list(rule = "quantiwise_if_public_else_dart_record",
                             doc = "정정 의심 기업-연도는 DART 당시 보고서 기록(접수 다음 거래일)을 쓴다 — 정정 의심 표지로 표본을 거르지 않는다(v1.1)",
                             late_version_pending = late_pending),
                        rs_diag %||% list()),
    momentum_sort_n = list(median = stats::median(res$diag$mom$n_sort), min = min(res$diag$mom$n_sort)),
    ret_abs_gt50_by_year = res$diag$ret_abs_gt50_by_year,
    columns = list(MKT = "시장 초과수익 = MKT_TOTAL − RF", RF = "CD91 전 거래일 금리의 일간 환산 복리(월간 = 그 달 복리)",
                   SMB = "3요인판(B/M 정렬)", SMB5 = "5요인판(B/M · OP · INV 정렬 평균)", WML = "모멘텀(UMD)",
                   n_obs_meta = "그 보유연도 B/M 정렬 종목 수")
  )
  writeLines(toJSON(meta, auto_unbox = TRUE, pretty = TRUE, digits = NA, na = "null", null = "null"),
             file.path(out, o$meta), useBytes = TRUE)
  invisible(meta)
}

## ── 실행 ────────────────────────────────────────────────────────────────────
krf_main <- function(args = commandArgs(trailingOnly = TRUE)) {
  root <- krf_root()
  arg <- function(k) { i <- match(k, args); if (is.na(i) || i == length(args)) NULL else args[i + 1L] }
  out <- arg("--out") %||% file.path(root, ".cache")
  to <- arg("--to")
  t0 <- Sys.time()
  cfg <- krf_config(root)
  cat(sprintf("[krf] %s · 설정 %s · out = %s\n", KRF_BUILDER, cfg$version, out))
  I <- krf_load_inputs(root, cfg)
  cat(sprintf("[krf] 입력: RAWDATA %s행 · 재무 %s행 · RF %s일 · epoch %s (%.0fs)\n", format(nrow(I$RAW), big.mark = ","),
              format(nrow(I$FUND), big.mark = ","), format(nrow(I$RFY), big.mark = ","), I$epoch$id,
              as.numeric(difftime(Sys.time(), t0, units = "secs"))))
  cat(sprintf("[krf] 정정 의심 기업-연도 %d · DART 기록 %d(BE %d · TA %d · OPN %d · 판 날짜 불일치로 BE 원장 값 버림 %d)\n",
              I$rs_diag$restated_company_years, I$rs_diag$with_dart_date, I$rs_diag$with_be, I$rs_diag$with_ta,
              I$rs_diag$with_opn, I$rs_diag$raw_version_date_mismatch))
  res <- krf_build(I$RAW, I$FUND, I$RFY, cfg, to = to, RS = I$RS)
  meta <- krf_write(res, out, cfg, I$inputs, I$epoch, vintage = !("--no-vintage" %in% args), rs_diag = I$rs_diag)
  cat(sprintf("[krf] 일간 %d행(%s~%s) · 월간 %d행(%s~%s) · 특성 %d행 · 월간 내용 md5 %s (%.0fs)\n",
              meta$daily$rows, meta$daily$first, meta$daily$last, meta$monthly$rows, meta$monthly$first, meta$monthly$last,
              nrow(res$chars), substr(meta$monthly$content_md5, 1, 12), as.numeric(difftime(Sys.time(), t0, units = "secs"))))
  lv <- meta$restated_record$late_version_pending
  nt <- lv$bm_total_not_decision_target
  cat(sprintf(paste0("[krf] B/M 정렬 결측 — 보유 DART 판 접수일 뒤(결측 유지 — 도훈 11-10 결정 · 최초 제출본 수집 대기) 누계 %d · 결정 대상 밖: 퀀티 공시 뒤 %d · ",
                     "정정 의심 기록 없음 %d · 근거 미상 %d · 정정 의심 기록 날짜 뒤 %d (연도별 = meta annual_sort_causes)\n"),
              as.integer(lv$bm_total_late_dart_version), as.integer(nt$late_filing), as.integer(nt$late_restated_no_record),
              as.integer(nt$late_unknown_basis), as.integer(nt$late_restated)))
  print(meta$summary_monthly)
  invisible(meta)
}

if (sys.nframe() == 0L) krf_main()
