local shh = {}

-- Math Helpers

local SH = {}
SH.__index = SH

function shh.new(t)
  local self = setmetatable({}, SH)

  for i = 1, 9 do
    self[i] = { 0, 0, 0 }
  end

  self:set(t)
  return self
end

function SH:clear()
  for i = 1, 9 do
    self[i][1] = 0
    self[i][2] = 0
    self[i][3] = 0
  end
end

local tempPass
local tempBuffer
function SH:set(t)
  if not t then
    self:clear()
  elseif type(t) == 'table' and type(t[1]) == 'table' then
    for i = 1, 9 do
      self[i][1] = t[i][1]
      self[i][2] = t[i][2]
      self[i][3] = t[i][3]
    end
  elseif type(t) == 'table' and type(t[1]) == 'number' then
    for i = 1, 9 do
      local b = (i - 1) * 3
      self[i][1] = t[b + 1]
      self[i][2] = t[b + 2]
      self[i][3] = t[b + 3]
    end
  elseif type(t) == 'string' then
    local texture = lovr.graphics.newTexture(t, { usage = { 'storage' } })
    self:set(texture)
    texture:release()
  elseif type(t) == 'userdata' and t:type() == 'Texture' then
    tempPass = tempPass or lovr.graphics.newPass()
    tempBuffer = tempBuffer or lovr.graphics.newBuffer('vec4', 9)
    tempPass:reset()
    shh.compute(tempPass, t, tempBuffer)
    lovr.graphics.submit(tempPass)
    return self:set(tempBuffer:getData())
  else
    error('Expected nil, table of numbers, or table of tables')
  end
end

local function evaluate(t, c, nx, ny, nz)
  return
    .88622692545276 * t[1][c] +
    1.0233267079465 * t[2][c] * ny +
    1.0233267079465 * t[3][c] * nz +
    1.0233267079465 * t[4][c] * nx +
    .85808553080978 * t[5][c] * nx * ny +
    .85808553080978 * t[6][c] * ny * nz +
    .24770795610038 * t[7][c] * (3 * nz * nz - 1) +
    .85808553080978 * t[8][c] * nx * nz +
    .42904276540489 * t[9][c] * (nx * nx - ny * ny)
end

function SH:evaluate(nx, ny, nz)
  if type(nx) == 'userdata' then
    nx, ny, nz = nx:unpack()
  end

  local r = evaluate(self, 1, nx, ny, nz)
  local g = evaluate(self, 2, nx, ny, nz)
  local b = evaluate(self, 3, nx, ny, nz)

  return r, g, b
end

function SH:addAmbientLight(r, g, b)
  local scale = 3.544907701811 -- 2 * math.pi ^ .5
  self[1][1] = self[1][1] + scale * .28209479177388 * r
  self[1][2] = self[1][2] + scale * .28209479177388 * g
  self[1][3] = self[1][3] + scale * .28209479177388 * b
end

local function integrate(t, c, x, dx, dy, dz)
  t[1][c] = t[1][c] + .28209479177388 * x
  t[2][c] = t[2][c] + .48860251190292 * x * dy
  t[3][c] = t[3][c] + .48860251190292 * x * dz
  t[4][c] = t[4][c] + .48860251190292 * x * dx
  t[5][c] = t[5][c] + 1.0925484305921 * x * dx * dy
  t[6][c] = t[6][c] + 1.0925484305921 * x * dy * dz
  t[7][c] = t[7][c] + .31539156525252 * x * (3 * dz * dz - 1)
  t[8][c] = t[8][c] + 1.0925484305921 * x * dx * dz
  t[9][c] = t[9][c] + .54627421529604 * x * (dx * dx - dy * dy)
end

function SH:addDirectionalLight(dx, dy, dz, r, g, b)
  local scale = 2.9567930857316 -- 16 * math.pi / 17
  r, g, b = r * scale, g * scale, b * scale
  integrate(self, 1, r, dx, dy, dz)
  integrate(self, 2, g, dx, dy, dz)
  integrate(self, 3, b, dx, dy, dz)
end

function SH:add(other)
  for i = 1, 9 do
    for c = 1, 3 do
      self[i][c] = self[i][c] + other[i][c]
    end
  end
end

function SH:lerp(other, t)
  for i = 1, 9 do
    for c = 1, 3 do
      self[i][c] = self[i][c] + (other[i][c] - self[i][c]) * t
    end
  end
end

function SH:scale(s)
  for i = 1, 9 do
    for c = 1, 3 do
      self[i][c] = self[i][c] * s
    end
  end
end

-- Shaders

local cubeShader = [[
#define RGBA8 0
#define RGBA16F 1
#define RGBA32F 2
#define RG11B10F 3

layout(constant_id = 0) const uint FORMAT = RGBA8;

layout(binding = 0, rgba8) uniform readonly imageCube TextureRGBA8;
layout(binding = 0, rgba16f) uniform readonly imageCube TextureRGBA16F;
layout(binding = 0, rgba32f) uniform readonly imageCube TextureRGBA32F;
layout(binding = 0, r11f_g11f_b10f) uniform readonly imageCube TextureRG11B10F;
layout(binding = 1, std140) buffer writeonly Basis { vec3 basis[9]; };

#define THREADS 96
layout(local_size_x = 4, local_size_y = 4, local_size_z = 6) in;
shared vec3 coefficients[THREADS][9];
shared float totalAngle[THREADS];

void lovrmain() {
  uint id = LocalThreadIndex;
  uint face = LocalThreadID.z;

  totalAngle[id] = 0.;
  for (int i = 0; i < 9; i++) {
    coefficients[id][i] = vec3(0.);
  }

  int size = imageSize(TextureRGBA8).x;
  int tile = size / int(WorkgroupSize.x);
  ivec2 origin = ivec2(LocalThreadID.xy) * tile;

  for (int y = 0; y < tile; y++) {
    for (int x = 0; x < tile; x++) {
      ivec2 xy = origin + ivec2(x, y);
      vec2 uv = (xy + .5) / size * 2. - 1.;

      // Note: Z coordinate is flipped to convert to left-handed cubemap coordinate space

      vec3 dir;
      switch (face) {
        case 0: dir = vec3(+1., -uv.y, +uv.x); break;
        case 1: dir = vec3(-1., -uv.y, -uv.x); break;
        case 2: dir = vec3(+uv.x, +1., -uv.y); break;
        case 3: dir = vec3(+uv.x, -1., +uv.y); break;
        case 4: dir = vec3(+uv.x, -uv.y, -1.); break;
        case 5: dir = vec3(-uv.x, -uv.y, +1.); break;
      }

      float len2 = dot(dir, dir);
      float len = sqrt(len2);
      dir *= 1. / len;

      float solidAngle = 4. / (len2 * len); // (uv^2)^(3/2) == len(uv)^2 * len(uv)
      totalAngle[id] += solidAngle;

      vec3 color;
      ivec3 texel = ivec3(xy, face);
      if (FORMAT == RGBA8) color = gammaToLinear(imageLoad(TextureRGBA8, texel).rgb);
      if (FORMAT == RGBA16F) color = imageLoad(TextureRGBA16F, texel).rgb;
      if (FORMAT == RGBA32F) color = imageLoad(TextureRGBA32F, texel).rgb;
      if (FORMAT == RG11B10F) color = imageLoad(TextureRG11B10F, texel).rgb;
      color *= solidAngle;

      coefficients[id][0] += color * .28209479177388;
      coefficients[id][1] += color * .48860251190292 * dir.y;
      coefficients[id][2] += color * .48860251190292 * dir.z;
      coefficients[id][3] += color * .48860251190292 * dir.x;
      coefficients[id][4] += color * 1.0925484305921 * dir.x * dir.y;
      coefficients[id][5] += color * 1.0925484305921 * dir.y * dir.z;
      coefficients[id][6] += color * .31539156525252 * (3. * dir.z * dir.z - 1.);
      coefficients[id][7] += color * 1.0925484305921 * dir.x * dir.z;
      coefficients[id][8] += color * .54627421529604 * (dir.x * dir.x - dir.y * dir.y);
    }
  }

  barrier();

  if (id == 0) {
    for (int t = 1; t < THREADS; t++) {
      totalAngle[0] += totalAngle[t];
      for (int i = 0; i < 9; i++) {
        coefficients[0][i] += coefficients[t][i];
      }
    }

    float scale = 4. * PI / totalAngle[0];

    for (int i = 0; i < 9; i++) {
      basis[i] = coefficients[0][i] * scale;
    }
  }
}
]]

local equirectShader = [[
#define RGBA8 0
#define RGBA16F 1
#define RGBA32F 2
#define RG11B10F 3

layout(constant_id = 0) const uint FORMAT = RGBA8;

layout(binding = 0, rgba8) uniform readonly image2D TextureRGBA8;
layout(binding = 0, rgba16f) uniform readonly image2D TextureRGBA16F;
layout(binding = 0, rgba32f) uniform readonly image2D TextureRGBA32F;
layout(binding = 0, r11f_g11f_b10f) uniform readonly image2D TextureRG11B10F;
layout(binding = 1, std140) buffer writeonly Basis { vec3 basis[9]; };

#define THREADS 64
layout(local_size_x = 8, local_size_y = 8) in;
shared vec3 coefficients[THREADS][9];
shared float totalAngle[THREADS];

void lovrmain() {
  uint id = LocalThreadIndex;

  totalAngle[id] = 0.;
  for (int i = 0; i < 9; i++) {
    coefficients[id][i] = vec3(0.);
  }

  ivec2 size = imageSize(TextureRGBA8);
  ivec2 tile = (size + ivec2(7, 7)) / ivec2(WorkgroupSize.xy);
  ivec2 origin = ivec2(LocalThreadID.xy) * tile;
  float width = size.x;
  float height = size.y;

  for (int y = 0; y < tile.y; y++) {
    if (origin.y + y >= size.y) continue;
    float phi = (origin.y + y) / height * PI;
    float sinphi = sin(phi);
    float cosphi = cos(phi);

    for (int x = 0; x < tile.x; x++) {
      if (origin.x + x >= size.x) continue;
      float theta = (.75 - (origin.x + x) / width) * 2. * PI;

      float solidAngle = (2. * PI / width) * (PI / height) * abs(sinphi);
      totalAngle[id] += solidAngle;

      vec3 color;
      ivec2 texel = origin + ivec2(x, y);
      if (FORMAT == RGBA8) color = gammaToLinear(imageLoad(TextureRGBA8, texel).rgb);
      if (FORMAT == RGBA16F) color = imageLoad(TextureRGBA16F, texel).rgb;
      if (FORMAT == RGBA32F) color = imageLoad(TextureRGBA32F, texel).rgb;
      if (FORMAT == RG11B10F) color = imageLoad(TextureRG11B10F, texel).rgb;
      color *= solidAngle;

      vec3 dir = normalize(vec3(cos(theta) * sinphi, cosphi, -sin(theta) * sinphi));
      coefficients[id][0] += color * .28209479177388;
      coefficients[id][1] += color * .48860251190292 * dir.y;
      coefficients[id][2] += color * .48860251190292 * dir.z;
      coefficients[id][3] += color * .48860251190292 * dir.x;
      coefficients[id][4] += color * 1.0925484305921 * dir.x * dir.y;
      coefficients[id][5] += color * 1.0925484305921 * dir.y * dir.z;
      coefficients[id][6] += color * .31539156525252 * (3. * dir.z * dir.z - 1.);
      coefficients[id][7] += color * 1.0925484305921 * dir.x * dir.z;
      coefficients[id][8] += color * .54627421529604 * (dir.x * dir.x - dir.y * dir.y);
    }
  }

  barrier();

  if (id == 0) {
    for (int t = 1; t < THREADS; t++) {
      totalAngle[0] += totalAngle[t];
      for (int i = 0; i < 9; i++) {
        coefficients[0][i] += coefficients[t][i];
      }
    }

    float scale = 4. * PI / totalAngle[0];

    for (int i = 0; i < 9; i++) {
      basis[i] = coefficients[0][i] * scale;
    }
  }
}
]]

local formatCodes = {
  rgba8 = 0,
  rgba16f = 1,
  rgba32f = 2,
  rg11b10f = 3
}

local shaders = {}

local function getComputeShader(kind, format)
  local code = kind == 'cube' and cubeShader or equirectShader
  local options = { flags = { FORMAT = formatCodes[format] } }

  if not shaders[kind] then
    shaders[kind] = {}
    shaders[kind][format] = lovr.graphics.newShader(code, options)
  elseif not shaders[kind][format] then
    shaders[kind][format] = shaders[kind][next(shaders[kind])]:clone(options)
  end

  return shaders[kind][format]
end

function shh.compute(pass, texture, buffer, offset)
  local kind, format, width, height = texture:getType(), texture:getFormat(), texture:getDimensions()

  if kind == 'cube' then
    assert(width % 4 == 0, 'Currently, cubemap dimensions must be a multiple of 4 (please open issue)')
  elseif kind == '2d' then
    assert(width == 2 * height, '2D equirectangular textures should have a 2:1 aspect ratio')
  else
    error('Expected 2d or cubemap texture')
  end

  assert(formatCodes[format], ('Unsupported texture format %q'):format(format))

  pass:push('state')
  pass:setShader(getComputeShader(kind, format))
  pass:send('Basis', buffer, offset)
  pass:send('TextureRGBA8', texture)
  pass:compute()
  pass:pop('state')

  return buffer
end

-- Convenience shader helper

local shader
function shh.setShader(pass, ...)
  if not shader then
    shader = lovr.graphics.newShader('unlit', [[
      layout(set = 2, binding = 0) uniform SH { vec3 sh[9]; };

      vec3 evaluateSH(vec3 sh[9], vec3 n) {
        return max(
          .88622692545276 * sh[0] +
          1.0233267079465 * sh[1] * n.y +
          1.0233267079465 * sh[2] * n.z +
          1.0233267079465 * sh[3] * n.x +
          .85808553080978 * sh[4] * n.x * n.y +
          .85808553080978 * sh[5] * n.y * n.z +
          .24770795610038 * sh[6] * (3 * n.z * n.z - 1) +
          .85808553080978 * sh[7] * n.x * n.z +
          .42904276540489 * sh[8] * (n.x * n.x - n.y * n.y),
          0
        );
      }

      vec4 lovrmain() {
        return vec4(evaluateSH(sh, normalize(Normal)) / PI, 1.);
      }
    ]])
  end
  pass:setShader(shader)
  if ... then pass:send('SH', ...) end
end

return shh
