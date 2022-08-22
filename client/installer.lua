--- MineBoy installer.

local function trimPrefix(text, prefix)
	return (text:sub(0, #prefix) == prefix) and text:sub(#prefix+1) or text
end

local function githubRequest(url, token)
	local headers = {}
	if token then
		headers["Authorization"] = 'token ' .. token
	end

	return textutils.unserializeJSON(http.get(url, headers).readAll())
end

--- Get all install options and files from github.
local function getInstallFiles(tree)
	local options = {}
	for _, v in ipairs(tree) do
		-- Must be in the client folder and be a folder itself
		if string.match(v.path, '^client/[^/]+$') and v.type == 'tree' then
			local name = trimPrefix(v.path, 'client/')
			local files = githubRequest(v.url .. '?recursive=1').tree

			-- Remove all non-blobs since we already have recursive file list.
			for i, v in ipairs(files) do
				if v.type ~= 'blob' then
					table.remove(files, i)
				end
			end

			options[name] = files
		end
	end

	return options
end

--- Base64 decode.
local function decode(data)
	local b = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
    data = string.gsub(data, '[^'..b..'=]', '')
    return (data:gsub('.', function(x)
        if (x == '=') then return '' end
        local r,f='',(b:find(x)-1)
        for i=6,1,-1 do r=r..(f%2^i-f%2^(i-1)>0 and '1' or '0') end
        return r;
    end):gsub('%d%d%d?%d?%d?%d?%d?%d?', function(x)
        if (#x ~= 8) then return '' end
        local c=0
        for i=1,8 do c=c+(x:sub(i,i)=='1' and 2^(8-i) or 0) end
        return string.char(c)
    end))
end

--- Download github file objects provided.
local function downloadFiles(files)
	for _, v in ipairs(files) do
		local fileObject = githubRequest(v.url)

		local file = fs.open(v.path, 'w')
		file.write(decode(fileObject.content))
		file.close()

		term.setTextColor(colors.gray)
		write('Downloaded ')
		term.setTextColor(colors.yellow)
		write(v.path .. '\n')
	end
end

-- Root tree of all files
local rootTree = githubRequest('https://api.github.com/repos/JSH32/Mineboy/git/trees/master?recursive=1').tree
if rootTree == nil then
	print('Could not get files.')
	return
end

local function getKeys(t)
	local keyArr = {}
	for k, _ in pairs(t) do
		table.insert(keyArr, k)
	end

	local keys = {}
	for k, v in ipairs(keyArr) do
		keys[tostring(k)] = v
	end

	return keys
end

local options = getInstallFiles(rootTree)
local keys = getKeys(options)

-- Top bar
term.clear()
term.setBackgroundColor(colors.cyan)
term.setCursorPos(1, 1)
term.clearLine()
print('[MineBoy Installer]')
term.setBackgroundColor(colors.black)

local function getOption()
	while true do
		term.setTextColor(colors.lightGray)
		print('Select an option to install (or "exit"):')

		-- Print out options
		for k, v in pairs(keys) do
			term.setTextColor(colors.orange)
			write(k)
			term.setTextColor(colors.white)
			write(' ' .. v .. '\n')
		end

		term.setTextColor(colors.cyan)
		write('> ')
		term.setTextColor(colors.white)
		local option = read()

		if option == 'exit' then
			term.clear()
			term.setCursorPos(1, 1)
			return
		end

		if keys[option] ~= nil then
			return options[keys[option]]
		end

		term.setTextColor(colors.red)
		print('Invalid option was chosen!')
	end
end

local option = getOption()
if option == nil then
	return
end

downloadFiles(option)