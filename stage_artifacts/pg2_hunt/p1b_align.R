## p1b — ★PG2 계열과 후보 패널의 날짜 규약 정렬 (추정 금지 — 벤치 값으로 실측)
## 두 계열 모두 KOSPI200 벤치를 갖는다. **벤치 값 자체를 지문으로** 써서 offset 을 찾는다.
## 1개월만 어긋나도 알파가 창조되거나 파괴된다([[reference-book-benchmark-alignment-realized-ym]]).
suppressPackageStartupMessages({ library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/pg2_hunt")
say  <- function(fmt, ...) { cat(sprintf(paste0("[p1b] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R"); source("02_Infrastructure/contracts/book_marginal.R")

B <- bm_load_incumbent()
M <- readRDS(file.path(OUT, "mkt.rds"))
CB <- as.data.table(M$bench)[, .(Date, BM_Ret)]
say("=== 입력 실측 ===")
say("  PG2 : %d행 · %s ~ %s · 날짜 예시 %s",
    nrow(B), min(B$date), max(B$date), paste(head(as.character(B$date),3), collapse=", "))
say("  후보: %d행 · %s ~ %s · 날짜 예시 %s",
    nrow(CB), min(CB$Date), max(CB$Date), paste(head(as.character(CB$Date),3), collapse=", "))

## ym 키로 후보 offset 을 -2..+2 개월 훑어 **벤치 값 일치율**로 판정
B[,  ym := as.integer(format(date, "%Y%m"))]
CB[, ym := as.integer(format(Date, "%Y%m"))]
say("=== ★offset 탐색 (벤치 값 지문) ===")
say("  %6s %8s %10s %12s %12s", "offset", "겹침", "일치(1e-8)", "평균절대차", "상관")
best <- NULL
for (k in -2:2) {
  C2 <- copy(CB)[, ym2 := ym + k]                       # 후보를 k개월 이동
  X <- merge(B[, .(ym, pg2 = benchmark_ret)], C2[, .(ym = ym2, cand = BM_Ret)], by = "ym")
  if (!nrow(X)) { say("  %+6d %8d %10s", k, 0L, "-"); next }
  d <- X$pg2 - X$cand
  mt <- sum(abs(d) < 1e-8); cr <- suppressWarnings(cor(X$pg2, X$cand))
  say("  %+6d %8d %10d %12.6f %12.4f", k, nrow(X), mt, mean(abs(d)), cr)
  if (is.null(best) || mt > best$match) best <- list(k = k, match = mt, n = nrow(X), cor = cr, mad = mean(abs(d)))
}
say("  ⇒ ★최적 offset = %+d (일치 %d/%d · 상관 %.4f · 평균절대차 %.6f)",
    best$k, best$match, best$n, best$cor, best$mad)

say("=== 판정 ===")
if (best$match >= best$n * 0.95) {
  say("  ★**동일 벤치 계열 확인** — offset %+d 개월로 정렬하면 값이 일치한다.", best$k)
  say("    ⇒ 정렬 규약: 후보 패널의 Date(ym) + %d = PG2 의 ym", best$k)
} else if (best$cor > 0.99) {
  say("  ★값은 다르나 상관 %.4f — **같은 지수의 다른 빈티지**다(이 저장소 IKS001/IKS200 전력).", best$cor)
  say("    ⇒ ΔIR 측정은 **PG2 벤치 단일 기준**으로 통일해야 한다. 후보 슬리브도 PG2 벤치로 재채점.")
} else {
  say("  ★★상관 %.4f — 다른 계열이다. 정렬 전 원인 규명 필요.", best$cor)
}

## 확정 정렬 맵 저장 — 모든 소비자가 이걸 쓴다 (선언 필드)
ALIGN <- list(
  candidate_ym_plus = best$k,
  match_rate = best$match / max(best$n, 1L),
  correlation = best$cor,
  mean_abs_diff = best$mad,
  n_overlap = best$n,
  rule = sprintf("candidate ym + %d = PG2 ym", best$k),
  bench_authority = "PG2 05_benchmark_returns.csv (KOSPI200) — 후보 슬리브도 이 벤치로 채점",
  measured_at = "2026-08-09")
saveRDS(ALIGN, file.path(OUT, "align.rds"))
jsonlite::write_json(ALIGN, file.path(OUT, "align.json"), auto_unbox = TRUE, pretty = TRUE, digits = NA)
say("=== align.rds / align.json 저장 ===")

## ★정렬 적용 후 배관 재검증 (양성 대조 하나만 — 정렬이 살아있는지)
say("=== 정렬 적용 재검증 ===")
say("  PG2 자신을 ym 기준으로 슬리브화 → ΔIR 0 이어야")
S <- B[, .(date, ret_net)]
r <- bm_delta_ir(S, weight = 0.20)
say("  겹침 %s · ΔIR %s", r$n_overlap, format(r$delta_ir))
