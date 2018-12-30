package;

#if export
import swfty.exporter.Exporter;
import file.save.FileSave;
#end

import haxe.net.WebSocket;
import haxe.ds.IntMap;
import haxe.io.Bytes;

import swfty.renderer.Layer;

import openfl.display.Sprite;
import openfl.events.Event;
import openfl.text.TextFormat;

using swfty.utils.Tools;
using swfty.extra.Lambda;
using swfty.extra.Tween;

class Main extends Sprite {

    var layers:Array<Layer>;

    var dt = 0.0;
    var timer = 0.0;

    #if sys
    var client:hxnet.tcp.Client = null;
    #end

	public function new() {	
		super();

        // This should be in your DEV code only
        var messages = new IntMap<{
            id: Int,
            total: Int,
            timestamp: Float,
            chunks: Array<{
                part: Int,
                bytes: Bytes
            }>
        }>();

        // TODO: Get rid of message if it been over X sec

        var ws = WebSocket.create("ws://127.0.0.1:49463/", [], false);
        ws.onopen = function() {
            trace('open!');
        };
        ws.onmessageString = function(message) {
            trace('message from server!' + (message.length > 200 ? message.substr(0, 200) + '...' : message));
            trace('message.length=' + message.length);
        };
        ws.onmessageBytes = function(bytes) {
            trace('message bytes from server!', bytes.length);

            // Verify magic number
            if (bytes.getUInt16(0) == 0xCACA) {
                var id = bytes.getInt32(2);
                var part = bytes.getInt32(2 + 4);
                var total = bytes.getInt32(2 + 4 + 4);

                if (!messages.exists(id)) {
                    messages.set(id, {
                        id: id,
                        timestamp: Date.now().getTime(),
                        total: total,
                        chunks: []
                    });
                }

                var message = messages.get(id);
                message.timestamp = Date.now().getTime();

                // Skip duplicate
                for (chunk in message.chunks) {
                    if (chunk.part == part) return;
                }

                message.chunks.push({
                    part: part,
                    bytes: bytes
                });

                if (message.chunks.length == total) {
                    trace('Received all message');

                    // Calculate size and read name
                    var len = 0;
                    var name = '';
                    for (chunk in message.chunks) {
                        len += chunk.bytes.length - (2 + 4 + 4 + 4);

                        if (chunk.part == 0) {
                            var l = chunk.bytes.getInt32(2 + 4 + 4 + 4);
                            len -= l + 4;
                            name = chunk.bytes.getString(2 + 4 + 4 + 4 + 4, l);
                        }
                    }

                    // Create SWFTY bytes back
                    var n = 0;
                    var swfty = Bytes.alloc(len);
                    for (chunk in message.chunks.sortf(chunk -> chunk.part)) {
                        var skip = 2 + 4 + 4 + 4 + (chunk.part == 0 ? 4 + chunk.bytes.getInt32(2 + 4 + 4 + 4) : 0);

                        swfty.blit(n, chunk.bytes, skip, chunk.bytes.length - skip);
                        n += chunk.bytes.length - skip;
                    }

                    trace('Got SWFTY!', name, swfty.length);

                    for (layer in layers) {
                        if (layer.id == name) {
                            trace('Found a layer!');
                            layer.loadBytes(swfty);
                        }
                    }
                    
                    messages.remove(id);
                }
            }
        };

        // Test
        layers = [];

        var fps:openfl.display.FPS = new openfl.display.FPS();
        fps.width = 200;
        fps.defaultTextFormat = new TextFormat(null, 40);
        fps.textColor = 0xFFFFFF;
        this.addChild(fps);

        /*var font = FontExporter.export('Bango', 24, false, false, iso8859_1);
        var bmp = new Bitmap(font.bitmapData);

        addChild(bmp);*/

        process();

        stage.addEventListener(Event.ENTER_FRAME, render);
    }

    function process() {
		// Process SWF

        // Asynchronous creation
        #if export
        processSWF('res/Popup.swf', function(layer) {
        #else
        Layer.load('res/swfty/high/Popup.swfty', stage.stageWidth, stage.stageHeight, function(layer) {
        #end

        /*({
            // Synchronous creation
            var layer = Layer.load('res/Popup.swfty', stage.stageWidth, stage.stageHeight, layer -> {
                trace('Yay loading finished!');
            }, error -> {
                trace('Error: $error');
            });*/

            /*var bmp = new Bitmap(layer.tileset.bitmapData);
            addChild(bmp);*/

            layers.push(layer);

            var names = layer.getAllNames();
            //trace(names);

            //trace(Report.getReport(layer.json));

            addChildAt(layer, 0);

            var sprite = layer.create('PopupShop');
            //sprite.scaleX = sprite.scaleY = 0.75;
            layer.add(sprite);

            sprite.x += 300;
            sprite.y += 300;
            //sprite.get('line').rotation = 90;
            //sprite.get('line').get('shape').scaleY = 1.75;

            sprite.get('mc').get('description').getText('title').fitText('A very long title, yes, hello!!!');

            return;

            // TODO: VSCode was choking on the naming, not sure why but this did the trick
            var spawn = function f() {
                haxe.Timer.delay(function() {
                    var name = names[Std.int(Math.random() * names.length)];
                    var sprite = layer.create(name);

                    var speedX = Math.random() * 50 - 25;
                    var speedY = Math.random() * 50 - 25;
                    var speedRotation = (Math.random() * 50 - 25) / 180 * Math.PI * 5;
                    var speedAlpha = Math.random() * 0.75 + 0.25;

                    speedRotation = speedRotation / Math.PI * 180;

                    sprite.x = Math.random() * stage.stageWidth * 0.75;// + stage.stageWidth / 4;
                    sprite.y = Math.random() * stage.stageHeight * 0.75;// + stage.stageHeight / 4;

                    var scale = Math.random() * 0.25 + 0.35;
                    sprite.scaleX = scale;
                    sprite.scaleY = scale;

                    sprite.tweenScale(1.5, 0.5, 0.5, BounceOut, function() 
                        sprite.tweenScale(0.25, 0.5, BackIn));

                    var render = null;
                    render = function(e) {
                        sprite.x += speedX * dt;
                        sprite.y += speedY * dt;
                        sprite.rotation += speedRotation * dt;
                        sprite.alpha -= speedAlpha * dt;

                        if (sprite.alpha <= 0) {
                            layer.remove(sprite);
                            removeEventListener(Event.ENTER_FRAME, render);
                        }
                    }

                    addEventListener(Event.ENTER_FRAME, render);

                    layer.add(sprite);

                    f();

                }, Std.int(DateTools.seconds(0.0025)));
            }

            spawn();
        }, function(e) trace('ERROR: $e'));
	}

    function render(e) {
        dt = (haxe.Timer.stamp() - timer); 
        timer = haxe.Timer.stamp();

        for (layer in layers) {
            layer.update(dt);
        }

        #if sys
        if (client != null) {
            client.update();
        }
        #end
    }

    #if export
    public function processSWF(path:String, ?onComplete:Layer->Void, ?onError:Dynamic->Void) {
		var layer = Layer.empty(stage.stageWidth, stage.stageHeight);

        File.loadBytes(path, function(bytes) {
            // Get name from path
            var name = new haxe.io.Path(path).file;

			var timer = haxe.Timer.stamp();
			Exporter.create(bytes, name, function(exporter) {
                // TODO: Could be more optimized by getting the tilemap + definition straigt from exporter object
                //       and passing it down to layer
                var bytes = exporter.getSwfty();
                layer.loadBytes(bytes, function() if (onComplete != null) onComplete(layer), onError);
                
                // Save file for test
                FileSave.saveClickBytes(bytes, '$name.swfty');
                FileSave.saveClickString(exporter.getAbstracts(), '${name.capitalize()}.hx');

                trace('Parsed SWF: ${haxe.Timer.stamp() - timer}');
            }, onError);
        }, onError);

        return layer;
	}
    #end
}

#if sys
class Client extends hxnet.protocols.WebSocket
{
	override private function recvText(line:String)
	{
        trace('HEY 2!', line);
	}
}
#end