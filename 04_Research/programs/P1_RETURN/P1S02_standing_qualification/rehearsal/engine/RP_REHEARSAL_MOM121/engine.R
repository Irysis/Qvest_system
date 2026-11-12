## P1S02 등록 전 리허설 전용 엔진(2026-11-12 · 판단 T1 C-20261111-085) — 리서치 산출이 아니다. 판정 경로(셀 워커 → 러너 → 측정 관문 →
##   칸 평가 → judge → 보고)를 싼 CPU 월말 격자 점수 엔진으로 한 번 끝까지 지나기 위한 것. 레인 · 등록부 · 기저 풀에 들어가지 않는다.
## 신호: 패널 달력의 달마다 마지막 거래일 t 에, 전 종목 12-1 모멘텀 = 종목 행 기준 (t−252, t−21] 거래일의 Σ log(1 + Ret)
##   (형성 창 관행 = Jegadeesh & Titman 1993, https://doi.org/10.1111/j.1540-6261.1993.tb04702.x).
## PIT: t 의 점수는 Date ≤ t 의 Ret 만 쓴다(누적합의 shift — 최근 21거래일 건너뜀). RAWDATA 열만(Date · Ticker · Ret).
## 측정 시작일: 셀 경로가 넘기는 .RP_START_DATE 이후 신호만 낸다 — 없으면 멈춘다(시작일 전달 경로 시험).
## 출력: FACTORS(Date, Ticker, Score).
if (!exists(".RP_START_DATE")) stop("[rehearsal engine] .RP_START_DATE 없음 — 셀 경로가 측정 시작일을 넘기지 않았다")
.rh_start <- as.Date(.RP_START_DATE)
.rh <- data.table::as.data.table(RAWDATA)[, list(Date = as.Date(Date), Ticker = as.character(Ticker), Ret = as.numeric(Ret))]
.rh <- unique(.rh, by = c("Ticker", "Date"))
data.table::setorder(.rh, Ticker, Date)
.rh[, lr := log1p(ifelse(is.finite(Ret) & Ret > -1, Ret, 0))]
.rh[, cs := cumsum(lr), by = Ticker]
.rh[, Score := data.table::shift(cs, 21L) - data.table::shift(cs, 252L), by = Ticker]
.rh_cal <- sort(unique(.rh$Date))
.rh_me <- .rh_cal[!duplicated(format(.rh_cal, "%Y-%m"), fromLast = TRUE)]
.rh_me <- .rh_me[.rh_me >= .rh_start]
FACTORS <- .rh[Date %in% .rh_me & is.finite(Score), list(Date, Ticker, Score)]
rm(.rh, .rh_cal, .rh_me); invisible(gc(verbose = FALSE))
