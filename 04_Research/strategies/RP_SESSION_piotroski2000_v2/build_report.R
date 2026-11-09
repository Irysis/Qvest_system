# build_report.R — Piotroski (2000) 충실구현 보고 재료(무인 레인 검증기와 같은 함수) + 1통 dry-run · 실제 발송 스크립트 생성
#   재료: 역할 카드(strategy_role.R::sr_card_for_series) · 행동 카드(matched_controls.R::mc_card + mc_write) ·
#         팩터 분석(replication_factor_analysis.R <dir> → rfa_section) · 등급 근거(rf_perf_summary.R::rf_perf_kv) · 차트(rf_perf_charts)
#   보고: programs/program_report.R::prep_send(program = "충실구현", crisis = "chart", push = TRUE) — QVEST_TG_DRY_RUN=1(발송 안 함)
#   발송: 같은 인자를 <대표 산출 디렉터리>/tg_send.R 로 남긴다(Q 검토 뒤 실행)
ROOT <- "G:/OneDrive/Quant_Module_Moltbot"
setwd(ROOT)
Sys.setenv(QM_ROOT = ROOT, CLAUDE_PROJECT_DIR = ROOT)
suppressMessages({ library(data.table); library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a
SDIR <- file.path(ROOT, "04_Research/strategies/RP_SESSION_piotroski2000_v2")
RS <- "C:/Program Files/R/R-4.6.2/bin/Rscript.exe"
RD <- fromJSON(file.path(SDIR, "run_dirs.json"), simplifyVector = FALSE)
FID <- fromJSON(file.path(SDIR, "FIDELITY.json"), simplifyVector = FALSE)
HEAD <- RD$hl$out_dir
TITLE <- "Value Investing: The Use of Historical Financial Statement Information to Separate Winners from Losers"

suppressMessages({
  source(file.path(ROOT, "02_Infrastructure/contracts/strategy_role.R"))
  source(file.path(ROOT, "02_Infrastructure/contracts/matched_controls.R"))
  source(file.path(ROOT, "02_Infrastructure/ops/rf_perf_summary.R"))
  source(file.path(ROOT, "02_Infrastructure/telegram/telegram_notify.R"))
  source(file.path(ROOT, "02_Infrastructure/programs/program_report.R"))
})
RVC <- tryCatch(fromJSON(file.path(ROOT, "06_Registry/rf_replication_variants.json"), simplifyVector = FALSE)$holdings_claims, error = function(e) list())

num <- function(x, d = 2L) { x <- suppressWarnings(as.numeric(x)[1]); if (!is.finite(x)) "NA" else sub("^-", "−", formatC(x, format = "f", digits = d)) }
pct <- function(x) { x <- suppressWarnings(as.numeric(x)[1]); if (is.finite(x)) sub("^-", "−", sprintf("%.1f%%", 100 * x)) else "NA" }

## 보유 대조(검증기 .v1001_holdings_check 와 같은 규칙 · 문턱 = rf_replication_variants.json::holdings_claims)
hold_check <- function(dir, claims, cfg = RVC) {
  h <- tryCatch(fread(file.path(dir, "04_holdings.csv"), select = c("date", "target_weight"), showProgress = FALSE), error = function(e) NULL)
  if (is.null(h) || !nrow(h)) return(list(status = "no_holdings"))
  h <- h[is.finite(target_weight) & target_weight != 0]
  s <- h[, .(n = .N, long = sum(pmax(target_weight, 0)), short = sum(pmax(-target_weight, 0)),
             nl = sum(target_weight > 0), ns = sum(target_weight < 0)), by = date]
  s[, `:=`(net = long - short, gross = long + short)]
  meas <- list(n_rebalance = nrow(s), n_names_median = stats::median(s$n), n_long_mean = mean(s$nl), n_short_mean = mean(s$ns),
               n_long_median = stats::median(s$nl), n_short_median = stats::median(s$ns), n_short_min = min(s$ns),
               short_share = mean(s$short > 0), net_median = stats::median(s$net), gross_median = stats::median(s$gross))
  n0 <- function(x) { x <- suppressWarnings(as.numeric(x %||% NA)[1]); if (is.finite(x)) x else NA_real_ }
  mis <- character(0)
  if (isTRUE(claims$long_short) && is.finite(n0(cfg$short_share_min)) && !(meas$short_share > n0(cfg$short_share_min)))
    mis <- c(mis, sprintf("롱숏 신고인데 숏 리밸일 비율 %.2f", meas$short_share))
  ne <- n0(claims$net_exposure); tol <- n0(cfg$net_abs_tol_of_gross)
  if (is.finite(ne) && is.finite(tol) && abs(meas$net_median - ne) > tol * max(meas$gross_median, 1e-12))
    mis <- c(mis, sprintf("순노출 신고 %g · 실측 중앙 %.2f", ne, meas$net_median))
  list(status = "ok", measured = meas, claims = claims, mismatch = length(mis) > 0L, findings = mis)
}

## 디렉터리별 재료
claims_of <- function(id) { for (v in FID$variants) if (identical(v$id, id)) return(v$claims); NULL }
label_of  <- function(id) { for (v in FID$variants) if (identical(v$id, id)) return(v$label); id }
rows <- list(); cards <- list()
for (id in c("hl", "ha", "rank")) {
  d <- RD[[id]]$out_dir %||% NA_character_
  if (is.na(d) || !dir.exists(d)) { rows[[id]] <- list(id = id, headline = identical(id, "hl"), status = "error", error = RD[[id]]$err %||% "no dir"); next }
  rc <- tryCatch(sr_card_for_series(file.path(d, "03_period_returns.csv"), ROOT), error = function(e) list(status = paste("error:", conditionMessage(e))))
  writeLines(toJSON(c(rc, list(declared_role = FID$declared_role, computed_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"))),
                    auto_unbox = TRUE, pretty = TRUE, digits = 6, na = "null", null = "null"), file.path(d, "role_card.json"))
  cd <- tryCatch({ z <- mc_card(d, root = ROOT); mc_write(z, d, root = ROOT); z }, error = function(e) { message("[report] mc_card 실패 ", id, ": ", conditionMessage(e)); NULL })
  cards[[id]] <- cd
  hc <- hold_check(d, claims_of(id))
  write(toJSON(hc, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = 6), file.path(d, "holdings_check.json"))
  a <- fromJSON(file.path(d, "authoritative_remeasure.json"), simplifyVector = TRUE); e <- a$essence %||% list()
  ov <- (cd %||% list())$overall %||% list()
  rows[[id]] <- list(id = id, label = label_of(id), headline = identical(id, "hl"), status = "ok",
                     grade = a$essence_grade %||% NA, run_id = a$run_id %||% NA, artifacts = d,
                     cagr = e$cagr %||% NA, calmar = e$calmar %||% NA, mdd = e$mdd %||% NA, port_t = e$portfolio_alpha_t_nw_lag3 %||% NA,
                     net_sharpe = e$net_sharpe %||% NA, dsr = e$dsr %||% NA,
                     paper_gross = a$replication$paper_basis %||% NULL,
                     selection_type = a$selection_type %||% NA, n_trials = a$n_trials_cumulative %||% NA,
                     effective_start = a$measurement_axis$effective_start %||% NULL,
                     crisis_verdict = ov$verdict %||% NA, crisis_dd_capture_median = ov$crisis_dd_capture_median %||% NA,
                     bull_up_capture_median = ov$bull_up_capture_median %||% NA,
                     beta = rc$beta %||% NA, alpha_t = rc$roles$alpha$t %||% NA, alpha_basis = rc$roles$alpha$basis %||% NA,
                     holdings = hc$measured, holdings_mismatch = isTRUE(hc$mismatch), holdings_findings = hc$findings,
                     judge_trigger = file.exists(file.path(d, "judge_request.eligible.json")),
                     judge_held = file.exists(file.path(d, "judge_request.held.json")))
}
SM <- list(schema = "replication_variants_v1", decision = "REPLICATION-ALL-METHODS-20261017", headline = "hl", n_variants = 3L,
           selection_note = "대표 = 논문이 꼽은 방법(High−Low · 측정 전 FIDELITY.headline_variant 고정 · chain/1 · 권위 등급) · 나머지 = sweep(n = 3 · DSR)",
           variants = unname(rows), measured_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"))
write(toJSON(SM, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = 6), file.path(HEAD, "variants_summary.json"))

## 팩터 분석(대표) — 러너가 점수형 FACTORS 로 이미 분석했으면 다시 돌지 않는다(rfa 규약)
system2(RS, c(shQuote(file.path(ROOT, "02_Infrastructure/alpha_search/replication_factor_analysis.R")), shQuote(HEAD)),
        stdout = file.path(HEAD, "analysis_rfa.log"), stderr = file.path(HEAD, "analysis_rfa.err.log"))
.rfa <- new.env(parent = globalenv()); sys.source(file.path(ROOT, "02_Infrastructure/alpha_search/replication_factor_analysis.R"), envir = .rfa)
FA_SEC <- tryCatch(.rfa$rfa_section(HEAD), error = function(e) NULL)

## 섹션들
H <- rows$hl
cv <- c(strong = "강함", normal = "보통", weak = "약함", insufficient = "판정 불가")
cvw <- function(x) { z <- unname(cv[as.character(x %||% "")]); if (length(z) && !is.na(z)) z else "NA" }
GRADE_KV <- c("다중검정 t값" = "PORT_t", "샤프지수" = "SR", "표본외 유지율" = "OOS 유지율", "감가샤프지수" = "DSR", "회전율" = "연 회전율", "유니버스" = "유니버스")
gkv <- tryCatch(rf_perf_kv(HEAD), error = function(e) list()); keep <- intersect(names(GRADE_KV), names(gkv))
GRADE_SEC <- if (length(keep)) list(list(type = "kv", emoji = "\U0001F4CF", heading = "등급 근거(계약 산출물)",
                                        kv = lapply(setNames(gkv[keep], unname(GRADE_KV[keep])), function(v) sub("^-", "−", as.character(v))))) else NULL
vl <- vapply(SM$variants, function(v) {
  nm <- sprintf("%s%s", v$id, if (isTRUE(v$headline)) "(대표)" else "")
  if (!identical(v$status, "ok")) return(sprintf("• %s — 측정 실패: %s", nm, substr(v$error %||% v$status, 1, 90)))
  sprintf("• %s — %s · CAGR %s · Calmar %s · PORT_t %s · 위기 방어 %s · 롱/숏 평균 %s/%s종%s", nm, v$grade %||% "NA", pct(v$cagr), num(v$calmar),
          num(v$port_t), cvw(v$crisis_verdict), num(v$holdings$n_long_mean, 1), num(v$holdings$n_short_mean, 1),
          if (isTRUE(v$holdings_mismatch)) " · 보유 대조 어긋남" else "")
}, character(1))
VAR_SEC <- list(list(type = "text", emoji = "\U0001F9EA",
                     heading = "논문 방법 3종 — 대표 hl(High−Low · 측정 전 고정) · ha = High−All · rank = 순위 합 5분위 · 비대표는 DSR 대상",
                     body = paste(vl, collapse = "\n")))
pg <- H$paper_gross %||% list()
es <- H$effective_start %||% list()
dg <- tryCatch(fread(file.path(SDIR, "engine_diag_hl.csv")), error = function(e) NULL)
skipped <- if (!is.null(dg)) dg[(is.na(n_long) | is.na(n_short)) & as.Date(form_date) > as.Date(es$date %||% "1900-01-01"), format(as.Date(form_date))] else character(0)
NOTE_SEC <- list(list(type = "bullet", emoji = "🧾", heading = "보충 · 경계 신고(FIDELITY.json)",
  items = c(
    "CFO 공백(v2 영업현금흐름 · 자본증감 = 2003년 1분기부터): 원문에 대체법이 없어 대체 안 함 — FY2000~2002 표본 제외 · 아홉 신호 유지",
    sprintf("Low 공집합 편입일 %s: 직전 코호트를 다음 편입일까지 보유(1년 보유 이탈)", if (length(skipped)) paste(skipped, collapse = " · ") else "없음"),
    "장기부채의 CurrentBorr(퀀티 M113300)는 단기차입금 + 유동성장기차입금 — 단기차입금이 섞인다 · 정의는 측정 전 그대로 · 전환 뒤 재측정 때 측정 전에 다시 정한다",
    "PIT 경계: 재무는 정정 뒤 값 — FY2015~ DART 0.5% 초과 차이는 가용일 미룸(그해 제외) · FY2014 이전과 미검사분은 나중 정정이 원래 날짜에 실렸을 수 있다")))
verdict <- sprintf("[정정 · PIT 누출 수리 뒤 재측정] 등급 %s(권위 · 15bps 순비용) · β %s · β 통제 α t %s(%s) · 논문 기준(gross · 비용 0) CAGR %s · 최대낙폭 %s vs 15bps CAGR %s · 최대낙폭 %s",
                   H$grade, num(H$beta), num(H$alpha_t), if (identical(as.character(H$alpha_basis), "2f")) "2요인" else "1요인",
                   pct(pg$cagr), pct(-abs(as.numeric(pg$mdd))), pct(H$cagr), pct(-abs(as.numeric(H$mdd))))
eff_txt <- if (identical(es$status, "ok")) sprintf("유효 시작 %s(첫 편입 신호일 — FY2003 은 Low 0 · FY2000~2002 는 CFO 공백)", es$date) else
           sprintf("유효 시작 %s(%s)", es$date %||% "?", es$status %||% "?")
status <- list(stage = "1계층 팩터전략 리서치 — 충실구현(세션 · 퀀티 재무 DB v2 직접 판독)",
               position = paste0("재무 원천 v2(전환 전) · DART 연간 보충 진행 중 · ", eff_txt, " · 측정 축 전 종목+위생+동전주 바닥"),
               previous = "현행 축에서 F-Score 논문 그대로 충실구현은 처음(과거 사용은 다른 전략의 부품 · 구 축)")
next_step <- "v2 전환 + 팩터 DB 재빌드 뒤 같은 엔진으로 재측정(인용 · 풀 등재 전) · 그 전까지 이 수치는 판독용 · 원장 · 풀 · L-code 미등록"
charts <- tryCatch({ p <- rf_perf_charts(HEAD); cap <- c(equity_curve.png = "누적수익 — 전략과 벤치마크", annual_returns.png = "연도별 수익률", drawdown.png = "낙폭 — 고점 대비")[basename(p)]
                     setNames(p, ifelse(is.na(cap), basename(p), cap)) }, error = function(e) NULL)
## ★정정(2026-11-09 · Q 검토 PIT 누출 수리) — 앞 보고(수리 전 산출 *_superseded_pitcut) 대비 앞 → 뒤
OLD <- fromJSON(file.path(fromJSON(file.path(SDIR, "run_dirs_superseded_pitcut.json"), simplifyVector = FALSE)$hl$out_dir, "variants_summary.json"), simplifyVector = FALSE)
.old <- setNames(OLD$variants, vapply(OLD$variants, function(v) v$id, ""))
.ab <- function(a, b, f) sprintf("%s/%s", f(a), f(b))
cmp <- vapply(SM$variants, function(v) {
  o <- .old[[v$id]]; if (is.null(o) || !identical(v$status, "ok")) return(sprintf("• %s — 비교 불가", v$id))
  sprintf("• %s%s — 등급 %s · CAGR %s · 최대낙폭 %s · Calmar %s · PORT_t %s · 롱 평균 %s · 숏 평균 %s · 위기 방어 %s", v$id, if (isTRUE(v$headline)) "(대표)" else "",
          .ab(o$grade, v$grade, function(x) as.character(x %||% "NA")), .ab(o$cagr, v$cagr, pct),
          .ab(-abs(as.numeric(o$mdd)), -abs(as.numeric(v$mdd)), pct), .ab(o$calmar, v$calmar, num), .ab(o$port_t, v$port_t, num),
          .ab(o$holdings$n_long_mean, v$holdings$n_long_mean, function(x) num(x, 1)), .ab(o$holdings$n_short_mean, v$holdings$n_short_mean, function(x) num(x, 1)),
          .ab(o$crisis_verdict, v$crisis_verdict, cvw))
}, character(1))
.dgn <- tryCatch(fread(file.path(SDIR, "engine_diag_hl.csv")), error = function(e) NULL)
.dgo <- tryCatch(fread(file.path(SDIR, "engine_diag_hl_superseded_pitcut.csv")), error = function(e) NULL)
cut_line <- if (!is.null(.dgn) && !is.null(.dgo)) {
  m <- merge(.dgn[, .(form_date, cn = cut80_prior, n_cut_late, hn = n_hbm)], .dgo[, .(form_date, co = cut80_prior, ho = n_hbm)], by = "form_date")
  m <- m[as.Date(form_date) >= as.Date(es$date %||% "1900-01-01")]
  sprintf("경계 표본에서 늦게 가용되는 행이 빠진 편입일 %d개(합 %d행) · 경계가 바뀐 편입일 %d개 · 고 BM 표본 수가 바뀐 편입일 %d개(유효 시작 이후)",
          sum(m$n_cut_late > 0), sum(m$n_cut_late), sum(abs(m$cn - m$co) > 1e-12, na.rm = TRUE), sum(m$hn != m$ho))
} else "경계 변화 집계 실패(진단 파일)"
CORR_SEC <- list(list(type = "text", emoji = "\U0001F6E0",
  heading = "정정 — 고 BM 5분위 경계 PIT 누출 수리 · 수치는 앞 보고/이번(앞 산출 = *_superseded_pitcut · 인용 금지) · 비대표 변형은 DSR 대상",
  body = paste(c("무엇을 고쳤나: 경계(직전 회계연도 BM 80 백분위)가 경계 표본 행의 가용일을 보지 않았다 — 편입일 이후에야 쓸 수 있는 장부가(정정 공시 늦은 접수 등)가 섞였다(선정 통계 as-of 위반 · C1). 이제 max(장부 자본 Factor_Date, 익년 3/31) ≤ 편입일 인 행만 쓴다.",
                 cut_line, cmp), collapse = "\n")))
EXTRA <- c(CORR_SEC, GRADE_SEC, FA_SEC, NOTE_SEC)   # 변형 3종 섹션은 정정 섹션(앞/뒤)이 대신한다(1통 길이)
ARGS <- list(program = "충실구현", target = paste0("정정 · ", TITLE), status = status, card = cards$hl, verdict_line = verdict, next_step = next_step,
             artifact = HEAD, charts = charts, extra = EXTRA, push = TRUE, root = ROOT, crisis = "chart")
saveRDS(ARGS, file.path(HEAD, "tg_args.rds"))

## dry-run(발송 안 함)
Sys.setenv(QVEST_TG_DRY_RUN = "1")
res <- do.call(prep_send, ARGS)
capture.output(print(res), file = file.path(HEAD, "tg_dryrun_result.txt"))

## 실제 발송 스크립트(Q 검토 뒤 실행 · 같은 인자)
writeLines(c(
  "# tg_send.R — Piotroski (2000) 충실구현 정정 보고 1통 실제 발송(앞 보고 10:5x 발송분의 정정 · 발송 규칙 §0.4)(build_report.R 가 dry-run 으로 만든 것과 같은 인자 · tg_args.rds)",
  "#   실행: \"C:/Program Files/R/R-4.6.2/bin/Rscript.exe\" <이 파일>   (프로젝트 루트에서)",
  sprintf("ROOT <- \"%s\"; setwd(ROOT); Sys.setenv(QM_ROOT = ROOT, CLAUDE_PROJECT_DIR = ROOT, QVEST_TG_DRY_RUN = \"0\")", ROOT),
  "suppressMessages({ source(file.path(ROOT, \"02_Infrastructure/telegram/telegram_notify.R\")); source(file.path(ROOT, \"02_Infrastructure/programs/program_report.R\")) })",
  sprintf("ARGS <- readRDS(\"%s\")", file.path(HEAD, "tg_args.rds")),
  "ARGS$dry_run <- FALSE",
  "print(do.call(prep_send, ARGS))"), file.path(HEAD, "tg_send.R"))
cat("[report] 끝 —", HEAD, "\n")
