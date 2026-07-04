import java.awt.*;
import java.awt.geom.RoundRectangle2D;
import java.awt.image.BufferedImage;
import java.io.File;
import javax.imageio.ImageIO;

/** Генерирует иконку запуска ic_launcher.png для всех плотностей. */
public class GenIcon {
    public static void main(String[] args) throws Exception {
        String base = args.length > 0 ? args[0] : "res";
        String[] dirs = {"mipmap-mdpi","mipmap-hdpi","mipmap-xhdpi","mipmap-xxhdpi","mipmap-xxxhdpi"};
        int[] sizes   = {48, 72, 96, 144, 192};
        for (int i = 0; i < dirs.length; i++) {
            BufferedImage img = draw(sizes[i]);
            File dir = new File(base, dirs[i]);
            dir.mkdirs();
            ImageIO.write(img, "png", new File(dir, "ic_launcher.png"));
        }
        System.out.println("icons generated");
    }

    static BufferedImage draw(int s) {
        BufferedImage img = new BufferedImage(s, s, BufferedImage.TYPE_INT_ARGB);
        Graphics2D g = img.createGraphics();
        g.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON);
        g.setRenderingHint(RenderingHints.KEY_TEXT_ANTIALIASING, RenderingHints.VALUE_TEXT_ANTIALIAS_ON);

        float r = s * 0.22f;
        RoundRectangle2D rr = new RoundRectangle2D.Float(0, 0, s, s, r, r);
        g.setClip(rr);
        GradientPaint gp = new GradientPaint(0, 0, new Color(0x6D, 0x5B, 0xF5),
                                             s, s, new Color(0x0E, 0xA5, 0xA4));
        g.setPaint(gp);
        g.fillRect(0, 0, s, s);

        // Текст "ЕГЭ"
        String label = "ЕГЭ";
        g.setColor(Color.WHITE);
        Font font = new Font("SansSerif", Font.BOLD, (int) (s * 0.30f));
        g.setFont(font);
        FontMetrics fm = g.getFontMetrics();
        int tw = fm.stringWidth(label);
        int tx = (s - tw) / 2;
        int ty = (int) (s * 0.46f) + fm.getAscent() / 2;
        g.drawString(label, tx, ty);

        // Подпись 2026
        Font f2 = new Font("SansSerif", Font.BOLD, (int) (s * 0.16f));
        g.setFont(f2);
        g.setColor(new Color(255, 255, 255, 220));
        FontMetrics fm2 = g.getFontMetrics();
        String yr = "2026";
        int yw = fm2.stringWidth(yr);
        g.drawString(yr, (s - yw) / 2, (int) (s * 0.74f));

        g.dispose();
        return img;
    }
}
