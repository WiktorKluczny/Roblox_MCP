local HttpService = game:GetService("HttpService")
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local ScriptEditorService = game:GetService("ScriptEditorService")
local LogService = game:GetService("LogService")
local Selection = game:GetService("Selection")
local StudioService = game:GetService("StudioService")
local StudioCaptureService = game:GetService("StudioCaptureService")
local AssetService = game:GetService("AssetService")
local RunService = game:GetService("RunService")

local BASE_URL = "http://127.0.0.1:8767"
local POLL_DELAY = 0.1
local CONNECTION_RETRY_DELAY = 3

local function log(...)
	print("[Roblox MCP]", ...)
end

local function warnLog(...)
	warn("[Roblox MCP]", ...)
end

local function resolve(path)
	if type(path) ~= "string" or path == "" then
		error("Invalid instance path")
	end

	local current = game

	for name in string.gmatch(path, "[^%.]+") do
		if name ~= "game" then
			local nextInstance = current:FindFirstChild(name)

			if not nextInstance then
				error(
					"Could not resolve '" ..
					path ..
					"': '" ..
					name ..
					"' not found under " ..
					current:GetFullName()
				)
			end

			current = nextInstance
		end
	end

	return current
end

local function getPath(instance)
	if instance == game then
		return "game"
	end

	return instance:GetFullName()
end

local function beginRecording(name)
	return ChangeHistoryService:TryBeginRecording(
		name,
		"Roblox MCP: " .. name
	)
end

local function finishRecording(recording, commit)
	if not recording then
		return
	end

	if commit then
		ChangeHistoryService:FinishRecording(
			recording,
			Enum.FinishRecordingOperation.Commit
		)
	else
		ChangeHistoryService:FinishRecording(
			recording,
			Enum.FinishRecordingOperation.Cancel
		)
	end
end

local function sendResult(commandId, result)
	local success, response = pcall(function()
		return HttpService:RequestAsync({
			Url = BASE_URL .. "/result",
			Method = "POST",
			Headers = {
				["Content-Type"] = "application/json"
			},
			Body = HttpService:JSONEncode({
				id = commandId,
				result = result
			})
		})
	end)

	if not success then
		warnLog("Could not send result:", response)
		return false
	end

	if not response.Success then
		warnLog(
			"Result request failed:",
			response.StatusCode,
			response.Body
		)

		return false
	end

	return true
end

local handlers = {}

handlers.list_children = function(args)
	local instance = resolve(args.path)
	local children = {}

	for _, child in ipairs(instance:GetChildren()) do
		table.insert(children, {
			name = child.Name,
			className = child.ClassName,
			path = getPath(child)
		})
	end

	return {
		output = HttpService:JSONEncode(children)
	}
end

handlers.search_game_tree = function(args)
	local root = resolve(args.path or "game")
	local query = string.lower(args.query or "")
	local results = {}

	local function search(instance)
		for _, child in ipairs(instance:GetChildren()) do
			if query == ""
				or string.find(
					string.lower(child.Name),
					query,
					1,
					true
				)
			then
				table.insert(results, {
					name = child.Name,
					className = child.ClassName,
					path = getPath(child)
				})
			end

			search(child)
		end
	end

	search(root)

	return {
		output = HttpService:JSONEncode(results)
	}
end

handlers.inspect_instance = function(args)
	local instance = resolve(args.path)
	local attributes = {}

	for name, value in instance:GetAttributes() do
		attributes[name] = value
	end

	return {
		output = HttpService:JSONEncode({
			name = instance.Name,
			className = instance.ClassName,
			path = getPath(instance),
			parent = instance.Parent and getPath(instance.Parent) or nil,
			attributes = attributes
		})
	}
end

handlers.script_read = function(args)
	local scriptInstance = resolve(args.path)

	if not scriptInstance:IsA("LuaSourceContainer") then
		error("Instance is not a script: " .. args.path)
	end

	local source = ScriptEditorService:GetEditorSource(
		scriptInstance
	)

	return {
		output = source
	}
end

handlers.multi_edit = function(args)
	local scriptInstance = resolve(args.path)

	if not scriptInstance:IsA("LuaSourceContainer") then
		error("Instance is not a script")
	end

	if type(args.source) ~= "string" then
		error("args.source must be a string")
	end

	local recording = beginRecording("multi_edit")

	local success, err = pcall(function()
		ScriptEditorService:UpdateSourceAsync(
			scriptInstance,
			function()
				return args.source
			end
		)
	end)

	if success then
		finishRecording(recording, true)

		return {
			output = "Script updated: " .. args.path
		}
	else
		finishRecording(recording, false)
		error(err)
	end
end

handlers.script_search = function(args)
	local query = args.query

	if type(query) ~= "string" then
		error("args.query must be a string")
	end

	local results = {}

	for _, instance in ipairs(game:GetDescendants()) do
		if instance:IsA("LuaSourceContainer") then
			local source = ScriptEditorService:GetEditorSource(
				instance
			)

			local lineNumber = 0

			for line in string.gmatch(
				source .. "\n",
				"(.-)\n"
			) do
				lineNumber += 1

				if string.find(
					string.lower(line),
					string.lower(query),
					1,
					true
				) then
					table.insert(results, {
						path = getPath(instance),
						line = lineNumber,
						text = line
					})
				end
			end
		end
	end

	return {
		output = HttpService:JSONEncode(results)
	}
end

handlers.script_grep = function(args)
	local query = args.query

	if type(query) ~= "string" then
		error("args.query must be a string")
	end

	local results = {}

	for _, instance in ipairs(game:GetDescendants()) do
		if instance:IsA("LuaSourceContainer") then
			local source = ScriptEditorService:GetEditorSource(
				instance
			)

			if string.find(
				string.lower(source),
				string.lower(query),
				1,
				true
			) then
				table.insert(results, {
					path = getPath(instance),
					className = instance.ClassName
				})
			end
		end
	end

	return {
		output = HttpService:JSONEncode(results)
	}
end

handlers.execute_luau = function(args)
	if type(args.code) ~= "string" then
		error("args.code must be a string")
	end

	local fn, compileError = loadstring(args.code)

	if not fn then
		error(
			"Luau compile error: " ..
			tostring(compileError)
		)
	end

	local success, result = pcall(fn)

	if not success then
		error(
			"Luau runtime error: " ..
			tostring(result)
		)
	end

	return {
		output = tostring(
			result or
			"Luau executed successfully"
		)
	end
end

handlers.get_selection = function()
	local selected = {}

	for _, instance in ipairs(Selection:Get()) do
		table.insert(selected, {
			name = instance.Name,
			className = instance.ClassName,
			path = getPath(instance)
		})
	end

	return {
		output = HttpService:JSONEncode(selected)
	}
end

handlers.set_selection = function(args)
	local instances = {}

	for _, path in ipairs(args.paths or {}) do
		table.insert(instances, resolve(path))
	end

	Selection:Set(instances)

	return {
		output = "Selection updated"
	}
end

handlers.create_instance = function(args)
	local parent = resolve(args.parent)

	if type(args.className) ~= "string" then
		error("className required")
	end

	local recording = beginRecording("create_instance")

	local success, result = pcall(function()
		local instance = Instance.new(args.className)

		instance.Name =
			args.name or
			args.className

		instance.Parent = parent

		return instance
	end)

	if success then
		finishRecording(recording, true)

		return {
			output = getPath(result)
		}
	else
		finishRecording(recording, false)
		error(result)
	end
end

handlers.destroy_instance = function(args)
	local instance = resolve(args.path)

	if instance == game then
		error("Cannot destroy game")
	end

	local recording = beginRecording(
		"destroy_instance"
	)

	local success, err = pcall(function()
		instance:Destroy()
	end)

	if success then
		finishRecording(recording, true)

		return {
			output = "Destroyed " .. args.path
		}
	else
		finishRecording(recording, false)
		error(err)
	end
end

handlers.set_property = function(args)
	local instance = resolve(args.path)

	if type(args.property) ~= "string" then
		error("property required")
	end

	local recording = beginRecording(
		"set_property"
	)

	local success, err = pcall(function()
		instance[args.property] = args.value
	end)

	if success then
		finishRecording(recording, true)

		return {
			output =
				"Set " ..
				args.property ..
				" on " ..
				args.path
		}
	else
		finishRecording(recording, false)
		error(err)
	end
end

handlers.insert_asset = function(args)
	local assetId = tonumber(args.assetId)

	if not assetId then
		error("assetId must be a number")
	end

	local parent = resolve(
		args.parent or "game.Workspace"
	)

	local recording = beginRecording(
		"insert_asset"
	)

	local success, model = pcall(function()
		return AssetService:LoadAssetAsync(
			assetId
		)
	end)

	if not success then
		finishRecording(recording, false)
		error(model)
	end

	model.Parent = parent

	finishRecording(recording, true)

	return {
		output = getPath(model)
	}
end

handlers.store_image = function(args)
	return {
		error =
			"store_image requires an image/content source implementation."
	}
end

handlers.upload_image = function(args)
	return {
		error =
			"upload_image requires image bytes/content from the Python side."
	}
end

handlers.search_asset = function(args)
	return {
		error =
			"search_asset should be implemented through the Python asset/search layer."
	}
end

handlers.generate_mesh = function(args)
	return {
		error =
			"generate_mesh requires a concrete mesh-generation format or algorithm."
	}
end

handlers.generate_material = function(args)
	return {
		error =
			"generate_material requires material-generation parameters."
	}
end

handlers.generate_procedural_model = function(args)
	return {
		error =
			"generate_procedural_model requires a defined procedural generation schema."
	}
end

handlers.wait_job_finished = function(args)
	return {
		output = "No asynchronous Roblox asset job is registered."
	}
end

handlers.get_studio_state = function()
	local activeScript = StudioService.ActiveScript

	return {
		output = HttpService:JSONEncode({
			isStudio = RunService:IsStudio(),
			isRunning = RunService:IsRunning(),
			activeScript =
				activeScript
				and getPath(activeScript)
				or nil
		})
	}
end

handlers.start_stop_play = function(args)
	return {
		error =
			"Play/stop control is not implemented by this bridge yet."
	}
end

local consoleMessages = {}

local messageConnection = LogService.MessageOut:Connect(
	function(message, messageType)
		table.insert(consoleMessages, {
			message = message,
			messageType = tostring(messageType),
			time = os.clock()
		})

		if #consoleMessages > 500 then
			table.remove(consoleMessages, 1)
		end
	end
)

handlers.get_console_output = function(args)
	local count = tonumber(args.count) or 100

	local startIndex = math.max(
		1,
		#consoleMessages - count + 1
	)

	local output = {}

	for i = startIndex, #consoleMessages do
		table.insert(
			output,
			consoleMessages[i]
		)
	end

	return {
		output = HttpService:JSONEncode(output)
	}
end

handlers.screen_capture = function(args)
	if not StudioCaptureService:CanCaptureScreenshot() then
		error(
			"Studio screenshot capture is currently unavailable"
		)
	end

	local permission =
		StudioCaptureService:RequestScreenshotPermissionAsync()

	if not permission then
		error("Screenshot permission was not granted")
	end

	local capture = StudioCaptureService:CaptureScreenshot({
		Format =
			Enum.StudioCaptureScreenshotFormat.RGBA8
	})

	return {
		error =
			"Screenshot captured, but binary image transfer is not implemented."
	}
end

handlers.character_navigation = function(args)
	return {
		error =
			"character_navigation is not available through this Studio plugin bridge yet."
	}
end

handlers.user_keyboard_input = function(args)
	return {
		error =
			"user_keyboard_input requires a dedicated input mechanism."
	}
end

handlers.user_mouse_input = function(args)
	return {
		error =
			"user_mouse_input requires a dedicated input mechanism."
	}
end

handlers.subagent = function(args)
	return {
		error =
			"subagent belongs on the Python/MCP side."
	}
end

task.spawn(function()

	log("Roblox MCP Bridge")
	log("HTTP server:", BASE_URL)

	while true do

		local requestSuccess, response = pcall(function()
			return HttpService:RequestAsync({
				Url = BASE_URL .. "/poll",
				Method = "GET"
			})
		end)

		if not requestSuccess then
			warnLog(
				"Connection failed:",
				tostring(response)
			)

			task.wait(
				CONNECTION_RETRY_DELAY
			)

			continue
		end

		if response.StatusCode == 204 then
			task.wait(POLL_DELAY)
			continue
		end

		if response.StatusCode ~= 200 then
			warnLog(
				"Unexpected HTTP status:",
				response.StatusCode,
				response.Body
			)

			task.wait(
				CONNECTION_RETRY_DELAY
			)

			continue
		end

		local decodeSuccess, command =
			pcall(function()
				return HttpService:JSONDecode(
					response.Body
				)
			end)

		if not decodeSuccess then
			warnLog(
				"Invalid JSON from Python:",
				tostring(command)
			)

			continue
		end

		if not command.id then
			warnLog(
				"Received command without ID"
			)

			continue
		end

		if not command.action then
			sendResult(command.id, {
				error = "Command has no action"
			})

			continue
		end

		log(
			"Executing:",
			command.action
		)

		local handler =
			handlers[command.action]

		if not handler then
			sendResult(command.id, {
				error =
					"Unknown action: " ..
					tostring(command.action)
			})

			continue
		end

		local handlerSuccess, result =
			pcall(function()
				return handler(
					command.args or {}
				)
			end)

		if not handlerSuccess then
			warnLog(
				"Handler failed:",
				command.action,
				tostring(result)
			)

			sendResult(command.id, {
				error = tostring(result)
			})

			continue
		end

		sendResult(
			command.id,
			result
		)
	end
end)
