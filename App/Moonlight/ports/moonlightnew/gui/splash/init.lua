-- This is an altered version of the original splashlib script.
-- Changes made: (Custom timing, logo, credited name, added animations)
-- Original version available at: https://github.com/love2d-community/splashes

local splashlib = {
  _VERSION     = "v1.2.0",
  _DESCRIPTION = "a 0.10.1 splash",
  _URL         = "https://github.com/love2d-community/splashes",
  _LICENSE     = [[Copyright (c) 2016 love-community members (as per git commits in repository above)

This software is provided 'as-is', without any express or implied
warranty. In no event will the authors be held liable for any damages
arising from the use of this software.

Permission is granted to anyone to use this software for any purpose,
including commercial applications, and to alter it and redistribute it
freely, subject to the following restrictions:

1. The origin of this software must not be misrepresented; you must not
   claim that you wrote the original software. If you use this software
   in a product, an acknowledgement in the product documentation would be
   appreciated but is not required.
2. Altered source versions must be plainly marked as such, and must not be
   misrepresented as being the original software.
3. This notice may not be removed or altered from any source distribution.

The font used in this splash is "Handy Andy" by www.andrzejgdula.com]]
}

local current_module = (...):gsub("%.init$", "")
local current_folder = current_module:gsub("%.", "/")

local timer = require(current_module .. ".timer")

local colors = {
  bg =     {.42, .75, .89},
  white =  {  1,   1,   1},
  blue =   {.15, .67, .88},
  pink =   {.91, .29,  .6},
  shadow = {0, 0, 0, .33},
}


-- patch shader:send if 'lighten' gets optimized away
local function safesend(shader, name, ...)
  if shader:hasUniform(name) then
    shader:send(name, ...)
  end
end




function splashlib.new(init)
  init = init or {}
  local self = {}
  local width, height = love.graphics.getDimensions()

  self.background = init.background == nil and colors.bg or init.background
  self.delay_before = init.delay_before or 0.1
  self.delay_after = init.delay_after or 2.6

  -- radial mask shader
  self.maskshader = love.graphics.newShader((init.fill == "lighten" and "#define LIGHTEN" or "") .. [[

  extern number radius;
  extern number blur;
  extern number shadow;
  extern number lighten;

  vec4 desat(vec4 color) {
    number g = dot(vec3(.299, .587, .114), color.rgb);
    return vec4(g, g, g, 1.0) * lighten;
  }

  vec4 effect(vec4 global_color, Image canvas, vec2 tc, vec2 _)
  {
    // radial mask
    vec4 color = Texel(canvas, tc);
    number r = length((tc - vec2(.5)) * love_ScreenSize.xy);
    number s = smoothstep(radius+blur, radius-blur, r);
    #ifdef LIGHTEN
    color = color + desat(color) * (1.0-s);
    #else
    color.a *= s;
    #endif
    color.a *= global_color.a;

    // add shadow on lower diagonal along the circle
    number sr = 7. * (1. - smoothstep(-.1,.04,(1.-tc.x)-tc.y));
    s = (1. - pow(exp(-pow(radius-r, 2.) / sr),3.) * shadow);

    return color - vec4(1, 1, 1, 0) * (1.0-s);
  }
  ]])

  -- this shader makes the text appear from left to right
  self.textshader = love.graphics.newShader[[
  extern number alpha;

  vec4 effect(vec4 color, Image logo, vec2 tc, vec2 sc)
  {
    //Probably would be better to just use the texture's dimensions instead; faster reaction.
    vec2 sd = sc / love_ScreenSize.xy;

    if (sd.x <= alpha) {
      return color * Texel(logo, tc);
    }
    return vec4(0);
  }
  ]]

  -- this shader applies a stroke effect on the logo using a gradient mask
  self.logoshader = love.graphics.newShader[[
  //Using the pen extern, only draw out pixels that have their color below a certain treshold.
  //Since pen will eventually equal 1.0, the full logo will be drawn out.

  extern number pen;
  extern Image mask;

  vec4 effect(vec4 color, Image logo, vec2 tc, vec2 sc)
  {
    number value = max(Texel(mask, tc).r, max(Texel(mask, tc).g, Texel(mask, tc).b));
    number alpha = Texel(mask, tc).a;

    //probably could be optimized...
    if (alpha > 0.0) {
      if (pen >= value) {
        return color * Texel(logo, tc);
      }
    }
    return vec4(0);
  }
  ]]

  self.canvas = love.graphics.newCanvas()

  self.elapsed = 0
  self.alpha = 1
  self.heart = {
    sprite = love.graphics.newImage(current_folder .. "/heart.png"),
    scale = 0,
    rot   = 0
  }

  self.boat = {
    sprite = love.graphics.newImage(current_folder .. "/boat.png"),
    scale = 0,
    rot   = 0
  }

  self.stripes = {
    rot     = 0,
    height  = 100,
    offset  = -2 * width,
    radius  = math.max(width, height),
    lighten = 0,
    shadow  = 0,
  }

  self.text = {
    obj   = love.graphics.newText(love.graphics.newFont(current_folder .. "/handy-andy.otf", 24*(height/600)), "made with"),
    alpha = 0
  }

  self.text.width, self.text.height = self.text.obj:getDimensions()

  self.logo = {
    sprite = love.graphics.newImage(current_folder .. "/logo.png"),
    mask   = love.graphics.newImage(current_folder .. "/logo-mask.png"),
    pen    = 0
  }
  self.logo.width, self.logo.height = self.logo.sprite:getDimensions()

  safesend(self.maskshader, "radius",  width*height)
  safesend(self.maskshader, "lighten", 0)
  safesend(self.maskshader, "shadow",  0)
  safesend(self.maskshader, "blur",    1)

  safesend(self.textshader, "alpha", 0)

  safesend(self.logoshader, "pen", 0)
  safesend(self.logoshader, "mask", self.logo.mask)

  timer.clear()
  timer.script(function(wait)

    wait(self.delay_before)

   

    -- hackety hack: execute timer to update shader every frame
    timer.every(0, function()
      safesend(self.maskshader, "radius", self.stripes.radius)
      safesend(self.maskshader, "lighten", self.stripes.lighten)
      safesend(self.maskshader, "shadow", self.stripes.shadow)
      safesend(self.textshader, "alpha", self.text.alpha)
      safesend(self.logoshader, "pen", self.logo.pen)
    end)
	
	  -- roll in stripes
    timer.tween(0.5, self.stripes, {offset = 0})
    wait(0.3)

    timer.tween(0.3, self.stripes, {rot = -5 * math.pi / 18, height = height})
    wait(0.2)


    -- focus the heart, desaturate the rest
    timer.tween(0.2, self.stripes, {radius = 200 * (height / 600)})
    timer.tween(0.4, self.stripes, {lighten = 0.06}, "quad")
    wait(0.2)

    timer.tween(0.2, self.stripes, {radius = 90 * (height / 600)}, "out-back")
    timer.tween(0.5, self.stripes, {shadow = 0.3}, "back")
    timer.tween(0.5, self.heart, {scale = 1.5}, "out-elastic", nil, 1, 0.4)

    -- write out the text
    timer.tween(0.75, self.text, {alpha = 1}, "linear")

    -- draw out the logo, in parts
    local mult = 0.8
    local function tween_and_wait(dur, pen, easing)
      timer.tween(mult * dur, self.logo, {pen = pen / 255}, easing)
      wait(mult * dur)
    end
    tween_and_wait(0.175, 50, "in-quad")     -- L
    tween_and_wait(0.300, 100, "in-out-quad") -- O
    tween_and_wait(0.075, 115, "out-sine")    -- first dot on O
    tween_and_wait(0.075, 129, "out-sine")    -- second dot on O
    tween_and_wait(0.125, 153, "in-out-quad") -- \
    tween_and_wait(0.075, 179, "in-quad")     -- /
    tween_and_wait(0.250, 205, "in-quart")    -- e->break
    tween_and_wait(0.150, 230, "out-cubic")   -- e finish
    tween_and_wait(0.150, 244, "linear")      -- ()
    tween_and_wait(0.100, 255, "linear")      -- R

    -- rotate stripes back to zero and change color to orange
    timer.tween(0.2, colors.pink, {0.30196, 0.7451, 0.9333}, "linear")
	timer.tween(0.2, colors.blue, {0.3765, 0.6588, 0.8667}, "linear")
    timer.tween(0.2, self.heart, {scale = 0}, "in-quad", nil, 1, 1)
    timer.tween(0.4, self.stripes, {rot = 0}, "out-back", function()
      timer.tween(0.6, self.boat, {scale = 1.2}, "out-elastic", nil, 1, 0.4)
    end)

-- fade everything to transparent with a delay
timer.after(2, function()
  timer.tween(0.3, self, {alpha = 0})
  timer.tween(0.3, self.text, {alpha = 0})
  timer.tween(0.3, self.logo, {pen = 0})
end)



    wait(self.delay_after)

    -- finalize
    timer.clear()
    self.done = true

    if self.onDone then self.onDone() end
  end)

  self.draw = splashlib.draw
  self.update = splashlib.update
  self.skip = splashlib.skip

  return self
end











function splashlib:draw()
  local width, height = love.graphics.getDimensions()
  local scale_factor = height / 600  -- Calculate scale factor based on reference height of 600 pixels

  -- Calculate positions
  local logoY = height * 0.82  -- Position logo at 0.5 of the height from the top

  -- Calculate vertical positions for text1 and text2
  local font_size = 24 * scale_factor
  love.graphics.setFont(love.graphics.newFont(current_folder .. "/handy-andy.otf", font_size))

  local text1 = self.text.obj  -- Assuming self.text.obj is the first text object
  local text2 = "by JanTrueno"

  local text1Y = logoY - text1:getHeight() / 2 - (64 * scale_factor)
  local text2Y = logoY - text1:getHeight() / 2 + (64 * scale_factor)

  -- Clear background if necessary
  if self.background then
    love.graphics.clear(self.background)
  end

  -- Perform any animation or canvas operations
  if self.fill and self.elapsed > self.delay_before + 0.6 then
    self:fill()
  end

  self.canvas:renderTo(function()
    love.graphics.clear()  -- Clear the canvas if needed

    love.graphics.push()
    love.graphics.translate(width / 2, height / 2)

    -- Draw your elements here, e.g., rotated rectangles
    love.graphics.push()
    love.graphics.rotate(self.stripes.rot)
    love.graphics.setColor(colors.pink)
    love.graphics.rectangle(
      "fill",
      self.stripes.offset - width, -self.stripes.height * scale_factor,
      width * 2, self.stripes.height * scale_factor
    )

    love.graphics.setColor(colors.blue)
    love.graphics.rectangle(
      "line",
      -width - self.stripes.offset, 0,
      width * 2, self.stripes.height * scale_factor
    )
    love.graphics.rectangle(
      "fill",
      -width - self.stripes.offset, 0,
      width * 2, self.stripes.height * scale_factor
    )
    love.graphics.pop()

    -- Draw the heart sprite
    love.graphics.setColor(1, 1, 1, self.heart.scale)
    love.graphics.draw(
      self.heart.sprite,
      0, 0,
      self.heart.rot,
      self.heart.scale * (height / 600),
      self.heart.scale * (height / 600),
      40, 36
    )

     -- Draw the heart sprite
    love.graphics.setColor(1, 1, 1, self.boat.scale)
    love.graphics.draw(
      self.boat.sprite,
      0, 0,
      self.boat.rot,
      self.boat.scale/1.9 * (height / 600),
      self.boat.scale/1.9 * (height / 600),
     146, 150
    )

    love.graphics.pop()  -- Pop the translation
  end)

  love.graphics.setColor(1, 1, 1, self.alpha)
  love.graphics.setShader(self.maskshader)
  love.graphics.draw(self.canvas, 0, 0)
  love.graphics.setShader()

  -- Draw text2 under the logo
  love.graphics.push()
  love.graphics.setShader(self.textshader)
  love.graphics.setColor(1, 1, 1, self.text.alpha)

  local text2Width = love.graphics.getFont():getWidth(text2)
  love.graphics.print(
    text2,
    (width / 2) - (text2Width / 2),
    text2Y  -- Adjusted Y position for text2
  )
  love.graphics.pop()

  -- Draw text1 above the logo
  love.graphics.push()
  love.graphics.setShader(self.textshader)
  love.graphics.draw(
    text1,
    (width / 2) - (text1:getWidth() / 2),
    text1Y   -- Adjusted Y position for text1
  )
  love.graphics.pop()

  -- Draw logo
  love.graphics.push()
  love.graphics.setShader(self.logoshader)
  love.graphics.draw(
    self.logo.sprite,
    width / 2,  -- Center X position
    logoY,      -- Center Y position
    0,          -- Rotation angle
    0.5 * scale_factor,  -- Scale factor X
    0.5 * scale_factor,  -- Scale factor Y
    self.logo.sprite:getWidth() / 2,  -- Offset X (center of the sprite)
    self.logo.sprite:getHeight() / 2  -- Offset Y (center of the sprite)
  )
  love.graphics.setShader()
  love.graphics.pop()
end







function splashlib:update(dt)
  timer.update(dt)
  self.elapsed = self.elapsed + dt
end

function splashlib:skip()
  if not self.done then
    self.done = true

    timer.tween(0.3, self, {alpha = 0})
    timer.after(0.3, function ()
      timer.clear() -- to be safe
      if self.onDone then self.onDone() end
    end)
  end
end

setmetatable(splashlib, { __call = function(self, ...) return self.new(...) end })

return splashlib
