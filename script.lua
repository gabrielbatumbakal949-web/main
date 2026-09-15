--!nonstrict
--[[ SmoothLock — hold RMB | Q cycle | LAlt release | P toggle panel ]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local LP = Players.LocalPlayer
local Cam = Workspace.CurrentCamera

local CFG = {
	HoldKey     = Enum.UserInputType.MouseButton2,
	CycleKey    = Enum.KeyCode.Q,
	ReleaseKey  = Enum.KeyCode.LeftAlt,
	PanelKey    = Enum.KeyCode.P,

	FOV         = 60,
	MaxDist     = 200,
	Smooth      = 0.08,
	AcquireTime = 0.18,
	AimPart     = "HumanoidRootPart",
	TeamCheck   = true,
	WallCheck   = true,
	AliveOnly   = true,

	UI = {
		StartVisible = false,
		Pos  = UDim2.new(0, 20, 0, 120),
		Size = UDim2.fromOffset(220, 78),
		Trans = 0.35,
	},
}

local State = {
	Holding = false,
	Released = false,
	Locked = nil,
	Candidates = {},
	AcquireStart = 0,
}

local function active()
	return State.Holding and not State.Released
end

-- Helpers
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function isAlive(char)
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	return hum and hum.Health > 0
end

local function getPart(char)
	if not char then return nil end
	local p = char:FindFirstChild(CFG.AimPart)
	return (p and p:IsA("BasePart") and p) or char.PrimaryPart or char:FindFirstChildWhichIsA("BasePart")
end

local function screenMag(pos)
	local vp = Cam.ViewportSize
	local sp, on = Cam:WorldToViewportPoint(pos)
	if not on then return nil end
	return (Vector2.new(sp.X, sp.Y) - Vector2.new(vp.X * 0.5, vp.Y * 0.5)).Magnitude
end

local function hasLOS(char, aimPos)
	if not CFG.WallCheck then return true end
	rayParams.FilterDescendantsInstances = {LP.Character, Cam}
	local res = Workspace:Raycast(Cam.CFrame.Position, aimPos - Cam.CFrame.Position, rayParams)
	return not res or res.Instance:IsDescendantOf(char)
end

-- Targeting
local function collect()
	local list, camPos = {}, Cam.CFrame.Position
	for _, plr in Players:GetPlayers() do
		if plr == LP then continue end
		local char = plr.Character
		if not char then continue end
		if CFG.AliveOnly and not isAlive(char) then continue end
		if CFG.TeamCheck and plr.Team and plr.Team == LP.Team then continue end

		local part = getPart(char)
		if not part then continue end

		local dist = (part.Position - camPos).Magnitude
		if dist > CFG.MaxDist then continue end

		local mag = screenMag(part.Position)
		if not mag or mag > CFG.FOV then continue end
		if not hasLOS(char, part.Position) then continue end

		table.insert(list, {
			Player = plr,
			Char = char,
			Part = part,
			Off = mag,
		})
	end
	table.sort(list, function(a, b) return a.Off < b.Off end)
	return list
end

local function alpha(dt)
	return 1 - (1 - CFG.Smooth) ^ (dt * 60)
end

local function acquireScale()
	if CFG.AcquireTime <= 0 then return 1 end
	return math.clamp((os.clock() - State.AcquireStart) / CFG.AcquireTime, 0, 1)
end

-- UI
local parent = (gethui and gethui()) or LP:WaitForChild("PlayerGui")
local gui = Instance.new("ScreenGui")
gui.Name = "SL"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 999
gui.Parent = parent

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.Position = CFG.UI.Pos
panel.Size = CFG.UI.Size
panel.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
panel.BackgroundTransparency = CFG.UI.Trans
panel.BorderSizePixel = 0
panel.Visible = CFG.UI.StartVisible
panel.Parent = gui

Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 8)
local stroke = Instance.new("UIStroke", panel)
stroke.Color = Color3.fromRGB(70, 70, 80)
stroke.Thickness = 1
stroke.Transparency = 0.55

-- Header (drag handle)
local header = Instance.new("TextLabel", panel)
header.BackgroundTransparency = 1
header.Position = UDim2.new(0, 10, 0, 4)
header.Size = UDim2.new(1, -20, 0, 16)
header.Font = Enum.Font.GothamMedium
header.TextSize = 11
header.TextColor3 = Color3.fromRGB(170, 170, 180)
header.TextXAlignment = Enum.TextXAlignment.Left
header.Text = "SmoothLock"
header.Active = true

local status = Instance.new("TextLabel", panel)
status.BackgroundTransparency = 1
status.Position = UDim2.new(0, 10, 0, 20)
status.Size = UDim2.new(1, -20, 0, 12)
status.Font = Enum.Font.Gotham
status.TextSize = 10
status.TextColor3 = Color3.fromRGB(120, 160, 200)
status.TextXAlignment = Enum.TextXAlignment.Left
status.Text = "Idle"

-- Dragging
do
	local dragging, dragStart, startPos
	header.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = input.Position
			startPos = panel.Position
		end
	end)
	UIS.InputChanged:Connect(function(input)
		if not dragging then return end
		if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
			local delta = input.Position - dragStart
			panel.Position = UDim2.new(
				startPos.X.Scale, startPos.X.Offset + delta.X,
				startPos.Y.Scale, startPos.Y.Offset + delta.Y
			)
		end
	end)
	UIS.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)
end

-- Slider
local function makeSlider(y, init, min, max, cb)
	local row = Instance.new("Frame", panel)
	row.BackgroundTransparency = 1
	row.Position = UDim2.new(0, 10, 0, y)
	row.Size = UDim2.new(1, -20, 0, 34)

	local lab = Instance.new("TextLabel", row)
	lab.BackgroundTransparency = 1
	lab.Size = UDim2.new(0.6, 0, 0, 12)
	lab.Font = Enum.Font.Gotham
	lab.TextSize = 10
	lab.TextColor3 = Color3.fromRGB(180, 180, 190)
	lab.TextXAlignment = Enum.TextXAlignment.Left
	lab.Text = "Smoothness"

	local val = Instance.new("TextLabel", row)
	val.BackgroundTransparency = 1
	val.Size = UDim2.new(1, 0, 0, 12)
	val.Font = Enum.Font.Gotham
	val.TextSize = 10
	val.TextColor3 = Color3.fromRGB(140, 180, 220)
	val.TextXAlignment = Enum.TextXAlignment.Right
	val.Text = string.format("%.3f", init)

	local track = Instance.new("Frame", row)
	track.BackgroundColor3 = Color3.fromRGB(40, 40, 46)
	track.BorderSizePixel = 0
	track.Position = UDim2.new(0, 0, 0, 18)
	track.Size = UDim2.new(1, 0, 0, 6)
	Instance.new("UICorner", track).CornerRadius = UDim.new(1, 0)

	local fill = Instance.new("Frame", track)
	fill.BackgroundColor3 = Color3.fromRGB(140, 180, 220)
	fill.BorderSizePixel = 0
	fill.Size = UDim2.new((init - min) / (max - min), 0, 1, 0)
	Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)

	local knob = Instance.new("Frame", track)
	knob.BackgroundColor3 = Color3.fromRGB(220, 220, 225)
	knob.BorderSizePixel = 0
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.Position = UDim2.new((init - min) / (max - min), 0, 0.5, 0)
	knob.Size = UDim2.fromOffset(11, 11)
	Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)

	local drag = false
	local function upd(x)
		local a = math.clamp((x - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
		local v = min + (max - min) * a
		fill.Size = UDim2.new(a, 0, 1, 0)
		knob.Position = UDim2.new(a, 0, 0.5, 0)
		val.Text = string.format("%.3f", v)
		cb(v)
	end

	local function beginDrag(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			drag = true
			upd(input.Position.X)
		end
	end

	track.InputBegan:Connect(beginDrag)
	knob.InputBegan:Connect(beginDrag)

	UIS.InputChanged:Connect(function(input)
		if drag and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			upd(input.Position.X)
		end
	end)

	UIS.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			drag = false
		end
	end)
end

makeSlider(36, CFG.Smooth, 0.01, 0.5, function(v) CFG.Smooth = v end)

-- Optional full cleanup
local function destroyUI()
	gui:Destroy()
end

-- Input
local function setHold(v)
	if State.Holding == v then return end
	State.Holding = v
	if not v then
		State.Locked = nil
		status.Text = "Idle"
	end
end

UIS.InputBegan:Connect(function(input, gp)
	if input.KeyCode == CFG.PanelKey then
		panel.Visible = not panel.Visible
		return
	end
	if gp then return end

	if input.UserInputType == CFG.HoldKey then
		setHold(true)
	elseif input.KeyCode == CFG.CycleKey and active() then
		local list = State.Candidates
		if #list >= 2 then
			local idx = 1
			for i, c in ipairs(list) do
				if c.Char == State.Locked then
					idx = i
					break
				end
			end
			local next = list[(idx % #list) + 1]
			State.Locked = next.Char
			State.AcquireStart = os.clock()
			status.Text = next.Player.Name
		end
	elseif input.KeyCode == CFG.ReleaseKey then
		State.Released = true
	end
end)

UIS.InputEnded:Connect(function(input)
	if input.UserInputType == CFG.HoldKey then
		setHold(false)
	elseif input.KeyCode == CFG.ReleaseKey then
		State.Released = false
	end
end)

-- Camera loop
local BIND = "SmoothLock"
pcall(function() RunService:UnbindFromRenderStep(BIND) end)

RunService:BindToRenderStep(BIND, Enum.RenderPriority.Camera.Value + 1, function(dt)
	if not Cam or not Cam.Parent then return end

	if not active() then
		State.Locked = nil
		State.Candidates = {}
		status.Text = "Idle"
		return
	end

	local cands = collect()
	State.Candidates = cands

	if #cands == 0 then
		State.Locked = nil
		status.Text = "No target"
		return
	end

	-- Validate current lock
	local target
	if State.Locked then
		for _, c in cands do
			if c.Char == State.Locked and isAlive(c.Char) then
				target = c
				break
			end
		end
		if not target then
			State.Locked = nil
		end
	end

	-- Acquire new if needed
	if not target then
		target = cands[1]
		State.Locked = target.Char
		State.AcquireStart = os.clock()
	end

	status.Text = target.Player.Name

	local aim = target.Part.Position
	local cur = Cam.CFrame
	if (aim - cur.Position).Magnitude < 0.05 then return end

	local desired = CFrame.lookAt(cur.Position, aim)
	Cam.CFrame = cur:Lerp(desired, alpha(dt) * acquireScale())
end)
