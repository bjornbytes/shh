local shh = require 'shh'

function lovr.load()
  skybox = lovr.graphics.newTexture('assets/industrial_workshop_foundry_2k.hdr', {
    usage = { 'storage', 'sample' }
  })

  colors = shh.new(skybox)

  print('Coefficients:')
  for i, color in ipairs(colors) do
    print(i, ('% 6f % 6f % 6f'):format(unpack(color)))
  end
end

function lovr.draw(pass)
  pass:skybox(skybox)
  shh.setShader(pass, colors)
  pass:sphere(0, 1.7, -2)
end
