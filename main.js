// main.js

const canvas = document.getElementById('glcanvas');
const gl = canvas.getContext('webgl');
if (!gl.getExtension('OES_texture_float')) throw new Error('OES_texture_float unsupported');
gl.getExtension('OES_texture_float_linear');
gl.getExtension('EXT_color_buffer_float');
gl.getExtension("WEBGL_color_buffer_float");

let exrWidth = 1920, exrHeight = 960;

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
const lastMousePos = new Float32Array(4);
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

async function loadData(url) {
  const res = await fetch(url);
  const data = await res.json();

  var verts = []
  const counts = new Uint8Array(data.shapes.length);
  for (let i = 0; i < data.shapes.length; i++) {
    let shape = data.shapes[i];
    counts[i] = shape.points.length;
    // all pairs
    var lastpoint = shape.points[shape.points.length - 1];
    for (let j = 0; j<shape.points.length; j++) {
      if (lastpoint[0] != shape.points[j][0] || lastpoint[1] != shape.points[j][1]) {
        verts.push(shape.points[j][0]);
        verts.push(exrHeight/1000.0 - shape.points[j][1]);
        lastpoint = shape.points[j];
      } else {
        counts[i] -= 2;
        console.log("dupe")
      }
    }
  }
  const vertices = new Float32Array(verts);
  console.log("Segs", counts.length, " - Verts", vertices.length)
  console.log(counts)
  console.log(vertices)
  return {counts: counts, verts: vertices};
}
function loadImageAsync(url) {
  return new Promise((resolve, reject) => {
    const image = new Image();
    image.src = url;
    image.onload = () => resolve(image);
    image.onerror = reject;
  });
}



// Main
(async () => {
  const [vsSrc, fsSrc] = await Promise.all([
    loadShaderSource('/shader.vert'),
    loadShaderSource('/shader.glsl')
  ]);
  const program = createProgram(gl, vsSrc, fsSrc);

  const logo = await loadData('./img/logo.json');

  resizeCanvas();

  const [evsSrc, efsSrc] = await Promise.all([
    loadShaderSource('/preprocess.vert'),
    loadShaderSource('/preprocess.glsl')
  ]);
  const expensiveProgram = createProgram(gl, evsSrc, efsSrc);


  const labelImage = await loadImageAsync('img/labels.png');
  const labelTexture = gl.createTexture();
  gl.bindTexture(gl.TEXTURE_2D, labelTexture);
  // Upload the image into the texture
  gl.texImage2D(
    gl.TEXTURE_2D,  // target
    0,              // level
    gl.RGBA,        // internal format
    gl.RGBA,        // format
    gl.UNSIGNED_BYTE, // type
    labelImage       // image
  );

  // Set texture parameters
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);


  const polyCountTex = gl.createTexture();
  gl.bindTexture(gl.TEXTURE_2D, polyCountTex);
  gl.texImage2D(
      gl.TEXTURE_2D,
      0, gl.LUMINANCE, logo.counts.length, 1, 0,
      gl.LUMINANCE, gl.UNSIGNED_BYTE,
      logo.counts
  );

  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);

  const vertTex = gl.createTexture();
  gl.bindTexture(gl.TEXTURE_2D, vertTex);
  gl.texImage2D(
    gl.TEXTURE_2D,
    0, gl.LUMINANCE, logo.verts.length, 1, 0,
    gl.LUMINANCE, gl.FLOAT,
    logo.verts
  );
  // Required for float textures:
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);


  const maxRefractions = 20;
  // This will hold light path values
  const lightPathTexture = gl.createTexture();
  gl.bindTexture(gl.TEXTURE_2D, lightPathTexture);
  gl.texImage2D(gl.TEXTURE_2D,
      0,                 // mip level
      gl.RGBA,          
      maxRefractions, 1,       // width, height
      0,                 // border
      gl.RGBA,             // format
      gl.FLOAT,          // type
      null               // no initial data
  );
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
  const fbo = gl.createFramebuffer();



  const buffer = createQuad(gl);
  const aPos = gl.getAttribLocation(program, 'a_position');
  const aPrepos = gl.getAttribLocation(expensiveProgram, 'a_position');
  const uRes = gl.getUniformLocation(program, 'iResolution');
  const uPreRes = gl.getUniformLocation(expensiveProgram, 'iResolution');
  const uPreTargetRes = gl.getUniformLocation(expensiveProgram, 'iTargetResolution');
  const uPrePolyCount = gl.getUniformLocation(expensiveProgram, 'iPolyCount');
  const uPolyCount = gl.getUniformLocation(program, 'iPolyCount');
  const uPointCount = gl.getUniformLocation(program, 'iPointCount');
  const uPrePointCount = gl.getUniformLocation(expensiveProgram, 'iPointCount');
  const uTime = gl.getUniformLocation(expensiveProgram, 'iTime');
  const uPath = gl.getUniformLocation(program, 'iChannel0');
  const uLabels = gl.getUniformLocation(program, "iChannel1");
  const uPrePolys = gl.getUniformLocation(expensiveProgram, "iChannel0");
  const uPolys = gl.getUniformLocation(program, "iChannel2");
  const uPoints = gl.getUniformLocation(program, "iChannel3");
  const uPrePoints = gl.getUniformLocation(expensiveProgram, "iChannel1");
  const uMouse = gl.getUniformLocation(expensiveProgram, "iMouse");


  function runExpensiveShaderOnce(time) {
    if (lastMousePos[0] == mousePos[0] && lastMousePos[1] == mousePos[1]) {
      return;
    }
    lastMousePos[0] = mousePos[0];
    lastMousePos[1] = mousePos[1];
    
    gl.bindFramebuffer(gl.FRAMEBUFFER, fbo);
    gl.viewport(0, 0, maxRefractions, 1);
    // Use your expensive shader here
    gl.useProgram(expensiveProgram);
    gl.clear(gl.COLOR_BUFFER_BIT);

    gl.bindFramebuffer(gl.FRAMEBUFFER, fbo);
    gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, lightPathTexture, 0);

    gl.uniform1f(uTime, time);
    gl.uniform2f(uPreTargetRes, maxRefractions, 1);
    gl.uniform2f(uPreRes, canvas.width, canvas.height);

    gl.activeTexture(gl.TEXTURE0);
    gl.bindTexture(gl.TEXTURE_2D, polyCountTex);
    gl.uniform1i(uPrePolys, 0);

    gl.activeTexture(gl.TEXTURE1);
    gl.bindTexture(gl.TEXTURE_2D, vertTex);
    gl.uniform1i(uPrePoints, 1);
    
    gl.uniform1i(uPrePolyCount, logo.counts.length);
    gl.uniform1i(uPrePointCount, logo.verts.length);
    gl.uniform4f(uMouse, mousePos[0], mousePos[1], 0.0, 0.0); // add click if needed
    // Draw a 1x20 quad

    gl.enableVertexAttribArray(aPrepos);
    gl.bindBuffer(gl.ARRAY_BUFFER, buffer);
    gl.vertexAttribPointer(aPrepos, 2, gl.FLOAT, false, 0, 0);
    gl.drawArrays(gl.TRIANGLES, 0, 3);
    gl.bindFramebuffer(gl.FRAMEBUFFER, null);
  }
  function runRenderShader(time) {
    gl.useProgram(program);
    gl.viewport(0, 0, canvas.width, canvas.height);

    gl.enableVertexAttribArray(aPos);
    gl.bindBuffer(gl.ARRAY_BUFFER, buffer);
    gl.vertexAttribPointer(aPos, 2, gl.FLOAT, false, 0, 0);

    gl.useProgram(program);
    gl.clear(gl.COLOR_BUFFER_BIT);

    gl.uniform2f(uRes, canvas.width, canvas.height);
    gl.uniform1i(uPolyCount, logo.counts.length);

    gl.activeTexture(gl.TEXTURE0);
    gl.bindTexture(gl.TEXTURE_2D, lightPathTexture);
    gl.uniform1i(uPath, 0);

    gl.activeTexture(gl.TEXTURE1);
    gl.bindTexture(gl.TEXTURE_2D, labelTexture);
    gl.uniform1i(uLabels, 1);

    gl.activeTexture(gl.TEXTURE2);
    gl.bindTexture(gl.TEXTURE_2D, polyCountTex);
    gl.uniform1i(uPolys, 2);

    gl.activeTexture(gl.TEXTURE3);
    gl.bindTexture(gl.TEXTURE_2D, vertTex);
    gl.uniform1i(uPoints, 3);

    gl.uniform1i(uPointCount, logo.verts.length);
    gl.drawArrays(gl.TRIANGLES, 0, 3);
  }

  const start = performance.now();
  function render() {

    const time = (performance.now() - start) / 1000;

    runExpensiveShaderOnce(time);

    runRenderShader(time);
    requestAnimationFrame(render);
  }
  render();
})();

