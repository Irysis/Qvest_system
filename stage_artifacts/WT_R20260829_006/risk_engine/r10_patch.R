suppressPackageStartupMessages({library(jsonlite)})
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
WT<-"WT-R20260829_006"; fp<-file.path("qepm/mailbox/worktask",WT,"risk_package.json")
p <- fromJSON(fp, simplifyVector=FALSE)
p$pit_gate <- list(
  detector="02_Infrastructure/validation/lookahead_detector.R::detect_lookahead",
  scanned_files=12L, scanned=TRUE, clean=TRUE, n_violations=0L,
  engine_ref="stage_artifacts/WT_R20260829_006/risk_engine/",
  positive_control=list(performed=TRUE, injected=4L, detected=4L,
    checks=c("C1","C15_DIRECT_PARQUET","C5_VT","C14_IC_TIMING"),
    note="위반 주입본이 4/4 적발됨 — 검사기 생존 실증. 양성 대조 없는 '경고 0' 은 방어선으로 세지 않는다."),
  manual_c_checks=list(
    C1="Omega/D 는 sig_date 까지의 확장창. 추정기 선택도 rolling-60m OOS 우도. 구간별 Sigma(pre/post-2015)는 어떤 의사결정에도 투입되지 않는 사후 구조 진단이며 두 구간 모두 sig_date 이전.",
    C5="rolling beta 는 Date < d 로 당월 forward 수익 제외. 오버레이 미적용(S0/S1 금지 준수).",
    C6="유니버스는 월별 K200|KQ150 실측 멤버십. 생존편향 없음.",
    C9="beta/노출 어디에도 same-day DD/VT 없음.",
    C10="유동성 adv20 = build_adv20_t1 (shift(1) — 당일 미포함). as_of 는 sig_date 에서 직접 재계산.",
    C11="외생 매크로 시계열 미사용(FRED 등 미소비).",
    C13="Z_Score_Aligned 만 사용 · NEGATE/FLIP 없음.",
    C14="IC 접근 없음(추정기 선택은 우도 기반).",
    C15="계열 z 는 load_month_factors() 경유 · factor_db parquet 직접 로드 0."))
p$escalation <- list(
  trigger="HIGH >= 5", high_count=5L,
  high_flags=c("RF-R1 (Market 68.8% > 40%)","WT006R-01 (구간 이질성 · Jennrich p 5.5e-17)",
    "WT006R-02 (계열 실효 해상도 3.25)","WT006R-03 (교체 레그 무우위 t -0.22)",
    "WT006R-04 (Hill alpha 1.862 < 2 · 정규-Sigma 1% 과소)"),
  sigma_pd_violation=FALSE, pit_hard_violation=FALSE,
  action="Q-Lead 보고(본 에이전트 최종 보고로 전달). Sigma PD/PIT 위반이 없으므로 ABORTED 아님 — 체인 완주 지시에 따라 하류 소비 가능 상태로 발행.")
write_json(p, fp, pretty=TRUE, auto_unbox=TRUE, digits=10, null="null")
cat("[patch] pit_gate + escalation appended. size =", file.info(fp)$size, "\n")
q <- fromJSON(fp, simplifyVector=FALSE)
cat("[patch] keys =", paste(names(q), collapse=","), "\n")
cat("[patch] challenge_flags n =", length(q$challenge_flags),
    " crowding n =", length(q$risk_summary$crowding_score_per_factor), "\n")
