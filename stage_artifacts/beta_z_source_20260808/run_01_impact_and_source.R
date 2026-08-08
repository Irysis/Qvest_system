# run_01_impact_and_source.R — 칩 task_972fe292 ①③: z 원천 대조 + 소급 영향 실측
# ③ 소급 영향: 북 시계열에서 β 가 '무뎌진'(z 결측 → 무발화 가지) 달이 몇 개월이고 ret_net 에 얼마인가.
# ① 원천 판정 선행 측정: 동결 패널 z(북) vs factor_db live z(배포) 가 **vintage 차이인가 다른 계산인가**.
#    cor 0.712 는 vintage 로는 설명하기 어려운 크기 — 겹치는 구간에서 per-ticker 대조로 성격을 가른다.
suppressMessages({ library(data.table); library(arrow); library(dplyr) })
options(scipen=999)
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
source("02_Infrastructure/config.R"); source("02_Infrastructure/factor_db/factor_db_connector.R")
OUT <- "stage_artifacts/beta_z_source_20260808"; dir.create(OUT, showWarnings=FALSE, recursive=TRUE)

## ── ③ 무뎌진 달 특정 ──────────────────────────────────────────────
P <- fread("stage_artifacts/tilt_realign_20260808/p20_flag_spec_panel.csv")
P[, Date := as.Date(Date)]
blunt <- P[n_valid == 0L]
cat(sprintf("[③ 무뎌진 달] 전체 %d 신호일 중 z 전결측 **%d일**: %s\n", nrow(P), nrow(blunt),
            paste(as.character(blunt$Date), collapse=", ")))
cat(sprintf("   z 원천 패널 종점 = %s (그 이후 전부 결측)\n",
            as.character(max(P[n_valid > 0L]$Date))))

L <- fread("06_Registry/live_track/STR_1715_on_M4gAE_R05_noLayer4_PG2/live_book_series.csv")
L[, key := as.character(realized_ym)]
B <- merge(P[, .(key, Date, regime, z, q20, beta_spec, n_valid)],
           L[, .(key, beta_R05_book = beta_R05, m4_book = m4, ret_net, ret_orig)], by="key")
cat("\n[③ 무뎌진 달의 북 기록]\n")
print(B[n_valid == 0L, .(key, regime, beta_book = beta_R05_book, m4 = m4_book,
                         ret_net_pct = round(100*ret_net, 2), ret_orig_pct = round(100*ret_orig, 2))])

## 배포 실측 β (manifest) 와 대조
mf <- Sys.glob("05_Production/2.Factor_Model/2-4.STR_1715_on_M4gAE_R05_noLayer4_PG2/02_holdings_universe/*_M4gAE_manifest.json")
dep <- rbindlist(lapply(mf, function(f) {
  j <- jsonlite::fromJSON(f, simplifyVector=TRUE)
  data.table(as_of = as.Date(j$as_of), beta_dep = j$overlays$beta_R05_V5$value,
             gate = j$overlays$m4_ae_gate, invested = j$invested)
}))
dep[, key := format(as_of + 32, "%Y-%m")]
dep[, key := format(as.Date(paste0(format(as_of, "%Y-%m"), "-01")) + 32, "%Y-%m")]
C <- merge(B, dep, by="key", all.x=TRUE)[!is.na(beta_dep)]
cat("\n[③ 북 vs 배포 β 대조 (manifest 존재 구간)]\n")
print(C[, .(key, regime, 북_beta = beta_R05_book, 배포_beta = beta_dep,
            일치 = ifelse(abs(beta_R05_book - beta_dep) < 1e-9, "O", "★X"),
            ret_net_pct = round(100*ret_net, 2))])
gap <- C[abs(beta_R05_book - beta_dep) > 1e-9]
if (nrow(gap)) {
  gap[, ret_if_dep := ret_net * (beta_dep / pmax(beta_R05_book, 1e-9))]
  cat(sprintf("\n[③ 영향] 불일치 %d개월 | 북 기록 ret_net 합 %+.2f%% vs 배포 β 적용 시 %+.2f%% → 차이 %+.2f%%pt\n",
      nrow(gap), 100*sum(gap$ret_net), 100*sum(gap$ret_if_dep), 100*(sum(gap$ret_if_dep) - sum(gap$ret_net))))
  cat("  ※ β 는 노출 배수이므로 ret_net 을 비율로 환산(1차 근사, 비용항 제외 — 라벨: scaled_approx)\n")
} else cat("\n[③ 영향] 불일치 없음\n")

## ── ① z 원천 성격 판정 ────────────────────────────────────────────
frz <- as.data.table(read_parquet("stage_artifacts/WT_D20260512_003/alpha_scores_new.parquet"))
frz[, Date := as.Date(Date)]
frz <- frz[is.finite(R05_Tail_Risk_Z), .(Date, Ticker, z_frozen = R05_Tail_Risk_Z)]
cat(sprintf("\n[① 동결 패널] %s행 | %s ~ %s\n", format(nrow(frz), big.mark=","), min(frz$Date), max(frz$Date)))

reg <- .load_registry()
test_dates <- sort(unique(frz$Date))
test_dates <- test_dates[test_dates >= as.Date("2024-01-01")]
test_dates <- test_dates[seq(1, length(test_dates), length.out = min(8, length(test_dates)))]
cmp <- rbindlist(lapply(test_dates, function(dd) {
  f <- tryCatch(load_month_factors(dd, factor_names="R05_Tail_Risk"), error=function(e) NULL)
  if (is.null(f) || !nrow(f)) return(NULL)
  f <- as.data.table(f)
  if (!("Z_Score" %in% names(f)) && "Z_Score_Aligned" %in% names(f)) setnames(f, "Z_Score_Aligned", "Z_Score")
  if ("Coverage" %in% names(f)) f <- f[Coverage == TRUE]
  f <- f[is.finite(Z_Score)]
  fa <- as.data.table(tryCatch(align_factor_direction(copy(f)[, sig_date := dd], reg, sig_date=dd, min_ic_months=12L),
                               error=function(e) copy(f)))
  zc <- if ("Z_Score_Aligned" %in% names(fa)) "Z_Score_Aligned" else "Z_Score"
  live <- fa[, .(Ticker, z_live = get(zc))]
  m <- merge(frz[Date == dd, .(Ticker, z_frozen)], live, by="Ticker")
  if (nrow(m) < 30) return(NULL)
  data.table(Date = dd, n_frozen = nrow(frz[Date==dd]), n_live = nrow(live), n_match = nrow(m),
             cor = cor(m$z_frozen, m$z_live), cor_rank = cor(m$z_frozen, m$z_live, method="spearman"),
             mean_abs_diff = mean(abs(m$z_frozen - m$z_live)),
             sd_frozen = sd(m$z_frozen), sd_live = sd(m$z_live))
}), fill=TRUE)
cat("\n[① 동결 vs live per-ticker 대조 (표본 월)]\n"); print(cmp)
if (nrow(cmp)) cat(sprintf("\n[① 판정] 평균 cor %.3f (rank %.3f) | 티커 매칭 %.0f/%.0f | %s\n",
  mean(cmp$cor), mean(cmp$cor_rank), mean(cmp$n_match), mean(cmp$n_frozen),
  ifelse(mean(cmp$cor) > 0.95, "vintage 차이 수준 — 연장으로 통일 가능",
    ifelse(mean(cmp$cor) > 0.7, "★부분 일치 — 계산 정의가 다를 가능성(정규화·유니버스·winsor 등) 규명 필요",
           "★★사실상 다른 지표 — 어느 쪽이 정본인지 설계 판정 선행"))))
fwrite(cmp, file.path(OUT, "z_source_compare.csv"))
if (exists("C")) fwrite(C, file.path(OUT, "beta_book_vs_deploy.csv"))
