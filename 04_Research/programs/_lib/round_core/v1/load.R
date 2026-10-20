## round_core v1 · 단일 진입 — source("04_Research/programs/_lib/round_core/v1/load.R")
##   이 판(v1)의 모듈을 정해진 순서로 적재한다. 출시된 판의 파일은 수정하지 않는다(RELEASES.json 매니페스트 · 검사가 막는다) —
##   바꿀 일이 생기면 새 판(v2)을 만든다. 라운드는 사전등록에 판 이름과 매니페스트 md5 를 핀으로 건다(R2).
RC_MODULES <- c("util.R", "rules.R", "metrics.R", "spec.R", "p1.R", "pins.R", "cell_eval.R", "register.R", "driver.R")
RC_MODULES <- c(RC_MODULES, "standing.R")   # WP5 P1 상설 자격(상설 판 · 판정 원장 · 레인 스캔)
local({
  of <- NULL
  for (i in rev(seq_len(sys.nframe()))) { f <- sys.frame(i); if (!is.null(f$ofile)) { of <- f$ofile; break } }
  ## 경로 정규화는 구분자 치환 + 작업 디렉터리 접두로만(한글 경로를 깨는 경로 정규화 함수 금지 — python-policy)
  here <- if (!is.null(of)) { p <- gsub("\\\\", "/", of); if (!grepl("^([A-Za-z]:|/)", p)) p <- file.path(gsub("\\\\", "/", getwd()), p); dirname(p) } else
    file.path(Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"), "04_Research/programs/_lib/round_core/v1")
  if (!file.exists(file.path(here, "util.R"))) stop("[round_core] v1 모듈 위치를 찾지 못했다: ", here)
  root <- dirname(dirname(dirname(dirname(dirname(here)))))
  if (!exists("pr_record_round", mode = "function"))
    invisible(capture.output(suppressMessages(sys.source(file.path(root, "02_Infrastructure/programs/program_registry.R"), envir = globalenv()))))
  for (m in RC_MODULES) sys.source(file.path(here, m), envir = globalenv())
  assign("RC_DIR", here, envir = globalenv())
})
