# tg_send.R — Piotroski (2000) 충실구현 보고 1통 실제 발송(build_report.R 가 dry-run 으로 만든 것과 같은 인자 · tg_args.rds)
#   실행: "C:/Program Files/R/R-4.6.2/bin/Rscript.exe" <이 파일>   (프로젝트 루트에서)
ROOT <- "G:/OneDrive/Quant_Module_Moltbot"; setwd(ROOT); Sys.setenv(QM_ROOT = ROOT, CLAUDE_PROJECT_DIR = ROOT, QVEST_TG_DRY_RUN = "0")
suppressMessages({ source(file.path(ROOT, "02_Infrastructure/telegram/telegram_notify.R")); source(file.path(ROOT, "02_Infrastructure/programs/program_report.R")) })
ARGS <- readRDS("G:/OneDrive/Quant_Module_Moltbot/stage_artifacts/replication/20261109_102936_33072/tg_args.rds")
ARGS$dry_run <- FALSE
print(do.call(prep_send, ARGS))
