## P1R02 측정 — 정본 계약 run_paper_replication + 롱 레그 래퍼(long_leg_engine.R) · 결과 경로를 results/measure.json 에
##   R2: 등록부의 prereg_md5 = 지금 사전등록 정본 md5 · 래퍼 md5 = 사전등록 기록값이어야 측정한다.
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; Sys.setenv(QM_ROOT = ROOT)
suppressPackageStartupMessages({ library(jsonlite); library(data.table) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
RD <- file.path(ROOT, "04_Research/programs/P1_RETURN/P1R02_1801_long_leg")
SAP <- file.path(ROOT, "stage_artifacts/programs/P1_RETURN/P1R02_1801_long_leg/prereg.json")
reg <- fromJSON(file.path(ROOT, "06_Registry/research_programs.json"), simplifyVector = FALSE)
rr <- NULL
for (p in reg$programs) if (identical(p$id, "P1_RETURN")) for (r in p$rounds) if (identical(r$round_id, "P1R02_1801_long_leg")) rr <- r
if (is.null(rr)) stop("[P1R02] 등록부에 라운드 없음 — 측정하지 않는다(R2)")
if (!identical(rr$prereg_md5, unname(tools::md5sum(SAP)))) stop("[P1R02] 사전등록 md5 ≠ 등록부")
pre <- fromJSON(SAP, simplifyVector = FALSE)
if (!identical(pre$wrapper_md5, unname(tools::md5sum(file.path(RD, "long_leg_engine.R"))))) stop("[P1R02] 래퍼 md5 ≠ 사전등록")
Sys.setenv(QVEST_NO_LEDGER_OPEN = "1", QVEST_RP_REGISTER = "0")
setwd(file.path(ROOT, "02_Infrastructure"))
suppressMessages(source(file.path(ROOT, "02_Infrastructure/alpha_search/run_paper_replication.R")))
t0 <- Sys.time()
res <- run_paper_replication(strategy_name = "P1R02_1801_LONG_LEG",
                             strategy_idea = "[P1R02] 1801.01777 충실구현 재검증판의 롱 레그만(상위 분위 동일가중 · Σw = 1)",
                             factor_engine_path = file.path(RD, "long_leg_engine.R"),
                             source_paper = list(url = "https://arxiv.org/abs/1801.01777",
                                                 title = "Deep Learning for Forecasting Stock Returns in the Cross-Section", paper_key = "1801.01777"),
                             commission_paper = 0, send_telegram = FALSE, portfolio_spec = list(construction = "engine_direct"))
od <- gsub("\\\\", "/", res$out_dir %||% dirname(res$authoritative_remeasure_path))
## 분해 진단은 Judge 대상이 아니다 — A 라우팅 트리거가 생겼으면 보류로 돌린다(사전등록 measurement 문장)
jr <- file.path(od, "judge_request.eligible.json")
if (file.exists(jr)) {
  j <- fromJSON(jr, simplifyVector = FALSE); j$status <- "held:p1r02_diagnostic"
  j$held_after_publish <- list(code = "p1r02_diagnostic", at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), by = "P1R02 measure.R")
  writeLines(toJSON(j, auto_unbox = TRUE, pretty = TRUE, null = "null"), file.path(od, "judge_request.held.json")); file.remove(jr)
}
dir.create(file.path(RD, "results"), showWarnings = FALSE)
writeLines(toJSON(list(out_dir = od, grade = res$grade, strategy_id = res$strategy_id, measured_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
                       minutes = round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 1)), auto_unbox = TRUE, pretty = TRUE),
           file.path(RD, "results/measure.json"))
cat("[P1R02] 측정 완료:", od, "· 등급", res$grade, "\n")
