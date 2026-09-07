#!/usr/bin/env Rscript
# test_ds_convex_retired.R — 볼록성 플래그 폐기 (도훈 결정 2026-09-07)
#   폐기 사유(실측): ①무신호 대조에서 더 잘 켜졌다(대조 25/48 52% vs 실제 57/179 32%) —
#   저베타 판은 정의상 deep$excess > down$excess 를 만족하므로 방어 기전이 아니라 베타 부족을 쟀다.
#   ②Henriksson-Merton 로 재니 진짜 볼록 0/179, 전부 오목(up-β 0.42 < down-β 1.06).
#   ③심도월 표본 10개 중 2개가 2026-03·07(역대 최심도 1·3위)이라 판정이 두 달에 얹혀 있었다.
#   양방향: 양성(새 산출에 필드 없음 · 다른 축은 불변) + 위반 주입(구판 복원 시 빨강).
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat("  OK  ", m, "\n") }
ng <- function(m, why = "") { FAIL <<- FAIL + 1L; cat("  FAIL", m, if (nzchar(why)) paste0(" — ", why) else "", "\n") }
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
suppressWarnings(suppressMessages({ library(data.table) }))
invisible(capture.output(suppressMessages(
  source(file.path(ROOT, "02_Infrastructure/contracts/defensive_score.R"), local = globalenv()))))

## 픽스처 — 저베타 판(구판이라면 convex TRUE 가 켜졌을 형태: 심도가 깊을수록 초과가 커진다)
set.seed(7)
n <- 180L
dts <- seq(as.Date("2011-01-31"), by = "month", length.out = n)
k <- rnorm(n, 0.004, 0.05)                 # 벤치 월수익
k[c(20, 55, 90, 130)] <- c(-0.16, -0.21, -0.12, -0.18)   # 심도월 주입
s <- 0.55 * k + rnorm(n, 0.002, 0.02)      # 저베타 = 하락 깊을수록 초과 커짐(구판 convex 발화 형태)
pr <- data.table(date = dts, ret_net = s)
br <- data.table(date = dts, benchmark_ret = k)
d  <- ds_score(pr, br, ds_params(ROOT))

cat("=== A. 양성 — 새 산출에 볼록 필드가 없다 ===\n")
if (identical(d$status, "ok")) ok("A0 픽스처가 판정 가능(하락월 충분)") else { ng("A0 판정 불가", d$status); }
if (is.null(d$convex)) ok("A1 반환 목록에 convex 없음") else ng("A1 convex 가 아직 나온다", as.character(d$convex))
if (!grepl("볼록", d$reason %||% "", fixed = TRUE)) ok("A2 사유 문구에 '볼록' 없음") else ng("A2 사유에 볼록 문구 잔존", d$reason)
## 폐기가 다른 축을 건드리지 않았는지 — 판정과 세그먼트는 그대로여야 한다
if (is.logical(d$defensive) && length(d$defensive) == 1L) ok("A3 defensive 판정은 그대로") else ng("A3 판정이 깨졌다")
for (seg in c("down", "mid", "deep", "up"))
  if (is.list(d[[seg]]) && !is.null(d[[seg]]$excess)) ok(sprintf("A4 %s 세그먼트 보존", seg)) else ng(sprintf("A4 %s 소실", seg))
## ★픽스처가 실제로 구판을 발화시키는 형태인가 — 아니면 A1 이 공허하다
if (is.finite(d$deep$excess) && is.finite(d$down$excess) && d$deep$excess > d$down$excess)
  ok("A5 픽스처는 구판이라면 convex=TRUE 였을 형태(deep > down) — A1 이 공허하지 않다") else
  ng("A5 픽스처가 구판을 발화 못 시킨다 — 검출력 없음",
     sprintf("deep %.4f down %.4f", d$deep$excess %||% NA, d$down$excess %||% NA))

cat("=== B. 위반 주입 — 구판을 되살리면 잡히는가 ===\n")
## 구판 정의를 그대로 재현해 "만약 남아 있었다면" 어떤 값이 나오는지 보인다(소스 복원 없이 논리만).
old_convex <- is.finite(d$deep$excess) && is.finite(d$down$excess) && d$deep$excess > d$down$excess
if (isTRUE(old_convex)) ok("B1 구판 논리는 이 픽스처에서 TRUE — 폐기 전후가 실제로 갈린다") else
  ng("B1 구판 논리도 FALSE — 대조가 성립 안 함")
## 소비자 전수: 새 산출 경로에 convex 를 싣는 코드가 남아 있으면 안 된다(주석은 제외)
srcs <- c("02_Infrastructure/contracts/defensive_score.R",
          "02_Infrastructure/contracts/essence_score.R",
          "02_Infrastructure/contracts/register_measured_module.R",
          "02_Infrastructure/contracts/register_module.R",
          "02_Infrastructure/ops/backfill_module_defensive.R",
          "02_Infrastructure/ops/retro_rolling_defensive.R",
          "02_Infrastructure/ops/rf_replication_verify.R")
live <- character(0)
for (f in srcs) {
  ln <- readLines(file.path(ROOT, f), encoding = "UTF-8", warn = FALSE)
  ln <- sub("#.*$", "", ln)                       # 주석 제외 — 폐기 사유 기록은 남아야 한다
  hit <- grep("convex", ln, fixed = TRUE, value = TRUE)
  if (length(hit)) live <- c(live, sprintf("%s: %s", basename(f), trimws(hit[1])))
}
if (!length(live)) ok("B2 소비자 7종 중 살아있는 convex 참조 0(주석 제외)") else
  ng(sprintf("B2 %d곳에 잔존", length(live)), paste(live, collapse = " | "))
## 폐기 사유는 주석으로 남아 있어야 한다 — 왜 없앴는지 없이 없애지 않는다
ds_src <- readLines(file.path(ROOT, "02_Infrastructure/contracts/defensive_score.R"), encoding = "UTF-8", warn = FALSE)
if (any(grepl("볼록성 플래그 폐기", ds_src, fixed = TRUE))) ok("B3 폐기 사유가 코드에 남아 있다") else
  ng("B3 사유 없이 지웠다 — 다음 사람이 되살린다")

cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
cat(sprintf('{"test":"ds_convex_retired","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL == 0L) 0L else 1L)
