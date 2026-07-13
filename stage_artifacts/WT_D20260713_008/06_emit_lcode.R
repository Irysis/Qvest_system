`%||%` <- function(a,b) if(is.null(a)||length(a)==0) b else a
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
source(file.path(ROOT,"02_Infrastructure/axiom/lcode_emit.R"))

res <- emit_lcode(
  mode="alpha_research", strategy_id="WT-D20260713_008", grade="F",
  metric_type="unavailable", construction_type="single", selection_type="chain", record_type="process",
  core_reference="FQ-037 R24 (NEW prereg; R23 P1+P2 joint consumption) / parent FQ-036 R23 config_scoped_negative + L-AR R23 P1/P2/P3 / preregistration.sha256 e13d4251 / verdict.json",
  mechanism_hypothesis="제출지연 극단꼬리(사업보고서 90일 법정기한 대비 지각일수)가 심각사건{상폐·관리종목 지정·불성실공시 지정} 12개월 예측을 Size·유동성·거래소·연도-FE 통제 후에도. R23 P1(유니버스 검정력)+P2(에피소드 설계) 결합. API 0, filings_inventory + disc_ck 로컬 소비.",
  falsification_attempts="NEW 사전등록 hash 동결(association 무관측·census 이후) / coverage census(677 유니버스 정직 동결, 전체 3914 중 filing-delay 데이터 상한) / 에피소드-레벨(ticker×fy, 월중복 제거) / firm-cluster-robust logistic + year-FE / firm 부트스트랩 lift CI / strict-tail leave-one-firm-out 27종목 / size-tier 분해 / 연속 지연 delisting hazard / hardened vs pure-flag / pre-post 2016 안정성",
  lesson_text=paste0(
    "제출지연 극단꼬리 x 심각사건 예측(R24, R23 P1+P2 결합 신규 prereg): 동결 PRIMARY = CONFIG_SCOPED_NEGATIVE + FRONTIER_OPEN. ",
    "Coverage census: filing-delay 데이터(무-API)는 677종목(과거 K200uKQ150 합집합)에 상한 — 전체 ~2500 filer 유니버스 도달 불가, 정직 축소·동결. ",
    "동결 PRIMARY(per-fy p90 & delay>0)가 '임의 지각'으로 collapse(대부분 연도 <10% 지각 -> p90<=0): 1105 에피소드/528종목, lift 1.23 firm-부트 CI[0.86,1.62]∋1, 통제 OR(year-FE) 2.34 p=0.051 근소 미달 -> 성립 못함. ",
    "그러나 R23 검정력 벽 해소: 신호는 명백히 극단꼬리에만. strict top-decile 진단(29에피소드/27독립종목/6사건) lift 10.0x, firm-부트 CI[3.5,17.3]∌1, 통제 OR 6.2 p<0.001, LOO 27종목 全생존(R23은 6종목중 3개 치명). 독립 event-firm 6(R23)->27(R24). 연속 지연 flat(OR 1.10 p 0.19)=비단조·극단꼬리 집중(R22 D2/R23 재현). ",
    "★DECISIVE size-tier: 극단꼬리 6사건 全 소형주(mid/large 극단지각 15에피소드 0사건). 소형내 lift 12x·통제 OR 생존=순수규모 아니나, 신호가 배포 유니버스(K200uKQ150 대/중형) 밖 소형주에 국소 -> R23 배포-유니버스 기아는 검정력 아닌 '구조'. 자본 관련성 상한. ",
    "goalpost 규율: 동결 PRIMARY가 판정(NOT ESTABLISHED); 극단꼬리 진단은 non-authoritative -> 사전등록 극단꼬리 라운드로 라우팅(upgrade 아님). 2단 분리 준수: stage-2 자본/필터 미개시."),
  tags=c("non_return","forensic_delay","event_prediction","config_scoped_negative","frontier_open",
    "episode_level_design","universe_power_resolved","extreme_tail_only","smallcap_confined",
    "label_pit_hardened","stage1_knowledge","goalpost_discipline"),
  metrics=list(next_probe=list(
    P1="사전등록 극단꼬리 확정 라운드: wd_strict(per-fy rank top-decile & delay>0) 또는 사전 고정 절대컷(예 delay>=15d)을 PRIMARY로 동결. R24 이미 LOO-강건(27종목)·부트CI∌1 확인 -> association 前 동결한 clean prereg면 established 판정 가능. 사건수(6) 얇음 -> P2 결합.",
    P2="극단꼬리 사건수 확대 위한 coverage 확장: never-index 소형주 filer(진짜 전체 ~2500) 사업보고서 제출일 확보 — 예약 DART 크롤(insider-backfill wave capacity) 또는 disc_ck 46 non-inventory 종목 균일 delay 재유도. 상폐 소형주 다수 -> 극단지각 심각사건 증가(현재 survivor-conservative).",
    P3="메커니즘 분리: 극단꼬리 내 지정공시(관리+불성실=frozen-primary 25건 중 23; 공시일자·아티팩트 면역) vs 상폐(2건, last-obs 기계성 가능) 분리. 지정-only 결과 사전등록으로 가장 깨끗한 공시-dated 채널 검정.")),
  project_root=ROOT
)
cat("[emit] l_code =", res$l_code %||% "?", "\n")
saveRDS(res$l_code, file.path(ROOT,"stage_artifacts/WT_D20260713_008/_lcode.rds"))
