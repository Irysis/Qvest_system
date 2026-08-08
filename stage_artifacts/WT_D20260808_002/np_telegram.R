setwd(Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
suppressPackageStartupMessages({ library(jsonlite) })
source("02_Infrastructure/telegram/telegram_notify.R")
AV <- fromJSON("stage_artifacts/WT_D20260808_002/alpha_validation.json", simplifyVector = TRUE)
charts <- readLines("stage_artifacts/WT_D20260808_002/chart_paths.txt")

tg_agent_brief(
  agent = "Alpha",
  title = "WT-D20260808_002 ALPHA_DONE — 매출 개정 신호, 재료 자격은 통과 자본 자격은 미달",
  sections = list(
    list(type = "text", emoji = "📌", heading = "한 줄",
         body = sprintf(paste0("이익 기반 컨센서스 3종을 통제한 뒤에도 매출 전망 개정(M26)이 횡단면 증분 정보를 갖는다 ",
           "— 증분 회귀 t %+.3f (문턱 2.0). 다만 상위 25종목 편입으로 옮기면 t %+.3f 로 자본 문턱 2.95 에 크게 못 미친다."),
           AV$primary$fmb_nw3_t, AV$transition$canonical_port_t_raw)),

    list(type = "bullet", emoji = "📖", heading = "쉬운 설명",
         items = c(
           "질문: 우리 운용 북이 이미 쓰는 이익 전망 신호 3종 위에, 매출 전망 신호가 무언가를 더 얹어주는가",
           "방법: 283개월 동안 매달 종목을 가로로 늘어놓고 4개 신호를 동시에 넣어 회귀했습니다 (Fama-MacBeth)",
           "결과: 매출 신호가 이익 신호와 별개로 다음달 수익을 설명했습니다 (재탕 아님 — 순위 상관 0.22)",
           "한계: 그런데 이 신호로 실제 25종목을 골라 담으면 초과수익이 자본 편입 문턱에 못 미쳤습니다",
           "의미: 재료로는 쓸 수 있으나 단독 편입은 불가 — 다른 소비 방식을 찾아야 합니다")),

    list(type = "table", emoji = "📊", heading = "실측 (문턱 대비)",
         df = data.frame(
           항목 = c("증분 회귀 t (주판정, 문턱 2.0)", "체결 하루 늦춘 t", "정보계수 평균", "정보계수 t",
                    "기존 3종과 최대 순위상관 (문턱 0.9)", "무작위 대조 p값",
                    "시총가중 초과수익 t (문턱 2.95)", "동일가중 대비 t", "검증구간 유지율 (문턱 0.7)"),
           값   = c(sprintf("%+.3f 통과", AV$primary$fmb_nw3_t),
                    sprintf("%+.3f (유지 %.2f)", AV$pit_robustness$t1exec$fmb_nw3_t, AV$pit_robustness$t1exec$retention_vs_baseline),
                    sprintf("%+.4f", AV$secondary$rank_ic_mean),
                    sprintf("%+.2f", AV$secondary$rank_ic_t_nw3),
                    sprintf("%.4f 재탕아님", AV$primary$max_spearman_vs_incumbent),
                    sprintf("%.4f 유의", AV$robustness$placebo_p),
                    sprintf("%+.3f 미달", AV$transition$canonical_port_t_raw),
                    sprintf("%+.3f 미달", AV$transition$dual_basis$ew_universe_port_t_raw),
                    sprintf("%.3f 미달", AV$transition$dual_basis$oos_retention_approx)))),

    list(type = "bullet", emoji = "🚩", heading = "주의",
         items = c(
           "자본 자격 주장 아님 — 재료 자격까지만. 편입 판단은 forge 실측과 governor 별도",
           "부기간 3구간 전부 검정력 미달 — 점추정은 하락하나 감쇠로 단정 불가",
           "신호를 한 달 묵히면 t 2.56 에서 0.60 으로 소멸 — 수명 1개월 미만",
           "통제 3종 중 실제로 작동한 것은 EPS 개정 1종뿐 (SUE t -0.04)",
           "회전율 연 11.74 — 운용 기준선 11.0 초과")),

    list(type = "bullet", emoji = "🔧", heading = "부수 발견 (인프라)",
         items = c(
           "당초 대상 C14_Revenue_Surprise 는 442개 월 파일 전 구간 0행 — 같은 식의 M26 이 이미 산출 중이라 대상 정정",
           "원인은 빌더 조건문이 리팩터 후 영구 거짓 — 같은 방식으로 7종이 조용히 누락 (C10·C11·C13·C14·C15·C17·C18)",
           "registry 등재 19종 대비 실산출 12종 — 정리 제안서 별도 산출 (코드 수정은 미실행)")),

    list(type = "bullet", emoji = "➡️", heading = "다음",
         items = c(
           "FQ-161 소비면 순회 — 랭킹 슬롯 말고 유니버스 필터·선별 라벨 쪽 한계기여 측정",
           "FQ-162 컨센서스 원천 T-1 재빌드 A/B — 북 incumbent 3종도 같은 노출",
           "FQ-163 빌더 침묵 누락 수리 후 C10·C13·C15·C18 재료 자격 라운드"))
  ),
  charts = charts
)
cat("[tg] 발송 완료\n")
