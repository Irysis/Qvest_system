## q0 — ★벤치 정합 관문 (blocking)
## PG2 incumbent 벤치(05_benchmark_returns.csv) vs 후보 슬리브 벤치(p0_panels.rds$bench)
## 두 계열이 다르면 ΔIR 은 전량 오염된다. 이 저장소엔 IKS001→IKS200 / 2026 이음매 전력이 있다.
suppressPackageStartupMessages({ library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
say <- function(fmt, ...) { cat(sprintf(paste0("[q0] ", fmt, "\n"), ...)); flush.console() }

OUT <- file.path(ROOT, "stage_artifacts/pg2_hunt")

## ---------- 1. 입력 실측 : PG2 자기 벤치 ----------
pg2_dir <- file.path(ROOT, "05_Production/2.Factor_Model",
                     "2-3.STR_1715_on_M4_R05_noLayer4_PG2/04_backtest_results")
BR <- fread(file.path(pg2_dir, "05_benchmark_returns.csv"))
say("=== 입력 실측 A: PG2 05_benchmark_returns.csv ===")
say("  컬럼: %s", paste(names(BR), collapse=", "))
say("  %d행 · benchmark_id 유일값 {%s} · benchmark_name {%s}",
    nrow(BR), paste(unique(BR$benchmark_id), collapse="|"), paste(unique(BR$benchmark_name), collapse="|"))
BR[, date := as.Date(date)]
say("  날짜범위 %s ~ %s · 유일 ym %d개", min(BR$date), max(BR$date), uniqueN(format(BR$date, "%Y-%m")))
say("  benchmark_ret 범위 [%+.6f, %+.6f] · 평균 %+.6f · NA %d",
    min(BR$benchmark_ret), max(BR$benchmark_ret), mean(BR$benchmark_ret), sum(is.na(BR$benchmark_ret)))
say("  ★|ret|>0.25 인 월 %d건:", sum(abs(BR$benchmark_ret) > 0.25))
if (sum(abs(BR$benchmark_ret) > 0.25)) print(BR[abs(benchmark_ret) > 0.25, .(date, benchmark_ret)])

## ---------- 2. 입력 실측 : 후보 슬리브 벤치 ----------
mkt_p <- file.path(OUT, "mkt.rds")
if (file.exists(mkt_p)) {
  M <- readRDS(mkt_p); BC <- as.data.table(M$bench)
  src <- "stage_artifacts/pg2_hunt/mkt.rds$bench"
} else {
  say("★ mkt.rds 부재 (p1_build_panel.R 미실행) — 그 상류 원천 p0_panels.rds$bench 로 대체")
  P <- readRDS(file.path(ROOT, "stage_artifacts/WT_D20260809_001/p0_panels.rds"))
  say("  p0_panels.rds 요소: %s", paste(names(P), collapse=", "))
  BC <- as.data.table(P$bench)
  src <- "stage_artifacts/WT_D20260809_001/p0_panels.rds$bench (mkt.rds 의 원천)"
}
say("=== 입력 실측 B: 후보 슬리브 벤치 (%s) ===", src)
say("  컬럼: %s", paste(names(BC), collapse=", "))
say("  %d행", nrow(BC))
print(head(BC, 3)); print(tail(BC, 3))

## 컬럼 식별 (선언적)
bd <- names(BC)[which(tolower(names(BC)) %in% c("date","period","ym","return_ym"))[1]]
bc <- names(BC)[which(tolower(names(BC)) %in% c("bm_ret","benchmark_ret","bench_ret","ret","bm"))[1]]
if (is.na(bd) || is.na(bc)) stop("q0: 후보 벤치 컬럼 식별 실패 — ", paste(names(BC), collapse=","))
say("  식별: date=%s · ret=%s", bd, bc)
BC2 <- data.table(date = as.Date(BC[[bd]]), cand_ret = as.numeric(BC[[bc]]))
BC2 <- BC2[is.finite(cand_ret)]
say("  날짜범위 %s ~ %s · %d개월 · 평균 %+.6f · 범위 [%+.6f, %+.6f]",
    min(BC2$date), max(BC2$date), uniqueN(format(BC2$date,"%Y-%m")),
    mean(BC2$cand_ret), min(BC2$cand_ret), max(BC2$cand_ret))
say("  ★|ret|>0.25 인 월 %d건", sum(abs(BC2$cand_ret) > 0.25))
if (sum(abs(BC2$cand_ret) > 0.25)) print(BC2[abs(cand_ret) > 0.25])

## ---------- 3. ym 키로 병합 · 3개 위상 대조 ----------
A <- BR[, .(ym = format(date, "%Y-%m"), pg2_ret = benchmark_ret)]
B <- BC2[, .(ym = format(date, "%Y-%m"), cand_ret)]
stopifnot(!any(duplicated(A$ym)), !any(duplicated(B$ym)))

phase_test <- function(shift_k) {
  ## shift_k = 후보 벤치를 k 개월 **앞으로** 밀어 PG2 와 맞춤
  Bs <- copy(B); setorder(Bs, ym)
  Bs[, ym_key := shift(ym, n = shift_k, type = "lag")]
  X <- merge(A, Bs[!is.na(ym_key), .(ym = ym_key, cand_ret)], by = "ym")
  if (!nrow(X)) return(data.table(shift = shift_k, n = 0L, exact = NA_integer_,
                                  max_abs = NA_real_, corr = NA_real_, mean_diff = NA_real_))
  X[, d := pg2_ret - cand_ret]
  data.table(shift = shift_k, n = nrow(X),
             exact = sum(abs(X$d) < 1e-10),
             near  = sum(abs(X$d) < 1e-6),
             max_abs = max(abs(X$d)),
             corr = suppressWarnings(cor(X$pg2_ret, X$cand_ret)),
             mean_diff = mean(X$d))
}
say("=== 3. 위상 스캔 (라벨 위상 차이를 불일치로 오독하지 않기 위해) ===")
PH <- rbindlist(lapply(c(-1, 0, 1), phase_test), fill = TRUE)
print(PH)

best <- PH[which.max(ifelse(is.na(near), -1, near))]
say("  최적 위상 shift=%d (near-exact %d/%d)", best$shift, best$near, best$n)

## ---------- 4. 최적 위상에서 정밀 대조 ----------
k <- best$shift
Bs <- copy(B); setorder(Bs, ym); Bs[, ym_key := shift(ym, n = k, type = "lag")]
X <- merge(A, Bs[!is.na(ym_key), .(ym = ym_key, cand_ret)], by = "ym")
setorder(X, ym)
X[, d := pg2_ret - cand_ret]
X[, mism := abs(d) >= 1e-6]

say("=== 4. 정밀 대조 (shift=%d) ===", k)
say("  겹침 %d개월 (%s ~ %s)", nrow(X), min(X$ym), max(X$ym))
say("  ★불일치(|차|>=1e-6) **%d / %d 개월 (%.1f%%)**", sum(X$mism), nrow(X), 100*mean(X$mism))
say("  최대 절대차 %+.6f (해당월 %s)", max(abs(X$d)), X[which.max(abs(d)), ym])
say("  차이 평균 %+.6f/월 · sd %.6f", mean(X$d), sd(X$d))
## 연율 차이 = 산술 평균차 x 12 (자체합성 아님 — 단순 스케일 표기)
say("  연율화 평균차(arith x12) %+.4f%%p", 100*mean(X$d)*12)
say("  두 계열 상관 %.6f", cor(X$pg2_ret, X$cand_ret))

if (sum(X$mism)) {
  MM <- X[mism == TRUE]
  say("  불일치 구간: %s ~ %s", min(MM$ym), max(MM$ym))
  say("  불일치 연도 분포:")
  print(MM[, .(n = .N, max_abs = max(abs(d)), mean_d = mean(d)), by = .(yr = substr(ym,1,4))][order(yr)])
  say("  불일치 상위 12건 (|차| 내림):")
  print(head(MM[order(-abs(d)), .(ym, pg2_ret, cand_ret, d)], 12))
  ## 청정 구간 = 불일치가 하나도 없는 최장 연속 접두
  first_bad <- min(which(X$mism))
  say("  ★청정 접두 구간: %s ~ %s (%d개월)", X$ym[1], X$ym[max(1, first_bad-1)], first_bad - 1L)
}

fwrite(X, file.path(OUT, "q0_bench_parity_detail.csv"))
saveRDS(list(phase = PH, detail = X, shift = k,
             n_mismatch = sum(X$mism), n_overlap = nrow(X),
             max_abs = max(abs(X$d)), mean_d = mean(X$d)),
        file.path(OUT, "q0_bench_parity.rds"))
say("=== q0 완료 → q0_bench_parity.rds / q0_bench_parity_detail.csv ===")
