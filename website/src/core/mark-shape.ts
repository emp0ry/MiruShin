type Point = readonly [number, number];
function outline(start: Point, segments: readonly (readonly [Point, Point, Point])[]) {
    const points: number[] = [];
    let current = start;
    for (const [a,b,end] of segments) {
        for (let i = 0; i < 24; i++) {
            const t = i/24, s = 1-t;
            points.push(s*s*s*current[0]+3*s*s*t*a[0]+3*s*t*t*b[0]+t*t*t*end[0],
                s*s*s*current[1]+3*s*s*t*a[1]+3*s*t*t*b[1]+t*t*t*end[1]);
        }
        current = end;
    }
    return new Float32Array(points);
}
function markContour(start: Point, segments: readonly (readonly [Point, Point, Point])[]) {
    return Float32Array.from(outline(start,segments), (value,i) => (i%2 ? 512-value : value-512)/340);
}
function markPolygon(points: readonly Point[]) {
    return Float32Array.from(points.flat(), (value,i) => (i%2 ? 512-value : value-512)/340);
}
/** Authored contours of 新 from MiruShin's own icon, in its 1024px design space.
 * These are point-sampled vectors; the reference bitmap is never loaded by the site.
 */
export const MIRUSHIN_OUTLINES = [
    markPolygon([[323,196],[415,196],[415,245],[323,245]]),
    markPolygon([[216,244],[527,244],[527,320],[216,320]]),
    markContour([254,319],[[[259,347],[263,372],[273,396]],[[299,396],[326,396],[352,396]],[[342,378],[337,350],[332,319]],[[306,319],[280,319],[254,319]]]),
    markContour([415,319],[[[412,344],[406,369],[397,395]],[[423,395],[449,395],[475,395]],[[484,378],[489,351],[493,319]],[[467,319],[441,319],[415,319]]]),
    markPolygon([[207,395],[531,395],[531,473],[207,473]]),
    markPolygon([[329,451],[414,451],[414,829],[329,829]]),
    markPolygon([[207,514],[527,514],[527,590],[207,590]]),
    markContour([303,589],[[[276,627],[245,670],[192,714]],[[206,738],[219,763],[233,785]],[[284,753],[341,699],[392,620]],[[363,608],[333,599],[303,589]]]),
    markPolygon([[414,594],[513,660],[477,726],[390,638]]),
    markContour([560,243],[
        [[642,239],[717,219],[781,192]], [[798,216],[815,240],[831,264]],
        [[765,291],[699,309],[641,317]], [[641,343],[641,369],[641,395]],
        [[703,395],[766,395],[828,395]], [[828,421],[828,447],[828,473]],
        [[813,473],[798,473],[783,473]], [[783,591],[783,710],[783,829]],
        [[756,829],[729,829],[702,829]], [[702,710],[702,591],[702,473]],
        [[682,473],[662,473],[642,473]], [[641,637],[611,748],[548,831]],
        [[524,815],[500,799],[477,783]], [[529,706],[556,621],[560,519]],
        [[560,427],[560,335],[560,243]],
    ]),
];
