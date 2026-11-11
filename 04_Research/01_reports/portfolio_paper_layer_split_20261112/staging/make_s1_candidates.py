# -*- coding: utf-8 -*-
"""판 2 구축 S1 — 셀 엔진 · 기저 캐시의 후보판을 만든다(운영 파일은 건드리지 않는다). 판 2(2026-11-11 23시대 · 인수 세션).
사용: python -X utf8 make_s1_candidates.py <저장소 루트> <후보판을 둘 폴더>
- 줄끝(CRLF/LF)을 원본 그대로 지킨다. 치환 대상이 정확히 한 곳인지 단정한다.
- 원본 md5 가 기대값과 다르면 멈춘다(원본이 바뀌었으면 치환 지점을 다시 본다).
- 산출: <폴더>/rf_cell_engine.R · <폴더>/rf_base_cache.R

앞 판(분류 세션 de255e1ae) 대비 달라진 것:
  ① 캐시 키의 시작일 = 엔진에 실제로 넘긴 값(.rf_rp_start) — 키가 계산 조건을 그대로 적게(전에는 칸 고정 축 .START)
  ② 진단에 from_cache · 첫/끝 월말 · 엔진 파일 이름(폴더/파일)을 남긴다
  ③ 달 스냅 뒤 패널이 비면 멈춘다(조용한 무신호 방지)"""
import hashlib, os, sys

ROOT, OUT = sys.argv[1], sys.argv[2]
os.makedirs(OUT, exist_ok=True)
EXPECT = {'02_Infrastructure/reinforcement/rf_cell_engine.R': '26993a0411bf1c1132df9962578dfb8d',
          '02_Infrastructure/reinforcement/rf_base_cache.R': 'f6fef4f9eee6adfb007b0e1d97668f9f'}

def load(rel):
    raw = open(os.path.join(ROOT, rel), 'rb').read()
    md5 = hashlib.md5(raw).hexdigest()
    if md5 != EXPECT[rel]:
        raise SystemExit('원본 md5 불일치 %s: %s (기대 %s)' % (rel, md5, EXPECT[rel]))
    nl = '\r\n' if b'\r\n' in raw else '\n'
    return raw.decode('utf-8').replace('\r\n', '\n'), nl

def save(name, text, nl):
    open(os.path.join(OUT, name), 'wb').write(text.replace('\n', nl).encode('utf-8'))

def once(text, old, new, what):
    n = text.count(old)
    if n != 1:
        raise SystemExit('치환 대상이 %d곳이다(1곳이어야 한다): %s' % (n, what))
    return text.replace(old, new, 1)

# ── rf_cell_engine.R ─────────────────────────────────────────────────────────
t, nl = load('02_Infrastructure/reinforcement/rf_cell_engine.R')

# 1) 달 스냅 함수 적재 — 엔진 기저 경로(rf_base_cache.R 를 적재하는 그 분기) 안에서만.
#    엔진 머리에서 무조건 적재하면 형제 파일을 골라 복사하는 격리 루트 시험 6종이 전부 멈춘다(10-13 rf_axes.R 때의 재발 형태).
a = '  suppressMessages(source(file.path(.RF_ROOT, "02_Infrastructure/reinforcement/rf_base_cache.R")))\n'
t = once(t, a, a +
         '  suppressMessages(source(file.path(.RF_ROOT, "02_Infrastructure/reinforcement/rf_base_align.R")))   # 기저 신호 달 스냅(판 2 S1 · 2026-11-11) — 엔진 기저 경로에서만 적재\n',
         'rf_base_cache source 줄')

# 2) 패널 달력 · 측정 시작일
a = '  .rf_dt_fp <- NULL   # 메모리 RAWDATA 지문 — 첫 기저 적재 때 한 번(기저 엔진이 DT 를 건드리기 전)\n'
t = once(t, a, a +
         '  .rf_cal <- sort(unique(DT$Date))                                                   # (판 2 S1) 달 스냅용 거래일 달력 — 패널 전체\n'
         '  .rf_rp_start <- if (exists(".RP_START_DATE")) as.Date(.RP_START_DATE) else .START   # (판 2 S1) 러너가 준 측정 시작일(없으면 칸 고정 축 시작일)\n',
         '.rf_dt_fp 줄')

# 3) 캐시 키의 시작일 = 엔진에 실제로 넘긴 값
a = '                             data_fp = .rf_dt_fp, n_rows = nrow(DT), start = .START)\n'
t = once(t, a,
         '                             data_fp = .rf_dt_fp, n_rows = nrow(DT), start = .rf_rp_start)   # (판 2 S1) 키의 시작일 = 엔진에 넘긴 값(레인 시드 키와 같은 값)\n',
         '캐시 키 start 인자')

# 4) 이 적재가 캐시 적중이었나(진단용)
a = ('    if (is.null(.b)) {\n'
     '      cat(sprintf("[rf_cell_engine] 기저 캐시 미스 — 엔진 실행: %s [%s · %s]\\n",\n')
t = once(t, a, '    .rf_hit <- !is.null(.b)   # (판 2 S1) 진단용 — 이 적재가 캐시 적중이었나\n' + a, '캐시 미스 분기 머리')

# 5) 측정 시작일을 기저 엔진 환경에 넘긴다
a = '      .env$RAWDATA <- DT; .env$BM_DT <- if (exists("BM_DT")) BM_DT else NULL\n'
t = once(t, a, a +
         '      ## (판 2 S1 · 2026-11-11) 측정 시작일을 기저 엔진에 넘긴다 — 러너(run_paper_replication.R)가 레인 측정에서 넘기는 것과 같은 값.\n'
         '      ##   전에는 넘기지 않아 엔진마다 다른 기본 시작일로 떨어졌다(2005-01-01 · 자료 첫날 · 멈춤). ★측정 변경이다(결과 동일 수리 아님 —\n'
         '      ##   04_Research/01_reports/portfolio_paper_layer_split_20261112/README.md §2-1 · §6-3). 캐시 판(rf_base_cache_v3)이 주입 전 캐시를 끊는다.\n'
         '      .env$.RP_START_DATE <- .rf_rp_start\n', '.env RAWDATA 줄')

# 5b) 기저의 종류(점수 패널 | 비중)를 캐시 객체 속성으로 남긴다 — 캐시 적중 때도 진단이 알 수 있게
a = ('      .b <- .b[, .(Date, Ticker, .base_sig)]\n'
     '      if (!nrow(.b)) stop("[rf_cell_engine] 기저 엔진 산출이 비었다: ", .be)\n')
t = once(t, a, a +
         '      data.table::setattr(.b, "rf_base_kind", if (exists("FACTORS", envir = .env, inherits = FALSE)) "factors" else "portfolio_weights")   # (판 2 S1) 기저 = 점수 패널인가 비중인가(캐시에 함께 남는다)\n',
         '기저 종류 속성')

# 6) 달 스냅 + 진단
a = '    data.table::setattr(.b, "rf_base_cache_key", NULL)\n    .b\n  }\n'
t = once(t, a,
         '    .rf_kind <- attr(.b, "rf_base_kind", exact = TRUE) %||% "unknown"   # (판 2 S1) v3 캐시 · 레인 시드가 남긴 속성(없으면 unknown)\n'
         '    data.table::setattr(.b, "rf_base_cache_key", NULL)\n'
         '    ## (판 2 S1 · 2026-11-11) 달 스냅 — 기저 신호를 월말 격자에 맞춘다(rf_base_align.R). 캐시에는 엔진 원산출 그대로 두고 적재 뒤에 맞춘다.\n'
         '    ##   월말 거래일에 신호를 내는 엔진은 항등(비트 동일) · 그 밖 격자는 그 달의 마지막 신호가 월말로 온다(s ≤ d · 모수 없음).\n'
         '    .al <- rf_base_month_snap(.b, .rf_cal)\n'
         '    if (!nrow(.al$panel))\n'
         '      stop("[rf_cell_engine] 달 스냅 뒤 기저 패널이 비었다(엔진 신호일이 전부 패널 달력 뒤): ", .be)\n'
         '    .RF_DIAG$base_alignment[[paste0(basename(dirname(.be)), "/", basename(.be))]] <<-\n'
         '      c(.al$diag, list(start_injected = TRUE, start = format(.rf_rp_start), from_cache = .rf_hit, base_kind = .rf_kind,\n'
         '                       first_cell_date = format(min(.al$panel$Date)), last_cell_date = format(max(.al$panel$Date))))\n'
         '    cat(sprintf("[rf_cell_engine] base_alignment %s | 엔진 신호일 %d → 월말 %d(항등 %d · 옮김 %d · 덮임 %d · 꼬리 제외 %d) · 최대 지연 %d거래일 · 시작 %s\\n",\n'
         '                .al$diag$rule, .al$diag$n_engine_dates, .al$diag$n_cell_dates, .al$diag$n_identity, .al$diag$n_moved,\n'
         '                .al$diag$n_superseded, .al$diag$n_dropped_tail, as.integer(.al$diag$max_lag_td), format(.rf_rp_start)))\n'
         '    .al$panel\n  }\n', '.load_one 반환부')
# 7) 진단 주석 — '기존 칸 무변화' 전제가 기저가 엔진인 칸에서는 바뀐다(항상 base_alignment 를 남긴다)
a = '.RF_DIAG <- list()   # 엔진 진단(B7 전달량 · cap_core) — 비어 있으면 아무것도 쓰지 않는다(기존 칸 무변화)\n'
t = once(t, a,
         '.RF_DIAG <- list()   # 엔진 진단(B7 전달량 · cap_core · 기저 정합) — 비어 있으면 아무것도 쓰지 않는다(기저가 엔진이 아닌 칸 무변화 · 기저가 엔진인 칸은 판 2 S1 부터 항상 base_alignment 를 남긴다)\n',
         '.RF_DIAG 선언 주석')
a = '# ── 엔진 진단 파일 (2026-10-03 · B7 전달량 · cap_core) — 진단이 비어 있으면(기존 칸 전부) 아무것도 쓰지 않는다 ──\n'
t = once(t, a,
         '# ── 엔진 진단 파일 (2026-10-03 · B7 전달량 · cap_core · 2026-11-11 기저 정합 base_alignment) — 진단이 비어 있으면(기저가 엔진이 아닌 칸) 아무것도 쓰지 않는다 ──\n',
         '엔진 진단 파일 절 주석')
save('rf_cell_engine.R', t, nl)

# ── rf_base_cache.R ──────────────────────────────────────────────────────────
t, nl = load('02_Infrastructure/reinforcement/rf_base_cache.R')
t = once(t, 'RF_BASE_CACHE_VERSION <- "rf_base_cache_v2"\n',
         'RF_BASE_CACHE_VERSION <- "rf_base_cache_v3"   # v3(2026-11-11 · 판 2 S1): 셀 경로가 기저 엔진에 측정 시작일을 넘긴다 — 주입 전(v2) 캐시가 적중하지 않게 판을 올린다\n',
         '캐시 판 상수')
t = once(t, 'file = paste0("base_v2_", ', 'file = paste0("base_v3_", ', '캐시 파일 접두')
a = '  data.table::setattr(b, "rf_base_seeded_from", as.character(provenance)[1])\n'
t = once(t, a, a +
         '  data.table::setattr(b, "rf_base_kind", if (data.table::is.data.table(FACTORS)) "factors" else "portfolio_weights")   # (판 2 S1) 셀 엔진 진단 base_kind 가 읽는다\n',
         '시드 저장 기저 종류 속성')
save('rf_base_cache.R', t, nl)
print('후보판 2개 작성:', OUT)
