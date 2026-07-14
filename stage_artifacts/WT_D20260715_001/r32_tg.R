setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
Sys.setenv(QM_ROOT="C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source("02_Infrastructure/telegram/telegram_notify.R")
CH<-"stage_artifacts/WT_D20260715_001/charts"
charts<-file.path(CH,c("equity_curve.png","oos_zoom_chart.png","value_marginal_era.png","risk_bars.png","drawdown.png"))
charts<-charts[file.exists(charts)]

sections<-list(
 list(type="text",emoji="📊",heading="R32 — PG2 북에 밸류 넣으면 성과 강화되나 (위험조정 축)",
   body=paste(
    "현행 PG2 배포 북(STR_1715 알파 x M4xR05 오버레이=국면 현금조절)에 밸류를 추가하면 최종 배포 성과가 강화되는지 확인.",
    "지금껏(R26~FQ-046)은 오버레이 前 맨몸 알파만 봤고, 이번엔 실제 굴러가는 북(오버레이 포함)의 최대낙폭·칼마를 실측.")),
 list(type="text",emoji="🧩",heading="쉬운 설명",
   body=paste(
    "전기간으로 보면 밸류 넣은 북이 더 좋음(덜 떨어지고 위험 대비 수익 좋음).",
    "그런데 좋아진 부분 대부분이 2024년 前에 벌어진 것이고, 2024년 後로는 밸류가 오히려 성과를 갉아먹음.",
    "→ '자본 배분 가능' 판정은 여전히 불가.")),
 list(type="kv",emoji="📈",heading="핵심 비교 (오버레이 적용 북, 269개월, clean recon)",
   kv=list("샤프"="1.089 → 1.369 (+밸류B2)","칼마"="0.724 → 1.141",
    "최대낙폭"="0.349 → 0.278","다중검정t"="3.455 → 4.533","정보비율 증분"="+0.269 (paired t 3.08)")),
 list(type="text",emoji="⚠️",heading="판정 평문 — 강화의 대부분이 2024+ 역전 알파",
   body=paste(
    "밸류 한계기여 paired t: 2024 前 +4.24 → 2024 後 -1.26 (음전환).",
    "북 초과수익 2024+: 현행 +85bps → B2 +14 → Z6 -22 (밸류가 갉아먹음).")),
 list(type="bullet",emoji="🔬",heading="과최적화·방어 근거",
   items=c(
    "OOS retention: 현행 0.244 / B2 0.195 / Z6 0.142 — 전부 문턱 0.7 미달, 밸류가 악화",
    "= 밸류 아크 lockbox OOS -1.19(밸류 vs 대형주 역전) 재현",
    "하락장 캡처 0.693→0.640 = 소폭 진짜 방어분(오버레이와 보완)",
    "칼마 개선 지배분은 2024+ 이미 역전된 pre-2024 알파")),
 list(type="bullet",emoji="🔎",heading="신규 발견 + 도훈 결정 재료",
   items=c(
    "construction 의존성: 시총가중 top-25 t 2.74 vs production N20 틸트 4.53",
    "오버레이 x 밸류 = 보완 채널(상쇄 아님)",
    "★§7b: production 역사 ret_orig NAV = 동월 vintage 부풀림 약 2.08배",
    "pinned t 6.21 / SR 1.90 vs clean recon 3.46 / 1.09 → book 재산출 필요(도훈)")),
 list(type="bullet",emoji="🧭",heading="다음 프로브",
   items=c(
    "P1: book pinned clean-basis 재산출 승격 (judge 라운드·도훈 confirm)",
    "P2: 밸류 recency tripwire (trailing-12m 한계기여 + 스프레드 0.175 추적)",
    "P3: construction 의존성 일반화 (타 재료 N20 틸트 basis 재측정)"))
)

tg_agent_brief(
  agent="Forge",
  title="R32 — PG2 북에 밸류 추가: 전기간 위험조정 성과 강화되나 최근 소진·자본 NO-GO (오버레이 적용 실측)",
  sections=sections,
  charts=charts)
cat("TG_DONE\n")
