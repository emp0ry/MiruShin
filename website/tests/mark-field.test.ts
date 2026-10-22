import test from 'node:test';
import assert from 'node:assert/strict';
import { createMarkPoints, sampleMark, type MarkFrame } from '../src/core/mark-field.ts';
import { createPulseTrain } from '../src/core/pulses.ts';
const state=():MarkFrame=>({phase:0,intro:1,pointerX:0,pointerY:0,strength:0,waves:createPulseTrain(1.7).frame});

test('mark samples are deterministic and maintain both glyph halves',()=>{
    const a=createMarkPoints(),b=createMarkPoints();assert.deepEqual(a,b);assert(a.length/4>2000);
    let left=0,right=0;for(let i=0;i<a.length;i+=4){if(a[i]<0)left++;else right++;}
    assert(left>700&&right>700);assert([...a].every(Number.isFinite));
});
test('the mark closes its loop and stays bounded during assembly and pointer interaction',()=>{
    const points=createMarkPoints(40),a=new Float32Array(4),b=new Float32Array(4),frame=state();
    for(let i=0;i<points.length;i+=4){frame.phase=0;sampleMark(points,i,frame,a);frame.phase=1;sampleMark(points,i,frame,b);for(let j=0;j<4;j++)assert(Math.abs(a[j]-b[j])<1e-5);}
    for(const phase of [0,.25,.5,.75,1])for(const intro of [0,.5,1])for(let i=0;i<points.length;i+=4){
        Object.assign(frame,{phase,intro,pointerX:points[i],pointerY:points[i+1],strength:1});sampleMark(points,i,frame,a);
        assert([...a].every(Number.isFinite));assert(Math.abs(a[0])<1.5&&Math.abs(a[1])<1.5);assert(a[2]>=0&&a[2]<1.3);
    }
});
test('repeated pulses retain earlier waves and expire back to the original mark',()=>{
    const waves=createPulseTrain(1.7),frame=state(),points=createMarkPoints(30),base=new Float32Array(4),changed=new Float32Array(4);
    frame.waves=waves.frame;sampleMark(points,0,frame,base);
    waves.push(points[0],points[1]);waves.advance(.1);const age=waves.frame.data[2];waves.push(.3,.2);
    assert.equal(waves.frame.count,2);assert.equal(waves.frame.data[2],age);
    waves.advance(.2);sampleMark(points,0,frame,changed);assert.notDeepEqual(base,changed);
    waves.advance(3);sampleMark(points,0,frame,changed);assert.deepEqual(base,changed);
});
