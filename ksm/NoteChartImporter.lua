local ncdk = require("ncdk")
local Ksh = require("ksm.Ksh")

local NoteChartImporter = {}

local NoteChartImporter_metatable = {}
NoteChartImporter_metatable.__index = NoteChartImporter

NoteChartImporter.new = function(self)
	local noteChartImporter = {}
	
	noteChartImporter.primaryTempo = 120
	noteChartImporter.measureCount = 0
	
	setmetatable(noteChartImporter, NoteChartImporter_metatable)
	
	return noteChartImporter
end

NoteChartImporter.import = function(self, noteChartString)
	self.foregroundLayerData = self.noteChart.layerDataSequence:requireLayerData(1)
	self.foregroundLayerData:setTimeMode("measure")
	self.foregroundLayerData:setSignatureMode("long")
	
	self.backgroundLayerData = self.noteChart.layerDataSequence:requireLayerData(2)
	self.backgroundLayerData.invisible = true
	self.backgroundLayerData:setTimeMode("absolute")
	self.backgroundLayerData:setSignatureMode("long")
	
	self.ksh = Ksh:new()
	self.ksh:import(noteChartString)
	
	self:processMetaData()
	self:processData()
	self.noteChart:hashSet("noteCount", self.noteCount)
	
	self.measureCount = #self.ksh.measureStrings
	self:processMeasureLines()
	
	self.noteChart.inputMode:setInputCount("bt", 4)
	self.noteChart.inputMode:setInputCount("fx", 2)
	self.noteChart.inputMode:setInputCount("laserleft", 2)
	self.noteChart.inputMode:setInputCount("laserright", 2)
	self.noteChart.type = "ksm"
	
	self.noteChart:compute()
	
	if self.maxTimePoint and self.minTimePoint then
		self.totalLength = self.maxTimePoint:getAbsoluteTime() - self.minTimePoint:getAbsoluteTime()
	else
		self.totalLength = 0
	end
	self.noteChart:hashSet("totalLength", self.totalLength)
	
	local audio = self.noteChart:hashGet("m")
	local split = audio:split(";")
	if split[1] then
		self.audioFileName = split[1]
	else
		self.audioFileName = audio
	end
	self.noteChart:hashSet("audio", self.audioFileName)
	self:processAudio()
end

NoteChartImporter.processMetaData = function(self)
	for key, value in pairs(self.ksh.options) do
		self.noteChart:hashSet(key, value)
	end
end

NoteChartImporter.processAudio = function(self)
	local audioFileName = self.audioFileName
	
	if audioFileName then
		local startTime = -(tonumber(self.ksh.options.o) or 0) / 1000
		local timePoint = self.backgroundLayerData:getTimePoint(startTime, -1)
		
		local noteData = ncdk.NoteData:new(timePoint)
		noteData.inputType = "auto"
		noteData.inputIndex = 0
		noteData.sounds = {{audioFileName, 1}}
		self.noteChart:addResource("sound", audioFileName)
		
		noteData.noteType = "SoundNote"
		self.backgroundLayerData:addNoteData(noteData)
	end
end

NoteChartImporter.processData = function(self)
	local longNoteData = {}
	
	self.noteCount = 0
	
	self.minTimePoint = nil
	self.maxTimePoint = nil
	
	for _, tempoData in ipairs(self.ksh.tempos) do
		local measureTime = ncdk.Fraction:new(tempoData.lineOffset, tempoData.lineCount) + tempoData.measureOffset
		self.currentTempoData = ncdk.TempoData:new(
			measureTime,
			tempoData.tempo
		)
		self.foregroundLayerData:addTempoData(self.currentTempoData)
		
		local timePoint = self.foregroundLayerData:getTimePoint(measureTime, -1)
		self.currentVelocityData = ncdk.VelocityData:new(timePoint, ncdk.Fraction:new():fromNumber(self.currentTempoData.tempo / self.primaryTempo, 1000))
		self.foregroundLayerData:addVelocityData(self.currentVelocityData)
	end
	
	for _, signatureData in ipairs(self.ksh.timeSignatures) do
		self.foregroundLayerData:setSignature(
			signatureData.measureIndex,
			ncdk.Fraction:new(signatureData.n * 4, signatureData.d)
		)
	end
	
	local allNotes = {}
	for _, note in ipairs(self.ksh.notes) do
		allNotes[#allNotes + 1] = note
	end
	for _, laser in ipairs(self.ksh.lasers) do
		allNotes[#allNotes + 1] = laser
	end
	
	for _, _noteData in ipairs(allNotes) do
		local startMeasureTime = ncdk.Fraction:new(_noteData.startLineOffset, _noteData.startLineCount) + _noteData.startMeasureOffset
		local startTimePoint = self.foregroundLayerData:getTimePoint(startMeasureTime, -1)
		
		local startNoteData = ncdk.NoteData:new(startTimePoint)
		startNoteData.inputType = _noteData.input
		startNoteData.inputIndex = _noteData.lane
		if startNoteData.inputType == "fx" then
			startNoteData.inputIndex = _noteData.lane - 4
		end
		
		if _noteData.input == "laser" then
			if _noteData.lane == 1 then
				if _noteData.posStart < _noteData.posEnd then
					startNoteData.inputType = "laserright"
					startNoteData.inputIndex = 1
				elseif _noteData.posStart > _noteData.posEnd then
					startNoteData.inputType = "laserleft"
					startNoteData.inputIndex = 1
				end
			elseif _noteData.lane == 2 then
				if _noteData.posStart < _noteData.posEnd then
					startNoteData.inputType = "laserright"
					startNoteData.inputIndex = 2
				elseif _noteData.posStart > _noteData.posEnd then
					startNoteData.inputType = "laserleft"
					startNoteData.inputIndex = 2
				end
			end
		end
		
		startNoteData.sounds = {}
		
		self.foregroundLayerData:addNoteData(startNoteData)
		
		local lastTimePoint = startTimePoint
		local endMeasureTime = ncdk.Fraction:new(_noteData.endLineOffset, _noteData.endLineCount) + _noteData.endMeasureOffset
		
		if startMeasureTime == endMeasureTime then
			startNoteData.noteType = "ShortNote"
		else
			startNoteData.noteType = "LongNoteStart"
			
			local endTimePoint = self.foregroundLayerData:getTimePoint(endMeasureTime, -1)
			
			local endNoteData = ncdk.NoteData:new(endTimePoint)
			endNoteData.inputType = startNoteData.inputType
			endNoteData.inputIndex = startNoteData.inputIndex
			endNoteData.sounds = {}
			
			endNoteData.noteType = "LongNoteEnd"
			
			endNoteData.startNoteData = startNoteData
			startNoteData.endNoteData = endNoteData
			
			self.foregroundLayerData:addNoteData(endNoteData)
			
			lastTimePoint = endTimePoint
		end
		
		self.noteCount = self.noteCount + 1
		
		if not self.minTimePoint or lastTimePoint < self.minTimePoint then
			self.minTimePoint = lastTimePoint
		end
		
		if not self.maxTimePoint or lastTimePoint > self.maxTimePoint then
			self.maxTimePoint = lastTimePoint
		end
	end
end

NoteChartImporter.processMeasureLines = function(self)
	for measureIndex = 0, self.measureCount do
		local measureTime = ncdk.Fraction:new(measureIndex)
		local timePoint = self.foregroundLayerData:getTimePoint(measureTime, -1)
		
		local startNoteData = ncdk.NoteData:new(timePoint)
		startNoteData.inputType = "measure"
		startNoteData.inputIndex = 1
		startNoteData.noteType = "LineNoteStart"
		self.foregroundLayerData:addNoteData(startNoteData)
		
		local endNoteData = ncdk.NoteData:new(timePoint)
		endNoteData.inputType = "measure"
		endNoteData.inputIndex = 1
		endNoteData.noteType = "LineNoteEnd"
		self.foregroundLayerData:addNoteData(endNoteData)
		
		startNoteData.endNoteData = endNoteData
		endNoteData.startNoteData = startNoteData
	end
end

return NoteChartImporter