package heaps.swfty.renderer;

typedef Line = {
    textWidth: Float,
    tiles: Array<{
        code: Int,
        sprite: Sprite
    }>
}

class Text extends Sprite {

    public static inline var SPACE = 0x20;

    public var text(default, set):String = '';

    public var textWidth(default, null):Float = 0.0;
    public var textHeight(default, null):Float = 0.0;

    var font:FontType;
    var textDefinition:TextType;

    public static inline function create(layer:Layer, definition:TextType, ?parent) {
        return new Text(layer, definition);
    }

    public function new(layer:Layer, definition:TextType, ?parent) {
        super(layer, parent);

        textDefinition = definition;

        font = definition.font;
        text = definition.text;
    }

    function set_text(text:String) {
        if (font == null || this.text == text) return text;

        // Clear tiles
        removeChildren();
        sprites = [];

        // Show characters
        var x = textDefinition.x;
        var y = textDefinition.y;

        var c = textDefinition.color;
        var r = (c & 0xFF0000) >> 16;
        var g = (c & 0xFF00) >> 8;
        var b = c & 0xFF;

        var scale = textDefinition.size / font.size;
        var lineHeight = textDefinition.size;

        var hasSpace = false;
        var lastSpaceX = 0.0;
        var currentLine:Line = {
            textWidth: 0.0,
            tiles: []
        };
        var lines:Array<Line> = [currentLine];

        for (i in 0...text.length) {
            var code = text.charCodeAt(i);

            if (code == SPACE) {
                lastSpaceX = x;
                hasSpace = true;
            }

            if (font.has(code)) {
                var char = font.get(code);
                var tile = layer.getTile(char.bitmap.id);

                if (tile != null) {
                    
                    var sprite = Sprite.create(layer, tile);

                    sprite.r = r/255;
                    sprite.g = g/255;
                    sprite.b = b/255;
                    
                    sprite.x = x + char.tx;
                    sprite.y = y + char.ty;

                    sprite.scaleX = sprite.scaleY = scale;

                    addTile(sprite);

                    currentLine.tiles.push({
                        code: code,
                        sprite: sprite
                    });

                    var w = tile.width * scale;
                    
                    if ((x - textDefinition.x) + w > textDefinition.width && hasSpace) {
                        y += lineHeight;
                        hasSpace = false;

                        // Take all characters until a space and move them to next line (ignoring the space)
                        var tiles = [];
                        var tile = currentLine.tiles.pop();
                        var offsetX = 0.0;
                        var maxWidth = (tile != null && tile.sprite != null) ? tile.sprite.x : 0.0;
                        while(tile != null && tile.code != SPACE) {
                            if (tile.sprite != null) {
                                tile.sprite.y += lineHeight;
                                offsetX = tile.sprite.x;
                            }
                            tiles.push(tile);

                            tile = currentLine.tiles.pop();
                            if (tile != null && tile.sprite != null) maxWidth = tile.sprite.x;
                        }

                        for (tile in tiles) tile.sprite.x -= offsetX - textDefinition.x;

                        currentLine.textWidth = maxWidth - textDefinition.x;
                        if (currentLine.textWidth > textWidth) textWidth = currentLine.textWidth;

                        currentLine = {
                            textWidth: 0.0,
                            tiles: tiles
                        };
                        lines.push(currentLine);

                        x -= offsetX - textDefinition.x;
                    }

                    x += w;
                } else {
                    currentLine.tiles.push({
                        code: code,
                        sprite: null
                    });
                }
            }
        }

        currentLine.textWidth = x - textDefinition.x;

        if (currentLine.textWidth > textWidth) textWidth = currentLine.textWidth;
        textHeight = y + lineHeight;

        switch(textDefinition.align) {
            case Left    : 
            case Right   : 
                for (line in lines)
                    for (tile in line.tiles) 
                        if (tile.sprite != null) tile.sprite.x += textDefinition.width - line.textWidth;
            case Center  : 
                for (line in lines)
                    for (tile in line.tiles) 
                        if (tile.sprite != null) tile.sprite.x += textDefinition.width / 2 - line.textWidth / 2;
            case Justify : 
                trace('Justify not supported!!!');
        }

        return text;
    }
}