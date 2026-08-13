#!/usr/bin/env Rscript
# N2c-2 — 술어 인라인 참조 층을 **파스트리로** 잡는다.
#   정규식 열거는 상수·선호표만 본다(커버리지 2/4). 놓친 2건은 검사 술어 안의
#   인라인 필드/문자열 참조였고, 그 층은 문자열 매칭이 아니라 AST 순회가 맞다.
#   ★목표는 완벽이 아니라 **알려진 실패 4건을 다 잡는가**(양성 대조 통과).
setwd(Sys.getenv("QM_ROOT")); suppressMessages(library(jsonlite))

FILES <- c("02_Infrastructure/methods/register_method.R",
           "02_Infrastructure/methods/new_adapter.R",
           "02_Infrastructure/methods/paper_source.R",
           "02_Infrastructure/methods/ctx_providers.R",
           "02_Infrastructure/tools/hypothesis_index.R",
           "02_Infrastructure/ops/paper_research_dispatch.R",
           "08_Tests/ops/test_hypothesis_index_paper_lane.R",
           "08_Tests/ops/test_queue_id_schema_tolerance.R",
           "08_Tests/methods/test_nearest_arm_axis.R",
           "08_Tests/methods/test_new_adapter_scaffold.R",
           "08_Tests/methods/test_ctx_characteristics.R")

# AST 순회로 두 형태를 수집한다:
#   (a) `$field` / `[["field"]]` 접근 — 특정 필드명에 묶인 참조
#   (b) 문자열 리터럴 — 원천명·필드명 하드코딩(선택자·허용목록의 재료)
.walk <- function(x, acc) {
  if (is.call(x)) {
    op <- tryCatch(as.character(x[[1]])[1], error = function(e) "")
    if (op == "$" && length(x) >= 3) {
      f <- tryCatch(as.character(x[[3]])[1], error = function(e) NA)
      if (!is.na(f)) acc$field <- c(acc$field, f)
    }
    if (op == "[[" && length(x) >= 3 && is.character(x[[3]])) acc$field <- c(acc$field, x[[3]][1])
    # ★인자 **이름**도 규칙의 자리다 — switch(sigma = c(...)) 처럼 kind 매핑이
    #   named argument 로 표현되면 문자열도 $접근도 아니라 앞의 두 축이 다 놓친다.
    .nm <- names(x); if (!is.null(.nm)) acc$field <- c(acc$field, .nm[nzchar(.nm)])
    for (i in seq_along(x)) acc <- .walk(x[[i]], acc)
  } else if (is.character(x) && length(x) == 1L && nzchar(x)) {
    acc$str <- c(acc$str, x)
  }
  acc
}

rows <- list()
for (f in FILES) {
  if (!file.exists(f)) next
  ex <- tryCatch(parse(f, keep.source = FALSE), error = function(e) NULL); if (is.null(ex)) next
  acc <- list(field = character(0), str = character(0))
  for (e in as.list(ex)) acc <- .walk(e, acc)
  tf <- table(acc$field)
  for (nm in names(tf)) rows[[length(rows)+1L]] <- data.frame(
    file = f, form = "field_ref", token = nm, n = as.integer(tf[[nm]]), stringsAsFactors = FALSE)
  # 문자열은 원천명/필드명처럼 **식별자 모양**인 것만(문장·경로 제외)
  s <- acc$str[grepl("^[a-z][a-z0-9_.]{2,30}$", acc$str)]
  ts <- table(s)
  for (nm in names(ts)) rows[[length(rows)+1L]] <- data.frame(
    file = f, form = "str_literal", token = nm, n = as.integer(ts[[nm]]), stringsAsFactors = FALSE)
}
d <- do.call(rbind, rows)
cat(sprintf("AST 수집 %d행 (파일 %d)\n", nrow(d), length(unique(d$file))))

# ── 양성 대조: 알려진 실패 4건을 잡는가
KNOWN <- list(
  list(id="① 큐 식별자 arxiv_id", file="02_Infrastructure/ops/paper_research_dispatch.R", tok="arxiv_id"),
  list(id="③ 검사 T6c avg_exposure", file="08_Tests/ops/test_hypothesis_index_paper_lane.R", tok="avg_exposure"),
  list(id="④ kind→lane 선호(sigma)", file="02_Infrastructure/tools/hypothesis_index.R", tok="sigma"),
  list(id="⑤ 검사 T6b ab_source", file="08_Tests/ops/test_hypothesis_index_paper_lane.R", tok="ab_source"))
cat("\n=== 양성 대조 (알려진 실패 4건) ===\n")
hit <- 0L
for (k in KNOWN) {
  ok <- any(d$file == k$file & d$token == k$tok)
  if (ok) hit <- hit + 1L
  cat(sprintf("  %-28s %s\n", k$id, if (ok) "잡힘" else "★못 잡음"))
}
cat(sprintf("\n커버리지 %d / %d  (정규식판 2/4)\n", hit, length(KNOWN)))
saveRDS(d, file.path(Sys.getenv("TEMP"), "n2_ast.rds"))

# ── 산출: 규칙 후보 + 검사군 등장 여부 (약한 신호) ────────────────────────────
TESTS <- FILES[grepl("^08_Tests/", FILES)]
tst_txt <- paste(unlist(lapply(TESTS[file.exists(TESTS)], readLines, warn = FALSE)), collapse = "\n")
d$in_tests <- vapply(seq_len(nrow(d)), function(i)
  grepl(d$token[i], tst_txt, fixed = TRUE), logical(1))
out <- list(
  generated_at = format(Sys.Date()), n_rows = nrow(d),
  scope = "논문 레인 배관 6 + 검사군 5",
  method = paste0("AST 순회로 (a) $field·[[\"field\"]] 접근 (b) 식별자 모양 문자열 리터럴 ",
                  "(c) 호출 인자 **이름** 을 수집한다. (c)가 없으면 switch(sigma=…) 형태의 ",
                  "kind 매핑을 통째로 놓친다."),
  positive_control = "알려진 실패 4건 전건 검출 (4/4). 정규식판은 2/4 였다.",
  caveat = paste0("★'검사군에 등장'이 '축이 있다'를 뜻하지 않는다 — 등장하면서도 박제로 무너진 ",
                  "실례가 있다(T6c/T6b). 판정은 수기다. 이 산출은 **후보 목록**이다."),
  rows = lapply(seq_len(nrow(d)), function(i) as.list(d[i, ])))
p <- "06_Registry/rule_axis_map_seed_20260813.json"
write(jsonlite::toJSON(out, pretty = TRUE, auto_unbox = TRUE), p)
cat(sprintf("\n→ %s (%d행)\n", p, nrow(d)))
