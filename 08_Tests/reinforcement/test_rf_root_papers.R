#!/usr/bin/env Rscript
#==============================================================================
# test_rf_root_papers.R — 강화 셀 근거 논문 목록 **양방향 검사** (2026-09-02)
#
# 사고: 2301.09173 entry 의 B1 5칸(유동성 → +베타비대칭 → +ROA → +ADX → +왜도)이 전부
#   Amihud(2002) 하나로 원장에 적혔다. rf_pick_factor_sets 가 첫 계열의 논문만 붙였고 사슬이
#   접두 집합이라 첫 계열 = 항상 시드였다. B5 오버레이 5칸은 자체 논문이 없어 러너가
#   `CELL$root_paper %||% w1$root_paper` 로 **B1 승자 논문을 차용**했다 — 낙폭 브레이크가
#   유동성 논문을 인용했고, B5 분기가 넣은 기저 논문은 14줄 뒤 덮어써져 죽은 코드였다.
#   원장의 "같은 root_papers 3회 연속" WARN 이 20칸 연속 발화했다 — 계기가 재려던 것(한 논문
#   매몰)이 아니라 이 표기 결함을 재고 있었다.
#
# 검사 (각각 정상 통과 + 위반 주입):
#   ① 다계열 셀 → 계열 **전부**의 논문이 나온다 (첫 계열 하나가 아니다)
#   ② url 중복 제거 — 같은 계열 팩터 둘 = 논문 하나
#   ③ 매핑 없는 계열은 **버리지 않고 이름으로 남는다**; 그것만 있고 기저도 없으면 원장이 거부한다
#      (기존 가드 rf_append_attempt 가 이 모양의 입력을 실제로 막는지 — 양성 대조)
#   ④ 기저 논문이 첫 항목, 셀 자체 처치 논문이 둘째 (source_paper 폴백 순서와 정합)
#   ⑤ 정적: 두 러너에 구 패턴이 없고 새 헬퍼가 배선돼 있다; B5 는 method 항목을 선두에 둔다
# 부작용 없음 — 원장에 쓰지 않는다(거부 경로는 원장 로드 전에 stop 한다).
#==============================================================================
suppressMessages({ library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
PASS <- 0L; FAIL <- 0L
ok <- function(m) { cat("  OK  ", m, "\n"); PASS <<- PASS + 1L }
ng <- function(m) { cat("  FAIL", m, "\n"); FAIL <<- FAIL + 1L }

suppressMessages(source("02_Infrastructure/ops/rf_factor_arms.R"))
urls_of <- function(ps) vapply(ps, function(p) as.character(p$url %||% ""), character(1))

# 계열별 대표 팩터를 **등록부에서** 고른다 — id 를 박아두면 등록부 위생 제거 때 검사가 낡는다.
EV <- fromJSON("06_Registry/factor_evidence.json", simplifyVector = FALSE)$factors
by_fam <- split(names(EV), vapply(EV, function(e) as.character(e$category %||% "unknown"), character(1)))
pick <- function(fam, k = 1L) { v <- by_fam[[fam]]; if (is.null(v) || length(v) < k) NULL else v[seq_len(k)] }
mapped   <- names(.RFF_FAMILY_PAPER)
unmapped <- setdiff(names(by_fam), c(mapped, "unknown"))
BASE <- list(title = "기저 논문(테스트)", url = "https://arxiv.org/abs/0000.00000")
CELLP <- list(title = "셀 처치 논문(테스트)", url = "https://example.org/cell-treatment")

# ── ① 다계열 → 전 계열 논문 ───────────────────────────────────────────────
f3 <- c(pick("liquidity"), pick("quality"), pick("defense"))
if (length(f3) == 3L) {
  r <- rf_root_papers_for(f3, root = ROOT)
  want <- unique(vapply(c("liquidity", "quality", "defense"), function(fm) .RFF_FAMILY_PAPER[[fm]]$url, character(1)))
  if (setequal(urls_of(r$papers), want) && length(r$families) == 3L)
    ok(sprintf("① 3계열 셀 → 논문 %d건 (계열 전부) · 매핑 공백 0", length(r$papers)))
  else ng(sprintf("① 3계열인데 논문 %d건 / 계열 %d — 첫 계열만 붙는 구판 거동", length(r$papers), length(r$families)))
  # 위반 주입: 구판 규칙(첫 계열 하나)을 흉내 낸 결과와 **달라야** 한다
  old_style <- .RFF_FAMILY_PAPER[[rf_factor_families(f3[1], ROOT)[[1]]]]$url
  if (length(r$papers) > 1L && old_style %in% urls_of(r$papers)) ok("①' 첫 계열 논문은 포함되되 유일하지 않다")
  else ng("①' 구판과 구별 불가(논문 1건) 또는 첫 계열 누락")
} else ng("① 등록부에 liquidity/quality/defense 대표 팩터가 없다")

# ── ② url 중복 제거 ───────────────────────────────────────────────────────
f2 <- pick("liquidity", 2L)
if (length(f2) == 2L) {
  r <- rf_root_papers_for(f2, root = ROOT)
  if (length(r$papers) == 1L && identical(r$papers[[1]]$url, .RFF_FAMILY_PAPER$liquidity$url))
    ok("② 같은 계열 팩터 2종 → 논문 1건(중복 제거)") else ng(sprintf("② 논문 %d건 — 중복 제거 실패", length(r$papers)))
} else ng("② liquidity 팩터 2종을 못 골랐다")

# ── ③ 매핑 없는 계열 — 이름으로 남고, 그것만이면 원장이 거부 ────────────────
if (length(unmapped)) {
  fu <- unlist(lapply(unmapped[seq_len(min(2L, length(unmapped)))], pick))
  r <- rf_root_papers_for(fu, root = ROOT)
  if (!length(r$papers) && setequal(r$unmapped_families, rf_factor_families(fu, ROOT)))
    ok(sprintf("③ 매핑 없는 계열 %s → 논문 0 · unmapped 로 표면화(침묵 누락 아님)", paste(r$unmapped_families, collapse = "+")))
  else ng(sprintf("③ 매핑 없는 계열인데 논문 %d건 / unmapped=%s", length(r$papers), paste(r$unmapped_families, collapse = "+")))
  # ③' ★계약 변경 (도훈 2026-09-03 "강화에는 근거논문 필요없게 배선해").
  #   구 계약은 논문 0건 목록을 원장이 거부하는 것이었다. 이제 거부하지 않는다.
  #   대신 **evidence 필드로 남는다** — 통과 여부가 아니라 적립된 레코드를 재도출해 확인한다.
  suppressMessages(source("02_Infrastructure/reinforcement/reinforce_ledger.R"))
  .tmp <- file.path(tempdir(), sprintf("rf_ev_%s", as.integer(Sys.time())))
  dir.create(file.path(.tmp, "06_Registry"), recursive = TRUE, showWarnings = FALSE)
  invisible(tryCatch(rf_open_entry(1L, "RP_TEST_NONE", "논문없음", "STR_x", "B", root = .tmp),
                     error = function(e) NULL))
  g <- tryCatch({ rf_append_attempt(1L, "RP_TEST_NONE", "근거 없는 시도 1건", "multifactor",
                                    r$papers, root = .tmp); "passed" },
                error = function(e) conditionMessage(e))
  .ev <- tryCatch({
    .e <- Filter(function(x) identical(x$base_id, "RP_TEST_NONE"), rf_load(1L, root = .tmp)$entries)
    .e[[1]]$attempts[[1]]$evidence
  }, error = function(e) NA_character_)
  if (identical(g, "passed") && identical(.ev, "none"))
    ok("③' 논문 0건 → 통과하되 evidence=\"none\" 으로 적립(의무 해제·기록 유지)") else
    ng(sprintf("③' 신계약 불일치: append=%s evidence=%s", substr(g, 1, 50), .ev))
  # 양성 대조 — 논문이 있으면 evidence 는 "paper" 여야 한다(필드가 상수로 굳지 않았음을 보인다)
  .g2 <- tryCatch({ rf_append_attempt(1L, "RP_TEST_NONE", "근거 있는 시도", "multifactor",
                                      list(list(url = BASE$url)), root = .tmp); "passed" },
                  error = function(e) conditionMessage(e))
  .ev2 <- tryCatch({
    .e <- Filter(function(x) identical(x$base_id, "RP_TEST_NONE"), rf_load(1L, root = .tmp)$entries)
    .e[[1]]$attempts[[2]]$evidence
  }, error = function(e) NA_character_)
  if (identical(.ev2, "paper")) ok("③'' 양성 대조 — url 이 있으면 evidence=\"paper\"") else
    ng(sprintf("③'' evidence 가 구별하지 않는다: %s", .ev2))
  unlink(.tmp, recursive = TRUE, force = TRUE)
  # 기저 논문이 붙으면 목록은 비지 않는다(기저 = 항상 첫 항목)
  r2 <- rf_root_papers_for(fu, base_paper = BASE, root = ROOT)
  if (length(r2$papers) == 1L && identical(r2$papers[[1]]$url, BASE$url) && length(r2$unmapped_families) == length(r$unmapped_families))
    ok("③'' 기저 논문 추가 → 목록 1건(기저) + unmapped 유지") else ng("③'' 기저 추가 후 목록/unmapped 불일치")
} else ok("③ (매핑 없는 계열이 없다 — .RFF_FAMILY_PAPER 가 전 계열을 덮는다)")

# ── ④ 순서: 기저 → 셀 처치 → 계열 ──────────────────────────────────────────
if (length(f3) == 3L) {
  r <- rf_root_papers_for(list(factors = lapply(f3, function(i) list(kind = "db", id = i)),
                               factor2 = list(kind = "none")), base_paper = BASE, cell_paper = CELLP, root = ROOT)
  u <- urls_of(r$papers)
  if (length(u) == 5L && u[1] == BASE$url && u[2] == CELLP$url) ok("④ 스펙 입력 · 순서 기저→셀 처치→계열 3 (총 5건)")
  else ng(sprintf("④ 순서/개수 불일치: %s", paste(substr(u, 1, 40), collapse = " | ")))
  # 위반 주입: kind != db 는 계열 조회에서 빠져야 한다 (엔진 내장 신호에 계열을 지어내지 않는다)
  r3 <- rf_root_papers_for(list(factors = list(list(kind = "builtin", id = "lowvol60"))), root = ROOT)
  if (!length(r3$papers) && !length(r3$families)) ok("④' builtin 신호 → 계열·논문 0(날조 없음)") else ng("④' builtin 에 계열/논문이 붙었다")
}

# ── ⑤ 정적 배선 ───────────────────────────────────────────────────────────
for (f in c("02_Infrastructure/ops/reinforce_auto_parallel.R", "02_Infrastructure/ops/reinforce_auto_run.R")) {
  src <- readLines(f, warn = FALSE)
  code <- src[!grepl("^[[:space:]]*#", src)]           # 주석 제외 — 회귀 가드는 코드만 본다
  old <- any(grepl("rp <- CELL$root_paper %||% w1$root_paper", code, fixed = TRUE))
  new <- any(grepl("rf_root_papers_for(SPEC", code, fixed = TRUE)) &&
         any(grepl("rp <- .base_paper %||% CELL$root_paper", code, fixed = TRUE)) &&
         any(grepl('identical(CELL$axis, "risk_overlay")', code, fixed = TRUE)) &&
         any(grepl("list(method = CELL$basis", code, fixed = TRUE))
  if (!old && new) ok(sprintf("⑤ %s — 구 패턴 0 · 헬퍼 배선 · 기저 우선 · B5 method 선두", basename(f)))
  else ng(sprintf("⑤ %s — old=%s new=%s", basename(f), old, new))
}

# ── ⑥ 근거 의무 해제가 **측정 계약까지** 배선됐는가 (2026-09-03 실사고) ──────
#   원장만 해제하고 run_paper_replication 을 그대로 두면, 시도는 등록되고 워커는 뜨고
#   계약에서 죽는다 — 칸 하나가 측정 0 으로 소모된다. 실제로 그렇게 죽었다.
.rpr <- tryCatch(paste(readLines(file.path(ROOT, "02_Infrastructure/alpha_search/run_paper_replication.R"),
                                 warn = FALSE), collapse = "\n"), error = function(e) "")
.wk  <- tryCatch(paste(readLines(file.path(ROOT, "02_Infrastructure/ops/rf_cell_worker.R"),
                                 warn = FALSE), collapse = "\n"), error = function(e) "")
if (grepl("require_source_paper = TRUE", .rpr, fixed = TRUE))
  ok("⑥ 충실구현 기본값은 필수 유지 — 논문 재현에서 논문을 빼지 않는다") else
  ng("⑥ require_source_paper 기본값이 TRUE 가 아니다 — 충실구현이 논문 없이 돈다")

if (grepl("isTRUE(require_source_paper)", .rpr, fixed = TRUE))
  ok("⑥ 게이트가 레인별로 갈린다(조건부)") else
  ng("⑥ 게이트가 무조건이다 — 강화 워커가 계약에서 죽는다")

if (grepl("require_source_paper = FALSE", .wk, fixed = TRUE))
  ok("⑥ 강화 워커가 해제를 넘긴다") else
  ng("⑥ 워커가 해제를 안 넘긴다 — 원장만 열리고 계약이 막는다")

# sprintf 영길이 붕괴 방어 — url 이 NULL 일 때 서식이 통째로 사라지면 안 된다
if (grepl(".sp_url", .rpr, fixed = TRUE) && !grepl("as.character(source_paper$url),", .rpr, fixed = TRUE))
  ok("⑥ url NULL 을 한 번만 정규화해 서식 붕괴를 막는다") else
  ng("⑥ source_paper$url 을 직접 서식에 넣는 자리가 남았다(영길이 붕괴 경로)")

cat(sprintf("\n통과 %d · 실패 %d\n", PASS, FAIL))
cat(sprintf('{"test":"rf_root_papers","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
if (FAIL > 0L) quit(status = 1L)
