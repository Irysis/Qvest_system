## analyze_engine.R — P5(미래교란 2시점) / P8(팩터 독립성) / P6(적용 지연) 판정 분석.
suppressPackageStartupMessages({library(data.table); library(arrow)})
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
AD<-"stage_artifacts/audit_dfa_20260821"
sink(file.path(AD,"analyze_engine_output.txt"), split=TRUE)
cat("== analyze_engine.R:", format(Sys.time()), "==\n\n")

dts<-as.data.table(read_parquet(file.path(AD,"synth_A.parquet")))$Date
dts<-as.Date(dts); NS<-length(dts)
rc<-function(base) sprintf(".cache/_dfa_v5_refit_f15_roll_synth_%s_parquet_m3_n6_ValSizMomQuaLowGro.rds",base)
sc<-function(base) sprintf(".cache/_dfa_v5_states_f15_roll_synth_%s_parquet_m3_n6_ValSizMomQuaLowGro_lm1.rds",base)
mainr<-function(key) readRDS(sprintf(".cache/_dfa_v5_%s.rds",key))
FACN<-c("Value","Size","Momentum","Quality","LowVol","Growth")

cmp_num<-function(a,b){ if(is.null(a)&&is.null(b))return(0); if(is.null(a)||is.null(b))return(Inf)
  if(length(a)!=length(b))return(Inf); m<-max(abs(as.numeric(a)-as.numeric(b))); if(is.na(m))Inf else m }

## ---------- P5 ----------
p5<-function(bkey, bbase, tstar, lab){
  cat(sprintf("---- [P5] %s (t*=%s) ----\n", lab, tstar))
  ZA<-mainr("audit_a"); ZB<-mainr(bkey)
  RA<-readRDS(rc("A"))$REF; RB<-readRDS(rc(bbase))$REF
  SA<-readRDS(sc("A"))$S;  SB<-readRDS(sc(bbase))$S
  me<-ZA$medates; stopifnot(identical(as.character(me),as.character(ZB$medates)))
  mi_pre<-which(me<=as.Date(tstar))
  ## 1) refit별 (λ,κ)·cur·m_ann·θ·w·μ·σ — t* 이전 월 전부
  worst<-0; nref<-0; lamdiff<-0
  for(f in FACN) for(mi in mi_pre){ a<-RA[[f]][[mi]]; b<-RB[[f]][[mi]]
    if(is.null(a)&&is.null(b)) next
    nref<-nref+1
    worst<-max(worst, cmp_num(a$th,b$th), cmp_num(a$wj,b$wj), cmp_num(a$mu,b$mu),
               cmp_num(a$sg,b$sg), cmp_num(a$m_ann,b$m_ann), cmp_num(a$cur,b$cur))
    lamdiff<-max(lamdiff, cmp_num(c(a$lam,a$k2), c(b$lam,b$k2)))
  }
  cat(sprintf("  [refit] t* 이전 refit %d건: (λ,κ²) max|Δ|=%.3g | θ/w/μ/σ/m_ann/cur max|Δ|=%.3g  [둘 다 0 필수]\n",nref,lamdiff,worst))
  ## 2) 일별 상태 t<=t*
  ipre<-which(dts<=as.Date(tstar))
  sdiff<-sum(SA[ipre,]!=SB[ipre,],na.rm=TRUE)+sum(is.na(SA[ipre,])!=is.na(SB[ipre,]))
  cat(sprintf("  [states] t<=t* 일수 %d × 6팩터: 불일치 셀=%d  [0 필수]\n",length(ipre),sdiff))
  ## 3) view/c 캘리브 t* 이전 월
  cat(sprintf("  [view_me] max|Δ|=%.3g | [cmat] max|Δ|=%.3g  [0 필수]\n",
    cmp_num(ZA$view_me[mi_pre,],ZB$view_me[mi_pre,]), cmp_num(ZA$cmat[mi_pre,,drop=FALSE],ZB$cmat[mi_pre,,drop=FALSE])))
  ## 4) 산출 시계열: M0 net_d (일별) t<=t* / D1 월간 pr — t* 월 이전
  ga<-ZA$RES[arm=="M0"&te==3&cost_bps==15]; gb<-ZB$RES[arm=="M0"&te==3&cost_bps==15]
  na_<-ga$series[[1]]$net_d; nb_<-gb$series[[1]]$net_d
  dif<-abs(na_-nb_); dif[is.na(na_)&is.na(nb_)]<-0; dif[is.na(dif)]<-Inf
  cat(sprintf("  [M0 net_d] t<=t* max|Δ|=%.3g | t*+1 이후 최초 상이일=%s (기대: t* 직후)\n",
    max(dif[ipre]), as.character(dts[which(dif>1e-15)][1])))
  da<-ZA$RES[arm=="D1"&te==3&cost_bps==15]; db<-ZB$RES[arm=="D1"&te==3&cost_bps==15]
  sa_<-da$series[[1]]; sb_<-db$series[[1]]
  mm<-intersect(sa_$months,sb_$months); i0<-match(mm,sa_$months); i1<-match(mm,sb_$months)
  tsm<-format(as.Date(tstar),"%Y-%m"); pre_m<-mm[mm<tsm]
  dd<-abs(sa_$pr[i0][mm<tsm]-sb_$pr[i1][mm<tsm])
  post<-abs(sa_$pr[i0]-sb_$pr[i1]); firstd<-mm[which(post>1e-15)][1]
  cat(sprintf("  [D1 월간 pr] t* 이전 완전월 %d개 max|Δ|=%.3g | 최초 상이월=%s (기대: t* 월 이후)\n",
    length(pre_m), ifelse(length(dd),max(dd),NA), firstd))
  ## 음성 대조: t* 이후는 실제로 달라야 프로브가 유효
  cat(sprintf("  [음성대조] t* 이후 상태 불일치 셀=%d (0이면 프로브 무효)\n\n",
    sum(SA[dts>as.Date(tstar),]!=SB[dts>as.Date(tstar),],na.rm=TRUE)))
}
p5("audit_b1","B1","2010-06-30","중반 교란")
p5("audit_b2","B2","2012-03-30","후반 교란")

## ---------- P8 ----------
cat("---- [P8] Value만 치환 → 나머지 5팩터 국면열·(λ,κ)·refit 완전 불변 ----\n")
ZA<-mainr("audit_a"); ZP<-mainr("audit_p8")
RA<-readRDS(rc("A"))$REF; RP<-readRDS(rc("P8"))$REF
SA<-readRDS(sc("A"))$S;  SP<-readRDS(sc("P8"))$S
for(f in FACN){
  worst<-0; lamd<-0; n<-0
  for(mi in seq_along(ZA$medates)){ a<-RA[[f]][[mi]]; b<-RP[[f]][[mi]]
    if(is.null(a)&&is.null(b))next; n<-n+1
    worst<-max(worst,cmp_num(a$th,b$th),cmp_num(a$wj,b$wj),cmp_num(a$m_ann,b$m_ann),cmp_num(a$cur,b$cur))
    lamd<-max(lamd,cmp_num(c(a$lam,a$k2),c(b$lam,b$k2))) }
  sdiff<-sum(SA[,f]!=SP[,f],na.rm=TRUE)
  cat(sprintf("  %-9s refit %d건: (λ,κ²)|Δ|=%.3g θ/w/m_ann/cur|Δ|=%.3g | 일별상태 불일치=%d  %s\n",
    f,n,lamd,worst,sdiff, ifelse(f=="Value","[치환 대상 — 달라야 정상]","[0 필수]")))
}
cat("\n")

## ---------- P6 ----------
cat("---- [P6-M0] 단일일 교란(2010-05-14) → 반응 시점 분해 (net_d, te3/15bps) ----\n")
ZM<-mainr("audit_m0d")
ga<-ZA$RES[arm=="M0"&te==3&cost_bps==15]; gm<-ZM$RES[arm=="M0"&te==3&cost_bps==15]
na_<-ga$series[[1]]$net_d; nm_<-gm$series[[1]]$net_d
dif<-abs(na_-nm_); both_na<-is.na(na_)&is.na(nm_); dif[both_na]<-0
tm<-as.Date("2010-05-14")
seg<-function(cond) {v<-dif[cond & !both_na]; if(!length(v)) NA else max(v)}
cat(sprintf("  t<tm       max|Δ| = %.3g   [0 필수 — 교란 전 절대 불변]\n", seg(dts<tm)))
cat(sprintf("  t=tm            |Δ| = %.3g   [기계적 수익차 — 비중 아닌 당일 수익 차]\n", dif[which(dts==tm)]))
cat(sprintf("  tm<t<=5/31 max|Δ| = %.3g   [드리프트-only 스케일이어야 — 결정 비중은 4월말 결정 그대로]\n", seg(dts>tm & dts<=as.Date("2010-05-31"))))
cat(sprintf("  6월(익월)  max|Δ| = %.3g   [5월말 결정 반영 — 여기서 결정-스케일 첫 반응 = 자기사양 '월말 결정→익월 적용' 충족]\n", seg(format(dts,"%Y-%m")=="2010-06")))
cat(sprintf("  최초 상이일 = %s [tm 당일이어야 — 이전이면 미래참조]\n\n", as.character(dts[which(dif>1e-15)][1])))

cat("---- [P6-D1] shift 사다리 배선 실효 (SHIFT 0/2/3 → 결과·최초적용일 달라야) ----\n")
r2<-ZA$RES[arm=="D1"&te==3&cost_bps==15]
r0<-mainr("audit_sh0")$RES[arm=="D1"&te==3&cost_bps==15]
r3<-mainr("audit_sh3")$RES[arm=="D1"&te==3&cost_bps==15]
cat(sprintf("  IR_vsEW: SHIFT0=%.4f | SHIFT2=%.4f | SHIFT3=%.4f  [서로 달라야 배선 실효]\n", r0$IR_vsEW, r2$IR_vsEW, r3$IR_vsEW))
for(k in c("audit_sh0","audit_a","audit_sh3")){
  pgf<-sprintf(".cache/_dfa_v5_prog_%s.txt",k)
  ln<-grep("D1 lm=.*done",readLines(pgf),value=TRUE)
  cat(sprintf("  %s: %s\n",k,trimws(ln[1])))
}
cat("  [최초적용일 = 최초결정일 + max(SHIFT,1) 영업일 — 코드 L326/L328과 대조]\n")
cat("\nANALYZE_ENGINE_DONE\n"); sink()
