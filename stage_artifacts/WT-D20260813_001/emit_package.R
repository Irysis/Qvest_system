## Emit optimization_package.json
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)})
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
WT<-"WT-D20260813_001";SA<-file.path("stage_artifacts",WT);MB<-file.path("qepm/mailbox/worktask",WT)
fw<-readRDS(file.path(SA,"final_weights.rds")); tw<-fw$tw; snap<-fw$snap
ap<-fromJSON(file.path(MB,"alpha_package.json"),simplifyVector=FALSE)
av<-names(unlist(ap$alpha_vector))
tw<-round(tw[av],6); tw[is.na(tw)]<-0
# fix rounding so sum==1 exactly
resid<-1-sum(tw); tw[which.max(tw)]<-tw[which.max(tw)]+resid
stopifnot(abs(sum(tw)-1)<1e-6, max(tw)<=0.2001, min(tw)>=0, length(tw)==25)

sched<-fread(file.path(SA,"weights.csv"))
# sector weights post-opt (current snapshot)
snap2<-fw$snap
secw<-snap2[,.(w=sum(weight)),by=sector][order(-w)]
sector_weights<-setNames(round(secw$w,4),secw$sector)

# active weights vs current_portfolio unknown at name level; report vs EW(1/25) as neutral active basis
active<-round(tw-1/25,6)

eff_n<-round(1/sum(tw^2),2)

pkg<-list(
  task_id=WT,
  as_of_date="2026-08-22",
  agent="optimizer_research_v1.3",
  method="EW_top25_with_semiconductor_cap_0.50",
  method_selected="EW_top25_semicap50",
  selection_objective="net_ir",
  selection_type="chain",
  method_rationale=paste0(
    "alpha research_verdict=NOT_SUPPORTED (paired NW3 t=+0.828), rank-IC=-0.028(음수)·decile-mono +0.964 ",
    "= 신호 약함·순위력↔소비 불일치. DeMiguel-Garlappi-Uppal 2009 1/N OOS 우위 정합: 약한 알파에서 ",
    "MVO/AlphaTilt sizing 은 섹터집중(반도체 56→67%)·vol(52.6→70%) 악화. score-tilt 개선은 IS/OOS split 에서 ",
    "부호반전(IS delta -0.16, OOS +0.18) = 비robust. 완전강도 tilt/InvVol 은 turnover cap 11.0 초과(12.3~12.6). ",
    "turnover-feasible blend(theta<=0.19) 도 개선 미미·비robust. ⇒ selection(top-25)=edge, sizing 아님. ",
    "EW 채택 + 반도체 50% cap(historical 2/199 dates만 binding·net SR delta +0.0003·MDD 불변 = costless safeguard, ",
    "현 regime 64% 집중 book 만 64→50% 완화). risk_package Σ(walk-forward 미제공)로 HRP/ERC/MVO 는 snapshot 진단만."
  ),
  target_weights=as.list(tw),
  active_weights_vs_ew=as.list(active),
  optimization_diagnostics=list(
    n_names=25L,
    max_weight=round(max(tw),4),
    min_weight=round(min(tw),4),
    effective_n=eff_n,
    hhi=round(sum(tw^2),4),
    sector_weights_post_opt=as.list(sector_weights),
    semiconductor_weight_current=round(sum(snap2[sector=="반도체"]$weight),4),
    expected_te="not_estimated_two_stage_ew",
    walkforward_net_sr_selected=0.6046,
    walkforward_net_sr_ew_baseline=0.6042,
    walkforward_port_t_nw3=0.9267,
    walkforward_active_ir=0.2569,
    walkforward_cagr=0.1541,
    walkforward_mdd=0.6701,
    walkforward_calmar=0.2300,
    ann_turnover_estimate=10.62,
    schedule_unique_dates=199L,
    schedule_density_ratio=1.0
  ),
  method_comparison=list(
    EW=list(net_sr=0.6042,port_t=0.9256,ann_turnover=10.61,mdd=0.6701,semi_wt_hist=0.073,note="baseline·selected(+semicap)"),
    ScoreTilt_full=list(net_sr=0.6505,port_t=1.5820,ann_turnover=12.56,mdd=0.7302,note="DISQUALIFIED turnover>11.0·IS/OOS 부호반전"),
    InvVol_full=list(net_sr=0.6513,port_t=1.1517,ann_turnover=12.27,mdd=0.7052,note="DISQUALIFIED turnover>11.0"),
    Blend_theta0.19=list(net_sr=0.6248,port_t=1.0933,ann_turnover=10.98,mdd=0.6779,note="feasible max tilt·개선 미미·비robust"),
    MVO_snapshot=list(vol_ann=0.5735,eff_n=15,semi_wt=0.667,note="snapshot only·섹터집중 악화"),
    HRP_snapshot=list(vol_ann=0.4644,eff_n=18.1,semi_wt=0.564,note="snapshot only·Σ walk-forward 미제공"),
    ERC_snapshot=list(vol_ann=0.4748,eff_n=22.3,semi_wt=0.523,note="snapshot only·Σ walk-forward 미제공")
  ),
  liquidity_flags=list(),
  liquidity_note="25/25 종목 20일 평균 거래대금 >= 2e8 KRW (RAWDATA Close*Vol, PIT <=sig_date). 미달 0.",
  concentration_flags=list(
    "risk RF-R1: 현 book 반도체 16/25 (64% natural EW) — semicap 0.50 으로 50% 완화 적용",
    "historical semi share mean 7.2%·median 4%·cap binding 2/199 dates only (현 regime anomaly)",
    "MDD 67% 는 섹터 아닌 시장 beta(0.78)·2018/2022 drawdown 구동 — sector cap 이 MDD 불변시킴(cap 무효 아님·MDD 원인이 sector 아님을 실증)"
  ),
  method_shopping_log=list(
    posterior_default=TRUE,
    posterior_note="약한알파·two-stage·multi-sleeve 미성립 → sweep 트리거 미발화(v1.3 posterior-default). full sweep 미실시.",
    candidates_tried=7L,
    method_log=list(
      list(name="EW_top25_semicap50",net_ir=0.2569,selected=TRUE),
      list(name="ScoreTilt_full",net_ir=0.4028,selected=FALSE,disqualify="turnover_cap_11.0"),
      list(name="InvVol_full",net_ir=0.3293,selected=FALSE,disqualify="turnover_cap_11.0"),
      list(name="Blend_theta0.19",net_ir=0.2974,selected=FALSE,reason="non_robust_marginal"),
      list(name="MVO_lambda_grid",net_ir=NA,selected=FALSE,reason="snapshot_concentration_worse"),
      list(name="HRP_from_cov",net_ir=NA,selected=FALSE,reason="sigma_walkforward_unavailable"),
      list(name="ERC",net_ir=NA,selected=FALSE,reason="sigma_walkforward_unavailable")
    )
  ),
  binding_constraints=list("turnover_cap_annual_11.0 (tilt/invvol 계열 disqualify)","sector_semiconductor_cap_0.50 (현 book 2 dates binding)"),
  infeasibility_report=NULL,
  challenge_flags=list(
    "[EW 정당성] score-tilt 개선이 IS/OOS split 에서 부호반전(IS -0.16/OOS +0.18) — 약한 알파(NOT_SUPPORTED·rank-IC -0.028)에서 sizing edge 는 noise. DeMiguel-Garlappi-Uppal 1/N 우위 정합.",
    "[turnover 방화벽] full-strength tilt/InvVol net SR 은 높으나(0.65) turnover 12.3~12.6 > 11.0 cap → silent relaxation 금지·DISQUALIFY. 도훈 mandate 준수.",
    "[sector cap = costless safeguard] 반도체 50% cap 은 historical net SR delta +0.0003·MDD 불변·2/199 dates 만 binding. 현 regime 의 64% 집중만 완화. 성과희생 없이 RF-R1 대응.",
    "[MDD 원인 분리] MDD 67% 는 sector 집중이 아니라 market beta·구조적 drawdown(2018/2022). sector cap 이 MDD 를 못 낮춘다 = cap 무용이 아니라 MDD 원인이 sector 가 아님을 실증. MDD graduation 미달은 표적/alpha 층 문제.",
    "[Σ walk-forward 부재 = risk 경계] HRP/ERC/MVO 는 date별 Σ 재추정 필요(risk agent 25명 snapshot Σ만 제공). optimizer 가 Σ 를 만들면 역할경계 침범 → snapshot 진단만·스케줄 미적용. 정직 보고.",
    "[자본 자격 아님·정직 라벨] walkforward net SR 0.605·PORT_t 0.927·MDD 67%·Calmar 0.230 — graduation HARD 3종(PORT_t 2.95·oos 0.7·calmar 0.64) 전부 미충족. weights 는 forge 백테스트/judge 심사용 진단이지 편입 후보 아님. upstream research_verdict=NOT_SUPPORTED."
  ),
  selected_series_walkforward=list(
    basis="Return.portfolio_equivalent_delta_cost (PerformanceAnalytics SharpeRatio.annualized/Return.annualized/maxDrawdown)",
    method_basis_label="optimizer_walk_forward_simulation",
    production_grade=FALSE,
    production_grade_note="optimizer walk-forward simulation (EW top-N with per-date sector cap). NOT forge-authoritative build_bt_result — PG2 admission 부적격. forge 재측정 필요."
  ),
  metric_type="canonical_screen_diag",
  tier="screen_diagnostic",
  scope_note="Optimization diagnostic only. upstream research_verdict=NOT_SUPPORTED (config-scoped negative). Weights = EW top-25 + semiconductor cap 0.50 for forge backtest. graduation HARD 3종 통과 주장 아님. selection=edge, sizing 아님(DeMiguel-Garlappi-Uppal)."
)
write_json(pkg, file.path(MB,"optimization_package.json"), pretty=TRUE, auto_unbox=TRUE, null="null", digits=8)
cat("PACKAGE_WRITTEN sumw=",sum(tw)," maxw=",max(tw)," n=",length(tw),"\n")
