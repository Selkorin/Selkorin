// U-образная вилка возвышения (устанавливается на поворотную платформу).
// openscad -o gimbal.stl gimbal.scad
include <params.scad>;

module cheek() {
    difference() {
        // щека
        hull() {
            translate([0, 0, 0]) cube([yoke_t, yoke_base, 1], center = false);
            translate([0, yoke_base/2 - 15, yoke_h]) cube([yoke_t, 30, 1]);
        }
        // отверстие оси возвышения
        translate([-1, yoke_base/2, yoke_h - 10])
            rotate([0, 90, 0])
                cylinder(d = optics_axle + 0.6, h = yoke_t + 2);
        // облегчение
        translate([-1, yoke_base/2 - 12, yoke_h/2 - 10])
            rotate([0, 90, 0])
                cylinder(d = 24, h = yoke_t + 2);
    }
}

module yoke() {
    // основание вилки, крепится к платформе
    difference() {
        cube([yoke_w + 2*yoke_t, yoke_base, wall*3], center = false);
        for (x = [15, yoke_w + 2*yoke_t - 15], y = [15, yoke_base - 15])
            translate([x, y, -1]) cylinder(d = m4, h = wall*3 + 2);
    }
    // левая щека
    translate([0, 0, wall*3]) cheek();
    // правая щека
    translate([yoke_w + yoke_t, 0, wall*3]) cheek();
}

yoke();
