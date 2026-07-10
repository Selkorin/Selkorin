// Юстируемый кронштейн лазера с винтами точной подстройки боресайта (2 оси).
// openscad -o laser_mount.stl laser_mount.scad
include <params.scad>;

laser_d = 12;   // диаметр корпуса лазерного модуля
adjust  = 8;    // ход юстировки

module laser_mount() {
    difference() {
        union() {
            // основание кронштейна
            translate([-20, -15, 0]) cube([40, 30, wall*2]);
            // кольцевой держатель лазера на стойке
            translate([0, 0, wall*2 + 18])
                rotate([0, 90, 0])
                    cylinder(d = laser_d + 2*wall, h = 24, center = true);
            // стойка
            translate([-6, -6, wall*2]) cube([12, 12, 18]);
        }
        // канал под лазер
        translate([0, 0, wall*2 + 18])
            rotate([0, 90, 0])
                cylinder(d = laser_d, h = 30, center = true);
        // крепёж к площадке (с пазами под юстировку)
        for (x = [-14, 14], y = [-9, 9])
            translate([x, y, -1]) cylinder(d = m3, h = wall*2 + 2);
        // отверстия под юстировочные винты M3 (2 оси)
        translate([12, 0, wall*2 + 18]) rotate([0, 90, 0]) cylinder(d = m3, h = 20);
        translate([0, 12, wall*2 + 18]) rotate([90, 0, 0]) cylinder(d = m3, h = 20);
    }
}

laser_mount();
