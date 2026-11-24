##=============================================================================
## style_brief_lib.R — 스타일 국면 브리핑 표시층 (FF5 + 스마트베타) · 2026-09-24 도훈 지시
##   "스타일 국면 브리핑 26년 8월 기준으로 고정된 부분 수정해줘"
##
## 결함: 브리핑의 제목·'최근 12개월 평균'·국면 판독·부활 워치·차트가 월간 파일의 마지막
##   **완결월**(ym 2026-08)에 묶여 9월 한 달 내내 같은 값이 발송됐다. 진행월 MTD 는 별도 절로만 붙었다.
## 수리: 12개월 창 = **완결 11개월 + 진행월 MTD** — 월평균 환산 = (11개월 합 + MTD) / 12.
##   FF5 5팩터 · 스마트베타 7스타일이 이 파일의 sw_window12() **하나**를 쓴다(브리핑·차트 공용).
##   진행월 MTD 가 없거나 낡았거나(as_of 가 완결월 말 이전·같음) 불연속이면 완결 12개월로 폴백하고
##   라벨·제목에 그 사유를 적는다(침묵 폴백 금지).
## ★표시층 전용 — 월간 파일(ff5_kr_monthly / smartbeta_kr_monthly)은 **완결월만** 발행하는 트래커
##   규약 불변(ff5_kr_tracker.R §1 · smartbeta_kr_tracker.R §3 '부분월 발행 오염' 가드). 진행월은 여기서만 합친다.
## ★PIT: 진행월 MTD = 트래커가 as_of(직전 영업일)까지의 확정 종가로 만든 값(신호 = 직전 월말).
##   as_of 가 오늘 이후(미래)이거나, 오늘이면서 KST 16시 전(장중 미확정 봉)이면 버린다.
## 라벨: diagnostic_monitoring — 시장 리뷰 전용(전략/자본 인용 금지).
## 검사: 08_Tests/ops/test_style_brief_mtd_window.R (양성 대조 + 위반 주입).
## v4 (2026-11-24 도훈 "스타일 국면 브리핑 국면판독 부분 개선"): 정본 요인(build_kr_factor_returns.R) 기반 국면 판독 —
##   아래 '정본 요인 국면 판독' 절. 정본이 없거나 판정 불가면 구 경로(v3) 그대로 + 사유 표기. 검토 =
##   04_Research/01_reports/style_regime_brief_review_20261124/README.md
##=============================================================================

.SW_FF5 <- c("MKT", "SMB", "HML", "RMW", "CMA")
.SW_SB  <- c("VAL", "QUAL", "MOM", "LOWVOL", "SIZE", "DIV", "EREV")
.SW_SB_KO <- c(VAL = "가치포워드", QUAL = "퀄리티", MOM = "모멘텀", LOWVOL = "저변동성",
               SIZE = "소형주", DIV = "고배당", EREV = "이익전망수정")
.SW_SB_BETA_KO <- c(VAL = "가치", QUAL = "퀄리티", MOM = "모멘텀", LOWVOL = "저변동성",
                    SIZE = "소형주", DIV = "고배당", EREV = "이익전망수정")
.SW_IDX_KO <- c(KOSPI200 = "코스피200", KOSDAQ150 = "코스닥150", KOSPI = "코스피", KOSDAQ = "코스닥")
.SW_TITLE_HEAD <- "스타일 국면 브리핑 — FF5 + 스마트베타"
.SW_CONFIRM_HOUR_KST <- 16L      # 장 마감(15:30) 후 확정 — 그 전의 '오늘' as_of 는 장중 봉
.SW_REASON_KO <- c(absent = "진행월 MTD 없음", stale = "진행월 MTD 낡음", gap = "진행월 MTD 불연속(완결월 결손)",
                   inconsistent = "진행월 MTD 라벨 불일치", future = "진행월 MTD 미래 날짜",
                   intraday = "진행월 MTD 장중 미확정", short = "완결월 표본 부족")

## 월 수익률 % 표기 — 도훈 지시 07-18 규약 그대로(브리핑 fmt 원형)
sw_fmt <- function(v) if (length(v) == 0L || is.na(v)) "NA" else sprintf("%+.2f%%", v * 100)

sw_next_ym <- function(ym) format(seq(as.Date(paste0(ym, "-01")), by = "1 month", length.out = 2L)[2L], "%Y-%m")

sw_read_json <- function(path) {
  if (!file.exists(path)) return(NULL)
  tryCatch(jsonlite::fromJSON(path), error = function(e) NULL)
}

## 진행월 MTD 판정 — ok=TRUE 일 때만 창에 합친다. reason ∈ names(.SW_REASON_KO) ∪ "ok"
sw_mtd_state <- function(mtd, last_ym, now = Sys.time(), tz = "Asia/Seoul",
                         confirm_hour = .SW_CONFIRM_HOUR_KST) {
  mk <- function(ok, reason, a = as.Date(NA), nd = NA_integer_)
    list(ok = ok, reason = reason, as_of = a, n_days = nd, last_ym = last_ym,
         mtd_ym = if (is.na(a)) NA_character_ else format(a, "%Y-%m"))
  ## [[ ]] = 정확 일치(리스트 $ 는 부분 일치 — 키 접두만 같은 항목을 집을 수 있다)
  if (is.null(mtd) || !is.list(mtd) || is.null(mtd[["as_of"]]) || length(mtd[["as_of"]]) != 1L) return(mk(FALSE, "absent"))
  a <- suppressWarnings(tryCatch(as.Date(as.character(mtd[["as_of"]])), error = function(e) as.Date(NA)))
  if (is.na(a)) return(mk(FALSE, "absent"))
  nd <- if (is.null(mtd[["n_days"]]) || length(mtd[["n_days"]]) != 1L) NA_integer_ else suppressWarnings(as.integer(mtd[["n_days"]]))
  mym <- format(a, "%Y-%m")
  if (!is.null(mtd[["ym"]]) && length(mtd[["ym"]]) == 1L && !identical(as.character(mtd[["ym"]]), mym))
    return(mk(FALSE, "inconsistent", a, nd))
  if (is.na(last_ym)) return(mk(FALSE, "short", a, nd))
  if (mym <= last_ym) return(mk(FALSE, "stale", a, nd))                 # as_of 가 완결월 말 이전(·같음)
  if (!identical(mym, sw_next_ym(last_ym))) return(mk(FALSE, "gap", a, nd))   # 사이에 빈 완결월
  today <- as.Date(format(now, "%Y-%m-%d", tz = tz))
  if (a > today) return(mk(FALSE, "future", a, nd))
  if (a == today && as.integer(format(now, "%H", tz = tz)) < confirm_hour) return(mk(FALSE, "intraday", a, nd))
  mk(TRUE, "ok", a, nd)
}

sw_reason_ko <- function(st) {
  r <- unname(.SW_REASON_KO[st$reason])
  if (is.na(r)) r <- st$reason
  if (st$reason %in% c("stale", "future", "intraday", "gap") && !is.na(st$as_of)) r <- sprintf("%s(as_of %s)", r, format(st$as_of))
  r
}

## ★12개월 창 (FF5·스마트베타 공용 · 브리핑·차트 공용) — 완결 (n-1)개월 + 진행월 MTD, 월평균 = 합 / n.
##   MTD 판정 불가 → 완결 n개월(폴백 사유는 label/short/state$reason).
##   결측: 열별로 관측된 값만 평균(분모 = 관측 수) — 결측이 없으면 정확히 (11개월 합 + MTD) / 12.
sw_window12 <- function(monthly, cols, mtd, now = Sys.time(), n = 12L) {
  m <- as.data.frame(monthly)
  if (!"ym" %in% names(m)) stop("sw_window12: monthly 에 ym 열이 없다")
  cols <- intersect(cols, names(m))
  m <- m[order(m$ym), c("ym", cols), drop = FALSE]
  last_ym <- if (nrow(m)) max(m$ym) else NA_character_
  st <- sw_mtd_state(mtd, last_ym, now)
  if (isTRUE(st$ok) && nrow(m) < n - 1L) { st$ok <- FALSE; st$reason <- "short" }   # 완결 11개월도 없으면 창 불성립
  use_mtd <- isTRUE(st$ok)
  base <- utils::tail(m, if (use_mtd) n - 1L else n)
  mv <- NULL
  if (use_mtd) mv <- vapply(cols, function(cc) { x <- mtd[[cc]]
    if (is.null(x) || length(x) != 1L || is.na(x)) NA_real_ else as.numeric(x) }, numeric(1))
  vals <- vapply(cols, function(cc) {
    v <- c(base[[cc]], if (use_mtd) mv[[cc]])
    if (all(is.na(v))) NA_real_ else sum(v, na.rm = TRUE) / sum(!is.na(v))
  }, numeric(1))
  need <- if (use_mtd) n - 1L else n
  if (nrow(base) < need) vals[] <- NA_real_
  mmdd <- if (use_mtd) format(st$as_of, "%m-%d") else NA_character_
  label <- if (use_mtd) {
    if (is.na(st$n_days)) sprintf("최근 12개월(진행월 MTD 포함, ~%s)", mmdd)
    else sprintf("최근 12개월(진행월 MTD %d거래일 포함, ~%s)", st$n_days, mmdd)
  } else if (nrow(base)) {
    sprintf("최근 12개월(완결 %s~%s · %s)", base$ym[1L], base$ym[nrow(base)], sw_reason_ko(st))
  } else sprintf("최근 12개월(%s)", sw_reason_ko(st))
  list(values = vals, mode = if (use_mtd) "mtd" else "complete", state = st, last_ym = last_ym,
       months = c(base$ym, if (use_mtd) sprintf("%s(MTD)", st$mtd_ym)), n = n,
       mtd_values = mv, label = label,
       short = if (use_mtd) "12개월+MTD" else "12개월(완결)",   # 국면 판독 줄 표기(한 줄 ≤80자 규율)
       mmdd = mmdd)
}

## 제목 — 기준일 = MTD as_of(직전 영업일) · 폴백이면 완결월 기준 + 사유
sw_brief_title <- function(w) {
  if (identical(w$mode, "mtd"))
    sprintf("%s (%s 기준 · 완결월 %s)", .SW_TITLE_HEAD, format(w$state$as_of), w$last_ym)
  else sprintf("%s (완결월 %s 기준 · %s)", .SW_TITLE_HEAD, w$last_ym, sw_reason_ko(w$state))
}

##-----------------------------------------------------------------------------
## 정본 요인 국면 판독 (v4 · 2026-11-24)
##   재료 = 한국 FF 요인 정본(02_Infrastructure/data/build_kr_factor_returns.R · 밤 갱신 [5c] · 현 측정 축) 일간 + 월간.
##   구 트래커 FF5(ff5_kr_tracker.R)는 정본이 있으면 쓰지 않는다 — 검토에서 확인한 결함:
##     ① CMA 부호 반전: 팩터 DB 가 Q06 을 −(자산증가율)로 저장(compute_fundamental.R:163)하는데 트래커가 다시 뒤집는다
##        (정본 대비 12개월 평균 상관 −0.75 · 부호 일치 17%) ② 월 수익 = 월말 종가 비율 — 가격 이음매를 수익으로 먹는다
##        (2026-03 소형 절반 +36% 가짜 · SMB +43.6% · Ret 연쇄로는 소형 −4.7%).
##   판독 규칙:
##     창 = 완결 (n−1)개월(정본 월간) + 진행월 MTD(정본 일간 복리) — 구판과 같은 창(n = 12 · 반전 점검 n = 3).
##     t = 창 수익 합 / (직전 252거래일 일간 표준편차 × √창 거래일 수) — 1년 일간 변동성으로 표준화한 창 수익.
##     |t| ≥ t_sig 일 때만 '우세'로 단정. t_sig = 등록부 tier_graduation::grade_b_min_portfolio_alpha_t(호출자가 넘긴다 ·
##       PORT_t B 진입 · 팩터 알파 노치와 같은 수). 미만이면 t 만 싣고 단정하지 않는다.
##     3개월 t 가 12개월과 반대 부호이며 |t| ≥ t_sig 면 '반전'.
##     스타일 위험 배율 = Barra USE4 변동성 국면 조정(VRA)의 단면 편의 통계(Menchero · Orr · Wang 2011, USE4 Methodology
##       Notes) — z = 요인 일간 수익 / 전날까지 252거래일 표준편차, B_t = √(5요인 평균 z²), 배율 = √(최근 21거래일 B_t² 평균).
##       1 = 1년 변동성 수준(모형의 영가설 값 · 조정 문턱 아님) · 1 보다 크면 변동성 상승 국면.
##     252거래일 = 1년 · 21거래일 = 1개월(달력 관례 · 조정한 수 아님).
##   PIT: 모든 값은 as_of(정본 일간 마지막 확정일 — 16시 확정 규칙은 sw_mtd_state 와 같다)까지의 값만 쓴다.
##-----------------------------------------------------------------------------
.SW_KF <- c("SMB", "HML", "RMW", "CMA", "WML")
.SW_KF_ALL <- c("MKT", .SW_KF)
.SW_KF_SD_DAYS <- 252L     # 1년(거래일)
.SW_KF_MONTH_DAYS <- 21L   # 1개월(거래일)
.SW_KF_NAME <- c(SMB = "소형", HML = "가치", RMW = "수익성", CMA = "보수투자", WML = "모멘텀")
.SW_KF_SIDE <- list(SMB = c("소형", "대형"), HML = c("가치", "성장"), RMW = c("고수익성", "저수익성"),
                    CMA = c("보수투자", "공격투자"), WML = c("모멘텀", "역모멘텀"))
.SW_KF_KV <- c(MKT = "시장초과 MKT", SMB = "소형-대형 SMB", HML = "가치-성장 HML", RMW = "수익성 RMW",
               CMA = "투자보수 CMA", WML = "모멘텀 WML")

sw_kf_asof <- function(dates, now = Sys.time(), tz = "Asia/Seoul", confirm_hour = .SW_CONFIRM_HOUR_KST) {
  today <- as.Date(format(now, "%Y-%m-%d", tz = tz))
  hr <- as.integer(format(now, "%H", tz = tz))
  ok <- !is.na(dates) & (dates < today | (dates == today & hr >= confirm_hour))
  if (!any(ok)) as.Date(NA) else max(dates[ok])
}

## kf = list(daily = (Date, MKT_TOTAL, MKT, SMB, HML, RMW, CMA, WML), monthly = (ym 'YYYY-MM', MKT … WML),
##           meta = list(cfg_version, md5, built_at) · 선택, ref_as_of = 가격 원장 as_of(신선도 대조) · 선택)
##   반환 ok = FALSE 면 reason(한국어) — 조립은 구 경로로 가고 사유를 싣는다(침묵 폴백 금지).
sw_kf_prepare <- function(kf, now = Sys.time()) {
  bad <- function(r) list(ok = FALSE, reason = r)
  if (is.null(kf) || !is.list(kf) || is.null(kf$daily) || is.null(kf$monthly)) return(bad("정본 요인 없음"))
  d <- as.data.frame(kf$daily); m <- as.data.frame(kf$monthly)
  if (!all(c("Date", "MKT_TOTAL", .SW_KF_ALL) %in% names(d)) || !all(c("ym", .SW_KF_ALL) %in% names(m)))
    return(bad("정본 요인 열 부족"))
  d$Date <- as.Date(d$Date); d <- d[order(d$Date), , drop = FALSE]
  a <- sw_kf_asof(d$Date, now)
  if (is.na(a)) return(bad("정본 요인 확정일 없음"))
  d <- d[d$Date <= a, , drop = FALSE]
  d <- d[stats::complete.cases(d[, c("MKT_TOTAL", .SW_KF_ALL)]), , drop = FALSE]
  if (nrow(d) < .SW_KF_SD_DAYS + .SW_KF_MONTH_DAYS + 1L) return(bad("정본 일간 표본 부족"))
  if (max(d$Date) != a) return(bad(sprintf("정본 일간 %s 결측", format(a))))
  mtd_ym <- format(a, "%Y-%m")
  m$ym <- as.character(m$ym); m <- m[order(m$ym), , drop = FALSE]
  comp <- m[m$ym <= mtd_ym & stats::complete.cases(m[, .SW_KF_ALL]), , drop = FALSE]
  if (!nrow(comp)) return(bad("정본 월간 없음"))
  last_ym <- max(comp$ym)
  mode <- if (identical(last_ym, mtd_ym)) "complete" else if (identical(sw_next_ym(last_ym), mtd_ym)) "mtd" else NA_character_
  if (is.na(mode)) return(bad(sprintf("정본 월간 결손(완결 %s · 일간 %s)", last_ym, format(a))))
  dym <- format(d$Date, "%Y-%m")
  dm <- d[dym == mtd_ym, , drop = FALSE]
  mtd <- if (identical(mode, "mtd")) vapply(.SW_KF_ALL, function(k) prod(1 + dm[[k]]) - 1, numeric(1)) else NULL
  sdv <- vapply(.SW_KF_ALL, function(k) stats::sd(utils::tail(d[[k]], .SW_KF_SD_DAYS)), numeric(1))
  win <- function(n) {
    k_comp <- if (identical(mode, "mtd")) n - 1L else n
    if (nrow(comp) < k_comp) return(NULL)
    mons <- utils::tail(comp$ym, k_comp)
    sums <- vapply(.SW_KF_ALL, function(k) sum(comp[comp$ym %in% mons, k]) + (if (is.null(mtd)) 0 else mtd[[k]]), numeric(1))
    nd <- sum(dym %in% c(mons, if (identical(mode, "mtd")) mtd_ym))
    list(n = n, months = mons, sum = sums, mean = sums / n, ndays = nd, t = sums / (sdv * sqrt(nd)))
  }
  ## 시장: 총수익 누적의 1년 고점 대비
  cum <- cumprod(1 + d$MKT_TOTAL)
  dd <- utils::tail(cum, 1L) / max(utils::tail(cum, .SW_KF_SD_DAYS)) - 1
  ## 스타일 위험 배율(Barra VRA 단면 편의 통계) — 최근 21거래일 각 날 z = 수익 / 전날까지 252일 표준편차
  n <- nrow(d); idx <- (n - .SW_KF_MONTH_DAYS + 1L):n
  z2 <- vapply(.SW_KF, function(k) vapply(idx, function(i)
    (d[[k]][i] / stats::sd(d[[k]][(i - .SW_KF_SD_DAYS):(i - 1L)]))^2, numeric(1)), numeric(length(idx)))
  vra <- sqrt(mean(rowMeans(matrix(z2, nrow = length(idx)))))
  vra_by <- colMeans(matrix(z2, nrow = length(idx), dimnames = list(NULL, .SW_KF)))
  ## 스타일 동조화(흡수 비율 · v4.1) — 5요인 일간 공분산의 제1 고유값 비중. 높을수록 스타일들이 한 덩어리(한 베팅)로 움직인다.
  ar <- sw_kf_absorption(d)
  ref <- if (is.null(kf$ref_as_of)) as.Date(NA) else suppressWarnings(as.Date(as.character(kf$ref_as_of)))
  list(ok = TRUE, reason = "ok", as_of = a, mode = mode, mtd_ym = mtd_ym, last_ym = last_ym,
       n_mtd = if (identical(mode, "mtd")) nrow(dm) else NA_integer_, mtd = mtd,
       last_month = unlist(comp[nrow(comp), .SW_KF_ALL]), w12 = win(12L), w3 = win(3L), sd_daily = sdv,
       dd = dd, vra = vra, vra_by = vra_by, ar = ar, meta = kf$meta, catchup = kf$catchup,
       stale_vs_ref = !is.na(ref) && ref > a, ref_as_of = ref)
}

## 스타일 동조화 = 흡수 비율(Kritzman · Li · Page · Rigobon 2011 JPM 37(4) https://doi.org/10.3905/jpm.2011.37.4.112):
##   공분산 고유값 중 제1 성분의 비중(요인 5개 → 상위 1개 = 1/5). 창 = 원 논문의 500거래일 · 최근 = 3개월(63거래일 · 달력 관례).
##   백분위 = 그 날까지의 자기 역사(500일 창 값을 5거래일 간격으로 · as-of)에서 지금 값의 위치 — 전기간 통계가 아니다(C1).
##   뜻: 높을수록 여러 스타일이 한 덩어리로 움직인다 = 브리핑의 여러 스타일 줄이 사실상 같은 베팅(Ghayur · Heaney · Platt 2018 FAJ
##   https://doi.org/10.2469/faj.v74.n3.5 의 '목표 요인 간 상관으로 생기는 쏠림').
.SW_KF_AR_DAYS <- 500L
sw_kf_absorption <- function(d, cols = .SW_KF, win = .SW_KF_AR_DAYS, recent = 3L * .SW_KF_MONTH_DAYS, step = 5L) {
  X <- as.matrix(d[, cols]); n <- nrow(X)
  ar1 <- function(rows) { ev <- eigen(stats::cov(X[rows, , drop = FALSE]), symmetric = TRUE, only.values = TRUE)$values; ev[1L] / sum(ev) }
  if (n < win) return(list(ok = FALSE))
  ends <- unique(c(seq(win, n, by = step), n))
  hist <- vapply(ends, function(e) ar1((e - win + 1L):e), numeric(1))
  cur <- hist[length(hist)]
  list(ok = TRUE, ar = cur, ar_recent = ar1((n - recent + 1L):n), pct = mean(hist <= cur), n_hist = length(hist),
       since = format(as.Date(d$Date[win]), "%Y"))
}

## 80자 bullet 규율(tg_agent_brief BULLET_ITEM_MAX) — 항목을 ' · ' 로 이어 붙이다 넘치면 다음 줄로
sw_pack <- function(head, items, max_chars = 80L, cont = "  ") {
  out <- character(0); cur <- head
  for (it in items) {
    cand <- if (identical(cur, head) || identical(cur, cont)) paste0(cur, it) else paste(cur, it, sep = " · ")
    if (nchar(cand) > max_chars && !identical(cur, head) && !identical(cur, cont)) { out <- c(out, cur); cur <- paste0(cont, it) }
    else cur <- cand
  }
  c(out, cur)
}

## 점프 모형 국면 줄(v4.1 · 정본 일간 · style_jump_model.R::sw_jump_regime) — 호출자가 그 파일을 source 했고 λ 파일이 있을 때만.
##   jp = style_jump_params.json(요인별 λ · 선택일 · 다음 선택일) · 상태는 K$as_of 까지의 자료로만(PIT).
sw_kf_jump_lines <- function(kf, K, jp, today = Sys.Date()) {
  if (is.null(jp) || is.null(jp$factors)) return(character(0))
  if (!exists("sw_jump_regime", mode = "function")) return("점프 모형 국면: 생략(style_jump_model.R 미적재)")
  d <- as.data.frame(kf$daily); d$Date <- as.Date(d$Date); d <- d[d$Date <= K$as_of, , drop = FALSE]
  d <- d[order(d$Date), , drop = FALSE]
  its <- character(0); stale <- FALSE
  for (k in .SW_KF) {
    p <- jp$factors[[k]]; if (is.null(p$lambda)) next
    if (!is.null(p$next_select) && as.Date(p$next_select) < today) stale <- TRUE
    z <- tryCatch(sw_jump_regime(d[[k]], d$MKT, d$Date, as.numeric(p$lambda), kappa = p$kappa,
                                 refit_months = if (is.null(jp$refit_months)) 1L else as.integer(jp$refit_months)),
                  error = function(e) list(ok = FALSE))
    its <- c(its, if (isTRUE(z$ok)) sprintf("%s %s %d일", .SW_KF_NAME[[k]], if (z$state == 1L) "강세" else "약세", z$days)
                  else sprintf("%s ?", .SW_KF_NAME[[k]]))
  }
  if (!length(its)) return(character(0))
  sw_pack(sprintf("점프 모형 국면(지속 일수%s): ", if (stale) " · λ 재선택 지남" else ""), its)
}

## 국면 판독 줄(정본) — K = sw_kf_prepare() 의 ok 산출 · t_sig = 등록부 문턱
sw_kf_lines <- function(K, t_sig) {
  ft <- function(x) if (!is.finite(x)) "NA" else sprintf("%+.1f", x)
  tag <- if (identical(K$mode, "mtd")) "12개월+MTD" else "12개월(완결)"
  t12 <- K$w12$t[.SW_KF]; t3 <- if (is.null(K$w3)) setNames(rep(NA_real_, length(.SW_KF)), .SW_KF) else K$w3$t[.SW_KF]
  side <- function(k, t) .SW_KF_SIDE[[k]][if (t >= 0) 1L else 2L]
  dec <- .SW_KF[is.finite(t12) & abs(t12) >= t_sig]
  l1 <- if (length(dec)) sw_pack(sprintf("국면(%s · |t|≥%.1f만 판정): ", tag, t_sig),
                                vapply(dec, function(k) sprintf("%s 우세 t%s", side(k, t12[[k]]), ft(t12[[k]])), ""))
        else sprintf("국면(%s · |t|≥%.1f만 판정): 뚜렷한 스타일 국면 없음", tag, t_sig)
  l2 <- sw_pack("12개월 t: ", sprintf("%s %s", .SW_KF_NAME[.SW_KF], vapply(t12, ft, "")))
  l3 <- sw_pack(sprintf("%s t: ", if (identical(K$mode, "mtd")) "3개월(2완결+MTD)" else "3개월"),
                sprintf("%s %s", .SW_KF_NAME[.SW_KF], vapply(t3, ft, "")))
  rv <- .SW_KF[is.finite(t3) & is.finite(t12) & abs(t3) >= t_sig & sign(t3) != sign(t12)]
  l3b <- if (length(rv)) sprintf("반전(3개월 |t|≥%.1f · 12개월과 반대): %s", t_sig,
                                 paste(vapply(rv, function(k) sprintf("%s 쪽 t%s", side(k, t3[[k]]), ft(t3[[k]])), ""), collapse = " · "))
         else character(0)
  l4 <- sprintf("시장: 1년 고점 대비 %+.1f%%%s", K$dd * 100,
                if (identical(K$mode, "mtd")) sprintf(" · 진행월 초과 %+.1f%%(%d거래일)", K$mtd[["MKT"]] * 100, K$n_mtd) else "")
  top_v <- names(K$vra_by)[which.max(K$vra_by)]
  l5 <- sprintf("스타일 위험 배율 %.1f배(최근 1개월 · 1년 변동성=1 · 최대 %s)", K$vra, .SW_KF_NAME[[top_v]])
  if (isTRUE(K$ar$ok))
    l5 <- c(l5, sprintf("스타일 동조화(제1 공통 성분) 500일 %.0f%%(%s~ 백분위 %.0f) · 최근 3개월 %.0f%%",
                        100 * K$ar$ar, K$ar$since, 100 * K$ar$pct, 100 * K$ar$ar_recent))
  fire <- is.finite(t12[["SMB"]]) && is.finite(t12[["HML"]]) && t12[["SMB"]] >= t_sig && t12[["HML"]] >= t_sig
  early <- !fire && is.finite(t3[["SMB"]]) && is.finite(t3[["HML"]]) && t3[["SMB"]] >= t_sig && t3[["HML"]] >= t_sig
  rw <- if (fire) sprintf("부활 워치: <b>발화</b> — 12개월 소형 t%s · 가치 t%s(매장 팩터 재검토)", ft(t12[["SMB"]]), ft(t12[["HML"]]))
        else if (early) sprintf("부활 워치: <b>조기 신호</b> — 3개월 소형 t%s · 가치 t%s(12개월 미달)", ft(t3[["SMB"]]), ft(t3[["HML"]]))
        else sprintf("부활 워치: 미발화 — 12개월 소형 t%s · 가치 t%s(둘 다 ≥%.1f 이면 발화)", ft(t12[["SMB"]]), ft(t12[["HML"]]), t_sig)
  list(regime = c(l1, l2, l3, l3b), market = c(l4, l5), revive = rw, fire = fire, early = early, decisive = dec, reversal = rv,
       regime_line = if (length(dec)) paste(vapply(dec, function(k) sprintf("%s 우세", side(k, t12[[k]])), ""), collapse = " / ")
                     else "뚜렷한 스타일 국면 없음")
}

## 브리핑 조립 — ff5_brief_send.R 가 이 함수의 산출을 그대로 발송(또는 드라이런)한다.
##   입력은 전부 인자(파일 I/O 0) — 검사가 운영 코드 그 자체를 합성 입력으로 돌린다.
##   kf · t_sig (v4): 정본 요인(sw_kf_prepare 입력)과 등록부 유의 문턱. 둘 다 있고 판정 가능하면 FF5 절 · 국면 판독 · 부활 워치를
##     정본으로 낸다. 없으면 구 경로(v3) 그대로 — kf 를 줬는데 판정 불가면 국면 판독 첫 줄에 사유를 싣는다.
sw_compose_brief <- function(FF, SB = NULL, mtd5 = NULL, sbm = NULL, ib = NULL, now = Sys.time(), kf = NULL, t_sig = NULL,
                             jp = NULL) {
  fmt <- sw_fmt
  pos <- function(x) length(x) == 1L && !is.na(x) && x > 0
  side <- function(x, neg, posl) if (length(x) != 1L || is.na(x)) "?" else if (x < 0) neg else posl
  FF <- as.data.frame(FF); FF <- FF[order(FF$ym), , drop = FALSE]
  L <- FF[nrow(FF), , drop = FALSE]
  wf <- sw_window12(FF, .SW_FF5, mtd5, now)
  r5 <- wf$values
  mtd_ok <- identical(wf$mode, "mtd")
  tag <- wf$short
  kv5 <- function(v) list("시장초과 MKT" = fmt(v[["MKT"]]), "소형-대형 SMB" = fmt(v[["SMB"]]),
                          "가치-성장 HML" = fmt(v[["HML"]]), "수익성 RMW" = fmt(v[["RMW"]]),
                          "투자보수 CMA" = fmt(v[["CMA"]]))
  lv <- vapply(.SW_FF5, function(cc) if (cc %in% names(L)) as.numeric(L[[cc]]) else NA_real_, numeric(1))

  regime_line <- sprintf("%s 주도 / %s 우위 / 퀄리티 %s (%s)", side(r5[["SMB"]], "대형", "소형"),
                         side(r5[["HML"]], "성장", "가치"),
                         if (is.na(r5[["RMW"]])) "?" else if (r5[["RMW"]] > 0) "강세" else "약세", wf$label)
  revive_fire <- pos(r5[["SMB"]]) && pos(r5[["HML"]])
  revive_watch <- if (revive_fire) sprintf("SMB·HML %s 동반 양전 — 소형/가치 반전 신호, 매장 팩터 un-bury 검토 발화", tag)
                  else sprintf("반전 신호 없음 (SMB·HML %s 동반 양전 시 발화)", tag)

  ## v4: 정본 요인 판정 — kf 와 유의 문턱이 모두 있고 판정 가능할 때만 정본 경로
  K <- if (is.null(kf)) NULL else if (is.null(t_sig) || length(t_sig) != 1L || !is.finite(t_sig))
         list(ok = FALSE, reason = "유의 문턱(등록부) 없음") else sw_kf_prepare(kf, now)
  use_kf <- !is.null(K) && isTRUE(K$ok) && !is.null(K$w12)
  if (!is.null(K) && isTRUE(K$ok) && is.null(K$w12)) K <- list(ok = FALSE, reason = "정본 월간 12개월 미만")

  if (use_kf) {
    kv6 <- function(v) setNames(as.list(vapply(.SW_KF_ALL, function(k) fmt(v[[k]]), character(1))), .SW_KF_KV[.SW_KF_ALL])
    klab <- if (identical(K$mode, "mtd")) sprintf("최근 12개월(진행월 MTD %d거래일 포함, ~%s)", K$n_mtd, format(K$as_of, "%m-%d"))
            else sprintf("최근 12개월(완결 %s~%s)", K$w12$months[1L], K$last_ym)
    sections <- list(
      list(heading = sprintf("FF5+모멘텀 최근 완결월 (%s · 정본 요인)", K$last_ym), type = "kv", kv = kv6(K$last_month)),
      list(heading = sprintf("FF5+모멘텀 %s 평균 · 정본 요인", klab), type = "kv", kv = kv6(K$w12$mean)))
    if (identical(K$mode, "mtd"))
      sections[[length(sections) + 1L]] <- list(
        heading = sprintf("진행월 MTD (직전영업일 %s, %d거래일 · 정본 요인)", format(K$as_of), K$n_mtd),
        type = "kv", kv = kv6(K$mtd))
    charts <- "outputs/ff5_kr/charts/kr_ff_regime_t.png"
  } else {
  sections <- list(
    list(heading = sprintf("FF5 최근 완결월 (%s)", L$ym), type = "kv", kv = kv5(lv)),
    list(heading = sprintf("FF5 %s 평균", wf$label), type = "kv", kv = kv5(r5)))
  ## 진행월 MTD (직전영업일까지 — 도훈 지시 07-18) — 판정 통과분만(낡은 MTD 를 '진행월'로 싣지 않는다)
  if (mtd_ok)
    sections[[length(sections) + 1L]] <- list(
      heading = sprintf("진행월 MTD (직전영업일 %s, %s거래일)", format(wf$state$as_of),
                        if (is.na(wf$state$n_days)) "?" else as.character(wf$state$n_days)),
      type = "kv", kv = kv5(wf$mtd_values))
  charts <- "outputs/ff5_kr/charts/ff5_rolling12.png"
  }

  ws <- NULL; wsc <- NULL; sb_line <- NULL; r12 <- NULL
  if (!is.null(SB) && nrow(SB) >= 11L) {
    SB <- as.data.frame(SB); SB <- SB[order(SB$ym), , drop = FALSE]
    sty <- intersect(.SW_SB, names(SB))
    ws <- sw_window12(SB, sty, sbm, now)
    wsc <- sw_window12(SB, sty, NULL, now)          # 완결 12개월 — MTD 부호반전 비교 기준(자기포함 회피)
    r12 <- ws$values
    if (length(r12) && any(!is.na(r12))) {
      kvl <- as.list(vapply(r12, fmt, character(1))); names(kvl) <- .SW_SB_KO[names(r12)]
      sections[[length(sections) + 1L]] <- list(heading = sprintf("스마트베타 %s 평균 초과수익", ws$label),
                                                type = "kv", kv = kvl)
      top <- names(r12)[which.max(r12)]; bot <- names(r12)[which.min(r12)]
      sb_line <- sprintf("스마트베타: %s 최강 / %s 최약 (%s 유니버스 대비)", .SW_SB_KO[top], .SW_SB_KO[bot], ws$label)
      ## v3 최근동향 차트 (도훈 지시): 정렬 막대 + 24개월 히트맵 (장기 소형패널은 rolling12 파일로 별도 보관)
      charts <- c(charts, "outputs/smartbeta_kr/charts/smartbeta_recent_bars.png",
                  "outputs/smartbeta_kr/charts/smartbeta_heatmap24.png")
    } else r12 <- NULL
  }
  ## 지수 팩터 민감도 (도훈 지시 07-18) — 창은 index_factor_beta.json 이 이미 '36개월+MTD' 로 동적
  ##   ★2026-11-13(도훈 "최신데이터로 계산 안하는 부분들 … 최신데이터 기반으로"): 진행월 점이 빠진 창은 라벨이
  ##   '36개월 ~<완결월> · 진행월 제외(<사유>)' 로 온다(index_factor_beta.R). 스마트베타 절도 자기 창(sb_window)을 제목에 싣고,
  ##   FF5 창은 진행월을 담았는데 지수 β 가 진행월을 못 담았으면 '지수 함의' 줄에 그 사실을 붙인다(옛 기준을 조용히 섞지 않는다).
  bn <- .SW_IDX_KO
  ib_win <- function(k) { w <- if (is.null(ib)) NULL else ib[[k]]; if (is.null(w) || length(w) != 1L || is.na(w)) NULL else as.character(w) }
  sb_win <- if (!is.null(ib_win("sb_window"))) ib_win("sb_window") else ib_win("window")
  ib_lag <- mtd_ok && !is.null(sb_win) && !grepl("+MTD", sb_win, fixed = TRUE)
  if (!is.null(ib) && !is.null(ib$betas)) {
    items_ff <- tryCatch(vapply(names(bn), function(ix) { b <- ib$betas[[ix]]
      v <- c(SMB = b$SMB, HML = b$HML, RMW = b$RMW, CMA = b$CMA)
      tk <- vapply(names(v), function(f) sprintf("%s %+.2f", f, v[f]), character(1))
      tk[which.max(v)] <- sprintf("<b>%s</b>", tk[which.max(v)])   # 양수 최대 볼드 (도훈 07-18)
      sprintf("%s: %s (MKT %.2f)", bn[ix], paste(tk, collapse = " · "), b$MKT) }, character(1)),
      error = function(e) NULL)
    if (!is.null(items_ff)) {
      sections[[length(sections) + 1L]] <- list(
        heading = sprintf("지수 팩터 민감도 (FF5%s·%s)", if (identical(ib$ff_source, "정본 요인")) " 정본" else "",
                          if (is.null(ib$window)) "36개월" else ib$window),
        type = "bullet", items = unname(items_ff))
      charts <- c(charts, "outputs/ff5_kr/charts/index_factor_beta.png")
    }
    if (!is.null(ib$sb_betas)) {
      krs <- .SW_SB_BETA_KO
      items_sb <- tryCatch(vapply(names(bn), function(ix) { v <- unlist(ib$sb_betas[[ix]])
        ip <- which.max(v); im <- which.min(v)                 # 양수 최대(볼드) + 음수 최대 병기
        sprintf("%s: <b>%s %+.2f</b> · %s %+.2f", bn[ix],
                krs[names(v)[ip]], v[ip], krs[names(v)[im]], v[im]) }, character(1)),
        error = function(e) NULL)
      if (!is.null(items_sb)) {
        sections[[length(sections) + 1L]] <- list(
          heading = sprintf("지수 스마트베타 민감도 (%s · 시장 통제 · 양수 최대·음수 최대)", if (is.null(sb_win)) "36개월" else sb_win),
          type = "bullet", items = unname(items_sb))
        charts <- c(charts, "outputs/ff5_kr/charts/index_smartbeta_beta.png")
      }
    }
  }
  ## 국면 판독 — v4(정본 요인 · 유의 문턱) 또는 v3(구 트래커 · 부호만)
  ##   v3: 12개월 창 = 완결 11개월 + 진행월 MTD (폴백 시 완결 12개월 · 표기 = tag)
  KL <- if (use_kf) sw_kf_lines(K, t_sig) else NULL
  JL <- if (use_kf) tryCatch(sw_kf_jump_lines(kf, K, jp, today = as.Date(format(now, "%Y-%m-%d", tz = "Asia/Seoul"))),
                             error = function(e) "점프 모형 국면: 계산 오류") else character(0)
  jd <- if (use_kf) c(KL$regime, JL, KL$market) else
    c(if (!is.null(K)) sprintf("정본 요인 미사용(%s) — 아래 FF5 는 구 트래커 값", K$reason),
      sprintf("FF5 %s: %s 주도(SMB %s)·%s 우위(HML %s)·퀄리티 %s(RMW %s)", tag,
              side(r5[["SMB"]], "대형", "소형"), fmt(r5[["SMB"]]),
              side(r5[["HML"]], "성장", "가치"), fmt(r5[["HML"]]),
              if (pos(r5[["RMW"]])) "강세" else "약세", fmt(r5[["RMW"]])))
  sig_ok <- !is.null(t_sig) && length(t_sig) == 1L && is.finite(t_sig)
  if (!is.null(r12)) {
    top12 <- names(r12)[which.max(r12)]; bot12 <- names(r12)[which.min(r12)]
    jd <- c(jd, sprintf("%s %s: 최강 %s %s · 최약 %s %s", if (use_kf) "스마트베타" else "스타일", ws$short,
                        .SW_SB_KO[top12], fmt(r12[[top12]]), .SW_SB_KO[bot12], fmt(r12[[bot12]])))
    if (identical(ws$mode, "mtd")) {
      mv <- ws$mtd_values; rc <- wsc$values[names(mv)]
      if (any(!is.na(mv))) {
        topm <- names(mv)[which.max(mv)]
        if (sig_ok) {
          ## v4: 반대 부호 진행월을 위험 단위로 — z = MTD / (완결 12개월 월 표준편차 × √(진행 거래일/21)) · |z| ≥ t_sig
          sdm <- vapply(names(mv), function(s) stats::sd(utils::tail(SB[[s]], 12L), na.rm = TRUE), numeric(1))
          nd <- if (is.na(ws$state$n_days)) .SW_KF_MONTH_DAYS else ws$state$n_days
          zz <- mv / (sdm * sqrt(nd / .SW_KF_MONTH_DAYS))
          flip <- names(mv)[!is.na(mv) & !is.na(rc) & is.finite(zz) & sign(mv) != sign(rc) & abs(zz) >= t_sig]
        } else flip <- names(mv)[!is.na(mv) & !is.na(rc) & sign(mv) != sign(rc) & abs(mv) > 0.02]
        fl_txt <- if (!length(flip)) "없음" else paste(head(.SW_SB_KO[flip], 3), collapse = "·")
        if (length(flip) > 3) fl_txt <- sprintf("%s 외%d", fl_txt, length(flip) - 3)
        jd <- c(jd, if (sig_ok) sprintf("진행월 MTD(~%s): 최강 %s %s · 12개월과 반대(|z|≥%.1f) %d개(%s)",
                                        ws$mmdd, .SW_SB_KO[topm], fmt(mv[[topm]]), t_sig, length(flip), fl_txt)
                    else sprintf("진행월 MTD(~%s): 최강 %s %s · 완결 12개월 대비 부호반전 %d개(%s)",
                                 ws$mmdd, .SW_SB_KO[topm], fmt(mv[[topm]]), length(flip), fl_txt))
      }
    }
    if (!is.null(ib) && !is.null(ib$sb_betas)) {
      bt <- tryCatch(vapply(names(bn), function(ix) as.numeric(unlist(ib$sb_betas[[ix]])[top12]), numeric(1)),
                     error = function(e) NULL)
      if (!is.null(bt) && any(!is.na(bt)))
        jd <- c(jd, if (use_kf)
          ## v4: 노출만 적는다 — 12개월 부호의 다음 달 적중은 기저율 수준(검토 진단 [3]) → '지속 시 · 반전 시' 예측 문구 삭제
          sprintf("%s 노출 지수 β%s: %s %+.1f · %s %+.1f", .SW_SB_KO[top12], if (ib_lag) "(진행월 제외)" else "",
                  bn[names(bn)[which.max(bt)]], max(bt, na.rm = TRUE), bn[names(bn)[which.min(bt)]], min(bt, na.rm = TRUE))
          else sprintf("지수 함의%s: %s 국면 지속 시 %s 우위(β%+.1f)·%s 역풍(β%+.1f) — 반전 시 역전",
                       if (ib_lag) "(β 진행월 제외)" else "",
                       .SW_SB_KO[top12], bn[names(bn)[which.max(bt)]], max(bt, na.rm = TRUE),
                       bn[names(bn)[which.min(bt)]], min(bt, na.rm = TRUE)))
    }
  }
  if (use_kf) {
    jd <- c(jd, KL$revive)
    regime_line <- sprintf("%s (%s · 정본 요인 · |t|≥%.1f)", KL$regime_line,
                           if (identical(K$mode, "mtd")) sprintf("12개월+MTD ~%s", format(K$as_of, "%m-%d")) else "12개월(완결)", t_sig)
    revive_watch <- gsub("</?b>", "", sub("^부활 워치: ", "", KL$revive))
  } else {
    early <- mtd_ok && pos(wf$mtd_values[["SMB"]]) && pos(wf$mtd_values[["HML"]])
    jd <- c(jd, if (revive_fire) sprintf("부활 워치: <b>발화</b> — SMB·HML %s 동반 양전(매장 팩터 un-bury 검토)", tag)
      else if (early) "부활 워치: <b>MTD 조기신호 점등</b> — 진행월 SMB·HML 양전(완결 시 발화 후보)"
      else sprintf("부활 워치: 반전 신호 없음(SMB·HML %s 동반 양전 시 발화)", tag))
  }
  sections[[length(sections) + 1L]] <- list(heading = "국면 판독", type = "bullet", items = jd)

  title <- if (!use_kf) sw_brief_title(wf) else if (identical(K$mode, "mtd"))
    sprintf("%s (%s 기준 · 완결월 %s)", .SW_TITLE_HEAD, format(K$as_of), K$last_ym)
    else sprintf("%s (완결월 %s 기준)", .SW_TITLE_HEAD, K$last_ym)
  ## v4.1 따라잡기(ff5_brief_send.R::kf_catchup) — 낡음이면 못 따라잡은 사유를, 따라잡았으면 꼬리말에 그 사실을 싣는다
  cu <- if (use_kf) K$catchup else NULL
  cu_why <- c(held = "갱신 진행 중", mem_wait = "메모리 대기", failed = "따라잡기 실패", skipped = "드라이런",
              unknown = "원장 판독 불가", error = "따라잡기 오류")
  if (use_kf && isTRUE(K$stale_vs_ref))
    title <- sprintf("%s · 정본 요인 낡음(원장 %s%s)", title, format(K$ref_as_of),
                     if (!is.null(cu$state) && cu$state %in% names(cu_why)) paste0(" · ", cu_why[[cu$state]]) else "")
  kf_tag <- if (use_kf) {
    md <- if (is.null(K$meta$md5)) "" else sprintf(" md5 %s", substr(as.character(K$meta$md5), 1L, 8L))
    sprintf(" · 정본 요인 %s%s%s", if (is.null(K$meta$cfg_version)) "" else as.character(K$meta$cfg_version), md,
            if (identical(cu$state, "ran")) " · 아침 따라잡기" else "")
  } else ""
  list(title = title, sections = sections, charts = charts,
       footer = sprintf("diagnostic_monitoring · 시장 리뷰 전용(전략/자본 인용 금지) · %s%s",
                        if (use_kf) "kr_factor_returns + smartbeta_kr" else "ff5_kr + smartbeta_kr", kf_tag),
       regime_line = regime_line, revive_watch = revive_watch, sb_line = sb_line,
       w_ff = wf, w_sb = ws, w_sb_complete = wsc, kf = K, kf_used = use_kf)
}

## 드라이런 본문 — 제목·절·차트 목록(발송 없음). charts_root = 존재 확인 기준 디렉터리
sw_dryrun_lines <- function(out, charts_root = ".") {
  ln <- c(sprintf("TITLE: %s", out$title), "")
  for (i in seq_along(out$sections)) {
    s <- out$sections[[i]]
    ln <- c(ln, sprintf("[절 %d · %s] %s", i, s$type, s$heading))
    if (identical(s$type, "kv")) ln <- c(ln, sprintf("  %s: %s", names(s$kv), unlist(s$kv)))
    else if (identical(s$type, "bullet")) ln <- c(ln, sprintf("  - %s", s$items))
    else ln <- c(ln, sprintf("  %s", paste(unlist(s$body), collapse = " ")))
    ln <- c(ln, "")
  }
  ex <- file.exists(file.path(charts_root, out$charts))
  mt <- ifelse(ex, format(file.mtime(file.path(charts_root, out$charts)), "%Y-%m-%d %H:%M"), "-")
  ln <- c(ln, sprintf("CHARTS (%d/%d 존재 — 발송 대상은 존재분만):", sum(ex), length(ex)),
          sprintf("  %s [%s · %s]", out$charts, ifelse(ex, "존재", "부재"), mt), "",
          sprintf("FOOTER: %s", out$footer),
          sprintf("WINDOW FF5: mode=%s · %s · months=%s", out$w_ff$mode, out$w_ff$label,
                  paste(out$w_ff$months, collapse = ",")))
  if (!is.null(out$w_sb))
    ln <- c(ln, sprintf("WINDOW SB : mode=%s · %s · months=%s", out$w_sb$mode, out$w_sb$label,
                        paste(out$w_sb$months, collapse = ",")))
  c(ln, sprintf("regime_line: %s", out$regime_line), sprintf("revive_watch: %s", out$revive_watch),
    sprintf("sb_line: %s", if (is.null(out$sb_line)) "-" else out$sb_line))
}
