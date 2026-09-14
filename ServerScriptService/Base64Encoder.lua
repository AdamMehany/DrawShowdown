local b = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

local function encode(data)
	local result = {}
	local len = #data

	local i = 1
	while i <= len do

		local a = data:byte(i) or 0
		local b1 = data:byte(i + 1) or 0
		local c = data:byte(i + 2) or 0

		local n = a * 65536 + b1 * 256 + c

		local c1 = math.floor(n / 262144) % 64
		local c2 = math.floor(n / 4096) % 64
		local c3 = math.floor(n / 64) % 64
		local c4 = n % 64

		table.insert(result, b:sub(c1 + 1, c1 + 1))
		table.insert(result, b:sub(c2 + 1, c2 + 1))
		table.insert(result, b:sub(c3 + 1, c3 + 1))
		table.insert(result, b:sub(c4 + 1, c4 + 1))

		i += 3
	end

	-- padding fix
	local mod = len % 3
	if mod == 1 then
		result[#result] = "="
		result[#result - 1] = "="
	elseif mod == 2 then
		result[#result] = "="
	end

	return table.concat(result)
end

return encode
