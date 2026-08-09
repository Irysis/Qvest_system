## shard3_2arm.R — 팩터 샤드 3/8 을 2-arm(무조건부 / 국면파킹) 으로 전수 측정
## arm1 = 전 기간 (sleeve 전체 창)  ·  arm2 = FQ191 국면 라벨 73개월 창
## ★두 arm 은 창이 다르므로 서로 비교하지 않고 각각 문턱 0.05 와만 비교한다.
suppressPackageStartupMessages({ library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/pg2_hunt")
say  <- function(fmt, ...) { cat(sprintf(paste0("[s3] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/contracts/book_marginal.R")

A <- readRDS(file.path(OUT, "factor_long.rds"))
M <- readRDS(file.path(OUT, "mkt.rds"))
ret <- as.data.table(M$ret)[!is.na(Ret_1m)]
inc <- bm_load_incumbent()
Mru <- fread(file.path(ROOT, "stage_artifacts/FQ191/p1_rule.csv"))[, date := as.Date(date)]
Mru <- Mru[date < as.Date("2026-01-01")]

## ===== 입력 실측 (가정 금지) =====
say("=== 입력 실측 ===")
say("factor_long: %d행 · %d팩터 · 개월 %d · 범위 %s ~ %s",
    nrow(A), uniqueN(A$Factor_Name), uniqueN(A$Date),
    as.character(min(A$Date)), as.character(max(A$Date)))
say("ret        : %d행 · 개월 %d · 범위 %s ~ %s",
    nrow(ret), uniqueN(ret$Date), as.character(min(ret$Date)), as.character(max(ret$Date)))
say("incumbent  : %d행 · 범위 %s ~ %s · active mean %+.6f sd %.6f · IR %.4f",
    nrow(inc), as.character(min(inc$date)), as.character(max(inc$date)),
    mean(inc$active), sd(inc$active), bm_ir(inc$active))
say("regime rule: %d개월 · ON %d · 에피소드 %d · 범위 %s ~ %s",
    nrow(Mru), sum(Mru$regime), sum(diff(c(0L, as.integer(Mru$regime))) == 1L),
    as.character(min(Mru$date)), as.character(max(Mru$date)))

FN <- sort(unique(A$Factor_Name))
mine <- FN[seq_along(FN) %% 8 == 3]
say("=== 샤드 3/8: %d팩터 (전체 %d) ===", length(mine), length(FN))

WTS <- c(0.05, 0.10, 0.15, 0.20, 0.30)
rows <- list(); fails <- list(); t0 <- Sys.time()
csv_path <- file.path(OUT, "shard3_results.csv")

for (j in seq_along(mine)) {
  f <- mine[j]
  S <- A[Factor_Name == f, .(Date, Ticker, score = z)]
  r <- tryCatch(suppressWarnings(canonical_screen_bt(S, ret, as.data.table(M$bench), top_n = 25L,
        cost_bps_oneway = 15, liq_dt = as.data.table(M$liq), liq_min = 2e8,
        run_id = f, strategy_id = f, diag_dual_basis = FALSE,
        size_dt = as.data.table(M$size_dt))), error = function(e) e)
  if (inherits(r, "error")) {
    fails[[length(fails) + 1L]] <- data.table(factor = f, stage = "canonical_screen_bt",
                                              reason = conditionMessage(r)); next
  }
  PR <- as.data.table(r$period_returns)
  if (!nrow(PR)) {
    fails[[length(fails) + 1L]] <- data.table(factor = f, stage = "period_returns",
                                              reason = "0행"); next
  }

  ## ---- arm1: 무조건부 (전 기간) ----
  sw1 <- tryCatch(bm_delta_ir_sweep(PR[, .(date, ret_net)], weights = WTS), error = function(e) e)
  ## ---- arm2: 국면 파킹 (73개월) ----
  X <- merge(PR[, .(date, ret_net, benchmark_ret)], Mru[, .(date, regime)], by = "date")
  sw2 <- NULL
  if (nrow(X) > 0) {
    X[, sw := c(0L, abs(diff(as.integer(regime))))]
    X[, r2 := ifelse(regime, ret_net, benchmark_ret) - sw * 15 / 1e4]
    sw2 <- tryCatch(bm_delta_ir_sweep(X[, .(date, ret_net = r2)], weights = WTS), error = function(e) e)
  }

  g <- function(sw) {
    if (is.null(sw) || inherits(sw, "error")) return(list(ok = FALSE))
    if (all(sw$status != "MEASURED")) return(list(ok = FALSE, st = sw$status[1], n = sw$n[1]))
    k <- which.max(sw$delta_ir)
    list(ok = TRUE, n = sw$n[k], cor = sw$cor_inc[k], best = sw$delta_ir[k],
         w = sw$weight[k], all = all(sw$beats), nb = sum(sw$beats))
  }
  ## sleeve standalone IR (겹침 창에서) — w 무관, bm_delta_ir 로 1회
  d1 <- tryCatch(bm_delta_ir(PR[, .(date, ret_net)], weight = 0.20, incumbent = inc), error = function(e) NULL)
  d2 <- if (nrow(X) > 0) tryCatch(bm_delta_ir(X[, .(date, ret_net = r2)], weight = 0.20, incumbent = inc),
                                  error = function(e) NULL) else NULL
  a1 <- g(sw1); a2 <- g(sw2)

  if (!a1$ok && !a2$ok) {
    fails[[length(fails) + 1L]] <- data.table(factor = f, stage = "delta_ir",
      reason = paste0("arm1=", if (is.null(a1$st)) "ERR" else a1$st,
                      " arm2=", if (is.null(a2$st)) "ERR" else a2$st)); next
  }

  rows[[length(rows) + 1L]] <- data.table(
    factor = f,
    n_uncond = if (a1$ok) a1$n else NA_integer_,
    n_park   = if (a2$ok) a2$n else NA_integer_,
    cor_uncond = if (!is.null(d1)) d1$correlation_with_incumbent else NA_real_,
    ir_uncond  = if (!is.null(d1)) d1$sleeve_standalone_ir else NA_real_,
    dIR_uncond = if (a1$ok) a1$best else NA_real_,
    w_uncond   = if (a1$ok) a1$w else NA_real_,
    allw_uncond = if (a1$ok) a1$all else NA,
    cor_park = if (!is.null(d2)) d2$correlation_with_incumbent else NA_real_,
    ir_park  = if (!is.null(d2)) d2$sleeve_standalone_ir else NA_real_,
    dIR_park = if (a2$ok) a2$best else NA_real_,
    w_park   = if (a2$ok) a2$w else NA_real_,
    allw_park = if (a2$ok) a2$all else NA,
    win_uncond = if (!is.null(d1)) paste(d1$window, collapse = "~") else NA_character_,
    win_park   = if (!is.null(d2)) paste(d2$window, collapse = "~") else NA_character_
  )

  if (j %% 10 == 0) {
    fwrite(rbindlist(rows, fill = TRUE), csv_path)
    say("  ... %d/%d (%.1f분) 누적 %d행 · 실패 %d",
        j, length(mine), as.numeric(difftime(Sys.time(), t0, units = "mins")),
        length(rows), length(fails))
  }
}

D <- rbindlist(rows, fill = TRUE)
fwrite(D, csv_path)
F <- if (length(fails)) rbindlist(fails, fill = TRUE) else data.table()
if (nrow(F)) fwrite(F, file.path(OUT, "shard3_failures.csv"))

say("=== 완료: 측정 %d / 실패 %d / 샤드 %d ===", nrow(D), nrow(F), length(mine))
q <- function(x, p) as.numeric(quantile(x, p, na.rm = TRUE))
for (arm in c("uncond", "park")) {
  cc <- D[[paste0("cor_", arm)]]; ii <- D[[paste0("ir_", arm)]]; dd <- D[[paste0("dIR_", arm)]]
  say("[%s] n=%d · cor 중앙 %+.3f [%.3f, %.3f] max %+.3f · <0.2 %d건",
      arm, sum(is.finite(dd)), median(cc, na.rm=TRUE), q(cc,.25), q(cc,.75), max(cc, na.rm=TRUE),
      sum(cc < 0.2, na.rm=TRUE))
  say("[%s] IR 중앙 %+.3f [%.3f, %.3f] max %+.3f · >0.5 %d건",
      arm, median(ii, na.rm=TRUE), q(ii,.25), q(ii,.75), max(ii, na.rm=TRUE), sum(ii > 0.5, na.rm=TRUE))
  say("[%s] dIR 중앙 %+.4f [%.4f, %.4f] max %+.4f · 양수 %d · >=0.05 %d",
      arm, median(dd, na.rm=TRUE), q(dd,.25), q(dd,.75), max(dd, na.rm=TRUE),
      sum(dd > 0, na.rm=TRUE), sum(dd >= 0.05, na.rm=TRUE))
}
## 요구조건 지도 (해석해) — w=0.20 기준 필요 최소 슬리브 IR
req_ir <- function(rho, w = 0.20, ir_i = 1.4160, thr = 0.05) {
  ## book active = (1-w) a_i + w a_s ; IR_book = mean/sd*sqrt(12)
  ## sd_i = 1 정규화: mu_i = ir_i/sqrt(12); mu_s = ir_s/sqrt(12)*s_s
  ## 슬리브 sd 는 incumbent sd 와 같다고 두면(비율 1) 닫힌 형태:
  f <- function(ir_s) {
    mu <- (1 - w) * ir_i + w * ir_s
    sdv <- sqrt((1 - w)^2 + w^2 + 2 * w * (1 - w) * rho)
    mu / sdv - ir_i - thr
  }
  lo <- -5; hi <- 20
  if (f(lo) > 0) return(lo)
  if (f(hi) < 0) return(NA_real_)
  uniroot(f, c(lo, hi))$root
}
D[, req_uncond := vapply(cor_uncond, function(x) if (is.finite(x)) req_ir(x) else NA_real_, numeric(1))]
D[, req_park   := vapply(cor_park,   function(x) if (is.finite(x)) req_ir(x) else NA_real_, numeric(1))]
D[, short_uncond := req_uncond - ir_uncond]
D[, short_park   := req_park - ir_park]
D[, best_arm := ifelse(!is.finite(dIR_park) | (is.finite(dIR_uncond) & dIR_uncond >= dIR_park), "uncond", "parked")]
D[, best_dIR := pmax(dIR_uncond, dIR_park, na.rm = TRUE)]
fwrite(D, csv_path)
say("=== 요구조건 부족분 ===")
say("uncond 부족분 중앙 %+.3f · park 부족분 중앙 %+.3f",
    median(D$short_uncond, na.rm=TRUE), median(D$short_park, na.rm=TRUE))
say("=== top5 closest (best_dIR) ===")
print(head(D[order(-best_dIR), .(factor, best_arm, best_dIR, cor_uncond, ir_uncond,
                                 req_uncond, short_uncond, cor_park, ir_park, req_park, short_park)], 8))
say("=== 생존 (best_dIR >= 0.05) ===")
print(D[best_dIR >= 0.05])
say("=== shard3 완료 ===")
