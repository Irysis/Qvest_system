## run_mfro_r62_recency.R — R62: 최근 집중의 정체 (진단 라운드)
##
## ★사전 선언(결과 전 기록): R61 이 IS 활성SR 0.152 vs OOS 0.469 로 성과의 최근 집중을 실측했다.
##   DFA 아크는 같은 계통에서 clean 창 전체를 잃었다 — 2026(7개월, 표본 5.3%) 제외 시 PORT_t +1.015 -> -0.001.
##   질문 = MFRO 의 clean 결과도 소수 최근 구간에 얹혀 있는가?
##   ★예상: D1 단독 수치는 2026 제외로 상당히 줄지만, **D1-C1(신호 기여)은 살아남는다**고 예상한다.
##     근거 = R60 의 permB p=0.005 는 전 창 대상이고, 2026 은 무신호 대조에도 똑같이 들어간다.
##     즉 시대 효과는 양 팔이 공유하므로 차분에서 상쇄돼야 한다. 이 예상이 빗나가면 신호 기여가
##     2026 국소 현상이라는 뜻이고 R60 라벨을 재작성해야 한다.
##   ★이 라운드는 성과 개선을 주장하지 않는다. 판정은 '기여가 시대에 얹혀 있나' 하나다.
suppressPackageStartupMessages({library(data.table);library(arrow)});suppressMessages({library(sandwich);library(lmtest)})
setwd(Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
nwt<-function(x){x<-x[is.finite(x)];if(length(x)<12)return(NA);m<-lm(x~1);as.numeric(coeftest(m,vcov=sandwich::NeweyWest(m,lag=3,prewhite=F))[1,3])}
IRf<-function(x){x<-x[is.finite(x)];mean(x)/sd(x)*sqrt(12)}
Z<-readRDS(".cache/_mfro_r60.rds"); AR<-Z$AR; YM<-Z$YM; E<-Z$E; bmf<-Z$bmf
msk<-function(r,extra=NULL){s<-E$clean&is.finite(r$pr)&is.finite(bmf);if(!is.null(extra))s<-s&extra;s}
yr<-as.integer(substr(YM,1,4))

cat("=== R62 최근 집중 진단 ===\n\n[① 창 절단 사다리 — 각 팔 단독]\n")
CUT<-list(all=rep(TRUE,length(YM)), ex2026=yr<2026L, ex2025=yr<2025L, ex2024=yr<2024L, ex2023=yr<2023L)
cat(sprintf("  %-18s %s\n","arm","전체      2026제외  2025+제외 2024+제외 2023+제외"))
for(nm in c("D1_rotation_top5","C1_no_signal","D0_all21_tilt","AP_allpos_tilt")){
  r<-AR[[nm]]
  v<-sapply(names(CUT),function(cc){s<-msk(r,CUT[[cc]]);a<-(r$pr-bmf)[s];nwt(a)})
  n<-sapply(names(CUT),function(cc)sum(msk(r,CUT[[cc]])))
  cat(sprintf("  %-18s %s   (n= %s)\n",paste0(nm," pt"),paste(sprintf("%+8.3f",v),collapse=" "),
    paste(n,collapse="/")))}

cat("\n[★② 신호 기여(D1 - C1) — 시대 효과는 차분에서 상쇄되어야 한다]\n")
for(cc in names(CUT)){s<-msk(AR$D1_rotation_top5,CUT[[cc]])&msk(AR$C1_no_signal,CUT[[cc]])
  d<-(AR$D1_rotation_top5$pr-AR$C1_no_signal$pr)[s]
  cat(sprintf("  %-10s n=%3d  mean=%+.4f%%/월  NW-t=%+.3f  %s\n",cc,sum(s),100*mean(d),nwt(d),
    ifelse(is.finite(nwt(d))&&nwt(d)>0,"부호 유지","★부호 반전/소멸")))}

cat("\n[★③ 랭킹 고유 기여(D1 - AP) — 부호 스크린 제거 후]\n")
for(cc in names(CUT)){s<-msk(AR$D1_rotation_top5,CUT[[cc]])&msk(AR$AP_allpos_tilt,CUT[[cc]])
  d<-(AR$D1_rotation_top5$pr-AR$AP_allpos_tilt$pr)[s]
  cat(sprintf("  %-10s n=%3d  mean=%+.4f%%/월  NW-t=%+.3f\n",cc,sum(s),100*mean(d),nwt(d)))}

cat("\n[④ 연도별 활성 수익 — 어디에 몰려 있나]\n")
for(nm in c("D1_rotation_top5","C1_no_signal")){
  r<-AR[[nm]];s<-msk(r);a<-(r$pr-bmf)[s];y<-yr[s]
  T<-data.table(y=y,a=a)[,.(n=.N,mean_pct=100*mean(a),SR=IRf(a)),by=y][order(y)]
  cat(sprintf("  %s:\n",nm))
  for(i in seq_len(nrow(T))) cat(sprintf("    %d n=%2d  %+7.3f%%/월  SR %+6.3f\n",T$y[i],T$n[i],T$mean_pct[i],T$SR[i]))}

cat("\n[⑤ 기여 집중도 — 상위 월 제거]\n")
for(nm in c("D1_rotation_top5","C1_no_signal")){
  r<-AR[[nm]];s<-msk(r);a<-(r$pr-bmf)[s];o<-order(a,decreasing=TRUE)
  cat(sprintf("  %-18s 전체 %+.4f | 상위1제거 %+.4f | 상위3제거 %+.4f | 상위5제거 %+.4f (%%/월)\n",
    nm,100*mean(a),100*mean(a[-o[1]]),100*mean(a[-o[1:3]]),100*mean(a[-o[1:5]])))}
s<-msk(AR$D1_rotation_top5)&msk(AR$C1_no_signal)
d<-(AR$D1_rotation_top5$pr-AR$C1_no_signal$pr)[s];o<-order(d,decreasing=TRUE)
cat(sprintf("  %-18s 전체 %+.4f | 상위1제거 %+.4f | 상위3제거 %+.4f | 상위5제거 %+.4f (%%/월)\n",
  "D1-C1(기여)",100*mean(d),100*mean(d[-o[1]]),100*mean(d[-o[1:3]]),100*mean(d[-o[1:5]])))

cat("\n[⑥ 판정]\n")
s26<-msk(AR$D1_rotation_top5,CUT$ex2026)&msk(AR$C1_no_signal,CUT$ex2026)
d26<-(AR$D1_rotation_top5$pr-AR$C1_no_signal$pr)[s26]
sall<-msk(AR$D1_rotation_top5)&msk(AR$C1_no_signal)
dall<-(AR$D1_rotation_top5$pr-AR$C1_no_signal$pr)[sall]
keep<-is.finite(nwt(d26))&&nwt(d26)>0&&mean(d26)>0
cat(sprintf("  기여 전체 %+.4f%%/월(t %+.3f) -> 2026 제외 %+.4f%%/월(t %+.3f)\n",
  100*mean(dall),nwt(dall),100*mean(d26),nwt(d26)))
cat(sprintf("  ⇒ %s\n",ifelse(keep,
  "★신호 기여가 2026 을 빼도 부호·방향 유지 = 시대 아티팩트 아님(R60 라벨 유지)",
  "★신호 기여가 2026 에 의존 = R60 라벨 재작성 필요")))
saveRDS(list(CUT=CUT,yr=yr),".cache/_mfro_r62.rds")
cat("\nR62_DONE\n")
