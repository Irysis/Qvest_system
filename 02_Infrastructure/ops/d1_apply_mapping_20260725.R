# D1 (2026-07-25): apply_universe_mapping() 러너 — us_* 신규 스냅샷(2026-04~07)을
# RAWDATA에 roll=Inf LOCF 재투영 (temp-rename 내장). 사전 pin: pins/d1_universe_20260725.
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source(file.path(ROOT, "02_Infrastructure", "config.R"))
source(file.path(ROOT, "02_Infrastructure", "data", "apply_universe_mapping.R"))
apply_universe_mapping()
