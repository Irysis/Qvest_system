## factor_group_consolidation.R — RAMP 정제: 102 신호팩터 → 경제 패밀리 composite 군
## group signal = 패밀리 멤버(approved) 순수 z(neutralized) 평균 → 월별 재표준화.
## 산출: 군별 net 검증(canonical_screen via validate_factor) + 군간 신호 상관(직교성) + group_scores.
## 단일스레드·실측-only. 진입: Rscript -e 'source(".../factor_group_consolidation.R")'
suppressPackageStartupMessages({library(data.table); library(arrow)})
setDTthreads(1); try(arrow::set_cpu_count(1),silent=TRUE); try(arrow::set_io_thread_count(2),silent=TRUE)
QM <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(QM)
source(file.path(QM,"02_Infrastructure/config.R"))
source("02_Infrastructure/ramp/factor_validation.R")  # validate_factor, build_monthly_forward_returns, %||%
con <- file(".cache/_consolidation.txt","w",encoding="UTF-8"); w<-function(...)writeLines(paste0(...),con)

fam_of <- function(fid){ p<-toupper(substr(fid,1,2)); p1<-substr(p,1,1)
  if(p1=="V") "Value" else if(p1=="M"&&p!="MA") "Momentum" else if(p1=="Q") "Quality"
  else if(p1=="D") "LowRisk" else if(p1=="L") "Size_Liquidity" else if(p1=="S"&&p!="SE") "Size_Liquidity"
  else if(p1=="R") "Reversal" else if(p=="GR") "Growth_Profit" else if(p=="AC") "Accruals"
  else if(p1=="C"&&p!="CR") "Consensus" else if(p=="CR") "Credit" else if(p=="IN") "Growth_Profit"
  else if(p=="XF") "Composite" else if(p=="MA") "Macro" else if(p=="TR") "Size_Liquidity" else "Composite" }

af <- as.data.table(read_parquet("06_Registry/ramp/approved_factor_library.parquet"))
## [2026-06-19 도훈: 팩터군 보강] RAMP_FULL_FACTORS=1 → 전체 316으로 군 구성(멤버多=composite 강건). 기각=standalone 허들(advisory).
sig <- if(Sys.getenv("RAMP_FULL_FACTORS")=="1") sort(unique(af$factor_id)) else af[status=="approved", factor_id]
w(sprintf("군 구성 팩터(%s): %d", ifelse(Sys.getenv("RAMP_FULL_FACTORS")=="1","FULL 316","approved 102"), length(sig)))

sc <- as.data.table(read_parquet("outputs/ramp/pure_factor_scores.parquet",
        col_select=c("signal_date","security_id","factor_id","neutralized_z")))
sc <- sc[factor_id %in% sig]; sc[, family := sapply(factor_id, fam_of)]; sc <- sc[family!="Macro"]
w(sprintf("scores(신호·non-Macro): %d rows", nrow(sc)))

# 패밀리 composite (date×ticker 멤버 z 평균 → 월별 cross-section 재표준화)
grp <- sc[, .(z=mean(neutralized_z,na.rm=TRUE), n_members=uniqueN(factor_id)),
          by=.(signal_date, security_id, family)]
grp[, gz := { m<-mean(z,na.rm=T); s<-sd(z,na.rm=T); if(is.na(s)||s<1e-9) z-m else (z-m)/s }, by=.(signal_date,family)]
fam_n <- sc[, .(n_member_factors=uniqueN(factor_id)), by=family][order(-n_member_factors)]
w("\n=== 경제 패밀리 군 (멤버 팩터 수) ===")
for(i in seq_len(nrow(fam_n))) w(sprintf("  %-16s : %d", fam_n$family[i], fam_n$n_member_factors[i]))
w(sprintf("→ 정제 결과: %d개 군 | 기저 %d 팩터", nrow(fam_n), length(sig)))

# 군별 net 검증
## [2026-06-18] col_select — full 14M×21col(2.5GB) 풀로드 세그폴트 회피. build_monthly_forward_returns 소비컬럼만.
.need<-c("Date","Ticker","Close","K200","KQ150","Vol","Size","Ret","Sector","BM_Ret")
rawdata <- as.data.table(read_parquet(".cache/rawdata.parquet", col_select=all_of(.need))); rawdata[,Date:=as.Date(Date)]
sig_dates <- sort(unique(as.Date(grp$signal_date)))
fwd <- build_monthly_forward_returns(rawdata, sig_dates)
fams <- sort(unique(grp$family)); mets <- list()
for(fm in fams){
  sdt <- grp[family==fm, .(signal_date, security_id, factor_id=fm, neutralized_z=gz)]
  v <- tryCatch(validate_factor(sdt, fwd, top_n=20L, cost_bps=15), error=function(e) NULL)
  if(is.null(v)) next
  mets[[fm]] <- data.table(group=fm, n_months=v$n_months, net_sr=v$net_sr,
                           port_t=v$portfolio_alpha_t_nw, ir=v$information_ratio, rank_ic_ir=v$rank_ic_ir)
}
M <- rbindlist(mets, fill=TRUE)[order(-port_t)]
w("\n=== 군별 long-only top-20 net (개별군도 약함 — 조합 전 baseline) ===")
for(i in seq_len(nrow(M))) w(sprintf("  %-16s net_sr=%+.3f port_t=%+.2f ir=%+.2f ic_ir=%+.3f",
  M$group[i], M$net_sr[i], M$port_t[i], M$ir[i], M$rank_ic_ir[i]))

# 군간 신호 직교성: (date×ticker) wide → 풀드 상관
wide <- dcast(grp, signal_date+security_id ~ family, value.var="gz")
fcols <- setdiff(names(wide), c("signal_date","security_id"))
cmat <- cor(as.matrix(wide[, ..fcols]), use="pairwise.complete.obs")
w("\n=== 군간 신호 상관 (직교성 — 절대값 평균/최대) ===")
od <- cmat[upper.tri(cmat)]
w(sprintf("  off-diagonal |cor|: mean=%.3f max=%.3f (낮을수록 직교/조합효익 큼)", mean(abs(od)), max(abs(od))))
hi <- which(abs(cmat)>0.5 & upper.tri(cmat), arr.ind=TRUE)
if(nrow(hi)) { for(k in seq_len(nrow(hi))) w(sprintf("  ⚠ %s ↔ %s : %.2f (중복 후보)", fcols[hi[k,1]], fcols[hi[k,2]], cmat[hi[k,1],hi[k,2]])) } else { w("  (|cor|>0.5 쌍 없음 — 군들 충분히 직교)") }

# 저장
.t<-".cache/_grpscores.parquet"; write_parquet(grp[, .(signal_date,security_id,family,group_z=gz)], "outputs/ramp/factor_group_scores.parquet")
saveRDS(list(metrics=M, fam_n=fam_n, cormat=cmat), ".cache/_consolidation.rds")
w(sprintf("\n[정제 완료] 최종 %d개 직교 경제군 / 기저 %d팩터 → Gate 6 M-code 입력", nrow(fam_n), length(sig)))
close(con); cat("CONSOL_DONE\n")
