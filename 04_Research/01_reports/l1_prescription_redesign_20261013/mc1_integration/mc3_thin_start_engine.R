## MC3 B안 통합 확인용 합성 엔진(2026-10-13) — 판정 대상 아님 · 배선 확인 전용
##   신호 = 직전 20거래일 수익률(하루 늦춤 · t−1 · PIT) — Jegadeesh & Titman(1993) 단기 모멘텀 꼴(성과는 보지 않는다)
##   ★폭 설계: 2003-01-01 전 신호일은 멤버 중 종목코드 앞 30종만 점수를 낸다(폭 30 < 보유 25 × 2 = 50) → 계약이 잘라야 한다.
##            2003-01-01 부터는 멤버 전부(수백 종) → 실효 시작 = 2003 년 첫 월말 신호일이어야 한다.
##   시작일은 계약 값(.RP_START_DATE)을 쓴다 — 리터럴 금지(측정 축 전환 규약).
suppressPackageStartupMessages(library(data.table))
.from <- if (exists(".RP_START_DATE")) .RP_START_DATE else stop("계약 시작일(.RP_START_DATE) 없음 — 러너 밖 실행 금지")
.thin_until <- as.Date("2003-01-01")
X <- RAWDATA[, .(Date = as.Date(Date), Ticker, Close = as.numeric(Close), mem = (K200 %in% c(1, TRUE)) | (KQ150 %in% c(1, TRUE)))]
setorder(X, Ticker, Date)
X[, r20 := Close / shift(Close, 20L) - 1, by = Ticker]
X[, sc := shift(r20, 1L), by = Ticker]                                  # t−1: 신호일 당일 종가를 쓰지 않는다
cal <- sort(unique(X$Date))
me <- cal[c(diff(as.integer(format(cal, "%Y%m"))) != 0L, TRUE)]          # 각 달 마지막 거래일
me <- me[me >= .from]
S <- X[Date %in% me & mem & is.finite(sc), .(Date, Ticker, Score = sc)]
setorder(S, Date, Ticker)
S <- S[Date >= .thin_until | rowid(Date) <= 30L]                          # 얇은 초기 구간: 종목코드 앞 30종만
FACTORS <- S
cat(sprintf("[mc3-thin] 신호일 %d개(%s ~ %s) · 2003 전 폭 %s · 2003 후 폭 중앙 %s\n", uniqueN(FACTORS$Date),
            format(min(FACTORS$Date)), format(max(FACTORS$Date)),
            paste(unique(FACTORS[Date < .thin_until, .N, by = Date]$N), collapse = "/"),
            format(stats::median(FACTORS[Date >= .thin_until, .N, by = Date]$N))))
