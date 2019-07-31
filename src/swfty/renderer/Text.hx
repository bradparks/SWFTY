package swfty.renderer;

// Currently no engine-specific implementation
// But this is because we're using Bitmap Fonts
// Eventually think about a solution to render text to reserved space in the texture

class FinalText extends BaseText {

    public static inline function create(layer:BaseLayer, ?definition:TextType):FinalText {
        return new FinalText(layer, definition);
    }

    public function new(layer:BaseLayer, ?definition:TextType) {
        super(layer, definition);

        type = Text(this);
    }

    override function set__name(name:String) {
        if (_parent != null) {
            @:privateAccess _parent._texts.remove(_name);
            @:privateAccess _parent._texts.set(name, this);
        }
        
        return super.set__name(name);
    }
}

@:forward(_name, x, y, scaleX, scaleY, rotation, text, short, singleLine, fit, multiline, checkMultiline, fitVertically, addRender, removeRender, width, height, textWidth, textHeight, align)
abstract Text(FinalText) from FinalText to FinalText {
    public inline function sprite():Sprite {
        return this;
    }

    public var color(get, set):Null<UInt>;
    inline function get_color():Null<UInt> {
        return this._color;
    }

    inline function set_color(scale:Null<UInt>):Null<UInt> {
        return this._color = color;
    }
}