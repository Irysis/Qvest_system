#==============================================================================
# build_l2v0_inputs.R — 2계층 역할 슬리브 로테이션 v0 (PR-L2-ROLESLEEVE-V0) 입력 동결
#
# 하는 일(성과 미열람 — 수익률 계열을 읽지 않는다):
#   ① 후보 대응표: module_performance.json 65 close_t1 모듈 ∩ asof_roles 구성원 81 → work/l2v0_candidates.csv
#   ② 모듈 보유 패널: 각 모듈 04_holdings.csv(date = 집행일 · target_weight) → work/l2v0_module_holdings.parquet
#   ③ 입력 지문: 설계·라벨·예측기·풀·패널의 sha256 → work/l2v0_inputs_manifest.json (사전등록이 이 파일을 고정)
# 실행: 이 디렉터리에서 Rscript --no-save -e 'source("build_l2v0_inputs.R")'
# 쓰기 범위: 04_Research/l2_role_rotation/work/ 만. 덮어쓰기 거부(재실행 = 파일을 먼저 치울 것 — 사전등록 뒤에는 금지).
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite); library(arrow) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

.find_root <- function() {
  for (p in c(Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""), getwd(), dirname(getwd()), dirname(dirname(getwd())))) {
    if (nzchar(p) && file.exists(file.path(p, "02_Infrastructure/config.R"))) return(normalizePath(p, winslash = "/"))
  }
  stop("[l2v0_inputs] 프로젝트 루트 미발견")
}
ROOT <- .find_root()
L2DIR <- file.path(ROOT, "04_Research/l2_role_rotation")
WORK <- file.path(L2DIR, "work")
sha256_file <- function(p) digest::digest(file = p, algo = "sha256")
out_cand <- file.path(WORK, "l2v0_candidates.csv")
out_pan  <- file.path(WORK, "l2v0_module_holdings.parquet")
out_man  <- file.path(WORK, "l2v0_inputs_manifest.json")
for (p in c(out_cand, out_pan, out_man)) if (file.exists(p)) stop(sprintf("[l2v0_inputs] 덮어쓰기 거부: %s", p))

design <- fromJSON(file.path(L2DIR, "l2v0_design.json"), simplifyVector = FALSE)

# ── ① 후보 대응표 ─────────────────────────────────────────────────────────────
mp <- fromJSON(file.path(ROOT, design$candidates$module_performance), simplifyVector = FALSE)
md <- rbindlist(lapply(names(mp$modules), function(k) {
  m <- mp$modules[[k]]
  data.table(module_key = k, series_dir = as.character(m$series_dir %||% NA_character_),
             series_source = as.character(m$series_source %||% NA_character_),
             series_exec_price = as.character(m$series_exec_price %||% NA_character_),
             essence_grade_registry = as.character(m$grade %||% NA_character_))
}))
mm <- fread(file.path(ROOT, design$candidates$member_meta))
bs <- "\\"
.norm <- function(x) tolower(gsub(bs, "/", x, fixed = TRUE))
md[, key := .norm(series_dir)]
.root_lc <- paste0(tolower(ROOT), "/")
mm[, key := .norm(series)]
mm[startsWith(key, .root_lc), key := substring(key, nchar(.root_lc) + 1L)]
mm[, key := sub("/(03_period_returns[.]csv|sim_result[.]rds)$", "", key)]
cand <- merge(md, mm[, .(key, member_id, kind, exec)], by = "key")
if (nrow(cand) != as.integer(design$candidates$expected_n))
  stop(sprintf("[l2v0_inputs] 후보 수 %d ≠ 설계 %s", nrow(cand), design$candidates$expected_n))
if (anyDuplicated(cand$module_key) || anyDuplicated(cand$member_id)) stop("[l2v0_inputs] 대응 중복")
if (any(cand$series_exec_price != "close_t1")) stop("[l2v0_inputs] close_t1 아닌 계열이 섞였다")
cand[, holdings_path := file.path(series_dir, "04_holdings.csv")]
cand[, holdings_sha256 := vapply(file.path(ROOT, holdings_path), sha256_file, character(1))]
setorder(cand, module_key)
fwrite(cand[, .(module_key, member_id, kind, series_source, series_exec_price, essence_grade_registry, series_dir, holdings_path, holdings_sha256)], out_cand)
cat(sprintf("[l2v0_inputs] 후보 %d 기록: %s\n", nrow(cand), out_cand))

# ── ② 모듈 보유 패널(집행일 · target_weight) ──────────────────────────────────
pan <- rbindlist(lapply(seq_len(nrow(cand)), function(i) {
  h <- fread(file.path(ROOT, cand$holdings_path[i]), select = c("date", "ticker", "target_weight"))
  h[, `:=`(module_key = cand$module_key[i], member_id = cand$member_id[i], exec_date = as.Date(date))]
  h[is.finite(target_weight) & target_weight != 0, .(module_key, member_id, exec_date, ticker, weight = as.numeric(target_weight))]
}))
setorder(pan, module_key, exec_date, ticker)
if (anyDuplicated(pan, by = c("module_key", "exec_date", "ticker"))) stop("[l2v0_inputs] 패널 중복 행")
arrow::write_parquet(pan, out_pan)
snap <- pan[, .(n = .N, s_pos = sum(weight[weight > 0]), s_neg = sum(weight[weight < 0])), by = .(module_key, exec_date)]
cat(sprintf("[l2v0_inputs] 보유 패널 %d 행 · 모듈 %d · 스냅샷 %d · 롱숏 모듈 %d\n", nrow(pan), uniqueN(pan$module_key),
            nrow(snap), uniqueN(snap[s_neg < 0]$module_key)))

# ── ③ 입력 지문 ───────────────────────────────────────────────────────────────
rel <- function(p) sub(paste0("^", ROOT, "/"), "", normalizePath(p, winslash = "/"))
fp <- function(p) list(path = rel(p), sha256 = sha256_file(p), bytes = file.info(p)$size,
                      mtime = format(file.info(p)$mtime, "%Y-%m-%dT%H:%M:%S%z"))
man <- list(
  schema = "l2v0_inputs_manifest_v1", prereg_id = design$prereg_id, built_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  note = "성과(수익률) 미열람 — 보유 비중·라벨·예측기·풀 정의만 읽었다. 사전등록이 이 파일의 sha256 을 고정한다.",
  files = list(
    design = fp(file.path(L2DIR, "l2v0_design.json")),
    asof_roles = fp(file.path(ROOT, design$labels$file)),
    msm_asof_daily = fp(file.path(ROOT, design$predictor$file)),
    module_performance = fp(file.path(ROOT, design$candidates$module_performance)),
    member_meta = fp(file.path(ROOT, design$candidates$member_meta)),
    candidates = fp(out_cand),
    holdings_panel = fp(out_pan),
    reinforce_program_fixed_axes = fp(file.path(ROOT, "06_Registry/reinforce_program.json")),
    constraint_defaults = fp(file.path(ROOT, "02_Infrastructure/worktask/constraint_defaults.json")),
    predictor_selection_IS = fp(file.path(L2DIR, "predictor_selection_IS.json")),
    predictor_oos_diagnostic = fp(file.path(L2DIR, "predictor_oos_diagnostic.json")),
    pit_audit = fp(file.path(L2DIR, "pit_audit.json"))),
  holdings_panel_summary = list(rows = nrow(pan), modules = uniqueN(pan$module_key), snapshots = nrow(snap),
                                long_short_modules = as.list(sort(unique(snap[s_neg < 0]$module_key))),
                                last_exec_by_module_min = format(min(snap[, max(exec_date), by = module_key]$V1)),
                                last_exec_by_module_max = format(max(snap[, max(exec_date), by = module_key]$V1)))
)
writeLines(toJSON(man, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null"), out_man, useBytes = TRUE)
cat(sprintf("[l2v0_inputs] 지문 기록: %s (sha256 %s)\n", out_man, substr(sha256_file(out_man), 1, 12)))
