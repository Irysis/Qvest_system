import urllib.request, urllib.error, re, ssl, html
CTX = ssl.create_default_context(); CTX.check_hostname=False; CTX.verify_mode=ssl.CERT_NONE
def get(u):
    r = urllib.request.Request(u, headers={"User-Agent":"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120 Safari/537.36",
        "Accept":"text/html,application/xhtml+xml","Accept-Language":"ko-KR,ko;q=0.9"})
    try:
        with urllib.request.urlopen(r, timeout=40, context=CTX) as f:
            return f.status, f.read().decode("utf-8","replace")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8","replace")
    except Exception as e:
        return -1, "EXC %s" % e

def txt(h):
    h = re.sub(r"<script.*?</script>", " ", h, flags=re.S|re.I)
    h = re.sub(r"<style.*?</style>", " ", h, flags=re.S|re.I)
    h = re.sub(r"<[^>]+>", " ", h)
    return re.sub(r"\s+"," ", html.unescape(h)).strip()

for pk in ["15101609","15100475"]:
    st, h = get("https://www.data.go.kr/data/%s/openapi.do" % pk)
    print("##### pk=%s HTTP=%s len=%d" % (pk, st, len(h)))
    if st != 200: continue
    t = txt(h)
    for kw in ["요청주소","엔드포인트","http://apis","https://apis","오퍼레이션","활용신청","자동승인","심의승인","조회기간","일일","트래픽","시작년월","hsSgn","strtYymm","기간"]:
        for m in re.finditer(re.escape(kw), t):
            s=max(0,m.start()-120); print("   [%s] ...%s..." % (kw, t[s:m.start()+220]))
            break
    print()
