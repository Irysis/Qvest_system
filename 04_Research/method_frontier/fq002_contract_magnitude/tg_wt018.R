# tg_wt018.R — WT-D20260802_018 완료 브리프 (tg_agent_brief 단일 진입점, v2 — 섹션 스키마 정정)
.rt <- function() {
  cands <- c(Sys.getenv("CLAUDE_PROJECT_DIR", unset = ""), Sys.getenv("QM_ROOT", unset = ""),
             "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
  cands <- cands[nzchar(cands)]
  hit <- cands[file.exists(file.path(cands, "02_Infrastructure/hooks/qvest_hook_router.py"))]
  if (!length(hit)) stop("root 미발견"); hit[1]
}
ROOT <- .rt(); setwd(ROOT)
source("02_Infrastructure/telegram/telegram_notify.R")

sections <- list(
  list(type = "summary",
       body = "FQ-002 계약수주 magnitude 파일럿: 사전등록 primary 미달 — 전구간 크롤 지불 안 함. 시총-분모 lead만 생존."),
  list(type = "kv", emoji = "📊", heading = "실측 (36개월 크롤, 정보계수 표본 24개월)",
       kv = list(
         "primary 정보계수(계약/매출)" = "+0.016 (t +0.52) — 미달",
         "시총-분모 셀(진단)" = "+0.081 (t +1.97, 잔차화 +1.91 생존)",
         "정정 A/B 누출검증" = "B-A -0.008 (t -0.74) — 지문 없음",
         "lag1 스트레스" = "+0.009 — 동월 누출 없음",
         "실현 초과수익 t값 (참고)" = "-0.73 / 4셀 전량 음수",
         "커버리지" = "77종/월, 20종 이상 100%",
         "크롤 실사용" = "5,169 호출 (배정 6,900 내)")),
  list(type = "text", emoji = "💡", heading = "쉬운 설명",
       body = paste0("큰 공급계약을 딴 회사가 이후 오르는지 봤습니다. '매출 대비 계약 크기'는 예측력이 없었고, ",
                     "'회사 몸값(시가총액) 대비 크기'만 약한 예측력이 보여 다음 라운드에서 재확인합니다.")),
  list(type = "bullet", emoji = "🚩", heading = "Challenge Flags",
       items = c("파일럿 표본 24개월 — 자본 판정 아님 (graduation HARD 미적용)",
                 "시총-분모 t 1.97은 문턱 근방 — 멤버십 섭동 취약 (WT-013 선례 sd 0.378)",
                 "정보계수 양수여도 포트 전이 실패 (4셀 PORT_t -0.57~-0.81) = 전이 벽 재현",
                 "파서 v2 수리 후에도 148건(5.4%) 추출 불가 — 보수적 제외")),
  list(type = "bullet", emoji = "➡️", heading = "next_probe",
       items = c("① 시총-분모 primary 신규 사전등록 라운드 — 데이터 기지불, 재크롤 불요",
                 "② 필터/오버레이 소비면 측정 (선례: 랭킹 죽어도 필터 ΔIR +0.169)",
                 "부활 조건: ①에서 t>2.5 재현 시 전구간 크롤 지불 / 2005~2016 수주 사이클 구간 미검"))
)

r <- tg_agent_brief(agent = "Alpha",
                    title = "WT-D20260802_018 ALPHA_DONE — FQ-002 계약수주 magnitude 파일럿",
                    sections = sections,
                    charts = c("04_Research/method_frontier/fq002_contract_magnitude/fq002_pilot_chart.png"))
cat("[tg] ok =", isTRUE(r$ok), "\n")
