## aif_gp_evo.R — 수식 탐색 3판의 '진화의 효과' 그림과 요약 줄(도훈 11-23 "진화에 따른 효과 보여주는 시각자료도 같이 보내주면").
##   aif_common.R 을 먼저 source 한다. 그림 층(aif_charts.R)은 그릴 일이 있을 때만 불러온다 — 주기 통이 가볍게 지나가게.
##   재료 = 수식 탐색이 남긴 기록뿐이다(추가 계산 없음 · 읽기 전용 · 값 표는 mmap 없이 읽어 도는 중인 탐색의 파일을 잡아 두지 않는다):
##     시행 원장 gp3/trial_ledger_<변형>.jsonl — 수식마다 태어난 세대 · 출처(무작위 출발 init · 전년도에서 물려받음 inherited · 진화로 태어남 offspring) · 학습과 검증 점수
##     해마다의 저장분 gp3/<변형>_<해>.json — 그해 말에 고른 식 / 값 표 gp3/<변형>_<해+1>_tab.parquet — 고른 식의 다음 해 월말 값
##     공통 틀 frame/ — 다음 달 수익과 유니버스 멤버(다음 해 실현 순위 IC 를 재는 데 쓴다)
##   점수 = 전 종목 순위 IC 의 안정성(월별 순위 IC 평균 ÷ 표준편차 × √12) — 탐색 점수와 같은 정의(py/aif_gp.py::metrics_ic).
##   그림(변형마다 두 장):
##     ① 세대별 진화 곡선 — 해마다, 그 세대까지 나온 식 가운데 적합도 상위 GPE_TOP 개의 학습 · 검증 구간 점수 평균
##     ② 진화가 보탠 것 — (가) 고른 식의 검증 점수: 무작위 출발만 대 진화 뒤 (나) 고른 식이 태어난 세대와 출처 (다) 고른 식의 순위 IC: 학습 · 검증 · 다음 해 실현
##   보고용이다 — 여기서 잰 값으로 식을 고르거나 설정을 바꾸지 않는다. 식을 쓴 해가 표본 밖(설정 measure.is_end 뒤)이면 요약 줄에서 따로 묶고 그림에 경계선을 긋는다.
##   색은 계열을 따라간다(학습 = 파랑 · 검증 = 주황 · 다음 해 실현 = 청록 — 세 색은 색각 이상 구분 검사를 통과한 조합이고 모양도 함께 다르게 쓴다).
GPE_COL <- c(train = "#2a78d6", val = "#eb6834", real = "#1baf7a")
GPE_LAB <- c(train = "학습 구간", val = "검증 구간", real = "다음 해 실현")
GPE_SHAPE <- c(train = 21, val = 22, real = 23)
GPE_INK <- "#52514e"; GPE_GRID <- "#e6e5e1"
GPE_VARIANT <- c(EXP = "확장 창", ROLL8 = "고정 8년 창")
GPE_ORIGIN <- c(offspring = "진화로 태어남(1세대 이후)", inherited = "전년도에서 물려받음", init = "무작위 출발")
GPE_TOP <- 20L          # 곡선에 쓰는 상위 식의 수 — 정한 값(엔진의 명예의 전당 50개와 마지막에 고르는 5개 사이 · 한두 식의 운에 곡선이 흔들리지 않게)
GPE_MIN_N <- 30L        # 순위 IC 를 재는 달의 최소 종목 수 — 측정기(R/aif_factor_perf.R::aif_ic)의 기본값과 같다
GPE_CFG_REL <- "04_Research/01_reports/gp_symbolic_alpha_20261116/gp_config.json"      # 수식 탐색이 읽는 설정(세대 수 · 검증 구간 길이 · 선택 규칙의 문턱)

gpe_years_done <- function(run_dir, v) {
  f <- list.files(run_dir, pattern = sprintf("^%s_[0-9]{4}\\.json$", v))
  sort(as.integer(sub(sprintf("^%s_([0-9]{4})\\.json$", v), "\\1", f)))
}
## 끝난 (변형, 해)의 수 — 주기 통이 '새로 끝난 해가 있는가'를 가리는 열쇠
gpe_key <- function(run_dir) paste(vapply(names(GPE_VARIANT), function(v) sprintf("%s:%d", v, length(gpe_years_done(run_dir, v))), ""), collapse = "|")
gpe_sent_path <- function(root, cfg) aif_out("gp3_evo", "sent.json", root = root, cfg = cfg)
aif_gp_evo_mark_sent <- function(key, root = aif_root(), cfg = aif_cfg(root)) {
  p <- gpe_sent_path(root, cfg); dir.create(dirname(p), recursive = TRUE, showWarnings = FALSE)
  aif_write_json(list(key = key, sent_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S")), p)
}

## 시행 원장 — 탐색이 쓰는 중인 파일이라 끝줄이 덜 쓰였을 수 있다(버린다). 중간에 끊겼다 이어 쓴 자리의 깨진 줄도 버린다(통째로 읽기가 실패할 때만 줄마다 검사).
##   같은 해를 다시 돌렸으면 같은 식은 처음 기록만 남긴다.
gpe_ledger <- function(path) {
  ln <- readLines(path, warn = FALSE, encoding = "UTF-8"); ln <- ln[nzchar(ln)]
  if (length(ln) && !isTRUE(jsonlite::validate(ln[length(ln)]))) ln <- ln[-length(ln)]
  ln <- ln[grepl('"type": "trial"', ln, fixed = TRUE)]
  if (!length(ln)) return(NULL)
  rd <- function(x) fromJSON(sprintf("[%s]", paste(x, collapse = ",")))
  d <- tryCatch(rd(ln), error = function(e) rd(ln[vapply(ln, function(z) isTRUE(jsonlite::validate(z)), TRUE, USE.NAMES = FALSE)]))
  d <- as.data.table(jsonlite::flatten(d))
  need <- c("train.alpha_ir", "val.alpha_ir", "train.rank_ic_mean", "val.rank_ic_mean", "train.coverage", "train.hold_hash", "val.hold_hash", "std_corr_max", "fitness")
  for (nm in setdiff(need, names(d))) set(d, j = nm, value = NA)
  d <- d[, .(year = as.integer(evo_year_end), gen = as.integer(gen), origin, status, hash, nodes = as.integer(nodes), fitness = as.numeric(fitness),
             train_ir = as.numeric(train.alpha_ir), val_ir = as.numeric(val.alpha_ir), train_icm = as.numeric(train.rank_ic_mean), val_icm = as.numeric(val.rank_ic_mean),
             train_cov = as.numeric(train.coverage), hold = paste0(train.hold_hash, val.hold_hash), std_corr_max = as.numeric(std_corr_max))]
  d[!duplicated(d, by = c("year", "hash"))]
}

## 세대별 앞선 식 — 그 세대까지 나온 식(유효한 것) 가운데 적합도 상위 top_n 개의 학습 · 검증 점수 평균(해 안에서 세대 순으로 쌓인다)
gpe_frontier <- function(tr, top_n) {
  ok <- tr[status == "ok" & is.finite(fitness)]
  rbindlist(lapply(split(ok, by = "year"), function(d) rbindlist(lapply(0:max(d$gen), function(g) {
    x <- d[gen <= g][order(-fitness)]; x <- x[seq_len(min(top_n, nrow(x)))]
    data.table(year = d$year[1], gen = g, train = mean(x$train_ir), val = mean(x$val_ir, na.rm = TRUE))
  }))))
}

## 무작위 출발만으로 고를 수 있던 식 — 0세대의 무작위 식에 선택 규칙(학습 · 검증 점수 > 0 · 채움 · 표준 팩터와의 상관 문턱 · 검증 점수 순 · 같은 보유 종목이면 하나)을 적용한 상위 k 개.
##   실제 규칙의 '이미 고른 식과의 상관 문턱'은 월말 값이 있어야 해 여기서는 뺐다 — 무작위 쪽이 조금 유리해지는 방향이다(그림에 적는다).
gpe_random_top <- function(tr, gcfg) {
  c0 <- tr[gen == 0L & origin == "init" & status == "ok" & train_ir > 0 & val_ir > 0 & train_cov >= gcfg$fitness$coverage_min & std_corr_max < gcfg$selection$corr_max_vs_std]
  setorder(c0, year, -val_ir, nodes, hash)
  c0 <- c0[!duplicated(c0, by = c("year", "hold"))]
  c0[, head(.SD, as.integer(gcfg$selection$k)), by = year][, .(rand_val = mean(val_ir)), by = year]
}

## 해마다 고른 식 — 저장분의 목록에 원장의 태어난 세대 · 출처 · 학습과 검증 구간 순위 IC 를 붙인다
gpe_picks <- function(run_dir, v, done, tr) {
  pk <- rbindlist(lapply(done, function(y) {
    z <- fromJSON(file.path(run_dir, sprintf("%s_%d.json", v, y)))
    if (is.data.frame(z$rows) && nrow(z$rows)) as.data.table(z$rows) else NULL
  }), fill = TRUE)
  if (!nrow(pk)) return(NULL)
  merge(pk[, .(year = as.integer(year_selected), hash, val_ir = as.numeric(val_ic_ir))],
        tr[, .(year, hash, gen, origin, train_icm, val_icm)], by = c("year", "hash"), all.x = TRUE)
}

gpe_frame <- function(root, cfg) {
  fd <- aif_out("frame", root = root, cfg = cfg)
  sg <- fread(file.path(fd, "signals.csv")); tk <- fread(file.path(fd, "tickers.csv"))
  ns <- nrow(sg); nt <- nrow(tk)
  rd <- function(nm, what, size) { con <- file(file.path(fd, nm), "rb"); on.exit(close(con)); matrix(readBin(con, what, n = ns * nt, size = size), ns, nt, byrow = TRUE) }
  list(sig = as.Date(sg$sig_date), hold_ok = sg$hold_ok == 1L, tick = tk$Ticker, fwd = rd("fwd_1.f32", "numeric", 4L), mem = rd("mem.u8", "raw", 1L) != as.raw(0L))
}

## 고른 식의 다음 해 실현 순위 IC — 그 달 멤버 가운데 값과 다음 달 수익이 모두 있는 종목(GPE_MIN_N 미만인 달은 뺀다). 식마다 월별 순위 IC 의 평균.
gpe_realized <- function(tab_path, fr) {
  tb <- as.data.table(arrow::read_parquet(tab_path, mmap = FALSE))
  s <- match(as.Date(tb$Date, tz = "UTC"), fr$sig); j <- match(tb$Ticker, fr$tick)
  keep <- !is.na(s) & !is.na(j) & is.finite(tb$Raw_Value)
  tb <- tb[keep]; s <- s[keep]; j <- j[keep]
  tb[, `:=`(s = s, fw = fr$fwd[cbind(s, j)], member = fr$mem[cbind(s, j)])]
  tb <- tb[member & is.finite(fw) & fr$hold_ok[s]]
  ic <- tb[, .(ic = if (.N >= GPE_MIN_N) suppressWarnings(cor(rank(Raw_Value), rank(fw))) else NA_real_), by = .(Factor_Name, s)]
  ic[, .(real_icm = mean(ic, na.rm = TRUE)), by = Factor_Name]
}

gpe_theme <- function() aif_theme(10) + theme(panel.grid.major = element_line(colour = GPE_GRID, linewidth = 0.3), legend.position = "top", legend.justification = "left",
                                              legend.margin = margin(0, 0, 0, 0), legend.text = element_text(size = 8.5), plot.title = element_text(size = 11.5),
                                              plot.subtitle = element_text(size = 8.5, lineheight = 1.05), strip.text = element_text(size = 9.5, hjust = 0))

gpe_plot_curve <- function(fr, done, v, gcfg, path) {
  gens <- as.integer(gcfg$evolution$generations)
  yrs <- sort(unique(fr$year))
  lab <- setNames(sprintf("%d년 말 진화%s", yrs, ifelse(yrs %in% done, "", " · 진행 중")), yrs)
  setorder(fr, year, gen)
  d <- melt(fr, id.vars = c("year", "gen"), measure.vars = c("train", "val"), variable.name = "series", value.name = "score")
  d[, f := factor(lab[as.character(year)], levels = lab)]
  an <- fr[, .(txt = sprintf("학습 %s → %s\n검증 %s → %s", aif_num(train[1], 1), aif_num(train[.N], 1), aif_num(val[1], 1), aif_num(val[.N], 1))), by = year]
  an[, f := factor(lab[as.character(year)], levels = lab)]
  nc <- min(4L, length(yrs))
  p <- ggplot(d, aes(gen, score, colour = series)) +
    geom_line(linewidth = 0.5, lineend = "round", linejoin = "round") +
    geom_point(data = d[, .SD[gen == max(gen)], by = .(year, series)], size = 1.5) +
    geom_text(data = an, aes(x = Inf, y = -Inf, label = txt), inherit.aes = FALSE, hjust = 1.06, vjust = -0.4, size = 2.7, lineheight = 0.95, colour = GPE_INK, family = aif_font()) +
    facet_wrap(~f, ncol = nc) +
    scale_colour_manual(values = GPE_COL[c("train", "val")], breaks = c("train", "val"), labels = GPE_LAB[c("train", "val")]) +
    scale_x_continuous(breaks = seq(0, gens, 5), limits = c(0, gens)) + scale_y_continuous(expand = expansion(mult = c(0.36, 0.08))) +
    labs(title = sprintf("수식 탐색 3판 — 세대가 지날수록 앞선 식이 좋아지는가 (%s)", GPE_VARIANT[[v]]),
         subtitle = sprintf(paste0("그 세대까지 나온 식 가운데 학습 점수 상위 %d개의 평균 · 가로 = 세대(0 = 출발 집단: 무작위 식 + 전년도에서 물려받은 식) · 검증 구간 = 학습 구간 뒤 %d개월\n",
                                   "세로 = 순위 IC 의 안정성(월별 순위 IC 평균 ÷ 표준편차 × √12) · 칸 안 숫자 = 0세대 → 마지막 세대"), GPE_TOP, as.integer(gcfg$walkforward$val_months)),
         caption = paste0("진화는 학습 구간 점수만 보고 식을 키운다 — 검증 구간 점수는 마지막에 고를 때만 쓴다(검증 선이 함께 오르면 학습 구간에만 맞춘 개선이 아니다).\n",
                          "둘째 해부터 0세대의 검증 점수가 높은 것은 전년도에 검증 점수로 고른 식을 물려받고, 검증 구간이 전년도와 두 해 겹치기 때문이다.")) +
    gpe_theme() + theme(plot.caption = element_text(hjust = 0, lineheight = 1.1))
  aif_png(p, path, w = 1080, h = 360L + 290L * as.integer(ceiling(length(yrs) / nc)))
}

gpe_plot_gain <- function(gain, pk, v, gcfg, is_year, path) {
  gens <- as.integer(gcfg$evolution$generations); k <- as.integer(gcfg$selection$k)
  yrs <- sort(unique(gain$year)); n <- length(yrs)
  ypos <- function(y) n + 1L - match(y, yrs)                                     # 이른 해가 위
  ysc <- scale_y_continuous(breaks = ypos(yrs), labels = sprintf("%d년 말", yrs), limits = c(0.4, n + 0.6))
  ## (가) 고른 식의 검증 점수: 무작위 출발만 대 진화 뒤
  a <- melt(gain[, .(year, rand = rand_val, pick = pick_val)], id.vars = "year", variable.name = "kind", value.name = "score")
  pa <- ggplot(gain, aes(y = ypos(year))) +
    geom_segment(aes(x = rand_val, xend = pick_val, yend = ypos(year)), colour = "#c9c8c2", linewidth = 0.7, na.rm = TRUE) +
    geom_point(data = a, aes(x = score, y = ypos(year), fill = kind), shape = 21, colour = GPE_COL[["val"]], size = 2.6, stroke = 0.9, na.rm = TRUE) +
    geom_text(aes(x = pmax(rand_val, pick_val, na.rm = TRUE), label = ifelse(is.finite(rand_val), sprintf("%+.1f", pick_val - rand_val), "무작위 쪽 후보 없음")),
              hjust = -0.45, size = 2.8, colour = GPE_INK, family = aif_font()) +
    scale_fill_manual(values = c(rand = "white", pick = GPE_COL[["val"]]), breaks = c("rand", "pick"),
                      labels = c(rand = sprintf("무작위 출발(0세대)만으로 고른 상위 %d개", k), pick = sprintf("진화 뒤 실제로 고른 %d개", k))) +
    scale_x_continuous(expand = expansion(mult = c(0.06, 0.14))) + ysc +
    labs(title = "(가) 고른 식의 검증 점수 — 무작위 출발만 대 진화 뒤", subtitle = sprintf("검증 구간 점수의 %d개 평균 · 오른쪽 숫자 = 진화가 더한 폭", k)) + gpe_theme()
  ## (나) 고른 식이 태어난 세대와 출처
  b <- pk[!is.na(gen)]
  b[, origin := factor(origin, levels = names(GPE_ORIGIN))]
  b[, yy := ypos(year) + (seq_len(.N) - (.N + 1) / 2) * 0.17, by = .(year, gen)]
  bn <- pk[, .(txt = sprintf("진화 %d · 물려받음 %d · 무작위 %d", sum(origin == "offspring", na.rm = TRUE), sum(origin == "inherited", na.rm = TRUE), sum(origin == "init", na.rm = TRUE))), by = year]
  pb <- ggplot(b, aes(gen, yy, shape = origin)) +
    geom_point(size = 2.3, colour = GPE_INK, stroke = 0.8, show.legend = TRUE) +
    geom_text(data = bn, aes(x = gens + 1, y = ypos(year), label = txt), inherit.aes = FALSE, hjust = 0, size = 2.7, colour = GPE_INK, family = aif_font()) +
    scale_shape_manual(values = c(offspring = 16, inherited = 2, init = 0), breaks = names(GPE_ORIGIN), labels = GPE_ORIGIN, drop = FALSE) +
    scale_x_continuous(breaks = seq(0, gens, 5), limits = c(-0.5, gens + 8.5)) + ysc +
    labs(title = "(나) 고른 식이 태어난 세대", subtitle = "점 하나 = 고른 식 하나 · 가로 = 그 식이 처음 만들어진 세대(0 = 출발 집단)") + gpe_theme()
  ## (다) 고른 식의 순위 IC — 학습 · 검증 · 다음 해 실현
  cc <- pk[, .(train = mean(train_icm, na.rm = TRUE), val = mean(val_icm, na.rm = TRUE), real = if (all(is.na(real_icm))) NA_real_ else mean(real_icm, na.rm = TRUE),
               lo = suppressWarnings(min(real_icm, na.rm = TRUE)), hi = suppressWarnings(max(real_icm, na.rm = TRUE))), by = .(used = year + 1L)]
  cl <- melt(cc, id.vars = "used", measure.vars = c("train", "val", "real"), variable.name = "series", value.name = "ic")[is.finite(ic)]
  cl[, series := factor(series, levels = c("train", "val", "real"))]
  pc <- ggplot(cl, aes(used, ic)) +
    geom_hline(yintercept = 0, colour = "#8a8983", linewidth = 0.3) +
    geom_linerange(data = cc[is.finite(real)], aes(x = used, ymin = lo, ymax = hi), inherit.aes = FALSE, colour = GPE_COL[["real"]], alpha = 0.55, linewidth = 0.7) +
    geom_point(aes(fill = series, shape = series), colour = "white", size = 2.9, stroke = 0.7) +
    geom_text(data = cc[is.finite(real)], aes(x = used, y = real, label = sprintf("%.3f", real)), inherit.aes = FALSE, hjust = -0.3, size = 2.6, colour = GPE_INK, family = aif_font()) +
    scale_fill_manual(values = GPE_COL, breaks = names(GPE_COL), labels = GPE_LAB, drop = FALSE) + scale_shape_manual(values = GPE_SHAPE, breaks = names(GPE_SHAPE), labels = GPE_LAB, drop = FALSE) +
    scale_x_continuous(breaks = sort(unique(cc$used)), labels = function(x) sprintf("%d년", x), expand = expansion(add = 0.6)) +
    scale_y_continuous(expand = expansion(mult = c(0.08, 0.08))) +
    labs(title = "(다) 고른 식의 순위 IC — 학습 · 검증 구간과 실제로 쓴 다음 해",
         subtitle = sprintf("월별 순위 IC 평균의 %d개 평균 · 가로 = 식을 쓴 해 · 세로 선 = 고른 식들의 다음 해 실현 값 범위 · 숫자 = 다음 해 실현", k)) + gpe_theme()
  if (min(cc$used) <= is_year && max(cc$used) > is_year)                          # 표본 안 / 밖 경계(연구의 그림 규칙 — 점선)
    pc <- pc + geom_vline(xintercept = is_year + 0.5, linetype = "dashed", colour = "#888888", linewidth = 0.4)
  g <- wrap_plots(pa, pb, pc, ncol = 1, heights = c(max(n, 3L), max(n, 3L), 8)) +
    plot_annotation(title = sprintf("수식 탐색 3판 — 진화가 보탠 것 (%s)", GPE_VARIANT[[v]]),
                    caption = sprintf(paste0("(가) 검증 점수로 고르므로 후보가 많을수록 최고점은 저절로 오른다 — 진화의 실제 효과는 (다)의 다음 해 실현 값으로 본다.\n",
                                             "(가)의 무작위 쪽은 '이미 고른 식과 상관 %.1f 미만' 조건을 적용하지 못해 조금 유리하게 잡혀 있다."), gcfg$selection$corr_max_vs_selected),
                    theme = aif_theme(10) + theme(plot.title = element_text(size = 13.5), plot.caption = element_text(size = 7.5, hjust = 0, lineheight = 1.1)))
  aif_png(g, path, w = 1080, h = 300L + 2L * (190L + 30L * max(n, 3L)) + 430L)
}

## 그림과 요약 줄을 만든다. only_new = TRUE 면 직전에 보낸 뒤로 새로 끝난 해가 없을 때 NULL(주기 통이 같은 그림을 되풀이해 보내지 않게).
##   돌려주는 것: key(보냄 기록에 쓸 열쇠) · charts(이름 붙은 그림 경로) · headline · lines(요약 줄) · guide(그림 읽는 법)
aif_gp_evo <- function(root = aif_root(), cfg = aif_cfg(root), only_new = FALSE) {
  run_dir <- aif_out("gp3", root = root, cfg = cfg)
  key <- gpe_key(run_dir)
  if (only_new) {
    last <- tryCatch(fromJSON(gpe_sent_path(root, cfg))$key, error = function(e) NULL)
    if (identical(last, key)) return(NULL)
  }
  source(file.path(aif_dir(root), "R", "aif_charts.R"))
  gcfg <- fromJSON(file.path(root, GPE_CFG_REL), simplifyVector = FALSE)
  gens <- as.integer(gcfg$evolution$generations); k <- as.integer(gcfg$selection$k); wf <- gcfg$walkforward
  n_all <- as.integer(wf$last_evolution_year_end) - as.integer(wf$first_evolution_year_end) + 1L
  is_year <- as.integer(substr(cfg$measure$is_end, 1L, 4L))
  out_dir <- aif_out("gp3_evo", root = root, cfg = cfg); dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  fr <- NULL; charts <- character(0); lines <- character(0); prog <- character(0)
  for (v in names(GPE_VARIANT)) {
    nm <- GPE_VARIANT[[v]]
    lp <- file.path(run_dir, sprintf("trial_ledger_%s.jsonl", v))
    tr <- if (file.exists(lp)) gpe_ledger(lp) else NULL
    if (is.null(tr)) { prog <- c(prog, sprintf("%s 0/%d", nm, n_all)); next }
    done <- gpe_years_done(run_dir, v)
    prog <- c(prog, sprintf("%s %d/%d%s", nm, length(done), n_all, if (length(done)) sprintf("(%d~%d년 말)", min(done), max(done)) else ""))
    fro <- gpe_frontier(tr, GPE_TOP)
    charts[sprintf("진화 곡선(%s)", nm)] <- gpe_plot_curve(copy(fro), done, v, gcfg, file.path(out_dir, sprintf("gp3_evo_%s_curve.png", v)))
    fd <- fro[year %in% done, .(t0 = train[1], t1 = train[.N], v0 = val[1], v1 = val[.N]), by = year]
    if (nrow(fd)) lines <- c(lines, sprintf("%s · 앞선 식 %d개의 점수(끝난 해 평균): 학습 구간 %.1f → %.1f · 검증 구간 %.1f → %.1f (0세대 → %d세대)",
                                            nm, GPE_TOP, mean(fd$t0), mean(fd$t1), mean(fd$v0), mean(fd$v1), gens))
    pk <- if (length(done)) gpe_picks(run_dir, v, done, tr) else NULL
    if (is.null(pk)) next
    if (is.null(fr)) fr <- gpe_frame(root, cfg)
    rl <- rbindlist(lapply(done, function(y) {
      tp <- file.path(run_dir, sprintf("%s_%d_tab.parquet", v, y + 1L))
      if (file.exists(tp)) cbind(year = y, gpe_realized(tp, fr)) else NULL
    }))
    pk[, real_icm := NA_real_]
    comp <- data.table(year = integer(0), comp = numeric(0))
    if (nrow(rl)) {
      rl[, hash := sub("^.*_", "", Factor_Name)]
      pk[rl[Factor_Name != sprintf("GPA_%s", v)], real_icm := i.real_icm, on = c("year", "hash")]
      comp <- rl[Factor_Name == sprintf("GPA_%s", v), .(year, comp = real_icm)]
    }
    gain <- merge(pk[, .(pick_val = mean(val_ir)), by = year], gpe_random_top(tr, gcfg), by = "year", all.x = TRUE)
    charts[sprintf("진화가 보탠 것(%s)", nm)] <- gpe_plot_gain(gain, pk, v, gcfg, is_year, file.path(out_dir, sprintf("gp3_evo_%s_gain.png", v)))
    g2 <- gain[is.finite(rand_val)]
    if (nrow(g2)) lines <- c(lines, sprintf("%s · 고른 식의 검증 점수(%d개 평균 · 해 평균): 무작위 출발만 %.1f → 진화 뒤 %.1f", nm, k, mean(g2$rand_val), mean(g2$pick_val)))
    lines <- c(lines, sprintf("%s · 고른 식 %d개의 출처: 진화로 태어남 %d · 전년도에서 물려받음 %d · 무작위 출발 %d", nm, nrow(pk),
                              sum(pk$origin == "offspring", na.rm = TRUE), sum(pk$origin == "inherited", na.rm = TRUE), sum(pk$origin == "init", na.rm = TRUE)))
    ## 다음 해 실현 순위 IC — 식을 쓴 해가 표본 안인 해와 표본 밖인 해를 따로 묶는다
    yr <- merge(pk[, .(tr = mean(train_icm, na.rm = TRUE), va = mean(val_icm, na.rm = TRUE), re = mean(real_icm, na.rm = TRUE)), by = year][is.finite(re)], comp, by = "year", all.x = TRUE)
    seg <- function(d, head) if (!nrow(d)) NULL else
      sprintf("%s · 고른 식의 월별 순위 IC(%d개 평균 · %s %d개 해 평균): 학습 %.3f · 검증 %.3f · 다음 해 실현 %.3f%s", nm, k, head, nrow(d), mean(d$tr), mean(d$va), mean(d$re),
              if (any(is.finite(d$comp))) sprintf(" — 고른 식을 합친 팩터의 다음 해 실현 %.3f", mean(d$comp, na.rm = TRUE)) else "")
    lines <- c(lines, seg(yr[year + 1L <= is_year], sprintf("쓴 해 %d년까지", is_year)), seg(yr[year + 1L > is_year], sprintf("쓴 해 %d년부터 · 표본 밖", is_year + 1L)))
  }
  if (!length(charts)) return(NULL)
  list(key = key, charts = charts, headline = sprintf("수식 탐색 3판 — 진화의 효과(끝난 해: %s)", paste(prog, collapse = " · ")),
       lines = c(sprintf("끝난 해 — %s", paste(prog, collapse = " · ")), lines,
                 "검증 점수로 식을 고르므로 후보가 많을수록 최고점은 저절로 오릅니다 — 진화의 실제 효과는 다음 해 실현 값으로 봅니다"),
       guide = c(sprintf("진화 곡선 — 해마다, 그 세대까지 나온 식 가운데 학습 점수 상위 %d개의 학습 · 검증 구간 점수 평균(0세대 = 출발 집단)", GPE_TOP),
                 "진화가 보탠 것 — (가) 고른 식의 검증 점수: 무작위 출발만 대 진화 뒤 (나) 고른 식이 태어난 세대 (다) 고른 식의 순위 IC: 학습 · 검증 · 다음 해 실현",
                 "수식 탐색이 도는 동안 해가 새로 끝날 때마다 주기 통에 같은 그림이 갱신돼 실립니다"))
}
