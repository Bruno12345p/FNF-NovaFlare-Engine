package objects.screen;

import openfl.display.Sprite;

import objects.screen.DataCounter;
import objects.screen.Graphics;

class FPS extends Sprite
{
	public function new(x:Float = 10, y:Float = 10)
	{
		super();

		this.x = x;
		this.y = y;
		
		create();
	}
    
    public static var fpsShow:FPSCounter;
    public static var extraShow:ExtraCounter;    
    
    function create()
    {        
        fpsShow = new FPSCounter();
        addChild(fpsShow);
    
        extraShow = new ExtraCounter();
        addChild(exteaShow);
    }
    
    private override function __enterFrame(deltaTime:Float):Void
	{	    	    	    
	    DataGet.update();
	    
	    fpsShow.update();
	    msShow.update();
    }
}