export function intersectRaySegment(rayOrigin, rayDir, a, b) {
    const v1 = [rayOrigin[0] - a[0], rayOrigin[1] - a[1]];
    const v2 = [b[0] - a[0], b[1] - a[1]];
    const v3 = [-rayDir[1], rayDir[0]];
  
    const dot = v2[0] * v3[0] + v2[1] * v3[1];
    if (Math.abs(dot) < 1e-6) return null; // Parallel
  
    const t1 = (v2[0] * v1[1] - v2[1] * v1[0]) / dot;
    const t2 = (v1[0] * v3[0] + v1[1] * v3[1]) / dot;
  
    if (t1 >= 0 && t2 >= 0 && t2 <= 1) {
      return [
        rayOrigin[0] + t1 * rayDir[0],
        rayOrigin[1] + t1 * rayDir[1],
        t1
      ];
    }
    return null;
 };


export function intersect(ro, rd, data) {
    let closest = null;
    var pid = null;
    for (const shape of data.closed) {
        const pts = shape.points;
        for (let i = 0; i < pts.length; i++) {
            const a = pts[i];
            const b = pts[(i + 1) % pts.length]; // wrap for polygons
            const hit = intersectRaySegment(ro, rd, a, b);
            if (hit && (!closest || hit[2] < closest[2])) {
                closest = hit;
                pid = i;
            }
        }
    }
    return closest;
};