# tg_wt018.R — WT-D20260802_018 완료 브리프 (tg_agent_brief 단일 진입점)
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
  list(type = "text", emoji = "📌",
       text = paste0("FQ-002 계약수주 magnitude 파일럿 판정 — 사전등록 primary(계약금액/최근매출액, 12M 누적) ",
                     "정보계수 +0.016 (t=+0.52) = 문턱 미달. 전구간 크롤(22,533 호출·3.2일) 지불하지 않음.")),
  list(type = "kv", emoji = "📊", title = "실측 (36개월 크롤, 정보계수 표본 24개월)",
       kv = list(
         "primary 정보계수" = "+0.016 (t +0.52, NW +0.57) — 부호는 가설 방향이나 크기 미달",
         "분모 시총 셀(진단)" = "+0.081 (t +1.97) — size-잔차화 후 +1.91 생존, 소형주 역풍(-1.96) 하에서",
         "정정 A/B 누출검증" = "B-A = -0.008 (paired t -0.74) → 누출 지문 없음",
         "lag1 스트레스" = "정보계수 +0.009 — 동월 누출 신호 없음",
         "canonical PORT_t (참고)" = "-0.73 (cap-w) / EW-유니버스 +0.36 — 4셀 포트 전량 음수",
         "커버리지" = "평균 77종/월, 20종 이상 월비율 100%",
         "크롤 실사용" = "5,169 호출 (배정 6,900 내: 크롤 4,435 + 재파싱 689 + 검증 45)")),
  list(type = "text", emoji = "💡", title = "쉬운 설명",
       text = paste0("큰 공급계약을 딴 회사 주식이 이후 오르는지 확인했습니다. '계약이 매출 대비 얼마나 큰가'로 줄을 세워봤더니 ",
                     "예측력이 사실상 없었습니다. 다만 '계약이 회사 몸값(시가총액) 대비 얼마나 큰가'로 재면 약한 예측력이 ",
                     "보여서, 이 방향만 다음 라운드에서 다시 확인합니다. 공시 정정본이 몰래 미래 정보를 흘리는 문제는 없는 것으로 ",
                     "확인됐고, 전체 20년치 데이터 수집(3일 소요)은 근거가 약해 하지 않기로 했습니다.")),
  list(type = "bullet", emoji = "🚩", title = "Challenge Flags",
       items = c("파일럿 표본 24개월 — 자본 판정 아님 (graduation HARD 미적용)",
                 "시총 분모 t=1.97은 문턱 근방 — 멤버십 섭동 취약(WT-013 sd 0.378 선례)",
                 "정보계수 양수여도 포트 전이 실패(4셀 PORT_t -0.57~-0.81) = 전이 벽 재현",
                 "파서 v2 수리 후에도 148건(5.4%) 추출 불가 — 보수적 제외")),
  list(type = "bullet", emoji = "➡️", title = "next_probe",
       items = c("① 분모 시총 primary 신규 사전등록 라운드 (데이터 기지불, 재크롤 불요)",
                 "② 필터/오버레이 소비면 측정 (WT-014/016 선례: 랭킹 죽어도 필터 생존 가능)",
                 "부활 조건: ①에서 t>2.5 재현 시 전구간 크롤 지불 / 2005~2016 수주 사이클 구간 미검"))
)

r <- tg_agent_brief(agent = "Alpha",
                    title = "WT-D20260802_018 ALPHA_DONE — FQ-002 계약수주 magnitude 파일럿: primary 미달, 시총-분모 lead 생존",
                    sections = sections,
                    charts = c("04_Research/method_frontier/fq002_contract_magnitude/fq002_pilot_chart.png"))
cat("[tg] ok =", isTRUE(r$ok), "\n")
