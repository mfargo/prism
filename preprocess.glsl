precision highp float;
#define M_PI 3.1415926535897932384626433832795

uniform vec2 iResolution;
uniform vec2 iTargetResolution;
uniform int iPolyCount;
uniform int iPointCount;
uniform float iTime;
uniform sampler2D iChannel0; // counts
uniform sampler2D iChannel1; // points

uniform vec4 iMouse;

const float TMAX = 1e20;
const float TMIN = 1e-10;
const vec2 dim = vec2(1.920, 0.96);
//const float NORMAL_EP = 0.00001;
const vec4 yellow = vec4(1.0, 1.0, 0.0, 1.0);
const vec4 purple = vec4(1.0, 0.0, 1.0, 1.0);

struct Hit {
    float d;
    vec2 ro;
    vec2 rd;
    vec2 p;
    vec2 n;
    int mask;
};

int segmentCount(int polyID) {
    float total = float(iPolyCount); 
    float x = (0.5 + float(polyID))/total;
    vec2 coord = vec2(x, 0.5);
    return int(texture2D(iChannel0, coord).r * 255.0);
}

vec2 point(int pointId) {
    float total = float(iPointCount);
    float x = (0.5 + float(pointId * 2))/total;
    vec2 coordx = vec2(x, 0.5);
    float y = (0.5 + float(pointId * 2 + 1))/total;
    vec2 coordy = vec2(y, 0.5);
    return vec2(texture2D(iChannel1, coordx).r, texture2D(iChannel1, coordy).r);
}


float intersectSegment(vec2 rayOrigin, vec2 rayDir, vec2 p1, vec2 p2) {
    vec2 v1 = rayOrigin - p1;
    vec2 v2 = p2 - p1;
    vec2 v3 = vec2(-rayDir.y, rayDir.x); // perpendicular to rayDir

    float denom = dot(v2, v3);
    if (abs(denom) < 1e-6) return TMAX; // parallel or nearly so

    float t1 = (v2.x * v1.y - v2.y * v1.x) / denom; // cross product / dot
    float t2 = dot(v1, v3) / denom;
    if (t1 >= 0.0 && t2 >= 0.0 && t2 <= 1.0) return t1;
    return TMAX;
}

float intersectRect(vec2 rayOrigin, vec2 rayDir) {
    vec2 tMin = (vec2(0.0) - rayOrigin) / rayDir;
    vec2 tMax = (vec2(1.0) - rayOrigin) / rayDir;

    // Choose minimum positive value for each axis
    vec2 t1 = min(tMin, tMax);
    vec2 t2 = max(tMin, tMax);

    float tNear = max(t1.x, t1.y);
    float tFar = min(t2.x, t2.y);

    // Clamp to positive direction only (we only want forward ray intersection)
    return tFar >= 0.0 ? tNear : -1.0;
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

vec2 pointOnRectEdge(float angle, vec2 rectSize) {
    // Direction from angle
    vec2 dir = vec2(cos(angle), sin(angle));
    vec2 halfSize = rectSize * 0.5;

    // Scale direction to reach edge of rectangle
    vec2 scale = halfSize / abs(dir);
    float t = min(scale.x, scale.y);

    return dir * t; // relative to center
}



// ditching path tracing for 
Hit scene(vec2 ro, vec2 rd) {
    Hit hit;
    hit.d = TMAX;
    hit.ro = ro;
    hit.rd = rd;
    int vid = 0;
    vec4 closestSeg;

    for (int shapeId = 0; shapeId < 100; shapeId++) {
        if (shapeId >= iPolyCount) {
            break;
        }
        
        int count = segmentCount(shapeId);
        vec2 firstPoint = point(vid);
        vec2 lastPoint = firstPoint;

        for (int j = 0; j < 100; j++) {
            vec2 p;
            if (j >= count) {
                p = firstPoint;
            } else {
                p = point(vid + j);
            }
            float d = intersectSegment(ro, rd, lastPoint, p);
            if (d < hit.d) {
                hit.d = d;
                closestSeg = vec4(lastPoint, p);
                hit.mask = shapeId;
            }
            if (j >= count) {
                break;
            }
            lastPoint = p;
        }
        vid += count;
    }
    if (hit.d >= TMAX) {
        return hit;
    }
    vec2 segDir = closestSeg.zw - closestSeg.xy;
    if (length(segDir) < 1e-6) {
        return hit;
    }

    hit.p = ro + hit.d * rd;

    hit.n = normalize(vec2(-segDir.y, segDir.x));
    //hit.n = normalize(vec2(-(closestSeg.w - closestSeg.y), closestSeg.z - closestSeg.x));

    if (dot(rd, hit.n) > 0.0) {
        hit.n = -hit.n;
    }
    return hit;
}


void render( out vec4 fragColor) {
    int step = int(gl_FragCoord.x - 0.5);

    vec2 lightPosition = (iMouse.xy / iResolution.xy) * dim;
    vec2 lightDirection = normalize(dim/2.0 - lightPosition);


    if (step == 0) {
        fragColor = vec4(lightPosition, lightPosition);
        return;
    }

    const float iorMin = 1.3; 
    const float iorMax = 1.6;
    float lineThickness = 0.001;

    Hit hit1;
    Hit hit2;
    hit1.ro = lightPosition + lightDirection * 0.001;
    hit1.p = hit1.ro;
    hit2.ro = hit1.ro;
    hit2.p = hit1.ro;
    hit1.rd = lightDirection;
    hit2.rd = lightDirection;

    bool inside = false;

    for (int i=0; i<20; i++) {     
                 
        if (i >= step) {
            break;
        }

        hit1 = scene(hit1.p, hit1.rd);
        hit2 = scene(hit2.p, hit2.rd);

        bool valid = hit1.mask == hit2.mask;
        if (!valid || hit1.d >= TMAX || hit2.d >= TMAX) {
            if (i == 0) {
                hit1.p = lightPosition + lightDirection * 4.0;
                hit2.p = lightPosition + lightDirection * 4.0;
                break;
            }
            else if (i == step-1) {
                hit1.p = hit1.p + hit1.rd * 4.0;
                hit2.p = hit2.p + hit2.rd * 4.0;
                break;
            } else {
                fragColor = vec4(-100.0);
                return;
            }
        }


        // float f0 = fresnel(mix(hit1.rd, hit2.rd, 0.5), mix(hit1.n, hit2.n, 0.5), mix(etaMin, etaMax, 0.5));
        
        // if (f0 > 1.0) {
        //     fragColor = vec4(0);
        //     return;
        //     hit1.rd = reflect(hit1.rd, hit1.n);
        //     hit2.rd = reflect(hit2.rd, hit2.n);
        // } else {

        // if (length(hit1.n) != 1.0 || length(hit2.n) != 1.0) {
        //     fragColor = vec4(1);
        //     return;
        // }

            float etaMin = inside ? iorMin : 1.0/iorMin;
            float etaMax = inside ? iorMax : 1.0/iorMax;

            vec2 nd1 = refract(hit1.rd, hit1.n, etaMin);
            vec2 nd2 = refract(hit2.rd, hit2.n, etaMax);

            if (length(nd2) <= 0.0 || length(nd1) <= 0.0) {
                //fragColor = vec4(0);
                //return;
                hit1.rd = reflect(hit1.rd, hit1.n);
                hit2.rd = reflect(hit2.rd, hit2.n);
            
            } else {
                inside = !inside;
                hit1.rd = nd1;
                hit2.rd = nd2;
            }
        // }
        hit1.p += hit1.rd * 0.001;
        hit2.p += hit2.rd * 0.001;
    }
    fragColor = vec4(hit1.p, hit2.p);
}

void main() {
    vec4 color;
    render(color);
    gl_FragColor = color;
}