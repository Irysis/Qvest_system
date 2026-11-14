## 공유 등록부의 '내 명령이 만든 변화'만 스테이징한다 — 다른 세션의 미커밋 변경은 작업 트리에 그대로 둔다.
##   사용: python stage_registry_delta.py <경로(저장소 상대)> <명령 전 사본> <임시 출력>
##   before(명령 전 작업 트리 사본) → after(지금 작업 트리)의 줄 차이(줄 끝 보존)를 색인 판(git show :경로)에 문맥 일치로 옮겨 넣고
##   hash-object -w → update-index --cacheinfo. 작업 트리 파일은 건드리지 않는다. 문맥이 색인 판에서 한 곳으로 안 잡히면 중단.
import difflib, json, subprocess, sys
P, BEFORE, OUT = sys.argv[1], sys.argv[2], sys.argv[3]
rd = lambda f: open(f, encoding='utf-8', newline='').read()
before = rd(BEFORE).splitlines(keepends=True)
after = rd(P).splitlines(keepends=True)
idx_txt = subprocess.run(['git', 'show', ':' + P], capture_output=True, check=True).stdout.decode('utf-8')
idx = idx_txt.splitlines(keepends=True)
ops = [o for o in difflib.SequenceMatcher(a=before, b=after, autojunk=False).get_opcodes() if o[0] != 'equal']
print('변화 묶음', len(ops))
K = 4   # 앞 문맥 줄 수
def locate(i1, i2):
    ## before[i1:i2] 자리를 색인 판에서 찾는다: 앞 문맥 K줄 + 지울 줄 + 뒤 문맥 1줄이 한 곳에서만 맞아야 한다
    pre = before[max(0, i1 - K):i1]; body = before[i1:i2]; post = before[i2:i2 + 1]
    pat = pre + body + post
    hits = [j for j in range(len(idx) - len(pat) + 1) if idx[j:j + len(pat)] == pat]
    if len(hits) != 1: raise SystemExit('문맥 일치 %d곳 — 중단 (before %d:%d)' % (len(hits), i1, i2))
    return hits[0] + len(pre)
import re
TOPKEY = re.compile(r'^  "(version|updated_at)": ')   # 최상위 판 번호 · 갱신 시각 — 다른 세션의 미커밋 변경이 색인 판과 값을 벌려 놓는다 → 문맥 대신 키로 찾아 새 값으로 덮는다
edits = []
for tag, i1, i2, j1, j2 in ops:
    if tag == 'replace' and before[i1:i2] and all(TOPKEY.match(x) for x in before[i1:i2] + after[j1:j2]):
        for new_ln in after[j1:j2]:
            k = TOPKEY.match(new_ln).group(1)
            hit = [j for j, x in enumerate(idx) if TOPKEY.match(x) and TOPKEY.match(x).group(1) == k]
            if len(hit) != 1: raise SystemExit('최상위 키 %s 가 색인 판에서 %d곳 — 중단' % (k, len(hit)))
            edits.append((hit[0], hit[0] + 1, [new_ln], 'topkey:' + k))
        continue
    s = locate(i1, i2); edits.append((s, s + (i2 - i1), after[j1:j2], tag))
for s, e, rep, tag in sorted(edits, key=lambda x: -x[0]):
    idx[s:e] = rep
new = ''.join(idx)
json.loads(new)   # JSON 유효
crlf_new = new.count('\r\n'); lf_new = new.count('\n')
crlf_after = ''.join(after).count('\r\n'); lf_after = ''.join(after).count('\n')
assert (crlf_new == lf_new) == (crlf_after == lf_after), '줄 끝 섞임'
open(OUT, 'w', encoding='utf-8', newline='').write(new)
h = subprocess.run(['git', 'hash-object', '-w', OUT], capture_output=True, check=True).stdout.decode().strip()
subprocess.run(['git', 'update-index', '--cacheinfo', '100644,%s,%s' % (h, P)], check=True)
print('staged', P, h, '· JSON ok · 묶음', [(t, s) for s, e, r, t in edits])
