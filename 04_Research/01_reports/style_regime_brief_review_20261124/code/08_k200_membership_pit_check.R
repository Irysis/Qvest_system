## 08_k200_membership_pit_check.R — 스마트베타 유니버스(K200 ∪ KQ150 열)가 그 시점 구성(PIT)인지 · 지금 구성을 과거에 덧씌운 것인지(C6)
##   판별: 월말마다 K200 == TRUE 종목 수(그 시점 구성이면 늘 200 안팎) · 상장폐지된 종목이 과거 K200 으로 남아 있는지.
##   RAWDATA 읽기 = 월말 날짜만 · 4열(메모리 상한).
suppressMessages({ library(arrow); library(data.table); library(dplyr) })
ud <- sort(unique(as.Date(as.data.table(read_parquet(".cache/rawdata.parquet", col_select = "Date"))$Date)))
me <- as.Date(tapply(ud, format(ud, "%Y-%m"), max), origin = "1970-01-01")
me <- me[me >= as.Date("2004-12-01")]
p <- as.data.table(open_dataset(".cache/rawdata.parquet") |> filter(Date %in% me) |> select(Date, Ticker, K200, KQ150) |> collect())
p[, Date := as.Date(Date)]
cnt <- p[, .(n_k200 = sum(K200 == TRUE, na.rm = TRUE), n_kq150 = sum(KQ150 == TRUE, na.rm = TRUE)), by = Date][order(Date)]
cat("[K200 · KQ150 = TRUE 종목 수 — 연 1회 표본]\n"); print(cnt[format(Date, "%m") == "06"])
last_seen <- p[, .(last = max(Date)), by = Ticker]
gone <- last_seen[last < max(me) - 365, Ticker]                    # 1년 넘게 전에 사라진 종목(상장폐지 등)
cat(sprintf("\n사라진 종목 %d개 중 과거 어느 월말에 K200 이었던 종목 %d개 · KQ150 이었던 종목 %d개\n", length(gone),
            p[Ticker %in% gone & K200 == TRUE, uniqueN(Ticker)], p[Ticker %in% gone & KQ150 == TRUE, uniqueN(Ticker)]))
cat(sprintf("월말 K200 종목 수 범위 %d~%d · KQ150 %d~%d (2010-01 이후)\n", min(cnt[Date >= as.Date("2010-01-01"), n_k200]),
            max(cnt[Date >= as.Date("2010-01-01"), n_k200]), min(cnt[Date >= as.Date("2010-01-01"), n_kq150]), max(cnt[Date >= as.Date("2010-01-01"), n_kq150])))
