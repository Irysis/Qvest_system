# -*- coding: utf-8 -*-
"""Qvest paper router v4 (v10 2계층) — TODAY=20261003.
Dedup = paper_registry.json(paper_key|duplicate_of) + alpha_search_queue_done.json::processed
        + alpha_search_route_*.json 이력(이 체인이 이미 판정한 논문).
신규 2건은 전문(PDF) 대조 후 수동 판정. 백테/큐 쓰기 없음."""
import json, glob, re, collections, io

ROOT = 'stage_artifacts/paper_recharge'
TODAY = '20261003'

disc = json.load(open(f'{ROOT}/mcp_discovery_{TODAY}.json', encoding='utf-8'))
cands = disc['candidates']

# --- dedup sources -----------------------------------------------------------
reg = json.load(open('06_Registry/paper_registry.json', encoding='utf-8'))
reg_keys = {r['paper_key'] for r in reg if r.get('paper_key')}
reg_keys |= {r['duplicate_of'] for r in reg if r.get('duplicate_of')}

qd = json.load(open(f'{ROOT}/alpha_search_queue_done.json', encoding='utf-8'))
proc = {str(x) for x in qd['processed']}

judged = {}  # paper_key -> (first_date, route, verdict)
for f in sorted(glob.glob(f'{ROOT}/alpha_search_route_*.json')):
    date = re.search(r'route_(\d{8})', f).group(1)
    if date >= TODAY:
        continue
    try:
        d = json.load(open(f, encoding='utf-8'))
    except Exception:
        continue
    for p in d.get('papers', []):
        k = p.get('paper_key') or ('axv:' + str(p.get('id')))
        if k not in judged:
            judged[k] = (date, p.get('route'), p.get('verdict'))

# --- manual verdicts for the genuinely-new candidates (PDF 전문 대조) ----------
MANUAL = {
 'axv:2503.19767': dict(
   route='skip', verdict='skip',
   reason=('개별주 실현변동성 예측 정확도 연구(HAR/adaptive-Lasso/CSR/RF · US 404종 · QLIKE·MSE 손실). '
           '횡단면 수익 신호·종목 선정·비중 규칙·포트폴리오 구성이 논문에 없고(포트·백테·경제적 가치 절 부재) '
           '오버레이 적용 규칙도 제시하지 않는다 → 충실구현 대상 신호 부재. '
           '신호를 지어내는 것은 금지(batch_434). 추가로 입력이 미국 특화 대체데이터'
           '(영문 Google Trends·Wikipedia PV·애널리스트 관심·소셜·뉴스 감성 × 미국 거시발표 10종)로 KR 대응 패널 없음.')),
 'axv:2601.08571': dict(
   route='skip', verdict='skip',
   reason=('EMD-HHT 순간에너지로 Normal/High/Extreme 국면 식별 + Holo-Hilbert AME 프로파일 + '
           '수익 5분위 상태(R1~R5) 가변길이 마코프(context tree) 전이 분석. 지수 레벨 기술통계 연구로 '
           '횡단면 신호·종목 선정·비중·백테·Sharpe 가 전무(포트폴리오 구성 절 부재) → 1계층 충실구현 후보 아님. '
           'KOSPI 포함 · 국면식별 방법론으로서는 2계층(전략 로테이션) 온디맨드 레인의 참고 문헌 — '
           '해당 레인은 이 트리아지 큐를 경유하지 않는다.')),
}

papers, counts = [], collections.Counter()
for c in cands:
    k = c['paper_key']
    pid = str(c.get('arxiv_id') or '')
    if k in MANUAL:
        m = MANUAL[k]
        route, verdict, reason = m['route'], m['verdict'], m['reason']
    elif k in judged:
        date, oroute, overdict = judged[k]
        prior = overdict or oroute or 'n/a'
        marks = []
        if k in reg_keys:
            marks.append('registry')
        if pid in proc or k in proc:
            marks.append('queue_done')
        tail = (' + ' + '/'.join(marks)) if marks else ''
        route, verdict = 'skip', 'redundant'
        reason = f'redundant — 이 체인이 이미 판정(route_{date}: {prior}){tail}'
    elif k in reg_keys or pid in proc:
        route, verdict = 'skip', 'redundant'
        reason = 'redundant — registry/queue_done 기수록'
    else:
        raise SystemExit(f'UNTRIAGED candidate {k} — 수동 판정 필요')
    counts[route] += 1
    papers.append(dict(title=c['title'], id=pid, paper_key=k, source='arxiv',
                       route=route, factor_candidate=None, verdict=verdict, reason=reason))

out = {
  'date': TODAY,
  'schema_version': 'paper_router_v4',
  'generated_by': 'paper triage v4 (v10 2계층) — Q-Lead session',
  'note': ('arxiv 245건. 신규 2건(axv:2503.19767·axv:2601.08571)은 PDF 전문 대조 후 수동 판정, '
           '나머지 243건은 route 이력상 기판정 → redundant. curated seed 미처리분 0 (CSV 26 = curated_routed 26). '
           'data_pipeline_required 0 → data_pipeline_queue 무변경. 백테·큐·BOOK 쓰기 없음.'),
  'counts_by_route': {'replication': counts.get('replication', 0), 'skip': counts.get('skip', 0)},
  'n_factor_candidates': sum(1 for p in papers if p['factor_candidate']),
  'papers': papers,
}
path = f'{ROOT}/alpha_search_route_{TODAY}.json'
with io.open(path, 'w', encoding='utf-8') as fh:
    json.dump(out, fh, ensure_ascii=False, indent=1)
vc = collections.Counter(p['verdict'] for p in papers)
print('written:', path)
print('counts_by_route:', out['counts_by_route'], '| n_factor_candidates:', out['n_factor_candidates'])
print('verdicts:', dict(vc), '| total:', len(papers))
