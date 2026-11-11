#!/usr/bin/env Rscript
# test_gv_family_extension.R — 생성 변형 가족 확장(generate_siblings 의 extends_family)과 공용 Σ 도우미의 등방 상관 분기 시험
#   (2026-11-11 · 비중 카탈로그 추정기 축 확장). 임시 루트(샌드박스)에서만 쓴다 — 실제 등록부 · 방출 원장 · 생성물을 건드리지 않는다.
#   합성 자료만 쓴다(실자료 · 성과 없음). 실패 1건이라도 있으면 종료 코드 1.
suppressWarnings(suppressMessages(library(jsonlite)))
root <- Sys.getenv("QM_TEST_ROOT", "")
if (!nzchar(root)) {
  a <- commandArgs(trailingOnly = FALSE); f <- sub("^--file=", "", a[grep("^--file=", a)])
  root <- if (length(f)) file.path(dirname(f[1]), "..", "..") else "."
}
GV  <- file.path(root, "02_Infrastructure", "methods", "generate_weight_variants.R")
ISO <- file.path(root, "02_Infrastructure", "portfolio", "isotropic_corr_cov.R")
stopifnot(file.exists(GV), file.exists(ISO))

n_ok <- 0L; n_bad <- 0L
ck <- function(cond, msg) { if (isTRUE(cond)) n_ok <<- n_ok + 1L else { n_bad <<- n_bad + 1L; cat("  FAIL:", msg, "\n") } }
err <- function(expr) tryCatch({ force(expr); NA_character_ }, error = function(e) conditionMessage(e))

## 샌드박스 루트 — 카탈로그 최소본(부모 둘) + 빈 원장
mk_sandbox <- function(tag) {
  sb <- file.path(gsub("\\\\", "/", tempdir()), paste0("gv_sb_", tag))
  unlink(sb, recursive = TRUE)
  dir.create(file.path(sb, "06_Registry"), recursive = TRUE)
  dir.create(file.path(sb, "02_Infrastructure", "methods", "adapters", "gen"), recursive = TRUE)
  cat(toJSON(list(entries = list(
    list(catalog_id = "qepm:MVO", label = "MVO", resolver = list(kind = "qepm_registry", dispatch_name = "MVO")),
    list(catalog_id = "lean:score_tilt", label = "score_tilt",
         resolver = list(kind = "lean_builtin", lean_name = "score_tilt", needs_score = TRUE, cov_hook = TRUE)))),
    auto_unbox = TRUE), file = file.path(sb, "06_Registry", "weight_catalog.json"))
  sb
}
ledger_rows <- function(sb) {
  p <- file.path(sb, "06_Registry", "weight_variant_ledger.jsonl")
  if (!file.exists(p)) return(list())
  lapply(Filter(nzchar, trimws(readLines(p, warn = FALSE))), fromJSON, simplifyVector = FALSE)
}
BASE_RECIPE <- list(est_cov_method = character(0), est_sigma = c("sample", "ledoit_wolf"), note = "시험용 기본 가족")

## 한 벌 실행 — 생성기 환경 G 로 샌드박스에서: 기본 가족(형제 2) 방출 → 확장(형제 1) 방출
run_scenario <- function(G, tag) {
  sb <- mk_sandbox(tag)
  d0 <- G$generate_siblings("qepm:MVO", "shrinkage_lift", fixed_recipe = BASE_RECIPE, root = sb, quiet = TRUE)
  d1 <- G$generate_siblings("qepm:MVO", "shrinkage_lift", fixed_recipe = G$gv_recipe_ext("shrinkage_lift"),
                            extends_family = d0$trial_family_id, root = sb, quiet = TRUE)
  list(sb = sb, d0 = d0, d1 = d1, rows = ledger_rows(sb))
}

.GV_QUIET_LOAD <- TRUE
G <- new.env(parent = globalenv()); assign(".GV_QUIET_LOAD", TRUE, envir = G)
suppressWarnings(suppressMessages(sys.source(GV, envir = G)))

## T1 시그니처 — 측정 인자가 없다(방출은 선언 축의 결정적 함수) · extends_family 는 선언 축 인자다
fm <- names(formals(G$generate_siblings))
ck(!length(intersect(tolower(fm), c("ir", "measured", "score", "grade", "sr", "performance", "result"))), "T1 시그니처에 측정 인자 없음")
ck("extends_family" %in% fm, "T1 extends_family 인자 존재")

## T2 가족 확장 — 같은 가족 id · 형제 수 누적 · 스윕 후보 표식 · 새 형제 파일
S <- run_scenario(G, "main")
r0 <- S$rows[[1]]; r1 <- S$rows[[2]]
ck(length(S$rows) == 2L, "T2 원장 2줄(기본 가족 + 확장)")
ck(identical(r0$n_siblings, 2L) && identical(r0$selection_type, "sweep_candidate_family") && !isTRUE(r0$family_extension), "T2 기본 가족 기록(형제 2 · 확장 아님)")
ck(identical(r1$trial_family_id, r0$trial_family_id), "T2 확장 기록이 기존 가족 id 를 쓴다")
ck(identical(r1$n_siblings, 3L) && identical(r1$n_new, 1L), "T2 형제 수 누적 3 · 새 형제 1")
ck(identical(r1$selection_type, "sweep_candidate_family") && isTRUE(r1$family_extension), "T2 확장 기록 = 스윕 후보 가족 · 확장 표식")
ck(isTRUE(r1$emission_is_pre_measurement) && nzchar(r1$emitted_at), "T2 확장 기록에도 측정 전 방출 표식")
ck(!length(intersect(names(r1), c("ir", "IR", "measured", "score", "grade", "sr", "SR"))), "T2 확장 기록에 측정 필드 없음")
new_id <- vapply(r1$siblings, function(s) s$adapter_id, "")
ck(identical(new_id, "qepm_MVO__shr_isotropic"), "T2 새 형제 id")
nf <- file.path(S$sb, "02_Infrastructure", "methods", "adapters", "gen", "qepm_MVO__shr_isotropic.R")
ck(file.exists(nf) && any(grepl('gen_sigma(ctx$R[, a, drop = FALSE], "isotropic")', readLines(nf, warn = FALSE), fixed = TRUE)), "T2 새 형제 파일이 isotropic 추정기를 부른다")

## T3 거부 — 다시 방출 · 모르는 가족 · 부모 불일치 · 빈 계획
ck(grepl("다시 방출", err(G$generate_siblings("qepm:MVO", "shrinkage_lift", fixed_recipe = G$gv_recipe_ext("shrinkage_lift"),
                                              extends_family = r0$trial_family_id, root = S$sb, quiet = TRUE))), "T3 같은 형제 재방출 거부")
ck(grepl("다시 방출", err(G$generate_siblings("qepm:MVO", "shrinkage_lift", fixed_recipe = BASE_RECIPE,
                                              extends_family = r0$trial_family_id, root = S$sb, quiet = TRUE))), "T3 기존 형제 재방출 거부")
ck(grepl("미지 가족", err(G$generate_siblings("qepm:MVO", "shrinkage_lift", fixed_recipe = G$gv_recipe_ext("shrinkage_lift"),
                                              extends_family = "WVF_NOPE", root = S$sb, quiet = TRUE))), "T3 모르는 가족 거부")
ck(grepl("불일치", err(G$generate_siblings("lean:score_tilt", "shrinkage_lift",
                                           fixed_recipe = list(est_cov_method = "isotropic", est_sigma = "isotropic", note = ""),
                                           extends_family = r0$trial_family_id, root = S$sb, quiet = TRUE))), "T3 부모 불일치 거부")
ck(grepl("방출할 형제가 없다", err(G$generate_siblings("lean:score_tilt", "shrinkage_lift", fixed_recipe = G$gv_recipe_ext("shrinkage_lift"),
                                                       root = S$sb, quiet = TRUE))), "T3 빈 계획 거부(cov_method 경로는 열지 않았다)")
ck(length(ledger_rows(S$sb)) == 2L, "T3 거부된 호출은 원장을 쓰지 않는다")

## T4 건식 실행은 파일 · 원장을 쓰지 않는다
sb4 <- mk_sandbox("dry")
d4 <- G$generate_siblings("qepm:MVO", "shrinkage_lift", fixed_recipe = BASE_RECIPE, root = sb4, dry_run = TRUE, quiet = TRUE)
ck(!length(ledger_rows(sb4)) && !length(list.files(file.path(sb4, "02_Infrastructure", "methods", "adapters", "gen"))), "T4 건식 실행 무기록")

## T5 확장 없는 기본 호출의 뜻은 그대로다(형제 1 = chain · 새 가족 id)
sb5 <- mk_sandbox("single")
d5 <- G$generate_siblings("qepm:MVO", "shrinkage_lift", fixed_recipe = list(est_cov_method = character(0), est_sigma = "sample", note = ""),
                          root = sb5, quiet = TRUE)
r5 <- ledger_rows(sb5)[[1]]
ck(identical(r5$n_siblings, 1L) && identical(r5$selection_type, "chain") && !isTRUE(r5$family_extension), "T5 형제 1 = chain")
ck(identical(names(formals(G$gv_recipe_ext)), "rule") && identical(G$gv_recipe_ext()$est_sigma, "isotropic") &&
     !length(G$gv_recipe_ext()$est_cov_method), "T5 확장 레시피 = isotropic 하나 · cov_method 경로 비움")
ck(identical(G$GV_FIXED_RECIPE$shrinkage_lift$est_sigma, c("sample", "ledoit_wolf", "lw_nls", "gerber_rmt", "OGK")), "T5 기본 방출 목록 5종 불변")

## T6 공용 Σ 도우미 — isotropic 분기가 등방 상관 추정기 그대로를 낸다 · 낙하하지 않는다 · sample 불변
source(ISO)                                                     # 도우미의 exists("isotropic_corr_cov") 가 참이 되게(전역)
he <- new.env(parent = globalenv())
sys.source(file.path(S$sb, "02_Infrastructure", "methods", "adapters", "gen", "_gen_sigma.R"), envir = he)
set.seed(20261111L)
n <- 8L; TT <- 260L
mkt <- rnorm(TT, 0, 0.01)
R <- sapply(seq_len(n), function(i) (0.6 + 0.15 * i) * (0.6 * mkt + rnorm(TT, 0, 0.012)))
colnames(R) <- sprintf("A%02d", seq_len(n))
Sg <- he$gen_sigma(R, "isotropic")
Si <- isotropic_corr_cov(R); attr(Si, "iso_diag") <- NULL
ck(isTRUE(all.equal(Sg, Si, tolerance = 0)) && identical(dimnames(Sg), list(colnames(R), colnames(R))), "T6 gen_sigma(isotropic) = isotropic_corr_cov")
ck(is.null(attr(Sg, "iso_diag")), "T6 진단 속성은 떼고 넘긴다")
ck(max(abs(Sg - stats::cov(R))) / max(abs(stats::cov(R))) > 1e-8, "T6 표본공분산과 구별된다")
ck(isTRUE(all.equal(he$gen_sigma(R, "sample"), stats::cov(R), tolerance = 0, check.attributes = FALSE)), "T6 sample 분기 불변")
Rbad <- R; Rbad[, 3] <- 0
ck(!is.na(err(he$gen_sigma(Rbad, "isotropic"))), "T6 분산 0 열 = 멈춤(표본공분산 낙하 없음)")

## T7 돌연변이(양성 대조) — 누적을 빼면(n_family = 새 형제 수) 확장 기록이 형제 1 · chain 이 된다 → T2 의 단정이 깨져야 한다
txt <- readLines(GV, warn = FALSE, encoding = "UTF-8")
hit <- grepl("n_family <- length(sibs) + ext_k_old", txt, fixed = TRUE)
ck(sum(hit) == 1L, "T7 치환 대상 한 곳")
mut <- sub("n_family <- length(sibs) + ext_k_old", "n_family <- length(sibs)", txt, fixed = TRUE)
tf <- tempfile(fileext = ".R"); writeLines(mut, tf, useBytes = TRUE)
M <- new.env(parent = globalenv()); assign(".GV_QUIET_LOAD", TRUE, envir = M)
suppressWarnings(suppressMessages(sys.source(tf, envir = M)))
SM <- run_scenario(M, "mut")
m1 <- SM$rows[[2]]
ck(!(identical(m1$n_siblings, 3L) && identical(m1$selection_type, "sweep_candidate_family")), "T7 돌연변이 검출(누적 누락 → 형제 1 · chain)")

unlink(file.path(gsub("\\\\", "/", tempdir()), c("gv_sb_main", "gv_sb_dry", "gv_sb_single", "gv_sb_mut")), recursive = TRUE)
cat(sprintf("[test_gv_family_extension] 통과 %d · 실패 %d\n", n_ok, n_bad))
if (n_bad > 0L) quit(status = 1L)
