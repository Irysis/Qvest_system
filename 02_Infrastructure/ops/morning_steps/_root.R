# _root.R — morning_steps 공통 헤더: 프로젝트 루트로 setwd + config source.
# 외부 .R 파일화 이유: 인라인 Rscript -e 의 한글/이모지 리터럴이 bash→Windows-R 코드페이지
# 변환에서 깨져 "Execution halted"/SIGSEGV. 파일은 UTF-8 정상 read (2026-06-13).
#
# [분리 보호 2026-06-17 도훈] 상속된 QM_ROOT가 별개 시스템(Qvest_Codex 등 sibling)을 가리키면
#   이 원본 트리의 morning_steps가 잘못된 .env/캐시/차트 경로로 해석된다(원본 차트 미갱신·발송 채널 오염).
#   원칙: "현 스크립트 위치가 곧 이 시스템의 루트"가 QM_ROOT보다 우선. QM_ROOT는 그 위치를 가리킬 때만 신뢰.
local({
  # 현 작업 디렉토리에서 이 프로젝트 루트 역추론 (caller가 BASE에서 호출하는 표준 가정).
  cwd <- getwd()
  has_marker <- function(p) nzchar(p) && dir.exists(p) &&
    file.exists(file.path(p, "02_Infrastructure", "config.R"))
  qm <- Sys.getenv("QM_ROOT", "")
  root <- if (has_marker(cwd)) cwd else if (has_marker(qm)) qm else cwd
  # QM_ROOT가 현 루트와 불일치하면(상속 오염) 강제 동기화 — config.R / .tg_load_env() 정합.
  if (!identical(normalizePath(qm, mustWork = FALSE), normalizePath(root, mustWork = FALSE))) {
    Sys.setenv(QM_ROOT = root, CLAUDE_PROJECT_DIR = root)
  }
  setwd(root)
})
source("02_Infrastructure/config.R")
