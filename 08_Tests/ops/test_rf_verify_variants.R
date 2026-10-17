## test_rf_verify_variants.R — 모든 방법론(2026-10-17 · 결정 REPLICATION-ALL-METHODS-20261017 — 도훈 '1. 대표칸만 / 2. 논문당 계산 시간 상한 없음 /
##   3. 포트폴리오 구성이 가능하다면 구현하여 성과 측정') 검증기 · 계약 배선 검사
##   [1] 변형 계획(.v1001_variants_plan) — 대표 먼저 · 형식 위반 거부   [2] 측정 뒤 보유 대조(.v1001_holdings_check · P4) — 양성 · 음성 · 경계
##   [3] 뮤테이션(소스 텍스트 치환) — 종목 수 규칙을 끈 사본은 [2] 의 양성을 놓친다   [4] 문턱은 설정에서 온다
##   [5] 보고 섹션(.v1001_variants_extra)   [6] 검증기 배선(정적 · 주석 제외)   [7] 측정 계약 engine_vars — 거부 · 주입 줄 실행 · 기록
##   검증기(02_Infrastructure/ops/rf_replication_verify.R)의 함수 정의만 격리 환경에 올린다(본문 미실행 · 운영 상태 무접촉 · 임시 디렉터리만 쓴다).
## 실행: Rscript 08_Tests/ops/test_rf_verify_variants.R
suppressPackageStartupMessages({ library(jsonlite); library(data.table) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
PASS <- 0L; FAIL <- 0L
chk <- function(cond, m, d = "") if (isTRUE(cond)) { PASS <<- PASS + 1L; cat("  OK  ", m, "\n") } else { FAIL <<- FAIL + 1L; cat("  FAIL", m, d, "\n") }
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
VERIFY_R <- file.path(ROOT, "02_Infrastructure/ops/rf_replication_verify.R")
RUNNER_R <- file.path(ROOT, "02_Infrastructure/alpha_search/run_paper_replication.R")
VL <- readLines(VERIFY_R, warn = FALSE, encoding = "UTF-8")
.def_text <- function(nm, L = VL) {
  i <- which(startsWith(L, paste0(nm, " <- function(")))
  if (!length(i)) return(NULL)
  for (j in i[1]:length(L)) {
    t <- paste(L[i[1]:j], collapse = "\n")
    if (!inherits(tryCatch(parse(text = t), error = function(e) e), "error")) return(t)
  }
  NULL
}
CFG <- fromJSON(file.path(ROOT, "06_Registry/rf_replication_variants.json"), simplifyVector = FALSE)
.load <- function(txts) {
  e <- new.env(parent = globalenv()); e$EV <- character(0); e$.RV_CFG <- CFG; e$ROOT <- ROOT
  e$jlog <- function(event, ...) assign("EV", c(get("EV", envir = e), event), envir = e)
  e$.tg_clip <- function(x, cap) substr(as.character(x), 1L, cap)
  e$.v1001_num <- function(x, d = 2L) { x <- suppressWarnings(as.numeric(x)[1]); if (is.finite(x)) formatC(x, format = "f", digits = d) else "NA" }
  for (t in txts) eval(parse(text = t), envir = e)
  e
}
PLAN <- .def_text(".v1001_variants_plan"); HC <- .def_text(".v1001_holdings_check"); VX <- .def_text(".v1001_variants_extra")
chk(!is.null(PLAN) && !is.null(HC) && !is.null(VX), "0 검증기에 변형 계획 · 보유 대조 · 보고 섹션 정의가 있다")
E <- .load(c(PLAN, HC, VX))

cat("\n[1] 변형 계획 — 대표 먼저 · 형식 위반은 측정 없이 거부\n")
cl <- function(ls, n, net) list(long_short = ls, n_names = n, net_exposure = net, weighting = "ew")
fid3 <- list(headline_variant = "lstm",
             variants = list(list(id = "mlp", label = "MLP", claims = cl(TRUE, 100, 0)),
                             list(id = "lstm", label = "LSTM", claims = cl(TRUE, 100, 0), portfolio_spec = list(construction = "engine_direct")),
                             list(id = "transformer", label = "Transformer", claims = cl(TRUE, 100, 0))))
vp <- E$.v1001_variants_plan(fid3)
chk(identical(vp$ids, c("lstm", "mlp", "transformer")) && identical(vp$headline, "lstm") && vp$n == 3L,
    "1a 대표(lstm)가 먼저 · 나머지는 신고 순서 · 변형 수 3", paste(vp$ids, collapse = ","))
chk(identical(vp$spec[[1]]$construction, "engine_direct") && is.null(vp$spec[[2]]) && isTRUE(vp$claims[[1]]$long_short),
    "1b 변형별 portfolio_spec · claims 가 id 와 같이 움직인다(대표의 사양 = 대표 행)")
chk(is.null(E$.v1001_variants_plan(list(fidelity = "faithful"))), "1c 변형 신고 없음(구판 엔진) = NULL → 구판 경로")
bad <- function(f) inherits(tryCatch(E$.v1001_variants_plan(f), error = function(e) e), "error")
f_up <- fid3; f_up$variants[[1]]$id <- "MLP"
f_dup <- fid3; f_dup$variants[[3]]$id <- "mlp"
f_hl <- fid3; f_hl$headline_variant <- "gru"
chk(bad(f_up) && bad(f_dup) && bad(f_hl), "1d 형식 밖 id · 중복 id · 목록에 없는 대표 = 거부(어느 변형이 권위인지 모르는 채 재지 않는다)")

cat("\n[2] 측정 뒤 보유 대조(P4) — 신고 claims ↔ 04_holdings.csv\n")
.hold <- function(tag, rows) {
  td <- gsub("\\\\", "/", file.path(tempdir(), paste0("vh_", tag))); unlink(td, recursive = TRUE); dir.create(td)
  fwrite(rows, file.path(td, "04_holdings.csv")); td
}
dts <- as.Date("2024-01-31") + c(0, 29, 60)
H_ls <- rbindlist(lapply(dts, function(d) data.table(date = d, ticker = c("A", "B", "C", "D"), target_weight = c(0.5, 0.5, -0.5, -0.5))))
H_one <- rbindlist(lapply(dts, function(d) data.table(date = d, ticker = "A", target_weight = 1)))
H_shortheavy <- rbindlist(lapply(dts, function(d) data.table(date = d, ticker = c("A", "B"), target_weight = c(0.3, -0.7))))
H_n <- function(k) rbindlist(lapply(dts, function(d) data.table(date = d, ticker = sprintf("T%02d", seq_len(k)), target_weight = 1 / k)))
r1 <- E$.v1001_holdings_check(.hold("ls", H_ls), cl(TRUE, 4, 0))
chk(identical(r1$status, "ok") && !isTRUE(r1$mismatch) && r1$measured$short_share == 1 && r1$measured$net_median == 0,
    "2a 롱숏 달러중립 신고 = 실측 → 어긋남 없음(음성 대조)", paste(r1$findings, collapse = "; "))
r2 <- E$.v1001_holdings_check(.hold("one", H_one), cl(FALSE, 10, 1))
chk(isTRUE(r2$mismatch) && any(grepl("종목 수", r2$findings)), "2b 신고 10종 · 실측 1종(2411.13555 형태) → 어긋남", paste(r2$findings, collapse = "; "))
r3 <- E$.v1001_holdings_check(.hold("sh", H_shortheavy), cl(TRUE, 2, 0))
chk(isTRUE(r3$mismatch) && any(grepl("순노출", r3$findings)), "2c 신고 순노출 0 · 실측 −0.4(2604.16773 형태) → 어긋남", paste(r3$findings, collapse = "; "))
r4 <- E$.v1001_holdings_check(.hold("ls2", H_ls), cl(FALSE, 4, 0))
chk(isTRUE(r4$mismatch) && any(grepl("롱온리 신고", r4$findings)), "2d 롱온리 신고인데 숏 보유 → 어긋남")
r5 <- E$.v1001_holdings_check(.hold("one2", H_one), cl(TRUE, 1, 1))
chk(isTRUE(r5$mismatch) && any(grepl("롱숏 신고", r5$findings)), "2e 롱숏 신고인데 숏 없음 → 어긋남")
r6 <- E$.v1001_holdings_check(.hold("nc", H_ls), NULL)
chk(identical(r6$status, "no_claims") && !isTRUE(r6$mismatch) && is.list(r6$measured), "2f 신고 없음 = 실측만 · 꼬리표 없음")
td7 <- gsub("\\\\", "/", file.path(tempdir(), "vh_none")); unlink(td7, recursive = TRUE); dir.create(td7)
chk(identical(E$.v1001_holdings_check(td7, cl(TRUE, 4, 0))$status, "no_holdings"), "2g 보유 기록 없음 = no_holdings(판정 없음)")
r8a <- E$.v1001_holdings_check(.hold("n20", H_n(20)), cl(FALSE, 10, 1))
r8b <- E$.v1001_holdings_check(.hold("n21", H_n(21)), cl(FALSE, 10, 1))
chk(!isTRUE(r8a$mismatch) && isTRUE(r8b$mismatch), "2h 경계 — 비 2.0 = 허용 · 비 2.1 = 어긋남(문턱 n_names_ratio_max 2)")
r9 <- E$.v1001_holdings_check(.hold("nn", H_one), list(long_short = FALSE, n_names = NULL, net_exposure = NULL, weighting = "model"))
chk(!isTRUE(r9$mismatch), "2i 모르는 값(null)은 대조하지 않는다(모델이 종목 수를 정하는 논문)")

cat("\n[3] 뮤테이션 — 종목 수 규칙을 끈 사본은 2b 를 놓친다(검출력 · 소스 텍스트 치환)\n")
HCm <- sub("    if (r > nrm || r < 1 / nrm) mis <- c(mis,", "    if (FALSE) mis <- c(mis,", HC, fixed = TRUE)
chk(!identical(HCm, HC), "3a 치환 성사")
Em <- .load(c(PLAN, HCm, VX))
rm2 <- Em$.v1001_holdings_check(.hold("onem", H_one), cl(FALSE, 10, 1))
chk(!isTRUE(rm2$mismatch), "3b 뮤테이션판은 1종 집중을 통과시킨다 → 2b 가 원본 규칙의 발화임")

cat("\n[4] 문턱은 설정에서 온다(rf_replication_variants.json::holdings_claims)\n")
loose <- CFG$holdings_claims; loose$n_names_ratio_max <- 20
r10 <- E$.v1001_holdings_check(.hold("one3", H_one), cl(FALSE, 10, 1), cfg = loose)
chk(!isTRUE(r10$mismatch) && isTRUE(r10$rules$n_names_ratio_max == 20), "4a 설정 문턱 20 이면 같은 보유가 통과 — 숫자를 코드에 박지 않았다")
chk(identical(as.numeric(CFG$holdings_claims$n_names_ratio_max), 2) && identical(as.numeric(CFG$holdings_claims$net_abs_tol_of_gross), 0.25) &&
      nzchar(CFG$holdings_claims$basis %||% ""), "4b 운영 설정 = 2.0 · 0.25 · 근거 문장 있음")

cat("\n[5] 보고 섹션 — 변형별 한 줄 · 대표 표시 · 측정 실패 · 보유 대조 어긋남\n")
sm <- list(n_variants = 3L, headline = "lstm", variants = list(
  list(id = "lstm", headline = TRUE, status = "ok", grade = "B", cagr = 0.123, calmar = 0.51, port_t = 1.2, crisis_verdict = "normal",
       holdings_mismatch = TRUE, holdings_findings = list("종목 수 신고 10 · 실측 중앙 1")),
  list(id = "mlp", headline = FALSE, status = "ok", grade = "C", cagr = -0.05, calmar = -0.1, port_t = -0.4, crisis_verdict = "weak"),
  list(id = "transformer", headline = FALSE, status = "error", error = "torch import 실패"),
  list(id = "gru", headline = FALSE, status = "ok", grade = "A", cagr = 0.2, calmar = 0.9, port_t = 3.1, crisis_verdict = NA, judge_trigger = TRUE)))
ex <- E$.v1001_variants_extra(sm)
b <- ex[[1]]$body %||% ""
chk(length(ex) == 1L && grepl("lstm(대표) — B", b, fixed = TRUE) && grepl("mlp — C", b, fixed = TRUE) &&
      grepl("transformer — 측정 실패: torch import 실패", b, fixed = TRUE) && grepl("보유 대조 어긋남", b, fixed = TRUE) &&
      grepl("대표 보유 대조(신고 ≠ 실측): 종목 수 신고 10", b, fixed = TRUE) && grepl("3종", ex[[1]]$heading, fixed = TRUE) &&
      grepl("gru — A", b, fixed = TRUE) && grepl("★Judge 트리거", b, fixed = TRUE) && grepl("위기 방어 NA", b, fixed = TRUE),
    "5a 섹션 = 대표 표시 · 등급 · 실패 사유 · 대표 보유 어긋남 상세 · 비대표 A 의 Judge 트리거 표시 · 판정 없음 = NA", substr(b, 1, 300))
chk(is.null(E$.v1001_variants_extra(NULL)), "5b 변형 측정이 없으면 섹션 없음(구판 보고 그대로)")

cat("\n[6] 검증기 배선(정적 · 주석 제외)\n")
VNC <- paste(sub("#.*$", "", VL), collapse = "\n")
MV <- .def_text(".v1001_measure_variants")
chk(grepl('engine_vars = list(.RP_VARIANT = .VP$headline)', VNC, fixed = TRUE) && grepl("variant_headline = TRUE", VNC, fixed = TRUE),
    "6a 대표 측정 = 변형 스위치(대표 id) + 측정 표식(variant_headline)")
chk(!is.null(MV) && grepl('selection_type = "sweep"', MV, fixed = TRUE) && grepl("n_trials_cumulative = as.integer(vp$n)", MV, fixed = TRUE) &&
      grepl('out_root = file.path(head_dir, "variants")', MV, fixed = TRUE) && grepl("engine_vars = list(.RP_VARIANT = id)", MV, fixed = TRUE),
    "6b 나머지 변형 = sweep · n = 변형 수 · 대표/variants/ · 변형 스위치")
chk(!is.null(MV) && grepl('Sys.setenv(QVEST_RP_SEED_BASE_CACHE = "0")', MV, fixed = TRUE) && grepl("on.exit(Sys.setenv(QVEST_RP_SEED_BASE_CACHE = old_seed)", MV, fixed = TRUE),
    "6c 변형 측정 동안 기저 캐시 시드 끔 · 끝나면 복원(캐시 = 대표 = 엔진 기본값)")
chk(grepl('cand[!grepl("/variants/[^/]+/authoritative_remeasure', VNC, fixed = TRUE), "6d 산출물 폴백 후보에서 변형 판 제외")
chk(grepl(".impl_suspect <- isTRUE(.aud_suspect) || isTRUE(.p4_suspect)", VNC, fixed = TRUE) &&
      lengths(regmatches(VNC, gregexpr("holdings_claim_mismatch = isTRUE(.p4_suspect)", VNC, fixed = TRUE))) >= 4L,
    "6e 보유 대조 어긋남 → 구현 의심 꼬리표(소비 · 인계 · 요청 기록)")
chk(lengths(regmatches(VNC, gregexpr(".v1001_variants_extra(), .v1001_factor_section(dirname(ar))", VNC, fixed = TRUE))) == 2L,
    "6f 변형 섹션이 보고 1통에 실린다(기저 미달 · 정상 두 분기)")
i_head <- which(grepl("res <- tryCatch(do.call(run_paper_replication", VL, fixed = TRUE))[1]
i_mv <- which(grepl(".VSUM <- .v1001_measure_variants(", VL, fixed = TRUE))[1]
i_gate <- which(grepl("rf_audit_gate(", VL, fixed = TRUE))[1]
chk(all(is.finite(c(i_gate, i_head, i_mv))) && i_gate < i_head && i_head < i_mv,
    "6g 순서 = 충실도 감사(전 변형 코드) → 대표 측정 → 나머지 변형 측정", sprintf("gate=%s head=%s mv=%s", i_gate, i_head, i_mv))

cat("\n[7] 측정 계약 engine_vars — 거부 · 주입 줄 실행 · 기록\n")
RL <- readLines(RUNNER_R, warn = FALSE, encoding = "UTF-8")
RNC <- paste(sub("#.*$", "", RL), collapse = "\n")
inj <- grep("for (.ev in names(engine_vars)) assign(.ev, engine_vars[[.ev]], envir = fe_env)", RL, fixed = TRUE)
i_sd <- grep("fe_env$.RP_START_DATE <- as.Date(start_date)", RL, fixed = TRUE)
i_src <- grep("source(factor_engine_path, local = fe_env)", RL, fixed = TRUE)
chk(length(inj) == 1L && length(i_sd) == 1L && length(i_src) == 1L && i_sd < inj && inj < i_src,
    "7a 주입 줄이 시작일 주입 뒤 · 엔진 source 앞에 한 번")
## 주입 줄을 그대로 실행 — 작은 엔진이 .RP_VARIANT 를 읽어 산출에 싣는가(양성) · NULL 이면 변수 자체가 없다(구판 동일)
eng <- gsub("\\\\", "/", file.path(tempdir(), "vv_engine.R"))
writeLines('FACTORS <- data.table::data.table(v = if (exists(".RP_VARIANT", inherits = FALSE)) .RP_VARIANT else "default")', eng)
.run_inj <- function(engine_vars) {
  fe_env <- new.env(parent = globalenv()); fe_env$.RP_START_DATE <- as.Date("2000-01-01")
  eval(parse(text = RL[inj]))
  source(eng, local = fe_env); fe_env$FACTORS$v
}
chk(identical(.run_inj(list(.RP_VARIANT = "lstm")), "lstm") && identical(.run_inj(NULL), "default"),
    "7b 주입 줄 실행 — 변형 스위치가 엔진에 닿는다 · NULL 이면 엔진 기본값(구판과 같다)")
chk(grepl("if (length(engine_vars)) list(engine_vars = engine_vars)", RNC, fixed = TRUE), "7c 주입한 값은 measurement_regime.engine_vars 에 기록(재현 = 같은 값)")
suppressMessages(suppressWarnings(source(RUNNER_R)))
rej <- function(ev) { m <- tryCatch({ run_paper_replication("t", "t", eng, engine_vars = ev); "ran" }, error = function(e) conditionMessage(e)); m }
m1 <- rej(list(RAWDATA = 1)); m2 <- rej(list(.RP_VARIANT = c("a", "b"))); m3 <- rej(list("x")); m4 <- rej(list(FACTORS = 1))
chk(grepl("engine_vars", m1) && grepl("engine_vars", m2) && grepl("engine_vars", m3) && grepl("engine_vars", m4),
    "7d RAWDATA 덮기 · 길이 2 값 · 이름 없는 목록 · 엔진 산출 이름(FACTORS) = 데이터 적재 전 거부", paste(substr(c(m1, m2, m3, m4), 1, 60), collapse = " | "))

cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
cat(sprintf('{"test":"rf_verify_variants","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL > 0L) 1L else 0L)
