#!/usr/bin/env Rscript
# fq193_coverage_decomp_20260809.R — F3 교락의 기전 판별: 시대 효과인가 **커버리지 함수**인가.
#
# ★배경: w_amt 필터가 전반 ΔIR -0.0634 / 후반 +0.2556 로 부호가 갈렸다(F3 발화, 단일 판정 금지).
#   겹침이 2020년 11% → 2026년 36% 로 추세적이므로, 후반 양(+)이 **효과가 아니라 커버 종목 수의 함수**일 수 있다.
#   판별: 월별 필터 효과를 커버 수(n_cov)로 층화한다. n_cov 에 단조면 커버리지 함수,
#   n_cov 통제 후에도 시대 차가 남으면 진짜 시대 효과.
# ★이 판별이 (A) 전구간 크롤(1.5일) 지불 여부의 입력이다.
# 월별 효과는 **gross active 차이**로 계산한다(비용은 2차) — metric_type=diagnostic.
suppressMessages({ library(data.table); library(arrow); library(jsonlite) })
setwd(Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
say <- function(...) cat(sprintf(...), "\n", sep = "")

mt  <- fromJSON("06_Registry/book_carrier/carrier_meta.json", simplifyVector = FALSE)
car <- as.data.table(read_parquet(as.character(mt$parquet)))
car[, `:=`(decision_date = as.Date(decision_date), eval_date = as.Date(eval_date))]
car <- car[selected == TRUE & !is.na(ret_fwd)]
car[, ym := as.integer(format(decision_date, "%Y%m"))]
P <- as.data.table(read_parquet("04_Research/method_frontier/fq002_contract_magnitude/panelx_B_corrected.parquet"))
P[, ym := as.integer(ym)]
shift_ym <- function(y){yr<-y%/%100L; mo<-y%%100L+1L; yr<-yr+(mo-1L)%/%12L; mo<-((mo-1L)%%12L)+1L; yr*100L+mo}
P[, ym_use := shift_ym(ym)]
C <- merge(car, P[, .(ym_use, Ticker, w_amt)], by.x=c("ym","Ticker"), by.y=c("ym_use","Ticker"), all.x=TRUE)
C[, covered := !is.na(w_amt)]
ovm <- sort(unique(C[covered==TRUE]$ym)); C <- C[ym>=min(ovm) & ym<=max(ovm)]; setorder(C, ym)
C[, drop_sig := FALSE]
C[covered==TRUE, drop_sig := frank(w_amt, ties.method="average")/.N <= (1/3), by=ym]

M <- C[, {
  w <- weight_strategy / sum(weight_strategy)
  r_base <- sum(w * ret_fwd)
  kp <- !drop_sig
  r_filt <- if (sum(w[kp]) > 0) sum(w[kp] * ret_fwd[kp]) / sum(w[kp]) else r_base
  .(n_held = .N, n_cov = sum(covered), n_drop = sum(drop_sig),
    r_base = r_base, r_filt = r_filt, diff = r_filt - r_base)
}, by = ym]
setorder(M, ym)
say("월 %d · 평균 커버 %.2f · 평균 제외 %.2f · 평균 효과 %+.5f (월 gross)",
    nrow(M), mean(M$n_cov), mean(M$n_drop), mean(M$diff))

mid <- M$ym[ceiling(nrow(M)/2)]
M[, era := ifelse(ym <= mid, "전반", "후반")]
M[, cov_t := cut(n_cov, breaks = quantile(n_cov, c(0, 1/3, 2/3, 1)), include.lowest = TRUE,
                 labels = c("低", "中", "高"))]

say("\n=== ① 커버 수 층별 월평균 효과 ===")
byc <- M[, .(n_months = .N, mean_cov = round(mean(n_cov),2), mean_drop = round(mean(n_drop),2),
             mean_diff = round(mean(diff), 5), t = round(mean(diff)/(sd(diff)/sqrt(.N)), 2)), by = cov_t][order(cov_t)]
print(byc)
mono <- all(diff(byc$mean_diff) > 0) || all(diff(byc$mean_diff) < 0)
say("  단조? %s", if (mono) "★예 — 커버리지 함수 시사" else "아니오")

say("\n=== ② 시대별 ===")
bye <- M[, .(n_months=.N, mean_cov=round(mean(n_cov),2), mean_diff=round(mean(diff),5),
             t=round(mean(diff)/(sd(diff)/sqrt(.N)),2)), by=era][order(era)]
print(bye)

say("\n=== ③ 2원: 커버층 × 시대 (커버 통제 후 시대 차가 남나) ===")
b2 <- M[, .(n=.N, mean_diff=round(mean(diff),5)), by=.(cov_t, era)][order(cov_t, era)]
print(dcast(b2, cov_t ~ era, value.var = c("n","mean_diff")))

say("\n=== ④ 회귀: diff ~ n_cov + era ===")
M[, era_bin := as.integer(era == "후반")]
fit <- lm(diff ~ n_cov + era_bin, data = M)
print(round(summary(fit)$coefficients, 5))
p_cov <- summary(fit)$coefficients["n_cov", 4]; p_era <- summary(fit)$coefficients["era_bin", 4]

verdict <- if (p_cov < 0.05 && p_era >= 0.05) "커버리지 함수 — n_cov 유의, 시대 더미 비유의. 후반 양(+)은 커버 증가의 산물." else
           if (p_era < 0.05 && p_cov >= 0.05) "시대 효과 — 커버 통제 후에도 시대 더미 유의." else
           if (p_cov < 0.05 && p_era < 0.05) "둘 다 유의 — 분리 불가(교락 지속)." else
           "둘 다 비유의 — 저검정력(n=79). 어느 쪽도 확립 불가."
say("\n★판별: %s", verdict)
say("  (A) 전구간 크롤 지불 함의: %s",
    if (grepl("^커버리지", verdict)) "EV 낮음 — 과거 구간은 커버가 더 적어 효과가 더 약할 것" else
    if (grepl("^시대", verdict)) "EV 높음 — 과거 구간이 독립 확인 표본" else
    "판정 유보 — 저검정력이면 크롤로도 못 가른다")

write(toJSON(list(schema="fq193_coverage_decomp_v1", date="20260809", metric_type="diagnostic",
  n_months=nrow(M), mean_effect=round(mean(M$diff),5),
  by_coverage=lapply(seq_len(nrow(byc)), function(i) as.list(byc[i])),
  by_era=lapply(seq_len(nrow(bye)), function(i) as.list(bye[i])),
  regression=list(p_n_cov=round(p_cov,4), p_era=round(p_era,4),
                  coef_n_cov=round(unname(coef(fit)["n_cov"]),6),
                  coef_era=round(unname(coef(fit)["era_bin"]),6)),
  monotone_in_coverage=mono, verdict=verdict), pretty=TRUE, auto_unbox=TRUE, na="null"),
  "stage_artifacts/paper_recharge/fq193_coverage_decomp_20260809.json")
say("\n저장: stage_artifacts/paper_recharge/fq193_coverage_decomp_20260809.json")
