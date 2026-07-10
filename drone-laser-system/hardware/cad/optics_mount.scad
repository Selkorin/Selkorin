// Оптическая площадка возвышения: несёт камеру, ИК-подсветку и кронштейн лазера.
// openscad -o optics_mount.stl optics_mount.scad
include <params.scad>;

module dovetail_slots() {
    // продольные пазы для регулировки положения камеры/лазера
    for (y = [-optics_w/4, optics_w/4])
        translate([-optics_l/2 + 15, y, -1])
            cube([optics_l - 30, 5, optics_t + 2]);
}

module optics_platform() {
    difference() {
        union() {
            // площадка
            translate([-optics_l/2, -optics_w/2, 0])
                cube([optics_l, optics_w, optics_t]);
            // цапфы оси возвышения по бокам
            for (s = [-1, 1])
                translate([0, s*(optics_w/2), optics_t/2])
                    rotate([90, 0, 0])
                        cylinder(d = 16, h = 10, center = false);
        }
        // отверстия оси возвышения
        for (s = [-1, 1])
            translate([0, s*(optics_w/2 + 11), optics_t/2])
                rotate([90, 0, 0])
                    cylinder(d = optics_axle, h = 14);
        // крепёжные пазы
        dovetail_slots();
        // сетка отверстий M3 для камеры/кронштейнов
        for (x = [-40 : 20 : 40], y = [-20 : 20 : 20])
            translate([x, y, -1]) cylinder(d = m3, h = optics_t + 2);
    }
}

optics_platform();
