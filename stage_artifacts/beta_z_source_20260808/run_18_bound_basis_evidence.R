## run_18 — weight_bounds 0.20 이 어느 벡터 기준인지 **증거로** 좁힌다
## 논리: invested=1 인 달에는 두 해석이 일치한다. 그 달들에서 전략 비중이 0.20 에 **실제로 닿으면**
##       상한은 전략-집중도 제약으로 기능하고 있다는 뜻(구속적) → 저노출 달에 배포-비중으로 재면 비구속.
##       반대로 어느 달에도 0.20 근처에 안 가면 상한은 사실상 비구속이라 해석 차이의 실익이 작다.
suppressPackageStartupMessages({library(data.table); library(jsonlite)})
R <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(R)
HD <- "05_Production/2.Factor_Model/2-4.STR_1715_on_M4gAE_R05_noLayer4_PG2/02_holdings_universe"
f <- sort(list.files(HD, pattern="_weights_cap_0p20\\.csv$", full.names=TRUE))
cat(sprintf("[대상] 배포 비중 파일 %d개\n\n", length(f)))
if (!length(f)) { cat("[중단] 파일 없음\n"); quit(status=0) }

res <- rbindlist(lapply(f, function(p) {
  W <- fread(p)
  wc <- grep("^Weight$|^w$", names(W), value=TRUE, ignore.case=TRUE)[1]
  if (is.na(wc)) return(NULL)
  E <- W[toupper(as.character(Ticker)) != "CASH"]
  inv <- sum(E[[wc]], na.rm=TRUE)
  data.table(file = basename(p), n_eq = nrow(E), invested = inv,
             max_deployed = max(E[[wc]], na.rm=TRUE),
             max_strategy = if (inv > 0) max(E[[wc]], na.rm=TRUE)/inv else NA_real_)
}), fill=TRUE)
setorder(res, file)
res[, `:=`(dep_over = max_deployed > 0.2001, str_over = max_strategy > 0.2001)]
print(res[, .(file = substr(file,1,26), n_eq, invested = round(invested,4),
              max_dep = round(max_deployed,4), max_str = round(max_strategy,4))])

cat(sprintf("\n[요약] 파일 %d · invested 범위 %.2f~%.2f\n", nrow(res), min(res$invested), max(res$invested)))
full <- res[invested > 0.999]
cat(sprintf("  invested≈1 달 %d개 — 두 해석 일치 구간\n", nrow(full)))
if (nrow(full)) cat(sprintf("    그 달 max 전략비중: %.4f ~ %.4f (상한 0.20 도달 %d건)\n",
                            min(full$max_strategy), max(full$max_strategy), sum(full$str_over)))
part <- res[invested <= 0.999]
cat(sprintf("  invested<1 달 %d개 — 해석이 갈리는 구간\n", nrow(part)))
if (nrow(part)) {
  cat(sprintf("    배포기준 위반 %d건 / 전략기준 위반 %d건 → **판정 갈림 %d건**\n",
              sum(part$dep_over), sum(part$str_over), sum(part$dep_over != part$str_over)))
  cat(sprintf("    그 달 max 전략비중 최대 %.4f (0.20 대비 %.0f%%)\n",
              max(part$max_strategy), 100*max(part$max_strategy)/0.20))
}
cat("\n[판정]\n")
if (nrow(res[(str_over)]) == 0) {
  cat("  실측 산출물 중 **전략기준 위반 0건** — 현재까지 두 해석 어느 쪽으로도 실제 위반 없음.\n")
  cat("  ⇒ 기준 모호성은 **잠복**(현 산출 무해)이나, 상한 도달률이 높을수록 실효 위험이 커진다.\n")
}
cat(sprintf("  상한 도달률(전략기준 max/0.20) 중앙 %.0f%% · 최대 %.0f%%\n",
            100*median(res$max_strategy)/0.20, 100*max(res$max_strategy)/0.20))
fwrite(res, "stage_artifacts/beta_z_source_20260808/bound_basis_evidence.csv")
cat("\n[저장] bound_basis_evidence.csv\n")
