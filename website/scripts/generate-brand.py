"""Create an outlined Geist social SVG and rasterize it with ImageMagick 7.
Requires fonttools[woff]. Run from website/: python3 scripts/generate-brand.py
"""
from pathlib import Path
from fontTools.ttLib import TTFont
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.varLib.instancer import instantiateVariableFont
import subprocess,json
source=TTFont('src/public/site/fonts/Geist.woff2');cmap=source.getBestCmap();upm=source['head'].unitsPerEm
fonts={w:instantiateVariableFont(source,{'wght':w},inplace=False).getGlyphSet() for w in [500,600,900]}
def text(value,x,y,size,weight=500,fill='#f4f2f7',tracking=-.025):
 glyphs=fonts[weight];advance=0;paths=[]
 for character in value:
  name=cmap[ord(character)];pen=SVGPathPen(glyphs);glyphs[name].draw(pen)
  paths.append(f'<path transform="translate({advance:.2f})" d="{pen.getCommands()}"/>');advance+=glyphs[name].width+tracking*upm
 return f'<g fill="{fill}" transform="translate({x} {y}) scale({size/upm} {-size/upm})">'+''.join(paths)+'</g>'
points=json.loads(subprocess.check_output(['node','--input-type=module','-e',"import {createMarkPoints} from './src/core/mark-field.ts';process.stdout.write(JSON.stringify(Array.from(createMarkPoints(88))));"],text=True))
mark=''.join(f'<circle cx="{912+points[i]*184:.2f}" cy="{320-points[i+1]*184:.2f}" r="{.7+points[i+2]*.25:.2f}" opacity="{.5+points[i+3]*.4:.2f}"/>' for i in range(0,len(points),4))
parts=['<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="630" viewBox="0 0 1200 630"><title>MiruShin — Find your next. Keep your place.</title><rect width="1200" height="630" fill="#09090d"/>',
 text('emp0ry.',64,68,27,900,tracking=-.07),text('/ MIRUSHIN',193,66,12,500,fill='#aaa6b5',tracking=.03),
 f'<g fill="#b7a0e5">{mark}</g>',
 text('MiruShin',64,254,92,600,tracking=-.055),text('Find your next.',68,327,37,500),text('Keep your place.',68,375,37,500,fill='#b7a0e5'),
 '<path d="M64 490H1136" stroke="#c7bcda" stroke-opacity=".24"/>',
 text('Windows   macOS   Linux   Android   iOS   TV',68,540,16,500,fill='#aaa6b5'),text('mirushin.emp0ry.com',914,540,15,500,fill='#cbb6ef'),'</svg>']
Path('design/social-preview.svg').write_text('\n'.join(parts))
subprocess.run(['magick','-background','#09090d','design/social-preview.svg','-depth','8','../docs/assets/social-preview.png'],check=True)
print('Generated design/social-preview.svg and docs/assets/social-preview.png')
