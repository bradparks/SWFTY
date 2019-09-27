package swfty.utils;

class MathUtils {
    
    // TODO: If skew is applied on sprite, it might not work correctly (like scaleY -1 which is skew -180 in Animate CC)

    public static inline function x(tx:Float) {
        return tx;
    }

    public static inline function y(ty:Float) {
        return ty;
    }

    public static inline function scaleX(a:Float, b:Float, c:Float, d:Float) {
        return if (b == 0)
            a;
        else
            // TODO: Figure out why I had to do that
            Math.sqrt(a * a + b * b) * (a < 0 ? -1 : 1) * (d < 0 ? -1 : 1);
    }

    public static inline function scaleY(a:Float, b:Float, c:Float, d:Float) {
        return if (c == 0)
            d;
        else
            // TODO: Why is this working?
            Math.sqrt(c * c + d * d);// * (b < 0 ? -1 : 1) * (c < 0 ? -1 : 1);
    }

    public static inline function rotation(a:Float, b:Float, c:Float, d:Float) {
        return if (b == 0 && c == 0)
            0.0;
        else {
            var radians = Math.atan2(d, c) - (Math.PI / 2);
            radians;
        }
    }

    public static inline function lower(a:Float, b:Float, ?precision:Float = 0.001) {
        return b < 0 ? a < b - precision : a < b + precision;
    }

    public static inline function greater(a:Float, b:Float, ?precision:Float = 0.001) {
        return b < 0 ? a > b - precision : a > b + precision;
    }

    public static inline function equals(a:Float, b:Float, ?precision:Float = 0.001) {
        return a > b - precision && a < b + precision;
    }
}

@:structInit
class Point {
    public var x:Float = 0.0;
    public var y:Float = 0.0;

    public static inline function distance(a:Point, b:Point) {
        var x = b.x - a.x;
        var y = b.y - a.y;
        return Math.sqrt(x * x + y * y);
    }

    public function new(?x:Float, ?y:Float) {
        this.x = x;
        this.y = y;
    }

    public inline function clone():Point {
        return { x: x, y: y };
    }

    public inline function toString() {
        return '{x: $x, y: $y}';
    }
}

@:structInit
class Size {
    public var width:Float = 0.0;
    public var height:Float = 0.0;

    public static inline function getSize(sprite:Sprite):Size {
        return {
            width: sprite.width,
            height: sprite.height
        }
    }

    public function new(?width:Float, ?height:Float) {
        this.width = width;
        this.height = height;
    }

    public inline function toString() {
        return '{width: $width, height: $height}';
    }
}

@:structInit
class Vector {
    public var x:Float = 0.0;
    public var y:Float = 0.0;
    public var z:Float = 0.0;

    public function new(?x:Float, ?y:Float, ?z:Float) {
        this.x = x;
        this.y = y;
        this.z = z;
    }

    public inline function toString() {
        return '{x: $x, y: $y, z: $z}';
    }
}

@:structInit
class Rectangle {

    public static var temp:Rectangle = new Rectangle();

    public var x:Float = 0.0;
    public var y:Float = 0.0;
    public var width:Float = 0.0;
    public var height:Float = 0.0;

    public var top(get, never):Float;
    public var bottom(get, never):Float;
    public var left(get, never):Float;
    public var right(get, never):Float;

    public function getSize():Size {
        return new Size(width, height);
    }

    public function new(?x:Float, ?y:Float, ?width:Float, ?height:Float) {
        this.x = x;
        this.y = y;
        this.width = width;
        this.height = height;
    }

    public inline function clone():Rectangle {
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

    public inline function set(x, y, width, height) {
        this.x = x;
        this.y = y;
        this.width = width;
        this.height = height;
        return this;
    }

    public inline function inflate(width:Float, height:Float) {
        this.x -= width;
        this.width += width * 2;
        this.y -= height;
        this.height += height * 2;
        return this;
    }

    public inline function normalize() {
        if (this.width < 0) {
            this.x += this.width;
            this.width *= -1;
        }
        if (this.height < 0) {
            this.y += this.height;
            this.height *= -1;
        }
        return this;
    }

    public inline function inside(x:Float, y:Float, margin = 0) {
        return (x >= this.x - margin) && 
               (x < this.x + this.width + margin) && 
               (y >= this.y - margin) && 
               (y < this.y + this.height + margin);
    }

    public inline function around(x:Float, y:Float, margin = 100) {
        var centerX = this.x + this.width / 2;
        var centerY = this.y + this.height / 2;
        var dx = centerX - x;
        var dy = centerY - y;
        return dx * dx + dy * dy < margin * margin;
    }

    public inline function union(rect:Rectangle):Rectangle {
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

    public inline function contains(rect:Rectangle):Bool {
		return if (rect.width <= 0 || rect.height <= 0) {
			rect.x > x && rect.y > y && rect.right < right && rect.bottom < bottom;
		} else {
			rect.x >= x && rect.y >= y && rect.right <= right && rect.bottom <= bottom;
		}
	}

    public inline function intersects(rect:Rectangle):Bool {
		return if (rect.x < this.x + this.width && this.x < rect.x + rect.width && rect.y < this.y + this.height) {
            this.y < rect.y + rect.height;
        } else {
            false;
        }
	}

    public inline function getIntersect(rect:Rectangle, ?temp:Rectangle):Rectangle {
        var x = Math.max(this.x, rect.x);
        var num1 = Math.min(this.x + this.width, rect.x + rect.width);
        var y = Math.max(this.y, rect.y);
        var num2 = Math.min(this.y + this.height, rect.y + rect.height);

        if (temp == null) temp = Rectangle.temp;

        if (num1 >= x && num2 >= y) {
            temp.x = x;
            temp.y = y;
            temp.width = num1 - x;
            temp.height = num2 - y;
        } else {
            temp.x = 0;
            temp.y = 0;
            temp.width = 1;
            temp.height = 1;
        }

        return temp;
    }

    public inline function empty() {
        return width <= 1 || height <= 1;
    }

    public inline function toString() {
        return '{x: $x, y: $y, width: $width, height: $height}';
    }
}