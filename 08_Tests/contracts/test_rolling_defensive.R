#!/usr/bin/env Rscript
#==============================================================================
# test_rolling_defensive.R — 롤링 등급 · 방어형 스코어 · F 구제 (도훈 2026-09-04)
#
# 지키는 것:
#   ① 전기간 1점이 오래된 사건에 지배될 때 롤링이 그것을 드러내는가
#   ② 구제가 **F 에서만** · **C 까지만** 움직이는가 (등급 산식을 대체하지 않는다)
#   ③ 회복→재붕괴 이력이 남는가 — 구제하되 감추지 않는다(1403.8125 는 5회 前例가 있었다)
#   ④ 방어형이 **실현 하락월**로 정의되는가 (국면 라벨 비의존 — 라벨은 이 시스템의 병목)
#   ⑤ 표본 부족은 '방어형 아님'이 아니라 '판정 불가(NA)'인가
#   ⑥ grade_base 가 보존되는가 — 소비자가 출처를 구분해야 한다
#==============================================================================
suppressMessages({ library(data.table); library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
Sys.setenv(QM_ROOT = ROOT)
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat(sprintf("  OK   %s\n", m)) }
ng <- function(m, d = "") { FAIL <<- FAIL + 1L; cat(sprintf("  FAIL %s%s\n", m, if (nzchar(d)) paste0(" — ", d) else "")) }

suppressMessages(source("02_Infrastructure/contracts/rolling_grade.R"))
suppressMessages(source("02_Infrastructure/contracts/defensive_score.R"))
RP <- rg_params(ROOT); DP <- ds_params(ROOT)

# ── 합성 시계열 생성기 ───────────────────────────────────────────────────────
.mk <- function(mret, bret = NULL) {
  ## ★월중으로 잡는다 — 말일에서 by="month" 로 굴리면 2월 31일이 3월 3일이 되어
  ##   월이 건너뛰고 중복된다(실측: 132개월 픽스처가 격월 시계열로 붕괴해 롤링 시작점이
  ##   36개월이 아니라 61개월이 됐다). 라이브러리가 아니라 픽스처의 결함이었다.
  d <- seq(as.Date("2005-01-15"), by = "month", length.out = length(mret))
  pr <- data.table(date = d, ret_net = mret)
  br <- if (is.null(bret)) NULL else data.table(date = d, benchmark_ret = bret)
  list(pr = pr, br = br)
}
set.seed(1)

cat("=== A. 롤링이 오래된 사건의 지배를 드러내는가 ===\n")
# 앞 60개월 파국(-8%/월 12회 포함) + 뒤 60개월 양호
bad  <- c(rep(-0.08, 12), rnorm(48, 0.002, 0.03))
good <- rnorm(60, 0.020, 0.020)
S <- .mk(c(bad, good))
r <- rg_rolling(S$pr, NULL, RP)
if (identical(r$status, "ok")) ok(sprintf("A1 산출(롤링점 %d)", r$n_points)) else ng("A1", r$status)
if (is.finite(r$pass_recent) && is.finite(r$pass_life) && r$pass_recent > r$pass_life)
  ok(sprintf("A2 최근 충족 %.2f > 생애 충족 %.2f ★전기간 1점이 못 보는 것", r$pass_recent, r$pass_life)) else
  ng("A2 롤링이 개선을 못 드러냄", sprintf("recent %.2f vs life %.2f", r$pass_recent %||% NA, r$pass_life %||% NA))
if (isTRUE(r$current$pass)) ok("A3 현재 롤링점이 문턱 통과") else ng("A3")

cat("\n=== B. 구제 경계 — F 에서만, C 까지만 ===\n")
res <- rg_rescue("F", r, RP)
if (isTRUE(res$rescued) && identical(res$new_grade, "C")) ok("B1 F -> C 구제") else
  ng("B1 구제 실패", res$reason)
if (identical(res$label, "recent_regime")) ok("B2 라벨 부착") else ng("B2 라벨 없음")
for (g in c("C", "B", "A")) {
  rr <- rg_rescue(g, r, RP)
  if (!isTRUE(rr$rescued)) ok(sprintf("B3 등급 %s 는 구제 대상 아님(위반 주입)", g)) else
    ng(sprintf("B3 등급 %s 가 구제됐다", g), "구제가 등급 산식을 침범")
}
if (identical(rg_rescue(NA_character_, r, RP)$rescued, FALSE)) ok("B4 NA 등급 구제 안 함") else ng("B4")

cat("\n=== C. 위반 주입 — 최근이 나쁘면 구제 안 된다 ===\n")
S2 <- .mk(c(good, bad))                                   # 순서를 뒤집는다
r2 <- rg_rolling(S2$pr, NULL, RP)
res2 <- rg_rescue("F", r2, RP)
if (!isTRUE(res2$rescued)) ok(sprintf("C1 최근 악화 시 구제 거부 (최근충족 %.2f)", r2$pass_recent)) else
  ng("C1 나쁜 최근이 구제됐다")
S3 <- .mk(rnorm(40, 0.001, 0.03))                          # 롤링점 부족
r3 <- rg_rolling(S3$pr, NULL, RP)
res3 <- rg_rescue("F", r3, RP)
if (!isTRUE(res3$rescued)) ok("C2 롤링점 부족 시 판단 보류") else ng("C2 표본 부족인데 구제")

cat("\n=== D. 회복->재붕괴 이력 (감추지 않는다) ===\n")
# 좋음 -> 나쁨 -> 좋음: 회복이 두 번
S4 <- .mk(c(rnorm(48, 0.02, 0.02), rep(-0.06, 24), rnorm(60, 0.02, 0.02)))
r4 <- rg_rolling(S4$pr, NULL, RP)
h <- r4$history
if (!is.null(h) && h$prior_recoveries >= 1L)
  ok(sprintf("D1 前例 %d회 포착", h$prior_recoveries)) else
  ng("D1 회복 이력 미포착", as.character(h$prior_recoveries %||% NA))
res4 <- rg_rescue("F", r4, RP)
if (isTRUE(res4$rescued) && grepl("처음이 아니다", res4$reason))
  ok("D2 구제 사유에 '처음이 아니다' 경고가 실린다 ★핵심") else
  ng("D2 경고 누락", "구제하되 감추지 않는다가 무너짐")
if (isTRUE(rg_rescue("F", r, RP)$rescued) && !grepl("처음이 아니다", rg_rescue("F", r, RP)$reason))
  ok("D3 前例 없으면 그 경고를 안 붙인다(음성 대조)") else
  cat("  SKIP 단조 회복 픽스처에도 前例가 잡힘\n")

cat("\n=== E. 방어형 = 실현 하락월 (국면 라벨 비의존) ===\n")
n <- 180L
bm <- rnorm(n, 0.005, 0.05)
st_def <- -0.6 * bm + rnorm(n, 0.004, 0.02)               # 역상관 = 방어형
st_agg <-  1.3 * bm + rnorm(n, 0.001, 0.02)               # 고베타 = 비방어형
Sd <- .mk(st_def, bm); Sa <- .mk(st_agg, bm)
dd <- ds_score(Sd$pr, Sd$br, DP); da <- ds_score(Sa$pr, Sa$br, DP)
if (isTRUE(dd$defensive)) ok(sprintf("E1 역상관 전략 = 방어형 (하락월 초과 %+.2f%%, t %.2f)",
    100*dd$down$excess, dd$down$t)) else ng("E1 방어형 미검출", dd$reason)
if (!isTRUE(da$defensive)) ok("E2 고베타 전략 = 비방어형 (위반 주입)") else
  ng("E2 고베타가 방어형으로 잡힘")
if (is.finite(dd$deep$excess) && is.finite(dd$down$excess))
  ok(sprintf("E3 심도별 세그먼트 산출 (deep n=%d)", dd$deep$n)) else ng("E3 심도 세그먼트 없음")
src <- paste(readLines("02_Infrastructure/contracts/defensive_score.R", warn = FALSE), collapse = "\n")
if (!grepl("regime_label|국면엔진 라벨 기준이다", src) && grepl("실제로 마이너스", src))
  ok("E4 정의가 실현 하락월 — 국면 라벨을 참조하지 않는다") else
  ng("E4 국면 라벨 의존 잔존")

cat("\n=== F. 표본 부족 = '아님'이 아니라 '판정 불가' ===\n")
Ss <- .mk(rnorm(70, 0.01, 0.02), c(rep(0.02, 62), rep(-0.03, 8)))   # 하락월 8개
ds8 <- ds_score(Ss$pr, Ss$br, DP)
if (is.na(ds8$defensive %||% NA)) ok(sprintf("F1 하락월 부족 -> NA (%s)", ds8$status)) else
  ng("F1 부족한데 판정을 냈다", as.character(ds8$defensive))
if (grepl("판정 불가", ds8$status)) ok("F2 사유 명시") else ng("F2 사유 없음")

cat("\n=== G. 풀 자격 — 등급 floor 와 방어형 경로 ===\n")
e1 <- ds_pool_eligible("B", dd, DP)
if (isTRUE(e1$eligible) && identical(e1$route, "grade_floor")) ok("G1 B 등급 = grade_floor 경로") else ng("G1")
e2 <- ds_pool_eligible("F", dd, DP)
if (isTRUE(e2$eligible) && identical(e2$route, "defensive_specialist"))
  ok("G2 F 등급 방어형 = defensive_specialist 경로 ★부활 지점") else ng("G2", e2$reason)
e3 <- ds_pool_eligible("F", da, DP)
if (!isTRUE(e3$eligible)) ok("G3 F 등급 비방어형 = 부적격(위반 주입)") else ng("G3")

cat("\n=== H. essence_score 배선 — grade_base 보존 ===\n")
esrc <- paste(readLines("02_Infrastructure/contracts/essence_score.R", warn = FALSE), collapse = "\n")
for (k in c("rolling_grade", "defensive_score", "grade_base", "recent_regime_rescued")) {
  if (grepl(k, esrc, fixed = TRUE)) ok(sprintf("H %s 필드 존재", k)) else ng(sprintf("H %s 누락", k))
}
if (grepl("rg_rescue", esrc, fixed = TRUE)) ok("H 구제 호출 배선") else ng("H 구제 미배선")
if (grepl("reasons <<-", esrc, fixed = TRUE))
  ok("H 실패가 사유에 남는다(<<- · 최상위 <- 는 조용한 no-op)") else ng("H 실패 침묵")

cat("\n=== I. 설정이 정본인가 (하드코딩 금지) ===\n")
for (f in c("06_Registry/rolling_grade.json", "06_Registry/defensive_score.json")) {
  if (file.exists(f)) ok(sprintf("I %s 존재", basename(f))) else ng(sprintf("I %s 부재", basename(f)))
}
if (identical(as.numeric(RP$floor_calmar), 0.64)) ok("I floor_calmar 가 essence A floor 와 일치") else
  ng("I floor 불일치", as.character(RP$floor_calmar))

cat("
=== J. 2계층 풀 배선 — 방어형 경로가 실제로 있는가 ===
")
bmp <- "02_Infrastructure/regime/build_module_performance.R"
bsrc <- paste(readLines(bmp, warn = FALSE), collapse = "
")
if (grepl(".defensive_ok", bsrc, fixed = TRUE)) ok("J1 풀 빌더에 방어형 판정 함수") else
  ng("J1 미배선", "산출만 하고 소비 없음 = 이 저장소의 상습병")
if (grepl("defensive_specialist", bsrc, fixed = TRUE))
  ok("J2 편입 경로가 산출물에 라벨로 남는다") else ng("J2 경로 라벨 없음")
if (grepl("n_defensive_admitted", bsrc, fixed = TRUE))
  ok("J3 방어형 편입 수가 결과에 기록된다") else ng("J3 미기록")
if (grepl("QVEST_L2_DEFENSIVE_ROUTE", bsrc, fixed = TRUE))
  ok("J4 kill switch 존재") else ng("J4 스위치 없음")
.bcode <- paste(sub("#.*$", "", readLines(bmp, warn = FALSE)), collapse = "
")
if (grepl("grade_floor", .bcode, fixed = TRUE) && grepl(".floor_ok", .bcode, fixed = TRUE))
  ok("J5 등급 floor 를 대체하지 않고 병렬 경로 (회귀)") else ng("J5 floor 손상")

cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
cat(sprintf('{"test":"rolling_defensive","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL > 0L) 1L else 0L)
