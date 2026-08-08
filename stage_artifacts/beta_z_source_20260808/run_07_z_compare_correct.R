# run_07_z_compare_correct.R — z 원천 대조 **재측정** (앞선 run_01/04/05 는 이중정렬로 무효)
# ★내 측정 버그 확정: `load_month_factors()` 는 내부에서 이미 `align_factor_direction`(min_months=36)
#   을 적용해 **`Z_Score_Aligned` 만** 돌려준다(실측: 1차 호출 결과 컬럼 = Ticker, Factor_Name,
#   Z_Score_Aligned — Coverage·Z_Score 없음). 나는 그 위에 min_ic_months=12 로 **한 번 더 정렬**했고,
#   방어코드가 분기마다 다른 값을 잡아 run_01(+0.9999)과 run_05(−1.0000)의 부호가 갈렸다.
#   → 앞선 z 비교 수치(rank 상관·flag 일치율 88.9%)는 전부 **철회**하고 여기서 다시 잰다.
# 정본 사용법: load_month_factors 결과의 Z_Score_Aligned 를 **그대로** 쓴다(재정렬 금지).
suppressMessages({ library(data.table); library(arrow); library(dplyr) })
options(scipen=999)
setwd(Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
source("02_Infrastructure/config.R"); source("02_Infrastructure/factor_db/factor_db_connector.R")
OUT <- "stage_artifacts/beta_z_source_20260808"

asp <- as.data.table(read_parquet("stage_artifacts/WT_D20260425_010/alpha_scores.parquet")); asp[, Date := as.Date(Date)]
frz <- as.data.table(read_parquet("stage_artifacts/WT_D20260512_003/alpha_scores_new.parquet")); frz[, Date := as.Date(Date)]
P <- fread("stage_artifacts/tilt_realign_20260808/p20_flag_spec_panel.csv"); P[, Date := as.Date(Date)]
dates <- sort(unique(P[is.finite(z)]$Date))
samp <- dates[seq(1, length(dates), length.out = min(30, length(dates)))]

get_live <- function(dd) {
  f <- tryCatch(as.data.table(load_month_factors(dd, factor_names = "R05_Tail_Risk")), error = function(e) NULL)
  if (is.null(f) || !nrow(f)) return(NULL)
  zc <- intersect(c("Z_Score_Aligned", "Z_Score"), names(f))[1]   ## 재정렬하지 않는다
  if (is.na(zc)) return(NULL)
  f[is.finite(get(zc)), .(Ticker, z_live = get(zc))]
}
R <- rbindlist(Filter(Negate(is.null), lapply(samp, function(dd) {
  lv <- get_live(dd); if (is.null(lv)) return(NULL)
  fz <- frz[Date == dd & is.finite(R05_Tail_Risk_Z), .(Ticker, z_frozen = R05_Tail_Risk_Z)]
  if (nrow(fz) < 30) return(NULL)
  m <- merge(fz, lv, by = "Ticker"); if (nrow(m) < 30) return(NULL)
  pt <- asp[Date == dd & !is.na(score_eff)]; setorder(pt, -score_eff)
  pk <- pt[seq_len(min(20L, nrow(pt)))]$Ticker
  data.table(Date = dd, n_match = nrow(m),
             cor_rank = cor(m$z_frozen, m$z_live, method = "spearman"),
             cor_pear = cor(m$z_frozen, m$z_live),
             top20_frozen = mean(m$z_frozen[m$Ticker %in% pk]),
             top20_live   = mean(m$z_live[m$Ticker %in% pk]))
})), fill = TRUE)
R <- R[is.finite(top20_frozen) & is.finite(top20_live)]; setorder(R, Date)
cat(sprintf("[재측정] %d개월 (%s ~ %s)\n", nrow(R), min(R$Date), max(R$Date)))
cat("\n[per-ticker 상관 — 처음3/마지막5]\n")
print(rbind(head(R[, .(Date, n_match, rank = round(cor_rank,4), pearson = round(cor_pear,4))], 3),
            tail(R[, .(Date, n_match, rank = round(cor_rank,4), pearson = round(cor_pear,4))], 5)))
cat(sprintf("\n[요약] rank 상관 중앙 %.4f (min %.4f, max %.4f) | 부호 음수인 달 %d/%d\n",
            median(R$cor_rank), min(R$cor_rank), max(R$cor_rank), sum(R$cor_rank < 0), nrow(R)))

expq <- function(x, p = 0.20, mn = 12L) sapply(seq_along(x), function(i) if (i <= mn) NA_real_ else quantile(x[1:(i-1)], p, names = FALSE, na.rm = TRUE))
R[, `:=`(q_f = expq(top20_frozen), q_l = expq(top20_live))]
R[, `:=`(flag_f = is.finite(q_f) & top20_frozen < q_f, flag_l = is.finite(q_l) & top20_live < q_l)]
V <- R[is.finite(q_f) & is.finite(q_l)]
cat(sprintf("\n[flag 일치] %d개월 중 %d (%.1f%%) | 동결 발화 %d · live 발화 %d\n",
            nrow(V), sum(V$flag_f == V$flag_l), 100*mean(V$flag_f == V$flag_l), sum(V$flag_f), sum(V$flag_l)))
if (nrow(V[flag_f != flag_l])) print(V[flag_f != flag_l, .(Date, top20_frozen = round(top20_frozen,4), q_f = round(q_f,4), flag_f,
                                                           top20_live = round(top20_live,4), q_l = round(q_l,4), flag_l)])
cat(sprintf("\n[판정] 원천 교체 시 flag 불일치 %.1f%% → %s\n", 100*mean(V$flag_f != V$flag_l),
  ifelse(mean(V$flag_f != V$flag_l) < 0.10, "소급 영향 작음", "★소급 영향 있음 — 도훈 판단 필요")))
fwrite(R, file.path(OUT, "z_compare_corrected.csv"))
