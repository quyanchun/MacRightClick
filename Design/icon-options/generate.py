from pathlib import Path
from html import escape

OUT=Path(__file__).resolve().parent
icons=[
 ('new-file','新建文件','#3488FF', '<path d="M6 3h8l4 4v14H6z"/><path d="M14 3v5h4"/>','<path d="M9 14h6m-3-3v6"/>'),
 ('cut','剪切','#F28A40','<circle cx="6" cy="7" r="3"/><circle cx="6" cy="17" r="3"/>','<path d="M8.4 8.8L20 19M8.4 15.2L20 5"/>'),
 ('path','拷贝路径','#398EFF','<path d="M9.5 14.5l-1 1a3.5 3.5 0 0 1-5-5l4-4a3.5 3.5 0 0 1 5 0"/><path d="M14.5 9.5l1-1a3.5 3.5 0 0 1 5 5l-4 4a3.5 3.5 0 0 1-5 0"/>','<path d="M8.5 15.5l7-7"/>'),
 ('name','拷贝文件名','#A77BF4','<path d="M3 4h9l9 9-8 8-10-10z"/>','<circle cx="7" cy="8" r="1" fill="currentColor" stroke="none"/><path d="M10 12l4 4m-2-6l4 4"/>'),
 ('paste','粘贴','#26B895','<rect x="5" y="5" width="14" height="16" rx="2"/>','<rect x="8" y="3" width="8" height="4" rx="1.5"/><path d="M9 12h6m-6 4h4"/>'),
 ('terminal','终端','#55A8C9','<rect x="2.5" y="4" width="19" height="16" rx="3"/>','<path d="M7 9l3 3-3 3m7 0h3"/>'),
 ('tools','实用工具','#EAA13B','<rect x="3" y="7" width="18" height="14" rx="3"/>','<path d="M8 7V5a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2M3 12h18"/><path d="M10 11v4h4v-4"/>'),
 ('hash','校验码','#5C91EB','<path d="M9 3L6 21M18 3l-3 18"/>','<path d="M4 9h17M3 15h17"/>'),
 ('qr','二维码','#AE76E5','<path d="M3 3h6v6H3zM15 3h6v6h-6zM3 15h6v6H3z"/>','<path d="M14 13h3v4h4v4h-7z"/><path d="M21 12v2M11 4v2M11 12h-3"/>'),
 ('image','图像转换','#E174AA','<rect x="3" y="3" width="18" height="18" rx="3"/>','<circle cx="8" cy="8" r="1.4"/><path d="M4 18l5-5 3 3 4-6 5 8"/>')
]
styles=[('A','清透双色','轻巧、留白多，最接近 macOS 原生菜单。','duotone'),('B','原生彩块','统一彩色底板，功能识别更醒目。','tiles'),('C','柔光立体','渐变与高光，更有桌面工具的质感。','soft')]

def symbol(style, i, unique):
    slug,label,color,body,detail=icons[i]
    g=f'g{unique}'
    defs=f'<defs><linearGradient id="{g}" x1="0" y1="0" x2="0.9" y2="1"><stop stop-color="{color}"/><stop offset="1" stop-color="{color}" stop-opacity="0.7"/></linearGradient><linearGradient id="{g}h" x2="0" y2="1"><stop stop-color="white" stop-opacity="0.5"/><stop offset="0.7" stop-color="white" stop-opacity="0"/></linearGradient></defs>'
    if style=='duotone':
        # No enclosing tile: color describes the functional silhouette itself.
        return f'<g color="{color}" stroke="{color}" stroke-width="1.85" stroke-linecap="round" stroke-linejoin="round"><g fill="{color}" fill-opacity="0.18">{body}</g><g fill="none">{detail}</g></g>'
    if style=='tiles':
        return f'<rect x="0.75" y="0.75" width="22.5" height="22.5" rx="6" fill="{color}"/><g transform="translate(3 3) scale(.75)" fill="none" color="white" stroke="white" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round">{body}{detail}</g>'
    return defs+f'<rect x="1.5" y="2.5" width="21" height="21" rx="6" fill="#030B1A" opacity="0.3"/><rect x="1" y=".5" width="22" height="22" rx="6" fill="url(#{g})"/><rect x="1.6" y="1.1" width="20.8" height="20.8" rx="5.5" fill="url(#{g}h)" stroke="white" stroke-opacity=".5" stroke-width=".6"/><g transform="translate(3 2.5) scale(.75)" fill="none" color="white" stroke="#16304C" stroke-opacity=".25" stroke-width="2.8" stroke-linecap="round" stroke-linejoin="round">{body}{detail}</g><g transform="translate(3 2) scale(.75)" fill="none" color="white" stroke="white" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">{body}{detail}</g>'

def svg_icon(style,i):
    return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24"><title>{icons[i][1]}</title>{symbol(style,i,style+str(i))}</svg>'

for _,_,_,style in styles:
    folder=OUT/style;folder.mkdir(exist_ok=True)
    for i,icon in enumerate(icons): (folder/(icon[0]+'.svg')).write_text(svg_icon(style,i))

parts=['<svg xmlns="http://www.w3.org/2000/svg" width="1500" height="1090" viewBox="0 0 1500 1090">', '<rect width="1500" height="1090" fill="#11151C"/>']
def text(x,y,t,size=16,color='#EBEFF7',weight=400):
    parts.append(f'<text x="{x}" y="{y}" fill="{color}" font-family="PingFang SC, sans-serif" font-size="{size}" font-weight="{weight}">{escape(t)}</text>')
def rect(x,y,w,h,fill,r=0,stroke='none'):
    parts.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" fill="{fill}" stroke="{stroke}"/>')
def icon(style,i,x,y,size,uid):
    parts.append(f'<g transform="translate({x} {y}) scale({size/24})">{symbol(style,i,uid)}</g>')
text(48,49,'右键助手 / 功能图标方向',29,weight=600)
text(48,81,'同一组功能，三种表达。下方按实际尺寸展示设置行与右键菜单。',15,'#96A5BA')
text(1250,47,'DESIGN STUDY  /  01',12,'#8DA0B8',500)
for col,(letter,title,desc,style) in enumerate(styles):
    x=42+col*478
    rect(x,112,460,914,'#1B222D',24,'#303A49')
    rect(x+22,137,34,34,'#344153',10)
    text(x+32,160,letter,18,weight=700)
    text(x+70,161,title,23,weight=600)
    text(x+24,194,desc,14,'#AEBBCD')
    text(x+24,234,'图标放大预览',12,'#8295AD',600)
    for i,(_,label,_,_,_) in enumerate(icons):
        ix=x+33+(i%5)*85;iy=260+(i//5)*104
        icon(style,i,ix+11,iy,40,f'{style}{i}big')
        # Center labels for compact gallery.
        parts.append(f'<text x="{ix+31}" y="{iy+65}" text-anchor="middle" fill="#C1CDDD" font-family="PingFang SC, sans-serif" font-size="12">{label}</text>')
    text(x+24,476,'设置页 · 20 px',12,'#8295AD',600)
    rect(x+22,494,416,130,'#282D35',14)
    for j,(idx,label) in enumerate([(1,'剪切'),(2,'拷贝完整路径'),(6,'实用工具')]):
        y=509+j*38
        icon(style,idx,x+37,y,20,f'{style}{j}settings')
        text(x+70,y+15,label,14)
        rect(x+377,y+2,42,23,'#3689FF',12)
        parts.append(f'<circle cx="{x+407}" cy="{y+13.5}" r="8.5" fill="white"/>')
        if j<2: rect(x+36,y+30,386,1,'#3B414B')
    text(x+24,660,'右键菜单 · 16 px / 浅色',12,'#8295AD',600)
    rect(x+22,677,416,150,'#F1F2F5',14)
    for j,(idx,label) in enumerate([(0,'新建文件'),(2,'拷贝完整路径'),(5,'在终端中打开'),(6,'实用工具')]):
        y=690+j*31
        icon(style,idx,x+38,y+1,16,f'{style}{j}light')
        text(x+65,y+14,label,14,'#252F3E',500)
        if idx in [0,6]: text(x+410,y+14,'›',21,'#596471')
    text(x+24,864,'右键菜单 · 16 px / 深色',12,'#8295AD',600)
    rect(x+22,881,416,116,'#363B43',14,'#525A66')
    for j,(idx,label) in enumerate([(0,'新建文件'),(2,'拷贝完整路径'),(6,'实用工具')]):
        y=893+j*31
        icon(style,idx,x+38,y+1,16,f'{style}{j}dark')
        text(x+65,y+14,label,14,'#FAFBFF',500)
        if idx in [0,6]: text(x+410,y+14,'›',21,'#D7E1F0')
text(48,1060,'建议：A 更克制，B 更易辨认，C 更强调质感。选定后统一应用到设置页与 Finder 菜单。',14,'#9CAFC5')
parts.append('</svg>')
(OUT/'comparison.svg').write_text(''.join(parts))
(OUT/'preview.html').write_text('''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>右键助手 · 功能图标方案</title><style>body{margin:0;background:#11151c}img{display:block;width:100%;max-width:1500px;margin:auto}</style><img alt="三套图标方案：A 清透双色，B 原生彩块，C 柔光立体" src="comparison.svg"></html>''')
print(OUT/'comparison.svg')
