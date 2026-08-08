# run_01_ab.R — 칩 task_deabaca2 ①②: C15 직접-read vs load_month_factors() A/B
#
# ① 치환 가능성 판정 (커넥터 내부 실독, factor_db_connector.R:236-283):
#   load_month_factors() = ⓐparquet read(.req_cols) ⓑas-of vintage 기록(필터 **이전**)
#     ⓒ**팩터-수준 coverage 게이트**(N_Covered/n_tickers >= coverage_min, 기본 0.05)
#     ⓓ행 필터 Coverage==TRUE & !is.na(Z_Score) ⓔ**align_factor_direction(sig_date, 기본 min_months=36)**
#     ⓕ반환 = Ticker/Factor_Name/**Z_Score_Aligned** (+ build_hash·asof·file attribute)
#   직접-read 판 = ⓓ만 하고 ⓒ·ⓑ·attribute 없음 + 정렬을 **min_ic_months=12** 로 호출부에서 수행.
#   ⇒ 치환은 **가능하나 값-중립이 아니다**: 정렬 창이 12 → 36 으로 바뀐다.
#
# ② 실측 A/B: 두 경로의 R05 z 를 per-ticker 로 대조하고, 하류 영향(top20 평균 z → zlt flag)까지 본다.
# ★이중정렬 금지 — load_month_factors 결과는 이미 정렬됨(오늘 내가 데인 지점).
suppressMessages({ library(data.table); library(arrow); library(dplyr) })
options(scipen=999)
setwd(Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
source("02_Infrastructure/config.R"); source("02_Infrastructure/factor_db/factor_db_connector.R")
OUT <- "stage_artifacts/c15_bypass_20260808"; dir.create(OUT, showWarnings=FALSE, recursive=TRUE)

asp <- as.data.table(read_parquet("stage_artifacts/WT_D20260425_010/alpha_scores.parquet")); asp[, Date := as.Date(Date)]
avail <- sort(gsub("factor_db_(\\d{6})\\.parquet", "\\1", list.files(".cache/factor_db", pattern="^factor_db_\\d{6}\\.parquet$")))
cat(sprintf("[factor_db] %d개월 %s ~ %s\n", length(avail), avail[1], avail[length(avail)]))
samp_ym <- avail[seq(max(1, length(avail)-23), length(avail))]   ## 최근 24개월
cat(sprintf("[표본] 최근 %d개월\n", length(samp_ym)))

R <- rbindlist(Filter(Negate(is.null), lapply(samp_ym, function(ym) {
  dd <- as.Date(paste0(substr(ym,1,4), "-", substr(ym,5,6), "-01"))
  fp <- sprintf(".cache/factor_db/factor_db_%s.parquet", ym)
  ## A: 직접-read + min_ic_months=12 (현행 production 방식)
  f <- as.data.table(read_parquet(fp, col_select=c("Ticker","Factor_Name","Z_Score","Coverage")))
  a_raw <- f[Factor_Name=="R05_Tail_Risk" & Coverage==TRUE & !is.na(Z_Score), .(Ticker, Factor_Name, Z_Score)]
  if (!nrow(a_raw)) return(NULL)
  a_in <- copy(a_raw)[, sig_date := dd]
  a_al <- as.data.table(tryCatch(align_factor_direction(a_in, .load_registry(), sig_date=dd, min_ic_months=12L),
                                 error=function(e) NULL))
  if (is.null(a_al) || !nrow(a_al)) return(NULL)
  zca <- intersect(c("Z_Score_Aligned","Z_Score"), names(a_al))[1]
  A <- a_al[, .(Ticker, zA = get(zca))]
  ## B: load_month_factors (정본, 내부 정렬 min_months=36 · 팩터-수준 coverage 게이트 포함)
  b <- tryCatch(as.data.table(load_month_factors(dd, factor_names="R05_Tail_Risk")), error=function(e) NULL)
  if (is.null(b) || !nrow(b)) return(data.table(ym=ym, n_A=nrow(A), n_B=0L, note="B 미산출(coverage 게이트 탈락 가능)"))
  zcb <- intersect(c("Z_Score_Aligned","Z_Score"), names(b))[1]
  B <- b[is.finite(get(zcb)), .(Ticker, zB = get(zcb))]
  m <- merge(A, B, by="Ticker")
  if (nrow(m) < 30) return(data.table(ym=ym, n_A=nrow(A), n_B=nrow(B), note="매칭 부족"))
  pt <- asp[Date == dd & !is.na(score_eff)]; setorder(pt, -score_eff)
  pk <- pt[seq_len(min(20L, nrow(pt)))]$Ticker
  data.table(ym=ym, n_A=nrow(A), n_B=nrow(B), n_match=nrow(m),
             cor_pear=cor(m$zA, m$zB), cor_rank=cor(m$zA, m$zB, method="spearman"),
             identical_vals = isTRUE(all.equal(m$zA, m$zB)),
             top20_A = mean(m$zA[m$Ticker %in% pk]), top20_B = mean(m$zB[m$Ticker %in% pk]),
             note = "")
})), fill=TRUE)
cat("\n===== A(직접-read+align12) vs B(load_month_factors, align36) =====\n")
print(R[, .(ym, n_A, n_B, n_match, pearson=round(cor_pear,4), rank=round(cor_rank,4),
            동일 = identical_vals, top20_A=round(top20_A,4), top20_B=round(top20_B,4))])
V <- R[is.finite(cor_pear)]
if (nrow(V)) {
  cat(sprintf("\n[요약] %d개월 | 값 완전동일 %d | rank 상관 중앙 %.4f | 부호 반대인 달 %d\n",
      nrow(V), sum(V$identical_vals, na.rm=TRUE), median(V$cor_rank), sum(V$cor_rank < 0)))
  cat(sprintf("[top20 평균 z] A 평균 %+.4f · B 평균 %+.4f · 두 계열 상관 %.4f\n",
      mean(V$top20_A), mean(V$top20_B), cor(V$top20_A, V$top20_B)))
  cat(sprintf("\n[② 판정] %s\n", ifelse(all(V$identical_vals, na.rm=TRUE),
    "치환해도 산출 불변 — 안전한 수리",
    ifelse(median(V$cor_rank) > 0.99, "★값은 다르나 순위 보존 — 하류(평균/문턱)에서 차이 발생 가능, 영향 측정 필요",
           "★★순위까지 갈림 — 치환은 산출을 바꾼다(정렬 창 12 vs 36 효과). 도훈 판단 필요"))))
}
fwrite(R, file.path(OUT, "ab_direct_vs_connector.csv"))
