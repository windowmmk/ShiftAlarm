// ─────────────────────────────────────────────────────────────────────────────
// ShiftAlarm v3.5 —— 海洋真光影線步進著色器（Flutter runtime effect）
//
// 移植自 web/ocean_shader.js 的 fsBody（第 155-350 行）。原版係 WebGL2 全屏 3D 物理海洋，
// 本檔改以 Flutter runtime effect 執行，Android（Impeller／Skia）與 Web（CanvasKit／skwasm）
// 共用同一份著色器，做到「兩端一致嘅真實光影」。
//
// 相對原版只改三處：
//   ① 前置宣告：#include <flutter/runtime_effect.glsl> + out vec4 fragColor
//      （刪走 #version 與 precision，因為 runtime_effect.glsl 已經提供）
//   ② 投影：固定「水平半角」，垂直半角由 aspect 反推（見 mainImage 註解）。
//      原式 ndc.x *= aspect 喺 464×96（aspect 4.83）會令水平半角變成 70°，魚眼＋太陽變橢圓。
//   ③ 入口：mainImage 由 void(out vec4, in vec2) 改為回傳 vec4，main() 一行轉發。
// 其餘（hash12 / noise2D / fbm / renderSky / const mat2 m2 / 9 波迴圈 / ACES tone map）一字不改。
//
// ⚠️ 19 個 uniform 全部都有被 body 真正引用。impellerc 會剔除「宣告但未引用」嘅 uniform，
//    令後面所有 float 索引整體前移 —— 畫面會變得莫名奇妙但唔會拋任何異常。
//    改動任何一個 uniform 時，必須同步改 lib/ui/widgets/ocean_shader_controller.dart 嘅 _U。
//    （回歸測試：test/ocean_uniform_layout_test.dart）
// ─────────────────────────────────────────────────────────────────────────────

#include <flutter/runtime_effect.glsl>

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

out vec4 fragColor;

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

vec4 mainImage(vec2 fragCoord) {
  // ── 投影（必須重寫，見 ARCH §3.5.3）───────────────────────────────────────
  // 原版：ndc.x *= uResolution.x / uResolution.y，再把兩個軸都乘 0.58。
  // 搬到 4.83:1 的帶上，水平半角會由 46° 暴增至 70° → 魚眼 + 太陽橫向壓扁。
  // 改為「固定水平半角、垂直半角由 aspect 反推」，等價於在 16:9 全屏畫面中央裁一條橫切片：
  // 太陽／月亮維持正圓（兩軸共用同一角比例），海平線維持水平（只有 rd.y 決定天海分界）。
  vec2 ndc = (fragCoord / uResolution) * 2.0 - 1.0;
  // Flutter 的 FlutterFragCoord().y 由頂部向下遞增；原版 gl_FragCoord.y 由底部向上遞增。
  // 唔反轉就會成條帶上下倒轉（天空走到底部），所以呢一行係必要嘅座標系修正。
  ndc.y = -ndc.y;
  float aspect = uResolution.x / max(uResolution.y, 1.0);
  const float kHorizHalfTan = 1.03;              // 與 16:9 原版等價（1.778 × 0.58 ≈ 1.03）
  float vertHalfTan = kHorizHalfTan / aspect;    // 464×96 → 0.213（垂直半角約 ±12°）

  vec3 rd = normalize(uCamFwd + ndc.x * kHorizHalfTan * uCamRight + ndc.y * vertHalfTan * uCamUp);
  vec3 ro = uCamPos;
  vec3 sunDir = normalize(uSunDir);

  vec3 skyCol = renderSky(rd, sunDir);

  if (rd.y >= -0.001) {
    vec3 mappedSky = pow(clamp((skyCol * uExposure) / (1.0 + skyCol * uExposure), 0.0, 1.0), vec3(1.0 / 2.2));
    return vec4(mappedSky, 1.0);
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
  return vec4(pow(clamp(mapped, 0.0, 1.0), vec3(1.0 / 2.2)), 1.0);
}

void main() {
  fragColor = mainImage(FlutterFragCoord().xy);
}
