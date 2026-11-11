# -*- coding: utf-8 -*-
"""개수 자료 병합 — 엔진별로 (기저 캐시 · 새 축 레인 보유 · L1 원장의 레인 보유) 세 출처의 날짜별 종목 개수를 한 표로.
입력(작업 폴더): engine_static.json · cache_counts.json · engine_runs.json(map_artifacts.py) · engine_l1.json(map_l1.py) · engine_meta.json(merge_meta.py)
출력: engine_counts_merged.json  (성과 수치 없음 — 개수 · 날짜 간격 · 신고 구성 · 인계 프로그램뿐)
사용: python -X utf8 merge_counts.py <작업 폴더>
     + 판 1 입구 건식 스캔 표 줄이기: python -X utf8 merge_counts.py <작업 폴더> --scan <scan --out 파일> <출력 json>
"""
import json, os, sys

S = sys.argv[1]

def rj(name):
    with open(os.path.join(S, name), encoding='utf-8') as f:
        return json.load(f)

if len(sys.argv) >= 5 and sys.argv[2] == '--scan':
    d = json.load(open(sys.argv[3], encoding='utf-8'))
    T = d['table']
    if isinstance(T, dict):                                   # 열 묶음 꼴 → 행 목록
        ks = list(T.keys()); n = len(T[ks[0]]); T = [{k: T[k][i] for k in ks} for i in range(n)]
    keep = ('dir', 'status', 'reasons', 'outputs', 'orientation', 'program', 'where', 'has_short', 'fidelity', 'audit_item', 'audit_file', 'paper_key')
    out = {'source': 'round.sh P1S01_standing_qualification scan --dry-run (쓰기 없음)', 'at': d.get('at'), 'round_id': d.get('round_id'),
           'rows': [{k: r.get(k) for k in keep} for r in T]}
    json.dump(out, open(sys.argv[4], 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
    print('scan rows', len(out['rows']))
    sys.exit(0)

st = {r['dir']: r for r in rj('engine_static.json') if r.get('has_engine')}
cc = {r['dir']: r for r in rj('cache_counts.json')}
runs = rj('engine_runs.json'); l1 = rj('engine_l1.json')
meta = {m['dir']: m for m in rj('engine_meta.json')}
rows = {}
for d in sorted(st):
    c = cc.get(d) or {}; r = runs.get(d) or {}; l = l1.get(d) or {}
    cache = None
    if c.get('cache') and not c.get('err'):
        cache = dict(nD=c['n_dates'], names=[c['all_min'], c['all_med'], c['all_max']], pos=[c['pos_min'], c['pos_med'], c['pos_max']],
                     gap_td=[c['gap_min'], c['gap_med'], c['gap_max']], n_me=c['n_me'], me=[c['me_min'], c['me_med'], c['me_max']],
                     n_me_ge50=c['n_me_ge50'], neg_dates=c['n_dates_with_neg'])
    lane = None
    h = r.get('holdings') or None
    if h and not h.get('err'):
        last = r.get('last') or {}
        lane = dict(axis=r.get('epoch') or ('구 축' if last.get('universe') != 'ALL_HYG' else 'ALL_HYG'), univ=last.get('universe'), nD=h['n_dates'],
                    names=h['names'], long=h['long'], gap_cd=h['gap_cal_days'], noLong=h['n_dates_no_long'],
                    es=(r.get('es') or {}).get('status'), basis=(r.get('es') or {}).get('basis'))
    old = None
    h2 = l.get('holdings') or None
    if h2 and not h2.get('err'):
        sp = l.get('spec') or {}
        old = dict(univ=sp.get('universe'), cons=sp.get('construction'), nD=h2['n_dates'], names=h2['names'], long=h2['long'],
                   gap_cd=h2['gap_cal_days'], noLong=h2['n_dates_no_long'])
    rows[d] = dict(out=st[d]['outputs'], cons=(meta[d].get('portfolio_spec') or {}).get('construction'), cache=cache, lane=lane, l1=old,
                   prog=(meta[d].get('handoff') or {}).get('program'), where=(meta[d].get('handoff') or {}).get('where'))
json.dump(rows, open(os.path.join(S, 'engine_counts_merged.json'), 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
print('engines', len(rows))
