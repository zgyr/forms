local component = require('component')
local computer = require('computer')
local gpu = component.gpu
local unicode = require('unicode')
local char = unicode.char
local len = unicode.len
local sub = unicode.sub
local block = char(0x2588)

local forms = {}
local mouseEv = {touch=true, scroll=true, drag=true, drop=true}
local activeForm

local baseComponent = {
  left = 1,
  top = 1,
  color = 0,
  textColor = 0xffffff,
  border = 0,
  visible = true,
  tag = 0,
  type = function() return 'unknown' end
}
baseComponent.__index = baseComponent

function baseComponent:paint() end

function baseComponent:isVisible()
  if not self.visible then return false end
  if self.parent then
    return self.parent:isVisible()
  else
    return self == activeForm
  end
end

function baseComponent:draw()
  if self.parent then
    self.X = self.parent.X + self.left - 1
    self.Y = self.parent.Y + self.top - 1
  else
    self.X = self.left
    self.Y = self.top
  end
  gpu.setBackground(self.color)
  gpu.setForeground(self.textColor)
  local brd = nil
  if self.border == 1 then
    brd = {0x256d, 0x2500, 0x256e, 0x2570, 0x2502, 0x256f}
  elseif self.border == 2 then
    brd = {0x250c, 0x2500, 0x2510, 0x2514, 0x2502, 0x2518}
  elseif self.border == 3 then
    brd = {0x2554, 0x2550, 0x2557, 0x255a, 0x2551, 0x255d}
  end
  if brd then
    for c = 1, #brd do
      brd[c] = char(brd[c])
    end
    gpu.set(self.X, self.Y, brd[1]..string.rep(brd[2], self.W-2)..brd[3])
    for i = self.Y+1, self.Y+self.H-2 do
      gpu.set(self.X, i, brd[5]..string.rep(' ', self.W-2)..brd[5])
    end
    gpu.set(self.X, self.Y+self.H-1, brd[4]..string.rep(brd[2], self.W-2)..brd[6])
  else
    gpu.fill(self.X, self.Y, self.W, self.H, ' ')
  end
  self:paint()
  if self.elements then
    for i = 1, #self.elements do
      if self.elements[i].visible then
        self.elements[i]:draw()
      end
    end
  end
end

function baseComponent:redraw()
  if self:isVisible() then
    self:draw()
  end
end

function baseComponent:makeChild(el)
  if not self.elements then self.elements = {} end
  el.parent = self
  table.insert(self.elements, el)
end

function baseComponent:mouseEv(ev, x, y, btn, user)
  if self.elements then
    for i = #self.elements, 1, -1 do
      local e = self.elements[i]
      if e.visible and e.X and x>=e.X and x<=e.X+e.W and y>=e.Y and y<e.Y+e.H then
        e:mouseEv(ev, x, y, btn, user)
        return
      end
    end
  end
  if self[ev] then
    self[ev](self, x-self.X+1, y-self.Y+1, btn, user)
  end
end

function baseComponent:hide()
  if self.parent then
    self.visible = false
    self.parent:draw()
  else
    gpu.setBackground(0)
    gpu.fill(self.X, self.Y, self.W, self.H, ' ')
  end
end
 
function baseComponent:show()
  if self.parent then
    self.visible=true
    self.parent:draw()
  else 
    self:draw()
  end
end
 
function baseComponent:destruct()
  if self.parent then
    for i=1,#self.parent.elements do
      if self.parent.elements[i]==self then table.remove(self.parent.elements,i) break end
    end
  end
end
 
function forms.activeForm() return activeForm end

function padRight(value, length)
  if not value or unicode.wlen(value) == 0 then
    return string.rep(' ', length)
  else
    return value .. string.rep(' ', length - unicode.wlen(value))
  end
end

function wrap(value, width, maxWidth)
  local line, nl = value:match('([^\r\n]*)(\r?\n?)')
  if unicode.wlen(line) > width then
    local partial = unicode.wtrunc(line, width)
    local wrapped = partial:match("(.*[^a-zA-Z0-9._()'`=])")
    if wrapped or unicode.wlen(line) > maxWidth then
      partial = wrapped or partial
      return partial, unicode.sub(value, unicode.len(partial) + 1), true
    else
      return '', value, true
    end
  end
  local start = unicode.len(line) + unicode.len(nl) + 1
  return line, start <= unicode.len(value) and unicode.sub(value, start) or nil, unicode.len(nl) > 0
end

----------- Visual components -----------
----------------- Form ------------------

local Form = setmetatable({type = function() return 'Form' end}, baseComponent)
Form.__index = Form

function Form:isActive() return self == activeForm end
 
function Form:setActive()
  if activeForm~=self then
    activeForm=self
    self:show()
  end  
end
 
function forms.addForm()
  local obj={}
  Form.W, Form.H = gpu.getResolution()
  return setmetatable(obj, Form)
end

---------------- Button -----------------

local Button = setmetatable(
  {
    color = 0x606060,
    type = function() return 'Button' end
  },
  baseComponent
)
Button.__index = Button

function Button:touch(x, y, btn, user)
  if btn == 0 then
    self.color, self.textColor = self.textColor, self.color
    self:redraw()
    if self.onClick then
      self:onClick(user)
    end
    self.color, self.textColor = self.textColor, self.color
    self:redraw()
  end
end
 
function Button:paint()
  gpu.set(self.X+(self.W-len(self.caption))/2, self.Y+(self.H-1)/2, self.caption)
end
 
function baseComponent:addButton(left, top, W, H, caption, onClick)
  local obj={left=left, top=top, W=W or 10, H=H or 1, caption=caption or 'Button', onClick=onClick}
  self:makeChild(obj)
  return setmetatable(obj, Button)
end

---------------- Label ------------------

local Label = setmetatable(
  {
    H = 1,
    centered = false,
    alignRight = false,
    autoSize = true,
    type = function() return 'Label' end
  },
  baseComponent
)
Label.__index = Label

function Label:paint()
  local line
  local value = tostring(self.caption)
  if self.autoSize then
    self.W, self.H = 0, 0
    for line in value:gmatch('([^\n]+)') do
      self.H = self.H + 1
      if len(line) > self.W then
        self.W = len(line)
      end
    end
    if self.W < 1 then self.W = 1 end
    if self.H < 1 then self.H = 1 end
  end
  for i = 0, self.H-1 do
    if not value then break end
    line, value = wrap(value, self.W, self.W)
    if self.centered then
       gpu.set(self.X + (self.W - len(line)) / 2, self.Y + i, line)
    else
      if self.alignRight then
        gpu.set(self.X + self.W - len(line), self.Y + i, line)
      else
        gpu.set(self.X, self.Y+i, line)
      end
    end
  end
end

function baseComponent:addLabel(left, top, caption)
  local obj = {left = left, top = top, caption = caption or 'Label'}
  obj.W = len(obj.caption)
  self:makeChild(obj)
  return setmetatable(obj, Label)
end

---------------- Frame ------------------

local Frame = setmetatable(
  {
    W = 20,
    H = 10,
    border = 1,
    type = function() return 'Frame' end
  },
  baseComponent
)
Frame.__index = Frame

function baseComponent:addFrame(left, top, border)
  local obj = {left = left, top = top, border = border}
  self:makeChild(obj)
  return setmetatable(obj, Frame)
end

---------------- Edit -------------------

local Edit = setmetatable({
  W = 20,
  H = 3,
  text = '',
  border = 3,
  type = function() return 'Edit' end
  },
  baseComponent
)

Edit.__index = Edit

function Edit:paint()
  local b = self.border == 0 and 0 or 1
  gpu.set(self.X+b, self.Y+b, sub(self.text, 1, self.W-2*b))
end

local function editText(text, left, top, W, H)
  local running = true
  local posX = 1
  local scrollX = 0
  
  local function writeText()
    gpu.fill(left, top, W, H, ' ')
    local buff = sub(text, 1, posX-1) .. block .. sub(text, posX)
    gpu.set(left, top, sub(buff, scrollX+1, scrollX+W))
  end

  local function setCursor(nx)
    posX = nx or posX
    if posX > len(text) + 1 then posX = len(text) + 1 end
    if posX < 1 then posX = 1 end
    if posX <= scrollX then scrollX = posX-1 end
    if posX > scrollX+W then scrollX = posX-W end
  end
  
  local function insert(value)
    if not value or len(value) < 1 then return end
    text = sub(text, 1, posX-1) .. value .. sub(text, posX)
    setCursor(posX + len(value))
  end
    
  local keys = {
    [203] = function() setCursor(posX - 1) end,
    [205] = function() setCursor(posX + 1) end,
    [199] = function() setCursor(1) end,
    [207] = function() setCursor(len(text) + 1) end,
    [211] = function()
      if posX <= len(text) then
        text = sub(text, 1, posX - 1) .. sub(text, posX + 1)
      end
    end,
    [14] = function()
      if posX > 1 then
        text = sub(text, 1, posX - 2) .. sub(text, posX)
        setCursor(posX - 1)
      end
    end,
    [28] = function() running = false end
  }
  
  local function onKeyDown(chr, code)
    if keys[code] then
      keys[code]()
    else
      if chr > 31 then
        insert(char(chr))
      end
    end
    writeText()
  end
  
  local function onClipboard(value)
    if value then
      text = sub(text, 1, posX-1) .. value .. sub(text, posX)
      writeText()
    end
  end
  
  local function onClick(x, y)
    if x >= left and x < left+W and y >= top and y < top+H then
      setCursor(x+scrollX-left+1, y-top+1)
      writeText()
    else
      running = false
    end
  end
     
  local event, address, arg1, arg2, arg3
  while running do
    event, address, arg1, arg2, arg3 = computer.pullSignal()
    if event == 'key_down' then onKeyDown(arg1, arg2)
    elseif event == 'clipboard' then onClipboard(arg1)
    elseif event == 'touch' then onClick(arg1, arg2)
    end
  end
  return text
end

function Edit:touch(x, y, btn, user)
  local b = self.border == 0 and 0 or 1
  if btn == 0 then
    gpu.setBackground(self.color)
    gpu.setForeground(self.textColor)
    self.text = editText(self.text, self.X+b, self.Y+b, self.W-2*b, 1)
    self:draw()
    if self.onEnter then
      self:onEnter(user)
    end
  end
end

function baseComponent:addEdit(left, top, W, H, onEnter)
  local obj = {left = left, top = top, W = W, H = H, onEnter}
  self:makeChild(obj)
  return setmetatable(obj, Edit)
end

---------------- List -------------------

local List = setmetatable(
  {
    W = 20,
    H = 10,
    border = 3,
    selColor = 0x0000ff,
    sfColor = 0xffff00,
    shift = 0,
    index = 0,
    type = function() return 'List' end
  },
  baseComponent
)
List.__index = List

function List:paint()
  local b = self.border == 0 and 0 or 1
  for i = 1, self.H-2*b do
    if i + self.shift == self.index then
      gpu.setForeground(self.sfColor)
      gpu.setBackground(self.selColor)
    end
    gpu.set(self.X + b, self.Y+i+b-1, padRight(sub(self.lines[i+self.shift] or '', 1, self.W-2*b), self.W-2*b))
    if i + self.shift == self.index then
      gpu.setForeground(self.textColor)
      gpu.setBackground(self.color)
    end
  end
end

function List:clear()
  self.shift = 0
  self.index = 0
  self.lines = {}
  self.items = {}
  self:redraw()
end

function List:insert(pos, line, item)
  if type(pos) ~= 'number' then
    pos, line, item = #self.lines + 1, pos, line
  end
  table.insert(self.lines, pos, line)
  table.insert(self.items, pos, item or false)
  if self.index < 1 then self.index = 1 end
  if pos < self.shift + self.H - 1 then self:redraw() end
end

function List:sort(comp)
  comp = comp or function(list, i, j) return list.lines[j]<list.lines[i] end
  for i = 1, #self.lines - 1 do
    for j = i + 1, #self.lines do
      if comp(self, i, j) then
        if self.index == i then
          self.index = j
        elseif self.index == j then
          self.index = i
        end
        self.lines[i], self.lines[j] = self.lines[j], self.lines[i]
        self.items[i], self.items[j] = self.items[j], self.items[i]
      end
    end
  end
  self:redraw()
end

function List:touch(x, y, btn, user)
  local b = self.border == 0 and 0 or 1
  if x > b and x <= self.W-b and y > b and y <= self.H -b and btn == 0 then
    local i = self.shift + y - b
    if self.index ~= i and self.lines[i] then
      self.index = i
      self:redraw()
      if self.onChange then
        self:onChange(self.lines[i], self.items[i], user)
      end
    end
  end
end

function List:scroll(x, y, sh, user)
  local b = self.border == 0 and 0 or 1
  self.shift = self.shift - sh
  if self.shift > #self.lines - self.H + 2 * b then
    self.shift = #self.lines - self.H + 2 * b
  end
  if self.shift < 0 then self.shift = 0 end
  self:redraw()
end

function baseComponent:addList(left, top, W, H, onChange)
  local obj = {left = left, top = top, W = W or 20, H = H or 10, lines = {}, items = {}, onChange = onChange}
  self:makeChild(obj)
  return setmetatable(obj, List)
end

---------- Nonvisual components ---------
local work

local Invisible = setmetatable({W = 10, H = 3, border = 2, draw = function() end}, baseComponent)

Invisible.__index = Invisible

---------------- Event ------------------

local Event = setmetatable({type = function() return 'Event' end}, Invisible)

Event.__index = Event

function Event:run()
  if self.onEvent then
    forms.listen(self.eventName, self.onEvent)
  end
end

function Event:stop()
  forms.ignore(self.eventName, self.onEvent)
end

function baseComponent:addEvent(eventName, onEvent)
  local obj = {eventName = eventName, onEvent = onEvent}
  self:makeChild(obj)
  setmetatable(obj, Event)
  obj:run()
  return obj
end

---------------- Timer ------------------
--[[
local Timer = setmetatable({Enabled = true, type = function() return 'Timer' end}, Invisible)

Timer.__index = Timer

function Timer:run()
  self.Enabled = nil
  if self.onTime then
    self.timerId = event.timer(self.interval,
      function()
        if self.Enabled and work then
          self.onTime(self)
        else
          self:stop()
        end
      end,
      math.huge
    )
  end
end

function Timer:stop()
  slef.Enabled = false
  event.cancel(self.timerId)
end

function baseComponent:addTimer(interval, onTime)
  local obj = {interval = interval, onTime = onTime}
  self:makeChild(obj)
  setmetatable(obj, Timer)
  obj:run()
  return obj
end
]]
------------- Event handler -------------

local listeners = {}

function forms.listen(name, callback)
  if type(name) ~= 'string' or type(callback) ~= 'function' then
    return nil
  end
  if listeners[name] then
    for i = 1, #listeners[name] do
      if listeners[name][i] == callback then
        return false
      end
    end
  else
    listeners[name] = {}
  end
  table.insert(listeners[name], callback)
  return true
end

function forms.ignore(name, callback)
  if type(name) ~= 'string' or type(callback) ~= 'function' then
    return nil
  end
  if listeners[name] then
    for i = 1, #listeners[name] do
      if listeners[name][i] == callback then
        table.remove(listeners[name], i)
        if #listeners[name] == 0 then
          listeners[name] = nil
        end
        return true
      end
    end
  end
end

function forms.ignoreAll()
  listeners = {}
end

------------------- ---------------------

function forms.run(form)
  local screen = gpu.getScreen()
  work = true
  local fC, bC = gpu.getForeground(), gpu.getBackground()
  activeForm = form
  activeForm:draw()
  while work do
    local ev, address, x, y, btn, user = computer.pullSignal()
    if mouseEv[ev] and address == screen then
      activeForm:mouseEv(ev, x, y, btn, user)
    end
    if listeners[''] then
      for i = 1, #listeners[''] do
        listeners[''][i](ev, address, x, y, btn, user)
      end
    end
  end
  gpu.setForeground(fC)
  gpu.setBackground(bC)
  forms.ignoreAll()
end

function forms.stop()
  work = false
end

return forms