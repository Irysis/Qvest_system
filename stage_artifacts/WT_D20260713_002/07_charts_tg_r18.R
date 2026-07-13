## R18 소비 진단 — 차트 + JSON 요약 + 텔레그램 v7 추가 보고 (원칙 9)
suppressPackageStartupMessages({library(data.table); library(jsonlite)})
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/telegram/telegram_notify.R")
source("02_Infrastructure/telegram/tg_chart_pack.R")
OUT <- "stage_artifacts/WT_D20260713_002"
res <- readRDS(file.path(OUT,"consumption_diagnostic.rds"))

bf <- res$binding$FB$by_tier; setkey(bf,tier)
# chart 1: binding rate by cap-tier (FB filter)
c1 <- tg_chart_sweep(
  labels=c("OTHER(31+)","MID(11-30)","MEGA(1-10)"),
  values=100*c(bf[tier=="OTHER",rate], bf[tier=="MID",rate], bf[tier=="MEGA",rate]),
  out_dir=OUT, title="R18 소비진단 — P-pure 보유 중 Benford 최악분위 걸림율 (%, tier별)",
  value_label="binding rate (%)", hline=5, hline_label="실재 문턱", filename="binding_tier.png")

# chart 2: A/B tail — Δdownside-dev forensic vs random(3seed mean)
abFB<-res$ab$FB; abUN<-res$ab$UNION
c2 <- tg_chart_sweep(
  labels=c("F-B 포렌식","F-B 무작위(평균)","합집합 포렌식","합집합 무작위(평균)"),
  values=c(abFB$d_dd, abFB$rand_d_dd_mean, abUN$d_dd, abUN$rand_d_dd_mean),
  out_dir=OUT, title="R18 소비진단 — 하방편차 개선 Δ (양수=개선, 포렌식 vs 무작위-제외)",
  value_label="Δ downside-deviation (연율)", hline=0, hline_label="무개선",
  highlight="F-B 포렌식", filename="ab_tail.png")
charts <- c(c1, c2)

# JSON 요약
summ <- list(
  label="POST-VERDICT CONSUMPTION DIAGNOSTIC — gate 판정과 분리(재측정 없음)",
  prereg_sha256=readLines(file.path(OUT,"consumption_diagnostic_prereg.sha256")),
  binding=list(
    Ppure_FB=list(overall_rate=res$binding$FB$overall_rate, by_tier=res$binding$FB$by_tier),
    Ppure_UNION=list(overall_rate=res$binding$UNION$overall_rate, by_tier=res$binding$UNION$by_tier),
    book_snapshots=res$binding$book,
    note="binding 실재(P-pure 9.7% FB / 13.9% union). tier횡단 존재 — '대형~0' 가설 미확인(MEGA 21% but n=123). book은 episodic(2023-12 7/20, 최근 cash-heavy 0·신호 2025-06 종료 영향)."),
  exclusion_ab=list(
    baseline_tail=res$baseline_tail,
    FB=list(mean_k=abFB$mean_k, d_mdd=abFB$d_mdd, d_downside_dev=abFB$d_dd,
      d_downside_dev_rel_pct=100*abFB$d_dd/res$baseline_tail$downside_dev,
      rand_d_dd_seeds=abFB$rand_d_dd_seeds, paired_nwt=abFB$paired$t, c4_d_dd_ex2=abFB$c4_d_dd_ex2),
    UNION=list(mean_k=abUN$mean_k, d_mdd=abUN$d_mdd, d_downside_dev=abUN$d_dd,
      rand_d_mdd_mean=abUN$rand_d_mdd_mean, paired_nwt=abUN$paired$t)),
  criteria_4=list(FB=res$criteria$FB, UNION=res$criteria$UNION),
  verdict=paste0("F-B 단독 4/4 사전등록 요건 충족(binding 실재·하방편차 개선이 무작위-제외 3seed 전부 능가·알파 비손상·비집중) → ",
    "'Production Constraints 기본 필터 승격 후보 — 도훈 confirm 회부'. ★단 효과크기 marginal(하방편차 -2.61% 상대 개선, MDD는 +0.51% 소폭 악화) — ",
    "승격 전 2차 소형전략 교차확인 + 효과 실질성 판단 권고. FA∪FB는 2/4 미달(C2 tail<random·C4 집중, F-A redundant noise가 꼬리 훼손). ",
    "AX-005 프레임: exclusion=필요조건, 포렌식 정보가 무작위 대비 하방편차서만 약한 우위(선택 알파는 여전히 null)."),
  frame="게이트 판정(config-scoped negative) 불변. 본 진단은 tail-risk 정보효과 별개 질문 — 선택 알파 부재 != 필터 무가치(AX-005)."
)
write_json(summ, file.path(OUT,"consumption_diagnostic.json"), pretty=TRUE, auto_unbox=TRUE, digits=5, na="null")
cat("charts:", paste(basename(charts),collapse=", "), "\n")

# 텔레그램 v7 추가 보고
tg_agent_brief(
  agent="Alpha",
  title="R18 소비진단 — Benford 배제필터 기본필터 승격 요건 4종 검증(판정-후, 게이트 불변)",
  sections=list(
    list(type="summary", emoji="📌",
      body="판정-후 소비 진단: F-B(벤포드) 최악분위 배제 오버레이가 소형 P-pure서 승격 요건 4/4 충족 — 단 효과 marginal, 도훈 confirm 회부."),
    list(type="bullet", emoji="📖", heading="쉬운 설명",
      items=c(
        "질문: 선택 알파는 없던 포렌식 신호를 '지뢰제거 필터'로 쓰면 가치 있나(유동성처럼 기본 필터 승격?)",
        "방법: 소형 전략(P-pure) 보유서 벤포드 최악 10분위 종목 제외 vs 미적용 + 무작위-제외 대조",
        "걸림율: 소형 P-pure 보유의 9.7%가 실제 걸림(필터가 실재로 작동, 대형북은 드묾)",
        "결과: 하방편차 2.6% 개선(무작위-제외 3회 전부 못 이긴 것을 이김=정보효과)·수익 무손상",
        "한계: 최대낙폭은 오히려 소폭 악화, 개선폭 작음 = 약한 양성",
        "합집합(F-A포함)은 미달 — 중복 팩터 F-A가 오히려 꼬리 훼손")),
    list(type="kv", emoji="📊", heading="승격 요건 4종 (사전등록·결과前 고정)",
      kv=list(
        "① 걸림 실재"   = "소형 9.3% / 중형 11.8% (문턱 5%↑) 충족",
        "② 꼬리>무작위" = "하방편차 Δ+0.0033 > 무작위 3seed 전부(음) 충족",
        "③ 알파 비손상" = "짝지은 순성과 t +0.19 (유의 음 아님) 충족",
        "④ 비집중"      = "최악2월 제외 후에도 하방개선 유지 충족",
        "F-B 종합"      = "4/4 충족 (효과 marginal)",
        "합집합 종합"   = "2/4 미달 (F-A 중복이 꼬리 훼손)")),
    list(type="bullet", emoji="🚩", heading="주의 · 정직",
      items=c(
        "게이트 판정 불변: 선택 알파는 여전히 null(F-B PORT_t 0.57)·재측정 없음",
        "효과크기 marginal: 하방편차 -2.6% 상대·최대낙폭은 +0.5% 악화 — 강한 방패 아님",
        "'대형 걸림 ~0' 가설 미확인: 걸림이 tier 횡단 존재(대형 21%나 표본 극소 n=123)",
        "book 걸림은 episodic(2023-12 7/20, 최근 cash+대형 0)",
        "AX-005: exclusion 필요조건이지 충분조건 아님 — 무작위 대비 약한 정보우위만")),
    list(type="bullet", emoji="➡️", heading="판정 · 다음",
      items=c(
        "판정: F-B 단독 = 기본 필터 승격 요건 4/4 충족(도훈 confirm 회부) — 단 marginal, 2차 소형전략 교차확인 권고",
        "합집합(FA∪FB) = 승격 부적격(2/4)",
        "다음①: 도훈 confirm — 유동성 기준류 전 전략 기본 필터 승격 여부 결정",
        "다음②: 승격 시 2차 독립 소형전략(예: V02_EP sleeve)서 동일 4종 재확인"))
  ),
  charts=charts,
  footer="📚 소비진단(판정-후) · consumption_prereg e7d6c8d8 · FQ-031 · 게이트판정(config-scoped negative) 불변"
)
cat("R18_CONSUMPTION_TG_DONE charts=", length(charts), "\n")
