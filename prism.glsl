float TMAX = 1e20;
float TMIN = 1e-10;
float NORMAL_EP = 0.001;
vec4 yellow = vec4(1.0, 1.0, 0.0, 1.0);
vec4 purple = vec4(1.0, 0.0, 1.0, 1.0);

struct Triangle {
    vec2 p0;
    vec2 p1;
    vec2 p2;
};



Triangle makeTriangle(vec2 a, vec2 b, vec2 c) {
    Triangle tri;
    tri.p0 = a;
    tri.p1 = b;
    tri.p2 = c;
    return tri;
}
struct TriangleIntersection {
    float d;
    vec2 rayDir;
    vec2 segA;
    vec2 segB;
};


void rotateTriangle(inout Triangle triangle, float radians, vec2 origin) {
    float c = cos(radians);
    float s = sin(radians);
    mat2 rot = mat2(c, -s, s,  c);
    triangle.p0 = origin + rot * (triangle.p0 - origin);
    triangle.p1 = origin + rot * (triangle.p1 - origin);
    triangle.p2 = origin + rot * (triangle.p2 - origin);
}

float sdTriangle(vec2 p, Triangle t) {
    vec2 e0 = t.p1 - t.p0, e1 = t.p2 - t.p1, e2 = t.p0 - t.p2;
    vec2 v0 = p -t.p0, v1 = p -t.p1, v2 = p -t.p2;
    vec2 pq0 = v0 - e0*clamp( dot(v0,e0)/dot(e0,e0), 0.0, 1.0 );
    vec2 pq1 = v1 - e1*clamp( dot(v1,e1)/dot(e1,e1), 0.0, 1.0 );
    vec2 pq2 = v2 - e2*clamp( dot(v2,e2)/dot(e2,e2), 0.0, 1.0 );
    float s = sign( e0.x*e2.y - e0.y*e2.x );
    vec2 d = min(min(vec2(dot(pq0,pq0), s*(v0.x*e0.y-v0.y*e0.x)),
                     vec2(dot(pq1,pq1), s*(v1.x*e1.y-v1.y*e1.x))),
                     vec2(dot(pq2,pq2), s*(v2.x*e2.y-v2.y*e2.x)));
    return -sqrt(d.x)*sign(d.y);
}

// This is from the fantastic example and writeup here:
// https://www.shadertoy.com/view/ls2Bz1
vec3 bump3y (vec3 x, vec3 yoffset)
{
	vec3 y = vec3(1.,1.,1.) - x * x;
	y = min(vec3(1.0), max(vec3(0.0), y-yoffset));
	return y;
}
vec3 spectral_zucconi(float normalizedProgress) {
    float w = normalizedProgress * 300. + 400.;
	float x = max(0.0, min(1.0, (w - 400.0)/ 300.0));

	const vec3 cs = vec3(3.54541723, 2.86670055, 2.29421995);
	const vec3 xs = vec3(0.69548916, 0.49416934, 0.28269708);
	const vec3 ys = vec3(0.02320775, 0.15936245, 0.53520021);

	return bump3y (	cs * (x - xs), ys);
}

float intersectSegment(vec2 origin, vec2 dir, vec2 a, vec2 b) {
    vec2 e = b - a;
    vec2 p = vec2(-dir.y, dir.x); // perp to rayDir

    float denom = dot(e, p);
    if (abs(denom) < 1e-8) return -1.0; // Parallel

    vec2 ao = origin - a;
    float t = dot(ao, vec2(-e.y, e.x)) / denom;
    float s = dot(ao, p) / denom;

    if (t >= 0.0 && s >= 0.0 && s <= 1.0)
        return t;

    return -1.0;
}


TriangleIntersection intersectTriangle(vec2 rayOrigin, vec2 rayDir, Triangle tri) {
    float t0 = intersectSegment(rayOrigin, rayDir, tri.p0, tri.p1);
    float t1 = intersectSegment(rayOrigin, rayDir, tri.p1, tri.p2);
    float t2 = intersectSegment(rayOrigin, rayDir, tri.p2, tri.p0);    
    TriangleIntersection t;
    t.d = TMAX;
    t.rayDir = rayDir;
    if (t0 > 0.0) {
        t.d = min(t.d, t0);
        t.segA = tri.p0;
        t.segB = tri.p1;
    }
    if (t1 > 0.0 && t1 < t.d) {
        t.d = t1;
        t.segA = tri.p1;
        t.segB = tri.p2;
    }
    if (t2 > 0.0 && t2 < t.d) {
        t.d = t2;
        t.segA = tri.p2;
        t.segB = tri.p0;
    }
    return t;
}    

vec2 getNormal(TriangleIntersection t) {
    vec2 edgeDir = normalize(t.segB - t.segA);
    vec2 normalA = vec2(-edgeDir.y, edgeDir.x);
    vec2 normalB = vec2(edgeDir.y, -edgeDir.x);
    // pick the normal opposing the ray
    return (dot(t.rayDir, normalA) < 0.0) ? normalA : normalB;
}

vec2 intersectLines(vec2 pA, vec2 vA, vec2 pB, vec2 vB) {
    float det = vA.x * vB.y - vA.y * vB.x;
    vec2 delta = pB - pA;
    if (abs(det) < 1e-8) return vec2(TMAX); // Lines are parallel
    float t = (delta.x * vB.y - delta.y * vB.x) / det;
    return pA + t * vA;
}

bool isBetween(vec2 vA, vec2 vB, vec2 vC) {
    float crossAB = vA.x * vB.y - vA.y * vB.x;
    float crossAC = vA.x * vC.y - vA.y * vC.x;
    float crossCB = vC.x * vB.y - vC.y * vB.x;
    return (crossAB > 0.0) ? (crossAC > 0.0 && crossCB > 0.0)
                           : (crossAC < 0.0 && crossCB < 0.0);
}
float angleBetween(vec2 from, vec2 to) {
    float dotVal = clamp(dot(from, to), -1.0, 1.0);
    float crossVal = from.x * to.y - from.y * to.x;
    return atan(crossVal, dotVal);
}

float fresnel(vec2 rayDir, vec2 normal, float eta) {
    float cosThetaI = clamp(dot(-rayDir, normal), 0.0, 1.0);
    float sin2ThetaT = eta * eta * (1.0 - cosThetaI * cosThetaI);
    if (sin2ThetaT > 1.0) {
        return TMAX;
    }
    float r0 = pow((1.0 - eta) / (1.0 + eta), 2.0);
    return r0 + (1.0 - r0) * pow(1.0 - cosThetaI, 5.0);
}

float distanceToLine(vec2 point, vec2 linePoint, vec2 lineDirNormalized) {
    vec2 diff = point - linePoint;
    vec2 perp = vec2(-lineDirNormalized.y, lineDirNormalized.x);
    return abs(dot(diff, perp));
}

float attenuation(float d) {
    return 0.5 / (d * d);
}

void render( out vec4 fragColor, in vec2 fragCoord, in float iTime) {
    vec2 uv = fragCoord/iResolution.xy;
    vec2 lightPosition = vec2(0, 0.5 + sin(iTime * 1.7) * 0.1);
    vec2 lightDirection = normalize(vec2(1.0, 0.02));
    Triangle triangle = makeTriangle(vec2(0.2, 0.3), vec2(0.7, 0.2), vec2(0.5, 0.7));
    rotateTriangle(triangle, iTime, vec2(0.5, 0.5));
    
    float iorMin = 1.0/1.4;
    float iorMax = 1.0/1.6;
    float lineThickness = 0.001;

    float d = sdTriangle(uv, triangle);
    vec3 c = vec3(0);//vec3(d);
    

    TriangleIntersection t = intersectTriangle(lightPosition, lightDirection, triangle); 
    
    // draw a thin beam, representing the path of the light to the first hit 
    if (length(uv - lightPosition) < t.d && distanceToLine(uv, lightPosition, lightDirection) < 0.001) {
        fragColor = vec4(1.0);
        return;
    }
    
    
    vec2 n1 = getNormal(t);
    vec2 n2 = n1;
    vec2 d1 = refract(t.rayDir, n1, iorMin);
    vec2 d2 = refract(t.rayDir, n1, iorMax);
    vec2 p1 = lightPosition + t.d * lightDirection;
    p1 += -n1 * NORMAL_EP;
    vec2 p2 = vec2(p1);
    

    float totalDistance = t.d;

    bool isInside = true;
    iorMax = 1.0/iorMax;
    iorMin = 1.0/iorMin;

    if (t.d > 100.0) {
        fragColor = vec4(0.0, 0.0, 0.0, 1.0);
        return;
    }

    bool uvInside = d < 0.0;
    // add a little color to inner edges of objects;
    if (uvInside) {
        c = vec3(pow(max(0.0, d + 0.05) * 20.0, 2.2));
    }
    for (int i=0; i<10; i++) {                    

        vec2 p = intersectLines(p1, d1, p2, d2);
        
        vec2 dir = normalize(uv - p);

        TriangleIntersection t1 = intersectTriangle(p1, d1, triangle);
        TriangleIntersection t2 = intersectTriangle(p2, d2, triangle);
        float avd = (t1.d + t2.d)/2.0;


        if (isBetween(d1, d2, dir)) {

            if ((isInside && uvInside) || (!isInside && !uvInside)) {
                float totalAngle = abs(angleBetween(d1, d2));
                float progress = abs(angleBetween(dir, d2));
                float normalizedProgress = progress/totalAngle;
                float np = normalizedProgress * normalizedProgress * normalizedProgress;
                vec3 spect = spectral_zucconi(np);
                c += spect * attenuation(totalDistance + length(uv - p1));
            }                
        }

        if (t1.d == TMAX && t2.d == TMAX) {
            break;
        }



        p1 += t1.d * t1.rayDir;
        p2 += t2.d * t2.rayDir;

        n1 = getNormal(t1);
        n2 = getNormal(t2);
        // normals are correct;

        float f0 = fresnel(mix(t1.rayDir, t2.rayDir, 0.5), mix(n1, n2, 0.5), mix(iorMin, iorMax, 0.5));
        
        if (f0 > 0.1) {
            d1 = reflect(t1.rayDir, n1);
            d2 = reflect(t2.rayDir, n2);
        } else {
            d1 = refract(t1.rayDir, n1, iorMin);
            d2 = refract(t2.rayDir, n2, iorMax);
            isInside = !isInside;
            iorMax = 1.0/iorMax;
            iorMin = 1.0/iorMin;
        }

        p1 += d1 * NORMAL_EP;
        p2 += d2 * NORMAL_EP;

        totalDistance += avd;

    }
  
    fragColor = vec4(c, 1.0);
}