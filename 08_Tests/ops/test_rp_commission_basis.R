## 논문 명시 비용의 전달 — "논문 기준 병기" 가 등급 기준(15bps)과 같은 수가 되면 병기가 아니다.
## 실사고 2026-09-04: 래퍼가 무명시(null)를 0.0015 로 덮어써서 병기판과 등급판이 동일해졌고,
##   두 판이 서로를 받치는 것처럼 읽혔다. 러너 계약(run_paper_replication.R:180)은 이미
##   `NULL = 논문 무명시 -> gross(0)` 였는데 래퍼가 그 기본값을 가로챘다.
suppressMessages(library(jsonlite))
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
P <- 0L; F <- 0L
ok <- function(m) { P <<- P + 1L; cat(sprintf("  ok   %s\n", m)) }
ng <- function(m, d = "") { F <<- F + 1L; cat(sprintf("  NG   %s%s\n", m, if (nzchar(d)) paste0(" — ", d) else "")) }
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a

cat("=== A. 추출 규칙 (4 픽스처) ===\n")
## 래퍼가 쓰는 식 그대로
extract <- function(fid) {
  cm <- suppressWarnings(as.numeric(fid$commission_paper %||% NA))
  known <- is.finite(cm)
  if (!known) cm <- NULL
  list(value = cm, known = known)
}
cases <- list(
  list(nm = "논문 명시 2.2bps", fid = list(commission_paper = 0.00022), want = 0.00022, known = TRUE),
  list(nm = "gross 로 명시(0)",  fid = list(commission_paper = 0),       want = 0,       known = TRUE),
  list(nm = "무명시(null)",      fid = list(commission_paper = NULL),    want = NULL,    known = FALSE),
  list(nm = "키 자체가 없음",     fid = list(),                          want = NULL,    known = FALSE)
)
for (c1 in cases) {
  r <- extract(c1$fid)
  if (!identical(r$known, c1$known)) { ng(sprintf("A %s known", c1$nm), sprintf("%s != %s", r$known, c1$known)); next }
  if (is.null(c1$want)) {
    if (is.null(r$value)) ok(sprintf("A %s -> NULL (러너가 gross 로 잡는다)", c1$nm))
    else ng(sprintf("A %s", c1$nm), sprintf("NULL 이어야 하는데 %s", format(r$value)))
  } else {
    if (isTRUE(all.equal(r$value, c1$want))) ok(sprintf("A %s -> %.5f", c1$nm, r$value))
    else ng(sprintf("A %s", c1$nm), sprintf("%s != %s", format(r$value), format(c1$want)))
  }
}

cat("\n=== B. 위반 주입 — 15bps 대체값이 되살아나면 잡히는가 ===\n")
bad <- function(fid) { cm <- suppressWarnings(as.numeric(fid$commission_paper %||% NA))
                       if (!is.finite(cm)) cm <- 0.0015; cm }
if (isTRUE(all.equal(bad(list(commission_paper = NULL)), 0.0015)))
  ok("B 구판 로직은 무명시를 0.0015 로 만든다 (이 검사가 잡아야 하는 것)") else
  ng("B 위반 주입이 재현 안 됨", "픽스처가 병을 못 흉내낸다")
gr <- extract(list(commission_paper = NULL))
if (is.null(gr$value)) ok("B 현행 로직은 같은 입력에서 0.0015 를 만들지 않는다") else
  ng("B 현행이 여전히 대체값을 만든다", format(gr$value))

cat("\n=== C. 소스에 대체값이 남아 있지 않은가 ===\n")
src <- paste(readLines(file.path(ROOT, "02_Infrastructure/ops/rf_replication_verify.R"),
                       warn = FALSE, encoding = "UTF-8"), collapse = "\n")
if (grepl("[.]cmsn *<- *0[.]0015", src)) ng("C .cmsn 에 0.0015 대체값이 있다") else
  ok("C .cmsn 대체값 없음")
if (grepl("[.]cmsn_known", src)) ok("C 명시/무명시 구분 플래그 존재") else
  ng("C .cmsn_known 없음", "무명시가 명시와 구분되지 않는다")

cat("\n=== D. 러너 계약이 여전히 NULL=gross 인가 ===\n")
rsrc <- paste(readLines(file.path(ROOT, "02_Infrastructure/alpha_search/run_paper_replication.R"),
                        warn = FALSE, encoding = "UTF-8"), collapse = "\n")
if (grepl("comm_paper *<- *commission_paper *%[|][|]% *0", rsrc))
  ok("D 러너가 NULL 을 0(gross) 으로 잡는다") else
  ng("D 러너 계약이 바뀌었다", "래퍼가 NULL 을 넘기는 전제가 깨졌다")

cat(sprintf("\n== test_rp_commission_basis: %d pass · %d fail ==\n", P, F))
if (F > 0L) quit(status = 1L)
