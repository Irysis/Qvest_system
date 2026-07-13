`%||%` <- function(a,b) if(is.null(a)||length(a)==0) b else a
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
source(file.path(ROOT,"02_Infrastructure/axiom/lcode_emit.R"))

res <- emit_lcode(
  mode="alpha_research", strategy_id="WT-D20260713_007", grade="F",
  metric_type="unavailable", construction_type="single", selection_type="chain", record_type="process",
  core_reference="FQ-036 R23 (NEW prereg, R22 P1 consumption) / parent FQ-035 config_scoped_negative_frontier_open + L-AR-20260713_180008 P1/P3 / preregistration.sha256 4b880cfb / verdict.json",
  mechanism_hypothesis="제출지연 극단꼬리(최악10%, R22 정의 동결)가 심각사건 한정 표적{상폐·관리종목 지정·불성실공시 지정}(단기 거래정지 제외)을 Size·tier·유동성 통제 후에도 예측. R22 분해: 상폐 6.4·관리 4.2·불성실 3.8배 lift가 합집합(단기정지 1.8배)에 희석. 사건 라벨 PIT 경화(실제 지정 공시일) 포함. API 0, disc_ck 로컬 아카이브 소비",
  falsification_attempts="NEW 사전등록 hash 동결(심각-union association 무관측 상태) / 라벨 PIT 경화 disc_ck 506874행·348종목 교차(플래그 onset vs 실제 지정 공시월 gap 분포) / ticker-cluster-robust logistic 통제 / ticker-cluster 부트스트랩 lift CI / pre-post 2016 안정성 / leave-one-ticker-out 유의성 / 월-permute placebo / 연속 days-late delisting hazard / 사건유형별 lift 분해 / hardened vs pure-flag A/B",
  lesson_text=paste0(
    "제출지연 극단꼬리 x 심각사건 한정 재과녁(R23, R22 P1 신규 prereg): CONFIG_SCOPED_NEGATIVE(강건히 성립 못함) + FRONTIER_OPEN. ",
    "심각사건 제한이 방향대로 작동 — 단기정지 제거로 union lift 2.07->3.74, 통제 전후 4.08->3.43(거의 안 줄어듦=크기위장 아님), 명목 PRIMARY 통과(통제 OR 3.43 cluster-robust p 0.011<0.05). ",
    "그러나 47건 worst-decile '사건'이 단 6개 late-filer 회사-에피소드(12개월 hold로 월단위 중복계상; 종목별 12/11/11/7/5/1). 사전등록 ticker-부트 lift CI [0.95,7.25] 포함 1 + leave-one-ticker-out 3/6 종목 각각 p>=0.05로 붕괴 + 6-cluster에서 cluster-robust 추론 무효 -> 명목 p 신뢰 불가. ",
    "라벨 PIT 경화(R22 P3 실행): 플래그 onset == 실제 지정 공시월 89%(median gap 0·flag-leads 5.6%) = 백데이팅 미래참조 없음. 단 coverage 36/2492(disc_ck survivor-biased 348종목) -> hardened==pure-flag(타깃 불변), 청정성만 입증. ",
    "보조: 연속 days-late delisting hazard flat(OR 1.18 p 0.62)=극단꼬리·비단조(R22 재확인). 전신호 post-2016(pre 미추정)=시대 robustness 미확립. per-type lift(상폐6.38·관리4.24·불성실3.82)=R22와 정확 일치(파이프라인 정합). ",
    "결론: R22 희석-가설 방향 확증. 바인딩 벽이 '희석'->'독립 late-filer 에피소드 부족(K200uKQ150 대형주는 지각제출 극소)'으로 이동 — universe-power 벽(해결가능). 2단 분리 준수: stage-2 필터 미개시."),
  tags=c("non_return","forensic_delay","event_prediction","config_scoped_negative","frontier_open","severity_restricted","few_cluster_fragility","label_pit_hardened","universe_power_wall")
)
cat("[emit] l_code =", res$l_code %||% "?", "\n")
saveRDS(res$l_code, file.path(ROOT,"stage_artifacts/WT_D20260713_007/_lcode.rds"))
