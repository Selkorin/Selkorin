// Гермокорпус электроники (вычислитель, драйверы, БП, реле блокировки).
// openscad -o enclosure.stl enclosure.scad
include <params.scad>;

enc_w = 180;
enc_d = 140;
enc_h = 90;

module enclosure() {
    difference() {
        // корпус
        cube([enc_w, enc_d, enc_h]);
        // внутренняя полость
        translate([wall, wall, wall])
            cube([enc_w - 2*wall, enc_d - 2*wall, enc_h]);
        // гермовводы кабелей (задняя стенка)
        for (x = [40, 90, 140])
            translate([x, -1, 30]) rotate([-90, 0, 0]) cylinder(d = 16, h = wall + 2);
        // вентиляция с жалюзи (боковая стенка)
        for (z = [25 : 12 : enc_h - 20])
            translate([-1, 30, z]) cube([wall + 2, enc_d - 60, 4]);
        // отверстия E-STOP и ключа (передняя панель)
        translate([50, enc_d + 1, enc_h - 30]) rotate([90, 0, 0]) cylinder(d = 22, h = wall + 2);   // E-STOP
        translate([90, enc_d + 1, enc_h - 30]) rotate([90, 0, 0]) cylinder(d = 19, h = wall + 2);    // ключ
        translate([120, enc_d + 1, enc_h - 30]) rotate([90, 0, 0]) cylinder(d = 10, h = wall + 2);   // индикатор
    }
    // стойки крепления платы
    for (x = [20, enc_w - 20], y = [20, enc_d - 20])
        translate([x, y, wall]) difference() {
            cylinder(d = 8, h = 12);
            cylinder(d = m3, h = 14);
        }
}

enclosure();
