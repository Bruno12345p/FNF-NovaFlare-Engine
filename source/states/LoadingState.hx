package states;

import haxe.Json;
import haxe.ds.StringMap;

import lime.utils.Assets;

import openfl.display.BitmapData;
import openfl.utils.AssetType;
import openfl.utils.Assets as OpenFlAssets;
import openfl.display.BitmapData;
import openfl.display.Shape;

import flixel.addons.transition.FlxTransitionableState;
import flixel.graphics.FlxGraphic;
import flixel.graphics.frames.FlxFilterFrames;
import flixel.FlxState;

import flash.filters.GlowFilter;

import states.editors.ChartingState;
import states.FreeplayState;

import backend.Song;
import backend.StageData;
import backend.Section;
import backend.Rating;

import objects.Note.EventNote; //why
import objects.*;

import sys.thread.Thread;
import sys.thread.Mutex;

class LoadingState extends MusicBeatState
{
	public static var loaded:Int = 0;
	public static var loadMax:Int = 0;
    
    public static var startChartLoad:Bool = false;
	static var requestedBitmaps:Map<String, BitmapData> = [];
	static var mutex:Mutex = new Mutex();
	
	static var isPlayState:Bool = false;
		
	function new(target:FlxState, stopMusic:Bool)
	{
		this.target = target;
		this.stopMusic = stopMusic;		
		startThreads();
		super();
	}

	inline static public function loadAndSwitchState(target:FlxState, stopMusic = false, intrusive:Bool = true)
		MusicBeatState.switchState(getNextState(target, stopMusic, intrusive));
	
	var target:FlxState = null;
	var stopMusic:Bool = false;
	var dontUpdate:Bool = false;
    
    var filePath:String = 'menuExtend/LoadingState/';
    
	var bar:FlxSprite;
    var button:LoadButton;
    var barHeight:Int = 10;
    
	var intendedPercent:Float = 0;
	var curPercent:Float = 0;
	var precentText:FlxText;	
	
	static var realStart:Bool = false;

	override public function create()
	{
		if (checkLoaded())
			dontUpdate = true;					
		
		Paths.clearStoredMemory();

		var bg = new FlxSprite().loadGraphic(Paths.image(filePath + 'loadScreen'));
		bg.setGraphicSize(Std.int(FlxG.width));
		bg.antialiasing = ClientPrefs.data.antialiasing;
		bg.updateHitbox();
		add(bg);			

		var bg:FlxSprite = new FlxSprite(0, FlxG.height - barHeight).makeGraphic(1, 1, FlxColor.BLACK);
		bg.scale.set(FlxG.width, barHeight);
		bg.updateHitbox();
		bg.alpha = 0.4;
		bg.screenCenter(X);
		add(bg);

		bar = new FlxSprite(0, FlxG.height - barHeight).makeGraphic(1, 1, FlxColor.WHITE);
		bar.scale.set(0, barHeight);
		bar.alpha = 0.6;
		bar.updateHitbox();
		add(bar);		
		
		button = new LoadButton(0, 0, 35, barHeight);
        button.y = FlxG.height - button.height;
        button.x = -button.width;
        button.antialiasing = ClientPrefs.data.antialiasing;
        button.updateHitbox();
        add(button);
        
        precentText = new FlxText(520, 600, 400, '0%', 30);
		precentText.setFormat(Paths.font("loadScreen.ttf"), 25, FlxColor.WHITE, RIGHT, OUTLINE_FAST, FlxColor.TRANSPARENT);
		precentText.borderSize = 0;
		precentText.antialiasing = ClientPrefs.data.antialiasing;
		add(precentText);		
		precentText.x = FlxG.width - precentText.width - 2;
        precentText.y = FlxG.height - precentText.height - barHeight - 2;                               
        		
		super.create();				
	}

	var transitioning:Bool = false;
	override function update(elapsed:Float)
	{
		super.update(elapsed);
		if (dontUpdate) return;		
		
		if (!realStart) startThreads();
		
		if (startChartLoad) 
        {
            preloadChart();
            startChartLoad = false;            
        }
        
		if (curPercent != intendedPercent)
		{
			if (Math.abs(curPercent - intendedPercent) < 0.001) curPercent = intendedPercent;
			else curPercent = FlxMath.lerp(intendedPercent, curPercent, Math.exp(-elapsed * 15));

			bar.scale.x = FlxG.width * curPercent - button.width / 2;
			button.x = bar.scale.x - button.width / 2;
			bar.updateHitbox();
			button.updateHitbox();
			var precent:Float = Math.floor(curPercent * 10000) / 100;
			if (precent % 1 == 0) precentText.text = precent + '.00%';
			else if ((precent * 10) % 1 == 0) precentText.text = precent + '0%';									
			else precentText.text = precent + '%'; //修复显示问题
		}
		
		if (!transitioning)
		{
			if (!finishedLoading && checkLoaded() && curPercent == 1)
			{
				transitioning = true;
				onLoad();
				return;
			}
			intendedPercent = loaded / loadMax;
		}
	}
	
	var finishedLoading:Bool = false; //use for stop update
	function onLoad()
	{
		if (stopMusic && FlxG.sound.music != null)
			FlxG.sound.music.stop();
		if (FreeplayState.vocals != null) FreeplayState.destroyFreeplayVocals();
					
		imagesToPrepare = [];
		soundsToPrepare = [];
		musicToPrepare = [];
		songsToPrepare = [];
        
        if (isPlayState){
            isPlayState = false;
            FlxTransitionableState.skipNextTransIn = true;
			FlxTransitionableState.skipNextTransOut = true;	
            MusicBeatState.switchState(new PlayState(unspawnNotes, noteTypes, events));
        } else {
		    MusicBeatState.switchState(target);
	    }
		transitioning = true;
		finishedLoading = true;
	}

	static function checkLoaded():Bool {
		for (key => bitmap in requestedBitmaps)
		{
			if (bitmap != null && Paths.cacheBitmap(key, bitmap) != null) trace('finished preloading image $key');
			else trace('failed to cache image $key');
		}
		requestedBitmaps.clear();
		return (loaded == loadMax);
	}

	static function getNextState(target:FlxState, stopMusic = false, intrusive:Bool = true):FlxState
	{
		var directory:String = 'shared';
		var weekDir:String = StageData.forceNextDirectory;
		StageData.forceNextDirectory = null;

		if (weekDir != null && weekDir.length > 0 && weekDir != '') directory = weekDir;

		Paths.setCurrentLevel(directory);
		trace('Setting asset folder to ' + directory);

		var doPrecache:Bool = false;
		if (ClientPrefs.data.loadingScreen)
		{
			clearInvalids();
			if(intrusive)
			{
				if (imagesToPrepare.length > 0 || soundsToPrepare.length > 0 || musicToPrepare.length > 0 || songsToPrepare.length > 0)
					return new LoadingState(target, stopMusic);
			}
			else doPrecache = true;
		}

		if (stopMusic && FlxG.sound.music != null)
			FlxG.sound.music.stop();
		
		if(doPrecache)
		{
			startThreads();
			while(true)
			{
				if(checkLoaded())
				{
					imagesToPrepare = [];
					soundsToPrepare = [];
					musicToPrepare = [];
					songsToPrepare = [];
					break;
				}
				else Sys.sleep(0.01);
			}
		}
		return target;
	}
	
	public static function clearInvalids()
	{
		clearInvalidFrom(imagesToPrepare, 'images', '.png', IMAGE);
		clearInvalidFrom(soundsToPrepare, 'sounds', '.${Paths.SOUND_EXT}', SOUND);
		clearInvalidFrom(musicToPrepare, 'music',' .${Paths.SOUND_EXT}', SOUND);
		clearInvalidFrom(songsToPrepare, 'songs', '.${Paths.SOUND_EXT}', SOUND, 'songs');

		for (arr in [imagesToPrepare, soundsToPrepare, musicToPrepare, songsToPrepare])
			while (arr.contains(null))
				arr.remove(null);
	}

	static function clearInvalidFrom(arr:Array<String>, prefix:String, ext:String, type:AssetType, ?library:String = null)
	{
		for (i in 0...arr.length)
		{
			var folder:String = arr[i];
			if(folder.trim().endsWith('/'))
			{
				for (subfolder in Mods.directoriesWithFile(Paths.getSharedPath(), '$prefix/$folder'))
					for (file in FileSystem.readDirectory(subfolder))
						if(file.endsWith(ext))
							arr.push(folder + file.substr(0, file.length - ext.length));
			}
		}

		var i:Int = 0;
		while(i < arr.length)
		{

			var member:String = arr[i];
			var myKey = '$prefix/$member$ext';
			if(library == 'songs') myKey = '$member$ext';

			//trace('attempting on $prefix: $myKey');
			var doTrace:Bool = false;
			if(member.endsWith('/') || (!Paths.fileExists(myKey, type, false, library) && (doTrace = true)))
			{
				arr.remove(member);
				if(doTrace) trace('Removed invalid $prefix: $member');
			}
			else i++;
		}
	}

	public static var imagesToPrepare:Array<String> = [];
	public static var soundsToPrepare:Array<String> = [];
	public static var musicToPrepare:Array<String> = [];
	public static var songsToPrepare:Array<String> = [];
	public static function prepare(images:Array<String> = null, sounds:Array<String> = null, music:Array<String> = null)
	{
		if (images != null) imagesToPrepare = imagesToPrepare.concat(images);
		if (sounds != null) soundsToPrepare = soundsToPrepare.concat(sounds);
		if (music != null) musicToPrepare = musicToPrepare.concat(music);
	}

	public static var dontPreloadDefaultVoices:Bool = false;
	public static function prepareToSong()
	{
		if (!ClientPrefs.data.loadingScreen) return;
		
		isPlayState = true;

		var song:SwagSong = PlayState.SONG;
		var folder:String = Paths.formatToSongPath(song.song);
		try
		{
			var path:String = Paths.json('$folder/preload');
			var json:Dynamic = null;

			#if MODS_ALLOWED
			var moddyFile:String = Paths.modsJson('$folder/preload');
			if (FileSystem.exists(moddyFile)) json = Json.parse(File.getContent(moddyFile));
			else json = Json.parse(File.getContent(path));
			#else
			json = Json.parse(Assets.getText(path));
			#end

			if (json != null)
				prepare((!ClientPrefs.data.lowQuality || json.images_low) ? json.images : json.images_low, json.sounds, json.music);
		}
		catch(e:Dynamic) {}

		if (song.stage == null || song.stage.length < 1)
			song.stage = StageData.vanillaSongStage(folder);

		var stageData:StageFile = StageData.getStageFile(song.stage);
		if (stageData != null && stageData.preload != null)
			prepare((!ClientPrefs.data.lowQuality || stageData.preload.images_low) ? stageData.preload.images : stageData.preload.images_low, stageData.preload.sounds, stageData.preload.music);

		songsToPrepare.push('$folder/Inst');

		var player1:String = song.player1;
		var player2:String = song.player2;
		var gfVersion:String = song.gfVersion;
		var needsVoices:Bool = song.needsVoices;
		var prefixVocals:String = needsVoices ? '$folder/Voices' : null;
		if (gfVersion == null) gfVersion = 'gf';

		dontPreloadDefaultVoices = false;
		preloadCharacter(player1, prefixVocals);
		if (player2 != player1) preloadCharacter(player2, prefixVocals);
		if (stageData != null && !stageData.hide_girlfriend && gfVersion != player2 && gfVersion != player1) preloadCharacter(gfVersion);
		
		preloadMisc();
		preloadScript();		
		
		events = [];	
		for (event in PlayState.SONG.events) //Event Notes
    		    events.push(event);
		
		if (!dontPreloadDefaultVoices && needsVoices) songsToPrepare.push(prefixVocals);
	}

	public static function startThreads()
	{
	    realStart = true;
	    
		loadMax = imagesToPrepare.length
		         + soundsToPrepare.length 
		         + musicToPrepare.length 
		         + songsToPrepare.length 
		         + 32;       
		loaded = 0;
        
       
		for (sound in soundsToPrepare) initThread(() -> Paths.sound(sound), 'sound $sound');
		for (music in musicToPrepare) initThread(() -> Paths.music(music), 'music $music');
		for (song in songsToPrepare) initThread(() -> Paths.returnSound(null, song, 'songs'), 'song $song');
                		
		for (images in 0...imagesToPrepare.length)
		{
		    var image = imagesToPrepare[images];
			Thread.create(() -> {
				mutex.acquire();			
				if (images == imagesToPrepare.length - 1) startChartLoad = true;
				try {
					var bitmap:BitmapData;
					var file:String = null;

					#if MODS_ALLOWED
					file = Paths.modsImages(image);
					if (Paths.currentTrackedAssets.exists(file)) {
						mutex.release();
						loaded++;
						return;
					}
					else if (FileSystem.exists(file))
						bitmap = BitmapData.fromFile(file);
					else
					#end
					{
						file = Paths.getPath('images/$image.png', IMAGE);
						if (Paths.currentTrackedAssets.exists(file)) {
							mutex.release();
							loaded++;
							return;
						}
						else if (OpenFlAssets.exists(file, IMAGE))
							bitmap = OpenFlAssets.getBitmapData(file);
						else {
							trace('no such image $image exists');
							mutex.release();
							loaded++;
							return;
						}
					}
					mutex.release();

					if (bitmap != null) requestedBitmaps.set(file, bitmap);
					else trace('oh no the image is null NOOOO ($image)');
				}
				catch(e:Dynamic) {
					mutex.release();
					trace('ERROR! fail on preloading image $image');
				}				
				loaded++;
			});		
        }
		setSpeed();		
	}

	static function initThread(func:Void->Dynamic, traceData:String)
	{
		Thread.create(() -> {
			mutex.acquire();
			try {
				var ret:Dynamic = func();
				mutex.release();

				if (ret != null) trace('finished preloading $traceData');
				else trace('ERROR! fail on preloading $traceData');
			}
			catch(e:Dynamic) {
				mutex.release();
				trace('ERROR! fail on preloading $traceData');
			}
			loaded++;
		});
	}

	public static function preloadCharacter(char:String, ?prefixVocals:String)
	{
		try
		{
			var path:String = Paths.getPath('characters/$char.json', TEXT, null, true);
			#if MODS_ALLOWED
			var character:Dynamic = Json.parse(File.getContent(path));
			#else
			var character:Dynamic = Json.parse(Assets.getText(path));
			#end
			
			imagesToPrepare.push('icons/' + character);	
			imagesToPrepare.push('icons/icon-' + character);		
			imagesToPrepare.push(character.image);		
			
			if (prefixVocals != null && character.vocals_file != null)
			{
				songsToPrepare.push(prefixVocals + "-" + character.vocals_file);
				if(char == PlayState.SONG.player1) dontPreloadDefaultVoices = true;
			}
			startScriptNamed('characters/' + char + '.lua');
		}
		catch(e:Dynamic) {}
	}
	
	static function preloadMisc(){
	    var ratingsData:Array<Rating> = Rating.loadDefault();
	    var stageData:StageFile = StageData.getStageFile(PlayState.SONG.stage);
		
	    var uiPrefix:String = '';
		var uiSuffix:String = '';
		
		if(stageData == null) { //Stage couldn't be found, create a dummy stage for preventing a crash
			stageData = StageData.dummy();
		}
		
		PlayState.stageUI = 'normal'; //fix
		if (stageData.stageUI != null && stageData.stageUI.trim().length > 0)
			PlayState.stageUI = stageData.stageUI;
		else {
			if (stageData.isPixelStage)
				PlayState.stageUI = "pixel";
		}		
		if (PlayState.stageUI != "normal")
		{
			uiPrefix = PlayState.stageUI +'UI/';
			if (PlayState.isPixelStage) uiSuffix = '-pixel';
		}

		for (rating in ratingsData){
			imagesToPrepare.push(uiPrefix + rating.image + uiSuffix);			         
		}
		
		for (i in 0...10)
		imagesToPrepare.push(uiPrefix + 'num' + i + uiSuffix);
		
        imagesToPrepare.push(uiPrefix + 'ready' + uiSuffix);	
        imagesToPrepare.push(uiPrefix + 'set' + uiSuffix);	
        imagesToPrepare.push(uiPrefix + 'go' + uiSuffix);				    
        imagesToPrepare.push('healthBar');
	}
	
	static function preloadScript(){	
        #if ((LUA_ALLOWED || HSCRIPT_ALLOWED) && sys)
    		for (folder in Mods.directoriesWithFile(Paths.getSharedPath(), 'scripts/'))
    			for (file in FileSystem.readDirectory(folder))
    			{
    				#if LUA_ALLOWED
    				
    				if(file.toLowerCase().endsWith('.lua'))
    					scriptFilesCheck(folder + file);					
    				#end
                    
    				#if HSCRIPT_ALLOWED
    				if(file.toLowerCase().endsWith('.hx'))
    					scriptFilesCheck(folder + file);
    				#end    				
    			}
    		
    		var songName = PlayState.SONG.song;
    		for (folder in Mods.directoriesWithFile(Paths.getSharedPath(), 'data/$songName/'))
    			for (file in FileSystem.readDirectory(folder))
    			{
    				#if LUA_ALLOWED
    				if(file.toLowerCase().endsWith('.lua'))
    					scriptFilesCheck(folder + file);
    				#end
                    
    				#if HSCRIPT_ALLOWED
    				if(file.toLowerCase().endsWith('.hx'))
    					scriptFilesCheck(folder + file);
    				#end    				
    			}
    			
    		startScriptNamed('stages/' + PlayState.SONG.stage + '.lua');	
    		startScriptNamed('stages/' + PlayState.SONG.stage + '.hx');
    		
    		for (event in events){
			    startScriptNamed('custom_events/' + event + '.lua');
			    startScriptNamed('custom_events/' + event + '.hx');
			}
		#end	        	    	
	}
	
	static function startScriptNamed(luaFile:String)
	{
		#if MODS_ALLOWED
		var luaToLoad:String = Paths.modFolders(luaFile);
		if(!FileSystem.exists(luaToLoad))
			luaToLoad = Paths.getSharedPath(luaFile);

		if(FileSystem.exists(luaToLoad))
		#elseif sys
		var luaToLoad:String = Paths.getSharedPath(luaFile);
		if(Assets.exists(luaToLoad))
		#end
		{			
			scriptFilesCheck(luaToLoad);		
		}
	}	
	
	static function scriptFilesCheck(path:String)
	{    	
    	var input:String = File.getContent(path);      
        var regex = ~/makeLuaSprite\(['"]([^'"]*)['"], ['"]([^'"]*)['"],.*?\)/g;
        while (regex.match(input)) {
            var result = regex.matched(2); // Extract the first capture group
            imagesToPrepare.push(result); // Output each match
            input = regex.matchedRight(); // Move to the next match
        }
    	
    	var input:String = File.getContent(path);    
    	var regex = ~/makeAnimatedLuaSprite\(['"]([^'"]*)['"], ['"]([^'"]*)['"],.*?\)/g;
    	while (regex.match(input)) {
    	    var result = regex.matched(2);    
    	    imagesToPrepare.push(result);
    	    input = regex.matchedRight(); 
    	}				
    	
    	var input:String = File.getContent(path);
    	var regex = ~/precacheImage\(['"]([^'"]*)['"],.*?\)/g;
    	while (regex.match(input)) {
    	    var result = regex.matched(1); 
    	    imagesToPrepare.push(result);
    	    input = regex.matchedRight();
    	}				    	
    	
    	var input:String = File.getContent(path);        
        var regex = ~/triggerEvent\(['"]([^'"]*)['"], ['"]([^'"]*)['"], ['"]([^'"]*)['"],.*?\)/g;
        while (regex.match(input)) {
            var event = regex.matched(1);
            var firstParam = regex.matched(2);
            var secondParam = regex.matched(3);            
            if (event == "Change Character") {              
                preloadCharacter(secondParam);
            }            
            input = regex.matchedRight();
        }
    	
    	var input:String = File.getContent(path);       
        var regex = ~/addCharacterToList\(['"]([^'"]*)['"],.*?\)/g;
        while (regex.match(input)) {    
            var result = regex.matched(1);
            preloadCharacter(result);
            input = regex.matchedRight();
        }
        
        var input:String = File.getContent(path);
    	var regex = ~/addLuaScript\(['"]([^'"]*)['"],.*?\)/g;
    	while (regex.match(input)) {
    	    var result = regex.matched(1); 
    	    startScriptNamed(result + '.lua');
    	    input = regex.matchedRight();
    	}
	}
	
	public static var unspawnNotes:Array<Note> = [];	
    public static var noteTypes:Array<String> = [];
    public static var events:Array<Array<Dynamic>> = [];    
    
	public static var chartMutex:Array<Mutex> = [];	
	public static var plistChart:Array<Int> = [];
	
	public static var songSpeed:Float = 1;	
	public static var songSpeedType:String = "multiplicative";		
	public static function setSpeed()
	{
	    songSpeed = PlayState.SONG.speed;
		songSpeedType = ClientPrefs.getGameplaySetting('scrolltype');
		switch(songSpeedType)
		{
			case "multiplicative":
				songSpeed = PlayState.SONG.speed * ClientPrefs.getGameplaySetting('scrollspeed');
			case "constant":
				songSpeed = ClientPrefs.getGameplaySetting('scrollspeed');
		}		
	}
	
	static function preloadChart()
	{	    
	    Note.globalRgbShaders = [];
		backend.NoteTypesConfig.clearNoteTypesData();
		
	    unspawnNotes = [];    	        	   	    
	    noteTypes = [];
	    plistChart = [];
	    chartMutex = [];
	        
	    var noteData:Array<SwagSection> =  PlayState.SONG.notes;	   	    	            
    	
    	addMutex(noteData);   	    	
    	
    	//Sys.sleep(0.1);
    	
    	for (bigSection in 0...32)
    	{
    	    Thread.create(() -> {    	         	  
    	        createNote(noteData, bigSection);          	                                                         
            });
        }
	}
	
	static function addMutex(chart:Array<SwagSection>)
	{		
		 for (plist in 0...32)      	
		 {
		    var mutex:Mutex = new Mutex();
		    chartMutex.push(mutex);		 
		 }   
		 
		 var bigSection:Int = Std.int(chart.length / 32);
		 for (plist in 0...32 + 1)
		 {	
		    if (plist != 32) plistChart.push(bigSection * plist);   
		    else plistChart.push(chart.length);		 		 
		 }
	}
	
	static function createNote(chart:Array<SwagSection>, plistData:Int)
	{		
	    try{
            var unspawnNotes:Array<Note> = [];	
	        var noteTypes:Array<String> = [];
	            	   
        	for (smallSection in plistChart[plistData]...plistChart[plistData + 1])
        	{   
        	    var section = chart[smallSection];        	                     	        
        		for (songNotes in section.sectionNotes)
        		{
    				var daStrumTime:Float = songNotes[0];
            		var daNoteData:Int = Std.int(songNotes[1] % 4);
            		var gottaHitNote:Bool = section.mustHitSection;
            		
            		if (ClientPrefs.data.filpChart) {
            		    if (daNoteData == 0) {
            		        daNoteData = 3;
            		    }    
            		    else if (daNoteData == 1) {
            		        daNoteData = 2;
            		    }    
            		    else if (daNoteData == 2) {
            		        daNoteData = 1;
            		    }   
            		    else if (daNoteData == 3) {
            		        daNoteData = 0;
            		    } 
            		}
            
            		if (songNotes[1] > 3)
            		{
            			gottaHitNote = !section.mustHitSection;
            		}
            
            		var oldNote:Note;
            		if (unspawnNotes.length > 0)
            			oldNote = unspawnNotes[Std.int(unspawnNotes.length - 1)];
            		else
            			oldNote = null;
            
            		var swagNote:Note = new Note(daStrumTime, daNoteData, oldNote, LoadingState);
            		swagNote.mustPress = gottaHitNote;
            		swagNote.sustainLength = songNotes[2];
            		swagNote.gfNote = (section.gfSection && (songNotes[1]<4));
            		swagNote.noteType = songNotes[3];
            		if(!Std.isOfType(songNotes[3], String)) swagNote.noteType = ChartingState.noteTypeList[songNotes[3]]; //Backward compatibility + compatibility with Week 7 charts
            
            		swagNote.scrollFactor.set();                        
            		unspawnNotes.push(swagNote);
                    
            		final susLength:Float = swagNote.sustainLength / Conductor.stepCrochet;
            		final floorSus:Int = Math.floor(susLength) - ClientPrefs.data.fixLNL;
            
            		if(floorSus > 0) {
            			for (susNote in 0...floorSus + 1)
            			{
            				oldNote = unspawnNotes[Std.int(unspawnNotes.length - 1)];
            
            				var sustainNote:Note = new Note(daStrumTime + (Conductor.stepCrochet * susNote), daNoteData, oldNote, true, LoadingState);
            				sustainNote.mustPress = gottaHitNote;
            				sustainNote.gfNote = (section.gfSection && (songNotes[1]<4));
            				sustainNote.noteType = swagNote.noteType;
            				sustainNote.scrollFactor.set();
            				sustainNote.parent = swagNote;
            				sustainNote.hitMultUpdate(susNote, floorSus + 1);                				
            				unspawnNotes.push(sustainNote);
            				swagNote.tail.push(sustainNote);                	
            
            				sustainNote.correctionOffset = swagNote.height / 2;
            				if(!PlayState.isPixelStage)
            				{
            					if(oldNote.isSustainNote)
            					{
            						oldNote.scale.y *= Note.SUSTAIN_SIZE / oldNote.frameHeight;
            						oldNote.scale.y /= ClientPrefs.getGameplaySetting('songspeed');
            						oldNote.updateHitbox();
            					}
            
            					if(ClientPrefs.data.downScroll)
            						sustainNote.correctionOffset = 0;
            				}
            				else if(oldNote.isSustainNote)
            				{
            					oldNote.scale.y /= ClientPrefs.getGameplaySetting('songspeed');
            					oldNote.updateHitbox();
            				}
            
            				if (sustainNote.mustPress) sustainNote.x += FlxG.width / 2; // general offset
            				else if(ClientPrefs.data.middleScroll)
            				{
            					sustainNote.x += 310;
            					if(daNoteData > 1) //Up and Right
            						sustainNote.x += FlxG.width / 2 + 25;
            				}
            				
            				sustainNote.updateHitbox();
            			}
            		}
            
            		if (swagNote.mustPress)
            		{
            			swagNote.x += FlxG.width / 2; // general offset
            		}
            		else if(ClientPrefs.data.middleScroll)
            		{
            			swagNote.x += 310;
            			if(daNoteData > 1) //Up and Right
            			{
            				swagNote.x += FlxG.width / 2 + 25;
            			}
            		}        		             
            		
            		if(!noteTypes.contains(swagNote.noteType)) {
            			noteTypes.push(swagNote.noteType);                
            		}
            		swagNote.updateHitbox();
        		}                           		                
            }
            pushData(unspawnNotes, noteTypes);
        } catch(e:Dynamic) {	       
	        createNote(chart, plistData); //try again            
	    }
	}
	
	static function pushData(chart:Array<Note>, types:Array<String>)
	{
	    mutex.acquire();
	    try{
    	    for (i in 0...chart.length)
    	        unspawnNotes.push(chart[i]);
    	    unspawnNotes.sort(PlayState.sortByTime);  
    	    
    	    for (i in 0...types.length)
    	        if(!noteTypes.contains(types[i]))
                        noteTypes.push(types[i]);                                   
            loaded++;                     
            mutex.release();                     	    	    
	    } catch(e:Dynamic) {
	        mutex.release(); 
	        pushData(chart, types); //try again	        
	    }
	}
}

class LoadButton extends FlxSprite
{
    public function new(x:Float, y:Float, Width:Int, Height:Int){
        super(x, y);    
        makeGraphic(Width, Height, 0x00);
		
		var shape:Shape = new Shape();
        shape.graphics.beginFill(color);
        shape.graphics.drawRoundRect(0, 0, Width, Height, Std.int(Height / 1), Std.int(Height / 1));     
        shape.graphics.endFill();
        
        var BitmapData:BitmapData = new BitmapData(Width, Height, 0x00);
        BitmapData.draw(shape);   
        
        pixels = BitmapData;                
        setGraphicSize(Width, Height);
    }
}