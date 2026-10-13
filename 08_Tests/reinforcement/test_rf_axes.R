## test_rf_axes.R — 처방 · 조립 고정 축 단정(MC5 · Σw ≤ 1) 검사기 (양방향: 양성 대조 + 위반 주입)
## 대상: 02_Infrastructure/reinforcement/rf_axes.R · 배선 = rf_cell_engine.R(비중 단계 · cap_core)
suppressPackageStartupMessages({ library(data.table) })
.qv_self_dir <- function() tryCatch({
  a <- commandArgs(trailingOnly = FALSE); f <- sub("^--file=", "", a[grepl("^--file=", a)])
  if (length(f)) dirname(f[1]) else "."
}, error = function(e) ".")
ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
SELF <- normalizePath(file.path(.qv_self_dir(), "..", ".."), mustWork = FALSE)
if (dir.exists(file.path(SELF, "02_Infrastructure/reinforcement"))) ROOT <- SELF
setwd(ROOT)
source("02_Infrastructure/reinforcement/rf_axes.R")
PASS <- 0L; FAIL <- 0L
chk <- function(name, ok, detail = "") {
  if (isTRUE(ok)) { PASS <<- PASS + 1L; cat(sprintf("  [ok]   %s\n", name)) }
  else { FAIL <<- FAIL + 1L; cat(sprintf("  [FAIL] %s %s\n", name, detail)) }
}
err <- function(expr) inherits(tryCatch({ force(expr); NULL }, error = function(e) e), "error")
mk <- function(w_list) rbindlist(lapply(seq_along(w_list), function(i)
  data.table(Date = as.Date("2020-01-31") + 31L * (i - 1L), Ticker = sprintf("T%03d", seq_along(w_list[[i]])), Weight = w_list[[i]])))
N <- 25L

cat("=== A. 통과(양성 대조) ===\n")
full <- mk(list(rep(1 / 25, 25), rep(1 / 20, 20)))
chk("A1 완전 투자(Σw = 1) · 25종 이하 통과", !err(rf_assert_axes(full, N)))
cash <- mk(list(rep(0.8 / 25, 25), rep(0.5 / 10, 10)))           # 현금 20% · 50%
s <- rf_assert_axes(cash, N)
chk("A2 잔여 현금(Σw = 0.8 · 0.5) 통과 — MC5 신규 허용", isTRUE(all.equal(sort(s$s), c(0.5, 0.8))))
old_rule <- function(P) max(abs(P[, .(s = sum(Weight)), by = Date]$s - 1)) < 1e-8   # 구판 단정(rf_cell_engine 구 :520)
chk("A3 [돌연변이 대조] 같은 현금 입력을 구판 단정은 거부했다(Σw = 1 강제)", !old_rule(cash) && old_rule(full))
chk("A4 부동소수 경계(Σw = 1 + 5e-9) 통과", !err(rf_assert_axes(mk(list(c(rep(1 / 25, 24), 1 / 25 + 5e-9))), N)))

cat("\n=== B. 위반 주입 ===\n")
chk("B1 레버리지 Σw = 1.2 거부", err(rf_assert_axes(mk(list(rep(1.2 / 25, 25))), N)))
chk("B2 음수 비중 거부(long-only)", err(rf_assert_axes(mk(list(c(rep(1.1 / 24, 24), -0.1))), N)))
chk("B3 보유 26종 > n_max 25 거부", err(rf_assert_axes(mk(list(rep(1 / 26, 26))), N)))
chk("B4 Σw = 0 날짜(빈 포트폴리오) 거부", err(rf_assert_axes(mk(list(rep(1 / 25, 25), rep(0, 5))), N)))
chk("B5 결측 비중 거부", err(rf_assert_axes(mk(list(c(rep(1 / 25, 24), NA))), N)))
chk("B6 n_max = NULL 이면 보유 수는 검사 안 함(오버레이 · 충실구현 재사용 대비)", !err(rf_assert_axes(mk(list(rep(1 / 40, 40))), NULL)))

cat("\n=== C. 배선 ===\n")
eng <- paste(readLines("02_Infrastructure/reinforcement/rf_cell_engine.R", warn = FALSE, encoding = "UTF-8"), collapse = "\n")
chk("C1 엔진이 rf_axes.R 을 불러오고 두 단정 지점에서 rf_assert_axes 를 쓴다",
    grepl("reinforcement/rf_axes.R", eng, fixed = TRUE) && lengths(regmatches(eng, gregexpr("rf_assert_axes\\(PORTFOLIO", eng))) == 2L)
chk("C2 엔진에 구판 Σw = 1 단정(abs(... - 1) < 1e-8)이 남아 있지 않다",
    !grepl("abs\\(\\.chk\\$s - 1\\)", eng) && !grepl("by = Date\\]\\$s - 1\\)\\) < 1e-8", eng))

cat("\n=== D. 동점 규칙(MC1 · rf_select_top) ===\n")
Pt <- data.table(Date = as.Date("2020-01-31"), Ticker = c("A001", "A002", "A003", "A004", "A005"),
                 Score = c(2, 1, 1, 1, 0.5), liq = c(9, 1, 7, NA, 9))
old_pick <- function(P, n) P[order(Date, -Score)][, head(.SD, n), by = Date]       # 구판 식(엔진 구 :384)
chk("D1 tie = NULL 은 구판 식과 같다(같은 Score 는 행 순서 = 종목코드 순 — 구 축 비트 동일)",
    identical(rf_select_top(Pt, 3), old_pick(Pt, 3)) && identical(rf_select_top(Pt, 3)$Ticker, c("A001", "A002", "A003")))
s2 <- rf_select_top(Pt, 3, tie = "liq")
chk("D2 tie = 거래대금 — 같은 Score(1) 중 거래대금 높은 A003 이 종목코드가 앞선 A002 보다 먼저 · 결측(A004)은 뒤로",
    identical(s2$Ticker, c("A001", "A003", "A002")) && identical(rf_select_top(Pt, 4, tie = "liq")$Ticker[4], "A004"))
Pr <- Pt[.N:1]                                                                    # 행 순서(엔진에선 종목코드 정렬 순)를 뒤집으면
chk("D3 [돌연변이 대조] 행 순서를 뒤집어도 tie 선정은 같다(거래대금이 정한다) · 구판 식은 선정이 바뀐다(행 순서가 정했다)",
    identical(rf_select_top(Pr, 3, tie = "liq")$Ticker, s2$Ticker) && !identical(old_pick(Pr, 3)$Ticker, old_pick(Pt, 3)$Ticker),
    sprintf("(tie %s · 구판 %s vs %s)", paste(rf_select_top(Pr, 3, tie = "liq")$Ticker, collapse = ","),
            paste(old_pick(Pr, 3)$Ticker, collapse = ","), paste(old_pick(Pt, 3)$Ticker, collapse = ",")))
chk("D4 동점 열이 없으면 멈춘다", err(rf_select_top(Pt, 3, tie = "nope")))
chk("D6 엔진 유니버스 all_hyg 는 측정 축 주입 표식(K200_IDX)이 없으면 멈춘다(처치 미전달 차단 · 구 all_listed 사고 형태)",
    grepl('identical(k, "all_hyg")', eng, fixed = TRUE) && grepl('if (!"K200_IDX" %in% names(x))', eng, fixed = TRUE))
chk("D5 엔진이 측정 축 주입 표식에서만 동점 규칙을 켠다(구 축 = tie NULL)",
    grepl('.tie_liq <- "K200_IDX" %in% names(DT)', eng, fixed = TRUE) &&
      grepl('rf_select_top(PANEL, .N_MAX, tie = if (.tie_liq) ".tie_adv" else NULL)', eng, fixed = TRUE))

cat(sprintf("\n== rf_axes: PASS %d · FAIL %d ==\n", PASS, FAIL))
cat(sprintf('{"test":"rf_axes","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
if (FAIL > 0L) quit(status = 1L)
