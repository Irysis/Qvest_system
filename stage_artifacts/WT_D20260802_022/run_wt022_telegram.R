# run_wt022_telegram.R — WT-022 완료 브리핑 (tg_agent_brief 단일 진입점 + 차트 2종)
suppressPackageStartupMessages({library(data.table); library(jsonlite)})
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
source("02_Infrastructure/telegram/telegram_notify.R")
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260802_022")

sections <- list(
  list(type = "summary",
       body = "복권필터를 현 PG2 실코드에 실측 — 역효과 확정, 실배치 상신 철회"),
  list(type = "kv", heading = "실코드 paired 실측 (256개월, 순비용 15bps)",
       kv = list(
         "정보비율 차이 (필터−무필터)" = "−0.1489 (1.559 → 1.410)",
         "짝지은 검정 t값 (NW lag-3)" = "−1.976",
         "샤프지수" = "1.935 → 1.796",
         "최대낙폭" = "−23.3% → −26.2% (악화)",
         "연복리수익률" = "45.8% → 40.6%",
         "회전율(연환산)" = "5.19 → 5.56",
         "재현 정합" = "production 271개월 오차 5e-16 통과")),
  list(type = "bullet", heading = "쉬운 설명 — 왜 어제와 부호가 뒤집혔나 (본체)",
       items = list(
         "어제 프레임은 시가총액 가중 — 걸러낸 복권형 종목은 대부분 소형주라 원래 무게가 거의 0",
         "빼도 수익 손실 없이 변동성만 줄어 지표가 좋아 보였던 것 (분모 효과)",
         "현 PG2 실코드는 알파 점수 순위 가중 — 걸러진 종목이 최상위 점수·최대 비중 종목",
         "실측: 걸러낸 종목이 대체 종목보다 월 +1.16%p 더 벌었음 = 승자를 자른 셈",
         "통제 실험: 가중 규칙만 시총 가중으로 바꾸면 +0.158(어제 재현), 순위·동일 가중은 전부 음수",
         "교훈: 개선 수치는 어느 base에서 쟀는지에 조건부 — 프레임 간 이식 불가")),
  list(type = "bullet", heading = "진단 (사전등록 병기, 전부 음수)",
       items = list(
         "국면조건부 해제(위기·주의에서 필터 끔)도 −0.155 — 손실원이 평시 승자 컷이라 못 구함",
         "문턱 5%/20% 판 −0.108/−0.104, 동일 노출 판 −0.152, 동일가중 판 −0.067",
         "신호 1개월 지연 판 −0.210, 오버레이 없는 종목계층 판 −0.113",
         "미래참조 방어: 신호 컷오프 전월말 확인 + 위반 주입 시 가드 발화 확인")),
  list(type = "bullet", heading = "다음 단계",
       items = list(
         "실배치 상신 철회 — 현행 무필터 유지 권고 (자본·북 변경은 도훈 수동 + governor 경로)",
         "다음 검증 ①: 순위 조건부 상호작용 — 걸러진 종목이 오히려 승자 표지인지 회귀로 확정",
         "다음 검증 ②: 어제 결과는 시총 가중 스크린 계층 전용으로 라벨 한정",
         "다음 검증 ③: 63일 꼬리변동성은 위험모델 입력으로 소비 (전 라운드 후속)")))

tg_agent_brief(
  agent = "Alpha",
  title = "WT-D20260802_022 ALPHA_DONE — 복권필터 실코드 검증: 상신 철회 (ΔIR −0.149)",
  sections = sections,
  charts = c(file.path(OUT, "charts/wt022_nav_recon.png"),
             file.path(OUT, "charts/wt022_decomp_weighting.png")))
cat("[wt022t] telegram 발송 완료\n")
