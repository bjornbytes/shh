local shh = {}

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

return shh
