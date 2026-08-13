#!/usr/bin/env Rscript
# test_new_adapter_scaffold.R — 어댑터 골격 생성기 계약 (2026-08-13 신설)
#
# 왜: 등재 병목이 "논문이 안 맞는다"가 아니라 **등재 노동량**임이 실측됐다(표본 12편,
#   도달 가능 10/12). 그래서 기계적 부분(진입점 이름·NULL 처리·헤더 규약·등재 stub)을
#   `new_adapter()` 가 깔아준다. 하필 그 둘이 **오늘 내가 두 번 틀린 곳**이다.
#
# ★이 검사의 본체는 T4 다: **골격은 등재를 통과하면 안 된다.**
#   생성기가 통과 가능한 골격을 내면 그건 노동 절감이 아니라 **날조 보조 도구**가 된다.
#   빈 골격이 거부되어야만 "사람이 원문을 읽어야 통과한다"가 성립한다.
set.seed(20260813)
.root <- (function() {
  for (c in c(Sys.getenv("QM_ROOT"), Sys.getenv("CLAUDE_PROJECT_DIR"), getwd()))
    if (nzchar(c) && dir.exists(file.path(c, "06_Registry"))) return(c)
  getwd()
})()
setwd(.root)
suppressWarnings(suppressMessages({
  source("02_Infrastructure/methods/new_adapter.R")
  source("02_Infrastructure/methods/register_method.R")
}))

PASS <- 0; FAIL <- 0
chk <- function(n, ok, d = "") { if (isTRUE(ok)) { PASS <<- PASS + 1; cat(sprintf("  ok   %s %s\n", n, d)) }
                                 else { FAIL <<- FAIL + 1; cat(sprintf("  FAIL %s %s\n", n, d)) } }
tmp <- file.path(tempdir(), "scaf"); dir.create(tmp, showWarnings = FALSE)
cat("== 어댑터 골격 생성기 계약 ==\n")

EP <- c(weight = "method_weights", sigma = "sigma_estimate", exposure = "exposure_schedule")
for (k in names(EP)) {
  f <- file.path(tmp, paste0("p_", k, ".R"))
  r <- suppressMessages(new_adapter(paste0("Probe", k), kind = k, paper_id = "arxiv:9999.99999", file = f))
  chk(sprintf("T1[%s] 골격이 R 로 파싱된다", k),
      tryCatch({ invisible(parse(f)); TRUE }, error = function(e) FALSE))
  e <- new.env(parent = globalenv()); tryCatch(sys.source(f, envir = e), error = function(z) NULL)
  # ★진입점 이름은 kind 가 정한다 — 어긋나면 loader 가 영원히 안 싣는다(오늘 실제로 겪은 함정)
  chk(sprintf("T2[%s] 진입점이 kind 규약과 일치(%s)", k, EP[[k]]),
      exists(EP[[k]], envir = e, inherits = FALSE) && identical(r$entrypoint, unname(EP[[k]])))
  chk(sprintf("T3[%s] 등재 stub 이 함께 나온다", k), nzchar(r$register_stub %||% ""))
  # ★T4 본체 — 빈 골격은 **거부**되어야 한다
  v <- suppressWarnings(verify_adapter(f, k, paste0("Probe", k)))
  chk(sprintf("T4[%s] ★빈 골격은 등재 거부(날조 보조 아님)", k), !isTRUE(v$ok),
      if (!isTRUE(v$ok)) sprintf("(%s)", substr(v$reason, 1, 30)) else "★통과됨 — 생성기가 날조를 돕는다")
}
# T5 잘못된 kind 는 생성 자체가 거부된다
chk("T5 미지원 kind 는 생성 거부",
    tryCatch({ new_adapter("X", kind = "bogus", paper_id = "a", file = file.path(tmp, "x.R")); FALSE },
             error = function(e) grepl("weight", conditionMessage(e))))
# T6 덮어쓰기 보호 — 기존 어댑터를 실수로 지우지 않는다
f1 <- file.path(tmp, "p_weight.R")
chk("T6 기존 파일 덮어쓰기는 overwrite 없이는 거부",
    tryCatch({ new_adapter("Probeweight", kind = "weight", paper_id = "a", file = f1); FALSE },
             error = function(e) grepl("이미 존재", conditionMessage(e))))

TOTAL <- PASS + FAIL
cat(sprintf("  ── %d/%d pass\n", PASS, TOTAL))
cat(sprintf('{"test":"new_adapter_scaffold","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, TOTAL))
quit(status = if (FAIL == 0) 0 else 1)
