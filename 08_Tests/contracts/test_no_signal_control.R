## test_no_signal_control.R — 무신호 대조군 계약 검사기 (양방향: 양성 대조 + 위반 주입)
## 규약: "경고 0" 만으로는 검사기가 살아있는지 알 수 없다 — 일부러 틀린 입력을 넣어 발화를 확인한다.
suppressPackageStartupMessages({library(data.table)})
ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
SELF <- normalizePath(file.path(dirname(sys.frame(1)$ofile %||% "."), "..", ".."), mustWork = FALSE)
`%||%` <- function(a, b) if (is.null(a)) b else a
if (dir.exists(file.path(SELF, "02_Infrastructure/contracts"))) ROOT <- SELF
setwd(ROOT)
source("02_Infrastructure/contracts/no_signal_control.R")

PASS <- 0L; FAIL <- 0L
chk <- function(name, ok, detail = "") {
  if (isTRUE(ok)) { PASS <<- PASS + 1L; cat(sprintf("  [ok]   %s\n", name)) }
  else { FAIL <<- FAIL + 1L; cat(sprintf("  [FAIL] %s %s\n", name, detail)) }
}
set.seed(20260822)
n <- 180L
bm <- rnorm(n, 0.008, 0.05)

cat("=== A. no_signal_gate — 양성 대조 (알파가 실재하는 전략) ===\n")
ctl <- 1.05 * bm + rnorm(n, 0.0000, 0.010)          # 대조군: beta 1.05, 알파 0
str_good <- ctl + 0.006 + rnorm(n, 0, 0.004)         # 전략: 대조군 + 월 0.6% 알파
g1 <- no_signal_gate(str_good, ctl, bm)
chk("알파 실재 시 SIGNAL_ADDS_VALUE", g1$verdict == "SIGNAL_ADDS_VALUE",
    sprintf("(verdict=%s, diff_t=%.2f)", g1$verdict, g1$diff_nw_t))
chk("diff_ann 이 주입한 알파(연 7.2%)에 근접", abs(g1$diff_ann - 0.072) < 0.02,
    sprintf("(diff_ann=%.4f)", g1$diff_ann))

cat("\n=== B. 위반 주입 — 전략이 대조군의 재라벨일 뿐일 때 ===\n")
str_same <- ctl + rnorm(n, 0, 0.002)                 # 알파 0, 잡음만
g2 <- no_signal_gate(str_same, ctl, bm)
chk("알파 부재 시 INDISTINGUISHABLE 발화", g2$verdict == "INDISTINGUISHABLE_FROM_NO_SIGNAL",
    sprintf("(verdict=%s, diff_t=%.2f)", g2$verdict, g2$diff_nw_t))
chk("★검출력 확인: A 와 B 가 다른 verdict", g1$verdict != g2$verdict)

cat("\n=== C. 위반 주입 — 전략이 대조군보다 나쁠 때 ===\n")
str_bad <- ctl - 0.006 + rnorm(n, 0, 0.004)
g3 <- no_signal_gate(str_bad, ctl, bm)
chk("열위 시 SIGNAL_HURTS 발화", g3$verdict == "SIGNAL_HURTS",
    sprintf("(verdict=%s, diff_t=%.2f)", g3$verdict, g3$diff_nw_t))

cat("\n=== D. beta 오염 분리 — PORT_t 는 높은데 알파는 0 인 경우 ===\n")
## 순수 레버리지: beta 1.4, 알파 0. PORT_t 는 (beta-1)*E[bm] 때문에 양수여야 하나 t_alpha 는 0 근방.
str_lev <- 1.4 * bm + rnorm(n, 0, 0.004)
g4 <- no_signal_gate(str_lev, ctl, bm)
chk("순수 레버리지의 t_alpha 가 비유의", abs(g4$strategy[["t_alpha"]]) < 1.96,
    sprintf("(t_alpha=%.3f)", g4$strategy[["t_alpha"]]))
chk("그런데 PORT_t 는 양수 — 지표가 알파를 과대표시함을 계약이 드러냄",
    g4$strategy[["port_t"]] > 0, sprintf("(port_t=%.3f)", g4$strategy[["port_t"]]))
chk("beta_contrib_ann 이 실제 (beta-1)*E[bm] 과 일치",
    abs(g4$strategy[["beta_contrib_ann"]] - (g4$strategy[["beta"]] - 1) * 12 * mean(bm)) < 1e-9)

cat("\n=== E. 계약 방어 — 표본 부족 시 stop ===\n")
e <- tryCatch({ no_signal_gate(rnorm(10), rnorm(10), rnorm(10)); "no_error" },
              error = function(x) "stopped")
chk("24개월 미만이면 stop", e == "stopped")

cat("\n=== F. build_no_signal_control — 인자 방어 ===\n")
e2 <- tryCatch({ build_no_signal_control(months = c("2020-01"), n_stocks = 25L); "no_error" },
               error = function(x) "stopped")
chk("월 그리드 24 미만이면 stop", e2 == "stopped")

cat("\n=== G. 실데이터 — 대조군이 제약을 지키는가 (rawdata 존재 시에만) ===\n")
if (file.exists(".cache/rawdata.parquet")) {
  ymv <- format(seq(as.Date("2015-01-01"), as.Date("2024-12-01"), by = "month"), "%Y-%m")
  ct <- tryCatch(build_no_signal_control(ymv, n_stocks = 25L, cap = 0.20),
                 error = function(e) NULL)
  if (is.null(ct)) { cat("  [skip] rawdata 로드 실패\n") } else {
    chk("보유 종목수 <= 25", is.na(ct$holdings_n) || ct$holdings_n <= 25L,
        sprintf("(n=%s)", ct$holdings_n))
    chk("단일비중 <= 0.20 (+eps)", is.na(ct$max_w) || ct$max_w <= 0.20 + 1e-9,
        sprintf("(max_w=%.4f)", ct$max_w))
    chk("수익 계열이 대부분 유효", mean(is.finite(ct$ret)) > 0.8,
        sprintf("(finite=%.2f)", mean(is.finite(ct$ret))))
  }
} else cat("  [skip] .cache/rawdata.parquet 부재\n")

cat(sprintf("\n=== 결과: PASS %d / FAIL %d ===\n", PASS, FAIL))
if (FAIL > 0) quit(status = 1)
