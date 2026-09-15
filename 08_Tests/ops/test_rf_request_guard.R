# test_rf_request_guard.R — 요청 종결 소유 대조 양방향 검사 (2026-09-15)
# 위반 주입 = 09-13 실사고 그대로: 실행 키 2002.06975 가 1806.01743 요청을 닫으려 한다 → 쓰면 안 된다.
# 양성 대조 = 같은 키면 종결이 기록된다(수리가 정상 종결까지 막으면 레인이 같은 논문을 다시 돈다).
# 격리: 임시 디렉터리 요청 파일만 쓴다 — 공유 replication_request.json 무접촉.
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
suppressWarnings(suppressMessages(library(jsonlite)))
source(file.path(ROOT, "02_Infrastructure/ops/rf_request_guard.R"))

n_fail <- 0L
chk <- function(cond, label) {
  if (isTRUE(cond)) cat("PASS", label, "\n") else { cat("FAIL", label, "\n"); n_fail <<- n_fail + 1L }
}
tmp <- tempfile("rfreq_"); dir.create(tmp)
mkreq <- function(key, status = "in_progress") {
  p <- file.path(tmp, sprintf("req_%s.json", gsub("[^A-Za-z0-9]", "_", key)))
  write(toJSON(list(requested_at = "2026-09-13T08:48:16+0900", source = "reinforce_auto_next_paper",
                    paper = list(title = "t", url = "https://arxiv.org/abs/x", paper_key = key),
                    status = status), auto_unbox = TRUE, pretty = TRUE), p)
  p
}
rd <- function(p) fromJSON(p, simplifyVector = FALSE)
fields <- list(base_id = "RP_20260913_090549_14760", grade = "C", artifacts = "x", fidelity = "adapted")

# (1) 위반 주입 — 09-13: 요청은 1806.01743 인데 늦게 끝난 2002.06975 실행이 닫으려 한다
p1 <- mkreq("1806.01743")
r1 <- rf_request_mark_done(p1, "2002.06975", fields)
d1 <- rd(p1)
chk(identical(r1$written, FALSE) && identical(r1$reason, "retargeted"), "retargeted 요청은 기록 거부")
chk(identical(d1$status, "in_progress") && is.null(d1$base_id) && is.null(d1$grade),
    "남의 요청 상태·base_id·grade 불변")

# (2) 양성 대조 — 같은 키면 종결 필드가 전부 기록된다
p2 <- mkreq("1806.01743")
r2 <- rf_request_mark_done(p2, "1806.01743", fields)
d2 <- rd(p2)
chk(isTRUE(r2$written) && identical(r2$reason, "match"), "소유 요청은 기록")
chk(identical(d2$status, "done") && identical(d2$base_id, fields$base_id) && identical(d2$grade, "C") &&
      identical(d2$fidelity, "adapted") && !is.null(d2$completed_at) &&
      identical(d2$paper$paper_key, "1806.01743") && identical(d2$source, "reinforce_auto_next_paper"),
    "종결 필드 기록 + 원 요청 필드 보존")

# (3) 결합 키 — 같은 combo 키는 기록, 구성이 다른 combo 키는 거부
p3 <- mkreq("combo:1403.8125+2007.08115")
chk(isTRUE(rf_request_mark_done(p3, "combo:1403.8125+2007.08115", fields)$written), "combo 동일 키 기록")
p3b <- mkreq("combo:1403.8125+2007.08115")
chk(identical(rf_request_mark_done(p3b, "combo:1403.8125+2011.05381", fields)$written, FALSE), "combo 다른 구성 거부")

# (4) 판별 불가 — 빈 실행 키·키 없는 구판 요청은 기존 동작(기록) 유지
p4 <- mkreq("1806.01743")
chk(isTRUE(rf_request_mark_done(p4, "", fields)$written), "실행 키 공백 → 기존 동작(기록)")
p5 <- file.path(tmp, "req_legacy.json")
write(toJSON(list(status = "in_progress", paper = list(title = "t")), auto_unbox = TRUE), p5)
chk(isTRUE(rf_request_mark_done(p5, "1806.01743", fields)$written), "요청 키 부재(구판) → 기존 동작(기록)")

# (5) 소비자 배선 — verify.R 의 요청 종결 writer 가 이 가드 하나인가 (소비자에서 재도출: AST 순회)
vx <- parse(file.path(ROOT, "02_Infrastructure/ops/rf_replication_verify.R"), keep.source = FALSE)
direct_done <- 0L; guard_calls <- 0L
walk <- function(e) {
  if (is.call(e)) {
    fn <- e[[1]]
    if (identical(fn, as.name("<-")) || identical(fn, as.name("="))) {
      lhs <- e[[2]]; rhs <- e[[3]]
      if (is.call(lhs) && (identical(lhs[[1]], as.name("$")) || identical(lhs[[1]], as.name("[["))) &&
          identical(as.character(lhs[[3]]), "status") && is.character(rhs) && identical(rhs, "done"))
        direct_done <<- direct_done + 1L
    }
    if (identical(fn, as.name("rf_request_mark_done"))) guard_calls <<- guard_calls + 1L
    # 빈 인자(x[, 1] 의 empty symbol)는 변수에 담는 순간 missing 오류 — 인덱스로 건너뛴다
    args <- as.list(e)[-1]
    for (i in seq_along(args)) if (!identical(args[[i]], quote(expr = ))) walk(args[[i]])
  } else if (is.expression(e) || is.pairlist(e) || is.list(e)) {
    for (i in seq_along(e)) if (!identical(e[[i]], quote(expr = ))) walk(e[[i]])
  }
}
for (e in vx) walk(e)
chk(direct_done == 0L, sprintf("verify.R 직접 status<-'done' 0건 (실측 %d)", direct_done))
chk(guard_calls >= 1L, sprintf("verify.R 가 가드 writer 경유 (호출 %d)", guard_calls))

unlink(tmp, recursive = TRUE)
if (n_fail > 0L) { cat(sprintf("FAIL rf_request_guard %d건\n", n_fail)); quit(status = 1) }
cat("rf_request_guard 10/10 PASS — retargeted 거부 · 소유 기록 · combo · 판별불가 기존동작 · 배선\n")
