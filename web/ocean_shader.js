// Web-Ocean 3D Real-Time Physical Sky & Ocean Shader (WebGL2 / WebGL1)
// Extracted from ShiftAlarm x Web-Ocean reference specification
(function () {
  'use strict';

  const SHIFT_OCEAN_PRESETS = {
    M: {
      sunElev: 10.5,
      sunAzimuth: 142.0,
      windSpeed: 7.5,
      swellHs: 1.0,
      choppiness: 0.95,
      turbidity: 0.72,
      foam: 0.65,
      haze: 0.45,
      clouds: 0.30,
      exposure: 1.15,
      bloom: 0.80,
      nightGlow: 0.0,
    },
    A: {
      sunElev: 55.0,
      sunAzimuth: 178.0,
      windSpeed: 6.0,
      swellHs: 0.70,
      choppiness: 0.82,
      turbidity: 0.92,
      foam: 0.38,
      haze: 0.14,
      clouds: 0.16,
      exposure: 1.38,
      bloom: 0.95,
      nightGlow: 0.0,
    },
    S: {
      sunElev: 3.5,
      sunAzimuth: 195.0,
      windSpeed: 11.5,
      swellHs: 1.7,
      choppiness: 1.35,
      turbidity: 0.50,
      foam: 1.15,
      haze: 0.60,
      clouds: 0.48,
      exposure: 1.08,
      bloom: 1.20,
      nightGlow: 0.0,
    },
    N: {
      sunElev: -16.0,
      sunAzimuth: 215.0,
      windSpeed: 8.5,
      swellHs: 1.7,
      choppiness: 1.10,
      turbidity: 0.16,
      foam: 1.40,
      haze: 0.18,
      clouds: 0.14,
      exposure: 0.82,
      bloom: 0.85,
      nightGlow: 1.0,
    },
    O: {
      sunElev: 48.0,
      sunAzimuth: 172.0,
      windSpeed: 5.6,
      swellHs: 0.65,
      choppiness: 0.78,
      turbidity: 0.95,
      foam: 0.35,
      haze: 0.14,
      clouds: 0.20,
      exposure: 1.30,
      bloom: 0.85,
      nightGlow: 0.0,
    },
    OT: {
      sunElev: 2.5,
      sunAzimuth: 202.0,
      windSpeed: 18.5,
      swellHs: 3.1,
      choppiness: 1.65,
      turbidity: 0.48,
      foam: 1.85,
      haze: 0.68,
      clouds: 0.78,
      exposure: 1.12,
      bloom: 0.80,
      nightGlow: 0.2,
    }
  };

  function getPresetByCurrentTime() {
    const hour = new Date().getHours();
    if (hour >= 3 && hour < 9) return SHIFT_OCEAN_PRESETS.M;   // 早班 06 晨曦破曉
    if (hour >= 9 && hour < 15) return SHIFT_OCEAN_PRESETS.A;  // 午班 12 豔陽碧海
    if (hour >= 15 && hour < 21) return SHIFT_OCEAN_PRESETS.S; // 18 晚班金暉落日
    return SHIFT_OCEAN_PRESETS.N;                              // 00 星夜深邃
  }

  const initialPreset = getPresetByCurrentTime();
  const oceanCurrent = Object.assign({}, initialPreset);
  const oceanTarget = Object.assign({}, initialPreset);

  const importFx = {
    active: false,
    startTime: 0,
    duration: 2.2,
    waveProgress: -1.0,
    surgeIntensity: 0.0,
    camDip: 0.0
  };

  // Expose global bridge functions for Flutter Web
  window.setOceanAtmosphereFromFlutter = function (shiftCode, sunElev, sunAzimuth, nightGlow) {
    if (SHIFT_OCEAN_PRESETS[shiftCode]) {
      Object.assign(oceanTarget, SHIFT_OCEAN_PRESETS[shiftCode]);
    } else {
      if (typeof sunElev === 'number') oceanTarget.sunElev = sunElev;
      if (typeof sunAzimuth === 'number') oceanTarget.sunAzimuth = sunAzimuth;
      if (typeof nightGlow === 'number') oceanTarget.nightGlow = nightGlow;
    }
  };

  window.triggerOceanSurgeFromFlutter = function () {
    importFx.active = true;
    importFx.startTime = performance.now();
  };

  function initWebGL() {
    const bgCanvas = document.getElementById('oceanBgCanvas');
    if (!bgCanvas) return;

    const gl = bgCanvas.getContext('webgl2', { alpha: false, antialias: false }) ||
               bgCanvas.getContext('webgl', { alpha: false, antialias: false });
    if (!gl) return;

    const isWebGL2 = (typeof WebGL2RenderingContext !== 'undefined' && gl instanceof WebGL2RenderingContext);

    const vsSource = isWebGL2 ? `#version 300 es
      precision highp float;
      in vec2 aPos;
      void main() {
        gl_Position = vec4(aPos, 0.0, 1.0);
      }
    ` : `
      precision highp float;
      attribute vec2 aPos;
      void main() {
        gl_Position = vec4(aPos, 0.0, 1.0);
      }
    `;

    const fsBody = `
      uniform vec2 uResolution;
      uniform float uTime;
      uniform vec3 uCamPos;
      uniform vec3 uCamFwd;
      uniform vec3 uCamRight;
      uniform vec3 uCamUp;

      uniform float uWindSpeed;
      uniform float uSwellHs;
      uniform float uChoppiness;
      uniform float uTurbidity;
      uniform float uFoam;
      uniform vec3 uSunDir;
      uniform float uHaze;
      uniform float uClouds;
      uniform float uExposure;
      uniform float uBloom;
      uniform float uNightGlow;
      uniform float uImportWaveProgress;
      uniform float uSurgeIntensity;

      const float PI = 3.14159265359;
      const float G = 9.81;

      float hash12(vec2 p) {
        vec3 p3 = fract(vec3(p.xyx) * 0.1031);
        p3 += dot(p3, p3.yzx + 33.33);
        return fract((p3.x + p3.y) * p3.z);
      }

      float noise2D(vec2 p) {
        vec2 i = floor(p);
        vec2 f = fract(p);
        vec2 u = f * f * (3.0 - 2.0 * f);
        return mix(
          mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
          mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x),
          u.y
        );
      }

      const mat2 m2 = mat2(0.80, -0.60, 0.60, 0.80);

      float fbm(vec2 p) {
        float v = 0.0;
        v += 0.50 * noise2D(p); p = m2 * p * 2.02;
        v += 0.25 * noise2D(p); p = m2 * p * 2.03;
        v += 0.125 * noise2D(p);
        return v;
      }

      vec3 renderSky(vec3 rd, vec3 sunDir) {
        float sunElev = sunDir.y;
        float zenithCos = max(rd.y, 0.0);
        float sunCos = clamp(dot(rd, sunDir), -1.0, 1.0);

        float dayF = smoothstep(0.00, 0.28, sunElev);
        float nightF = smoothstep(0.02, -0.10, sunElev);

        // Zenith color:
        // Midday (午班): bright radiant sapphire azure
        // Dawn/Sunset: warm deep twilight
        // Night (夜班): deep pitch dark midnight void
        vec3 zenithCol = mix(vec3(0.08, 0.16, 0.42), vec3(0.04, 0.28, 0.82), dayF);
        zenithCol = mix(zenithCol, vec3(0.001, 0.002, 0.006), nightF);

        // Horizon color:
        // Midday (午班): bright clear azure sky mist
        // Dawn/Sunset: fiery golden-peach / crimson sunrise/sunset
        // Night (夜班): deep obsidian night mist
        vec3 sunriseSunsetHoriz = mix(vec3(1.0, 0.38, 0.12), vec3(1.0, 0.62, 0.28), clamp(sunDir.x * 0.5 + 0.5, 0.0, 1.0));
        vec3 dayHoriz = vec3(0.50, 0.80, 1.0);
        vec3 horizCol = mix(sunriseSunsetHoriz, dayHoriz, smoothstep(0.04, 0.32, sunElev));
        horizCol = mix(horizCol, vec3(0.003, 0.006, 0.016), nightF);

        vec3 sky = mix(zenithCol, horizCol, pow(1.0 - zenithCos, 3.0));

        // Mie aerosol glow
        float g = 0.80;
        float mie = (1.0 - g * g) / (4.0 * PI * pow(max(1.0 + g * g - 2.0 * g * sunCos, 0.0001), 1.5));
        vec3 sunTint = mix(vec3(1.0, 0.42, 0.14), vec3(1.0, 0.98, 0.92), smoothstep(-0.02, 0.25, sunElev));
        sunTint = mix(sunTint, vec3(0.28, 0.50, 0.95), nightF);
        // Suppress atmospheric haze at night so the sky stays deeply dark
        sky += sunTint * mie * ((0.35 + 0.65 * uHaze) * (1.0 - nightF * 0.88));

        // Clouds
        if (rd.y > 0.008 && uClouds > 0.01) {
          vec2 uv = rd.xz / max(rd.y, 0.03) * 0.24 + vec2(uTime * 0.015, uTime * 0.008);
          float n = fbm(uv);
          float cov = smoothstep(0.60 - uClouds * 0.35, 0.78, n) * smoothstep(0.01, 0.12, rd.y);
          vec3 cloudCol = mix(vec3(0.18, 0.24, 0.38) * (1.0 - nightF * 0.92), sunTint * 0.95, (0.55 + 0.45 * max(sunCos, 0.0)) * (1.0 - nightF * 0.85));
          sky = mix(sky, cloudCol, cov * 0.78);
        }

        // Solar or Lunar Disc
        float halo = pow(max(sunCos, 0.0), 220.0) * 2.2 + pow(max(sunCos, 0.0), 30.0) * 0.40;
        sky += sunTint * halo * uBloom * (1.0 - nightF * 0.60);
        return sky;
      }

      void mainImage(out vec4 fragColor, in vec2 fragCoord) {
        vec2 ndc = (fragCoord / uResolution) * 2.0 - 1.0;
        ndc.x *= uResolution.x / max(uResolution.y, 1.0);

        vec3 rd = normalize(uCamFwd + ndc.x * 0.58 * uCamRight + ndc.y * 0.58 * uCamUp);
        vec3 ro = uCamPos;
        vec3 sunDir = normalize(uSunDir);

        vec3 skyCol = renderSky(rd, sunDir);

        if (rd.y >= -0.001) {
          vec3 mappedSky = pow(clamp((skyCol * uExposure) / (1.0 + skyCol * uExposure), 0.0, 1.0), vec3(1.0 / 2.2));
          fragColor = vec4(mappedSky, 1.0);
          return;
        }

        // Ray-intersect ocean plane with 4-step height refinement
        float t = ro.y / max(-rd.y, 0.001);
        vec3 hit = ro + rd * t;
        float windScale = max(0.25, uWindSpeed / 11.5) + uSurgeIntensity * 0.65;

        // Compute multi-cascade wave height & normal
        vec2 grad = vec2(0.0);
        float crest = 0.0;
        float dist = length(hit - ro);
        float lod = exp(-dist * 0.007);

        for (int i = 0; i < 9; i++) {
          float fi = float(i);
          float k = 0.14 * pow(1.52, fi);
          float w = sqrt(G * k);
          float amp = (0.24 * windScale + 0.08 * uSwellHs) / pow(1.46, fi);
          float ang = sin(fi * 2.399) * 0.55;
          vec2 d = vec2(sin(ang), cos(ang));
          float ph = dot(hit.xz, d) * k - w * uTime * (1.0 + uSurgeIntensity * 0.8) + fi * 1.9;
          float c = cos(ph);
          float s = sin(ph);
          grad += d * (amp * k * c * lod);
          crest += max(s, 0.0) * (0.25 / (1.0 + fi * 0.3));
        }

        // Special Schedule-Import Shockwave Ring sweeping across the sea!
        float shockRing = 0.0;
        if (uImportWaveProgress >= 0.0 && uImportWaveProgress <= 1.2) {
          float targetDist = mix(2.0, 68.0, uImportWaveProgress);
          float ringDelta = dist - targetDist;
          shockRing = exp(-(ringDelta * ringDelta) / (18.0 + targetDist * 0.45));
          grad += normalize(hit.xz + vec2(0.001)) * (-ringDelta * 0.12 * shockRing);
          crest += shockRing * 1.35;
        }

        vec3 N = normalize(vec3(-grad.x * uChoppiness, 1.0, -grad.y * uChoppiness));
        vec3 V = -rd;
        vec3 effN = normalize(mix(N, vec3(0.0, 1.0, 0.0), clamp(1.0 - pow(max(V.y, 0.0), 0.45), 0.0, 0.55)));
        float NoV = clamp(dot(effN, V), 0.001, 1.0);
        float fresnel = clamp(0.02 + 0.98 * pow(1.0 - NoV, 5.0), 0.02, 0.95);

        vec3 R = reflect(-V, effN);
        R.y = max(R.y, 0.015);
        vec3 reflSky = renderSky(normalize(R), sunDir);

        // Water body & subsurface glow
        float dayLight = smoothstep(-0.06, 0.25, sunDir.y);
        vec3 deepCol = mix(vec3(0.001, 0.005, 0.014), vec3(0.016, 0.11, 0.14), uTurbidity) * (0.06 + 0.96 * dayLight);
        vec3 sssCol = vec3(0.04, 0.54, 0.46) * crest * (0.35 + 0.65 * uTurbidity) * (0.12 + 0.88 * dayLight);

        vec3 sea = mix(deepCol + sssCol, reflSky, fresnel);

        // Anisotropic sun/moon glitter
        vec3 H = normalize(V + sunDir);
        float spec = pow(max(dot(effN, H), 0.0), 140.0) * 3.5;
        vec3 sunTint = mix(vec3(1.0, 0.45, 0.15), vec3(1.0, 0.98, 0.92), smoothstep(0.0, 0.28, sunDir.y));
        sunTint = mix(sunTint, vec3(0.25, 0.48, 0.90), uNightGlow);
        sea += sunTint * spec * fresnel * uBloom * (0.15 + 0.85 * dayLight);

        // Whitecap foam + Night Shift Bioluminescence ("藍眼淚") + Import Shockwave Golden-Cyan Crest
        float foamMask = smoothstep(0.40, 0.86, crest * uFoam) * lod;
        vec3 foamCol = mix(vec3(0.88, 0.92, 0.96) * (0.22 + 0.78 * dayLight), vec3(0.06, 0.95, 1.0) * 3.2, uNightGlow);
        sea = mix(sea, foamCol, clamp(foamMask, 0.0, 0.92));

        if (shockRing > 0.005) {
          vec3 waveEnergyCol = mix(vec3(0.22, 0.88, 1.0), vec3(1.0, 0.78, 0.28), 0.5 + 0.5 * sin(dist * 0.25 - uTime * 8.0));
          sea += waveEnergyCol * shockRing * 2.2;
        }

        // Horizon aerial perspective blend
        float fog = clamp(1.0 - exp(-dist * 0.0035), 0.0, 1.0);
        vec3 finalHdr = mix(sea, skyCol, fog);

        // Filmic tone map
        vec3 c = finalHdr * uExposure;
        vec3 mapped = (c * (2.51 * c + 0.03)) / (c * (2.43 * c + 0.59) + 0.14);
        fragColor = vec4(pow(clamp(mapped, 0.0, 1.0), vec3(1.0 / 2.2)), 1.0);
      }
    `;

    const fsSource = isWebGL2 ? `#version 300 es
      precision highp float;
      out vec4 outColor;
      ${fsBody}
      void main() { mainImage(outColor, gl_FragCoord.xy); }
    ` : `
      precision highp float;
      ${fsBody}
      void main() { vec4 c; mainImage(c, gl_FragCoord.xy); gl_FragColor = c; }
    `;

    function compileShader(type, src) {
      const s = gl.createShader(type);
      gl.shaderSource(s, src);
      gl.compileShader(s);
      return s;
    }

    const prog = gl.createProgram();
    gl.attachShader(prog, compileShader(gl.VERTEX_SHADER, vsSource));
    gl.attachShader(prog, compileShader(gl.FRAGMENT_SHADER, fsSource));
    gl.linkProgram(prog);
    gl.useProgram(prog);

    const qBuf = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, qBuf);
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1,-1, 1,-1, -1,1, -1,1, 1,-1, 1,1]), gl.STATIC_DRAW);
    const aPos = gl.getAttribLocation(prog, 'aPos');
    gl.enableVertexAttribArray(aPos);
    gl.vertexAttribPointer(aPos, 2, gl.FLOAT, false, 0, 0);

    const uLocs = {
      uResolution: gl.getUniformLocation(prog, 'uResolution'),
      uTime: gl.getUniformLocation(prog, 'uTime'),
      uCamPos: gl.getUniformLocation(prog, 'uCamPos'),
      uCamFwd: gl.getUniformLocation(prog, 'uCamFwd'),
      uCamRight: gl.getUniformLocation(prog, 'uCamRight'),
      uCamUp: gl.getUniformLocation(prog, 'uCamUp'),
      uWindSpeed: gl.getUniformLocation(prog, 'uWindSpeed'),
      uSwellHs: gl.getUniformLocation(prog, 'uSwellHs'),
      uChoppiness: gl.getUniformLocation(prog, 'uChoppiness'),
      uTurbidity: gl.getUniformLocation(prog, 'uTurbidity'),
      uFoam: gl.getUniformLocation(prog, 'uFoam'),
      uSunDir: gl.getUniformLocation(prog, 'uSunDir'),
      uHaze: gl.getUniformLocation(prog, 'uHaze'),
      uClouds: gl.getUniformLocation(prog, 'uClouds'),
      uExposure: gl.getUniformLocation(prog, 'uExposure'),
      uBloom: gl.getUniformLocation(prog, 'uBloom'),
      uNightGlow: gl.getUniformLocation(prog, 'uNightGlow'),
      uImportWaveProgress: gl.getUniformLocation(prog, 'uImportWaveProgress'),
      uSurgeIntensity: gl.getUniformLocation(prog, 'uSurgeIntensity')
    };

    function resizeCanvas() {
      const dpr = Math.min(window.devicePixelRatio || 1, 1.5);
      bgCanvas.width = Math.floor(window.innerWidth * dpr);
      bgCanvas.height = Math.floor(window.innerHeight * dpr);
      gl.viewport(0, 0, bgCanvas.width, bgCanvas.height);
    }
    window.addEventListener('resize', resizeCanvas);
    resizeCanvas();

    const t0 = performance.now();
    let lastT = t0;

    function renderLoop(now) {
      const dt = Math.min(0.1, (now - lastT) * 0.001);
      lastT = now;
      const elapsed = (now - t0) * 0.001;

      const lerpSpeed = Math.min(1.0, dt * 3.8);
      Object.keys(oceanTarget).forEach((k) => {
        if (typeof oceanTarget[k] === 'number') {
          oceanCurrent[k] += (oceanTarget[k] - oceanCurrent[k]) * lerpSpeed;
        }
      });

      if (importFx.active) {
        const p = (now - importFx.startTime) / (importFx.duration * 1000);
        if (p >= 1.0) {
          importFx.active = false;
          importFx.waveProgress = -1.0;
          importFx.surgeIntensity = 0.0;
          importFx.camDip = 0.0;
        } else {
          importFx.waveProgress = p;
          importFx.surgeIntensity = Math.sin(p * Math.PI) * 1.35;
          importFx.camDip = Math.sin(p * Math.PI) * 0.75;
        }
      }

      const elevRad = (oceanCurrent.sunElev * Math.PI) / 180.0;
      const azimRad = (oceanCurrent.sunAzimuth * Math.PI) / 180.0;
      const sunX = Math.sin(azimRad) * Math.cos(elevRad);
      const sunY = Math.sin(elevRad);
      const sunZ = Math.cos(azimRad) * Math.cos(elevRad);

      const camY = Math.max(1.2, 2.5 - importFx.camDip + Math.sin(elapsed * 1.3) * 0.18);
      const pitch = -0.04 - importFx.camDip * 0.06;
      const cosP = Math.cos(pitch);
      const sinP = Math.sin(pitch);

      gl.useProgram(prog);
      gl.uniform2f(uLocs.uResolution, bgCanvas.width, bgCanvas.height);
      gl.uniform1f(uLocs.uTime, elapsed);
      gl.uniform3f(uLocs.uCamPos, 0.0, camY, 0.0);
      gl.uniform3f(uLocs.uCamFwd, 0.0, sinP, -cosP);
      gl.uniform3f(uLocs.uCamRight, -1.0, 0.0, 0.0);
      gl.uniform3f(uLocs.uCamUp, 0.0, cosP, sinP);

      gl.uniform1f(uLocs.uWindSpeed, oceanCurrent.windSpeed);
      gl.uniform1f(uLocs.uSwellHs, oceanCurrent.swellHs);
      gl.uniform1f(uLocs.uChoppiness, oceanCurrent.choppiness);
      gl.uniform1f(uLocs.uTurbidity, oceanCurrent.turbidity);
      gl.uniform1f(uLocs.uFoam, oceanCurrent.foam);
      gl.uniform3f(uLocs.uSunDir, sunX, sunY, sunZ);
      gl.uniform1f(uLocs.uHaze, oceanCurrent.haze);
      gl.uniform1f(uLocs.uClouds, oceanCurrent.clouds);
      gl.uniform1f(uLocs.uExposure, oceanCurrent.exposure);
      gl.uniform1f(uLocs.uBloom, oceanCurrent.bloom);
      gl.uniform1f(uLocs.uNightGlow, oceanCurrent.nightGlow);
      gl.uniform1f(uLocs.uImportWaveProgress, importFx.waveProgress);
      gl.uniform1f(uLocs.uSurgeIntensity, importFx.surgeIntensity);

      gl.drawArrays(gl.TRIANGLES, 0, 6);

      requestAnimationFrame(renderLoop);
    }

    requestAnimationFrame(renderLoop);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initWebGL);
  } else {
    initWebGL();
  }
})();
