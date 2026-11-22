## aif_charts.R — 그래프와 성과표 그림. 규칙(승인 계획): 글꼴 현대하모니 M · 비교 표기 'vs' · IS/OOS 경계 2022-12-31 점선.
suppressPackageStartupMessages({ library(ggplot2); library(patchwork); library(scales); library(ragg); library(systemfonts); library(gridExtra); library(grid) })

aif_font <- function() {
  if (!is.null(.aif_env$font)) return(.aif_env$font)
  dirs <- c(file.path(Sys.getenv("LOCALAPPDATA"), "Microsoft", "Windows", "Fonts"),
            "C:/Users/99922/AppData/Local/Microsoft/Windows/Fonts", file.path(Sys.getenv("WINDIR", "C:/Windows"), "Fonts"))
  f <- file.path(dirs, "\ud604\ub300\ud558\ubaa8\ub2c8+M.ttf"); f <- f[file.exists(f)][1]
  .aif_env$font <- if (is.na(f)) "Malgun Gothic" else { systemfonts::register_font(name = "HDHM", plain = f); "HDHM" }
  .aif_env$font
}
.aif_env <- new.env()
aif_theme <- function(base = 11) theme_minimal(base_family = aif_font(), base_size = base) +
  theme(plot.title = element_text(size = base + 3, margin = margin(b = 3)), plot.subtitle = element_text(size = base - 1, colour = "#555555"),
        legend.position = "bottom", legend.title = element_blank(), panel.grid.minor = element_blank(),
        plot.caption = element_text(size = base - 3, colour = "#777777"), axis.title = element_blank())
AIF_COL <- c(factor = "#d62728", bench = "#4d4d4d", univ = "#9aa5b1", ls = "#1f77b4", net = "#ff9896")
aif_png <- function(plot, path, w = 1080, h = 1500, res = 144) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  ragg::agg_png(path, width = w, height = h, res = res, background = "white")
  if (inherits(plot, "ggplot")) print(plot) else grid::grid.draw(plot)   # 표 그림(gtable)은 grid 로 그린다
  invisible(dev.off()); path
}
aif_cum <- function(r) cumprod(1 + ifelse(is.finite(r), r, 0))
aif_pct <- function(x, d = 1) ifelse(is.finite(x), sprintf(paste0("%+.", d, "f%%"), 100 * x), "–")
aif_num <- function(x, d = 2) ifelse(is.finite(x), formatC(x, format = "f", digits = d), "–")
.aif_split_line <- function(cfg, d) { ie <- as.Date(cfg$measure$is_end); if (ie > min(d) && ie < max(d)) geom_vline(xintercept = ie, linetype = "dashed", colour = "#888888", linewidth = 0.4) else NULL }
.aif_one <- function(st, port, cst = "gross", per = "ALL") st[portfolio == port & cost == cst & period == per]   # 인자 이름은 열 이름과 겹치지 않게

## 팩터 한 장: ① 상위 분위 롱온리 vs 벤치마크 vs 유니버스 동일가중(로그축) ② 낙폭 ③ 5분위 누적수익 ④ 롱숏 누적수익 ⑤ 누적 IC
aif_chart_factor <- function(res, ref, cfg, label, out_png, note = NULL) {
  bl <- cfg$measure$benchmark_label
  D <- merge(res$daily, ref$daily, by = "Date", all.x = TRUE)
  P <- rbind(data.table(Date = D$Date, s = paste(label, "상위 분위"), v = aif_cum(D$top)),
             data.table(Date = D$Date, s = bl, v = aif_cum(D$bm)), data.table(Date = D$Date, s = "유니버스 동일가중", v = aif_cum(D$universe_ew)))
  P[, s := factor(s, levels = unique(s))]
  cols <- setNames(c(AIF_COL[["factor"]], AIF_COL[["bench"]], AIF_COL[["univ"]]), levels(P$s))
  a <- .aif_one(res$stats, "top")
  bst <- aif_stats(D$bm, D$Date, D$bm, D$rf, cfg)                       # 벤치마크도 이 팩터의 측정 구간에서 다시 잰다(시작 시점이 팩터마다 다르다)
  sub <- sprintf("상위 분위 롱온리: CAGR %s · SD %s · SR %s · MDD %s\n%s(같은 구간 %s~): CAGR %s · SD %s · SR %s · MDD %s",
                 aif_pct(a$CAGR), aif_pct(a$SD), aif_num(a$SR), aif_pct(a$MDD), bl, format(min(D$Date), "%Y-%m"),
                 aif_pct(bst$CAGR), aif_pct(bst$SD), aif_num(bst$SR), aif_pct(bst$MDD))
  p1 <- ggplot(P, aes(Date, v, colour = s)) + geom_line(linewidth = 0.55) + .aif_split_line(cfg, D$Date) + scale_y_log10(labels = label_number(accuracy = 0.1)) +
    scale_colour_manual(values = cols) + labs(title = sprintf("%s — 상위 분위 롱온리 vs %s", label, bl), subtitle = sub) + aif_theme()
  dd <- function(v) v / cummax(v) - 1
  P2 <- P[s != "유니버스 동일가중"][, dd := dd(v), by = s]
  p2 <- ggplot(P2, aes(Date, dd, colour = s)) + geom_line(linewidth = 0.45) + .aif_split_line(cfg, D$Date) + scale_y_continuous(labels = label_percent(accuracy = 1)) +
    scale_colour_manual(values = cols) + labs(title = "낙폭") + aif_theme(10) + theme(legend.position = "none")
  qn <- grep("^q[0-9]+$", names(D), value = TRUE)
  p3 <- if (length(qn)) {
    Q <- rbindlist(lapply(qn, function(q) data.table(Date = D$Date, s = sub("q", "", q), v = aif_cum(D[[q]]))))
    Q[, s := factor(paste0(s, "분위"), levels = paste0(seq_along(qn), "분위"))]
    ggplot(Q, aes(Date, v, colour = s)) + geom_line(linewidth = 0.45) + .aif_split_line(cfg, D$Date) + scale_y_log10(labels = label_number(accuracy = 0.1)) +
      scale_colour_brewer(palette = "RdYlBu", direction = -1) + labs(title = "5분위 누적수익(5분위 = 점수 상위)") + aif_theme(10)
  } else NULL
  l <- .aif_one(res$stats, "ls")
  L <- rbind(data.table(Date = D$Date, s = "거래비용 전", v = aif_cum(D$ls)), data.table(Date = D$Date, s = "편도 15bp 차감", v = aif_cum(D$ls_net)))
  p4 <- ggplot(L, aes(Date, v, colour = s)) + geom_line(linewidth = 0.5) + .aif_split_line(cfg, D$Date) + scale_y_log10(labels = label_number(accuracy = 0.1)) +
    scale_colour_manual(values = c("거래비용 전" = AIF_COL[["ls"]], "편도 15bp 차감" = AIF_COL[["net"]])) +
    labs(title = sprintf("상위−하위 롱숏 누적수익(CAGR %s · SR %s · MDD %s)", aif_pct(l$CAGR), aif_num(l$SR), aif_pct(l$MDD))) + aif_theme(10)
  I <- copy(res$ic_monthly)[, cum := cumsum(IC)]
  i1 <- res$ic[horizon_m == 1L & period == "ALL"]
  p5 <- ggplot(I, aes(Date, cum)) + geom_line(colour = "#2ca02c", linewidth = 0.5) + .aif_split_line(cfg, I$Date) +
    labs(title = sprintf("누적 순위 IC(평균 %s · ICIR %s · t %s)", aif_num(i1$IC, 3), aif_num(i1$ICIR), aif_num(i1$IC_t, 1)), caption = note) + aif_theme(10)
  pl <- Filter(Negate(is.null), list(p1, p2, p3, p4, p5)); hs <- c(3.2, 1.3, if (!is.null(p3)) 2.4, 2.0, 1.4)
  aif_png(wrap_plots(pl, ncol = 1, heights = hs), out_png, w = 1080, h = if (!is.null(p3)) 2150 else 1650)
}

## 여러 팩터를 한 장에 격자로 — 팩터마다 상위 분위 롱온리 vs 벤치마크(로그축). 한 장에 n_per 개.
aif_chart_grid <- function(res_list, labels, ref, cfg, out_prefix, n_per = 6L, what = c("top", "ls")) {
  what <- match.arg(what); bl <- cfg$measure$benchmark_label; ids <- names(res_list)
  pages <- split(ids, ceiling(seq_along(ids) / n_per)); out <- character(0)
  for (pg in seq_along(pages)) {
    P <- rbindlist(lapply(pages[[pg]], function(id) {
      D <- merge(res_list[[id]]$daily, ref$daily, by = "Date", all.x = TRUE); st <- .aif_one(res_list[[id]]$stats, what)
      ttl <- sprintf("%s\nCAGR %s · SR %s · MDD %s", labels[[id]], aif_pct(st$CAGR), aif_num(st$SR), aif_pct(st$MDD))
      if (what == "top") rbind(data.table(f = ttl, Date = D$Date, s = "팩터 상위 분위", v = aif_cum(D$top)), data.table(f = ttl, Date = D$Date, s = bl, v = aif_cum(D$bm)))
      else data.table(f = ttl, Date = D$Date, s = "상위−하위 롱숏", v = aif_cum(D$ls))
    }))
    P[, f := factor(f, levels = unique(f))]
    cols <- if (what == "top") setNames(c(AIF_COL[["factor"]], AIF_COL[["bench"]]), c("팩터 상위 분위", bl)) else c("상위−하위 롱숏" = AIF_COL[["ls"]])
    g <- ggplot(P, aes(Date, v, colour = s)) + geom_line(linewidth = 0.45) + facet_wrap(~f, ncol = 2, scales = "free") +
      geom_vline(xintercept = as.Date(cfg$measure$is_end), linetype = "dashed", colour = "#888888", linewidth = 0.3) +
      scale_y_log10(labels = label_number(accuracy = 0.1)) + scale_colour_manual(values = cols) +
      labs(title = if (what == "top") sprintf("신규 팩터 P/L — 상위 분위 롱온리 vs %s (%d/%d)", bl, pg, length(pages)) else sprintf("신규 팩터 P/L — 상위−하위 롱숏 (%d/%d)", pg, length(pages)),
           subtitle = "로그축 · 점선 = IS/OOS 경계(2022-12-31) · 거래비용 전") + aif_theme(10) + theme(strip.text = element_text(size = 9, hjust = 0))
    out <- c(out, aif_png(g, sprintf("%s_%s_%02d.png", out_prefix, what, pg), w = 1080, h = 380 + 420 * ceiling(length(pages[[pg]]) / 2)))
  }
  out
}

## 성과표를 그림으로(모바일에서 글자 표는 2열까지만 보인다) — 한 장에 rows_per 줄
##   글자 열은 왼쪽, 숫자 열은 오른쪽으로 맞춘다. 정렬 값은 칸 수만큼(열 우선 순서) 넘겨야 한다 —
##   gridExtra 는 짧은 벡터를 '줄' 단위로 되풀이해서, 열 수만큼만 넘기면 몇 줄마다 한 줄씩 정렬이 뒤집힌다.
aif_table_png <- function(dt, out_prefix, title, rows_per = 28L, hl_rows = NULL, note = NULL) {
  dt <- as.data.frame(dt, check.names = FALSE); n <- nrow(dt); nc <- ncol(dt)
  pages <- split(seq_len(n), ceiling(seq_len(n) / rows_per)); out <- character(0)
  numlike <- vapply(dt, function(v) all(grepl("^[-+\u2212\u2013]?[0-9][0-9.,]*%?( \\([0-9]+\uc704\\))?$|^\u2013$|^[0-9]+ / [0-9]+$|^[0-9]{4}-[0-9]{2}$|^$", as.character(v))), TRUE)
  hj <- ifelse(numlike, 1, 0); xx <- ifelse(numlike, 0.97, 0.03)
  for (pg in seq_along(pages)) {
    idx <- pages[[pg]]; nr <- length(idx)
    fill <- rep(c("#ffffff", "#f5f7fa"), length.out = nr); if (!is.null(hl_rows)) fill[idx %in% hl_rows] <- "#fde9e7"
    th <- ttheme_minimal(base_size = 10, base_family = aif_font(),
                         core = list(bg_params = list(fill = rep(fill, times = nc), col = NA), fg_params = list(hjust = rep(hj, each = nr), x = rep(xx, each = nr))),
                         colhead = list(bg_params = list(fill = "#2f3b4a", col = NA), fg_params = list(col = "white", fontface = "plain")))
    g <- tableGrob(dt[idx, , drop = FALSE], rows = NULL, theme = th)
    g$vp <- viewport(y = 1, just = "top", height = sum(g$heights))                       # 표를 제목 바로 아래에 붙인다
    ragg::agg_capture(width = 1080, height = 400, res = 144)                              # 표의 실제 크기를 재서 그림 크기를 정한다(열이 많으면 넓어진다)
    tw <- convertWidth(sum(g$widths), "inches", valueOnly = TRUE) * 144; thh <- convertHeight(sum(g$heights), "inches", valueOnly = TRUE) * 144
    invisible(dev.off())
    ttl <- textGrob(if (length(pages) > 1L) sprintf("%s (%d/%d)", title, pg, length(pages)) else title, x = 0.02, hjust = 0, gp = gpar(fontfamily = aif_font(), fontsize = 13))
    nt <- if (is.null(note)) nullGrob() else textGrob(note, x = 0.02, hjust = 0, gp = gpar(fontfamily = aif_font(), fontsize = 8.5, col = "#666666"))
    nl <- if (is.null(note)) 0.3 else 1.4 + 1.1 * lengths(regmatches(note, gregexpr("\n", note)))
    out <- c(out, aif_png(arrangeGrob(ttl, g, nt, ncol = 1, heights = unit.c(unit(2.6, "lines"), unit(1, "null"), unit(nl, "lines"))),
                          sprintf("%s_%02d.png", out_prefix, pg), w = max(1080, ceiling(tw) + 60), h = ceiling(thh + (2.6 + nl) * 28.8) + 16))
  }
  out
}
