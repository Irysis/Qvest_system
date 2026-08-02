# =============================================================================
# run_wt020_telegram.R — WT-D20260802_020 Alpha 브리핑 (tg_agent_brief 단일 진입점)
# 실행: Rscript -e 'source("stage_artifacts/WT_D20260802_020/run_wt020_telegram.R")'
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260802_020")
source("02_Infrastructure/telegram/telegram_notify.R")
source("02_Infrastructure/telegram/tg_chart_pack.R")

R <- readRDS(file.path(OUT, "wt020_eval_results.rds"))
dec <- as.data.table(R$decile)

# 차트 1 — 십분위 crash 발생률 (%)
ch1 <- tg_chart_sweep(
  labels = sprintf("십분위 %d%s", dec$dec,
                   ifelse(dec$dec == 1, " (저MAX5)", ifelse(dec$dec == 10, " (고MAX5·복권형)", ""))),
  values = round(100 * dec$p_crash, 2),
  out_dir = file.path(OUT, "charts"),
  title = "WT-020 MAX5 십분위별 익월 crash 발생률 (횡단면 하위 10% 진입 확률, 256개월)",
  value_label = "crash 발생률 (%)", hline = 10.12, hline_label = "전체 평균",
  highlight = "십분위 10 (고MAX5·복권형)")

# 차트 2 — 국면별 양측 꼬리 lift (%p)
ri <- as.data.table(R$regime$inc)
ord <- c("RISK_ON", "NEUTRAL", "CAUTION", "CRISIS")
ri <- ri[match(ord, Category)]
lab2 <- c(rbind(paste0(ord, " · crash lift"), paste0(ord, " · 상방(boom) lift")))
val2 <- c(rbind(round(100 * ri$crash_lift, 2), round(100 * ri$boom_lift, 2)))
ch2 <- tg_chart_sweep(
  labels = lab2, values = val2, out_dir = file.path(OUT, "charts"),
  title = "WT-020 국면별 MAX5 상위군 꼬리 발생률 증가폭 — 위기에도 crash 예측 유지",
  value_label = "발생률 증가폭 (%p, 상위 10% MAX5군 vs 전체)",
  highlight = "CRISIS · crash lift")

tg_agent_brief(
  agent = "Alpha",
  title = "WT-D20260802_020 ALPHA_DONE — MAX5 crash 예측력: 현행 위험 축 대비 증분 실재, 정체는 단기창 변동성",
  sections = list(
    list(type = "summary", emoji = "\U0001F4CC",
         body = "MAX5 상위군은 다음 달 급락(crash) 확률이 2.11배 — 현행 1년창 위험 축 통제 후에도 유의(t +13.1). 단, 같은 63일창 변동성으로 통제하면 소멸(t +0.95): 위험모델에 필요한 것은 MAX5가 아니라 '단기창 꼬리-변동성 축'"),
    list(type = "kv", emoji = "\U0001F4CA", heading = "핵심 실측 (256개월 · 사전등록 단일시험 · 횡단면 회귀)",
         kv = list(
           "판별 기준" = "위험 축 4종(1년창 변동성·고유변동성·하방편차·베타) 통제 후 t값 2.0 이상 — 실측 +13.15 (충족)",
           "crash 발생률" = "MAX5 상위 10%군 21.4% vs 전체 10.1% (2.11배, t +17.7) — 십분위 단조 3.9%→21.6%",
           "라벨 강건성" = "절대 문턱(월 -20% 이하) 라벨로도 t +8.4",
           "★동일창 통제" = "같은 63일창 변동성+하방편차 통제 시 증분 소멸 (t +0.95) — MAX5 고유 정보 아님",
           "★위기월 긴장 해소" = "crash '발생률' 예측은 위기에도 유효(t +2.33, lift +10.1%p). WT-014 배제 필터가 위기에 손해였던 건 '평균수익' 때문 — 상방 반등 꼬리가 상쇄(주의 국면 수익 스프레드 +1.76%/월, t +2.08)",
           "규모 분해" = "초대형 t +2.5 / 대형 +3.4 / 그 외 +17.0 — 소형 국소 아님 (전 구간 유의)",
           "평균수익" = "상위군 익월 수익 스프레드 t -0.12 — 수익 랭킹 소비는 근거 없음 (위험지표 전용)",
           "포트 tail 신호" = "하위 5% 초과수익 월 직전 포트 MAX5 노출 유의 상승 (p 0.001) — 문턱형 경보만 적합",
           "PIT 검증" = "라벨 방향 독립 재계산 상관 1.0000 + 위반 주입 시 검증기 차단 발화 (검사 실효 실증)")),
    list(type = "bullet", emoji = "\U0001F9E0", heading = "쉬운 설명",
         items = list(
           "최근 석 달 사이 '하루 급등'이 유난히 컸던 종목은 다음 달 크게 떨어질 확률이 두 배가 넘습니다",
           "지금 위험모델이 보는 1년짜리 변동성 지표에는 이 최근 정보가 희석되어 안 잡힙니다",
           "다만 그 정보의 실체는 '최근 63일 변동성'이라, 같은 창으로 변동성을 재면 MAX5는 따로 필요 없습니다",
           "이런 종목은 급락 확률과 급등 확률이 함께 높아서(양쪽 꼬리), 위기 때 미리 빼버리면 반등을 놓쳐 오히려 손해 — 지난 라운드의 수수께끼가 풀렸습니다",
           "결론: 종목을 빼는 필터가 아니라 '위험 진단·경보' 용도로 쓰는 게 맞습니다")),
    list(type = "bullet", emoji = "\U0001F6A9", heading = "판정 평문 + 유의점",
         items = list(
           "판정: 특성화 positive — 사전등록 기준 충족. 단 헤드라인은 'MAX5 고유'가 아니라 '단기창 변동성 정보의 위험 축 결손'",
           "제한 1: 위기 국면 셀 13개월 (t +2.33 — 4국면 방향 일관으로 보강)",
           "제한 2: 수익 예측 아님 — alpha_vector에 위험지표 라벨 명시, 랭킹 소비 금지",
           "무결성: Self-Adversarial 7건 기록 (challenge_note.md) · 자본 주장 없음 · Σ/비중 산출 없음",
           "배관 플래그 2건: 승계 패널 최종월 부분월 절단 + 벤치마크 2소스 괴리 35개월 — 본 측정 비오염 실증 후 전달")),
    list(type = "bullet", emoji = "\U000027A1", heading = "다음 단계",
         items = list(
           "1순위(NP-1): DB에 이미 있는 단기 변동성 팩터(D34_RealVol_21d/D42_EWMA_Vol)가 이 증분을 흡수하는지 재시험 — 흡수하면 신규 팩터 없이 배선만",
           "2순위(NP-2): 포트 MAX5 노출 문턱 경보(monitoring tripwire) 사전등록 라운드 — 적중률/오경보율 실측",
           "3순위(NP-3): 주의 국면 lottery 보유 편익(t +2.08)의 국면-조건부 소비 — 팩터 로테이션/RAMP 이식 후보",
           "risk_package 이식은 설계 제안 문서(risk_integration_proposal.md)까지 — 실배선은 별도 라운드 (governor+도훈)"))),
  charts = c(ch1, ch2))
cat("[tg] 발송 완료\n")
