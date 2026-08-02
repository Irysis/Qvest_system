#!/usr/bin/env Rscript
# test_mode_queue_dispatch_schema.R — mode_queue 라우트 해석기 위반 주입 테스트.
#
# 원 결함 (2026-08-02 실측, 확정 유실 사고):
#   mode_queue_20260727.json 이 3키를 최상위가 아니라 `queue`{} 안에 넣었는데
#   paper_research_dispatch.R 의 resolver 는 최상위만 봐서 optimizer=0 risk=0 regime=0.
#   → research_status_20260727.json::actions = []  = **14편(opt 7·risk 4·regime 3) 전량 드롭**.
#     optimizer 7편은 Σ-가중 A/B 배터리를 타야 했는데 한 편도 돌지 않았다.
#   ★schema_version 으로 분기 불가 — 07-27="mode_queue_v1" / 08-02="paper_router_v2"(생산자 이름).
#   ★"0편"과 "못 읽음"이 겉보기가 같아서, 드롭이 정상 종료로 보고됐다.
#
# ★검사 설계 — 양방향:
#   (A) 정본 평면 판을 정확히 읽는가            — 관용을 넣다가 정본을 깨지 않았는지
#   (B) queue{} 중첩 판을 구제하는가            — 원 결함
#   (C) 진짜로 빈 큐는 0 으로 읽되, **미해석 키가 있으면 경고**하는가 (드롭≠0 구분)
#   legacy(수리 전 한 줄 resolver)를 음성 기준으로 동반 실행 — 전부 통과하면 검사가 무력.
#
# ★검사 대상 = 사본이 아니라 원본 .R 의 마커 구간 추출.
#   >>> MODE_QUEUE_ROUTE_RESOLVER … <<< MODE_QUEUE_ROUTE_RESOLVER

suppressWarnings(suppressMessages(library(jsonlite)))

.root <- local({
  for (k in c("CLAUDE_PROJECT_DIR", "QM_ROOT")) {
    v <- Sys.getenv(k, ""); if (nzchar(v) && dir.exists(v)) return(v)
  }
  cand <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
  if (dir.exists(cand)) cand else getwd()
})
TARGET <- Sys.getenv("QVEST_DISPATCH_R",
                     file.path(.root, "02_Infrastructure", "ops", "paper_research_dispatch.R"))

PASS <- 0; FAIL <- 0
ok  <- function(m) { PASS <<- PASS + 1; cat(sprintf("  [PASS] %s\n", m)) }
bad <- function(m, d) { FAIL <<- FAIL + 1; cat(sprintf("  [FAIL] %s — %s\n", m, d)) }

# ── 원본에서 resolver 추출 ────────────────────────────────────────────────────
extract_resolver <- function(path) {
  if (!file.exists(path)) { cat("FATAL: 대상 부재:", path, "\n"); quit(status = 2) }
  ln <- readLines(path, warn = FALSE)
  b <- grep(">>> MODE_QUEUE_ROUTE_RESOLVER", ln, fixed = TRUE)
  e <- grep("<<< MODE_QUEUE_ROUTE_RESOLVER", ln, fixed = TRUE)
  if (length(b) != 1L || length(e) != 1L || e <= b) {
    cat("FATAL: resolver 마커를 찾지 못했다 (b=", length(b), " e=", length(e), ") — ",
        "마커가 바뀌었으면 이 추출기부터 고칠 것. 조용히 0건 검사하는 것을 막기 위해 중단.\n", sep = "")
    quit(status = 2)
  }
  blk <- paste(ln[(b + 1):(e - 1)], collapse = "\n")
  if (!grepl("getrt\\s*<-\\s*function", blk)) {
    cat("FATAL: 추출 구간에 getrt 정의가 없다 — 추출 범위 오류.\n"); quit(status = 2)
  }
  blk
}

LEGACY <- 'getrt <- function(rt) { x <- Q[[rt]]; if (is.null(x)) list() else x }'

# resolver 블록을 주어진 Q 로 평가해 3라우트 길이를 돌려준다.
route_counts <- function(resolver_src, Qval) {
  env <- new.env(parent = globalenv())
  assign("Q", Qval, envir = env)
  eval(parse(text = resolver_src), envir = env)
  g <- get("getrt", envir = env)
  c(optimizer = length(g("optimizer")), risk = length(g("risk")), regime = length(g("regime")))
}

paper <- function(id) list(id = id, title = paste0("t-", id))

# 실 산출과 같은 경로로 만든다(fromJSON simplifyVector=FALSE 통과분).
as_Q <- function(lst) fromJSON(toJSON(lst, auto_unbox = TRUE), simplifyVector = FALSE)

FLAT <- as_Q(list(date = "20260802", schema_version = "paper_router_v2",
                  optimizer = list(paper("a"), paper("b"), paper("c")),
                  risk = list(paper("d"), paper("e")),
                  regime = list(paper("f"))))
NESTED <- as_Q(list(date = "20260727", schema_version = "mode_queue_v1",
                    generated_by = "paper_router_v2",
                    queue = list(optimizer = list(paper("a"), paper("b"), paper("c")),
                                 risk = list(paper("d"), paper("e")),
                                 regime = list(paper("f")))))
EMPTY <- as_Q(list(date = "20260803", schema_version = "paper_router_v2",
                   optimizer = list(), risk = list(), regime = list()))
ONLY_META <- as_Q(list(date = "20260804", schema_version = "paper_router_v2", note = "n"))

RES <- extract_resolver(TARGET)
cat("대상:", sub(paste0("^", .root, "/?"), "", TARGET), "\n")
cat(strrep("=", 74), "\n")

# ── A. 정본 평면 (관용 추가가 정본을 깨지 않았는가) ──
a <- route_counts(RES, FLAT)
if (identical(unname(a), c(3L, 2L, 1L))) ok("A1 정본 평면 판 3/2/1 정확 해석")   else bad("A1 정본 평면", paste(a, collapse = "/"))

# ── B. queue{} 중첩 (원 결함) ──
b <- route_counts(RES, NESTED)
lb <- route_counts(LEGACY, NESTED)
if (identical(unname(b), c(3L, 2L, 1L))) ok("B1 ★원결함 queue{} 중첩 판 구제 3/2/1")  else bad("B1 중첩 구제", paste(b, collapse = "/"))
# ★최상위 if/else 를 두 줄로 쪼개면 R 이 "unexpected 'else'" 로 죽는다
#   (daily_refresh r18 실사고와 동형) — 반드시 중괄호로 묶을 것.
if (identical(unname(lb), c(0L, 0L, 0L))) {
  ok("B2 음성 기준: legacy 는 중첩을 0/0/0 으로 읽는다 (검사에 이빨 있음)")
} else {
  bad("B2 ★검사 무력", sprintf("legacy 가 %s — 이 검사가 결함을 구별하지 못한다", paste(lb, collapse = "/")))
}

# ── C. 진짜 빈 큐는 0 (관용이 아무거나 주워오지 않는가) ──
cc <- route_counts(RES, EMPTY)
if (identical(unname(cc), c(0L, 0L, 0L))) ok("C1 진짜 빈 큐 → 0/0/0 (관용이 유령 항목을 만들지 않는다)") else bad("C1 빈 큐", paste(cc, collapse = "/"))
cm <- route_counts(RES, ONLY_META)
if (identical(unname(cm), c(0L, 0L, 0L))) ok("C2 메타 키만 있는 큐 → 0/0/0") else bad("C2 메타만", paste(cm, collapse = "/"))

# ── D. 미해석 경고 배선 — "드롭"과 "0편"을 구분하는 유일 축 ──
src <- readLines(TARGET, warn = FALSE)
if (any(grepl("미해석 키가 있다", src, fixed = TRUE))) ok("D1 미해석 키 경고 배선 존재 (드롭≠0편 구분)") else bad("D1 경고 배선 부재", "0편과 못읽음이 다시 같은 출력이 된다")
if (any(grepl("n_opt \\+ n_risk \\+ n_reg == 0", src))) ok("D2 경고 조건이 3라우트 합=0 에 걸려 있다") else bad("D2 경고 조건", "조건식 변경됨")

# ── E. 생산자 계약 명문화 (형제 파일 미전파 방지) ──
pp <- file.path(.root, "02_Infrastructure", "ops", "paper_router_prompt.md")
ptxt <- if (file.exists(pp)) paste(readLines(pp, warn = FALSE), collapse = "\n") else ""
if (grepl("정본 형태 = 평면", ptxt, fixed = TRUE)) ok("E1 생산자 프롬프트에 정본 형태(평면) 선언 존재") else bad("E1 생산자 계약 부재", "소비자만 고치면 생산자는 계속 흔들린다")
if (grepl("schema_version", ptxt, fixed = TRUE) && grepl("형태 식별자", ptxt, fixed = TRUE)) ok("E2 schema_version = 형태 식별자 규약 선언 존재") else bad("E2 schema_version 규약 부재", "생산자 이름이 다시 들어가면 분기 불가")

cat(strrep("=", 74), "\n")
cat(sprintf("PASS=%d FAIL=%d\n", PASS, FAIL))
cat(sprintf('{"test":"mode_queue_dispatch_schema","pass":%d,"fail":%d,"total":%d}\n',
            PASS, FAIL, PASS + FAIL))
if (FAIL > 0) quit(status = 1)
