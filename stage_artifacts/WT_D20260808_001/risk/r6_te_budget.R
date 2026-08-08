# =============================================================================
# r6_te_budget.R — 추적오차(TE) 예산의 구조 분해
#   Q2: "담을 수 없는 tier 가 벤치에 있다"가 TE 예산에 반영돼 있는가.
#   ① arm 별 사전(ex-ante) TE 를 MKT/SECTOR/STYLE/SPECIFIC 으로 분해
#   ② 상한 0.20 이 강제하는 mega 저가중 성분의 기여 분리
#   ③ 기수(25종) 제약을 푼 볼록완화 QP 하한 = "상한만으로 강제되는 TE 바닥"
#   ★비중 산출물 없음 — 스칼라 위험량만. QP 해는 하한 계산의 내부값이며 저장하지 않는다.
#   metric_type = risk_estimate
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(quadprog) })
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- "stage_artifacts/WT_D20260808_001/risk"
say <- function(fmt,...) cat(sprintf(paste0("[r6] ",fmt,"\n"),...))
source("02_Infrastructure/portfolio/hrp_core.R")

E   <- as.data.table(read_parquet(file.path(OUT,"exposure_panel.parquet"))); E[,Date:=as.Date(Date)]
FR  <- as.data.table(read_parquet(file.path(OUT,"factor_returns.parquet"))); FR[,Date:=as.Date(Date)]
RES <- as.data.table(read_parquet(file.path(OUT,"residuals_panel.parquet"))); RES[,Date:=as.Date(Date)]
SECM<- as.data.table(read_parquet(file.path(OUT,"sector_map.parquet"))); SECM[,Date:=as.Date(Date)]
AS  <- as.data.table(read_parquet("stage_artifacts/WT_D20260808_001/alpha_scores.parquet")); AS[,Date:=as.Date(Date)]
FW  <- readRDS("stage_artifacts/WT_D20260808_001/fwd_cache.rds")
LIQ <- as.data.table(FW$liq_dt); LIQ[,Date:=as.Date(Date)]
m2  <- readRDS(file.path(OUT,"r2_meta.rds")); fac_names<-m2$fac_names; STY<-m2$sty
base_sec<-m2$base_sec; sec_use<-m2$sec_use; SC<-as.data.table(m2$sec_counts); SC[,Date:=as.Date(Date)]
say("입력 E %d행/%d월 | FR %d월 | AS %d행 | LIQ %d행 (관측단위 월간)",
    nrow(E), uniqueN(E$Date), nrow(FR), nrow(AS), nrow(LIQ))

FRo <- FR[order(Date)]; WINF <- 60L
om_at <- function(d){
  ft <- tail(FRo[Date < d], WINF); if (nrow(ft) < WINF) return(NULL)
  X <- as.matrix(ft[, ..fac_names]); X[!is.finite(X)] <- 0
  a <- which(apply(X,2,stats::sd)>1e-10)
  Om <- tryCatch(.get_cor_cov(X[,a,drop=FALSE], "lw_nls")$cov, error=function(e) NULL)
  if (is.null(Om)) return(NULL); dimnames(Om) <- list(colnames(X)[a], colnames(X)[a]); Om
}
d_at <- function(d){
  lo <- seq(d, by="-60 months", length.out=2)[2]
  ds <- RES[Date<=d & Date>lo][, .(n=.N, sv=stats::var(resid)), by=Ticker][n>=24]
  pri <- median(ds$sv, na.rm=TRUE); ds[, w:=n/(n+24)][, spec_var := w*sv+(1-w)*pri]
  list(ds=ds[, .(Ticker, spec_var)], prior=pri)
}
mkB <- function(sub, d, fn){
  cn <- SC[Date==d]; nb <- cn[sec==base_sec]$N; if(!length(nb)||nb==0) nb <- 1
  B <- matrix(0, nrow(sub), length(fn), dimnames=list(sub$Ticker, fn))
  if ("MKT" %in% fn) B[,"MKT"] <- 1
  isb <- as.numeric(sub$sec==base_sec)
  for (s in sec_use){ col<-paste0("SEC_",s); if(!(col %in% fn)) next
    ns <- cn[sec==s]$N; ns <- if(length(ns)) ns else 0
    B[,col] <- as.numeric(sub$sec==s) - (ns/nb)*isb }
  for (s in intersect(STY, fn)) B[,s] <- ifelse(is.finite(sub[[s]]), sub[[s]], 0)
  B
}

dts <- sort(unique(E$Date)); dts <- dts[dts>=as.Date("2009-01-01") & dts<=as.Date("2026-06-30")]
rows <- list(); qp_rows <- list()
qp_dates <- dts[seq(1, length(dts), by=12)]; qp_dates <- unique(c(qp_dates, max(dts)))

for (d in dts) {
  d <- as.Date(d)
  Om <- om_at(d); if (is.null(Om)) next
  dd <- d_at(d)
  U <- E[Date==d & is.finite(Size) & Size>0]
  U <- merge(U, SECM[Date==d, .(Ticker, sec)], by="Ticker", all.x=TRUE); U[is.na(sec), sec:="OTHER"]
  U <- merge(U, dd$ds, by="Ticker", all.x=TRUE); U[!is.finite(spec_var), spec_var:=dd$prior]
  U <- U[is.finite(X_BETA)]
  if (nrow(U) < 80) next
  U[, wb := Size/sum(Size)]
  B <- mkB(U, d, colnames(Om))
  dv <- U$spec_var

  # arm 비중 (canonical 과 동일 규칙: 유동성 2e8 필터 후 top-25 EW)
  sc <- merge(AS[Date==d, .(Ticker, score, score_q01filtered)], LIQ[Date==d, .(Ticker, adv)], by="Ticker", all.x=TRUE)
  sc <- sc[is.na(adv) | adv >= 2e8]
  armw <- function(col){
    s <- sc[is.finite(get(col))][order(-get(col))]
    s <- s[Ticker %in% U$Ticker]; if (nrow(s) < 25) return(NULL)
    w <- rep(0, nrow(U)); names(w) <- U$Ticker
    w[s$Ticker[1:25]] <- 1/25; w
  }
  for (nm in c("score","score_q01filtered")) {
    w <- armw(nm); if (is.null(w)) next
    a <- w - U$wb
    x <- as.numeric(t(B) %*% a); names(x) <- colnames(Om)
    v_fac <- as.numeric(t(x) %*% Om %*% x); v_spec <- sum(a^2*dv); v_tot <- v_fac+v_spec
    contrib <- x * as.numeric(Om %*% x)
    c_mkt <- if ("MKT" %in% names(contrib)) contrib[["MKT"]] else 0
    c_sec <- sum(contrib[grepl("^SEC_", names(contrib))])
    c_sty <- sum(contrib[names(contrib) %in% STY])
    # 상한 강제 성분: w_b > 0.20 종목의 불가피 저가중 -(w_b-0.20)
    a_cap <- rep(0, nrow(U)); ix <- which(U$wb > 0.20)
    if (length(ix)) a_cap[ix] <- -(U$wb[ix]-0.20)
    xc <- as.numeric(t(B) %*% a_cap)
    v_cap_solo <- as.numeric(t(xc)%*%Om%*%xc) + sum(a_cap^2*dv)
    v_cap_marg <- as.numeric(t(xc)%*%Om%*%x) + sum(a_cap*a*dv)   # 총분산 대비 한계기여
    rows[[length(rows)+1]] <- data.table(
      Date=d, arm=nm, n_uni=nrow(U), te_ann=sqrt(v_tot*12),
      sh_mkt=c_mkt/v_tot, sh_sec=c_sec/v_tot, sh_sty=c_sty/v_tot, sh_spec=v_spec/v_tot,
      x_beta=x[["X_BETA"]], x_size=x[["X_SIZE"]], x_ivol=x[["X_IVOL"]],
      x_mom=x[["X_MOM"]], x_qual=x[["X_QUAL"]], x_liq=x[["X_LIQ"]],
      te_cap_solo_ann=sqrt(max(v_cap_solo,0)*12), cap_marg_share=v_cap_marg/v_tot,
      n_capped=length(ix), capped_mass=sum(pmax(0,U$wb-0.20)))
  }

  if (d %in% qp_dates) {
    SIGu <- B %*% Om %*% t(B) + diag(dv); SIGu <- (SIGu+t(SIGu))/2
    n <- nrow(SIGu); wb <- U$wb
    Dm <- 2*SIGu + diag(1e-10, n)
    dv2 <- as.numeric(2*SIGu %*% wb)
    Am <- cbind(rep(1,n), diag(n), -diag(n))
    bv <- c(1, rep(0,n), rep(-0.20, n))
    sol <- tryCatch(solve.QP(Dm, dv2, Am, bv, meq=1), error=function(e) NULL)
    if (!is.null(sol)) {
      aa <- sol$solution - wb
      qp_rows[[length(qp_rows)+1]] <- data.table(Date=d, n=n,
        te_floor_caponly_ann = sqrt(max(as.numeric(t(aa)%*%SIGu%*%aa),0)*12),
        n_eff_sol = 1/sum(sol$solution^2))
    }
  }
}
TB <- rbindlist(rows); QP <- rbindlist(qp_rows)
say("TE 예산 패널 rows=%d (arm x 월) | 월 %d", nrow(TB), uniqueN(TB$Date))
for (nm in unique(TB$arm)) {
  s <- TB[arm==nm]
  say("[arm %s] 사전 TE 연율 중앙 %.4f | 구성비 중앙: MKT %.3f SECTOR %.3f STYLE %.3f SPECIFIC %.3f",
      nm, median(s$te_ann), median(s$sh_mkt), median(s$sh_sec), median(s$sh_sty), median(s$sh_spec))
  say("        active 노출 중앙: β %+.3f SIZE %+.3f IVOL %+.3f MOM %+.3f QUAL %+.3f LIQ %+.3f",
      median(s$x_beta), median(s$x_size), median(s$x_ivol), median(s$x_mom), median(s$x_qual), median(s$x_liq))
  say("        상한강제 성분 단독 TE %.4f | 총분산 한계기여 %.3f | 상한 걸린 종목수 중앙 %.1f | 초과질량 중앙 %.4f",
      median(s$te_cap_solo_ann), median(s$cap_marg_share), median(s$n_capped), median(s$capped_mass))
}
if (nrow(QP)) {
  say("[볼록완화 QP] 상한 0.20 만으로 강제되는 TE 바닥(기수제약 해제) 연율 중앙 %.4f [%.4f, %.4f] (n=%d 시점)",
      median(QP$te_floor_caponly_ann), min(QP$te_floor_caponly_ann), max(QP$te_floor_caponly_ann), nrow(QP))
  say("   최근 시점(%s) = %.4f | 해의 유효종목수 %.1f",
      as.character(max(QP$Date)), QP[Date==max(Date)]$te_floor_caponly_ann, QP[Date==max(Date)]$n_eff_sol)
  print(QP[, .(Date, te_floor_caponly = round(te_floor_caponly_ann,4), n_eff = round(n_eff_sol,1))])
}
write_parquet(TB, file.path(OUT,"te_budget_panel.parquet"))
saveRDS(list(TB=TB, QP=QP), file.path(OUT,"r6_te_budget.rds"))
say("저장 완료")
