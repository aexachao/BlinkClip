// Read-only verification of the selected existing brand. Modules are loaded from the installed skill.
import fs from 'node:fs';
import { createRequire } from 'node:module';
const require = createRequire('/Users/chrisli/.agents/skills/app-icon-gen/scripts/package.json');
const {Resvg} = require('@resvg/resvg-js');
const {PNG} = require('pngjs');
const [repo,out,decodedICNS] = process.argv.slice(2);
const render = new Resvg(fs.readFileSync(`${repo}/branding/BlinkClipAssets/ExistingBrandSource/BlinkClipIcon.origin.svg`)).render().asPng();
fs.writeFileSync(`${out}/existing-source-render.png`,render);
const actual=PNG.sync.read(fs.readFileSync(`${repo}/replica/Assets/BlinkClipIcon.png`));
const candidate=PNG.sync.read(render);
let delta=0,max=0,changed=0;
for(let i=0;i<actual.data.length;i++){const d=Math.abs(actual.data[i]-candidate.data[i]);delta+=d;max=Math.max(max,d);if(d)changed++;}
fs.writeFileSync(`${out}/source-verification.json`,JSON.stringify({size:[actual.width,actual.height],candidateSize:[candidate.width,candidate.height],changedChannels:changed,meanChannelDelta:delta/actual.data.length,maxChannelDelta:max,exactPixels:changed===0,scope:'SVG renderer comparison only; legal provenance and runtime integration not certified'},null,2));
console.log(`source pixels exact=${changed===0}, mean=${delta/actual.data.length}`);

function compare(a,b) {
  let max=0,sum=0,changed=0;
  for(let i=0;i<a.data.length;i+=4) {
    for(let c=0;c<4;c++) {
      const av=c===3?a.data[i+3]:a.data[i+c]*a.data[i+3]/255;
      const bv=c===3?b.data[i+3]:b.data[i+c]*b.data[i+3]/255;
      const d=Math.abs(av-bv);max=Math.max(max,d);sum+=d;if(d>0.01)changed++;
    }
  }
  return {maxPremultipliedDelta:max,meanPremultipliedDelta:sum/a.data.length,changedChannels:changed};
}
const overlay=new PNG({width:1024,height:1024}),diff=new PNG({width:1024,height:1024});
for(let i=0;i<actual.data.length;i+=4) {
  for(let c=0;c<3;c++) {overlay.data[i+c]=(actual.data[i+c]+candidate.data[i+c])/2;diff.data[i+c]=Math.min(255,Math.abs(actual.data[i+c]*actual.data[i+3]/255-candidate.data[i+c]*candidate.data[i+3]/255)*10);}
  overlay.data[i+3]=Math.max(actual.data[i+3],candidate.data[i+3]);diff.data[i+3]=255;
}
fs.writeFileSync(`${out}/existing-source-overlay.png`,PNG.sync.write(overlay));
fs.writeFileSync(`${out}/existing-source-diff-x10.png`,PNG.sync.write(diff));
const visible={sourceSVG:compare(actual,candidate)};
if(decodedICNS) visible.icns1024=compare(actual,PNG.sync.read(fs.readFileSync(decodedICNS)));
fs.writeFileSync(`${out}/visible-pixel-verification.json`,JSON.stringify(visible,null,2));
