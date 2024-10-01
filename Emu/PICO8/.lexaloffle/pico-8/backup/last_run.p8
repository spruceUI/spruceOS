pico-8 cartridge // http://www.pico-8.com
version 42
__lua__

function initVariables()
	--timer
	t = 0
	St = 0

	--init grid
	--20 x 10
	grid = {}
	gx = 10
	gy = 20
	cs = 6
	px = 30
	py = -2
	for i = 1, gx do
		grid[i] = {}
		for k = 1, gy do
			grid[i][k] = {
				falling = false,
				locked = false,
				spr = 0
			} 
		end
	end

	lockpause = -1
	diffMap = {
		48, 43, 38, 33, 28, 23, 18, 13, 8, 6, 5, 5, 5, 4, 4, 4, 3, 3, 3, 2
	}
	transition = 0
	score1 = 0
	score2 = 0
	if level + 1 <= #diffMap then
		diff = diffMap[level + 1]
	else
		diff = 2
	end
	spd = diff
	fastfall = false
	fallrelease = false

	pushDownPts = 0
	
	clearAnim = 0
	clearLines = {}
	clear = false
	clearAnimLength = 4

	--t, j, z, o, s, l, i
	piecesStats = { 0, 0, 0, 0, 0, 0, 0 }
	shapesMap = { 4, 1, 7, 5, 2, 6, 3}

	--das
	das = 0
	dasMax = 16
	asMax = 5
	firstTap = true
	
	tuckTweak = -1
	tuckT = 0
	tuckWait = 0

	minSt = 99
	St = 0

	gameover = false
	gameoverAnim = 0
	gameoverSpd = 4

	-- 0 = main, 1 = options, 2 = replays, 3 = replayload,  game = -1
	menu = 0
	menucursor = 0


	drought = 0
	totalclears = 0
	tetrises = 0
	trt = 0

	yanim = 15

	replayindex = 1
	replaypage = 1
	replaypiecesindex = 1
	lockinputp = true
	replaymode = false


	--set transition level based on starting level
	if level < 10 then
		transition = (level + 1) * 10
	elseif level >= 10 and level < 16 then
		transition = 100
	elseif level >= 16 then
		transition = level * 10 - 50 
	end
end

function _init()
	if cartdata("picotris") then
		sprlock = dget(2)
		sprtheme = dget(3)
		if dget(4) == 1 then
			showdas = true
		else
			showdas = false
		end
		if dget(5) == 1 then
			showstats = true
		else
			showstats = false
		end
		if dget(6) == 1 then
			showrate = true
		else
			showrate = false
		end
		if dget(7) then
			showdrought = dget(7)
		else
			showdrought = 1
		end
		if dget(8) then
			swapbtns = dget(8)
		else
			swapbtns = 0
		end
		highscore1 = dget(0)
		highscore2 = dget(1)
	else
		showrate = true
		showdrought = 1
		sprtheme = 0
		sprlock = -1
		showdas = true
		showstats = true
		swapbtns = 0
		highscore1 = 0
		highscore2 = 0

		dset(2, sprlock)
		dset(3, sprtheme)
		dset(4, 1)
		dset(5, 1)
		dset(6, 1)
		dset(7, 1)
	end
	
	level = 0
	menulv = 0
	lines = 0
	setlv = 0
	sprnumber = 5

	replaymode = false
	replayinputs = {}
	add(replayinputs, {})
	replaypieces = {}
	replayindex = 1
	replaypage = 1
	pagesize = 3600
	replaypiecesindex = 1
	lockinputp = true
	startinglevel = 0
	replayduration = { m = 0, s = 0 }
	replaydate = ""
	replayscore = ""
	replaymaxlv = ""
	replaylines = ""
	replaytrt = ""
	replaylines = ""
	loadtutorialpage = 0

	saving = false
	savingt = 0
	
	
	initVariables()	
end

--0 normal, 1 replay
function initGame(type)
	if type == 0 then
		-- prepare replay variables for recording
		replayinputs = {}
		add(replayinputs, {})
		replaypieces = {}

		initVariables()
		level = menulv	
		startinglevel = level
		setlv = level
		diff = diffMap[level + 1]

		--set transition level based on starting level
		if level < 10 then
			transition = (level + 1) * 10
		elseif level >= 10 and level < 16 then
			transition = 100
		elseif level >= 16 then
			transition = level * 10 - 50 
		end

		lines = 0
		sprshift = 3 * (level % sprnumber) + (sprtheme * 16)

		--next tetromino preview
		if replaymode == false then
			nexttetro = tetroGen(6, 1, 0, flr(rnd(7)))
		else
			nexttetro = tetroGen(6, 1, 0, replaypieces[replaypiecesindex + 1])
		end
		--spawn first tetromino
		if replaymode == false then
			tetro = tetroGen(6, 1, 0, flr(rnd(7)))
			add(replaypieces, tetro.shape)
		else
			tetro = tetroGen(6, 1, 0, replaypieces[replaypiecesindex])
			replaypiecesindex += 1
		end

		drawNewFalling()

		menu = -1
	elseif type == 1 then
	-- debug replay mode
		initVariables()
		level = startinglevel
		setlv = level
		diff = diffMap[level + 1]

		--set transition level based on starting level
		if level < 10 then
			transition = (level + 1) * 10
		elseif level >= 10 and level < 16 then
			transition = 100
		elseif level >= 16 then
			transition = level * 10 - 50 
		end

		lines = 0
		sprshift = 3 * (level % sprnumber) + (sprtheme * 16)

		--next tetromino preview
		nexttetro = tetroGen(6, 1, 0, replaypieces[replaypiecesindex + 1])
		--spawn first tetromino
		tetro = tetroGen(6, 1, 0, replaypieces[replaypiecesindex])
		replaypiecesindex += 1

		drawNewFalling()

		menu = -1
		replaymode = true
	end
end


function _update60()
	--update timer
	t += 1
	St += 1

	--replay input playing
	if menu == -1 and not gameover and not saving then
		if replayindex <= pagesize then
			replayindex += 1
		else
			add(replayinputs, {})
			replaypage += 1
			replayindex = 1
		end
	end

	--replay timer
	if replaymode then
		if replayindex % 60 == 0 then
			if replayduration.s > 0 then
				replayduration.s -= 1
			else
				replayduration.m -=1
				replayduration.s = 59
			end
		end
	end


	if menu == 0 then
		--mainmenu commands
		if btnp(0) and menucursor == 1 then
			if menulv > 0 then menulv -= 1
			else menulv = 19 end
		elseif btnp(1) and menucursor == 1 then
			if menulv < 19 then menulv += 1
			else menulv = 0 end
		elseif btnp(2) and menucursor > 0 then
			menucursor -= 1
		elseif btnp(3) and menucursor < 3 then
			menucursor += 1
		end

		if (btnp(4) or btnp(5)) then
			if menucursor == 0 then
				-- start game
				initGame(0)
			elseif menucursor == 2 then
				-- reset clipboard
				printh("", "@clip")
				-- replays menu
				menu = 2
				menucursor = 0
			elseif menucursor == 3 then
				-- customize menu
				menu = 1
				menucursor = 0
			end
		end


	elseif menu == 1 then
		--optionsmenu commands
		if btnp(2) and menucursor > 0 then
			menucursor -= 1
		elseif btnp(3) and menucursor < 7 then
			menucursor += 1
		elseif (btnp(4) or btnp(5)) and menucursor == 7 then
			menu = 0
			menucursor = 0
		end
		if menucursor == 0 then
			if btnp(1) then
				sprlock += 1
				if sprlock > 4 then sprlock = -1 end
				dset(2, sprlock)
			elseif btnp(0) then
				sprlock -= 1
				if sprlock < -1 then sprlock = 4 end
				dset(2, sprlock)
			end
		elseif menucursor == 1 then
			if btnp(1) then
				sprtheme += 1
				if sprtheme > 3 then sprtheme = 0 end
				dset(3, sprtheme)
			elseif btnp(0) then
				sprtheme -= 1
				if sprtheme < 0 then sprtheme = 3 end
				dset(3, sprtheme)
			end
		elseif menucursor == 2 then
			if btnp(0) or btnp(1) then
				showdas = not showdas
				if showdas then
					dset(4, 1)
				else
					dset(4, 0)
				end
			end
		elseif menucursor == 3 then
			if btnp(0) or btnp(1) then
				showstats = not showstats
				if showstats then
					dset(5, 1)
				else
					dset(5, 0)
				end
			end
		elseif menucursor == 4 then
			if btnp(0) or btnp(1) then
				showrate = not showrate
				if showrate then
					dset(6, 1)
				else
					dset(6, 0)
				end
			end
		elseif menucursor == 5 then
			if btnp(0) and showdrought > 0 then showdrought -= 1
			elseif btnp(1) and showdrought < 2 then showdrought += 1 end
			dset(7, showdrought)
		elseif menucursor == 6 then
			if btnp(0) and swapbtns > 0 then swapbtns -= 1
			elseif btnp(1) and swapbtns < 1 then swapbtns += 1 end
			dset(8, swapbtns)
		end
	elseif menu == 2 then
		--replay menu navigation
		if btnp(3) and menucursor == 0 then menucursor = 1
		elseif btnp(2) and menucursor == 1 then menucursor = 0 end

		if btnp(0) and loadtutorialpage == 1 then loadtutorialpage = 0
		elseif btnp(1) and loadtutorialpage == 0 then loadtutorialpage = 1 end

		if btnp(4) or btnp(5) then
			if menucursor == 0 then extcmd("folder")
			elseif menucursor == 1 then
				menu = 0
				menucursor = 0
				loadtutorialpage = 0
			end
		end

		--replay load
		--via drag & drop
		if stat(120) then
			local str = ""
			local size = serial(0x800, 0x8000, 0x7fff)
			for i=0, size do
				local b = peek(0x8000 + i)
				str = str..chr(b)
			end

			fromString(sub(split(str, "*", false)[2], 2))
			menu = 3
			menucursor = 0
		end

		--via clipboard
		if stat(4) ~= "" then
			fromString(sub(split(stat(4), "*", false)[2], 2))
			menu = 3
			menucursor = 0
		end
	elseif menu == 3 then
		--replayload menu navigation
		if btnp(3) and menucursor == 0 then menucursor = 1
		elseif btnp(2) and menucursor == 1 then menucursor = 0 end

		if btnp(4) or btnp(5) then
			if menucursor == 0 then initGame(1)
			elseif menucursor == 1 then
				menu = 2
				menucursor = 0
				--reset clipboard
				printh("", "@clip")
			end
		end

	elseif not gameover and menu == -1 then
		--initial fast fall
		if rbtn(3) and t < 50 then
			t = 50
		end

		--do not stop if t overflows
		if lines > 0 and t < 50 then
			t = 50
		end

		--line clear
		if #clearLines > 0 then
			qsort(
				clearLines,
				function(a,b) return (a < b) end
			)
			for i in all(clearLines) do
				if clearAnim < 5 and t % clearAnimLength == 0 then
					grid[5-clearAnim][i].locked = false
					grid[6+clearAnim][i].locked = false
				end
			end
			if t % clearAnimLength == 0 then
				if clearAnim == 0 then
					if #clearLines == 4 then sfx(3)
					else sfx(2) end
				end
				clearAnim += 1
			end
			if clearAnim == 6 then
				-- add to total line cleared
				lines += #clearLines

				-- subtract transition lines
				if transition - #clearLines > 0 then
					transition -= #clearLines
				else
					transition = 10 + (transition - #clearLines)

					-- increase level
					level += 1

					-- change palette on level change
					if sprlock == -1 then
						sprshift = 3 * (level % sprnumber) + (sprtheme * 16)
						nexttetro.spr = (nexttetro.spr - 3 * ((level - 1) % sprnumber) - (sprtheme * 16)) + sprshift
						tetro.spr = (tetro.spr - 3 * ((level - 1) % sprnumber) - (sprtheme * 16)) + sprshift
						for i = 1, gx do
							for k = 1, gy do
								grid[i][k].spr = (grid[i][k].spr - 3 * ((level - 1) % sprnumber) - (sprtheme * 16)) + sprshift
							end
						end
					end
				end

				-- set diff
				if level <= 19 then
					diff = diffMap[level + 1]
				elseif level >= 29 then
					diff = 1
				end

				-- add score
				local lineMult = 40
				if #clearLines == 2 then
					lineMult = 100
				elseif #clearLines == 3 then
					lineMult = 300
				elseif #clearLines == 4 then
					lineMult = 1200
				end

				for i = 0, level do
					score1 += lineMult
					while score1 > 999 do
						score1 -= 1000
						score2 += 1
					end
				end

				-- calculate trt
				if #clearLines == 4 then tetrises += 4 end
				totalclears += #clearLines

				trt = ceil(tetrises / totalclears * 100)
				
				-- clear lines
				for i in all(clearLines) do
					for z = i, 2, -1 do
						for zz = 1, gx do
							grid[zz][z].locked = grid[zz][z - 1].locked
							grid[zz][z].spr = grid[zz][z - 1].spr
						end
					end
					clearAnim = 0
					del(clearLines, i)
				end
			end
		end
		
		--move tetromino down
		if t % spd == 0 and lockpause == -1 and t > 50 then
			--refresh grid
			if not checkSide(2) then
				delOldFalling()
				tetro.y += 1
				if fastfall then
					pushDownPts += 1
				end
				for b in all(tetro.blocks) do
					b.y += 1
				end
				drawNewFalling()
			elseif checkSide(2) and lockpause == -1 then
				--activate lockpause
				if tetro.y <= 6 then
					lockpause = 18
				elseif tetro.y > 6 and tetro.y <= 10 then
					lockpause = 16
				elseif tetro.y > 10 and tetro.y <= 14 then
					lockpause = 14
				elseif tetro.y > 14 and tetro.y <= 18 then
					lockpause = 12
				elseif tetro.y > 18 then
					lockpause = 10
				end 
			end
		end
		
		
		--lock pause, spawn new tetromino
		if lockpause > 0 then
			lockpause -= 1
		elseif lockpause == 0 and #clearLines == 0 then
			--lock tetromino
			if not clear then
				for b in all(tetro.blocks) do
					if b.y > 0 then
						grid[b.x][b.y].falling = false
						grid[b.x][b.y].locked = true
						grid[b.x][b.y].spr = tetro.spr
					end

					sfx(1)
					lineClearCheck()

					--add pushdown points
					score1 += pushDownPts
					pushDownPts = 0
					while score1 > 999 do
						score1 -= 1000
						score2 += 1
					end
				end
			end

			if #clearLines == 0 then		
				-- update pieces stats
				piecesStats[shapesMap[tetro.shape + 1]] += 1

				--generate new tetromino, reroll once if the next shape is the same as the current
				--also set gameover = true if there's no space to generate a new tetromino
				if not replaymode then
					tetro = nexttetro
					for b in all(tetro.blocks) do
						if not grid[b.x][b.y + 1].locked then
							nexttetro = tetroGen(6, 1, 0, flr(rnd(7)))
							if nexttetro.shape == tetro.shape then
								nexttetro = tetroGen(6, 1, 0, flr(rnd(7)))
							end
						else
							gameover = true
						end
					end

					add(replaypieces, tetro.shape)
				else
					tetro = nexttetro
					if replaypiecesindex < #replaypieces then
						nexttetro = tetroGen(6, 1, 0, replaypieces[replaypiecesindex + 1])
						replaypiecesindex += 1
					else
						nexttetro = tetroGen(6, 1, 0, replaypieces[replaypiecesindex])
						gameover = true
					end
				end

				fastfall = false
				fallrelease = true
				lockpause = -1
				as = asMax
				tuckT = 0
				tuckTweak = -1
				clearLines = {}
				clear = false

				--calculate drought
				if tetro.shape != 2 then
					drought += 1
				else
					drought = 0
				end

				drawNewFalling()
			end
		end


		--move tetromino left and right
		if rbtn(1) then
			if firstTap and ((lockpause == -1) or (lockpause != -1 and das < dasMax - asMax)) then
				das = 0
			end
			if das == dasMax or firstTap then
				if lockpause == -1 then
					if not checkSide(1) then
						delOldFalling()
						tetro.x += 1
						for b in all(tetro.blocks) do
							b.x += 1
						end
						drawNewFalling()
						sfx(0,1)
						if St < minSt then 
							minSt = St
						end
						St = 0 
						if das == dasMax then
							das = dasMax - asMax
						end
					else
						tuckTweak = 1
						tuckT = min(diff + 3, 8)
					end
				end
			else
				das += 1
			end
			firstTap = false
		end
		if rbtn(0) then
			if firstTap and ((lockpause == -1) or (lockpause != -1 and das < dasMax - asMax)) then
				das = 0
			end
			if das == dasMax or firstTap then
				if lockpause == -1 then
					if not checkSide(0) then
						delOldFalling()
						tetro.x -= 1
						for b in all(tetro.blocks) do
							b.x -= 1
						end
						drawNewFalling()
						sfx(0,1)
						if St < minSt then
							minSt = St
						end
						St = 0
						if das == dasMax then
							das = dasMax - asMax
						end
					else
						tuckTweak = 0
						tuckT = min(diff + 3, 8)
					end
				end
			else
				das += 1
			end
			firstTap = false
		end
		if not rbtn(0) and not rbtn(1) and lockpause == -1 then
			firstTap = true
		end
		if rbtn(0) and rbtn(1) and lockpause == -1 then
			das = 0
		end

		--tuck tweak
		if tuckTweak != -1 and tuckWait == 0 then
			if tuckTweak == 0 then
				if rbtn(1) then
					tuckT = 0
					tuckTweak = -1
				end
				if not checkSide(0) and tuckT > 0 then
					delOldFalling()
					tetro.x -= 1
					tuckWait = 40
					for b in all(tetro.blocks) do
						b.x -= 1
					end
					drawNewFalling()
					sfx(0,1)

					if das == dasMax then
						das = das - asMax
					end
				end
			else
				if rbtn(0) then
					tuckT = 0
					tuckTweak = -1
				end
				if not checkSide(1) and tuckT > 0 then
					delOldFalling()
					tetro.x += 1
					tuckWait = 40
					for b in all(tetro.blocks) do
						b.x += 1
					end
					drawNewFalling()
					sfx(0,1)

					if das == dasMax then
						das = das - asMax
					end
				end
			end
		end
		if tuckT > 0 then tuckT -= 1
		else
			tuckTweak = -1
		end

		if tuckWait > 0 then
			tuckWait -= 1
		end


		--rotate tetromino
		if lockpause == -1 and #clearLines == 0 and not checkSide(2) then
			if not lockinputp and rbtn(4 + swapbtns) and not blockedRotation(tetro, tetro.rot - 1) then
				delOldFalling()
				tetro = tetroGen(tetro.x, tetro.y, tetro.rot - 1, tetro.shape)
				drawNewFalling()
				lockinputp = true
				--sfx(0)
			elseif not lockinputp and rbtn(5 - swapbtns) and not blockedRotation(tetro, tetro.rot + 1) then
				delOldFalling()
				tetro = tetroGen(tetro.x, tetro.y, tetro.rot + 1, tetro.shape)
				drawNewFalling()
				lockinputp = true
				--sfx(0)
			end
		end
		if not rbtn(4) and not rbtn(5) then
			lockinputp = false
		end

		


		--fast fall
		if rbtn(3) and not fallrelease and lockpause == -1 then
			fastfall = true
		else
			fastfall = false
		end
		if not rbtn(3) then
			fallrelease = false
		end

		if fastfall then
			spd = 2
		else
			spd = diff
		end

	elseif menu == -1 and gameover then
		--gameover animation
		if t % gameoverSpd == 0 then
			gameoverAnim += 1
		end
		if gameoverAnim <= gy then
			if t % gameoverSpd == 0 then
				for i = 1, gx do
					grid[i][gameoverAnim].locked = true
					if sprlock == -1 then
						grid[i][gameoverAnim].spr = rnd({3, 2, 1}) + sprshift
					else
						grid[i][gameoverAnim].spr = rnd({3, 2, 1}) + (sprlock * 3) + (sprtheme * 16)
					end
				end
			end
		elseif gameoverAnim > gy + 30 and not saving then
			if replaymode == false then
				--set highscore
				if score2 > highscore2 then
					highscore1 = score1
					highscore2 = score2

					dset(0, highscore1)
					dset(1, highscore2)
				elseif score2 == highscore2 then
					if score1 > highscore1 then
						highscore1 = score1
						highscore2 = score2

						dset(0, highscore1)
						dset(1, highscore2)
					end
				end

				--save replay to file
				partsindex = 1 
				compressedstring = ""
				count = 0
				prevnum = -1
				savingt = 0
				saving = true
			else
				menu = 0
				replaymode = false
				gameover = false
				gameoverAnim = 0
				t = 0
				piecesStats = { 0, 0, 0, 0, 0, 0, 0 }
			end
		end
	end

	if saving then
		savingt += 1

		--convert and compress replayinputs
		if partsindex <= #replayinputs then
			local part = replayinputs[partsindex]
			for i = 1, #part, 1 do
				local currnum = part[i]
				
				if prevnum == -1 then
					prevnum = currnum
					count = 1
				else
					if currnum == prevnum then
						count += 1
					else
						compressedstring = compressedstring..prevnum.."-"..count..","
						count = 1
					end
					prevnum = currnum
				end
			end
			partsindex += 1
		else
			compressedstring = compressedstring..prevnum.."-"..count..","

			--compression phase 2
			local tempstr = ""
			local deftable = {}
			local compressedstring2 = ""
			for k = 1, #compressedstring do
				local char = compressedstring[k]
				
				if char ~= "," then
					tempstr = tempstr..char
				else
					local found = false
					for i, d in ipairs(deftable) do
						if d == tempstr then
							found = true
							compressedstring2 = compressedstring2..i..(k < #compressedstring and "," or "")
							tempstr = ""
							break
						end
					end
					if found == false then
						add(deftable, tempstr)
						compressedstring2 = compressedstring2..#deftable..(k < #compressedstring and "," or "")
						tempstr = ""
					end
				end
			end
			compressedstring2 = compressedstring2.."="
			for t = 1, #deftable do
				compressedstring2 = compressedstring2..deftable[t]..(t < #deftable and "," or "")
			end


			saveToFile(compressedstring2)
			savingt = 0
			partsindex = 1
			pagesindex = ""
			compressedstring = ""
			count = 0
			prevnum = -1
			
			menu = 0
			gameover = false
			gameoverAnim = 0
			t = 0
			piecesStats = { 0, 0, 0, 0, 0, 0, 0 }
			saving = false
		end
	end


	-- replay input saving
	-- left right up down o x
	if menu == -1 and not replaymode then
		local inputmask = 0b000000

		if btn(0) then
			inputmask = inputmask | 0b100000
		end
		if btn(1) then
			inputmask = inputmask | 0b010000
		end
		if btn(2) then
			inputmask = inputmask | 0b001000
		end
		if btn(3) then
			inputmask = inputmask | 0b000100
		end
		if btn(4) then
			inputmask = inputmask | 0b000010
		end
		if btn(5) then
			inputmask = inputmask | 0b000001
		end

		add(replayinputs[replaypage], inputmask)
	end
end





function _draw()
	cls(6)
	palt(0, false)
	palt(1, true)

	--background animation
	fillp(▒)
	rectfill(0, 0, 128, 128, 7)	
	fillp()

	--draw board shadow
	rectfill(37, 5, 97, 125, 5)

	--draw board
	rectfill(36, 4, 96, 124, 0)
	print(stat(1),108,58,0)
	print(stat(7),120,64,0)
	print(stat(8),120,70,0)
	--draw replay text
	if replaymode then
		print("REPLAY", 55, 56, 5)

		local currentsecs = replayduration.s + (replayduration.m * 60)

		if replaypage == 1 and replayindex == 1 then
			totalsecs = currentsecs
		end

		local barsize = 25
		local barprogress = (currentsecs * barsize) / totalsecs

		pset(54 + barsize, 63, 5)
		rectfill(54, 63, 79 - barprogress, 63, 5)


		print(zeroPad(""..replayduration.m, 2)..":"..zeroPad(""..replayduration.s, 2), 57, 66, 5)
	end

	--draw grid
	if menu == -1 then
		for i = 1, gx do
			for k = 1, gy do
				if grid[i][k].falling or grid[i][k].locked then
					spr(grid[i][k].spr, px + i*(cs), py + k*(cs))
				end
			end
		end
	end



	--draw next piece
	local nx = 76
	local ny = 80

	rectfill(nx + 24, ny, nx + 50, ny + 20, 5)
	rectfill(nx + 23, ny - 1, nx + 49, ny + 19, 0)
	print('NEXT', nx + 24, ny, 6)
	if menu == -1 then
		for b in all(nexttetro.blocks) do
			spr(nexttetro.spr, nx + b.x*(cs), ny + b.y*(cs))
		end
	end

	--draw trt
	if showrate then
		local tx = 76
		local ty = 23

		rectfill(tx + 24, ty, tx + 50, ty + 14, 5)
		rectfill(tx + 23, ty - 1, tx + 49, ty + 13, 0)
		print('TRT', tx + 24, ty, 6)
		print(hideZeroes(zeroPad(''..trt, 3))..'%', tx + 33, ty + 7, 6)
	end


	--draw button overlay
	local nx = 76
	local ny = 115

	rectfill(nx + 24, ny - 10, nx + 50, ny + 10, 5)
	rectfill(nx + 23, ny - 11, nx + 49, ny + 9, 0)
	print('BTNS', nx + 24, ny - 10, 6)

	palt(0, 1)
	spr(65 + 16 * boolToInt(rbtn(0)) * boolToInt(menu == -1), nx + 24, ny)
	spr(66 + 16 * boolToInt(rbtn(3)) * boolToInt(menu == -1), nx + 29, ny)
	spr(67 + 16 * boolToInt(rbtn(1)) * boolToInt(menu == -1), nx + 34, ny)
	spr(64 + 16 * boolToInt(rbtn(2)) * boolToInt(menu == -1), nx + 29, ny - 5)
	spr(68 + 16 * boolToInt(rbtn(4)) * boolToInt(menu == -1), nx + 39, ny)
	spr(69 + 16 * boolToInt(rbtn(5)) * boolToInt(menu == -1), nx + 44, ny)


	--draw drought
	if showdrought == 2 or (showdrought == 1 and drought >= 15) then
		local tx = 76
		local ty = 105

		rectfill(tx + 24, ty, tx + 50, ty + 20, 5)
		rectfill(tx + 23, ty - 1, tx + 49, ty + 19, 0)
		print('DRT', tx + 24, ty, 6)
		local dcol = 6
		if drought >= 15 then dcol = 8 end
		print(hideZeroes(zeroPad(''..drought, 3)), tx + 37, ty + 13, dcol)
	end


	--draw pieces stats
	if showstats then
		local px, py = showdas and 3 or 21, 65

		rectfill(px, py - 2, px + 13, py + 60, 5)
		rectfill(px - 1, py - 3, px + 12, py + 59, 0)

		print('PCS', px, py - 2, 6)

		--2=0010 3=0011 5=0101 8=1000 11=1011 12=1100 13=1101 14=1110 15=1111
		local cols = { 0b100011001110, 0b111000101110, 0b010110110011, 0b111111011111, 0b110111001100 }
		local pcsl = 'TJZOSLI'
		local s = sprlock > -1 and sprlock or level % sprnumber

		for i = 1, 7 do
			print(pcsl[i], px, py+4 + 7*i, cols[s+1] >> (i-1)%3 * 4)
			print(hideZeroes(zeroPad(''..piecesStats[i], 2)), px+4, py+11 + 7 * (i-1), 6)
		end
	end

	--draw das
	if showdas then
		local dx = 20
		local dy = 60

		rectfill(dx + 1, dy + 3, dx + 14, dy + 65, 5)
		rectfill(dx, dy + 2, dx + 13, dy + 64, 0)

		local col = 6
		local themedcol = 14
		local s = level % sprnumber
		if sprlock > -1 then
			s = sprlock
		end

		if s % sprnumber == 0 then
			themedcol = 14
		elseif s % sprnumber == 1 then
			themedcol = 2
		elseif s % sprnumber == 2 then
			themedcol = 3
		elseif s % sprnumber == 3 then
			themedcol = 15
		elseif s % sprnumber == 4 then
			themedcol = 12
		end


		if das >= dasMax - asMax then col = themedcol end
		print(hideZeroes(zeroPad(""..das, 3)), dx + 1, dy + 53, col)
		print('DAS', dx + 1, dy + 58, 6)
		for i = 1, 16 do
			if i <= das then
				rectfill(dx + 2, dy+53-i*3, dx + 11, dy+53-i*3-1, col)
			end
		end
	end

	--draw level, total lines and score
	local gux = 100
	local guy = 5

	rectfill(gux, guy, gux + 26, guy + 14, 5)
	rectfill(gux - 1, guy - 1, gux + 25, guy + 13, 0)
	print("LV", gux, guy, 6)
	print("LI", gux, guy + 7, 6)
	print(hideZeroes(zeroPad(""..level, 3)), gux + 13, guy, 6)
	print(hideZeroes(zeroPad(""..lines, 3)), gux + 13, guy + 7, 6)

	local gux2 = 3
	local guy2 = 5

	rectfill(gux2, guy2, gux2 + 31, guy2 + 14, 5)
	rectfill(gux2 - 1, guy2 - 1, gux2 + 30, guy2 + 13, 0)
	print("SCORE", gux2, guy2, 6)
	print(hideZeroes(zeroPad(fixScore(score1, score2), 7)), gux2 + 2, guy2 + 7, 6)

	local gux3 = 3
	local guy3 = 23

	rectfill(gux3, guy3, gux3 + 31, guy3 + 14, 5)
	rectfill(gux3 - 1, guy3 - 1, gux3 + 30, guy3 + 13, 0)
	print("HIGH", gux3, guy3, 6)
	print(hideZeroes(zeroPad(fixScore(highscore1, highscore2), 7)), gux3 + 2, guy3 + 7, 6)

	--draw replay saving popup
	if saving then
		rectfill(36, 64 - 4, 96, 64 + 5, 0)
		print("SAVING REPLAY", 41, 64 - 2, 6)
	end


	if menu == 0 then
		--draw main menu
		print("CLASSIC", 64 - 20, 20, 6)
		print("PICOTRIS", 64 - 7, 30, 6)

		--title processing
		if t % 5 == 0 then yanim += 1 end
		if yanim >= 45 then yanim = 15 end

		for i = 40, 90 do
			local p = pget(i, yanim - 1)
			pset(i, yanim - 1, 0)
			if p == 6 then
				pset(i, yanim - 1, 14)
			end

			local p = pget(i, yanim)
			pset(i, yanim, 0)
			if p == 6 then
				pset(i, yanim, 8)
			end

			local p = pget(i, yanim + 1)
			pset(i, yanim + 1, 0)
			if p == 6 then
				pset(i, yanim + 1, 8)
			end

			local p = pget(i, yanim + 2)
			pset(i, yanim + 2, 0)
			if p == 6 then
				pset(i, yanim + 2, 14)
			end
		end

		local selcol1 = 6
		if menucursor == 0 then
			if t % 20 < 10 then
				selcol1 = 14
			else
				selcol1 = 6
			end
		end
		print("START", 64 - 8, 80, selcol1)

		local selcol2 = 6
		if menucursor == 1 then selcol2 = 12 end
		print("LEVEL", 64 - 8, 90, selcol2)
		if menucursor != 1 then
			print(zeroPad(""..menulv, 2), 64 - 2, 97, selcol2)
		else
			print("["..zeroPad(""..menulv, 2).."]", 64 - 6, 97, selcol2)
			if menulv == 0 then
				print(zeroPad(""..19, 2), 64 - 20, 97, 6)
			else
				print(zeroPad(""..menulv-1, 2), 64 - 20, 97, 6)
			end
			if menulv == 19 then
				print(zeroPad(""..0, 2), 64 + 16, 97, 6)
			else
				print(zeroPad(""..menulv+1, 2), 64 + 16, 97, 6)
			end
		end

		local selcol3 = 6
		if menucursor == 2 then selcol3 = 11 end
		print("REPLAYS", 64 - 12, 106, selcol3)

		local selcol4 = 6
		if menucursor == 3 then selcol4 = 9 end
		print("CUSTOMIZE", 64 - 16, 116, selcol4)
	elseif menu == 1 then
		--draw optionsmenu
		local selcol1 = 6
		if menucursor == 0 then selcol1 = 14 end
		print("PALETTE LOCK", 43, 5, selcol1)
		local x = 57
		if sprlock == -1 then
			print("---", x + 4, 12, selcol1)
		else
			for i = 1, 3 do
				spr((i + (3 * sprlock)) + (16 * sprtheme), x + ((i-1) * 6), 12)
			end
		end

		local selcol2 = 6
		if menucursor == 1 then selcol2 = 12 end
		print("THEME", 57, 25, selcol2)
		local sl = sprlock
		if sl == -1 then sl = 0 end
		for i = 1, 3 do
			spr((i + (3 * sl)) + (16 * sprtheme), x + ((i-1) * 6), 32)
		end

		local selcol3 = 6
		if menucursor == 2 then selcol3 = 9 end
		print("SHOW DAS", 51, 45, selcol3)
		local l = "N"
		if showdas == true then l = "Y" end
		print(l, 65, 51, selcol3)

		local selcol4 = 6
		if menucursor == 3 then selcol4 = 10 end
		print("SHOW STATS", 47, 59, selcol4)
		local l = "N"
		if showstats == true then l = "Y" end
		print(l, 65, 65, selcol4)

		local selcol4 = 6
		if menucursor == 4 then selcol4 = 11 end
		print("SHOW RATE", 49, 73, selcol4)
		local l = "N"
		if showrate == true then l = "Y" end
		print(l, 65, 79, selcol4)

		local selcol4 = 6
		if menucursor == 5 then selcol4 = 12 end
		print("SHOW DROUGHT", 43, 87, selcol4)
		local l = "N"
		if showdrought == 0 then l = "N"
		elseif showdrought == 1 then l = "DYNAMIC"
		elseif showdrought == 2 then l = "ALWAYS" end
		local drx = 65
		if showdrought == 1 then drx = 54
		elseif showdrought == 2 then drx = 55 end
		print(l, drx, 93, selcol4)

		local selcol5 = 6
		if menucursor == 6 then selcol5 = 14 end
		print("SWAP BUTTONS", 43, 102, selcol5)
		local l = "N"
		if swapbtns == 1 then l = "Y" end
		print(l, 65, 108, selcol5)

		local selcol5 = 6
		if menucursor == 7 then selcol5 = 13 end
		print("BACK", 59, 118, selcol5)
	elseif menu == 2 then
		--draw replays menu
		if loadtutorialpage == 0 then
			print("TO LOAD A \nREPLAY, DRAG \nAND DROP A \nREPLAY FILE \nINTO THIS \nSCREEN.", 39, 5, 5)
			print(
				"\nYOUR LAST \nPLAYED GAME IS \nALWAYS SAVED \nAS REPLAY.TXT \nON GAME OVER."..
				"\nBE SURE TO \nRENAME IT IF \nYOU WANT TO \nKEEP IT.",
				39, 37, 5
			)
		elseif loadtutorialpage == 1 then
			print("YOUR LAST GAME \nIS ALSO SAVED \nTO THE \nCLIPBOARD FOR \nQUICK SHARING.", 39, 5, 5)
			print("A CTRL+V HERE \nWILL LOAD A \nREPLAY \nCURRENTLY \nCOPIED TO YOUR \nCLIPBOARD.", 39, 37, 5)
		end

		circfill(61, 100, 1, 6 - loadtutorialpage)
		circfill(67, 100, 1, 5 + loadtutorialpage)

		if t % 80 < 40 then
			spr(65, 55, 95)
			spr(67, 69, 95)
		end

		if menucursor == 0 then
			selcol1 = 11
			selcol2 = 6
		elseif menucursor == 1 then
			selcol1 = 6
			selcol2 = 14
		end
		print("OPEN SAVE \nFOLDER", 39, 104, selcol1)
		print("BACK", 39, 117, selcol2)
	elseif menu == 3 then
		--draw replayload menu
		print("LOAD OK", 39, 6, 6)
		print("DATE "..replaydate, 39, 26, 6)
		print("SCORE   "..hideZeroes(zeroPad(replayscore, 6)), 39, 26 + 10, 6)
		print("TIME     "..zeroPad(replayduration.m.."", 2)..":"..zeroPad(replayduration.s.."", 2), 39, 26 + 20, 6)
		print("START LV    "..zeroPad(startinglevel.."", 2), 39, 26 + 30, 6)
		print("END LV      "..zeroPad(replaymaxlv, 2), 39, 26 + 40, 6)
		print("LINES      "..hideZeroes(zeroPad(replaylines, 3)), 39, 26 + 50, 6)
		print("TRT       "..hideZeroes(zeroPad(replaytrt, 3)).."%", 39, 26 + 60, 6)

		if menucursor == 0 then
			if t % 20 < 10 then
				selcol1 = 11
			else
				selcol1 = 0
			end
			selcol2 = 6
		elseif menucursor == 1 then
			selcol1 = 6
			selcol2 = 14
		end
		print("START REPLAY", 39, 109, selcol1)
		print("BACK", 39, 117, selcol2)
	end
end



--refresh grid
function gridRefresh(grid, gx, gy)
	for i = 1, gx do
		for k = 1, gy do
			if grid[i][k].falling then
				grid[i][k].falling = false
			end
		end
	end
end



--generate and rotate tetromino
function tetroGen(x, y, rot, shape)
	local x = x
	local y = y
	local shape = shape
	local selshape = {}
	local rot = rot
	local spr = 0

	--rotation lock
	if shape == 0 then
		rot = 0
	elseif shape == 2 or shape == 3 or shape == 4 then
		rot = rot % 2
	else
		rot = rot % 4
	end

	--set sprite
	local s = sprshift
	if sprlock > -1 then
		s = (sprlock * 3) + (sprtheme * 16)
	end
	if shape == 0 or shape == 1 or shape == 2 then
		spr = 3 + s
	elseif shape == 3 or shape == 6 then
		spr = 2 + s
	else
		spr = 1 + s
	end
	
	--all shapes and rotations
	shapes = {
		{
			--o
			s = 0,
			blocks = {
				{
					r = 0,
					b = {
						{ x = x, y = y },
						{ x = x - 1, y = y },
						{ x = x, y = y + 1 },
						{ x = x - 1, y = y + 1 }
					}
				}
			}
		},
		{
			--t
			s = 1,
			blocks = {
				{
					r = 0,
					b = {
						{ x = x, y = y },
						{ x = x - 1, y = y },
						{ x = x + 1, y = y },
						{ x = x, y = y + 1 }
					}
				},
				{
					r = 1,
					b = {
						{ x = x, y = y },
						{ x = x - 1, y = y },
						{ x = x, y = y - 1 },
						{ x = x, y = y + 1 }
					}
				},
				{
					r = 2,
					b = {
						{ x = x, y = y },
						{ x = x - 1, y = y },
						{ x = x + 1, y = y },
						{ x = x, y = y - 1 }
					}
				},
				{
					r = 3,
					b = {
						{ x = x, y = y },
						{ x = x, y = y - 1 },
						{ x = x, y = y + 1 },
						{ x = x + 1, y = y }
					}
				}
			}
		},
		{
			--i
			s = 2,
			blocks = {
				{
					r = 0,
					b = {
						{ x = x, y = y },
						{ x = x - 1, y = y },
						{ x = x - 2, y = y },
						{ x = x + 1, y = y },
					}
				},
				{
					r = 1,
					b = {
						{ x = x, y = y },
						{ x = x, y = y + 1 },
						{ x = x, y = y - 1 },
						{ x = x, y = y - 2 }
					}
				}
			}
		},
		{
			--s
			s = 3,
			blocks = {
				{
					r = 0,
					b = {
						{ x = x, y = y },
						{ x = x, y = y + 1 },
						{ x = x - 1, y = y + 1 },
						{ x = x + 1, y = y}
					}
				},
				{
					r = 1,
					b = {
						{ x = x, y = y },
						{ x = x, y = y - 1 },
						{ x = x + 1, y = y },
						{ x = x + 1, y = y + 1 }
					}
				}
			}
		},
		{
			--z
			s = 4,
			blocks = {
				{
					r = 0,
					b = {
						{ x = x, y = y + 1 },
						{ x = x, y = y },
						{ x = x - 1, y = y },
						{ x = x + 1, y = y + 1 }
					}
				},
				{
					r = 1,
					b = {
						{ x = x, y = y + 1 },
						{ x = x, y = y },
						{ x = x + 1, y = y },
						{ x = x + 1, y = y - 1 }
					}
				}
			}
		},
		{
			--l
			s = 5,
			blocks = {
				{
					r = 0,
					b = {
						{ x = x, y = y },
						{ x = x - 1, y = y },
						{ x = x + 1, y = y },
						{ x = x - 1, y = y + 1 }
					}
				},
				{
					r = 1,
					b = {
						{ x = x, y = y },
						{ x = x, y = y - 1 },
						{ x = x, y = y + 1 },
						{ x = x - 1, y = y - 1 }
					}
				},
				{
					r = 2,
					b = {
						{ x = x, y = y },
						{ x = x - 1, y = y },
						{ x = x + 1, y = y },
						{ x = x + 1, y = y - 1 }
					}
				},
				{
					r = 3,
					b = {
						{ x = x, y = y },
						{ x = x, y = y - 1 },
						{ x = x, y = y + 1 },
						{ x = x + 1, y = y + 1 }
					}
				}
			}
		},
		{
			--j
			s = 6,
			blocks = {
				{
					r = 0,
					b = {
						{ x = x, y = y },
						{ x = x - 1, y = y },
						{ x = x + 1, y = y },
						{ x = x + 1, y = y + 1 }
					}
				},
				{
					r = 1,
					b = {
						{ x = x, y = y },
						{ x = x, y = y - 1 },
						{ x = x, y = y + 1 },
						{ x = x - 1, y = y + 1 }
					}
				},
				{
					r = 2,
					b = {
						{ x = x, y = y },
						{ x = x - 1, y = y },
						{ x = x + 1, y = y },
						{ x = x - 1, y = y - 1 }
					}
				},
				{
					r = 3,
					b = {
						{ x = x, y = y },
						{ x = x, y = y + 1 },
						{ x = x, y = y - 1 },
						{ x = x + 1, y = y - 1 }
					}
				}
			}
		}
	}

	for s in all(shapes) do
		if s.s == shape then
			for b in all(s.blocks) do
				if b.r == rot then
					selshape = b.b
				end
			end
		end
	end
	
	return { 
		shape = shape,
		x = x,
		y = y,
		blocks = selshape,
		rot = rot,
		spr = spr
	}
end


--boolean to int
function boolToInt(bool)
	if bool then
		return 1
	else
		return 0
	end
end


--check collision with locked
function checkLocked()
	for b in all(tetro.blocks) do
		if b.y < 20 and grid[b.x][b.y+1].locked then
			return true
		end
	end
end



--check collision with sides
function checkSide(side)
	--0 = left
	--1 = right
	--2 = down
	if side == 0 then
		for b in all(tetro.blocks) do
			if b.x == 1 then
				return true
			else
				if b.y > 0 then
					if grid[b.x - 1][b.y].locked then
						return true
					end
				end
			end
		end
	elseif side == 1 then
		for b in all(tetro.blocks) do
			if b.x == 10 then
				return true
			else
				if b.y > 0 then
					if grid[b.x + 1][b.y].locked then
						return true
					end
				end
			end
		end
	else
		for b in all(tetro.blocks) do
			if b.y == 20 then
				return true
			else
				if b.y > 0 then
					if grid[b.x][b.y + 1].locked then
						return true
					end
				end
			end
		end
	end

	return false
end



--line clear
function lineClearCheck()
	for i = gy, 1, -1 do
		local allLocked = true
		for k = 1, gx do
			if not grid[k][i].locked then
				allLocked = false
			end
		end

		if allLocked then
			local found = false
			for l in all(clearLines) do
				if i == l then
					found = true
					break
				end
			end
			if not found then
				add(clearLines, i)
				clear = true
			end
		end
	end
end



--delete falling frame - 1
function delOldFalling()
	for b in all(tetro.blocks) do
		if b.y > 0 then
			grid[b.x][b.y].falling = false
			grid[b.x][b.y].spr = 0
		end
	end
end
--draw falling frame
function drawNewFalling()  
	for b in all(tetro.blocks) do
		if b.y > 0 then
			grid[b.x][b.y].falling = true
			grid[b.x][b.y].spr = tetro.spr
		end
	end
end



--check for rotation blocked by walls
function blockedRotation(tetro, rot)
	--check against walls
	local x = tetro.x
	local shape = tetro.shape
	if shape == 3 or shape == 4 then
		if x == 1 then return true end
	elseif tetro.shape == 2 then
		if x <= 2 or x == 10 then return true end
	elseif tetro.shape == 1 or shape == 5 or shape == 6 then
		if x == 1 or x == 10 then return true end
	end

	--check against other locked tetrominoes
	local tempTetro = tetroGen(tetro.x, tetro.y, rot, tetro.shape)
	local blocked = false

	for b in all(tempTetro.blocks) do
		if b.y > 20 then
			return true
		end
		if b.y > 1 then
			if grid[b.x][b.y].locked then
				blocked = true
				break
			end
		end
	end 
	if blocked then return true end

	return false
end



function qsort(a,c,l,r)
	c,l,r=c or function(a,b) return a<b end,l or 1,r or #a
	if l<r then
		if c(a[r],a[l]) then
			a[l],a[r]=a[r],a[l]
		end
		local lp,k,rp,p,q=l+1,l+1,r-1,a[l],a[r]
		while k<=rp do
			local swaplp=c(a[k],p)
			-- "if a or b then else"
			-- saves a token versus
			-- "if not (a or b) then"
			if swaplp or c(a[k],q) then
			else
				while c(q,a[rp]) and k<rp do
					rp-=1
				end
				a[k],a[rp],swaplp=a[rp],a[k],c(a[rp],p)
				rp-=1
			end
			if swaplp then
				a[k],a[lp]=a[lp],a[k]
				lp+=1
			end
			k+=1
		end
		lp-=1
		rp+=1
		-- sometimes lp==rp, so 
		-- these two lines *must*
		-- occur in sequence;
		-- don't combine them to
		-- save a token!
		a[l],a[lp]=a[lp],a[l]
		a[r],a[rp]=a[rp],a[r]
		qsort(a,c,l,lp-1       )
		qsort(a,c,  lp+1,rp-1  )
		qsort(a,c,       rp+1,r)
	end
end


function fixScore(score1, score2)
	if score1 >= 100 then return score2..score1
	elseif score1 >= 10 then return score2.."0"..score1
	else return score2.."00"..score1 end
end

function zeroPad(string, length)
	if (#string == length) then return string
	else return "0"..zeroPad(string, length-1) end
end

function hideZeroes(string)
	local canc = true
	local newS = ""

	for i = 1, #string do
		c = sub(string, i, i)
		if c != "0" or i == #string then canc = false end
		if canc == true and c == "0" then c = " " end
		newS = newS..c
	end

	return newS
end

function eraseZeroes(string)
	local canc = true
	local newS = ""

	for i = 1, #string do
		c = sub(string, i, i)
		if c != "0" or i == #string then canc = false end
		if canc and c == "0" then c = "" end
		newS = newS..c
	end

	return newS
end


function rbtn(input)
	if not replaymode then
		return btn(input)
	else
		local replayinput = replayinputs[replaypage][replayindex]
		local mask = 0b100000
		for i = 0,5 do
			if input == i then
				return replayinput & (mask >> i) == (mask >> i)
			end
		end
	end
end


--save variables to replay file and clipboard
function saveToFile(str)
  replayduration = { m = #replayinputs - 1, s = flr(#replayinputs[#replayinputs] / 60) }
	str = "Date: "..stat(90).."/"..stat(91).."/"..stat(92).."\n"..
		"Score: "..eraseZeroes(fixScore(score1, score2)).."\n"..
		"Duration: "..zeroPad(""..replayduration.m, 2)..":"..zeroPad(""..replayduration.s, 2).."\n"..
		"Starting level: "..startinglevel.."\n"..
		"Level: "..level.."\n"..
		"Lines cleared: "..lines.."\n"..
		"Tetris rate: "..trt.."%".."\n"..
		"*".."\n"..
		eraseZeroes(stat(90).."-"..stat(91).."-"..stat(92).."/"..fixScore(score1, score2)).."/"..startinglevel.."/"..level.."/"..lines.."/"..trt.."/"..str.."/"..piecesToString()

		printh(str, "replay.txt", true)
		printh(str, "@clip")
end

--converts replaypieces to string
function piecesToString()
  local str = ""
  for i = 1, #replaypieces, 1 do
  	str = str..replaypieces[i]
  end
  return str 
end


--converts string to replayinputs and replaypieces tables
function fromString(str)
	replayinputs = {}
	add(replayinputs, {})
	replaypieces = {}
	local parts = split(str, "/", false)
	local page = 1
	local index = 1

	--replayinputs decoding
	local inputcompressed = split(parts[7], "=", false)
	local indexes = split(inputcompressed[1], ",", true)
	local inputtable = split(inputcompressed[2], ",", false)
	for i = 1, #indexes do
		local input = split(inputtable[indexes[i]], "-", true)

		for k = 1, input[2] do
			add(replayinputs[page], input[1])

			if index <= pagesize then
				index += 1
			else
				add(replayinputs, {})
				page += 1
				index = 1
			end
		end
	end

	--replaypieces
	local pieces = parts[8]
	for p in all(pieces) do
		add(replaypieces, tonum(p))
	end

	replayduration = { m = #replayinputs - 1, s = flr(#replayinputs[#replayinputs] / 60) }
	replaydate = parts[1]
	replayscore = parts[2]
	startinglevel = tonum(parts[3])
	replaymaxlv = parts[4]
	replaylines = parts[5]
	replaytrt = parts[6]
end


__gfx__
00000001000000010000000100000001000000010000000100000001000000010000000100000001000000010000000100000001000000010000000100000001
000000010788880107cccc0107eeee0107eeee010722220107eeee010733330107bbbb0107bbbb0107ffff0107dddd0107ffff0107dddd0107cccc0107cccc01
00000001087788010c77cc010e777e010e77ee01027722010e777e01037733010b777b010b77bb010f77ff010d77dd010f777f010d77dd010c77cc010c777c01
00000001087888010c7ccc010e777e010e7eee01027222010e777e01037333010b777b010b7bbb010f7fff010d7ddd010f777f010d7ddd010c7ccc010c777c01
00000001088888010ccccc010e777e010eeeee01022222010e777e01033333010b777b010bbbbb010fffff010ddddd010f777f010ddddd010ccccc010c777c01
00000001088888010ccccc010eeeee010eeeee01022222010eeeee01033333010bbbbb010bbbbb010fffff010ddddd010fffff010ddddd010ccccc010ccccc01
00000001000000010000000100000001000000010000000100000001000000010000000100000001000000010000000100000001000000010000000100000001
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
00000000000000010000000100000001000000010000000100000001000000010000000100000001000000010000000100000001000000010000000100000001
0000000007e8e801076c6c0107fefe0107fefe0107e2e20107fefe0107d3d301076b6b0107b3b301077f7f01076d6d01077f7f01076d6d01076c6c01076c6c01
000000000e778e010677c6010f777f010f77ef010e772e010f777f010d773d01067776010b773b010777f7010677d601077777010677d6010677c60106777601
000000000878e8010c7c6c010e777e010e7efe010272e2010e777e010373d3010b777b010373b3010f7f7f010d7d6d010f777f010d7d6d010c7c6c010c777c01
000000000e8e8e0106c6c6010f777f010fefef010e2e2e010f777f010d3d3d01067776010b3b3b0107f7f70106d6d6010777770106d6d60106c6c60106777601
0000000008e8e8010c6c6c010efefe010efefe0102e2e2010efefe0103d3d3010b6b6b0103b3b3010f7f7f010d6d6d010f7f7f010d6d6d010c6c6c010c6c6c01
00000000000000010000000100000001000000010000000100000001000000010000000100000001000000010000000100000001000000010000000100000001
00000000111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
00000000000000010000000100000001000000010000000100000001000000010000000100000001000000010000000100000001000000010000000100000001
00000000088888010ccccc010eeeee010eeeee01022222010eeeee01033333010bbbbb010bbbbb010fffff010ddddd010fffff010ddddd010ccccc010ccccc01
00000000088888010ccccc010eeeee010eeeee01022222010eeeee01033333010bbbbb010bbbbb010fffff010ddddd010fffff010ddddd010ccccc010ccccc01
00000000088888010ccccc010eeeee010eeeee01022222010eeeee01033333010bbbbb010bbbbb010fffff010ddddd010fffff010ddddd010ccccc010ccccc01
00000000088888010ccccc010eeeee010eeeee01022222010eeeee01033333010bbbbb010bbbbb010fffff010ddddd010fffff010ddddd010ccccc010ccccc01
00000000088888010ccccc010eeeee010eeeee01022222010eeeee01033333010bbbbb010bbbbb010fffff010ddddd010fffff010ddddd010ccccc010ccccc01
00000000000000010000000100000001000000010000000100000001000000010000000100000001000000010000000100000001000000010000000100000001
00000000111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
00000000000000010000000100000001000000010000000100000001000000010000000100000001000000010000000100000001000000010000000100000001
00000000088788010cc7cc010ee7ee010ee7ee01022622010ee7ee01033633010bb7bb01033633010ff7ff010dd6dd010ff7ff010dd6dd010cc7cc010cc7cc01
00000000088888010ccccc010eeeee010eeeee01022222010eeeee01033333010bbbbb01033333010fffff010ddddd010fffff010ddddd010ccccc010ccccc01
000000000788870107ccc70107eee70107eee7010622260107eee7010633360107bbb7010633360107fff70106ddd60107fff70106ddd60107ccc70107ccc701
00000000088888010ccccc010eeeee010eeeee01022222010eeeee01033333010bbbbb01033333010fffff010ddddd010fffff010ddddd010ccccc010ccccc01
00000000088788010cc7cc010ee7ee010ee7ee01022622010ee7ee01033633010bb7bb01033633010ff7ff010dd6dd010ff7ff010dd6dd010cc7cc010cc7cc01
00000000000000010000000100000001000000010000000100000001000000010000000100000001000000010000000100000001000000010000000100000001
00000000111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00600000006000000000000000600000006000000606000000000000000000000000000000000000000000000000000000000000000000000000000000000000
06060000060000000606000000060000060600000060000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000006000000060000000600000006000000606000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
66666000666660006666600066666000666660006666600000000000000000000000000000000000000000000000000000000000000000000000000000000000
66066000660660006666600066066000660660006060600000000000000000000000000000000000000000000000000000000000000000000000000000000000
60606000606660006060600066606000606060006606600000000000000000000000000000000000000000000000000000000000000000000000000000000000
66666000660660006606600066066000660660006060600000000000000000000000000000000000000000000000000000000000000000000000000000000000
66666000666660006666600066666000666660006666600000000000000000000000000000000000000000000000000000000000000000000000000000000000
__label__
76767676767676767676767676767676767676767676767676767676767676767676767676767676767676767676767676767676767676767676767676767676
67676767676767676767676767676767676767676767676767676767676767676767676767676767676767676767676767676767676767676767676767676767
76767676767676767676767676767676767676767676767676767676767676767676767676767676767676767676767676767676767676767676767676767676
67676767676767676767676767676767676767676767676767676767676767676767676767676767676767676767676767676767676767676767676767676767
76000000000000000000000000000000007600000000000000000000000000000000000000000000000000000000000006700000000000000000000000000076
67000000000000000000000000000000005700000000000000000000000000000000000000000000000000000000000005600000000000000000000006660057
76006600660066066006660000000000005600000000000000000000000000000000000000000000000000000000000005706000606000000000000006060056
67060006000606060606600000000000005700000000000000000000000000000000000000000000000000000000000005606000606000000000000006060057
76000606000606066006000000000000005600000000000000000000000000000000000000000000000000000000000005706000666000000000000006060056
67066000660660060600660000000000005700000000000000000000000000000000000000000000000000000000000005600660060000000000000006660057
76000000000000000000000000000000005600000000000000000000000000000000000000000000000000000000000005700000000000000000000000000056
67000000000000000000000000000000005700000000000000000000000000000000000000000000000000000000000005600000000000000000000000000057
76000000000000000000000000000666005600000000000000000000000000000000000000000000000000000000000005700000000000000000000006660056
67000000000000000000000000000606005700000000000000000000000000000000000000000000000000000000000005606000666000000000000006060057
76000000000000000000000000000606005600000000000000000000000000000000000000000000000000000000000005706000060000000000000006060056
67000000000000000000000000000606005700000000000000000000000000000000000000000000000000000000000005606000060000000000000006060057
76000000000000000000000000000666005600000000000000000000000000000000000000000000000000000000000005700660666000000000000006660056
67000000000000000000000000000000005700000000000000000000000000000000000000000000000000000000000005600000000000000000000000000057
76000000000000000000000000000000005600000000000000000000000000000000000000000000000000000000000005700000000000000000000000000056
67655555555555555555555555555555555700000000000000000000000000000000000000000000000000000000000005675555555555555555555555555557
76767676767676767676767676767676767600000000000000000000000000000000000000000000000000000000000005767676767676767676767676767676
67676767676767676767676767676767676700000000066060000660066006606660066000000000000000000000000005676767676767676767676767676767
76000000000000000000000000000000007600000000600060006060600060000600600000000000000000000000000005700000000000000000000000000076
67000000000000000000000000000000005700000000600060006660006000600600600000000000000000000000000005600000000000000000000000000057
76060606660066060600000000000000005600000000066006606060660066006660066000000000000000000000000005706660660066600000000000000056
67060600600600060600000000000000005700000000000000000000000000000000000000000000000000000000000005600600606006000000000000000057
76066600600606066600000000000000005600000000000000000000000000000000000000000000000000000000000005700600660006000000000000000056
67060606660666060600000000000000005700000000000000000000000000000000000000000000000000000000000005600600606006000000000000000057
76000000000000000000000000000000005600000000000000000000000000000000000000000000000000000000000005700000000000000000000000000056
67000000000000000000000000000000005700000000000000000000000000000000000000000000000000000000000005600000000000000000000000000057
76000000066606660666066606060666005600000000000000000000000000000000000000000000000000000000000005700000000000000000066606060056
67000000060600060006060006060606005700000000000000000000008808880088008808880880088800880000000005600000000000000000060600060057
760000000666006600060666066606060056000000000000000000000e0e00e00e000e0e00e00e0e00e00e000000000005700000000000000000060600600056
67000000060600060006000600060606005700000000000000000000066600600600060600600660006000060000000005600000000000000000060606000057
76000000066606660006066600060666005600000000000000000000060006660066066000600606066606600000000005700000000000000000066606060056
67000000000000000000000000000000005700000000000000000000000000000000000000000000000000000000000005600000000000000000000000000057
76000000000000000000000000000000005600000000000000000000000000000000000000000000000000000000000005700000000000000000000000000056
67655555555555555555555555555555555700000000000000000000000000000000000000000000000000000000000005675555555555555555555555555557
76767676767676767676767676767676767600000000000000000000000000000000000000000000000000000000000005767676767676767676767676767676
67676767676767676767676767676767676700000000000000000000000000000000000000000000000000000000000005676767676767676767676767676767
76767676767676767676767676767676767600000000000000000000000000000000000000000000000000000000000005767676767676767676767676767676
67676767676767676767676767676767676700000000000000000000000000000000000000000000000000000000000005676767676767676767676767676767
76767676767676767676767676767676767600000000000000000000000000000000000000000000000000000000000005767676767676767676767676767676
67676767676767676767676767676767676700000000000000000000000000000000000000000000000000000000000005676767676767676767676767676767
76767676767676767676767676767676767600000000000000000000000000000000000000000000000000000000000005767676767676767676767676767676
67676767676767676767676767676767676700000000000000000000000000000000000000000000000000000000000005676767676767676767676767676767
76767676767676767676767676767676767600000000000000000000000000000000000000000000000000000000000005767676767676767676767676767676
67676767676767676767676767676767676700000000000000000000000000000000000000000000000000000000000005676767676767676767676767676767
76767676767676767676767676767676767600000000000000000000000000000000000000000000000000000000000005767676767676767676767676767676
67676767676767676767676767676767676700000000000000000000000000000000000000000000000000000000000005676767676767676767676767676767
76767676767676767676767676767676767600000000000000000000000000000000000000000000000000000000000005767676767676767676767676767676
67676767676767676767676767676767676700000000000000000000000000000000000000000000000000000000000005676767676767676767676767676767
76767676767676767676767676767676767600000000000000000000000000000000000000000000000000000000000005767676767676767676767676767676
67676767676767676767676767676767676700000000000000000000000000000000000000000000000000000000000005676767676767676767676767676767
76767676767676767676767676767676767600000000000000000000000000000000000000000000000000000000000005767676767676767676767676767676
67676767676767676767676767676767676700000000000000000000000000000000000000000000000000000000000005676767676767676767676767676767
76767676767676767676767676767676767600000000000000000000000000000000000000000000000000000000000005767676767676767676767676767676
67676767676767676767676767676767676700000000000000000000000000000000000000000000000000000000000005676767676767676767676767676767
76767676767676767676767676767676767600000000000000000000000000000000000000000000000000000000000005767676767676767676767676767676
67676767676767676767676767676767676700000000000000000000000000000000000000000000000000000000000005676767676767676767676767676767
76767676767676767676767676767676767600000000000000000000000000000000000000000000000000000000000005767676767676767676767676767676
67676767676767676767676767676767676700000000000000000000000000000000000000000000000000000000000005676767676767676767676767676767
76000000000000007676000000000000007600000000000000000000000000000000000000000000000000000000000005767676767676767676767676767676
67000000000000005767000000000000005700000000000000000000000000000000000000000000000000000000000005676767676767676767676767676767
76006600660066005676000000000000005600000000000000000000000000000000000000000000000000000000000005767676767676767676767676767676
67060606000600005767000000000000005700000000000000000000000000000000000000000000000000000000000005676767676767676767676767676767
76066606000006005676000000000000005600000000000000000000000000000000000000000000000000000000000005767676767676767676767676767676
67060000660660005767000000000000005700000000000000000000000000000000000000000000000000000000000005676767676767676767676767676767
76000000000000005676000000000000005600000000000000000000000000000000000000000000000000000000000005767676767676767676767676767676
67000000000000005767000000000000005700000000000000000000000000000000000000000000000000000000000005676767676767676767676767676767
76000000000000005676000000000000005600000000000000000000000000000000000000000000000000000000000005767676767676767676767676767676
67000000000000005767000000000000005700000000000000000000000000000000000000000000000000000000000005676767676767676767676767676767
76000000000000005676000000000000005600000000000000000000000000000000000000000000000000000000000005767676767676767676767676767676
67000000000000005767000000000000005700000000000000000000000000000000000000000000000000000000000005676767676767676767676767676767
76000000000000005676000000000000005600000000000000000000000000000000000000000000000000000000000005767676767676767676767676767676
67000000000000005767000000000000005700000000000000000000000000000000000000000000000000000000000005676767676767676767676767676767
76000000000666005676000000000000005600000000000000000000000000000000000000000000000000000000000005767676767676767676767676767676
670eee00000606005767000000000000005700000000000000000000000000000000000000000000000000000000000005676767676767676767676767676767
7600e000000606005676000000000000005600000000000000000000000000000000000000000000000000000000000005767676767676767676767676767676
6700e000000606005767000000000000005700000000000000000000000000000000000000000000000000000000000005600000000000000000000000000067
7600e000000666005676000000000000005600000000000000000000000000000000000000000000000000000000000005700000000000000000000000000056
67000000000000005767000000000000005700000000000000000000066066600660660066600000000000000000000005606600666060606660000000000057
76000000000000005676000000000000005600000000000000000000600006006060606006000000000000000000000005706060660006000600000000000056
67000000000666005767000000000000005700000000000000000000006006006660660006000000000000000000000005606060600006000600000000000057
760ccc00000606005676000000000000005600000000000000000000660006006060606006000000000000000000000005706060066060600600000000000056
6700c000000606005767000000000000005700000000000000000000000000000000000000000000000000000000000005600000000000000000000000000057
7600c000000606005676000000000000005600000000000000000000000000000000000000000000000000000000000005700000000000000000000000000056
670cc000000666005767000000000000005700000000000000000000000000000000000000000000000000000000000005600000000000000000000000000057
76000000000000005676000000000000005600000000000000000000000000000000000000000000000000000000000005700000000000000000000000000056
67000000000000005767000000000000005700000000000000000000000000000000000000000000000000000000000005600000000000000000000000000057
76000000000666005676000000000000005600000000000000000000000000000000000000000000000000000000000005700000000000000000000000000056
67088800000606005767000000000000005700000000000000000000600066606060666060000000000000000000000005600000000000000000000000000057
76000800000606005676000000000000005600000000000000000000600066006060660060000000000000000000000005700000000000000000000000000056
67080000000606005767000000000000005700000000000000000000600060006660600060000000000000000000000005600000000000000000000000000057
76088800000666005676000000000000005600000000000000000000066006600600066006600000000000000000000005700000000000000000000000000056
67000000000000005767000000000000005700000000000000000000000000000000000000000000000000000000000005600000000000000000000000000057
76000000000000005676000000000000005600000000000000000000000000000000000000000000000000000000000005700000000000000000000000000056
67000000000666005767000000000000005700000000000000000000000000666066600000000000000000000000000005600000000000000000000000000057
7600ee00000606005676000000000000005600000000000000000000000000606060600000000000000000000000000005700000000000000000000000000056
670e0e00000606005767000000000000005700000000000000000000000000606060600000000000000000000000000005600000000000000000000000000057
760e0e00000606005676000000000000005600000000000000000000000000606060600000000000000000000000000005765555555555555555555555555556
670ee000000666005767000000000000005700000000000000000000000000666066600000000000000000000000000005676767676767676767676767676767
76000000000000005676000000000000005600000000000000000000000000000000000000000000000000000000000005767676767676767676767676767676
67000000000000005767000000000000005700000000000000000000000000000000000000000000000000000000000005676767676767676767676767676767
76000000000666005676000000000000005600000000000000000000000000000000000000000000000000000000000005700000000000000000000000000076
6700cc00000606005767000000000000005700000000000000000000000000000000000000000000000000000000000005600000000000000000000000000057
760c0000000606005676000000000000005600000000000000000000000000000000000000000000000000000000000005706600666066000660000000000056
67000c00000606005767000000000000005700000000000000006600666006606000066060600660000000000000000005606600060060606000000000000057
760cc000000666005676000000000000005600000000000000006060660060606000606066606000000000000000000005706060060060600060000000000056
67000000000000005767000000000000005700000000000000006600600066606000666000600060000000000000000005606660060060606600000000000057
76000000000000005676000000000000005600000000000000006060066060000660606066006600000000000000000005700000000000000000000000000056
67000000000666005767000000000000005700000000000000000000000000000000000000000000000000000000000005600000000000000000000000000057
76080000000606005676000000000000005600000000000000000000000000000000000000000000000000000000000005700000000000000000000000000056
67080000000606005767000000000666005700000000000000000000000000000000000000000000000000000000000005600000000000000000000000000057
76080000000606005676000000000606005600000000000000000000000000000000000000000000000000000000000005700000000600000000000000000056
67008800000666005767000000000606005700000000000000000000000000000000000000000000000000000000000005600000006060000000000000000057
76000000000000005676000000000606005600000000000000000000000000000000000000000000000000000000000005700000000000000000000000000056
67000000000000005767000000000666005700000000000006606060066066600660666066606660666000000000000005600000000000000000000000000057
76000000000666005676000000000000005600000000000060006060600006006060666006000060660000000000000005700000000000000000000000000056
670eee00000606005767066000660066005700000000000060006060006006006060606006006000600000000000000005600060000000006000060006060057
7600e000000606005676060606060600005600000000000006600660660006006600606066606660066000000000000005700600006060000600606000600056
6700e000000606005767060606660006005700000000000000000000000000000000000000000000000000000000000005600060000600006000060006060057
760eee00000666005676066006060660005600000000000000000000000000000000000000000000000000000000000005700000000000000000000000000056
67000000000000005767000000000000005700000000000000000000000000000000000000000000000000000000000005600000000000000000000000000057
76000000000000005676000000000000005600000000000000000000000000000000000000000000000000000000000005700000000000000000000000000056
67655555555555555767655555555555555765555555555555555555555555555555555555555555555555555555555555675555555555555555555555555557
76767676767676767676767676767676767676767676767676767676767676767676767676767676767676767676767676767676767676767676767676767676
67676767676767676767676767676767676767676767676767676767676767676767676767676767676767676767676767676767676767676767676767676767

__sfx__
0001000029010330000000000000000000000000000000000000000000000003a0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000100000d0200b0200a0200902009020080200602004020020200002000020000000500004000020000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000200000d0200d0200d0200f0201002012020130201502017020180201a0201a0201c0201c0201c0101c01000000000000000000000000000000000000000000000000000000000000000000000000000000000
000200000d0201402016020180201a0201c0201e0201f02022020260202d020320203502035000350003502035020350203400035000350203502035020350003500035010350103501000000000003501035010
