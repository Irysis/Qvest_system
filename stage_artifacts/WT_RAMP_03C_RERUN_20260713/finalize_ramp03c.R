## finalize_ramp03c.R — post-2017 decay 증거 + 차트 + verdict.json
suppressPackageStartupMessages({library(data.table); library(jsonlite)})
setDTthreads(1)
suppressMessages({library(sandwich); library(lmtest)})
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
WT<-file.path(QM,"stage_artifacts/WT_RAMP_03C_RERUN_20260713")
SCR<-"C:/Users/99922/AppData/Local/Temp/claude/C--Users-99922-OneDrive-Quant-Module-Moltbot/3d6b0eb6-6786-4a56-916d-9681f94897fe/scratchpad"
source("02_Infrastructure/telegram/tg_chart_pack.R")
nwt<-function(x){x<-as.numeric(x);x<-x[is.finite(x)];if(length(x)<10)return(NA);as.numeric(coeftest(lm(x~1),vcov=sandwich::NeweyWest(lm(x~1),lag=3,prewhite=FALSE))[1,3])}
srf<-function(x){x<-x[is.finite(x)];if(length(x)<6)return(NA);mean(x)/sd(x)*sqrt(12)}

RR<-readRDS(file.path(SCR,"ramp03c_results.rds")); R<-RR$R; BKP<-RR$BKP
pr_proxy<-readRDS(file.path(SCR,"pr_capw_proxy_full.rds"))
pr_iks<-readRDS(file.path(SCR,"pr_capw_iks_full.rds"))

## ---- post-2017 decay (challenge #3) ----
decay<-function(pr,lab){pr<-as.data.table(pr); pr[,date:=as.Date(date)]; pr[,act:=ret_net-benchmark_ret]
  pre<-pr[date<as.Date("2017-01-01")]; pos<-pr[date>=as.Date("2017-01-01")]
  data.table(basis=lab, n_pre=nrow(pre), n_post=nrow(pos),
    pt_pre=nwt(pre$act), pt_post=nwt(pos$act),
    actSR_pre=srf(pre$act), actSR_post=srf(pos$act))}
DEC<-rbindlist(list(decay(pr_proxy,"proxy_capw"),decay(pr_iks,"iks200")))
cat("=== post-2017 decay (cap-w) ===\n"); print(DEC)

## ---- 차트 1: cap-w proxy full 표준 3종 ----
cap_full<-R[weighting=="capw"&bench=="proxy_capw"&window=="full"][1]
note<-sprintf("PORT_t %.2f(proxy)/%.2f(IKS200) · oos %.2f · calmar %.2f (essence)",
  cap_full$pt_capwt, R[weighting=="capw"&bench=="iks200"&window=="full"]$pt_capwt[1], cap_full$oos_ret, cap_full$calmar)
p1<-tg_chart_pack(pr_proxy, out_dir=WT, title="RAMP_03C 재현 (cap-weight)",
  bm_label="K200uKQ150 cap-w proxy", metrics_note=note, prefix="capw_")

## ---- 차트 2: PORT_t sweep (원 기록 vs 재현) ----
labs<-c("원기록(버그기·164mo)","재현 proxy(255mo)","재현 IKS200(255mo)","재현 IKS200(t164)")
vals<-c(2.98, cap_full$pt_capwt,
        R[weighting=="capw"&bench=="iks200"&window=="full"]$pt_capwt[1],
        R[weighting=="capw"&bench=="iks200"&window=="t164"]$pt_capwt[1])
p2<-tg_chart_sweep(labels=labs, values=vals, out_dir=WT,
  title="RAMP_03C PORT_t: 원기록 vs 재현", hline=2.95, hline_label="게이트 2.95",
  highlight="원기록(버그기·164mo)", filename="sweep_port_t.png")

## ---- 차트 3: 3-가중 PORT_t (cap-w = 최악, closet-indexing) ----
labs3<-c("EW","score-tilt","cap-weight")
vals3<-c(R[weighting=="ew"&bench=="proxy_capw"&window=="full"]$pt_capwt[1],
         R[weighting=="score"&bench=="proxy_capw"&window=="full"]$pt_capwt[1],
         cap_full$pt_capwt)
p3<-tg_chart_sweep(labels=labs3, values=vals3, out_dir=WT,
  title="가중별 PORT_t (proxy): cap-w가 최악", hline=2.95, hline_label="게이트 2.95",
  highlight="cap-weight", filename="sweep_weighting.png")

CHARTS<-c(p1, p2, p3)
cat("charts:\n"); cat(paste(CHARTS,collapse="\n"),"\n")

## ---- verdict.json ----
gate<-function(pt,oos,cal) c(port_t=isTRUE(pt>=2.95), oos=isTRUE(oos>=0.7), calmar=isTRUE(cal>=0.64))
v<-list(
  task="FQ-020 RAMP_03C_BOOKMOM_CAPW 단일 config 재현",
  strategy_id="RAMP_03C_BOOKMOM_CAPW", source_lcode="L-RAMP-20260620_184815",
  config_hash=RR$cfg_hash, pin_tag=RR$pin_tag,
  as_of_date="2026-07-13", generated_at=format(Sys.time(),"%Y-%m-%dT%H:%M:%S%z"),
  source_version="qvest_v8.3", security_id="Ticker(RAWDATA K200uKQ150)",
  original_record=list(pt=2.98, oos_retention=1.19, calmar=0.89, SR=0.99, window_mo=164, note="벤치버그기 측정·경계값+0.03·원 시계열 소실"),
  remeasured=list(
    proxy_full=as.list(R[weighting=="capw"&bench=="proxy_capw"&window=="full"][1,.(pt_capwt,oos_ret,calmar,SR,CAGR,MDD,net_IR,grade,n)]),
    proxy_t164=as.list(R[weighting=="capw"&bench=="proxy_capw"&window=="t164"][1,.(pt_capwt,oos_ret,calmar,SR,CAGR,MDD,net_IR,grade,n)]),
    iks200_full=as.list(R[weighting=="capw"&bench=="iks200"&window=="full"][1,.(pt_capwt,oos_ret,calmar,SR,CAGR,MDD,net_IR,grade,n)]),
    iks200_t164=as.list(R[weighting=="capw"&bench=="iks200"&window=="t164"][1,.(pt_capwt,oos_ret,calmar,SR,CAGR,MDD,net_IR,grade,n)]),
    alt_mom6_rez_proxy_full=as.list(R[weighting=="capw"&bench=="proxy_capw_ALTrez"&window=="full"][1,.(pt_capwt,oos_ret,calmar,grade)])),
  weighting_pattern=list(ew_pt=vals3[1], score_pt=vals3[2], capw_pt=vals3[3],
    note="원 기록은 cap-w가 최고(OOS레버 주장). 재현은 cap-w가 최악(EW/score PORT_t 4.25/4.26 > cap-w 2.98) — cap-tier localization / closet-indexing 정합"),
  decay_post2017=as.list(DEC),
  hard_verdict=list(
    proxy_full=as.list(gate(R[weighting=="capw"&bench=="proxy_capw"&window=="full"]$pt_capwt[1],R[weighting=="capw"&bench=="proxy_capw"&window=="full"]$oos_ret[1],R[weighting=="capw"&bench=="proxy_capw"&window=="full"]$calmar[1])),
    iks200_full=as.list(gate(R[weighting=="capw"&bench=="iks200"&window=="full"]$pt_capwt[1],R[weighting=="capw"&bench=="iks200"&window=="full"]$oos_ret[1],R[weighting=="capw"&bench=="iks200"&window=="full"]$calmar[1]))),
  verdict="DEMOTED — 재현 실패. authoritative 교정 IKS200 basis HARD 0/3, RAMP-native proxy basis 1/3(PORT_t만). oos_retention 1.19->0.22~0.41 붕괴 + calmar 0.89->0.42~0.60 붕괴 + cap-w OOS레버 기전 반전(cap-w=최악 가중). 원 2.98/1.19/0.89 = 벤치버그기+소실164mo창 아티팩트. config-scoped negative.",
  original_config_fidelity="high(pt 2.98 proxy-full exact match) — construction 복원 충실. 단 164mo 정확 월-집합은 _bo_fwdgic 소실로 미복원(full+t164 병기로 대체)",
  benchmark_basis_note="원 RAMP는 IKS를 쓰지 않고 build_monthly_forward_returns cap-w K200uKQ150 proxy 사용 — 'IKS001->IKS200 벤치버그'는 RAMP에 직접 비적용. RAMP 벤치버그=RAWDATA April-gap(말단 1mo, 영향 미미). authoritative 판정은 태스크 지정 교정 IKS200 채택(보수적)",
  capital_note="자본 편입 = governor 정지(도훈 수동). 본 재현은 편입 근거 아님(FAIL)."
)
writeLines(toJSON(v,auto_unbox=TRUE,pretty=TRUE,null="null"), file.path(WT,"verdict.json"))
cat("VERDICT written.\n")
saveRDS(list(CHARTS=CHARTS,DEC=DEC,v=v), file.path(SCR,"ramp03c_final.rds"))
cat("FINALIZE_DONE\n")
