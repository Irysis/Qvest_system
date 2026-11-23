#==============================================================================
# 관세청 수출 실적 수집기 — 10일 단위 잠정치(품목별 · 국가별) + 월 확정치 총계
#   2026-11-23 · 도훈 '수출 데이터 더 빠른 원천을 찾아봐' → '배선해주고' · '공공데이터 포털에 신청했어' · 결정 KR-EXPORT-CUSTOMS-FAST-PIPELINE-20261123
#
# 왜: 한국은행 ECOS 의 수출금액(KR_EXPORT)은 두 달쯤 늦게 반영된다(2026-11-23 에 9월분이 최신). 관세청은 같은 통관 자료를
#     그 달 11일(1~10일분) · 21일(1~20일분) · 다음 달 1일(한 달분 잠정) · 15일경(확정)에 낸다. 월말 신호에 전월 확정치와 그 달 1~20일분까지 붙일 수 있다.
#
# 원천(공공데이터포털 · 키 = 저장소 .env 의 DATA_GO_API_KEY · 키 값은 어디에도 찍지 않는다):
#   ① 수출 주요품목별 10일 단위 잠정치  apis.data.go.kr/1220000/prlstMmUtPrviExpAcrs/getPrlstMmUtPrviExpAcrs   https://www.data.go.kr/data/15157908/openapi.do
#   ② 수출 주요국가별 10일 단위 잠정치  apis.data.go.kr/1220000/cntyMmUtPrviExpAcrs/getCntyMmUtPrviExpAcrs     https://www.data.go.kr/data/15157941/openapi.do
#      ① · ② 는 2016-01 부터, 달마다 세 줄(01~10 · 01~20 · 01~말일), 단위 천 달러. 응답에는 열 이름이 없다 — 열의 뜻은 위 두 쪽의 명세(2026-11-23 확인)를 따랐다.
#      지난 달들의 값은 '그때 발표된 잠정치'가 아니라 그 뒤 고쳐진 값이다(2016~2025년 한 달분은 ECOS 수출금액과 같다 — 2026-11-23 대조).
#   ③ 품목별 수출입실적  apis.data.go.kr/1220000/Itemtrade/getItemtradeList   https://www.data.go.kr/data/15101609/openapi.do
#      품목 부호 없이 한 달을 부르면 10자리 품목 전부와 마지막에 '총계' 행이 온다(약 2MB). 다음 달 15일경(휴일이면 다음 영업일) 그 달이 생기고,
#      그때 전월까지의 값도 고쳐진다. 아직 안 나온 달은 빈 목록이 온다.
#
# 계열(단위 = 천 달러 · Date = 관측월 1일):
#   KR_EXP_<품목>_D10 · _D20 · _MON     품목 = TOTAL(전체) · SEMI(반도체) · STEEL(철강제품) · CAR(승용차) · PETRO(석유제품) · PHONE(무선통신기기)
#                                        · SHIP(선박) · AUTOPART(자동차부품) · COMPPERIPH(컴퓨터주변기기) · PRECISION(정밀기기) · APPLIANCE(가전제품)
#   KR_EXP_TO_<나라>_D10 · _D20 · _MON  나라 = CN · US · EU · VN · HK · JP · TW · IN · SG · MY
#       D10 = 1~10일 누계 · D20 = 1~20일 누계 · MON = 한 달분(다음 달 1일에 잠정치로 생기고 그 뒤 고쳐진다)
#   KR_EXP_TOTAL_CONF · KR_IMP_TOTAL_CONF   월 확정치 총계(③ 의 '총계' 행 · 달러를 1000 으로 나눈 값)
#   주 계열은 KR_EXP_TOTAL_* 다. 나머지는 같은 응답의 열을 버리지 않고 남긴 것이다(수집 이력은 지나가면 복원할 수 없다).
#
# 쓰는 파일:
#   .cache/customs_kr_trade.parquet            최신 값 — Date · Value · Series (ecos_kr_activity 와 같은 꼴)
#   .cache/customs_kr_trade_vintages.parquet   수집 이력 — Series · Date · Value · First_Seen · Kind(backfill · new · revision · late). 덧붙이기만 한다.
#   '그때 알 수 있던 값'은 이 이력이 쌓인 구간에서만 쓸 수 있다 — 그 전 구간은 고쳐진 값이다(PIT 경계 · pit.md C4 와 같은 성격).
#
# 가용일 규칙 = 06_Registry/kr_activity_availability_rules.json 의 KR_CUSTOMS_D10 · _D20 · _MON · _CONF(계열 이름은 aliases).
# 하나라도 못 받으면 아무 파일도 쓰지 않는다. 응답이 선언한 모양과 다르면 멈춘다(기간 표기 · 총계 행 = 품목 합).
#
# Usage(daily_refresh [4ka] — data/run_ecos_kr_activity.R 가 부른다):
#   source("config.R"); source("data/data_collector_customs_trade.R"); customs_fetch_kr_trade()
#==============================================================================
cat("[customs] Loading...\n")

suppressPackageStartupMessages({ library(data.table); library(arrow) })
if (!exists(".ecos_act_vintage_rows", mode = "function")) {      # 수집 이력 판정과 파일 쓰기는 한국 경기 지표 수집기의 것을 그대로 쓴다
  source(file.path(if (exists("INFRA_DIR")) INFRA_DIR else file.path(PROJECT_ROOT, "02_Infrastructure"), "data", "data_collector_ecos_activity.R"))
}
if (!exists("CACHE_DIR")) CACHE_DIR <- file.path(PROJECT_ROOT, ".cache")
if (!exists("CUSTOMS_TRADE_CACHE")) CUSTOMS_TRADE_CACHE <- file.path(CACHE_DIR, "customs_kr_trade.parquet")
if (!exists("CUSTOMS_TRADE_VINTAGES")) CUSTOMS_TRADE_VINTAGES <- file.path(CACHE_DIR, "customs_kr_trade_vintages.parquet")

CUSTOMS_API_BASE <- "https://apis.data.go.kr/1220000"
CUSTOMS_PROV_FROM <- 2016L                                       # 잠정치 API 의 제공 시작 해
## 열 순서 = itemUsdAmt00 ~ itemUsdAmt10. NA = 계열로 쓰지 않는 열(국가별의 전체 수출액 — 품목별의 전체와 같아야 한다)
CUSTOMS_PROV_SOURCES <- list(
  list(endpoint = "prlstMmUtPrviExpAcrs", op = "getPrlstMmUtPrviExpAcrs",
       keys = c("TOTAL", "SEMI", "STEEL", "CAR", "PETRO", "PHONE", "SHIP", "AUTOPART", "COMPPERIPH", "PRECISION", "APPLIANCE")),
  list(endpoint = "cntyMmUtPrviExpAcrs", op = "getCntyMmUtPrviExpAcrs",
       keys = c(NA, "TO_CN", "TO_US", "TO_EU", "TO_VN", "TO_HK", "TO_JP", "TO_TW", "TO_IN", "TO_SG", "TO_MY"))
)
CUSTOMS_CONF_SERIES <- c(exp = "KR_EXP_TOTAL_CONF", imp = "KR_IMP_TOTAL_CONF")

.customs_key <- function() {
  f <- file.path(PROJECT_ROOT, ".env")
  if (!file.exists(f)) stop("[customs] .env 가 없다 — DATA_GO_API_KEY 를 읽을 수 없다")
  ln <- grep("^DATA_GO_API_KEY=", readLines(f, warn = FALSE, encoding = "UTF-8"), value = TRUE)
  k <- if (length(ln)) trimws(sub("^DATA_GO_API_KEY=", "", ln[1L])) else ""
  if (!nzchar(k)) stop("[customs] .env 에 DATA_GO_API_KEY 가 없다")
  k
}

## 한 번 부른다. 정상 응답(HTTP 200 + 결과 코드 00)의 글을 돌려주고, 아니면 멈춘다. 오류 글에 키가 섞이면 가린다.
.customs_get <- function(endpoint, op, start_ym, end_ym, key, tries = 3L) {
  enc <- utils::URLencode(key, reserved = TRUE, repeated = TRUE)
  url <- sprintf("%s/%s/%s?serviceKey=%s&strtYymm=%s&endYymm=%s", CUSTOMS_API_BASE, endpoint, op, enc, start_ym, end_ym)
  mask <- function(s) gsub(enc, "<가림>", gsub(key, "<가림>", s, fixed = TRUE), fixed = TRUE)
  last <- "응답 없음"
  for (i in seq_len(tries)) {
    resp <- tryCatch(httr::GET(url, httr::timeout(90)), error = function(e) { last <<- conditionMessage(e); NULL })
    if (!is.null(resp)) {
      txt <- httr::content(resp, "text", encoding = "UTF-8")
      st <- httr::status_code(resp)
      if (st == 200L && grepl("<resultCode>00</resultCode>", txt, fixed = TRUE)) return(txt)
      last <- sprintf("HTTP %d · %s", st, substr(gsub("\\s+", " ", txt), 1L, 200L))
      if (grepl("returnReasonCode", txt, fixed = TRUE)) break    # 인증 · 미등록 오류는 다시 불러도 같다
    }
    if (i < tries) Sys.sleep(2 * i)
  }
  stop(sprintf("[customs] %s %s~%s 수급 실패 — %s", endpoint, start_ym, end_ym, mask(last)))
}

## 응답을 <item> 조각으로 나눈다. 2MB 응답 한 줄을 정규식으로 훑으면(일치마다 글자 위치를 다시 세어) 한 번에 수십 초가 걸린다 —
##   그래서 고정 글자로 자르고(strsplit fixed), 짧은 조각마다 꼬리표 값을 뽑는다.
.customs_items <- function(txt) {
  x <- strsplit(txt, "</item>", fixed = TRUE)[[1L]]
  x <- x[grepl("<item>", x, fixed = TRUE)]
  sub("^.*<item>", "<item>", x)
}
.customs_tag <- function(items, tag) {
  x <- trimws(sub(sprintf("^.*<%s>([^<]*)</%s>.*$", tag, tag), "\\1", items))
  x[!grepl(sprintf("<%s>", tag), items, fixed = TRUE)] <- NA_character_
  x
}
.customs_month_first <- function(ym) as.Date(paste0(ym, "01"), format = "%Y%m%d")
.customs_month_days <- function(d) as.integer(format(as.Date(format(d + 31L, "%Y-%m-01")) - 1L, "%d"))

#' 잠정치 응답의 글 → 긴 표(Date · Value · Series). 줄이 없으면 NULL
#' @param keys 열 itemUsdAmt00~10 의 계열 이름 조각(NA = 계열로 쓰지 않는다)
.customs_parse_prov <- function(txt, keys) {
  items <- .customs_items(txt)
  if (!length(items)) return(NULL)
  ym <- .customs_tag(items, "priodMon"); per <- .customs_tag(items, "priodDt")
  d <- .customs_month_first(ym)
  dd <- suppressWarnings(as.integer(sub("^01~", "", per)))
  code <- fifelse(dd == 10L, "D10", fifelse(dd == 20L, "D20", fifelse(dd == .customs_month_days(d), "MON", NA_character_)))
  if (anyNA(d) || anyNA(code)) stop(sprintf("[customs] 모르는 기간 표기 — %s", paste(unique(sprintf("%s %s", ym, per)[is.na(d) | is.na(code)]), collapse = " · ")))
  if (anyDuplicated(paste(ym, code))) stop("[customs] 같은 달 · 같은 기간이 두 번 왔다")
  parts <- lapply(seq_along(keys), function(k) {
    v <- suppressWarnings(as.numeric(gsub(",", "", .customs_tag(items, sprintf("itemUsdAmt%02d", k - 1L)), fixed = TRUE)))
    data.table(Date = d, Value = v, Series = if (is.na(keys[k])) sprintf("_CHECK_%s", code) else sprintf("KR_EXP_%s_%s", keys[k], code))
  })
  out <- rbindlist(parts)
  if (anyNA(out$Value)) stop("[customs] 숫자가 아닌 값이 왔다")
  out
}

#' 품목별 수출입실적 한 달 응답의 글 → list(exp, imp, rows) (천 달러). 아직 안 나온 달(빈 목록)은 NULL
.customs_parse_conf <- function(txt, ym) {
  items <- .customs_items(txt)
  if (!length(items)) return(NULL)
  ex <- suppressWarnings(as.numeric(.customs_tag(items, "expDlr"))); im <- suppressWarnings(as.numeric(.customs_tag(items, "impDlr")))
  yr <- .customs_tag(items, "year")
  n <- length(yr)
  if (n < 2L || anyNA(ex) || anyNA(im) || anyNA(yr) || yr[n] != "총계") stop(sprintf("[customs] %s 확정치 — 총계 행이 끝에 없거나 값이 빠진 행이 있다", ym))
  if (any(yr[-n] != sprintf("%s.%s", substr(ym, 1L, 4L), substr(ym, 5L, 6L)))) stop(sprintf("[customs] %s 확정치 — 다른 달의 행이 섞여 왔다", ym))
  if (abs(sum(ex[-n]) - ex[n]) > 0.5 || abs(sum(im[-n]) - im[n]) > 0.5) stop(sprintf("[customs] %s 확정치 — 총계 행이 품목 합과 다르다(덜 받은 응답일 수 있다)", ym))
  list(exp = ex[n] / 1000, imp = im[n] / 1000, rows = n - 1L)
}

.customs_months_back <- function(d, n) seq(d, by = "-1 month", length.out = n + 1L)[n + 1L]

#' 관세청 수출 실적(10일 단위 잠정치 + 월 확정치 총계)을 받아 최신 값 파일과 수집 이력을 갱신한다
#' @param today 수집일(시험용 — 기본 = 오늘)
#' @param backfill_months 확정치를 처음 받을 때 거슬러 받는 달 수(한 달 = 호출 한 번 · 약 2MB)
#' @param revise_months 새 달의 확정치가 생긴 날, 고쳐진 값을 다시 받는 앞선 달 수
#' @return 최신 값 data.table(Date, Value, Series) — 보이지 않게
#' @export
customs_fetch_kr_trade <- function(today = Sys.Date(), backfill_months = 24L, revise_months = 12L) {
  today <- as.Date(today); key <- .customs_key()
  ## ① ② 잠정치 — 제공 시작 해부터 올해까지 해마다 한 번(응답 수 KB)
  prov <- list()
  for (src in CUSTOMS_PROV_SOURCES) {
    for (y in seq.int(CUSTOMS_PROV_FROM, as.integer(format(today, "%Y")))) {
      p <- .customs_parse_prov(.customs_get(src$endpoint, src$op, sprintf("%d01", y), sprintf("%d12", y), key), src$keys)
      if (is.null(p)) stop(sprintf("[customs] %s %d년 — 줄이 없다", src$endpoint, y))
      prov[[paste(src$endpoint, y)]] <- p
    }
  }
  prov <- rbindlist(prov)
  if (anyDuplicated(prov[, .(Series, Date)])) stop("[customs] 잠정치 — 같은 계열 · 같은 달이 두 번 왔다")
  chk <- merge(prov[grepl("^_CHECK_", Series), .(Date, code = sub("^_CHECK_", "", Series), ctry = Value)],
               prov[grepl("^KR_EXP_TOTAL_D10$|^KR_EXP_TOTAL_D20$|^KR_EXP_TOTAL_MON$", Series), .(Date, code = sub("^KR_EXP_TOTAL_", "", Series), item = Value)], by = c("Date", "code"))
  nbad <- chk[abs(ctry - item) > 0.5, .N]
  if (nbad) cat(sprintf("[customs] 주의 — 국가별 응답의 전체 수출액이 품목별 응답과 다른 줄 %d개(두 응답이 서로 다른 때에 고쳐졌을 수 있다)\n", nbad))
  prov <- prov[!grepl("^_CHECK_", Series)]

  ## ③ 확정치 총계 — 처음이면 거슬러 받고, 그 뒤로는 아직 없는 달만 부른다. 새 달이 생긴 날에는 앞선 달들도 다시 받는다(그날 함께 고쳐진다)
  old <- if (file.exists(CUSTOMS_TRADE_CACHE)) as.data.table(read_parquet(CUSTOMS_TRADE_CACHE, mmap = FALSE)) else NULL   # 곧 같은 파일을 덮어쓴다 — 매핑으로 잡아 두지 않는다
  if (!is.null(old)) old[, Date := as.Date(Date)]
  conf_old <- if (is.null(old)) NULL else old[Series %in% CUSTOMS_CONF_SERIES]
  target <- .customs_months_back(as.Date(format(today, "%Y-%m-01")), 1L)                 # 지난달
  have <- if (!is.null(conf_old) && nrow(conf_old)) max(conf_old$Date) else as.Date(NA)
  want <- if (is.na(have)) seq(.customs_months_back(target, backfill_months - 1L), target, by = "month")
          else if (have < target) seq(have, target, by = "month")[-1L] else as.Date(character(0))
  fetch_conf <- function(d) {
    ym <- format(d, "%Y%m")
    r <- .customs_parse_conf(.customs_get("Itemtrade", "getItemtradeList", ym, ym, key), ym)
    if (is.null(r)) return(NULL)
    data.table(Date = d, Value = c(r$exp, r$imp), Series = unname(CUSTOMS_CONF_SERIES[c("exp", "imp")]))
  }
  got <- list(); fresh <- as.Date(character(0))
  for (i in seq_along(want)) {
    r <- fetch_conf(want[i])
    if (is.null(r)) break                                                                 # 아직 안 나왔다 — 그 뒤 달도 없다
    got[[length(got) + 1L]] <- r; fresh <- c(fresh, want[i])
  }
  if (is.na(have) && !length(got)) stop("[customs] 확정치를 한 달도 받지 못했다")
  if (!is.na(have) && length(fresh)) {                                                    # 새 달이 생겼다 — 앞선 달들의 고쳐진 값을 받는다
    back <- seq(.customs_months_back(min(fresh), revise_months), min(fresh), by = "month")
    for (d in as.list(back[-length(back)])) {
      r <- fetch_conf(d)
      if (is.null(r)) stop(sprintf("[customs] %s 확정치 — 전에 있던 달이 비어 왔다", format(d, "%Y-%m")))
      got[[length(got) + 1L]] <- r
    }
  }
  conf_new <- if (length(got)) rbindlist(got) else NULL
  conf <- rbindlist(list(if (!is.null(conf_old) && !is.null(conf_new)) conf_old[!conf_new, on = c("Series", "Date")] else conf_old, conf_new), use.names = TRUE)

  out <- rbindlist(list(prov, conf[, .(Date, Value, Series)]), use.names = TRUE)
  setorder(out, Series, Date)
  vint <- if (file.exists(CUSTOMS_TRADE_VINTAGES)) as.data.table(read_parquet(CUSTOMS_TRADE_VINTAGES, mmap = FALSE)) else NULL
  if (!is.null(vint)) vint[, `:=`(Date = as.Date(Date), First_Seen = as.Date(First_Seen))]
  add <- .ecos_act_vintage_rows(out, vint, today)
  if (nrow(add)) {
    vint2 <- rbindlist(list(vint, add), use.names = TRUE)
    setorder(vint2, Series, Date, First_Seen)
    .ecos_act_write(vint2, CUSTOMS_TRADE_VINTAGES)
  }
  .ecos_act_write(out, CUSTOMS_TRADE_CACHE)

  last <- function(s) { x <- out[Series == s]; if (nrow(x)) sprintf("%s %s", format(x$Date[nrow(x)], "%Y-%m"), format(round(x$Value[nrow(x)]), big.mark = ",")) else "없음" }
  cat(sprintf("[customs] 전체 수출(천 달러) — 1~10일 %s · 1~20일 %s · 한 달 잠정 %s · 확정 %s\n",
              last("KR_EXP_TOTAL_D10"), last("KR_EXP_TOTAL_D20"), last("KR_EXP_TOTAL_MON"), last("KR_EXP_TOTAL_CONF")))
  k <- add[, .N, by = Kind]
  cat(sprintf("[customs] 저장 — 최신 값 %d행 · 계열 %d개 · 확정치 호출 %d번 · 수집 이력에 덧붙인 줄 %d(%s)\n", nrow(out), uniqueN(out$Series), length(got),
              nrow(add), if (nrow(k)) paste(sprintf("%s %d", k$Kind, k$N), collapse = " · ") else "변화 없음"))
  nw <- add[Kind == "new" & grepl("^KR_EXP_TOTAL_", Series)]
  if (nrow(nw)) cat(sprintf("[customs] 새 관측 — %s\n", paste(sprintf("%s %s", sub("^KR_EXP_TOTAL_", "", nw$Series), format(nw$Date, "%Y-%m")), collapse = " · ")))
  invisible(out)
}

#' 최신 값(Date, Value, Series) — 없으면 받는다
#' @export
customs_load_kr_trade <- function() {
  if (!file.exists(CUSTOMS_TRADE_CACHE)) {
    cat("[customs] Cache not found, fetching...\n")
    return(customs_fetch_kr_trade())
  }
  as.data.table(read_parquet(CUSTOMS_TRADE_CACHE))
}

#' 수집 이력(Series, Date, Value, First_Seen, Kind)
#' @export
customs_load_kr_trade_vintages <- function() {
  if (!file.exists(CUSTOMS_TRADE_VINTAGES)) return(NULL)
  as.data.table(read_parquet(CUSTOMS_TRADE_VINTAGES))
}

cat("[customs] Loaded. Functions: customs_fetch_kr_trade(), customs_load_kr_trade(), customs_load_kr_trade_vintages()\n")
