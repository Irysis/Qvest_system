## 07_sandbox_render.R — 스테이징 조립(style_brief_lib.R v4)을 사본 자료로 돌려 본문을 만들고, 운영 텔레그램 모듈의
##   tg_agent_brief(dry_run = TRUE) 렌더 규율(bullet ≤80자 · 약어 · 골격)을 통과하는지 본다. 발송 0(QVEST_TG_DRY_RUN=1 이중 차단).
##   인자: <샌드박스 자료 루트(outputs/ · .cache/ 사본)> <코드 루트(스테이징)> <운영 루트(텔레그램 모듈 · 등록부)> <출력 txt> [now KST]
Sys.setenv(QVEST_TG_DRY_RUN = "1")
suppressMessages({ library(arrow); library(data.table); library(jsonlite) })
a <- commandArgs(trailingOnly = TRUE)
DATA <- a[1]; CODE <- a[2]; PROD <- a[3]; OUTF <- a[4]
NOW <- as.POSIXct(if (length(a) >= 5) a[5] else format(Sys.time(), "%Y-%m-%d %H:%M:%S", tz = "Asia/Seoul"), tz = "Asia/Seoul")
source(file.path(CODE, "02_Infrastructure/reports/style_brief_lib.R"))
dp <- function(p) file.path(DATA, p)
## ff5_brief_send.R(v4) 의 읽기 함수와 같은 규칙 — 스테이징 송신 스크립트에서 그 함수만 꺼내 쓴다
ex <- parse(file = file.path(CODE, "02_Infrastructure/ops/morning_steps/ff5_brief_send.R"), encoding = "UTF-8", keep.source = FALSE)
for (e in ex) if (is.call(e) && identical(e[[1]], as.name("<-")) && identical(e[[2]], as.name("sw_read_kf"))) eval(e)
T_SIG <- as.numeric(fromJSON(file.path(PROD, "02_Infrastructure/worktask/constraint_defaults.json"))$tier_graduation[["grade_b_min_portfolio_alpha_t"]])
FF <- as.data.table(read_parquet(dp("outputs/ff5_kr/ff5_kr_monthly.parquet")))
SB <- as.data.table(read_parquet(dp("outputs/smartbeta_kr/smartbeta_kr_monthly.parquet")))
mtd5 <- sw_read_json(dp("outputs/ff5_kr/ff5_kr_mtd.json")); sbm <- sw_read_json(dp("outputs/smartbeta_kr/smartbeta_kr_mtd.json"))
ib <- sw_read_json(dp("outputs/ff5_kr/index_factor_beta.json"))
kf <- sw_read_kf(dp, ref_as_of = sbm$as_of)
out <- sw_compose_brief(FF, SB, mtd5 = mtd5, sbm = sbm, ib = ib, now = NOW, kf = kf, t_sig = T_SIG)
ln <- sw_dryrun_lines(out, charts_root = DATA)
suppressMessages(source(file.path(PROD, "02_Infrastructure/telegram/telegram_notify.R")))
rr <- tryCatch({ invisible(capture.output(x <- tg_agent_brief(agent = "Q-Lead", title = out$title, sections = out$sections,
                                                              charts = NULL, footer = out$footer, dry_run = TRUE))); x },
               error = function(e) list(ok = FALSE, error = conditionMessage(e)))
ln <- c(sprintf("=== v4 샌드박스 렌더 — now %s KST · kf=%s · t_sig=%.1f · 발송 없음 ===", format(NOW, "%Y-%m-%d %H:%M"),
                if (isTRUE(out$kf_used)) sprintf("정본(%s)", format(out$kf$as_of)) else sprintf("구 경로(%s)", out$kf$reason), T_SIG),
        ln, "", sprintf("RENDER ok=%s dry_run=%s%s", isTRUE(rr$ok), isTRUE(rr$dry_run), if (is.null(rr$error)) "" else paste0(" · ", rr$error)),
        if (is.null(rr$msg)) character(0) else c("--- 렌더 본문 ---", rr$msg))
bl <- unlist(lapply(out$sections, function(s) if (identical(s$type, "bullet")) s$items else character(0)))
ln <- c(ln, "", sprintf("bullet 최대 자수 = %d (규율 80)", max(nchar(bl))))
writeLines(enc2utf8(ln), OUTF, useBytes = TRUE)
cat(paste(ln, collapse = "\n"), "\n")
