local AssetService = game:GetService("AssetService")
local UIS = game:GetService("UserInputService")
local Players = game:GetService("Players")

local player = Players.LocalPlayer

local screenGui = script.Parent.Parent.Parent
local imageLabel = script.Parent
local previewLabel = screenGui.MainFrame:WaitForChild("PreviewLabel")

local brushSize = 5
local originalBrushSize = brushSize
local transparency = 0
local color = Color3.new(0, 0, 0)
local originalColor = color
local drawing = false
local lastPoint = nil
local firstPoint = nil

local undoStack = {}
local redoStack = {}
local MAX_HISTORY = 20

local brushSizeValue = screenGui.MainFrame:WaitForChild("BrushSize")
local transparencyValue = screenGui.MainFrame:WaitForChild("TransparencyInt")
local colorValue = screenGui.MainFrame:WaitForChild("ColorV")
local canDrawValue = screenGui.MainFrame:WaitForChild("CanDraw")
local drawModeValue = screenGui.MainFrame:WaitForChild("DrawMode")

local combineType = Enum.ImageCombineType.BlendSourceOver
local IMAGE_SIZE = Vector2.new(512, 354)

local editableImage = AssetService:CreateEditableImage({Size = IMAGE_SIZE})
local previewImage = AssetService:CreateEditableImage({Size = IMAGE_SIZE})

local size = IMAGE_SIZE.X * IMAGE_SIZE.Y
local whiteBuffer = buffer.create(size * 4)
for i = 0, size - 1 do
	buffer.writeu8(whiteBuffer, i * 4 + 0, 255)
	buffer.writeu8(whiteBuffer, i * 4 + 1, 255)
	buffer.writeu8(whiteBuffer, i * 4 + 2, 255)
	buffer.writeu8(whiteBuffer, i * 4 + 3, 255)
end

editableImage:WritePixelsBuffer(Vector2.new(0, 0), IMAGE_SIZE, whiteBuffer)
imageLabel.ImageContent = Content.fromObject(editableImage)
previewLabel.ImageContent = Content.fromObject(previewImage)

local activeSabotages = {}

local function getPixelPos(inputPos)
	local relX = (inputPos.X - imageLabel.AbsolutePosition.X) / imageLabel.AbsoluteSize.X
	local relY = (inputPos.Y - imageLabel.AbsolutePosition.Y) / imageLabel.AbsoluteSize.Y

	local pixelPos = Vector2.new(
		math.clamp(math.floor(relX * IMAGE_SIZE.X), 0, IMAGE_SIZE.X - 1),
		math.clamp(math.floor(relY * IMAGE_SIZE.Y), 0, IMAGE_SIZE.Y - 1)
	)

	if activeSabotages["Inverted X Axis"] then
		pixelPos = Vector2.new(IMAGE_SIZE.X - 1 - pixelPos.X, pixelPos.Y)
	end
	if activeSabotages["Inverted Y Axis"] then
		pixelPos = Vector2.new(pixelPos.X, IMAGE_SIZE.Y - 1 - pixelPos.Y)
	end
	if activeSabotages["Wobbly Brush"] then
		pixelPos += Vector2.new(math.random(-4,4), math.random(-4,4))
	end
	
	return pixelPos
end

local function inputInLabel(inputPos)
	local pos = imageLabel.AbsolutePosition
	local size = imageLabel.AbsoluteSize
	return inputPos.X >= pos.X and inputPos.X <= pos.X + size.X
		and inputPos.Y >= pos.Y and inputPos.Y <= pos.Y + size.Y
end

local function drawThickLine(image, fromPos, toPos, radius, col, trans, comb, delayed)
	if activeSabotages["Delayed Pen"] and not delayed and image == editableImage then
		local fp, tp, r, c, tr, cb = fromPos, toPos, radius, col, trans, comb
		task.delay(0.25, function()
			drawThickLine(image, fp, tp, r, c, tr, cb, true)
		end)
		return
	end

	local distance = (toPos - fromPos).Magnitude
	local steps = math.max(1, distance / (radius * 0.35))
	for i = 0, steps do
		local alpha = i / steps
		local point = fromPos:Lerp(toPos, alpha)
		image:DrawCircle(point, radius, col, trans, comb, Enum.AntiAliasing.Enabled)
	end
end

local function drawCircleShape(image, center, edge, radius, col, trans, comb, delayed)
	if activeSabotages["Delayed Pen"] and not delayed and image == editableImage then
		local c, e, r, co, tr, cb = center, edge, radius, col, trans, comb
		task.delay(0.25, function()
			drawCircleShape(image, c, e, r, co, tr, cb, true)
		end)
		return
	end

	local circleRadius = (edge - center).Magnitude
	local points = 72
	local lastP = nil
	for i = 0, points do
		local rad = math.rad(i * (360 / points))
		local point = center + Vector2.new(math.cos(rad) * circleRadius, math.sin(rad) * circleRadius)
		if lastP then
			drawThickLine(image, lastP, point, radius, col, trans, comb, true)
		end
		lastP = point
	end
end

local function drawRectangle(image, p1, p2, radius, col, trans, comb, delayed)
	if activeSabotages["Delayed Pen"] and not delayed and image == editableImage then
		local a, b, r, c, tr, cb = p1, p2, radius, col, trans, comb
		task.delay(0.25, function()
			drawRectangle(image, a, b, r, c, tr, cb, true)
		end)
		return
	end

	local x1, y1 = math.min(p1.X, p2.X), math.min(p1.Y, p2.Y)
	local x2, y2 = math.max(p1.X, p2.X), math.max(p1.Y, p2.Y)
	local corners = {
		Vector2.new(x1, y1), Vector2.new(x2, y1),
		Vector2.new(x2, y2), Vector2.new(x1, y2),
		Vector2.new(x1, y1)
	}
	for i = 1, 4 do
		drawThickLine(image, corners[i], corners[i+1], radius, col, trans, comb, true)
	end
end

local function saveSnapshot()
	local snap = editableImage:ReadPixelsBuffer(Vector2.new(0, 0), IMAGE_SIZE)
	table.insert(undoStack, snap)
	if #undoStack > MAX_HISTORY then table.remove(undoStack, 1) end
	table.clear(redoStack)
end

local function undo()
	if #undoStack == 0 then return end
	local current = editableImage:ReadPixelsBuffer(Vector2.new(0, 0), IMAGE_SIZE)
	table.insert(redoStack, current)
	local snap = table.remove(undoStack)
	editableImage:WritePixelsBuffer(Vector2.new(0, 0), IMAGE_SIZE, snap)
end

local function redo()
	if #redoStack == 0 then return end
	local current = editableImage:ReadPixelsBuffer(Vector2.new(0, 0), IMAGE_SIZE)
	table.insert(undoStack, current)
	if #undoStack > MAX_HISTORY then table.remove(undoStack, 1) end
	local snap = table.remove(redoStack)
	editableImage:WritePixelsBuffer(Vector2.new(0, 0), IMAGE_SIZE, snap)
end

-- Sabotage
game.ReplicatedStorage.Remotes.ApplySabotage.OnClientEvent:Connect(function(sabotageType)
	activeSabotages[sabotageType] = true
	print(sabotageType)
	script.Parent.Parent.sabotage.Text = "Sabotage: " .. sabotageType

	if sabotageType == "Tiny Brush" then
		brushSizeValue.Value = 1
	elseif sabotageType == "Fat Brush" then
		brushSizeValue.Value = 20
	elseif sabotageType == "One Color" then
		colorValue.Value = Color3.new(0, 0, 0)
	end
	
	if sabotageType == "Blindness" then
		screenGui.MainFrame.Blind.Visible = true
	else
		screenGui.MainFrame.Blind.Visible = false
	end
end)

colorValue:GetPropertyChangedSignal("Value"):Connect(function()
	if activeSabotages["One Color"] then
		colorValue.Value = Color3.new(0, 0, 0)
	end
end)

brushSizeValue:GetPropertyChangedSignal("Value"):Connect(function()
	if activeSabotages["Tiny Brush"] then
		brushSizeValue.Value = 1
	elseif activeSabotages["Fat Brush"] then
		brushSizeValue.Value = 20
	end
end)

-- Phase handling (single connection)
game.ReplicatedStorage.Remotes.PhaseChanged.OnClientEvent:Connect(function(phase)
	if phase == "Voting" then
		drawing = false
		lastPoint = nil
		firstPoint = nil
		
		activeSabotages = {}
		script.Parent.Parent.sabotage.Text = "Sabotage: None" 
		brushSizeValue.Value = originalBrushSize
		colorValue.Value = originalColor
		local pixelBuffer = editableImage:ReadPixelsBuffer(Vector2.zero, IMAGE_SIZE)
		game.ReplicatedStorage.Remotes.SubmitDrawing:FireServer(pixelBuffer)
	end
end)

-- Input
UIS.InputBegan:Connect(function(input, processed)
	if processed or not screenGui.MainFrame.Visible then return end

	if input.KeyCode == Enum.KeyCode.Z then undo() return
	elseif input.KeyCode == Enum.KeyCode.Y then redo() return end

	combineType = Enum.ImageCombineType.BlendSourceOver

	if (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) and inputInLabel(input.Position) then
		brushSize = brushSizeValue.Value
		transparency = transparencyValue.Value
		color = activeSabotages["One Color"] and Color3.new(0, 0, 0) or colorValue.Value
		
		if activeSabotages["Random Colors"] then
			color = Color3.new(math.random(), math.random(), math.random())
		end

		local pixelPos = getPixelPos(input.Position)
		firstPoint = pixelPos

		if not canDrawValue.Value then
			local pixel = editableImage:ReadPixelsBuffer(pixelPos, Vector2.new(1, 1))
			colorValue.Value = Color3.new(buffer.readu8(pixel, 0)/255, buffer.readu8(pixel, 1)/255, buffer.readu8(pixel, 2)/255)
			canDrawValue.Value = true
			return
		end

		if drawModeValue.Value < 2 then
			saveSnapshot()
			drawing = true
			if drawModeValue.Value == 1 then
				transparency = 1
				color = Color3.new(1, 1, 1)
				combineType = Enum.ImageCombineType.Overwrite
			end
		elseif drawModeValue.Value == 2 and inputInLabel(input.Position) then
			saveSnapshot()
			local width, height = IMAGE_SIZE.X, IMAGE_SIZE.Y
			local imageBuffer = editableImage:ReadPixelsBuffer(Vector2.new(0, 0), IMAGE_SIZE)
			local visited = buffer.create(width * height)

			local startOffset = (pixelPos.Y * width + pixelPos.X) * 4
			local targetR = buffer.readu8(imageBuffer, startOffset)
			local targetG = buffer.readu8(imageBuffer, startOffset + 1)
			local targetB = buffer.readu8(imageBuffer, startOffset + 2)

			local fillColor = activeSabotages["One Color"] and Color3.new(0, 0, 0) or color
			local newR = math.round(fillColor.R * 255)
			local newG = math.round(fillColor.G * 255)
			local newB = math.round(fillColor.B * 255)
			local threshold = 13

			local stack = {pixelPos.Y * width + pixelPos.X}
			buffer.writeu8(visited, stack[1], 1)

			while #stack > 0 do
				local idx = table.remove(stack)
				local px = idx % width
				local py = math.floor(idx / width)
				local offset = idx * 4

				local r = buffer.readu8(imageBuffer, offset)
				local g = buffer.readu8(imageBuffer, offset + 1)
				local b = buffer.readu8(imageBuffer, offset + 2)

				if math.abs(r - targetR) <= threshold and math.abs(g - targetG) <= threshold and math.abs(b - targetB) <= threshold then
					buffer.writeu8(imageBuffer, offset, newR)
					buffer.writeu8(imageBuffer, offset + 1, newG)
					buffer.writeu8(imageBuffer, offset + 2, newB)
					buffer.writeu8(imageBuffer, offset + 3, 255)

					local neighbors = {{px+1,py},{px-1,py},{px,py+1},{px,py-1}}
					for _, n in neighbors do
						local nx, ny = n[1], n[2]
						if nx >= 0 and nx < width and ny >= 0 and ny < height then
							local nIdx = ny * width + nx
							if buffer.readu8(visited, nIdx) == 0 then
								buffer.writeu8(visited, nIdx, 1)
								table.insert(stack, nIdx)
							end
						end
					end
				end
			end
			editableImage:WritePixelsBuffer(Vector2.new(0, 0), IMAGE_SIZE, imageBuffer)
		end
	end
end)

UIS.InputEnded:Connect(function(input)
	if (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) and screenGui.MainFrame.Visible then
		if drawing then
			drawing = false
			local point = getPixelPos(input.Position)
			editableImage:DrawCircle(point, brushSize, color, math.pow(transparency, 1/brushSize), combineType, Enum.AntiAliasing.Enabled)
			firstPoint = nil
			lastPoint = nil
		elseif firstPoint and drawModeValue.Value > 2 then
			saveSnapshot()
			local currentPoint = getPixelPos(input.Position)
			local trans = math.pow(transparency, 1/brushSize)
			local fp = firstPoint -- capture before it gets cleared
			local dm = drawModeValue.Value

			local function doShapeDraw()
				if dm == 3 then
					drawThickLine(editableImage, fp, currentPoint, brushSize, color, trans, combineType, true)
				elseif dm == 4 then
					drawCircleShape(editableImage, fp, currentPoint, brushSize, color, trans, combineType, true)
				elseif dm == 5 then
					drawRectangle(editableImage, fp, currentPoint, brushSize, color, trans, combineType, true)
				end
			end

			if activeSabotages["Delayed Pen"] then
				task.delay(0.25, doShapeDraw)
			else
				doShapeDraw()
			end

			local clearBuffer = buffer.create(size * 4)
			previewImage:WritePixelsBuffer(Vector2.new(0, 0), IMAGE_SIZE, clearBuffer)
			firstPoint = nil
		end
	end
end)

UIS.InputChanged:Connect(function(input)
	if (input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch) or not screenGui.MainFrame.Visible then return end
	
	if activeSabotages["No Cursor"] then
		UIS.MouseIconEnabled =
			not inputInLabel(input.Position)
	else
		UIS.MouseIconEnabled = true
	end
	
	local pixelPos = getPixelPos(input.Position)

	if not canDrawValue.Value then
		local pixel = editableImage:ReadPixelsBuffer(pixelPos, Vector2.new(1, 1))
		colorValue.Value = Color3.new(buffer.readu8(pixel, 0)/255, buffer.readu8(pixel, 1)/255, buffer.readu8(pixel, 2)/255)
	end

	if drawing then
		local currentPoint = getPixelPos(input.Position)
		if lastPoint then
			drawThickLine(editableImage, lastPoint, currentPoint, brushSize, color, math.pow(transparency, 1/brushSize), combineType)
		end
		lastPoint = currentPoint
	end

	if firstPoint and drawModeValue.Value > 2 then
		local clearBuffer = buffer.create(size * 4)
		previewImage:WritePixelsBuffer(Vector2.new(0, 0), IMAGE_SIZE, clearBuffer)
		local currentPoint = getPixelPos(input.Position)
		local trans = math.pow(transparency, 1/brushSize)
		if drawModeValue.Value == 3 then
			drawThickLine(previewImage, firstPoint, currentPoint, brushSize, color, trans, combineType, true)
		elseif drawModeValue.Value == 4 then
			drawCircleShape(previewImage, firstPoint, currentPoint, brushSize, color, trans, combineType, true)
		elseif drawModeValue.Value == 5 then
			drawRectangle(previewImage, firstPoint, currentPoint, brushSize, color, trans, combineType, true)
		end
	end
end)

game.ReplicatedStorage.Remotes.ClearBoards.OnClientEvent:Connect(function()
	editableImage:WritePixelsBuffer(Vector2.new(0, 0), IMAGE_SIZE, whiteBuffer)
	table.clear(undoStack)
	table.clear(redoStack)
end)

game.ReplicatedStorage.Remotes.ShowVotingDrawing.OnClientEvent:Connect(function(userId, pixelBuffer)
	local p = game:GetService("Players"):GetPlayerByUserId(userId)
	screenGui.Voting.PlayerDrawing.Text = p.DisplayName .. "'s Drawing!"
	screenGui.votePrompt.Text = '"' .. game.ReplicatedStorage.Remotes.GetCurrentPrompt:InvokeServer() .. '"'
	local newImage = AssetService:CreateEditableImage({Size = IMAGE_SIZE})
	newImage:WritePixelsBuffer(Vector2.zero, IMAGE_SIZE, pixelBuffer)
	workspace.Frame.SurfaceGui.ImageLabel.ImageContent = Content.fromObject(newImage)
	
	UIS.MouseIconEnabled = true
	screenGui.MainFrame.Blind.Visible = false
end)

screenGui.MainFrame.Background2:WaitForChild("Undo").MouseButton1Click:Connect(undo)
screenGui.MainFrame.Background2:WaitForChild("Redo").MouseButton1Click:Connect(redo)
