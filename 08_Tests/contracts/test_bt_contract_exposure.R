## test_bt_contract_exposure.R — 계약 nav 순노출 · 낙폭 지속 단위(2026-10-17 수리 · 도훈 승인 '수리승인')
##   ① build_nav: 시뮬레이터가 net_exposure 를 주지 않으면 보유 Σw 를 리밸일마다 재고 다음 리밸까지 이어 붙인다(첫 리밸 전 = 0).
##      구판은 gross(1 − 현금)로 채워 롱숏 장부도 순노출 1 로 적었다(2604.16773 점검 — 실제 순노출 중앙 −0.51).
##   ② 시뮬레이터가 준 값 · 보유 없음은 구판 그대로. ③ 뮤테이션(보유 무시)을 ① 이 잡는다(소스 텍스트 치환).
## 실행: Rscript 08_Tests/contracts/test_bt_contract_exposure.R
suppressPackageStartupMessages({ library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
PASS <- 0L; FAIL <- 0L
chk <- function(name, ok, detail = "") if (isTRUE(ok)) { PASS <<- PASS + 1L; cat("  [PASS]", name, "\n") } else { FAIL <<- FAIL + 1L; cat("  [FAIL]", name, detail, "\n") }
SRC <- "02_Infrastructure/contracts/backtest_result_contract.R"
E <- new.env(); invisible(capture.output(suppressMessages(sys.source(SRC, envir = E))))
days <- seq(as.Date("2024-01-01"), by = "day", length.out = 30)
sim <- function(extra_nav = NULL) {
  nav <- data.table(Date = days, NAV = seq(1, 1.29, by = 0.01), NAV_gross = seq(1, 1.29, by = 0.01))
  if (!is.null(extra_nav)) nav[, names(extra_nav) := extra_nav]
  list(DAILY_NAV_DT = nav, PORTFOLIO_LOG = NULL)
}
H <- data.table(date = as.Date(c("2024-01-05", "2024-01-05", "2024-01-05", "2024-01-20", "2024-01-20")),
                ticker = c("A", "B", "C", "A", "D"), target_weight = c(0.3, -0.5, -0.2, 0.6, 0.4))
n1 <- E$build_nav(sim(), "r", "s", holdings_tbl = H)
at <- function(nv, d) nv$net_exposure[nv$date == as.Date(d)]
chk("1a 롱숏 장부 — 리밸일(01-05)부터 Σw = −0.40 · 다음 리밸 전날(01-19)까지 이어 붙임", isTRUE(all.equal(at(n1, "2024-01-05"), -0.4)) && isTRUE(all.equal(at(n1, "2024-01-19"), -0.4)))
chk("1b 다음 리밸(01-20)부터 Σw = 1.00 · 첫 리밸 전(01-04) = 0", isTRUE(all.equal(at(n1, "2024-01-20"), 1.0)) && identical(at(n1, "2024-01-04"), 0))
n2 <- E$build_nav(sim(list(net_exposure = rep(0.7, 30))), "r", "s", holdings_tbl = H)
chk("2a 시뮬레이터가 준 net_exposure 는 그대로(0.7)", all(n2$net_exposure == 0.7))
n3 <- E$build_nav(sim(), "r", "s", holdings_tbl = NULL)
chk("2b 보유 없음 = 구판 그대로(gross = 1 − 현금 = 1)", all(n3$net_exposure == 1))
src <- readLines(SRC, encoding = "UTF-8", warn = FALSE)
mut <- sub("    if (!is.null(hw) && nrow(hw) && !is.na(dcol)) {", "    if (FALSE) {", src, fixed = TRUE)
Em <- new.env(); invisible(capture.output(suppressMessages(eval(parse(text = mut, encoding = "UTF-8"), envir = Em))))
nm <- Em$build_nav(sim(), "r", "s", holdings_tbl = H)
chk("3 뮤테이션(보유 무시) — 치환 성사 · 뮤테이션판은 1a 를 어긴다(롱숏도 1) → 검출력", !identical(mut, src) && !isTRUE(all.equal(at(nm, "2024-01-05"), -0.4)))
cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
cat(sprintf('{"test":"bt_contract_exposure","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL > 0L) 1L else 0L)
