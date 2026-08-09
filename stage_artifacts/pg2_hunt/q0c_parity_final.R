## q0c — 참 위상(k=+2, Oct-2008 폭락으로 독립 확인)에서 정밀 정합 판정 + 병합 배관 실측
suppressPackageStartupMessages({ library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
say <- function(fmt, ...) { cat(sprintf(paste0("[q0c] ", fmt, "\n"), ...)); flush.console() }
OUT <- file.path(ROOT, "stage_artifacts/pg2_hunt")

pg2_dir <- file.path(ROOT, "05_Production/2.Factor_Model",
                     "2-3.STR_1715_on_M4_R05_noLayer4_PG2/04_backtest_results")
BR <- fread(file.path(pg2_dir, "05_benchmark_returns.csv")); BR[, date := as.Date(date)]
PRp <- fread(file.path(pg2_dir, "03_period_returns.csv"))

say("=== 0. PG2 period_returns 컬럼/키 실측 (merge 배관 확인용) ===")
say("  컬럼: %s", paste(names(PRp), collapse=", "))
PRp[, date := as.Date(date)]
say("  %d행 · %s ~ %s · 일(day-of-month) 유일값 {%s}", nrow(PRp), min(PRp$date), max(PRp$date),
    paste(sort(unique(as.integer(format(PRp$date,"%d")))), collapse=","))
say("  PG2 벤치 일(day-of-month) 유일값 {%s}",
    paste(sort(unique(as.integer(format(BR$date,"%d")))), collapse=","))

P <- readRDS(file.path(ROOT, "stage_artifacts/WT_D20260809_001/p0_panels.rds"))
BC <- as.data.table(P$bench)[is.finite(BM_Ret)]
say("  후보 벤치 일(day-of-month) 유일값 {%s}",
    paste(sort(unique(as.integer(format(BC$Date,"%d")))), collapse=","))
say("  ★날짜 정확일치 교집합 = **%d** (bm_delta_ir 는 by='date' 정확병합)",
    length(intersect(as.character(PRp$date), as.character(BC$Date))))

## ---- 참 위상 k=+2 (후보 Date 월 + 2 = PG2 라벨 월) ----
A <- BR[, .(t = as.integer(format(date,"%Y"))*12L + as.integer(format(date,"%m")),
            pg2 = benchmark_ret)]
B <- BC[, .(t = as.integer(format(Date,"%Y"))*12L + as.integer(format(Date,"%m")) + 2L,
            cand = BM_Ret)]
X <- merge(A, B, by = "t")
X[, ym := sprintf("%04d-%02d", (t-1L) %/% 12L, (t-1L) %% 12L + 1L)]
X[, d := pg2 - cand]
setorder(X, t)

say("=== 1. 참 위상 k=+2 정밀 대조 ===")
say("  겹침 %d개월 (PG2 라벨 %s ~ %s)", nrow(X), min(X$ym), max(X$ym))
say("  상관 %.6f · 정확일치(|d|<1e-10) %d · 1e-6 이내 %d",
    cor(X$pg2, X$cand), sum(abs(X$d) < 1e-10), sum(abs(X$d) < 1e-6))
say("  ★불일치 **%d / %d (%.1f%%)**", sum(abs(X$d) >= 1e-6), nrow(X), 100*mean(abs(X$d) >= 1e-6))
say("  최대 절대차 %+.6f (%s) · 평균차 %+.6f/월 · sd(d) %.6f",
    max(abs(X$d)), X[which.max(abs(d)), ym], mean(X$d), sd(X$d))
say("  연율 평균차(arith x12) %+.4f%%p · 추적오차(sd(d)*sqrt12) %.4f%%p",
    100*mean(X$d)*12, 100*sd(X$d)*sqrt(12))

say("=== 2. 구간 분해 — 2026 이음매 vs 상시 정의차 ===")
X[, era := fifelse(ym >= "2025-11", "seam_2025_11+", "pre_2025_11")]
print(X[, .(n = .N, corr = cor(pg2, cand), mean_d = mean(d), sd_d = sd(d),
            max_abs = max(abs(d)), n_gt_5pct = sum(abs(d) > 0.05)), by = era])

say("=== 3. 연도별 절대차 ===")
print(X[, .(n = .N, mean_d = mean(d), max_abs = max(abs(d)),
            n_gt_3pct = sum(abs(d) > 0.03)), by = .(yr = substr(ym,1,4))][order(yr)])

say("=== 4. 청정 창 후보: 2025-10 까지로 축소 시 ===")
Xc <- X[ym <= "2025-10"]
say("  %d개월 · 상관 %.6f · 불일치 %d/%d · 최대차 %+.5f · 연율 평균차 %+.4f%%p · TE %.4f%%p",
    nrow(Xc), cor(Xc$pg2, Xc$cand), sum(abs(Xc$d) >= 1e-6), nrow(Xc),
    max(abs(Xc$d)), 100*mean(Xc$d)*12, 100*sd(Xc$d)*sqrt(12))
say("  ★축소해도 정확일치 %d 건 — 즉 **잔여 불일치는 이음매가 아니라 정의차**", sum(abs(Xc$d) < 1e-10))

say("=== 5. 선언 필드 대조 ===")
say("  PG2 05_benchmark_returns.csv: benchmark_id=%s · benchmark_name=%s",
    paste(unique(BR$benchmark_id), collapse="|"), paste(unique(BR$benchmark_name), collapse="|"))
say("  후보 bench 생성자 = build_monthly_forward_returns() → BM_Ret = **유니버스(K200∪KQ150) Size-가중 forward 수익 횡단면 평균**")
say("  canonical_screen_bt 는 이 계열에 benchmark_id='KOSPI200_total_return' 을 **하드코딩** 부여 (라벨 ≠ 실체)")

saveRDS(list(X = X, corr_full = cor(X$pg2, X$cand), corr_clean = cor(Xc$pg2, Xc$cand),
             n_mismatch = sum(abs(X$d) >= 1e-6), n = nrow(X),
             max_abs = max(abs(X$d)), mean_d = mean(X$d), te = sd(X$d)*sqrt(12)),
        file.path(OUT, "q0c_parity.rds"))
fwrite(X, file.path(OUT, "q0c_parity_detail.csv"))
say("=== q0c 완료 ===")
