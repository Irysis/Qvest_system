## =============================================================================
## make_engines.R — DT_2002_06975 엔진 7개 결정론 생성 (P2R05 · 설계 §7.1)
##   템플릿(engine_template.R)의 규칙 줄 '.DT_RULE <- "TEMPLATE"' 하나만 '.DT_RULE <- "<규칙>"' 로 바꾼 자기완결 파일
##   engine_{Q50,V1,V2,N1,N2,S1,S2}.R 을 쓴다. source(코어) 래퍼는 쓰지 않는다 — 셀 기저 캐시 키가 엔진 파일 md5 하나라서
##   코어만 고치면 래퍼 키가 깨지지 않는다(무효화 키 누락).
##   바이트 그대로: 템플릿을 LF 로 나눠 그 한 줄만 바꾸고 LF 로 다시 잇는다(마지막 줄바꿈 여부 보존). 내용이 같으면 파일을 다시 쓰지 않는다.
##   + rx0s/engine_RX0S.R(P2R05 시드 띠 · 판단 T1 C-20261018-054) — 원본 평균 엔진 engine.R(rev3) 사본에서 template_diff_check.R 의
##     RX0S_SUBST 세 줄의 부분 문자열만 바꾼다: 72행 시드 기저 20020697L → 20261018L(캐시 키 명세의 시드가 바뀌므로 261개월 전부 새로 학습) ·
##     101행 작업 디렉터리(원본 .WD 는 루트 기준 고정 경로라 바꾸지 않으면 원본 RP_AUTO_2002_06975/_work/cache 에 쓴다 → rx0s/_work/{run_*, cache}) ·
##     48행 로그 꼬리표 [DT_2002_06975:RX0S]. 파이썬 rev3 본문 · CODE_VERSION 은 그대로(평균 표적 모델 그대로 · 시드만 다름).
##   + engines_manifest.json(템플릿 · 생성기 · 생성 7개 · RX0S · 원본 engine.R 의 md5 · 생성 시각 · CODE_VERSION) → template_diff_check 로 즉시 대조.
## 실행: Rscript make_engines.R      (종료 코드 0 = 생성 + 차분 대조 통과)
## =============================================================================
suppressPackageStartupMessages(library(jsonlite))
.me_root <- function() {
  marker <- "02_Infrastructure/hooks/qvest_hook_router.py"
  ca <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", ca[startsWith(ca, "--file=")])
  from_file <- if (length(f)) normalizePath(file.path(dirname(f[1]), "..", "..", ".."), winslash = "/", mustWork = FALSE) else ""
  for (p in c(Sys.getenv("QM_ROOT", ""), Sys.getenv("CLAUDE_PROJECT_DIR", ""), from_file, "C:/Users/99922/OneDrive/Quant_Module_Moltbot")) {
    if (!nzchar(p)) next
    p <- gsub("\\\\", "/", p)
    if (file.exists(file.path(p, marker))) return(p)
  }
  stop("[make_engines] 프로젝트 루트를 찾지 못함")
}
ROOT <- .me_root()
REL <- "04_Research/strategies/DT_2002_06975"
DD <- file.path(ROOT, REL)
source(file.path(DD, "template_diff_check.R"))         # RX0S_SUBST · dt_rx0s_lines · dt_template_diff_check(같은 정의 — 생성과 대조가 한 정본)
write_bytes_if_changed <- function(lines, final_nl, p) {
  ob <- charToRaw(paste0(paste(lines, collapse = "\n"), if (final_nl) "\n" else ""))
  same <- file.exists(p) && identical(readBin(p, "raw", file.info(p)$size), ob)
  if (!same) {
    tmp <- sprintf("%s.%d.tmp", p, Sys.getpid())
    writeBin(ob, tmp)
    if (!file.rename(tmp, p)) { unlink(tmp); stop("[make_engines] 교체 실패: ", p) }
  }
  !same
}
RULES <- c("Q50", "V1", "V2", "N1", "N2", "S1", "S2")
TEMPLATE_LINE <- '.DT_RULE <- "TEMPLATE"'
md5f <- function(p) unname(as.character(tools::md5sum(p)))

tp <- file.path(DD, "engine_template.R")
raw_t <- readBin(tp, "raw", file.info(tp)$size)
txt <- rawToChar(raw_t); Encoding(txt) <- "bytes"
final_nl <- length(raw_t) > 0L && raw_t[length(raw_t)] == as.raw(10L)
L <- strsplit(txt, "\n", fixed = TRUE, useBytes = TRUE)[[1]]
k <- which(L == TEMPLATE_LINE)
if (length(k) != 1L) stop(sprintf("[make_engines] 템플릿의 규칙 줄 '%s' 가 %d개 — 1개여야 한다", TEMPLATE_LINE, length(k)))
cv <- grep('^CODE_VERSION = "', L, value = TRUE, useBytes = TRUE)
if (length(cv) != 1L) stop("[make_engines] 템플릿 파이썬 CODE_VERSION 줄이 1개가 아니다")
code_version <- sub('^CODE_VERSION = "([^"]+)".*$', "\\1", cv, useBytes = TRUE)

eng <- list()
for (r in RULES) {
  L2 <- L; L2[k] <- sprintf('.DT_RULE <- "%s"', r)
  p <- file.path(DD, sprintf("engine_%s.R", r))
  wrote <- write_bytes_if_changed(L2, final_nl, p)
  eng[[length(eng) + 1L]] <- list(rule = r, path = file.path(REL, basename(p)), md5 = md5f(p), rule_line_no = k,
                                  rule_line = L2[k], written = wrote)
  cat(sprintf("[make_engines] engine_%s.R %s · md5 %s\n", r, if (wrote) "생성" else "그대로(내용 같음)", md5f(p)))
}
## RX0S — 원본 engine.R 바이트에서 RX0S_SUBST 세 줄만 치환
op <- file.path(ROOT, "04_Research/strategies/RP_AUTO_2002_06975/engine.R")
raw_o <- readBin(op, "raw", file.info(op)$size)
txo <- rawToChar(raw_o); Encoding(txo) <- "bytes"
LO <- strsplit(txo, "\n", fixed = TRUE, useBytes = TRUE)[[1]]
fo_nl <- length(raw_o) > 0L && raw_o[length(raw_o)] == as.raw(10L)
dir.create(file.path(DD, "rx0s"), recursive = TRUE, showWarnings = FALSE)
rxp <- file.path(DD, RX0S_REL)
rx_wrote <- write_bytes_if_changed(dt_rx0s_lines(LO), fo_nl, rxp)
cat(sprintf("[make_engines] %s %s · md5 %s · 원본 대비 %d줄(%s)\n", RX0S_REL, if (rx_wrote) "생성" else "그대로(내용 같음)", md5f(rxp),
            length(RX0S_SUBST), paste(vapply(RX0S_SUBST, function(s) sprintf("%d %s", s$line, s$what), ""), collapse = " · ")))
man <- list(schema = "dt_engines_manifest_v1",
            generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
            round_id = "P2R05_distribution_target",
            code_version = code_version,
            template = list(path = file.path(REL, "engine_template.R"), md5 = md5f(tp), n_lines = length(L), final_newline = final_nl),
            generator = list(path = file.path(REL, "make_engines.R"), md5 = md5f(file.path(DD, "make_engines.R"))),
            source_engine = list(path = "04_Research/strategies/RP_AUTO_2002_06975/engine.R",
                                 md5 = md5f(file.path(ROOT, "04_Research/strategies/RP_AUTO_2002_06975/engine.R"))),
            diff_checker = list(path = file.path(REL, "template_diff_check.R"), md5 = md5f(file.path(DD, "template_diff_check.R"))),
            rule_line_template = TEMPLATE_LINE, rule_line_no = k,
            engines = eng,
            rx0s = list(path = file.path(REL, RX0S_REL), md5 = md5f(rxp), seed_base = RX0S_SEED_BASE, source_seed_base = 20020697L,
                        work_dir = file.path(REL, "rx0s", "_work"), code_version = "RP_AUTO_2002_06975/dnn_rolling/rev3",
                        changes = lapply(RX0S_SUBST, function(s) list(line = s$line, what = s$what, old = s$old, new = s$new)),
                        purpose = "P2R05 seed band (judgment Superfan T1 C-20261018-054): mean-target rev3 model reseeded; all 261 months retrain (seed is in the cache key spec)"))
mp <- file.path(DD, "engines_manifest.json")
writeLines(toJSON(man, auto_unbox = TRUE, pretty = TRUE, null = "null"), paste0(mp, ".tmp"), useBytes = TRUE)
if (!file.rename(paste0(mp, ".tmp"), mp)) stop("[make_engines] 매니페스트 교체 실패")
cat(sprintf("[make_engines] 매니페스트 %s · 템플릿 md5 %s · 원본 engine.R md5 %s · CODE_VERSION %s\n", mp, man$template$md5, man$source_engine$md5, code_version))

## 생성 직후 차분 대조(같은 함수 — precheck 와 같다)
res <- dt_template_diff_check(ROOT)
if (!isTRUE(res$ok)) { cat("[make_engines] 차분 대조 실패:\n", paste0("  · ", res$errors, collapse = "\n"), "\n", sep = ""); quit(status = 1L) }
cat(sprintf("[make_engines] 차분 대조 통과 — 구역 %d개 · 엔진 %d개 = 템플릿 + 규칙 줄 1줄 · RX0S = 원본 + %d줄\n", as.integer(res$n_zones), length(res$engines),
            as.integer(res$rx0s$n_diff_lines)))
