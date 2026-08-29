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
  # ★앵커 1순위 = 이 스크립트 자신의 위치 (2026-08-02 수리).
  #   구판은 env(CLAUDE_PROJECT_DIR/QM_ROOT)를 먼저 믿었다 — worktree 에서 돌리면 조용히
  #   **main 트리**를 검사한다. 실측: 이 세션의 수리가 worktree 에 있는데 검사기가 main 을
  #   보고 "술어 정본 부재" FAIL 을 냈다(반대 방향이면 낡은 파일을 초록으로 통과시킨다).
  #   [[reference-cpd-set-in-hooks-unset-in-bash-tool]] · [[project-resolve-project-marker-gate-20260801]]
  #   ★존재 검사가 아니라 **정체 검사** — 표지 파일로 확인하고서야 채택한다.
  .marker <- file.path("02_Infrastructure", "ops", "paper_research_dispatch.R")
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", a[grep("^--file=", a)])
  if (length(f)) {
    d <- dirname(normalizePath(f[1], winslash = "/", mustWork = FALSE))
    r <- normalizePath(file.path(d, "..", ".."), winslash = "/", mustWork = FALSE)
    if (file.exists(file.path(r, .marker))) return(r)
  }
  for (k in c("CLAUDE_PROJECT_DIR", "QM_ROOT")) {
    v <- Sys.getenv(k, "")
    if (nzchar(v) && file.exists(file.path(v, .marker))) return(v)
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

# ── E. 생산자 계약 — ★v10 반전 (2026-08-29): mode_queue 생산 자체가 폐지됐다 ──
#   트리아지 v4(paper_router_v4)는 route {replication, skip} 만 내고 mode_queue 를
#   생산하지 않는다(도훈: 수집 = 팩터전략 단일 목적). 이제 생산 선언이 **되살아나면**
#   위반이다. 본 파일의 소비자(dispatch) 축 A~D·F 는 구 큐 파일 소급 소비 호환으로 유지.
pp <- file.path(.root, "02_Infrastructure", "ops", "paper_router_prompt.md")
ptxt <- if (file.exists(pp)) paste(readLines(pp, warn = FALSE), collapse = "\n") else ""
if (grepl("생산하지 않는다", ptxt, fixed = TRUE) && grepl("mode_queue", ptxt, fixed = TRUE))
  ok("E1(v10) 트리아지가 mode_queue 미생산을 명문 선언") else
  bad("E1(v10) 미생산 선언 부재", "생산 재개가 조용히 가능해진다")
if (!grepl("정본 형태 = 평면", ptxt, fixed = TRUE))
  ok("E2(v10) 구 생산 계약(평면 스키마 선언)이 프롬프트에서 제거됨") else
  bad("E2(v10) 구 생산 계약 잔존", "mode_queue 생산이 되살아난 신호")

# ── F. R↔Python 쌍둥이 동치 (2026-08-02 공용 모듈 승격 동반축) ────────────────
#   dispatch 는 R 이라 술어 정본(research_pool_predicates.py)을 import 할 수 없어 getrt 를
#   유지한다. 그러면 정의가 2벌이 되고, **그 2벌이 갈리는 것이 바로 이번 결함들의 기전**이다.
#   → 무검사 포크로 두지 않고 매 실행 동치를 대조한다. 어느 한쪽만 고치면 여기서 깨진다.
#   ★같은 JSON 바이트를 양쪽에 먹인다(각자 만든 픽스처를 비교하면 비교 자체가 거짓말이 된다).
PRED <- file.path(.root, "02_Infrastructure", "ops", "research_pool_predicates.py")
PY <- Sys.getenv("QVEST_PY", "")
if (!nzchar(PY) || !file.exists(PY)) {
  for (cand in c(Sys.which("python"), Sys.which("python3"))) {
    if (nzchar(cand)) { PY <- cand; break }
  }
}
if (!file.exists(PRED)) {
  bad("F0 술어 정본 부재", PRED)
} else if (!nzchar(PY)) {
  # ★계측 사망을 SKIP(=합격)으로 내려앉히지 않는다 — 이 저장소의 반복 결함 부류다.
  bad("F0 python 해석 실패", "QVEST_PY 미설정 + python/python3 부재 — 동치 대조 불가(미측정)")
} else {
  py_routes <- function(txt) {
    tf <- tempfile(fileext = ".json")
    on.exit(unlink(tf), add = TRUE)
    writeLines(txt, tf, useBytes = TRUE)
    out <- suppressWarnings(system2(PY, c(PRED, "mode-routes", tf), stdout = TRUE))
    if (length(out) == 0L) return(NULL)
    j <- tryCatch(fromJSON(paste(out, collapse = "")), error = function(e) NULL)
    if (is.null(j)) return(NULL)
    c(optimizer = as.integer(j$optimizer), risk = as.integer(j$risk),
      regime = as.integer(j$regime))
  }
  FIX <- list(
    "평면(정본)"     = '{"date":"20260802","schema_version":"paper_router_v2","optimizer":[{"id":"a"},{"id":"b"},{"id":"c"}],"risk":[{"id":"d"},{"id":"e"}],"regime":[{"id":"f"}]}',
    "queue{} 중첩"   = '{"schema_version":"mode_queue_v1","date":"20260727","generated_by":"paper_router_v2","queue":{"optimizer":[{"id":"a"},{"id":"b"},{"id":"c"}],"risk":[{"id":"d"},{"id":"e"}],"regime":[{"id":"f"}]}}',
    "진짜 빈 큐"     = '{"date":"20260803","optimizer":[],"risk":[],"regime":[]}',
    "메타 키만"      = '{"date":"20260804","note":"n"}',
    "부분 중첩(혼합)" = '{"date":"20260805","optimizer":[{"id":"a"}],"queue":{"risk":[{"id":"d"},{"id":"e"}],"regime":[]}}'
  )
  for (nm in names(FIX)) {
    txt <- FIX[[nm]]
    rq <- route_counts(RES, fromJSON(txt, simplifyVector = FALSE))
    pq <- py_routes(txt)
    if (is.null(pq)) {
      bad(sprintf("F %s", nm), "python 쪽 산출 없음 — 동치 미측정(계측 사망)")
    } else if (identical(unname(rq), unname(pq))) {
      ok(sprintf("F %s: R↔Python 동치 %s", nm, paste(unname(rq), collapse = "/")))
    } else {
      bad(sprintf("F %s ★쌍둥이 발산", nm),
          sprintf("R=%s Python=%s — 한쪽만 수리된 상태",
                  paste(unname(rq), collapse = "/"), paste(unname(pq), collapse = "/")))
    }
  }
  # 음성 기준: legacy R 은 중첩 판에서 Python 과 **어긋나야** 한다(이 대조에 이빨이 있는가).
  lq <- route_counts(LEGACY, fromJSON(FIX[["queue{} 중첩"]], simplifyVector = FALSE))
  pq <- py_routes(FIX[["queue{} 중첩"]])
  if (!is.null(pq) && !identical(unname(lq), unname(pq))) {
    ok("F 음성기준: legacy R 은 Python 과 발산한다 (동치 대조에 이빨 있음)")
  } else {
    bad("F ★동치 대조 무력", "legacy R 조차 Python 과 일치 — 이 축이 발산을 못 잡는다")
  }
}

cat(strrep("=", 74), "\n")
cat(sprintf("PASS=%d FAIL=%d\n", PASS, FAIL))
cat(sprintf('{"test":"mode_queue_dispatch_schema","pass":%d,"fail":%d,"total":%d}\n',
            PASS, FAIL, PASS + FAIL))
if (FAIL > 0) quit(status = 1)
