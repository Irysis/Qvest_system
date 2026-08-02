## _decomp_012.R — R43 창-정합(window-matched) 통제: A′ SUSTAIN 희석의 귀속
##   질문: REST tier 에서 SUSTAIN vs OFF 가 A t=+3.52 → A′ t=+2.07 로 약해진 것이
##         (가설1) 기존 월의 신호를 보조축이 오염시켜서인가,
##         (가설2) 새로 열린 월(A 침묵월)이 원래 약해서인가.
##   방법: A 활성월로 월집합을 고정(창-정합)해 A′ 를 재측정 + A 침묵월 단독 측정.
## 실행: Rscript -e 'source("stage_artifacts/WT_D20260802_012/_decomp_012.R", encoding="UTF-8")'
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite); library(sandwich); library(lmtest)})
setDTthreads(1)
QM <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(QM)
OUT <- "stage_artifacts/WT_D20260802_012"
logf <- file.path(OUT, "_r43_decomp_log.txt"); if (file.exists(logf)) try(file.remove(logf), silent = TRUE)
w  <- function(...) { m <- paste0(...); try({ .c<-file(logf,"a",encoding="UTF-8"); writeLines(m,.c); close(.c) }, silent=TRUE); cat(m,"\n") }
wf <- function(...) w(sprintf(...))
nw_fit <- function(x){ x<-x[is.finite(x)]; if(length(x)<12) return(list(mean=NA,se=NA,t=NA,n=length(x)))
  m<-lm(x~1); ct<-coeftest(m, vcov=sandwich::NeweyWest(m,lag=3,prewhite=FALSE))
  list(mean=as.numeric(ct[1,1]), se=as.numeric(ct[1,2]), t=as.numeric(ct[1,3]), n=length(x)) }
paired_grp <- function(DT, grpcol, target, ref, basis="Ret_1m"){
  d <- DT[get(grpcol) %in% c(target, ref)]
  if(!nrow(d)) return(list(gap_ann=NA, gap_t=NA, n_months=0L, avg_target_mo=NA))
  g <- d[, .(m_s=mean(get(basis)[get(grpcol)==target],na.rm=TRUE), m_r=mean(get(basis)[get(grpcol)==ref],na.rm=TRUE),
             ns=sum(get(grpcol)==target), nr=sum(get(grpcol)==ref)), by=hold_ym][ns>0 & nr>0]
  if(!nrow(g)) return(list(gap_ann=NA, gap_t=NA, n_months=0L, avg_target_mo=NA))
  f <- nw_fit(g$m_s-g$m_r); list(gap_ann=f$mean*12, gap_t=f$t, n_months=f$n, avg_target_mo=mean(g$ns)) }
pr <- function(x) sprintf("gap_ann=%+.4f t=%+.2f (mo=%d, %.1f names/mo)", x$gap_ann, x$gap_t, x$n_months, x$avg_target_mo)

O <- readRDS(file.path(OUT, "_r43_objects.rds")); U <- as.data.table(O$uni_slim)
## A 활성월 = uni 안에서 A flag 가 하나라도 켜진 홀딩월
A_MONTHS <- U[a == 1L, unique(hold_ym)]
wf("[decomp] A 활성월=%d / 전체=%d | A 침묵월=%d", length(A_MONTHS), uniqueN(U$hold_ym), uniqueN(U$hold_ym)-length(A_MONTHS))

DEC <- list()
for (sl in c("MID_habitat", "REST", "TOP30", "ALL")) {
  D <- switch(sl, MID_habitat = U[sz_tercile=="mid"], REST = U[megatier=="REST"], TOP30 = U[megatier=="TOP30"], ALL = U)
  a_full   <- paired_grp(D, "state_A",  "SUSTAIN", "OFF")
  ap_full  <- paired_grp(D, "state_Ap", "SUSTAIN", "OFF")
  ap_match <- paired_grp(D[hold_ym %in% A_MONTHS],  "state_Ap", "SUSTAIN", "OFF")   # 창-정합
  a_match  <- paired_grp(D[hold_ym %in% A_MONTHS],  "state_A",  "SUSTAIN", "OFF")
  ap_new   <- paired_grp(D[!hold_ym %in% A_MONTHS], "state_Ap", "SUSTAIN", "OFF")   # 새로 열린 월 단독
  DEC[[sl]] <- list(A_full=a_full, Ap_full=ap_full, A_matched=a_match, Ap_matched=ap_match, Ap_newmonths=ap_new)
  w(sprintf("\n[%s]", sl))
  wf("   A  전체월      : %s", pr(a_full))
  wf("   A′ 전체월      : %s", pr(ap_full))
  wf("   A  A활성월     : %s   ← 기준", pr(a_match))
  wf("   A′ A활성월(창-정합): %s   ← 오염 여부는 여기서만 읽는다", pr(ap_match))
  wf("   A′ A침묵월 단독: %s   ← 새로 열린 월의 고유 강도", pr(ap_new))
  if (is.finite(a_match$gap_t) && is.finite(ap_match$gap_t))
    wf("   ⇒ 창-정합 Δt = %+.2f (A′−A, 같은 월집합) | 전체월 Δt = %+.2f",
       ap_match$gap_t - a_match$gap_t, ap_full$gap_t - a_full$gap_t)
}
## 정확한 침묵월 max z (표시 반올림 방지)
I2 <- as.data.table(read_parquet(file.path(OUT, "r43_live_monthly_maxz.parquet")))
sm <- I2[n_ge1 == 0]
wf("\n[boundary] 침묵월 max z 최대값 = %.10f (문턱 1.0 미달 확인) | 침묵월 %d개", max(sm$max_z), nrow(sm))
write_json(list(A_active_months=length(A_MONTHS), total_months=uniqueN(U$hold_ym),
                decomposition=lapply(DEC, function(x) lapply(x, function(y)
                  list(gap_ann=round(y$gap_ann,5), gap_t=round(y$gap_t,3), n_months=y$n_months,
                       avg_target_mo=round(y$avg_target_mo,2)))),
                silent_month_max_z=max(sm$max_z), n_silent_months=nrow(sm)),
           file.path(OUT, "r43_decomposition.json"), auto_unbox=TRUE, pretty=TRUE, digits=6, na="null")
w("\nDECOMP_DONE"); cat("[SAVED]", file.path(OUT,"r43_decomposition.json"), "\n")
