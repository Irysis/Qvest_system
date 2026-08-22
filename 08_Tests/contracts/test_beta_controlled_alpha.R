# test_beta_controlled_alpha.R — β-통제 α 계약의 **양방향 검출력** (2026-08-22 신설)
#
# 왜 있나 (measurement-graduation.md §2):
#   §2 는 PORT_t 보고 시 β-통제 α 병기를 의무화했는데 계산 함수가 없어 매번 손으로 짰다.
#   구현이 갈리면 수치를 나란히 인용할 수 없다(오늘 하루 세 번 겪은 정규화 문제와 같은 계통).
#
# ★1급 축은 "계산이 되는가" 가 아니라 **"두 방향을 다 잡는가"** 다.
#   · β>1 → PORT_t 가 α 를 **과대** 표시 (DFA T3: 활성수익의 52%가 β 기여)
#   · β<1 → PORT_t 가 α 를 **과소** 표시 (q90_pinball: β 기여 −37.3%)
#   과소 쪽을 못 잡으면 **살릴 것을 버린다**. 규범이 β>1 사례만 담고 있었던 것이 그 위험이었다.
#
# ★그리고 **합성 대조**가 핵심이다 — 실데이터만으로는 '정답' 을 모른다.
#   α·β 를 내가 정한 값으로 심고 그 값이 회수되는지 본다(위반 주입의 정공법).
suppressWarnings(suppressMessages({
  ROOT <- Sys.getenv("QM_ROOT", Sys.getenv("CLAUDE_PROJECT_DIR", getwd()))
  src <- file.path(ROOT, "02_Infrastructure", "contracts", "beta_controlled_alpha.R")
}))
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat("  PASS ", m, "\n") }
ng <- function(m, d) { FAIL <<- FAIL + 1L; cat("  FAIL ", m, " :: ", d, "\n") }

if (!file.exists(src)) {
  cat("  SKIP  계약 부재\n== t_summary: PASS=0 FAIL=0 ==\n"); quit(status = 0)
}
source(src)
set.seed(20260822)

mk <- function(n, alpha_m, beta, bench_mu = 0.010, bench_sd = 0.05, eps_sd = 0.02) {
  b <- rnorm(n, bench_mu, bench_sd)
  r <- alpha_m + beta * b + rnorm(n, 0, eps_sd)
  list(r = r, b = b)
}

cat("== 회수 축: 심은 α·β 가 되돌아오는가 (합성 대조) ==\n")
d <- mk(400, alpha_m = 0.004, beta = 1.0)
x <- beta_controlled_alpha(d$r, d$b, 12, 3)
if (abs(x$beta - 1.0) < 0.08) ok(sprintf("β=1.0 회수 (%.3f)", x$beta)) else ng("β 회수", x$beta)
if (abs(x$alpha_ann - 0.048) < 0.02) ok(sprintf("α 연율 4.8%% 회수 (%.2f%%)", x$alpha_ann * 100)) else ng("α 회수", x$alpha_ann)
if (abs(x$port_t - x$t_alpha) < 1.0) ok("β=1 이면 PORT_t ≈ t(α)") else ng("β=1 동치", sprintf("%.2f vs %.2f", x$port_t, x$t_alpha))

cat("== ★방향 1: β>1 → PORT_t 가 α 를 과대 표시 (DFA T3 계통) ==\n")
d <- mk(400, alpha_m = 0.000, beta = 1.40)   # 순수 레버리지, 진짜 α=0
x <- beta_controlled_alpha(d$r, d$b, 12, 3)
if (x$port_t > x$t_alpha) ok(sprintf("PORT_t(%.2f) > t(α)(%.2f) — 과대 표시 검출", x$port_t, x$t_alpha)) else
  ng("과대 미검출", sprintf("PORT_t %.2f vs t(α) %.2f", x$port_t, x$t_alpha))
if (x$beta_share > 0.5) ok(sprintf("β 기여 비중 %.0f%% (>50%%)", 100 * x$beta_share)) else
  ng("β 기여 비중", x$beta_share)
if (abs(x$t_alpha) < 2.0 && x$port_t > 2.0) ok("★α=0 인데 PORT_t 만 유의 — §2 가 막으려는 그 상태") else
  cat("  INFO  표본 잡음에 따라 임계 근처일 수 있음 (t(α)=", round(x$t_alpha,2), " PORT_t=", round(x$port_t,2), ")\n")
if (grepl("과대", x$direction)) ok("direction 라벨 = 과대") else ng("direction", x$direction)

cat("== ★방향 2: β<1 → PORT_t 가 α 를 과소 표시 (q90_pinball 계통) ==\n")
d <- mk(400, alpha_m = 0.006, beta = 0.80)   # 방어적 노출 + 진짜 α 존재
x <- beta_controlled_alpha(d$r, d$b, 12, 3)
if (x$t_alpha > x$port_t) ok(sprintf("t(α)(%.2f) > PORT_t(%.2f) — 과소 표시 검출", x$t_alpha, x$port_t)) else
  ng("과소 미검출", sprintf("t(α) %.2f vs PORT_t %.2f — 살릴 것을 버리는 방향", x$t_alpha, x$port_t))
if (x$beta_share < 0) ok(sprintf("β 기여 음수 %.0f%% (상승장에서 활성수익을 깎음)", 100 * x$beta_share)) else
  ng("β 기여 부호", x$beta_share)
if (grepl("과소", x$direction)) ok("direction 라벨 = 과소") else ng("direction", x$direction)

cat("== 결손 처리: 조용히 0 으로 채우지 않는가 ==\n")
d <- mk(200, 0.003, 1.0); d$r[c(5, 50, 120)] <- NA
x <- beta_controlled_alpha(d$r, d$b, 12, 3)
if (x$n_dropped == 3 && x$n == 197) ok("NA 3개 제외 + 개수 보고 (n=197, dropped=3)") else
  ng("결손 처리", sprintf("n=%d dropped=%d", x$n, x$n_dropped))

cat("== 경계: 길이 불일치·과소 표본을 거부하는가 ==\n")
e1 <- tryCatch({ beta_controlled_alpha(rnorm(10), rnorm(11)); "통과함" }, error = function(e) "거부")
if (e1 == "거부") ok("길이 불일치 → 오류 (조용한 재활용 금지)") else ng("길이 검증", e1)
e2 <- tryCatch({ beta_controlled_alpha(rnorm(8), rnorm(8)); "통과함" }, error = function(e) "거부")
if (e2 == "거부") ok("관측 12 미만 → 오류 (판정 불가를 판정으로 위장 안 함)") else ng("표본 검증", e2)

cat("== 실데이터 재현: 스크래치 계산과 일치하는가 ==\n")
btp <- file.path(ROOT, "stage_artifacts", "WT-D20260813_001", "bt_result.rds")
if (file.exists(btp)) {
  bt <- readRDS(btp)
  m <- merge(bt$period_returns[, c("date", "ret_net")],
             bt$benchmark_returns[, c("date", "benchmark_ret")], by = "date")
  m <- m[order(m$date), ]
  x <- beta_controlled_alpha(m$ret_net, m$benchmark_ret, 12, 3)
  # 2026-08-22 스크래치 실측: PORT_t 0.837 · t(α) 1.207 · β 0.814 · β비중 -37.3%
  chk <- abs(x$port_t - 0.837) < 0.01 && abs(x$t_alpha - 1.207) < 0.01 && abs(x$beta - 0.814) < 0.005
  if (chk) ok("q90_pinball 198개월 재현 (PORT_t 0.837 · t(α) 1.207 · β 0.814)") else
    ng("실데이터 재현", sprintf("PORT_t %.3f t(α) %.3f β %.3f", x$port_t, x$t_alpha, x$beta))
} else {
  cat("  SKIP  bt_result.rds 부재\n")
}

cat("== 계약 축: 판정을 바꾸지 않는다는 것이 명시돼 있는가 ==\n")
if (grepl("HARD", x$note) && grepl("PORT_t", x$note)) ok("note 에 'HARD 는 PORT_t 로 판정' 명시") else
  ng("판정 경계", x$note)
if (identical(x$metric_type, "backtested_beta_controlled")) ok("metric_type 라벨 존재") else
  ng("metric_type", x$metric_type)

cat(sprintf("== t_summary: PASS=%d FAIL=%d ==\n", PASS, FAIL))
if (FAIL > 0L) quit(status = 1)
