## 수동 채움 등록부 재작성 — 사건 종류(DART) + 거래소 원주가(네이버 모바일 일별 시세 · closePrice) 로 확인한 행
##   이전상장(코넥스 → 코스닥) = 퀀티 생비율(코넥스 마지막 종가 → 코스닥 첫 종가 · 일반공모 신주가 시총을 부풀린다)
##   장외 → 상장 첫날 = 거래소 첫 종가(원주가) / 퀀티 장외 마지막 종가(원주가 · 호가 단위) − 1
##   1998 토요일 결손 = 네이버 수정주가(KRX 수정계수) 같은 구간 비율
suppressPackageStartupMessages({ library(data.table); library(arrow); library(dplyr); library(jsonlite) })
ROOT <- "G:/OneDrive/Quant_Module_Moltbot"
SP <- "C:/Users/User/AppData/Local/Temp/claude/594eba70e8c297ec/4f700b6a-cb14-4bd1-ada4-261a3fe97759/scratchpad"
REG <- file.path(ROOT, "06_Registry/ret_fill_registry.json")
off <- fread(file.path(SP, "d2_official.csv"))[found == 1]
off[, Date := as.Date(Date)]
tk <- c("A197210", "A220100", "A214610", "A107640", "A250030", "A042000", "A046120", "A053580", "A062970", "A012170",
        "A037030", "A127160", "A180400", "A204990")
rd <- as.data.table(open_dataset(file.path(ROOT, ".cache/RAWDATA.parquet")) |> filter(Ticker %in% tk) |>
  select(Date, Ticker, Close, Size, Ret) |> collect())
rd[, Date := as.Date(Date)]; setorder(rd, Ticker, Date)
rd[, `:=`(pDate = shift(Date), pClose = shift(Close)), by = Ticker]
qr <- function(d, t) { x <- rd[Ticker == t & Date == as.Date(d)]; stopifnot(nrow(x) == 1L); x }
oc <- function(d, t) { x <- off[Ticker == t & Date == as.Date(d)]; stopifnot(nrow(x) == 1L); x }
now <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S+09:00")
DEC <- "RAWDATA-INTERNAL-BREAK-FILL-D2D3-20261114"
E <- list()
add <- function(d, t, ret, method, ev) E[[length(E) + 1L]] <<- list(Date = d, Ticker = t, Ret = round(ret, 10), method = method, evidence = ev,
                                                                    decision = DEC, recorded_at = now)
## ① 코넥스 → 코스닥 이전상장 — 퀀티 생비율(= 보유자 수익)
tr <- list(
  list("2015-11-20", "A197210", "DART 이전상장결정 · 유상증자(일반공모) · 상장폐지결정(코스닥시장 이전상장). 거래소 일별 시세에 없는 종목(상장폐지) — 네이버 수정주가 비율 −40.24% 가 같다."),
  list("2016-12-01", "A220100", "DART 이전상장결정 · 일반공모. 거래소 원주가 코넥스 18,350(11-30) → 코스닥 11,050 = −39.78%(공모가 15,750 기준 등락률 −29.84% 는 보유자 수익이 아니다)."),
  list("2020-10-22", "A214610", "DART 이전상장결정 · 일반공모 유상증자 · 전환청구. 거래소 원주가 코넥스 22,000(10-21) → 코스닥 13,800 = −37.27%. 네이버 수정주가(−14.29%)는 공모가 16,100 에 다시 맞춘 계열이라 보유자 수익이 아니다."),
  list("2024-06-24", "A107640", "DART 이전상장결정 · 일반공모. 거래소 원주가 코넥스 55,000(06-21) → 코스닥 34,000 = −38.18%(공모가 30,000 기준 +13.33% 는 보유자 수익이 아니다)."),
  list("2015-11-19", "A127160", "DART 이전상장결정 · 유상증자 · 상장폐지결정(코스닥시장 이전상장). 상장폐지 종목이라 거래소 일별 시세 없음 — 네이버 수정주가 비율이 같다. 저장값 그대로(확인)."),
  list("2015-11-20", "A180400", "DART 이전상장결정 · 유상증자. 거래소 원주가 코넥스 63,600 → 코스닥 36,300 = −42.92%. 저장값 그대로(확인)."),
  list("2016-12-09", "A204990", "DART 이전상장결정 · 유상증자. 상장폐지 종목이라 거래소 일별 시세 없음 — 네이버 수정주가 비율이 같다. 저장값 그대로(확인).")
)
for (z in tr) {
  x <- qr(z[[1]], z[[2]]); r <- x$Close / x$pClose - 1
  add(z[[1]], z[[2]], r, "konex_transfer_holder_ratio",
      sprintf("코넥스 → 코스닥 이전상장 첫날. 일반공모 신주가 시가총액을 부풀려 시총 기준(%.2f%%)은 보유자 수익이 아니다. 보유자 수익 = 퀀티 생비율 %s %s → %s %s = %.2f%%. %s",
              100 * (x$Size / rd[Ticker == z[[2]] & Date == x$pDate, Size] - 1), x$pDate, format(x$pClose, big.mark = ","), z[[1]], format(x$Close, big.mark = ","), 100 * r, z[[3]]))
}
## A250030 — 정정(17:21 '무상증자 권리락' 판정은 틀렸다)
x <- qr("2026-10-15", "A250030"); o <- oc("2026-10-15", "A250030"); r <- x$Close / x$pClose - 1
add("2026-10-15", "A250030", r, "konex_transfer_holder_ratio",
    sprintf(paste0("★정정(11-14 17:21 의 '무상증자 권리락 · 하한가' 판정은 틀렸다 — DART: 이전상장결정 07-06 · 유상증자결정 08-27 · 상장폐지결정(코스닥시장 이전상장) 10-08). ",
                   "코넥스 → 코스닥 이전상장 첫날 · 공모가 %s. 보유자 수익 = 코넥스 마지막 종가 %s → 첫 종가. 저장 종가 계열(퀀티 %s) 기준 %.2f%% 를 쓴다(다음 날 수익과 이어지게). ",
                   "거래소 종가는 %s(%.2f%%)로 다르다 — 2026-09 부터 퀀티 종가가 거래소 종가와 대부분 어긋나는 별도 결함(거래량은 같다 · 별도 보고)."),
            format(o$base, big.mark = ","), format(x$pClose, big.mark = ","), format(x$Close, big.mark = ","), 100 * r, format(o$close, big.mark = ","),
            100 * (o$close / x$pClose - 1)))
## ② 장외 → 거래소 신규 상장 첫날 — 거래소 첫 종가(원주가) / 장외 마지막 종가(퀀티 · 원주가)
ipo <- list(
  list("2018-02-08", "A042000", "장외(K-OTC)", "DART 증권신고서 · 투자설명서 · 증권발행실적보고서 2018-02-05"),
  list("2010-06-15", "A046120", "장외(프리보드 — DART 호가중개시스템을통한소액매출공시서류 2009-08 · 2010-03)", "DART 증권신고서 · 투자설명서 · 증권발행실적보고서 2010-06-10"),
  list("2019-01-25", "A053580", "장외", "DART 증권신고서 · 투자설명서 · 증권발행실적보고서 2019-01-22"),
  list("2019-12-26", "A062970", "장외", "DART 증권신고서 · 투자설명서 · 증권발행실적보고서 2019-12-20"),
  list("2018-06-07", "A037030", "장외", "DART 증권신고서 · 투자설명서 · 증권발행실적보고서 2018-06-01")
)
for (z in ipo) {
  x <- qr(z[[1]], z[[2]]); o <- oc(z[[1]], z[[2]])
  r <- o$close / x$pClose - 1
  mc <- x$Size / rd[Ticker == z[[2]] & Date == x$pDate, Size] - 1
  f <- 1 - (1 + r) / (1 + mc)
  add(z[[1]], z[[2]], r, "otc_to_exchange_first_day_holder_ratio",
      sprintf(paste0("%s → 코스닥 신규 상장 첫날(%s · 네이버 일별 시세의 첫 날 = 이날). 퀀티는 상장 뒤 가격만 이후 사건으로 수정하고 장외 가격은 원주가로 둬서 생비율(%.2f%%)이 깨졌다. ",
                     "보유자 수익 = 장외 마지막 종가 %s(%s · 호가 단위 원주가) → 거래소 첫 종가 %s(네이버 모바일 원주가 · 기준가 %s) = %.2f%%. ",
                     "교차 검증: 시총 기준 %.2f%% 과 맞추면 상장일 신주 비율 %.1f%%(공모 규모로 타당)."),
              z[[3]], z[[4]], 100 * (x$Close / x$pClose - 1), format(x$pClose, big.mark = ","), x$pDate, format(o$close, big.mark = ","),
              format(o$base, big.mark = ","), 100 * r, 100 * mc, 100 * f))
}
## ③ A012170 1998-01-05 — 퀀티 12-27 · 01-03(토요일) 행 결손 · 같은 구간 네이버 수정주가 비율
x <- qr("1998-01-05", "A012170")
setwd(file.path(ROOT, "02_Infrastructure")); suppressMessages(source("config.R")); invisible(capture.output(source("data/naver_data_collector.R")))
d <- as.data.table(naver_daily_adjusted("012170", "19971215", "19980110")); setnames(d, tolower(names(d)))
dc <- intersect(c("date", "dt"), names(d))[1]; cc <- intersect(c("close", "clpr"), names(d))[1]; d[, dd := as.Date(get(dc))]
r <- d[dd == as.Date("1998-01-05"), get(cc)] / d[dd == x$pDate, get(cc)] - 1
add("1998-01-05", "A012170", r, "second_source_adjusted_ratio",
    sprintf(paste0("퀀티는 1997-12-27 · 1998-01-03(토요일 거래) 행이 없고 그 구간의 수정 계수가 빠져 생비율 %.2f%%. 네이버 수정주가(KRX 수정계수) 같은 구간 %s → 1998-01-05 = %.2f%%(사용). ",
                   "시총 기준 %.2f%% 와는 다르다(주식 수 변화 미상). 측정 축(2000~) 밖."), 100 * (x$Close / x$pClose - 1), x$pDate, 100 * r,
            100 * (x$Size / rd[Ticker == "A012170" & Date == x$pDate, Size] - 1)))
old <- fromJSON(REG, simplifyVector = FALSE)
new <- list(schema = old$schema,
            `_purpose` = paste0("수동 채움 등록부 — 다른 계기(거래소 원주가 · 공시 사건 종류 · 두 번째 원천 수정주가)로 맞는 값을 확인한 단절 행. 가드(seam_scale_guard.R)와 감사기(rawdata_seam_audit.R)가 ",
                                "seam_fill_resolve 로 읽어 시총 기준 값보다 우선하고, 감사기는 단절로 잡히지 않은 행에도 이 값을 강제한다(11-14 · 등록부 = 확인된 값). ",
                                "★사건 종류가 값을 정한다: 무상 · 분할 · 병합 · 감자 = 시총 기준 · 이전상장 · 일반공모 · 합병 = 생비율(신주가 시총을 부풀린다) · 장외 → 상장 첫날 = 거래소 첫 종가 / 장외 마지막 종가. ",
                                "도훈 결정 RAWDATA-INTERNAL-BREAK-FILL-D2D3-20261114('데이터 빈 부분 제대로 채워'). 행마다 근거(method · evidence)."),
            `_owner` = "쓰기 = Q(근거 필수) · 값 변경은 근거 갱신과 함께 · 2026-11-14 신설 · 11-14 19시 재작성(DART 사건 분류 + 거래소 원주가)",
            entries = E)
writeLines(toJSON(new, auto_unbox = TRUE, pretty = TRUE, digits = NA), REG, useBytes = TRUE)
chk <- as.data.table(fromJSON(REG)$entries)
options(width = 200)
print(chk[order(Date), .(Date, Ticker, Ret = round(100 * Ret, 2), method)])
