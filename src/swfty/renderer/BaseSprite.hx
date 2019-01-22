package swfty.renderer;

import haxe.ds.StringMap;

@:allow(swfty.renderer.BaseSprite)
class BaseSprite extends EngineSprite {

    var disposed = false;

    public var og:Bool = false;

    // I was so close to have no custom defined ;_;
    #if (!openfl || !list)
    public var width(get, set):Float;
    public var height(get, set):Float;
    #end

    public var bounds(get, null):Rect;

    public var layer:BaseLayer;

    public var loaded = false;
    public var debug = false;

    // TODO: Only used on heaps, kind of a hack, I think saving the ColorType instead might solve this
    public var r:Float = 1.0;
    public var g:Float = 1.0;
    public var b:Float = 1.0;

    // For reload if definition didn't exists
    var _linkage:String;

    // Using underscore to prevent var clasing with base class
    // TODO: All private var should have an underscore?
    var _name(default, set):String;
    var _parent:FinalSprite;
    var _sprites:Array<FinalSprite>;
    var _names:StringMap<FinalSprite>;
    var _texts:StringMap<FinalText>;
    var _definition:Null<MovieClipType>;
    var _bounds:Rect;

    // Being able to add a render loop is a pretty nice tool
    // The map allows you to give it a name so you can easily remove all render loop from a specific name 
    // TODO: Would using an IntMap bring more performance?
    var _renders:Array<Float->Void>;
    var _rendersMap:StringMap<Array<Float->Void>>;

    var _pruneRenders:Array<Float->Void>;
    var _pruneSprites:Array<FinalSprite>;

    public function new(layer:BaseLayer, ?definition:MovieClipType, ?linkage:String) {
        super();

        this.layer = layer;
        _linkage = linkage;

        _renders = [];
        _rendersMap = new StringMap();

        _sprites = [];
        _names = new StringMap();
        _texts = new StringMap();

        _pruneRenders = [];
        _pruneSprites = [];

        load(definition);
    }

    function set__name(name:String) {
        if (_parent != null) {
            @:privateAccess _parent._names.remove(_name);
        }
        
        _name = name;
        return _name;
    }

    public function calcBounds(?relative:BaseSprite):Rect {
        throw 'Not implemented';
    }

    public function top() {
        throw 'Not implemented';
    }

    public function bottom() {
        throw 'Not implemented';
    }

    inline function get_bounds() {
        if (_bounds == null) _bounds = calcBounds();
        return _bounds;
    }

    public inline function setBounds(x:Float, y:Float, width:Float, height:Float) {
        if (_bounds == null) 
            _bounds = {x: x, y: y, width: width, height: height};
        else {
            _bounds.x = x;
            _bounds.y = y;
            _bounds.width = width;
            _bounds.height = height;
        }
    }

    #if (openfl && list && !flash) override #else inline #end
    function get_width():Float {
        return bounds.width * scaleX;
    }

    #if (openfl && list && !flash) override #else inline #end
    function set_width(width:Float) {
        scaleX = width / bounds.width;
        return width;
    }

    #if (openfl && list && !flash) override #else inline #end
    function get_height():Float {
        return bounds.height * scaleY;
    }

    #if (openfl && list && !flash) override #else inline #end
    function set_height(height:Float) {
        scaleY = height / bounds.height;
        return height;
    }

    public inline function addRender(?name:String, f:Float->Void, ?priority = false) {
        if (priority) _renders.unshift(f);
        else _renders.push(f);
        
        if (name != null) {
            if (!_rendersMap.exists(name)) _rendersMap.set(name, []);
            _rendersMap.get(name).push(f);
        }
    }

    public inline function removeRender(?name:String, ?f:Float->Void) {
        if (f != null) {
            _pruneRenders.push(f);

            if (_rendersMap.exists(name)) {
                _rendersMap.get(name).remove(f);
            }
        } else if (name != null && _rendersMap.exists(name)) {
            for (f in _rendersMap.get(name)) {
                _pruneRenders.push(f);
            }
            
            _rendersMap.remove(name);
        }
    }

    public function update(dt:Float) {
        for (sprite in _sprites) {
            sprite.update(dt);
        }

        for (f in _renders) f(dt);

        while(_pruneRenders.length > 0) _renders.remove(_pruneRenders.pop());
        while(_pruneSprites.length > 0) _sprites.remove(_pruneSprites.pop());
    }

    public inline function display():DisplaySprite {
        return this;
    }

    public function removeAll() {
        display().removeAll();
        _sprites = [];
    }

    public function load(definition:MovieClipType) {
        _definition = definition;
        if (definition != null) _linkage = definition.name;
        
        var childs = _sprites;

        // Clear all childrens
        removeAll();

        if (definition == null) return;

        // Create children
        var updateVisible = true, updatePosition = true, updateScale = true, updateRotation = true, updateAlpha = true;
        for (child in definition.children) {
            
            if (!loaded) {
                // TODO: Probably not the best way to do it.... Might as well create getter for properties and not override the EngineSprite class
                //       but keep it as a var, this way I could turn a switch on whenever a propery has been changed by the user rather than the library
                updateVisible = true;
                updatePosition = true;
                updateScale = true;
                updateRotation = true;
                updateAlpha = true;
            }
            
            if (child.text != null) {
                var text = if (!child.name.empty() && _texts.exists(child.name)) {
                    var text = _texts.get(child.name);

                    if (!loaded) {
                        if (!text.visible) updateVisible = false;
                        if (text.x != 0 || text.y != 0) updatePosition = false;
                        if (text.scaleX != 1 || text.scaleY != 1) updateScale = false;
                        if (text.rotation != 0) updateRotation = false;
                        if (text.alpha != 1) updateAlpha = false;
                    }

                    text.loadText(child.text);

                    text.refresh();
                    for (sprite in text._sprites) {
                        sprite.refresh();
                    }

                    text;
                } else {
                    var text = FinalText.create(layer, child.text);

                    if (!child.name.empty()) {
                        text._name = child.name;
                        _texts.set(child.name, text);
                    }
                    text;
                }
                
                text.og = true;

                if (updatePosition && updateScale && updateRotation) text.display().transform(child.a, child.b, child.c, child.d, child.tx, child.ty);
                if (updateAlpha) text.alpha = child.alpha;
                if (updateVisible) text.visible = child.visible;

                addSprite(text);
            } else {
                var sprite:FinalSprite = if (!child.name.empty() && _names.exists(child.name)) {
                    var sprite:FinalSprite = _names.get(child.name);

                    if (!loaded) {
                        if (!sprite.visible) updateVisible = false;
                        if (sprite.x != 0 || sprite.y != 0) updatePosition = false;
                        if (sprite.scaleX != 1 || sprite.scaleY != 1) updateScale = false;
                        if (sprite.rotation != 0) updateRotation = false;
                        if (sprite.alpha != 1) updateAlpha = false;
                    }

                    sprite.refresh();

                    sprite.load(child.mc);
                    sprite;
                } else {
                    var sprite:FinalSprite = FinalSprite.create(layer, child.mc);
                    if (!child.name.empty()) {
                        sprite._name = child.name;
                        _names.set(child.name, sprite);
                    }
                    sprite;
                }

                sprite.og = true;
                
                if (updatePosition && updateScale && updateRotation) sprite.display().transform(child.a, child.b, child.c, child.d, child.tx, child.ty);
                if (updateVisible) sprite.visible = child.visible;

                // This will add drawCalls, so big no no unless you really want them
                #if allowBlendMode
                if (mode != Normal && mode != null) {
                    sprite.blend(child.blendMode);
                } else {
                    sprite.resetBlend();
                }
                #end

                if (child.color != null) {
                    var color = child.color;
                    sprite.display().color(color.r, color.g, color.b, color.rAdd, color.gAdd, color.bAdd);
                } else {
                    sprite.display().resetColor();
                }

                if (updateAlpha) sprite.alpha = child.alpha;

                for (shape in child.shapes) {
                    var tile = layer.createBitmap(shape.bitmap.id, true);
                    tile.transform(shape.a, shape.b, shape.c, shape.d, shape.tx, shape.ty);
                    sprite.addBitmap(tile);
                }

                addSprite(sprite);
            }
        }

        loaded = true;
        
        // Re-add non-og tile
        for (child in childs) {
            if (!child.og) {
                if (!child._name.empty()) Log.warn('Missing Child: ${child._name}');

                //child.reload();

                // TODO: Usually non-og sprites are added on top, figure out a better way to preserve order
                addSprite(child);
            }
        }
    }

    public inline function getParent() {
        return _parent;
    }

    function refresh() {
        // Override if necessary, this is when the texture get replaced by a new one
    }

    public function reload() {
        // We cannot use definition.id because it can change... would've been nice if it was using the "itemID" instead...
        /*if (_definition != null) {
            if (layer.hasDefinition(_definition.id)) {
                var definition = layer.getDefinition(_definition.id);
                load(definition);
            } else {
                Log.warn('Definition does no longer exists: ${_definition.name} (${_definition.id})');
            }
        } else*/ if (_linkage != null) {
            if (layer.hasMC(_linkage)) {
                var definition = layer.getMC(_linkage);
                load(definition);
            } else {
                Log.warn('Definition does not exists: ${_linkage}');
            }
        } else {
            // Simply reload all sprites
            for (sprite in _sprites) sprite.reload();

            loaded = true;
        }
    }

    public function getIndex(sprite:FinalSprite) {
        return _sprites.indexOf(sprite);
    }

    public function addSpriteAt(sprite:FinalSprite, index:Int = 0) {
        if (sprite._name != null) _names.set(sprite._name, sprite);
        _sprites.insert(index, sprite);
        if (loaded && !sprite.loaded) sprite.reload();
    }

    public function addSprite(sprite:FinalSprite) {
        if (sprite._name != null) _names.set(sprite._name, sprite);
        _sprites.push(sprite);
        if (loaded && !sprite.loaded) sprite.reload();
    }

    public function removeSprite(sprite:FinalSprite) {
        if (sprite._name != null) _names.remove(sprite._name);
        _pruneSprites.push(sprite);
        sprite._parent = null;
    }

    public function setIndex(sprite:FinalSprite, index:Int) {
        if (_sprites.remove(sprite)) {
            _sprites.insert(index, sprite);
        }
    }

    public function addBitmap(shape:EngineBitmap) {
        throw 'Not implemented';
    }

    public function removeBitmap(shape:EngineBitmap) {
        throw 'Not implemented';
    }

    public inline function exists(name:String, og = false):Bool {
        return _names.exists(name) && (!og || _names.get(name).og);
    }

    public function get(?name:String):FinalSprite {
        return if (_names.exists(name)) {
            _names.get(name);
        } else if (_texts.exists(name)) {
            _texts.get(name);
        } else {
            if (_definition != null) Log.warn('Child: $name does not exists!');
            var sprite = FinalSprite.create(layer);
            sprite._name = name;
            _names.set(name, sprite);
            addSprite(sprite);
            sprite;
        }
    }

    public function getText(name:String):FinalText {
        return if (_texts.exists(name)) {
            _texts.get(name);
        } else {
            if (_definition != null) Log.warn('Text: $name does not exists!');
            var text = FinalText.create(layer);
            text._name = name;
            _texts.set(name, text);
            addSprite(text);
            text;
        }
    }

    public function dispose() {
        // TODO: Not really necessary... I guess it can help a bit the GC...
        if (!disposed) {
            disposed = true;

            for (sprite in _sprites) sprite.dispose();
            
            // TODO: Should I null everything?
            _renders = [];
            _rendersMap = new StringMap();

            _sprites = [];
            _names = new StringMap();
            _texts = new StringMap();

            _pruneRenders = [];
            _pruneSprites = [];

            _parent = null;
            _bounds = null;
        }
    }
}

@:structInit
class Point {
    public var x:Float = 0.0;
    public var y:Float = 0.0;

    public function new(?x:Float, ?y:Float) {
        this.x = x;
        this.y = y;
    }
}

@:structInit
class Rect {
    public var x:Float = 0.0;
    public var y:Float = 0.0;
    public var width:Float = 0.0;
    public var height:Float = 0.0;

    public var top(get, never):Float;
    public var bottom(get, never):Float;
    public var left(get, never):Float;
    public var right(get, never):Float;

    public function new(?x:Float, ?y:Float, ?width:Float, ?height:Float) {
        this.x = x;
        this.y = y;
        this.width = width;
        this.height = height;
    }

    public inline function clone():Rect {
        return {
            x: x,
            y: y,
            width: width,
            height: height
        }
    }

    public inline function get_top() {
        return y;
    }

    public inline function get_bottom() {
        return y + height;
    }

    public inline function get_right() {
        return x + width;
    }

    public inline function get_left() {
        return x;
    }

    public inline function inside(x:Float, y:Float) {
        return (x >= this.x) && (x < this.x + this.width) && (y >= this.y) && (y < this.y + this.height);
    }

    public inline function union(rect:Rect):Rect {
        return if (width == 0 || height == 0) {
			rect.clone();
		} else if (rect.width == 0 || rect.height == 0) {
			clone();
		} else {
            var x0 = x > rect.x ? rect.x : x;
            var x1 = right < rect.right ? rect.right : right;
            var y0 = y > rect.y ? rect.y : y;
            var y1 = bottom < rect.bottom ? rect.bottom : bottom;
            
            {
                x: x0,
                y: y0,
                width: x1 - x0,
                height: y1 - y0
            }
        }
    }

    public inline function toString() {
        return '{x: $x, y: $y, width: $width, height: $height}';
    }
}