# run_02_ab_multifactor.R — C15 A/B 확장: `_recompute_alpha_asof.R` 이 읽는 **7팩터 전체**
# run_01: R05_Tail_Risk 는 24/24개월 값 완전 동일 → 치환 값-중립.
# 그러나 `_recompute_alpha_asof.R::rdf()` 는 core 4 + defense 3 을 읽는다. 팩터-수준 coverage
# 게이트(Pct >= coverage_min)와 정렬 창(12 vs 36)의 영향은 **팩터마다 다를 수 있다** —
# 특히 커버리지가 낮은 팩터는 커넥터에서 **통째로 탈락**할 수 있고 그건 산출 변화다.
suppressMessages({ library(data.table); library(arrow); library(dplyr) })
options(scipen=999)
setwd(Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
source("02_Infrastructure/config.R"); source("02_Infrastructure/factor_db/factor_db_connector.R")
OUT <- "stage_artifacts/c15_bypass_20260808"
FACS <- c("C01_SUE","C02_EPS_Chg_1m","C04_ESBR","C06_TP_Gap",
          "Q07_Earnings_Stability","M08_Residual_Mom","Q25_Ohlson_O")
avail <- sort(gsub("factor_db_(\\d{6})\\.parquet", "\\1", list.files(".cache/factor_db", pattern="^factor_db_\\d{6}\\.parquet$")))
samp <- avail[seq(max(1, length(avail)-11), length(avail))]   ## 최근 12개월
cat(sprintf("[표본] %d개월 %s~%s | 팩터 %d종\n", length(samp), samp[1], samp[length(samp)], length(FACS)))

R <- rbindlist(Filter(Negate(is.null), lapply(samp, function(ym) {
  dd <- as.Date(paste0(substr(ym,1,4), "-", substr(ym,5,6), "-01"))
  fp <- sprintf(".cache/factor_db/factor_db_%s.parquet", ym)
  f <- as.data.table(read_parquet(fp, col_select=c("Ticker","Factor_Name","Z_Score","Coverage")))
  ## A: rdf() 방식 (직접 read + Coverage 행필터) → 호출부에서 align(12)
  a_raw <- f[Factor_Name %in% FACS & Coverage==TRUE & !is.na(Z_Score), .(Ticker, Factor_Name, Z_Score)]
  if (!nrow(a_raw)) return(NULL)
  a_al <- as.data.table(tryCatch(align_factor_direction(copy(a_raw)[, sig_date := dd], .load_registry(),
                                                        sig_date=dd, min_ic_months=12L), error=function(e) NULL))
  if (is.null(a_al)) return(NULL)
  zca <- intersect(c("Z_Score_Aligned","Z_Score"), names(a_al))[1]
  A <- a_al[, .(Ticker, Factor_Name, zA = get(zca))]
  ## B: 커넥터
  b <- tryCatch(as.data.table(load_month_factors(dd, factor_names=FACS)), error=function(e) NULL)
  if (is.null(b)) return(data.table(ym=ym, Factor_Name="(전체)", n_A=nrow(A), n_B=0L, verdict="B 미산출"))
  zcb <- intersect(c("Z_Score_Aligned","Z_Score"), names(b))[1]
  B <- b[is.finite(get(zcb)), .(Ticker, Factor_Name, zB = get(zcb))]
  rbindlist(lapply(FACS, function(fc) {
    aa <- A[Factor_Name==fc]; bb <- B[Factor_Name==fc]
    if (!nrow(aa) && !nrow(bb)) return(NULL)
    if (!nrow(bb)) return(data.table(ym=ym, Factor_Name=fc, n_A=nrow(aa), n_B=0L,
                                     cor_rank=NA_real_, identical_vals=FALSE, verdict="★커넥터에서 탈락(coverage 게이트)"))
    if (!nrow(aa)) return(data.table(ym=ym, Factor_Name=fc, n_A=0L, n_B=nrow(bb),
                                     cor_rank=NA_real_, identical_vals=FALSE, verdict="직접-read 에 없음"))
    m <- merge(aa[, .(Ticker, zA)], bb[, .(Ticker, zB)], by="Ticker")
    if (nrow(m) < 10) return(data.table(ym=ym, Factor_Name=fc, n_A=nrow(aa), n_B=nrow(bb),
                                        cor_rank=NA_real_, identical_vals=FALSE, verdict="매칭 부족"))
    data.table(ym=ym, Factor_Name=fc, n_A=nrow(aa), n_B=nrow(bb),
               cor_rank=cor(m$zA, m$zB, method="spearman"),
               identical_vals=isTRUE(all.equal(m$zA, m$zB)),
               verdict=ifelse(isTRUE(all.equal(m$zA, m$zB)), "동일",
                       ifelse(cor(m$zA,m$zB,method="spearman") < 0, "★부호 반대", "값 상이")))
  }))
})), fill=TRUE)
cat("\n===== 팩터별 요약 (12개월 집계) =====\n")
S <- R[, .(개월=.N, 동일=sum(identical_vals, na.rm=TRUE),
           탈락=sum(grepl("탈락", verdict)), 부호반대=sum(grepl("부호", verdict)),
           rank중앙=round(median(cor_rank, na.rm=TRUE),4),
           nA중앙=round(median(n_A)), nB중앙=round(median(n_B))), by=Factor_Name][order(Factor_Name)]
print(S)
cat(sprintf("\n[판정] 전 팩터·전 월 동일: %s | 커넥터 탈락 발생: %s | 부호 반대: %s\n",
  all(R$identical_vals, na.rm=TRUE), any(grepl("탈락", R$verdict)), any(grepl("부호", R$verdict))))
cat(sprintf("[결론] %s\n", ifelse(all(R$identical_vals, na.rm=TRUE),
  "치환 값-중립 — `_recompute_alpha_asof.R` 도 안전하게 수리 가능",
  "★치환이 산출을 바꾸는 팩터 존재 — 해당 팩터는 개별 판정 필요")))
fwrite(R, file.path(OUT, "ab_multifactor.csv"))
