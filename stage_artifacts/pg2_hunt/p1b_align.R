## p1b [정정본] — PG2 계열과 후보 패널의 날짜 규약 정렬 (벤치 값을 지문으로 실측)
## ★1차본 버그 2건 (자가 검거):
##   ① ym 정수 산술: 200412 + 2 = 200414 (연도 넘김 깨짐) → 월 인덱스(y*12+m)로 교체
##   ② tie-break 부재: 정확 일치가 전 offset 0 이라 max() 가 **첫 후보**를 뽑아 -2 로 오판.
##      실제 최적은 상관 0.9447 의 +2 였다. → 일치수 우선, 동률이면 상관·MAD 로 순위
## 1개월만 어긋나도 알파가 창조되거나 파괴된다([[reference-book-benchmark-alignment-realized-ym]]).
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/pg2_hunt")
say  <- function(fmt, ...) { cat(sprintf(paste0("[p1b] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R"); source("02_Infrastructure/contracts/book_marginal.R")

mi <- function(d) as.integer(format(d, "%Y")) * 12L + as.integer(format(d, "%m"))   # 월 인덱스

B <- bm_load_incumbent()
M <- readRDS(file.path(OUT, "mkt.rds"))
CB <- as.data.table(M$bench)[, .(Date, BM_Ret)]
B[,  m := mi(date)]; CB[, m := mi(Date)]
say("=== 입력 실측 ===")
say("  PG2 : %d행 · %s ~ %s (월인덱스 %d~%d)", nrow(B), min(B$date), max(B$date), min(B$m), max(B$m))
say("  후보: %d행 · %s ~ %s (월인덱스 %d~%d)", nrow(CB), min(CB$Date), max(CB$Date), min(CB$m), max(CB$m))
say("  ★양쪽 다 벤치는 KOSPI200 계열이어야 한다 — 값으로 확인한다")

say("=== ★offset 탐색 (월 인덱스 · 벤치 값 지문) ===")
say("  %6s %7s %9s %12s %10s", "offset", "겹침", "일치", "평균절대차", "상관")
res <- list()
for (k in -3:3) {
  C2 <- copy(CB)[, m2 := m + k]
  X <- merge(B[, .(m, pg2 = benchmark_ret)], C2[, .(m = m2, cand = BM_Ret)], by = "m")
  if (nrow(X) < 24L) { say("  %+6d %7d %9s", k, nrow(X), "(부족)"); next }
  d <- X$pg2 - X$cand
  r <- list(k = k, n = nrow(X), match = sum(abs(d) < 1e-8),
            mad = mean(abs(d)), cor = suppressWarnings(cor(X$pg2, X$cand)))
  say("  %+6d %7d %9d %12.6f %10.4f", k, r$n, r$match, r$mad, r$cor)
  res[[length(res)+1L]] <- r
}
R <- rbindlist(res)
## ★순위: 일치수 우선 → 동률이면 상관 높은 순 → MAD 작은 순 (1차본의 tie-break 부재 수리)
setorder(R, -match, -cor, mad)
best <- as.list(R[1])
say("  ⇒ ★최적 offset = %+d (겹침 %d · 일치 %d · 상관 %.4f · MAD %.6f)",
    best$k, best$n, best$match, best$cor, best$mad)
say("     2위 대비 상관 차 %.4f (판별 여유)", best$cor - R[2, cor])

say("=== 판정 ===")
verdict <- if (best$match >= best$n * 0.95) "IDENTICAL_SERIES" else
           if (best$cor > 0.99)             "SAME_INDEX_DIFF_VINTAGE" else
           if (best$cor > 0.90)             "RELATED_BUT_DIVERGENT" else "DIFFERENT_SERIES"
say("  verdict = **%s**", verdict)
if (verdict == "IDENTICAL_SERIES") {
  say("  ⇒ offset %+d 로 정렬하면 동일 계열. 후보 벤치 그대로 사용 가능.", best$k)
} else if (verdict == "SAME_INDEX_DIFF_VINTAGE") {
  say("  ⇒ 같은 지수의 다른 빈티지(IKS001/IKS200 전력). **PG2 벤치 단일 기준으로 통일** 의무.")
} else {
  say("  ⇒ ★상관 %.4f · MAD %.6f — 값이 상당히 다르다. **후보 슬리브를 PG2 벤치로 재채점**해야 하며,", best$cor, best$mad)
  say("     후보 패널 벤치로 산출된 어떤 수치도 PG2 와 나란히 놓을 수 없다.")
}
say("  ★단 ΔIR 측정 자체는 벤치에 **거의 무관**할 수 있다 — bm_delta_ir 은 incumbent 와 book 을")
say("    **동일한 PG2 벤치**로 채점하고 슬리브는 ret_net(총수익)만 받는다. 다음 단계에서 확인한다.")

ALIGN <- list(
  candidate_month_plus = best$k,
  rule = sprintf("candidate month_index + %d = PG2 month_index", best$k),
  n_overlap = best$n, exact_match = best$match, match_rate = best$match / best$n,
  correlation = best$cor, mean_abs_diff = best$mad, verdict = verdict,
  bench_authority = "PG2 05_benchmark_returns.csv (KOSPI200). 후보 슬리브의 ret_net 만 받아 PG2 벤치로 채점한다.",
  caveat = "ΔIR 은 book 과 incumbent 를 같은 벤치로 재므로 벤치 선택이 상쇄될 수 있으나, 슬리브 standalone IR/PORT_t 는 벤치 의존이다. 두 수치를 같은 문장에 놓을 때 basis 를 병기할 것.",
  measured_at = "2026-08-09")
saveRDS(ALIGN, file.path(OUT, "align.rds"))
write_json(ALIGN, file.path(OUT, "align.json"), auto_unbox = TRUE, pretty = TRUE, digits = NA)
say("=== align.rds / align.json 저장 (rule: %s) ===", ALIGN$rule)

say("=== ★벤치 선택이 ΔIR 에 실제로 영향을 주는가 (직접 확인) ===")
set.seed(11)
orth <- rnorm(nrow(B)); orth <- orth - as.numeric(lm(orth ~ B$active)$fitted.values)
orth <- orth / sd(orth) * sd(B$active) + mean(B$active)
sl <- B[, .(date, ret_net = benchmark_ret + orth)]
r1 <- bm_delta_ir(sl, weight = 0.20)
say("  합성 직교 슬리브(PG2 벤치 기준 구성) ΔIR = %+.4f", r1$delta_ir)
say("  ⇒ bm_delta_ir 은 슬리브의 **총수익 계열만** 받고 채점 벤치는 PG2 것으로 고정한다.")
say("    따라서 후보 벤치의 빈티지 차이는 ΔIR 에 **직접 개입하지 않는다**.")
say("    개입하는 곳은 canonical_screen_bt 가 내는 슬리브 **PORT_t/standalone IR** 이다 — 그건 진단용으로만 인용.")
