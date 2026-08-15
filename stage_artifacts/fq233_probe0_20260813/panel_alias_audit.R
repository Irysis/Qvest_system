## Lane A 패널 alias 감사 — 331피처 = 정본 320 + alias 11 인가, 그 11종은 진짜 중복인가
## 왜: 연결자가 "정본과 함께 등재된 alias 11종 · dedup=FALSE 기본이라 지금은 중복 투표한다" 고 경고했다.
##     ML 선별에서 중복 피처는 ①중요도 분산 ②정규화 왜곡을 낳으므로 **사전등록 시점에 결정**해야 한다.
##     여기서는 드롭하지 않고 **실측 + 매니페스트 고정**만 한다(arm 이 결정적으로 선택하도록).
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)})
OUT <- "stage_artifacts/fq233_probe0_20260813"

pan <- as.data.table(read_parquet(file.path(OUT, "lane_a_feature_panel.parquet")))
meta_cols <- c("anchor", "sig_date", "Ticker", "fwd_ret_1m")
feats <- setdiff(names(pan), meta_cols)
cat(sprintf("패널: %d행 · 피처 %d종 · %d개월\n", nrow(pan), length(feats), uniqueN(pan$sig_date)))

reg <- fromJSON("02_Infrastructure/factor_db/factor_registry.json", simplifyVector = FALSE)
alias <- list()
for (k in names(reg)) {
  dd <- reg[[k]]$dedup
  if (is.null(dd)) next
  if (identical(dd$role %||% "", "alias") && nzchar(dd$canonical %||% "")) {
    alias[[k]] <- dd$canonical
  }
}
`%||%` <- function(a,b) if (is.null(a)) b else a
cat(sprintf("\nregistry alias 선언: %d종\n", length(alias)))

cat("\n=== alias ↔ canonical 실측 상관 (패널 내 동시 존재분) ===\n")
rows <- list()
for (a in names(alias)) {
  cn <- alias[[a]]
  if (!(a %in% feats)) { rows[[a]] <- list(alias=a, canonical=cn, in_panel=FALSE, cor=NA_real_,
                                           identical_frac=NA_real_, note="패널에 alias 없음"); next }
  if (!(cn %in% feats)) { rows[[a]] <- list(alias=a, canonical=cn, in_panel=TRUE, cor=NA_real_,
                                            identical_frac=NA_real_, note="패널에 canonical 없음"); next }
  x <- pan[[a]]; y <- pan[[cn]]
  ok <- is.finite(x) & is.finite(y)
  r  <- if (sum(ok) > 100) cor(x[ok], y[ok]) else NA_real_
  idf <- if (sum(ok) > 0) mean(abs(x[ok]-y[ok]) < 1e-9) else NA_real_
  rows[[a]] <- list(alias=a, canonical=cn, in_panel=TRUE, cor=r, identical_frac=idf,
                    note=if (!is.na(r) && r > 0.999) "중복 확정" else "중복 아님 — 드롭 금지")
  cat(sprintf("  %-32s -> %-28s cor=%s  완전일치=%s  %s\n", a, cn,
              if (is.na(r)) "NA" else sprintf("%+.4f", r),
              if (is.na(idf)) "NA" else sprintf("%.3f", idf), rows[[a]]$note))
}

dt <- rbindlist(lapply(rows, as.data.table), fill = TRUE)
dup <- dt[in_panel == TRUE & !is.na(cor) & cor > 0.999, alias]
keep <- setdiff(feats, dup)
cat(sprintf("\n★중복 확정 alias %d종 · 드롭 시 잔여 피처 %d종\n", length(dup), length(keep)))
if (length(dt[in_panel == TRUE & !is.na(cor) & cor <= 0.999, alias]))
  cat("  ⚠alias 선언인데 상관 낮음(드롭 금지):",
      paste(dt[in_panel==TRUE & !is.na(cor) & cor<=0.999, alias], collapse=", "), "\n")

man <- list(
  panel = "lane_a_feature_panel.parquet",
  built_at = "2026-08-13",
  n_rows = nrow(pan), n_months = uniqueN(pan$sig_date), n_features_raw = length(feats),
  target = "fwd_ret_1m",
  pit = paste0("load_month_factors + Z_Score_Aligned (C13/C15) · 팩터 Date +1개월 스탬프(앵커 규약) · ",
               "유니버스 K200∪KQ150 플래그 참 · ym 키 조인 · forward = build_monthly_forward_returns 정본"),
  alias_audit = dt,
  dedup_recommendation = list(
    drop = dup, n_after_drop = length(keep),
    rationale = paste0("연결자 기본 dedup=FALSE 이므로 패널에 alias 가 정본과 함께 실려 있다. ",
                       "ML 선별에서 중복 피처는 중요도 분산·정규화 왜곡을 낳는다. ",
                       "★arm 사전등록에서 drop 여부를 명시할 것 — 측정 후 바꾸면 사양 변경이다."),
    default_for_lane_a = "drop (선별/랭킹 용도 = 연결자 권고 dedup=TRUE 와 동치)"
  ),
  caveat = "본 감사는 중복 여부만 판정한다. 드롭 자체는 수행하지 않았다(패널 원본 불변)."
)
write_json(man, file.path(OUT, "lane_a_panel_manifest.json"), auto_unbox = TRUE, pretty = TRUE, digits = 8)
cat(sprintf("\n저장: %s\n", file.path(OUT, "lane_a_panel_manifest.json")))
