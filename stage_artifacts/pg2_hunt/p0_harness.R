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

say("=== 3. [★항등 함정 확인] active x1.5 슬리브 = ΔIR 정확히 0 이어야 ===")
say("    (IR = mean/sd 이므로 incumbent active 의 **스칼라 배수**는 분자·분모가 같이 커진다.")
say("     내 1차 설계는 이걸 '양성 대조' 라 불렀는데 **항등변환 = 정보 0** 이었다.)")
r3 <- bm_delta_ir(B[, .(date, ret_net = benchmark_ret + active * 1.5)], weight = 0.20)
say("  ΔIR %+.2e → %s", r3$delta_ir, if (abs(r3$delta_ir) < 1e-9) "PASS(항등 확인)" else "★FAIL")

say("=== 3b. [진짜 양성 대조] incumbent 와 **무상관**이고 IR 동등한 슬리브 = ΔIR > 0 이어야 ===")
say("    기전: ΔIR 은 오직 **분산 효과**로만 오른다 — 이것이 사냥의 표적이다.")
set.seed(7)
orth <- rnorm(nrow(B)); orth <- orth - as.numeric(lm(orth ~ B$active)$fitted.values)  # active 에 직교화
orth <- orth / sd(orth) * sd(B$active) + mean(B$active)                                # IR 을 incumbent 와 동등하게
r3b <- bm_delta_ir(B[, .(date, ret_net = benchmark_ret + orth)], weight = 0.20)
say("  슬리브 standalone IR %.3f (incumbent %.3f) · incumbent 와 상관 %+.4f",
    r3b$sleeve_standalone_ir, r3b$incumbent_ir_on_overlap, r3b$correlation_with_incumbent)
say("  ΔIR %+.4f · verdict %s → %s", r3b$delta_ir, r3b$verdict,
    if (r3b$delta_ir > 0) "PASS" else "★FAIL")

say("=== 3c. [경계] 같은 IR 이라도 **상관 1** 이면 ΔIR 0 — 직교성이 유일 레버임을 못박음 ===")
r3c <- bm_delta_ir(B[, .(date, ret_net = benchmark_ret + B$active)], weight = 0.20)
say("  상관 %+.3f → ΔIR %+.2e → %s", r3c$correlation_with_incumbent, r3c$delta_ir,
    if (abs(r3c$delta_ir) < 1e-9) "PASS" else "★FAIL")

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
