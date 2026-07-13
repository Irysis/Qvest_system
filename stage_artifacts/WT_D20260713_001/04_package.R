#==============================================================================
# WT-D20260713_001 R17 — Step 04: emit alpha_scores.parquet + alpha_validation.json
#                                  + alpha_package.json + lineage
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
setDTthreads(1L); try(arrow::set_io_thread_count(2L), silent=TRUE)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT  <- file.path(ROOT,"stage_artifacts/WT_D20260713_001")
MB   <- file.path(ROOT,"qepm/mailbox/worktask/WT-D20260713_001")
res  <- readRDS(file.path(OUT,"canon_results.rds"))

# unified alpha_scores.parquet (all 3 factors, long)
sA<-as.data.table(read_parquet(file.path(OUT,"scores_FA.parquet")))[,factor:="F-A"]
sB<-as.data.table(read_parquet(file.path(OUT,"scores_FB.parquet")))[,factor:="F-B"]
sC<-as.data.table(read_parquet(file.path(OUT,"scores_FC.parquet")))[,factor:="F-C"]
allsc <- rbindlist(list(sA,sB,sC), fill=TRUE)[,.(Date,Ticker,factor,score)]
write_parquet(allsc, file.path(OUT,"alpha_scores.parquet"))

# lead factor latest-month alpha_vector (F-B, representative — none graduate)
lead<-"F-B"; slead<-as.data.table(read_parquet(file.path(OUT,"scores_FB.parquet")))
lastd<-max(slead$Date); av<-slead[Date==lastd]
alpha_vector<-as.list(setNames(round(av$score,4),av$Ticker))
conf<-as.list(setNames(round(pmin(1,pmax(0,0.3+0.1*abs(av$score))),3),av$Ticker))

f2 <- function(x) if(is.null(x)||!is.finite(x)) NA else round(x,4)
mk <- function(r) list(
  cap_w_port_t_nw_lag3=f2(r$port_t_full), cap_w_port_pvalue=f2(r$port_p),
  port_t_IS=f2(r$port_t_IS), port_t_OOS=f2(r$port_t_OOS),
  ew_uni_t=f2(r$ew_t), ew_uni_post2017_t=f2(r$ew_post2017_t), ew_uni_oos_retention_approx=f2(r$ew_oos_ret),
  cap_tier_weight_share=list(MEGA=f2(r$mega_w),MID=f2(r$mid_w),OTHER=f2(r$other_w)),
  rank_ic=f2(r$rank_ic), icir=f2(r$icir), rank_ic_t=f2(r$ric_t),
  size_partial_cap_w_port_t=f2(r$szpartial_port_t),
  placebo_p_value=f2(r$placebo_p), placebo_base=f2(r$placebo_base),
  net_sr=f2(r$net_sr), calmar=f2(r$calmar), turnover_annual=f2(r$turnover), n_months=r$n_months)

validation <- list(
  wt_id="WT-D20260713_001", iteration="R17", frontier_id="FQ-030",
  preregistration_sha256=readLines(file.path(OUT,"preregistration.sha256")),
  metric_type="canonical_screen", selection_authority="cap-w portfolio_alpha_t_nw_lag3 (NW lag-3)",
  hard_gates=list(PORT_t=2.95, oos_retention=0.7, calmar=0.64, DSR=0.5),
  n_trials=3, selection_type="sweep",
  factors=list("F-A"=mk(res$FA), "F-B"=mk(res$FB), "F-C"=mk(res$FC)),
  fa_decomposition=list(note="단일지표 분해 — cos-only/jac-only 동일(0.67, EW-uni 음수) → 합성 은폐 아님, 진짜 null. INVERTED sign(low-sim long) cap-w 1.38·EW-uni 0.33 = post-hoc(사전등록 아님)·sub-threshold — KR Lazy Prices 부호 반전 가능성 next_probe",
    cos_only_cap_w_t=0.67, jac_only_cap_w_t=0.67, cos_jac_cor=0.86,
    inverted_cap_w_t=1.38, inverted_ew_uni_t=0.33),
  universe_comparison=list(
    note="cap-w HARD 판정 권위 불변. EW-uni는 진단 병기(canonical_screen_diag). 3종 모두 cap-w<2.95 AND EW-uni도 미생존(F-A 음수·F-B 0.46·F-C 0.26). 감쇠=벤치 아티팩트 아님(EW-uni도 약함).",
    KR_top342="cap-w authoritative (위 factors)", KR_TOP500_FREEFLOAT="미실행 — cap-w·EW-uni 공히 신호 부재로 v2 확대 EV 낮음(next_probe)"),
  verdict=list(
    survivors=0,
    verdict_label="config-scoped negative (3/3) — 프론티어 표시. 종결어휘 없음.",
    by_factor=list(
      "F-A"="prereg-sign null (cap-w 0.72·EW-uni −0.59·placebo p0.25). 분해로 blending-artifact 배제. 부호반전 약양성(post-hoc).",
      "F-B"="lead — 방향 일관(조기=long)·Size-robust(1.10)·EW post2017 +0.80, 그러나 cap-w 1.29≪2.95·placebo p0.135. prior earliness FAIL(MDD-killed, 폐지 게이트)이 canonical선 '약함'으로 재판정.",
      "F-C"="불안정(IS0.13/OOS1.45)·turnover 4.87 과다·placebo p0.22. insider-count churn 노이즈."),
    survivor_criterion="placebo p<0.05 AND Size-무관 → 미충족(3/3). add_factor 온보딩 권고 없음."),
  screen_route=list("F-A"="NONE","F-B"="NONE (frontier lead)","F-C"="NONE"),
  next_probe=c(
    "F-A: full MD&A(≤40000자) 유사도 재추출 — section_head는 '개요' boilerplate 지배로 유사도 상향편의 의심(재추출=쿼터 필요, insider 백필 후)",
    "F-A: KR Lazy Prices 부호 반전 가설(changers outperform, inverted 1.38) 정식 사전등록 재검증",
    "F-B: 조기성 연속 스프레드 × 소형/distress 상호작용 + overlay-candidate로 β/regime 결합 검토",
    "F-C: YoY-change 대신 count-level 또는 방향서명(net-buy 부호 가중) insider-density; 전체-유형 공시 count는 full list.json 크롤 필요",
    "universe v2(KR_TOP500_FREEFLOAT)는 cap-w·EW-uni 공히 신호부재로 후순위"),
  parallel_note="insider 백필(PID 17920/48260) 중 — DART API 0, text_cache read-only 준수")
write_json(validation, file.path(OUT,"alpha_validation.json"), pretty=TRUE, auto_unbox=TRUE, na="null")

alpha_package <- list(
  task_id="WT-D20260713_001", as_of_date=as.character(lastd), forecast_horizon="1M",
  wt_type="discovery", frontier_id="FQ-030",
  alpha_vector=alpha_vector, confidence_vector=conf,
  signal_matrix_ref="stage_artifacts/WT_D20260713_001/alpha_scores.parquet",
  selection_objective="canonical_port_t",
  factor_specs=list(
    list(factor_family="text_disclosure_similarity", proxy="MD&A section_head YoY sim (0.5cos+0.5jac, 5-gram)",
         formula="sim=0.5*cosine+0.5*jaccard(charNgram5, head_Y vs head_Y-1)", lag_rule="annual, rcept月+1, hold 12m",
         neutralization="none (Size-partial 진단)", economic_rationale="Lazy Prices: 문구변화=부정정보(CMN 2020). KR 부호반전 실증",
         weight_theta=NA, references=list("Cohen-Malloy-Nguyen 2020 JF Lazy Prices"), source="new_designed",
         canonical_port_t_nw_lag3=round(res$FA$port_t_full,3)),
    list(factor_family="filing_timeliness", proxy="사업보고서 제출지연 vs 법정기한 90d",
         formula="delay_d=rcept-(Dec31+90d); score=-z(delay)", lag_rule="annual, rcept月+1, hold 12m",
         neutralization="none (Size-partial 진단)", economic_rationale="조기제출=거버넌스 우수=long; 지연=distress",
         weight_theta=NA, references=list("filing-delay distress; KR earliness prior(FAIL, MDD-killed)"), source="new_designed",
         canonical_port_t_nw_lag3=round(res$FB$port_t_full,3)),
    list(factor_family="insider_filing_activity_change", proxy="임원·주요주주 공시 건수 YoY (insider-only)",
         formula="yoy=(q_cnt-q_cnt_-4)/(q_cnt_-4+1); score=-z(yoy)", lag_rule="quarterly, qend月+1, hold 3m",
         neutralization="none (Size-partial 진단)", economic_rationale="공시 활동 급변=이벤트밀도/불확실성",
         weight_theta=NA, references=list("event/insider activity density"), source="new_designed",
         canonical_port_t_nw_lag3=round(res$FC$port_t_full,3))),
  diagnostics=list(
    canonical_port_t_nw_lag3=round(res$FB$port_t_full,3),  # lead factor
    canonical_port_t_pvalue=round(res$FB$port_p,4),
    canonical_n_months=res$FB$n_months,
    rank_ic=round(res$FB$rank_ic,4), icir=round(res$FB$icir,4),
    harvey_t_stat=round(res$FB$ric_t,3),
    turnover_proxy=round(res$FB$turnover,3),
    note="diagnostics = lead factor F-B. 전 3종 상세 = alpha_validation.json"),
  metric_type="canonical_screen",
  graduation_status="ALL_BELOW_HARD (survivors 0)",
  challenge_flags=c(
    "3/3 cap-w PORT_t<2.95 + placebo p<0.05 통과 0건 — survivors 없음, add_factor 권고 없음",
    "F-A prereg-sign null·EW-uni 음수; 부호반전(1.38)은 post-hoc·sub-threshold",
    "F-B가 prior 'DART Disclosure Earliness' FAIL과 동일 신호 축(차별=canonical frame·MDD게이트 폐지). config-scoped 재측정",
    "F-C = insider-only 공시(전체공시 아님, 정직 재라벨) + insider lane confound(Size-partial로 부분 배제) + turnover 4.87 과다"))
write_json(alpha_package, file.path(MB,"alpha_package.json"), pretty=TRUE, auto_unbox=TRUE, na="null")
file.copy(file.path(OUT,"alpha_validation.json"), file.path(MB,"alpha_validation.json"), overwrite=TRUE)

# lineage AFTER package write (L-194 order)
source(file.path(ROOT,"02_Infrastructure/worktask/lineage_utils.R"))
tryCatch(record_package_lineage(task_id="WT-D20260713_001", package_type="alpha_package",
  method_selected="3-factor non-return canonical dual-basis (F-A sim / F-B delay / F-C insider-count)",
  input_file_paths=c(file.path(OUT,"scores_FA.parquet"),file.path(OUT,"scores_FB.parquet"),
    file.path(OUT,"scores_FC.parquet"),file.path(ROOT,".cache/dart/insider_activity_hist.parquet"))),
  error=function(e) cat("[lineage] warn:",conditionMessage(e),"\n"))
cat("[04] DONE — alpha_package + alpha_validation + alpha_scores emitted\n")
