# =============================================================================
# tg_book_dispatch.R — BOOK 리밸 텔레그램 2통 발송 헬퍼 (v10 2026-08-30 신설)
# =============================================================================
# 도훈 지시(2026-08-30): "이 포맷을 BOOK 리밸런싱 스킬의 텔레그램 발송 파트로 추가해줘."
#
# 리밸 1회당 **두 통**을 보낸다 — 숫자와 해석을 한 통에 섞으면 둘 다 안 읽힌다.
#   ① tg_book_weights()  확정 비중 (표 + 배분 요약)
#   ② tg_book_comment()  배분 해설 (애널리스트 노트 — 왜 이 배분이 나왔나)
#
# ★이 헬퍼가 표준화하는 것 = **골격**(섹션 순서·표 구성·중복가드 처리·표제 규약).
#   해설의 내용(어느 축이 움직였고 왜인가)은 매달 다르고 판단이 들어가므로 호출부가 쓴다.
#   기계가 못 채우는 것을 채운 척하지 않는다.
#
# ★넣지 않는 것 — 수리 이력·인프라 작업(도훈 2026-08-30). 전략 코멘트는 배분 판단을
#   설명하는 문서다. 결함 수리·배선 변경·검사 결과는 섞지 않는다(필요하면 별건 보고).
#
# 규약 = .claude/skills/book-rebalance/SKILL.md §5
# =============================================================================

suppressPackageStartupMessages({ library(data.table) })

.tgb_src <- function() {
  root <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
  f <- file.path(root, "02_Infrastructure", "telegram", "telegram_notify.R")
  if (!exists("tg_agent_brief")) suppressPackageStartupMessages(source(f))
  invisible(TRUE)
}

#' ① 확정 비중
#'
#' @param book_id       "BOOK_0001"
#' @param label_month   "9월" 등 표제용
#' @param as_of         "2026-09-01"
#' @param weights_csv   비중 CSV 경로 (rank,Ticker,Name,Sector,Weight)
#' @param summary       한 줄 결론 (20~100자)
#' @param status_kv     "현재 리서치 상황" kv (list) — 단계·대상·데이터 종점·검증
#' @param alloc_kv      "배분 요약" kv (list) — 국면·주식/현금·종목수·전월 대비
#' @param footer        지문·데이터 종점 등
tg_book_weights <- function(book_id, label_month, as_of, weights_csv,
                            summary, status_kv, alloc_kv, footer,
                            dry_run = FALSE, force = FALSE) {
  .tgb_src()
  W <- fread(weights_csv, encoding = "UTF-8")
  eq <- W[Ticker != "CASH"][order(-Weight)]
  # ★표는 2열 상한(tg_format_table v6 SOT — 모바일 가독성). 순위는 행 순서로 표현한다.
  #   종목명에 순번을 붙이면 열 폭 초과로 이름이 잘린다(실측).
  tbl <- data.frame(종목 = eq$Name, 비중 = sprintf("%.2f%%", eq$Weight * 100),
                    stringsAsFactors = FALSE)
  tg_agent_brief(
    agent = "Book",
    title = sprintf("[BOOK] 트래킹 — %s %s 확정 비중", book_id, label_month),
    as_of = as_of, dry_run = dry_run, force = force,
    sections = list(
      list(type = "summary", emoji = "📌", body = summary),
      list(type = "kv", emoji = "🧭", heading = "현재 리서치 상황", kv = status_kv),
      list(type = "kv", emoji = "📊", heading = "배분 요약", kv = alloc_kv),
      list(type = "table", emoji = "📋", heading = "종목별 비중 (전체 대비)", df = tbl)),
    footer = footer)
}

#' ② 배분 해설 (애널리스트 노트)
#'
#' 문체 규약(SKILL §5-2):
#'   · 기계적 표현 금지 — "꺼졌다/걷혔다" 대신 "경보 문턱을 하향 통과하며 총점에서
#'     8점이 일괄 제거됐습니다" / "해소된 결과로 보기는 어렵습니다"
#'   · 약어는 **반드시** terms 에 풀이. 독자가 사전을 찾게 하지 않는다.
#'   · 수치는 **변화의 원인까지** — "-0.354 -> -0.514" 로 끝내지 말고 기여분 분해까지.
#'   · **움직이지 않은 축도 적는다.** 한 축만 보고하면 그 축이 원인으로 읽힌다.
#'
#' @param terms     용어 풀이 character 벡터 ("MSM: 마르코프 전환 모형. ...")
#' @param axes      list(list(emoji=, heading=, items=character())) — 오버레이 축별 섹션
#' @param outlook   전망·관찰 포인트 character 벡터
#' @param nature    판정의 성격(절대 수준 vs 상대 순위 등) character 벡터. NULL 가능
#' ★force 기본값은 FALSE 다 (2026-08-30 실사고로 정정).
#'   초판은 "코멘트는 늘 두 번째 메시지"라는 이유로 force=TRUE 를 **기본값**으로 뒀는데,
#'   그러면 중복 가드가 상시 무력화된다. 실제로 발송 성공 여부를 확인하려 스크립트를
#'   한 번 더 돌렸다가 **같은 메시지가 두 번 나갔다.** 편의를 위해 안전장치를 기본으로
#'   끄면 안 된다 — 필요한 호출에서만 명시적으로 켠다(5-1 직후 5-2 를 보낼 때).
#' @param topic  표제 꼬리표. 기본 "배분 해설". ★한 달에 코멘트를 여러 통 보낼 때는
#'   **topic 을 달리한다** — 제목이 같으면 중복 가드의 scope 가 같아져 2통째가 막히고,
#'   그걸 force 로 뚫는 습관이 들면 진짜 중복도 통과한다. 제목을 구분하는 게 정답이다.
tg_book_comment <- function(book_id, label_month, as_of, summary, status_kv,
                            terms, axes, outlook, nature = NULL, footer,
                            topic = "배분 해설", dry_run = FALSE, force = FALSE) {
  .tgb_src()
  if (!length(terms))
    stop("[tg_book_comment] terms 필수 — 약어 풀이 없는 코멘트는 보내지 않는다(SKILL §5-2)")
  secs <- c(
    list(list(type = "summary", emoji = "📌", body = summary),
         list(type = "kv", emoji = "🧭", heading = "현재 리서치 상황", kv = status_kv),
         list(type = "bullet", emoji = "📖", heading = "용어", items = terms)),
    lapply(axes, function(a) list(type = "bullet", emoji = a$emoji %||% "📉",
                                  heading = a$heading, items = a$items)),
    list(list(type = "bullet", emoji = "🔭", heading = "전망 및 관찰 포인트", items = outlook)))
  if (length(nature))
    secs <- c(secs, list(list(type = "bullet", emoji = "📐",
                              heading = "판정의 성격", items = nature)))
  # ★5-1(확정 비중) 직후에 보내면 제목 scope 가 같게 정규화돼 30분 창에서 막힌다.
  #   그 때만 호출부가 force=TRUE 를 **명시**한다. 기본값으로 켜두지 않는다 —
  #   기본 TRUE 였던 초판에서 재실행 한 번에 같은 메시지가 두 번 나갔다(2026-08-30).
  tg_agent_brief(
    agent = "Book",
    title = sprintf("[BOOK] 코멘트 — %s %s %s", book_id, label_month, topic),
    as_of = as_of, dry_run = dry_run, force = force,
    sections = secs, footer = footer)
}

`%||%` <- function(a, b) if (is.null(a)) b else a

cat("[tg_book_dispatch.R] Loaded — tg_book_weights() / tg_book_comment() (SKILL §5)\n")
