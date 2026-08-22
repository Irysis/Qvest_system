# alpha_scores.parquet (정렬월 유니버스-제한 score) + alpha_validation.json
suppressWarnings(suppressMessages({library(arrow); library(data.table); library(jsonlite)}))
root <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
Sys.setenv(CLAUDE_PROJECT_DIR=root, QM_ROOT=root)
WT <- file.path(root, "qepm/mailbox/worktask/WT-D20260822_012")
SA <- file.path(root, "stage_artifacts/WT_D20260822_012")
dir.create(SA, showWarnings = FALSE, recursive = TRUE)
res <- readRDS(file.path(WT, "_measure_res.rds"))

# regime 재구성 (score 패널에 aligned/direction 라벨 부착)
mb <- as.data.table(read_parquet(file.path(root,".cache/macro_beta_scores.parquet")))
setnames(mb,"Score","score"); mb[,Date:=as.Date(Date)]
fm <- as.data.table(read_parquet(file.path(root,".cache/fred_macro.parquet"))); fm[,Date:=as.Date(Date)]
sig_dates <- sort(unique(mb$Date))
sn <- c("Term_Spread","VIX","KRW_USD")
mac <- fm[Series%in%sn & Frequency=="d",.(Date,Series,Value)]
mw <- dcast(mac,Date~Series,value.var="Value"); setorder(mw,Date)
for(cc in sn){ v<-mw[[cc]]; if(anyNA(v)) mw[[cc]]<-nafill(v,type="locf") }
mw[,d20_ts:=shift(Term_Spread,1)-shift(Term_Spread,21)]
mw[,d20_vix:=shift(VIX,1)-shift(VIX,21)]
mw[,d20_krw:=shift(KRW_USD,1)-shift(KRW_USD,21)]
lab_at<-function(rd){sub<-mw[Date<=rd&!is.na(d20_ts)&!is.na(d20_vix)&!is.na(d20_krw)]; if(!nrow(sub))return(data.table(d20_ts=NA_real_,d20_vix=NA_real_,d20_krw=NA_real_)); sub[.N,.(d20_ts,d20_vix,d20_krw)]}
reg<-data.table(Date=sig_dates,rbindlist(lapply(sig_dates,lab_at)))
sgn<-function(x)fifelse(x>0,1L,fifelse(x<0,-1L,0L))
reg[,s1:=sgn(d20_ts)][,s2:=sgn(d20_vix)][,s3:=sgn(d20_krw)]
reg[,aligned:=(s1!=0L)&(s2!=0L)&(s3!=0L)&(s1==s2)&(s2==s3)]
reg[,regime_direction:=fifelse(!aligned,"mixed",fifelse(s1>0,"up","down"))]

# 유니버스 제한 (returns_dt 키) — RAWDATA 멤버십으로 근사(K200|KQ150)
raw <- as.data.table(read_parquet(file.path(root,".cache/RAWDATA.parquet"),
  col_select=c("Date","Ticker","K200","KQ150"))); raw[,Date:=as.Date(Date)]
univ <- unique(raw[(K200==TRUE|KQ150==TRUE), .(Date,Ticker)])
mbu <- merge(mb[!is.na(score)], univ, by=c("Date","Ticker"))
scores_out <- merge(mbu, reg[,.(Date,aligned,regime_direction,d20_ts,d20_vix,d20_krw)], by="Date")
scores_out <- scores_out[, .(Date, Ticker, score, aligned, regime_direction, d20_ts, d20_vix, d20_krw)]
write_parquet(scores_out, file.path(SA, "alpha_scores.parquet"))
cat("alpha_scores rows:", nrow(scores_out), " → ", file.path(SA,"alpha_scores.parquet"), "\n")

# alpha_validation.json
e1 <- res$E1_primary
val <- list(
  wt_id="WT-D20260822_012", fq_id="FQ-245",
  metric_type="canonical_screen", tier="screen_diagnostic",
  produced_by="alpha-research", produced_at=format(Sys.time(),"%Y-%m-%dT%H:%M:%S%z"),
  ic_series = list(
    note = "E0 조건부 rank-IC advisory (선별 권위 아님). PRIMARY = PORT_t.",
    unconditional_ic_prior = -0.0025,
    unconditional_port_t_prior = -1.265
  ),
  portfolio_alpha_t = list(
    E1_aligned_pooled = round(e1$port_t_nw3,4),
    S1_up_only = round(res$S1_up_only$port_t_nw3,4),
    r1_clean_2016 = round(res$r1_clean$port_t_nw3,4),
    note = "portfolio-alpha t (NW lag-3, canonical_screen). rank-IC t 아님. 3 arm 전부 음(-)."
  ),
  net_of_cost = list(
    cost_bps_oneway = 15, cost_model_version = "v2.4_kr_retail_15bps",
    E1_information_ratio = round(e1$information_ratio,4),
    E1_active_return_mean_annual_net = round(e1$active_return_mean_annual,4),
    note = "모든 수치 net-of-cost(15bps). gross 단독 보고 없음."
  ),
  uncertainty = list(
    verdict_with_power_external_sd = e1$verdict_with_power_external_sd,
    required_annual_t2 = round(e1$required_annual_t2,4),
    reachable_ceiling_port_t = round(e1$reachable_ceiling_port_t,2),
    final_label = "NULL_WITH_NEGATIVE_POINT_ESTIMATE",
    note = "부호 음(-) 앵커. 완전예지 상한 +17.15 로 창 도달 가능 → 미결 아님."
  ),
  economic_rationale = paste0("정렬국면(3채널 동부호 매크로 충격)서 score(Σβ·δ)가 일관 충격에 지배되어 횡단면 선별 유효 회복 가설. ",
    "실측: E1 −12.4%/yr(음-) — 가설 방향(양+) 성립 아님. 기전 부수관측(F-flow 전달·MDD 방어·정합강도 단조) 모두 미지지."),
  redundancy_cluster_id = "macro_conditional_selection (macro-beta family 선례 0 — hypothesis_index 미탐색. regime-timing 계열과 구분: 선별 유효성 조건화, 노출 크기 아님)",
  cor_vs_admitted = list(note = "E1 음(-) NULL 이라 admitted 대비 상관 산출 실익 없음(book 기여 후보 아님). standalone screen tier NULL."),
  ax001_v2_defensive = list(
    applicable = FALSE,
    note = "방어형 팩터 아님(정렬국면 조건부 선별). aligned_down 42월서 MDD 방어 실패(−59.5%)로 조건부 crisis_alpha 도 부재."
  ),
  dsr = list(applicable = FALSE, selection_type = "single_prereg",
             note = "config argmax 없음 — DSR 게이트 비발동(진단 산출도 단일 config 라 무의미)."),
  pit_checks = list(
    assert_overlay_pit = "PASS", lag1_collapse = FALSE,
    strict_pit_inflation = 0.0, macro_freq_d_enforced = TRUE,
    delta20_shift1 = TRUE, macro_regime_parquet_consumed = FALSE
  ),
  hard_gates_status = "NOT_EVALUATED (alpha 단계 — forge-authoritative 없음)",
  verdict = "NULL_WITH_NEGATIVE_POINT_ESTIMATE (screen_diagnostic)"
)
writeLines(toJSON(val, auto_unbox=TRUE, pretty=TRUE, null="null"),
           file.path(WT, "alpha_validation.json"))
cat("VALIDATION_DONE\n")
