function normalize(v) {
    const length = Math.hypot(v[0], v[1]);
    return length > 0 ? [v[0] / length, v[1] / length] : [0, 0];
  }
function reflect(incident, normal) {
    const dot = incident[0] * normal[0] + incident[1] * normal[1];
    return [
        incident[0] - 2 * dot * normal[0],
        incident[1] - 2 * dot * normal[1]
    ];
}

function refract(incident, normal, eta) {
    const dotNI = incident[0] * normal[0] + incident[1] * normal[1];
    const k = 1 - eta * eta * (1 - dotNI * dotNI);
    if (k < 0) {
        return null;
    } else {
        const a = eta * dotNI + Math.sqrt(k);
        return [
            eta * incident[0] - a * normal[0],
            eta * incident[1] - a * normal[1]
        ];
    }
}

export function intersectRaySegment(rayOrigin, rayDir, a, b) {
    const v1 = [rayOrigin[0] - a[0], rayOrigin[1] - a[1]];
    const v2 = [b[0] - a[0], b[1] - a[1]];
    const v3 = [-rayDir[1], rayDir[0]];
  
    const dot = v2[0] * v3[0] + v2[1] * v3[1];
    if (Math.abs(dot) < 1e-6) return null; // Parallel
  
    const t1 = (v2[0] * v1[1] - v2[1] * v1[0]) / dot;
    const t2 = (v1[0] * v3[0] + v1[1] * v3[1]) / dot;
  
    if (t1 >= 0 && t2 >= 0 && t2 <= 1) {
        const intersection = [
            rayOrigin[0] + t1 * rayDir[0],
            rayOrigin[1] + t1 * rayDir[1]
        ];
        // Compute normal of segment (perpendicular to v2)
        let normal = [-(b[1] - a[1]), b[0] - a[0]];

        // Normalize
        const len = Math.hypot(normal[0], normal[1]);
        normal = [normal[0] / len, normal[1] / len];

        // Flip normal if it's pointing in the same direction as the ray
        const dotRayNormal = rayDir[0] * normal[0] + rayDir[1] * normal[1];
        if (dotRayNormal > 0) {
            normal = [-normal[0], -normal[1]];
        }
        return {
            p: intersection,
            t: t1,
            n: normal
        };
    }
    return null;
 };


export function intersect(ro, rd, shapes) {
    let closest = null;
    var pid = null;
    for (const shape of shapes) {
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

function getRefractions(ro, rd, shapes) {
    const hit = intersect(ro, rd, shapes);

    var refractions = {
        ro: ro,
        rd: rd
    }
    if (hit == null) {
        return refractions
    }
    refractions["entry"] = {
        hit
    }
    var points = []

    var eta1 = 1.0/1.4;
    var eta2 = 1.0/1.6;

    var r1 = {
        ro: hit.p,
        rd: refract(rd, hit.n, eta1) ?? reflect(rd, hit.n)
    }
    var r2 = {
        ro: hit.p,
        rd: refract(rd, hit.n, eta2) ?? reflect(rd, hit.n)
    }

    for (var i=0; i<10; i++) {
        let hit1 = intersect(r1.ro, r1.rd, shapes);
        let hit2 = intersect(r2.ro, r2.rd, shapes);
        if (hit1 == null || hit2 == null) {
            break;
        }
        points.push([hit1.p, hit2.p]);

        eta1 = 1.0/eta1;
        eta2 = 1.0/eta2;
        r1 = {
            ro: hit1.p,
            rd: refract(r1.rd, hit1.n, eta1) ?? reflect(r1.rd, hit1.n)
        }
        r2 = {
            ro: hit2.p,
            rd: refract(r2.rd, hit1.n, eta2) ?? reflect(r2.rd, hit2.n)
        }

    }

    refractions["points"] = points;
    return refractions;
}


export function drawShapes(canvas, mouse, shapes, strokeStyle = '#000') {
    const width = canvas.width;
    const height = canvas.height;
    const ctx = canvas.getContext('2d');
    ctx.clearRect(0, 0, width, height);
    ctx.lineWidth = 1;

    // ctx.strokeStyle = '#F00';
    // ctx.beginPath();
    // ctx.arc(hit[0] * width, hit[1] * height, 40, 0, 2 * Math.PI);
    // ctx.stroke(); 

    const ro = [mouse[0]/width, 1.0 - mouse[1]/height];
    const rd = normalize([0.5 - ro[0], 0.5 - ro[1]]);
    var refractions = getRefractions(ro, rd, shapes);
  
    ctx.strokeStyle = strokeStyle
    for (const shape of shapes) {
      const points = shape.points;
  
      if (points.length < 2) continue;
  
      //ctx.beginPath();
      const [x0, y0] = points[0];
      ctx.moveTo(x0 * width, y0 * height);
  
      for (let i = 1; i < points.length; i++) {
        const [x, y] = points[i];
        ctx.lineTo(x * width, y * height);
      }

      ctx.lineTo(x0 * width, y0 * height);

      //if (shape.tag === 'polygon' || shape.tag === 'path') {
        //ctx.closePath();
      //}
      ctx.fill("evenodd");
      ctx.stroke();

      
    }
}