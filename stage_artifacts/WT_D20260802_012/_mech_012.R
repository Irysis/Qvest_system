## _mech_012.R — 기전 귀속: 창-정합에서 A′ 가 강해진 이유
##   모순: 채널①(보조 flag)이 개선 전량을 설명하는데, 정작 보조축 '신규 이름'(MAG_ONLY) 은
##         같은 월에서 OFF 대비 null~음수(MID +0.00 / REST -0.75).
##   가설: 보조축이 '새 이름을 더한' 게 아니라 INS02 on-run 의 구멍을 메워
##         R38 이 신뢰 낮다고 판정한 ENTRY(단발, t+0.05)를 신뢰 높은 SUSTAIN(t+3.63)으로 재분류한 것.
##   검증: state_A × state_Ap 이행행렬(창-정합) + 이행 셀별 forward 안전 특성.
## 실행: Rscript -e 'source("stage_artifacts/WT_D20260802_012/_mech_012.R", encoding="UTF-8")'
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite); library(sandwich); library(lmtest)})
setDTthreads(1); try(arrow::set_io_thread_count(2L), silent=TRUE)
QM <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(QM)
OUT <- "stage_artifacts/WT_D20260802_012"
logf <- file.path(OUT,"_r43_mech_log.txt"); if(file.exists(logf)) try(file.remove(logf), silent=TRUE)
w <- function(...){ m<-paste0(...); try({.c<-file(logf,"a",encoding="UTF-8"); writeLines(m,.c); close(.c)},silent=TRUE); cat(m,"\n") }
wf <- function(...) w(sprintf(...))
nw_fit <- function(x){ x<-x[is.finite(x)]; if(length(x)<12) return(list(mean=NA,t=NA,n=length(x)))
  m<-lm(x~1); ct<-coeftest(m,vcov=sandwich::NeweyWest(m,lag=3,prewhite=FALSE))
  list(mean=as.numeric(ct[1,1]),t=as.numeric(ct[1,3]),n=length(x)) }
risk_metrics <- function(r){ r<-r[is.finite(r)]; if(!length(r)) return(list(n=0L,mean=NA_real_,downside=NA_real_,tail=NA_real_,vol=NA_real_))
  list(n=length(r), mean=mean(r), downside=mean(r[r<0]), tail=mean(r< -0.15), vol=sd(r)) }

O <- readRDS(file.path(OUT,"_r43_objects.rds")); U <- as.data.table(O$uni_slim)
A_MONTHS <- U[a==1L, unique(hold_ym)]
M <- U[hold_ym %in% A_MONTHS]                       # 창-정합
M[, sA  := fifelse(is.na(state_A),  "(uncovered)", state_A)]
M[, sAp := fifelse(is.na(state_Ap), "(uncovered)", state_Ap)]

w("────── state_A × state_Ap 이행행렬 (창-정합 A 활성 126개월, 전체 tier) ──────")
TM <- dcast(M[, .N, by=.(sA,sAp)], sA ~ sAp, value.var="N", fill=0L)
print(TM); w(paste(capture.output(print(TM)), collapse="\n"))

## 이행 셀 라벨: 변화 없는 셀은 무시, 변한 셀만 안전 특성 비교
M[, cell := fifelse(sA==sAp, "unchanged", paste0(sA, "→", sAp))]
CH <- M[cell!="unchanged", .N, by=cell][order(-N)]
w("\n[이행 셀] 창-정합에서 라벨이 바뀐 name-months:")
for(i in seq_len(nrow(CH))) wf("   %-28s n=%d", CH$cell[i], CH$N[i])

## 핵심 셀들의 forward 안전 특성 vs A-OFF 기준선
ref <- M[sA=="OFF", Ret_1m]; RM_ref <- risk_metrics(ref)
wf("\n[기준선] A-OFF: n=%d fwd=%+.4f downside=%+.4f tail=%.4f vol=%.4f",
   RM_ref$n, RM_ref$mean, RM_ref$downside, RM_ref$tail, RM_ref$vol)
KEY <- CH[N>=30, cell]
CELLS <- list()
w("[이행 셀별 forward 안전 특성]")
for(cc in KEY){ x <- risk_metrics(M[cell==cc, Ret_1m])
  ## 월별-paired vs A-OFF
  d <- M[cell==cc | sA=="OFF"]
  g <- d[, .(ms=mean(Ret_1m[cell==cc],na.rm=TRUE), mr=mean(Ret_1m[sA=="OFF"],na.rm=TRUE),
             ns=sum(cell==cc), nr=sum(sA=="OFF")), by=hold_ym][ns>0 & nr>0]
  f <- if(nrow(g)) nw_fit(g$ms-g$mr) else list(mean=NA,t=NA,n=0)
  CELLS[[cc]] <- list(n=x$n, mean=round(x$mean,5), downside=round(x$downside,5), tail=round(x$tail,5),
                      vol=round(x$vol,5), paired_vs_A_OFF_ann=round(f$mean*12,5), paired_t=round(f$t,3), n_months=f$n)
  wf("   %-28s n=%4d fwd=%+.4f downside=%+.4f tail=%.4f | vs A-OFF gap_ann=%+.4f t=%+.2f (mo=%d)",
     cc, x$n, x$mean, x$downside, x$tail, f$mean*12, f$t, f$n) }

## 확증: A′ SUSTAIN 중 'A 에서는 SUSTAIN 이 아니었던' 부분집합의 기여
add_sus <- M[sAp=="SUSTAIN" & sA!="SUSTAIN"]
old_sus <- M[sAp=="SUSTAIN" & sA=="SUSTAIN"]
wf("\n[SUSTAIN 구성] A′ SUSTAIN %d = 기존 %d + 신규편입 %d (신규편입 출처: %s)",
   M[sAp=="SUSTAIN",.N], nrow(old_sus), nrow(add_sus),
   paste(sprintf("%s=%d", add_sus[,.N,by=sA]$sA, add_sus[,.N,by=sA]$N), collapse=" "))
rm_add <- risk_metrics(add_sus$Ret_1m); rm_old <- risk_metrics(old_sus$Ret_1m)
wf("[SUSTAIN 구성] 기존 SUSTAIN: fwd=%+.4f downside=%+.4f tail=%.4f | 신규편입: fwd=%+.4f downside=%+.4f tail=%.4f",
   rm_old$mean, rm_old$downside, rm_old$tail, rm_add$mean, rm_add$downside, rm_add$tail)

## MID/REST 슬라이스 반복 (habitat 확인)
SLICE <- list()
for(sl in c("MID_habitat","REST")){
  D <- if(sl=="MID_habitat") M[sz_tercile=="mid"] else M[megatier=="REST"]
  as_ <- D[sAp=="SUSTAIN" & sA!="SUSTAIN"]; os_ <- D[sAp=="SUSTAIN" & sA=="SUSTAIN"]
  ra <- risk_metrics(as_$Ret_1m); ro <- risk_metrics(os_$Ret_1m)
  d <- D[(sAp=="SUSTAIN" & sA!="SUSTAIN") | sA=="OFF"]
  g <- d[, .(ms=mean(Ret_1m[sAp=="SUSTAIN" & sA!="SUSTAIN"],na.rm=TRUE), mr=mean(Ret_1m[sA=="OFF"],na.rm=TRUE),
             ns=sum(sAp=="SUSTAIN" & sA!="SUSTAIN"), nr=sum(sA=="OFF")), by=hold_ym][ns>0 & nr>0]
  f <- if(nrow(g)) nw_fit(g$ms-g$mr) else list(mean=NA,t=NA,n=0)
  SLICE[[sl]] <- list(n_added=ra$n, added_mean=round(ra$mean,5), added_downside=round(ra$downside,5), added_tail=round(ra$tail,5),
                      old_n=ro$n, old_mean=round(ro$mean,5), added_vs_A_OFF_ann=round(f$mean*12,5), added_t=round(f$t,3), n_months=f$n,
                      sources=setNames(as.list(as_[,.N,by=sA]$N), as_[,.N,by=sA]$sA))
  wf("[%s] 신규편입 SUSTAIN n=%d (출처 %s) fwd=%+.4f downside=%+.4f tail=%.4f | vs A-OFF gap_ann=%+.4f t=%+.2f (mo=%d)",
     sl, ra$n, paste(sprintf("%s=%d", as_[,.N,by=sA]$sA, as_[,.N,by=sA]$N), collapse=","),
     ra$mean, ra$downside, ra$tail, f$mean*12, f$t, f$n)
}
write_json(list(window="A_active_126_months", transition_matrix=as.list(TM),
                changed_cells=setNames(as.list(CH$N), CH$cell), cell_metrics=CELLS,
                sustain_composition=list(total=M[sAp=="SUSTAIN",.N], existing=nrow(old_sus), added=nrow(add_sus),
                  added_sources=setNames(as.list(add_sus[,.N,by=sA]$N), add_sus[,.N,by=sA]$sA),
                  existing_metrics=rm_old, added_metrics=rm_add),
                slices=SLICE, reference_A_OFF=RM_ref),
           file.path(OUT,"r43_mechanism.json"), auto_unbox=TRUE, pretty=TRUE, digits=6, na="null")
w("\nMECH_DONE"); cat("[SAVED]", file.path(OUT,"r43_mechanism.json"), "\n")
