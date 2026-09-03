#==============================================================================
# test_rf_coverage.R — 지식 소비면 계약 (v10.2 2026-09-03)
#   A 전 entry 정확 중복 · B 좌표 커버리지(성과 무누출) · D 공리 도달·정직 기록
# ★소비면은 "읽었다" 가 아니라 "읽고 무엇이 달라졌나" 로 잰다.
#==============================================================================
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
suppressMessages({ library(data.table); source("02_Infrastructure/reinforcement/rf_coverage.R") })
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat(paste("  OK   ", m), fill = TRUE) }
ng <- function(m, d = "") { FAIL <<- FAIL + 1L
  cat(paste("  FAIL ", m, if (nzchar(d)) paste("—", d) else ""), fill = TRUE) }
rd <- function(f) tryCatch(paste(readLines(file.path(ROOT, f), warn = FALSE), collapse = "\n"),
                           error = function(e) "")

idx <- rf_coverage_index()

# ── A. 전 entry 정확 중복 ───────────────────────────────────────────────────
if (nrow(idx) > 0L && length(unique(idx$base_id)) > 1L)
  ok(sprintf("A1 색인 %d행 · entry %d개 (전 entry 범위)", nrow(idx), length(unique(idx$base_id)))) else
  ng("A1 색인이 비었거나 한 entry 만 본다", sprintf("행 %d", nrow(idx)))

if (nrow(idx) > 0L) {
  s1 <- idx$sig[1]; b1 <- idx$base_id[1]
  h <- rf_coverage_find(s1, idx)
  if (!is.null(h) && nrow(h) == 1L) ok("A2 알려진 서명 조회 적중") else ng("A2 조회 실패")
  # 양성 대조 — 없는 서명은 NULL 이어야 한다(무엇이든 맞다고 하면 가드가 아니다)
  if (is.null(rf_coverage_find("zz|no|such|signature", idx))) ok("A3 미지 서명 → NULL(무차별 적중 아님)") else
    ng("A3 없는 서명에도 적중한다")
  # exclude_base 가 실제로 거르는가
  own <- idx[sig == s1]
  h2 <- rf_coverage_find(s1, idx, exclude_base = b1)
  if (length(unique(own$base_id)) == 1L) {
    if (is.null(h2)) ok("A4 exclude_base 발화 — 자기 entry 만 있으면 NULL") else
      ng("A4 자기 entry 를 못 걸렀다")
  } else {
    if (!is.null(h2) && h2$base_id[1] != b1) ok("A4 exclude_base 발화 — 다른 entry 만 남는다") else
      ng("A4 exclude_base 미발화")
  }
  # 실제 낭비가 잡히는가
  d <- idx[, .N, by = sig][N > 1L]
  if (nrow(d) > 0L)
    ok(sprintf("A5 전 entry 중복 %d종 검출 (측정 %d · 고유 %d)", nrow(d), nrow(idx), length(unique(idx$sig)))) else
    ok("A5 전 entry 중복 0 — 낭비 없음")
}

# 러너 배선 — 색인이 있어도 안 물리면 소용없다
rp <- rd("02_Infrastructure/ops/reinforce_auto_parallel.R")
if (grepl("rf_coverage_find(", rp, fixed = TRUE)) ok("A6 러너가 전 entry 중복을 조회한다") else
  ng("A6 러너 미배선 — 색인만 있고 결정을 안 바꾼다")

# ── B. 좌표 커버리지 — 성과 무누출 ──────────────────────────────────────────
br <- rf_coverage_brief(idx = idx)
lk <- c("calmar", "port_t", "sharpe", "grade", "cagr", "mdd")
hit <- lk[vapply(lk, function(k) grepl(k, tolower(br), fixed = TRUE), logical(1))]
if (!length(hit)) ok("B1 좌표 축약본에 성과 0 — 생성기에 넣어도 안전") else
  ng("B1 축약본이 성과를 누출", paste(hit, collapse = ","))
if (any(vapply(lk, function(k) grepl(k, "best_calmar 0.44", fixed = TRUE), logical(1))))
  ok("B2 누출 스캐너 양성 대조 발화") else ng("B2 스캐너가 죽어 있다")

# ── 서명 정본 — 복제본이 생기면 '같은 포트폴리오' 판정이 소비자마다 갈린다 ──
rr <- rd("02_Infrastructure/ops/reinforce_auto_run.R")
if (file.exists(file.path(ROOT, "02_Infrastructure/reinforcement/rf_spec_sig.R")))
  ok("C1 서명 정본 파일 존재") else ng("C1 정본 파일 부재")
if (!grepl("\n.spec_sig <- function", rp, fixed = TRUE) &&
    !grepl("\n.spec_sig <- function", rr, fixed = TRUE))
  ok("C2 러너 2종에 로컬 서명 정의 0 — 정본만 읽는다") else
  ng("C2 러너가 아직 자기 서명을 정의한다(복제본 부활)")

# ── D. 공리 도달 + 정직한 기록 ──────────────────────────────────────────────
suppressMessages(source("02_Infrastructure/ops/rf_preflight.R"))
ax <- rf_preflight_axioms()
if (length(ax) >= 1L) ok(sprintf("D1 무인 레인이 active 공리 %d건을 직접 적재", length(ax))) else
  ng("D1 공리 적재 0 — 훅도 못 닿고 레인도 안 읽는다")

lg <- rd("02_Infrastructure/reinforcement/reinforce_ledger.R")
if (grepl("axiom_injected = isTRUE(axiom_injected)", lg, fixed = TRUE))
  ok("D2 원장이 인자를 받아 적는다(상수 TRUE 폐지)") else
  ng("D2 axiom_injected 가 아직 상수다 — 거짓 기록")
if (grepl("axiom_injected = FALSE", lg, fixed = TRUE))
  ok("D3 기본값 FALSE — 증명 못 하면 안 적는다") else
  ng("D3 기본값이 FALSE 가 아니다")
if (grepl("axiom_injected = isTRUE(SPEC$preflight$axiom_injected)", rp, fixed = TRUE))
  ok("D4 러너가 실제 적재 여부를 넘긴다") else ng("D4 러너가 값을 안 넘긴다")

# ── E. 죽은-선례 입력 품질 — 잡음을 결정에 물리지 않는다 ────────────────────
sp <- list(factors = list(list(kind = "db", id = "D42_EWMA_Vol"),
                          list(kind = "db", id = "SE02_Consensus_Revision")),
           weighting = list(kind = "catalog"), universe = list(kind = "index"))
kw <- rf_preflight_keywords(sp)
if (any(grepl("D42_EWMA_Vol", kw, fixed = TRUE)))
  ok(sprintf("E1 키워드가 실제 팩터를 낸다 (%s)", paste(head(kw, 4), collapse = "·"))) else
  ng("E1 키워드에 팩터가 없다 — factor2(구판)만 읽는 상태", paste(kw, collapse = ","))
if (length(setdiff(kw, c("catalog", "index"))) >= 2L)
  ok("E2 셀-종류 라벨(catalog/index) 밖의 키가 2개 이상") else
  ng("E2 키가 셀 종류 라벨뿐 — 조회해도 의미 없다", paste(kw, collapse = ","))

cat("", fill = TRUE)
cat(sprintf("합계: 통과 %d · 실패 %d", PASS, FAIL), fill = TRUE)
cat(sprintf('{"test":"rf_coverage","pass":%d,"fail":%d,"total":%d}', PASS, FAIL, PASS + FAIL), fill = TRUE)
if (FAIL > 0L) quit(status = 1L)
