## [1계층] 논문 트리아지 발신 — 2026-09-24
## 단일 진입점 tg_agent_brief() 만 사용 (직접 호출은 PreToolUse Hook 차단).
## ★본 파일은 UTF-8 리터럴로 쓴다 — \uXXXX 이스케이프는 LC_CTYPE=C 에서
##   kv **이름**으로 쓸 때 native 변환에 실패해 <U+B2E8> 꼴로 깨진다(실측 2026-09-24).
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source(file.path(ROOT, "02_Infrastructure/telegram/telegram_notify.R"))

secs <- list(
  list(emoji = "\U0001F52D", heading = "결론", type = "summary",
       body = "복구 253건 · 신규 8건 · testable 1건 — 2603.20271 KR 투자자유형 흐름 네트워크"),

  list(emoji = "\U0001F4CD", heading = "현재 리서치 상황", type = "kv",
       kv = list(
         "단계"      = "1계층 논문 트리아지 — 백테 없음",
         "대상"      = "arXiv 복구 253건 + curated 시드 26건",
         "산출"      = "stage_artifacts/paper_recharge/alpha_search_route_20260924.json",
         "직전 판정" = "09-18 · 09-19 수집 실패로 라우팅 0건"
       )),

  list(emoji = "\U0001F9ED", heading = "판정 내역", type = "kv",
       kv = list(
         "testable"               = "1건 → route replication",
         "redundant"              = "245건 (이 체인이 이미 소비)",
         "skip"                   = "7건 (파생가격 · 미시구조 · 보험 · 채권표적)",
         "data_pipeline_required" = "0건 (큐 append 없음)"
       )),

  list(emoji = "\U0001F52C", heading = "유일한 후보 2603.20271", type = "text",
       body = paste0(
         "Transfer Entropy 로 외국인 · 기관 · 개인 순매수 흐름의 종목간 정보전이 네트워크를 구성하고 중심성을 횡단면 스코어로 쓴다. ",
         "데이터 충족 — investor_all 패널 3231만행 · 2000년부터, 논문 창(2020-01~2025-02) 실측 2642종목 · 1269거래일로 전구간 커버된다. ",
         "★저자 자신이 알파 부재를 보고한다 — 중심성 기여 negligible, 일별 상호정보 0. ",
         "따라서 충실구현의 '논문 기준 성과'는 유의 알파 없음이고, 재현 성공 = 알파 부재의 재현이다.")),

  list(emoji = "\U0001F6E0\uFE0F", heading = "수집원 복구", type = "text",
       body = paste0(
         "금일 · 전일 수집(mcp_discovery)은 status=mcp_error · candidates 0 이었다 — arxiv-mcp-server 가 30질의를 무간격 연사해 HTTP 406 을 맞았다. ",
         "arXiv 자체는 정상(단건 응답 0.14초)이라 동일 질의를 3.1초 간격으로 직접 재발사해 253건 복구했다(실패 질의 0). ",
         "환경 실패를 '신규 논문 0건'이라는 리서치 판정으로 굳힐 자리였다.")),

  list(emoji = "\u27A1\uFE0F", heading = "다음", type = "bullet",
       items = c(
         "2603.20271 은 null 재현 후보 — 큐 우선순위는 1계층 세션 판단",
         "하네스 유의 — 논문은 일별 신호인데 충실구현은 월간 집행, changed 신고 의무",
         "dedup 에 구표기 arXiv id 포함 — 미포함 시 신규가 8→21 로 부풀었다",
         "curated 시드 26건은 전건 기처리 — 신규 0건"
       ))
)

res <- tg_agent_brief(
  agent      = "AlphaSearch",
  title      = "[1계층] 논문 트리아지",
  as_of      = "2026-09-24",
  sections   = secs,
  relaxed    = TRUE,
  force      = TRUE,
  lock_scope = "paper_router_20260924"
  ## glossary 는 기본값(NULL → relaxed 에서 파생) 유지 = 이 레인의 기존 관행.
  ## ★실행 시 유효한 UTF-8 로케일 필수 — LC_ALL=C.UTF-8 은 Windows R 이 못 세워
  ##   LC_CTYPE=C 로 떨어지고, telegram_notify.R 안의 한글·중점(·) 리터럴이
  ##   mojibake 가 된다(실측 2026-09-24). LC_ALL="English_United States.utf8" 로 기동할 것.
)
cat("\n[tg] ok=", isTRUE(res$ok), " bytes=", res$bytes %||% NA,
    " error=", res$error %||% "none", "\n", sep = "")
if (!isTRUE(res$ok)) quit(status = 1)
