## round_core v1 · 단일 진입 — source("04_Research/programs/_lib/round_core/v1/load.R")
##   이 판(v1)의 모듈을 정해진 순서로 적재한다. 출시된 판의 파일은 수정하지 않는다(RELEASES.json 매니페스트 · 검사가 막는다) —
##   바꿀 일이 생기면 새 판(v2)을 만든다. 라운드는 사전등록에 판 이름과 매니페스트 md5 를 핀으로 건다(R2).
RC_MODULES <- c("util.R", "rules.R", "metrics.R", "spec.R", "p1.R", "pins.R", "cell_eval.R", "register.R", "driver.R")
RC_MODULES <- c(RC_MODULES, "standing.R")   # WP5 P1 상설 자격(상설 판 · 판정 원장 · 레인 스캔)
RC_MODULES <- c(RC_MODULES, "outcomes.R")   # v10.2 결과 원장(닫는 단계 기계화 — 다음 탐침 · 교훈 · 목표 축 판독)
RC_MODULES <- c(RC_MODULES, "p4.R")         # v10.2 P4 강화 사슬(p4_chain — 기저 풀 · 격차 · 사슬 판 · 걸음 원장 · 설계 입력 · 닫기 · 생성기 판)
RC_MODULES <- c(RC_MODULES, "freshness.R")  # 11-10 측정 경로 데이터 신선도 차단(아침 신선도 감사기 규칙 재사용 · 측정 경로 넷의 단일 판정)
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
  sys.source(file.path(root, "02_Infrastructure/ops/qv_bash.R"), envir = globalenv())   # bare "bash" 금지(금칙 ⑦ · 11-07) — WSL 있는 PC 에선 System32 bash 가 PATH 보다 먼저 잡힌다 · rc_fingerprint · rc_standing_fingerprint
  for (m in c(RC_MODULES, "pair.R", "p2.R", "p3.R", "rules_p2.R")) sys.source(file.path(here, m), envir = globalenv())   # 짝 판정 P2 · P3(WP1-b)
  assign("RC_DIR", here, envir = globalenv())
})
