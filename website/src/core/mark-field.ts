import { MIRUSHIN_OUTLINES } from './mark-shape.ts';
import { samplePulses, type PulseFrame } from './pulses.ts';

export const LOOP_SECONDS = 24;
export function inside(polygon: Float32Array, x: number, y: number) {
    let hit = false;
    for (let i = 0, j = polygon.length - 2; i < polygon.length; j = i, i += 2) {
        const ax = polygon[i], ay = polygon[i+1], bx = polygon[j], by = polygon[j+1];
        if ((ay > y) !== (by > y) && x < (bx-ax)*(y-ay)/(by-ay)+ax) hit = !hit;
    }
    return hit;
}
function random(value: number) { const n = Math.sin(value*127.1+311.7)*43758.5453; return n-Math.floor(n); }
/** Stratified samples stay stable through refresh. No per-frame random noise. */
export function createMarkPoints(density = 108) {
    const result: number[] = [];
    for (let row = 0; row < density; row++) for (let col = 0; col < density; col++) {
        const seed = row*density+col+1;
        const x = (col+.17+random(seed)*.66)/density*2-1;
        const y = (row+.17+random(seed+13)*.66)/density*2-1;
        if (MIRUSHIN_OUTLINES.some(polygon => inside(polygon,x,y))) result.push(x,y,random(seed+51),random(seed+87));
    }
    return new Float32Array(result);
}
export interface MarkFrame { phase: number; intro: number; pointerX: number; pointerY: number; strength: number; waves: PulseFrame }
const pulse = new Float32Array(3);
/** A shallow mathematical relief of the mark, with bounded local interaction. */
export function sampleMark(points: Float32Array, offset: number, frame: MarkFrame, out: Float32Array) {
    const bx = points[offset], by = points[offset+1], seed = points[offset+2], light = points[offset+3];
    const phase = frame.phase*Math.PI*2;
    const z = Math.sin(bx*2.5+phase)*Math.cos(by*1.8-phase)*.09;
    const tiltY = frame.pointerX*frame.strength*.12, tiltX = frame.pointerY*frame.strength*.1;
    let x = bx+z*Math.sin(phase)*.28+z*tiltY;
    let y = by+z*Math.cos(phase)*.16+z*tiltX;
    const dx = x-frame.pointerX, dy = y-frame.pointerY, distance = Math.hypot(dx,dy);
    const repulsion = Math.exp(-distance*distance/0.075)*frame.strength*.065;
    x += (dx-dy*.3)/(distance+.06)*repulsion;
    y += (dy+dx*.3)/(distance+.06)*repulsion;
    samplePulses(frame.waves,bx,by,1,2.8,.14,.085,.2,pulse);
    x += pulse[0]; y += pulse[1];
    const intro = Math.min(1,Math.max(0,frame.intro));
    const ease = 1-(1-intro)**4;
    x += Math.cos(seed*19)*(.08+seed*.32)*(1-ease);
    y += Math.sin(seed*19)*(.08+seed*.32)*(1-ease);
    out[0] = x; out[1] = y;
    out[2] = (.48+light*.32+Math.sin(bx*2+by+phase)*.1+pulse[2]*.25)*Math.min(1,intro*3);
    out[3] = 1+seed*.55+z*.8;
}
