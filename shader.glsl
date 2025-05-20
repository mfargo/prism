precision highp float;

uniform vec2 iResolution;
uniform int iPointCount;
uniform int iPolyCount;
uniform sampler2D iChannel0; // lightpath
uniform sampler2D iChannel1; // labels
uniform sampler2D iChannel2; // polys
uniform sampler2D iChannel3; // points

const float TMAX = 1e20;
const int maxRefractions = 20;
const vec2 dim = vec2(1.920, 0.96);



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

float attenuation(float d) {
    return 1.0 / (d * d);
}

// https://iquilezles.org/articles/distfunctions2d/
float sdSegment( in vec2 p, in vec2 a, in vec2 b ) {
    vec2 pa = p-a, ba = b-a;
    float h = clamp( dot(pa,ba)/dot(ba,ba), 0.0, 1.0 );
    return length( pa - ba*h );
}


vec2 intersectLines(vec2 p1, vec2 rd1, vec2 p2, vec2 rd2) {
    float determinate = rd1.x * rd2.y - rd1.y * rd2.x;
    vec2 delta = p2 - p1;
    if (abs(determinate) < 1e-8) return vec2(TMAX); // Lines are parallel
    float t = (delta.x * rd2.y - delta.y * rd2.x) / determinate;
    return p1 + t * rd1;
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
int segmentCount(int polyID) {
    float total = float(iPolyCount); 
    float x = (0.5 + float(polyID))/total;
    vec2 coord = vec2(x, 0.5);
    return int(texture2D(iChannel2, coord).r * 255.0);
}

vec2 point(int pointId) {
    float total = float(iPointCount);
    float x = (0.5 + float(pointId*2))/total;
    vec2 coordx = vec2(x, 0.5);
    float y = (0.5 + float(pointId*2 + 1))/total;
    vec2 coordy = vec2(y, 0.5);
    return vec2(texture2D(iChannel3, coordx).r, texture2D(iChannel3, coordy).r);
}

vec4 debugColor(vec2 uv) {
    const float thresh = 0.002;
    int vid = 0;
    // int pp = segmentCount(1);
    // if (pp == 18) {
    //     return vec4(1.0,0.0,1.0,1.0);
    // }
    for (int shapeId = 0; shapeId < 100; shapeId++) {
        if (shapeId >= iPolyCount) {
            break;
        }
        int count = segmentCount(shapeId);
        vec2 firstPoint = point(vid);
        vec2 lastPoint = firstPoint;
        

        for (int i = 0; i < 100; i++) {
            vec2 p;
            if (i >= count) {
                p = firstPoint;
            } else {
                p = point(vid + i);
            }
            float d = sdSegment(uv, lastPoint, p);
            if (d < thresh) {
                float amt = smoothstep(0.0, 1.0, 1.0 - d/thresh);
                return vec4(amt, amt, amt, 1.0);
            }
            if (i >= count) {
                break;
            }
            lastPoint = p;
        }
        vid += count;
    }
    return vec4(0);
}

float labelAt(vec2 screenPos) {
    vec2 uv = screenPos / dim;
    return texture2D(iChannel1, vec2(uv.x, 1.0 - uv.y)).r;
}

void render( out vec4 fragColor) {
    vec2 uv = gl_FragCoord.xy / iResolution.xy;
    //fragColor = texture2D(iChannel0, uv); // test refractions
    //return;
    //fragColor = debugColor(uv * dim);
    // //fragColor = texture2D(iChannel2, uv);
    float u = float(0.5)/float(maxRefractions); 
    vec4 sample = texture2D(iChannel0, vec2(u, 0.5));
    vec2 a1 = sample.xy;
    vec2 b1 = sample.zw;

    vec2 screenPos = uv * dim;
    
    float label = labelAt(screenPos);
    vec4 color = debugColor(screenPos);//texture2D(iChannel1, vec2(uv.x, 1.0 - uv.y))/5.0;

    float totalDistance = 0.0;
    for (int i = 1; i<maxRefractions; i++) {
        u = (float(i) + 0.5)/float(maxRefractions); 
        sample = texture2D(iChannel0, vec2(u, 0.5));

        if (sample.x < -10.0) {
            break;
        }

        totalDistance += length(sample.xy - a1);

        vec2 rd1 = normalize(sample.xy - a1);
        vec2 rd2 = normalize(sample.zw - b1);
        vec2 p = intersectLines(a1, rd1, b1, rd2);

        vec2 angularDir = normalize(screenPos - p);

        if (i == 1) {
            if (sdSegment(screenPos, a1, sample.xy) < 0.001) {
                 float tint = rand(uv);
                 color = vec4(tint, tint, tint, 1.0);
                 break;
            }
        }
        else if (isBetween(rd1, rd2, angularDir)) {
        //      fragColor = vec4(1.0, 0.1, 0.6, 1.0);
        // //     // 同じ文字の中かチェック
            vec2 uvVector = screenPos - a1;
            float uvDistance = length(uvVector);
            float hitLabelA = labelAt((a1 + sample.xy)/2.0);
            if (label == hitLabelA) {
        //         // in the same object

             
                    float totalAngle = abs(angleBetween(rd1, rd2));
                    float progress = abs(angleBetween(angularDir, rd2));
                    float normalizedProgress = progress/totalAngle;
                    float np = normalizedProgress * normalizedProgress * normalizedProgress;
                    vec3 spect = spectral_zucconi(np);
                    vec3 attenuatedColor = spect * attenuation(totalDistance + uvDistance);
                    color += vec4(attenuatedColor, 1.0);
            }            
       }
       a1 = sample.xy;
       b1 = sample.zw;

    }




    fragColor = color;

}

void main() {
    vec4 color;
    render(color);
    gl_FragColor = color;
}