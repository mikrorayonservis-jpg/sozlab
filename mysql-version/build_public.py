#!/usr/bin/env python3
"""SözLab MySQL versiyası üçün public/ qovluğunu qurur.

Mənbə: əsas sayt (Supabase versiyası) — ona TOXUNULMUR.
Nəticə: sozlab-server/public/  (Node server bu qovluğu sayt kimi verir)

Dəyişikliklər:
  • supabase-js CDN importu → ./sozlab-api.js (öz serverimizə gedən müştəri)
  • SUPABASE_URL / SUPABASE_KEY → boş (eyni sayt, açar lazım deyil)
  • sw.js: /api/ və /storage/ sorğularına toxunmasın, keş adı yenilənir
İstifadə:  SITE_URL=https://domeniniz python3 build_public.py [mənbə_qovluq]
"""
import os, re, shutil, sys

HERE = os.path.dirname(os.path.abspath(__file__))
def default_src():
    # PC-də: mysql-version/ əsas saytın (sozlab-main) içindədir → ../index.html
    for c in (os.path.join(HERE, '..'), os.path.join(HERE, '..', 'sozlab')):
        if os.path.exists(os.path.join(c, 'index.html')):
            return c
    sys.exit('index.html tapılmadı — yolu göstərin: python3 build_public.py <qovluq>')
SRC = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else default_src())
OUT = os.path.join(HERE, 'sozlab-server', 'public')

def must_sub(pattern, repl, s, what, count=1):
    new, n = re.subn(pattern, repl, s, count=count)
    if n != count:
        sys.exit(f'XƏTA: "{what}" tapılmadı (gözlənilən {count}, tapılan {n}) — index.html dəyişib?')
    return new

html = open(os.path.join(SRC, 'index.html'), encoding='utf-8').read()
html = must_sub(r"import\{createClient\}from'https://cdn\.jsdelivr\.net/npm/@supabase/supabase-js/\+esm';",
                "import{createClient}from'./sozlab-api.js?v=1';", html, 'supabase importu')
html = must_sub(r"const SUPABASE_URL='[^']*';", "const SUPABASE_URL='';   // eyni sayt — Node.js server", html, 'SUPABASE_URL')
html = must_sub(r"const SUPABASE_KEY='[^']*';", "const SUPABASE_KEY='';   // MySQL versiyasında açar lazım deyil", html, 'SUPABASE_KEY')
html = html.replace('Supabase-də hər hansı problem olsa belə', 'serverdə hər hansı problem olsa belə')
# Saytın ünvanı (SEO): SITE_URL=https://sayt.az python3 build_public.py
site = os.environ.get('SITE_URL', '').rstrip('/')
if site:
    html = html.replace('https://sozlab205.vercel.app/', site + '/')
    html = html.replace('sozlab205.vercel.app', re.sub(r'^https?://', '', site))
else:   # ünvan bilinmirsə köhnə (Vercel) ünvanını göstərmə
    html = re.sub(r'<link rel="canonical"[^>]*>\n?', '', html)
    html = re.sub(r'<meta property="og:url"[^>]*>\n?', '', html)
if 'supabase.co' in html or 'eyJhbGci' in html:
    sys.exit('XƏTA: Supabase ünvanı/açarı hələ də qalıb')

os.makedirs(OUT, exist_ok=True)          # mövcud fayllar üzərinə yazılır (silinmir)
open(os.path.join(OUT, 'index.html'), 'w', encoding='utf-8').write(html)
shutil.copy(os.path.join(HERE, 'client', 'sozlab-api.js'), os.path.join(OUT, 'sozlab-api.js'))

sw = open(os.path.join(SRC, 'sw.js'), encoding='utf-8').read()
sw = must_sub(r"const CACHE_NAME = '([^']*)';", r"const CACHE_NAME = '\1-mysql';", sw, 'CACHE_NAME')
sw = must_sub(r"(  if \(url\.origin !== self\.location\.origin\) return;[^\n]*\n)",
              r"\1  if (url.pathname.startsWith('/api/')) return;       // server API — həmişə canlı, keşlənmir\n",
              sw, 'origin yoxlaması')
sw = sw.replace("const CACHE_FIRST = [/^\\/data\\//,", "const CACHE_FIRST = [/^\\/storage\\//, /^\\/data\\//,")
sw = sw.replace("const SHELL_FILES = ['/', '/index.html', '/manifest.json'];",
                "const SHELL_FILES = ['/', '/index.html', '/manifest.json', '/sozlab-api.js?v=1'];")
open(os.path.join(OUT, 'sw.js'), 'w', encoding='utf-8').write(sw)

for f in ['manifest.json', 'word_pool.json']:
    if os.path.exists(os.path.join(SRC, f)):
        shutil.copy(os.path.join(SRC, f), os.path.join(OUT, f))
for d in ['icons', 'school205', 'data']:
    if os.path.isdir(os.path.join(SRC, d)):
        shutil.copytree(os.path.join(SRC, d), os.path.join(OUT, d), dirs_exist_ok=True)

total = sum(os.path.getsize(os.path.join(r, f)) for r, _, fs in os.walk(OUT) for f in fs)
print(f'public/ hazırdır: {OUT}  ({total/1e6:.1f} MB)')
