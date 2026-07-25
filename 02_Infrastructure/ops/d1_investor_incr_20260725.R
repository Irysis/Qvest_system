# D1 부산물 (2026-07-25): Investor_Act_update.xlsx (QW 리프레시 11:17 완료분)
#  → investor_all + per-type 분리 4종 + wide 파생 재생성 (수급 ~22일 지연 일회 해소).
# 사전 pin: .cache/pins/d1_universe_20260725/investor_all_pre_d1.parquet (08:38).
# incremental_investor()는 겹침 날짜 교체 merge라 idempotent (incremental_update_file.R L269~).
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source(file.path(ROOT, "02_Infrastructure", "config.R"))
source(file.path(ROOT, "02_Infrastructure", "data", "incremental_update_file.R"))
incremental_investor()
