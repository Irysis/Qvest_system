#!/usr/bin/env Rscript
# test_dart_account_id_fallback.R — DART 표준계정코드 폴백의 위반 주입 테스트 (2026-08-08).
#
# 왜 있나: `dart_parse_financials()` 는 원래 `account_nm %in% patterns` 로 **한글 계정명
#   완전일치**만 인식했다. 실제 응답은 기업마다 표기가 달라("법인세비용" vs "법인세비용(수익)",
#   "배당금지급" vs "배당금의 지급", "이익잉여금" vs "이익잉여금(결손금)") 목록 밖 표기가
#   조용히 탈락했고 — FY2023 유니버스 실측 법인세비용 25.7%·이익잉여금 35.6% —
#   그 빈자리를 `.pit_fund()` 의 무제한 carry-forward 가 FY2014 값으로 메워
#   **커버리지 지표에는 정상으로 보였다**. 2026-08-08 에 account_id(IFRS 표준태그) 폴백을 넣었다.
#
# ★설계 축 (존재 검사로 정체성 검사를 대체하지 않기 위해):
#   (A) 추가-전용 불변식 — 이름 매칭으로 이미 잡히던 값은 **한 건도 바뀌면 안 된다**.
#       이게 깨지면 과거 측정·판정과의 비교 가능성이 사라진다(가장 중요한 축).
#   (B) 폴백 실효 — 표기 변형 종목이 실제로 회수되는가.
#   (C) 감가상각비 합산 — Dep + Amort 는 D&A 의 *구성요소*이므로 first-wins 로 뽑으면
#       과소계상된다. 합산이 맞는지 값으로 확인.
#   (D) ★오인식 배제 — 이름이 비슷하지만 개념이 다른 태그를 끌어오지 않는가.
#       OCI 법인세 / 배당금'수취' / 자본변동표 배당(부호 반대). 이 축이 없으면
#       "커버리지가 올랐다"가 "틀린 값으로 채웠다"와 구별되지 않는다.
#   (E) 전제 부재 처리 — account_id 컬럼이 없는 구 캐시는 **경고와 함께 건너뛴다**
#       (조용한 성공 금지).
#   (F) 돌연변이 — 태그를 훼손하면 커버리지가 baseline 으로 **떨어져야** 한다.
#       안 떨어지면 폴백이 죽었거나 애초에 발화하지 않은 것이다.

.root <- local({
  .marker <- file.path("02_Infrastructure", "data", "data_collector_dart.R")
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", a[grep("^--file=", a)])
  if (length(f)) {
    d <- dirname(normalizePath(f[1], winslash = "/", mustWork = FALSE))
    r <- normalizePath(file.path(d, "..", ".."), winslash = "/", mustWork = FALSE)
    if (file.exists(file.path(r, .marker))) return(r)
  }
  for (k in c("CLAUDE_PROJECT_DIR", "QM_ROOT")) {
    v <- Sys.getenv(k, "")
    if (nzchar(v) && file.exists(file.path(v, .marker))) return(v)
  }
  cand <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
  if (file.exists(file.path(cand, .marker))) cand else getwd()
})

suppressMessages({ library(data.table) })
PASS <- 0; FAIL <- 0
ok  <- function(m) { PASS <<- PASS + 1; cat(sprintf("  [PASS] %s\n", m)) }
bad <- function(m, d) { FAIL <<- FAIL + 1; cat(sprintf("  [FAIL] %s — %s\n", m, d)) }

TARGET <- file.path(.root, "02_Infrastructure", "data", "data_collector_dart.R")
if (!file.exists(TARGET)) { cat("FATAL: 대상 부재:", TARGET, "\n"); quit(status = 2) }

# 수집기 본체는 .env(API 키)를 요구하므로, 파서 함수만 격리 로드한다.
src <- readLines(TARGET, warn = FALSE)
b <- grep("^dart_parse_financials <- function", src)
if (!length(b)) { cat("FATAL: dart_parse_financials 정의를 못 찾음\n"); quit(status = 2) }
e <- grep("^dart_compute_factors <- function", src)
e <- if (length(e)) e[e > b[1]][1] - 1L else length(src)
eval(parse(text = paste(src[b[1]:e], collapse = "\n")), envir = globalenv())

# ── 픽스처: 표기 변형·태그·배제 케이스를 모두 담은 최소 합성 응답 ──────────────
row <- function(tk, sj, id, nm, amt)
  data.table(Ticker = tk, bsns_year = 2023L, sj_div = sj,
             account_id = id, account_nm = nm, thstrm_amount = as.character(amt))
FIX <- rbindlist(list(
  # A사: 모든 계정을 "표준 표기"로 → 이름 매칭이 성공하는 대조군
  row("A001","BS","ifrs-full_Assets","자산총계",1000),
  row("A001","BS","ifrs-full_Liabilities","부채총계",400),
  row("A001","BS","ifrs-full_Equity","자본총계",600),
  row("A001","BS","ifrs-full_RetainedEarnings","이익잉여금",300),
  row("A001","IS","ifrs-full_IncomeTaxExpenseContinuingOperations","법인세비용",50),
  row("A001","CF","ifrs-full_CashFlowsFromUsedInInvestingActivities","투자활동현금흐름",-70),
  # B사: 표기 변형 → 이름 매칭 실패, 태그로만 회수 가능
  row("B002","BS","ifrs-full_Assets","연결재무상태표 자산 합계",2000),
  row("B002","BS","ifrs-full_Liabilities","부채 합계",800),
  row("B002","BS","ifrs-full_Equity","자본 합계",1200),
  row("B002","BS","ifrs-full_RetainedEarnings","이익잉여금(결손금)",500),
  row("B002","IS","ifrs-full_IncomeTaxExpenseContinuingOperations","법인세비용(수익)",90),
  row("B002","CF","ifrs-full_CashFlowsFromUsedInInvestingActivities","투자활동으로 인한 현금유출",-120),
  # B사 감가상각비: 손익계산서에 없고 현금흐름표 조정항목 2줄로만 존재 → 합산되어야 함
  row("B002","CF","ifrs-full_AdjustmentsForDepreciationExpense","감가상각",30),
  row("B002","CF","ifrs-full_AdjustmentsForAmortisationExpense","무형자산상각",7),
  # C사: 오인식 유도 — 개념이 다른 태그만 보유. 어떤 항목도 채워지면 안 된다.
  row("C003","CIS","ifrs-full_IncomeTaxRelatingToComponentsOfOtherComprehensiveIncomeThatWillBeReclassifiedToProfitOrLoss","법인세효과",11),
  row("C003","CF","ifrs-full_DividendsReceivedClassifiedAsOperatingActivities","배당금의 수취",22),
  row("C003","SCE","ifrs-full_DividendsPaid","연차배당",33),
  row("C003","BS","ifrs-full_LongtermBorrowings","비유동차입금의 비유동성 부분",44)
))

cat("== (A) 추가-전용 불변식: 기존 이름-매칭 값 불변 ==\n")
p_new <- dart_parse_financials(copy(FIX))
FIX_noid <- copy(FIX)[, account_id := NULL]
p_old <- suppressWarnings(dart_parse_financials(FIX_noid))
items <- setdiff(intersect(names(p_old), names(p_new)), c("Ticker", "bsns_year"))
m <- merge(p_old, p_new, by = c("Ticker", "bsns_year"), suffixes = c(".old", ".new"))
changed <- 0L; checked <- 0L
for (v in items) {
  o <- m[[paste0(v, ".old")]]; n <- m[[paste0(v, ".new")]]
  i <- !is.na(o); checked <- checked + sum(i)
  changed <- changed + sum(i & (is.na(n) | abs(o - n) > 1e-9 * pmax(1, abs(o))))
}
if (checked == 0) {
  bad("불변식 검사 자체가 공허", "기존 값 0건 — 픽스처가 이름 매칭을 전혀 못 시킴")
} else if (changed == 0) {
  ok(sprintf("기존 값 %d건 전부 불변", checked))
} else {
  bad("기존 값이 변경됨", sprintf("%d/%d 셀", changed, checked))
}

cat("== (B) 폴백 실효: 표기 변형 종목 회수 ==\n")
gv <- function(p, tk, v) { r <- p[Ticker == tk]; if (!nrow(r) || !v %in% names(r)) NA_real_ else r[[v]][1] }
for (v in c("TotalAssets", "RetainedEarnings", "TaxExpense", "InvestCF")) {
  before <- gv(p_old, "B002", v); after <- gv(p_new, "B002", v)
  if (is.na(before) && !is.na(after)) {
    ok(sprintf("B002 %s: 미인식 -> %s", v, format(after)))
  } else {
    bad(sprintf("B002 %s 회수 실패", v), sprintf("before=%s after=%s", before, after))
  }
}

cat("== (C) 감가상각비 = Dep + Amort 합산 ==\n")
d <- gv(p_new, "B002", "DepAmort")
if (isTRUE(all.equal(d, 37))) {
  ok("DepAmort = 30 + 7 = 37 (합산)")
} else {
  bad("DepAmort 합산 오류", sprintf("기대 37, 실제 %s (30 이면 first-wins 로 과소계상)", d))
}

cat("== (D) 오인식 배제: 개념이 다른 태그를 끌어오지 않는가 ==\n")
chk_na <- function(v, why) {
  x <- gv(p_new, "C003", v)
  if (is.na(x)) {
    ok(sprintf("C003 %s = NA (%s)", v, why))
  } else {
    bad(sprintf("C003 %s 오인식", v), sprintf("%s 인데 %s 로 채워짐", why, format(x)))
  }
}
chk_na("TaxExpense",   "OCI 법인세는 법인세비용이 아님")
chk_na("Dividends",    "배당금'수취'/자본변동표 배당(부호 반대)은 배당금지급이 아님")
chk_na("LongTermBorr", "사채/차입금 개념 혼재로 태그 폴백 미적용")

cat("== (E) 전제 부재: account_id 없는 구 캐시는 경고와 함께 건너뜀 ==\n")
w <- NULL
withCallingHandlers(dart_parse_financials(copy(FIX_noid)),
                    warning = function(x) { w <<- c(w, conditionMessage(x)); invokeRestart("muffleWarning") })
if (length(w) && any(grepl("account_id", w, fixed = TRUE))) {
  ok("account_id 부재 시 경고 발생 (조용한 성공 아님)")
} else {
  bad("전제 부재가 조용히 통과", "account_id 부재인데 경고 없음")
}

cat("== (F) 돌연변이: 태그 훼손 시 커버리지 하락 ==\n")
for (tg in c("ifrs-full_RetainedEarnings", "ifrs-full_IncomeTaxExpenseContinuingOperations")) {
  MUT <- copy(FIX); MUT[account_id == tg, account_id := "ifrs-full_MUTATED"]
  pm <- dart_parse_financials(MUT)
  v  <- if (grepl("Retained", tg)) "RetainedEarnings" else "TaxExpense"
  n_ok <- sum(!is.na(p_new[[v]])); n_mut <- if (v %in% names(pm)) sum(!is.na(pm[[v]])) else 0L
  if (n_mut < n_ok) {
    ok(sprintf("%s 훼손 -> %d건 -> %d건 (검사 살아있음)", v, n_ok, n_mut))
  } else {
    bad(sprintf("%s 돌연변이 미검출", v), sprintf("%d -> %d (폴백이 죽었거나 미발화)", n_ok, n_mut))
  }
}

cat("== (G) 회계 항등식: 자산총계 = 부채총계 + 자본총계 ==\n")
q <- p_new[!is.na(TotalAssets) & !is.na(TotalLiab) & !is.na(TotalEquity)]
if (!nrow(q)) {
  bad("항등식 검사 공허", "대상 0행")
} else if (all(abs(q$TotalAssets - (q$TotalLiab + q$TotalEquity)) < 1e-6)) {
  ok(sprintf("%d개 기업-연도 항등식 성립", nrow(q)))
} else {
  bad("항등식 위반", "태그 선택이 잘못된 값을 채웠을 수 있음")
}

cat(sprintf("\nFINAL: PASS=%d FAIL=%d\n", PASS, FAIL))
quit(status = if (FAIL > 0) 1 else 0)
