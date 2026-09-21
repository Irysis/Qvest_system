#!/usr/bin/env Rscript
#==============================================================================
# test_rf_rebalance.R — 집행 주기·회전 통제 축(B6) 양방향 검사 · 2026-09-21 신설
#
# 대상: 02_Infrastructure/reinforcement/rf_rebalance.R (순수 함수 — 엔진·하네스 없이 잰다)
# 재는 것:
#   ① 파싱이 **조용히 무시하지 않는가**(미지원 kind·불가능 파라미터 = stop)
#   ② interval 이 위상까지 정확히 나누는가(위상 대조 = 같은 k 의 두 칸이 서로소)
#   ③ band·cap 이 **회전율을 실제로 줄이는가**(이 축의 존재 이유) · 문턱은 과거에서만 온다
#   ④ rank_buffer 가 보유를 유지하되 n_max 를 지키는가
#   ⑤ 돌연변이 — 규칙 줄을 지우면 회전 감소가 사라진다(= 이 검사가 결함을 잡는다)
#
# 실행: Rscript --no-environ 08_Tests/reinforcement/test_rf_rebalance.R
#==============================================================================
suppressMessages(library(data.table))
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
SRC <- file.path(ROOT, "02_Infrastructure/reinforcement/rf_rebalance.R")
invisible(capture.output(suppressMessages(source(SRC))))
PASS <- 0L; FAIL <- 0L
ok <- function(m, d = "") { PASS <<- PASS + 1L; cat("  OK  ", m, if (nzchar(d)) paste0(" — ", d) else "", "\n") }
ng <- function(m, d = "") { FAIL <<- FAIL + 1L; cat("  FAIL", m, if (nzchar(d)) paste0(" — ", d) else "", "\n") }
chk <- function(cond, m, d = "") if (isTRUE(cond)) ok(m, d) else ng(m, d)

set.seed(11)
DS <- seq(as.Date("2005-01-31"), by = "month", length.out = 60)
N_MAX <- 5L
# 후보 20종 · 점수는 매달 흔들린다(상위 5종이 자주 바뀌도록) — 회전율이 높은 기저
PANEL <- rbindlist(lapply(seq_along(DS), function(i)
  data.table(Date = DS[i], Ticker = sprintf("A%02d", 1:20),
             Score = c(20:1) / 20 + rnorm(20, 0, 0.35))))
SEL <- PANEL[order(Date, -Score)][, head(.SD, N_MAX), by = Date]
PORT <- SEL[, .(Date, Ticker, Weight = 1 / .N, Leg = "LONG"), by = Date][, .(Date, Ticker, Weight, Leg)]
base_to <- rf_rb_turnover(PORT)

cat("=== A. 파싱 (조용한 무시 금지) ===\n")
chk(is.null(rf_rb_parse(NULL)) && is.null(rf_rb_parse(list())), "A1 규칙 없음 → NULL(무처치)")
chk(identical(rf_rb_parse(list(kind = "interval", k = 3))$phase, 0L), "A2 interval 기본 위상 0")
chk(inherits(try(rf_rb_parse(list(kind = "quarterly")), silent = TRUE), "try-error"), "A3 [위반] 미지원 kind → stop")
chk(inherits(try(rf_rb_parse(list(kind = "interval", k = 1)), silent = TRUE), "try-error"), "A4 [위반] k=1 → stop(무처치 위장 금지)")
chk(inherits(try(rf_rb_parse(list(kind = "interval", k = 3, phase = 3)), silent = TRUE), "try-error"), "A5 [위반] phase >= k → stop")
chk(inherits(try(rf_rb_parse(list(kind = "rank_buffer", mult = 1)), silent = TRUE), "try-error"), "A6 [위반] mult<=1 → stop(버퍼 없는 버퍼)")

cat("\n=== B. interval — 주기·위상 ===\n")
r2a <- rf_rb_parse(list(kind = "interval", k = 2, phase = 0))
r2b <- rf_rb_parse(list(kind = "interval", k = 2, phase = 1))
r3  <- rf_rb_parse(list(kind = "interval", k = 3, phase = 0))
e2a <- rf_rb_emit(PORT, r2a); e2b <- rf_rb_emit(PORT, r2b); e3 <- rf_rb_emit(PORT, r3)
d2a <- sort(unique(e2a$Date)); d2b <- sort(unique(e2b$Date)); d3 <- sort(unique(e3$Date))
chk(length(d2a) == 30L && length(d2b) == 30L && length(d3) == 20L,
    "B1 k=2 는 30회 · k=3 은 20회 (60개월)", sprintf("%d/%d/%d", length(d2a), length(d2b), length(d3)))
chk(!length(intersect(d2a, d2b)) && length(union(d2a, d2b)) == 60L,
    "B2 같은 k 의 두 위상은 서로소이고 합치면 전 기간 (위상 대조가 성립한다)")
chk(identical(d2a[1], DS[1]) && identical(d2b[1], DS[2]), "B3 위상 0/1 의 시작이 한 달 어긋난다")
chk(rf_rb_turnover(e2a) > 0 && length(unique(e3$Date)) < length(unique(PORT$Date)),
    "B4 배출 날짜가 줄어든다 = 리밸 횟수가 준다(비용은 리밸 시점에만 부과된다)")

cat("\n=== C. no_trade_band · turnover_cap — 회전이 실제로 줄어드는가 ===\n")
rb <- rf_rb_parse(list(kind = "no_trade_band", stat = "expanding_median", min_hist = 6L))
rc <- rf_rb_parse(list(kind = "turnover_cap", stat = "expanding_quantile", q = 0.25, min_hist = 6L))
eb <- rf_rb_emit(PORT, rb); ec <- rf_rb_emit(PORT, rc)
chk(length(unique(eb$Date)) < 60L, "C1 밴드가 일부 달을 미체결로 건너뛴다",
    sprintf("%d/60회", length(unique(eb$Date))))
chk(rf_rb_turnover(ec) < base_to, "C2 상한이 회전율을 낮춘다",
    sprintf("%.3f → %.3f", base_to, rf_rb_turnover(ec)))
s_in  <- PORT[, .(s = sum(Weight)), by = Date]
s_out <- ec[, .(s = sum(Weight)), by = Date]
m <- merge(s_in, s_out, by = "Date")
chk(max(abs(m$s.x - m$s.y)) < 1e-8, "C3 상한 혼합이 그 날의 노출(Σw)을 보존한다",
    sprintf("최대 편차 %.2e", max(abs(m$s.x - m$s.y))))
# 문턱은 과거에서만 온다 — 첫 min_hist 구간은 규칙이 발화하지 않는다(미래 참조 금지의 실물)
first6 <- sort(unique(PORT$Date))[1:7]
chk(all(first6 %in% unique(eb$Date)), "C4 min_hist 이전에는 규칙이 발화하지 않는다(확장창 = 과거만)")

cat("\n=== D. rank_buffer — 유지하되 n_max 는 지킨다 ===\n")
rr <- rf_rb_parse(list(kind = "rank_buffer", mult = 2))
SB <- rf_rb_select(PANEL, SEL, rr, N_MAX)
cnt <- SB[, .N, by = Date]
chk(all(cnt$N == N_MAX), "D1 매 달 정확히 n_max 종", sprintf("min %d max %d", min(cnt$N), max(cnt$N)))
PB <- SB[, .(Date, Ticker, Weight = 1 / .N, Leg = "LONG"), by = Date][, .(Date, Ticker, Weight, Leg)]
chk(rf_rb_turnover(PB) < base_to, "D2 버퍼가 회전율을 낮춘다(이 축의 존재 이유)",
    sprintf("%.3f → %.3f", base_to, rf_rb_turnover(PB)))
# 유지 규칙의 직접 증거: 순위가 n_max 밖(6~10위)인데 유지된 이름이 있어야 한다
P2 <- copy(PANEL)[order(Date, -Score)][, .rk := seq_len(.N), by = Date]
chk(nrow(merge(SB[, .(Date, Ticker)], P2[.rk > N_MAX & .rk <= 2 * N_MAX, .(Date, Ticker)],
               by = c("Date", "Ticker"))) > 0L,
    "D3 상위 n_max 밖(버퍼 구간)의 보유가 실제로 유지된 달이 있다")
chk(nrow(merge(SB[, .(Date, Ticker)], P2[.rk > 2 * N_MAX, .(Date, Ticker)], by = c("Date", "Ticker"))) == 0L,
    "D4 버퍼 밖(2*n_max 초과)은 유지하지 않는다 — 버퍼는 무한 보유가 아니다")

cat("\n=== E. 무처치·돌연변이 ===\n")
chk(identical(rf_rb_emit(PORT, NULL), PORT) && identical(rf_rb_select(PANEL, SEL, NULL, N_MAX), SEL),
    "E1 규칙 NULL 이면 입력 그대로(월간 그대로 · 기존 칸 비트 동일)")
mut <- readLines(SRC, warn = FALSE, encoding = "UTF-8")
drop <- grepl("if (is.finite(thr) && dist < thr) next", mut, fixed = TRUE)
if (sum(drop) != 1L) ng("E2 돌연변이 대상 줄 탐색", sprintf("%d건", sum(drop))) else {
  mp <- tempfile(fileext = ".R"); writeLines(mut[!drop], mp, useBytes = TRUE)
  me <- new.env(parent = globalenv()); invisible(capture.output(suppressMessages(source(mp, local = me))))
  eb_m <- me$rf_rb_emit(PORT, rb)
  chk(length(unique(eb_m$Date)) == 60L,
      "E2 [돌연변이] 밴드 판정 줄 제거 → 미체결이 사라진다(= C1 이 결함을 잡는다)",
      sprintf("%d/60회", length(unique(eb_m$Date))))
  unlink(mp)
}

cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
cat(sprintf('{"test":"rf_rebalance","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
if (FAIL > 0L) quit(status = 1)
