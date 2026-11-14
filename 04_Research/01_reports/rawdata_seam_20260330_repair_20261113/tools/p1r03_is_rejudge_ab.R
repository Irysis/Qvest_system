## P1R03 IS(보는 창 ≤ τ_D) 자격 판정 A/B — 같은 코드(round_core v3 · 현행 계약)로 D2 전 · 후 산출물을 칸 평가 → 판정 규칙 적용(쓰기 = 출력 폴더뿐)
##   왜: D2(수익률 단절 채움)는 2000~2022 의 Ret 도 바꿔 IS 일간 수익이 달라질 수 있다. 닫힌 라운드의 verdict.json(11-13)은 그대로 두고,
##       같은 코드로 전 · 후를 나란히 평가해 자격(t_alpha_vis ≥ 2 ∧ uc_vis ≥ 0.55)이 바뀌는지만 본다 — 차이는 자료에서만 온다.
##   규칙 = 원 판정 기록(results/verdict.json)의 해석된 규칙 그대로(문턱 · 출처) — 다시 해석하지 않는다.
##   사용(저장소 루트): Rscript <이 파일> <출력 폴더> <엔진,…> [전 결과 폴더(엔진별 우선순위는 아래)]
##     전 = remeasure_d1_20261114/results 에 있으면 그것 · 없으면 remeasure_seam_20261113/results · 후 = remeasure_d2_20261114/results
##   출력: <출력>/{pre,post}/results/<code>/eval.json · <출력>/is_rejudge_ab.csv · 화면 표
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
a <- commandArgs(trailingOnly = TRUE)
if (length(a) < 2L) stop("usage: p1r03_is_rejudge_ab.R <out_dir> <ENGINE,...>")
OUT <- gsub("\\\\", "/", a[1]); ENG <- strsplit(a[2], ",", fixed = TRUE)[[1]]
ROOT <- sub("/+$", "", gsub("\\\\", "/", Sys.getenv("QM_ROOT", getwd())))
if (!file.exists(file.path(ROOT, "CLAUDE.md"))) ROOT <- gsub("\\\\", "/", getwd())
setwd(ROOT)
RD <- "04_Research/programs/P1_RETURN/P1R03_factor_family_composites"
source(file.path(ROOT, "04_Research/programs/_lib/round_core/v3/load.R"))
spec <- rc_spec_load(file.path(RD, "round_spec.json"), root = ROOT)
V0 <- fromJSON(file.path(RD, "results/verdict.json"), simplifyVector = FALSE)
rules <- V0$rules                                                           # 원 판정의 해석된 규칙(value · value_source 포함)
tau <- as.Date(spec[["tau_d"]])
src_pre <- function(code) { for (d in c("remeasure_d1_20261114", "remeasure_seam_20261113")) { p <- file.path(RD, d, "results", paste0(code, ".json")); if (file.exists(p)) return(p) }; NA_character_ }
src_post <- function(code) { p <- file.path(RD, "remeasure_d2_20261114/results", paste0(code, ".json")); if (file.exists(p)) p else NA_character_ }
cells <- Filter(function(x) x[["engine"]] %in% ENG, spec[["cells"]])
if (length(cells) != length(ENG)) stop("엔진 이름이 사양에 없다: ", paste(setdiff(ENG, vapply(spec[["cells"]], `[[`, "", "engine")), collapse = ","))
env <- rc_eval_env(ROOT, spec[["behavior_card_cfg"]])                       # 사전등록 때 고정한 행동 카드 설정(R2)
tabs <- list()
for (side in c("pre", "post")) {
  rdir <- file.path(OUT, side); dir.create(file.path(rdir, "results"), recursive = TRUE, showWarnings = FALSE)
  for (cl in cells) {                                                        # ★루프 변수 = cl — 전역 'c' 는 base::c 를 가려 계약의 do.call(c, …) 이 깨진다(11-14 첫 실행 실패)
    s <- if (side == "pre") src_pre(cl[["code"]]) else src_post(cl[["code"]])
    if (is.na(s)) stop("측정 결과 없음: ", side, " ", cl[["code"]])
    file.copy(s, file.path(rdir, "results", basename(s)), overwrite = TRUE)
    t0 <- Sys.time(); ev <- rc_eval_cell(ROOT, rdir, cl, env, tau)
    cat(sprintf("[ab] %s %s %s · %.0fs\n", side, cl[["code"]], ev$status %||% "?", as.numeric(difftime(Sys.time(), t0, units = "secs"))))
  }
  sp2 <- spec; sp2$cells <- lapply(cells, function(x) { x$source_results <- file.path(rdir, "results"); x })
  TT <- rc_p1_table(sp2, ROOT)                                               # 이름 = TT — 전역 T 는 TRUE 별칭을 가린다
  TT <- rc_rules_apply(rules, TT, eligible = TT$status == "evaluated")
  TT[, side := side]
  tabs[[side]] <- TT
}
X <- rbindlist(tabs, fill = TRUE)
keep <- intersect(c("engine", "side", "status", "t_alpha_vis", "uc_vis", "beta_vis", "port_t_vis", "n_vis", "qualify"), names(X))
X <- X[, ..keep]
fwrite(X, file.path(OUT, "is_rejudge_ab.csv"))
W <- dcast(X, engine ~ side, value.var = intersect(c("t_alpha_vis", "uc_vis", "qualify"), names(X)))
orig <- rbindlist(lapply(V0$table, function(r) data.table(engine = r$engine, t_alpha_vis_1113 = as.numeric(r$t_alpha_vis %||% NA), uc_vis_1113 = as.numeric(r$uc_vis %||% NA),
                                                          qualify_1113 = isTRUE(r$qualify))), fill = TRUE)
W <- merge(W, orig, by = "engine", all.x = TRUE)
print(W)
cat(sprintf("[ab] 자격이 바뀐 엔진: %s\n", { ch <- W[get("qualify_pre") != get("qualify_post"), engine]; if (length(ch)) paste(ch, collapse = ", ") else "없음" }))
