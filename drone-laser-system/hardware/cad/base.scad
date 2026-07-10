// Опорно-поворотная платформа (ось азимута).
// openscad -o base.stl base.scad
include <params.scad>;

module nema17_holes() {
    for (x = [-1, 1], y = [-1, 1])
        translate([x*motor_hole/2, y*motor_hole/2, -1])
            cylinder(d = m3, h = base_h + 2);
}

module base() {
    difference() {
        union() {
            // диск платформы
            cylinder(d = base_d, h = base_h);
            // бортик под подшипник
            cylinder(d = bearing_d + 2*wall, h = base_h + bearing_h);
        }
        // посадка упорного подшипника
        translate([0, 0, base_h])
            cylinder(d = bearing_d, h = bearing_h + 1);
        // центральное отверстие под вал/кабель
        translate([0, 0, -1])
            cylinder(d = motor_bore, h = base_h + bearing_h + 2);
        // крепление двигателя азимута снизу
        nema17_holes();
        // монтажные отверстия к треноге (по кругу)
        for (a = [0 : 60 : 359])
            rotate([0, 0, a])
                translate([base_d/2 - 12, 0, -1])
                    cylinder(d = m4, h = base_h + 2);
    }
}

base();
