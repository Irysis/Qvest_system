# fe_dfa_regimesignals_bl — DFA_RegimeSignals (논문명 기반: 'Dynamic Factor Allocation Leveraging
#   Regime-Switching Signals', Shu & Mulvey, JPM 51(3) 2025 / arXiv:2410.14841) KR 보정판의
#   BL 팩터 비중을 종목 스코어로 전파: Score_{i,t} = Σ_{f∈6} w^BL_{f,t} · Z_{f,i,t}
#   w^BL = FQ-239 v5 보정 회계 월말 비중 (M0-roll f15, TE3, 인과 c-캘리브 — t 종가까지 정보만)
#   Z    = load_month_factors(sig_date=t) Z_Score_Aligned (C13/14/15) — 스코어 t → 익월 적용(캐노니컬)
# 선행(INV-7 차별점 명기): 6월 stock25 변환 전수 음수는 **동월 결함 회계 상태** 위 실측(RAMP_SHUMULVEY_25STOCK_FAIL).
#   본 엔진 = 보정 상태·신규 vintage·알파서칭 하네스 공식 채점(hurdle_gate screen_route + L1 improvement_potential).
# 한계 명기: Market 성분 w[1]은 스코어에 미반영(상대 틸트만 전파) — 배포 형태 변환의 구조 한계.
stopifnot(exists("RAWDATA"), data.table::is.data.table(RAWDATA))
suppressPackageStartupMessages({library(arrow); library(quadprog); library(data.table)})
.PRJ <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
if (!exists("load_month_factors", mode="function"))
  source(file.path(.PRJ,"02_Infrastructure/factor_db/factor_db_connector.R"))

.Z5 <- readRDS(file.path(.PRJ,".cache/_smv_v5_f15_roll.rds"))
.cmat<-.Z5$cmat; .vme<-.Z5$view_me; .meix<-.Z5$meix; .medates<-.Z5$medates
.Ridx<-as.data.table(read_parquet(.Z5$idxfile))
.Ridx[,Date:=as.Date(Date)]; setorder(.Ridx,Date); .Ridx<-.Ridx[is.finite(Market)]
.IDX<-c("Market","Value","Size","Momentum","Quality","LowVol","Growth")
.Rm<-as.matrix(.Ridx[, .IDX, with=FALSE]); .Rm[!is.finite(.Rm)]<-0
.a126<-1-exp(log(0.5)/126); .Sacc<-matrix(0,7,7); .SigL<-vector("list",length(.medates)); .mi<-1L
for(.t in 1:nrow(.Rm)){ .x<-.Rm[.t,]; .Sacc<-.a126*tcrossprod(.x)+(1-.a126)*.Sacc
  if(.mi<=length(.meix)&&.t==.meix[.mi]){ if(.t>=130).SigL[[.mi]]<-.Sacc*252; .mi<-.mi+1L } }
.delta<-2.5; .wew<-rep(1/7,7); .P<-matrix(0,6,7); for(.j in 1:6).P[.j,1+.j]<-1; .P[,1]<--1
.solveMVO<-function(muv,Sig){ D<-.delta*Sig+diag(1e-6,7); A<-cbind(rep(1,7),diag(7)); b0<-c(1,rep(0,7))
  r<-tryCatch(quadprog::solve.QP(D,muv,A,b0,meq=1),error=function(e)NULL)
  if(is.null(r))return(.wew); pmax(r$solution,0)/sum(pmax(r$solution,0)) }
.bl_w<-function(Sig,vv,cc){ pri<-.delta*as.numeric(Sig%*%.wew)
  M<-.P%*%Sig%*%t(.P); Om<-cc*diag(diag(M))
  muBL<-pri+as.numeric(Sig%*%t(.P)%*%solve(M+Om,(vv-as.numeric(.P%*%pri))))
  .solveMVO(muBL,Sig) }
.kTE<-3L   # TE3 — prereg smv_v6 헤드라인 셀 (사전지정, 사후 선택 아님)
.FACM<-c(Value="V12_Composite_Value",Size="S01_Size",Momentum="M09_Composite_Mom",
         Quality="Q08_Composite_Quality",LowVol="D03_RealVol",Growth="GR07_Composite_Growth")
.rows<-list()
for(.mi2 in seq_along(.medates)){
  if(!is.finite(.cmat[.mi2,.kTE])) next
  .Sig<-.SigL[[.mi2]]; if(is.null(.Sig)) next
  .vv<-.vme[.mi2,]; if(any(!is.finite(.vv))) next
  .w<-.bl_w(.Sig,.vv,.cmat[.mi2,.kTE])
  .sd<-.medates[.mi2]
  .f<-tryCatch(as.data.table(load_month_factors(.sd,factor_names=unname(.FACM))),error=function(e)NULL)
  if(is.null(.f)||!nrow(.f)) next
  .zw<-dcast(.f[Factor_Name %in% unname(.FACM)], Ticker~Factor_Name, value.var="Z_Score_Aligned")
  .sc<-rep(0,nrow(.zw)); .wt<-.w[2:7]; names(.wt)<-names(.FACM)
  for(.nm in names(.FACM)){ .col<-.FACM[[.nm]]
    if(.col %in% names(.zw)){ .zz<-.zw[[.col]]; .zz[!is.finite(.zz)]<-0; .sc<-.sc+.wt[[.nm]]*.zz } }
  .rows[[length(.rows)+1]]<-data.table(Date=.sd, Ticker=.zw$Ticker, Score=.sc)
}
FACTORS<-rbindlist(.rows)
.liq<-RAWDATA[Date %in% unique(FACTORS$Date) & LiqPass==TRUE, .(Date,Ticker)]
FACTORS<-merge(FACTORS, .liq, by=c("Date","Ticker"))
FACTORS<-FACTORS[is.finite(Score)]
cat(sprintf("[fe_shumulvey_bl] FACTORS rows=%d | dates=%d (%s ~ %s)\n",
    nrow(FACTORS), uniqueN(FACTORS$Date), min(FACTORS$Date), max(FACTORS$Date)))
