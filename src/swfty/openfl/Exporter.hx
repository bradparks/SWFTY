package swfty.openfl;

import swfty.openfl.TilemapExporter;

import zip.ZipWriter;

import haxe.ds.StringMap;
import haxe.ds.IntMap;
import haxe.ds.Option;
import haxe.io.Bytes;
import haxe.io.BytesOutput;

import openfl.display.PNGEncoderOptions;
import openfl.display.BitmapData;
import openfl.geom.Matrix;
import openfl.geom.Point;
import openfl.utils.ByteArray;

import lime.graphics.Image;
import lime.graphics.ImageChannel;
import lime.math.Vector2;

import format.png.Data;
import format.png.Writer;
import format.tools.Deflate;

import format.swf.exporters.ShapeBitmapExporter;
import format.swf.exporters.ShapeCommandExporter;
import format.swf.data.consts.BitmapFormat;
import format.swf.data.consts.BlendMode;
import format.swf.data.SWFSymbol;
import format.swf.tags.IDefinitionTag;
import format.swf.tags.TagDefineBits;
import format.swf.tags.TagDefineBitsJPEG2;
import format.swf.tags.TagDefineBitsJPEG3;
import format.swf.tags.TagDefineBitsLossless;
import format.swf.tags.TagDefineButton;
import format.swf.tags.TagDefineButton2;
import format.swf.tags.TagDefineEditText;
import format.swf.tags.TagDefineFont;
import format.swf.tags.TagDefineFont2;
import format.swf.tags.TagDefineFont4;
import format.swf.tags.TagDefineShape;
import format.swf.tags.TagDefineSprite;
import format.swf.tags.TagDefineText;
import format.swf.tags.TagPlaceObject;
import format.swf.tags.TagSymbolClass;
import format.swf.tags.TagDefineSound;
import format.swf.SWFRoot;
import format.swf.SWFTimelineContainer;
import format.SWF;

using Lambda;

class Exporter {

    var definitions:IntMap<Bool>;
    
    var movieClips:IntMap<MovieClipDefinition>;
    var shapes:IntMap<Array<ShapeDefinition>>;

    var bitmaps:IntMap<BitmapDefinition>;
    var bitmapDatas:IntMap<BitmapData>;

    var swf:SWF;
    var data:SWFRoot;

    var alphaPalette:Bytes;

    var tilemap:Option<TilePack> = None;

    public static function create(bytes:Bytes, onComplete:Exporter->Void) {
        return new Exporter(bytes, onComplete);
    }

    public function new(bytes:Bytes, onComplete:Exporter->Void) {
        swf = new SWF(bytes);
        data = swf.data;

        definitions = new IntMap();
        
        movieClips = new IntMap();
        shapes = new IntMap();
        bitmaps = new IntMap();
        bitmapDatas = new IntMap();

        var json:SWFTYJson = {
            definitions: [],
            tiles: []
        };

        // TODO: Process root?

        function process(i) {
            var tag = data.tags[i];

        
            function complete() {
                if (i + 1 < data.tags.length) process(i + 1) else onComplete(this);
            }

            if (Std.is(tag, TagSymbolClass)) {
                var symbols = cast (tag, TagSymbolClass).symbols;
                
                //trace('TAG: ${tag.name} ${tag.toString()}');
                
                function process2(j) {
                    var symbol = symbols[j];
                    processSymbol(symbol, () -> {
                        if (j + 1 < symbols.length) process2(j + 1) else complete();                        
                    });
                }

                if (symbols.length > 0) process2(0) else complete();
            } else {
                complete();
            }
        }
        if (data.tags.length > 0) process(0) else onComplete(this);
    }

    public function getTilemap() {
        return switch(tilemap) {
            case Some(tilemap) : tilemap;
            case None : 
                // Create Tilemap based on all bitmapDatas
                var bmpds = [for (bmpd in bitmapDatas) bmpd];
                var tilemap = TilemapExporter.pack(bmpds);

                trace('Tilemap is ${tilemap.bitmapData.width}x${tilemap.bitmapData.height}');

                var keys = [for (key in bitmapDatas.keys()) key];
                for (i in 0...keys.length) {
                    var key = keys[i];

                    var bitmap = bitmaps.get(key);
                    var tile = tilemap.tiles[i];
                    
                    bitmap.x = tile.x;
                    bitmap.y = tile.y;
                }

                this.tilemap = Some(tilemap);
                tilemap;
        }
    }

    public function getJSON() {
        var definition:SWFTYJson = {
            definitions: [for (mc in movieClips) mc],
            tiles: [for (bmp in bitmaps) bmp]
        }

        return haxe.Json.stringify(definition);
    }

    public function getPNG(bmpd:BitmapData) {
        return bmpd.encode(bmpd.rect, new PNGEncoderOptions());
    }

    public function getSwfty() {
        var tilemap = getTilemap();
        var json = getJSON();
        var png = getPNG(tilemap.bitmapData);

        var zip = new ZipWriter();
        zip.addBytes(png, 'tilemap.png', false);
        zip.addString(json, 'definitions.json', true);

        return zip.finalize();
    }

    function getTransform(matrix:Matrix):Transform {
        return {
            a: matrix.a,
            b: matrix.b,
            c: matrix.c,
            d: matrix.d,
            tx: matrix.tx,
            ty: matrix.ty
        }
    }

    function addSprite(tag:SWFTimelineContainer, root:Bool = false, ?onComplete:Void->Void):MovieClipDefinition {
        
        var id = if (Std.is (tag, IDefinitionTag)) {
			untyped tag.characterId;
		} else {
            -1;
        }

        var children = [];
        var definition:MovieClipDefinition = {
            id: id,
            name: '',
            children: children
        }

        movieClips.set(id, definition);

        function process(i) {
            var frameData = tag.frames[i];
            var objects = frameData.getObjectsSortedByDepth();

            function process2(j) {
                var object = objects[j];

                var childTag = cast data.getCharacter(object.characterId);
                
                processTag(childTag, () -> {
                    var placeTag:TagPlaceObject = cast tag.tags[object.placedAtIndex];

                    var matrix = if (placeTag.matrix != null) {
                        var matrix = placeTag.matrix.matrix;
                        matrix.tx *= (1 / 20);
                        matrix.ty *= (1 / 20);
                        matrix;
                    } else {
                        new Matrix();
                    }

                    if (placeTag.colorTransform != null) {
                        // TODO: ColorTransform
                    }

                    if (placeTag.hasFilterList) {
                        // TODO: Filters list
                    }

                    var visible = if (placeTag.hasVisible) {
                        placeTag.visible != 0;
                    } else {
                        true;
                    }

                    if (placeTag.hasBlendMode) {
                        // TODO: Blend mode
                    }

                    if (placeTag.hasCacheAsBitmap) {
                        // TODO: Cache as Bitmap
                    }

                    var transform = getTransform(matrix);
                    var definition:SpriteDefinition = {
                        id: object.characterId,
                        name: placeTag.instanceName,
                        a: transform.a,
                        b: transform.b,
                        c: transform.c,
                        d: transform.d,
                        tx: transform.tx,
                        ty: transform.ty,
                        visible: visible,
                        shapes: shapes.exists(object.characterId) ? shapes.get(object.characterId) : []
                    }

                    children.push(definition);

                    if (j + 1 < objects.length) process2(j + 1) 
                    // TODO: Only process 1 frame for now...
                    //else if (i + 1 < tag.frames.length) process(i + 1) 
                    else onComplete();

                    //if (j + 1 >= objects.length) onComplete();
                });
            }

            if (objects.length > 0) process2(0) else onComplete();
        }
        if (tag.frames.length > 0) process(0) else onComplete();

        return definition;
    }

    function addShape(tag:TagDefineShape, onComplete:Void->Void) {
        var handler = new ShapeCommandExporter(data);
		tag.export(handler);

        var bitmaps = ShapeBitmapExporter.process(handler);

        var shapes = [];
        this.shapes.set(tag.characterId, shapes);

        if (bitmaps != null) {
            //for (i in 0...bitmaps.length) {

            function process(i) {  
                var bitmap = bitmaps[i];

                processTag(cast data.getCharacter(bitmap.id), () -> {
                    var transform = getTransform(bitmap.transform);
                    var definition:ShapeDefinition = {
                        id: i,
                        bitmap: bitmap.id,
                        a: transform.a,
                        b: transform.b,
                        c: transform.c,
                        d: transform.d,
                        tx: transform.tx,
                        ty: transform.ty
                    }

                    shapes.push(definition);

                    if (i + 1 < bitmaps.length) process(i + 1) else onComplete();
                });
            }

            if (bitmaps.length > 0) process(0) else onComplete();
        } else {
            function process(i) {
                var command = handler.commands[i];
                switch(command) {
					case BeginBitmapFill(bitmapID, _, _, _):
						processTag(cast data.getCharacter(bitmapID), () -> {
                            var definition:ShapeDefinition = {
                                id: i,
                                bitmap: bitmapID,
                                a: 0.0,
                                b: 0.0,
                                c: 0.0,
                                d: 0.0,
                                tx: 0.0,
                                ty: 0.0
                            }

                            shapes.push(definition);

                            if (i + 1 < handler.commands.length) process(i + 1) else onComplete();
                        });
					default:
                        if (i + 1 < handler.commands.length) process(i + 1) else onComplete();
				}
            }
            if (handler.commands.length > 0) process(0) else onComplete();
        }
    }

    function addBitmap(tag:IDefinitionTag, onComplete:Void->Void) {
        var bitmapData:BitmapData = null;
		
        function complete() {
            if (bitmapData != null) {
                var definition:BitmapDefinition = {
                    id: tag.characterId,
                    x: 0,
                    y: 0,
                    width: bitmapData.width,
                    height: bitmapData.height
                };

                bitmaps.set(tag.characterId, definition);
                bitmapDatas.set(tag.characterId, bitmapData);
            }

            onComplete();
        }

		if (Std.is(tag, TagDefineBitsLossless)) {
			
			var data:TagDefineBitsLossless = cast tag;

			var transparent = (data.level > 1);
			var buffer = data.zlibBitmapData;
			buffer.uncompress();
			buffer.position = 0;

			if (data.bitmapFormat == BitmapFormat.BIT_8) {
				
				var palette = Bytes.alloc(data.bitmapColorTableSize * 3);
				var alpha = null;
				
				if (transparent) alpha = Bytes.alloc(data.bitmapColorTableSize);
				var index = 0;
				
				for (i in 0...data.bitmapColorTableSize) {
					palette.set(index++, buffer.readUnsignedByte());
					palette.set(index++, buffer.readUnsignedByte());
					palette.set(index++, buffer.readUnsignedByte());
					if (transparent) alpha.set(i, buffer.readUnsignedByte());
				}
				
				var paddedWidth:Int = Math.ceil(data.bitmapWidth / 4) * 4;
				var values = Bytes.alloc((data.bitmapWidth + 1) * data.bitmapHeight);
				index = 0;
				
				for (y in 0...data.bitmapHeight) {
					values.set(index++, 0);
					values.blit(index, buffer, buffer.position, data.bitmapWidth);
					index += data.bitmapWidth;
					buffer.position += paddedWidth;
				}
				
				var png = new List();
				png.add(CHeader( { width: data.bitmapWidth, height: data.bitmapHeight, colbits: 8, color: ColIndexed, interlaced: false } ));
				png.add(CPalette(palette));
				if (transparent) png.add(CUnknown("tRNS", alpha));
				
                var bytes = zip.Zip.compress(values);
                png.add(CData(bytes));
                png.add(CEnd);
				
				var output = new BytesOutput();
				var writer = new Writer(output);
				writer.write(png);
				
                #if sync
                ({var bmpd = BitmapData.fromBytes(output.getBytes());
                #else
                BitmapData.loadFromBytes(output.getBytes()).onComplete((bmpd) -> {
                #end
                    bitmapData = bmpd;
                    complete();
                });
			} else {

				bitmapData = new BitmapData(data.bitmapWidth, data.bitmapHeight, transparent);
				
				bitmapData.image.buffer.premultiplied = false;
				bitmapData.setPixels(bitmapData.rect, buffer);
				bitmapData.image.buffer.premultiplied = true;
				bitmapData.image.premultiplied = false;
				
                complete();
			}
			
		} else if (Std.is(tag, TagDefineBitsJPEG2)) {
			
			var data:TagDefineBitsJPEG2 = cast tag;
			
			if (Std.is(tag, TagDefineBitsJPEG3)) {
				
				var alpha = cast (tag, TagDefineBitsJPEG3).bitmapAlphaData;
				alpha.uncompress();
				alpha.position = 0;
				
				if (alphaPalette == null) {
					alphaPalette = Bytes.alloc(256 * 3);
					var index = 0;
					
					for (i in 0...256) {
						alphaPalette.set(index++, i);
						alphaPalette.set(index++, i);
						alphaPalette.set(index++, i);
					}
				}
				
                #if sync
				({var image = Image.fromBytes(data.bitmapData);
                #else
                Image.loadFromBytes(data.bitmapData).onComplete(function(image) {
                #end
                    var values = Bytes.alloc((image.width + 1) * image.height);
                    var index = 0;
                    
                    for (y in 0...image.height) {
                        values.set(index++, 0);
                        values.blit(index, alpha, alpha.position, image.width);
                        index += image.width;
                        alpha.position += image.width;
                    }
                    
                    var png = new List();
                    png.add(CHeader( { width: image.width, height: image.height, colbits: 8, color: ColIndexed, interlaced: false } ));
                    png.add(CPalette(alphaPalette));
                    
                    var bytes = zip.Zip.compress(values);
                    png.add(CData(bytes));
                    png.add(CEnd);
                    
                    var output = new BytesOutput();
                    var writer = new Writer(output);
                    writer.write(png);
                    
                    #if sync
                    ({var bitmapDataAlpha = BitmapData.fromBytes(output.getBytes());
                    #else
                    BitmapData.loadFromBytes(output.getBytes()).onComplete(function(bitmapDataAlpha) {
                    #end
                        var bitmapDataJPEG = BitmapData.fromImage(image);
                        bitmapData = new BitmapData(image.width, image.height, true, 0x00000000);

                        var alpha = Image.fromBitmapData(bitmapDataAlpha);
                        bitmapData.copyPixels(bitmapDataJPEG, bitmapDataJPEG.rect, new Point(0, 0));
                        
                        var jpeg = Image.fromBitmapData(bitmapData);
                        jpeg.copyChannel(alpha, alpha.rect, new Vector2(), ImageChannel.RED, ImageChannel.ALPHA);
                        
                        bitmapData = BitmapData.fromImage(jpeg);
                        complete();
                    });
                });
			} else {
                #if sync
                ({var bmpd = BitmapData.fromBytes(data.bitmapData);
                #else
                BitmapData.loadFromBytes(data.bitmapData).onComplete(function(bmpd) {
                #end
                    bitmapData = bmpd;
                    complete();
                });
			}
			
		} else if (Std.is(tag, TagDefineBits)) {
			
            var data:TagDefineBits = cast tag;
            #if sync
            ({var bmpd = BitmapData.fromBytes(data.bitmapData);
            #else
            BitmapData.loadFromBytes(data.bitmapData).onComplete(function(bmpd) {
            #end
                bitmapData = bmpd;
                complete();
            });
		}
    }

    function processSymbol(symbol:SWFSymbol, onComplete:Void->Void) {
        var tag = cast data.getCharacter(symbol.tagId);

        // Only process Sprite Symbol
        if (Std.is(tag, TagDefineSprite)) {
            processTag(tag, () -> {
                var definition = movieClips.get(symbol.tagId);
                definition.name = symbol.name;

                onComplete();
            });
        } else {
            onComplete();
        }
    }

    function processTag(tag:IDefinitionTag, onComplete:Void->Void) {
        // Stop if exists or null
        if (tag == null || definitions.exists(tag.characterId)) {
            onComplete();
            return;
        }

        definitions.set(tag.characterId, true);

        if (Std.is(tag, TagDefineSprite)) {
            
            addSprite(cast tag, onComplete);

        } else if (Std.is(tag, TagDefineBits) || Std.is(tag, TagDefineBitsJPEG2) || Std.is(tag, TagDefineBitsLossless)) {
            
            addBitmap(cast tag, onComplete);
            
        } else if (Std.is(tag, TagDefineButton) || Std.is(tag, TagDefineButton2)) {
            
            // Will not support
            onComplete();
            
        } else if (Std.is(tag, TagDefineEditText)) {
            
            // TODO: Dynamic Text
            onComplete();
            
        } else if (Std.is(tag, TagDefineText)) {
            
            // TODO: Static Text
            onComplete();
            
        } else if (Std.is(tag, TagDefineShape)) {
            
            addShape(cast tag, onComplete);
            
        } else if (Std.is(tag, TagDefineFont) || Std.is(tag, TagDefineFont4)) {
            
            // Will not support
            onComplete();
            
        } else if (Std.is(tag, TagDefineSound)) {

            // Will not support
            onComplete();

        } else {
            onComplete();
        }
    }
}