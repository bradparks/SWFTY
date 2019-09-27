package swfty.extra;

import swfty.renderer.Sprite;

using swfty.extra.Tween;

@:access(swfty.renderer.BaseLayer)
@:access(swfty.renderer.Layer)
class Interactions {

    static inline var RENDER_ID = 'interaction';

    static var useManager = false;

    // Keep track of all interactions for this layer
    static var interactions:Map<Layer, Array<Interaction>> = new Map();
    static var nInteractions = 0;
    static var lastInteraction:Interaction = null;
    static var lastClick:Array<Sprite> = [];

    // You need to be carefull here as you need to makes sure to remove it! Put behind private until I figure a safer way
    public static var exclusive:Sprite = null;

    public static var debugCount = 0;
    public static var clickID = 0;

    // Inject the layer resolver interaction
    static function manage(manager:Manager) {
        // We switch to manager mode
        useManager = true;

        manager.addOnRemove(function(layer) {
            interactions.remove(layer);
        });

        manager.addRender(function() {

            if (debugCount > 0) {
                debugCount = 0;
            }

            // Look interactions in all layers and resolve it, if there was only one we can skip all this
            if (nInteractions == 1) { // Ez peazy
                if (lastInteraction != null) {
                    if (interactions.exists(lastInteraction.sprite.layer)) {
                        interactions.set(lastInteraction.sprite.layer, []);
                    }
                    
                    if (!lastInteraction.sprite.disposed && !lastInteraction.sprite.layer.disposed) {
                        if (lastInteraction.handler != null) lastInteraction.handler();
                        
                        if (lastInteraction != null) {
                            if (lastInteraction.isClick) {
                                @:privateAccess manager.click(lastClick);
                            }
                        }
                    }
                }

            } else if (nInteractions > 1) {
                var sortedLayers = manager.layers.copy();
                sortedLayers.sort(function(a, b):Int {
                    if (a.renderID < b.renderID) return -1;
                    else if (a.renderID > b.renderID) return 1;
                    return 0;
                });

                var found = false;
                for (layer in sortedLayers) {
                    if (layer.disposed || layer.renderID <= 0) {
                        interactions.remove(layer);
                    } else if (interactions.exists(layer)) {
                        var sprites = interactions.get(layer);
                        if (found) {
                            if (sprites.length > 0) {
                                interactions.set(layer, []);
                            }
                        } else if (sprites.length > 0) {
                            found = true;
                            var oneClick = false;

                            // Sort by lowest renderID
                            sprites.sort(function(a, b):Int {
                                if (a.sprite.renderID < b.sprite.renderID) return -1;
                                else if (a.sprite.renderID > b.sprite.renderID) return 1;
                                return 0;
                            });

                            var currentInteraction = null;

                            for (interaction in sprites) {
                                var parent = interaction.sprite;
                                if (parent.disposed) continue;
                                if (currentInteraction == null) currentInteraction = interaction;

                                while (parent != null) {
                                    if (parent == currentInteraction.sprite) {
                                        currentInteraction = interaction;

                                        if (interaction.handler != null) interaction.handler();
                                        
                                        if (!oneClick) {
                                            oneClick = true;
                                            
                                            if (interaction.isClick) {
                                                @:privateAccess manager.click(lastClick);
                                            }
                                        }
                                        break;
                                    }
                                    parent = parent.parent;
                                }

                                if (manager.stopPropagation) {
                                    lastClick = [];
                                    break;
                                }
                            }

                            interactions.set(layer, []);
                        }
                    }
                }
            }

            if (nInteractions > 0) {
                clickID++;
                
                nInteractions = 0;
                lastInteraction = null;
                manager.stopPropagation = false;

                if (manager.mouse.leftChanged) {
                    switch(manager.mouse.left) {
                        case Down : 
                        case Up   : lastClick = [];
                        case _    :
                    }
                }
            }
        });
    }

    public static inline function clear() {
        exclusive = null;
        nInteractions = 0;
        lastInteraction = null;
        interactions = new Map();
    }

    static inline function chainName(sprite:Sprite) {
        var str = '';
        var parent = sprite;

        while(parent != null) {
            str += (str == '' ? '' : '.') + parent.name;
            parent = parent.parent;
        }

        return str;
    }

    static inline function addInteraction(sprite:Sprite, ?f:Void->Void, ?isClick = false) {
        lastInteraction = {sprite: sprite, handler: f, isClick: isClick};
        nInteractions++;

        if (!interactions.exists(sprite.layer)) {
            interactions.set(sprite.layer, [lastInteraction]);
        } else {
            interactions.get(sprite.layer).push(lastInteraction);
        }
    }

    static function checkExclusive(sprite:Sprite) {
        if (exclusive == null) {
            return false;
        }

        var parent = sprite;
        while (parent != null) {
            if (parent == exclusive) return false;
            parent = parent.parent;
        }

        return true;
    } 

    public static function removeExclusive() {
        exclusive = null;
    }

    public static function hasExclusive() {
        return exclusive != null;
    }

    static var rect:Rectangle = {};
    public static function checkMask(sprite:Sprite, x:Float, y:Float) {
        // Loop all parent until we find a mask and return false if not inside
        var parent = sprite;

        while (parent != null) {
            if (parent.mask != null) {
                var topLeft = parent.localToLayer(parent.mask.x, parent.mask.y, 1);
                var bottomRight = parent.localToLayer(parent.mask.x + parent.mask.width, parent.mask.y + parent.mask.height, 2);

                if (!rect.set(topLeft.x, topLeft.y, bottomRight.x - topLeft.x, bottomRight.y - topLeft.y).inside(x, y)) {
                    return false;
                }
            }

            parent = parent.parent;
        }

        return true;
    }

    public static function isVisible(sprite:Sprite):Bool {
        while (sprite != null) {
            if (!sprite.visible) return false;
            sprite = sprite.parent;
        }
        return true;
    }

    public static function click(sprite:Sprite, ?name:String, ?cache = true, f:Void->Void) {
        var child = name == null ? sprite : sprite.get(name);

        child.interactive = true;

        // Cache bounds with transform to stage coordinate
        // TODO: 99% of case the bounds doesn't change, but maybe we shouldn't cache it? We still take into account local x / y
        var bounds:Rectangle = null;
        inline function getBounds() {
            // TODO: Think of a better way to cache bounds
            /*if (!cache || bounds == null)*/ bounds = child.calcBounds(true);
            return bounds;
        }

        // Detect left click inside and wait for mouse up inside to trigger handler
        var wasInside = false;
        child.addRender(RENDER_ID, function render(dt) {

            if (child.layer == null) return;

            var mouse = child.layer.mouse;
            if (mouse.leftChanged) {

                debugCount++;

                if ((!child.loaded && !child.hasForceBounds()) || !child.visible || !child.layer.shared.canInteract || child.layer._base.cancelInteract || checkExclusive(sprite)) return;

                var x = mouse.x;
                var y = mouse.y;

                switch(mouse.left) {
                    case Down : 
                        if (checkMask(child, x, y) && isVisible(child) && getBounds().inside(x, y)) {
                            wasInside = true;
                            if (useManager) {
                                lastClick.push(child);
                                addInteraction(child);
                            }
                        }
                    case Up : 
                        if (wasInside && checkMask(child, x, y) && isVisible(child) && getBounds().inside(x, y)) {
                            if (useManager) {
                                addInteraction(child, f, true);
                            } else {
                                f();
                            }
                        }
                        wasInside = false;
                    case _ : 
                }
            }
        });

        return sprite;
    }

    public static function mouseDown(sprite:Sprite, ?name:String, ?cache = true, f:Void->Void) {
        var child = name == null ? sprite : sprite.get(name);

        child.interactive = true;

        // Cache bounds with transform to stage coordinate
        // TODO: 99% of case the bounds doesn't change, but maybe we shouldn't cache it? We still take into account local x / y
        // TODO: The x / y does changes a lot tho!
        var bounds:Rectangle = null;
        inline function getBounds() {
            /*if (!cache || bounds == null)*/ bounds = child.calcBounds(true);
            return bounds;
        }

        // Detect left click inside and wait for mouse up inside to trigger handler
        child.addRender(RENDER_ID, function render(dt) {
            
            if (child.layer == null) return;
            
            var mouse = child.layer.mouse;
            if (mouse.leftChanged) {
                debugCount++;
                
                if (child.layer == null || !child.visible || (!child.loaded && !child.hasForceBounds()) || !child.layer.shared.canInteract || child.layer._base.cancelInteract || checkExclusive(sprite)) return;
                
                var y = mouse.y;
                var x = mouse.x;
                switch(mouse.left) {
                    case Down : 
                        if (checkMask(child, x, y) && isVisible(child) && getBounds().inside(x, y)) {
                            if (useManager) {
                                addInteraction(child, f);
                            } else {
                                f();
                            }
                        }
                    case Up :
                        /*if (useManager) { // Block mouse up on sprite below
                            if (getBounds().inside(x, y)) addInteraction(child);
                        }*/                       
                    case _ : 
                }
            }
        });

        return sprite;
    }

    public static function mouseUp(sprite:Sprite, ?name:String, ?cache = true, f:Void->Void) {
        var child = name == null ? sprite : sprite.get(name);

        child.interactive = true;

        // Cache bounds with transform to stage coordinate
        // TODO: 99% of case the bounds doesn't change, but maybe we shouldn't cache it? We still take into account local x / y
        var bounds:Rectangle = null;
        inline function getBounds() {
            /*if (!cache || bounds == null)*/ bounds = child.calcBounds(true);
            return bounds;
        }

        // Detect left click inside and wait for mouse up inside to trigger handler
        var wasInside = false;
        child.addRender(RENDER_ID, function render(dt) {
            
            if (child.layer == null) return;
            
            var mouse = child.layer.mouse;
            if (mouse.leftChanged) {
                debugCount++;

                if ((!child.loaded && !child.hasForceBounds()) || !child.visible || !child.layer.shared.canInteract || child.layer._base.cancelInteract || checkExclusive(sprite)) return;
                
                var y = mouse.y;
                var x = mouse.x;

                switch(mouse.left) {
                    case Down : 
                        if (checkMask(child, x, y) && isVisible(child) && getBounds().inside(x, y)) {
                            wasInside = true;
                        }
                    case Up : 
                        if (wasInside && checkMask(child, x, y) && isVisible(child) && getBounds().inside(x, y)) {
                            if (useManager) {
                                addInteraction(child, f);
                            } else {
                                f();
                            }
                        }
                        wasInside = false;
                    case _ : 
                }
            }
        });

        return sprite;
    }

    public static function mouseUpAnywhere(sprite:Sprite, ?name:String, ?cache = true, f:Void->Void) {
        var child = name == null ? sprite : sprite.get(name);

        child.addRender(RENDER_ID, function render(dt) {
            if (child.layer == null || !child.loaded || !child.visible) return;

            var mouse = child.layer.mouse;
            if (mouse.leftChanged) {

                debugCount++;

                switch(mouse.left) {
                    case Down : 
                    case Up : f();
                    case _ : 
                }
            }
        });

        return sprite;
    }

    public static function mouseDownAnywhere(sprite:Sprite, ?name:String, ?cache = true, f:Void->Void) {
        var child = name == null ? sprite : sprite.get(name);

        child.addRender(RENDER_ID, function render(dt) {
            if (child.layer == null || !child.loaded || !child.visible) return;

            var mouse = child.layer.mouse;
            if (mouse.leftChanged) {

                debugCount++;

                switch(mouse.left) {
                    case Down : f();
                    case Up : 
                    case _ : 
                }
            }
        });

        return sprite;
    }

    public static inline function clickOnce(sprite:Sprite, ?name:String, ?cache = true, f:Void->Void) {
        click(sprite, name, cache, function() {
            removeClick(sprite, name);
            f();
        });
    }

    public static function fancyClick(sprite:Sprite, ?name:String, f:Void->Void) {
        var child = name == null ? sprite : sprite.get(name);

        // TODO: Add a quick tween on "down" and when "up", like scale down a bit with a bounce then scale back up

        return sprite;
    }

    // TODO: Should we specify the function?
    public static inline function removeClick(sprite:Sprite, ?name:String) {
        var child = name == null ? sprite : sprite.get(name);

        child.removeRender(RENDER_ID);
        return sprite;
    }

    public static inline function getMouse(sprite:Sprite) {
        return sprite.layerToLocal(sprite.layer.mouse.x, sprite.layer.mouse.y);
    }

    public static inline function getMouseX(sprite:Sprite) {
        return getMouse(sprite).x;
    }
    
    public static inline function getMouseY(sprite:Sprite) {
        return getMouse(sprite).y;
    }
}

class InteractionText {

    public static inline function click(text:Text, ?name:String, ?cache = true, f:Void->Void) {
        var sprite:FinalSprite = text;
        Interactions.click(sprite, name, cache, f);
    }

    public static inline function mouseDown(text:Text, ?name:String, ?cache = true, f:Void->Void) {
        var sprite:FinalSprite = text;
        Interactions.mouseDown(sprite, name, cache, f);
    }

    public static inline function mouseDownAnywhere(text:Text, ?name:String, ?cache = true, f:Void->Void) {
        var sprite:FinalSprite = text;
        Interactions.mouseDownAnywhere(sprite, name, cache, f);
    }
}

@:structInit
class Interaction {
    public var sprite:Sprite;
    public var handler:Void->Void;
    public var isClick:Bool;

    public function new(sprite:Sprite, ?handler:Void->Void, ?isClick = false) {
        this.sprite = sprite;
        this.handler = handler;
        this.isClick = isClick;
    }
}