import urllib.request, urllib.error, re, ssl
CTX = ssl.create_default_context(); CTX.check_hostname = False; CTX.verify_mode = ssl.CERT_NONE

def get(u, data=None, hdr=None):
    h = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120 Safari/537.36",
         "Accept": "*/*", "Accept-Language": "ko-KR", "Referer": "https://www.data.go.kr/"}
    if hdr: h.update(hdr)
    r = urllib.request.Request(u, data=data, headers=h)
    try:
        with urllib.request.urlopen(r, timeout=40, context=CTX) as f:
            return f.status, f.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8", "replace")
    except Exception as e:
        return -1, "EXC %s" % e

st, h = get("https://www.data.go.kr/data/15101609/openapi.do")
print("page HTTP", st, len(h))
open("pk15101609.html", "w", encoding="utf-8").write(h)

for m in sorted(set(re.findall(r'https?://apis\.data\.go\.kr[^\s"\'<>]*', h))):
    print("  URL-in-page:", m)

for name, pat in [("detailPk", r'publicDataDetailPk[\'"]?\s*[:=]\s*[\'"]?([\w\-]+)'),
                  ("dataPk",   r'publicDataPk[\'"]?\s*[:=]\s*[\'"]?(\d+)'),
                  ("ajax",     r'select\w+\.do'),
                  ("ops",      r'\b(get[A-Za-z]{3,40}List)\b'),
                  ("openapi",  r'openApi\w+')]:
    f = list(dict.fromkeys(re.findall(pat, h, flags=re.I)))
    if f: print("  %-9s -> %s" % (name, f[:14]))
