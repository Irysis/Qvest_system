#==============================================================================
# liquidity_basis.R — 유동성(거래대금) 자를 **한 조정기준 위에서** 재게 하는 모듈 (구멍 A)
#
# 2026-09-07 신설. basis_break_scan.R 이 실측한 기준 단절을 소비한다.
#
# ─── 먼저: 왜 "가격 레벨 재척도" 가 아닌가 (실측 근거) ───────────────────────
# 액면분할/병합은 Close 를 x k 로, Vol 을 x 1/k 로 움직인다.
#     거래대금 = Close x Vol = (k*Close) x (Vol/k)  ⇒ **기준 불변**
# 실측이 그대로 확인한다(2026-09-07, 2026-03-30 확정 단절):
#     하루 거래대금 비율   단절 275건 q25 0.573 · q50 0.858 · q75 1.537
#                          정상 2,200건 q25 0.632 · q50 0.857 · q75 1.247
#     10세션 창 비율       단절 343건 q25 0.610 · q50 0.867 · q75 1.377
#                          무작위 대조 1,437건 q25 0.644 · q50 0.916 · q75 1.378
#     (중앙 |log2| 0.616 vs 0.557)
# ⇒ adv20 이 기준 단절을 가로질러도 **대부분 이미 한 기준 위에 있다**. 두 배수가 상쇄된다.
# ⇒ 반대로 **가격 레벨만** 한 기준으로 재척도하면 그 상쇄가 깨져 거래대금이 배수만큼
#    틀어진다. 그리고 Close*Vol 소비 지점은 02_Infrastructure 안에만 72파일이다.
#    ★그래서 이 모듈은 어떤 가격·수량 레벨도 건드리지 않는다.
#
# ─── 그러면 무엇이 남는가: **한쪽 다리만 재척도된** 경우 ─────────────────────
# 실측 초과분: |log2(창 TV 비율)|>2 가 단절 11.7% vs 대조 6.1% (초과 5.6%p).
# 전기간 스윕에서 이 잔여 + undecidable = 107건(기준단절 43 + 판정불가 64)이다.
# 그 창에서만 거래대금 시계열에 **계단**이 있고, 20일 평균이 두 기준을 섞는다.
#
# ─── 처분: NA 가 아니라 **창 재시작** ────────────────────────────────────────
# ★NA 로 비우면 안 된다. canonical_screen_bt 는 `is.na(adv) | adv >= liq_min` 이라
#   NA 가 **통과**한다 — 결손이 제약 완화가 된다(factor_validation.R FQ-181 규약).
# ★임의 수정(재척도)도 안 된다 — 다리가 어긋난 이유를 모르는 채 고치는 것이다.
# ⇒ 남는 옳은 처분: 단절 지점에서 평균 창을 **재시작**한다. 이는 build_adv20_t1 이
#   이미 종목의 첫 20거래일에 쓰는 adaptive 확장창과 **같은 기전**이다 —
#   "같은 기준 위의 관측만 평균한다" 는 규약을 신규 상장이 아니라 기준 단절에도 적용한다.
#   값은 항상 측정되고(완화 없음), 두 기준을 섞지 않으며, 창이 짧아진 만큼만 잡음이 는다.
#
# 사용법:
#   source(file.path(DATA_DIR, "liquidity_basis.R"))
#   rp <- liq_basis_reset_points()                 # 레지스트리에서 재시작 지점
#   adv <- build_adv20_t1(daily, at_dates, basis_reset = rp)   # factor_validation.R
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(jsonlite)
})

.liqb_root <- function() {
  cands <- c(if (exists("PROJECT_ROOT", envir = globalenv(), inherits = FALSE))
               get("PROJECT_ROOT", envir = globalenv()) else NULL,
             Sys.getenv("CLAUDE_PROJECT_DIR", unset = ""),
             Sys.getenv("QM_ROOT", unset = ""))
  cands <- gsub("\\\\", "/", cands[nzchar(cands)])
  for (p in cands)
    if (file.exists(file.path(p, "02_Infrastructure/hooks/qvest_hook_router.py"))) return(p)
  stop("[liquidity_basis] PROJECT_ROOT 미해석 — marker 를 가진 후보 없음")
}

LIQ_BASIS_REGISTRY <- function(root = .liqb_root())
  file.path(root, "06_Registry", "basis_break_registry.json")

#' 기준 단절 레지스트리 → 유동성 창 **재시작 지점**.
#'
#' 재시작하는 자리는 "기준이 끊긴 전부"가 아니라 **거래대금 시계열에 계단이 남은 자리**다:
#'   action == "block_liquidity_window"  (다리 불일치 43 + 판정불가 64)
#' 다리가 정합인 단절(303건)은 거래대금이 이미 불변이므로 재시작하지 않는다 —
#' 불필요하게 창을 잘라 표본만 잃는다(상쇄되는 것을 '고치면' 그때 오염이 생긴다).
#'
#' @param path 레지스트리 경로. 부재면 0행(가드 부재를 조용한 통과로 바꾸지 않으려면
#'   호출부가 strict 로 물어야 한다 — liq_basis_require() 참조)
#' @return data.table(Ticker, Date) — Date = 새 기준의 **첫 거래일**
liq_basis_reset_points <- function(path = LIQ_BASIS_REGISTRY(),
                                   actions = "block_liquidity_window") {
  empty <- data.table(Ticker = character(0), Date = as.Date(character(0)))
  if (!file.exists(path)) return(empty)
  js <- jsonlite::fromJSON(path, simplifyVector = TRUE)
  e <- js$entries
  if (is.null(e) || !length(e) || !NROW(e)) return(empty)
  e <- as.data.table(e)
  if (!all(c("Ticker", "Date", "action") %in% names(e))) return(empty)
  out <- e[action %chin% actions, .(Ticker = as.character(Ticker), Date = as.Date(Date))]
  unique(out[!is.na(Date) & nzchar(Ticker)])
}

#' 재시작 지점 필수 — 레지스트리가 없으면 stop.
#' 가드 부재를 "이상 없음" 으로 읽지 않으려는 호출부가 쓴다.
liq_basis_require <- function(path = LIQ_BASIS_REGISTRY()) {
  if (!file.exists(path))
    stop("[liquidity_basis] 기준 단절 레지스트리 부재: ", path,
         " — basis_break_scan.R 로 생성할 것. 부재를 '단절 없음' 으로 읽지 말 것")
  liq_basis_reset_points(path)
}

#' 종목별 **기준 구간(segment)** 번호 — 재시작 지점마다 1 씩 오른다.
#'
#' @param DT data.table(Ticker, Date) — 정렬 무관(내부에서 종목·날짜 순 가정)
#' @param reset data.table(Ticker, Date)
#' @return integer vector, nrow(DT) 길이
liq_basis_segment <- function(DT, reset) {
  stopifnot(is.data.table(DT), all(c("Ticker", "Date") %in% names(DT)))
  seg <- rep(0L, nrow(DT))
  if (is.null(reset) || !nrow(reset)) return(seg)
  key <- paste0(DT$Ticker, "|", as.character(DT$Date))
  rk  <- paste0(reset$Ticker, "|", as.character(reset$Date))
  is_reset <- key %chin% rk
  # 종목 안에서 누적 — DT 는 (Ticker, Date) 오름차순이어야 한다
  seg <- ave_cumsum_by(is_reset, DT$Ticker)
  as.integer(seg)
}

# data.table 없이도 도는 소형 헬퍼 (검사에서 격리 호출된다)
ave_cumsum_by <- function(x, g) {
  o <- integer(length(x)); run <- 0L; prev <- NA_character_
  for (i in seq_along(x)) {
    if (is.na(prev) || !identical(g[i], prev)) { run <- 0L; prev <- g[i] }
    if (isTRUE(x[i])) run <- run + 1L
    o[i] <- run
  }
  o
}

#' 유동성 창이 기준 단절을 가로지르는가 — 진단용(값을 바꾸지 않는다).
#'
#' @return data.table(Ticker, Date, straddles) — straddles=TRUE 면 그 날짜의 20일 창이
#'   재시작 지점을 품는다(구판 계산이었다면 두 기준을 섞었을 자리)
liq_basis_straddles <- function(DT, reset, win = 20L) {
  stopifnot(is.data.table(DT))
  out <- data.table(Ticker = DT$Ticker, Date = as.Date(DT$Date), straddles = FALSE)
  if (is.null(reset) || !nrow(reset)) return(out)
  sess <- sort(unique(out$Date))
  out[, .si := match(Date, sess)]
  r <- copy(as.data.table(reset)); r[, .si := match(as.Date(Date), sess)]
  r <- r[!is.na(.si)]
  if (!nrow(r)) { out[, .si := NULL]; return(out) }
  setkey(r, Ticker)
  for (i in seq_len(nrow(r))) {
    s <- r$.si[i]; tk <- r$Ticker[i]
    # 창 [e-win+1, e] 가 단절 앞뒤를 모두 품는 e 의 범위: s <= e <= s+win-2
    out[Ticker == tk & .si >= s & .si <= s + win - 2L, straddles := TRUE]
  }
  out[, .si := NULL]
  out[]
}

cat("[liquidity_basis] Loaded. liq_basis_reset_points() / liq_basis_segment() / liq_basis_straddles()\n")
