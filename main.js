// main.js
import parseExr from 'parse-exr';
import { intersect } from './ray.js'

const canvas = document.getElementById('glcanvas');
const gl = canvas.getContext('webgl');
if (!gl.getExtension('OES_texture_float')) throw new Error('OES_texture_float unsupported');
gl.getExtension('OES_texture_float_linear');
gl.getExtension('EXT_color_buffer_float');

let exrWidth = 1, exrHeight = 1;

function resizeCanvas() {
  const vw = window.innerWidth;
  const vh = window.innerHeight;
  const windowAspect = vw / vh;
  const imageAspect = exrWidth / exrHeight;

  let drawWidth, drawHeight;
  if (windowAspect > imageAspect) {
    // window is wider than image: constrain by height
    drawHeight = vh;
    drawWidth = Math.floor(vh * imageAspect);
  } else {
    // window is taller than image: constrain by width
    drawWidth = vw;
    drawHeight = Math.floor(vw / imageAspect);
  }

  canvas.style.position = 'absolute';
  canvas.style.top = `${Math.floor((vh - drawHeight) / 2)}px`;
  canvas.style.left = `${Math.floor((vw - drawWidth) / 2)}px`;
  canvas.width = drawWidth;
  canvas.height = drawHeight;

  gl.viewport(0, 0, canvas.width, canvas.height);
}
window.addEventListener('resize', resizeCanvas);

const mousePos = new Float32Array(4);
canvas.addEventListener('mousemove', function (e) {
  const rect = canvas.getBoundingClientRect();
  const mouseX = e.clientX - rect.left;
  const mouseY = rect.bottom - e.clientY; // Y flipped for bottom-left origin
  mousePos[0] = mouseX;
  mousePos[1] = mouseY;
});

// Load GLSL shader from file
async function loadShaderSource(url) {
  const res = await fetch(url);
  return res.text();
}

// Compile shader
function compileShader(gl, type, source) {
  const shader = gl.createShader(type);
  gl.shaderSource(shader, source);
  gl.compileShader(shader);
  if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
    throw new Error('Shader compile error: ' + gl.getShaderInfoLog(shader));
  }
  return shader;
}

// Create WebGL program
function createProgram(gl, vsSource, fsSource) {
  const vs = compileShader(gl, gl.VERTEX_SHADER, vsSource);
  const fs = compileShader(gl, gl.FRAGMENT_SHADER, fsSource);
  const program = gl.createProgram();
  gl.attachShader(program, vs);
  gl.attachShader(program, fs);
  gl.linkProgram(program);
  if (!gl.getProgramParameter(program, gl.LINK_STATUS)) {
    throw new Error('Program link error: ' + gl.getProgramInfoLog(program));
  }
  return program;
}

// Create fullscreen quad
function createQuad(gl) {
  const buffer = gl.createBuffer();
  gl.bindBuffer(gl.ARRAY_BUFFER, buffer);
  gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 3, -1, -1, 3]), gl.STATIC_DRAW);
  return buffer;
}

function halfToFloat(h) {
  const s = (h & 0x8000) >> 15;
  const e = (h & 0x7C00) >> 10;
  const f = h & 0x03FF;

  if (e === 0) return (s ? -1 : 1) * Math.pow(2, -14) * (f / Math.pow(2, 10));
  if (e === 0x1F) return f ? NaN : ((s ? -1 : 1) * Infinity);

  return (s ? -1 : 1) * Math.pow(2, e - 15) * (1 + f / 1024);
}

// Load EXR texture
async function loadExrTexture(gl, url) {
  const res = await fetch(url);
  const buffer = await res.arrayBuffer();
  const exr = parseExr(buffer);

  const { width, height, data } = exr;
  exrWidth = width;
  exrHeight = height;
  resizeCanvas();
  const rgba = new Float32Array(width * height * 4);
  for (let i = 0; i < width * height; i++) {
    rgba[i * 4 + 0] = halfToFloat(data[i * 4 + 0]);
    rgba[i * 4 + 1] = halfToFloat(data[i * 4 + 1]);
    rgba[i * 4 + 2] = halfToFloat(data[i * 4 + 2]);
    rgba[i * 4 + 3] =  halfToFloat(data[i * 4 + 3]);
  }




  const tex = gl.createTexture();
  gl.bindTexture(gl.TEXTURE_2D, tex);

  gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, width, height, 0, gl.RGBA, gl.FLOAT, rgba);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
  gl.bindTexture(gl.TEXTURE_2D, null);

  return tex;
}

async function loadData(url) {
  const res = await fetch(url);
  const data = await res.json();
  return data;
}

function normalize(v) {
  const length = Math.hypot(v[0], v[1]);
  return length > 0 ? [v[0] / length, v[1] / length] : [0, 0];
}
// Main
(async () => {
  const [vsSrc, fsSrc] = await Promise.all([
    loadShaderSource('/shader.vert'),
    loadShaderSource('/shader.glsl')
  ]);
  const program = createProgram(gl, vsSrc, fsSrc);

  const tex = await loadExrTexture(gl, 'img/texture.exr');
  const logo = await loadData('./img/logo.json');
  console.log(logo);

  const buffer = createQuad(gl);
  const aPos = gl.getAttribLocation(program, 'a_position');
  const uRes = gl.getUniformLocation(program, 'iResolution');
  const uTextureSize = gl.getUniformLocation(program, 'iTextureSize');
  const uTime = gl.getUniformLocation(program, 'iTime');
  const uTex = gl.getUniformLocation(program, 'iChannel0');
  const uMouse = gl.getUniformLocation(program, "iMouse");

  gl.useProgram(program);
  gl.enableVertexAttribArray(aPos);
  gl.bindBuffer(gl.ARRAY_BUFFER, buffer);
  gl.vertexAttribPointer(aPos, 2, gl.FLOAT, false, 0, 0);

  const start = performance.now();
  function render() {

    const time = (performance.now() - start) / 1000;

    const ro = [mousePos[0]/canvas.width, mousePos[1]/canvas.height];
    const rd = normalize([0.5 - ro[0], 0.5 - ro[1]]);
    intersect(ro, rd, logo);

    gl.clear(gl.COLOR_BUFFER_BIT);
    gl.useProgram(program);
    gl.uniform2f(uRes, canvas.width, canvas.height);
    gl.uniform2f(uTextureSize, exrWidth, exrHeight);
    gl.uniform1f(uTime, time);
    gl.uniform4f(uMouse, mousePos[0], mousePos[1], 0.0, 0.0); // add click if needed
    gl.uniform1i(uTex, 0);
    gl.activeTexture(gl.TEXTURE0);
    gl.bindTexture(gl.TEXTURE_2D, tex);
    gl.drawArrays(gl.TRIANGLES, 0, 3);
    requestAnimationFrame(render);
  }
  render();
})();

