# ============================================================================
# repair_rawdata_bmret_from_benchmark.R — ★W-09(2026-09-23): 단일 writer 위임 shim
#   RAWDATA.parquet::BM_Ret 을 정본 benchmark.parquet::BM_Ret 으로 정정
# ----------------------------------------------------------------------------
# 신설 2026-08-02 (Q-Lead 야간 라운드). 구판은 이 파일 안에 자체 정정 로직(대상 산출 ·
#   정합 감시기 방향 게이트 · 국소 set · write)을 들고 있었다 — BM_Ret writer 가 5곳에 흩어진
#   병의 한 갈래였다. 2026-09-23 W-09 에서 정의·보호·킬스위치·원자 쓰기·사후검증을
#   02_Infrastructure/data/rawdata_bm_ret_sync.R 하나로 모으고, 이 스크립트는 CLI 호환만 남긴다.
#
# ## 구판 방향 게이트는 어디로 갔나
#   구판은 benchmark_source_parity.R 의 날짜별 판정으로 "RAWDATA 가 오염 측인 날짜" 만 고쳤다.
#   2026-09-18 벤치를 정본 xlsx(IKS200) 축으로 재구축한 뒤 방향은 선언으로 고정됐다
#   (benchmark_axis.json · 벤치 = 정본). 벤치 쪽 오염은 벤치 게이트(benchmark_currency_gate.R
#   축 A~D)가 잡고, 이 경로의 잔여 위험(벤치 축 이동)은 단일 writer 의 덮어쓰기 상한
#   (max_overwrite_per_run)이 막는다 — 한 번에 많은 날이 갈리면 전부 거부한다.
#   판단이 보류된 계열(1990~98 토요장 · 2024-12-30)은 설정 protect 가 막는다.
#
# ## 사용 (프로젝트 루트에서)
#   Rscript 02_Infrastructure/data/repair_rawdata_bmret_from_benchmark.R            # dry-run
#   Rscript 02_Infrastructure/data/repair_rawdata_bmret_from_benchmark.R --apply    # 실제 쓰기
#   덮어쓰기는 킬스위치(06_Registry/reinforce_auto_config.json::enabled=false)가 내려가 있어야 한다.
# ============================================================================
suppressWarnings(suppressMessages({library(arrow); library(data.table)}))

args  <- commandArgs(trailingOnly = TRUE)
APPLY <- any(args %in% c("--apply", "apply", "TRUE"))

.here <- local({
  m <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
  if (length(m)) dirname(gsub("\\\\", "/", sub("^--file=", "", m[1L]))) else "02_Infrastructure/data"
})
source(file.path(.here, "rawdata_bm_ret_sync.R"))

BACKUP <- sprintf(".cache/rawdata_pre_bmret_fix_%s.parquet", format(Sys.Date(), "%Y%m%d"))
res <- rawdata_sync_bm_ret(dry_run = !APPLY,
                           backup_path = if (APPLY && !file.exists(BACKUP)) BACKUP else NULL)
cat(bm_ret_status_line(res), "\n")
if (!APPLY) cat("[repair] DRY-RUN — 실제 적용은 --apply 로 재실행하세요.\n")
quit(save = "no", status = res$rc)
