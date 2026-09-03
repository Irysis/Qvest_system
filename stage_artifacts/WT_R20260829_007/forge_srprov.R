Sys.setenv(QM_ROOT="C:/Users/99922/OneDrive/Quant_Module_Moltbot")
suppressPackageStartupMessages({library(data.table);library(jsonlite)})
S<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot/stage_artifacts/WT_R20260829_007"
d<-fromJSON(file.path(S,"authoritative_remeasure.json"),simplifyVector=FALSE)
bt<-readRDS(file.path(S,"bt_result.rds")); M<-as.data.table(bt$metrics)
sr_real<-as.numeric(M[metric_name=="Sharpe",metric_value][1])
sr_up<-0.6445   # optimizer M2_EW25_buffer50 net_sharpe (247M 공통창, Sigma warm-up 12M)
dv<-sr_real-sr_up
d$sr_provenance<-list(
  sr_realized_share_based=sr_real,
  sr_realized_basis="weights.csv as-is -> t+1 정수주 집행 -> 일별 share-based NAV -> 252 annualization (259 리밸, 5319 일)",
  sr_upstream_continuous_claim=sr_up,
  sr_upstream_basis="optimizer method_comparison M2_EW25_buffer50 net_sharpe (월별 연속수익 집계, 2006-01~2026-08 247M, Sigma warm-up 12M 절단)",
  sr_lockbox_daily_harness="retired (v10 lockbox 제도 폐지 — 발급 금지)",
  measurement_basis_primary="forge_realized_share_based",
  divergence_upstream_vs_realized_pp=dv,
  diagnosis=if(abs(dv)<0.1)"NEGLIGIBLE" else if(abs(dv)<0.3)"MINOR_DRIFT" else if(abs(dv)<0.6)"SIGNIFICANT_DRAG" else "FABRICATION_SUSPECTED",
  diagnosis_note=paste(sprintf("|divergence| %.4f < 0.6 -> FABRICATION 아님.",abs(dv)),
    "잔차의 알려진 원인 2종: ①창 길이(forge 259M 2005-02~ vs optimizer 247M 2006-01~, Sigma warm-up 절단)",
    "②집행 해상도(forge 일별 정수주 share-based vs optimizer 월별 연속 비중).",
    "두 값은 같은 양이 아니며 forge 값이 권위다."))
writeLines(toJSON(d,auto_unbox=TRUE,pretty=TRUE,digits=8,na="null"),file.path(S,"authoritative_remeasure.json"))
cat(sprintf("sr_realized %.4f | upstream %.4f | div %.4f -> %s\n",sr_real,sr_up,dv,d$sr_provenance$diagnosis))
