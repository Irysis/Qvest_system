## test_overlay_window_cutoff.R — C5 오버레이 컷오프 주간 일반화(MC4 · 2026-10-13) 검사기 (양방향)
## 대상: 02_Infrastructure/validation/overlay_pit_guard.R::holding_window_cutoff · assert_overlay_pit
suppressPackageStartupMessages({ library(data.table) })
.self <- tryCatch({ a <- commandArgs(trailingOnly = FALSE); f <- sub("^--file=", "", a[grepl("^--file=", a)])
                    if (length(f)) dirname(f[1]) else "." }, error = function(e) ".")
root <- normalizePath(file.path(.self, "..", ".."), winslash = "/", mustWork = FALSE)
if (!file.exists(file.path(root, "02_Infrastructure", "config.R"))) root <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(root)
source("02_Infrastructure/validation/overlay_pit_guard.R")
pass <- 0L; fail <- 0L
chk <- function(name, ok, detail = "") {
  if (isTRUE(ok)) { pass <<- pass + 1L; cat(sprintf("  [PASS] %s\n", name)) } else { fail <<- fail + 1L; cat(sprintf("  [FAIL] %s %s\n", name, detail)) }
}
err <- function(expr) inherits(tryCatch({ force(expr); NULL }, error = function(e) e), "error")

days <- seq(as.Date("2019-12-01"), as.Date("2020-12-31"), by = "day")
days <- days[!format(days, "%u") %in% c("6", "7")]
days <- as.Date(setdiff(days, as.Date(c("2020-01-01", "2020-05-05"))), origin = "1970-01-01")
me <- data.table(d = days)[, list(d = max(d)), by = list(ym = format(d, "%Y-%m"))]
me <- me[d < max(days)]

cat("=== 월말 신호 — 구 컷오프와 같은 거래일 집합 ===\n")
cw <- holding_window_cutoff(me$d, days)
hm <- format(cw, "%Y-%m")                                   # 홀딩월 = 집행일의 달
co <- overlay_signal_cutoff(hm)
same_set <- vapply(seq_along(cw), function(i) identical(days[days < cw[i]], days[days < co[i]]), logical(1))
chk("C5W1 월말 신호: Date < 창 컷오프(집행일) = Date < 홀딩월 1일 (거래일 집합 동일 · 전 달)", all(same_set), sprintf("(%d/%d)", sum(same_set), length(same_set)))
chk("C5W2 월말 신호의 창 컷오프 = 익월 첫 거래일(1월 1일 · 5월 5일 공휴일 건너뜀)",
    all(format(cw, "%Y-%m") > format(me$d, "%Y-%m")) && identical(cw[format(me$d, "%Y-%m") == "2019-12"], as.Date("2020-01-02")))

cat("\n=== 주간 신호 ===\n")
fri <- as.Date("2020-03-06"); mon <- as.Date("2020-03-09")
c1 <- holding_window_cutoff(fri, days)
chk("C5W3 금요일 신호 → 컷오프 = 다음 월요일(신호일 금요일 데이터까지 허용)", identical(c1, mon) && max(days[days < c1]) == fri)
chk("C5W4 assert_overlay_pit — 창 컷오프 이하 사용 = 통과 · 하루 뒤(집행일 데이터 사용) = 차단",
    !err(assert_overlay_pit(fri + 1, c1)) && err(assert_overlay_pit(c1 + 1, c1)))
mc <- holdings_signal_cutoff(fri)                           # 월 단위 패널 규칙(익월 1일)을 주간 신호에 잘못 쓴 경우
chk("C5W5 [돌연변이 대조] 월 단위 규칙을 주간 신호에 쓰면 컷오프가 집행일 뒤(익월 1일 — 3주 미래 허용) · assert 가 차단",
    mc == as.Date("2020-04-01") && mc > c1 && err(assert_overlay_pit(mc, c1)))
chk("C5W6 마지막 거래일 신호 → NA(다음 거래일 없음)", is.na(holding_window_cutoff(max(days), days)))

cat(sprintf("\n== overlay_window_cutoff: PASS %d · FAIL %d ==\n", pass, fail))
cat(sprintf('{"test":"overlay_window_cutoff","pass":%d,"fail":%d,"total":%d}\n', pass, fail, pass + fail))
if (fail > 0L) quit(status = 1L)
