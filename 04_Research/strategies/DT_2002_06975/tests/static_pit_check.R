## =============================================================================
## static_pit_check.R — 생성 엔진 7개 정적 PIT 검사(설계 §7.3 사전 점검 ① · C7) — 02_Infrastructure/validation/lookahead_detector.R 그대로 사용
##   검사기는 고치지 않는다. 위반이 나오면 그 줄(번호 · 코드 · 규칙)을 그대로 보고하고 종료 코드 1.
##   참고로 원본 engine.R 과 템플릿도 같은 검사기에 넣어 기준선을 함께 적는다(판정 대상 = 생성 7개).
## 실행: Rscript tests/static_pit_check.R      산출 = tests/_out/static_pit_results.json
## =============================================================================
suppressPackageStartupMessages(library(jsonlite))
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
for (p in c(Sys.getenv("QM_ROOT", ""), Sys.getenv("CLAUDE_PROJECT_DIR", ""))) if (nzchar(p) && file.exists(file.path(p, "02_Infrastructure/hooks/qvest_hook_router.py"))) { ROOT <- gsub("\\\\", "/", p); break }
DT_DIR <- file.path(ROOT, "04_Research/strategies/DT_2002_06975")
RULES <- c("Q50", "V1", "V2", "N1", "N2", "S1", "S2")
invisible(capture.output(suppressMessages(source(file.path(ROOT, "02_Infrastructure/validation/lookahead_detector.R")))))
scan1 <- function(p, role) {
  r <- detect_lookahead(p, verbose = FALSE)
  v <- lapply(r$violations, function(z) list(check = z$check, line = z$line, code = substr(z$code, 1L, 200L), msg = z$msg))
  cat(sprintf("[static-pit] %-10s %-20s clean=%s scanned=%s 위반 %d · md5 %s\n", role, basename(p), as.character(r$clean), as.character(r$scanned),
              as.integer(r$n_violations), unname(tools::md5sum(p))))
  for (z in v) cat(sprintf("    %s %d행: %s — %s\n", z$check, as.integer(z$line), z$code, z$msg))
  list(file = basename(p), role = role, md5 = unname(as.character(tools::md5sum(p))), clean = r$clean, scanned = r$scanned,
       n_violations = as.integer(r$n_violations), violations = v)
}
res <- c(list(scan1(file.path(ROOT, "04_Research/strategies/RP_AUTO_2002_06975/engine.R"), "기준선"),
              scan1(file.path(DT_DIR, "engine_template.R"), "템플릿")),
         lapply(RULES, function(r) scan1(file.path(DT_DIR, sprintf("engine_%s.R", r)), "판정")),
         list(scan1(file.path(DT_DIR, "rx0s", "engine_RX0S.R"), "판정")))                 # RX0S(원본 재시드 사본)도 판정 대상
## 내장 파이썬(.PY_SRC) — .R 검사에서는 R 패턴만 걸리므로 .py 로 꺼내 파이썬 패턴(PY_*)으로도 본다(7 엔진의 .PY_SRC 는 같다 — template_diff_check)
SO <- file.path(DT_DIR, "tests", "_out", "static_pit"); unlink(SO, recursive = TRUE); dir.create(SO, recursive = TRUE, showWarnings = FALSE)
EL <- readLines(file.path(DT_DIR, "engine_Q50.R"), encoding = "UTF-8", warn = FALSE)
a <- which(EL == '.PY_SRC <- r"---('); b <- which(EL == ')---"')
if (length(a) != 1L || length(b) != 1L || b <= a) stop("[static-pit] .PY_SRC 구간을 찾지 못함")
py_path <- file.path(SO, "dnn_rolling_dt.py")
writeLines(EL[(a + 1L):(b - 1L)], py_path, useBytes = TRUE)
res <- c(res, list(scan1(py_path, "판정(py)")))
## 검사기 양성 대조 — 같은 파일 형태에 위반 1줄 주입 → 검사기가 그 줄을 잡아야 한다(발화 실증 · 검사기는 바꾸지 않는다)
inj <- function(src_lines, after_pat, line, out) {
  k <- grep(after_pat, src_lines)[1]; if (is.na(k)) stop("주입 위치 없음: ", after_pat)
  writeLines(c(src_lines[seq_len(k)], line, src_lines[-seq_len(k)]), out, useBytes = TRUE); k + 1L
}
k_r <- inj(EL, "^\\.DT_PTS <- sort", ".dt_bad_vol <- sd(lr_all) * sqrt(252)", file.path(SO, "engine_Q50_injected.R"))
k_p <- inj(EL[(a + 1L):(b - 1L)], "^def rearrange", "    raw = pd.DataFrame(raw).shift(-1).to_numpy()", file.path(SO, "dnn_rolling_dt_injected.py"))
pc_r <- detect_lookahead(file.path(SO, "engine_Q50_injected.R"), verbose = FALSE)
pc_p <- detect_lookahead(file.path(SO, "dnn_rolling_dt_injected.py"), verbose = FALSE)
fired_r <- any(vapply(pc_r$violations, function(z) identical(as.integer(z$line), k_r) && identical(z$check, "C1"), logical(1)))
fired_p <- any(vapply(pc_p$violations, function(z) identical(as.integer(z$line), k_p) && identical(z$check, "PY_C7_NEG_SHIFT"), logical(1)))
cat(sprintf("[static-pit] 검사기 양성 대조 — R 주입(%d행 sd()*sqrt) %s · py 주입(%d행 shift(-1)) %s\n", k_r, if (fired_r) "발화" else "미발화",
            k_p, if (fired_p) "발화" else "미발화"))
judged <- Filter(function(z) startsWith(z$role, "판정"), res)
ok <- length(judged) == length(RULES) + 2L && all(vapply(judged, function(z) isTRUE(z$clean) && isTRUE(z$scanned), logical(1))) && fired_r && fired_p
dir.create(file.path(DT_DIR, "tests", "_out"), recursive = TRUE, showWarnings = FALSE)
writeLines(toJSON(list(ok = ok, detector = "02_Infrastructure/validation/lookahead_detector.R",
                       detector_md5 = unname(as.character(tools::md5sum(file.path(ROOT, "02_Infrastructure/validation/lookahead_detector.R")))),
                       files = res, positive_control = list(r_injected_line = k_r, r_fired = fired_r, py_injected_line = k_p, py_fired = fired_p),
                       at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S")), auto_unbox = TRUE, pretty = TRUE, null = "null"),
           file.path(DT_DIR, "tests", "_out", "static_pit_results.json"))
cat(sprintf("[static-pit] %s — 판정 파일 %d개(엔진 7 + RX0S 1 + 내장 파이썬 1) 중 clean %d · 검사기 양성 대조 %s\n", if (ok) "OK" else "FAIL", length(judged),
            sum(vapply(judged, function(z) isTRUE(z$clean), logical(1))), if (fired_r && fired_p) "2/2 발화" else "미발화 있음"))
quit(status = if (ok) 0L else 1L)
