precision highp float;
#define M_PI 3.1415926535897932384626433832795

uniform vec2 iResolution;
uniform vec2 iTextureSize;
uniform float iTime;
uniform sampler2D iChannel0;
uniform vec4 iMouse;

const float TMAX = 1e20;
const float TMIN = 1e-10;
//const float NORMAL_EP = 0.00001;
const vec4 yellow = vec4(1.0, 1.0, 0.0, 1.0);
const vec4 purple = vec4(1.0, 0.0, 1.0, 1.0);
const int MAX_STEPS = 30;

struct Hit {
    float d;
    vec2 ro;
    vec2 rd;
    vec2 p;
    vec2 n;
    int mask;
};


float rand(vec2 n) { 
	return fract(sin(dot(n, vec2(12.9898, 4.1414))) * 43758.5453);
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



vec2 intersectLines(Hit a, Hit b) {
    float determinate = a.rd.x * b.rd.y - a.rd.y * b.rd.x;
    vec2 delta = b.ro - a.ro;
    if (abs(determinate) < 1e-8) return vec2(TMAX); // Lines are parallel
    float t = (delta.x * b.rd.y - delta.y * b.rd.x) / determinate;
    return a.ro + t * a.rd;
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
    return 0.1 / (d * d);
}

float map(vec2 p) {
    return texture2D(iChannel0, p).b;
}


// I think I need to use inside parameter after all
Hit pathtrace(vec2 ro, vec2 rd, vec2 texelSize) {
    Hit hit;
    hit.d = length(texelSize);
    hit.ro = ro;
    hit.rd = rd;
    vec4 maskSample = texture2D(iChannel0, hit.ro + hit.rd * hit.d);
    hit.mask = int(maskSample.a);

    float d = TMAX;
    for (int i = 0; i < MAX_STEPS; ++i) {
        vec2 p = ro + rd * hit.d;
        d = abs(map(p));
        if (d < 0.0001) break;
        hit.d += d;
        if (hit.d > 2.0) break; // max distance of 2 for now;
    }
    hit.p = ro + rd * hit.d;

    // using central differences;
    float dx = map(hit.p + vec2(texelSize.x, 0)) - 
                map(hit.p - vec2(texelSize.x, 0));
    float dy = map(hit.p + vec2(0, texelSize.y)) - 
                map(hit.p - vec2(0, texelSize.y));
    vec2 grad = vec2(dx, dy) * 0.5;
    hit.n = normalize(grad);


    // vec2 grad = vec2(0.0);
    // float w = 1.0 / 9.0;
    // for (int x = -1; x <= 1; ++x) {
    //     for (int y = -1; y <= 1; ++y) {
    //         vec2 offset = vec2(x, y) * texelSize;
    //         grad += texture2D(iChannel0, hit.p + offset).rg * w;
    //     }
    // }
    // hit.n = normalize(grad);

    //vec4 normalSample =  texture2D(iChannel0, hit.p);
    //hit.n = normalize(normalSample.rg);

    return hit;
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

void render( out vec4 fragColor) {

    vec2 uv = gl_FragCoord.xy / iResolution.xy;
    vec2 mouseNorm = iMouse.xy / iResolution.xy;
    vec2 mouseCentered = mouseNorm - vec2(0.5);
    float mouseAngle = atan(mouseCentered.y, mouseCentered.x);
    vec2 lightPosition = pointOnRectEdge(mouseAngle, vec2(1, 1)) + vec2(0.5);
    
    vec2 texelSize = vec2(1.0)/iResolution.xy;
    vec4 uvSample = texture2D(iChannel0, uv);
    int uvMask = int(uvSample.a);

    float lightAngle = -mouseAngle;
    vec2 lightDirection = normalize(mouseNorm - lightPosition);
    
    float iorMin = 1.0/1.4;
    float iorMax = 1.0/1.65;
    float lineThickness = 0.001;


    float d = uvSample.b;


    Hit hit1 = pathtrace(lightPosition, lightDirection, texelSize);
    vec3 c = vec3(0);//vec3(d);

    
    // don't need to run this on every pixel but for now:    
    // draw a thin beam, representing the path of the light to the first hit 
    if (length(uv - lightPosition) < hit1.d
        && distanceToLine(uv, hit1.ro, hit1.rd) < 0.001) {
        c = vec3(rand(uv));
        fragColor = vec4(c, 1.0);
        return;
    }

    float etaMin = (hit1.mask == 0) ? iorMin : 1.0/iorMin;
    float etaMax = (hit1.mask == 0) ? iorMax : 1.0/iorMax;

    hit1.rd = refract(hit1.rd, hit1.n, etaMin);
    Hit hit2 = hit1;
    hit2.rd = refract(hit2.rd, hit2.n, etaMax);
    
    

    float totalDistance = hit1.d;

    if (hit1.d > 100.0) {
        fragColor = vec4(0.0, 0.0, 0.0, 1.0);
        return;
    }

    bool uvInside = d < 0.0;
    // add a little color to inner edges of objects;
    if (uvInside) {
        c = vec3(pow(max(0.0, d + 0.02) * 40.0, 4.0));
    }

    for (int i=0; i<20; i++) {                    

        hit1 = pathtrace(hit1.p, hit1.rd, texelSize);
        hit2 = pathtrace(hit2.p, hit2.rd, texelSize);
        vec2 p = intersectLines(hit1, hit2);
        
        vec2 angularDir = normalize(uv - p);

        if (isBetween(hit1.rd, hit2.rd, angularDir)) {
            // 同じ文字の中かチェック
            vec2 uvVector = uv - hit1.ro;
            float uvDistance = length(uvVector);
            if (uvMask == hit1.mask) {
                // in the same object

                bool valid = true;
                if (uvMask == 0) {
                    vec2 angularOrigin = (hit1.ro + hit2.ro)/2.0 + angularDir * 0.01;
                    Hit directHit = pathtrace(angularOrigin, angularDir, texelSize);
                    if (directHit.d < uvDistance) {
                        valid = false;
                    }
                }

                if (valid) {

                    float totalAngle = abs(angleBetween(hit1.rd, hit2.rd));
                    float progress = abs(angleBetween(angularDir, hit2.rd));
                    float normalizedProgress = progress/totalAngle;
                    float np = normalizedProgress * normalizedProgress * normalizedProgress;
                    vec3 spect = spectral_zucconi(np);
                    c += spect * attenuation(totalDistance + uvDistance);
                }                
            }
        }

        // これ、起きていない
        if (hit1.d == TMAX && hit2.d == TMAX) {
            break;
        }

        float f0 = fresnel(mix(hit1.rd, hit2.rd, 0.5), mix(hit1.n, hit2.n, 0.5), mix(iorMin, iorMax, 0.5));
        
        if (f0 > 1.0) {
            hit1.rd = reflect(hit1.rd, hit1.n);
            hit2.rd = reflect(hit2.rd, hit2.n);
        } else {
            etaMin = (hit1.mask == 0) ? iorMin : 1.0/iorMin;
            etaMax = (hit2.mask == 0) ? iorMax : 1.0/iorMax;
            vec2 nd1 = refract(hit1.rd, hit1.n, etaMin);
            vec2 nd2 = refract(hit2.rd, hit2.n, etaMax);

            if (length(nd1) < 1.0 || length(nd2) < 0.0) {
                hit1.rd = reflect(hit1.rd, hit1.n);
                hit2.rd = reflect(hit2.rd, hit2.n);

            } else {
                hit1.rd = nd1;
                hit2.rd = nd2;
            }
        }


        totalDistance += (hit1.d + hit2.d)/2.0;

    }
  
    fragColor = vec4(c, 1.0);
}

void main() {
    vec4 color;
    render(color);
    gl_FragColor = color;
}