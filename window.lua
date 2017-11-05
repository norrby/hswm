local pkg = {}

local border = dofile( os.getenv("HOME") .. "/.hammerspoon/border.lua")
local tools = dofile( os.getenv("HOME") .. "/.hammerspoon/tools.lua")
local tree = dofile( os.getenv("HOME") .. "/.hammerspoon/tree.lua")

pkg.GLOBAL = {}

local events = hs.uielement.watcher

local watchers = {}
local bdw = {}
local workspace = {}

local current_space = {}

local mouse_loc = nil
local cur_node = nil
local new_node = nil


local disableClick = false
local isSwap = false
local isResize = false

local spaces = require("hs._asm.undocumented.spaces")

-- a placeholder
pkg.window_manager = function()
end

local function space_manager(spaceid)
    spaceid = spaces.activeSpace()
    local global_padding = pkg.GLOBAL.global_padding

    if workspace[spaceid] == nil then
        workspace[spaceid] = {}
    end

    current_space = workspace[spaceid]

    if current_space.root == nil then
        current_space.root = tree.initTreeforWorkSpace(global_padding)
    end

    pkg.root = nil
    pkg.root = current_space.root
    if previous_border ~= nil then
        previous_border:hide()
    end

    hs.timer.doAfter(0, pkg.window_manager)

    pkg.GLOBAL.root = pkg.root

    return false
end

pkg.space_manager = space_manager

local function window_manager(t) 
    local global_padding = pkg.GLOBAL.global_padding
    local window_padding = pkg.GLOBAL.window_padding
    local root = pkg.root

    if root == nil then
        pkg.space_manager()
        return
    end

    if t == "timer" then
        local tm = function ()
            window_manager("timer")
        end
        hs.timer.doAfter(10, tm)
    end

    local function compare(a,b)
        return a:id() < b:id()
    end
	local ws = hs.window.visibleWindows()

    table.sort(ws, compare)

    local mmm = {}
    tree.travelTree(root, mmm)

    local father = tree.findFatherOfNode(root, focusedWindowID)

    local mm = {}

    for i = 1, #ws do
        local w = ws[i]
        if w:application():name() ~= "Hammerspoon" and w:isStandard() then
            if not mmm[w:id()] then
                if father == nil then
                    tree.insertToTree(root, w)
                else
                    if father.left.windowId == focusedWindowID then
                        tree.insertToNode(father.left, w)
                    else
                        tree.insertToNode(father.right, w)
                    end

                    if father.left == nil then
                    end
                end
            end
            mm[w:id()] = ws[i]
        end
    end


    tree.deleteZombies(root, mm)
    tree.deleteWindowFromTree(root, -1, global_padding)


    local dic = {}
    tree.travelTreeAndTiling(root, dic, window_padding)

    local screen = hs.screen.mainScreen():name()

    for i  = 1, #ws do 
        local w = ws[i]
        if dic[w:id()] then
            local f = function()
                w:setFrame(dic[w:id()])
            end
            f()
        end
    end


    local f = function()

        local fw = hs.window.focusedWindow()
        if fw ~= nil then
            focusedWindowID = fw:id()
        else
            return
        end

        local frame = fw:frame()
        if bdw[fw:id()] == nil then
            bdw[fw:id()] = border.init_border()
        end

        bdw[fw:id()]:setFrame(frame)

        if previous_border ~= nil and previous_border ~= bdw[fw:id()] then
            previous_border:hide()
        end

        if previous_border ~= bdw[fw:id()] then
            bdw[fw:id()]:show()
        end

        previous_border = bdw[fw:id()]

    end
    f()
end

pkg.window_manager = window_manager

local function handleGlobalAppEvent(name, event, app)
  if  event == hs.application.watcher.launched then
    watchApp(app)
  elseif event == hs.application.watcher.terminated then
    -- Clean up
    local appWatcher = watchers[app:pid()]
    if appWatcher then
      appWatcher.watcher:stop()

      for id, watcher in pairs(appWatcher.windows) do
        watcher:stop()
      end
      watchers[app:pid()] = nil
    end
  end
  hs.timer.doAfter(0, window_manager)
  return false
end

pkg.handleGlobalAppEvent = handleGlobalAppEvent

local function handleWindowEvent(win, event, watcher, info)
  if event == events.elementDestroyed then
    watcher:stop()
    watchers[info.pid].windows[info.id] = nil
    if bdw[win:id()] ~= nil then
        bdw[win:id()]:delete()
        bdw[win:id()] = nil 
    end
    tree.deleteWindowFromTree(root, win:id(), global_padding)
  end

  hs.timer.doAfer(0, window_manager)

  return false
end

pkg.handleWindowEvent = handleWindowEvent

local function watchWindow(win, initializing)
  local appWindows = watchers[win:application():pid()].windows
  if  win:isStandard() and not appWindows[win:id()] and win:application():name() ~= "Hammerspoon" then
    local watcher = win:newWatcher(pkg.handleWindowEvent, {pid=win:pid(), id=win:id()})
    appWindows[win:id()] = watcher

    watcher:start({events.elementDestroyed})

    if not initializing then
    end
  end
end

pkg.watchWindow = watchWindow

local function handleAppEvent(element, event)
  if event == events.windowCreated then
    watchWindow(element)
  elseif event == events.focusedWindowChanged then
    -- Handle window change
  end

  hs.timer.doAfter(0, window_manager)
  return false
end

pkg.handleAppEvent = handleAppEvent


local function watchApp(app, initializing)
  if watchers[app:pid()] then return end

  local watcher = app:newWatcher(pkg.handleAppEvent)
  watchers[app:pid()] = {watcher = watcher, windows = {}}

  watcher:start({events.windowCreated, events.focusedWindowChanged, events.mainWindowChanged, events.titleChanged})

  -- Watch any windows that already exist
  for i, window in pairs(app:allWindows()) do

    bdw[window:id()] = border.init_border()
    bdw[window:id()]:hide()

    watchWindow(window, initializing)
  end
end

pkg.watchApp = watchApp




local windowResizeAndSwap = function(ev)
    local root = pkg.root
    local result = ev:getFlags().ctrl

    if ev:getType() == hs.eventtap.event.types.leftMouseUp or 
        ev:getType() == hs.eventtap.event.types.flagsChanged or 
        ev:getType() == hs.eventtap.event.types.rightMouseUp then

        disableClick = false

        if root.canvas ~= nil then
            root.canvas:delete()
            root.canvas = nil
        end

        if isSwap then
            isSwap = false

            if cur_node ~= nil and new_node ~= nil and cur_node ~= new_node then
                local t = cur_node.windowId
                cur_node.windowId = new_node.windowId
                new_node.windowId = t
                hs.timer.doAfter(0, window_manager)
            end

            cur_node = nil
            new_node = nil
        end

        if isResize then
            isResize = false
            border.convertFromBorderToFrame(root)
            hs.timer.doAfter(0, window_manager)
            cur_node = nil
            new_node = nil
        end
    end

    if result then
        disableClick = true
    end

    if disableClick then
        if ev:getType() == hs.eventtap.event.types.rightMouseDown then

            disableClick = false
            isResize = true
            mouse_loc = hs.mouse.getAbsolutePosition()
            cur_node = tree.findNodewithPointer(root, mouse_loc)

            for i, appWatcher in pairs(watchers) do
               if appWatcher then
                  for id, watcher in pairs(appWatcher.windows) do
                    watcher:stop()
                  end
               end
            end

            return true
        end

    end

    if disableClick then
        if ev:getType() == hs.eventtap.event.types.leftMouseDown then

            disableClick = false

            isSwap = true
            mouse_loc = hs.mouse.getAbsolutePosition()
            cur_node = tree.findNodewithPointer(root, mouse_loc)

            root.canvas = hs.canvas.new(border.cloneBorder(hs.screen.mainScreen():frame()))
            root.canvas:alpha(1)

            root.canvas:wantsLayer(true)
            root.canvas:show()


            if cur_node ~= nil then
                root.canvas:appendElements( border.create_canvas_border(cur_node.frame) )
            end

            return true
        end
    end

    if isResize then
        if ev:getType() == hs.eventtap.event.types.rightMouseDragged then

            local t = root.canvas

            root.canvas = hs.canvas.new(border.cloneBorder(hs.screen.mainScreen():frame()))
            root.canvas:alpha(1)

            local ml = hs.mouse.getAbsolutePosition()
            local dx = ml.x - mouse_loc.x
            local dy = ml.y - mouse_loc.y
            tree.resizeNode(root, cur_node, dx, dy)
            root.canvas:wantsLayer(true)
            border.travelAndAppendToCanvas(root, root.canvas)
            root.canvas:show()

            if t ~= nil then
                t:delete()
            end


            return false
        end
    end

    if isSwap then
        if ev:getType() == hs.eventtap.event.types.leftMouseDragged then
        local ml = hs.mouse.getAbsolutePosition()
        local temp_new_node = new_node

        new_node = tree.findNodewithPointer(root, ml)

        local tt = root.canvas

        root.canvas = hs.canvas.new(border.cloneBorder(hs.screen.mainScreen():frame()))
        root.canvas:alpha(1)
        root.canvas:wantsLayer(true)
        root.canvas:show()

        if cur_node ~= nil then
            root.canvas:appendElements( border.create_canvas_border(cur_node.frame) )
        end

        if new_node ~= nil then
            root.canvas:appendElements( border.create_canvas_border(new_node.frame) )
        end

        if tt ~= nil then
            tt:delete()
            tt = nil
        end

        return false
        end
    end

    return false
end

--
-- verify that *only* the ctrl key flag is being pressed
local function onlyShiftCmd(ev)

    hs.timer.doAfter(0, function()
        windowResizeAndSwap(ev)
    end)

    if disableClick then
        if ev:getType() == hs.eventtap.event.types.leftMouseDown or ev:getType() == hs.eventtap.event.types.rightMouseDown then
            return true
        end
    end

    return false 
end

local tt = 0
local function onlyShiftCmd3(ev)
    windowResizeAndSwap(ev)
    return false 
end


local ttt = hs.eventtap.event.types

pkg.resizeWatcher1 = hs.eventtap.new({ttt.rightMouseUp}, onlyShiftCmd3)

pkg.resizeWatcher1:start()

pkg.resizeWatcher3 = hs.eventtap.new({ttt.rightMouseDragged}, onlyShiftCmd)
pkg.resizeWatcher3:start()

pkg.resizeWatcher2 = hs.eventtap.new({ttt.flagsChanged, ttt.keyDown, ttt.keyUp, ttt.leftMouseDown, ttt.leftMouseDragged, ttt.leftMouseUp, ttt.rightMouseDown}, onlyShiftCmd)

pkg.resizeWatcher2:start()


pkg.spaceWatcher = hs.spaces.watcher.new(pkg.space_manager)
pkg.spaceWatcher:start()


local function init(GLOBAL)
  appsWatcher = hs.application.watcher.new(pkg.handleGlobalAppEvent)
  appsWatcher:start()

  pkg.GLOBAL = GLOBAL

  -- Watch any apps that already exist
  local apps = hs.application.runningApplications()
  for i = 1, #apps do
      if apps[i]:name() ~= "Hammerspoon" then
          print(apps[i]:name())
          watchApp(apps[i], true)
      end
  end
  window_manager("timer")
end

pkg.init = init

return pkg
