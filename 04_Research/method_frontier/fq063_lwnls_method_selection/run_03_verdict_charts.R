# =============================================================================
# FQ-063 run_03: verdict JSON + 차트팩(방법×Σ PORT_t 막대 sweep)
# =============================================================================
suppressPackageStartupMessages({ library(jsonlite); library(data.table); library(arrow) })
ROOT<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
OUT_DIR<-file.path(ROOT,"stage_artifacts/method_frontier")
m<-fromJSON(file.path(OUT_DIR,"fq063_metrics.json"), simplifyVector=FALSE)
sl<-as.data.table(fromJSON(file.path(OUT_DIR,"fq063_shopping_log.json"))$shopping_log)
cellreg<-fromJSON(file.path(OUT_DIR,"fq063_cell_registry.json"), simplifyVector=FALSE)
setorder(sl,-port_t_capw)

# ---- Chart 1: 전 셀 PORT_t(cap-w) 막대 sweep, 기준선 표시 ------------------
png(file.path(OUT_DIR,"fq063_chart_sweep_port_t.png"), width=1400, height=900, res=130)
par(mar=c(4,11,3,2))
d<-sl[order(port_t_capw)]
cols<-ifelse(d$cell %in% c("A_EW","A_LinearTilt","A_prodLT20"), "#1f77b4",
        ifelse(startsWith(d$cell,"A_"), "#ff7f0e", "#7f7f7f"))
bp<-barplot(d$port_t_capw, horiz=TRUE, names.arg=d$cell, las=1, cex.names=0.62,
   col=cols, xlim=c(min(d$port_t_capw)-0.3, 2.4), border=NA,
   main="FQ-063 canonical PORT_t (cap-w) — 비중결정 방법 스윕 (production STR_1715 score)")
base_lt<-m$baseline_best_port_t
abline(v=base_lt, col="#1f77b4", lwd=2, lty=2)
abline(v=2.082, col="#2ca02c", lwd=2, lty=3)
abline(v=2.95, col="red", lwd=1.5, lty=1)
text(base_lt, 1, sprintf("LinearTilt %.2f", base_lt), col="#1f77b4", pos=4, cex=0.7)
text(2.082, 3, "prodLT20 2.08", col="#2ca02c", pos=4, cex=0.7)
text(2.95, 5, "grad HARD 2.95", col="red", pos=4, cex=0.7)
legend("bottomright", c("baseline(EW/LinearTilt/prodLT20)","Mode A sweep","Mode B risk-select"),
   fill=c("#1f77b4","#ff7f0e","#7f7f7f"), bty="n", cex=0.7)
dev.off()

# ---- Chart 2: Mode B — Σ(sample/lwlin/lwnls) × method(GMV/MaxDiv/HRP) × variant ----
png(file.path(OUT_DIR,"fq063_chart_modeB_sigma.png"), width=1300, height=800, res=130)
par(mar=c(6,4,3,2))
b<-sl[startsWith(cell,"B_")]
b[, sig:=sapply(cell, function(c) cellreg[[c]]$sigma)]
b[, mv:=sapply(cell, function(c) paste0(cellreg[[c]]$method,"_",cellreg[[c]]$variant))]
bw<-dcast(b, mv~sig, value.var="port_t_capw")
mm<-as.matrix(bw[,-1]); rownames(mm)<-bw$mv
cols2<-c(ledoit_wolf="#d62728", lw_nls="#2ca02c", sample="#9467bd")
mm<-mm[, intersect(c("sample","ledoit_wolf","lw_nls"), colnames(mm)), drop=FALSE]
barplot(t(mm), beside=TRUE, las=2, cex.names=0.7, col=cols2[colnames(mm)], border=NA,
   ylim=c(min(mm,na.rm=TRUE)-0.2, max(0.2,max(mm,na.rm=TRUE))),
   main="FQ-063 Mode B: Σ A/B × 위험방법 canonical PORT_t (cap-w)  [lw_nls 퇴화교정 물리는 영역]")
abline(h=0, col="grey40"); abline(h=base_lt, col="#1f77b4", lwd=2, lty=2)
legend("topright", c("sample","linear LW(μI 퇴화)","lw_nls(교정)","baseline LinearTilt"),
   fill=c("#9467bd","#d62728","#2ca02c",NA), border=c(NA,NA,NA,NA),
   lty=c(NA,NA,NA,2), col=c(NA,NA,NA,"#1f77b4"), bty="n", cex=0.65)
dev.off()
cat("[charts] written\n")

# ---- verdict JSON ----------------------------------------------------------
gp<-function(c) m$cells[[c]]
baseline_best<-m$baseline_best; best<-m$best_overall
pv_lt<-m$paired_best_vs_baseline$A_LinearTilt; pv_ew<-m$paired_best_vs_baseline$A_EW

# mode B lw_nls 셀 추출
bcells<-sl[startsWith(cell,"B_")]
lwnls_cells<-bcells[grepl("lwnls",cell)]
lwlin_deg<-sl[cell %in% c("B_GMV_lwlin_pure","B_MaxDiv_lwlin_pure")]

verdict<-list(
  id="FQ-063", lane="method_frontier", round_type="independent_research_round_not_WT",
  agent="optimizer-research", finalized_at=format(Sys.time(),"%Y-%m-%d %H:%M:%S"),
  pin_tag="fq057_20260718_171024",
  preregistration_ref="stage_artifacts/method_frontier/fq063_preregistration.json",
  hypothesis=paste0("production STR_1715 score_eff 알파 위에서 비중결정 방법을 lw_nls 기반으로 고르면",
    "(Mode A 8-방법 스윕 / Mode B 대형-유니버스 위험선택 3-방법 × Σ 3-A/B) best-of-sweep canonical PORT_t가 ",
    "EW/LinearTilt 기준선을 유의 초과하는가"),
  verdict=paste0("config_scoped_negative — best-of-sweep(A_CVaR PORT_t ",gp(best)$port_t_capw,
    ")가 baseline(LinearTilt ",m$baseline_best_port_t,", incumbent prodLT20 2.082)을 초과 못함(paired NW-t vs LinearTilt ",
    pv_lt$nw_t_lag3,", ann_diff ",pv_lt$ann_diff,"). 27셀 전부 graduation HARD FAIL·DSR ",m$dsr$dsr_best,
    "<0.5. Mode B lw_nls 퇴화교정 셀 전부 PORT_t 음수/영. ⑤비중 층 소진을 MVO-only(NP4)->전방법 실측 확정."),
  metric_type="optimizer_lane_ab_diagnostic",
  capital_claim=FALSE, graduation_claim=FALSE,
  selection_objective="net_ir (paired canonical PORT_t, NW lag3) — sweep형 argmax, DSR HARD 적용",
  n_months=m$n_months, n_cells=m$n_cells,

  mode_A_results=list(
    design="score_eff top-25 고정 선택 위 비중 스윕, Σ=lw_nls 25x25(p<n->sample tie)",
    ranking_port_t_capw=setNames(lapply(sl[startsWith(cell,"A_")][order(-port_t_capw), cell],
      function(c) gp(c)$port_t_capw), sl[startsWith(cell,"A_")][order(-port_t_capw), cell]),
    finding=paste0("알파비례(prodLT20 2.082 > LinearTilt-25 1.756)가 전 최적화/위험방법 지배. ",
      "위험기반(GMV -0.405/MaxDiv -0.110/HRP -0.059/ERC 0.099)은 알파 무시로 EW(0.464)보다도 열등. ",
      "알파 쓰는 방법(MVO 0.747·CVaR 0.906)도 알파비례 tilt에 미달. ",
      "★top-20 vs top-25(prodLT20 2.082 vs LinearTilt 1.756, +0.33)이 어떤 비중-방법 차이보다 큰 레버 = Grinold breadth(선택/집중>사이징)")),

  mode_B_results=list(
    design="full elig(p≈300>n=60) 위험방법(GMV/MaxDiv/HRP) Σ 구조로 25종 선택+비중, Σ 3-A/B, pure/alpha 2변형",
    ranking_port_t_capw=setNames(lapply(bcells[order(-port_t_capw), cell],
      function(c) gp(c)$port_t_capw), bcells[order(-port_t_capw), cell]),
    lwlin_degeneracy_visible=paste0("linear LW p>n μI 퇴화(cond≈1, 197/197월) -> GMV=MaxDiv=EW-over-all -> ",
      "B_GMV_lwlin_pure == B_MaxDiv_lwlin_pure 동일(PORT_t -0.785·oos 3.43·TO 1.41) = 위험선택 불능(임의 top-25)"),
    lwnls_correction_finding=paste0("★핵심: lw_nls는 퇴화교정으로 GMV≠MaxDiv 진짜 min-var 포트 생성(NP4 미측정 영역)하나 ",
      "그 포트는 저변동/방어 집중으로 알파 edge 부재 -> PORT_t 오히려 더 음수(GMV_lwnls_pure -1.052·MaxDiv_lwnls_pure -1.118, ",
      "퇴화 lwlin -0.785보다도 낮음). alpha_combined(위험선택×LinearTilt) 재적용해도 best 0.076(HRP_lwlin_alpha)·lwnls best 0.051 ≪ baseline. ",
      "= lw_nls 퇴화교정이 '작동'하나 위험선택 자체가 알파선택 대체라 PORT_t 미달 — NP4 외삽('estimator-무관')을 전방법 실측으로 확정")),

  method_shopping_log=lapply(seq_len(nrow(sl)), function(i) list(
    cell=sl$cell[i], mode=sl$mode[i], method=sl$method[i], sigma=sl$sigma[i], variant=sl$variant[i],
    port_t_capw=sl$port_t_capw[i], port_t_ew=sl$port_t_ew[i], calmar=sl$calmar[i],
    oos_v2_median=sl$oos_v2_median[i], to_oneway_annual=sl$to_oneway_annual[i],
    to_le_11=sl$to_ok[i], grad_hard_pass=sl$grad_hard_pass[i])),

  best_vs_baseline_paired=list(
    baseline_best=baseline_best, baseline_best_port_t=m$baseline_best_port_t,
    incumbent_ref="A_prodLT20 (top-20 LinearTilt, PORT_t 2.082 = 전 셀 최고)",
    best_of_sweep=best, best_of_sweep_port_t=gp(best)$port_t_capw,
    vs_LinearTilt=list(nw_t_lag3=pv_lt$nw_t_lag3, n=pv_lt$n, ann_diff=pv_lt$ann_diff,
      exceed=FALSE, note="best-of-sweep가 LinearTilt 미달(방향 음, |t|<2 비유의 — 초과 아님)"),
    vs_EW=list(nw_t_lag3=pv_ew$nw_t_lag3, n=pv_ew$n, ann_diff=pv_ew$ann_diff,
      note="best-of-sweep(CVaR)≈EW 근방(비유의) — 둘 다 LinearTilt 미달")),

  dsr=list(n_trials=m$dsr$n_trials, sr_star_monthly=m$dsr$sr_star_monthly,
    dsr_best=m$dsr$dsr_best, pass=m$dsr$pass,
    note="sweep형 24-셀 argmax -> DSR HARD. best(A_CVaR) DSR 0.247<0.5 FAIL (baseline 미달이라 moot이나 게이트 준수)"),

  dual_basis=list(
    finding="상대 순위 cap-w·EW-uni 양 basis 강건: 양 basis 공히 prodLT20>LinearTilt>CVaR>MVO>EW>위험방법. ",
    note="EW-uni PORT_t가 전반 높음(cap-w mega-regime 아티팩트, 기존 지식 정합)이나 방법 간 순위 불변 -> '알파비례 지배'는 벤치-basis 무관",
    captier=lapply(names(m$dual_basis$cells), function(nm){ c<-m$dual_basis$cells[[nm]]
      list(cell=nm, port_t_capw=c$port_t_capw, port_t_ew=c$port_t_ew,
           MEGA=c$captier$MEGA, MID=c$captier$MID, SMALL=c$captier$SMALL) })),

  hard_constraints_audit=list(
    max_names_25="PASS (run_01 stopifnot 전 셀 감사)", long_only="PASS", weight_bounds_0_020="PASS",
    sum_w_1="PASS", liquidity_t1_2e8="PASS (AvgTV20 t-1)",
    cost_model="15bps one-way delta (BOP vs 전월 EOP)",
    turnover_note=m$turnover_note,
    rf_o9_walk_forward="PASS — fq063_weights.parquet 197 as_of_date 시계열 schedule(single-snapshot 아님)"),

  mechanism_diagnosis=list(
    alpha_proportional_dominates="LinearTilt(알파비례)가 모든 최적화/위험방법 지배 — single-cluster book서 위험기반 배분은 알파 희석(07-03 HRP frontier 재확인·전방법 확장). 알파 쓰는 MVO/CVaR도 λ/위험항이 tilt를 알파에서 멀어지게 해 미달.",
    risk_selection_abandons_alpha="Mode B 위험선택은 저변동 종목 선택 = 알파선택 대체. lw_nls가 그 선택을 well-conditioned로 실현할수록(진짜 min-var) 알파에서 더 멀어져 PORT_t 더 음수. '직교≠수익'·min-var-settled 벽의 전방법 재현.",
    lwnls_is_risk_axis_not_return_axis="NP4(MVO-only) '위험-축만 전이·평균-축 NULL'을 전방법으로 확장 확정: lw_nls 우위는 estimation-quality/위험-축이지 성과(평균)-축 레버 아님. 대형-Σ 소비면(risk_package)은 P1/P1c 유지, optimizer 성과-축은 미달.",
    breadth_over_sizing="prodLT20(top-20) vs top-25 +0.33 PORT_t가 최대 레버 = 사이징 방법이 아니라 선택 breadth/집중(Grinold IR=IC√breadth)이 지배."),

  limitations=list(
    "단일 알파(production STR_1715 score_eff) config — 알파-족 일반화 아님. 단 NP4(12-1 모멘텀)와 2개 상이 알파서 동일 결론(방법-무관 소진).",
    "Mode A Σ=lw_nls는 p(25)<n(60)라 sample과 tie(P1c) — mode A는 lw_nls 테스트 아니라 '비중-방법 완결성'(NP4 확장). lw_nls 고유가치는 mode B에서 시험.",
    "Mode B GMV/MaxDiv 카디널리티=full해->top25 재해 휴리스틱(정확 cardinality min-var은 NP-hard). 단 alpha_combined 변형이 위험선택에 최선 기회 부여해도 미달.",
    "sample p>n 특이 -> make_pd ridge 정규화(사실상 shrunk-GMV) — sample 대형-Σ 부적격의 방증이자 결론 불변(음수 PORT_t).",
    "알파 자체 post-2017 감쇠(baseline 1.76<2.95) — 단 판정은 RELATIVE(방법 부가가치)이지 절대 graduation 아님. 약한 알파일수록 좋은 Σ 여지 큰데도 어느 방법도 baseline 초과 못함(약-알파 caveat이 method selection 구제 못함).",
    "TO>11(mode A 전체, baseline 포함)=월간 top-25 스케줄 속성, 방법-판별자 아님(binding=PORT_t)."),

  next_probes=list(
    list(id="NP1", title="multi-sleeve 성립 시 위험기반 배분 재측정",
      detail="위험방법(HRP/GMV)의 평균-축 가치는 이질 sleeve 간 배분에서 발생 여지 — single-alpha top-25 corner 해서는 기계적 억제. admitted sleeves>=2(INV-7) 트리거 시 재측정(NP4-P2와 동일 조건)."),
    list(id="NP2", title="TC-aware MVO(turnover_penalty 배선 후) no-trade region 재측정",
      detail="mvo v2.4가 phi*|x-x_prev| L1 배선(07-18) — mode A MVO/저-TO 위험방법에 no-trade region 적용해 순-격차 회복분 측정. 단 gross가 주인이라 판정 반전 기대 낮음(정직 기록).")),

  revival_or_followup_conditions=list(
    "optimizer 성과-축 방법 재탕: multi-sleeve book 성립 또는 cap-w PORT_t 2.95 통과 알파 등장(전이 벽 이동) 시에만(INV-7). 그 전 동형 재탕 금지.",
    "lw_nls WT-시점 소비 자격(NP3 등재)은 estimation-quality/위험-축 근거로 유지 — 본 라운드가 '성과-축 개선 불가' 라벨의 전방법 실측 경계.",
    "위험기반 배분(HRP/ERC/GMV/MaxDiv)은 single-cluster long-only book서 알파비례 대비 열등 확정 — 부활=multi-sleeve(NP1)."),

  bottleneck_map_update_proposal=paste0("5행(비중): 'NP4 실측(MVO Σ-swap NULL)' -> '전방법 실측 완료(FQ-063): ",
    "8-비중방법(EW/LinearTilt/MVO/GMV/HRP/ERC/MaxDiv/CVaR) + 대형-유니버스 위험선택(GMV/MaxDiv/HRP)×Σ 3-A/B 27셀 ",
    "전부 알파비례 baseline(LinearTilt 1.756/prodLT20 2.082) 미달·graduation HARD 0/27·DSR FAIL. ",
    "lw_nls 퇴화교정이 물리는 mode B서도 위험선택은 알파포기라 PORT_t 음수. ⑤비중 소진 = MVO-only->전방법 확정·강화. ",
    "잔여 = multi-sleeve 조건부(NP1)·TC-aware(NP2)'. 갭 귀속(①재료) 불변."),

  artifacts=list(
    runner_dir="04_Research/method_frontier/fq063_lwnls_method_selection/",
    preregistration="stage_artifacts/method_frontier/fq063_preregistration.json",
    weights="stage_artifacts/method_frontier/fq063_weights.parquet (197 as_of_date x 27 cell)",
    series="stage_artifacts/method_frontier/fq063_series.parquet",
    metrics="stage_artifacts/method_frontier/fq063_metrics.json",
    shopping_log="stage_artifacts/method_frontier/fq063_shopping_log.json",
    cell_registry="stage_artifacts/method_frontier/fq063_cell_registry.json",
    challenge_note="stage_artifacts/method_frontier/fq063_challenge_note.md",
    charts=c("stage_artifacts/method_frontier/fq063_chart_sweep_port_t.png",
             "stage_artifacts/method_frontier/fq063_chart_modeB_sigma.png"))
)
write_json(verdict, file.path(OUT_DIR,"fq063_verdict.json"), auto_unbox=TRUE, pretty=TRUE, digits=6)
cat("[verdict] written:", file.path(OUT_DIR,"fq063_verdict.json"),"\n")
cat("[done] run_03\n")
