# tg_wt023.R — WT-D20260802_023 완료 브리프 (tg_agent_brief 단일 진입점)
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
       body = "FQ-125 확정: 섭동 q05 +1.44>0 (120/120 양수) — 신호 실재. 크롤은 전액 일괄 대신 단계 지불 권고."),
  list(type = "kv", emoji = "📊", heading = "실측 (사전등록 섭동 판정, 120 draws)",
       kv = list(
         "섭동 q05 (t_NW)" = "+1.44 (멤버십 +1.42 / 스코어 노이즈 +1.62) — 전 120 draws 양수",
         "무섭동 정보계수" = "+0.081 (t +1.97, NW +1.70, ICIR 0.40) — WT-018 정확 재현",
         "정정 A/B 누출검증" = "B-A -0.004 (paired t -0.83) — 지문 없음",
         "lag1 스트레스" = "t +1.94 — 붕괴 없음 (12개월 누적 신호 특성)",
         "부기간" = "전반12 +0.122 (t 1.99) → 후반12 +0.040 (t 0.73) — 감쇠",
         "감쇠 진단" = "커버리지 아티팩트 기각(상관 +0.05) / 국면 연동 -0.26·산포 -12%는 방향만",
         "실현 초과수익 t값 (cap-w)" = "-0.37 — 전이 벽 불변 (EW-유니버스 대비 +1.49)",
         "PIT 검사기" = "9/9 재실행 통과 (위반 주입 포함)")),
  list(type = "bullet", emoji = "💡", heading = "쉬운 설명",
       items = c("'몸값 대비 큰 계약을 딴 회사가 이후 오른다'는 신호를 120번 흔들어 재봄(종목 빼기·노이즈)",
                 "120번 전부 양수 — 우연한 한 번의 결과 아님. 다만 세기는 통계 문턱(2.0) 아래",
                 "최근 1년 약화 — 과거 데이터를 한 번에 다 사지 말고 절반 먼저, 중간 점검 후 나머지 권고")),
  list(type = "bullet", emoji = "🚩", heading = "Challenge Flags (자가 적대검증 8건 중 핵심)",
       items = c("같은 패널 재사용 — q05 확정은 강건성 확인이지 독립 표본 확인 아님 (n=24 한계는 크롤만 해소)",
                 "q05 +1.44 < 문턱 2.0 — 부호 강건과 문턱 통과는 다른 주장 (지불 권고에 병기)",
                 "후반 12개월 감쇠 미해명 — 1단계 크롤(n=103)의 판별 목적",
                 "cap-w PORT_t -0.37 = 랭킹 소비 불가 — 소비는 필터/오버레이 면(FQ-126)",
                 "WT-022 교훈 승계: 소비면 편익은 production 실코드 base 위에서만 유효 판정")),
  list(type = "bullet", emoji = "➡️", heading = "next_probe + 지불 권고 (최종 결정 = 도훈)",
       items = c("① 단계 크롤: 2017~2023 먼저(~8,000호출·~1.2일) — interim 게이트로 잔여 지불 결정",
                 "  게이트: 합산 t_NW>=1.5 AND 신규구간 IC>0 → 잔여 지불 / t_NW<1.0 → 중단·재분류",
                 "② FQ-126 필터/오버레이 소비면 — 착수 시 production 실코드 base 의무",
                 "③ (위생) 전구간 grid 재빌드 시 rawdata_sanitize 적용 vintage 사용",
                 "부활 조건: 초대형주 집중 정상화 6개월 지속 후 trailing 24개월 재측정"))
)

r <- tg_agent_brief(agent = "Alpha",
                    title = "WT-D20260802_023 ALPHA_DONE — FQ-125 시총-분모 확정 (섭동 q05 +1.44, 단계 지불 권고)",
                    sections = sections,
                    charts = c("04_Research/method_frontier/fq002_contract_magnitude/fq125_confirm_chart.png"))
cat("[tg] ok =", isTRUE(r$ok), "\n")
