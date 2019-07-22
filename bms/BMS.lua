local ncdk = require("ncdk")
local enums = require("bms.enums")

local BMS = {}

local BMS_metatable = {}
BMS_metatable.__index = BMS

BMS.new = function(self)
	local bms = {}
	
	bms.header = {}
	bms.wav = {}
	bms.bpm = {}
	bms.bmp = {}
	bms.stop = {}
	bms.signature = {}
	
	bms.primaryTempo = 120
	bms.measureCount = 0
	
	bms.timePoints = {}
	bms.timeList = {}
	
	setmetatable(bms, BMS_metatable)
	
	return bms
end

BMS.import = function(self, noteChartString)
	for _, line in ipairs(noteChartString:split("\n")) do
		self:processLine(line:trim())
	end
	
	for _, timeData in pairs(self.timePoints) do
		table.insert(self.timeList, timeData)
	end
	
	table.sort(self.timeList, function(a, b)
		return a.measureTime < b.measureTime
	end)
end

BMS.processLine = function(self, line)
	if line:upper():find("^#WAV.. .+$") then
		local index, fileName = line:match("^#...(..) (.+)$")
		self.wav[index:upper()] = fileName
	elseif line:upper():find("^#BPM.. .+$") then
		local index, tempo = line:match("^#...(..) (.+)$")
		self.bpm[index:upper()] = tonumber(tempo)
	elseif line:upper():find("^#BMP.. .+$") then
		local index, path = line:match("^#...(..) (.+)$")
		self.bmp[index:upper()] = path
	elseif line:upper():find("^#STOP.. .+$") then
		local index, duration = line:match("^#....(..) (.+)$")
		self.stop[index:upper()] = tonumber(duration)
	elseif line:find("^#%d%d%d..:.+$") then
		self:processLineData(line)
	elseif line:find("^#[%S]+ .+$") then
		self:processHeaderLine(line)
	end
end

BMS.processHeaderLine = function(self, line)
	local key, value = line:match("^#(%S+) (.+)$")
	key = key:upper()
	self.header[key] = value
	
	if key == "BPM" then
		self.baseTempo = tonumber(value)
	elseif key == "LNOBJ" then
		self.lnobj = value
	end
end

BMS.updateMode = function(self, channel)
	local inputIndex = enums.ChannelEnum[channel].inputIndex
	if inputIndex then
		self.mode = self.mode or 5
		if inputIndex > self.mode then
			if inputIndex > 12 then
				self.mode = 14
			elseif inputIndex > 7 then
				self.mode = 10
			elseif inputIndex > 5 then
				self.mode = 7
			end
		end
	end
end

BMS.processLineData = function(self, line)
	local measure, channel, message = line:match("^#(...)(..):(.+)$")
	measure = tonumber(measure)
	
	if measure > self.measureCount then
		self.measureCount = measure
	end
	
	if not enums.ChannelEnum[channel] then
		return
	end
	
	self:updateMode(channel)
	
	if enums.ChannelEnum[channel].name == "Signature" then
		self.signature[measure] = tonumber((message:gsub(",", ".")))
		return
	end
	
	if
		(enums.ChannelEnum[channel].name == "Tempo" or
		enums.ChannelEnum[channel].name == "ExtendedTempo") and
		measure == 0 and
		message:sub(1, 2) ~= "00"
	then
		self.tempoAtStart = true
	end
	
	local compound = enums.ChannelEnum[channel].name ~= "BGM"
	local messageLength = math.floor(#message / 2)
	for i = 1, messageLength do
		local value = message:sub(2 * i - 1, 2 * i)
		if value ~= "00" then
			local measureTime = ncdk.Fraction:new(i - 1, messageLength) + measure
			local measureTimeString = tostring(measureTime)
			
			local timeData
			if self.timePoints[measureTimeString] then
				timeData = self.timePoints[measureTimeString]
			else
				timeData = {}
				timeData.measureTime = measureTime
				self.timePoints[measureTimeString] = timeData
			end
			
			local settedNoteChannel
			for currentChannel, values in pairs(timeData) do
				if
					enums.ChannelEnum[currentChannel] and
					enums.ChannelEnum[currentChannel].name == "Note" and
					enums.ChannelEnum[channel].inputType == enums.ChannelEnum[currentChannel].inputType and
					enums.ChannelEnum[channel].inputIndex == enums.ChannelEnum[currentChannel].inputIndex
				then
					settedNoteChannel = currentChannel
					break
				end
			end
			
			timeData[channel] = timeData[channel] or {}
			if compound then
				if enums.ChannelEnum[channel].name == "Note" then
					if enums.ChannelEnum[channel].long then
						if settedNoteChannel then
							timeData[settedNoteChannel][1] = nil
							timeData[settedNoteChannel] = nil
						end
						timeData[channel][1] = value
					end
					if not enums.ChannelEnum[channel].long and not settedNoteChannel then
						timeData[channel][1] = value
					end
				else
					timeData[channel][1] = value
				end
			else
				table.insert(timeData[channel], value)
			end
		end
	end
end

return BMS
