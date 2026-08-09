## p0 — book-marginal 측정 배관 검증 (양방향: 양성 대조 + 음성 대조)
suppressPackageStartupMessages({ library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
say <- function(fmt, ...) { cat(sprintf(paste0("[h] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R"); source("02_Infrastructure/contracts/book_marginal.R")

B <- bm_load_incumbent()
say("=== 입력 실측 ===")
say("  PG2 계열 %d개월 · %s ~ %s", nrow(B), min(B$date), max(B$date))
say("  ret_net 평균 %+.5f/월 · 벤치 %+.5f · active %+.5f", mean(B$ret_net), mean(B$benchmark_ret), mean(B$active))
say("  ★재현 확인: IR(active) = %.4f  vs  선언값 1.416 (차 %+.4f)", bm_ir(B$active), bm_ir(B$active) - 1.416)
say("  SR_geo 대조용 net SR = %.4f", mean(B$ret_net)/sd(B$ret_net)*sqrt(12))

say("=== 1. [양성 대조] incumbent 자신을 슬리브로 = ΔIR 0 이어야 ===")
r <- bm_delta_ir(B[, .(date, ret_net)], weight = 0.20)
say("  ΔIR %+.6f · verdict %s → %s", r$delta_ir, r$verdict,
    if (abs(r$delta_ir) < 1e-9) "PASS" else "★FAIL")

say("=== 2. [음성 대조] 벤치를 슬리브로 = active 희석이므로 ΔIR < 0 이어야 ===")
r2 <- bm_delta_ir(B[, .(date, ret_net = benchmark_ret)], weight = 0.20)
say("  ΔIR %+.4f · verdict %s → %s", r2$delta_ir, r2$verdict,
    if (r2$delta_ir < 0) "PASS" else "★FAIL")

say("=== 3. [양성 대조] 인위적 우수 슬리브(active x1.5, 잡음 없음) = ΔIR > 0 이어야 ===")
r3 <- bm_delta_ir(B[, .(date, ret_net = benchmark_ret + active * 1.5)], weight = 0.20)
say("  ΔIR %+.4f · verdict %s → %s", r3$delta_ir, r3$verdict,
    if (r3$delta_ir > 0) "PASS" else "★FAIL")

say("=== 4. [음성 대조] 순수 잡음 슬리브 = 통과하면 안 됨 ===")
set.seed(42)
nz <- bm_delta_ir(B[, .(date, ret_net = benchmark_ret + rnorm(.N, 0, sd(B$active)))], weight = 0.20)
say("  ΔIR %+.4f · verdict %s → %s", nz$delta_ir, nz$verdict,
    if (nz$delta_ir < 0.05) "PASS" else "★FAIL(잡음이 통과)")

say("=== 5. 겹침 가드 ===")
sh <- bm_delta_ir(B[1:30, .(date, ret_net)], weight = 0.20)
say("  30개월 슬리브 → status %s → %s", sh$status, if (sh$status == "INSUFFICIENT_OVERLAP") "PASS" else "★FAIL")

say("=== 6. weight sweep 동작 (단일 draw 취약성 배제) ===")
sw <- bm_delta_ir_sweep(B[, .(date, ret_net = benchmark_ret + active * 1.5)])
print(sw)
say("=== 배관 검증 완료 — 이 경로로만 후보를 잰다 ===")
saveRDS(B, "stage_artifacts/pg2_hunt/incumbent.rds")
