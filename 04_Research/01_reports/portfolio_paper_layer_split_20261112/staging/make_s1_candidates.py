# -*- coding: utf-8 -*-
"""판 2 구축 S1 — 셀 엔진 · 기저 캐시의 후보판을 만든다(운영 파일은 건드리지 않는다).
사용: python -X utf8 make_s1_candidates.py <저장소 루트> <후보판을 둘 폴더>
- 줄끝(CRLF/LF)을 원본 그대로 지킨다. 치환 대상이 정확히 한 곳인지 단정한다.
- 산출: <폴더>/rf_cell_engine.R · <폴더>/rf_base_cache.R · 원본 md5(표준 출력)"""
import hashlib, os, sys

ROOT, OUT = sys.argv[1], sys.argv[2]
os.makedirs(OUT, exist_ok=True)

def load(rel):
    raw = open(os.path.join(ROOT, rel), 'rb').read()
    nl = '\r\n' if b'\r\n' in raw else '\n'
    return raw, raw.decode('utf-8').replace('\r\n', '\n'), nl

def save(name, text, nl):
    open(os.path.join(OUT, name), 'wb').write(text.replace('\n', nl).encode('utf-8'))

def once(text, old, new, what):
    n = text.count(old)
    if n != 1:
        raise SystemExit('치환 대상이 %d곳이다(1곳이어야 한다): %s' % (n, what))
    return text.replace(old, new, 1)

# ── rf_cell_engine.R ─────────────────────────────────────────────────────────
raw, t, nl = load('02_Infrastructure/reinforcement/rf_cell_engine.R')
print('rf_cell_engine.R 원본 md5', hashlib.md5(raw).hexdigest(), '줄끝', 'CRLF' if nl == '\r\n' else 'LF')
a1 = 'suppressMessages(source(file.path(.RF_ROOT, "02_Infrastructure/reinforcement/rf_axes.R")))   # 고정 축 단정(MC5 · Σw ≤ 1)\n'
t = once(t, a1, a1 + 'suppressMessages(source(file.path(.RF_ROOT, "02_Infrastructure/reinforcement/rf_base_align.R")))   # 기저 신호 달 스냅(판 2 S1 · 2026-11-11)\n', 'rf_axes source 줄')
a0 = '  .rf_dt_fp <- NULL   # 메모리 RAWDATA 지문 — 첫 기저 적재 때 한 번(기저 엔진이 DT 를 건드리기 전)\n'
t = once(t, a0, a0 +
         '  .rf_cal <- sort(unique(DT$Date))                                                   # (판 2 S1) 달 스냅용 거래일 달력 — 패널 전체\n'
         '  .rf_rp_start <- if (exists(".RP_START_DATE")) as.Date(.RP_START_DATE) else .START   # (판 2 S1) 러너가 준 측정 시작일(없으면 칸 고정 축 시작일)\n',
         '.rf_dt_fp 줄')
a2 = '      .env$RAWDATA <- DT; .env$BM_DT <- if (exists("BM_DT")) BM_DT else NULL\n'
t = once(t, a2, a2 +
         '      ## (판 2 S1 · 2026-11-11) 측정 시작일을 기저 엔진에 넘긴다 — 러너(run_paper_replication.R)가 레인 측정에서 넘기는 것과 같은 값.\n'
         '      ##   전에는 넘기지 않아 엔진마다 다른 기본 시작일로 떨어졌다(2005-01-01 · 자료 첫날 · 멈춤). ★측정 변경이다(결과 동일 수리 아님 —\n'
         '      ##   04_Research/01_reports/portfolio_paper_layer_split_20261112/README.md §2-1 · §6-3). 캐시 판(rf_base_cache_v3)이 주입 전 캐시를 끊는다.\n'
         '      .env$.RP_START_DATE <- .rf_rp_start\n', '.env RAWDATA 줄')
a3 = '    data.table::setattr(.b, "rf_base_cache_key", NULL)\n    .b\n  }\n'
t = once(t, a3,
         '    data.table::setattr(.b, "rf_base_cache_key", NULL)\n'
         '    ## (판 2 S1 · 2026-11-11) 달 스냅 — 기저 신호를 월말 격자에 맞춘다(rf_base_align.R). 캐시에는 엔진 원산출 그대로 두고 적재 뒤에 맞춘다.\n'
         '    ##   월말 거래일에 신호를 내는 엔진은 항등(비트 동일) · 그 밖 격자는 그 달의 마지막 신호가 월말로 온다(s ≤ d · 모수 없음).\n'
         '    .al <- rf_base_month_snap(.b, .rf_cal)\n'
         '    .RF_DIAG$base_alignment[[basename(dirname(.be))]] <<- c(.al$diag, list(start_injected = TRUE, start = format(.rf_rp_start)))\n'
         '    cat(sprintf("[rf_cell_engine] base_alignment %s | 엔진 신호일 %d → 월말 %d(항등 %d · 옮김 %d · 덮임 %d · 꼬리 제외 %d) · 최대 지연 %d거래일\\n",\n'
         '                .al$diag$rule, .al$diag$n_engine_dates, .al$diag$n_cell_dates, .al$diag$n_identity, .al$diag$n_moved,\n'
         '                .al$diag$n_superseded, .al$diag$n_dropped_tail, as.integer(.al$diag$max_lag_td)))\n'
         '    .al$panel\n  }\n', '.load_one 반환부')
save('rf_cell_engine.R', t, nl)

# ── rf_base_cache.R ──────────────────────────────────────────────────────────
raw, t, nl = load('02_Infrastructure/reinforcement/rf_base_cache.R')
print('rf_base_cache.R 원본 md5', hashlib.md5(raw).hexdigest(), '줄끝', 'CRLF' if nl == '\r\n' else 'LF')
t = once(t, 'RF_BASE_CACHE_VERSION <- "rf_base_cache_v2"\n',
         'RF_BASE_CACHE_VERSION <- "rf_base_cache_v3"   # v3(2026-11-11 · 판 2 S1): 셀 경로가 기저 엔진에 측정 시작일을 넘긴다 — 주입 전(v2) 캐시가 적중하지 않게 판을 올린다\n', '캐시 판 상수')
t = once(t, 'file = paste0("base_v2_", ', 'file = paste0("base_v3_", ', '캐시 파일 접두')
save('rf_base_cache.R', t, nl)
print('후보판 2개 작성:', OUT)
