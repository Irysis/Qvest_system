# D1 (2026-07-25): incremental_update_all() 러너 — OHLCVS/Consensus/Investor 증분 파싱.
# Universe_Support는 내부적으로 cache-hit no-op (append는 d1_us_append_20260725.R 별도 수행).
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source(file.path(ROOT, "02_Infrastructure", "config.R"))
source(file.path(ROOT, "02_Infrastructure", "data", "incremental_update_file.R"))
res <- incremental_update_all()
str(res, max.level = 1)
