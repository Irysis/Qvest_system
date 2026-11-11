# -*- coding: utf-8 -*-
"""판 2 구축 S1 — 3차 후보판(판단 Superfan T4 R-20261111-008 반영).
사용: python -X utf8 make_s1_cand3.py <저장소 루트> <후보판 폴더>
대상(지금 운영 파일 md5 가 기대값일 때만):
  rf_base_align.R        — 진단에 n_offcal · first_engine_date · last_engine_date(C-061 · C-063)
  rf_cell_engine.R       — 진단에 n_cell_dates_from_start(C-065)
  run_paper_replication.R — 변형 스위치(engine_vars)를 받은 실행은 기저 캐시를 시드하지 않는다(C-060)"""
import hashlib, os, sys

ROOT, OUT = sys.argv[1], sys.argv[2]
os.makedirs(OUT, exist_ok=True)
EXPECT = {'02_Infrastructure/reinforcement/rf_cell_engine.R': '1560e5d8a1dc82a62de3d9ce75267530'}

def load(rel):
    raw = open(os.path.join(ROOT, rel), 'rb').read()
    md5 = hashlib.md5(raw).hexdigest()
    if rel in EXPECT and md5 != EXPECT[rel]:
        raise SystemExit('운영 파일 md5 불일치 %s: %s' % (rel, md5))
    nl = '\r\n' if b'\r\n' in raw else '\n'
    return raw.decode('utf-8').replace('\r\n', '\n'), nl, md5

def save(name, text, nl):
    b = text.replace('\n', nl).encode('utf-8')
    open(os.path.join(OUT, name), 'wb').write(b)
    return hashlib.md5(b).hexdigest()

def once(text, old, new, what):
    n = text.count(old)
    if n != 1:
        raise SystemExit('치환 대상이 %d곳이다(1곳이어야 한다): %s' % (n, what))
    return text.replace(old, new, 1)

# ── rf_base_align.R ──────────────────────────────────────────────────────────
t, nl, m0 = load('02_Infrastructure/reinforcement/rf_base_align.R')
t = once(t,
         '#     diag  = list(rule, n_engine_dates, n_cell_dates, n_identity, n_moved, n_superseded, n_dropped_tail,\n'
         '#                  max_lag_td, median_lag_td)   (지연 = 거래일 수)\n',
         '#     diag  = list(rule, n_engine_dates, n_cell_dates, n_identity, n_moved, n_superseded, n_dropped_tail, n_offcal,\n'
         '#                  max_lag_td, median_lag_td, first_engine_date, last_engine_date)   (지연 = 거래일 수)\n'
         '#       n_superseded > 0 = 한 달에 신호가 둘 이상(주간 · 일간 격자 — 셀 경로는 월말 표본) · n_offcal > 0 = 달력에 없는 날짜의 신호\n'
         '#       (그 달 마지막 거래일 뒤 도장이면 한 달 늦게 가거나 다음 달 신호에 덮인다) — 둘 다 소비자(상설 판 코어)가 판정 전에 본다.\n',
         '계약 주석')
t = once(t,
         '  ci <- as.integer(cal)\n',
         '  ci <- as.integer(cal)\n'
         '  n_offcal <- sum(!(as.integer(E) %in% ci))                    # 거래일 달력에 없는 엔진 신호일 수\n',
         'ci 줄')
t = once(t,
         '                   n_dropped_tail = n_tail, max_lag_td = if (nrow(keep)) max(lag) else 0L,\n'
         '                   median_lag_td = if (nrow(keep)) as.numeric(stats::median(lag)) else 0))\n',
         '                   n_dropped_tail = n_tail, n_offcal = n_offcal, max_lag_td = if (nrow(keep)) max(lag) else 0L,\n'
         '                   median_lag_td = if (nrow(keep)) as.numeric(stats::median(lag)) else 0,\n'
         '                   first_engine_date = format(min(E)), last_engine_date = format(max(E))))\n',
         'diag 목록')
m1 = save('rf_base_align.R', t, nl)
print('rf_base_align.R %s -> %s' % (m0, m1))

# ── rf_cell_engine.R ─────────────────────────────────────────────────────────
t, nl, m0 = load('02_Infrastructure/reinforcement/rf_cell_engine.R')
t = once(t,
         '      c(.al$diag, list(start_injected = TRUE, start = format(.rf_rp_start), from_cache = .rf_hit, base_kind = .rf_kind,\n',
         '      c(.al$diag, list(start_injected = TRUE, start = format(.rf_rp_start), from_cache = .rf_hit, base_kind = .rf_kind,\n'
         '                       n_cell_dates_from_start = sum(unique(.al$panel$Date) >= .START),   # 칸 시작일 이후 월말 수(n_cell_dates 는 시작일 전 월말도 센다)\n',
         '진단 목록')
m1 = save('rf_cell_engine.R', t, nl)
print('rf_cell_engine.R %s -> %s' % (m0, m1))

# ── run_paper_replication.R ──────────────────────────────────────────────────
t, nl, m0 = load('02_Infrastructure/alpha_search/run_paper_replication.R')
t = once(t,
         '  if (identical(Sys.getenv("QVEST_RP_SEED_BASE_CACHE", ""), "1") && is.null(data_cutoff)) {\n',
         '  ## (2026-11-11 · 판단 T4 C-20261111-060) 변형 스위치(engine_vars)를 받은 실행은 시드하지 않는다 — 시드 키에는 변형이 없어서, 대표 변형을\n'
         '  ##   스위치로 지정한 실행의 산출이 기본 키로 심기면 셀(스위치 없이 엔진 기본값으로 돈다)이 캐시 적중 여부에 따라 다른 변형을 기저로 받는다.\n'
         '  if (identical(Sys.getenv("QVEST_RP_SEED_BASE_CACHE", ""), "1") && is.null(data_cutoff) && !length(engine_vars)) {\n',
         '시드 조건')
m1 = save('run_paper_replication.R', t, nl)
print('run_paper_replication.R %s -> %s (줄끝 %s)' % (m0, m1, 'CRLF' if nl == '\r\n' else 'LF'))
